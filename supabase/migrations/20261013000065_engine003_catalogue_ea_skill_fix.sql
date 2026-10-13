-- ============================================================================
-- Defect in 058 (found by the WP9 lifecycle suite): fn_service_catalogue_office_register
-- compared Engine 5's ea_skill_category (an enum) with text, so registering ANY
-- Executive Assistant service failed with "operator does not exist". Suite 38 only
-- asserted that invalid EA registrations were rejected, so it passed for the wrong
-- reason; it now also proves a valid EA registration and the refusal reasons.
-- Second defect (same function): a NULL pillar cast to the pillar enum without error,
-- so an Executive Assistant service without a pillar was not refused (TBOC Art.27.2.1).
-- Fix: compare as text; require the pillar. Engine 5 is still only read.
-- ============================================================================

DO $patch$
DECLARE
  v_def TEXT;
  a1 TEXT := E'WHERE ea_skill_category = upper(trim(coalesce(p_ea_skill_category, '''')))';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'trustride' AND p.proname = 'fn_service_catalogue_office_register';
  IF position(a1 IN v_def) = 0 THEN RAISE EXCEPTION 'EA skill anchor not found'; END IF;
  v_def := replace(v_def, a1, E'WHERE ea_skill_category::text = upper(trim(coalesce(p_ea_skill_category, '''')))');
  IF position(E'    BEGIN PERFORM upper(trim(p_pillar))::trustride.service_pillar_code_enum;' IN v_def) = 0 THEN RAISE EXCEPTION 'pillar anchor not found'; END IF;
  v_def := replace(v_def, E'    BEGIN PERFORM upper(trim(p_pillar))::trustride.service_pillar_code_enum;',
    E'    IF nullif(trim(coalesce(p_pillar, '''')), '''') IS NULL THEN
'
    || E'      RAISE EXCEPTION ''An Executive Assistant service names one of the six pillars (TBOC Art.27)'';
'
    || E'    END IF;
'
    || E'    BEGIN PERFORM upper(trim(p_pillar))::trustride.service_pillar_code_enum;');
  EXECUTE v_def;
END;
$patch$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
