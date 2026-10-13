-- ============================================================================
-- Founder direction (WP9 item 2) -- the Office support screen needs the case
-- requester's identity reference to follow up an unreachable person through
-- their next of kin (fn_office_next_of_kin_reveal). Additive field only.
-- ============================================================================

DO $patch$
DECLARE
  v_def TEXT;
  a1 TEXT := E'''requester'', (SELECT display_name FROM trustride.platform_users WHERE user_id = c.opened_by_user_id),';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'trustride' AND p.proname = 'fn_present_proj_office_support';
  IF position(a1 IN v_def) = 0 THEN RAISE EXCEPTION 'support projection anchor not found'; END IF;
  EXECUTE replace(v_def, a1, a1 || E' ''requester_user_id'', c.opened_by_user_id,');
END;
$patch$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
