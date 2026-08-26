-- ============================================================================
-- PLATFORM FUNCTION GRANT RESWEEP -- Engines 9, 10, 11
-- ============================================================================
-- Found during the trustride-stagging closure test (structural stability
-- check A4): 28 functions across Engines 9/10/11 carry the default PUBLIC
-- EXECUTE grant, exactly the same class of issue the earlier platform audit
-- (20260825000001) already fixed for Engines 1-8.
--
-- Root cause, confirmed empirically this time rather than assumed: Postgres's
-- "PUBLIC has EXECUTE on functions" default is a hardcoded fallback applied
-- whenever a new function's initial ACL is computed, not a genuine stored
-- default-privilege grant. `ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE ON
-- FUNCTIONS FROM PUBLIC` -- the fix applied in 20260825000001 -- creates NO
-- pg_default_acl row and has NO effect on functions created afterward,
-- confirmed directly: a GRANT-then-REVOKE round trip on the PUBLIC default
-- left no trace, and a freshly created function still carried `=X/postgres`
-- in its ACL regardless. ALTER DEFAULT PRIVILEGES can only ADD extra default
-- grants on top of that hardcoded baseline; it cannot suppress it.
--
-- This means the correct, durable discipline is NOT "set it once platform-
-- wide" -- it is "every migration that creates a new function must revoke
-- PUBLIC from it explicitly," or, as a safety net, re-run this exact sweep
-- at every future engine-batch closure. This file does the latter now and
-- documents the former as the going-forward rule.
-- ============================================================================
DO $$
DECLARE
  v_func RECORD;
BEGIN
  FOR v_func IN
    SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'trustride'
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %I.%I(%s) FROM PUBLIC', v_func.nspname, v_func.proname, v_func.args);
  END LOOP;
END;
$$;

-- ============================================================================
-- VALIDATION
-- ============================================================================
DO $$
DECLARE
  v_public_count INTEGER;
BEGIN
  SELECT count(*) INTO v_public_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  CROSS JOIN LATERAL aclexplode(p.proacl) g
  WHERE n.nspname = 'trustride' AND p.proacl IS NOT NULL AND g.grantee = 0;

  IF v_public_count <> 0 THEN
    RAISE EXCEPTION 'RESWEEP FAILED: % trustride functions still carry a PUBLIC execute grant', v_public_count;
  END IF;

  RAISE NOTICE 'PLATFORM FUNCTION GRANT RESWEEP VERIFIED: 0 functions carry a PUBLIC execute grant.';
END;
$$;
