-- ============================================================================
-- Engine 7 (Orchestration) -- every signal reaches an explicit terminal state
-- TRS026-ENG-REMEDIATION-001, findings D10, D22
-- ============================================================================
-- Forensic audit 2026-10-08:
--   D10  a signal with no active route was recorded NO_RULE_MATCHED but left
--        PENDING, so the 10-second dispatch cycle decided it again forever
--        (one routing decision and one audit row per cycle, unbounded);
--   D22  a routed signal's queue entry stayed DISPATCHED after its handler
--        ran; COMPLETED and FAILED were never written.
--
-- Correction (fn_orch_dispatch_cycle only):
--   * no route -> the outbox row ends DEAD_LETTER with reason NO_ROUTE, a
--     dead_letter_review row is opened and the Office is told, once;
--   * after the destination handler runs, the queue entry is COMPLETED, or
--     FAILED when the handler raised (the existing dead-letter path).
-- The queue's lease, retry and checkpoint tables remain unused: handling is
-- synchronous inside the cycle, with failures dead-lettered for review.
-- ============================================================================

DO $patch$
DECLARE
  v_def TEXT;
  v_no_route TEXT := E'        VALUES (v_row.signal_id, v_row.correlation_id, ''NO_RULE_MATCHED'', v_prev_hash, v_new_hash);\n\n        CONTINUE;\n';
  v_ok TEXT := E'          ELSE NULL;\n        END CASE;\n        v_processed := v_processed + 1;\n      EXCEPTION WHEN OTHERS THEN\n        PERFORM trustride.fn_orch_handler_failed(v_cache.destination_inbox_table, v_row.signal_id, v_row.emitting_engine, v_cache.destination_engine_code, v_row.signal_type, SQLERRM);\n      END;\n';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_orch_dispatch_cycle()'::regprocedure) INTO v_def;
  IF position(v_no_route IN v_def) = 0 THEN RAISE EXCEPTION 'no-route branch not found'; END IF;
  IF position(v_ok IN v_def) = 0 THEN RAISE EXCEPTION 'handler block not found'; END IF;

  v_def := replace(v_def, v_no_route,
       E'        VALUES (v_row.signal_id, v_row.correlation_id, ''NO_RULE_MATCHED'', v_prev_hash, v_new_hash);\n\n'
    || E'        -- Terminal: dead-lettered once with the reason, reviewed by the Office.\n'
    || E'        EXECUTE format(''UPDATE trustride.%I SET signal_status = ''''DEAD_LETTER'''', rejection_reason = $2 WHERE signal_id = $1'', v_row.src_outbox_table)\n'
    || E'        USING v_row.signal_id, left(''NO_ROUTE: no active route for '' || v_row.signal_type || '' from '' || v_row.emitting_engine || '' to '' || coalesce(v_row.receiving_engine, ''?''), 500);\n'
    || E'        INSERT INTO trustride.dead_letter_review (event_id, source_engine, target_engine, failure_reason)\n'
    || E'        VALUES (v_row.signal_id, v_row.emitting_engine, coalesce(v_row.receiving_engine, ''UNKNOWN''), left(v_row.signal_type || '': no active route'', 1000));\n'
    || E'        PERFORM trustride.fn_present_notify_office(''Signal has no route: '' || v_row.signal_type,\n'
    || E'          v_row.emitting_engine || '' -> '' || coalesce(v_row.receiving_engine, ''?'') || ''. Dead-lettered for review; add the route or correct the emitter.'',\n'
    || E'          ''PLATFORM_EXCEPTION'', v_row.signal_id, ARRAY[''FOUNDER'', ''ADMINISTRATOR''], FALSE);\n'
    || E'        CONTINUE;\n');

  v_def := replace(v_def, v_ok,
       E'          ELSE NULL;\n        END CASE;\n        v_processed := v_processed + 1;\n'
    || E'        UPDATE trustride.orch_signal_queue SET queue_status = ''COMPLETED'' WHERE signal_id = v_row.signal_id AND queue_status IN (''QUEUED'', ''LEASED'', ''DISPATCHED'');\n'
    || E'      EXCEPTION WHEN OTHERS THEN\n'
    || E'        PERFORM trustride.fn_orch_handler_failed(v_cache.destination_inbox_table, v_row.signal_id, v_row.emitting_engine, v_cache.destination_engine_code, v_row.signal_type, SQLERRM);\n'
    || E'        UPDATE trustride.orch_signal_queue SET queue_status = ''FAILED'' WHERE signal_id = v_row.signal_id AND queue_status IN (''QUEUED'', ''LEASED'', ''DISPATCHED'');\n'
    || E'      END;\n');
  EXECUTE v_def;
END;
$patch$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
