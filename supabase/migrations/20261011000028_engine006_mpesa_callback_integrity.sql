-- ============================================================================
-- Engine 6 (Integration) -- an M-Pesa success settles only what was prompted
-- TRS026-ENG-REMEDIATION-001, findings D06, D07
-- ============================================================================
-- Forensic audit 2026-10-08 proved that fn_integration_mpesa_callback_ingest
-- settled a payment on ResultCode 0 when:
--   D06  the callback carried no Amount, no MpesaReceiptNumber, or an amount
--        below the prompt (it accepted anything at or above floor(fare));
--   D07  the payer phone differed from the phone TrustRide prompted.
-- A success arriving after TrustRide had timed the payment out was dropped
-- without anyone being told, although the customer's money had moved; and
-- the full payer phone was kept in the webhook log.
--
-- Correction (Engine 6 only; Engine 4 settlement and Engine 5 untouched):
--   * ResultCode 0 settles only with a receipt number, an Amount equal to
--     the whole-shilling amount prompted (ceil, as sent to Daraja) and a
--     PhoneNumber equal to the phone prompted;
--   * otherwise the payment fails with a stated reason (CALLBACK_INCOMPLETE,
--     AMOUNT_MISMATCH, PAYER_PHONE_MISMATCH), the customer is told through
--     the existing PAYMENT_FAILED path, and the Office gets a critical
--     PAYMENT_EXCEPTION alert to reconcile with Safaricom;
--   * a success for a payment already closed (timed out or failed) leaves it
--     closed and raises the same critical alert, with the receipt;
--   * the webhook log keeps the payer phone masked (last three digits).
-- ============================================================================

