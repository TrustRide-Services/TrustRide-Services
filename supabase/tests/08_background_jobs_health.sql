-- Suite 08 -- G9: every defined job is scheduled and runs; platform health
-- reflects what actually happened; advisory output reaches decision makers.
DO $$
DECLARE
  founder UUID; exec UUID; v JSONB; n INT; j TEXT; missing TEXT := '';
  expected TEXT[] := ARRAY['trustride_dispatch_cycle', 'trustride_actor_request_sla_sweep', 'trustride_business_dispatch_sweep',
    'trustride_cost_quote_expire_sweep', 'trustride_payment_timeout_sweep', 'trustride_integration_outbound_retry_sweep',
    'trustride_marketplace_sweep', 'trustride_telemetry_health_sweep', 'trustride_support_sla_sweep', 'trustride_orch_capacity_snapshot',
    'trustride_engine_health_record', 'trustride_orch_sla_check', 'trustride_coord_consensus_timeout', 'trustride_advisory_hourly',
    'trustride_advisory_daily', 'trustride_platform_conformance_watch', 'trustride_cron_log_trim'];
BEGIN
  founder := pg_temp.t_person('Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  exec := pg_temp.t_person('Executive', NULL);  PERFORM pg_temp.t_role(exec, 'EXECUTIVE');

  FOREACH j IN ARRAY expected LOOP
    IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = j AND active) THEN missing := missing || j || ' '; END IF;
  END LOOP;
  PERFORM pg_temp.t_check('every defined background job is scheduled and active', missing = '', missing);

  -- Each job's command executes cleanly (what cron will run).
  FOR j IN SELECT command FROM cron.job WHERE jobname LIKE 'trustride%' AND jobname <> 'trustride_cron_log_trim' LOOP
    PERFORM pg_temp.t_check('job runs: ' || left(j, 70), NOT pg_temp.t_fails(j), j);
  END LOOP;

  -- Health is computed, not asserted.
  PERFORM trustride.fn_orch_capacity_snapshot_record();
  v := trustride.fn_present_platform_health();
  PERFORM pg_temp.t_check('health snapshot recorded (no longer permanently OFFLINE)', v->>'status' IN ('HEALTHY', 'DEGRADED') AND (v->>'stale')::boolean = false, v::text);
  INSERT INTO trustride.dead_letter_review (event_id, source_engine, target_engine, failure_reason) VALUES (gen_random_uuid(), 'X', 'Y', 'test');
  PERFORM trustride.fn_orch_capacity_snapshot_record();
  v := trustride.fn_present_platform_health();
  PERFORM pg_temp.t_check('a dead-lettered signal makes health DEGRADED, with the reason', v->>'status' = 'DEGRADED' AND v::text LIKE '%DEAD_LETTERS_LAST_HOUR%', v::text);
  DELETE FROM cron.job_run_details WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'trustride_dispatch_cycle');
  PERFORM trustride.fn_orch_capacity_snapshot_record();
  v := trustride.fn_present_platform_health();
  PERFORM pg_temp.t_check('a stopped dispatch cycle shows OFFLINE (critical)', v->>'status' = 'OFFLINE' AND v::text LIKE '%DISPATCH_CYCLE_NOT_RUNNING%', v::text);
  PERFORM pg_temp.t_check('per-engine health is recorded for Engine 8/9', trustride.fn_platform_engine_health_record() >= 5);
  PERFORM pg_temp.t_check('conformance watch reports zero drift', trustride.fn_platform_conformance_watch() = 0);
  SELECT count(*) INTO n FROM trustride.fn_platform_job_health();
  PERFORM pg_temp.t_check('Office can see every job''s last run', n >= cardinality(expected), n::text);

  -- Advisory output reaches the Executive Dashboard (G19).
  INSERT INTO trustride.present_event_inbox (signal_id, correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key, emitted_at)
  VALUES (gen_random_uuid(), gen_random_uuid(), 'TRS026_ENG009_AIADV', 'TRS026_ENG011_PRESENT', 'ADVISORY_RECOMMENDATION_PUBLISHED',
    '{"recommendation_type":"CAPACITY_PLANNING","summary":"Add 3 bodas to the CBD morning shift"}', 'T-ADV-1', now());
  INSERT INTO trustride.present_event_inbox (signal_id, correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key, emitted_at)
  VALUES (gen_random_uuid(), gen_random_uuid(), 'TRS026_ENG009_AIADV', 'TRS026_ENG011_PRESENT', 'ADVISORY_ANOMALY_FLAGGED',
    '{"anomaly_type":"MARGIN_BREACH","severity":"HIGH","description":"Sedan margins below floor"}', 'T-ADV-2', now());
  PERFORM trustride.fn_present_inbox_process((SELECT signal_id FROM trustride.present_event_inbox WHERE idempotency_key = 'T-ADV-1'));
  PERFORM trustride.fn_present_inbox_process((SELECT signal_id FROM trustride.present_event_inbox WHERE idempotency_key = 'T-ADV-2'));
  PERFORM pg_temp.t_check('recommendations reach Executives and the Founder (in-app)', EXISTS (
    SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = exec AND category = 'ADVISORY' AND title LIKE 'Advisory:%')
    AND EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = founder AND category = 'ADVISORY'));
  PERFORM pg_temp.t_check('a high-severity anomaly is also sent by SMS', EXISTS (
    SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = exec AND title LIKE 'Anomaly:%' AND critical));
END;
$$;
