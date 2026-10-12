-- Suite 25 -- the database side of the external audit seal (Construction Directive WP2).
-- A seal is exported as a versioned record; a receipt is accepted only for that exact record
-- and a retention date in the future; failures alert the Office; the verifier can recompute
-- every chain hash from the rows; only service_role reaches these functions; the watchdog is
-- silent until a destination is activated and then alerts on a missing receipt.
DO $$
DECLARE
  founder UUID; n INT; m INT; v TEXT; ok BOOLEAN; rec RECORD; seal UUID; e UUID;
BEGIN
  founder := pg_temp.t_person('Seal Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  PERFORM trustride.fn_model_decision_log_write(NULL, 'SEAL_PROBE', 'suite 25');
  n := trustride.fn_platform_audit_chain_seal();

  -- ============ export
  SELECT * INTO rec FROM trustride.fn_platform_audit_seal_export('S3_COMPATIBLE_TEST', 'suite25')
  WHERE chain_table = 'model_decision_log' ORDER BY seal_chain_seq DESC LIMIT 1;
  PERFORM pg_temp.t_check('export: today''s model_decision_log seal is offered as a versioned record',
    rec.seal_id IS NOT NULL AND (rec.payload_text::jsonb)->>'schema' = 'trustride.audit-seal/v1'
    AND (rec.payload_text::jsonb)->>'head_hash' = (SELECT head_hash FROM trustride.platform_audit_chain WHERE chain_table = 'model_decision_log'),
    left(coalesce(rec.payload_text, 'none'), 160));
  PERFORM pg_temp.t_check('export: payload_sha256 is the sha256 of the exact text', rec.payload_sha256 = encode(sha256(convert_to(rec.payload_text, 'UTF8')), 'hex'));

  -- ============ receipts
  BEGIN PERFORM trustride.fn_platform_audit_seal_receipt_record(rec.seal_id, 'S3_COMPATIBLE_TEST', 'suite25', 'b', 'k', 'v1', 'e', 'COMPLIANCE', now() + interval '1 day', repeat('0', 64));
    ok := false; EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'AUDIT_SEAL_PAYLOAD_MISMATCH%'; END;
  PERFORM pg_temp.t_check('receipt refused when the stored object is not the exported record', ok);
  BEGIN PERFORM trustride.fn_platform_audit_seal_receipt_record(rec.seal_id, 'S3_COMPATIBLE_TEST', 'suite25', 'b', 'k', 'v1', 'e', 'COMPLIANCE', now() - interval '1 second', rec.payload_sha256);
    ok := false; EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'AUDIT_SEAL_NOT_RETAINED%'; END;
  PERFORM pg_temp.t_check('receipt refused without retention into the future', ok);
  PERFORM trustride.fn_platform_audit_seal_receipt_record(rec.seal_id, 'S3_COMPATIBLE_TEST', 'suite25', 'b', 'k', 'v1', 'e', 'COMPLIANCE', now() + interval '1 day', rec.payload_sha256);
  SELECT count(*) INTO n FROM trustride.fn_platform_audit_seal_export('S3_COMPATIBLE_TEST', 'suite25') WHERE seal_id = rec.seal_id;
  PERFORM pg_temp.t_check('a receipted seal is no longer offered for that destination', n = 0, n::text);
  BEGIN UPDATE trustride.platform_audit_seal_receipt SET bucket = 'x' WHERE seal_id = rec.seal_id; ok := false;
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%append-only%'; END;
  PERFORM pg_temp.t_check('receipts are append-only', ok);

  -- ============ events alert the Office
  e := trustride.fn_platform_audit_seal_event_record('PUBLISH_FAILED', rec.seal_id, 'S3_COMPATIBLE_TEST', '{"message":"suite 25 simulated failure"}');
  PERFORM pg_temp.t_check('a publish failure is recorded and alerts the Office (critical)',
    EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = founder AND critical AND title ILIKE 'Audit seal: publish failed%'));

  -- ============ the verifier can recompute every hash from the rows
  SELECT count(*), count(*) FILTER (WHERE encode(sha256(convert_to(coalesce(prev_hash, '') || '|' || canonical, 'UTF8')), 'hex') = immutable_hash)
  INTO n, m FROM trustride.fn_platform_audit_chain_rows('model_decision_log',
    (SELECT rebase_seq + 1 FROM trustride.platform_audit_chain WHERE chain_table = 'model_decision_log'),
    (SELECT head_seq FROM trustride.platform_audit_chain WHERE chain_table = 'model_decision_log'));
  PERFORM pg_temp.t_check('chain rows: sha256(prev | canonical) reproduces every stored hash', n > 0 AND n = m, m || ' of ' || n);

  -- ============ authority
  SELECT bool_and(NOT has_function_privilege(r, f, 'EXECUTE')) INTO ok
  FROM unnest(ARRAY['anon', 'authenticated', 'trustride_authenticated']) r,
       unnest(ARRAY['trustride.fn_platform_audit_seal_export(text,text,integer)',
                    'trustride.fn_platform_audit_seal_receipt_record(uuid,text,text,text,text,text,text,text,timestamptz,text)',
                    'trustride.fn_platform_audit_seal_event_record(text,uuid,text,jsonb)',
                    'trustride.fn_platform_audit_chain_rows(text,bigint,bigint)']) f;
  PERFORM pg_temp.t_check('no signed-in or anonymous role can call the seal functions', ok);
  PERFORM pg_temp.t_check('service_role can call the seal functions',
    has_function_privilege('service_role', 'trustride.fn_platform_audit_seal_export(text,text,integer)', 'EXECUTE')
    AND has_function_privilege('service_role', 'trustride.fn_platform_audit_chain_rows(text,bigint,bigint)', 'EXECUTE'));

  -- ============ watchdog
  n := trustride.fn_platform_audit_seal_watch();
  PERFORM pg_temp.t_check('watchdog is silent while no destination is activated (and claims nothing)',
    (trustride.fn_business_config('AUDIT_SEAL_EXTERNAL_DESTINATION') = 'NOT_ACTIVATED' AND n = 0)
    OR trustride.fn_business_config('AUDIT_SEAL_EXTERNAL_DESTINATION') <> 'NOT_ACTIVATED', n::text);
  INSERT INTO trustride.platform_configuration (config_key, config_value, environment, effective_from, changed_by)
  VALUES ('AUDIT_SEAL_EXTERNAL_DESTINATION', 'AWS_S3_OBJECT_LOCK', 'ALL', now(), founder),
         ('AUDIT_SEAL_PUBLISH_GRACE_HOURS', '-1', 'ALL', now(), founder);
  n := trustride.fn_platform_audit_seal_watch();
  SELECT count(*) INTO m FROM trustride.platform_audit_seal_event WHERE event_type = 'RECEIPT_MISSING' AND destination = 'AWS_S3_OBJECT_LOCK' AND recorded_at = now();
  PERFORM pg_temp.t_check('once activated, a seal with no external receipt is reported (and the Office alerted)', m >= 1
    AND EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = founder AND title ILIKE 'Audit seal: receipt missing%'), m::text);
  PERFORM pg_temp.t_check('once activated, the absence of a passing verification is reported',
    EXISTS (SELECT 1 FROM trustride.platform_audit_seal_event WHERE event_type = 'VERIFICATION_OVERDUE' AND recorded_at = now()));
  n := trustride.fn_platform_audit_seal_watch();
  SELECT count(*) INTO n FROM trustride.platform_audit_seal_event WHERE event_type = 'RECEIPT_MISSING' AND recorded_at = now();
  PERFORM pg_temp.t_check('the watchdog reports each missing receipt once', n = m, n || ' vs ' || m);
  PERFORM pg_temp.t_check('the watch runs hourly', EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'trustride_audit_seal_watch'));
END
$$;
