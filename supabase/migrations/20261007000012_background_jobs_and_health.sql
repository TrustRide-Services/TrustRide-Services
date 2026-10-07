-- ============================================================================
-- Background processing and honest platform health -- Engines 7, 8, 9, 11
-- Implementation Completion G9, Sec.17, G19 (advisory output reaches people)
-- ============================================================================
-- Every job a TrustRide engine defines is now either scheduled here (or by
-- the stage that introduced it) -- none is left as dead configuration:
--
--   job                                   schedule       introduced
--   trustride_dispatch_cycle              10 seconds     Engine 7
--   trustride_actor_request_sla_sweep     */15 min       Engine 4 v3
--   trustride_business_dispatch_sweep     every minute   order lifecycle
--   trustride_cost_quote_expire_sweep     every minute   order lifecycle
--   trustride_payment_timeout_sweep       every minute   payments
--   trustride_integration_outbound_retry  every minute   integration gateway
--   trustride_marketplace_sweep           */5 min        marketplace
--   trustride_telemetry_health_sweep      */2 min        telemetry
--   trustride_support_sla_sweep           */5 min        support
--   trustride_orch_capacity_snapshot      every minute   HERE (health)
--   trustride_engine_health_record        */5 min        HERE (per-engine health)
--   trustride_orch_sla_check              */5 min        HERE
--   trustride_coord_consensus_timeout     every minute   HERE
--   trustride_advisory_hourly             hourly         HERE (7 Engine 9 sweeps)
--   trustride_advisory_daily              02:00 EAT      HERE (2 Engine 9 sweeps)
--   trustride_platform_conformance_watch  daily 03:00    HERE
--
-- And the health snapshot stops claiming HEALTHY unconditionally: it is
-- computed from what actually ran.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Honest health
-- ---------------------------------------------------------------------------
ALTER TABLE trustride.orch_capacity_snapshot ADD COLUMN health_detail JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE OR REPLACE FUNCTION trustride.fn_orch_capacity_snapshot_record()
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_active_partitions INTEGER;
  v_total_depth INTEGER;
  v_in_flight INTEGER;
  v_last_cycle TIMESTAMPTZ;
  v_oldest_pending TIMESTAMPTZ;
  v_dead_1h INTEGER;
  v_failed_jobs INTEGER;
  v_open_circuits TEXT[];
  v_waiting_config INTEGER;
  v_status TEXT := 'HEALTHY';
  v_reasons TEXT[] := ARRAY[]::TEXT[];
  v_id UUID;
  v_union TEXT;
