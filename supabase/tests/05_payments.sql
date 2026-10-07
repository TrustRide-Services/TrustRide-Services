-- Suite 05 -- Payments (G10): simulator, the real Daraja path through the
-- gateway boundary, callbacks, failures, retry, timeout, limits, bank transfer.
DO $$
DECLARE
  founder UUID; cust UUID; other UUID; nophone UUID; est UUID; r JSONB; ord UUID; o RECORD; t RECORD; req RECORD; v TEXT; n INT;
BEGIN
  PERFORM pg_temp.t_open_all_hours();
  founder := pg_temp.t_person('Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  cust := pg_temp.t_customer('Payer');
  other := pg_temp.t_customer('Other');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"P-HUB","estate_type":"OPERATING_HUB","estate_name":"Pay Hub","lat":-0.0917,"lon":34.7680}');
  est := (r->>'signal')::uuid;
  PERFORM pg_temp.t_ready_unit(founder, 'BODA_BODA', est, 'Rider P');

  -- ------------------------------------------------ simulator (staging)
  ord := pg_temp.t_order_to_completed(cust);
  SELECT * INTO t FROM trustride.integration_payment_gateway_transaction WHERE order_id = ord;
  PERFORM pg_temp.t_check('completion requests payment from the verified phone', t.txn_status = 'PENDING_CALLBACK' AND t.msisdn_masked LIKE '%***%', coalesce(t.txn_status::text, 'no txn'));
  r := pg_temp.t_cmd(other, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'CONFIRM_SIMULATED_PAYMENT', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_check('another customer cannot confirm my payment', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'CONFIRM_SIMULATED_PAYMENT', jsonb_build_object('order_id', ord, 'success', false));
  PERFORM pg_temp.t_cycle(6);
  PERFORM pg_temp.t_check('failed payment recorded and customer told how to retry', EXISTS (
    SELECT 1 FROM trustride.business_settlement WHERE order_id = ord AND payment_status = 'FAILED')
    AND EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = cust AND title = 'Payment not completed'), r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RETRY_PAYMENT', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_check('customer retries payment', r->>'status' = 'TRANSLATED', r::text);
  PERFORM pg_temp.t_cycle(4);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'CONFIRM_SIMULATED_PAYMENT', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_cycle(6);
  SELECT o2.status::text AS st, s.receipt_code INTO o FROM trustride.business_order o2 JOIN trustride.business_settlement s ON s.order_id = o2.order_id WHERE o2.order_id = ord;
  PERFORM pg_temp.t_check('retry settles the order with a receipt', o.st = 'SETTLED' AND o.receipt_code IS NOT NULL, o.st);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RETRY_PAYMENT', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_check('a paid order cannot be charged again', r->>'status' = 'REJECTED', r::text);
  SELECT count(*) INTO n FROM trustride.integration_payment_gateway_transaction WHERE order_id = ord AND txn_status = 'SETTLED';
  PERFORM pg_temp.t_check('exactly one settled payment (no duplicate charge)', n = 1, n::text);

  -- ------------------------------------------------ Daraja path (gateway)
  PERFORM pg_temp.t_as(founder);
  PERFORM trustride.fn_integration_adapter_set('PAYMENT_GATEWAY', 'PRODUCTION', 'test');
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_release_completed();
  ord := pg_temp.t_order_to_completed(cust);
  SELECT * INTO t FROM trustride.integration_payment_gateway_transaction WHERE order_id = ord;
  SELECT * INTO req FROM trustride.integration_outbound_request WHERE request_id = t.outbound_request_id;
  PERFORM pg_temp.t_check('PRODUCTION: an STK_PUSH goes to the gateway (or waits for its configuration)',
    req.operation = 'STK_PUSH' AND req.status IN ('SENT', 'WAITING_CONFIGURATION') AND req.payload->>'msisdn' ~ '^2547[0-9]{8}$' AND (req.payload->>'amount')::int > 0,
    coalesce(req.status, 'none') || ' ' || coalesce(req.payload::text, ''));
  PERFORM trustride.fn_integration_outbound_result(req.request_id, TRUE, 'ws_CO_TEST_0001', '{"ResponseCode":"0","CustomerMessage":"Success. Request accepted for processing"}', NULL);
  SELECT * INTO t FROM trustride.integration_payment_gateway_transaction WHERE gateway_txn_id = t.gateway_txn_id;
  PERFORM pg_temp.t_check('Safaricom accepted the push -> PENDING_CALLBACK with CheckoutRequestID', t.txn_status = 'PENDING_CALLBACK' AND t.provider_reference = 'ws_CO_TEST_0001', t.txn_status::text);
  v := trustride.fn_integration_mpesa_callback_ingest(jsonb_build_object('Body', jsonb_build_object('stkCallback', jsonb_build_object(
    'MerchantRequestID', 'm-1', 'CheckoutRequestID', 'ws_CO_TEST_0001', 'ResultCode', 0, 'ResultDesc', 'The service request is processed successfully.',
    'CallbackMetadata', jsonb_build_object('Item', jsonb_build_array(jsonb_build_object('Name', 'Amount', 'Value', ceil(t.amount_kes)),
      jsonb_build_object('Name', 'MpesaReceiptNumber', 'Value', 'SGR7TEST01'), jsonb_build_object('Name', 'PhoneNumber', 'Value', 254700000000)))))));
  PERFORM pg_temp.t_check('Safaricom success callback settles the transaction', v = 'SETTLED', v);
  v := trustride.fn_integration_mpesa_callback_ingest(jsonb_build_object('Body', jsonb_build_object('stkCallback', jsonb_build_object(
    'CheckoutRequestID', 'ws_CO_TEST_0001', 'ResultCode', 0))));
  PERFORM pg_temp.t_check('a duplicate callback changes nothing', v = 'ALREADY_SETTLED', v);
  PERFORM pg_temp.t_cycle(6);
  SELECT o2.status::text AS st, s.receipt_code INTO o FROM trustride.business_order o2 JOIN trustride.business_settlement s ON s.order_id = o2.order_id WHERE o2.order_id = ord;
  PERFORM pg_temp.t_check('real-path settlement produces the receipt', o.st = 'SETTLED' AND o.receipt_code IS NOT NULL, o.st);
  PERFORM pg_temp.t_check('M-Pesa receipt number kept for reconciliation', EXISTS (SELECT 1 FROM trustride.integration_payment_gateway_transaction WHERE order_id = ord AND mpesa_receipt_number = 'SGR7TEST01'));

  -- cancelled by the customer on the phone, then a timeout
  PERFORM pg_temp.t_release_completed();
  ord := pg_temp.t_order_to_completed(cust);
  SELECT * INTO t FROM trustride.integration_payment_gateway_transaction WHERE order_id = ord;
  PERFORM trustride.fn_integration_outbound_result(t.outbound_request_id, TRUE, 'ws_CO_TEST_0002', '{"ResponseCode":"0"}', NULL);
  v := trustride.fn_integration_mpesa_callback_ingest(jsonb_build_object('Body', jsonb_build_object('stkCallback', jsonb_build_object(
    'CheckoutRequestID', 'ws_CO_TEST_0002', 'ResultCode', 1032, 'ResultDesc', 'Request cancelled by user'))));
  PERFORM pg_temp.t_cycle(6);
  PERFORM pg_temp.t_check('cancelled on the phone -> FAILED with a readable reason', v = 'FAILED' AND EXISTS (
    SELECT 1 FROM trustride.integration_payment_gateway_transaction WHERE provider_reference = 'ws_CO_TEST_0002' AND failure_reason = 'CANCELLED_BY_CUSTOMER'), v);
  PERFORM pg_temp.t_check('customer told the prompt was cancelled', EXISTS (
    SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = cust AND body LIKE '%prompt was cancelled%'));
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RETRY_PAYMENT', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_cycle(4);
  SELECT * INTO t FROM trustride.integration_payment_gateway_transaction WHERE order_id = ord AND attempt_no > 1 ORDER BY initiated_at DESC LIMIT 1;
  PERFORM trustride.fn_integration_outbound_result(t.outbound_request_id, TRUE, 'ws_CO_TEST_0003', '{"ResponseCode":"0"}', NULL);
  UPDATE trustride.integration_payment_gateway_transaction SET initiated_at = now() - interval '1 hour' WHERE gateway_txn_id = t.gateway_txn_id;
  n := trustride.fn_integration_payment_timeout_sweep();
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('no callback in time -> TIMED_OUT, customer told', EXISTS (
    SELECT 1 FROM trustride.integration_payment_gateway_transaction WHERE gateway_txn_id = t.gateway_txn_id AND txn_status = 'TIMED_OUT')
    AND EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = cust AND body LIKE '%did not confirm in time%'), n::text);
  PERFORM pg_temp.t_check('an unknown CheckoutRequestID is logged, not crashed on',
    trustride.fn_integration_mpesa_callback_ingest('{"Body":{"stkCallback":{"CheckoutRequestID":"ws_CO_NOPE","ResultCode":0}}}') = 'UNKNOWN_CHECKOUT_REQUEST');

  -- ------------------------------------------------ explicit refusals
  INSERT INTO trustride.integration_event_inbox (signal_id, correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key, emitted_at)
  VALUES (gen_random_uuid(), gen_random_uuid(), 'TRS026_ENG004_BUS', 'TRS026_ENG006_INTG', 'PAYMENT_STK_TRIGGERED',
    jsonb_build_object('order_id', gen_random_uuid(), 'requester_user_id', cust, 'computed_total_fare_kes', 300000), 'T-LIMIT', now());
  PERFORM trustride.fn_integration_inbox_process((SELECT signal_id FROM trustride.integration_event_inbox WHERE idempotency_key = 'T-LIMIT'));
  PERFORM pg_temp.t_check('above the STK limit -> refused explicitly (bank transfer path)', EXISTS (
    SELECT 1 FROM trustride.integration_payment_gateway_transaction WHERE amount_kes = 300000 AND failure_reason = 'AMOUNT_ABOVE_MPESA_STK_LIMIT'));
  nophone := pg_temp.t_person('No Phone', 'CUSTOMER');
  INSERT INTO trustride.integration_event_inbox (signal_id, correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key, emitted_at)
  VALUES (gen_random_uuid(), gen_random_uuid(), 'TRS026_ENG004_BUS', 'TRS026_ENG006_INTG', 'PAYMENT_STK_TRIGGERED',
    jsonb_build_object('order_id', gen_random_uuid(), 'requester_user_id', nophone, 'computed_total_fare_kes', 500), 'T-NOPHONE', now());
  PERFORM trustride.fn_integration_inbox_process((SELECT signal_id FROM trustride.integration_event_inbox WHERE idempotency_key = 'T-NOPHONE'));
  PERFORM pg_temp.t_check('no verified phone -> refused explicitly', EXISTS (
    SELECT 1 FROM trustride.integration_payment_gateway_transaction WHERE requester_user_id = nophone AND failure_reason = 'NO_VERIFIED_PHONE'));

  -- ------------------------------------------------ bank transfer (Office)
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RECORD_BANK_PAYMENT', jsonb_build_object('order_id', ord, 'amount_kes', 1, 'bank_reference', 'EQ123'));
  PERFORM pg_temp.t_check('bank transfer must be the full amount', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RECORD_BANK_PAYMENT', jsonb_build_object('order_id', ord,
    'amount_kes', (SELECT computed_total_fare_kes FROM trustride.business_settlement WHERE order_id = ord), 'bank_reference', 'EQ-REF-0099'));
  PERFORM pg_temp.t_cycle(6);
  PERFORM pg_temp.t_check('Office records a bank transfer -> order SETTLED', EXISTS (SELECT 1 FROM trustride.business_order WHERE order_id = ord AND status = 'SETTLED'), r::text);

  -- ------------------------------------------------ boundaries
  PERFORM pg_temp.t_as(cust);
  PERFORM pg_temp.t_check('a customer cannot inject an M-Pesa callback', pg_temp.t_fails('SELECT trustride.fn_integration_mpesa_callback_ingest(''{}'')'));
  PERFORM pg_temp.t_check('a customer cannot record bank transfers', pg_temp.t_fails(format('SELECT trustride.fn_integration_payment_record_bank_transfer(%L, 1, ''x'', %L, %L)', ord, cust, ord)));
  PERFORM pg_temp.t_check('a customer sees only their own payments', pg_temp.t_visible('integration_payment_gateway_transaction', format('requester_user_id <> %L', cust)) = 0);
  PERFORM pg_temp.t_admin();
  SELECT count(*) INTO n FROM trustride.fn_platform_conformance_violations();
  PERFORM pg_temp.t_check('conformance: zero violations', n = 0, n || ' violations');
END;
$$;
