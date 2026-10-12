-- ============================================================================
-- TRS026 Construction Directive section 4.8 (WP7) -- the nine-level integration
-- status on the integration register. Each port states every checkpoint with its
-- evidence:
--   1 contract defined            2 adapter implemented        3 simulator implemented
--   4 internal workflow and persistence tested                 5 security and audit tests passed
--   6 live adapter implemented    7 provider credentials and authorization available
--   8 live end-to-end transaction tested                       9 operational monitoring and recovery proven
-- status_level is the highest checkpoint reached with no gap below it (computed,
-- never typed). Checkpoints 7-9 cannot be recorded for a port whose live adapter
-- is not built. As of this migration no provider credentials exist in staging,
-- no live transaction has been run, and no port is above level 6.
-- ============================================================================

CREATE FUNCTION trustride.fn_integration_status_level(p_checkpoints jsonb)
 RETURNS smallint
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
  SELECT coalesce(min(g) - 1, 9)::smallint FROM generate_series(1, 9) g
  WHERE NOT coalesce((p_checkpoints->g::text->>'met')::boolean, false);
$function$;

ALTER TABLE trustride.integration_port_registry
  ADD COLUMN status_checkpoints JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN status_level SMALLINT GENERATED ALWAYS AS (trustride.fn_integration_status_level(status_checkpoints)) STORED,
  ADD CONSTRAINT integration_port_live_levels_need_live_adapter CHECK (
    live_adapter = 'BUILT' OR NOT (coalesce((status_checkpoints->'7'->>'met')::boolean, false)
                               OR coalesce((status_checkpoints->'8'->>'met')::boolean, false)
                               OR coalesce((status_checkpoints->'9'->>'met')::boolean, false)));

CREATE FUNCTION pg_temp.cp(p_met boolean[], p_evidence text[]) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_object_agg(i::text, jsonb_build_object('met', p_met[i], 'evidence', p_evidence[i])) FROM generate_series(1, 9) i;
$$;

