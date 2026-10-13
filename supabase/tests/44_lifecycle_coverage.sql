-- Suite 44 -- lifecycle coverage across every dispatched catalogue service (WP9). Each service is driven
-- through the seven constitutional stages of TBOC Art.19 with a resource of the class and certifications its
-- eligibility rule requires:
--   1 Placement and Scope         2 Assignment Validation and Job Creation   3 Dispatch
--   4 Execution and Completion    5 Payment and Settlement                   6 Review, Rate and Support
--   7 Resource Availability
-- Executive Assistant trades whose gazetted occupation still awaits the Founder (caregiver, corporate
-- representative) must stop at pricing with an explicit refusal -- never priced on an uncertain basis.
DO $$
DECLARE
  founder UUID; cust UUID; est UUID; s RECORD; unit UUID; r JSONB; o trustride.business_order; ord UUID; j UUID; op UUID; i INT;
  st TEXT; v TEXT; lines JSONB; pending BOOLEAN; n INT := 0; k INT := 0;
BEGIN
  PERFORM pg_temp.t_open_all_hours();
  founder := pg_temp.t_person('LC Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  cust := pg_temp.t_customer('LC Customer');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"LC-HUB","estate_type":"OPERATING_HUB","estate_name":"Lifecycle Hub","lat":-0.0917,"lon":34.7680}');
  est := (r->>'signal')::uuid;

  FOR s IN
    SELECT sc.service_code, sm.domain_code, er.required_capacity_class_code AS cls,
           ARRAY(SELECT jsonb_array_elements_text(coalesce(er.required_certifications, '[]'::jsonb)))
             || CASE WHEN er.required_vetting_tier = 'ENHANCED' THEN ARRAY['ENHANCED_VETTING_CLEARANCE'] ELSE ARRAY[]::text[] END AS caps,
           coalesce((SELECT eo.mapping_status FROM trustride.cost_ea_trade_occupation eo WHERE eo.ea_skill_category::text = sc.requirements->>'ea_skill_category'), '') AS mapping
    FROM trustride.service_catalogue sc JOIN trustride.service_macro_domain sm ON sm.macro_domain_id = sc.macro_domain_id
    JOIN trustride.service_eligibility_rule er ON er.service_id = sc.service_id AND er.active
    WHERE sc.status = 'ACTIVE' AND sc.requirements->>'fulfilment' = 'DISPATCH'
    ORDER BY sm.domain_code, sc.service_code
  LOOP
    k := k + 1;
    pending := s.mapping = 'NEAREST_OCCUPATION_PENDING_FOUNDER';
    PERFORM pg_temp.t_release_completed();
    unit := pg_temp.t_ready_unit(founder, s.cls, est, 'LC ' || s.service_code, s.caps);
    lines := CASE WHEN s.domain_code = 'EXECUTIVE_ASSISTANTS'
                  THEN '[{"scope_detail":{"origin_zone_code":"KSM-MILIMANI-02","billed_hours":3}}]'::jsonb
                  ELSE '[{"scope_detail":{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02"}}]'::jsonb END;

    -- 1 placement and scope
    r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', s.service_code, 'order_lines', lines));
    ord := (pg_temp.t_order(r)).order_id;
    PERFORM pg_temp.t_check(s.service_code || ' 1 placement: order placed with its scope', r->>'status' = 'TRANSLATED' AND ord IS NOT NULL
      AND EXISTS (SELECT 1 FROM trustride.business_order_line WHERE order_id = ord), r::text);
    PERFORM pg_temp.t_cycle(14);
    SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;

    IF pending THEN
      PERFORM pg_temp.t_check(s.service_code || ' 2 assignment: refused at pricing while its occupation awaits the Founder (no uncertain price)',
        o.quote_id IS NULL AND (o.status::text IN ('FAILED', 'DECLINED', 'CANCELLED') OR coalesce(o.status_reason, '') ILIKE '%AWAITING%DETERMINATION%'),
        o.status::text || ' ' || coalesce(o.status_reason, ''));
      CONTINUE;
    END IF;

    -- 2 assignment validation and job creation
    PERFORM pg_temp.t_check(s.service_code || ' 2 assignment: a qualified resource reserved and a price quoted', o.status::text = 'QUOTED' AND o.quote_id IS NOT NULL,
      o.status::text || ' ' || coalesce(o.status_reason, ''));
    IF o.quote_id IS NULL THEN CONTINUE; END IF;
    PERFORM pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'ACCEPT_QUOTATION', jsonb_build_object('quote_id', o.quote_id));
    PERFORM pg_temp.t_cycle(4);
    SELECT job_id INTO j FROM trustride.business_job WHERE order_id = ord;
    SELECT wu.operator_user_id INTO op FROM trustride.business_job bj JOIN trustride.resource_workforce_unit wu ON wu.workforce_unit_id = bj.workforce_unit_id WHERE bj.job_id = j;
    PERFORM pg_temp.t_check(s.service_code || ' 2 job: accepting the price creates the job for the reserved resource', j IS NOT NULL AND op IS NOT NULL);
    IF j IS NULL THEN CONTINUE; END IF;

    -- 3 dispatch
    FOR i IN 1..2 LOOP PERFORM pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', jsonb_build_object('job_id', j)); END LOOP;
    PERFORM pg_temp.t_cycle(4);
    SELECT status::text INTO st FROM trustride.business_job WHERE job_id = j;
    PERFORM pg_temp.t_check(s.service_code || ' 3 dispatch: acknowledged and dispatched', st IN ('DISPATCHED', 'EN_ROUTE', 'ARRIVED', 'EXECUTING'), st);

    -- 4 execution and completion
    FOR i IN 1..4 LOOP PERFORM pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', jsonb_build_object('job_id', j)); END LOOP;
    PERFORM pg_temp.t_cycle(8);
    SELECT status::text INTO st FROM trustride.business_job WHERE job_id = j;
    PERFORM pg_temp.t_check(s.service_code || ' 4 execution: executed and completed', st = 'COMPLETED', st);

    -- 5 payment and settlement
    PERFORM pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'CONFIRM_SIMULATED_PAYMENT', jsonb_build_object('order_id', ord));
    PERFORM pg_temp.t_cycle(8);
    SELECT o2.status::text || '|' || coalesce(s2.receipt_code, '') || '|' || (s2.computed_total_fare_kes = q.computed_total_fare_kes)::text INTO v
    FROM trustride.business_order o2 JOIN trustride.business_settlement s2 ON s2.order_id = o2.order_id
    JOIN trustride.fare_quote q ON q.quote_id = o2.quote_id WHERE o2.order_id = ord;
    PERFORM pg_temp.t_check(s.service_code || ' 5 payment: settled for exactly the accepted price, receipt issued',
      v LIKE 'SETTLED|_%|true', coalesce(v, 'no settlement'));

    -- 6 review, rate and support
    r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'SUBMIT_REVIEW', jsonb_build_object('order_id', ord, 'rating', 5));
    PERFORM pg_temp.t_check(s.service_code || ' 6 review: the customer rates the service', r->>'status' = 'TRANSLATED', r::text);
    r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'OPEN_SUPPORT_CASE', jsonb_build_object('order_id', ord, 'category', 'ORDER_ISSUE', 'subject', 'Lifecycle check', 'body', 'Follow-up'));
    PERFORM pg_temp.t_check(s.service_code || ' 6 support: a support case can be opened on the order', r->>'status' = 'TRANSLATED', r::text);

    -- 7 resource availability
    PERFORM pg_temp.t_release_completed();
    SELECT trustride.fn_resource_unit_availability(bj.workforce_unit_id) INTO st FROM trustride.business_job bj WHERE bj.job_id = j;
    PERFORM pg_temp.t_check(s.service_code || ' 7 availability: the resource is released and available again', st = 'AVAILABLE', st);
    n := n + 1;
  END LOOP;
  PERFORM pg_temp.t_check('lifecycle: every dispatched catalogue service was exercised (' || k || ' services, ' || n || ' through all seven stages)', k >= 16, k::text);
END
$$;
