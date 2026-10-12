-- ============================================================================
-- TRS026 Construction Directive 2.11 (WP8) -- safe registration retry, and one
-- identity per national ID (Foundation, Engine 1).
--
-- Defects found by inspection (fn_registration_retry_primary was already
-- callable by any signed-in person, with no screen):
--   * nothing stopped two identities holding the same national ID, although
--     FDN-001 Art.13 says duplication is structurally impossible;
--   * a retry replayed exactly the same details after a definitive answer, and
--     could not correct a typo;
--   * two retries at once could open two verifications (no row lock);
--   * on success Foundation activated every NATIONAL_ID row of the person, so an
--     ID corrected on retry would have re-activated the wrong one.
--
-- Retryable states (now defined):
--   * the identity is VERIFICATION_FAILED and no verification is pending;
--   * after PROVIDER_UNAVAILABLE (the register was never consulted) the same
--     details may be sent again;
--   * after any definitive answer (invalid, deceased, not found, record found
--     but not confirmable, names not matching, ID held by another identity) the
--     person must correct the name or ID number -- the same details are refused.
--   No attempt limit is imposed: none is set in the specifications (open item).
-- A national ID held by another verified identity can be neither captured nor
-- retried; a verification that would create a second holder fails with
-- NATIONAL_ID_HELD_BY_ANOTHER_IDENTITY. A unique index is the backstop.
-- ============================================================================

CREATE UNIQUE INDEX user_identifier_national_id_one_holder ON trustride.user_identifier (identifier_value)
  WHERE identifier_type = 'NATIONAL_ID' AND status = 'ACTIVE';

