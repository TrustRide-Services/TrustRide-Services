-- Suite 03 -- Resource management (G2), eligibility (G15), duty, telemetry
-- binding: the Office journey that turns real people and vehicles into a
-- dispatchable pool, without editing a table by hand.
DO $$
DECLARE
  founder UUID; op UUID; op2 UUID; ea UUID; cust UUID; notyet UUID;
  r JSONB; est UUID; moto UUID; moto_bad UUID; car UUID; dev UUID; fleet UUID; fleet_bad UUID; fleet_car UUID;
  unit UUID; ea_unit UUID; cap UUID; v TEXT; n INT;
BEGIN
  founder := pg_temp.t_person('Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  op := pg_temp.t_person('Rider Achieng', 'OPERATOR');
  op2 := pg_temp.t_person('Rider Two', 'OPERATOR');
  ea := pg_temp.t_person('EA Njeri', 'OPERATOR');
  notyet := pg_temp.t_person('Applicant', 'OPERATOR', 'PENDING');
  cust := pg_temp.t_person('Customer', 'CUSTOMER');

  -- Base
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"ksm-hub-01","estate_type":"OPERATING_HUB","estate_name":"Kisumu CBD Hub","lat":-0.0917,"lon":34.7680}');
  PERFORM pg_temp.t_check('Office registers a base', r->>'status' = 'TRANSLATED', r::text);
  est := (r->>'signal')::uuid;

  -- Vehicles: object -> fleet -> NTSA verification through Engine 6
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_OBJECT',
    '{"object_type":"MOTORCYCLE","make":"Honda","model":"Ace 125","year":2025,"plate_number":"KMGA 101A"}');
  moto := (r->>'signal')::uuid;
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_OBJECT',
    '{"object_type":"MOTORCYCLE","make":"Bajaj","model":"Boxer","year":2022,"plate_number":"KMGA 100Z"}');
  moto_bad := (r->>'signal')::uuid;
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_OBJECT',
    '{"object_type":"CAR","make":"Toyota","model":"Axio","year":2016,"plate_number":"KDC 222C"}');
  car := (r->>'signal')::uuid;
  PERFORM pg_temp.t_check('Office registers vehicle objects', moto IS NOT NULL AND moto_bad IS NOT NULL AND car IS NOT NULL);

  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_FLEET',
    jsonb_build_object('object_id', car, 'capacity_class', 'BODA_BODA', 'home_estate_id', est, 'inspection_status', 'PASSED', 'insurance_status', 'ACTIVE'));
  PERFORM pg_temp.t_check('a car cannot be registered as a boda', r->>'status' = 'REJECTED', r::text);

  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_FLEET',
    jsonb_build_object('object_id', moto, 'capacity_class', 'BODA_BODA', 'home_estate_id', est, 'inspection_status', 'PASSED', 'insurance_status', 'ACTIVE'));
  fleet := (r->>'signal')::uuid;
  -- plate ending 00 -> NTSA simulator NOT_FOUND (KMGA100Z normalises to ...00Z; use a 00 suffix plate below)
  UPDATE trustride.object_registry SET plate_number = 'KMGA100' WHERE object_id = moto_bad;
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_FLEET',
    jsonb_build_object('object_id', moto_bad, 'capacity_class', 'BODA_BODA', 'home_estate_id', est, 'inspection_status', 'PASSED', 'insurance_status', 'ACTIVE'));
  fleet_bad := (r->>'signal')::uuid;
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_FLEET',
    jsonb_build_object('object_id', car, 'capacity_class', 'SEDAN', 'home_estate_id', est, 'inspection_status', 'PASSED', 'insurance_status', 'EXPIRED'));
  fleet_car := (r->>'signal')::uuid;
  PERFORM pg_temp.t_cycle(8);

  SELECT lifecycle_state::text INTO v FROM trustride.resource_fleet_register WHERE fleet_resource_id = fleet;
  PERFORM pg_temp.t_check('NTSA-valid, inspected, insured vehicle becomes VERIFIED', v = 'VERIFIED', v);
  PERFORM pg_temp.t_check('Foundation object marked ACTIVE after NTSA', EXISTS (SELECT 1 FROM trustride.object_registry WHERE object_id = moto AND status = 'ACTIVE'));
  SELECT lifecycle_state::text INTO v FROM trustride.resource_fleet_register WHERE fleet_resource_id = fleet_bad;
  PERFORM pg_temp.t_check('plate NTSA cannot find is not verified', v = 'REGISTERED', v);
  PERFORM pg_temp.t_check('Foundation object marked VERIFICATION_FAILED', EXISTS (SELECT 1 FROM trustride.object_registry WHERE object_id = moto_bad AND status = 'VERIFICATION_FAILED'));
  SELECT lifecycle_state::text INTO v FROM trustride.resource_fleet_register WHERE fleet_resource_id = fleet_car;
  PERFORM pg_temp.t_check('expired insurance is not verified', v = 'REGISTERED', v);

  -- Onboarding
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ONBOARD_OPERATOR',
    jsonb_build_object('operator_user_id', notyet, 'capacity_class', 'BODA_BODA', 'estate_id', est, 'fleet_resource_id', fleet));
  PERFORM pg_temp.t_check('an unapproved applicant cannot be onboarded', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ONBOARD_OPERATOR',
    jsonb_build_object('operator_user_id', op, 'capacity_class', 'BODA_BODA', 'estate_id', est, 'fleet_resource_id', fleet_bad));
  PERFORM pg_temp.t_check('an unverified vehicle cannot be bound', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ONBOARD_OPERATOR',
    jsonb_build_object('operator_user_id', op, 'capacity_class', 'BODA_BODA', 'estate_id', est));
  PERFORM pg_temp.t_check('a boda unit needs a vehicle', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ONBOARD_OPERATOR',
    jsonb_build_object('operator_user_id', op, 'capacity_class', 'BODA_BODA', 'estate_id', est, 'fleet_resource_id', fleet));
  PERFORM pg_temp.t_check('Office onboards an approved operator with a verified vehicle', r->>'status' = 'TRANSLATED', r::text);
  unit := (r->>'signal')::uuid;
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ONBOARD_OPERATOR',
    jsonb_build_object('operator_user_id', op2, 'capacity_class', 'BODA_BODA', 'estate_id', est, 'fleet_resource_id', fleet));
  PERFORM pg_temp.t_check('one vehicle cannot serve two units', r->>'status' = 'REJECTED', r::text);
  PERFORM pg_temp.t_check('new unit starts OFF DUTY', trustride.fn_resource_unit_availability(unit) = 'OFFLINE');
  PERFORM pg_temp.t_check('vehicle custody moves to the operator', EXISTS (SELECT 1 FROM trustride.resource_fleet_register WHERE fleet_resource_id = fleet AND custodian_user_id = op));
  PERFORM pg_temp.t_check('employment engagement opened (Article 44)', EXISTS (
    SELECT 1 FROM trustride.business_operator_engagement e JOIN trustride.business_actor_registration a ON a.actor_registration_id = e.actor_registration_id
    WHERE a.user_id = op AND e.engagement_status = 'ACTIVE'));
  PERFORM pg_temp.t_check('operator told they are onboarded', EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = op AND title = 'You are onboarded'));
  SELECT count(*) INTO n FROM trustride.fn_resource_discover_eligible('BODA_BODA', -0.09, 34.77, 'STANDARD', '[]', 'KISUMU_COUNTY');
  PERFORM pg_temp.t_check('an off-duty unit is not offered work', n = 0, n::text);

  -- Duty
  r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'SET_DUTY', '{"on_duty":true}');
  PERFORM pg_temp.t_check('operator starts shift from the Operator App', r->>'status' = 'TRANSLATED' AND trustride.fn_resource_unit_availability(unit) = 'AVAILABLE', r::text);
  SELECT count(*) INTO n FROM trustride.fn_resource_discover_eligible('BODA_BODA', -0.09, 34.77, 'STANDARD', '[]', 'KISUMU_COUNTY');
  PERFORM pg_temp.t_check('on-duty unit is discoverable', n = 1, n::text);
  SELECT count(*) INTO n FROM trustride.fn_resource_discover_eligible('BODA_BODA', -0.09, 34.77, 'STANDARD', '[]', 'NAIROBI_METRO');
  PERFORM pg_temp.t_check('a Kisumu unit is not offered Nairobi work', n = 0, n::text);
  r := pg_temp.t_cmd(op2, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'SET_DUTY', '{"on_duty":true}');
  PERFORM pg_temp.t_check('an operator with no unit cannot go on duty', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'SET_DUTY', '{"on_duty":true}');
  PERFORM pg_temp.t_check('a customer cannot open the Operator App', r->>'status' = 'SESSION_REFUSED', r::text);

  -- Office intervention
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'SET_UNIT_STATE',
    jsonb_build_object('workforce_unit_id', unit, 'state', 'MAINTENANCE', 'reason', 'Brake service'));
  PERFORM pg_temp.t_check('Office sends a unit to maintenance', trustride.fn_resource_unit_availability(unit) = 'MAINTENANCE', r::text);
  r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'SET_DUTY', '{"on_duty":true}');
  PERFORM pg_temp.t_check('a unit in maintenance cannot go on duty', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'SET_UNIT_STATE',
    jsonb_build_object('workforce_unit_id', unit, 'state', 'AVAILABLE', 'reason', 'Service done'));
  PERFORM pg_temp.t_check('Office returns it to service', trustride.fn_resource_unit_availability(unit) = 'AVAILABLE');

  -- Executive Assistant: vetting and certifications (G15)
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ONBOARD_OPERATOR',
    jsonb_build_object('operator_user_id', ea, 'capacity_class', 'EXECUTIVE_ASSISTANT_HUMAN', 'estate_id', est));
  ea_unit := (r->>'signal')::uuid;
  PERFORM pg_temp.t_check('Office onboards an Executive Assistant (no vehicle)', r->>'status' = 'TRANSLATED', r::text);
  r := pg_temp.t_cmd(ea, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'SET_DUTY', '{"on_duty":true}');
  SELECT count(*) INTO n FROM trustride.fn_resource_discover_eligible('EXECUTIVE_ASSISTANT_HUMAN', -0.09, 34.77, 'ENHANCED', '["SKILL_CAREGIVING"]', 'KISUMU_COUNTY');
  PERFORM pg_temp.t_check('an un-vetted EA is never matched to ENHANCED (caregiving) work', n = 0, n::text);
  SELECT count(*) INTO n FROM trustride.fn_resource_discover_eligible('EXECUTIVE_ASSISTANT_HUMAN', -0.09, 34.77, 'STANDARD', '["SKILL_ERRANDS"]', 'KISUMU_COUNTY');
  PERFORM pg_temp.t_check('an EA without the skill is not matched', n = 0, n::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RECORD_CAPABILITY',
    jsonb_build_object('workforce_unit_id', ea_unit, 'capability_type', 'ENHANCED_VETTING_CLEARANCE', 'credential_ref', 'DCI-2026-0001', 'expires_at', now() + interval '1 year'));
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RECORD_CAPABILITY',
    jsonb_build_object('workforce_unit_id', ea_unit, 'capability_type', 'SKILL_CAREGIVING', 'credential_ref', 'CARE-CERT-77'));
  cap := (r->>'signal')::uuid;
  SELECT count(*) INTO n FROM trustride.fn_resource_discover_eligible('EXECUTIVE_ASSISTANT_HUMAN', -0.09, 34.77, 'ENHANCED', '["SKILL_CAREGIVING"]', 'KISUMU_COUNTY');
  PERFORM pg_temp.t_check('vetted, certified EA is matched to caregiving', n = 1, n::text);
  UPDATE trustride.resource_workforce_capability SET expires_at = now() - interval '1 day'
  WHERE workforce_unit_id = ea_unit AND capability_type = 'ENHANCED_VETTING_CLEARANCE';
  SELECT count(*) INTO n FROM trustride.fn_resource_discover_eligible('EXECUTIVE_ASSISTANT_HUMAN', -0.09, 34.77, 'ENHANCED', '["SKILL_CAREGIVING"]', 'KISUMU_COUNTY');
  PERFORM pg_temp.t_check('an expired clearance stops matching immediately', n = 0, n::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REVOKE_CAPABILITY', jsonb_build_object('capability_id', cap, 'reason', 'test'));
  PERFORM pg_temp.t_check('Office revokes a credential', NOT EXISTS (SELECT 1 FROM trustride.resource_workforce_capability WHERE capability_id = cap AND active));

  -- Telemetry identity
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_OBJECT',
    '{"object_type":"TRACKING_DEVICE","make":"Protrack","model":"PT-100","serial_number":"865000000000777"}');
  dev := (r->>'signal')::uuid;
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'BIND_TELEMETRY_DEVICE', jsonb_build_object('fleet_resource_id', fleet, 'device_object_id', dev));
  PERFORM pg_temp.t_check('Office binds a Protrack device to the motorcycle', r->>'status' = 'TRANSLATED' AND EXISTS (
    SELECT 1 FROM trustride.resource_telemetry_binding WHERE fleet_resource_id = fleet AND provider_device_ref = '865000000000777' AND status = 'ACTIVE'), r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'BIND_TELEMETRY_DEVICE', jsonb_build_object('fleet_resource_id', fleet, 'device_object_id', moto));
  PERFORM pg_temp.t_check('only a TRACKING_DEVICE can be bound', r->>'status' = 'REJECTED', r::text);

  -- Negative: Office commands are Office-only
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_OBJECT', '{"object_type":"CAR","plate_number":"KAA 1"}');
  PERFORM pg_temp.t_check('a customer cannot reach the Admin Console', r->>'status' = 'SESSION_REFUSED', r::text);
  r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'ONBOARD_OPERATOR', jsonb_build_object('operator_user_id', op2));
  PERFORM pg_temp.t_check('an operator cannot issue Admin verbs', r->>'status' = 'CAPTURE_REFUSED', r::text);
  PERFORM pg_temp.t_as(op);
  PERFORM pg_temp.t_check('an operator cannot call Office resource functions directly',
    pg_temp.t_fails(format('SELECT trustride.fn_resource_office_unit_state_set(%L, ''OFFLINE'', ''x'')', unit)));
  PERFORM pg_temp.t_admin();

  -- Dissolve
  PERFORM pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'SET_DUTY', '{"on_duty":false}');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'DISSOLVE_UNIT', jsonb_build_object('workforce_unit_id', unit, 'reason', 'Reassignment'));
  PERFORM pg_temp.t_check('Office dissolves a unit; vehicle returns to the pool', r->>'status' = 'TRANSLATED' AND EXISTS (
    SELECT 1 FROM trustride.resource_availability_ledger WHERE resource_type = 'FLEET' AND resource_ref_id = fleet AND effective_to IS NULL AND availability_state = 'AVAILABLE'), r::text);

  SELECT count(*) INTO n FROM trustride.fn_platform_conformance_violations();
  PERFORM pg_temp.t_check('conformance: zero violations', n = 0, n || ' violations');
END;
$$;
