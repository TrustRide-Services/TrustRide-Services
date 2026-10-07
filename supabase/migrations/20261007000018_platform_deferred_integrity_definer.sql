-- ============================================================================
-- Platform: deferred integrity checks run with their owner's rights
-- ============================================================================
--   Four integrity checks are DEFERRABLE INITIALLY DEFERRED constraint
--   triggers: they fire at COMMIT, after every SECURITY DEFINER function has
--   returned, as the caller's own role. Since G1 (20261007000001) narrowed
--   reads of the platform tables, a non-Office caller can no longer see the
--   rows those checks look up. The Surface Law check on
--   present_command_capture therefore refused, at commit, every command a
--   Customer, Operator, Governor, Partner, Intermediary or Vendor issued
--   through the Data API ("... is not a permitted verb ..."). The
--   rollback-only test suites never reached COMMIT, so it went unseen until
--   the browser journeys (suite 10 now forces commit-time checks).
--
--   An integrity check must judge every row whatever the caller may read, so
--   each runs as its owner. The bodies are unchanged: they only read and
--   raise.
-- ============================================================================

ALTER FUNCTION trustride.fn_present_command_capability_check() SECURITY DEFINER;
ALTER FUNCTION trustride.business_order_scope_exists() SECURITY DEFINER SET search_path = trustride, pg_temp;
ALTER FUNCTION trustride.resource_workforce_unit_fleet_requirement() SECURITY DEFINER SET search_path = trustride, pg_temp;
ALTER FUNCTION trustride.service_pillar_domain_ea() SECURITY DEFINER SET search_path = trustride, pg_temp;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;

SELECT trustride.fn_platform_conformance_assert();