CREATE FUNCTION trustride.fn_registration_national_id_holder(p_national_id text, p_except uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
  SELECT user_id FROM trustride.user_identifier
  WHERE identifier_type = 'NATIONAL_ID' AND status = 'ACTIVE'
    AND identifier_value = regexp_replace(coalesce(p_national_id, ''), '\s', '', 'g')
    AND user_id IS DISTINCT FROM p_except
  LIMIT 1;
$function$;

-- First capture: refuse an ID another verified identity holds (nothing is created).
DO $patch$
DECLARE
  v_def TEXT;
  v_old TEXT := E'  v_user_id := trustride.fn_user_register(';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_registration_capture_primary(text,text,boolean)'::regprocedure) INTO v_def;
  IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'capture anchor not found'; END IF;
  EXECUTE replace(v_def, v_old,
       E'  IF trustride.fn_registration_national_id_holder(p_national_id, auth.uid()) IS NOT NULL THEN\n'
    || E'    RAISE EXCEPTION ''This national ID is already registered to another identity -- one person, one TrustRide identity. Contact TrustRide support if this is your ID.'';\n'
    || E'  END IF;\n\n'
    || v_old);
END;
$patch$;

-- Verification completion: never a second holder; activate only the pending ID; record the provider's answer.
DO $patch$
DECLARE
  v_def TEXT;
  a1 TEXT := E'  IF NOT v_kra_present  THEN v_reasons := array_append(v_reasons, ''KRA_PIN_NOT_RETURNED''); END IF;';
  a2 TEXT := E'  IF v_names_match AND v_status_valid AND v_kra_present THEN';
  a3 TEXT := E'WHERE user_id = v_subject_user_id AND identifier_type = ''NATIONAL_ID'';';
  a4 TEXT := E'jsonb_build_object(''verification_id'', p_verification_id, ''reasons'', to_jsonb(v_reasons), ''raw_response'', p_raw_response)';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'trustride' AND p.proname = 'fn_verification_completed_accept';
  IF position(a1 IN v_def) = 0 OR position(a2 IN v_def) = 0 OR position(a3 IN v_def) = 0 OR position(a4 IN v_def) = 0 THEN
    RAISE EXCEPTION 'verification completion anchors not found';
  END IF;
  v_def := replace(v_def, a1, a1
    || E'\n  IF trustride.fn_registration_national_id_holder((SELECT national_id_ref FROM trustride.person_profile WHERE user_id = v_subject_user_id), v_subject_user_id) IS NOT NULL THEN\n'
    || E'    v_reasons := array_append(v_reasons, ''NATIONAL_ID_HELD_BY_ANOTHER_IDENTITY'');\n  END IF;');
  v_def := replace(v_def, a2, E'  IF v_names_match AND v_status_valid AND v_kra_present AND cardinality(v_reasons) = 0 THEN');
  v_def := replace(v_def, a3, E'WHERE user_id = v_subject_user_id AND identifier_type = ''NATIONAL_ID'' AND status = ''PENDING'';');
  v_def := replace(v_def, a4, E'jsonb_build_object(''verification_id'', p_verification_id, ''reasons'', to_jsonb(v_reasons), ''returned_status'', p_returned_status, ''raw_response'', p_raw_response)');
  EXECUTE v_def;
END;
$patch$;

-- The last identity result of a person, from Foundation's own audit record of it.
CREATE FUNCTION trustride.fn_registration_last_result(p_user_id uuid)
 RETURNS TABLE(verification_id uuid, outcome text, returned_status text, reasons jsonb)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
  SELECT v.verification_id, v.outcome, a.after_snapshot->>'returned_status', coalesce(a.after_snapshot->'reasons', '[]'::jsonb)
  FROM (SELECT * FROM trustride.verification_record WHERE subject_user_id = p_user_id AND verification_type = 'NATIONAL_ID'
        ORDER BY coalesce(verified_at, 'infinity'::timestamptz) DESC, ctid DESC LIMIT 1) v
  LEFT JOIN LATERAL (SELECT al.after_snapshot FROM trustride.audit_log al
                     WHERE al.entity_id = p_user_id AND al.action = 'REGISTRATION_PRIMARY_FAILED'
                       AND al.after_snapshot->>'verification_id' = v.verification_id::text
                     ORDER BY al.chain_seq DESC LIMIT 1) a ON true;
$function$;

CREATE FUNCTION trustride.fn_my_registration_retry_options()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_status TEXT;
  v_last RECORD;
  v_pending BOOLEAN;
  v_profile RECORD;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  SELECT status INTO v_status FROM trustride.platform_users WHERE user_id = v_uid;
  SELECT * INTO v_last FROM trustride.fn_registration_last_result(v_uid);
  SELECT legal_name, national_id_ref INTO v_profile FROM trustride.person_profile WHERE user_id = v_uid;
  v_pending := EXISTS (SELECT 1 FROM trustride.verification_record WHERE subject_user_id = v_uid AND outcome = 'PENDING');
  RETURN jsonb_build_object(
    'status', v_status,
    'retryable', v_status = 'VERIFICATION_FAILED' AND NOT v_pending,
    'same_details_allowed', v_status = 'VERIFICATION_FAILED' AND NOT v_pending AND v_last.returned_status = 'PROVIDER_UNAVAILABLE',
    'last_result', v_last.returned_status,
    'reasons', coalesce(v_last.reasons, '[]'::jsonb),
    'legal_name', v_profile.legal_name,
    'national_id_masked', CASE WHEN v_profile.national_id_ref IS NULL THEN NULL ELSE '****' || right(v_profile.national_id_ref, 4) END);
END;
$function$;

DROP FUNCTION trustride.fn_registration_retry_primary();
CREATE FUNCTION trustride.fn_registration_retry_primary(p_full_legal_name text DEFAULT NULL, p_national_id text DEFAULT NULL)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_status TEXT;
  v_cur RECORD;
  v_last RECORD;
  v_name TEXT;
  v_id TEXT;
  v_name_changed BOOLEAN;
  v_id_changed BOOLEAN;
  v_verification_id UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'fn_registration_retry_primary: no authenticated session'; END IF;
  -- Serialise retries of one identity: a second concurrent retry waits, then sees PENDING_VERIFICATION.
  SELECT status INTO v_status FROM trustride.platform_users WHERE user_id = v_uid FOR UPDATE;
  IF v_status IS DISTINCT FROM 'VERIFICATION_FAILED' THEN
    RAISE EXCEPTION 'Nothing to retry: registration can be retried only after a failed identity check (current status %)', coalesce(v_status, 'not registered');
  END IF;
  IF EXISTS (SELECT 1 FROM trustride.verification_record WHERE subject_user_id = v_uid AND outcome = 'PENDING') THEN
    RAISE EXCEPTION 'An identity check is already in progress';
  END IF;

  SELECT legal_name, national_id_ref INTO v_cur FROM trustride.person_profile WHERE user_id = v_uid;
  IF v_cur.legal_name IS NULL THEN RAISE EXCEPTION 'No primary registration on record to retry'; END IF;
  v_name := coalesce(nullif(regexp_replace(trim(coalesce(p_full_legal_name, '')), '\s+', ' ', 'g'), ''), v_cur.legal_name);
  v_id := coalesce(nullif(regexp_replace(coalesce(p_national_id, ''), '\s', '', 'g'), ''), regexp_replace(v_cur.national_id_ref, '\s', '', 'g'));
  v_name_changed := lower(v_name) <> lower(regexp_replace(trim(v_cur.legal_name), '\s+', ' ', 'g'));
  v_id_changed := v_id <> regexp_replace(v_cur.national_id_ref, '\s', '', 'g');

  SELECT * INTO v_last FROM trustride.fn_registration_last_result(v_uid);
  IF NOT (v_name_changed OR v_id_changed) AND v_last.returned_status IS DISTINCT FROM 'PROVIDER_UNAVAILABLE' THEN
    RAISE EXCEPTION 'The identity check gave a definitive answer for these details -- correct your legal name or ID number before trying again';
  END IF;
  IF trustride.fn_registration_national_id_holder(v_id, v_uid) IS NOT NULL THEN
    RAISE EXCEPTION 'This national ID is already registered to another identity -- one person, one TrustRide identity. Contact TrustRide support if this is your ID.';
  END IF;

  IF v_id_changed THEN
    UPDATE trustride.user_identifier SET status = 'SUPERSEDED'
    WHERE user_id = v_uid AND identifier_type = 'NATIONAL_ID' AND status = 'PENDING';
    INSERT INTO trustride.user_identifier (user_id, identifier_type, identifier_value, status)
    VALUES (v_uid, 'NATIONAL_ID', v_id, 'PENDING');
  END IF;
  IF v_name_changed OR v_id_changed THEN
    UPDATE trustride.person_profile SET legal_name = v_name, national_id_ref = v_id, updated_at = now() WHERE user_id = v_uid;
  END IF;
  IF v_name_changed THEN
    UPDATE trustride.platform_users SET display_name = v_name WHERE user_id = v_uid;
  END IF;

  INSERT INTO trustride.verification_record (subject_user_id, verification_type, outcome)
  VALUES (v_uid, 'NATIONAL_ID', 'PENDING') RETURNING verification_id INTO v_verification_id;
  UPDATE trustride.platform_users SET status = 'PENDING_VERIFICATION', updated_at = now() WHERE user_id = v_uid;

  INSERT INTO trustride.platform_event_outbox (correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (gen_random_uuid(), 'TRS026_ENG001_FDN', 'TRS026_ENG006_INTG', 'VERIFICATION_REQUESTED',
    jsonb_build_object('verification_id', v_verification_id, 'subject_user_id', v_uid,
      'verification_type', 'NATIONAL_ID', 'full_legal_name', v_name, 'national_id', v_id),
    'VERIFICATION_REQUESTED:' || v_verification_id::text);

  PERFORM trustride.fn_audit_log_append('platform_users', v_uid, 'REGISTRATION_PRIMARY_RETRY', v_uid, 'USER', NULL, NULL,
    jsonb_build_object('previous_result', v_last.returned_status, 'previous_verification_id', v_last.verification_id),
    jsonb_build_object('verification_id', v_verification_id, 'name_changed', v_name_changed, 'national_id_changed', v_id_changed,
      'national_id_masked', '****' || right(v_id, 4)));
  RETURN v_verification_id;
END;
$function$;

CREATE OR REPLACE FUNCTION trustride.fn_platform_authenticated_function_allowlist()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT ARRAY[
    -- Engine 11 gateway, Sovereign Gate and session (each checks the caller's own identity)
    'fn_present_command_execute', 'fn_present_projection', 'fn_present_shell_session_open', 'fn_present_shell_session_end',
    'fn_present_heartbeat_sync', 'fn_present_notifications_mark_read', 'fn_present_office_access_request',
    'fn_present_gate_context', 'fn_present_gate_context_v2', 'fn_present_system_access_record', 'fn_present_system_access_bind',
    -- Foundation self-service (own identity or a represented organisation)
    'fn_user_register', 'fn_registration_capture_primary', 'fn_registration_retry_primary', 'fn_registration_capture_entity',
    'fn_registration_declare_kra_pin', 'fn_registration_capture_object', 'fn_registration_capture_external_system',
    'fn_secondary_profile_submit', 'fn_my_registration_status', 'fn_my_registration_retry_options', 'fn_founder_exists', 'fn_founder_bootstrap',
    'fn_user_contact_add', 'fn_user_contact_add_for', 'fn_user_contact_remove', 'fn_user_contact_send_code',
    'fn_user_contact_set_primary', 'fn_user_contact_verify', 'fn_user_contact_preference_set', 'fn_user_contact_preference_set_for',
    'fn_entity_member_add', 'fn_business_actor_register', 'fn_resource_operator_duty_set',
    -- Role-checked Office actions
    'fn_role_assign', 'fn_business_actor_request_decide', 'fn_integration_adapter_set', 'fn_external_system_credential_issue',
    'fn_external_system_credential_revoke', 'fn_advisory_recommendation_decide',
    -- Policy helpers used by row-level security
    'fn_am_i_administrator', 'fn_am_i_governor', 'fn_am_i_role', 'fn_am_i_member_of_entity', 'fn_am_i_member_of_entity_user',
    'fn_am_i_representative_of', 'fn_contact_may_manage'
  ]::TEXT[];
$function$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_registration_retry_primary(text, text) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_my_registration_retry_options() TO trustride_authenticated;
SELECT trustride.fn_platform_conformance_assert();
