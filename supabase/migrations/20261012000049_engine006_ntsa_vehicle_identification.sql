-- ============================================================================
-- TRS026 Construction Directive WP7 (section 2.7) -- Engine 6 boundary for NTSA
-- vehicle identification by VIN or chassis (frame) number, with its simulator.
--
-- NTSA publishes no API for VIN/chassis lookup; access to its records needs an
-- agreement with NTSA or a licensed gateway. So no endpoint is invented and
-- nothing is scraped: the boundary validates and normalises the identifier,
-- answers from the simulator (marked simulated, with no vehicle particulars
-- invented), logs every lookup, and in a live mode refuses with
-- PROVIDER_NOT_INTEGRATED. The Office reaches it through the command gateway
-- (NTSA_VEHICLE_LOOKUP).
--
-- Validation:
--   VIN      17 characters, A-Z and 0-9 without I, O or Q (ISO 3779). The check
--            digit is not enforced: it is mandatory only for North American VINs.
--   CHASSIS  5-25 characters, A-Z, 0-9 and hyphens (Japanese frame numbers such as
--            NZE141-6012345 are not VINs). Formats vary by manufacturer, so only the
--            character set and length are checked.
-- ============================================================================

CREATE FUNCTION trustride.fn_integration_ntsa_vehicle_identify(p_identifier_type text, p_identifier text, p_correlation_id uuid DEFAULT NULL)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_kind TEXT := upper(trim(coalesce(p_identifier_type, '')));
  v_ref TEXT := upper(regexp_replace(coalesce(p_identifier, ''), '\s', '', 'g'));
  v_outcome trustride.integration_ntsa_check_outcome_enum;
  v_id UUID;
BEGIN
  IF v_kind = 'VIN' THEN
    IF v_ref !~ '^[A-HJ-NPR-Z0-9]{17}$' THEN
      RAISE EXCEPTION 'NTSA_IDENTIFIER_INVALID: a VIN is 17 characters, letters and digits without I, O or Q (got "%")', left(v_ref, 40);
    END IF;
  ELSIF v_kind = 'CHASSIS' THEN
    IF v_ref !~ '^[A-Z0-9][A-Z0-9-]{3,23}[A-Z0-9]$' THEN
      RAISE EXCEPTION 'NTSA_IDENTIFIER_INVALID: a chassis number is 5-25 letters, digits and hyphens (got "%")', left(v_ref, 40);
    END IF;
  ELSE
    RAISE EXCEPTION 'NTSA_IDENTIFIER_INVALID: identifier type must be VIN or CHASSIS (got "%")', left(v_kind, 20);
  END IF;

  PERFORM trustride.fn_integration_port_assert_simulated('NTSA_SERVICE');
  IF trustride.fn_integration_circuit_check('NTSA_SERVICE') = 'OPEN' THEN
    RAISE EXCEPTION 'fn_integration_ntsa_vehicle_identify: NTSA_SERVICE circuit is OPEN';
  END IF;

  -- Simulator: the platform's test pattern (a reference ending in 00 is not found).
  v_outcome := CASE WHEN right(v_ref, 2) = '00' THEN 'NOT_FOUND' ELSE 'VALID' END;
  PERFORM trustride.fn_integration_circuit_record_result('NTSA_SERVICE', TRUE, 400);

  INSERT INTO trustride.integration_ntsa_verification_log (check_type, reference_number, outcome, details, adapter_type, correlation_id)
  VALUES ('VEHICLE_IDENTIFICATION', v_ref, v_outcome,
    jsonb_build_object('simulated', true, 'identifier_type', v_kind,
      'reason', CASE WHEN v_outcome = 'NOT_FOUND' THEN 'TEST_PATTERN_00_SUFFIX' ELSE 'SIMULATED_RECORD_EXISTS' END,
      'note', 'Simulated answer: NTSA vehicle particulars are not available to TrustRide without an NTSA agreement'),
    'SIMULATOR', p_correlation_id)
  RETURNING ntsa_verification_id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE FUNCTION trustride.fn_present_cmd_ntsa_vehicle_lookup(p_session uuid, p_payload jsonb, p_command uuid)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'trustride', 'public'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN
    RAISE EXCEPTION 'Only the Office looks vehicles up with NTSA';
  END IF;
  RETURN trustride.fn_integration_ntsa_vehicle_identify(p_payload->>'identifier_type', p_payload->>'identifier', p_command);
END;
$function$;
INSERT INTO trustride.present_shell_capability_registry (top_shell, sub_shell, command_type, permitted, requires_delegated_authority)
VALUES ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'NTSA_VEHICLE_LOOKUP', TRUE, FALSE);

UPDATE trustride.integration_port_registry SET
  consumers = 'Fleet and vehicle verification (registration, inspection, licence); Office vehicle identification by VIN or chassis number (NTSA_VEHICLE_LOOKUP)',
  blocking_dependency = 'NTSA API access agreement or a licensed gateway (NTSA publishes no plate or VIN/chassis lookup API; no endpoint is invented and nothing is scraped); then the gateway adapter'
WHERE port_code = 'NTSA_SERVICE' AND active;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
