-- ============================================================================
-- Engine 6 -- EPRA fuel prices and route distances as governed pricing inputs
-- Construction Directive WP6 (section 2.5) -- TrustRide side; Engine 5 not changed
-- ============================================================================
-- EPRA. Engine 5 already implements the specified derivation (blueprint 425,
-- 874): on EPRA_FUEL_INDEX_UPDATED, fn_cost_epra_fuel_index_ingest versions
-- every active fuel-consuming rate as R_d = pump price / km per litre +
-- maintenance per km. EPRA publishes no API: maximum retail prices are
-- announced monthly for the cycle 15th - 14th (Petroleum Act 2019 s.101(y),
-- L.N. 192 of 2022) by press statement. The authoritative "adapter" is
-- therefore a governed Office record of the published cycle with its source.
--
-- Found and stopped (directive 4.5): the established ingest applies ANY fuel
-- type to EVERY fuel-consuming rate and ignores jurisdiction (cost_rate has
-- neither column), so feeding real Kisumu petrol and diesel prices would
-- re-derive every rate from whichever arrived last; and at the September
-- cycle's Kisumu prices R_d would fall 9-20%. Correcting the derivation needs
-- an Engine 5 change and the fare impact needs the Founder's approval, so:
--   * EPRA cycles are recorded, validated and kept current here, but nothing
--     is sent to Engine 5 while EPRA_RATE_DERIVATION_ACTIVE is FALSE;
--   * the EPRA simulator no longer emits EPRA_FUEL_INDEX_UPDATED -- simulated
--     fuel prices can never re-derive live rates.
--
-- Routing. Every routing input now carries its provenance (provider,
-- reference, retrieval time, simulated or not). A live path exists for when a
-- provider adapter is built: route distances come from a zone-pair matrix
-- (integration_route_matrix) imported from the provider and fresh for
-- ROUTING_MATRIX_MAX_AGE_DAYS; a missing or stale pair fails explicitly
-- (ROUTING_UNAVAILABLE) and requests a refresh -- never a fabricated or zero
-- distance. The provider itself is a Founder choice (no account exists); the
-- port stays NOT_BUILT, so it cannot be switched live yet.
-- ============================================================================

INSERT INTO trustride.platform_configuration (config_key, config_value, environment, effective_from, changed_by)
SELECT v.k, v.v, 'ALL', now(), '00000000-0000-0000-0000-000000000000' FROM (VALUES
  ('EPRA_RATE_DERIVATION_ACTIVE', 'FALSE'),       -- TRUE only after the Engine 5 derivation fix and the Founder's fare-impact approval
  ('EPRA_PRICE_MIN_KES', '80'), ('EPRA_PRICE_MAX_KES', '400'),
  ('EPRA_WATCH_JURISDICTIONS', 'KISUMU_COUNTY'),
  ('ROUTING_MATRIX_MAX_AGE_DAYS', '30')
) v(k, v);

-- ----------------------------------------------------------------------------- EPRA
ALTER TABLE trustride.integration_epra_fuel_ingestion_log
  ADD COLUMN price_cycle_start DATE,
  ADD COLUMN price_cycle_end DATE,
  ADD COLUMN publication_date DATE,
  ADD COLUMN source_reference TEXT,
  ADD COLUMN source_url TEXT,
  ADD COLUMN recorded_by UUID,
  ADD COLUMN status TEXT NOT NULL DEFAULT 'SIMULATED' CHECK (status IN ('SIMULATED', 'RECORDED_NOT_APPLIED', 'APPLIED'));
CREATE UNIQUE INDEX uq_integration_epra_cycle ON trustride.integration_epra_fuel_ingestion_log (fuel_type, jurisdiction, price_cycle_start)
  WHERE status <> 'SIMULATED';

-- The simulator records a simulated price and nothing else.
DO $patch$
DECLARE
  v_def TEXT;
  i1 INT; i2 INT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_integration_epra_fuel_price_ingest(text,trustride.cost_jurisdiction_enum,uuid)'::regprocedure) INTO v_def;
  i1 := position('  -- Closes the loop' IN v_def);
  i2 := position('  RETURN v_id;' IN v_def);
  IF i1 = 0 OR i2 = 0 OR i2 < i1 THEN RAISE EXCEPTION 'EPRA simulator emission block not found'; END IF;
  v_def := substr(v_def, 1, i1 - 1)
    || E'  -- Simulated prices are recorded as SIMULATED and never sent to Engine 5 (WP6):\n'
    || E'  -- a simulated fuel price must not re-derive a live per-km rate.\n'
    || substr(v_def, i2);
  EXECUTE v_def;
