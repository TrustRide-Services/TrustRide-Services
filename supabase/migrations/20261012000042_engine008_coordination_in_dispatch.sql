-- ============================================================================
-- Engines 7 and 8 -- coordinated executions pass through Engine 8, enforced
-- Construction Directive WP4 (section 2.2)
-- ============================================================================
-- Specification: Engine 7 decides when and in what order a signal moves;
-- Engine 8 decides whether the distributed execution it belongs to may
-- proceed and when it is truly finished. "No fan-out or fan-in signal
-- completes without passing through Engine 8; no one-to-one signal needs to"
-- (Engine 8 blueprint 1.1; Engine 7 blueprint 774).
--
-- Found (WP4 inventory, 2026-10-12): the dispatch cycle called
-- fn_coord_admission_check for every signal and IGNORED its answer (a DEFERRED
-- signal was dispatched anyway); 14 of Engine 8's 18 runtime functions were
-- never called; Engine 5 pricing depended on two signals (service context from
-- Engine 3, dispatch from Engine 2) with no governed dependency -- a dispatch
-- arriving first failed the order with NO_SERVICE_CONTEXT_CACHED.
--
-- Interpretation recorded (specification gap): the blueprints say the routing
-- rule marks a signal one-to-many or many-to-one, but Foundation's routing_rule
-- (FDN-001) carries no such column. Engine 8's own coord_admission_policy is the
-- existing per-signal-type declaration of coordination requirements; a signal
-- type with a policy row is coordinated. No Foundation table is altered.
--
-- Correction (Engine 8 owns every new object; no domain engine's business
-- logic moves):
--   * coord_admission_policy declares the six fan-out executions found in the
--     inventory and the one fan-in dependency;
--   * coord_dependency_rule declares prerequisites per signal type and
--     destination: RESOURCE_DISPATCH_INITIATED -> Engine 5 requires
--     SERVICE_CONTEXT_RESOLVED -> Engine 5 for the same correlation;
--   * fn_coord_govern -- admission (once per signal), exactly-once fingerprint,
--     workflow instance and stage per correlation, dependency hold / release /
--     failure / timeout, consensus hold / commit / abort / not-opened timeout.
--     Re-evaluation of a held signal writes nothing until its state changes;
--   * fn_coord_finalize -- after the destination handler: stage completed or
--     failed, execution completion (certificate when completed), release back to
--     Engine 7; a failed branch fails the workflow, opens a TERMINATE recovery
--     record and a runtime alert (partial completion is never silent);
--   * fn_orch_dispatch_cycle -- calls fn_coord_govern before anything else for a
--     discovered signal: HELD stays PENDING (decided again next cycle, nothing
--     written); a coordination refusal ends DEAD_LETTER with the reason, a
--     dead-letter review row and an Office alert; ADMITTED or DIRECT continues
--     as before. The unconditional admission call is removed (one-to-one
--     signals no longer enter Engine 8, as specified). fn_coord_finalize runs
--     after every handler outcome.
-- ============================================================================

INSERT INTO trustride.platform_configuration (config_key, config_value, environment, effective_from, changed_by)
SELECT 'COORD_FAN_IN_TIMEOUT_SEC', '300', 'ALL', now(), '00000000-0000-0000-0000-000000000000'
WHERE NOT EXISTS (SELECT 1 FROM trustride.platform_configuration WHERE config_key = 'COORD_FAN_IN_TIMEOUT_SEC');

-- The fan-out executions (one emission, several receiving engines) and the fan-in.
INSERT INTO trustride.coord_admission_policy (signal_type, mandatory_validation, dependency_check_required, consensus_required, active)
VALUES ('ORDER_PLACED', TRUE, FALSE, FALSE, TRUE),                  -- with SERVICE_LOOKUP_REQUESTED (fn_business_order_place)
       ('SERVICE_RESOLVED', TRUE, FALSE, FALSE, TRUE),              -- with SERVICE_CONTEXT_RESOLVED (fn_service_lookup_requested_accept)
       ('SERVICE_CONTEXT_RESOLVED', TRUE, FALSE, FALSE, TRUE),
       ('RESOURCE_ASSIGNED', TRUE, FALSE, FALSE, TRUE),             -- with RESOURCE_DISPATCH_INITIATED (fn_resource_assign)
       ('RESOURCE_DISPATCH_INITIATED', TRUE, TRUE, FALSE, TRUE),    -- fan-in: needs the service context
       ('OBJECT_VERIFICATION_UPDATED', TRUE, FALSE, FALSE, TRUE),   -- with FLEET_VERIFICATION_UPDATED (fn_integration_fleet_verification_requested_accept)
       ('ADVISORY_ANOMALY_FLAGGED', TRUE, FALSE, FALSE, TRUE)       -- to Engines 8 and 11 (fn_advisory_inbox_process)