BEGIN
  SELECT count(*) INTO v_active_partitions FROM trustride.orch_queue_partition WHERE partition_status = 'ACTIVE';
  SELECT count(*) INTO v_total_depth FROM trustride.orch_signal_queue WHERE queue_status = 'QUEUED';
  SELECT count(*) INTO v_in_flight FROM trustride.orch_signal_queue WHERE queue_status IN ('LEASED', 'DISPATCHED');

  -- Is the dispatch cycle actually running?
  SELECT max(d.end_time) INTO v_last_cycle FROM cron.job_run_details d JOIN cron.job j ON j.jobid = d.jobid
  WHERE j.jobname = 'trustride_dispatch_cycle' AND d.status = 'succeeded';
  -- Oldest signal still waiting to be routed.
  SELECT string_agg(format('SELECT min(emitted_at) AS t FROM trustride.%I WHERE signal_status = ''PENDING''', outbox_table_name), ' UNION ALL ')
  INTO v_union FROM trustride.orch_outbox_registry WHERE active;
  IF v_union IS NOT NULL THEN
    EXECUTE 'SELECT min(t) FROM (' || v_union || ') x' INTO v_oldest_pending;
  END IF;
  SELECT count(*) INTO v_dead_1h FROM trustride.dead_letter_review WHERE created_at > now() - interval '1 hour';
  SELECT count(*) INTO v_failed_jobs FROM cron.job_run_details d JOIN cron.job j ON j.jobid = d.jobid
  WHERE j.jobname LIKE 'trustride%' AND d.status = 'failed' AND d.start_time > now() - interval '15 minutes';
  SELECT array_agg(port_code::text) INTO v_open_circuits FROM trustride.integration_circuit_breaker_state WHERE state = 'OPEN';
  SELECT count(*) INTO v_waiting_config FROM trustride.integration_outbound_request WHERE status = 'WAITING_CONFIGURATION';

  IF v_last_cycle IS NULL OR v_last_cycle < now() - interval '5 minutes' THEN
    v_status := 'CRITICAL'; v_reasons := array_append(v_reasons, 'DISPATCH_CYCLE_NOT_RUNNING');
  END IF;
  IF v_oldest_pending < now() - interval '2 minutes' THEN
    v_reasons := array_append(v_reasons, 'SIGNAL_BACKLOG');
  END IF;
  IF v_dead_1h > 0 THEN v_reasons := array_append(v_reasons, ('DEAD_LETTERS_LAST_HOUR:' || v_dead_1h)); END IF;
  IF v_failed_jobs > 0 THEN v_reasons := array_append(v_reasons, ('FAILED_JOB_RUNS_15MIN:' || v_failed_jobs)); END IF;
  IF cardinality(coalesce(v_open_circuits, ARRAY[]::TEXT[])) > 0 THEN v_reasons := array_append(v_reasons, ('OPEN_CIRCUITS:' || array_to_string(v_open_circuits, ','))); END IF;
  IF v_waiting_config > 0 THEN v_reasons := array_append(v_reasons, ('INTEGRATIONS_AWAITING_CONFIGURATION:' || v_waiting_config)); END IF;
  IF v_status = 'HEALTHY' AND cardinality(v_reasons) > 0 THEN v_status := 'DEGRADED'; END IF;

  INSERT INTO trustride.orch_capacity_snapshot (active_partitions, total_queue_depth, signals_in_flight, runtime_health_status, snapshot_at, health_detail)
  VALUES (v_active_partitions, v_total_depth, v_in_flight, v_status, clock_timestamp(), jsonb_build_object(
    'reasons', to_jsonb(v_reasons), 'last_dispatch_cycle_at', v_last_cycle, 'oldest_pending_signal_at', v_oldest_pending,
    'dead_letters_last_hour', v_dead_1h, 'failed_job_runs_15min', v_failed_jobs, 'open_circuits', to_jsonb(coalesce(v_open_circuits, ARRAY[]::TEXT[])),
    'integrations_awaiting_configuration', v_waiting_config))
  RETURNING capacity_snapshot_id INTO v_id;

  -- Keep the snapshot table small: the latest day is enough for the surfaces.
  DELETE FROM trustride.orch_capacity_snapshot WHERE snapshot_at < now() - interval '1 day';
  RETURN v_id;
END;
$$;

-- Engine 11's bridge: CRITICAL now maps to OFFLINE and the reasons travel.
CREATE OR REPLACE FUNCTION trustride.fn_present_platform_health()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT coalesce((
    SELECT jsonb_build_object('status', CASE runtime_health_status WHEN 'HEALTHY' THEN 'HEALTHY' WHEN 'DEGRADED' THEN 'DEGRADED' ELSE 'OFFLINE' END,
      'as_of', snapshot_at, 'stale', snapshot_at < now() - interval '3 minutes', 'detail', health_detail,
      'queue_depth', total_queue_depth, 'in_flight', signals_in_flight)
    FROM trustride.orch_capacity_snapshot ORDER BY snapshot_at DESC LIMIT 1),
    jsonb_build_object('status', 'OFFLINE', 'as_of', NULL, 'stale', TRUE, 'detail', jsonb_build_object('reasons', jsonb_build_array('NO_HEALTH_SNAPSHOT_YET'))));
$$;

-- Per-engine health (feeds Engine 8's coordination health and Engine 9's
-- coordination-health sweep): rejected or dead-lettered signals per engine
-- in the last hour, out of everything that engine received.
CREATE OR REPLACE FUNCTION trustride.fn_platform_engine_health_record()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  r RECORD;
  v_total INTEGER;
  v_bad INTEGER;
  v_score NUMERIC;
  n INTEGER := 0;
BEGIN
  FOR r IN SELECT DISTINCT engine_code, inbox_table_name FROM (
      SELECT target_engine AS engine_code,
        (SELECT destination_inbox_table FROM trustride.orch_destination_cache c WHERE c.destination_engine_code = rr.target_engine LIMIT 1) AS inbox_table_name
      FROM trustride.routing_rule rr WHERE rr.active) x WHERE inbox_table_name IS NOT NULL LOOP
    EXECUTE format('SELECT count(*), count(*) FILTER (WHERE signal_status IN (''REJECTED'', ''DEAD_LETTER'')) FROM trustride.%I WHERE received_at > now() - interval ''1 hour''',
      r.inbox_table_name) INTO v_total, v_bad;
    v_score := CASE WHEN v_total = 0 THEN 100 ELSE round(100.0 * (v_total - v_bad) / v_total, 2) END;
    PERFORM trustride.fn_coord_coordination_health_record(r.engine_code, v_score,
      (CASE WHEN v_score >= 95 THEN 'HEALTHY' WHEN v_score >= 80 THEN 'DEGRADED' ELSE 'CRITICAL' END)::trustride.coord_health_status_enum);
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;

