-- Suite 15 -- an M-Pesa success callback settles only the payment TrustRide asked for
-- (TRS026-ENG-REMEDIATION-001: D06, D07). A success needs the receipt, the
-- exact amount prompted and the phone prompted; anything else fails with a
-- reason and the Office is alerted, and a success arriving after TrustRide
-- closed the payment is never silent.
DO $$
DECLARE
  founder UUID; cust UUID; est UUID; boda UUID; ord UUID; r JSONB; t RECORD; req RECORD; v TEXT; n INT; ref TEXT; items JSONB;
BEGIN
  PERFORM pg_temp.t_open_all_hours();
  founder := pg_temp.t_person('CbInt Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  cust := pg_temp.t_customer('CbInt Cust');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"CBI-01","estate_name":"CbInt Hub","estate_type":"OPERATING_HUB","lat":-0.09,"lon":34.76}');
  est := (r->>'signal')::uuid;
  boda := pg_temp.t_ready_unit(founder, 'BODA_BODA', est, 'CbInt Rider');
  PERFORM pg_temp.t_as(founder);
  PERFORM trustride.fn_integration_adapter_set('PAYMENT_GATEWAY', 'PRODUCTION', 'test');
  PERFORM pg_temp.t_admin();

  FOR n IN 1..6 LOOP
    IF n > 1 THEN PERFORM pg_temp.t_release_completed(); END IF;
    ord := pg_temp.t_order_to_completed(cust);
    SELECT * INTO t FROM trustride.integration_payment_gateway_transaction WHERE order_id = ord;
    SELECT * INTO req FROM trustride.integration_outbound_request WHERE request_id = t.outbound_request_id;
    ref := 'ws_CO_CBI_' || n;
    PERFORM trustride.fn_integration_outbound_result(req.request_id, TRUE, ref, '{"ResponseCode":"0"}', NULL);
    IF n = 5 THEN  -- TrustRide gives up first; Safaricom's success arrives after
      UPDATE trustride.integration_payment_gateway_transaction SET initiated_at = now() - interval '1 hour' WHERE gateway_txn_id = t.gateway_txn_id;
      PERFORM trustride.fn_integration_payment_timeout_sweep();
    END IF;
    SELECT coalesce(jsonb_agg(i), '[]'::jsonb) INTO items FROM jsonb_array_elements(jsonb_build_array(
      CASE WHEN n <> 1 THEN jsonb_build_object('Name', 'Amount', 'Value', CASE WHEN n = 3 THEN ceil(t.amount_kes) - 1 ELSE ceil(t.amount_kes) END) END,
      CASE WHEN n <> 2 THEN jsonb_build_object('Name', 'MpesaReceiptNumber', 'Value', 'SCB' || n || 'TEST') END,
      jsonb_build_object('Name', 'PhoneNumber', 'Value', CASE WHEN n = 4 THEN 254799999999 ELSE (req.payload->>'msisdn')::bigint END))) i
    WHERE i <> 'null'::jsonb;
    v := trustride.fn_integration_mpesa_callback_ingest(jsonb_build_object('Body', jsonb_build_object('stkCallback', jsonb_build_object(
      'CheckoutRequestID', ref, 'ResultCode', 0, 'ResultDesc', 'The service request is processed successfully.',
      'CallbackMetadata', jsonb_build_object('Item', items)))));
    SELECT * INTO t FROM trustride.integration_payment_gateway_transaction WHERE gateway_txn_id = t.gateway_txn_id;
    CASE n
      WHEN 1 THEN PERFORM pg_temp.t_check('D06 a success callback without Amount does not settle', v = 'FAILED' AND t.txn_status::text = 'FAILED' AND t.failure_reason = 'CALLBACK_INCOMPLETE', v || ' ' || t.txn_status || ' ' || coalesce(t.failure_reason, ''));
      WHEN 2 THEN PERFORM pg_temp.t_check('D06 a success callback without MpesaReceiptNumber does not settle', v = 'FAILED' AND t.failure_reason = 'CALLBACK_INCOMPLETE', v || ' ' || coalesce(t.failure_reason, ''));
      WHEN 3 THEN PERFORM pg_temp.t_check('D06 a success callback for less than was prompted does not settle', v = 'FAILED' AND t.failure_reason = 'AMOUNT_MISMATCH', v || ' ' || coalesce(t.failure_reason, ''));
      WHEN 4 THEN PERFORM pg_temp.t_check('D07 a success callback from a phone that was not prompted does not settle', v = 'FAILED' AND t.failure_reason = 'PAYER_PHONE_MISMATCH', v || ' ' || coalesce(t.failure_reason, ''));
      WHEN 5 THEN PERFORM pg_temp.t_check('a success after TrustRide timed the payment out leaves it closed', v = 'ALREADY_TIMED_OUT' AND t.txn_status::text = 'TIMED_OUT', v);
      WHEN 6 THEN PERFORM pg_temp.t_check('positive control: receipt, exact amount and the prompted phone settle', v = 'SETTLED' AND t.mpesa_receipt_number = 'SCB6TEST', v);
    END CASE;
    IF n BETWEEN 1 AND 5 THEN
      PERFORM pg_temp.t_check('Office alerted (critical) for case ' || n, EXISTS (SELECT 1 FROM trustride.present_notification_inbox
        WHERE recipient_user_id = founder AND category = 'PAYMENT_EXCEPTION' AND critical AND source_signal_correlation_id = t.correlation_id));
    END IF;
  END LOOP;
  PERFORM pg_temp.t_check('D07 no full payer phone is kept in the webhook log', NOT EXISTS (SELECT 1 FROM trustride.integration_webhook_log
    WHERE provider_reference LIKE 'ws_CO_CBI_%' AND raw_payload::text ~ '2547[0-9]{8}'));
END
$$;
