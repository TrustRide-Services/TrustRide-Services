-- Suite 21 -- Engine 6 never presents a simulation as a real provider result
-- (TRS026-ENG-REMEDIATION-001: D11-D14). Every port is on the integration
-- register with its live-adapter status and blocking dependency; a port
-- whose live adapter is not built cannot be switched off the simulator; and
-- a port function refuses to run in a live mode it cannot honour.
DO $$
DECLARE
  founder UUID; n INT; v TEXT; ok BOOLEAN;
BEGIN
  founder := pg_temp.t_person('Intg Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');

  -- ============ the register is complete
  SELECT count(*), string_agg(port_code::text, ' ') INTO n, v FROM trustride.integration_port_registry
  WHERE active AND (to_jsonb(integration_port_registry) ->> 'live_adapter') IS NULL;
  PERFORM pg_temp.t_check('register: every active port states whether its live adapter is built', n = 0, coalesce(v, ''));
  SELECT count(*) INTO n FROM unnest(enum_range(NULL::trustride.integration_port_code_enum)) e(p)
  WHERE NOT EXISTS (SELECT 1 FROM trustride.integration_port_registry r WHERE r.port_code = e.p AND r.active);
  PERFORM pg_temp.t_check('register: every port code is on the register', n = 0, n::text);

  -- ============ D11: no switch to a live mode without a live adapter
  PERFORM pg_temp.t_as(founder);
  BEGIN PERFORM trustride.fn_integration_adapter_set('IDENTITY_AUTHORITY', 'PRODUCTION', 'suite 21'); ok := false; v := 'switched';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%no live adapter%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('D11 IDENTITY_AUTHORITY cannot leave the simulator (no live adapter built)', ok, left(v, 160));
  BEGIN PERFORM trustride.fn_integration_adapter_set('NTSA_SERVICE', 'SANDBOX', 'suite 21'); ok := false; v := 'switched';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%no live adapter%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('D11 NTSA_SERVICE cannot leave the simulator', ok, left(v, 160));
  BEGIN PERFORM trustride.fn_integration_adapter_set('SMS_SERVICE', 'PRODUCTION', 'suite 21'); ok := true; v := 'switched';
  EXCEPTION WHEN OTHERS THEN ok := false; v := SQLERRM; END;
  PERFORM pg_temp.t_check('positive control: SMS_SERVICE (live adapter built) can be switched', ok, left(v, 160));
  PERFORM trustride.fn_integration_adapter_set('SMS_SERVICE', 'SIMULATOR', 'suite 21');
  PERFORM pg_temp.t_admin();

  -- ============ D11/D12: a port function refuses a live mode it cannot honour (registry edited around the switch)
  UPDATE trustride.integration_adapter_registry SET active = FALSE WHERE port_code IN ('NTSA_SERVICE', 'ETIMS_SERVICE', 'ROUTING_SERVICE') AND active;
  INSERT INTO trustride.integration_adapter_registry (port_code, adapter_type, active, notes)
  VALUES ('NTSA_SERVICE', 'PRODUCTION', TRUE, 'suite 21'), ('ETIMS_SERVICE', 'PRODUCTION', TRUE, 'suite 21'), ('ROUTING_SERVICE', 'PRODUCTION', TRUE, 'suite 21');
  BEGIN PERFORM trustride.fn_integration_ntsa_verify('VEHICLE_REGISTRATION', 'KDA123A'); ok := false; v := 'simulated as if live';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'PROVIDER_NOT_INTEGRATED%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('D11 NTSA verification refuses PRODUCTION instead of simulating', ok, left(v, 160));
  BEGIN PERFORM trustride.fn_integration_etims_invoice_submit(gen_random_uuid(), 100); ok := false; v := 'simulated as if live';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'PROVIDER_NOT_INTEGRATED%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('D12 eTIMS submission refuses PRODUCTION instead of simulating', ok, left(v, 160));
  BEGIN PERFORM * FROM trustride.fn_integration_routing_compute('NOPE', 'NOPE'); ok := false; v := 'ran';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'PROVIDER_NOT_INTEGRATED%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('D11 routing refuses PRODUCTION instead of simulating', ok, left(v, 160));
END
$$;