-- What every scheduled job last did (Office health surface).
CREATE OR REPLACE FUNCTION trustride.fn_platform_job_health()
RETURNS TABLE (jobname TEXT, schedule TEXT, active BOOLEAN, last_run_at TIMESTAMPTZ, last_status TEXT, last_message TEXT, failures_24h BIGINT, runs_24h BIGINT)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT j.jobname::text, j.schedule::text, j.active,
    (SELECT d.start_time FROM cron.job_run_details d WHERE d.jobid = j.jobid ORDER BY d.start_time DESC LIMIT 1),
    (SELECT d.status::text FROM cron.job_run_details d WHERE d.jobid = j.jobid ORDER BY d.start_time DESC LIMIT 1),
    (SELECT left(d.return_message, 200) FROM cron.job_run_details d WHERE d.jobid = j.jobid ORDER BY d.start_time DESC LIMIT 1),
    (SELECT count(*) FROM cron.job_run_details d WHERE d.jobid = j.jobid AND d.status = 'failed' AND d.start_time > now() - interval '24 hours'),
    (SELECT count(*) FROM cron.job_run_details d WHERE d.jobid = j.jobid AND d.start_time > now() - interval '24 hours')
  FROM cron.job j WHERE j.jobname LIKE 'trustride%' ORDER BY j.jobname;
$$;

-- The standing conformance check, at runtime: a drift (a grant, a policy, a
-- PUBLIC function) introduced outside the migration chain is reported.
CREATE OR REPLACE FUNCTION trustride.fn_platform_conformance_watch()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_n INTEGER;
  v_list TEXT;
BEGIN
  SELECT count(*), string_agg(check_code || ':' || object_name, ', ') INTO v_n, v_list FROM trustride.fn_platform_conformance_violations();
  IF v_n > 0 THEN
    PERFORM trustride.fn_present_notify_office('Platform conformance drift (' || v_n || ')', left(v_list, 500), 'PLATFORM_EXCEPTION', gen_random_uuid());
  END IF;
  RETURN v_n;
END;
$$;

