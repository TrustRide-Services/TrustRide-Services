-- ============================================================================
-- Engine 6 -- live identity and entity verification (provider-neutral; MetaMap first)
-- Construction Directive WP7 (section 2.6)
-- ============================================================================
-- Founder decision: MetaMap is the first-stage provider for individual and
-- business verification; direct IPRS is deferred.
--
-- Verified from MetaMap's documentation (2026-10-12):
--   POST https://api.prod.metamap.com/govchecks/v1/ke/iprs
--     in:  documentNumber, firstName, lastName, callbackUrl
--     out: data {documentNumber, givenNames, lastName, fullName, gender, dateOfBirth}
--          or error {type: govCheckError|systemError, code: kenyanIprs.notFound|kenyanIprs.serviceUnavailable}
--   POST https://api.prod.metamap.com/govchecks/v1/ke/brs
--     in:  registrationNumber, callbackURL
--     out: data {registrationNumber, companyName, companyType, registrationDate, registrationStatus,
--                postalAddress, physicalAddress, phoneNumber, kraPIN, shareCapital, shareHolders, ...}
--          or error code kenyanBrs.notFound
--   Auth: OAuth 2.0 client credentials (client id/secret as Basic) for a bearer token.
--   MetaMap documents no Kenyan NTSA, driving-licence or standalone KRA check.
--
-- What TrustRide does with an answer is unchanged: Engine 6 maps the provider's
-- answer FACTUALLY into VERIFICATION_COMPLETED and Foundation applies its own
-- onboarding rules (fn_verification_completed_accept). A found IPRS record is
-- RECORD_FOUND_STATUS_UNKNOWN -- never ALIVE_VALID, because MetaMap returns no
-- vital status -- and no KRA PIN is invented. Under Foundation's current rule
-- (ALIVE_VALID and a returned KRA PIN) a person verified through MetaMap's IPRS
-- check would therefore FAIL; that onboarding rule is a Founder decision, so the
-- IDENTITY_AUTHORITY port stays NOT_BUILT (cannot be switched live) until it is
-- taken. Entity verification through BRS returns the company's KRA PIN.
--
-- Built here:
--   * fn_integration_identity_request_live -- non-simulator mode: an outbound
--     IDENTITY_VERIFY / ENTITY_VERIFY request through the integration gateway
--     (one per verification: idempotent on the verification id);
--   * fn_integration_identity_apply_outcome -- the provider's answer (sync result
--     or webhook), once per verification; a provider failure after the governed
--     retries completes as PROVIDER_UNAVAILABLE (never left pending);
--   * fn_integration_metamap_webhook_ingest -- callback ingestion (service role),
--     logged, duplicate-safe;
--   * logs record the provider and the outbound request; the raw answer is kept
--     without shareholder identity numbers.
-- ============================================================================

ALTER TABLE trustride.integration_identity_verification_log ADD COLUMN provider TEXT NOT NULL DEFAULT 'TRUSTRIDE_SIMULATOR', ADD COLUMN outbound_request_id UUID;
ALTER TABLE trustride.integration_entity_verification_log ADD COLUMN provider TEXT NOT NULL DEFAULT 'TRUSTRIDE_SIMULATOR', ADD COLUMN outbound_request_id UUID;

