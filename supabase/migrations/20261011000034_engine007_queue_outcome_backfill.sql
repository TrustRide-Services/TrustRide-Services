-- ============================================================================
-- Engine 7 (Orchestration) -- queue entries written before migration 033
-- carry their recorded outcome
-- TRS026-ENG-REMEDIATION-001, finding D22 (history)
-- ============================================================================
-- Before migration 033 every queue entry stayed DISPATCHED although its
-- handler had run. The handled outcome was recorded in the destination
-- inbox; this copies it onto the queue once: inbox ACCEPTED or REJECTED (the
-- handler ran and decided) -> COMPLETED; DEAD_LETTER (the handler raised)
-- -> FAILED. Entries whose inbox row is still RECEIVED stay DISPATCHED.
-- The orchestration audit chains are not touched.
-- ============================================================================

DO $backfill$
DECLARE
  d RECORD;
  n INTEGER;
BEGIN
  FOR d IN SELECT DISTINCT destination_engine_code, destination_inbox_table FROM trustride.orch_destination_cache LOOP
    EXECUTE format(
      'UPDATE trustride.orch_signal_queue q
          SET queue_status = CASE WHEN i.signal_status::text = ''DEAD_LETTER'' THEN ''FAILED'' ELSE ''COMPLETED'' END
         FROM trustride.%I i
        WHERE q.queue_status = ''DISPATCHED'' AND q.destination_engine_code = $1 AND i.signal_id = q.signal_id
          AND i.signal_status::text IN (''ACCEPTED'', ''REJECTED'', ''DEAD_LETTER'')', d.destination_inbox_table)
    USING d.destination_engine_code;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n > 0 THEN RAISE NOTICE 'queue outcome backfill: % entries for %', n, d.destination_engine_code; END IF;
  END LOOP;
END;
$backfill$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
