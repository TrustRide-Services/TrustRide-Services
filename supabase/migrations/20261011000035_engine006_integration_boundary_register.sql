-- ============================================================================
-- Engine 6 (Integration) -- the integration register and an honest live boundary
-- TRS026-ENG-REMEDIATION-001, findings D11, D12, D13, D14
-- ============================================================================
-- Forensic audit 2026-10-08: nine port functions (identity and entity
-- verification, NTSA, routing, geocoding, eTIMS, EPRA, USSD, voice masking,
-- the legacy WhatsApp sender) call their simulator whatever the port's
-- adapter mode, and fn_integration_adapter_set accepts SANDBOX/PRODUCTION for
-- any port. Switching IDENTITY_AUTHORITY to PRODUCTION would have kept
-- simulating identity checks while recording them under a live adapter.
--
-- Correction:
--   * integration_port_registry becomes the integration register: for every
--     port, whether a live adapter is built in the integration-gateway Edge
--     Function, the live operations, the TrustRide flows that use it, the
--     readiness class and the dependency that blocks going live;
--   * fn_integration_adapter_set refuses SANDBOX/PRODUCTION for a port whose
--     live adapter is not built, naming the dependency;
--   * each simulator-only port function refuses (PROVIDER_NOT_INTEGRATED) to
--     run in a live mode, so a registry edit made around the switch fails
--     loudly instead of passing a simulation off as a provider result.
-- In SIMULATOR mode every function behaves exactly as before (Engine 4 and
-- Engine 5 callers of routing are unaffected).
-- ============================================================================

ALTER TABLE trustride.integration_port_registry
  ADD COLUMN live_adapter TEXT CHECK (live_adapter IN ('BUILT', 'NOT_BUILT', 'INTERNAL')),
  ADD COLUMN live_operations TEXT[],
  ADD COLUMN consumers TEXT,
  ADD COLUMN readiness TEXT CHECK (readiness IN ('LIVE_READY_PENDING_CREDENTIALS', 'SIMULATOR_ONLY_PENDING_PROVIDER',
                                                 'NOT_WIRED_PENDING_DECISION', 'INTERNAL')),
  ADD COLUMN blocking_dependency TEXT;

UPDATE trustride.integration_port_registry r SET
  live_adapter = x.live_adapter, live_operations = x.ops, consumers = x.consumers, readiness = x.readiness, blocking_dependency = x.dep
FROM (VALUES
  ('PAYMENT_GATEWAY', 'BUILT', ARRAY['STK_PUSH', 'B2C_PAYOUT'], 'Order payment (STK push, callback via mpesa-callback), vendor payouts (B2C)', 'LIVE_READY_PENDING_CREDENTIALS',
     'Safaricom Daraja production credentials (shortcode, passkey, consumer key and secret, B2C initiator) and MPESA_CALLBACK_TOKEN as Edge secrets; Safaricom go-live approval'),
  ('SMS_SERVICE', 'BUILT', ARRAY['NOTIFY_SMS'], 'Contact verification codes, customer and staff notifications, critical Office alerts', 'LIVE_READY_PENDING_CREDENTIALS',
     'Africa''s Talking account, API key and approved sender ID as Edge secrets'),
  ('WHATSAPP_SERVICE', 'BUILT', ARRAY['NOTIFY_WHATSAPP'], 'Notifications on the WhatsApp channel (fn_integration_notification_send)', 'LIVE_READY_PENDING_CREDENTIALS',
     'WhatsApp Business account with approved templates and provider credentials as Edge secrets'),
  ('TELEMETRY_SERVICE', 'BUILT', ARRAY['PROTRACK_POLL', 'PROTRACK_PUSH'], 'Vehicle and device GPS tracking (protrack-ingest, every 30 seconds)', 'LIVE_READY_PENDING_CREDENTIALS',
     'Protrack account credentials (PROTRACK_*) as Edge secrets'),
  ('NOTIFICATION_ROUTER', 'INTERNAL', NULL, 'Channel choice, preferences and quiet hours for every notification', 'INTERNAL', NULL),
  ('IDENTITY_AUTHORITY', 'NOT_BUILT', NULL, 'Registration: person identity (IPRS) and organisation (BRS registration, KRA PIN) verification', 'SIMULATOR_ONLY_PENDING_PROVIDER',
     'Contract with a licensed IPRS/BRS data provider; registration with the Office of the Data Protection Commissioner; then the gateway adapter'),
  ('NTSA_SERVICE', 'NOT_BUILT', NULL, 'Fleet and vehicle verification (registration, inspection, licence)', 'SIMULATOR_ONLY_PENDING_PROVIDER',
     'NTSA API access agreement or a licensed gateway; then the gateway adapter'),
  ('ROUTING_SERVICE', 'NOT_BUILT', NULL, 'Distance and duration at order placement (Engine 4) and dispatch costing (Engine 5)', 'SIMULATOR_ONLY_PENDING_PROVIDER',
     'Provider choice (HERE, Google or self-hosted OSM) and a Founder ruling, because routing distance feeds Engine 5 pricing'),
  ('MAP_SERVICE', 'NOT_BUILT', NULL, 'None wired (address search and geocoding are not used by any screen)', 'NOT_WIRED_PENDING_DECISION',
     'Product decision on address search; Google Maps Platform key'),
  ('ETIMS_SERVICE', 'NOT_BUILT', NULL, 'None wired (no invoice is submitted on settlement)', 'NOT_WIRED_PENDING_DECISION',
     'Legal and tax determination of who issues the eTIMS invoice for a TrustRide fare (TrustRide on its commission, or on the full fare as agent) and KRA eTIMS VSCU/OSCU onboarding'),
  ('EPRA_SERVICE', 'NOT_BUILT', NULL, 'None wired (Engine 5 fuel index accepts EPRA_FUEL_INDEX_UPDATED but nothing emits it)', 'NOT_WIRED_PENDING_DECISION',
     'Founder ruling: Engine 5 pricing is not to change, so feeding EPRA prices into it is a Founder decision; EPRA data source'),
  ('USSD_SERVICE', 'NOT_BUILT', NULL, 'None wired (no inbound USSD endpoint)', 'NOT_WIRED_PENDING_DECISION',
     'Product decision on a USSD channel; Africa''s Talking USSD service code'),
  ('VOICE_MASKING_SERVICE', 'NOT_BUILT', NULL, 'None wired (customer and operator do not call each other through TrustRide)', 'NOT_WIRED_PENDING_DECISION',
     'Product decision on masked calling; provider with Kenyan proxy numbers'),
  ('EMAIL_SERVICE', 'NOT_BUILT', NULL, 'Notifications on the email channel (the gateway returns EMAIL_PROVIDER_NOT_SELECTED); sign-up and password emails go through Supabase Auth, not this port', 'NOT_WIRED_PENDING_DECISION',
     'Founder selects a transactional email provider'),
  ('PUSH_SERVICE', 'NOT_BUILT', NULL, 'Notifications on the push channel (the gateway returns PUSH_NOT_AVAILABLE: the web app registers no device tokens)', 'NOT_WIRED_PENDING_DECISION',
     'A native app, or web push with device-token registration')
) AS x(port, live_adapter, ops, consumers, readiness, dep)
WHERE r.port_code::text = x.port AND r.active;

