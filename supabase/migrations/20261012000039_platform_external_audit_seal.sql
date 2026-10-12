-- ============================================================================
-- Platform -- daily audit seals retained outside the database
-- Construction Directive WP2 (section 2.9: external audit seals)
-- ============================================================================
-- Migration 029 made every audit log a hash chain and seals the verified heads
-- daily in platform_audit_chain_seal. The database owner can still disable
-- triggers and rewrite a chain together with its in-database seals. Detecting
-- that requires each seal to be held where the database owner has no write
-- authority: an object store with immutable retention (Amazon S3 Object Lock,
-- Founder-approved), written and checked by a publisher and a verifier that run
-- in a separate administrative domain (ops/audit-seal; AWS credentials never
-- enter Supabase).
--
-- This migration is the database side only:
--   * fn_platform_audit_seal_export       -- seals not yet retained at a destination,
--                                            as a versioned record (trustride.audit-seal/v1)
--   * fn_platform_audit_seal_receipt_record -- the publisher records a retention receipt
--                                            only after the store confirmed it; the payload
--                                            hash must match the exported record
--   * fn_platform_audit_seal_event_record  -- publish failures and verification results;
--                                            failures alert the Office (critical)
--   * fn_platform_audit_chain_rows         -- chain rows with the exact canonical text the
--                                            chain trigger hashes, so the verifier recomputes
--                                            every hash itself
--   * fn_platform_audit_seal_watch (hourly) -- once a destination is activated, a seal with
--                                            no receipt after the grace period, or no passing
--                                            verification in 48 hours, alerts the Office
-- All five are callable only by service_role (the publisher and verifier), never by a
-- signed-in or anonymous user. Receipts and events are append-only.
-- Activation: AUDIT_SEAL_EXTERNAL_DESTINATION stays NOT_ACTIVATED until a real
-- bucket has retained and verified a seal end to end.
-- ============================================================================

INSERT INTO trustride.platform_configuration (config_key, config_value, environment, effective_from, changed_by)
SELECT v.k, v.v, 'ALL', now(), '00000000-0000-0000-0000-000000000000' FROM (VALUES
  ('AUDIT_SEAL_EXTERNAL_DESTINATION', 'NOT_ACTIVATED'),  -- AWS_S3_OBJECT_LOCK once provisioned and proven
  ('AUDIT_SEAL_PUBLISH_GRACE_HOURS', '6'),
  ('AUDIT_SEAL_VERIFY_MAX_AGE_HOURS', '48')
) v(k, v);

CREATE TABLE trustride.platform_audit_seal_receipt (
  receipt_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  seal_id         UUID NOT NULL REFERENCES trustride.platform_audit_chain_seal (seal_id),
  destination     TEXT NOT NULL CHECK (destination IN ('AWS_S3_OBJECT_LOCK', 'S3_COMPATIBLE_TEST')),
  bucket          TEXT NOT NULL,
  object_key      TEXT NOT NULL,
  version_id      TEXT,
  etag            TEXT,
  lock_mode       TEXT NOT NULL CHECK (lock_mode IN ('COMPLIANCE', 'GOVERNANCE')),
  retain_until    TIMESTAMPTZ NOT NULL,
  payload_sha256  CHAR(64) NOT NULL,
  recorded_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (seal_id, destination)
);
ALTER TABLE trustride.platform_audit_seal_receipt ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_platform_audit_seal_receipt_append_only BEFORE UPDATE OR DELETE ON trustride.platform_audit_seal_receipt
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_platform_audit_chain_append_only();
COMMENT ON TABLE trustride.platform_audit_seal_receipt IS
  'Proof that a daily audit seal is retained in an immutable external store (written by the publisher after the store confirmed retention). Append-only.';