-- The nine Engine 9 sweeps, grouped by cadence. Each runs in its own
-- sub-transaction: one failing model never stops the others.
CREATE OR REPLACE FUNCTION trustride.fn_advisory_run_sweeps(p_cadence TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_fn TEXT;
  v_out JSONB := '{}'::jsonb;
  v_n INTEGER;
BEGIN
  FOREACH v_fn IN ARRAY CASE p_cadence
    WHEN 'HOURLY' THEN ARRAY['fn_advisory_demand_sweep', 'fn_advisory_revenue_sweep', 'fn_advisory_service_mix_sweep',
      'fn_advisory_payment_success_rate_sweep', 'fn_advisory_external_reliability_sweep', 'fn_advisory_routing_capacity_sweep',
      'fn_advisory_coordination_health_sweep']
    WHEN 'DAILY' THEN ARRAY['fn_advisory_capacity_planning_sweep', 'fn_advisory_fleet_replacement_sweep']
    ELSE ARRAY[]::TEXT[] END
  LOOP
    BEGIN
      EXECUTE format('SELECT trustride.%I()', v_fn) INTO v_n;
      v_out := v_out || jsonb_build_object(v_fn, v_n);
    EXCEPTION WHEN OTHERS THEN
      v_out := v_out || jsonb_build_object(v_fn, 'ERROR: ' || SQLERRM);
      PERFORM trustride.fn_present_notify_office('Advisory sweep failed: ' || v_fn, left(SQLERRM, 300), 'PLATFORM_EXCEPTION', gen_random_uuid());
    END;
  END LOOP;
  RETURN v_out;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Schedules
-- ---------------------------------------------------------------------------
SELECT cron.schedule('trustride_orch_capacity_snapshot', '* * * * *', 'SELECT trustride.fn_orch_capacity_snapshot_record();');
SELECT cron.schedule('trustride_engine_health_record', '*/5 * * * *', 'SELECT trustride.fn_platform_engine_health_record();');
SELECT cron.schedule('trustride_orch_sla_check', '*/5 * * * *', 'SELECT trustride.fn_orch_sla_check_sweep();');
SELECT cron.schedule('trustride_coord_consensus_timeout', '* * * * *', 'SELECT trustride.fn_coord_consensus_timeout_sweep();');
SELECT cron.schedule('trustride_advisory_hourly', '7 * * * *', 'SELECT trustride.fn_advisory_run_sweeps(''HOURLY'');');
SELECT cron.schedule('trustride_advisory_daily', '0 23 * * *', 'SELECT trustride.fn_advisory_run_sweeps(''DAILY'');');   -- 02:00 Africa/Nairobi
SELECT cron.schedule('trustride_platform_conformance_watch', '0 0 * * *', 'SELECT trustride.fn_platform_conformance_watch();');  -- 03:00 Africa/Nairobi
-- Keep cron's own run log from growing without bound.
SELECT cron.schedule('trustride_cron_log_trim', '30 0 * * *', $$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '7 days'$$);

-- ---------------------------------------------------------------------------
-- 3. Advisory output reaches the Executive Dashboard (G19)
-- ---------------------------------------------------------------------------
DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_present_inbox_process(uuid)'::regprocedure) INTO v_def;
  IF position('fn_office_recipients(ARRAY[''FOUNDER'', ''EXECUTIVE''])' IN v_def) = 0 THEN
    v_def := replace(v_def,
      E'    WHEN ''ADVISORY_RECOMMENDATION_PUBLISHED'' THEN\n      NULL; -- no recipient carried; rendered as an aggregate Executive_Dashboard feed once built',
      E'    WHEN ''ADVISORY_RECOMMENDATION_PUBLISHED'' THEN\n'
      || E'      -- Advice is non-authoritative: in-app only, to the people who decide.\n'
      || E'      INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, source_signal_correlation_id, category, external_channels)\n'
      || E'      SELECT r, ''TRUSTRIDE_OFFICE'', ''EXECUTIVE_DASHBOARD'', ''Advisory: '' || lower(replace(coalesce(v_payload->>''recommendation_type'', ''recommendation''), ''_'', '' '')),\n'
      || E'        left(coalesce(v_payload->>''summary'', v_payload->''recommendation_payload''->>''summary'', ''A new recommendation is waiting for a decision.''), 300), v_correlation_id, ''ADVISORY'', ARRAY[]::TEXT[]\n'
      || E'      FROM trustride.fn_office_recipients(ARRAY[''FOUNDER'', ''EXECUTIVE'']) r;');
    v_def := replace(v_def,
      E'    WHEN ''ADVISORY_ANOMALY_FLAGGED'' THEN\n      NULL; -- same as above',
      E'    WHEN ''ADVISORY_ANOMALY_FLAGGED'' THEN\n'
      || E'      INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, source_signal_correlation_id, category, external_channels, critical)\n'
      || E'      SELECT r, ''TRUSTRIDE_OFFICE'', ''EXECUTIVE_DASHBOARD'', ''Anomaly: '' || lower(replace(coalesce(v_payload->>''anomaly_type'', ''detected''), ''_'', '' '')),\n'
      || E'        left(coalesce(v_payload->>''description'', ''An anomaly was flagged by the advisory engine.''), 300), v_correlation_id, ''ADVISORY'',\n'
      || E'        CASE WHEN v_payload->>''severity'' IN (''HIGH'', ''CRITICAL'') THEN ARRAY[''SMS'']::TEXT[] ELSE ARRAY[]::TEXT[] END, v_payload->>''severity'' IN (''HIGH'', ''CRITICAL'')\n'
      || E'      FROM trustride.fn_office_recipients(ARRAY[''FOUNDER'', ''EXECUTIVE'', ''ADMINISTRATOR'']) r;');
    IF position('fn_office_recipients(ARRAY[''FOUNDER'', ''EXECUTIVE''])' IN v_def) = 0 OR position('Anomaly: ' IN v_def) = 0 THEN
      RAISE EXCEPTION 'presentation advisory patch did not apply';
    END IF;
    EXECUTE v_def;
  END IF;
END;
$patch$;

-- ---------------------------------------------------------------------------
-- 4. Grants
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;

SELECT trustride.fn_platform_conformance_assert();
