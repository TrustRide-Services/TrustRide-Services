-- Suite 01 -- G1 signed-in permissions, RLS isolation, negative paths.
DO $$
DECLARE
  cust UUID; other UUID; op UUID; op2 UUID; founder UUID; partner UUID; est UUID; wu UUID; wu2 UUID;
  o1 UUID; o2 UUID; n BIGINT;
BEGIN
  cust := pg_temp.t_person('Customer A', 'CUSTOMER');
  other := pg_temp.t_person('Customer B', 'CUSTOMER');
  op := pg_temp.t_person('Operator A', 'OPERATOR');
  op2 := pg_temp.t_person('Operator B', 'OPERATOR');
  partner := pg_temp.t_person('Partner A', 'PARTNER');
  founder := pg_temp.t_person('Founder', NULL);
  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  est := trustride.fn_resource_estate_register('T-HUB-01', 'OPERATING_HUB', 'Test Hub', -0.091, 34.767, 'KISUMU_COUNTY', founder);
  wu := trustride.fn_resource_workforce_unit_form(op, 'BODA_BODA', est);
  wu2 := trustride.fn_resource_workforce_unit_form(op2, 'SEDAN', est);
  o1 := trustride.fn_business_order_place(cust, 'CUSTOMER', 'TRANSPORT-BODA-STANDARD', 'TRANSPORT',
    '[{"line_description":"t","scope_detail":{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02"}}]', 'SERVICE_ORDER', 'KISUMU_COUNTY', gen_random_uuid());
  o2 := trustride.fn_business_order_place(other, 'CUSTOMER', 'TRANSPORT-BODA-STANDARD', 'TRANSPORT',
    '[{"line_description":"t","scope_detail":{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02"}}]', 'SERVICE_ORDER', 'KISUMU_COUNTY', gen_random_uuid());

  -- Structural: the standing conformance check is clean.
  SELECT count(*) INTO n FROM trustride.fn_platform_conformance_violations();
  PERFORM pg_temp.t_check('conformance: zero violations', n = 0, n || ' violations');

  -- Customer: the screens that used to fail with "permission denied".
  PERFORM pg_temp.t_as(cust);
  PERFORM pg_temp.t_check('customer reads the service catalogue', pg_temp.t_visible('service_catalogue') >= 24);
  PERFORM pg_temp.t_check('customer reads the macro domains', pg_temp.t_visible('service_macro_domain') = 5);
  PERFORM pg_temp.t_check('customer reads own actor registration', pg_temp.t_visible('business_actor_registration') = 1);
  PERFORM pg_temp.t_check('customer reads own order', pg_temp.t_visible('business_order', format('order_id = %L', o1)) = 1);
  PERFORM pg_temp.t_check('customer reads own order lines', pg_temp.t_visible('business_order_line', format('order_id = %L', o1)) = 1);
  -- Negative paths: isolation.
  PERFORM pg_temp.t_check('customer cannot see another customer''s order', pg_temp.t_visible('business_order', format('order_id = %L', o2)) = 0);
  PERFORM pg_temp.t_check('customer sees only own orders', pg_temp.t_visible('business_order') = 1);
  PERFORM pg_temp.t_check('customer cannot see workforce units', pg_temp.t_visible('resource_workforce_unit') = 0);
  PERFORM pg_temp.t_check('customer cannot see the availability ledger', pg_temp.t_visible('resource_availability_ledger') = 0);
  PERFORM pg_temp.t_check('customer cannot see custody logs', pg_temp.t_visible('resource_custody_log') = 0);
  PERFORM pg_temp.t_check('customer cannot see advisory output', pg_temp.t_visible('advisory_recommendation') = 0);
  PERFORM pg_temp.t_check('customer cannot see orchestration internals', pg_temp.t_visible('orch_signal_queue') <= 0);
  PERFORM pg_temp.t_check('customer cannot see other users', pg_temp.t_visible('platform_users', format('user_id <> %L', cust)) = 0);
  PERFORM pg_temp.t_check('customer cannot write orders directly',
    pg_temp.t_fails(format('UPDATE trustride.business_order SET status = ''SETTLED'' WHERE order_id = %L', o1)));
  PERFORM pg_temp.t_check('customer cannot call an internal accept handler',
    pg_temp.t_fails('SELECT trustride.fn_business_payment_settled_accept(gen_random_uuid())'));
  PERFORM pg_temp.t_check('customer cannot decide actor requests',
    pg_temp.t_fails(format('SELECT trustride.fn_business_actor_request_decide(%L, ''ACCEPTED'', NULL)', o1)));
  PERFORM pg_temp.t_check('customer cannot open TrustRide Office',
    pg_temp.t_fails(format('SELECT trustride.fn_present_shell_session_open(''TRUSTRIDE_OFFICE'', ''ADMIN_CONSOLE'', %L, ''WEB'', NULL, NULL, NULL)', cust)));
  PERFORM pg_temp.t_check('customer cannot open a session as someone else',
    pg_temp.t_fails(format('SELECT trustride.fn_present_shell_session_open(''TRUSTRIDE_BUSINESS'', ''CUSTOMER_APP'', %L, ''WEB'', NULL, NULL, NULL)', other)));
  PERFORM pg_temp.t_check('customer can open own Customer App',
    NOT pg_temp.t_fails(format('SELECT trustride.fn_present_shell_session_open(''TRUSTRIDE_BUSINESS'', ''CUSTOMER_APP'', %L, ''WEB'', NULL, NULL, NULL)', cust)));

  -- Operator: own working unit only.
  PERFORM pg_temp.t_as(op);
  PERFORM pg_temp.t_check('operator reads own working unit', pg_temp.t_visible('resource_workforce_unit') = 1);
  PERFORM pg_temp.t_check('operator cannot read another operator''s unit', pg_temp.t_visible('resource_workforce_unit', format('workforce_unit_id = %L', wu2)) = 0);
  PERFORM pg_temp.t_check('operator reads own availability', pg_temp.t_visible('resource_availability_ledger') = 1);
  PERFORM pg_temp.t_check('operator cannot read customer orders', pg_temp.t_visible('business_order') = 0);

  -- Partner: no resource visibility until something is in their custody.
  PERFORM pg_temp.t_as(partner);
  PERFORM pg_temp.t_check('partner cannot read fleet not in their custody', pg_temp.t_visible('resource_fleet_register') = 0);

  -- Founder / Office: full lawful visibility.
  PERFORM pg_temp.t_as(founder);
  PERFORM pg_temp.t_check('Office reads all orders', pg_temp.t_visible('business_order') >= 2);
  PERFORM pg_temp.t_check('Office reads all working units', pg_temp.t_visible('resource_workforce_unit') >= 2);
  PERFORM pg_temp.t_check('Office reads the actor-request queue', pg_temp.t_visible('business_partnership_response') >= 0);
  PERFORM pg_temp.t_check('Office reads advisory output', pg_temp.t_visible('advisory_recommendation') >= 0);
  PERFORM pg_temp.t_check('Office still cannot write tables directly',
    pg_temp.t_fails(format('DELETE FROM trustride.business_order WHERE order_id = %L', o2)));

  -- Anonymous: nothing but the System Access record.
  PERFORM pg_temp.t_as(NULL);
  PERFORM pg_temp.t_check('anon cannot read the catalogue table', pg_temp.t_visible('service_catalogue') = -1);
  PERFORM pg_temp.t_check('anon cannot read orders', pg_temp.t_visible('business_order') = -1);
  PERFORM pg_temp.t_check('anon may record System Access',
    NOT pg_temp.t_fails('SELECT trustride.fn_present_system_access_record(''WEB'', ''REGISTER'', ''NATURAL_PERSON'', ''INTERACTIVE'', NULL)'));
  PERFORM pg_temp.t_check('anon cannot place orders',
    pg_temp.t_fails(format('SELECT trustride.fn_business_order_place(%L, ''CUSTOMER'', ''X'', ''X'', ''[{}]'', ''SERVICE_ORDER'', ''X'', gen_random_uuid())', cust)));
  PERFORM pg_temp.t_admin();
END;
$$;
