-- ============================================================================
-- TrustRide test helpers (prepended to every suite by supabase/tests/run.sh).
-- Every suite is ROLLBACK-ONLY: it ends by raising an exception that carries
-- its results, so nothing it creates ever persists -- safe against staging.
-- ============================================================================
CREATE TEMP TABLE IF NOT EXISTS t_result (seq SERIAL, suite TEXT, name TEXT, ok BOOLEAN, detail TEXT);
GRANT ALL ON t_result TO PUBLIC;
GRANT ALL ON SEQUENCE t_result_seq_seq TO PUBLIC;

-- Record one assertion.
CREATE OR REPLACE FUNCTION pg_temp.t_check(p_name TEXT, p_ok BOOLEAN, p_detail TEXT DEFAULT NULL) RETURNS VOID
LANGUAGE sql AS $$
  INSERT INTO t_result (suite, name, ok, detail) VALUES (current_setting('trs.suite', true), p_name, coalesce(p_ok, false), p_detail);
$$;

-- Become a signed-in user (or anon when p_user is NULL) for the rest of the
-- transaction, exactly as the Data API would: role + JWT claims.
CREATE OR REPLACE FUNCTION pg_temp.t_as(p_user UUID) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF p_user IS NULL THEN
    PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
    PERFORM set_config('request.jwt.claim.sub', '', true);
    EXECUTE 'SET LOCAL ROLE anon';
  ELSE
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', p_user::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
  END IF;
END;
$$;

-- Back to the migration owner (fixtures, engine-side steps).
CREATE OR REPLACE FUNCTION pg_temp.t_admin() RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
END;
$$;

-- A verified person with one environment registration.
CREATE OR REPLACE FUNCTION pg_temp.t_person(p_label TEXT, p_domain TEXT DEFAULT NULL, p_status TEXT DEFAULT 'ACTIVE') RETURNS UUID
LANGUAGE plpgsql AS $$
DECLARE v UUID := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, email, aud, role) VALUES (v, lower(p_label) || '-' || substr(v::text, 1, 8) || '@test.trustride.ke', 'authenticated', 'authenticated')
  ON CONFLICT DO NOTHING;
  INSERT INTO trustride.platform_users (user_id, global_uid, identity_primitive, display_name, status)
  VALUES (v, 'T-' || substr(v::text, 1, 12), 'PERSON', p_label, 'ACTIVE');
  IF p_domain IS NOT NULL THEN
    INSERT INTO trustride.business_actor_registration (user_id, user_type_domain, registration_status)
    VALUES (v, p_domain::trustride.business_user_type_domain_enum, p_status);
  END IF;
  RETURN v;
END;
$$;

-- Give a person an Office role (bypasses the Governor gate: fixture only).
CREATE OR REPLACE FUNCTION pg_temp.t_role(p_user UUID, p_role TEXT) RETURNS VOID LANGUAGE sql AS $$
  INSERT INTO trustride.role_assignment (user_id, role_id, assigned_by, status)
  SELECT p_user, role_id, p_user, 'ACTIVE' FROM trustride.role_definition WHERE role_code = p_role;
$$;

-- Run the dispatch cycle n times (what pg_cron does every 10 seconds).
CREATE OR REPLACE FUNCTION pg_temp.t_cycle(p_n INT DEFAULT 12) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  FOR i IN 1..p_n LOOP PERFORM trustride.fn_orch_dispatch_cycle(); END LOOP;
END;
$$;

-- Count of rows visible to the current role, or -1 when access is refused.
CREATE OR REPLACE FUNCTION pg_temp.t_visible(p_table TEXT, p_where TEXT DEFAULT 'true') RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE n BIGINT;
BEGIN
  EXECUTE format('SELECT count(*) FROM trustride.%I WHERE %s', p_table, p_where) INTO n;
  RETURN n;
EXCEPTION WHEN insufficient_privilege THEN
  RETURN -1;
END;
$$;

-- Does a statement fail? (for negative-path checks)
CREATE OR REPLACE FUNCTION pg_temp.t_fails(p_sql TEXT) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN FALSE;
EXCEPTION WHEN OTHERS THEN
  RETURN TRUE;
END;
$$;

