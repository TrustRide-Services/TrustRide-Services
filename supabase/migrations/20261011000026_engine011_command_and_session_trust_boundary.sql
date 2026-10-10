-- ============================================================================
-- Engine 11 (Presentation) -- command and session trust boundary
-- TRS026-ENG-REMEDIATION-001, findings D01, D03, D04, D05, D16, D26
-- ============================================================================
-- Forensic audit 2026-10-08 proved that a signed-in user could:
--   D01  execute any command inside another identity's shell session by
--        calling fn_present_capture_command directly (a support case was
--        opened as another customer), and act while suspended;
--   D03  render a projection through the legacy fn_present_render_projection
--        without an ownership check (USER_ORDER_STATUS_CARD had no handler);
--   D04  end or heart-beat another identity's session;
--   D05  read which environment any identity holds;
--   D26  (found during remediation) compare and write Executive scenario
--        results through fn_model_run_compare with no role check.
-- D16: eight verbs were permitted on surfaces with no handler, so a call
-- ended CAPTURED with no outcome.
--
-- Root cause (one class): SECURITY DEFINER functions granted to signed-in
-- users that trusted a caller-supplied session or user id. The gateway
-- (fn_present_command_execute, fn_present_projection) checks ownership;
-- functions reachable around it did not.
--
-- Correction: the gateway stays the only signed-in entry for commands;
-- every function that takes a session checks the caller owns it (or acts
-- for it) and is not suspended; functions with no signed-in purpose lose
-- signed-in execute; and a reviewed allowlist, checked by the platform
-- conformance assertion in every future migration, stops the class from
-- returning.
-- ============================================================================

-- D01 -- capture: owner and suspension checks inside, direct execute revoked.
DO $patch$
DECLARE
  v_def TEXT;
  v_old TEXT := E'  IF v_session IS NULL THEN\n    RAISE EXCEPTION ''fn_present_capture_command: no ACTIVE session %'', p_shell_session_id;\n  END IF;\n';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_present_capture_command(uuid,text,jsonb)'::regprocedure) INTO v_def;
  IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'capture session check not found'; END IF;
  v_def := replace(v_def, v_old, v_old
    || E'  -- The caller must own the session or act for it, and be in good standing.\n'
    || E'  IF auth.uid() IS NULL OR (auth.uid() IS DISTINCT FROM v_session.user_id AND auth.uid() IS DISTINCT FROM v_session.acting_person_user_id) THEN\n'
    || E'    RAISE EXCEPTION ''SESSION_INVALID: open your shell again'';\n'
    || E'  END IF;\n'
    || E'  IF EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id IN (v_session.user_id, auth.uid()) AND status = ''SUSPENDED'') THEN\n'
    || E'    RAISE EXCEPTION ''This identity is suspended -- contact TrustRide Office'';\n'
    || E'  END IF;\n');
  EXECUTE v_def;
END;
$patch$;
REVOKE EXECUTE ON FUNCTION trustride.fn_present_capture_command(uuid, text, jsonb) FROM PUBLIC, anon, authenticated, trustride_authenticated;

-- D03 -- the legacy renderer and its handler-less projection are retired
-- (no frontend caller, no render or cache rows, no foreign key).
DROP FUNCTION trustride.fn_present_render_projection(uuid, text);
DELETE FROM trustride.projection_registry WHERE projection_code = 'USER_ORDER_STATUS_CARD'
  AND NOT EXISTS (SELECT 1 FROM trustride.present_projection_render WHERE projection_code = 'USER_ORDER_STATUS_CARD');