DO $check$
BEGIN
  IF EXISTS (SELECT 1 FROM trustride.integration_port_registry WHERE active AND (live_adapter IS NULL OR readiness IS NULL)) THEN
    RAISE EXCEPTION 'integration register incomplete';
  END IF;
END;
$check$;

-- A port function that only has its simulator refuses a live mode.
CREATE FUNCTION trustride.fn_integration_port_assert_simulated(p_port_code trustride.integration_port_code_enum)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_mode trustride.integration_adapter_type_enum := trustride.fn_integration_adapter_mode(p_port_code);
BEGIN
  IF v_mode <> 'SIMULATOR' THEN
    RAISE EXCEPTION 'PROVIDER_NOT_INTEGRATED: % is set to % but this TrustRide function has only its simulator -- %', p_port_code, v_mode,
      coalesce((SELECT blocking_dependency FROM trustride.integration_port_registry WHERE port_code = p_port_code AND active), 'live adapter not built');
  END IF;
END;
$function$;

DO $patch$
DECLARE
  f RECORD;
  v_def TEXT;
  v_old TEXT;
BEGIN
  FOR f IN SELECT * FROM (VALUES
    ('fn_integration_verification_requested_accept(uuid)', 'IDENTITY_AUTHORITY'),
    ('fn_integration_ntsa_verify(trustride.integration_ntsa_check_type_enum,text,uuid)', 'NTSA_SERVICE'),
    ('fn_integration_routing_compute(text,text,uuid)', 'ROUTING_SERVICE'),
    ('fn_integration_map_geocode(text,uuid)', 'MAP_SERVICE'),
    ('fn_integration_etims_invoice_submit(uuid,numeric,text,uuid)', 'ETIMS_SERVICE'),
    ('fn_integration_epra_fuel_price_ingest(text,trustride.cost_jurisdiction_enum,uuid)', 'EPRA_SERVICE'),
    ('fn_integration_ussd_session_advance(text,text,text)', 'USSD_SERVICE'),
    ('fn_integration_voice_masking_provision(text,text,uuid)', 'VOICE_MASKING_SERVICE'),
    ('fn_integration_whatsapp_send(uuid,text,jsonb,uuid)', 'WHATSAPP_SERVICE')) AS t(sig, port)
  LOOP
    SELECT pg_get_functiondef(('trustride.' || f.sig)::regprocedure) INTO v_def;
    v_old := 'v_circuit := trustride.fn_integration_circuit_check(''' || f.port || ''');';
    IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'circuit check not found in %', f.sig; END IF;
    v_def := replace(v_def, v_old, 'PERFORM trustride.fn_integration_port_assert_simulated(''' || f.port || ''');' || E'\n  ' || v_old);
    EXECUTE v_def;
  END LOOP;
END;
$patch$;

-- The switch refuses a live mode the platform cannot honour.
DO $patch$
DECLARE
  v_def TEXT;
  v_old TEXT := E'    RAISE EXCEPTION ''Only TrustRide Office (Founder or Administrator) may switch integration adapters'';\n  END IF;\n';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_integration_adapter_set(trustride.integration_port_code_enum,trustride.integration_adapter_type_enum,text)'::regprocedure) INTO v_def;
  IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'adapter_set role check not found'; END IF;
  v_def := replace(v_def, v_old, v_old
    || E'  IF p_adapter_type <> ''SIMULATOR'' AND NOT EXISTS (SELECT 1 FROM trustride.integration_port_registry\n'
    || E'                                                  WHERE port_code = p_port_code AND active AND live_adapter = ''BUILT'') THEN\n'
    || E'    RAISE EXCEPTION ''% has no live adapter built -- it stays on the simulator until: %'', p_port_code,\n'
    || E'      coalesce((SELECT blocking_dependency FROM trustride.integration_port_registry WHERE port_code = p_port_code AND active), ''a live adapter is built'');\n'
    || E'  END IF;\n');
  EXECUTE v_def;
END;
$patch$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
