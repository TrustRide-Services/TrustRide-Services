-- ============================================================================
-- Platform: signed-in permission completion (Implementation Completion G1)
-- ============================================================================
-- Engine 11 Compatibility Check (2026-10-01), finding G1: 119 tables in
-- Engines 2-10 carry row policies for trustride_authenticated, but the
-- underlying SELECT grant was never issued, so every signed-in read of them
-- fails with "permission denied" (customer redirect loop, empty catalogue,
-- My Orders, request status and the Office review queue).
--
-- A blanket grant is NOT safe on its own: 98 of those tables have a policy
-- that is simply `true` -- "any signed-in user may read every row". That
-- would expose operator workforce units, custody logs, internal routing and
-- coordination state and AI advisory output to every customer. So this
-- migration does three things, in order:
--
--   1. Narrows every open policy that is not genuinely public reference data
--      to TrustRide Office authority (Founder / Administrator / Executive),
--      and adds the row-scoped self-reads that real actors need (an operator
--      reads their own working unit; a custodian reads the fleet in their
--      custody; a vendor reads their own listings).
--   2. Grants SELECT on every table that has a signed-in policy -- the
--      policies, never the grant, decide which rows each person sees.
--   3. Installs a standing conformance check (fn_platform_conformance_
--      violations / _assert) that every future migration ends by calling, so
--      a missing grant, an unscoped open policy, a PUBLIC function grant or
--      an anonymous table privilege can never ship silently again.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Public reference data: signed-in users may read all rows. These are the
--    published catalogue, coverage, eligibility and tariff registers -- what a
--    customer must see to choose and understand a service. Nothing personal.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_platform_open_read_allowlist()
RETURNS TEXT[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY[
    -- Engine 3 (Services): the published catalogue
    'service_catalogue', 'service_coverage_zone', 'service_eligibility_rule', 'service_line',
    'service_macro_domain', 'service_pillar', 'service_special_intent',
    -- Engine 5 (Cost): published tariffs and the operating-zone vocabulary
    'cost_operational_zones', 'cost_rate', 'cost_rate_version', 'cost_registry', 'cost_component',
    'cost_component_rule', 'cost_ea_rate', 'cost_ea_shift_multiplier', 'cost_model', 'cost_model_version',
    -- Engine 2 (Resources): the capacity-class vocabulary (not the units themselves)
    'resource_capacity_class'
  ]::TEXT[];
$$;

-- ---------------------------------------------------------------------------
-- 1a. Narrow every other open (`true`) signed-in policy to Office authority.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
  v_new TEXT;
BEGIN
  FOR r IN
    SELECT p.tablename, p.policyname
    FROM pg_policies p
    WHERE p.schemaname = 'trustride'
      AND 'trustride_authenticated' = ANY (p.roles)
      AND p.cmd = 'SELECT'
      AND p.qual = 'true'
      AND p.tablename <> ALL (trustride.fn_platform_open_read_allowlist())
  LOOP
    v_new := r.tablename || '_office_read';
    EXECUTE format('DROP POLICY %I ON trustride.%I', r.policyname, r.tablename);
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'trustride' AND tablename = r.tablename AND policyname = v_new) THEN
      EXECUTE format(
        'CREATE POLICY %I ON trustride.%I FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_role(ARRAY[''FOUNDER'', ''ADMINISTRATOR'', ''EXECUTIVE'']))',
        v_new, r.tablename);
    END IF;
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1b. Row-scoped self-reads real actors need.
-- ---------------------------------------------------------------------------
-- An operator reads their own working unit(s), its capabilities and its
-- current availability -- nobody else's.
CREATE POLICY resource_workforce_unit_operator_self_read ON trustride.resource_workforce_unit
  FOR SELECT TO trustride_authenticated USING (operator_user_id = auth.uid());

CREATE POLICY resource_workforce_capability_operator_self_read ON trustride.resource_workforce_capability
  FOR SELECT TO trustride_authenticated USING (EXISTS (
    SELECT 1 FROM trustride.resource_workforce_unit wu
    WHERE wu.workforce_unit_id = resource_workforce_capability.workforce_unit_id AND wu.operator_user_id = auth.uid()));

CREATE POLICY resource_availability_ledger_operator_self_read ON trustride.resource_availability_ledger
  FOR SELECT TO trustride_authenticated USING (resource_type = 'WORKFORCE_UNIT' AND EXISTS (
    SELECT 1 FROM trustride.resource_workforce_unit wu
    WHERE wu.workforce_unit_id = resource_availability_ledger.resource_ref_id AND wu.operator_user_id = auth.uid()));

-- A custodian (an operator driving it, or a partner who contributed it)
-- reads the fleet resource in their custody.
CREATE POLICY resource_fleet_register_custodian_read ON trustride.resource_fleet_register
  FOR SELECT TO trustride_authenticated USING (custodian_user_id = auth.uid() OR EXISTS (
    SELECT 1 FROM trustride.resource_workforce_unit wu
    WHERE wu.fleet_resource_id = resource_fleet_register.fleet_resource_id AND wu.operator_user_id = auth.uid()));

