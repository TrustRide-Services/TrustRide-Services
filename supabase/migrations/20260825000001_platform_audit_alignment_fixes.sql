-- ============================================================================
-- PLATFORM AUDIT & ALIGNMENT FIXES -- Engines 1-8
-- ============================================================================
-- Founder-directed full audit and alignment test across every implemented
-- engine before starting Engine 9. Three checks run clean (signal routing:
-- all 20 routing_rule rows trace to a real emitter and a real handler across
-- Engines 1-8, no orphans; RLS: every trustride table has row level security
-- enabled; table grants: no table carries a PUBLIC privilege). Two real
-- findings, fixed here.
--
-- FINDING 1 (critical): every function created across Engines 1-8 still
-- carries Postgres's own default EXECUTE-to-PUBLIC grant -- CREATE FUNCTION
-- grants PUBLIC execute unless explicitly revoked, and no migration this
-- entire build ever revoked it. Combined with every SECURITY DEFINER
-- function being owned by `postgres` (a BYPASSRLS superuser, confirmed via
-- pg_roles) and `trustride_authenticated` holding USAGE on the schema, this
-- means an ordinary authenticated end user could currently call internal
-- signal accept-handlers directly (e.g. fn_business_payment_settled_accept,
-- fn_cost_fare_calculate, fn_resource_assign) -- bypassing both the
-- signal-driven architecture and RLS entirely, since SECURITY DEFINER
-- execution as a BYPASSRLS owner ignores every RLS policy on every table it
-- touches. Confirmed via direct query that every one of the 138 affected
-- functions already carries its own genuine, intentional role-based grant
-- alongside the stray PUBLIC one -- revoking PUBLIC strips no legitimate
-- access from anything.
--
-- FINDING 2 (minor): engine_registry.engine_version for TRS026_ENG005_COST
-- was last bumped to '2.1.0' by the Universal Asset Matrix file, but Engine
-- 6's full-port-coverage file (20260824000008) bumped fn_cost_fare_calculate's
-- own internal engine_version literal (written into every cost_record row)
-- to '2.2.0' without updating the registry to match. The registry is the
-- platform's source of truth for "what version is this engine" -- it must
-- reflect what the code actually claims.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- FIX 1a: strip the stray PUBLIC grant from every function that exists today.
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- FIX 1b: stop future functions in this schema from silently reinheriting
-- the PUBLIC default -- every engine built from here on must grant EXECUTE
-- explicitly, matching the discipline already followed for every service
-- role grant issued this entire session.
-- ----------------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA trustride REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- FIX 2: align the registry with the code's own claimed version.
-- ----------------------------------------------------------------------------
UPDATE trustride.engine_registry SET engine_version = '2.2.0' WHERE engine_code = 'TRS026_ENG005_COST';

-- ============================================================================
-- VALIDATION
-- ============================================================================
DO $$
DECLARE
  v_public_count INTEGER;
  v_cost_version TEXT;
BEGIN
  SELECT count(*) INTO v_public_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  CROSS JOIN LATERAL aclexplode(p.proacl) g
  WHERE n.nspname = 'trustride' AND p.proacl IS NOT NULL AND g.grantee = 0;

  IF v_public_count <> 0 THEN
    RAISE EXCEPTION 'ALIGNMENT FIX FAILED: % trustride functions still carry a PUBLIC execute grant', v_public_count;
  END IF;

  SELECT engine_version INTO v_cost_version FROM trustride.engine_registry WHERE engine_code = 'TRS026_ENG005_COST';
  IF v_cost_version <> '2.2.0' THEN
    RAISE EXCEPTION 'ALIGNMENT FIX FAILED: Cost engine_registry version is %, expected 2.2.0', v_cost_version;
  END IF;

  RAISE NOTICE 'PLATFORM AUDIT ALIGNMENT FIXES VERIFIED: 0 functions carry a PUBLIC execute grant, Cost registry version = 2.2.0';
END;
$$;