END;
$patch$;

CREATE FUNCTION trustride.fn_integration_epra_cycle_record(p_cycle_start date, p_cycle_end date, p_publication_date date,
  p_source_reference text, p_source_url text, p_prices jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
DECLARE
  v_by UUID := auth.uid();
  v_min NUMERIC := coalesce(nullif(trustride.fn_business_config('EPRA_PRICE_MIN_KES'), '')::numeric, 80);
  v_max NUMERIC := coalesce(nullif(trustride.fn_business_config('EPRA_PRICE_MAX_KES'), '')::numeric, 400);
  v_apply BOOLEAN := upper(coalesce(trustride.fn_business_config('EPRA_RATE_DERIVATION_ACTIVE'), 'FALSE')) = 'TRUE';
  p JSONB; v_fuel TEXT; v_jur trustride.cost_jurisdiction_enum; v_price NUMERIC; v_existing RECORD; v_id UUID; n INT := 0; v_corr UUID := gen_random_uuid();
BEGIN
  IF v_by IS NOT NULL AND NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN
    RAISE EXCEPTION 'Only TrustRide Office (Founder or Administrator) records EPRA price cycles';
  END IF;
  IF p_cycle_start IS NULL OR p_cycle_end IS NULL OR extract(day FROM p_cycle_start) <> 15 OR p_cycle_end <> (p_cycle_start + interval '1 month')::date - 1 THEN
    RAISE EXCEPTION 'An EPRA pricing cycle runs from the 15th to the 14th of the next month';
  END IF;
  IF p_publication_date IS NULL OR p_publication_date > p_cycle_start THEN
    RAISE EXCEPTION 'Give the publication date (on or before the cycle start)';
  END IF;
  IF coalesce(trim(p_source_reference), '') = '' THEN
    RAISE EXCEPTION 'Give the EPRA source (press release or gazette reference) -- a price without its source is not recorded';
  END IF;
  IF p_prices IS NULL OR jsonb_typeof(p_prices) <> 'array' OR jsonb_array_length(p_prices) = 0 THEN
    RAISE EXCEPTION 'Give at least one price';
  END IF;
  FOR p IN SELECT * FROM jsonb_array_elements(p_prices) LOOP
    v_fuel := upper(coalesce(p->>'fuel_type', ''));
    IF v_fuel NOT IN ('PETROL_SUPER', 'DIESEL') THEN RAISE EXCEPTION 'Fuel type must be PETROL_SUPER or DIESEL (got %)', coalesce(p->>'fuel_type', 'nothing'); END IF;
    BEGIN v_jur := (p->>'jurisdiction')::trustride.cost_jurisdiction_enum;
    EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'Unknown jurisdiction %', coalesce(p->>'jurisdiction', 'nothing'); END;
    v_price := (p->>'pump_price_kes')::numeric;
    IF v_price IS NULL OR v_price < v_min OR v_price > v_max THEN
      RAISE EXCEPTION '% % KES % is outside the plausible range % - % per litre -- check the publication', v_jur, v_fuel, coalesce(v_price::text, 'nothing'), v_min, v_max;
    END IF;
    SELECT * INTO v_existing FROM trustride.integration_epra_fuel_ingestion_log
    WHERE fuel_type = v_fuel AND jurisdiction = v_jur AND price_cycle_start = p_cycle_start AND status <> 'SIMULATED';
    IF v_existing.epra_ingestion_id IS NOT NULL THEN
      IF v_existing.pump_price_kes = v_price THEN CONTINUE; END IF;   -- the same record again: nothing to do
      RAISE EXCEPTION '% % for the cycle from % is already recorded at KES % -- a correction is a new publication, not an edit',
        v_jur, v_fuel, p_cycle_start, v_existing.pump_price_kes;
    END IF;
    INSERT INTO trustride.integration_epra_fuel_ingestion_log (fuel_type, jurisdiction, pump_price_kes, adapter_type, correlation_id,
      price_cycle_start, price_cycle_end, publication_date, source_reference, source_url, recorded_by, status)
    VALUES (v_fuel, v_jur, v_price, 'PRODUCTION', v_corr, p_cycle_start, p_cycle_end, p_publication_date, trim(p_source_reference), p_source_url, v_by,
      CASE WHEN v_apply THEN 'APPLIED' ELSE 'RECORDED_NOT_APPLIED' END)
    RETURNING epra_ingestion_id INTO v_id;
    IF v_apply THEN
      INSERT INTO trustride.integration_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
      VALUES (v_corr, 'TRS026_ENG005_COST', 'EPRA_FUEL_INDEX_UPDATED',
        jsonb_build_object('price_period', p_cycle_start, 'fuel_type', v_fuel, 'jurisdiction', v_jur, 'pump_price_kes', v_price,
          'source_reference', trim(p_source_reference)), 'EPRA_FUEL_INDEX_UPDATED:' || v_id::text);
    END IF;
    n := n + 1;
  END LOOP;
  PERFORM trustride.fn_audit_log_append('integration_epra_fuel_ingestion_log', v_corr, 'EPRA_CYCLE_RECORDED', v_by, CASE WHEN v_by IS NULL THEN 'SYSTEM' ELSE 'USER' END,
    NULL, 'TRUSTRIDE_OFFICE', NULL, jsonb_build_object('cycle_start', p_cycle_start, 'cycle_end', p_cycle_end, 'source', p_source_reference,
      'prices_recorded', n, 'applied_to_pricing', v_apply));
  RETURN n;
END;
$function$;

CREATE FUNCTION trustride.fn_integration_epra_current(p_fuel_type text, p_jurisdiction trustride.cost_jurisdiction_enum, p_on date DEFAULT (now() AT TIME ZONE 'Africa/Nairobi')::date)
 RETURNS TABLE(pump_price_kes numeric, price_cycle_start date, price_cycle_end date, source_reference text, status text)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
  SELECT l.pump_price_kes, l.price_cycle_start, l.price_cycle_end, l.source_reference, l.status
  FROM trustride.integration_epra_fuel_ingestion_log l
  WHERE l.fuel_type = p_fuel_type AND l.jurisdiction = p_jurisdiction AND l.status <> 'SIMULATED'
    AND p_on BETWEEN l.price_cycle_start AND l.price_cycle_end
  ORDER BY l.ingested_at DESC LIMIT 1;
$function$;

CREATE FUNCTION trustride.fn_integration_epra_freshness_watch()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  j TEXT; f TEXT; n INTEGER := 0; v_missing TEXT;
BEGIN
  FOREACH j IN ARRAY string_to_array(coalesce(trustride.fn_business_config('EPRA_WATCH_JURISDICTIONS'), 'KISUMU_COUNTY'), ',') LOOP
    FOREACH f IN ARRAY ARRAY['PETROL_SUPER', 'DIESEL'] LOOP
      IF NOT EXISTS (SELECT 1 FROM trustride.fn_integration_epra_current(f, trim(j)::trustride.cost_jurisdiction_enum)) THEN
        v_missing := concat_ws(', ', v_missing, trim(j) || ' ' || f);
        n := n + 1;
      END IF;
    END LOOP;
  END LOOP;
  IF v_missing IS NOT NULL AND NOT EXISTS (SELECT 1 FROM trustride.present_notification_inbox
       WHERE title = 'EPRA prices for the current cycle are not recorded' AND delivered_at > now() - interval '20 hours') THEN
    PERFORM trustride.fn_present_notify_office('EPRA prices for the current cycle are not recorded',
      'Missing: ' || v_missing || '. Record the EPRA maximum retail prices published for this cycle (15th - 14th) with their source.',
      'PLATFORM_EXCEPTION', gen_random_uuid(), ARRAY['FOUNDER', 'ADMINISTRATOR'], FALSE);
  END IF;
  RETURN n;
END;
$function$;
SELECT cron.schedule('trustride_epra_freshness_watch', '0 6 * * *', 'SELECT trustride.fn_integration_epra_freshness_watch();');  -- 09:00 Nairobi

CREATE FUNCTION trustride.fn_present_cmd_record_epra_price_cycle(p_session uuid, p_payload jsonb, p_command uuid)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'trustride', 'public'
AS $function$
BEGIN
  PERFORM trustride.fn_integration_epra_cycle_record((p_payload->>'cycle_start')::date, (p_payload->>'cycle_end')::date,
    (p_payload->>'publication_date')::date, p_payload->>'source_reference', p_payload->>'source_url', p_payload->'prices');
  RETURN p_command;
END;
$function$;
INSERT INTO trustride.present_shell_capability_registry (top_shell, sub_shell, command_type, permitted, requires_delegated_authority)
VALUES ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RECORD_EPRA_PRICE_CYCLE', TRUE, FALSE);

-- -------------------------------------------------------------------------- Routing
ALTER TABLE trustride.integration_outbound_request DROP CONSTRAINT integration_outbound_request_operation_check;
ALTER TABLE trustride.integration_outbound_request ADD CONSTRAINT integration_outbound_request_operation_check
  CHECK (operation IN ('NOTIFY_SMS', 'NOTIFY_WHATSAPP', 'NOTIFY_EMAIL', 'NOTIFY_PUSH', 'STK_PUSH', 'B2C_PAYOUT', 'ROUTE_MATRIX'));

-- A provider route carries no terrain: it is recorded as unknown, never invented.
ALTER TABLE trustride.integration_routing_request_log ALTER COLUMN terrain_type DROP NOT NULL, ALTER COLUMN terrain_multiplier DROP NOT NULL;
ALTER TABLE trustride.integration_routing_request_log
  ADD COLUMN provider TEXT NOT NULL DEFAULT 'TRUSTRIDE_SIMULATOR',
  ADD COLUMN provider_reference TEXT,
  ADD COLUMN simulated BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN retrieved_at TIMESTAMPTZ;

CREATE TABLE trustride.integration_route_matrix (
  route_matrix_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  origin_zone_code       TEXT NOT NULL,
  destination_zone_code  TEXT NOT NULL,
  distance_km            NUMERIC(10,3) NOT NULL CHECK (distance_km >= 0 AND distance_km <= 1000),
  duration_min           NUMERIC(10,2) NOT NULL CHECK (duration_min >= 0 AND duration_min <= 1440),
  provider               TEXT NOT NULL,
  adapter_type           trustride.integration_adapter_type_enum NOT NULL,
  provider_reference     TEXT NOT NULL,
  response_sha256        CHAR(64) NOT NULL,
  retrieved_at           TIMESTAMPTZ NOT NULL,
  valid_until            TIMESTAMPTZ NOT NULL,
  superseded_at          TIMESTAMPTZ,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (origin_zone_code, destination_zone_code, provider_reference)
);
ALTER TABLE trustride.integration_route_matrix ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_integration_route_matrix_pair ON trustride.integration_route_matrix (origin_zone_code, destination_zone_code) WHERE superseded_at IS NULL;
COMMENT ON TABLE trustride.integration_route_matrix IS
  'Zone-to-zone road distance and duration from a live routing provider, with provenance and freshness. Pricing reads only current, unsuperseded rows.';

-- Applies a provider's matrix response (called with the gateway's result). The whole response is refused if any route is malformed.
CREATE FUNCTION trustride.fn_integration_route_matrix_apply(p_provider text, p_adapter_type trustride.integration_adapter_type_enum, p_provider_reference text, p_response jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
DECLARE
  r JSONB; n INT := 0; v_hash TEXT; v_age INT := coalesce(nullif(trustride.fn_business_config('ROUTING_MATRIX_MAX_AGE_DAYS'), '')::int, 30);
BEGIN
  IF p_adapter_type = 'SIMULATOR' THEN RAISE EXCEPTION 'A simulator response is never stored as a provider route'; END IF;
  IF coalesce(trim(p_provider), '') = '' OR coalesce(trim(p_provider_reference), '') = '' THEN RAISE EXCEPTION 'ROUTE_MATRIX_MALFORMED: provider and reference required'; END IF;
  IF p_response IS NULL OR jsonb_typeof(p_response->'routes') <> 'array' OR jsonb_array_length(p_response->'routes') = 0 THEN
    RAISE EXCEPTION 'ROUTE_MATRIX_MALFORMED: no routes';
  END IF;
  IF EXISTS (SELECT 1 FROM trustride.integration_route_matrix WHERE provider_reference = p_provider_reference) THEN
    RETURN 0;   -- the same response delivered again
  END IF;
  v_hash := encode(sha256(convert_to(p_response::text, 'UTF8')), 'hex');
  FOR r IN SELECT * FROM jsonb_array_elements(p_response->'routes') LOOP
    IF NOT EXISTS (SELECT 1 FROM trustride.cost_operational_zones WHERE zone_code = r->>'origin_zone_code' AND active)
       OR NOT EXISTS (SELECT 1 FROM trustride.cost_operational_zones WHERE zone_code = r->>'destination_zone_code' AND active) THEN
      RAISE EXCEPTION 'ROUTE_MATRIX_MALFORMED: unknown zone pair % -> %', r->>'origin_zone_code', r->>'destination_zone_code';
    END IF;
    IF (r->>'distance_km') IS NULL OR (r->>'duration_min') IS NULL OR (r->>'distance_km')::numeric < 0 OR (r->>'duration_min')::numeric < 0
       OR (r->>'distance_km')::numeric > 1000 OR (r->>'duration_min')::numeric > 1440
       OR ((r->>'distance_km')::numeric = 0 AND r->>'origin_zone_code' <> r->>'destination_zone_code') THEN
      RAISE EXCEPTION 'ROUTE_MATRIX_MALFORMED: implausible route % -> % (% km, % min)', r->>'origin_zone_code', r->>'destination_zone_code', r->>'distance_km', r->>'duration_min';
    END IF;
    UPDATE trustride.integration_route_matrix SET superseded_at = now()
    WHERE origin_zone_code = r->>'origin_zone_code' AND destination_zone_code = r->>'destination_zone_code' AND superseded_at IS NULL;
    INSERT INTO trustride.integration_route_matrix (origin_zone_code, destination_zone_code, distance_km, duration_min, provider, adapter_type,
      provider_reference, response_sha256, retrieved_at, valid_until)
    VALUES (r->>'origin_zone_code', r->>'destination_zone_code', (r->>'distance_km')::numeric, (r->>'duration_min')::numeric, p_provider, p_adapter_type,
      p_provider_reference, v_hash, coalesce((p_response->>'retrieved_at')::timestamptz, now()),
      coalesce((p_response->>'retrieved_at')::timestamptz, now()) + make_interval(days => v_age));
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$function$;

-- Requests a fresh matrix for every active zone pair from the live provider (Engine 6 outbound request).
CREATE FUNCTION trustride.fn_integration_route_matrix_refresh_request(p_correlation_id uuid DEFAULT NULL)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
DECLARE
  v_req UUID;
  v_corr UUID := coalesce(p_correlation_id, gen_random_uuid());
BEGIN
  SELECT request_id INTO v_req FROM trustride.integration_outbound_request
  WHERE port_code = 'ROUTING_SERVICE' AND operation = 'ROUTE_MATRIX' AND status NOT IN ('SUCCEEDED', 'FAILED') AND created_at > now() - interval '1 hour'
  ORDER BY created_at DESC LIMIT 1;
  IF v_req IS NOT NULL THEN RETURN v_req; END IF;   -- one refresh in flight at a time
  RETURN trustride.fn_integration_outbound_enqueue('ROUTING_SERVICE', 'ROUTE_MATRIX',
    jsonb_build_object('zones', (SELECT jsonb_agg(jsonb_build_object('zone_code', zone_code, 'lat', ST_Y(ST_Centroid(boundary)), 'lon', ST_X(ST_Centroid(boundary))) ORDER BY zone_code)
                                 FROM trustride.cost_operational_zones WHERE active)),
    'ROUTE_MATRIX', v_corr, v_corr);
END;
$function$;

-- fn_integration_routing_compute: provenance always; a live path that never fabricates.
DO $patch$
DECLARE
  v_def TEXT;
  a1 TEXT := E'  PERFORM trustride.fn_integration_port_assert_simulated(''ROUTING_SERVICE'');\n';
  a2 TEXT := E'  SELECT * INTO v_sim FROM trustride.fn_integration_routing_compute_simulate(v_origin.lat, v_origin.lon, v_dest.lat, v_dest.lon);\n';
  a3 TEXT := E'  INSERT INTO trustride.integration_routing_request_log (origin_lat, origin_lon, destination_lat, destination_lon, distance_km, duration_min, terrain_type, terrain_multiplier, correlation_id)\n'
          || E'  VALUES (v_origin.lat, v_origin.lon, v_dest.lat, v_dest.lon, v_sim.distance_km, v_sim.duration_min, v_sim.terrain_type, v_sim.terrain_multiplier, p_correlation_id)\n';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_integration_routing_compute(text,text,uuid)'::regprocedure) INTO v_def;
  IF position(a1 IN v_def) = 0 OR position(a2 IN v_def) = 0 OR position(a3 IN v_def) = 0 THEN RAISE EXCEPTION 'routing compute anchors not found'; END IF;
  v_def := replace(v_def, E'  v_circuit trustride.integration_circuit_state_enum;\n',
    E'  v_circuit trustride.integration_circuit_state_enum;\n  v_mode trustride.integration_adapter_type_enum := trustride.fn_integration_adapter_mode(''ROUTING_SERVICE'');\n  v_live RECORD;\n');
  v_def := replace(v_def, a1, '');
  v_def := replace(v_def, a2,
       E'  IF v_mode <> ''SIMULATOR'' THEN\n'
    || E'    -- Live: only a current provider route for this zone pair; otherwise an explicit failure and a refresh.\n'
    || E'    SELECT * INTO v_live FROM trustride.integration_route_matrix m\n'
    || E'    WHERE m.origin_zone_code = p_origin_zone_code AND m.destination_zone_code = p_destination_zone_code AND m.superseded_at IS NULL\n'
    || E'    ORDER BY m.retrieved_at DESC LIMIT 1;\n'
    || E'    IF v_live.route_matrix_id IS NULL OR v_live.valid_until < now() THEN\n'
    || E'      PERFORM trustride.fn_integration_route_matrix_refresh_request(p_correlation_id);\n'
    || E'      RAISE EXCEPTION ''ROUTING_UNAVAILABLE: no current % route for % -> % (refresh requested)'', v_mode, p_origin_zone_code, p_destination_zone_code;\n'
    || E'    END IF;\n'
    || E'    INSERT INTO trustride.integration_routing_request_log (origin_lat, origin_lon, destination_lat, destination_lon, distance_km, duration_min,\n'
    || E'      terrain_type, terrain_multiplier, correlation_id, adapter_type, provider, provider_reference, simulated, retrieved_at)\n'
    || E'    VALUES (v_origin.lat, v_origin.lon, v_dest.lat, v_dest.lon, v_live.distance_km, v_live.duration_min, NULL, NULL, p_correlation_id,\n'
    || E'      v_mode, v_live.provider, v_live.provider_reference, FALSE, v_live.retrieved_at)\n'
    || E'    RETURNING integration_routing_request_log.routing_request_id INTO v_id;\n'
    || E'    RETURN QUERY SELECT v_id, v_live.distance_km, v_live.duration_min, NULL::trustride.integration_terrain_type_enum, NULL::numeric;\n'
    || E'    RETURN;\n'
    || E'  END IF;\n'
    || a2);
  v_def := replace(v_def, a3,
       E'  INSERT INTO trustride.integration_routing_request_log (origin_lat, origin_lon, destination_lat, destination_lon, distance_km, duration_min, terrain_type, terrain_multiplier, correlation_id,\n'
    || E'    adapter_type, provider, provider_reference, simulated, retrieved_at)\n'
    || E'  VALUES (v_origin.lat, v_origin.lon, v_dest.lat, v_dest.lon, v_sim.distance_km, v_sim.duration_min, v_sim.terrain_type, v_sim.terrain_multiplier, p_correlation_id,\n'
    || E'    ''SIMULATOR'', ''TRUSTRIDE_SIMULATOR'', ''simulated'', TRUE, now())\n');
  EXECUTE v_def;
END;
$patch$;

UPDATE trustride.integration_port_registry SET
  consumers = consumers || '. TrustRide side built (WP6): provenance on every route, zone-pair matrix with freshness, explicit ROUTING_UNAVAILABLE, validated matrix import',
  blocking_dependency = 'Founder chooses the routing provider (recommendation: OpenRouteService / OSM-based, or HERE); then its matrix adapter in the gateway and an account'
WHERE port_code = 'ROUTING_SERVICE' AND active;
UPDATE trustride.integration_port_registry SET
  live_adapter = 'BUILT', live_operations = ARRAY['RECORD_EPRA_PRICE_CYCLE (Office record of the published cycle)'],
  consumers = 'Engine 5 per-km rate derivation (R_d) -- recorded and validated; NOT applied while EPRA_RATE_DERIVATION_ACTIVE is FALSE',
  readiness = 'NOT_WIRED_PENDING_DECISION',
  blocking_dependency = 'Engine 5 derivation applies any fuel type to every rate and ignores jurisdiction (needs a fuel type and jurisdiction per rate) and the Founder''s approval of the fare impact (R_d -9% to -20% at September Kisumu prices); EPRA publishes no API -- Office records each cycle from the press release'
WHERE port_code = 'EPRA_SERVICE' AND active;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_integration_route_matrix_apply(text, trustride.integration_adapter_type_enum, text, jsonb) TO service_role;
SELECT trustride.fn_platform_conformance_assert();