-- Marketplace listings: buyers see what is LISTED; a vendor sees all of
-- their own (draft, reserved, sold); Office sees everything (policy above).
CREATE POLICY service_marketplace_listing_public_listed_read ON trustride.service_marketplace_listing
  FOR SELECT TO trustride_authenticated USING (listing_status = 'LISTED');
CREATE POLICY service_marketplace_listing_vendor_self_read ON trustride.service_marketplace_listing
  FOR SELECT TO trustride_authenticated USING (vendor_user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 2. Grant SELECT wherever a signed-in policy exists.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  t TEXT;
BEGIN
  FOR t IN
    SELECT DISTINCT p.tablename
    FROM pg_policies p
    WHERE p.schemaname = 'trustride'
      AND 'trustride_authenticated' = ANY (p.roles)
      AND p.cmd IN ('SELECT', 'ALL')
  LOOP
    EXECUTE format('GRANT SELECT ON trustride.%I TO trustride_authenticated', t);
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Standing conformance check.
-- ---------------------------------------------------------------------------
-- Anonymous callers may execute exactly these (the Sovereign Gate's first
-- step happens before any identity exists).
CREATE OR REPLACE FUNCTION trustride.fn_platform_anon_function_allowlist()
RETURNS TEXT[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY['fn_present_system_access_record']::TEXT[];
$$;

CREATE OR REPLACE FUNCTION trustride.fn_platform_conformance_violations()
RETURNS TABLE (check_code TEXT, object_name TEXT, detail TEXT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, pg_catalog AS $$
  -- Every table carries RLS.
  SELECT 'RLS_DISABLED', c.relname::text, 'row level security is off'
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'trustride' AND c.relkind = 'r' AND NOT c.relrowsecurity
  UNION ALL
  -- A signed-in read policy is useless without the grant (G1).
  SELECT 'POLICY_WITHOUT_GRANT', c.relname::text, 'signed-in read policy exists but SELECT is not granted'
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'trustride' AND c.relkind = 'r'
    AND EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'trustride' AND p.tablename = c.relname
                AND 'trustride_authenticated' = ANY (p.roles) AND p.cmd IN ('SELECT', 'ALL'))
    AND NOT has_table_privilege('trustride_authenticated', c.oid, 'SELECT')
  UNION ALL
  -- An open signed-in policy is only lawful on published reference data.
  SELECT 'OPEN_POLICY_NOT_ALLOWLISTED', p.tablename::text, p.policyname::text
  FROM pg_policies p
  WHERE p.schemaname = 'trustride' AND 'trustride_authenticated' = ANY (p.roles)
    AND p.cmd IN ('SELECT', 'ALL') AND p.qual = 'true'
    AND p.tablename <> ALL (trustride.fn_platform_open_read_allowlist())
  UNION ALL
  -- Signed-in users never write tables directly: every write is a function.
  SELECT 'AUTHENTICATED_TABLE_WRITE', c.relname::text, 'trustride_authenticated holds a write privilege'
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'trustride' AND c.relkind = 'r'
    AND (has_table_privilege('trustride_authenticated', c.oid, 'INSERT')
      OR has_table_privilege('trustride_authenticated', c.oid, 'UPDATE')
      OR has_table_privilege('trustride_authenticated', c.oid, 'DELETE'))
  UNION ALL
  -- Anonymous callers hold no table privilege at all.
  SELECT 'ANON_TABLE_ACCESS', c.relname::text, 'anon holds a table privilege'
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'trustride' AND c.relkind IN ('r', 'v', 'm')
    AND (has_table_privilege('anon', c.oid, 'SELECT') OR has_table_privilege('anon', c.oid, 'INSERT')
      OR has_table_privilege('anon', c.oid, 'UPDATE') OR has_table_privilege('anon', c.oid, 'DELETE'))
  UNION ALL
  -- CREATE FUNCTION grants PUBLIC execute by default; every function must
  -- have it revoked (anon holds USAGE on the schema since Engine 11 v3.0.0).
  SELECT 'PUBLIC_FUNCTION_EXECUTE', p.proname::text, pg_get_function_identity_arguments(p.oid)
  FROM pg_proc p
  WHERE p.pronamespace = 'trustride'::regnamespace
    AND EXISTS (SELECT 1 FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
  UNION ALL
  SELECT 'ANON_FUNCTION_NOT_ALLOWLISTED', p.proname::text, pg_get_function_identity_arguments(p.oid)
  FROM pg_proc p
  WHERE p.pronamespace = 'trustride'::regnamespace
    AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND p.proname <> ALL (trustride.fn_platform_anon_function_allowlist());
$$;

CREATE OR REPLACE FUNCTION trustride.fn_platform_conformance_assert()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_catalog AS $$
DECLARE
  v_report TEXT;
BEGIN
  SELECT string_agg(check_code || ':' || object_name || coalesce(' (' || detail || ')', ''), E'\n' ORDER BY check_code, object_name)
  INTO v_report FROM trustride.fn_platform_conformance_violations();
  IF v_report IS NOT NULL THEN
    RAISE EXCEPTION 'Platform conformance failed:%', E'\n' || v_report;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION trustride.fn_platform_open_read_allowlist() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_platform_anon_function_allowlist() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_platform_conformance_violations() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_platform_conformance_assert() FROM PUBLIC;

-- Every migration from here on ends with this line.
SELECT trustride.fn_platform_conformance_assert();
