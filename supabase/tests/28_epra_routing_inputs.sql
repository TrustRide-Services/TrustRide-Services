-- Suite 28 -- EPRA fuel prices and route distances as governed pricing inputs (Construction Directive WP6).
-- EPRA: the Office records each published cycle with its source; impossible, malformed, conflicting
-- and duplicate records are refused; nothing reaches Engine 5 while derivation is not approved; a
-- simulated price never re-derives a live rate; a missing current cycle is reported. Routing: every
-- route used in pricing says where it came from; the live path uses only a current provider route,
-- fails explicitly otherwise and asks for a refresh; a malformed or simulated provider response is
-- refused; the same response twice is stored once.
DO $$
DECLARE
  founder UUID; cust UUID; n INT; m INT; v TEXT; ok BOOLEAN; rd_before NUMERIC; rd_after NUMERIC; r RECORD; rid UUID;
  ready BOOLEAN := to_regprocedure('trustride.fn_integration_epra_cycle_record(date,date,date,text,text,jsonb)') IS NOT NULL;
  prices JSONB := '[{"jurisdiction":"KISUMU_COUNTY","fuel_type":"PETROL_SUPER","pump_price_kes":213.69},{"jurisdiction":"KISUMU_COUNTY","fuel_type":"DIESEL","pump_price_kes":218.08}]';
