-- Suite 02 -- Identity, contact verification, registrant classes, the
-- integration gateway boundary and notification delivery.
DO $$
DECLARE
  cust UUID; other UUID; founder UUID; partner UUID; rep UUID; outsider UUID;
  c_phone UUID; c_other UUID; v_body TEXT; v_code TEXT; ok BOOLEAN; n INT; v TEXT;
  ent UUID; ent_bad UUID; sys UUID; v_key TEXT; obj UUID; obj2 UUID; sess UUID; req UUID; r RECORD;
BEGIN
  cust := pg_temp.t_person('Wanjiru', 'CUSTOMER');
  other := pg_temp.t_person('Otieno', 'CUSTOMER');
  founder := pg_temp.t_person('Founder', NULL);
  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  partner := pg_temp.t_person('Partner', 'PARTNER');
  rep := pg_temp.t_person('Company Rep', NULL);
  outsider := pg_temp.t_person('Outsider', NULL);

  -- ---------------------------------------------------------------- contact
  PERFORM pg_temp.t_as(cust);
  c_phone := trustride.fn_user_contact_add('PHONE', '0712 345 678');
  SELECT contact_value INTO v FROM trustride.user_contact WHERE contact_id = c_phone;
  PERFORM pg_temp.t_check('phone normalised to E.164', v = '+254712345678', v);
  PERFORM pg_temp.t_check('bad phone rejected', pg_temp.t_fails('SELECT trustride.fn_user_contact_add(''PHONE'', ''12345'')'));
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_as(cust);
  SELECT payload->>'body' INTO v_body FROM trustride.integration_notification_dispatch_log
  WHERE recipient_ref = cust AND template_code = 'CONTACT_VERIFICATION_CODE' ORDER BY created_at DESC LIMIT 1;
  v_code := substring(v_body from '([0-9]{6})');
  PERFORM pg_temp.t_check('verification SMS delivered (simulator) and visible to its owner', v_code IS NOT NULL, v_body);
  PERFORM pg_temp.t_check('wrong code refused', trustride.fn_user_contact_verify(c_phone, '000000') = FALSE OR v_code = '000000');
  ok := trustride.fn_user_contact_verify(c_phone, v_code);
  PERFORM pg_temp.t_check('right code verifies the phone', ok);
  SELECT is_verified AND is_primary INTO ok FROM trustride.user_contact WHERE contact_id = c_phone;
  PERFORM pg_temp.t_check('verified phone becomes primary', ok);
  PERFORM pg_temp.t_check('only verified phone cannot be removed', pg_temp.t_fails(format('SELECT trustride.fn_user_contact_remove(%L)', c_phone)));

  -- The same number cannot be verified on a second identity.
  PERFORM pg_temp.t_as(other);
  PERFORM pg_temp.t_check('a verified number cannot be claimed by another identity',
    pg_temp.t_fails('SELECT trustride.fn_user_contact_add(''PHONE'', ''+254712345678'')'));
  PERFORM pg_temp.t_check('another user cannot verify my contact', pg_temp.t_fails(format('SELECT trustride.fn_user_contact_verify(%L, ''123456'')', c_phone)));
  PERFORM pg_temp.t_check('another user cannot read my contacts', pg_temp.t_visible('user_contact', format('user_id = %L', cust)) = 0);
  PERFORM pg_temp.t_check('another user cannot read my simulated messages', pg_temp.t_visible('integration_notification_dispatch_log', format('recipient_ref = %L', cust)) = 0);
  PERFORM pg_temp.t_admin();

  SELECT destination INTO v FROM trustride.fn_user_contact_resolve(cust, 'SMS');
  PERFORM pg_temp.t_check('Foundation resolves the SMS destination', v = '+254712345678');
  PERFORM pg_temp.t_check('M-Pesa payer number comes from the verified phone', trustride.fn_user_payment_msisdn(cust) = '254712345678');
  PERFORM pg_temp.t_check('no verified phone -> no payer number', trustride.fn_user_payment_msisdn(other) IS NULL);

  -- ------------------------------------------------- notification fan-out
  INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, category)
  VALUES (cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'Driver assigned', 'Your boda is on the way.', 'ORDER');
  INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, category)
  VALUES (other, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'Driver assigned', 'Your boda is on the way.', 'ORDER');
  PERFORM pg_temp.t_cycle(4);
  SELECT status::text INTO v FROM trustride.integration_notification_dispatch_log WHERE recipient_ref = cust AND template_code = 'TRUSTRIDE_NOTICE' ORDER BY created_at DESC LIMIT 1;
  PERFORM pg_temp.t_check('in-app notification also delivered by SMS', v = 'DISPATCHED', v);
  SELECT status::text INTO v FROM trustride.integration_notification_dispatch_log WHERE recipient_ref = other AND template_code = 'TRUSTRIDE_NOTICE' ORDER BY created_at DESC LIMIT 1;
  PERFORM pg_temp.t_check('person without a verified phone recorded UNREACHABLE (not dropped)', v = 'UNREACHABLE', v);

  PERFORM pg_temp.t_as(cust);
  PERFORM trustride.fn_user_contact_preference_set('SMS', FALSE);
  PERFORM pg_temp.t_admin();
  INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, category)
  VALUES (cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'Promo', 'Opted out.', 'GENERAL') RETURNING notification_id INTO req;
  PERFORM pg_temp.t_cycle(4);
  SELECT status::text INTO v FROM trustride.integration_notification_dispatch_log WHERE correlation_id = req;
  PERFORM pg_temp.t_check('opted-out channel recorded SUPPRESSED', v = 'SUPPRESSED', v);

  n := trustride.fn_present_notify_office('Order cannot be served', 'TEST', 'EXCEPTION', gen_random_uuid());
  PERFORM pg_temp.t_check('Office exception notification reaches the Founder', n >= 1 AND EXISTS (
    SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = founder AND category = 'EXCEPTION'));

  -- -------------------------------------------- gateway boundary behaviour
  PERFORM pg_temp.t_as(founder);
  PERFORM trustride.fn_integration_adapter_set('SMS_SERVICE', 'PRODUCTION', 'test');
  PERFORM pg_temp.t_admin();
  -- (Vault may hold real gateway config on staging; force the unconfigured
  -- path by checking what the dispatcher reports.)
  req := trustride.fn_integration_outbound_enqueue('SMS_SERVICE', 'NOTIFY_SMS', '{"destination":"+254700000000","body":"x"}', 'TEST', gen_random_uuid(), NULL);
  SELECT status INTO v FROM trustride.integration_outbound_request WHERE request_id = req;
  PERFORM pg_temp.t_check('PRODUCTION adapter: request is SENT to the gateway or explicitly WAITING_CONFIGURATION',
    v IN ('SENT', 'WAITING_CONFIGURATION'), v);
  PERFORM trustride.fn_integration_outbound_result(req, FALSE, NULL, NULL, 'provider down');
  SELECT status INTO v FROM trustride.integration_outbound_request WHERE request_id = req;
  PERFORM pg_temp.t_check('a provider failure is retryable, not lost', v IN ('FAILED_RETRYABLE', 'WAITING_CONFIGURATION'), v);
  PERFORM pg_temp.t_as(founder);
  PERFORM trustride.fn_integration_adapter_set('SMS_SERVICE', 'SIMULATOR', 'test');
  PERFORM pg_temp.t_admin();
  UPDATE trustride.integration_outbound_request SET next_attempt_at = now() WHERE request_id = req;
  PERFORM trustride.fn_integration_outbound_retry_sweep();
  SELECT status INTO v FROM trustride.integration_outbound_request WHERE request_id = req;
  PERFORM pg_temp.t_check('retry sweep completes the request once an adapter can serve it', v = 'SUCCEEDED', v);
  PERFORM trustride.fn_integration_outbound_result(req, FALSE, NULL, NULL, 'late duplicate');
  SELECT status INTO v FROM trustride.integration_outbound_request WHERE request_id = req;
  PERFORM pg_temp.t_check('a late duplicate result changes nothing (idempotent)', v = 'SUCCEEDED', v);
  PERFORM pg_temp.t_as(cust);
  PERFORM pg_temp.t_check('customer cannot switch adapters', pg_temp.t_fails('SELECT trustride.fn_integration_adapter_set(''SMS_SERVICE'', ''PRODUCTION'')'));
  PERFORM pg_temp.t_check('customer cannot report gateway results', pg_temp.t_fails(format('SELECT trustride.fn_integration_outbound_result(%L, true, null, null, null)', req)));

  -- --------------------------------------------- registrant class LEGAL_ENTITY
  PERFORM pg_temp.t_as(rep);
  PERFORM pg_temp.t_check('commercial entity needs a KRA PIN',
    pg_temp.t_fails('SELECT trustride.fn_registration_capture_entity(''Kisumu Fleet Ltd'', ''COMPANY'', ''PVT-ABC123'', NULL)'));
  ent := trustride.fn_registration_capture_entity('Kisumu Fleet Ltd', 'COMPANY', 'PVT-ABC123', 'P051234567X', '42');
  ent_bad := trustride.fn_registration_capture_entity('Ghost Co', 'COMPANY', '00-NOTREAL', 'P059999999Z');
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(6);
  SELECT status INTO v FROM trustride.platform_users WHERE user_id = ent;
  PERFORM pg_temp.t_check('entity verified through Engine 6 becomes ACTIVE', v = 'ACTIVE', v);
  SELECT status INTO v FROM trustride.platform_users WHERE user_id = ent_bad;
  PERFORM pg_temp.t_check('entity not found at the registry is VERIFICATION_FAILED', v = 'VERIFICATION_FAILED', v);
  PERFORM pg_temp.t_check('KRA PIN kept on the entity profile', EXISTS (SELECT 1 FROM trustride.entity_profile WHERE user_id = ent AND kra_pin = 'P051234567X'));

  PERFORM pg_temp.t_as(rep);
  PERFORM trustride.fn_business_actor_register(ent, 'PARTNER', 'Fleet partner');
  sess := trustride.fn_present_shell_session_open('TRUSTRIDE_BUSINESS', 'PARTNER_APP', ent, 'WEB');
  PERFORM pg_temp.t_check('representative opens Partner App for the entity', sess IS NOT NULL);
  PERFORM pg_temp.t_check('session records who is acting', EXISTS (SELECT 1 FROM trustride.present_shell_session WHERE session_id = sess AND acting_person_user_id = rep AND user_id = ent));
  PERFORM pg_temp.t_check('representative may not open TrustRide Office for an entity',
    pg_temp.t_fails(format('SELECT trustride.fn_present_shell_session_open(''TRUSTRIDE_OFFICE'', ''ADMIN_CONSOLE'', %L, ''WEB'')', ent)));
  PERFORM pg_temp.t_as(outsider);
  PERFORM pg_temp.t_check('a non-representative cannot act for the entity',
    pg_temp.t_fails(format('SELECT trustride.fn_present_shell_session_open(''TRUSTRIDE_BUSINESS'', ''PARTNER_APP'', %L, ''WEB'')', ent)));
  PERFORM pg_temp.t_check('a non-representative cannot register environments for the entity',
    pg_temp.t_fails(format('SELECT trustride.fn_business_actor_register(%L, ''CUSTOMER'')', ent)));

  -- ------------------------------------------ registrant class EXTERNAL_SYSTEM
  PERFORM pg_temp.t_as(cust);
  PERFORM pg_temp.t_check('customer cannot register an external system',
    pg_temp.t_fails('SELECT trustride.fn_registration_capture_external_system(''Protrack'', ''GPS telemetry'')'));
  PERFORM pg_temp.t_as(founder);
  sys := trustride.fn_registration_capture_external_system('Protrack', 'GPS telemetry for TrustRide vehicles');
  v_key := trustride.fn_external_system_credential_issue(sys, ARRAY['TELEMETRY_INGEST']);
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('system credential authenticates for its scope', trustride.fn_external_system_authenticate(v_key, 'TELEMETRY_INGEST') = sys);
  PERFORM pg_temp.t_check('system credential refused outside its scope', trustride.fn_external_system_authenticate(v_key, 'PAYMENT_CALLBACK') IS NULL);
  PERFORM pg_temp.t_check('a wrong key is refused', trustride.fn_external_system_authenticate(split_part(v_key, '.', 1) || '.deadbeef', 'TELEMETRY_INGEST') IS NULL);
  PERFORM pg_temp.t_check('only the key hash is stored', NOT EXISTS (SELECT 1 FROM trustride.entity_system_credential WHERE key_hash = v_key));
  PERFORM pg_temp.t_as(founder);
  PERFORM trustride.fn_external_system_credential_revoke(split_part(v_key, '.', 1));
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('a revoked key is refused', trustride.fn_external_system_authenticate(v_key, 'TELEMETRY_INGEST') IS NULL);

  -- ------------------------------------------------- registrant class OBJECT
  PERFORM pg_temp.t_as(founder);
  obj := trustride.fn_registration_capture_object('MOTORCYCLE', 'Honda', 'CB125', 2024::smallint, 'KMFA 123A', NULL, founder);
  PERFORM pg_temp.t_check('Office registers a motorcycle (pending NTSA)', EXISTS (SELECT 1 FROM trustride.object_registry WHERE object_id = obj AND status = 'PENDING_VERIFICATION' AND plate_number = 'KMFA123A'));
  PERFORM pg_temp.t_check('duplicate plate refused', pg_temp.t_fails('SELECT trustride.fn_registration_capture_object(''MOTORCYCLE'', ''Honda'', ''X'', 2024::smallint, ''KMFA123A'', NULL)'));
  obj2 := trustride.fn_registration_capture_object('TRACKING_DEVICE', 'Protrack', 'PT-200', NULL, NULL, '860000000000001');
  PERFORM pg_temp.t_check('Office registers a tracking device (active)', EXISTS (SELECT 1 FROM trustride.object_registry WHERE object_id = obj2 AND status = 'ACTIVE'));
  PERFORM pg_temp.t_as(partner);
  PERFORM pg_temp.t_check('approved partner registers a vehicle into own custody',
    NOT pg_temp.t_fails('SELECT trustride.fn_registration_capture_object(''CAR'', ''Toyota'', ''Probox'', 2018::smallint, ''KDA 555B'', NULL)'));
  PERFORM pg_temp.t_as(cust);
  PERFORM pg_temp.t_check('customer cannot register objects',
    pg_temp.t_fails('SELECT trustride.fn_registration_capture_object(''CAR'', ''Toyota'', ''Vitz'', 2015::smallint, ''KCC 111C'', NULL)'));

  -- ------------------------------------------------------ KRA PIN (person)
  PERFORM pg_temp.t_check('person may declare a KRA PIN', NOT pg_temp.t_fails('SELECT trustride.fn_registration_declare_kra_pin(''A001234567X'')'));
  PERFORM pg_temp.t_check('malformed KRA PIN refused', pg_temp.t_fails('SELECT trustride.fn_registration_declare_kra_pin(''12345'')'));
  PERFORM pg_temp.t_admin();

  SELECT count(*) INTO n FROM trustride.fn_platform_conformance_violations();
  PERFORM pg_temp.t_check('conformance: zero violations', n = 0, n || ' violations');
END;
$$;
