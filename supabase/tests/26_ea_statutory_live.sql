-- Suite 26 -- live Executive Assistant quotes use the statutory method (Construction Directive WP3, D24).
-- The price shown, accepted, prompted for payment and settled is the EA-STATUTORY-1.0.0 estimate;
-- hours and days, night hours, minimum engagement and engagement limits follow the method;
-- a trade whose gazetted occupation is still awaiting determination is refused, never priced on
-- an uncertain basis; an EA quote cannot be issued from the superseded equation; transport pricing
-- is untouched.
DO $$
DECLARE
  founder UUID; cust UUID; est UUID; ea UUID; op UUID; r JSONB; o RECORD; ord UUID; q RECORD; e RECORD; c RECORD; j UUID;
  v TEXT; n INT; total NUMERIC; hourly NUMERIC; daily NUMERIC; i INT; calc UUID; ok BOOLEAN; nxt TIMESTAMPTZ;
BEGIN
  PERFORM pg_temp.t_open_all_hours();
  founder := pg_temp.t_person('EAS Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  cust := pg_temp.t_customer('EAS Cust');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"EAS-26","estate_name":"EAS Hub","estate_type":"OPERATING_HUB","lat":-0.10,"lon":34.75}');
  est := (r->>'signal')::uuid;
  ea := pg_temp.t_ready_unit(founder, 'EXECUTIVE_ASSISTANT_HUMAN', est, 'EAS Assistant', ARRAY['SKILL_ERRANDS', 'SKILL_SHOPPING', 'SKILL_CLEANING']);
  SELECT operator_user_id INTO op FROM trustride.resource_workforce_unit WHERE workforce_unit_id = ea;
  SELECT w.hourly_kes, w.daily_kes INTO hourly, daily FROM trustride.cost_labour_statutory_wage w
  JOIN trustride.cost_labour_zone_wage_area m ON m.wage_area_code = w.wage_area_code JOIN trustride.cost_operational_zones z ON z.zone_id = m.zone_id
  WHERE z.zone_code = 'KSM-MILIMANI-02' AND w.occupation_row = 1 AND w.active;

  -- ============ hourly engagement, priced statutorily end to end
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'EA-ERRANDS-GENERAL',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-MILIMANI-02","billed_hours":3}}]'::jsonb));
  ord := (pg_temp.t_order(r)).order_id;
  PERFORM pg_temp.t_cycle(14);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  SELECT * INTO q FROM trustride.fare_quote WHERE quote_id = o.quote_id;
  SELECT * INTO c FROM trustride.fare_calculation WHERE calculation_id = q.calculation_id;
  SELECT * INTO e FROM trustride.cost_ea_engagement_estimate WHERE order_id = ord ORDER BY created_at DESC LIMIT 1;
  PERFORM pg_temp.t_check('errands, 3 hours: quoted', o.status::text = 'QUOTED', o.status::text || ' ' || coalesce(o.status_reason, ''));
  PERFORM pg_temp.t_check('the quote is the statutory estimate (EA-STATUTORY-1.0.0)', c.model_version = 'EA-STATUTORY-1.0.0' AND e.estimate_id IS NOT NULL
    AND q.computed_total_fare_kes = e.total_kes AND to_jsonb(e)->>'calculation_id' = c.calculation_id::text,
    coalesce(c.model_version, 'none') || ' quote ' || coalesce(q.computed_total_fare_kes::text, '-') || ' estimate ' || coalesce(e.total_kes::text, '-'));
  PERFORM pg_temp.t_check('worker pay is at least the gazetted hourly minimum x hours', e.worker_pay_kes >= round(3 * hourly, 2),
    e.worker_pay_kes || ' >= ' || round(3 * hourly, 2));
  PERFORM pg_temp.t_check('the customer price covers the worker''s legal pay', q.computed_total_fare_kes > e.worker_pay_kes);
  PERFORM pg_temp.t_check('every price line cites a provision', NOT EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line WHERE estimate_id = e.estimate_id AND provision_code IS NULL)
    AND (SELECT count(*) FROM trustride.fare_calculation_line WHERE calculation_id = c.calculation_id) =
        (SELECT count(*) FROM trustride.cost_ea_engagement_line WHERE estimate_id = e.estimate_id AND line_role = 'PRICE'));

  -- accept, work, pay: the amount prompted and settled is the statutory quote
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'ACCEPT_QUOTATION', jsonb_build_object('quote_id', q.quote_id));
  PERFORM pg_temp.t_cycle(4);
  SELECT job_id INTO j FROM trustride.business_job WHERE order_id = ord;
  SELECT wu.operator_user_id INTO op FROM trustride.business_job bj JOIN trustride.resource_workforce_unit wu ON wu.workforce_unit_id = bj.workforce_unit_id WHERE bj.job_id = j;
  FOR i IN 1..6 LOOP PERFORM pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', jsonb_build_object('job_id', j)); END LOOP;
  PERFORM pg_temp.t_cycle(8);
  SELECT amount_kes INTO total FROM trustride.integration_payment_gateway_transaction WHERE order_id = ord ORDER BY initiated_at LIMIT 1;
  PERFORM pg_temp.t_check('the payment prompt is for the statutory quote', total = q.computed_total_fare_kes, coalesce(total::text, 'no payment') || ' vs ' || q.computed_total_fare_kes);
  PERFORM pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'CONFIRM_SIMULATED_PAYMENT', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_cycle(8);
  SELECT computed_total_fare_kes INTO total FROM trustride.business_settlement WHERE order_id = ord;
  PERFORM pg_temp.t_check('the settlement is for the statutory quote', total = q.computed_total_fare_kes, coalesce(total::text, 'no settlement'));
  PERFORM pg_temp.t_release_completed();

  -- ============ by the day, two days
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'EA-CLEANING-GENERAL',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-MILIMANI-02","engagement_unit":"DAYS","billed_days":2,"billed_hours":8}}]'::jsonb));
  ord := (pg_temp.t_order(r)).order_id;
  PERFORM pg_temp.t_cycle(14);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  SELECT * INTO e FROM trustride.cost_ea_engagement_estimate WHERE order_id = ord ORDER BY created_at DESC LIMIT 1;
  SELECT count(*) INTO n FROM trustride.cost_ea_engagement_line WHERE estimate_id = e.estimate_id AND component_code = 'EA_WORKER_PAY_DAILY' AND quantity = 2;
  PERFORM pg_temp.t_check('cleaning, 2 days: quoted on the gazetted daily rate', o.status::text = 'QUOTED' AND n = 1 AND e.worker_pay_kes >= 2 * daily,
    o.status::text || ' daily-lines=' || n || ' worker ' || coalesce(e.worker_pay_kes::text, '-'));
  PERFORM pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'DECLINE_QUOTATION', jsonb_build_object('quote_id', o.quote_id));
  PERFORM pg_temp.t_cycle(4);

  -- ============ night hours priced with the night uplift (scheduled 20:00 Nairobi on the next weekday)
  nxt := ((now() AT TIME ZONE 'Africa/Nairobi')::date + CASE extract(isodow FROM now() AT TIME ZONE 'Africa/Nairobi') WHEN 5 THEN 3 WHEN 6 THEN 2 ELSE 1 END + time '20:00') AT TIME ZONE 'Africa/Nairobi';
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'EA-ERRANDS-GENERAL', 'requested_start_at', nxt,
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-MILIMANI-02","billed_hours":2}}]'::jsonb));
  ord := (pg_temp.t_order(r)).order_id;
  SELECT scope_detail->>'start_at' INTO v FROM trustride.business_order_line WHERE order_id = ord ORDER BY line_sequence LIMIT 1;
  PERFORM pg_temp.t_check('the order records when the engagement really starts (scheduled 20:00)', v::timestamptz = nxt, coalesce(v, 'none') || ' vs ' || nxt);
  -- the live pricing function, given that line as Business sends it, prices the evening hours as night hours
  SELECT scope_detail INTO r FROM trustride.business_order_line WHERE order_id = ord ORDER BY line_sequence LIMIT 1;
  calc := trustride.fn_cost_ea_statutory_calculate('PERSONAL_SHOPPER_ERRAND', 'KISUMU_COUNTY', 'KSM-MILIMANI-02', jsonb_build_object('scope_detail', r),
    cust, gen_random_uuid(), ord, NULL, 'EA-ERRANDS-GENERAL');
  SELECT * INTO e FROM trustride.cost_ea_engagement_estimate WHERE calculation_id = calc;
  SELECT count(*) INTO n FROM trustride.cost_ea_engagement_line WHERE estimate_id = e.estimate_id AND component_code = 'EA_WORKER_PAY_NIGHT';
  PERFORM pg_temp.t_check('an evening engagement is priced from its real start (night lines present)', n = 1, n || ' night lines; estimate ' || coalesce(e.estimate_id::text, 'none'));
  PERFORM trustride.fn_business_order_cancel(ord, cust, 'suite 26');
  PERFORM pg_temp.t_cycle(4);

  -- ============ engagement limits are refused at the order, with the reason
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'EA-CLEANING-GENERAL',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-MILIMANI-02","engagement_unit":"DAYS","billed_days":7,"billed_hours":8}}]'::jsonb));
  PERFORM pg_temp.t_check('seven days in one engagement is refused (a rest day in every seven)', r->>'status' <> 'TRANSLATED' AND r->>'reason' ILIKE '%rest day%', left(r::text, 160));
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'EA-CLEANING-GENERAL',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-MILIMANI-02","engagement_unit":"WEEKS","billed_hours":8}}]'::jsonb));
  PERFORM pg_temp.t_check('an unknown booking unit is refused', r->>'status' <> 'TRANSLATED', left(r::text, 160));

  -- ============ a trade awaiting determination of its gazetted occupation is refused, not priced
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'EA-SHOPPING-REPRESENTATION_DELIVERY',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-MILIMANI-02","billed_hours":2}}]'::jsonb));
  ord := (pg_temp.t_order(r)).order_id;
  PERFORM pg_temp.t_cycle(14);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('corporate representation (occupation awaiting determination) is refused with the reason, unpriced',
    o.status::text IN ('FAILED', 'WAITING') AND o.quote_id IS NULL AND (o.status::text = 'WAITING' OR coalesce(o.status_reason, '') ILIKE '%determination%'),
    o.status::text || ' ' || coalesce(o.status_reason, ''));
  PERFORM pg_temp.t_check('no worker is left reserved by the refusal', NOT EXISTS (
    SELECT 1 FROM trustride.resource_workforce_unit wu WHERE wu.unit_status = 'ACTIVE' AND trustride.fn_resource_unit_availability(wu.workforce_unit_id) IN ('RESERVED', 'ASSIGNED')));

  -- ============ the superseded equation cannot produce an EA quote
  calc := trustride.fn_cost_ea_labor_calculate('PERSONAL_SHOPPER_ERRAND', 'KISUMU_COUNTY', 'KSM-MILIMANI-02', 3, 'DAY', 0, 0, cust, gen_random_uuid(), NULL, NULL, 'EA-ERRANDS-GENERAL');
  BEGIN
    INSERT INTO trustride.fare_quote (calculation_id, quote_code, computed_total_fare_kes, currency, quote_hash, expires_at, correlation_id)
    VALUES (calc, 'SUITE26-BYPASS', 100, 'KES', repeat('a', 64), now() + interval '10 minutes', gen_random_uuid());
    ok := false; v := 'quote issued';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%statutory%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('an EA quote from the superseded EA-LABOR equation is refused', ok, left(v, 160));
  PERFORM pg_temp.t_check('no signed-in role can call EA pricing directly', NOT has_function_privilege('authenticated',
    'trustride.fn_cost_ea_engagement_rate(trustride.ea_skill_category_enum,text,text,jsonb,uuid,uuid,uuid)', 'EXECUTE'));

  -- ============ transport is untouched
  PERFORM pg_temp.t_ready_unit(founder, 'BODA_BODA', est, 'EAS Rider');
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02"}}]'::jsonb));
  ord := (pg_temp.t_order(r)).order_id;
  PERFORM pg_temp.t_cycle(14);
  SELECT c2.model_version INTO v FROM trustride.business_order o2 JOIN trustride.fare_quote q2 ON q2.quote_id = o2.quote_id
  JOIN trustride.fare_calculation c2 ON c2.calculation_id = q2.calculation_id WHERE o2.order_id = ord;
  PERFORM pg_temp.t_check('a boda trip is still priced by the established transport equation', v IS NOT NULL AND v NOT LIKE 'EA-%', coalesce(v, 'not priced'));
END
$$;