ON CONFLICT (signal_type) DO UPDATE SET dependency_check_required = EXCLUDED.dependency_check_required, active = TRUE;
-- Already declared since Engine 8's first build: SERVICE_LOOKUP_REQUESTED, FLEET_VERIFICATION_UPDATED,
-- MARKETPLACE_LISTING_SOLD (to Engines 2 and 4), RESOURCE_MARKETPLACE_ITEM_READY, ASSIGNMENT_REQUESTED,
-- JOB_COMPLETED, VENDOR_VERIFICATION_UPDATED.

CREATE TABLE trustride.coord_dependency_rule (
  dependency_rule_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_type                      TEXT NOT NULL,
  destination_engine_code          TEXT NOT NULL,
  prerequisite_signal_type         TEXT NOT NULL,
  prerequisite_destination_engine  TEXT NOT NULL,
  hold_timeout_seconds             INTEGER NOT NULL DEFAULT 300 CHECK (hold_timeout_seconds >= 0),
  active                           BOOLEAN NOT NULL DEFAULT TRUE,
  created_at                       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (signal_type, destination_engine_code, prerequisite_signal_type)
);
ALTER TABLE trustride.coord_dependency_rule ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE trustride.coord_dependency_rule IS
  '[Engine 8 2.4-2.6] A signal to this destination is held until the prerequisite signal for the same correlation has been ACCEPTED by its destination; refused if the prerequisite was refused; refused after hold_timeout_seconds.';
INSERT INTO trustride.coord_dependency_rule (signal_type, destination_engine_code, prerequisite_signal_type, prerequisite_destination_engine, hold_timeout_seconds)
VALUES ('RESOURCE_DISPATCH_INITIATED', 'TRS026_ENG005_COST', 'SERVICE_CONTEXT_RESOLVED', 'TRS026_ENG005_COST', 300);

