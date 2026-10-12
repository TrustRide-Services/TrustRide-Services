-- Suite 31 -- integration hardening, database side (Construction Directive WP7, section 2.8).
-- The gateway leaves a money request whose fate is unknown in SENT; Engine 6 must then settle it
-- safely: Safaricom's late result still applies, an unanswered request becomes a final failure plus an
-- Office instruction to verify on the M-Pesa portal, and nothing is ever re-sent automatically.
-- Google email is registered as a built adapter awaiting credentials, and the Office can switch it.
DO $$
DECLARE
  founder UUID; cust UUID; est UUID; r JSONB; ord UUID; t RECORD; req RECORD; v TEXT; n INT; b2c UUID; ok BOOLEAN;
BEGIN
  PERFORM pg_temp.t_open_all_hours();
  founder := pg_temp.t_person('Hard Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  cust := pg_temp.t_customer('Hard Payer');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"H-HUB","estate_type":"OPERATING_HUB","estate_name":"Hardening Hub","lat":-0.0917,"lon":34.7680}');
  est := (r->>'signal')::uuid;
  PERFORM pg_temp.t_ready_unit(founder, 'BODA_BODA', est, 'Rider H');
  PERFORM pg_temp.t_as(founder);
  PERFORM trustride.fn_integration_adapter_set('PAYMENT_GATEWAY', 'PRODUCTION', 'suite 31');
  PERFORM pg_temp.t_admin();

  -- ============ STK push whose fate is unknown (the gateway reported nothing)
  ord := pg_temp.t_order_to_completed(cust);
  SELECT * INTO t FROM trustride.integration_payment_gateway_transaction WHERE order_id = ord;
  UPDATE trustride.integration_outbound_request SET status = 'SENT', sent_at = now() - interval '5 minutes', provider_reference = NULL
  WHERE request_id = t.outbound_request_id;
  PERFORM trustride.fn_integration_outbound_retry_sweep();
  SELECT * INTO req FROM trustride.integration_outbound_request WHERE request_id = t.outbound_request_id;
  PERFORM pg_temp.t_check('money: an unknown STK outcome is left alone inside its window (no failure, no re-send)',
    req.status = 'SENT' AND req.attempts = 1, req.status || ' attempts=' || req.attempts);
  UPDATE trustride.integration_outbound_request SET sent_at = now() - interval '11 minutes' WHERE request_id = t.outbound_request_id;
  PERFORM trustride.fn_integration_outbound_retry_sweep();
  SELECT * INTO req FROM trustride.integration_outbound_request WHERE request_id = t.outbound_request_id;
  PERFORM pg_temp.t_check('money: after the window it is a final failure that names the Safaricom portal check',
    req.status = 'FAILED' AND req.last_error LIKE 'NO_FINAL_RESULT_FROM_MPESA%', req.status || ' ' || coalesce(req.last_error, ''));
  PERFORM pg_temp.t_check('money: the Office is told to verify with Safaricom before any retry',
    EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = founder AND title = 'Verify STK_PUSH with Safaricom'));
  SELECT count(*) INTO n FROM trustride.integration_outbound_request WHERE ref_id = t.gateway_txn_id AND operation = 'STK_PUSH';
  PERFORM trustride.fn_integration_outbound_retry_sweep();
  PERFORM pg_temp.t_check('money: the push is never re-sent automatically',
    n = 1 AND (SELECT attempts FROM trustride.integration_outbound_request WHERE request_id = t.outbound_request_id) = 1, n::text);
  PERFORM pg_temp.t_check('money: the payment is recorded failed, not paid',
    (SELECT txn_status::text FROM trustride.integration_payment_gateway_transaction WHERE gateway_txn_id = t.gateway_txn_id) = 'FAILED');

  -- ============ B2C payout: unknown outcome, then Safaricom's result arrives
  b2c := trustride.fn_integration_outbound_enqueue('PAYMENT_GATEWAY', 'B2C_PAYOUT',
    '{"msisdn":"254712345678","amount":500,"remarks":"suite 31"}', 'VENDOR_PAYOUT', gen_random_uuid(), gen_random_uuid());
  UPDATE trustride.integration_outbound_request SET status = 'SENT', sent_at = now() - interval '5 minutes', provider_reference = NULL WHERE request_id = b2c;
  v := trustride.fn_integration_outbound_result(b2c, TRUE, 'SGR7B2C001', '{"Result":{"ResultCode":0}}', NULL);
  PERFORM pg_temp.t_check('money: a B2C whose call timed out is still settled by Safaricom''s result (never lost)',
    v = 'SUCCEEDED' AND EXISTS (SELECT 1 FROM trustride.integration_event_outbox WHERE idempotency_key = 'VENDOR_PAYOUT_RESULT:' || b2c::text AND signal_type = 'VENDOR_PAYOUT_COMPLETED'), v);

  -- ============ B2C accepted by Safaricom: 2 hours for its result, then Office verification
  b2c := trustride.fn_integration_outbound_enqueue('PAYMENT_GATEWAY', 'B2C_PAYOUT',
    '{"msisdn":"254712345678","amount":700,"remarks":"suite 31"}', 'VENDOR_PAYOUT', gen_random_uuid(), gen_random_uuid());
  UPDATE trustride.integration_outbound_request SET status = 'SENT', sent_at = now() - interval '30 minutes' WHERE request_id = b2c;
  PERFORM trustride.fn_integration_gateway_ack(b2c, 'AG_20261012_0001', '{"ResponseCode":"0"}');
  PERFORM trustride.fn_integration_outbound_retry_sweep();
  PERFORM pg_temp.t_check('money: an accepted B2C keeps waiting for its result inside 2 hours',
    (SELECT status FROM trustride.integration_outbound_request WHERE request_id = b2c) = 'SENT');
  UPDATE trustride.integration_outbound_request SET sent_at = now() - interval '3 hours' WHERE request_id = b2c;
  PERFORM trustride.fn_integration_outbound_retry_sweep();
  PERFORM pg_temp.t_check('money: an accepted B2C with no result after 2 hours -> failed and Office verification (with the reference)',
    (SELECT status FROM trustride.integration_outbound_request WHERE request_id = b2c) = 'FAILED'
    AND EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = founder AND title = 'Verify B2C_PAYOUT with Safaricom' AND body LIKE '%AG_20261012_0001%'));
  v := trustride.fn_integration_outbound_result(b2c, TRUE, 'late', '{}', NULL);
  PERFORM pg_temp.t_check('money: after Office verification is requested, a late result cannot silently flip the record',
    v = 'FAILED', v);

  PERFORM pg_temp.t_as(founder);
  PERFORM trustride.fn_integration_adapter_set('PAYMENT_GATEWAY', 'SIMULATOR', 'suite 31');
  PERFORM pg_temp.t_admin();

  -- ============ Google email (decision 2.8)
  SELECT live_adapter || '|' || readiness || '|' || primary_vendor INTO v FROM trustride.integration_port_registry WHERE port_code = 'EMAIL_SERVICE' AND active;
  PERFORM pg_temp.t_check('email: Google email is registered as a built adapter awaiting credentials',
    v LIKE 'BUILT|LIVE_READY_PENDING_CREDENTIALS|Google%', coalesce(v, 'none'));
  PERFORM pg_temp.t_as(founder);
  BEGIN PERFORM trustride.fn_integration_adapter_set('EMAIL_SERVICE', 'PRODUCTION', 'suite 31'); ok := true; v := 'switched';
  EXCEPTION WHEN OTHERS THEN ok := false; v := SQLERRM; END;
  PERFORM pg_temp.t_check('email: the Office can switch email to the live adapter', ok, left(v, 160));
  PERFORM pg_temp.t_admin();
  PERFORM trustride.fn_integration_notification_deliver(cust, 'EMAIL', 'payer@example.co.ke', 'TRUSTRIDE_NOTICE',
    '{"title":"Receipt","body":"Thank you"}', gen_random_uuid());
  SELECT * INTO req FROM trustride.integration_outbound_request WHERE port_code = 'EMAIL_SERVICE' AND created_at = now() ORDER BY created_at DESC LIMIT 1;
  PERFORM pg_temp.t_check('email: a live email becomes one NOTIFY_EMAIL request to the gateway (never simulated as sent)',
    req.operation = 'NOTIFY_EMAIL' AND req.status IN ('SENT', 'WAITING_CONFIGURATION') AND req.payload->>'destination' = 'payer@example.co.ke',
    coalesce(req.status, 'none'));
END
$$;