-- D04 -- a session is ended or heart-beaten only by its owner.
CREATE OR REPLACE FUNCTION trustride.fn_present_shell_session_end(p_session_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
BEGIN
  UPDATE trustride.present_shell_session SET session_status = 'ENDED', ended_at = now()
  WHERE session_id = p_session_id AND session_status = 'ACTIVE'
    AND (auth.uid() IS NULL OR auth.uid() = user_id OR auth.uid() = acting_person_user_id);
  IF NOT FOUND AND auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'SESSION_INVALID: open your shell again';
  END IF;
END;
$function$;

DO $patch$
DECLARE
  v_def TEXT;
  v_old TEXT := E'BEGIN\n  SELECT * INTO v_snapshot FROM trustride.orch_capacity_snapshot';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_present_heartbeat_sync(uuid)'::regprocedure) INTO v_def;
  IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'heartbeat body not found'; END IF;
  v_def := replace(v_def, v_old, E'BEGIN\n'
    || E'  IF NOT EXISTS (SELECT 1 FROM trustride.present_shell_session WHERE session_id = p_shell_session_id AND session_status = ''ACTIVE''\n'
    || E'                 AND (auth.uid() = user_id OR auth.uid() = acting_person_user_id)) THEN\n'
    || E'    RAISE EXCEPTION ''SESSION_INVALID: open your shell again'';\n'
    || E'  END IF;\n'
    || E'  SELECT * INTO v_snapshot FROM trustride.orch_capacity_snapshot');
  EXECUTE v_def;
END;
$patch$;

-- D05 -- environment lookup is internal to Engine 11 (fn_present_inbox_process).
REVOKE EXECUTE ON FUNCTION trustride.fn_present_sub_shell_for_user(uuid) FROM PUBLIC, anon, authenticated, trustride_authenticated;

-- D26 -- scenario comparison is Executive work.
DO $patch$
DECLARE
  v_def TEXT;
  v_old TEXT := E'BEGIN\n  SELECT projected_value INTO v_base_value';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_model_run_compare(uuid,uuid,text)'::regprocedure) INTO v_def;
  IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'model compare body not found'; END IF;
  v_def := replace(v_def, v_old, E'BEGIN\n'
    || E'  IF auth.uid() IS NOT NULL AND NOT trustride.fn_am_i_role(ARRAY[''FOUNDER'', ''EXECUTIVE'']) THEN\n'
    || E'    RAISE EXCEPTION ''Scenario comparison is for the Founder and Executives'';\n'
    || E'  END IF;\n'
    || E'  SELECT projected_value INTO v_base_value');
  EXECUTE v_def;
END;
$patch$;
REVOKE EXECUTE ON FUNCTION trustride.fn_model_run_compare(uuid, uuid, text) FROM PUBLIC, anon, authenticated, trustride_authenticated;

-- D16 -- a verb is permitted only where it has a live handler. These eight
-- were registered by the original Engine 11 specification and never built;
-- they stay in the registry (history) but are no longer offered.
UPDATE trustride.present_shell_capability_registry SET permitted = FALSE
WHERE permitted AND command_type IN ('CAPTURE_EVIDENCE', 'EMIT_GOVERNANCE_SIGNAL', 'RULE_ON_EXCEPTION', 'SETTLE_LAWFUL_FLOW',
                                     'VIEW_ASSIGNMENT_PROJECTION', 'VIEW_PROJECTION', 'VIEW_REGISTER', 'VIEW_WHOLE_ESTATE');

-- Systemic guard -- the reviewed set of functions a signed-in user may call.
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
    'fn_secondary_profile_submit', 'fn_my_registration_status', 'fn_founder_exists', 'fn_founder_bootstrap',
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

DO $patch$
DECLARE
  v_def TEXT;
  v_old TEXT := E'    AND p.proname <> ALL (trustride.fn_platform_anon_function_allowlist());\n$function$';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_platform_conformance_violations()'::regprocedure) INTO v_def;
  IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'conformance tail not found'; END IF;
  v_def := replace(v_def, v_old, E'    AND p.proname <> ALL (trustride.fn_platform_anon_function_allowlist())\n'
    || E'  UNION ALL\n'
    || E'  -- Signed-in users execute only the reviewed functions (each checks the caller''s own identity or role).\n'
    || E'  SELECT ''AUTHENTICATED_FUNCTION_NOT_ALLOWLISTED'', p.proname::text, pg_get_function_identity_arguments(p.oid)\n'
    || E'  FROM pg_proc p\n'
    || E'  WHERE p.pronamespace = ''trustride''::regnamespace\n'
    || E'    AND has_function_privilege(''trustride_authenticated'', p.oid, ''EXECUTE'')\n'
    || E'    AND p.proname <> ALL (trustride.fn_platform_authenticated_function_allowlist());\n$function$');
  EXECUTE v_def;
END;
$patch$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