UPDATE trustride.integration_port_registry SET status_checkpoints = pg_temp.cp(v.met, v.ev)
FROM (VALUES
  ('PAYMENT_GATEWAY', ARRAY[true, true, true, true, true, true, false, false, false], ARRAY[
    'Outbound STK_PUSH / B2C_PAYOUT; mpesa-callback kinds stk, b2c-result, b2c-timeout',
    'integration-gateway/providers.ts stkPush, b2cPayout',
    'fn_integration_payment_stk_simulate; simulator confirmation command',
    'Suites 05 (payments), 15 (callback integrity), 31 (unknown outcomes, sweep)',
    'Suites 13, 15 (callback token, idempotency, amount checks), 31 (no automatic money re-send)',
    'providers.ts against Daraja sandbox/production hosts; providers.test.ts (mocked HTTP)',
    'Not available: no Daraja credentials as Edge secrets',
    'Not done: no sandbox or live M-Pesa transaction executed',
    'Not done: requires a live transaction first']),
  ('SMS_SERVICE', ARRAY[true, true, true, true, true, true, false, false, false], ARRAY[
    'NOTIFY_SMS (destination, body)', 'providers.ts sendSms (Africa''s Talking)', 'Outbound simulator via fn_integration_outbound_simulate',
    'Suite 02 (contact verification, fan-out, retry sweep)', 'Suites 02 (cross-user isolation), 13',
    'providers.ts against Africa''s Talking sandbox/production; providers.test.ts (mocked HTTP)',
    'Not available: no AT_USERNAME / AT_API_KEY / sender ID secrets', 'Not done', 'Not done']),
  ('WHATSAPP_SERVICE', ARRAY[true, true, true, true, true, true, false, false, false], ARRAY[
    'NOTIFY_WHATSAPP (destination, subject, body; template optional)', 'providers.ts sendWhatsapp (WhatsApp Cloud API)', 'Outbound simulator via fn_integration_outbound_simulate',
    'Suite 34 (simulator delivery, live hand-off, failure, single delivery record)', 'Suite 34 (cross-user isolation; destination masked)',
    'providers.ts against graph.facebook.com; providers.test.ts (mocked HTTP)',
    'Not available: no WhatsApp Business account, approved template or token', 'Not done', 'Not done']),
  ('EMAIL_SERVICE', ARRAY[true, true, true, true, true, true, false, false, false], ARRAY[
    'NOTIFY_EMAIL (destination, subject, body)', 'integration-gateway/gmail.ts (Gmail API users.messages.send)', 'Outbound simulator via fn_integration_outbound_simulate',
    'Suite 31 (live hand-off to the gateway)', 'gmail.test.ts (header injection, recipient validation, sandbox isolation, token handling)',
    'gmail.ts: Workspace service account or OAuth refresh token; gmail.test.ts (mocked HTTP)',
    'Not available: no Google mailbox credentials', 'Not done', 'Not done']),
  ('TELEMETRY_SERVICE', ARRAY[true, true, false, true, true, true, false, false, false], ARRAY[
    'Push (Bearer system key, point list) and poll ({"mode":"poll"}) to fn_integration_telemetry_ingest',
    'protrack-ingest/protrack.ts', 'Not built: no telemetry simulator; tests push points through the production ingest',
    'Suite 07 (ingest, binding, staleness)', 'Suite 07 (bad key refused and logged); protrack.test.ts (fail-closed poll, malformed push)',
    'protrack.ts poll against the Protrack Open API; protrack.test.ts (mocked HTTP)',
    'Not available: no PROTRACK_* credentials or devices', 'Not done', 'Not done']),
  ('IDENTITY_AUTHORITY', ARRAY[true, true, true, true, true, true, false, false, false], ARRAY[
    'IDENTITY_VERIFY / ENTITY_VERIFY outbound; metamap-webhook callback; VERIFICATION_COMPLETED to Foundation',
    'fn_integration_identity_request_live / _apply_outcome; integration-gateway/metamap.ts', 'fn_integration_identity_verify_simulate, fn_integration_entity_verify_simulate',
    'Suites 02, 29', 'Suite 29 (service-role callbacks, shareholder minimisation, single application)',
    'metamap.ts (MetaMap GovChecks ke/iprs, ke/brs); metamap.test.ts (mocked HTTP). Switching live is blocked by the person-onboarding decision',
    'Not available: no MetaMap account', 'Not done', 'Not done']),
  ('NTSA_SERVICE', ARRAY[true, true, true, true, true, false, false, false, false], ARRAY[
    'Plate verification; VIN/chassis identification (NTSA_VEHICLE_LOOKUP)', 'fn_integration_ntsa_verify, fn_integration_ntsa_vehicle_identify (Engine 6 boundary)',
    'fn_integration_ntsa_verify_simulate; simulated identification', 'Suites 03, 30', 'Suites 21, 30 (live mode refused, Office only)',
    'Not built: NTSA publishes no API; access needs an agreement or licensed gateway', 'Not available', 'Not done', 'Not done']),
  ('ETIMS_SERVICE', ARRAY[true, true, true, true, true, false, false, false, false], ARRAY[
    'Sales (basis stated, treatment undetermined), purchases, reconciliation', 'fn_integration_etims_sale_record, _purchase_record, _reconcile',
    'fn_integration_etims_invoice_submit_simulate (SIM- references, no KRA imitation)', 'Suite 32', 'Suites 21, 32 (determination gate, Office only, no KRA traffic)',
    'Not built: awaits the legal and tax determination, then KRA OSCU/VSCU onboarding and certification', 'Not available', 'Not done', 'Not done']),
  ('EPRA_SERVICE', ARRAY[true, true, true, true, true, false, false, false, false], ARRAY[
    'RECORD_EPRA_PRICE_CYCLE; fn_integration_epra_current', 'fn_integration_epra_cycle_record (Office records the published cycle)',
    'fn_integration_epra_fuel_price_ingest_simulate (never emits to pricing)', 'Suite 28', 'Suite 28 (validation, provenance, no simulated prices in pricing)',
    'Not applicable as an API: EPRA publishes no API. Applying prices to pricing awaits the Engine 5 derivation decision', 'Not applicable', 'Not done', 'Not done']),
  ('ROUTING_SERVICE', ARRAY[true, false, true, true, true, false, false, false, false], ARRAY[
    'ROUTE_MATRIX outbound; fn_integration_route_matrix_apply; fn_integration_routing_compute', 'Not built: routing provider not chosen (Founder decision)',
    'fn_integration_routing_compute_simulate (provenance recorded)', 'Suite 28 (matrix apply, freshness, unavailable)', 'Suite 28 (malformed and simulator responses refused)',
    'Not built', 'Not available', 'Not done', 'Not done']),
  ('MAP_SERVICE', ARRAY[false, false, true, false, false, false, false, false, false], ARRAY[
    'Not defined: address search awaits a product decision', 'Not built', 'fn_integration_map_geocode_simulate', 'Not done', 'Not done', 'Not built', 'Not available', 'Not done', 'Not done']),
  ('VOICE_MASKING_SERVICE', ARRAY[false, false, true, false, false, false, false, false, false], ARRAY[
    'Not defined: masked calling awaits a product decision', 'Not built', 'fn_integration_voice_masking_provision_simulate', 'Not done', 'Not done', 'Not built', 'Not available', 'Not done', 'Not done']),
  ('USSD_SERVICE', ARRAY[false, false, true, false, false, false, false, false, false], ARRAY[
    'Not defined: a USSD channel awaits a product decision', 'Not built', 'fn_integration_ussd_session_advance_simulate', 'Not done', 'Not done', 'Not built', 'Not available', 'Not done', 'Not done']),
  ('PUSH_SERVICE', ARRAY[true, false, true, false, false, false, false, false, false], ARRAY[
    'NOTIFY_PUSH', 'Not built: the gateway refuses (no device tokens on the web surfaces)', 'Outbound simulator via fn_integration_outbound_simulate',
    'Not done', 'Not done', 'Not built', 'Not available', 'Not done', 'Not done'])
) v(port, met, ev)
WHERE port_code::text = v.port AND active;

DROP FUNCTION pg_temp.cp(boolean[], text[]);
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
