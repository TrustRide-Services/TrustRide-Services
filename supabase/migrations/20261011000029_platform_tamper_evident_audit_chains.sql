-- ============================================================================
-- Platform -- every audit log is one tamper-evident chain
-- TRS026-ENG-REMEDIATION-001, findings D08, D09
-- ============================================================================
-- Forensic audit 2026-10-08 proved:
--   D08  the seven hash-chained logs fork. About ten writer functions each
--        read "the latest hash" (mostly ORDER BY recorded_at, which ties
--        inside one transaction) with no lock, so two writes in one
--        transaction, or two transactions at once, link to the same
--        predecessor. The hash also covered ids only, not the row's content,
--        and nothing stopped UPDATE, DELETE or TRUNCATE of a log row.
--   D09  audit_log already holds broken links (26 and 28 August 2026).
--
-- Correction (one mechanism for every chain, owned by the platform):
--   * platform_audit_chain holds each chain's head (sequence and hash).
--     A BEFORE INSERT trigger locks that head row, so appends to one chain
--     are serialised in commit order; it assigns chain_seq, sets prev_hash
--     to the head and immutable_hash = sha256(prev || '|' || the row's full
--     content as canonical JSON, nulls stripped, in UTC). Values a writer
--     supplies for these three columns are replaced, so no writer function
--     needs to change and none can get it wrong.
--   * UPDATE, DELETE and TRUNCATE are refused on every chained table.
--   * Rows written before this migration are kept exactly as they are. Each
--     chain is rebased at its current head: its legacy rows and breaks
--     (forks, dangling links, extra roots) are counted, recorded and
--     announced as an audit event; new rows link from the legacy head.
--   * fn_platform_audit_chain_verify finds a missing row, a broken link, an
--     altered row or a head mismatch; fn_platform_audit_chain_seal records
--     every verified head daily (itself a chain) and alerts the Office on
--     any break.
--   * Conformance refuses any table carrying prev_hash and immutable_hash
--     without this guard.
--
-- Limits, stated plainly: the database owner can disable triggers and
-- rewrite a chain together with its head and seals; detecting that needs
-- the daily seal hash held outside the database (Founder decision on where).
-- Columns added to a chained table later must be nullable with no default,
-- or older rows stop verifying. fare_quote (Engine 5) is not one of these
-- logs and is untouched.
-- ============================================================================