CREATE FUNCTION trustride.fn_coord_govern(p_signal_id uuid, p_correlation_id uuid, p_signal_type text, p_source_engine text,
  p_destination_engine text, p_payload jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_policy RECORD; v_sess RECORD; v_wf UUID; v_rule RECORD; v_inbox TEXT; v_pre_status TEXT; v_pre_signal UUID;
  v_graph UUID; v_cons RECORD; v_decision TEXT; v_timeout INTEGER;
BEGIN
  SELECT * INTO v_policy FROM trustride.coord_admission_policy WHERE signal_type = p_signal_type AND active;
  IF v_policy IS NULL THEN RETURN 'DIRECT'; END IF;   -- one-to-one: Engine 7 alone

  SELECT * INTO v_sess FROM trustride.coord_admission_session WHERE signal_id = p_signal_id ORDER BY started_at LIMIT 1;
  IF v_sess IS NULL THEN
    INSERT INTO trustride.coord_admission_session (signal_id, correlation_id, source_engine_code, destination_engine_code, admission_policy_id)
    VALUES (p_signal_id, p_correlation_id, p_source_engine, coalesce(p_destination_engine, 'UNKNOWN'), v_policy.admission_policy_id)
    RETURNING * INTO v_sess;
    -- Exactly once: the same business content for the same destination and correlation executes once.
    IF trustride.fn_coord_execution_fingerprint_check(p_correlation_id, p_signal_id,
         p_signal_type || '|' || coalesce(p_destination_engine, '') || '|' || coalesce(p_payload::text, '')) THEN
      UPDATE trustride.coord_admission_session SET session_status = 'REJECTED', completed_at = now() WHERE admission_session_id = v_sess.admission_session_id;
      INSERT INTO trustride.coord_admission_decision (admission_session_id, decision, decision_reason)
      VALUES (v_sess.admission_session_id, 'REJECTED', 'DUPLICATE_EXECUTION');
      RETURN 'DEAD:DUPLICATE_EXECUTION: the same ' || p_signal_type || ' for this correlation was already executed';
    END IF;
    -- Context: one workflow instance per correlation; one stage per coordinated delivery.
    SELECT workflow_instance_id INTO v_wf FROM trustride.coord_workflow_instance WHERE correlation_id = p_correlation_id ORDER BY started_at LIMIT 1;
    IF v_wf IS NULL THEN v_wf := trustride.fn_coord_workflow_instance_start('COORDINATED_EXECUTION', p_correlation_id); END IF;
    PERFORM trustride.fn_coord_workflow_stage_enter(v_wf,
      ((SELECT count(*) FROM trustride.coord_workflow_stage WHERE workflow_instance_id = v_wf) + 1)::smallint, p_signal_type, coalesce(p_destination_engine, 'UNKNOWN'));
    PERFORM trustride.fn_coord_execution_state_set(v_sess.admission_session_id, coalesce(p_destination_engine, 'UNKNOWN'), 'ADMISSION');
  END IF;

  IF v_sess.session_status = 'ADMITTED' THEN RETURN 'ADMITTED'; END IF;
  IF v_sess.session_status = 'REJECTED' THEN
    RETURN 'DEAD:' || coalesce((SELECT decision_reason FROM trustride.coord_admission_decision WHERE admission_session_id = v_sess.admission_session_id
                                ORDER BY decided_at DESC LIMIT 1), 'refused by coordination');
  END IF;

  -- Dependency governance.
  FOR v_rule IN SELECT * FROM trustride.coord_dependency_rule WHERE signal_type = p_signal_type AND destination_engine_code = p_destination_engine AND active LOOP
    SELECT destination_inbox_table INTO v_inbox FROM trustride.orch_destination_cache WHERE destination_engine_code = v_rule.prerequisite_destination_engine LIMIT 1;
    v_pre_status := NULL; v_pre_signal := NULL;
    IF v_inbox IS NOT NULL THEN
      EXECUTE format('SELECT signal_status::text, signal_id FROM trustride.%I WHERE correlation_id = $1 AND signal_type = $2
                      ORDER BY (signal_status::text = ''ACCEPTED'') DESC, received_at DESC NULLS LAST LIMIT 1', v_inbox)
      INTO v_pre_status, v_pre_signal USING p_correlation_id, v_rule.prerequisite_signal_type;
    END IF;
    SELECT dependency_graph_id INTO v_graph FROM trustride.coord_dependency_graph WHERE child_signal_id = p_signal_id ORDER BY created_at LIMIT 1;
    IF v_pre_status = 'ACCEPTED' THEN
      IF v_graph IS NOT NULL AND NOT EXISTS (SELECT 1 FROM trustride.coord_dependency_resolution WHERE dependency_graph_id = v_graph) THEN
        PERFORM trustride.fn_coord_dependency_release(v_graph, v_rule.prerequisite_signal_type || ' accepted');
      END IF;
      CONTINUE;
    END IF;
    IF v_graph IS NULL THEN
      INSERT INTO trustride.coord_dependency_graph (correlation_id, execution_id, parent_signal_id, child_signal_id, graph_level)
      VALUES (p_correlation_id, v_sess.admission_session_id, v_pre_signal, p_signal_id, 1) RETURNING dependency_graph_id INTO v_graph;
      IF v_pre_signal IS NOT NULL THEN
        INSERT INTO trustride.coord_dependency_wait (dependency_graph_id, signal_id, blocking_signal_id, wait_reason, wait_timeout_at)
        VALUES (v_graph, p_signal_id, v_pre_signal, 'Awaiting ' || v_rule.prerequisite_signal_type, v_sess.started_at + make_interval(secs => v_rule.hold_timeout_seconds));
      END IF;
      UPDATE trustride.coord_admission_session SET session_status = 'DEFERRED' WHERE admission_session_id = v_sess.admission_session_id;
      INSERT INTO trustride.coord_admission_decision (admission_session_id, decision, decision_reason)
      VALUES (v_sess.admission_session_id, 'DEFERRED', 'Awaiting ' || v_rule.prerequisite_signal_type || ' for this correlation');
    END IF;
    IF v_pre_status IN ('REJECTED', 'DEAD_LETTER') THEN
      INSERT INTO trustride.coord_dependency_resolution (dependency_graph_id, resolution_result, blocking_dependency, resolution_message)
      VALUES (v_graph, FALSE, TRUE, v_rule.prerequisite_signal_type || ' was ' || v_pre_status);
      UPDATE trustride.coord_admission_session SET session_status = 'REJECTED', completed_at = now() WHERE admission_session_id = v_sess.admission_session_id;
      INSERT INTO trustride.coord_admission_decision (admission_session_id, decision, decision_reason)
      VALUES (v_sess.admission_session_id, 'REJECTED', 'DEPENDENCY_FAILED: ' || v_rule.prerequisite_signal_type || ' was ' || v_pre_status);
      RETURN 'DEAD:DEPENDENCY_FAILED: ' || v_rule.prerequisite_signal_type || ' was ' || v_pre_status;
    END IF;
    IF now() > v_sess.started_at + make_interval(secs => v_rule.hold_timeout_seconds) THEN
      UPDATE trustride.coord_dependency_wait SET queue_status = 'TIMED_OUT' WHERE dependency_graph_id = v_graph AND queue_status = 'WAITING';
      INSERT INTO trustride.coord_dependency_resolution (dependency_graph_id, resolution_result, blocking_dependency, resolution_message)
      VALUES (v_graph, FALSE, TRUE, v_rule.prerequisite_signal_type || ' not accepted within ' || v_rule.hold_timeout_seconds || ' s');
      UPDATE trustride.coord_admission_session SET session_status = 'REJECTED', completed_at = now() WHERE admission_session_id = v_sess.admission_session_id;
      INSERT INTO trustride.coord_admission_decision (admission_session_id, decision, decision_reason)
      VALUES (v_sess.admission_session_id, 'REJECTED', 'DEPENDENCY_TIMEOUT: ' || v_rule.prerequisite_signal_type || ' not accepted within ' || v_rule.hold_timeout_seconds || ' s');
      RETURN 'DEAD:DEPENDENCY_TIMEOUT: ' || v_rule.prerequisite_signal_type || ' not accepted within ' || v_rule.hold_timeout_seconds || ' s';
    END IF;
    RETURN 'HELD';
  END LOOP;

  -- Consensus (many-to-one): opened by the execution's owner; held until the binding decision.
  IF v_policy.consensus_required THEN
    SELECT s.*, d.decision AS decided INTO v_cons FROM trustride.coord_consensus_session s
    LEFT JOIN trustride.coord_consensus_decision d ON d.consensus_session_id = s.consensus_session_id
    WHERE s.execution_id = v_sess.admission_session_id ORDER BY s.started_at DESC LIMIT 1;
    v_timeout := coalesce(nullif(trustride.fn_business_config('COORD_FAN_IN_TIMEOUT_SEC'), '')::int, 300);
    IF v_cons IS NULL THEN
      IF now() > v_sess.started_at + make_interval(secs => v_timeout) THEN
        UPDATE trustride.coord_admission_session SET session_status = 'REJECTED', completed_at = now() WHERE admission_session_id = v_sess.admission_session_id;
        INSERT INTO trustride.coord_admission_decision (admission_session_id, decision, decision_reason)
        VALUES (v_sess.admission_session_id, 'REJECTED', 'CONSENSUS_NOT_OPENED within ' || v_timeout || ' s');
        RETURN 'DEAD:CONSENSUS_NOT_OPENED within ' || v_timeout || ' s';
      END IF;
      IF v_sess.session_status <> 'DEFERRED' THEN
        UPDATE trustride.coord_admission_session SET session_status = 'DEFERRED' WHERE admission_session_id = v_sess.admission_session_id;
        INSERT INTO trustride.coord_admission_decision (admission_session_id, decision, decision_reason)
        VALUES (v_sess.admission_session_id, 'DEFERRED', 'consensus required -- awaiting the session and its votes');
      END IF;
      RETURN 'HELD';
    END IF;
    v_decision := coalesce(v_cons.decided, CASE WHEN v_cons.session_status = 'TIMED_OUT' THEN 'ABORT' END);
    IF v_decision IS NULL THEN RETURN 'HELD'; END IF;
    IF v_decision = 'ABORT' THEN
      UPDATE trustride.coord_admission_session SET session_status = 'REJECTED', completed_at = now() WHERE admission_session_id = v_sess.admission_session_id;
      INSERT INTO trustride.coord_admission_decision (admission_session_id, decision, decision_reason)
      VALUES (v_sess.admission_session_id, 'REJECTED', 'CONSENSUS_ABORTED');
      RETURN 'DEAD:CONSENSUS_ABORTED';
    END IF;
  END IF;

  UPDATE trustride.coord_admission_session SET session_status = 'ADMITTED', completed_at = now() WHERE admission_session_id = v_sess.admission_session_id;
  INSERT INTO trustride.coord_admission_decision (admission_session_id, decision, decision_reason)
  VALUES (v_sess.admission_session_id, 'ADMITTED', CASE WHEN v_policy.dependency_check_required OR v_policy.consensus_required
                                                        THEN 'requirements satisfied' ELSE 'coordinated fan-out delivery' END);
  PERFORM trustride.fn_coord_execution_state_set(v_sess.admission_session_id, coalesce(p_destination_engine, 'UNKNOWN'), 'ADMITTED');
  RETURN 'ADMITTED';
END;
$function$;

CREATE FUNCTION trustride.fn_coord_finalize(p_signal_id uuid, p_inbox_table text, p_error text DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_sess RECORD; v_status TEXT; v_ok BOOLEAN; v_stage UUID; v_wf UUID; v_comp UUID; v_rel UUID; v_sig RECORD;
BEGIN
  SELECT * INTO v_sess FROM trustride.coord_admission_session WHERE signal_id = p_signal_id AND session_status = 'ADMITTED' ORDER BY started_at LIMIT 1;
  IF v_sess IS NULL OR EXISTS (SELECT 1 FROM trustride.coord_execution_completion WHERE execution_id = v_sess.admission_session_id) THEN
    RETURN;   -- not coordinated, or already final
  END IF;
  EXECUTE format('SELECT signal_status::text, signal_type, rejection_reason FROM trustride.%I WHERE signal_id = $1', p_inbox_table)
  INTO v_sig USING p_signal_id;
  v_status := coalesce(v_sig.signal_status, 'DEAD_LETTER');
  v_ok := v_status = 'ACCEPTED';

  SELECT workflow_instance_id INTO v_wf FROM trustride.coord_workflow_instance WHERE correlation_id = v_sess.correlation_id ORDER BY started_at LIMIT 1;
  SELECT workflow_stage_id INTO v_stage FROM trustride.coord_workflow_stage
  WHERE workflow_instance_id = v_wf AND stage_status = 'ENTERED' AND stage_code = v_sig.signal_type ORDER BY stage_sequence LIMIT 1;
  IF v_stage IS NOT NULL THEN PERFORM trustride.fn_coord_workflow_stage_complete(v_stage, v_ok); END IF;
  PERFORM trustride.fn_coord_execution_state_set(v_sess.admission_session_id, v_sess.destination_engine_code, CASE WHEN v_ok THEN 'COMPLETED' ELSE 'FAILED' END);

  -- Finality, then hand-back to Engine 7.
  v_comp := trustride.fn_coord_execution_complete(v_sess.admission_session_id, CASE WHEN v_ok THEN 'COMPLETED' ELSE 'FAILED' END::trustride.coord_completion_state_enum,
    v_status || coalesce(': ' || coalesce(p_error, v_sig.rejection_reason), ''), v_sess.destination_engine_code);
  SELECT execution_release_id INTO v_rel FROM trustride.coord_execution_release WHERE execution_completion_id = v_comp;
  PERFORM trustride.fn_coord_execution_release(v_rel, p_signal_id);

  IF NOT v_ok THEN
    -- A failed branch: the distributed execution did not complete; never silent.
    UPDATE trustride.coord_workflow_instance SET workflow_status = 'FAILED', completed_at = now() WHERE workflow_instance_id = v_wf AND workflow_status = 'RUNNING';
    INSERT INTO trustride.coord_recovery_plan (execution_id, recovery_action, execution_order, plan_status)
    VALUES (v_sess.admission_session_id, 'TERMINATE', 1, 'COMPLETED');
    INSERT INTO trustride.coord_runtime_alert (alert_code, alert_level, alert_reason, engine_code)
    VALUES ('COORDINATED_BRANCH_FAILED', 'CRITICAL',
      left(coalesce(v_sig.signal_type, '?') || ' to ' || v_sess.destination_engine_code || ' ended ' || v_status || ' in correlation ' || v_sess.correlation_id
           || ' (' || (SELECT count(*) FROM trustride.coord_workflow_stage WHERE workflow_instance_id = v_wf AND stage_status = 'COMPLETED') || ' other stages completed)', 500),
      v_sess.destination_engine_code);
  END IF;
END;
$function$;

-- Engine 7 dispatch: Engine 8 first for coordinated signals; finality after every handler.
DO $patch$
DECLARE
  v_def TEXT;
  a1 TEXT := E'  v_new_hash     CHAR(64);\n';
  a2 TEXT := E'      v_discovered := v_discovered + 1;\n';
  a3 TEXT := E'      PERFORM trustride.fn_coord_admission_check(v_row.signal_type, v_row.signal_id, v_row.correlation_id, v_row.emitting_engine, v_cache.destination_engine_code);\n';
  a4 TEXT := E'        UPDATE trustride.orch_signal_queue SET queue_status = ''COMPLETED'' WHERE signal_id = v_row.signal_id AND queue_status IN (''QUEUED'', ''LEASED'', ''DISPATCHED'');\n';
  a5 TEXT := E'        UPDATE trustride.orch_signal_queue SET queue_status = ''FAILED'' WHERE signal_id = v_row.signal_id AND queue_status IN (''QUEUED'', ''LEASED'', ''DISPATCHED'');\n';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_orch_dispatch_cycle()'::regprocedure) INTO v_def;
  IF position(a1 IN v_def) = 0 OR position(a2 IN v_def) = 0 OR position(a3 IN v_def) = 0 OR position(a4 IN v_def) = 0 OR position(a5 IN v_def) = 0 THEN
    RAISE EXCEPTION 'dispatch cycle anchors not found';
  END IF;
  v_def := replace(v_def, a1, a1 || E'  v_gov          TEXT;\n');
  v_def := replace(v_def, a2, a2
    || E'      -- Engine 8 first: a coordinated (fan-out / fan-in) signal proceeds only when admitted.\n'
    || E'      v_gov := trustride.fn_coord_govern(v_row.signal_id, v_row.correlation_id, v_row.signal_type, v_row.emitting_engine, v_row.receiving_engine, v_row.payload_in);\n'
    || E'      IF v_gov = ''HELD'' THEN\n'
    || E'        CONTINUE;   -- stays PENDING; decided again next cycle\n'
    || E'      END IF;\n'
    || E'      IF v_gov LIKE ''DEAD:%'' THEN\n'
    || E'        EXECUTE format(''UPDATE trustride.%I SET signal_status = ''''DEAD_LETTER'''', rejection_reason = $2 WHERE signal_id = $1'', v_row.src_outbox_table)\n'
    || E'        USING v_row.signal_id, left(''COORDINATION: '' || substr(v_gov, 6), 500);\n'
    || E'        INSERT INTO trustride.dead_letter_review (event_id, source_engine, target_engine, failure_reason)\n'
    || E'        VALUES (v_row.signal_id, v_row.emitting_engine, coalesce(v_row.receiving_engine, ''UNKNOWN''), left(v_row.signal_type || '': '' || substr(v_gov, 6), 1000));\n'
    || E'        PERFORM trustride.fn_present_notify_office(''Signal stopped by coordination: '' || v_row.signal_type, left(substr(v_gov, 6), 300),\n'
    || E'          ''PLATFORM_EXCEPTION'', v_row.signal_id, ARRAY[''FOUNDER'', ''ADMINISTRATOR''], FALSE);\n'
    || E'        CONTINUE;\n'
    || E'      END IF;\n');
  v_def := replace(v_def, a3, '');
  v_def := replace(v_def, a4, a4 || E'        PERFORM trustride.fn_coord_finalize(v_row.signal_id, v_cache.destination_inbox_table);\n');
  v_def := replace(v_def, a5, a5 || E'        PERFORM trustride.fn_coord_finalize(v_row.signal_id, v_cache.destination_inbox_table, SQLERRM);\n');
  EXECUTE v_def;
END;
$patch$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