CREATE FUNCTION trustride.fn_integration_identity_request_live(p_signal_id uuid, p_payload jsonb, p_correlation_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
DECLARE
  v_entity BOOLEAN := p_payload->>'verification_type' = 'ENTITY_REGISTRATION';
  v_vid UUID := (p_payload->>'verification_id')::uuid;
  v_names TEXT[] := regexp_split_to_array(trim(coalesce(p_payload->>'full_legal_name', '')), '\s+');
  v_req UUID;
BEGIN
  SELECT request_id INTO v_req FROM trustride.integration_outbound_request
  WHERE port_code = 'IDENTITY_AUTHORITY' AND ref_id = v_vid ORDER BY created_at LIMIT 1;
  IF v_req IS NULL THEN
    v_req := trustride.fn_integration_outbound_enqueue('IDENTITY_AUTHORITY', CASE WHEN v_entity THEN 'ENTITY_VERIFY' ELSE 'IDENTITY_VERIFY' END,
      CASE WHEN v_entity THEN jsonb_build_object('provider', 'METAMAP', 'verification_id', v_vid, 'subject_user_id', p_payload->>'subject_user_id',
                                                 'registration_number', p_payload->>'registration_number', 'legal_name', p_payload->>'full_legal_name')
           ELSE jsonb_build_object('provider', 'METAMAP', 'verification_id', v_vid, 'subject_user_id', p_payload->>'subject_user_id',
                                   'document_number', p_payload->>'national_id', 'first_name', v_names[1], 'last_name', v_names[array_length(v_names, 1)]) END,
      'VERIFICATION', v_vid, p_correlation_id);
  END IF;
  UPDATE trustride.integration_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(),
    payload_out = jsonb_build_object('pending_provider', 'METAMAP', 'outbound_request_id', v_req)
  WHERE signal_id = p_signal_id;
  RETURN v_req;
END;
$function$;

CREATE FUNCTION trustride.fn_integration_identity_apply_outcome(p_request trustride.integration_outbound_request, p_final_success boolean, p_final_failure boolean)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
DECLARE
  v_vid UUID := p_request.ref_id;
  v_entity BOOLEAN := p_request.operation = 'ENTITY_VERIFY';
  v_resp JSONB := coalesce(p_request.response, '{}'::jsonb);
  v_data JSONB := CASE WHEN jsonb_typeof(v_resp->'data') = 'object' THEN v_resp->'data' END;   -- JSON null is not an answer
  v_err TEXT := coalesce(v_resp->'error'->>'code', '');
  v_name TEXT; v_status TEXT; v_kra TEXT; v_raw JSONB; v_rec RECORD;
BEGIN
  IF NOT (p_final_success OR p_final_failure) THEN RETURN 'PENDING'; END IF;
  SELECT * INTO v_rec FROM trustride.verification_record WHERE verification_id = v_vid;
  IF v_rec.verification_id IS NULL THEN RAISE EXCEPTION 'identity outcome for unknown verification %', v_vid; END IF;
  IF v_rec.outcome <> 'PENDING' OR EXISTS (SELECT 1 FROM trustride.integration_event_outbox
       WHERE signal_type = 'VERIFICATION_COMPLETED' AND idempotency_key = 'VERIFICATION_COMPLETED:' || v_vid::text) THEN
    RETURN 'ALREADY_COMPLETED';   -- duplicate answer (e.g. webhook after the synchronous result)
  END IF;

  IF p_final_failure OR v_resp->'error'->>'type' = 'systemError' THEN
    v_status := 'PROVIDER_UNAVAILABLE';
  ELSIF v_err LIKE '%notFound' THEN
    v_status := 'NOT_FOUND';
  ELSIF v_data IS NULL OR jsonb_typeof(v_data) <> 'object' THEN
    v_status := 'PROVIDER_UNAVAILABLE';   -- an answer we cannot read is not a verification
  ELSIF v_entity THEN
    v_name := v_data->>'companyName';
    v_status := CASE WHEN lower(coalesce(v_data->>'registrationStatus', '')) IN ('registered', 'active') THEN 'VALID'
                     ELSE upper(coalesce(nullif(v_data->>'registrationStatus', ''), 'STATUS_UNKNOWN')) END;
    v_kra := nullif(trim(coalesce(v_data->>'kraPIN', '')), '');
  ELSE
    v_name := coalesce(nullif(v_data->>'fullName', ''), trim(concat_ws(' ', v_data->>'givenNames', v_data->>'lastName')));
    v_status := 'RECORD_FOUND_STATUS_UNKNOWN';   -- the provider gives no vital status
    v_kra := NULL;                               -- the provider gives no KRA PIN
  END IF;
  -- Keep the answer, without shareholder identity numbers.
  v_raw := jsonb_build_object('provider', 'METAMAP', 'operation', p_request.operation, 'adapter', p_request.adapter_type,
    'error', v_resp->'error',
    'data', CASE WHEN v_data IS NULL THEN NULL ELSE v_data - 'shareHolders' || jsonb_build_object('shareholder_count', CASE WHEN jsonb_typeof(v_data->'shareHolders') = 'array' THEN jsonb_array_length(v_data->'shareHolders') ELSE 0 END) END);

  IF v_entity THEN
    INSERT INTO trustride.integration_entity_verification_log (verification_id, subject_user_id, submitted_registration_number, submitted_legal_name,
      submitted_kra_pin, returned_legal_name, returned_status, returned_kra_pin, adapter_type, raw_response, provider, outbound_request_id)
    VALUES (v_vid, v_rec.subject_user_id, coalesce(p_request.payload->>'registration_number', ''), coalesce(p_request.payload->>'legal_name', ''),
      NULL, v_name, v_status, v_kra, p_request.adapter_type, v_raw, 'METAMAP', p_request.request_id);
  ELSE
    INSERT INTO trustride.integration_identity_verification_log (verification_id, subject_user_id, submitted_national_id, submitted_legal_name,
      returned_legal_name, returned_status, returned_kra_pin, adapter_type, raw_response, responded_at, provider, outbound_request_id)
    VALUES (v_vid, v_rec.subject_user_id, coalesce(p_request.payload->>'document_number', ''),
      trim(concat_ws(' ', p_request.payload->>'first_name', p_request.payload->>'last_name')),
      v_name, v_status::trustride.integration_verification_outcome_enum, NULL, p_request.adapter_type, v_raw, now(), 'METAMAP', p_request.request_id);
  END IF;

  INSERT INTO trustride.integration_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_request.correlation_id, 'TRS026_ENG001_FDN', 'VERIFICATION_COMPLETED',
    jsonb_build_object('verification_id', v_vid, 'returned_legal_name', v_name, 'returned_status', v_status, 'returned_kra_pin', v_kra, 'raw_response', v_raw),
    'VERIFICATION_COMPLETED:' || v_vid::text);
  RETURN v_status;
