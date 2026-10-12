-- Suite 27 -- Engines 7 and 8 coordinate fan-out and fan-in executions (Construction Directive WP4).
-- Through the real dispatch cycle: a dependent signal arriving early is held, not failed, and released
-- when its prerequisite is accepted; a refused or overdue prerequisite ends the dependent explicitly;
-- a duplicate execution is refused; a consumer failure is final, alerted and never silent; consensus
-- holds until COMMIT or ABORT; a held signal writes nothing more each cycle; in a real order every
-- coordinated delivery is admitted, finalized with a certificate and released back to Engine 7, while
-- one-to-one signals bypass Engine 8; every signal of the order reaches a terminal state.
DO $$
DECLARE
  founder UUID; cust UUID; est UUID; r JSONB; ord UUID; corr UUID; c UUID; d UUID; x UUID; n INT; m INT; v TEXT; s RECORD; sess UUID; cons UUID;
  ready BOOLEAN := to_regprocedure('trustride.fn_coord_govern(uuid,uuid,text,text,text,jsonb)') IS NOT NULL;
BEGIN
  founder := pg_temp.t_person('Coord Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');

  -- ============ delayed delivery: the dispatch arrives before the service context
  c := gen_random_uuid(); d := gen_random_uuid();
  INSERT INTO trustride.resource_event_outbox (signal_id, correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, signal_status, idempotency_key)
  VALUES (d, c, 'TRS026_ENG002_RESC', 'TRS026_ENG005_COST', 'RESOURCE_DISPATCH_INITIATED', jsonb_build_object('existing_quote_id', gen_random_uuid()), 'PENDING', 'suite27:' || d);
  PERFORM trustride.fn_orch_dispatch_cycle(); PERFORM trustride.fn_orch_dispatch_cycle(); PERFORM trustride.fn_orch_dispatch_cycle();
  SELECT signal_status INTO v FROM trustride.resource_event_outbox WHERE signal_id = d;
  SELECT count(*) INTO n FROM trustride.cost_event_inbox WHERE signal_id = d;
  PERFORM pg_temp.t_check('fan-in: a dispatch arriving before its service context is held (PENDING, not delivered, not failed)', v = 'PENDING' AND n = 0, v || ' delivered=' || n);
  SELECT count(*) INTO n FROM trustride.orch_routing_decision WHERE signal_id = d;
  SELECT count(*) INTO m FROM trustride.orch_execution_graph WHERE signal_id = d;
  PERFORM pg_temp.t_check('a held signal writes nothing more on each cycle (no routing decisions, no graph rows)', n = 0 AND m = 0, n || ' decisions, ' || m || ' graph rows after 3 cycles');
  IF ready THEN
    SELECT count(*) INTO n FROM trustride.coord_admission_session WHERE signal_id = d;
    PERFORM pg_temp.t_check('Engine 8 opened one admission session for it, DEFERRED', n = 1
      AND (SELECT session_status::text FROM trustride.coord_admission_session WHERE signal_id = d) = 'DEFERRED', n::text);
  END IF;
  x := gen_random_uuid();
  INSERT INTO trustride.service_event_outbox (signal_id, correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, signal_status, idempotency_key)
  VALUES (x, c, 'TRS026_ENG003_SERV', 'TRS026_ENG005_COST', 'SERVICE_CONTEXT_RESOLVED', '{"macro_domain":"TRANSPORT","service_code":"TRANSPORT-BODA-STANDARD"}', 'PENDING', 'suite27:' || x);
  PERFORM trustride.fn_orch_dispatch_cycle(); PERFORM trustride.fn_orch_dispatch_cycle();
  SELECT signal_status INTO v FROM trustride.cost_event_inbox WHERE signal_id = d;
  PERFORM pg_temp.t_check('fan-in: once the context is accepted the held dispatch is delivered and handled', v = 'ACCEPTED', coalesce(v, 'not delivered'));
  IF ready THEN
    SELECT s2.session_status::text AS st, (SELECT completion_state::text FROM trustride.coord_execution_completion WHERE execution_id = s2.admission_session_id) AS comp,
           (SELECT count(*) FROM trustride.coord_execution_certificate ce JOIN trustride.coord_execution_completion cc ON cc.execution_completion_id = ce.execution_completion_id
            WHERE cc.execution_id = s2.admission_session_id) AS certs,
           (SELECT release_status FROM trustride.coord_execution_release er JOIN trustride.coord_execution_completion cc ON cc.execution_completion_id = er.execution_completion_id
            WHERE cc.execution_id = s2.admission_session_id) AS rel,
           (SELECT bool_and(resolution_result) FROM trustride.coord_dependency_resolution dr JOIN trustride.coord_dependency_graph g ON g.dependency_graph_id = dr.dependency_graph_id
            WHERE g.child_signal_id = d) AS dep
    INTO s FROM trustride.coord_admission_session s2 WHERE s2.signal_id = d;
    PERFORM pg_temp.t_check('Engine 8 admitted it, resolved the dependency, certified completion and released it to Engine 7',
      s.st = 'ADMITTED' AND s.comp = 'COMPLETED' AND s.certs = 1 AND s.rel = 'RELEASED' AND s.dep, row_to_json(s)::text);
  END IF;

  -- ============ a refused prerequisite ends the dependent explicitly
  c := gen_random_uuid(); d := gen_random_uuid();
  INSERT INTO trustride.cost_event_inbox (signal_id, correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, signal_status, rejection_reason, idempotency_key)
  VALUES (gen_random_uuid(), c, 'TRS026_ENG003_SERV', 'TRS026_ENG005_COST', 'SERVICE_CONTEXT_RESOLVED', '{}', 'REJECTED', 'suite 27 fixture', 'suite27:pre:' || c);
  INSERT INTO trustride.resource_event_outbox (signal_id, correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, signal_status, idempotency_key)
  VALUES (d, c, 'TRS026_ENG002_RESC', 'TRS026_ENG005_COST', 'RESOURCE_DISPATCH_INITIATED', jsonb_build_object('existing_quote_id', gen_random_uuid()), 'PENDING', 'suite27:' || d);
  PERFORM trustride.fn_orch_dispatch_cycle();
  SELECT signal_status || ' ' || coalesce(rejection_reason, '') INTO v FROM trustride.resource_event_outbox WHERE signal_id = d;
  PERFORM pg_temp.t_check('a dependent whose prerequisite was refused ends DEAD_LETTER (DEPENDENCY_FAILED), reviewed, Office told',
    v LIKE 'DEAD_LETTER COORDINATION: DEPENDENCY_FAILED%' AND EXISTS (SELECT 1 FROM trustride.dead_letter_review WHERE event_id = d)
    AND EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = founder AND source_signal_correlation_id = d), v);

  -- ============ an overdue prerequisite: never pending indefinitely
  c := gen_random_uuid(); d := gen_random_uuid();
  INSERT INTO trustride.resource_event_outbox (signal_id, correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, signal_status, idempotency_key)
  VALUES (d, c, 'TRS026_ENG002_RESC', 'TRS026_ENG005_COST', 'RESOURCE_DISPATCH_INITIATED', jsonb_build_object('existing_quote_id', gen_random_uuid()), 'PENDING', 'suite27:' || d);
  PERFORM trustride.fn_orch_dispatch_cycle();
  UPDATE trustride.coord_admission_session SET started_at = now() - interval '1 hour' WHERE signal_id = d;   -- the hold window has passed
  PERFORM trustride.fn_orch_dispatch_cycle();
  SELECT signal_status || ' ' || coalesce(rejection_reason, '') INTO v FROM trustride.resource_event_outbox WHERE signal_id = d;
  PERFORM pg_temp.t_check('a dependent whose prerequisite never arrives ends DEAD_LETTER (DEPENDENCY_TIMEOUT) after its hold window', v LIKE 'DEAD_LETTER COORDINATION: DEPENDENCY_TIMEOUT%', v);

  -- ============ duplicate execution
  c := gen_random_uuid(); d := gen_random_uuid(); x := gen_random_uuid();
  INSERT INTO trustride.advisory_event_outbox (signal_id, correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, signal_status, idempotency_key)
  VALUES (d, c, 'TRS026_ENG009_AIADV', 'TRS026_ENG008_COORD', 'ADVISORY_ANOMALY_FLAGGED', '{"severity":"LOW","anomaly_type":"MARGIN_BREACH","anomaly_id":"suite27-dup"}', 'PENDING', 'suite27:' || d),
         (x, c, 'TRS026_ENG009_AIADV', 'TRS026_ENG008_COORD', 'ADVISORY_ANOMALY_FLAGGED', '{"severity":"LOW","anomaly_type":"MARGIN_BREACH","anomaly_id":"suite27-dup"}', 'PENDING', 'suite27:' || x);
  PERFORM trustride.fn_orch_dispatch_cycle();
  SELECT count(*) FILTER (WHERE signal_status = 'DISPATCHED'), count(*) FILTER (WHERE signal_status = 'DEAD_LETTER' AND rejection_reason LIKE 'COORDINATION: DUPLICATE_EXECUTION%')
  INTO n, m FROM trustride.advisory_event_outbox WHERE signal_id IN (d, x);
  PERFORM pg_temp.t_check('the same execution delivered twice runs once; the duplicate is refused', n = 1 AND m = 1, n || ' dispatched, ' || m || ' refused as duplicate');

  -- ============ consumer failure: final, the branch and workflow FAILED, alerted
  c := gen_random_uuid(); d := gen_random_uuid();
  INSERT INTO trustride.service_event_outbox (signal_id, correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, signal_status, idempotency_key)
  VALUES (d, c, 'TRS026_ENG003_SERV', 'TRS026_ENG004_BUS', 'SERVICE_RESOLVED', jsonb_build_object('order_id', gen_random_uuid(), 'service_code', 'NO-SUCH'), 'PENDING', 'suite27:' || d);
  PERFORM trustride.fn_orch_dispatch_cycle();
  SELECT signal_status INTO v FROM trustride.business_event_inbox WHERE signal_id = d;
  PERFORM pg_temp.t_check('a consumer that cannot handle the signal ends it terminally (not RECEIVED)', v IN ('DEAD_LETTER', 'REJECTED'), coalesce(v, 'none'));
  IF ready THEN
    SELECT (SELECT completion_state::text FROM trustride.coord_execution_completion WHERE execution_id = s2.admission_session_id) AS comp,
           (SELECT workflow_status::text FROM trustride.coord_workflow_instance WHERE correlation_id = c) AS wf,
           (SELECT count(*) FROM trustride.coord_recovery_plan WHERE execution_id = s2.admission_session_id AND recovery_action = 'TERMINATE') AS rp,
           (SELECT count(*) FROM trustride.coord_runtime_alert WHERE alert_code = 'COORDINATED_BRANCH_FAILED' AND alert_reason LIKE '%' || c::text || '%') AS al
    INTO s FROM trustride.coord_admission_session s2 WHERE s2.signal_id = d;
    PERFORM pg_temp.t_check('Engine 8 records the failed branch: completion FAILED, workflow FAILED, TERMINATE recovery, critical alert',
      s.comp = 'FAILED' AND s.wf = 'FAILED' AND s.rp = 1 AND s.al = 1, row_to_json(s)::text);
  END IF;

  -- ============ consensus (many-to-one): held until COMMIT; refused on ABORT
  IF ready THEN
    UPDATE trustride.coord_admission_policy SET consensus_required = TRUE WHERE signal_type = 'ADVISORY_ANOMALY_FLAGGED';
    c := gen_random_uuid(); d := gen_random_uuid();
    INSERT INTO trustride.advisory_event_outbox (signal_id, correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, signal_status, idempotency_key)
    VALUES (d, c, 'TRS026_ENG009_AIADV', 'TRS026_ENG008_COORD', 'ADVISORY_ANOMALY_FLAGGED', '{"severity":"LOW","anomaly_type":"MARGIN_BREACH","anomaly_id":"suite27-commit"}', 'PENDING', 'suite27:' || d);
    PERFORM trustride.fn_orch_dispatch_cycle();
    SELECT signal_status INTO v FROM trustride.advisory_event_outbox WHERE signal_id = d;
    PERFORM pg_temp.t_check('consensus: held while no binding decision exists', v = 'PENDING', v);
    SELECT admission_session_id INTO sess FROM trustride.coord_admission_session WHERE signal_id = d;
    cons := trustride.fn_coord_consensus_session_open(sess, c, ARRAY['TRS026_ENG008_COORD'], ARRAY['MANDATORY']::trustride.coord_participant_role_enum[], 300);
    v := trustride.fn_coord_consensus_vote_cast(cons, 'TRS026_ENG008_COORD', 'ACCEPT', 'suite 27');
    PERFORM trustride.fn_orch_dispatch_cycle();
    SELECT signal_status INTO v FROM trustride.coord_event_inbox WHERE signal_id = d;
    PERFORM pg_temp.t_check('consensus COMMIT releases the held signal to its destination', v = 'ACCEPTED', coalesce(v, 'not delivered'));
    c := gen_random_uuid(); d := gen_random_uuid();
    INSERT INTO trustride.advisory_event_outbox (signal_id, correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, signal_status, idempotency_key)
    VALUES (d, c, 'TRS026_ENG009_AIADV', 'TRS026_ENG008_COORD', 'ADVISORY_ANOMALY_FLAGGED', '{"severity":"LOW","anomaly_type":"MARGIN_BREACH","anomaly_id":"suite27-abort"}', 'PENDING', 'suite27:' || d);
    PERFORM trustride.fn_orch_dispatch_cycle();
    SELECT admission_session_id INTO sess FROM trustride.coord_admission_session WHERE signal_id = d;
    cons := trustride.fn_coord_consensus_session_open(sess, c, ARRAY['TRS026_ENG008_COORD'], ARRAY['MANDATORY']::trustride.coord_participant_role_enum[], 300);
    v := trustride.fn_coord_consensus_vote_cast(cons, 'TRS026_ENG008_COORD', 'REJECT', 'suite 27');
    PERFORM trustride.fn_orch_dispatch_cycle();
    SELECT signal_status || ' ' || coalesce(rejection_reason, '') INTO v FROM trustride.advisory_event_outbox WHERE signal_id = d;
    PERFORM pg_temp.t_check('consensus ABORT ends the signal DEAD_LETTER (CONSENSUS_ABORTED)', v LIKE 'DEAD_LETTER COORDINATION: CONSENSUS_ABORTED%', v);
    UPDATE trustride.coord_admission_policy SET consensus_required = FALSE WHERE signal_type = 'ADVISORY_ANOMALY_FLAGGED';
  END IF;

  -- ============ a real order: coordinated deliveries certified and released; one-to-one bypasses; all terminal
  PERFORM pg_temp.t_open_all_hours();
  cust := pg_temp.t_customer('Coord Cust');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"CRD-27","estate_name":"Coord Hub","estate_type":"OPERATING_HUB","lat":-0.09,"lon":34.76}');
  est := (r->>'signal')::uuid;
  PERFORM pg_temp.t_ready_unit(founder, 'BODA_BODA', est, 'Coord Rider');
  ord := pg_temp.t_order_to_completed(cust);
  SELECT correlation_id INTO corr FROM trustride.business_order WHERE order_id = ord;
  IF ready THEN
    SELECT count(*), count(*) FILTER (WHERE a.session_status = 'ADMITTED'
             AND EXISTS (SELECT 1 FROM trustride.coord_execution_completion cc JOIN trustride.coord_execution_certificate ce ON ce.execution_completion_id = cc.execution_completion_id
                         JOIN trustride.coord_execution_release er ON er.execution_completion_id = cc.execution_completion_id
                         WHERE cc.execution_id = a.admission_session_id AND cc.completion_state = 'COMPLETED' AND er.release_status = 'RELEASED'))
    INTO n, m FROM trustride.coord_admission_session a WHERE a.correlation_id = corr;
    PERFORM pg_temp.t_check('order: every coordinated delivery is admitted, certified and released (fan-outs and the pricing fan-in)', n >= 6 AND n = m, m || ' of ' || n);
    SELECT count(*) INTO n FROM trustride.cost_event_inbox ci WHERE ci.correlation_id = corr AND ci.signal_type = 'FARE_QUOTED'
      AND EXISTS (SELECT 1 FROM trustride.coord_admission_session a WHERE a.signal_id = ci.signal_id);
    SELECT count(*) INTO m FROM trustride.coord_admission_session a WHERE a.correlation_id = corr
      AND NOT EXISTS (SELECT 1 FROM trustride.coord_admission_policy p WHERE p.signal_type = (SELECT signal_type FROM trustride.orch_routing_decision rd WHERE rd.signal_id = a.signal_id LIMIT 1));
    PERFORM pg_temp.t_check('order: one-to-one signals do not enter Engine 8', m = 0, m || ' non-coordinated admissions');
    PERFORM pg_temp.t_check('order: the workflow context records its coordinated stages, all completed',
      EXISTS (SELECT 1 FROM trustride.coord_workflow_instance w WHERE w.correlation_id = corr AND w.workflow_status = 'RUNNING'
              AND (SELECT count(*) FROM trustride.coord_workflow_stage st WHERE st.workflow_instance_id = w.workflow_instance_id) >= 6
              AND NOT EXISTS (SELECT 1 FROM trustride.coord_workflow_stage st WHERE st.workflow_instance_id = w.workflow_instance_id AND st.stage_status <> 'COMPLETED')));
  END IF;
  SELECT count(*) INTO n FROM trustride.orch_routing_decision rd WHERE rd.correlation_id = corr;
  SELECT count(*) INTO m FROM (
    SELECT signal_status::text st FROM trustride.business_event_inbox WHERE correlation_id = corr UNION ALL SELECT signal_status::text FROM trustride.cost_event_inbox WHERE correlation_id = corr
    UNION ALL SELECT signal_status::text FROM trustride.resource_event_inbox WHERE correlation_id = corr UNION ALL SELECT signal_status::text FROM trustride.service_event_inbox WHERE correlation_id = corr
    UNION ALL SELECT signal_status::text FROM trustride.integration_event_inbox WHERE correlation_id = corr UNION ALL SELECT signal_status::text FROM trustride.present_event_inbox WHERE correlation_id = corr) z
  WHERE st NOT IN ('ACCEPTED', 'REJECTED', 'DEAD_LETTER');
  PERFORM pg_temp.t_check('order: every routed signal of the order reached a terminal state at its consumer', n > 0 AND m = 0, n || ' routed, ' || m || ' not terminal');
END
$$;
