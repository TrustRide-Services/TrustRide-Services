-- ============================================================================
-- Engine 7 (Orchestration) -- unrecoverable historical queue entries are
-- registered, kept as found, and never counted as work in flight
-- Construction Directive WP1 (residual exception: six historical queue entries)
-- ============================================================================
-- Migration 034 copied each pre-033 queue entry's recorded inbox outcome onto
-- the queue. Six entries on staging (26 and 28 August 2026, destination
-- Engine 11) have no destination inbox record, so no outcome can be
-- established. They stay DISPATCHED -- an outcome is never invented -- but the
-- capacity snapshot counted every DISPATCHED entry as "in flight", so these six
-- inflated signals_in_flight permanently.
--
-- Correction:
--   * orch_queue_historical_exception registers such entries with their
--     classification and the evidence; append-only;
--   * the entries found now are registered: DISPATCHED, created before
--     migration 033, and with no row in the destination inbox;
--   * fn_orch_capacity_snapshot_record no longer counts registered entries as
--     in flight. Nothing else reads DISPATCHED queue entries.
-- ============================================================================

CREATE TABLE trustride.orch_queue_historical_exception (
  queue_id        UUID PRIMARY KEY REFERENCES trustride.orch_signal_queue (queue_id),
  classification  TEXT NOT NULL CHECK (classification IN ('UNRECOVERABLE_NO_INBOX_RECORD')),
  evidence        TEXT NOT NULL,
  registered_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE trustride.orch_queue_historical_exception ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE trustride.orch_queue_historical_exception IS
  'Queue entries whose outcome cannot be established (no destination inbox record). Kept as found; excluded from in-flight counts. Append-only.';
CREATE TRIGGER trg_orch_queue_historical_exception_append_only BEFORE UPDATE OR DELETE ON trustride.orch_queue_historical_exception
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_platform_audit_chain_append_only();

DO $register$
DECLARE
  d RECORD;
BEGIN
  FOR d IN SELECT DISTINCT destination_engine_code, destination_inbox_table FROM trustride.orch_destination_cache LOOP
    EXECUTE format(
      'INSERT INTO trustride.orch_queue_historical_exception (queue_id, classification, evidence)
       SELECT q.queue_id, ''UNRECOVERABLE_NO_INBOX_RECORD'',
              ''queued '' || q.queued_at || '' for '' || q.destination_engine_code || '' ('' || q.signal_type || ''); no row in %s; registered by migration 038''
       FROM trustride.orch_signal_queue q
       WHERE q.queue_status = ''DISPATCHED'' AND q.destination_engine_code = $1 AND q.created_at < ''2026-10-11''
         AND NOT EXISTS (SELECT 1 FROM trustride.%I i WHERE i.signal_id = q.signal_id)
       ON CONFLICT DO NOTHING', d.destination_inbox_table, d.destination_inbox_table)
    USING d.destination_engine_code;
  END LOOP;
END;
$register$;

DO $patch$
DECLARE
  v_def TEXT;
  v_old TEXT := E'SELECT count(*) INTO v_in_flight FROM trustride.orch_signal_queue WHERE queue_status IN (''LEASED'', ''DISPATCHED'');';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_orch_capacity_snapshot_record()'::regprocedure) INTO v_def;
  IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'in-flight count not found'; END IF;
  v_def := replace(v_def, v_old,
    E'SELECT count(*) INTO v_in_flight FROM trustride.orch_signal_queue q WHERE q.queue_status IN (''LEASED'', ''DISPATCHED'')\n'
    || E'    AND NOT EXISTS (SELECT 1 FROM trustride.orch_queue_historical_exception x WHERE x.queue_id = q.queue_id);');
  EXECUTE v_def;
END;
$patch$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