-- Act as a user: open their shell session and capture one Engine 11 command.
-- Returns {status, reason, signal}; leaves the transaction as the admin.
CREATE OR REPLACE FUNCTION pg_temp.t_cmd(p_user UUID, p_top TEXT, p_sub TEXT, p_cmd TEXT, p_payload JSONB) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE s UUID; c UUID; r JSONB;
BEGIN
  PERFORM pg_temp.t_as(p_user);
  BEGIN
    s := trustride.fn_present_shell_session_open(p_top::trustride.present_top_shell_enum, p_sub::trustride.present_sub_shell_enum, p_user, 'WEB');
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.t_admin();
    RETURN jsonb_build_object('status', 'SESSION_REFUSED', 'reason', SQLERRM);
  END;
  BEGIN
    c := trustride.fn_present_capture_command(s, p_cmd, p_payload);
  EXCEPTION WHEN OTHERS THEN
    PERFORM pg_temp.t_admin();
    RETURN jsonb_build_object('status', 'CAPTURE_REFUSED', 'reason', SQLERRM);
  END;
  SELECT jsonb_build_object('status', translation_status, 'reason', rejection_reason, 'signal', translated_signal_id, 'command_id', command_id)
  INTO r FROM trustride.present_command_capture WHERE command_id = c;
  PERFORM pg_temp.t_admin();
  RETURN r;
END;
$$;

-- Fixture: an approved operator formed into an on-duty working unit through
-- the real Office commands (vehicle verified directly -- NTSA is suite 03).
CREATE OR REPLACE FUNCTION pg_temp.t_ready_unit(p_founder UUID, p_class TEXT, p_estate UUID, p_label TEXT, p_caps TEXT[] DEFAULT ARRAY[]::TEXT[])
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE op UUID; obj UUID; fleet UUID; r JSONB; unit UUID; c TEXT;
BEGIN
  op := pg_temp.t_person(p_label, 'OPERATOR');
  IF p_class <> 'EXECUTIVE_ASSISTANT_HUMAN' THEN
    PERFORM pg_temp.t_as(p_founder);
    obj := trustride.fn_registration_capture_object(
      CASE p_class WHEN 'BODA_BODA' THEN 'MOTORCYCLE' WHEN 'TUKTUK' THEN 'TUKTUK' WHEN 'SEDAN' THEN 'CAR' WHEN 'PICKUP_TOWN' THEN 'PICKUP'
        WHEN 'VAN_CARGO' THEN 'VAN' ELSE 'TRUCK' END, 'Test', p_class, 2024::smallint, 'T' || substr(md5(random()::text), 1, 6), NULL, p_founder);
    PERFORM pg_temp.t_admin();
    fleet := trustride.fn_resource_fleet_register(obj, p_class::trustride.resource_capacity_class_enum, 'OWNED', 'TEST', p_estate, p_founder);
    UPDATE trustride.resource_fleet_register SET lifecycle_state = 'VERIFIED', inspection_status = 'PASSED', insurance_status = 'ACTIVE' WHERE fleet_resource_id = fleet;
    PERFORM trustride.fn_resource_availability_move('FLEET', fleet, 'AVAILABLE', 'TEST_VERIFIED', p_founder);
  END IF;
  r := pg_temp.t_cmd(p_founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ONBOARD_OPERATOR',
    jsonb_strip_nulls(jsonb_build_object('operator_user_id', op, 'capacity_class', p_class, 'estate_id', p_estate, 'fleet_resource_id', fleet)));
  unit := (r->>'signal')::uuid;
  IF unit IS NULL THEN RAISE EXCEPTION 't_ready_unit: onboarding failed: %', r; END IF;
  FOREACH c IN ARRAY p_caps LOOP
    PERFORM pg_temp.t_cmd(p_founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RECORD_CAPABILITY',
      jsonb_build_object('workforce_unit_id', unit, 'capability_type', c, 'credential_ref', 'TEST-' || c, 'expires_at', now() + interval '1 year'));
  END LOOP;
  PERFORM pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'SET_DUTY', '{"on_duty":true}');
  RETURN unit;
END;
$$;