END;
$function$;

-- The outbound outcome router hands identity answers to the function above.
DO $patch$
DECLARE
  v_def TEXT;
  v_old TEXT := E'  ELSIF p_request.operation = ''B2C_PAYOUT'' THEN\n    PERFORM trustride.fn_integration_payout_outcome(p_request, p_final_success, p_final_failure);\n';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_integration_outbound_apply_outcome(trustride.integration_outbound_request,boolean,boolean)'::regprocedure) INTO v_def;
  IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'outcome router anchor not found'; END IF;
  EXECUTE replace(v_def, v_old, v_old
    || E'  ELSIF p_request.operation IN (''IDENTITY_VERIFY'', ''ENTITY_VERIFY'') THEN\n'
    || E'    PERFORM trustride.fn_integration_identity_apply_outcome(p_request, p_final_success, p_final_failure);\n');
END;
$patch$;

-- Verification requested: the simulator in SIMULATOR mode (unchanged); otherwise the live request.
DO $patch$
DECLARE
  v_def TEXT;
  v_old TEXT := E'PERFORM trustride.fn_integration_port_assert_simulated(''IDENTITY_AUTHORITY'');';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_integration_verification_requested_accept(uuid)'::regprocedure) INTO v_def;
  IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'identity guard anchor not found'; END IF;
  EXECUTE replace(v_def, v_old,
       E'IF trustride.fn_integration_adapter_mode(''IDENTITY_AUTHORITY'') <> ''SIMULATOR'' THEN\n'
    || E'    PERFORM trustride.fn_integration_identity_request_live(p_signal_id, v_payload, v_correlation_id);\n'
    || E'    RETURN ''ACCEPTED'';\n'
    || E'  END IF;');
END;
$patch$;

-- Webhook / callback from the provider (service role, via the metamap-webhook Edge Function).
CREATE FUNCTION trustride.fn_integration_metamap_webhook_ingest(p_request_id uuid, p_body jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
DECLARE
  v_req trustride.integration_outbound_request;
  v_webhook UUID;
BEGIN
  INSERT INTO trustride.integration_webhook_log (port_code, provider_reference, signature_valid, raw_payload, processed)
  VALUES ('IDENTITY_AUTHORITY', p_request_id::text, TRUE, p_body - 'shareHolders', FALSE) RETURNING webhook_id INTO v_webhook;
  SELECT * INTO v_req FROM trustride.integration_outbound_request WHERE request_id = p_request_id AND port_code = 'IDENTITY_AUTHORITY';
  IF v_req.request_id IS NULL THEN
    UPDATE trustride.integration_webhook_log SET processed = TRUE, processed_at = now() WHERE webhook_id = v_webhook;
    RETURN 'UNKNOWN_REQUEST';
  END IF;
  IF v_req.status = 'SUCCEEDED' THEN
    UPDATE trustride.integration_webhook_log SET processed = TRUE, processed_at = now() WHERE webhook_id = v_webhook;
    RETURN 'ALREADY_APPLIED';
  END IF;
  PERFORM trustride.fn_integration_outbound_result(p_request_id, TRUE, coalesce(p_body->>'id', p_request_id::text), p_body, NULL);
  UPDATE trustride.integration_webhook_log SET processed = TRUE, processed_at = now() WHERE webhook_id = v_webhook;
  RETURN 'APPLIED';
END;
$function$;

UPDATE trustride.integration_port_registry SET
  primary_vendor = 'MetaMap (GovChecks: ke/iprs, ke/brs)', secondary_vendor = 'Direct IPRS (deferred by Founder)',
  live_operations = ARRAY['IDENTITY_VERIFY (MetaMap ke/iprs)', 'ENTITY_VERIFY (MetaMap ke/brs)'],
  readiness = 'NOT_WIRED_PENDING_DECISION',
  blocking_dependency = 'Founder decision on the person onboarding rule: MetaMap''s IPRS check returns names, date of birth and gender but no vital status and no KRA PIN, while Foundation requires ALIVE_VALID and a returned KRA PIN; then a MetaMap account (client id and secret as Edge secrets) and ODPC registration. Entity (BRS) verification returns the KRA PIN.'
WHERE port_code = 'IDENTITY_AUTHORITY' AND active;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_integration_metamap_webhook_ingest(uuid, jsonb) TO service_role;
SELECT trustride.fn_platform_conformance_assert();
