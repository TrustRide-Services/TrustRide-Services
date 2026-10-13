-- ============================================================================
-- Founder direction (WP9 item 3) and TBOC Art.20.1: catalogue access follows
-- Platform Access -> Registration -> Identity Verification -> Authentication ->
-- Authorization -> User Type Profile Activated -> Service Catalogue Access.
--
-- Defect: neither fn_business_actor_register (Engine 4, user-type profile
-- activation) nor fn_present_shell_session_open (Engine 11) checked that the
-- identity had passed verification. A signed-in but unverified person
-- (PENDING_VERIFICATION or VERIFICATION_FAILED) could, by calling the database
-- directly, activate a Customer profile and open the Customer shell -- the
-- browser's /verify screen was the only barrier. Now:
--   * a user-type profile is activated only for a verified (ACTIVE) identity,
--     by that identity or its verified representative;
--   * every shell session needs the session identity and the signed-in person
--     to be verified (ACTIVE); suspended identities keep their own message.
-- Unchanged: a verified person's Customer profile still activates at once (no
-- manual approval), so the catalogue opens automatically; Partner, Governor and
-- Intermediary still wait for Office review; catalogue management stays with
-- the Office; each service's own prerequisites (coverage, Engine 5 price,
-- verified M-Pesa phone, working hours) still apply.
-- ============================================================================

DO $patch$
DECLARE
  v_def TEXT;
  a1 TEXT := E'    IF p_user_type_domain = ''OPERATOR'' THEN';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'trustride' AND p.proname = 'fn_business_actor_register';
  IF position(a1 IN v_def) = 0 THEN RAISE EXCEPTION 'actor register anchor not found'; END IF;
  EXECUTE replace(v_def, a1,
       E'    IF EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id IN (p_user_id, v_caller) AND status <> ''ACTIVE'')\n'
    || E'       OR NOT EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id = p_user_id) THEN\n'
    || E'      RAISE EXCEPTION ''Verify your identity first -- a TrustRide profile opens only after the official identity check has passed'';\n'
    || E'    END IF;\n'
    || a1);
END;
$patch$;

DO $patch$
DECLARE
  v_def TEXT;
  a1 TEXT := E'    RAISE EXCEPTION ''This identity is suspended -- contact TrustRide Office'';\n  END IF;';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'trustride' AND p.proname = 'fn_present_shell_session_open';
  IF position(a1 IN v_def) = 0 THEN RAISE EXCEPTION 'session anchor not found'; END IF;
  EXECUTE replace(v_def, a1, a1
    || E'\n  IF EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id IN (p_user_id, auth.uid()) AND status <> ''ACTIVE'') THEN\n'
    || E'    RAISE EXCEPTION ''Verify your identity first -- TrustRide opens only after the official identity check has passed'';\n'
    || E'  END IF;');
END;
$patch$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
