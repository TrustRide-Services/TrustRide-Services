-- ============================================================================
-- Platform -- views never widen what a caller may read
-- TRS026-ENG-REMEDIATION-001, finding D02
-- ============================================================================
-- Forensic audit 2026-10-08 proved that a plain customer read every row of
-- all 14 trustride views, including other customers' orders through
-- v_business_order_status. A Postgres view runs with its owner's rights
-- unless security_invoker is set, so each view bypassed the row-level
-- security of the tables beneath it, and trustride_authenticated held SELECT
-- on every one. Eight engine service roles also held INSERT, UPDATE and
-- DELETE on views.
--
-- No frontend code and no database function reads any of these views (audit
-- inventory and catalogue search, 2026-10-11): they are operator read
-- surfaces, and signed-in reads go through Engine 11 projections.
--
-- Correction:
--   * every view except Engine 5's runs with the reading caller's rights;
--   * no signed-in or anonymous role reads any view;
--   * no role other than the owner holds a write privilege on any view;
--   * the platform conformance assertion (run at the end of every
--     migration) now refuses a view readable past row-level security and a
--     view that grants writes.
-- Engine 5 (v_cost_registry_active): definition and options unchanged, by
-- Founder ruling; only the signed-in read and the write grants that no code
-- uses are withdrawn.
-- ============================================================================

DO $views$
DECLARE
  v RECORD;
BEGIN
  FOR v IN SELECT c.relname FROM pg_class c WHERE c.relnamespace = 'trustride'::regnamespace AND c.relkind = 'v' LOOP
    IF v.relname <> 'v_cost_registry_active' THEN
      EXECUTE format('ALTER VIEW trustride.%I SET (security_invoker = true)', v.relname);
    END IF;
    EXECUTE format('REVOKE ALL ON trustride.%I FROM PUBLIC, anon, authenticated, trustride_authenticated', v.relname);
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON trustride.%I FROM '
      'trs026_eng001_fdn_service, trs026_eng002_resc_service, trs026_eng003_serv_service, trs026_eng004_bus_service, '
      'trs026_eng005_cost_service, trs026_eng006_intg_service, trs026_eng007_orch_service, trs026_eng008_coord_service', v.relname);
  END LOOP;
END;
$views$;

-- Systemic guard -- two view checks added to the conformance assertion.
DO $patch$
DECLARE
  v_def TEXT;
  v_old TEXT := E'    AND p.proname <> ALL (trustride.fn_platform_authenticated_function_allowlist());\n$function$';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_platform_conformance_violations()'::regprocedure) INTO v_def;
  IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'conformance tail not found'; END IF;
  v_def := replace(v_def, v_old, E'    AND p.proname <> ALL (trustride.fn_platform_authenticated_function_allowlist())\n'
    || E'  UNION ALL\n'
    || E'  -- A view a signed-in or anonymous caller can read must run with the caller''s rights.\n'
    || E'  SELECT ''VIEW_BYPASSES_ROW_SECURITY'', c.relname::text, ''readable by a signed-in or anonymous role without security_invoker''\n'
    || E'  FROM pg_class c\n'
    || E'  WHERE c.relnamespace = ''trustride''::regnamespace AND c.relkind = ''v''\n'
    || E'    AND NOT coalesce(c.reloptions, ''{}'') @> ARRAY[''security_invoker=true'']\n'
    || E'    AND (has_table_privilege(''trustride_authenticated'', c.oid, ''SELECT'') OR has_table_privilege(''anon'', c.oid, ''SELECT''))\n'
    || E'  UNION ALL\n'
    || E'  -- Views are read surfaces: only the owner holds a write privilege.\n'
    || E'  SELECT ''VIEW_GRANTS_WRITE'', c.relname::text, pg_get_userbyid(x.grantee) || '' holds '' || x.privilege_type\n'
    || E'  FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) x\n'
    || E'  WHERE c.relnamespace = ''trustride''::regnamespace AND c.relkind = ''v''\n'
    || E'    AND x.grantee <> c.relowner AND x.privilege_type IN (''INSERT'', ''UPDATE'', ''DELETE'', ''TRUNCATE'');\n$function$');
  EXECUTE v_def;
END;
$patch$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
