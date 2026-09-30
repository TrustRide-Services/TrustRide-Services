-- ============================================================================
-- FOUNDATION -- IS THE GENESIS FOUNDER CLAIMED?
-- [Trace: TBOC-v2.0.0 Art.10, 12.5; fn_founder_bootstrap genesis path]
--
-- The live platform has no Founder role assigned, so nobody can yet approve
-- a request or enter TrustRide Office -- a wall. fn_founder_bootstrap is the
-- lawful one-time genesis path, but role_assignment is private (self or
-- governor read), so the Sovereign Gate cannot tell whether to offer it.
-- This answers only that yes/no -- it exposes no identity, no assignment.
-- ============================================================================
CREATE OR REPLACE FUNCTION trustride.fn_founder_exists()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1 FROM trustride.role_assignment ra
    JOIN trustride.role_definition rd ON rd.role_id = ra.role_id
    WHERE rd.role_code = 'FOUNDER' AND ra.status = 'ACTIVE'
  );
$$;
REVOKE EXECUTE ON FUNCTION trustride.fn_founder_exists() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_founder_exists() TO trustride_authenticated;
