-- Suite 38 -- catalogue management and its cost-registry linkage (Construction Directive 2.11, WP8).
-- Engine 3 owns the catalogue; Engine 5 owns pricing and is only read. The Office registers DISPATCH services
-- (the special intents of TBOC Art.18 are fixed), adds coverage, and activates only when every covered
-- jurisdiction has an active Engine 5 pricing row; suspension stops new orders but not orders in flight;
-- retirement needs no open orders. Every transition is audited and broadcast; repeats are harmless.
DO $$
DECLARE
  founder UUID; admin UUID; cust UUID; est UUID; r JSONB; v TEXT; n INT; sid UUID; boda UUID; o trustride.business_order; ord UUID;
  op UUID; j UUID; i INT; reg_before INT; t RECORD;
  ready BOOLEAN := to_regprocedure('trustride.fn_present_cmd_register_service(uuid,jsonb,uuid)') IS NOT NULL;
BEGIN
  IF NOT ready THEN
    PERFORM pg_temp.t_check('catalogue management commands exist', false, 'fn_present_cmd_register_service absent');
  ELSE
  PERFORM pg_temp.t_open_all_hours();
  founder := pg_temp.t_person('Cat Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  admin := pg_temp.t_person('Cat Admin', NULL);  PERFORM pg_temp.t_role(admin, 'ADMINISTRATOR');
  cust := pg_temp.t_customer('Cat Customer');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"C-HUB","estate_type":"OPERATING_HUB","estate_name":"Catalogue Hub","lat":-0.0917,"lon":34.7680}');
  est := (r->>'signal')::uuid;
  PERFORM pg_temp.t_ready_unit(founder, 'BODA_BODA', est, 'Rider C');
  SELECT count(*) INTO reg_before FROM trustride.cost_registry;
  SELECT service_id INTO boda FROM trustride.service_catalogue WHERE service_code = 'TRANSPORT-BODA-STANDARD';

  -- ============ register a draft
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_SERVICE', '{"service_code":"TRANSPORT-BODA-EXPRESS","service_name":"Express Ride (Boda Boda)","macro_domain":"TRANSPORT","description":"Priority motorcycle ride.","fulfilment":"DISPATCH"}');
  sid := (r->>'signal')::uuid;
  PERFORM pg_temp.t_check('catalogue: the Office registers a DISPATCH service as a DRAFT',
    r->>'status' = 'TRANSLATED' AND (SELECT status::text FROM trustride.service_catalogue WHERE service_id = sid) = 'DRAFT'
    AND (SELECT requirements->>'fulfilment' FROM trustride.service_catalogue WHERE service_id = sid) = 'DISPATCH', r::text);
  PERFORM pg_temp.t_check('catalogue: registration is audited with the person',
    EXISTS (SELECT 1 FROM trustride.audit_log WHERE entity_id = sid AND action = 'SERVICE_REGISTERED' AND actor_id = admin));
  FOR t IN SELECT * FROM (VALUES
      ('a malformed service code', '{"service_code":"boda express","service_name":"X","macro_domain":"TRANSPORT","description":"x","fulfilment":"DISPATCH"}'),
      ('a special intent (fixed by TBOC Art.18)', '{"service_code":"EA-ACADEMY-ADVANCED","service_name":"X","macro_domain":"EXECUTIVE_ASSISTANTS","description":"x","fulfilment":"INTAKE"}'),
      ('a sixth domain', '{"service_code":"FLIGHT-CHARTER","service_name":"X","macro_domain":"AVIATION","description":"x","fulfilment":"DISPATCH"}'),
      ('an Executive Assistant service without its pillar', '{"service_code":"EA-ERRANDS-EXTRA","service_name":"X","macro_domain":"EXECUTIVE_ASSISTANTS","description":"x","fulfilment":"DISPATCH","ea_skill_category":"PERSONAL_SHOPPER_ERRAND"}'),
      ('an Executive Assistant skill Engine 5 cannot rate', '{"service_code":"EA-ERRANDS-EXTRA","service_name":"X","macro_domain":"EXECUTIVE_ASSISTANTS","description":"x","fulfilment":"DISPATCH","pillar":"ERRANDS","ea_skill_category":"ASTRONAUT"}'),
      ('a code already in the catalogue', '{"service_code":"TRANSPORT-BODA-STANDARD","service_name":"X","macro_domain":"TRANSPORT","description":"x","fulfilment":"DISPATCH"}'),
      ('a service with no description', '{"service_code":"TRANSPORT-BODA-NIGHT","service_name":"X","macro_domain":"TRANSPORT","fulfilment":"DISPATCH"}')) x(label, payload) LOOP
    r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_SERVICE', t.payload::jsonb);
    PERFORM pg_temp.t_check('catalogue: ' || t.label || ' is refused', r->>'status' = 'REJECTED', r::text);
  END LOOP;
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_SERVICE', '{"service_code":"EA-ERRANDS-PRIORITY","service_name":"Priority Errands","macro_domain":"EXECUTIVE_ASSISTANTS","description":"Same-day errands.","fulfilment":"DISPATCH","pillar":"ERRANDS","ea_skill_category":"PERSONAL_SHOPPER_ERRAND"}');
  PERFORM pg_temp.t_check('catalogue: a valid Executive Assistant service is registered with its pillar and an Engine 5-rated skill',
    r->>'status' = 'TRANSLATED' AND (SELECT requirements->>'ea_skill_category' FROM trustride.service_catalogue WHERE service_code = 'EA-ERRANDS-PRIORITY') = 'PERSONAL_SHOPPER_ERRAND', r::text);
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_SERVICE', '{"service_code":"EA-ERRANDS-EXTRA","service_name":"X","macro_domain":"EXECUTIVE_ASSISTANTS","description":"x","fulfilment":"DISPATCH","pillar":"ERRANDS","ea_skill_category":"ASTRONAUT"}');
  PERFORM pg_temp.t_check('catalogue: an unrated skill is refused for that reason', r->>'reason' ILIKE '%Engine 5 rates%', r::text);
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_SERVICE', '{"service_code":"EA-ERRANDS-EXTRA","service_name":"X","macro_domain":"EXECUTIVE_ASSISTANTS","description":"x","fulfilment":"DISPATCH","ea_skill_category":"PERSONAL_SHOPPER_ERRAND"}');
  PERFORM pg_temp.t_check('catalogue: a missing pillar is refused for that reason', r->>'reason' ILIKE '%pillar%', r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_SERVICE', '{"service_code":"TRANSPORT-BODA-FAKE","service_name":"X","macro_domain":"TRANSPORT","description":"x","fulfilment":"DISPATCH"}');
  PERFORM pg_temp.t_check('catalogue: a customer cannot change the catalogue', coalesce(r->>'status', '') <> 'TRANSLATED', r::text);
  PERFORM pg_temp.t_check('catalogue: the Engine 3 functions are not callable directly by signed-in users',
    NOT has_function_privilege('authenticated', 'trustride.fn_service_catalogue_activate(uuid,uuid,uuid)', 'EXECUTE')
    AND NOT has_function_privilege('authenticated', 'trustride.fn_present_cmd_register_service(uuid,jsonb,uuid)', 'EXECUTE'));

  -- ============ coverage and the pricing linkage
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ACTIVATE_SERVICE', jsonb_build_object('service_id', sid));
  PERFORM pg_temp.t_check('catalogue: a service with no coverage cannot be activated', r->>'status' = 'REJECTED' AND r->>'reason' ILIKE '%coverage%', r::text);
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ADD_SERVICE_COVERAGE', jsonb_build_object('service_id', sid, 'jurisdiction', 'KISUMU_COUNTY'));
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ADD_SERVICE_COVERAGE', jsonb_build_object('service_id', sid, 'jurisdiction', 'KISUMU_COUNTY'));
  SELECT count(*) INTO n FROM trustride.service_coverage_zone WHERE service_id = sid AND active;
  PERFORM pg_temp.t_check('catalogue: coverage is added once (a repeat changes nothing)', r->>'status' = 'TRANSLATED' AND n = 1, n::text);
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ADD_SERVICE_COVERAGE', jsonb_build_object('service_id', sid, 'jurisdiction', 'ATLANTIS'));
  PERFORM pg_temp.t_check('catalogue: an unknown jurisdiction is refused', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ACTIVATE_SERVICE', jsonb_build_object('service_id', sid));
  PERFORM pg_temp.t_check('catalogue: a DISPATCH service without an Engine 5 pricing row for its coverage cannot be activated',
    r->>'status' = 'REJECTED' AND r->>'reason' ILIKE '%pricing%KISUMU_COUNTY%', r::text);
  PERFORM pg_temp.t_check('catalogue: nothing was written to Engine 5', (SELECT count(*) FROM trustride.cost_registry) = reg_before);
  r := trustride.fn_present_proj_office_catalogue(NULL, '{}');
  SELECT x INTO r FROM jsonb_array_elements(r->'services') x WHERE x->>'service_id' = sid::text;
  PERFORM pg_temp.t_check('catalogue: the Office sees why the draft cannot go live yet',
    r->>'status' = 'DRAFT' AND (r->>'ready_to_activate')::boolean = false AND (r->'blockers')::text ILIKE '%pricing%', coalesce(r::text, 'none'));
  r := trustride.fn_present_proj_office_catalogue(NULL, '{}');
  SELECT x INTO r FROM jsonb_array_elements(r->'services') x WHERE x->>'service_id' = boda::text;
  PERFORM pg_temp.t_check('catalogue: a live service shows its Engine 5 pricing linkage per jurisdiction',
    jsonb_array_length(r->'pricing') >= 1 AND r->'pricing'->0->>'jurisdiction' = 'KISUMU_COUNTY' AND (r->'pricing'->0->>'current_rate_kes') IS NOT NULL, coalesce(r::text, 'none'));

  -- ============ suspension: new orders stop, orders in flight continue
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02"}}]'::jsonb));
  o := pg_temp.t_order(r);
  PERFORM pg_temp.t_cycle(12);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = o.order_id;
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'SUSPEND_SERVICE', jsonb_build_object('service_id', boda));
  PERFORM pg_temp.t_check('catalogue: suspension needs a reason', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'SUSPEND_SERVICE', jsonb_build_object('service_id', boda, 'reason', 'Suite 38 suspension'));
  PERFORM pg_temp.t_check('catalogue: the Office suspends a live service; audited and broadcast',
    r->>'status' = 'TRANSLATED' AND (SELECT status::text FROM trustride.service_catalogue WHERE service_id = boda) = 'SUSPENDED'
    AND EXISTS (SELECT 1 FROM trustride.audit_log WHERE entity_id = boda AND action = 'SERVICE_SUSPENDED' AND actor_id = admin)
    AND EXISTS (SELECT 1 FROM trustride.service_event_outbox WHERE signal_type = 'SERVICE_CATALOGUE_UPDATED' AND payload_in->>'service_id' = boda::text AND payload_in->>'status' = 'SUSPENDED'), r::text);
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'SUSPEND_SERVICE', jsonb_build_object('service_id', boda, 'reason', 'again'));
  SELECT count(*) INTO n FROM trustride.audit_log WHERE entity_id = boda AND action = 'SERVICE_SUSPENDED';
  PERFORM pg_temp.t_check('catalogue: suspending again changes nothing (no second audit entry)', r->>'status' = 'TRANSLATED' AND n = 1, n::text);
  PERFORM pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'ACCEPT_QUOTATION', jsonb_build_object('quote_id', o.quote_id));
  PERFORM pg_temp.t_cycle(4);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = o.order_id;
  SELECT operator_user_id INTO op FROM trustride.resource_workforce_unit WHERE workforce_unit_id = o.reserved_workforce_unit_id;
  SELECT job_id INTO j FROM trustride.business_job WHERE order_id = o.order_id;
  FOR i IN 1..6 LOOP PERFORM pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', jsonb_build_object('job_id', j)); END LOOP;
  PERFORM pg_temp.t_cycle(6);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = o.order_id;
  PERFORM pg_temp.t_check('catalogue: an order quoted before suspension is still accepted, dispatched and completed',
    o.status::text IN ('COMPLETED', 'AWAITING_PAYMENT', 'SETTLED'), o.status::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02"}}]'::jsonb));
  ord := (pg_temp.t_order(r)).order_id;
  PERFORM pg_temp.t_cycle(12);
  PERFORM pg_temp.t_check('catalogue: a new order for a suspended service is refused (service not available) and nothing is created',
    r->>'status' = 'REJECTED' AND r->>'reason' ILIKE '%not available%' AND ord IS NULL,
    r::text || ' ' || coalesce((SELECT status::text FROM trustride.business_order WHERE order_id = ord), 'no order'));
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RETIRE_SERVICE', jsonb_build_object('service_id', boda, 'reason', 'try'));
  PERFORM pg_temp.t_check('catalogue: a service with open orders cannot be retired', r->>'status' = 'REJECTED' AND r->>'reason' ILIKE '%open order%', r::text);

  -- ============ reinstatement passes the same checks
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ACTIVATE_SERVICE', jsonb_build_object('service_id', boda));
  PERFORM pg_temp.t_check('catalogue: a suspended service with its pricing in place is reinstated',
    r->>'status' = 'TRANSLATED' AND (SELECT status::text FROM trustride.service_catalogue WHERE service_id = boda) = 'ACTIVE'
    AND EXISTS (SELECT 1 FROM trustride.audit_log WHERE entity_id = boda AND action = 'SERVICE_ACTIVATED' AND actor_id = admin), r::text);
  PERFORM pg_temp.t_release_completed();
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02"}}]'::jsonb));
  o := pg_temp.t_order(r);
  PERFORM pg_temp.t_cycle(12);
  PERFORM pg_temp.t_check('catalogue: after reinstatement new orders are priced again',
    (SELECT quote_id IS NOT NULL FROM trustride.business_order WHERE order_id = o.order_id),
    r::text || ' ' || coalesce((SELECT status::text || ' ' || coalesce(status_reason, '') FROM trustride.business_order WHERE order_id = o.order_id), 'no order'));

  -- ============ retirement of an unused service
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RETIRE_SERVICE', jsonb_build_object('service_id', sid, 'reason', 'Never launched'));
  PERFORM pg_temp.t_check('catalogue: an unused draft is retired (terminal)', r->>'status' = 'TRANSLATED'
    AND (SELECT status::text FROM trustride.service_catalogue WHERE service_id = sid) = 'RETIRED', r::text);
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ACTIVATE_SERVICE', jsonb_build_object('service_id', sid));
  PERFORM pg_temp.t_check('catalogue: a retired service cannot come back', r->>'status' = 'REJECTED', r::text);
  END IF;
END
$$;
