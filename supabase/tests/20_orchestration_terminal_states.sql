-- Suite 20 -- every signal reaches an explicit terminal state (TRS026-ENG-REMEDIATION-001: D10, D22).
-- A signal with no route is decided once, dead-lettered with a reason and
-- reported to the Office; a routed signal's queue entry records whether its
-- handler completed or failed.
DO $$
DECLARE
  sig UUID := gen_random_uuid(); n INT; v TEXT; cust UUID; founder UUID; r JSONB;
BEGIN
  founder := pg_temp.t_person('Queue Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  -- ============ D10: no route -> one decision, dead letter, Office told
  INSERT INTO trustride.business_event_outbox (signal_id, correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, signal_status, idempotency_key)
  VALUES (sig, gen_random_uuid(), 'TRS026_ENG004_BUS', 'TRS026_ENG005_COST', 'SUITE20_NO_SUCH_SIGNAL', '{}', 'PENDING', 'suite20:' || sig);
  PERFORM trustride.fn_orch_dispatch_cycle();
  PERFORM trustride.fn_orch_dispatch_cycle();
  PERFORM trustride.fn_orch_dispatch_cycle();
  SELECT count(*) INTO n FROM trustride.orch_routing_decision WHERE signal_id = sig;
  PERFORM pg_temp.t_check('D10 an unroutable signal is decided once, not every cycle', n = 1, n || ' decisions after 3 cycles');
  SELECT signal_status::text || ' ' || coalesce(rejection_reason, '') INTO v FROM trustride.business_event_outbox WHERE signal_id = sig;
  PERFORM pg_temp.t_check('D10 it ends DEAD_LETTER with the reason', v LIKE 'DEAD_LETTER NO_ROUTE%', v);
  PERFORM pg_temp.t_check('D10 it is queued for dead-letter review', EXISTS (SELECT 1 FROM trustride.dead_letter_review WHERE event_id = sig));
  PERFORM pg_temp.t_check('D10 the Office is told', EXISTS (SELECT 1 FROM trustride.present_notification_inbox
    WHERE recipient_user_id = founder AND source_signal_correlation_id = sig AND category = 'PLATFORM_EXCEPTION'));

  -- ============ D22: a routed signal's queue entry records its outcome
  PERFORM pg_temp.t_open_all_hours();
  cust := pg_temp.t_customer('Queue Cust');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"Q20-01","estate_name":"Queue Hub","estate_type":"OPERATING_HUB","lat":-0.09,"lon":34.76}');
  PERFORM pg_temp.t_ready_unit(founder, 'BODA_BODA', (r->>'signal')::uuid, 'Queue Rider');
  PERFORM pg_temp.t_order_to_completed(cust);
  SELECT count(*) FILTER (WHERE queue_status = 'COMPLETED'), count(*) FILTER (WHERE queue_status = 'DISPATCHED') INTO n, v
  FROM trustride.orch_signal_queue WHERE created_at = now();
  PERFORM pg_temp.t_check('D22 handled signals are COMPLETED on the queue, none left DISPATCHED', n > 0 AND v::int = 0, n || ' completed, ' || v || ' dispatched');
END
$$;
