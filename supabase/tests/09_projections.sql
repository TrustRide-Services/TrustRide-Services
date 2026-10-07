-- Suite 09 -- G20 lawful projections: every screen's read model renders for
-- the identity it serves, and nothing renders outside its boundary.
DO $$
DECLARE
  founder UUID; exec UUID; cust UUID; other UUID; op UUID; partner UUID; gov UUID; inter UUID; vendor UUID; est UUID; unit UUID;
  r JSONB; p JSONB; ord UUID; s UUID; n INT; code TEXT;
BEGIN
  PERFORM pg_temp.t_open_all_hours();
  founder := pg_temp.t_person('Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  exec := pg_temp.t_person('Exec', NULL);  PERFORM pg_temp.t_role(exec, 'EXECUTIVE');
  cust := pg_temp.t_customer('Projection Customer');
  other := pg_temp.t_customer('Other Customer');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"PR-HUB","estate_type":"OPERATING_HUB","estate_name":"Projection Hub","lat":-0.0917,"lon":34.7680}');
  est := (r->>'signal')::uuid;
  unit := pg_temp.t_ready_unit(founder, 'BODA_BODA', est, 'Projection Rider');
  SELECT operator_user_id INTO op FROM trustride.resource_workforce_unit WHERE workforce_unit_id = unit;

  -- A live order to look at.
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02"}}]'::jsonb));
  ord := (pg_temp.t_order(r)).order_id;
  PERFORM pg_temp.t_cycle(12);

  -- Gate context (pre-shell)
  PERFORM pg_temp.t_as(cust);
  p := trustride.fn_present_gate_context();
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('Gate context: identity, environments, phone', (p->>'registered')::boolean AND (p->>'phone_verified')::boolean
    AND p->'environments' @> '[{"domain":"CUSTOMER","status":"ACTIVE"}]', p::text);

  -- Customer
  p := pg_temp.t_proj(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'SERVICE_CATALOGUE');
  PERFORM pg_temp.t_check('SERVICE_CATALOGUE: families, zones, hours', jsonb_array_length(p->'families') = 5 AND jsonb_array_length(p->'zones') >= 3 AND p ? 'working_hours', left(p::text, 300));
  p := pg_temp.t_proj(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'CUSTOMER_HOME');
  PERFORM pg_temp.t_check('CUSTOMER_HOME: the active order is there', jsonb_array_length(p->'active_orders') = 1, left(p::text, 300));
  p := pg_temp.t_proj(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'MY_ORDERS');
  PERFORM pg_temp.t_check('MY_ORDERS lists the order with its allowed actions', p->'orders'->0->>'order_id' = ord::text
    AND (p->'orders'->0->'actions'->>'accept_quote')::boolean, left(p::text, 400));
  p := pg_temp.t_proj(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'ORDER_DETAIL', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_check('ORDER_DETAIL: lines, quote, no operator identity before the fare is accepted', jsonb_array_length(p->'lines') = 1
    AND p->'quote'->>'total_kes' IS NOT NULL AND p->'operator' = 'null'::jsonb, left(p::text, 500));
  p := pg_temp.t_proj(other, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'ORDER_DETAIL', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_check('another customer cannot render my order', p ? 'error', p::text);
  PERFORM pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'ACCEPT_QUOTATION', jsonb_build_object('quote_id', (SELECT quote_id FROM trustride.business_order WHERE order_id = ord)));
  PERFORM pg_temp.t_cycle(4);
  FOR n IN 1..3 LOOP PERFORM pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL',
    jsonb_build_object('job_id', (SELECT job_id FROM trustride.business_job WHERE order_id = ord))); END LOOP;
  PERFORM pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'TRACK_ELEMENT', jsonb_build_object('job_id', (SELECT job_id FROM trustride.business_job WHERE order_id = ord),
    'lat', -0.093, 'lon', 34.765, 'eta', now() + interval '6 minutes'));
  p := pg_temp.t_proj(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'ORDER_DETAIL', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_check('after acceptance: operator first name + vehicle; live tracking with the 5 Article 21 elements',
    p->'operator'->>'first_name' = 'Projection' AND p->'tracking'->>'status' IS NOT NULL AND p->'tracking'->>'lat' IS NOT NULL
    AND p->'tracking'->>'eta' IS NOT NULL AND p->'tracking' ? 'resource_type' AND p->'tracking' ? 'resource_id', left(p::text, 700));
  PERFORM pg_temp.t_check('the customer never sees the operator''s full name or phone', p::text NOT LIKE '%Rider%' AND p::text NOT LIKE '%+2547%');
  p := pg_temp.t_proj(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'MY_PROFILE');
  PERFORM pg_temp.t_check('MY_PROFILE: contacts and staging messages', jsonb_array_length(p->'contacts') = 1, left(p::text, 300));
  p := pg_temp.t_proj(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'NOTIFICATIONS');
  PERFORM pg_temp.t_check('NOTIFICATIONS: the customer''s inbox', jsonb_array_length(p->'items') >= 3, left(p::text, 200));
  p := pg_temp.t_proj(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'MY_SUPPORT');
  PERFORM pg_temp.t_check('MY_SUPPORT renders', p ? 'cases', p::text);
  p := pg_temp.t_proj(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'OFFICE_ORDERS');
  PERFORM pg_temp.t_check('a customer cannot render an Office projection', p ? 'error', p::text);
  p := pg_temp.t_proj(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'NOT_A_SCREEN');
  PERFORM pg_temp.t_check('an unregistered screen is refused (C-III-3)', p->>'error' LIKE '%not a registered projection%', p::text);
  PERFORM pg_temp.t_check('every render is recorded', EXISTS (SELECT 1 FROM trustride.present_projection_render WHERE projection_code = 'ORDER_DETAIL'));
  PERFORM pg_temp.t_as(other);
  s := (SELECT session_id FROM trustride.present_shell_session WHERE user_id = cust ORDER BY started_at DESC LIMIT 1);
  PERFORM pg_temp.t_check('nobody can read through someone else''s session', pg_temp.t_fails(format('SELECT trustride.fn_present_projection(%L, ''MY_ORDERS'', ''{}'')', s)));
  PERFORM pg_temp.t_admin();

  -- Operator
  p := pg_temp.t_proj(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'OPERATOR_HOME');
  PERFORM pg_temp.t_check('OPERATOR_HOME: unit, vehicle, duty state, active job', p->'unit'->>'class_code' = 'BODA_BODA'
    AND jsonb_array_length(p->'active_jobs') = 1, left(p::text, 600));
  p := pg_temp.t_proj(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'OPERATOR_JOB', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_check('OPERATOR_JOB: stops, customer first name only, fare', jsonb_array_length(p->'stops') = 1 AND p->>'customer_first_name' = 'Projection'
    AND p::text NOT LIKE '%+2547%', left(p::text, 500));
  p := pg_temp.t_proj(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'OFFICE_USERS');
  PERFORM pg_temp.t_check('an operator cannot render Office user management', p ? 'error', p::text);

  -- Office
  FOREACH code IN ARRAY ARRAY['OFFICE_OVERVIEW', 'OFFICE_REQUESTS', 'OFFICE_ORDERS', 'OFFICE_RESOURCES', 'OFFICE_TRACKING', 'OFFICE_MARKETPLACE',
                              'OFFICE_SUPPORT', 'OFFICE_USERS', 'OFFICE_INTEGRATIONS', 'OFFICE_HEALTH', 'EXEC_KPIS', 'EXEC_ADVISORY'] LOOP
    p := pg_temp.t_proj(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', code);
    PERFORM pg_temp.t_check('Admin Console renders ' || code, NOT (p ? 'error'), left(p::text, 300));
  END LOOP;
  p := pg_temp.t_proj(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'OFFICE_RESOURCES');
  PERFORM pg_temp.t_check('OFFICE_RESOURCES shows the unit and its vehicle', jsonb_array_length(p->'units') = 1 AND jsonb_array_length(p->'vehicles') = 1, left(p::text, 300));
  FOREACH code IN ARRAY ARRAY['OFFICE_OVERVIEW', 'EXEC_KPIS', 'EXEC_ADVISORY', 'EXEC_SCENARIOS', 'OFFICE_HEALTH'] LOOP
    p := pg_temp.t_proj(exec, 'TRUSTRIDE_OFFICE', 'EXECUTIVE_DASHBOARD', code);
    PERFORM pg_temp.t_check('Executive Dashboard renders ' || code, NOT (p ? 'error'), left(p::text, 300));
  END LOOP;
  p := pg_temp.t_proj(exec, 'TRUSTRIDE_OFFICE', 'EXECUTIVE_DASHBOARD', 'OFFICE_USERS');
  PERFORM pg_temp.t_check('Executives do not manage users (Admin projection)', p ? 'error', p::text);
  p := pg_temp.t_proj(exec, 'TRUSTRIDE_OFFICE', 'EXECUTIVE_DASHBOARD', 'EXEC_SCENARIOS');
  PERFORM pg_temp.t_check('EXEC_SCENARIOS lists the scenario templates', jsonb_array_length(p->'scenarios') >= 1, left(p::text, 300));

  -- Partner / Governor / Intermediary / Marketplace / Vendor
  partner := pg_temp.t_customer('P Partner');  PERFORM pg_temp.t_as(partner);  PERFORM trustride.fn_business_actor_register(partner, 'PARTNER');  PERFORM pg_temp.t_admin();
  p := pg_temp.t_proj(partner, 'TRUSTRIDE_BUSINESS', 'PARTNER_APP', 'PARTNER_HOME');
  PERFORM pg_temp.t_check('PARTNER_HOME renders (pending partner)', p->>'registration' = 'PENDING', left(p::text, 300));
  p := pg_temp.t_proj(partner, 'TRUSTRIDE_BUSINESS', 'PARTNER_APP', 'REQUEST_HISTORY');
  PERFORM pg_temp.t_check('REQUEST_HISTORY renders', p ? 'requests', p::text);
  gov := pg_temp.t_customer('G Governor');  PERFORM pg_temp.t_as(gov);  PERFORM trustride.fn_business_actor_register(gov, 'GOVERNOR');  PERFORM pg_temp.t_admin();
  p := pg_temp.t_proj(gov, 'TRUSTRIDE_BUSINESS', 'GOVERNOR_APP', 'GOVERNOR_OVERSIGHT');
  PERFORM pg_temp.t_check('GOVERNOR_OVERSIGHT before approval: nothing, with an explanation', p->'engagement' = 'null'::jsonb AND p->>'message' IS NOT NULL, p::text);
  r := pg_temp.t_cmd(gov, 'TRUSTRIDE_BUSINESS', 'GOVERNOR_APP', 'SUBMIT_REGULATORY_REQUEST', '{"scope_lines":[{"line_description":"County oversight","scope_detail":{}}]}');
  PERFORM pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REVIEW_ACTOR_REQUEST', jsonb_build_object('order_id', (r->>'signal')::uuid, 'decision', 'ACCEPTED'));
  p := pg_temp.t_proj(gov, 'TRUSTRIDE_BUSINESS', 'GOVERNOR_APP', 'GOVERNOR_OVERSIGHT');
  PERFORM pg_temp.t_check('approved governor with no grant still sees no data', p->'scopes' = '{}'::jsonb, p::text);
  PERFORM pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'SET_GOVERNOR_SCOPE', jsonb_build_object('governor_user_id', gov, 'data_scope', 'FLEET_COMPLIANCE_SUMMARY'));
  p := pg_temp.t_proj(gov, 'TRUSTRIDE_BUSINESS', 'GOVERNOR_APP', 'GOVERNOR_OVERSIGHT');
  PERFORM pg_temp.t_check('after a grant: exactly that aggregate scope, no personal data', p->'scopes' ? 'FLEET_COMPLIANCE_SUMMARY'
    AND NOT (p->'scopes' ? 'AGGREGATE_REVENUE_AND_TAX') AND p::text NOT LIKE '%Rider%', left(p::text, 400));
  inter := pg_temp.t_customer('I Intermediary');  PERFORM pg_temp.t_as(inter);  PERFORM trustride.fn_business_actor_register(inter, 'INTERMEDIARY');  PERFORM pg_temp.t_admin();
  p := pg_temp.t_proj(inter, 'TRUSTRIDE_BUSINESS', 'INTERMEDIARY_APP', 'INTERMEDIARY_HOME');
  PERFORM pg_temp.t_check('INTERMEDIARY_HOME renders', p ? 'referrals', p::text);
  p := pg_temp.t_proj(cust, 'TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'MARKETPLACE_LISTINGS');
  PERFORM pg_temp.t_check('MARKETPLACE_LISTINGS renders', p ? 'listings', p::text);
  p := pg_temp.t_proj(cust, 'TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'MY_ORDERS', '{"scope":"PURCHASE"}');
  PERFORM pg_temp.t_check('MY_ORDERS (purchases) renders on the Marketplace', p ? 'orders', p::text);
  vendor := pg_temp.t_customer('V Vendor');
  p := pg_temp.t_proj(vendor, 'TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'VENDOR_HOME');
  PERFORM pg_temp.t_check('VENDOR_HOME renders (no agreement yet)', p->'agreement' = 'null'::jsonb, p::text);
  p := pg_temp.t_proj(vendor, 'TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'SERVICE_CATALOGUE');
  PERFORM pg_temp.t_check('a projection is only served on its registered sub-shells', p ? 'error', p::text);

  -- every registered projection has a function, and vice versa
  SELECT count(*) INTO n FROM trustride.projection_registry r
  WHERE to_regprocedure('trustride.fn_present_proj_' || lower(r.projection_code) || '(uuid,jsonb)') IS NULL AND r.projection_code <> 'USER_ORDER_STATUS_CARD';
  PERFORM pg_temp.t_check('every registered projection has a renderer', n = 0, n::text);
  SELECT count(*) INTO n FROM pg_proc p2 WHERE p2.pronamespace = 'trustride'::regnamespace AND p2.proname LIKE 'fn\_present\_proj\_%'
    AND NOT EXISTS (SELECT 1 FROM trustride.projection_registry r WHERE 'fn_present_proj_' || lower(r.projection_code) = p2.proname);
  PERFORM pg_temp.t_check('no renderer exists without registration', n = 0, n::text);
  SELECT count(*) INTO n FROM trustride.fn_platform_conformance_violations();
  PERFORM pg_temp.t_check('conformance: zero violations', n = 0, n || ' violations');
END;
$$;
