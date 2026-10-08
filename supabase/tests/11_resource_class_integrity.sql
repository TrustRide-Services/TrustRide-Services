-- Suite 11 -- resource-class integrity (found by the integrated Company ->
-- Boda proof): a Boda order is never matched to, and never accepts, a unit
-- of another class, even when Engine 2 is made to reserve one.
DO $$
DECLARE
  founder UUID; cust UUID; est UUID; sedan UUID; r JSONB; o RECORD; n INT; v TEXT; line UUID;
BEGIN
  PERFORM pg_temp.t_open_all_hours();
  -- Only the Sedan exists for this test: every other active Boda unit is set aside (rolled back).
  UPDATE trustride.resource_workforce_unit wu SET unit_status = 'INACTIVE'
  FROM trustride.resource_capacity_class cc WHERE cc.capacity_class_id = wu.capacity_class_id AND cc.class_code = 'BODA_BODA' AND wu.unit_status = 'ACTIVE';
  founder := pg_temp.t_person('Class Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  cust := pg_temp.t_customer('Class Customer');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"CLS-01","estate_name":"Class Hub","estate_type":"OPERATING_HUB","lat":-0.09,"lon":34.76}');
  est := (r->>'signal')::uuid;
  sedan := pg_temp.t_ready_unit(founder, 'SEDAN', est, 'Class Sedan Driver');

  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02"}}]'::jsonb));
  o := pg_temp.t_order(r);
  PERFORM pg_temp.t_cycle(8);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = o.order_id;
  PERFORM pg_temp.t_check('Boda order waits while only a Sedan is free', o.status = 'WAITING', o.status::text);
  SELECT count(*) INTO n FROM trustride.resource_availability_ledger WHERE job_ref_id = o.order_id AND resource_ref_id = sedan;
  PERFORM pg_temp.t_check('matching never reserves the Sedan for a Boda order', n = 0, n::text);

  -- Fault injection: Engine 2 is made to reserve the Sedan for the Boda order.
  SELECT order_line_id INTO line FROM trustride.business_order_line WHERE order_id = o.order_id LIMIT 1;
  PERFORM trustride.fn_resource_reserve(sedan, o.order_id, o.correlation_id, '00000000-0000-0000-0000-000000000000', line);
  PERFORM pg_temp.t_cycle(8);
  SELECT payload_out->>'rejected' INTO v FROM trustride.business_event_inbox WHERE correlation_id = o.correlation_id AND signal_type = 'RESOURCE_RESERVED' ORDER BY received_at DESC LIMIT 1;
  PERFORM pg_temp.t_check('Business refuses the wrong-class reservation', v = 'CAPACITY_CLASS_MISMATCH', coalesce(v, 'accepted'));
  SELECT count(*) INTO n FROM trustride.business_job WHERE order_id = o.order_id;
  PERFORM pg_temp.t_check('no job is created on the Sedan', n = 0, n::text);
  PERFORM pg_temp.t_check('the Sedan is released back to AVAILABLE', trustride.fn_resource_unit_availability(sedan) = 'AVAILABLE', trustride.fn_resource_unit_availability(sedan)::text);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = o.order_id;
  PERFORM pg_temp.t_check('the order keeps waiting for an eligible Boda, with no quote', o.status = 'WAITING' AND o.quote_id IS NULL AND o.reserved_workforce_unit_id IS NULL, o.status::text);
  PERFORM pg_temp.t_check('TrustRide Office is alerted', EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = founder AND title LIKE 'Wrong resource class refused on%'));
  SELECT count(*) INTO n FROM trustride.fn_platform_conformance_violations();
  PERFORM pg_temp.t_check('conformance: zero violations', n = 0, n || ' violations');
END;
$$;
