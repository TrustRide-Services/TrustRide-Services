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
