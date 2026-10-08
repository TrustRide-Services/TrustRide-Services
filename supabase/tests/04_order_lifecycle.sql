-- Suite 04 -- Order lifecycle: Journeys A (customer transport), B (resource
-- unavailable), C (operator), F (Executive Assistant), all 24 services,
-- multi-stop, estimate/acceptance, expiry, cancellation, decline, timeouts,
-- Office intervention, scheduling, intake services, pricing failure.
DO $$
DECLARE
  founder UUID; cust UUID; cust2 UUID; est UUID;
  boda UUID; boda2 UUID; r JSONB; o trustride.business_order; ord UUID; q RECORD; j RECORD; v TEXT; n INT; total NUMERIC; sumlines NUMERIC;
  op UUID; op2 UUID; txn UUID; svc RECORD; unit UUID; ea_units JSONB := '{}'::jsonb;
  lines JSONB := '[{"scope_detail":{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02"}}]';
BEGIN
  PERFORM pg_temp.t_open_all_hours();
  founder := pg_temp.t_person('Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  cust := pg_temp.t_customer('Akinyi');
  cust2 := pg_temp.t_customer('Other');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"T-HUB","estate_type":"OPERATING_HUB","estate_name":"Test Hub","lat":-0.0917,"lon":34.7680}');
  est := (r->>'signal')::uuid;

  -- ===================================================== guard rails at entry
  r := pg_temp.t_cmd(pg_temp.t_person('No Phone', 'CUSTOMER'), 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT',
    jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD', 'order_lines', lines));
  PERFORM pg_temp.t_check('no verified phone -> order refused up front (would be unpayable)', r->>'status' = 'REJECTED' AND r->>'reason' LIKE '%phone%', r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT',
    jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD', 'order_lines', '[{"scope_detail":{"origin_zone_code":"NOWHERE","destination_zone_code":"KSM-CBD-01"}}]'));
  PERFORM pg_temp.t_check('unknown zone refused', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT',
    jsonb_build_object('service_code', 'MARKETPLACE-ITEM-SALE', 'order_lines', lines));
  PERFORM pg_temp.t_check('a Marketplace service never enters dispatch (G6)', r->>'status' = 'REJECTED' AND r->>'reason' LIKE '%PURCHASE_LISTING%', r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT',
    jsonb_build_object('service_code', 'EA-ACADEMY-TRAINING', 'order_lines', lines));
  PERFORM pg_temp.t_check('an intake service is sent to its own path (G6)', r->>'status' = 'REJECTED' AND r->>'reason' LIKE '%ENROLL_ACADEMY%', r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'TRACK_ELEMENT', '{"job_id":"00000000-0000-0000-0000-000000000000","lat":0,"lon":0}');
  PERFORM pg_temp.t_check('customers can no longer write locations (G13)', r->>'status' = 'CAPTURE_REFUSED', r::text);

  -- ============================ Journey B: nobody free -> WAITING -> retry
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT',
    jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD', 'order_lines', lines));
  PERFORM pg_temp.t_check('boda order placed', r->>'status' = 'TRANSLATED', r::text);
  o := pg_temp.t_order(r);  ord := o.order_id;
  SELECT (scope_detail->>'distance_km')::numeric INTO total FROM trustride.business_order_line WHERE order_id = ord;
  PERFORM pg_temp.t_check('distance computed by the routing port, not typed (G14)', total > 0, total::text);
  PERFORM pg_temp.t_cycle(10);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('no boda on duty -> order WAITING, not silent (G4)', o.status = 'WAITING', o.status::text);
  PERFORM pg_temp.t_check('customer told they are waiting', EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = cust AND title LIKE 'Finding you a%'));
  boda := pg_temp.t_ready_unit(founder, 'BODA_BODA', est, 'Rider One');
  SELECT operator_user_id INTO op FROM trustride.resource_workforce_unit WHERE workforce_unit_id = boda;
  UPDATE trustride.business_order SET last_assignment_requested_at = now() - interval '5 minutes' WHERE order_id = ord;
  r := to_jsonb(trustride.fn_business_dispatch_sweep());
  PERFORM pg_temp.t_cycle(12);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('rider comes on duty -> retry matches -> estimate issued (QUOTED)', o.status = 'QUOTED', o.status::text || ' ' || coalesce(o.status_reason, ''));
  PERFORM pg_temp.t_check('worker held RESERVED->ASSIGNED for the order', trustride.fn_resource_unit_availability(boda) = 'ASSIGNED');
  PERFORM pg_temp.t_check('the waiting reason is cleared once a worker is matched', o.status_reason IS NULL AND o.waiting_since IS NULL, coalesce(o.status_reason, ''));
  PERFORM pg_temp.t_check('customer asked to confirm the fare (SMS-critical)', EXISTS (
    SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = cust AND title LIKE 'Confirm your fare%' AND critical));
  SELECT quote_state::text, computed_total_fare_kes INTO q FROM trustride.fare_quote WHERE quote_id = o.quote_id;
  PERFORM pg_temp.t_check('estimate is NOT auto-locked (D2)', q.quote_state = 'FARE_ESTIMATED', q.quote_state);

  -- ============================ Journey C: operator cannot start before acceptance
  SELECT * INTO j FROM trustride.business_job WHERE order_id = ord;
  r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'ACKNOWLEDGE_JOB', jsonb_build_object('job_id', j.job_id));
  PERFORM pg_temp.t_check('operator cannot start a job the customer has not confirmed', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(cust2, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'ACCEPT_QUOTATION', jsonb_build_object('quote_id', o.quote_id));
  PERFORM pg_temp.t_check('another customer cannot accept my fare', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'ACCEPT_QUOTATION', jsonb_build_object('quote_id', o.quote_id));
  PERFORM pg_temp.t_check('customer accepts the fare', r->>'status' = 'TRANSLATED', r::text);
  PERFORM pg_temp.t_check('the fare buttons disappear at once, before the cycle runs',
    NOT (trustride.fn_present_order_actions(ord)->>'accept_quote')::boolean AND NOT (trustride.fn_present_order_actions(ord)->>'decline_quote')::boolean,
    trustride.fn_present_order_actions(ord)::text);
  PERFORM pg_temp.t_cycle(6);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('fare locked -> order ready for the operator', o.status = 'JOB_CREATED' AND EXISTS (SELECT 1 FROM trustride.business_settlement WHERE order_id = ord), o.status::text);
  PERFORM pg_temp.t_check('operator told: new job (SMS-critical)', EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = op AND title LIKE 'New job%' AND critical));
  r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'ACKNOWLEDGE_JOB', jsonb_build_object('job_id', j.job_id));
  PERFORM pg_temp.t_check('operator acknowledges', r->>'status' = 'TRANSLATED', r::text);
  boda2 := pg_temp.t_ready_unit(founder, 'BODA_BODA', est, 'Rider Two');
  SELECT operator_user_id INTO op2 FROM trustride.resource_workforce_unit WHERE workforce_unit_id = boda2;
  r := pg_temp.t_cmd(op2, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', jsonb_build_object('job_id', j.job_id));
  PERFORM pg_temp.t_check('another operator cannot progress my job', r->>'status' = 'REJECTED', r::text);
  FOREACH v IN ARRAY ARRAY['DISPATCHED', 'EN_ROUTE', 'ARRIVED'] LOOP
    r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', jsonb_build_object('job_id', j.job_id));
  END LOOP;
  r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'TRACK_ELEMENT', jsonb_build_object('job_id', j.job_id, 'lat', -0.09, 'lon', 34.76));
  PERFORM pg_temp.t_check('operator reports location for own job', r->>'status' = 'TRANSLATED', r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'CANCEL_ORDER', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_check('customer cannot cancel once the rider has arrived', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', jsonb_build_object('job_id', j.job_id));  -- EXECUTING
  r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', jsonb_build_object('job_id', j.job_id));  -- COMPLETED
  PERFORM pg_temp.t_cycle(8);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('service complete -> order COMPLETED', o.status = 'COMPLETED', o.status::text);
  SELECT gateway_txn_id INTO txn FROM trustride.integration_payment_gateway_transaction WHERE quote_id = o.quote_id;
  PERFORM pg_temp.t_check('payment requested only after completion', txn IS NOT NULL);
  PERFORM pg_temp.t_check('customer told an M-Pesa request is coming', EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = cust AND title = 'Service complete'));
  PERFORM trustride.fn_integration_payment_callback_simulate(txn, 'SETTLED');
  PERFORM pg_temp.t_cycle(6);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('paid -> SETTLED with a receipt', o.status = 'SETTLED' AND EXISTS (SELECT 1 FROM trustride.business_settlement WHERE order_id = ord AND receipt_code IS NOT NULL), o.status::text);
  PERFORM pg_temp.t_check('customer receives the receipt notification', EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = cust AND title = 'Payment settled'));
  r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', jsonb_build_object('job_id', j.job_id));  -- VERIFIED
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('verified -> rider back in the pool, available again', trustride.fn_resource_unit_availability(boda) = 'AVAILABLE');
  SELECT count(*) INTO n FROM trustride.present_notification_inbox WHERE recipient_user_id = cust AND category = 'ORDER';
  PERFORM pg_temp.t_check('customer received a notification at every step (G12)', n >= 8, n::text);

  -- ============================ multi-stop (G7)
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02"}},
                     {"scope_detail":{"origin_zone_code":"KSM-MILIMANI-02","destination_zone_code":"KSM-KONDELE-03"}},
                     {"scope_detail":{"origin_zone_code":"KSM-KONDELE-03","destination_zone_code":"KSM-CBD-01"}}]'::jsonb));
  PERFORM pg_temp.t_check('three-stop order accepted', r->>'status' = 'TRANSLATED', r::text);
  o := pg_temp.t_order(r);  ord := o.order_id;
  PERFORM pg_temp.t_cycle(14);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  SELECT count(*) INTO n FROM trustride.business_job WHERE order_id = ord;
  PERFORM pg_temp.t_check('three stops -> three jobs, none dropped', n = 3, n::text || ' ' || o.status::text);
  SELECT fq.computed_total_fare_kes, (SELECT sum(line_fare_kes) FROM trustride.fare_quote_line l WHERE l.quote_id = fq.quote_id), (SELECT count(*) FROM trustride.fare_quote_line l WHERE l.quote_id = fq.quote_id)
  INTO total, sumlines, n FROM trustride.fare_quote fq WHERE fq.quote_id = o.quote_id;
  PERFORM pg_temp.t_check('every stop priced; order total = sum of stops', n = 3 AND total = sumlines AND total > 0, format('lines=%s total=%s sum=%s', n, total, sumlines));
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'ACCEPT_QUOTATION', jsonb_build_object('quote_id', o.quote_id));
  PERFORM pg_temp.t_cycle(4);
  SELECT operator_user_id INTO op FROM trustride.resource_workforce_unit WHERE workforce_unit_id = o.reserved_workforce_unit_id;
  r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'ACKNOWLEDGE_JOB', jsonb_build_object('order_id', ord));
  SELECT job_id INTO j FROM trustride.business_job WHERE order_id = ord AND line_sequence = 2;
  r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', jsonb_build_object('job_id', j.job_id));
  PERFORM pg_temp.t_check('stops are served in order (stop 2 waits for stop 1)', r->>'status' = 'REJECTED', r::text);
  FOR j IN SELECT job_id FROM trustride.business_job WHERE order_id = ord ORDER BY line_sequence LOOP
    FOR n IN 1..5 LOOP  -- DISPATCHED..COMPLETED
      r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', jsonb_build_object('job_id', j.job_id));
    END LOOP;
  END LOOP;
  PERFORM pg_temp.t_cycle(6);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('order completes only after the last stop', o.status = 'COMPLETED', o.status::text);
  SELECT amount_kes INTO total FROM trustride.integration_payment_gateway_transaction WHERE quote_id = o.quote_id;
  PERFORM pg_temp.t_check('payment request is for the whole order (sum of stops)', total = sumlines, format('%s vs %s', total, sumlines));
  -- Auto-verify releases the rider even if they never press Verify.
  UPDATE trustride.business_job SET completed_at = now() - interval '1 hour' WHERE order_id = ord;
  PERFORM trustride.fn_business_dispatch_sweep();
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('auto-verify releases the worker (no permanent reservation)',
    trustride.fn_resource_unit_availability((SELECT workforce_unit_id FROM trustride.business_job WHERE order_id = ord LIMIT 1)) = 'AVAILABLE');

  -- ============================ expiry, cancellation, decline, timeout, intervention
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD', 'order_lines', lines));
  o := pg_temp.t_order(r);  ord := o.order_id;
  PERFORM pg_temp.t_cycle(12);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  unit := o.reserved_workforce_unit_id;
  UPDATE trustride.fare_quote SET expires_at = now() - interval '1 minute' WHERE quote_id = o.quote_id;
  PERFORM trustride.fn_cost_quote_expire_sweep();
  PERFORM pg_temp.t_cycle(6);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('unconfirmed fare expires -> order EXPIRED', o.status = 'EXPIRED', o.status::text);
  PERFORM pg_temp.t_check('expired order releases its worker', trustride.fn_resource_unit_availability(unit) = 'AVAILABLE');
  PERFORM pg_temp.t_check('customer told it closed, not charged', EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = cust AND title = 'Order closed'));

  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD', 'order_lines', lines));
  o := pg_temp.t_order(r);  ord := o.order_id;
  PERFORM pg_temp.t_cycle(12);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  r := pg_temp.t_cmd(cust2, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'CANCEL_ORDER', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_check('another customer cannot cancel my order', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'CANCEL_ORDER', jsonb_build_object('order_id', ord, 'reason', 'Changed my mind'));
  PERFORM pg_temp.t_cycle(4);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('customer cancels before dispatch -> CANCELLED', o.status = 'CANCELLED', o.status::text);
  PERFORM pg_temp.t_check('cancelled order releases worker and quote', trustride.fn_resource_unit_availability(unit) = 'AVAILABLE'
    AND EXISTS (SELECT 1 FROM trustride.fare_quote WHERE quote_id = o.quote_id AND quote_state = 'CANCELLED'));

  -- decline -> the other rider gets it
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD', 'order_lines', lines));
  o := pg_temp.t_order(r);  ord := o.order_id;
  PERFORM pg_temp.t_cycle(12);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'ACCEPT_QUOTATION', jsonb_build_object('quote_id', o.quote_id));
  PERFORM pg_temp.t_cycle(4);
  unit := o.reserved_workforce_unit_id;
  SELECT operator_user_id INTO op FROM trustride.resource_workforce_unit WHERE workforce_unit_id = unit;
  r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'DECLINE_JOB', jsonb_build_object('order_id', ord, 'reason', 'Flat tyre'));
  PERFORM pg_temp.t_check('operator declines before setting off', r->>'status' = 'TRANSLATED', r::text);
  PERFORM pg_temp.t_cycle(14);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('order reassigned to the other rider, accepted price kept', o.status = 'JOB_CREATED' AND o.reserved_workforce_unit_id <> unit
    AND EXISTS (SELECT 1 FROM trustride.fare_quote WHERE quote_id = o.quote_id AND quote_state = 'FARE_LOCKED'), o.status::text);
  PERFORM pg_temp.t_check('declining rider is free again', trustride.fn_resource_unit_availability(unit) = 'AVAILABLE');
  -- the new rider never acknowledges -> timeout -> back to the first rider
  UPDATE trustride.fare_quote SET locked_at = now() - interval '10 minutes' WHERE quote_id = o.quote_id;
  UPDATE trustride.business_job SET created_at = now() - interval '10 minutes' WHERE order_id = ord AND status = 'CREATED';
  r := to_jsonb(trustride.fn_business_dispatch_sweep());
  PERFORM pg_temp.t_check('unacknowledged job is re-offered after the timeout', (r->>'reassigned_unacknowledged')::int >= 1, r::text);
  PERFORM pg_temp.t_cycle(14);
  -- Office intervention: cancel
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'INTERVENE_ORDER', jsonb_build_object('order_id', ord, 'action', 'CANCEL', 'reason', 'x'));
  PERFORM pg_temp.t_check('a customer cannot intervene', r->>'status' = 'SESSION_REFUSED', r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'INTERVENE_ORDER', jsonb_build_object('order_id', ord, 'action', 'CANCEL', 'reason', 'Customer called support'));
  PERFORM pg_temp.t_cycle(4);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('Office cancels an order; every rider is free', o.status = 'CANCELLED'
    AND trustride.fn_resource_unit_availability(boda) = 'AVAILABLE' AND trustride.fn_resource_unit_availability(boda2) = 'AVAILABLE', o.status::text);

  -- ============================ waiting too long -> EXPIRED + Office told
  PERFORM pg_temp.t_cmd((SELECT operator_user_id FROM trustride.resource_workforce_unit WHERE workforce_unit_id = boda), 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'SET_DUTY', '{"on_duty":false}');
  PERFORM pg_temp.t_cmd((SELECT operator_user_id FROM trustride.resource_workforce_unit WHERE workforce_unit_id = boda2), 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'SET_DUTY', '{"on_duty":false}');
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD', 'order_lines', lines));
  o := pg_temp.t_order(r);  ord := o.order_id;
  PERFORM pg_temp.t_cycle(10);
  UPDATE trustride.business_order SET waiting_since = now() - interval '2 hours' WHERE order_id = ord;
  PERFORM trustride.fn_business_dispatch_sweep();
  PERFORM pg_temp.t_cycle(4);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('waited past the limit -> EXPIRED (explicit end)', o.status = 'EXPIRED', o.status::text);
  PERFORM pg_temp.t_check('Office alerted to the unserved order', EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = founder AND category = 'ORDER_EXCEPTION'));

  -- ============================ scheduling (G11)
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD',
    'order_lines', lines, 'requested_start_at', now() + interval '3 hours'));
  o := pg_temp.t_order(r);  ord := o.order_id;
  PERFORM pg_temp.t_cycle(8);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('future order is SCHEDULED, not dispatched', o.status = 'SCHEDULED' AND o.dispatch_mode = 'SCHEDULED', o.status::text);
  PERFORM pg_temp.t_cmd((SELECT operator_user_id FROM trustride.resource_workforce_unit WHERE workforce_unit_id = boda), 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'SET_DUTY', '{"on_duty":true}');
  UPDATE trustride.business_order SET requested_start_at = now() + interval '10 minutes' WHERE order_id = ord;
  PERFORM trustride.fn_business_dispatch_sweep();
  PERFORM pg_temp.t_cycle(12);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('dispatch window opens -> matched and quoted', o.status = 'QUOTED', o.status::text);
  PERFORM pg_temp.t_check('scheduled jobs carry their window', EXISTS (SELECT 1 FROM trustride.business_job WHERE order_id = ord AND job_type = 'SCHEDULED' AND scheduled_window_start IS NOT NULL));
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'CANCEL_ORDER', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_check('a scheduled order can be cancelled', r->>'status' = 'TRANSLATED', r::text);
  PERFORM pg_temp.t_check('Sunday is off duty: next working open after Sunday noon is Monday 05:00',
    to_char(trustride.fn_business_next_working_open(('2026-10-11 12:00 Africa/Nairobi')::timestamptz) AT TIME ZONE 'Africa/Nairobi', 'Dy HH24:MI') = 'Mon 05:00'
    OR (SELECT config_value FROM trustride.platform_configuration WHERE config_key = 'WORKING_WINDOW_SUNDAY') <> 'OFF_DUTY');
  PERFORM pg_temp.t_check('D1: the Sunday/holiday EA rate is retired', NOT EXISTS (SELECT 1 FROM trustride.cost_ea_shift_multiplier WHERE shift_type = 'SUNDAY_HOLIDAY' AND active));

  -- ============================ every dispatch service reaches a priced estimate
  PERFORM pg_temp.t_ready_unit(founder, 'TUKTUK', est, 'Tuk Rider');
  PERFORM pg_temp.t_ready_unit(founder, 'SEDAN', est, 'Sedan Driver');
  PERFORM pg_temp.t_ready_unit(founder, 'PICKUP_TOWN', est, 'Pickup Driver');
  PERFORM pg_temp.t_ready_unit(founder, 'VAN_CARGO', est, 'Van Driver');
  PERFORM pg_temp.t_cmd((SELECT operator_user_id FROM trustride.resource_workforce_unit WHERE workforce_unit_id = boda2), 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'SET_DUTY', '{"on_duty":true}');
  PERFORM pg_temp.t_ready_unit(founder, 'EXECUTIVE_ASSISTANT_HUMAN', est, 'EA General',
    ARRAY['SKILL_ERRANDS', 'SKILL_SHOPPING', 'SKILL_DRIVING', 'SKILL_CLEANING', 'SKILL_CHEF']);
  PERFORM pg_temp.t_ready_unit(founder, 'EXECUTIVE_ASSISTANT_HUMAN', est, 'EA Safeguarded',
    ARRAY['ENHANCED_VETTING_CLEARANCE', 'CHILD_SAFEGUARDING_CERT', 'FIRST_AID_CERT', 'SKILL_CAREGIVING', 'SKILL_ERRANDS', 'SKILL_DRIVING']);
  FOR svc IN SELECT sc.service_code, sm.domain_code::text AS dom FROM trustride.service_catalogue sc JOIN trustride.service_macro_domain sm ON sm.macro_domain_id = sc.macro_domain_id
             WHERE sc.requirements->>'fulfilment' = 'DISPATCH' ORDER BY sc.service_code LOOP
    r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', svc.service_code,
      'order_lines', CASE WHEN svc.dom = 'EXECUTIVE_ASSISTANTS' THEN '[{"scope_detail":{"origin_zone_code":"KSM-MILIMANI-02","billed_hours":3}}]'::jsonb ELSE lines END));
    o := pg_temp.t_order(r);  ord := o.order_id;
    PERFORM pg_temp.t_cycle(14);
    SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
    SELECT computed_total_fare_kes INTO total FROM trustride.fare_quote WHERE quote_id = o.quote_id;
    PERFORM pg_temp.t_check('service ' || svc.service_code || ' -> matched and priced', o.status = 'QUOTED' AND total > 0,
      coalesce(o.status::text, 'no order: ' || (r::text)) || ' ' || coalesce(o.status_reason, '') || ' KES ' || coalesce(total::text, '-'));
    PERFORM pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'DECLINE_QUOTATION', jsonb_build_object('quote_id', o.quote_id));
    PERFORM pg_temp.t_cycle(4);
  END LOOP;
  PERFORM pg_temp.t_check('declined fares release every worker', NOT EXISTS (
    SELECT 1 FROM trustride.resource_workforce_unit wu WHERE wu.unit_status = 'ACTIVE' AND trustride.fn_resource_unit_availability(wu.workforce_unit_id) IN ('RESERVED', 'ASSIGNED')));

  -- ============================ Journey F: EA safeguarding and pricing failure
  PERFORM pg_temp.t_cmd((SELECT wu.operator_user_id FROM trustride.resource_workforce_unit wu JOIN trustride.platform_users p ON p.user_id = wu.operator_user_id WHERE p.display_name = 'EA Safeguarded'),
    'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'SET_DUTY', '{"on_duty":false}');
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'EA-CAREGIVING-GENERAL',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-MILIMANI-02","billed_hours":4}}]'::jsonb));
  o := pg_temp.t_order(r);  ord := o.order_id;
  PERFORM pg_temp.t_cycle(10);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('caregiving is never given to an un-vetted EA (waits instead)', o.status = 'WAITING', o.status::text);
  PERFORM trustride.fn_business_order_cancel(ord, cust, 'test');
  UPDATE trustride.cost_ea_rate SET active = FALSE WHERE ea_skill_category = 'CERTIFIED_CHEF';
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'EA-CHEF-GENERAL',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-MILIMANI-02","billed_hours":3}}]'::jsonb));
  o := pg_temp.t_order(r);  ord := o.order_id;
  PERFORM pg_temp.t_cycle(14);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('pricing failure -> order FAILED explicitly (G5)', o.status = 'FAILED', o.status::text || ' ' || coalesce(o.status_reason, ''));
  PERFORM pg_temp.t_check('pricing failure releases the reserved EA (G5)', NOT EXISTS (
    SELECT 1 FROM trustride.resource_workforce_unit wu WHERE wu.unit_status = 'ACTIVE' AND trustride.fn_resource_unit_availability(wu.workforce_unit_id) IN ('RESERVED', 'ASSIGNED')));
  PERFORM pg_temp.t_check('customer told, not charged', EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = cust AND title = 'We could not complete your order'));

  -- ============================ intake services (G6)
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'ENROLL_ACADEMY', '{"programme":"Professional Chauffeur","preferred_start":"2026-11-02"}');
  PERFORM pg_temp.t_check('Academy enrollment becomes a governed Office request', r->>'status' = 'TRANSLATED' AND EXISTS (
    SELECT 1 FROM trustride.business_order WHERE order_id = (r->>'signal')::uuid AND order_root_type = 'ACADEMY_ENROLLMENT_REQUEST'), r::text);
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('enrollee told it is with Office', EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = cust AND title = 'Academy enrollment received'));
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'APPLY_EMPLOYMENT', '{"role_sought":"Executive Assistant (chef)","experience":"5 years"}');
  PERFORM pg_temp.t_check('employment application becomes an Operator access request', r->>'status' = 'TRANSLATED' AND EXISTS (
    SELECT 1 FROM trustride.business_order WHERE order_id = (r->>'signal')::uuid AND order_root_type = 'OFFICE_ACCESS_REQUEST'), r::text);

  -- ============================ integrity
  SELECT count(*) INTO n FROM trustride.business_order WHERE order_root_type = 'SERVICE_ORDER' AND status IN ('PLACED', 'VALIDATED') AND updated_at < now() - interval '1 second';
  PERFORM pg_temp.t_check('no service order left in a transient state', n = 0, n::text);
  SELECT count(*) INTO n FROM (
    SELECT signal_id FROM trustride.business_event_inbox WHERE signal_status = 'RECEIVED'
    UNION ALL SELECT signal_id FROM trustride.resource_event_inbox WHERE signal_status = 'RECEIVED'
    UNION ALL SELECT signal_id FROM trustride.cost_event_inbox WHERE signal_status = 'RECEIVED'
    UNION ALL SELECT signal_id FROM trustride.integration_event_inbox WHERE signal_status = 'RECEIVED'
    UNION ALL SELECT signal_id FROM trustride.present_event_inbox WHERE signal_status = 'RECEIVED'
    UNION ALL SELECT signal_id FROM trustride.service_event_inbox WHERE signal_status = 'RECEIVED') z;
  PERFORM pg_temp.t_check('no signal left unprocessed (no swallowed handler errors)', n = 0, n::text);
  SELECT count(*) INTO n FROM trustride.fn_platform_conformance_violations();
  PERFORM pg_temp.t_check('conformance: zero violations', n = 0, n || ' violations');
END;
$$;
