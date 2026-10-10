-- Suite 16 -- every audit log is one tamper-evident chain (TRS026-ENG-REMEDIATION-001: D08, D09).
-- Writers in one transaction or many link into a single line; a row cannot
-- be changed, removed or truncated through SQL; an altered row is found by
-- verification; history before the fix is acknowledged, not rewritten; and
-- the chains are verified and sealed daily.
DO $$
DECLARE
  cust UUID; r JSONB; n INT; m INT; v TEXT; t RECORD; seq BIGINT; ok BOOLEAN;
  chains TEXT[] := ARRAY['audit_log', 'present_decision_log', 'advisory_decision_log', 'model_decision_log',
                         'orch_execution_audit', 'orch_routing_audit', 'resource_ledger_event'];
  c TEXT;
BEGIN
  -- ============ D08 exploit replay: several writes in one transaction must form one line, not a fork
  PERFORM trustride.fn_model_decision_log_write(NULL, 'CHAIN_PROBE_1', 'suite 16');
  PERFORM trustride.fn_model_decision_log_write(NULL, 'CHAIN_PROBE_2', 'suite 16');
  PERFORM trustride.fn_model_decision_log_write(NULL, 'CHAIN_PROBE_3', 'suite 16');
  SELECT count(DISTINCT coalesce(prev_hash, '-')) INTO n FROM trustride.model_decision_log WHERE event_type LIKE 'CHAIN_PROBE_%';
  SELECT count(*) INTO m FROM trustride.model_decision_log a JOIN trustride.model_decision_log b ON b.prev_hash = a.immutable_hash
  WHERE a.event_type LIKE 'CHAIN_PROBE_%' AND b.event_type LIKE 'CHAIN_PROBE_%';
  PERFORM pg_temp.t_check('D08 three writes in one transaction link in a single line (no fork)', n = 3 AND m = 2, 'distinct_prev=' || n || ' links=' || m);
  cust := pg_temp.t_customer('Chain Cust');
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'OPEN_SUPPORT_CASE', '{"category":"ORDER_ISSUE","subject":"Chain 1","body":"x"}');
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'OPEN_SUPPORT_CASE', '{"category":"ORDER_ISSUE","subject":"Chain 2","body":"y"}');
  SELECT count(*) INTO n FROM (SELECT prev_hash FROM trustride.present_decision_log GROUP BY prev_hash HAVING count(*) > 1) f;
  PERFORM pg_temp.t_check('D08 no two Engine 11 decisions share a predecessor', n = 0, n::text);

  IF to_regclass('trustride.platform_audit_chain') IS NULL THEN
    PERFORM pg_temp.t_check('D08/D09 chain register, link trigger, verification and seal exist', false, 'platform_audit_chain absent');
  ELSE
    -- ============ every chain is registered, linked by the database and append-only
    FOREACH c IN ARRAY chains || ARRAY['platform_audit_chain_seal'] LOOP
      ok := to_regclass('trustride.platform_audit_chain') IS NOT NULL
        AND EXISTS (SELECT 1 FROM trustride.platform_audit_chain h WHERE h.chain_table = c)
        AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = ('trustride.' || c)::regclass AND tgfoid = 'trustride.fn_platform_audit_chain_link'::regproc AND tgenabled = 'O')
        AND EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = ('trustride.' || c)::regclass AND tgfoid = 'trustride.fn_platform_audit_chain_append_only'::regproc AND tgenabled = 'O');
      PERFORM pg_temp.t_check('D08 ' || c || ' is a registered, database-linked, append-only chain', coalesce(ok, false));
    END LOOP;
    BEGIN UPDATE trustride.present_decision_log SET event_description = 'rewritten' WHERE decision_log_id = (SELECT decision_log_id FROM trustride.present_decision_log LIMIT 1);
      ok := false; EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%append-only%'; END;
    PERFORM pg_temp.t_check('an audit row cannot be rewritten', ok);
    BEGIN DELETE FROM trustride.audit_log WHERE audit_id = (SELECT audit_id FROM trustride.audit_log LIMIT 1);
      ok := false; EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%append-only%'; END;
    PERFORM pg_temp.t_check('an audit row cannot be deleted', ok);
    BEGIN TRUNCATE trustride.orch_routing_audit; ok := false; EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%append-only%'; END;
    PERFORM pg_temp.t_check('an audit log cannot be truncated', ok);

    -- ============ verification: clean now; an altered row is found
    SELECT count(*) FILTER (WHERE first_break_seq IS NOT NULL), count(*) INTO n, m FROM trustride.fn_platform_audit_chain_verify(TRUE);
    PERFORM pg_temp.t_check('every chain verifies end to end from its rebase point', n = 0 AND m = 8, n || ' broken of ' || m);
    SELECT chain_seq INTO seq FROM trustride.model_decision_log WHERE event_type = 'CHAIN_PROBE_2';
    ALTER TABLE trustride.model_decision_log DISABLE TRIGGER USER;   -- what only the database owner can do
    UPDATE trustride.model_decision_log SET event_description = 'tampered' WHERE event_type = 'CHAIN_PROBE_2';
    ALTER TABLE trustride.model_decision_log ENABLE TRIGGER USER;
    SELECT * INTO t FROM trustride.fn_platform_audit_chain_verify(TRUE) WHERE chain_table = 'model_decision_log';
    PERFORM pg_temp.t_check('an altered row is found by verification at its position', t.first_break_seq = seq AND t.break_kind = 'CONTENT_ALTERED',
      coalesce(t.first_break_seq::text, 'none') || ' ' || coalesce(t.break_kind, '') || ' expected ' || seq);

    -- ============ D09: history before the fix is acknowledged, not rewritten
    SELECT count(*) INTO n FROM trustride.platform_audit_chain WHERE legacy_rows IS NOT NULL AND legacy_breaks IS NOT NULL;
    PERFORM pg_temp.t_check('D09 every chain records its pre-fix rows and breaks', n = 8, n::text);
    PERFORM pg_temp.t_check('D09 the rebase is itself an audit event',
      EXISTS (SELECT 1 FROM trustride.audit_log WHERE entity_type = 'PLATFORM_AUDIT_CHAIN' AND action = 'CHAIN_REBASED'));

    -- ============ daily seal and systemic guard
    ALTER TABLE trustride.model_decision_log DISABLE TRIGGER USER;
    UPDATE trustride.model_decision_log SET event_description = 'suite 16' WHERE event_type = 'CHAIN_PROBE_2';
    ALTER TABLE trustride.model_decision_log ENABLE TRIGGER USER;
    n := trustride.fn_platform_audit_chain_seal();
    SELECT count(*) INTO m FROM trustride.platform_audit_chain_seal WHERE sealed_at = now() AND verified;
    PERFORM pg_temp.t_check('the seal verifies and records every chain head', n = 8 AND m = 8, n || ' sealed, ' || m || ' verified');
    PERFORM pg_temp.t_check('the seal runs daily', EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'trustride_audit_chain_seal'));
    SELECT count(*) INTO n FROM trustride.fn_platform_conformance_violations() WHERE check_code = 'AUDIT_CHAIN_UNGUARDED';
    PERFORM pg_temp.t_check('systemic: conformance refuses a hash-chained table without the chain guard',
      pg_get_functiondef('trustride.fn_platform_conformance_violations()'::regprocedure) LIKE '%AUDIT_CHAIN_UNGUARDED%' AND n = 0, n::text);
  END IF;
END
$$;
