-- ============================================================================
-- Platform -- staging reconciled with the migrations
-- TRS026-ENG-REMEDIATION-001, finding D19
-- ============================================================================
-- A full catalogue comparison (functions, columns, constraints, indexes,
-- triggers, policies, grants, function ACLs, enums, RLS, cron, extensions)
-- of staging against a clean rebuild from these migrations, 2026-10-11,
-- found four objects on staging that no migration creates:
--   1-2  trs026_eng004_bus_service: INSERT, SELECT, UPDATE, DELETE on
--        resource_ledger_event and SELECT on v_resource_eagle_eye;
--   3-4  function trustride.cost_quotes_block_illegal_mutation() and its ACL
--        (a trigger function attached to no trigger and called by nothing).
-- All other differences were presentation only (policy text printed under a
-- different search_path; equal ACLs listed in a different order).
--
-- Correction:
--   * the Engine 4 grants are revoked (no-op on a clean rebuild);
--   * the audit chains are append-only (migration 029), so no role but the
--     owner keeps UPDATE, DELETE or TRUNCATE on them;
--   * the orphan function carries an Engine 5 name. By Founder ruling Engine 5
--     is not touched; it is inert and is left in place, recorded here and in
--     the remediation report for the Founder's decision.
-- ============================================================================

REVOKE ALL ON trustride.resource_ledger_event FROM trs026_eng004_bus_service;
REVOKE ALL ON trustride.v_resource_eagle_eye FROM trs026_eng004_bus_service;

DO $chains$
DECLARE
  g RECORD;
BEGIN
  FOR g IN SELECT DISTINCT c.relname, pg_get_userbyid(x.grantee) AS role_name
           FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) x
           WHERE c.relnamespace = 'trustride'::regnamespace AND c.relkind = 'r' AND x.grantee <> c.relowner AND x.grantee <> 0
             AND x.privilege_type IN ('UPDATE', 'DELETE', 'TRUNCATE')
             AND c.relname IN (SELECT chain_table FROM trustride.platform_audit_chain UNION ALL SELECT 'platform_audit_chain') LOOP
    EXECUTE format('REVOKE UPDATE, DELETE, TRUNCATE ON trustride.%I FROM %I', g.relname, g.role_name);
  END LOOP;
END;
$chains$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