CREATE OR REPLACE FUNCTION trustride.fn_integration_mpesa_callback_ingest(p_body jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
DECLARE
  v_cb JSONB := p_body->'Body'->'stkCallback';
  v_checkout TEXT := v_cb->>'CheckoutRequestID';
  v_code TEXT := v_cb->>'ResultCode';
  v_items JSONB := coalesce(p_body->'Body'->'stkCallback'->'CallbackMetadata'->'Item', '[]'::jsonb);
  v_logged JSONB := p_body;
  v_txn RECORD;
  v_webhook UUID;
  v_receipt TEXT;
  v_amount NUMERIC;
  v_phone TEXT;
  v_prompted TEXT;
  v_reason TEXT;
BEGIN
  SELECT i->>'Value' INTO v_receipt FROM jsonb_array_elements(v_items) i WHERE i->>'Name' = 'MpesaReceiptNumber';
  SELECT (i->>'Value')::numeric INTO v_amount FROM jsonb_array_elements(v_items) i WHERE i->>'Name' = 'Amount';
  SELECT regexp_replace(i->>'Value', '\D', '', 'g') INTO v_phone FROM jsonb_array_elements(v_items) i WHERE i->>'Name' = 'PhoneNumber';

  -- The log keeps the payer phone masked.
  IF jsonb_typeof(v_items) = 'array' AND jsonb_array_length(v_items) > 0 THEN
    v_logged := jsonb_set(p_body, '{Body,stkCallback,CallbackMetadata,Item}',
      (SELECT jsonb_agg(CASE WHEN i->>'Name' = 'PhoneNumber'
                             THEN jsonb_build_object('Name', 'PhoneNumber', 'Value', repeat('*', greatest(length(v_phone) - 3, 0)) || right(v_phone, 3))
                             ELSE i END) FROM jsonb_array_elements(v_items) i));
  END IF;
  INSERT INTO trustride.integration_webhook_log (port_code, provider_reference, signature_valid, raw_payload, processed)
  VALUES ('PAYMENT_GATEWAY', v_checkout, TRUE, v_logged, FALSE) RETURNING webhook_id INTO v_webhook;

  SELECT * INTO v_txn FROM trustride.integration_payment_gateway_transaction WHERE provider_reference = v_checkout FOR UPDATE;
  IF v_txn.gateway_txn_id IS NULL THEN
    UPDATE trustride.integration_webhook_log SET processed = TRUE, processed_at = now() WHERE webhook_id = v_webhook;
    RETURN 'UNKNOWN_CHECKOUT_REQUEST';
  END IF;
  IF v_txn.txn_status <> 'PENDING_CALLBACK' THEN  -- duplicate or late callback
    UPDATE trustride.integration_webhook_log SET processed = TRUE, processed_at = now() WHERE webhook_id = v_webhook;
    IF v_code = '0' AND v_txn.txn_status::text <> 'SETTLED' THEN
      -- The customer paid after TrustRide closed the payment: reconcile or refund.
      PERFORM trustride.fn_present_notify_office('M-Pesa confirmed a payment TrustRide had closed',
        'Payment ' || v_txn.txn_status::text || ', then Safaricom confirmed it: receipt ' || coalesce(v_receipt, 'none') || ', KES '
          || coalesce(v_amount::text, '?') || ', account ' || coalesce(v_txn.account_reference, '?') || '. Reconcile with Safaricom and refund or settle the order.',
        'PAYMENT_EXCEPTION', v_txn.correlation_id, ARRAY['FOUNDER', 'ADMINISTRATOR'], TRUE);
    END IF;
    RETURN 'ALREADY_' || v_txn.txn_status::text;
  END IF;

  UPDATE trustride.integration_payment_gateway_transaction
  SET result_code = v_code, result_desc = v_cb->>'ResultDesc', mpesa_receipt_number = v_receipt
  WHERE gateway_txn_id = v_txn.gateway_txn_id;

  IF v_code = '0' THEN
    SELECT regexp_replace(o.payload->>'msisdn', '\D', '', 'g') INTO v_prompted
    FROM trustride.integration_outbound_request o WHERE o.request_id = v_txn.outbound_request_id;
    v_prompted := coalesce(v_prompted, regexp_replace(trustride.fn_user_payment_msisdn(v_txn.requester_user_id), '\D', '', 'g'));
    v_reason := CASE
      WHEN v_receipt IS NULL OR v_amount IS NULL OR v_phone IS NULL THEN 'CALLBACK_INCOMPLETE'
      WHEN v_amount <> ceil(v_txn.amount_kes) THEN 'AMOUNT_MISMATCH'
      WHEN v_prompted IS NULL OR v_phone <> v_prompted THEN 'PAYER_PHONE_MISMATCH'
    END;
    IF v_reason IS NULL THEN
      PERFORM trustride.fn_integration_payment_callback_process(v_txn.gateway_txn_id, v_receipt, 'SETTLED', v_webhook);
      RETURN 'SETTLED';
    END IF;
    PERFORM trustride.fn_present_notify_office('M-Pesa success refused: ' || lower(replace(v_reason, '_', ' ')),
      'Account ' || coalesce(v_txn.account_reference, '?') || ': Safaricom reported success (receipt ' || coalesce(v_receipt, 'none')
        || ', KES ' || coalesce(v_amount::text, 'none') || ') for a prompt of KES ' || ceil(v_txn.amount_kes)
        || '. Not settled. Reconcile with Safaricom before the customer pays again.',
      'PAYMENT_EXCEPTION', v_txn.correlation_id, ARRAY['FOUNDER', 'ADMINISTRATOR'], TRUE);
  END IF;
  UPDATE trustride.integration_payment_gateway_transaction
  SET failure_reason = coalesce(v_reason, CASE v_code WHEN '1032' THEN 'CANCELLED_BY_CUSTOMER' WHEN '1037' THEN 'PHONE_UNREACHABLE'
    WHEN '2001' THEN 'WRONG_PIN' WHEN '1' THEN 'INSUFFICIENT_FUNDS' ELSE 'MPESA_RESULT_' || coalesce(v_code, '?') END)
  WHERE gateway_txn_id = v_txn.gateway_txn_id;
  PERFORM trustride.fn_integration_payment_callback_process(v_txn.gateway_txn_id, v_checkout, 'FAILED', v_webhook);
  RETURN 'FAILED';
END;
$function$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