CREATE TABLE trustride.platform_audit_chain (
  chain_table    TEXT PRIMARY KEY,
  head_seq       BIGINT NOT NULL,
  head_hash      CHAR(64),
  rebase_seq     BIGINT NOT NULL,
  legacy_rows    BIGINT NOT NULL,
  legacy_breaks  BIGINT NOT NULL,
  legacy_detail  JSONB NOT NULL,
  rebased_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE trustride.platform_audit_chain ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE trustride.platform_audit_chain IS
  'Head of each tamper-evident audit chain (D08). Rows after rebase_seq are verified strictly; legacy_* records the pre-fix history as found (D09).';

CREATE TABLE trustride.platform_audit_chain_seal (
  seal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chain_table      TEXT NOT NULL,
  head_seq         BIGINT NOT NULL,
  head_hash        CHAR(64),
  rows_verified    BIGINT NOT NULL,
  first_break_seq  BIGINT,
  break_kind       TEXT,
  verified         BOOLEAN NOT NULL,
  sealed_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  chain_seq        BIGINT,
  prev_hash        CHAR(64),
  immutable_hash   CHAR(64)
);
ALTER TABLE trustride.platform_audit_chain_seal ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE trustride.platform_audit_chain_seal IS
  'Daily verified head of every audit chain; itself an append-only chain. Copy the latest heads outside the database to detect owner-level rewriting.';

CREATE FUNCTION trustride.fn_platform_audit_chain_hash(p_prev TEXT, p_row JSONB)
 RETURNS CHAR(64)
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT encode(sha256(convert_to(coalesce(p_prev, '') || '|' || jsonb_strip_nulls(p_row - 'prev_hash' - 'immutable_hash')::text, 'UTF8')), 'hex')::CHAR(64);
$function$;

CREATE FUNCTION trustride.fn_platform_audit_chain_link()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
 SET timezone TO 'UTC'
AS $function$
DECLARE
  v_seq  BIGINT;
  v_hash CHAR(64);
BEGIN
  SELECT h.head_seq, h.head_hash INTO v_seq, v_hash FROM trustride.platform_audit_chain h WHERE h.chain_table = TG_TABLE_NAME FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'audit chain % is not registered', TG_TABLE_NAME; END IF;
  NEW.chain_seq := v_seq + 1;
  NEW.prev_hash := v_hash;
  NEW.immutable_hash := trustride.fn_platform_audit_chain_hash(v_hash, to_jsonb(NEW));
  UPDATE trustride.platform_audit_chain SET head_seq = NEW.chain_seq, head_hash = NEW.immutable_hash WHERE chain_table = TG_TABLE_NAME;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION trustride.fn_platform_audit_chain_append_only()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  RAISE EXCEPTION '% is an append-only audit chain: % refused', TG_TABLE_NAME, TG_OP;
END;
$function$;

-- Rebase each chain at its current head and put it under the guard.
DO $chains$
DECLARE
  c TEXT;
  v_order TEXT;
  v_rows BIGINT; v_forks BIGINT; v_dangling BIGINT; v_roots BIGINT;
  v_head_seq BIGINT; v_head_hash CHAR(64);
BEGIN
  FOREACH c IN ARRAY ARRAY['audit_log', 'resource_ledger_event', 'present_decision_log', 'advisory_decision_log',
                           'model_decision_log', 'orch_execution_audit', 'orch_routing_audit', 'platform_audit_chain_seal'] LOOP
    IF c IN ('audit_log', 'resource_ledger_event') THEN
      -- chain_seq becomes the trigger's (an identity number is drawn before the lock, out of commit order).
      EXECUTE format('ALTER TABLE trustride.%I ALTER COLUMN chain_seq DROP IDENTITY IF EXISTS', c);
      IF c = 'resource_ledger_event' THEN
        CREATE UNIQUE INDEX idx_resource_ledger_event_chain_seq ON trustride.resource_ledger_event (chain_seq);
      END IF;
    ELSIF c <> 'platform_audit_chain_seal' THEN
      v_order := CASE c WHEN 'present_decision_log' THEN 'recorded_at, decision_log_id' WHEN 'advisory_decision_log' THEN 'recorded_at, decision_log_id'
        WHEN 'model_decision_log' THEN 'recorded_at, decision_log_id' WHEN 'orch_execution_audit' THEN 'recorded_at, execution_audit_id'
        ELSE 'recorded_at, routing_audit_id' END;
      EXECUTE format('ALTER TABLE trustride.%I ADD COLUMN chain_seq BIGINT', c);
      EXECUTE format('UPDATE trustride.%I t SET chain_seq = s.n FROM (SELECT ctid AS id, row_number() OVER (ORDER BY %s) AS n FROM trustride.%I) s WHERE t.ctid = s.id', c, v_order, c);
      EXECUTE format('ALTER TABLE trustride.%I ALTER COLUMN chain_seq SET NOT NULL', c);
      EXECUTE format('CREATE UNIQUE INDEX idx_%s_chain_seq ON trustride.%I (chain_seq)', c, c);
    END IF;
    IF c = 'platform_audit_chain_seal' THEN
      EXECUTE format('ALTER TABLE trustride.%I ALTER COLUMN chain_seq SET NOT NULL', c);
      EXECUTE format('CREATE UNIQUE INDEX idx_%s_chain_seq ON trustride.%I (chain_seq)', c, c);
    END IF;

    -- Legacy history as found, independent of any ordering.
    EXECUTE format('SELECT count(*), count(*) FILTER (WHERE prev_hash IS NULL) FROM trustride.%I', c) INTO v_rows, v_roots;
    EXECUTE format('SELECT coalesce(sum(k - 1), 0) FROM (SELECT count(*) AS k FROM trustride.%I WHERE prev_hash IS NOT NULL GROUP BY prev_hash HAVING count(*) > 1) f', c) INTO v_forks;
    EXECUTE format('SELECT count(*) FROM trustride.%I a WHERE a.prev_hash IS NOT NULL AND NOT EXISTS (SELECT 1 FROM trustride.%I b WHERE b.immutable_hash = a.prev_hash)', c, c) INTO v_dangling;
    EXECUTE format('SELECT chain_seq, immutable_hash FROM trustride.%I ORDER BY chain_seq DESC LIMIT 1', c) INTO v_head_seq, v_head_hash;
    INSERT INTO trustride.platform_audit_chain (chain_table, head_seq, head_hash, rebase_seq, legacy_rows, legacy_breaks, legacy_detail)
    VALUES (c, coalesce(v_head_seq, 0), v_head_hash, coalesce(v_head_seq, 0), v_rows, v_forks + v_dangling + greatest(v_roots - 1, 0),
      jsonb_build_object('forks', v_forks, 'dangling_links', v_dangling, 'extra_roots', greatest(v_roots - 1, 0)));

    EXECUTE format('CREATE TRIGGER trg_%s_chain_link BEFORE INSERT ON trustride.%I FOR EACH ROW EXECUTE FUNCTION trustride.fn_platform_audit_chain_link()', c, c);
    EXECUTE format('CREATE TRIGGER trg_%s_append_only BEFORE UPDATE OR DELETE ON trustride.%I FOR EACH ROW EXECUTE FUNCTION trustride.fn_platform_audit_chain_append_only()', c, c);
    EXECUTE format('CREATE TRIGGER trg_%s_no_truncate BEFORE TRUNCATE ON trustride.%I FOR EACH STATEMENT EXECUTE FUNCTION trustride.fn_platform_audit_chain_append_only()', c, c);
  END LOOP;
END;
$chains$;

CREATE FUNCTION trustride.fn_platform_audit_chain_verify(p_full BOOLEAN DEFAULT FALSE)
 RETURNS TABLE(chain_table TEXT, rows_verified BIGINT, first_break_seq BIGINT, break_kind TEXT, head_seq BIGINT, legacy_rows BIGINT, legacy_breaks BIGINT)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
 SET timezone TO 'UTC'
AS $function$
#variable_conflict use_column
DECLARE
  c RECORD; r RECORD;
  v_from BIGINT; v_prev CHAR(64); v_seq BIGINT; v_n BIGINT; v_break BIGINT; v_kind TEXT;
BEGIN
  FOR c IN SELECT * FROM trustride.platform_audit_chain ORDER BY chain_table LOOP
    -- From the rebase point, or (daily) from the last verified seal of this chain.
    v_from := c.rebase_seq; v_prev := NULL;
    IF NOT p_full THEN
      SELECT s.head_seq INTO v_from FROM trustride.platform_audit_chain_seal s
      WHERE s.chain_table = c.chain_table AND s.verified ORDER BY s.chain_seq DESC LIMIT 1;
      v_from := coalesce(v_from, c.rebase_seq);
    END IF;
    IF v_from > 0 THEN
      EXECUTE format('SELECT immutable_hash FROM trustride.%I WHERE chain_seq = $1', c.chain_table) INTO v_prev USING v_from;
    END IF;
    v_seq := v_from; v_n := 0; v_break := NULL; v_kind := NULL;
    IF v_from > 0 AND v_prev IS NULL THEN
      v_break := v_from; v_kind := 'MISSING_ROW';
    ELSE
      FOR r IN EXECUTE format('SELECT t.chain_seq AS s, t.prev_hash AS p, t.immutable_hash AS h, to_jsonb(t) AS j FROM trustride.%I t WHERE t.chain_seq > $1 ORDER BY t.chain_seq', c.chain_table) USING v_from LOOP
        IF r.s <> v_seq + 1 THEN v_break := v_seq + 1; v_kind := 'MISSING_ROW'; EXIT; END IF;
        IF r.p IS DISTINCT FROM v_prev THEN v_break := r.s; v_kind := 'LINK_BROKEN'; EXIT; END IF;
        IF r.h IS DISTINCT FROM trustride.fn_platform_audit_chain_hash(r.p, r.j) THEN v_break := r.s; v_kind := 'CONTENT_ALTERED'; EXIT; END IF;
        v_prev := r.h; v_seq := r.s; v_n := v_n + 1;
      END LOOP;
      IF v_break IS NULL AND (v_seq <> c.head_seq OR v_prev IS DISTINCT FROM c.head_hash) THEN
        v_break := v_seq + 1; v_kind := 'HEAD_MISMATCH';
      END IF;
    END IF;
    chain_table := c.chain_table; rows_verified := v_n; first_break_seq := v_break; break_kind := v_kind;
    head_seq := c.head_seq; legacy_rows := c.legacy_rows; legacy_breaks := c.legacy_breaks;
    RETURN NEXT;
  END LOOP;
END;
$function$;

CREATE FUNCTION trustride.fn_platform_audit_chain_seal()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v RECORD;
  n INTEGER := 0;
  v_bad TEXT;
BEGIN
  FOR v IN SELECT f.*, h.head_hash FROM trustride.fn_platform_audit_chain_verify(FALSE) f
           JOIN trustride.platform_audit_chain h ON h.chain_table = f.chain_table LOOP
    INSERT INTO trustride.platform_audit_chain_seal (chain_table, head_seq, head_hash, rows_verified, first_break_seq, break_kind, verified)
    VALUES (v.chain_table, v.head_seq, v.head_hash, v.rows_verified, v.first_break_seq, v.break_kind, v.first_break_seq IS NULL);
    n := n + 1;
    IF v.first_break_seq IS NOT NULL THEN
      v_bad := concat_ws('; ', v_bad, v.chain_table || ' at ' || v.first_break_seq || ' (' || v.break_kind || ')');
    END IF;
  END LOOP;
  IF v_bad IS NOT NULL THEN
    PERFORM trustride.fn_present_notify_office('Audit chain broken', v_bad, 'PLATFORM_EXCEPTION', gen_random_uuid(), ARRAY['FOUNDER', 'ADMINISTRATOR'], TRUE);
  END IF;
  RETURN n;
END;
$function$;

-- D09 -- the rebase and the history found are themselves on the record.
SELECT trustride.fn_audit_log_append('PLATFORM_AUDIT_CHAIN', md5('platform_audit_chain')::uuid, 'CHAIN_REBASED', NULL, 'SYSTEM', NULL, NULL, NULL,
  (SELECT jsonb_build_object('finding', 'TRS026-ENG-REMEDIATION-001 D08/D09', 'chains',
     jsonb_object_agg(chain_table, jsonb_build_object('legacy_rows', legacy_rows, 'legacy_breaks', legacy_breaks, 'rebase_seq', rebase_seq) || legacy_detail))
   FROM trustride.platform_audit_chain));

-- 00:15 UTC (03:15 Africa/Nairobi), after the conformance watch.
SELECT cron.schedule('trustride_audit_chain_seal', '15 0 * * *', 'SELECT trustride.fn_platform_audit_chain_seal();');

-- Systemic guard -- a hash-chained table must be registered and guarded.
DO $patch$
DECLARE
  v_def TEXT;
  v_old TEXT := E'    AND x.grantee <> c.relowner AND x.privilege_type IN (''INSERT'', ''UPDATE'', ''DELETE'', ''TRUNCATE'');\n$function$';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_platform_conformance_violations()'::regprocedure) INTO v_def;
  IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'conformance tail not found'; END IF;
  v_def := replace(v_def, v_old, E'    AND x.grantee <> c.relowner AND x.privilege_type IN (''INSERT'', ''UPDATE'', ''DELETE'', ''TRUNCATE'')\n'
    || E'  UNION ALL\n'
    || E'  -- A hash-chained table is registered and linked, and is append-only, by the platform.\n'
    || E'  SELECT ''AUDIT_CHAIN_UNGUARDED'', c.relname::text, ''prev_hash/immutable_hash without the platform chain guard''\n'
    || E'  FROM pg_class c\n'
    || E'  WHERE c.relnamespace = ''trustride''::regnamespace AND c.relkind = ''r''\n'
    || E'    AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = ''prev_hash'' AND NOT a.attisdropped)\n'
    || E'    AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = ''immutable_hash'' AND NOT a.attisdropped)\n'
    || E'    AND NOT (EXISTS (SELECT 1 FROM trustride.platform_audit_chain h WHERE h.chain_table = c.relname)\n'
    || E'         AND EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = c.oid AND t.tgfoid = ''trustride.fn_platform_audit_chain_link''::regproc AND t.tgenabled = ''O'')\n'
    || E'         AND EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = c.oid AND t.tgfoid = ''trustride.fn_platform_audit_chain_append_only''::regproc AND t.tgenabled = ''O''));\n$function$');
  EXECUTE v_def;
END;
$patch$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
