-- Suite 34 -- integration register with the nine-level status (Construction Directive section 4.8, WP7)
-- and the WhatsApp workflow (section 2.8). Every port states each of the nine checkpoints with its
-- evidence; its level is the highest checkpoint reached without a gap; no port claims credentials, a live
-- end-to-end transaction or proven operations without a built live adapter; and the WhatsApp channel is
-- proven through Engine 6 (simulator delivery, live hand-off to the gateway, quiet hours, failure).
DO $$
DECLARE
  founder UUID; cust UUID; d UUID; v TEXT; n INT; req RECORD; ok BOOLEAN;
  ready BOOLEAN := EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'trustride'
                           AND table_name = 'integration_port_registry' AND column_name = 'status_checkpoints');
BEGIN
  founder := pg_temp.t_person('Reg Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  cust := pg_temp.t_customer('Wa Customer');
  INSERT INTO trustride.user_contact (user_id, contact_type, contact_value, is_primary, is_verified, verified_at, status)
  VALUES (cust, 'WHATSAPP', '+254733000111', FALSE, TRUE, now(), 'ACTIVE');

  -- ============ WhatsApp through Engine 6
  d := trustride.fn_integration_notification_send(cust, ARRAY['WHATSAPP'], 'TRUSTRIDE_NOTICE', '{"title":"Trip","body":"Your boda is on the way"}', gen_random_uuid(), TRUE);
  SELECT channel::text || '|' || status::text || '|' || (payload->>'destination_masked') INTO v FROM trustride.integration_notification_dispatch_log WHERE dispatch_id = d;
  PERFORM pg_temp.t_check('WhatsApp: a message is delivered by the simulator on the WhatsApp channel, destination masked',
    v = 'WHATSAPP|DISPATCHED|*********0111', coalesce(v, 'none'));
  PERFORM pg_temp.t_as(founder);
  PERFORM trustride.fn_integration_adapter_set('WHATSAPP_SERVICE', 'PRODUCTION', 'suite 34');
  PERFORM pg_temp.t_admin();
  d := trustride.fn_integration_notification_send(cust, ARRAY['WHATSAPP'], 'TRUSTRIDE_NOTICE', '{"title":"Trip","body":"Arrived"}', gen_random_uuid(), TRUE);
  SELECT * INTO req FROM trustride.integration_outbound_request WHERE ref_id = d;
  PERFORM pg_temp.t_check('WhatsApp: live, the message becomes one NOTIFY_WHATSAPP request to the gateway and is not shown as delivered',
    req.operation = 'NOTIFY_WHATSAPP' AND req.port_code::text = 'WHATSAPP_SERVICE' AND req.payload->>'destination' = '+254733000111'
    AND (SELECT status::text FROM trustride.integration_notification_dispatch_log WHERE dispatch_id = d) = 'QUEUED', coalesce(req.status, 'none'));
  UPDATE trustride.integration_outbound_request SET attempts = max_attempts WHERE request_id = req.request_id;
  PERFORM trustride.fn_integration_outbound_result(req.request_id, FALSE, NULL, '{"error":{"message":"Re-engagement message"}}', 'Re-engagement message');
  PERFORM pg_temp.t_check('WhatsApp: a provider refusal after the retries is recorded FAILED with its reason',
    (SELECT status::text FROM trustride.integration_notification_dispatch_log WHERE dispatch_id = d) = 'FAILED'
    AND (SELECT last_error FROM trustride.integration_outbound_request WHERE request_id = req.request_id) = 'Re-engagement message');
  d := trustride.fn_integration_notification_send(cust, ARRAY['WHATSAPP'], 'TRUSTRIDE_NOTICE', '{"title":"x","body":"y"}', gen_random_uuid(), TRUE);
  SELECT * INTO req FROM trustride.integration_outbound_request WHERE ref_id = d;
  PERFORM trustride.fn_integration_outbound_result(req.request_id, TRUE, 'wamid.TEST1', '{"messages":[{"id":"wamid.TEST1"}]}', NULL);
  PERFORM trustride.fn_integration_outbound_result(req.request_id, TRUE, 'wamid.TEST2', '{}', NULL);
  PERFORM pg_temp.t_check('WhatsApp: delivery is recorded once with Meta''s message id (a duplicate result changes nothing)',
    (SELECT status::text || '|' || provider_reference FROM trustride.integration_notification_dispatch_log WHERE dispatch_id = d) = 'DISPATCHED|wamid.TEST1');
  PERFORM pg_temp.t_as(founder);
  PERFORM trustride.fn_integration_adapter_set('WHATSAPP_SERVICE', 'SIMULATOR', 'suite 34');
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_as(cust);
  PERFORM pg_temp.t_check('WhatsApp: a customer cannot read another person''s WhatsApp deliveries',
    pg_temp.t_visible('integration_notification_dispatch_log', format('recipient_ref <> %L AND channel = ''WHATSAPP''', cust)) = 0);
  PERFORM pg_temp.t_admin();

  -- ============ the register's nine-level status
  IF NOT ready THEN
    PERFORM pg_temp.t_check('register: every port carries the nine-level integration status', false, 'status_checkpoints absent');
  ELSE
    SELECT count(*), string_agg(port_code::text, ' ') INTO n, v FROM trustride.integration_port_registry
    WHERE active AND live_adapter <> 'INTERNAL'
      AND (SELECT count(*) FROM generate_series(1, 9) g WHERE status_checkpoints ? g::text AND jsonb_typeof(status_checkpoints->g::text->'met') = 'boolean'
             AND coalesce(trim(status_checkpoints->g::text->>'evidence'), '') <> '') < 9;
    PERFORM pg_temp.t_check('register: every external port states all nine checkpoints, each with evidence', n = 0, coalesce(v, ''));
    SELECT count(*), string_agg(port_code::text, ' ') INTO n, v FROM trustride.integration_port_registry
    WHERE active AND status_level <> trustride.fn_integration_status_level(status_checkpoints);
    PERFORM pg_temp.t_check('register: the level is the highest checkpoint reached without a gap', n = 0, coalesce(v, ''));
    SELECT count(*), string_agg(port_code::text, ' ') INTO n, v FROM trustride.integration_port_registry
    WHERE active AND ((status_checkpoints->'7'->>'met')::boolean OR (status_checkpoints->'8'->>'met')::boolean OR (status_checkpoints->'9'->>'met')::boolean);
    PERFORM pg_temp.t_check('register: no port claims credentials, a live end-to-end transaction or proven operations (none exist on staging)', n = 0, coalesce(v, ''));
    BEGIN
      UPDATE trustride.integration_port_registry SET status_checkpoints = jsonb_set(status_checkpoints, '{8}', '{"met":true,"evidence":"wishful"}')
      WHERE port_code = 'NTSA_SERVICE' AND active;
      ok := false; v := 'accepted';
    EXCEPTION WHEN OTHERS THEN ok := true; v := SQLERRM; END;
    PERFORM pg_temp.t_check('register: a live level cannot be recorded for a port whose live adapter is not built', ok, left(v, 160));
    SELECT string_agg(port_code::text || '=' || status_level, ' ' ORDER BY port_code::text) INTO v FROM trustride.integration_port_registry
    WHERE active AND port_code::text IN ('PAYMENT_GATEWAY', 'SMS_SERVICE', 'WHATSAPP_SERVICE', 'EMAIL_SERVICE', 'TELEMETRY_SERVICE', 'IDENTITY_AUTHORITY', 'NTSA_SERVICE', 'ETIMS_SERVICE');
    PERFORM pg_temp.t_check('register: the evidenced levels (adapters built and tested: 6; boundary and simulator only: 5; telemetry 2: no simulator)',
      v = 'EMAIL_SERVICE=6 ETIMS_SERVICE=5 IDENTITY_AUTHORITY=6 NTSA_SERVICE=5 PAYMENT_GATEWAY=6 SMS_SERVICE=6 TELEMETRY_SERVICE=2 WHATSAPP_SERVICE=6', v);
  END IF;
END
$$;