CREATE TABLE trustride.platform_audit_seal_event (
  event_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type   TEXT NOT NULL CHECK (event_type IN ('PUBLISH_FAILED', 'VERIFY_PASSED', 'VERIFY_MISMATCH', 'VERIFY_MISSING_SEAL', 'VERIFY_ERROR',
                                                   'RECEIPT_MISSING', 'VERIFICATION_OVERDUE')),
  seal_id      UUID REFERENCES trustride.platform_audit_chain_seal (seal_id),
  destination  TEXT NOT NULL,
  detail       JSONB NOT NULL DEFAULT '{}'::jsonb,
  recorded_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE trustride.platform_audit_seal_event ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_platform_audit_seal_event_seal ON trustride.platform_audit_seal_event (seal_id);
CREATE TRIGGER trg_platform_audit_seal_event_append_only BEFORE UPDATE OR DELETE ON trustride.platform_audit_seal_event
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_platform_audit_chain_append_only();
COMMENT ON TABLE trustride.platform_audit_seal_event IS
  'External-seal publish failures, verification results and watchdog findings. Append-only.';

-- The versioned external seal record. Its text form (payload::text) is what the
-- publisher stores byte for byte; payload_sha256 = sha256 of that text.
CREATE FUNCTION trustride.fn_platform_audit_seal_record(p_seal_id uuid, p_environment text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
 SET timezone TO 'UTC'
AS $function$
  SELECT jsonb_build_object(
    'schema', 'trustride.audit-seal/v1',
    'environment', p_environment,
    'seal_id', s.seal_id,
    'seal_chain_seq', s.chain_seq,
    'sealed_at', s.sealed_at,
    'chain_table', s.chain_table,
    'head_seq', s.head_seq,
    'head_hash', s.head_hash,
    'rows_verified', s.rows_verified,
    'verified', s.verified,
    'first_break_seq', s.first_break_seq,
    'break_kind', s.break_kind,
    'rebase_seq', c.rebase_seq,
    'legacy_rows', c.legacy_rows,
    'seal_prev_hash', s.prev_hash,
    'seal_hash', s.immutable_hash)
  FROM trustride.platform_audit_chain_seal s JOIN trustride.platform_audit_chain c ON c.chain_table = s.chain_table
  WHERE s.seal_id = p_seal_id;
$function$;

CREATE FUNCTION trustride.fn_platform_audit_seal_export(p_destination text, p_environment text, p_limit integer DEFAULT 200)
 RETURNS TABLE(seal_id uuid, seal_chain_seq bigint, chain_table text, payload_text text, payload_sha256 text)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
 SET timezone TO 'UTC'
AS $function$
  SELECT s.seal_id, s.chain_seq, s.chain_table, r.t, encode(sha256(convert_to(r.t, 'UTF8')), 'hex')
  FROM trustride.platform_audit_chain_seal s
  CROSS JOIN LATERAL (SELECT trustride.fn_platform_audit_seal_record(s.seal_id, p_environment)::text AS t) r
  WHERE p_destination IN ('AWS_S3_OBJECT_LOCK', 'S3_COMPATIBLE_TEST')
    AND NOT EXISTS (SELECT 1 FROM trustride.platform_audit_seal_receipt x WHERE x.seal_id = s.seal_id AND x.destination = p_destination)
  ORDER BY s.chain_seq
  LIMIT greatest(least(p_limit, 1000), 1);
$function$;

CREATE FUNCTION trustride.fn_platform_audit_seal_receipt_record(p_seal_id uuid, p_destination text, p_environment text, p_bucket text,
  p_object_key text, p_version_id text, p_etag text, p_lock_mode text, p_retain_until timestamptz, p_payload_sha256 text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
 SET timezone TO 'UTC'
AS $function$
DECLARE
  v_expected TEXT;
  v_id UUID;
BEGIN
  SELECT encode(sha256(convert_to(trustride.fn_platform_audit_seal_record(p_seal_id, p_environment)::text, 'UTF8')), 'hex') INTO v_expected;
  IF v_expected IS NULL THEN RAISE EXCEPTION 'AUDIT_SEAL_UNKNOWN: no seal %', p_seal_id; END IF;
  IF v_expected <> lower(p_payload_sha256) THEN
    RAISE EXCEPTION 'AUDIT_SEAL_PAYLOAD_MISMATCH: the stored object is not the exported seal record';
  END IF;
  IF p_retain_until IS NULL OR p_retain_until <= now() THEN
    RAISE EXCEPTION 'AUDIT_SEAL_NOT_RETAINED: retention must extend into the future';
  END IF;
  INSERT INTO trustride.platform_audit_seal_receipt (seal_id, destination, bucket, object_key, version_id, etag, lock_mode, retain_until, payload_sha256)
  VALUES (p_seal_id, p_destination, p_bucket, p_object_key, p_version_id, p_etag, p_lock_mode, p_retain_until, lower(p_payload_sha256))
  RETURNING receipt_id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE FUNCTION trustride.fn_platform_audit_seal_event_record(p_event_type text, p_seal_id uuid, p_destination text, p_detail jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO trustride.platform_audit_seal_event (event_type, seal_id, destination, detail)
  VALUES (p_event_type, p_seal_id, p_destination, coalesce(p_detail, '{}'::jsonb))
  RETURNING event_id INTO v_id;
  IF p_event_type <> 'VERIFY_PASSED' THEN
    PERFORM trustride.fn_present_notify_office('Audit seal: ' || lower(replace(p_event_type, '_', ' ')),
      left(coalesce(p_detail->>'message', p_detail::text), 400) || ' (destination ' || p_destination || ')',
      'PLATFORM_EXCEPTION', coalesce(p_seal_id, v_id), ARRAY['FOUNDER', 'ADMINISTRATOR'], TRUE);
  END IF;
  RETURN v_id;
END;
$function$;

-- Rows of one chain with the exact text its trigger hashed:
-- immutable_hash = sha256(coalesce(prev_hash,'') || '|' || canonical).
CREATE FUNCTION trustride.fn_platform_audit_chain_rows(p_chain text, p_from bigint, p_to bigint)
 RETURNS TABLE(chain_seq bigint, prev_hash text, immutable_hash text, canonical text)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
 SET timezone TO 'UTC'
AS $function$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM trustride.platform_audit_chain WHERE chain_table = p_chain) THEN
    RAISE EXCEPTION 'not a registered audit chain: %', p_chain;
  END IF;
  IF p_to - p_from > 5000 THEN RAISE EXCEPTION 'at most 5000 rows per call'; END IF;
  RETURN QUERY EXECUTE format(
    'SELECT t.chain_seq, t.prev_hash::text, t.immutable_hash::text, jsonb_strip_nulls(to_jsonb(t) - ''prev_hash'' - ''immutable_hash'')::text
     FROM trustride.%I t WHERE t.chain_seq BETWEEN $1 AND $2 ORDER BY t.chain_seq', p_chain) USING p_from, p_to;
END;
$function$;

CREATE FUNCTION trustride.fn_platform_audit_seal_watch()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_dest TEXT := coalesce(trustride.fn_business_config('AUDIT_SEAL_EXTERNAL_DESTINATION'), 'NOT_ACTIVATED');
  v_grace INTEGER := coalesce(nullif(trustride.fn_business_config('AUDIT_SEAL_PUBLISH_GRACE_HOURS'), '')::int, 6);
  v_max_age INTEGER := coalesce(nullif(trustride.fn_business_config('AUDIT_SEAL_VERIFY_MAX_AGE_HOURS'), '')::int, 48);
  s RECORD;
  n INTEGER := 0;
BEGIN
  IF v_dest = 'NOT_ACTIVATED' THEN RETURN 0; END IF;
  FOR s IN SELECT x.seal_id, x.chain_table, x.sealed_at FROM trustride.platform_audit_chain_seal x
           WHERE x.sealed_at < now() - make_interval(hours => v_grace)
             AND x.sealed_at >= (SELECT min(effective_from) FROM trustride.platform_configuration
                                 WHERE config_key = 'AUDIT_SEAL_EXTERNAL_DESTINATION' AND config_value = v_dest)
             AND NOT EXISTS (SELECT 1 FROM trustride.platform_audit_seal_receipt r WHERE r.seal_id = x.seal_id AND r.destination = v_dest)
             AND NOT EXISTS (SELECT 1 FROM trustride.platform_audit_seal_event e WHERE e.seal_id = x.seal_id AND e.event_type = 'RECEIPT_MISSING' AND e.destination = v_dest)
  LOOP
    PERFORM trustride.fn_platform_audit_seal_event_record('RECEIPT_MISSING', s.seal_id, v_dest,
      jsonb_build_object('message', 'Seal of ' || s.chain_table || ' at ' || s.sealed_at || ' has no external retention receipt after ' || v_grace || ' hours'));
    n := n + 1;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM trustride.platform_audit_seal_event WHERE event_type = 'VERIFY_PASSED' AND destination = v_dest
                 AND recorded_at > now() - make_interval(hours => v_max_age))
     AND NOT EXISTS (SELECT 1 FROM trustride.platform_audit_seal_event WHERE event_type = 'VERIFICATION_OVERDUE' AND destination = v_dest
                 AND recorded_at > now() - interval '24 hours') THEN
    PERFORM trustride.fn_platform_audit_seal_event_record('VERIFICATION_OVERDUE', NULL, v_dest,
      jsonb_build_object('message', 'No passing external seal verification in the last ' || v_max_age || ' hours'));
    n := n + 1;
  END IF;
  RETURN n;
END;
$function$;

SELECT cron.schedule('trustride_audit_seal_watch', '40 * * * *', 'SELECT trustride.fn_platform_audit_seal_watch();');

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_platform_audit_seal_export(text, text, integer) TO service_role;
GRANT EXECUTE ON FUNCTION trustride.fn_platform_audit_seal_receipt_record(uuid, text, text, text, text, text, text, text, timestamptz, text) TO service_role;
GRANT EXECUTE ON FUNCTION trustride.fn_platform_audit_seal_event_record(text, uuid, text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION trustride.fn_platform_audit_chain_rows(text, bigint, bigint) TO service_role;
SELECT trustride.fn_platform_conformance_assert();