-- Fixture: a customer with a verified M-Pesa phone.
CREATE OR REPLACE FUNCTION pg_temp.t_customer(p_label TEXT) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE c UUID;
BEGIN
  c := pg_temp.t_person(p_label, 'CUSTOMER');
  INSERT INTO trustride.user_contact (user_id, contact_type, contact_value, is_primary, is_verified, verified_at, status)
  VALUES (c, 'PHONE', '+2547' || lpad((floor(random() * 100000000))::bigint::text, 8, '0'), TRUE, TRUE, now(), 'ACTIVE');
  RETURN c;
END;
$$;

-- Fixture: open every working window for the rest of the transaction, so
-- order suites behave the same whatever day and hour they run.
CREATE OR REPLACE FUNCTION pg_temp.t_open_all_hours() RETURNS VOID LANGUAGE sql AS $$
  UPDATE trustride.platform_configuration SET config_value = '00:00-23:59'
  WHERE config_key IN ('WORKING_WINDOW_WEEKDAY', 'WORKING_WINDOW_SATURDAY', 'WORKING_WINDOW_SUNDAY');
  DELETE FROM trustride.calendar_reference WHERE calendar_date = (now() AT TIME ZONE 'Africa/Nairobi')::date AND day_type = 'PUBLIC_HOLIDAY';
$$;

-- The order behind an Engine 11 command.
CREATE OR REPLACE FUNCTION pg_temp.t_order(p_command JSONB) RETURNS trustride.business_order LANGUAGE sql AS $$
  SELECT * FROM trustride.business_order WHERE correlation_id = (p_command->>'command_id')::uuid ORDER BY created_at DESC LIMIT 1;
$$;

-- Fixture: drive a one-stop boda order to COMPLETED through the real verbs.
-- Returns the order id. A boda unit must be on duty.
CREATE OR REPLACE FUNCTION pg_temp.t_order_to_completed(p_cust UUID) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE r JSONB; o trustride.business_order; op UUID; j UUID; i INT;
BEGIN
  r := pg_temp.t_cmd(p_cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02"}}]'::jsonb));
  o := pg_temp.t_order(r);
  PERFORM pg_temp.t_cycle(12);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = o.order_id;
  PERFORM pg_temp.t_cmd(p_cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'ACCEPT_QUOTATION', jsonb_build_object('quote_id', o.quote_id));
  PERFORM pg_temp.t_cycle(4);
  SELECT operator_user_id INTO op FROM trustride.resource_workforce_unit WHERE workforce_unit_id = o.reserved_workforce_unit_id;
  SELECT job_id INTO j FROM trustride.business_job WHERE order_id = o.order_id;
  FOR i IN 1..6 LOOP  -- ACKNOWLEDGED .. COMPLETED
    PERFORM pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', jsonb_build_object('job_id', j));
  END LOOP;
  PERFORM pg_temp.t_cycle(8);
  RETURN o.order_id;
END;
$$;

-- Act as a user: open their shell session and render one lawful projection.
-- Returns the projection, or {"error": ...}; leaves the transaction as admin.
CREATE OR REPLACE FUNCTION pg_temp.t_proj(p_user UUID, p_top TEXT, p_sub TEXT, p_code TEXT, p_params JSONB DEFAULT '{}'::jsonb) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE s UUID; r JSONB;
BEGIN
  PERFORM pg_temp.t_as(p_user);
  BEGIN
    s := trustride.fn_present_shell_session_open(p_top::trustride.present_top_shell_enum, p_sub::trustride.present_sub_shell_enum, p_user, 'WEB');
    r := trustride.fn_present_projection(s, p_code, p_params);
  EXCEPTION WHEN OTHERS THEN
    r := jsonb_build_object('error', SQLERRM);
  END;
  PERFORM pg_temp.t_admin();
  RETURN r;
END;
$$;

-- Fixture: release every completed job's worker immediately (what the
-- auto-verify sweep does after JOB_AUTO_VERIFY_MIN).
CREATE OR REPLACE FUNCTION pg_temp.t_release_completed() RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  UPDATE trustride.business_job SET completed_at = now() - interval '1 hour' WHERE status = 'COMPLETED';
  PERFORM trustride.fn_business_dispatch_sweep();
  PERFORM pg_temp.t_cycle(4);
END;
$$;
