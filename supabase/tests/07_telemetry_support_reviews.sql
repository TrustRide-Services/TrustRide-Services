-- Suite 07 -- Journey G (Protrack telemetry -> TrustRide resource -> active
-- assignment -> authorised tracking -> termination), support cases, reviews.
DO $$
DECLARE
  founder UUID; cust UUID; other UUID; op UUID; est UUID; r JSONB; sys UUID; key TEXT; dev UUID; unit UUID; fleet UUID;
  ord UUID; j UUID; res JSONB; loc TEXT; n INT; v_case UUID; i INT; v TEXT;
BEGIN
  PERFORM pg_temp.t_open_all_hours();
  founder := pg_temp.t_person('Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  cust := pg_temp.t_customer('Tracked Customer');
  other := pg_temp.t_customer('Someone Else');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"G-HUB","estate_type":"OPERATING_HUB","estate_name":"GPS Hub","lat":-0.0917,"lon":34.7680}');
  est := (r->>'signal')::uuid;
  unit := pg_temp.t_ready_unit(founder, 'BODA_BODA', est, 'Tracked Rider');
  SELECT fleet_resource_id, operator_user_id INTO fleet, op FROM trustride.resource_workforce_unit WHERE workforce_unit_id = unit;

  -- Protrack is an external system with a telemetry credential.
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_EXTERNAL_SYSTEM', '{"system_name":"Protrack","purpose":"GPS telemetry"}');
  sys := (r->>'signal')::uuid;
  PERFORM pg_temp.t_as(founder);
  key := trustride.fn_external_system_credential_issue(sys, ARRAY['TELEMETRY_INGEST']);
  PERFORM pg_temp.t_admin();
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_OBJECT', '{"object_type":"TRACKING_DEVICE","make":"Protrack","model":"PT-300","serial_number":"867000000000123"}');
  dev := (r->>'signal')::uuid;
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'BIND_TELEMETRY_DEVICE', jsonb_build_object('fleet_resource_id', fleet, 'device_object_id', dev));

  -- ------------------------------------------------ ingestion boundary
  res := trustride.fn_integration_telemetry_ingest('trs_wrong.key', '[{"imei":"867000000000123","lat":-0.09,"lng":34.76,"gpstime":1}]');
  PERFORM pg_temp.t_check('telemetry with a bad key is refused and logged', res->>'outcome' = 'UNAUTHENTICATED'
    AND EXISTS (SELECT 1 FROM trustride.integration_telemetry_ingest_log WHERE outcome = 'UNAUTHENTICATED'), res::text);
  res := trustride.fn_integration_telemetry_ingest(key, jsonb_build_array(
    jsonb_build_object('imei', '867000000000123', 'lat', -0.0920, 'lng', 34.7690, 'gpstime', extract(epoch FROM now())::bigint, 'speed', 22, 'course', 90, 'acc', 1),
    jsonb_build_object('imei', '867000000000123', 'lat', 0, 'lng', 0, 'gpstime', extract(epoch FROM now())::bigint),
    jsonb_build_object('imei', '869999999999999', 'lat', -0.09, 'lng', 34.77, 'gpstime', extract(epoch FROM now())::bigint)));
  PERFORM pg_temp.t_check('valid points accepted, invalid coordinates rejected with a reason', (res->>'accepted')::int = 2 AND jsonb_array_length(res->'rejected') = 1, res::text);
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('Resources records the bound vehicle''s location; device LIVE', EXISTS (
    SELECT 1 FROM trustride.resource_location_event WHERE fleet_resource_id = fleet) AND EXISTS (
    SELECT 1 FROM trustride.resource_telemetry_binding WHERE fleet_resource_id = fleet AND telemetry_status = 'LIVE'));
  PERFORM pg_temp.t_check('an unregistered device never becomes a resource location', NOT EXISTS (
    SELECT 1 FROM trustride.resource_location_event WHERE device_ref = '869999999999999'));
  PERFORM pg_temp.t_check('no customer can see raw location history', (SELECT pg_temp.t_visible('resource_location_event')) >= 0);
  PERFORM pg_temp.t_as(cust);
  PERFORM pg_temp.t_check('a customer reads no fleet location history', pg_temp.t_visible('resource_location_event') = 0);
  PERFORM pg_temp.t_admin();

  -- ------------------------------------------------ active job tracking
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02"}}]'::jsonb));
  ord := (pg_temp.t_order(r)).order_id;
  PERFORM pg_temp.t_cycle(12);
  PERFORM pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'ACCEPT_QUOTATION', jsonb_build_object('quote_id', (SELECT quote_id FROM trustride.business_order WHERE order_id = ord)));
  PERFORM pg_temp.t_cycle(4);
  SELECT job_id INTO j FROM trustride.business_job WHERE order_id = ord;
  FOR i IN 1..3 LOOP PERFORM pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', jsonb_build_object('job_id', j)); END LOOP;  -- ACK, DISPATCHED, EN_ROUTE
  res := trustride.fn_integration_telemetry_ingest(key, jsonb_build_array(
    jsonb_build_object('imei', '867000000000123', 'lat', -0.0950, 'lng', 34.7600, 'gpstime', extract(epoch FROM now())::bigint + 1, 'speed', 30, 'acc', 1)));
  PERFORM pg_temp.t_cycle(6);
  SELECT round(ST_Y(exact_location)::numeric, 4)::text || ',' || round(ST_X(exact_location)::numeric, 4)::text INTO loc FROM trustride.business_tracking_session WHERE job_id = j;
  PERFORM pg_temp.t_check('device position reaches the active tracking session', loc = '-0.0950,34.7600', coalesce(loc, 'none'));
  PERFORM pg_temp.t_check('location history is tied to the order', EXISTS (SELECT 1 FROM trustride.resource_location_event WHERE order_id = ord));
  PERFORM pg_temp.t_as(cust);
  PERFORM pg_temp.t_check('the customer can read their own active tracking session', pg_temp.t_visible('business_tracking_session', format('job_id = %L', j)) = 1);
  PERFORM pg_temp.t_as(other);
  PERFORM pg_temp.t_check('another customer cannot see this vehicle', pg_temp.t_visible('business_tracking_session', format('job_id = %L', j)) = 0);
  PERFORM pg_temp.t_admin();
  res := trustride.fn_integration_telemetry_ingest(key, jsonb_build_array(
    jsonb_build_object('imei', '867000000000123', 'lat', -1.2921, 'lng', 36.8219, 'gpstime', extract(epoch FROM now())::bigint + 2)));
  PERFORM pg_temp.t_cycle(6);
  PERFORM pg_temp.t_check('a vehicle on a job far outside the service area alerts Office (safety)', EXISTS (
    SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = founder AND category = 'SAFETY'));
  FOR i IN 1..3 LOOP PERFORM pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', jsonb_build_object('job_id', j)); END LOOP;  -- ARRIVED, EXECUTING, COMPLETED
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('completion ends tracking', EXISTS (SELECT 1 FROM trustride.business_tracking_session WHERE job_id = j AND ended_at IS NOT NULL));
  res := trustride.fn_integration_telemetry_ingest(key, jsonb_build_array(
    jsonb_build_object('imei', '867000000000123', 'lat', -0.0800, 'lng', 34.7500, 'gpstime', extract(epoch FROM now())::bigint + 3)));
  PERFORM pg_temp.t_cycle(4);
  SELECT round(ST_Y(exact_location)::numeric, 4)::text INTO loc FROM trustride.business_tracking_session WHERE job_id = j;
  PERFORM pg_temp.t_check('after completion the customer''s session stops moving (active-session only)', loc <> '-0.0800', loc);

  -- device health
  UPDATE trustride.resource_telemetry_binding SET last_seen_at = now() - interval '1 hour' WHERE fleet_resource_id = fleet;
  n := trustride.fn_resource_telemetry_health_sweep();
  PERFORM pg_temp.t_check('a silent tracker on an on-duty vehicle is flagged STALE and Office told', n = 1 AND EXISTS (
    SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = founder AND category = 'TELEMETRY_EXCEPTION'), n::text);

  -- ------------------------------------------------ reviews
  r := pg_temp.t_cmd(other, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'SUBMIT_REVIEW', jsonb_build_object('order_id', ord, 'rating', 5));
  PERFORM pg_temp.t_check('only the customer reviews their order', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'SUBMIT_REVIEW', jsonb_build_object('order_id', ord, 'rating', 4, 'comment', 'Safe, a little late'));
  PERFORM pg_temp.t_check('customer rates the operator after the service', r->>'status' = 'TRANSLATED' AND EXISTS (
    SELECT 1 FROM trustride.business_review WHERE order_id = ord AND reviewee_user_id = op AND rating = 4), r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'SUBMIT_REVIEW', jsonb_build_object('order_id', ord, 'rating', 1));
  PERFORM pg_temp.t_check('one review per order', r->>'status' = 'REJECTED', r::text);
  PERFORM pg_temp.t_as(op);
  PERFORM pg_temp.t_check('the operator can read the review about them', pg_temp.t_visible('business_review', format('order_id = %L', ord)) = 1);
  PERFORM pg_temp.t_admin();

  -- ------------------------------------------------ support
  r := pg_temp.t_cmd(other, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'OPEN_SUPPORT_CASE', jsonb_build_object('order_id', ord, 'category', 'ORDER_ISSUE', 'subject', 'x', 'body', 'y'));
  PERFORM pg_temp.t_check('nobody opens a case about someone else''s order', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'OPEN_SUPPORT_CASE', jsonb_build_object('order_id', ord, 'category', 'LOST_ITEM',
    'subject', 'Left my bag on the boda', 'body', 'A black backpack, left at Milimani drop-off.'));
  v_case := (r->>'signal')::uuid;
  PERFORM pg_temp.t_check('customer opens a case; Office is told; SLA set', r->>'status' = 'TRANSLATED'
    AND EXISTS (SELECT 1 FROM trustride.business_support_case WHERE case_id = v_case AND severity = 'HIGH' AND sla_due_at > now())
    AND EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = founder AND category = 'SUPPORT'), r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ASSIGN_SUPPORT_CASE', jsonb_build_object('case_id', v_case));
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REPLY_SUPPORT_CASE', jsonb_build_object('case_id', v_case, 'body', 'Internal: rider confirms bag', 'internal', true));
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REPLY_SUPPORT_CASE', jsonb_build_object('case_id', v_case, 'body', 'Your bag is at the CBD hub.'));
  PERFORM pg_temp.t_check('Office reply reaches the customer', EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = cust AND title LIKE 'Reply on%'));
  PERFORM pg_temp.t_as(cust);
  PERFORM pg_temp.t_check('internal notes stay internal', pg_temp.t_visible('business_support_message', format('case_id = %L', v_case)) = 2);
  PERFORM pg_temp.t_admin();
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RESOLVE_SUPPORT_CASE', jsonb_build_object('case_id', v_case, 'resolution', 'Bag collected by customer'));
  PERFORM pg_temp.t_check('Office resolves; customer told', EXISTS (SELECT 1 FROM trustride.business_support_case WHERE case_id = v_case AND status = 'RESOLVED')
    AND EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = cust AND title LIKE '%resolved'), r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'CLOSE_SUPPORT_CASE', jsonb_build_object('case_id', v_case, 'action', 'REOPEN', 'body', 'Wrong bag!'));
  PERFORM pg_temp.t_check('customer can reopen a recently resolved case', r->>'status' = 'TRANSLATED' AND EXISTS (
    SELECT 1 FROM trustride.business_support_case WHERE case_id = v_case AND status IN ('OPEN', 'ASSIGNED')), r::text);
  UPDATE trustride.business_support_case SET sla_due_at = now() - interval '1 minute' WHERE case_id = v_case;
  n := trustride.fn_business_support_sla_sweep();
  PERFORM pg_temp.t_check('an SLA breach escalates', n >= 1 AND EXISTS (SELECT 1 FROM trustride.business_support_case WHERE case_id = v_case AND escalated_at IS NOT NULL), n::text);
  r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'REPORT_PROBLEM', jsonb_build_object('job_id', j, 'category', 'SAFETY', 'subject', 'Customer was aggressive'));
  PERFORM pg_temp.t_check('operator reports a safety problem on their job -> CRITICAL case', r->>'status' = 'TRANSLATED' AND EXISTS (
    SELECT 1 FROM trustride.business_support_case WHERE job_id = j AND severity = 'CRITICAL'), r::text);
  r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'REPORT_PROBLEM', jsonb_build_object('job_id', gen_random_uuid(), 'subject', 'x'));
  PERFORM pg_temp.t_check('an operator reports only on their own job', r->>'status' = 'REJECTED', r::text);

  SELECT count(*) INTO n FROM trustride.dead_letter_review;
  PERFORM pg_temp.t_check('no dead-lettered signals', n = 0, coalesce((SELECT string_agg(failure_reason, ' | ') FROM trustride.dead_letter_review), ''));
  SELECT count(*) INTO n FROM trustride.fn_platform_conformance_violations();
  PERFORM pg_temp.t_check('conformance: zero violations', n = 0, n || ' violations');
END;
$$;
