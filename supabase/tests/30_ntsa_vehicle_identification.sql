-- Suite 30 -- NTSA vehicle identification by VIN or chassis number (Construction Directive WP7, section 2.7).
-- The boundary validates the identifier before any lookup, answers from the simulator (marked simulated,
-- no vehicle particulars invented), logs every lookup, is reached by the Office through the command
-- gateway, and refuses a live mode: NTSA publishes no VIN/chassis lookup API, so none is invented.
DO $$
DECLARE
  founder UUID; cust UUID; r JSONB; v TEXT; n INT; id UUID; ok BOOLEAN; t RECORD;
  ready BOOLEAN := to_regprocedure('trustride.fn_integration_ntsa_vehicle_identify(text,text,uuid)') IS NOT NULL;
BEGIN
  IF NOT ready THEN
    PERFORM pg_temp.t_check('NTSA vehicle identification boundary exists', false, 'fn_integration_ntsa_vehicle_identify absent');
  ELSE
  founder := pg_temp.t_person('Ntsa Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  cust := pg_temp.t_customer('Ntsa Customer');

  -- ============ identifiers are validated before any lookup
  FOR t IN SELECT * FROM (VALUES
      ('a VIN shorter than 17 characters', 'VIN', 'JTDBR32E30051234'),
      ('a VIN longer than 17 characters', 'VIN', 'JTDBR32E3005123456'),
      ('a VIN containing I, O or Q (ISO 3779)', 'VIN', 'JTDBR32E3O0512345'),
      ('a VIN with punctuation', 'VIN', 'JTDBR32E-00512345'),
      ('a chassis number that is too short', 'CHASSIS', 'NZ1'),
      ('a chassis number with other characters', 'CHASSIS', 'NZE141/6012345'),
      ('an unknown identifier type', 'ENGINE', 'ABC12345'),
      ('an empty identifier', 'VIN', '   ')) x(label, kind, val) LOOP
    BEGIN PERFORM trustride.fn_integration_ntsa_vehicle_identify(t.kind, t.val); ok := false; v := 'accepted';
    EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'NTSA_IDENTIFIER_INVALID%'; v := SQLERRM; END;
    PERFORM pg_temp.t_check('NTSA: ' || t.label || ' is refused before any lookup', ok, left(v, 140));
  END LOOP;
  SELECT count(*) INTO n FROM trustride.integration_ntsa_verification_log WHERE check_type::text = 'VEHICLE_IDENTIFICATION' AND created_at = now();
  PERFORM pg_temp.t_check('NTSA: a refused identifier is not logged as a lookup', n = 0, n::text);

  -- ============ the simulator answers, marked simulated, with no particulars invented
  id := trustride.fn_integration_ntsa_vehicle_identify('VIN', ' jtdbr32e300512345 ');
  SELECT to_jsonb(l) INTO r FROM trustride.integration_ntsa_verification_log l WHERE ntsa_verification_id = id;
  PERFORM pg_temp.t_check('NTSA: a valid VIN is normalised and logged as a simulated VEHICLE_IDENTIFICATION',
    r->>'check_type' = 'VEHICLE_IDENTIFICATION' AND r->>'reference_number' = 'JTDBR32E300512345' AND r->>'outcome' = 'VALID'
    AND r->>'adapter_type' = 'SIMULATOR' AND (r->'details'->>'simulated')::boolean AND r->'details'->>'identifier_type' = 'VIN', r::text);
  PERFORM pg_temp.t_check('NTSA: the simulator invents no vehicle particulars (no make, model, owner or plate)',
    NOT (r->'details' ?| ARRAY['make', 'model', 'owner', 'plate_number', 'year']), (r->'details')::text);
  id := trustride.fn_integration_ntsa_vehicle_identify('CHASSIS', 'nze141-6012300');
  PERFORM pg_temp.t_check('NTSA: a chassis (frame) number is accepted; the simulator''s 00 pattern answers NOT_FOUND',
    (SELECT outcome::text || '|' || reference_number FROM trustride.integration_ntsa_verification_log WHERE ntsa_verification_id = id) = 'NOT_FOUND|NZE141-6012300');

  -- ============ the Office reaches it through the command gateway; others do not
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'NTSA_VEHICLE_LOOKUP', '{"identifier_type":"VIN","identifier":"1HGCM82633A004352"}');
  PERFORM pg_temp.t_check('NTSA: the Office looks a vehicle up through the command gateway', r->>'status' = 'TRANSLATED'
    AND EXISTS (SELECT 1 FROM trustride.integration_ntsa_verification_log WHERE reference_number = '1HGCM82633A004352' AND check_type::text = 'VEHICLE_IDENTIFICATION'), r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'NTSA_VEHICLE_LOOKUP', '{"identifier_type":"VIN","identifier":"1HGCM82633A00435"}');
  PERFORM pg_temp.t_check('NTSA: an invalid identifier through the command is rejected', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'NTSA_VEHICLE_LOOKUP', '{"identifier_type":"VIN","identifier":"1HGCM82633A004352"}');
  PERFORM pg_temp.t_check('NTSA: a customer cannot look vehicles up', coalesce(r->>'status', '') <> 'TRANSLATED', r::text);
  PERFORM pg_temp.t_check('NTSA: the boundary is not callable directly by signed-in users',
    NOT has_function_privilege('authenticated', 'trustride.fn_integration_ntsa_vehicle_identify(text,text,uuid)', 'EXECUTE'));

  -- ============ no live mode is pretended
  UPDATE trustride.integration_adapter_registry SET active = FALSE WHERE port_code = 'NTSA_SERVICE' AND active;
  INSERT INTO trustride.integration_adapter_registry (port_code, adapter_type, active, notes) VALUES ('NTSA_SERVICE', 'PRODUCTION', TRUE, 'suite 30');
  BEGIN PERFORM trustride.fn_integration_ntsa_vehicle_identify('VIN', '1HGCM82633A004352'); ok := false; v := 'simulated as if live';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'PROVIDER_NOT_INTEGRATED%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('NTSA: in a live mode the lookup refuses instead of simulating (no endpoint invented)', ok, left(v, 160));
  SELECT count(*) INTO n FROM trustride.integration_outbound_request WHERE port_code = 'NTSA_SERVICE' AND created_at = now();
  PERFORM pg_temp.t_check('NTSA: nothing is sent to any provider', n = 0, n::text);
  SELECT live_adapter || '|' || readiness INTO v FROM trustride.integration_port_registry WHERE port_code = 'NTSA_SERVICE' AND active;
  PERFORM pg_temp.t_check('NTSA: the register states the lookup exists only as a simulator', v = 'NOT_BUILT|SIMULATOR_ONLY_PENDING_PROVIDER'
    AND (SELECT live_operations FROM trustride.integration_port_registry WHERE port_code = 'NTSA_SERVICE' AND active) IS NULL
    AND (SELECT blocking_dependency FROM trustride.integration_port_registry WHERE port_code = 'NTSA_SERVICE' AND active) ILIKE '%VIN%', v);
  END IF;
END
$$;
