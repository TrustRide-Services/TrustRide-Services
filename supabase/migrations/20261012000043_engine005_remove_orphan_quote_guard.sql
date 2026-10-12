-- ============================================================================
-- Engine 5 -- remove the staging-only orphan cost_quotes_block_illegal_mutation()
-- Construction Directive WP5 (section 2.3, D19) -- Founder-authorized, conditional
-- ============================================================================
-- Authorization: removal only if the function is proven an unused staging
-- orphan and removing it weakens no Engine 5 invariant.
--
-- Evidence (staging, 2026-10-12; WP5_orphan_dependency_scan.txt):
--   * pg_depend references to it: 0; triggers using it: 0; event triggers: 0;
--     policies: 0; views: 0; cron jobs: 0; other functions naming it (including
--     dynamic SQL): none; no application, Edge Function or ops code names it.
--   * No migration creates it (030 names it in a comment only); a database
--     rebuilt from 001 onwards does not contain it (D19 catalogue diff).
--   * It was written by the Engine 5 blueprint for a table named
--     cost_unit_price_quotes, which does not exist; owner postgres, execute
--     postgres only.
--   * Its invariant (fare and hash immutable once a quote is locked) is
--     enforced on the real table by trustride.fare_quote_block_illegal_mutation()
--     through trg_fare_quote_block_illegal_mutation on fare_quote -- the same
--     logic, line for line. Nothing that protects a quote changes.
--
-- Forensic record of the object removed (staging only), as pg_get_functiondef
-- returned it:
--   CREATE OR REPLACE FUNCTION trustride.cost_quotes_block_illegal_mutation()
--    RETURNS trigger LANGUAGE plpgsql SET search_path TO 'trustride', 'pg_temp'
--   AS $function$
--   BEGIN
--     IF OLD.quote_state IN ('FARE_LOCKED', 'SERVICE_IN_PROGRESS', 'FARE_FINALIZED', 'C2B_PAYMENT_TRIGGERED')
--        AND (NEW.computed_total_fare_kes IS DISTINCT FROM OLD.computed_total_fare_kes
--             OR NEW.quote_hash IS DISTINCT FROM OLD.quote_hash) THEN
--       RAISE EXCEPTION 'cost_unit_price_quotes: fare and hash are immutable once quote_state = %; correction requires a new quote', OLD.quote_state;
--     END IF;
--     RETURN NEW;
--   END;
--   $function$
--   ACL: {postgres=X/postgres}
--
-- Repeatable: on a database built from the migrations it does nothing. The
-- guard below refuses to drop if anything has come to depend on the function
-- since the scan, or if the real guard on fare_quote is missing.
-- ============================================================================

DO $remove$
BEGIN
  IF to_regprocedure('trustride.cost_quotes_block_illegal_mutation()') IS NULL THEN
    RETURN;   -- not present (clean rebuild): nothing to do
  END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgfoid = 'trustride.cost_quotes_block_illegal_mutation()'::regprocedure)
     OR EXISTS (SELECT 1 FROM pg_depend WHERE refobjid = 'trustride.cost_quotes_block_illegal_mutation()'::regprocedure) THEN
    RAISE EXCEPTION 'cost_quotes_block_illegal_mutation() is now in use -- not removed; re-run the WP5 scan';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'trustride.fare_quote'::regclass AND tgname = 'trg_fare_quote_block_illegal_mutation'
                 AND tgfoid = 'trustride.fare_quote_block_illegal_mutation()'::regprocedure AND tgenabled = 'O') THEN
    RAISE EXCEPTION 'the fare_quote immutability guard is missing -- the orphan is not removed until it is restored';
  END IF;
  DROP FUNCTION trustride.cost_quotes_block_illegal_mutation();
  RAISE NOTICE 'removed staging-only orphan trustride.cost_quotes_block_illegal_mutation()';
END;
$remove$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
