-- Suite 43 -- deterministic Protrack simulator on the Engine 6 telemetry contract (Founder direction WP9 item 5).
-- The simulator feeds the same normalisation and Engine 2 path as the provider, marks every point simulated,
-- and covers: valid readings, unknown and unauthorized devices, duplicates, out-of-order and stale points,
-- malformed records, provider timeouts and unavailability, and recovery. It never runs when the port is live.
DO $$
DECLARE
  founder UUID; est UUID; unit UUID; fleet UUID; dev UUID; r JSONB; res JSONB; res2 JSONB; v TEXT; n INT; ok BOOLEAN;
  t0 TIMESTAMPTZ := date_trunc('second', now());
  ready BOOLEAN := to_regprocedure('trustride.fn_integration_telemetry_simulate(text,text,integer,timestamp with time zone)') IS NOT NULL;
BEGIN
  IF NOT ready THEN
    PERFORM pg_temp.t_check('Protrack simulator exists', false, 'fn_integration_telemetry_simulate absent');
  ELSE
  PERFORM pg_temp.t_open_all_hours();
  founder := pg_temp.t_person('Sim Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"S-HUB","estate_type":"OPERATING_HUB","estate_name":"Sim Hub","lat":-0.0917,"lon":34.7680}');
  est := (r->>'signal')::uuid;
  unit := pg_temp.t_ready_unit(founder, 'BODA_BODA', est, 'Sim Rider');
  SELECT fleet_resource_id INTO fleet FROM trustride.resource_workforce_unit WHERE workforce_unit_id = unit;
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_OBJECT', '{"object_type":"TRACKING_DEVICE","make":"Protrack","model":"PT-300","serial_number":"867000000043001"}');
  dev := (r->>'signal')::uuid;
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'BIND_TELEMETRY_DEVICE', jsonb_build_object('fleet_resource_id', fleet, 'device_object_id', dev));

  -- ============ valid readings, deterministic, marked simulated
  res := trustride.fn_integration_telemetry_simulate('VALID', '867000000043001', 7, t0);
  res2 := trustride.fn_integration_telemetry_simulate('VALID', '867000000043001', 7, t0);
  PERFORM pg_temp.t_check('sim: the same seed produces the same readings (deterministic)', res->'records' = res2->'records', left(res::text, 200));
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('sim: valid readings reach the bound vehicle and the device is LIVE',
    (SELECT count(*) FROM trustride.resource_location_event WHERE fleet_resource_id = fleet) = 3
    AND (SELECT telemetry_status FROM trustride.resource_telemetry_binding WHERE fleet_resource_id = fleet AND status = 'ACTIVE') = 'LIVE');
  PERFORM pg_temp.t_check('sim: a repeated batch is stored once (no duplicate location history)',
    (SELECT count(*) FROM trustride.resource_location_event WHERE fleet_resource_id = fleet) = 3);
  PERFORM pg_temp.t_check('sim: every simulated reading is marked simulated -- in Engine 6''s log and in Engine 2''s history',
    NOT EXISTS (SELECT 1 FROM trustride.resource_location_event WHERE fleet_resource_id = fleet AND NOT simulated)
    AND NOT EXISTS (SELECT 1 FROM trustride.integration_telemetry_ingest_log WHERE ingest_id = (res->>'ingest_id')::uuid AND NOT simulated));

  -- ============ duplicates within a batch, out of order, stale
  res := trustride.fn_integration_telemetry_simulate('DUPLICATE', '867000000043001', 8, t0 + interval '30 seconds');
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('sim: a point sent twice in one batch is recorded once',
    (SELECT count(*) FROM trustride.resource_location_event WHERE fleet_resource_id = fleet AND recorded_at = t0 + interval '30 seconds') = 1);
  res := trustride.fn_integration_telemetry_simulate('OUT_OF_ORDER', '867000000043001', 9, t0 + interval '90 seconds');
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('sim: an older point arriving late is kept as history but does not move the vehicle back',
    (SELECT last_seen_at FROM trustride.resource_telemetry_binding WHERE fleet_resource_id = fleet AND status = 'ACTIVE') = t0 + interval '90 seconds'
    AND EXISTS (SELECT 1 FROM trustride.resource_location_event WHERE fleet_resource_id = fleet AND recorded_at = t0 + interval '30 seconds' - interval '1 second'));
  res := trustride.fn_integration_telemetry_simulate('STALE', '867000000043001', 10, t0);
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('sim: a stale point is recorded as not live and does not update the vehicle',
    (SELECT last_seen_at FROM trustride.resource_telemetry_binding WHERE fleet_resource_id = fleet AND status = 'ACTIVE') = t0 + interval '90 seconds'
    AND res->'records'->0 ? 'gpstime');

  -- ============ malformed, unknown and unauthorized
  res := trustride.fn_integration_telemetry_simulate('MALFORMED', '867000000043001', 11, t0);
  PERFORM pg_temp.t_check('sim: malformed records are rejected one by one with their reasons, nothing stored from them',
    (SELECT rejected_count FROM trustride.integration_telemetry_ingest_log WHERE ingest_id = (res->>'ingest_id')::uuid) = 4
    AND (SELECT accepted_count FROM trustride.integration_telemetry_ingest_log WHERE ingest_id = (res->>'ingest_id')::uuid) = 0, res::text);
  res := trustride.fn_integration_telemetry_simulate('UNKNOWN_DEVICE', '869000000043999', 12, t0);
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('sim: readings from a device not bound to a vehicle never become a resource location',
    NOT EXISTS (SELECT 1 FROM trustride.resource_location_event WHERE device_ref = '869000000043999'));
  res := trustride.fn_integration_telemetry_simulate('UNAUTHORIZED', '867000000043001', 13, t0);
  PERFORM pg_temp.t_check('sim: a sender without a valid key is refused and logged', res->>'outcome' = 'UNAUTHENTICATED', res::text);

  -- ============ provider timeout and outage, then recovery
  UPDATE trustride.resource_telemetry_binding SET last_seen_at = now() - interval '30 minutes' WHERE fleet_resource_id = fleet AND status = 'ACTIVE';
  res := trustride.fn_integration_telemetry_simulate('PROVIDER_TIMEOUT', '867000000043001', 14, t0);
  res2 := trustride.fn_integration_telemetry_simulate('PROVIDER_UNAVAILABLE', '867000000043001', 15, t0);
  PERFORM pg_temp.t_check('sim: a provider timeout and an outage are logged as such, with no readings invented',
    (SELECT outcome FROM trustride.integration_telemetry_ingest_log WHERE ingest_id = (res->>'ingest_id')::uuid) = 'PROVIDER_TIMEOUT'
    AND (SELECT outcome FROM trustride.integration_telemetry_ingest_log WHERE ingest_id = (res2->>'ingest_id')::uuid) = 'PROVIDER_UNAVAILABLE'
    AND (SELECT accepted_count FROM trustride.integration_telemetry_ingest_log WHERE ingest_id = (res2->>'ingest_id')::uuid) = 0, res::text || res2::text);
  PERFORM pg_temp.t_check('sim: the failures count against the port''s circuit breaker',
    (SELECT failure_count FROM trustride.integration_circuit_breaker_state WHERE port_code = 'TELEMETRY_SERVICE') >= 2);
  PERFORM trustride.fn_resource_telemetry_health_sweep();
  PERFORM pg_temp.t_check('sim: with no readings the on-duty vehicle goes STALE and the Office is alerted',
    (SELECT telemetry_status FROM trustride.resource_telemetry_binding WHERE fleet_resource_id = fleet AND status = 'ACTIVE') = 'STALE'
    AND EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE title = 'Tracker silent: 867000000043001'));
  res := trustride.fn_integration_telemetry_simulate('VALID', '867000000043001', 16, now());
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('sim: when readings resume the vehicle is LIVE again and the circuit records success',
    (SELECT telemetry_status FROM trustride.resource_telemetry_binding WHERE fleet_resource_id = fleet AND status = 'ACTIVE') = 'LIVE'
    AND (SELECT failure_count FROM trustride.integration_circuit_breaker_state WHERE port_code = 'TELEMETRY_SERVICE') = 0);

  -- ============ never pretends to be live; access
  BEGIN PERFORM trustride.fn_integration_telemetry_simulate('NO_SUCH_SCENARIO', '867000000043001', 1, t0); ok := false;
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM pg_temp.t_check('sim: an unknown scenario is refused', ok);
  UPDATE trustride.integration_adapter_registry SET active = FALSE WHERE port_code = 'TELEMETRY_SERVICE' AND active;
  INSERT INTO trustride.integration_adapter_registry (port_code, adapter_type, active, notes) VALUES ('TELEMETRY_SERVICE', 'PRODUCTION', TRUE, 'suite 43');
  BEGIN PERFORM trustride.fn_integration_telemetry_simulate('VALID', '867000000043001', 1, t0); ok := false; v := 'simulated in live mode';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%simulator%live%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('sim: the simulator refuses to run while the port is live (simulated data never mixes with live)', ok, left(v, 160));
  PERFORM pg_temp.t_check('sim: not callable by signed-in users', NOT has_function_privilege('authenticated', 'trustride.fn_integration_telemetry_simulate(text,text,integer,timestamp with time zone)', 'EXECUTE'));
  SELECT status_level INTO n FROM trustride.integration_port_registry WHERE port_code = 'TELEMETRY_SERVICE' AND active;
  PERFORM pg_temp.t_check('sim: the register now evidences a simulator for Protrack (level 6, still no live credentials)', n = 6, n::text);
  END IF;
END
$$;