BEGIN
  founder := pg_temp.t_person('WP6 Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  cust := pg_temp.t_customer('WP6 Cust');
  SELECT direct_per_km_rate_kes INTO rd_before FROM trustride.cost_rate WHERE asset_class = 'BODA_BODA' AND active;

  -- ============ a simulated fuel price never reaches live rates
  PERFORM trustride.fn_integration_epra_fuel_price_ingest('PETROL_SUPER', 'KISUMU_COUNTY');
  PERFORM pg_temp.t_cycle(4);
  SELECT direct_per_km_rate_kes INTO rd_after FROM trustride.cost_rate WHERE asset_class = 'BODA_BODA' AND active;
  SELECT count(*) INTO n FROM trustride.integration_event_outbox WHERE signal_type = 'EPRA_FUEL_INDEX_UPDATED' AND emitted_at = now();
  PERFORM pg_temp.t_check('a simulated EPRA price is recorded as simulated and never re-derives a per-km rate', n = 0 AND rd_after = rd_before,
    n || ' signals; boda R_d ' || rd_before || ' -> ' || rd_after);

  IF NOT ready THEN
    PERFORM pg_temp.t_check('EPRA cycle recording exists', false, 'fn_integration_epra_cycle_record absent');
  ELSE
    n := trustride.fn_integration_epra_freshness_watch();
    PERFORM pg_temp.t_check('a missing current EPRA cycle is reported to the Office', n >= 1
      AND EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = founder AND title = 'EPRA prices for the current cycle are not recorded'), n::text);

    -- ============ recording a published cycle (as the Office, through the command)
    v := (pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RECORD_EPRA_PRICE_CYCLE', jsonb_build_object(
      'cycle_start', '2026-09-15', 'cycle_end', '2026-10-14', 'publication_date', '2026-09-14',
      'source_reference', 'EPRA maximum retail prices, cycle 15 Sep - 14 Oct 2026', 'source_url', 'https://www.epra.go.ke', 'prices', prices)))->>'status';
    SELECT count(*) INTO n FROM trustride.integration_epra_fuel_ingestion_log WHERE price_cycle_start = '2026-09-15' AND status = 'RECORDED_NOT_APPLIED' AND source_reference IS NOT NULL;
    PERFORM pg_temp.t_check('Office records a published cycle with its source', v = 'TRANSLATED' AND n = 2, v || ' rows=' || n);
    SELECT count(*) INTO n FROM trustride.integration_event_outbox WHERE signal_type = 'EPRA_FUEL_INDEX_UPDATED' AND emitted_at = now();
    PERFORM pg_temp.t_check('nothing is sent to Engine 5 while derivation is not approved (rates unchanged)', n = 0
      AND (SELECT direct_per_km_rate_kes FROM trustride.cost_rate WHERE asset_class = 'BODA_BODA' AND active) = rd_before, n::text);
    SELECT * INTO r FROM trustride.fn_integration_epra_current('PETROL_SUPER', 'KISUMU_COUNTY', '2026-10-01');
    PERFORM pg_temp.t_check('the current cycle is known with its provenance', r.pump_price_kes = 213.69 AND r.source_reference LIKE 'EPRA%', coalesce(r.pump_price_kes::text, 'none'));
    PERFORM pg_temp.t_check('outside the cycle there is no current price (no stale value served)',
      NOT EXISTS (SELECT 1 FROM trustride.fn_integration_epra_current('PETROL_SUPER', 'KISUMU_COUNTY', '2026-10-20')));
    v := (pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RECORD_EPRA_PRICE_CYCLE', jsonb_build_object(
      'cycle_start', '2026-09-15', 'cycle_end', '2026-10-14', 'publication_date', '2026-09-14', 'source_reference', 'same again', 'prices', prices)))->>'status';
    SELECT count(*) INTO n FROM trustride.integration_epra_fuel_ingestion_log WHERE price_cycle_start = '2026-09-15';
    PERFORM pg_temp.t_check('the same cycle recorded twice is stored once', v = 'TRANSLATED' AND n = 2, n::text);
    FOR r IN SELECT * FROM (VALUES
        ('a conflicting price for a recorded cycle', '2026-09-15', '2026-10-14', 'x', '[{"jurisdiction":"KISUMU_COUNTY","fuel_type":"DIESEL","pump_price_kes":200}]'),
        ('a zero price', '2026-11-15', '2026-12-14', 'x', '[{"jurisdiction":"KISUMU_COUNTY","fuel_type":"DIESEL","pump_price_kes":0}]'),
        ('an implausible price', '2026-11-15', '2026-12-14', 'x', '[{"jurisdiction":"KISUMU_COUNTY","fuel_type":"DIESEL","pump_price_kes":2180}]'),
        ('a cycle that is not 15th - 14th', '2026-11-01', '2026-11-30', 'x', '[{"jurisdiction":"KISUMU_COUNTY","fuel_type":"DIESEL","pump_price_kes":218}]'),
        ('a price with no source', '2026-11-15', '2026-12-14', '', '[{"jurisdiction":"KISUMU_COUNTY","fuel_type":"DIESEL","pump_price_kes":218}]'),
        ('an unknown fuel type', '2026-11-15', '2026-12-14', 'x', '[{"jurisdiction":"KISUMU_COUNTY","fuel_type":"JET_A1","pump_price_kes":218}]'),
        ('a malformed price list', '2026-11-15', '2026-12-14', 'x', '{"oops":true}')) t(label, s, e, src, pr) LOOP
      v := (pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RECORD_EPRA_PRICE_CYCLE', jsonb_build_object(
        'cycle_start', r.s, 'cycle_end', r.e, 'publication_date', '2026-09-14', 'source_reference', r.src, 'prices', r.pr::jsonb)))->>'status';
      PERFORM pg_temp.t_check('EPRA: ' || r.label || ' is refused', v = 'REJECTED', v);
    END LOOP;
    PERFORM pg_temp.t_as(cust);
    PERFORM pg_temp.t_check('a customer cannot record EPRA prices',
      pg_temp.t_fails('SELECT trustride.fn_integration_epra_cycle_record(''2026-12-15'', ''2027-01-14'', ''2026-12-14'', ''x'', NULL, ''[{"jurisdiction":"KISUMU_COUNTY","fuel_type":"DIESEL","pump_price_kes":218}]'')'));
    PERFORM pg_temp.t_admin();
    PERFORM pg_temp.t_check('recording a cycle is on the audit record', EXISTS (SELECT 1 FROM trustride.audit_log WHERE action = 'EPRA_CYCLE_RECORDED' AND actor_id = founder));
  END IF;

  -- ============ routing provenance (simulator)
  SELECT * INTO r FROM trustride.fn_integration_routing_compute('KSM-CBD-01', 'KSM-MILIMANI-02', gen_random_uuid());
  SELECT to_jsonb(l) INTO v FROM trustride.integration_routing_request_log l WHERE l.routing_request_id = r.routing_request_id;
  PERFORM pg_temp.t_check('every route used for pricing says where it came from (simulated, simulator provider)',
    (v::jsonb)->>'simulated' = 'true' AND (v::jsonb)->>'provider' = 'TRUSTRIDE_SIMULATOR' AND (v::jsonb)->>'adapter_type' = 'SIMULATOR', left(v, 200));

  -- ============ live routing path (registry edited around the switch, as a provider would be activated)
  IF ready THEN
    UPDATE trustride.integration_adapter_registry SET active = FALSE WHERE port_code = 'ROUTING_SERVICE' AND active;
    INSERT INTO trustride.integration_adapter_registry (port_code, adapter_type, active, notes) VALUES ('ROUTING_SERVICE', 'PRODUCTION', TRUE, 'suite 28');
    BEGIN PERFORM * FROM trustride.fn_integration_routing_compute('KSM-CBD-01', 'KSM-MILIMANI-02', gen_random_uuid()); ok := false; v := 'route served';
    EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'ROUTING_UNAVAILABLE%'; v := SQLERRM; END;
    PERFORM pg_temp.t_check('live: with no provider route the request fails explicitly (no fabricated distance)', ok, left(v, 160));
    PERFORM trustride.fn_integration_route_matrix_refresh_request(gen_random_uuid());
    SELECT count(*) INTO n FROM trustride.integration_outbound_request WHERE port_code = 'ROUTING_SERVICE' AND operation = 'ROUTE_MATRIX' AND created_at = now();
    PERFORM pg_temp.t_check('live: a matrix refresh is requested from the provider, one in flight at a time', n = 1, n::text);
    BEGIN PERFORM trustride.fn_integration_route_matrix_apply('TEST_PROVIDER', 'PRODUCTION', 'ref-bad',
      '{"routes":[{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02","distance_km":-3,"duration_min":9}]}'); ok := false;
    EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'ROUTE_MATRIX_MALFORMED%'; END;
    PERFORM pg_temp.t_check('live: a malformed provider response is refused whole', ok AND NOT EXISTS (SELECT 1 FROM trustride.integration_route_matrix WHERE provider_reference = 'ref-bad'));
    BEGIN PERFORM trustride.fn_integration_route_matrix_apply('TEST_PROVIDER', 'PRODUCTION', 'ref-unknown',
      '{"routes":[{"origin_zone_code":"NO-SUCH","destination_zone_code":"KSM-MILIMANI-02","distance_km":3,"duration_min":9}]}'); ok := false;
    EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'ROUTE_MATRIX_MALFORMED%'; END;
    PERFORM pg_temp.t_check('live: a response naming an unknown zone is refused', ok);
    BEGIN PERFORM trustride.fn_integration_route_matrix_apply('TRUSTRIDE_SIMULATOR', 'SIMULATOR', 'ref-sim',
      '{"routes":[{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02","distance_km":3,"duration_min":9}]}'); ok := false;
    EXCEPTION WHEN OTHERS THEN ok := true; END;
    PERFORM pg_temp.t_check('live: a simulator response is never stored as a provider route', ok);
    n := trustride.fn_integration_route_matrix_apply('TEST_PROVIDER', 'PRODUCTION', 'ref-001',
      '{"routes":[{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02","distance_km":4.2,"duration_min":13.5}]}');
    m := trustride.fn_integration_route_matrix_apply('TEST_PROVIDER', 'PRODUCTION', 'ref-001',
      '{"routes":[{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02","distance_km":4.2,"duration_min":13.5}]}');
    PERFORM pg_temp.t_check('live: the same provider response delivered twice is stored once', n = 1 AND m = 0, n || ' then ' || m);
    SELECT * INTO r FROM trustride.fn_integration_routing_compute('KSM-CBD-01', 'KSM-MILIMANI-02', gen_random_uuid());
    SELECT to_jsonb(l) INTO v FROM trustride.integration_routing_request_log l WHERE l.routing_request_id = r.routing_request_id;
    PERFORM pg_temp.t_check('live: pricing gets the provider route with its provenance (not simulated)',
      r.distance_km = 4.2 AND r.duration_min = 13.5 AND (v::jsonb)->>'simulated' = 'false' AND (v::jsonb)->>'provider' = 'TEST_PROVIDER' AND (v::jsonb)->>'provider_reference' = 'ref-001', left(v, 200));
    UPDATE trustride.integration_route_matrix SET valid_until = now() - interval '1 second' WHERE provider_reference = 'ref-001';
    BEGIN PERFORM * FROM trustride.fn_integration_routing_compute('KSM-CBD-01', 'KSM-MILIMANI-02', gen_random_uuid()); ok := false; v := 'stale route served';
    EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'ROUTING_UNAVAILABLE%'; v := SQLERRM; END;
    PERFORM pg_temp.t_check('live: a stale provider route is not used', ok, left(v, 160));
  END IF;
END
$$;
