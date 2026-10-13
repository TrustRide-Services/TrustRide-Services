-- ============================================================================
-- Founder direction (WP9 item 5) -- deterministic Protrack simulator on the
-- approved Engine 6 telemetry contract; duplicate-safe location history.
--
-- Engine 6:
--   * the provider path (fn_integration_telemetry_ingest: key, then records) and
--     the simulator now share one normalisation step,
--     fn_integration_telemetry_accept(system, records, simulated), so simulated
--     readings travel exactly the provider's path;
--   * every simulated reading is marked: ingest log simulated = TRUE, each point
--     and the TELEMETRY_BATCH_NORMALIZED batch carry simulated = true;
--   * fn_integration_telemetry_simulate(scenario, device, seed, at) -- same seed,
--     same readings. Scenarios: VALID, DUPLICATE, OUT_OF_ORDER, STALE, MALFORMED,
--     UNKNOWN_DEVICE, UNAUTHORIZED (through the real key check), PROVIDER_TIMEOUT,
--     PROVIDER_UNAVAILABLE (logged as such, no readings invented, counted against
--     the port's circuit breaker). It refuses to run unless the port is on its
--     simulator, so simulated data never mixes with live data.
-- Engine 2 (defect): a re-sent point was stored again in the location history.
--   Now one point per binding and timestamp (unique index; repeats ignored), and
--   the location event carries the simulated mark.
-- Live activation stays blocked: no Protrack credentials, and its documented API
-- base is plain HTTP until Protrack confirms HTTPS.
-- ============================================================================

ALTER TABLE trustride.integration_telemetry_ingest_log ADD COLUMN simulated BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE trustride.integration_telemetry_ingest_log DROP CONSTRAINT integration_telemetry_ingest_log_outcome_check;
ALTER TABLE trustride.integration_telemetry_ingest_log ADD CONSTRAINT integration_telemetry_ingest_log_outcome_check
  CHECK (outcome IN ('ACCEPTED', 'PARTIAL', 'REJECTED', 'UNAUTHENTICATED', 'PROVIDER_TIMEOUT', 'PROVIDER_UNAVAILABLE'));

ALTER TABLE trustride.resource_location_event ADD COLUMN simulated BOOLEAN NOT NULL DEFAULT FALSE;
CREATE UNIQUE INDEX resource_location_event_one_point ON trustride.resource_location_event (binding_id, recorded_at) WHERE binding_id IS NOT NULL;

CREATE FUNCTION trustride.fn_integration_telemetry_accept(p_system uuid, p_records jsonb, p_simulated boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
DECLARE
  v_rec JSONB;
  v_points JSONB := '[]'::jsonb;
  v_rejections JSONB := '[]'::jsonb;
  v_lat NUMERIC; v_lon NUMERIC; v_at TIMESTAMPTZ;
  v_n INT := 0;
  v_ingest UUID;
  v_max_age INTERVAL := make_interval(hours => coalesce(nullif(trustride.fn_business_config('TELEMETRY_MAX_POINT_AGE_HOURS'), '')::int, 24));
BEGIN
  FOR v_rec IN SELECT * FROM jsonb_array_elements(coalesce(p_records, '[]'::jsonb)) LOOP
    v_n := v_n + 1;
    BEGIN
      v_lat := coalesce(v_rec->>'lat', v_rec->>'latitude')::numeric;
      v_lon := coalesce(v_rec->>'lng', v_rec->>'lon', v_rec->>'longitude')::numeric;
      v_at := CASE WHEN coalesce(v_rec->>'gpstime', '') ~ '^[0-9]+$' THEN to_timestamp((v_rec->>'gpstime')::bigint)
                   ELSE coalesce(v_rec->>'gpstime', v_rec->>'recorded_at')::timestamptz END;
      IF coalesce(v_rec->>'imei', v_rec->>'device_id', '') = '' THEN RAISE EXCEPTION 'missing device id'; END IF;
      IF v_lat IS NULL OR v_lon IS NULL OR v_lat NOT BETWEEN -90 AND 90 OR v_lon NOT BETWEEN -180 AND 180 OR (v_lat = 0 AND v_lon = 0) THEN
        RAISE EXCEPTION 'invalid coordinates';
      END IF;
      IF v_at IS NULL OR v_at > now() + interval '5 minutes' THEN RAISE EXCEPTION 'invalid or future timestamp'; END IF;
      v_points := v_points || jsonb_build_array(jsonb_build_object(
        'device_ref', coalesce(v_rec->>'imei', v_rec->>'device_id'), 'lat', v_lat, 'lon', v_lon, 'recorded_at', v_at,
        'speed_kmh', (v_rec->>'speed')::numeric, 'heading_deg', (v_rec->>'course')::numeric,
        'ignition_on', CASE WHEN v_rec->>'acc' IN ('1', 'true') THEN TRUE WHEN v_rec->>'acc' IN ('0', 'false') THEN FALSE END,
        'live', v_at > now() - v_max_age, 'simulated', p_simulated));
    EXCEPTION WHEN OTHERS THEN
      v_rejections := v_rejections || jsonb_build_array(jsonb_build_object('index', v_n - 1, 'reason', SQLERRM));
    END;
  END LOOP;

  INSERT INTO trustride.integration_telemetry_ingest_log (system_user_id, provider_code, record_count, accepted_count, rejected_count, rejections, outcome, simulated)
  VALUES (p_system, 'PROTRACK', v_n, jsonb_array_length(v_points), jsonb_array_length(v_rejections), v_rejections,
    CASE WHEN jsonb_array_length(v_rejections) = 0 THEN 'ACCEPTED' WHEN jsonb_array_length(v_points) = 0 THEN 'REJECTED' ELSE 'PARTIAL' END, p_simulated)
  RETURNING ingest_id INTO v_ingest;

  IF jsonb_array_length(v_points) > 0 THEN
    INSERT INTO trustride.integration_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (v_ingest, 'TRS026_ENG002_RESC', 'TELEMETRY_BATCH_NORMALIZED',
      jsonb_build_object('ingest_id', v_ingest, 'provider_code', 'PROTRACK', 'simulated', p_simulated, 'points', v_points),
      'TELEMETRY_BATCH_NORMALIZED:' || v_ingest::text);
  END IF;
  PERFORM trustride.fn_integration_circuit_check('TELEMETRY_SERVICE');
  PERFORM trustride.fn_integration_circuit_record_result('TELEMETRY_SERVICE', TRUE, 0);
  RETURN jsonb_build_object('outcome', 'ACCEPTED', 'ingest_id', v_ingest, 'accepted', jsonb_array_length(v_points), 'rejected', v_rejections, 'simulated', p_simulated);
END;
$function$;

CREATE OR REPLACE FUNCTION trustride.fn_integration_telemetry_ingest(p_key text, p_records jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
DECLARE
  v_system UUID;
BEGIN
  v_system := trustride.fn_external_system_authenticate(p_key, 'TELEMETRY_INGEST');
  IF v_system IS NULL THEN
    INSERT INTO trustride.integration_telemetry_ingest_log (provider_code, record_count, accepted_count, rejected_count, outcome)
    VALUES ('PROTRACK', coalesce(jsonb_array_length(p_records), 0), 0, coalesce(jsonb_array_length(p_records), 0), 'UNAUTHENTICATED');
    RETURN jsonb_build_object('outcome', 'UNAUTHENTICATED');
  END IF;
  RETURN trustride.fn_integration_telemetry_accept(v_system, p_records, FALSE);
END;
$function$;

CREATE FUNCTION trustride.fn_integration_telemetry_simulate(p_scenario text, p_device_ref text, p_seed integer DEFAULT 1, p_at timestamptz DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
DECLARE
  v_at BIGINT := extract(epoch FROM date_trunc('second', p_at))::bigint;
  v_lat NUMERIC := round(-0.0917 + (p_seed % 50) * 0.0010, 6);
  v_lon NUMERIC := round(34.7680 + (p_seed % 50) * 0.0010, 6);
  pt JSONB;
  v_records JSONB;
  v_res JSONB;
  v_ingest UUID;
BEGIN
  IF trustride.fn_integration_adapter_mode('TELEMETRY_SERVICE') <> 'SIMULATOR' THEN
    RAISE EXCEPTION 'The Protrack simulator does not run while TELEMETRY_SERVICE is live -- simulated readings never mix with live data';
  END IF;
  pt := jsonb_build_object('imei', p_device_ref, 'lat', v_lat, 'lng', v_lon, 'gpstime', v_at, 'speed', 20 + p_seed % 15, 'course', (p_seed * 37) % 360, 'acc', 1);
  v_records := CASE upper(p_scenario)
    WHEN 'VALID' THEN jsonb_build_array(
        pt || jsonb_build_object('gpstime', v_at - 60, 'lat', v_lat - 0.0010),
        pt || jsonb_build_object('gpstime', v_at - 30, 'lat', v_lat - 0.0005),
        pt)
    WHEN 'DUPLICATE' THEN jsonb_build_array(pt, pt)
    WHEN 'OUT_OF_ORDER' THEN jsonb_build_array(pt, pt || jsonb_build_object('gpstime', v_at - 61, 'lat', v_lat - 0.0020))
    WHEN 'STALE' THEN jsonb_build_array(pt || jsonb_build_object('gpstime', v_at - 2 * 86400))
    WHEN 'MALFORMED' THEN jsonb_build_array(
        pt - 'imei',
        pt || jsonb_build_object('lat', 0, 'lng', 0),
        pt || jsonb_build_object('gpstime', v_at + 3600),
        pt || jsonb_build_object('lat', 'north'))
    WHEN 'UNKNOWN_DEVICE' THEN jsonb_build_array(pt)
    WHEN 'UNAUTHORIZED' THEN jsonb_build_array(pt)
    WHEN 'PROVIDER_TIMEOUT' THEN '[]'::jsonb
    WHEN 'PROVIDER_UNAVAILABLE' THEN '[]'::jsonb
    ELSE NULL END;
  IF v_records IS NULL THEN
    RAISE EXCEPTION 'Unknown simulator scenario % (VALID, DUPLICATE, OUT_OF_ORDER, STALE, MALFORMED, UNKNOWN_DEVICE, UNAUTHORIZED, PROVIDER_TIMEOUT, PROVIDER_UNAVAILABLE)', p_scenario;
  END IF;

  IF upper(p_scenario) = 'UNAUTHORIZED' THEN
    v_res := trustride.fn_integration_telemetry_ingest('trs_simulated.invalid-key', v_records);   -- the real key check
  ELSIF upper(p_scenario) IN ('PROVIDER_TIMEOUT', 'PROVIDER_UNAVAILABLE') THEN
    INSERT INTO trustride.integration_telemetry_ingest_log (provider_code, record_count, accepted_count, rejected_count, outcome, simulated, rejections)
    VALUES ('PROTRACK', 0, 0, 0, upper(p_scenario), TRUE,
      jsonb_build_array(jsonb_build_object('reason', CASE upper(p_scenario) WHEN 'PROVIDER_TIMEOUT' THEN 'simulated: Protrack did not answer within 20 s'
                                                       ELSE 'simulated: Protrack service unavailable (HTTP 503)' END)))
    RETURNING ingest_id INTO v_ingest;
    PERFORM trustride.fn_integration_circuit_check('TELEMETRY_SERVICE');
    PERFORM trustride.fn_integration_circuit_record_result('TELEMETRY_SERVICE', FALSE, CASE upper(p_scenario) WHEN 'PROVIDER_TIMEOUT' THEN 20000 ELSE 0 END);
    v_res := jsonb_build_object('outcome', upper(p_scenario), 'ingest_id', v_ingest, 'accepted', 0, 'simulated', true);
  ELSE
    v_res := trustride.fn_integration_telemetry_accept(NULL, v_records, TRUE);
  END IF;
  RETURN v_res || jsonb_build_object('scenario', upper(p_scenario), 'records', v_records);
END;
$function$;

-- Engine 2: one point per binding and timestamp; the simulated mark is kept.
DO $patch$
DECLARE
  v_def TEXT;
  a1 TEXT := E'    INSERT INTO trustride.resource_location_event (fleet_resource_id, binding_id, provider_code, device_ref, location, recorded_at, speed_kmh, heading_deg, ignition_on, order_id, outside_service_area)\n'
          || E'    VALUES (v_b.fleet_resource_id, v_b.binding_id, v_b.provider_code, v_b.provider_device_ref, v_geom, (v_pt->>''recorded_at'')::timestamptz,\n'
          || E'      (v_pt->>''speed_kmh'')::numeric, (v_pt->>''heading_deg'')::numeric, (v_pt->>''ignition_on'')::boolean, v_order, v_outside);';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'trustride' AND p.proname = 'fn_resource_telemetry_batch_accept';
  IF position(a1 IN v_def) = 0 THEN RAISE EXCEPTION 'location insert anchor not found'; END IF;
  EXECUTE replace(v_def, a1,
       E'    INSERT INTO trustride.resource_location_event (fleet_resource_id, binding_id, provider_code, device_ref, location, recorded_at, speed_kmh, heading_deg, ignition_on, order_id, outside_service_area, simulated)\n'
    || E'    VALUES (v_b.fleet_resource_id, v_b.binding_id, v_b.provider_code, v_b.provider_device_ref, v_geom, (v_pt->>''recorded_at'')::timestamptz,\n'
    || E'      (v_pt->>''speed_kmh'')::numeric, (v_pt->>''heading_deg'')::numeric, (v_pt->>''ignition_on'')::boolean, v_order, v_outside,\n'
    || E'      coalesce((v_pt->>''simulated'')::boolean, (v_payload->>''simulated'')::boolean, false))\n'
    || E'    ON CONFLICT (binding_id, recorded_at) WHERE binding_id IS NOT NULL DO NOTHING;');
END;
$patch$;

UPDATE trustride.integration_port_registry
SET status_checkpoints = jsonb_set(status_checkpoints, '{3}', jsonb_build_object('met', true,
      'evidence', 'fn_integration_telemetry_simulate: deterministic Protrack simulator on the Engine 6 contract, readings marked simulated (suite 43)'))
WHERE port_code = 'TELEMETRY_SERVICE' AND active;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
