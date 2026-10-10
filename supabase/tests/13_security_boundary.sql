-- Suite 13 -- the authorization boundary at every directly callable function
-- (TRS026-ENG-REMEDIATION-001: D01, D03, D04, D05, D16, D26). A signed-in
-- user acts only through the Engine 11 gateway, only in a session they own,
-- and never while suspended; nothing a signed-in user can call accepts
-- another identity's session, user id or Executive data.
DO $$
DECLARE
  a UUID; b UUID; exe UUID; sa UUID; sb UUID; r JSONB; x UUID; n INT; v TEXT; ok BOOLEAN;
BEGIN
  a := pg_temp.t_customer('Boundary Cust A');
  b := pg_temp.t_customer('Boundary Cust B');
  exe := pg_temp.t_person('Boundary Exec', NULL);  PERFORM pg_temp.t_role(exe, 'EXECUTIVE');
  PERFORM pg_temp.t_as(a);  sa := trustride.fn_present_shell_session_open('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', a, 'WEB');
  PERFORM pg_temp.t_as(b);  sb := trustride.fn_present_shell_session_open('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', b, 'WEB');
  PERFORM pg_temp.t_admin();

  -- ============ D01: commands only through the gateway, only in one's own session, never while suspended
  PERFORM pg_temp.t_check('D01 signed-in users cannot call fn_present_capture_command directly',
    NOT has_function_privilege('authenticated', 'trustride.fn_present_capture_command(uuid,text,jsonb)', 'EXECUTE'));
  PERFORM pg_temp.t_check('D01 the gateway fn_present_command_execute stays callable',
    has_function_privilege('authenticated', 'trustride.fn_present_command_execute(uuid,text,jsonb)', 'EXECUTE'));
  -- Defence in depth: even with execute rights, capture refuses a session the caller does not own.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  BEGIN
    x := trustride.fn_present_capture_command(sb, 'OPEN_SUPPORT_CASE', '{"category":"ORDER_ISSUE","subject":"x","body":"y"}');
    PERFORM pg_temp.t_check('D01 capture refuses a session owned by another identity', false, 'captured ' || x);
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.t_check('D01 capture refuses a session owned by another identity', SQLERRM LIKE 'SESSION_INVALID%', SQLERRM); END;
  PERFORM pg_temp.t_admin();
  SELECT count(*) INTO n FROM trustride.business_support_case WHERE opened_by_user_id = b;
  PERFORM pg_temp.t_check('D01 no support case was created under B', n = 0, n::text);
  PERFORM pg_temp.t_as(a);
  BEGIN PERFORM trustride.fn_present_command_execute(sb, 'OPEN_SUPPORT_CASE', '{}');
    PERFORM pg_temp.t_check('D01 the gateway refuses a session owned by another identity', false, 'accepted');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.t_check('D01 the gateway refuses a session owned by another identity', SQLERRM LIKE 'SESSION_INVALID%', SQLERRM); END;
  PERFORM pg_temp.t_admin();
  UPDATE trustride.platform_users SET status = 'SUSPENDED' WHERE user_id = a;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  BEGIN x := trustride.fn_present_capture_command(sa, 'OPEN_SUPPORT_CASE', '{"category":"ORDER_ISSUE","subject":"x","body":"y"}');
    PERFORM pg_temp.t_check('D01 capture refuses a suspended identity in its own session', false, 'captured ' || x);
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.t_check('D01 capture refuses a suspended identity in its own session', SQLERRM ILIKE '%suspended%', SQLERRM); END;
  PERFORM pg_temp.t_admin();
  UPDATE trustride.platform_users SET status = 'ACTIVE' WHERE user_id = a;
  r := pg_temp.t_cmd(a, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'OPEN_SUPPORT_CASE', '{"category":"ORDER_ISSUE","subject":"Own case","body":"positive control"}');
  PERFORM pg_temp.t_check('D01 positive control: A acts in its own session through the gateway', r->>'status' = 'TRANSLATED', r::text);

  -- ============ D03: the legacy projection renderer and its dead projection are retired
  PERFORM pg_temp.t_check('D03 fn_present_render_projection no longer exists', to_regprocedure('trustride.fn_present_render_projection(uuid,text)') IS NULL);
  PERFORM pg_temp.t_check('D03 every registered projection has its handler', NOT EXISTS (SELECT 1 FROM trustride.projection_registry
    WHERE to_regprocedure('trustride.fn_present_proj_' || lower(projection_code) || '(uuid,jsonb)') IS NULL));

  -- ============ D04: ending and heart-beating a session belongs to its owner
  PERFORM pg_temp.t_as(a);
  BEGIN PERFORM trustride.fn_present_shell_session_end(sb); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM trustride.fn_present_heartbeat_sync(sb); ok := false; EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'SESSION_INVALID%'; END;
  PERFORM pg_temp.t_admin();
  SELECT session_status::text INTO v FROM trustride.present_shell_session WHERE session_id = sb;
  PERFORM pg_temp.t_check('D04 A cannot end B''s session', v = 'ACTIVE', v);
  PERFORM pg_temp.t_check('D04 A cannot heartbeat B''s session', ok);
  SELECT count(*) INTO n FROM trustride.present_heartbeat_status WHERE shell_session_id = sb;
  PERFORM pg_temp.t_check('D04 no heartbeat row was written for B''s session', n = 0, n::text);
  PERFORM pg_temp.t_as(a);
  PERFORM trustride.fn_present_heartbeat_sync(sa);
  PERFORM trustride.fn_present_shell_session_end(sa);
  PERFORM pg_temp.t_admin();
  SELECT session_status::text INTO v FROM trustride.present_shell_session WHERE session_id = sa;
  PERFORM pg_temp.t_check('D04 positive control: A heartbeats and ends its own session', v = 'ENDED', v);

  -- ============ D05 / D26: no signed-in access to another identity's environments or to Executive scenario data
  PERFORM pg_temp.t_check('D05 signed-in users cannot call fn_present_sub_shell_for_user',
    NOT has_function_privilege('authenticated', 'trustride.fn_present_sub_shell_for_user(uuid)', 'EXECUTE'));
  PERFORM pg_temp.t_check('D26 signed-in users cannot call fn_model_run_compare',
    NOT has_function_privilege('authenticated', 'trustride.fn_model_run_compare(uuid,uuid,text)', 'EXECUTE'));
  PERFORM set_config('request.jwt.claims', json_build_object('sub', a, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', a::text, true);
  BEGIN PERFORM trustride.fn_model_run_compare(gen_random_uuid(), gen_random_uuid(), 'X');
    PERFORM pg_temp.t_check('D26 a customer context cannot compare scenario runs even with execute rights', false, 'accepted');
  EXCEPTION WHEN OTHERS THEN PERFORM pg_temp.t_check('D26 a customer context cannot compare scenario runs even with execute rights', SQLERRM ILIKE '%Executive%', SQLERRM); END;
  PERFORM pg_temp.t_admin();

  -- ============ D16: no permitted verb without a live handler
  SELECT count(*) INTO n FROM trustride.present_shell_capability_registry r WHERE r.permitted
    AND r.command_type NOT IN ('RAISE_INTENT', 'TRACK_ELEMENT', 'SUBMIT_PARTNERSHIP_REQUEST', 'SUBMIT_REGULATORY_REQUEST', 'SUBMIT_FACILITATION_REQUEST',
                               'SUBMIT_VENDOR_LISTING', 'RESERVE_VEHICLE', 'REVIEW_ACTOR_REQUEST', 'EMIT_PROGRESS_SIGNAL', 'RUN_SCENARIO')
    AND to_regprocedure('trustride.fn_present_cmd_' || lower(r.command_type) || '(uuid,jsonb,uuid)') IS NULL;
  PERFORM pg_temp.t_check('D16 every permitted verb has a live handler', n = 0, n::text);

  -- ============ systemic guard
  SELECT count(*) INTO n FROM trustride.fn_platform_conformance_violations() WHERE check_code = 'AUTHENTICATED_FUNCTION_NOT_ALLOWLISTED';
  PERFORM pg_temp.t_check('systemic: every function a signed-in user can execute is on the reviewed allowlist (conformance)',
    to_regprocedure('trustride.fn_platform_authenticated_function_allowlist()') IS NOT NULL AND n = 0, n::text);
END
$$;
