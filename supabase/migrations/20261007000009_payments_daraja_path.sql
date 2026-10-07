-- ============================================================================
-- Payments: the complete M-Pesa Daraja software path (G10, Sec.18)
-- Engines 4, 5, 6, 11
-- ============================================================================
--   Identity (Foundation verified primary phone, D3)
--   -> payment request (Cost on service completion; Business on Marketplace
--      purchase or a customer retry)
--   -> Engine 6 payment port: SIMULATOR completes in-database for staging;
--      SANDBOX/PRODUCTION sends STK_PUSH through the integration gateway
--      (Daraja 3.0 credentials live only in the gateway's environment)
--   -> CheckoutRequestID -> PENDING_CALLBACK
--   -> Safaricom callback -> gateway -> fn_integration_mpesa_callback_ingest
--   -> SETTLED / FAILED (with M-Pesa receipt or the customer-readable reason)
--   -> Business settlement -> receipt -> customer notified.
-- Explicit outcomes for every failure: no verified phone, above the STK
-- limit, gateway down (retried), customer cancelled / wrong PIN / timeout
-- (customer may RETRY_PAYMENT). Nothing waits silently.
-- ============================================================================

INSERT INTO trustride.platform_configuration (config_key, config_value, environment, effective_from, changed_by)
SELECT v.k, v.v, 'ALL', now(), '00000000-0000-0000-0000-000000000000' FROM (VALUES
  ('PAYMENT_STK_MAX_KES', '250000'),          -- Daraja STK per-transaction ceiling; above it, bank transfer
  ('PAYMENT_CALLBACK_TIMEOUT_MIN', '3'),      -- no Safaricom callback by then -> TIMED_OUT, customer may retry
  ('PAYMENT_MAX_RETRIES', '5'),
  ('MPESA_PAYBILL_ACCOUNT_PREFIX', 'TRS')
) AS v(k, v)
WHERE NOT EXISTS (SELECT 1 FROM trustride.platform_configuration c WHERE c.config_key = v.k);

-- ---------------------------------------------------------------------------
-- 1. The transaction record carries everything a reconciliation needs
-- ---------------------------------------------------------------------------
ALTER TABLE trustride.integration_payment_gateway_transaction
  ADD COLUMN order_id UUID,
  ADD COLUMN msisdn_masked TEXT,
  ADD COLUMN account_reference TEXT,
  ADD COLUMN mpesa_receipt_number TEXT,
  ADD COLUMN result_code TEXT,
  ADD COLUMN result_desc TEXT,
  ADD COLUMN failure_reason TEXT,
  ADD COLUMN attempt_no SMALLINT NOT NULL DEFAULT 1,
  ADD COLUMN outbound_request_id UUID;
CREATE UNIQUE INDEX integration_payment_txn_provider_ref_uq ON trustride.integration_payment_gateway_transaction (provider_reference)
  WHERE provider_reference IS NOT NULL;
CREATE UNIQUE INDEX integration_payment_txn_receipt_uq ON trustride.integration_payment_gateway_transaction (mpesa_receipt_number)
  WHERE mpesa_receipt_number IS NOT NULL;
CREATE INDEX idx_integration_payment_txn_order ON trustride.integration_payment_gateway_transaction (order_id);

ALTER TABLE trustride.integration_outbound_request DROP CONSTRAINT integration_outbound_request_operation_check;
ALTER TABLE trustride.integration_outbound_request ADD CONSTRAINT integration_outbound_request_operation_check
  CHECK (operation IN ('NOTIFY_SMS', 'NOTIFY_WHATSAPP', 'NOTIFY_EMAIL', 'NOTIFY_PUSH', 'STK_PUSH', 'B2C_PAYOUT'));

-- Cost's payment trigger now names the order it is for.
DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_cost_quote_finalize(uuid,uuid)'::regprocedure) INTO v_def;
  IF position('''order_id''' IN v_def) = 0 THEN
    v_def := replace(v_def, E'''payment_rail'', ''MPESA_C2B_STK''),',
      E'''payment_rail'', ''MPESA_C2B_STK'', ''order_id'', (SELECT order_id FROM trustride.fare_calculation WHERE calculation_id = v_quote.calculation_id)),');
    IF position('''order_id''' IN v_def) = 0 THEN RAISE EXCEPTION 'quote finalize patch did not apply'; END IF;
    EXECUTE v_def;
  END IF;
END;
$patch$;

-- ---------------------------------------------------------------------------
-- 2. Engine 6: requesting a payment
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_integration_payment_fail(p_txn UUID, p_reason TEXT, p_signal TEXT DEFAULT 'PAYMENT_STK_FAILED')
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v RECORD;
BEGIN
  UPDATE trustride.integration_payment_gateway_transaction SET txn_status = 'FAILED', failure_reason = p_reason, settled_at = now()
  WHERE gateway_txn_id = p_txn RETURNING * INTO v;
  INSERT INTO trustride.integration_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v.correlation_id, 'TRS026_ENG004_BUS', p_signal,
    jsonb_build_object('quote_id', v.quote_id, 'order_id', v.order_id, 'gateway_txn_id', p_txn, 'reason', p_reason),
    p_signal || ':' || p_txn::text);
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_integration_payment_stk_triggered_accept(p_signal_id uuid)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_corr UUID;
  v_txn UUID;
  v_mode trustride.integration_adapter_type_enum := trustride.fn_integration_adapter_mode('PAYMENT_GATEWAY');
  v_msisdn TEXT;
  v_amount NUMERIC;
  v_sim RECORD;
  v_req UUID;
  v_account TEXT;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_corr FROM trustride.integration_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'fn_integration_payment_stk_triggered_accept: no RECEIVED signal %', p_signal_id; END IF;
  v_amount := (v_payload->>'computed_total_fare_kes')::numeric;
  v_msisdn := trustride.fn_user_payment_msisdn((v_payload->>'requester_user_id')::uuid);
  v_account := coalesce(nullif(trustride.fn_business_config('MPESA_PAYBILL_ACCOUNT_PREFIX'), ''), 'TRS') || coalesce(v_payload->>'order_code', substr(coalesce(v_payload->>'order_id', v_corr::text), 1, 8));

  INSERT INTO trustride.integration_payment_gateway_transaction
    (quote_id, order_id, requester_user_id, amount_kes, currency, payment_rail, txn_status, adapter_type, correlation_id,
     msisdn_masked, account_reference, attempt_no)
  VALUES ((v_payload->>'quote_id')::uuid, (v_payload->>'order_id')::uuid, (v_payload->>'requester_user_id')::uuid, v_amount,
    coalesce(v_payload->>'currency', 'KES'), coalesce(v_payload->>'payment_rail', 'MPESA_C2B_STK'), 'INITIATED', v_mode, v_corr,
    CASE WHEN v_msisdn IS NULL THEN NULL ELSE repeat('*', length(v_msisdn) - 3) || right(v_msisdn, 3) END, v_account,
    coalesce((v_payload->>'attempt')::smallint, 1))
  RETURNING gateway_txn_id INTO v_txn;

  -- Explicit refusals, each reaching the customer as a reason, never a hang.
  IF v_msisdn IS NULL THEN
    PERFORM trustride.fn_integration_payment_fail(v_txn, 'NO_VERIFIED_PHONE');
  ELSIF v_amount > coalesce(nullif(trustride.fn_business_config('PAYMENT_STK_MAX_KES'), '')::numeric, 250000) THEN
    PERFORM trustride.fn_integration_payment_fail(v_txn, 'AMOUNT_ABOVE_MPESA_STK_LIMIT');
  ELSIF trustride.fn_integration_circuit_check('PAYMENT_GATEWAY') = 'OPEN' THEN
    PERFORM trustride.fn_integration_payment_fail(v_txn, 'PAYMENT_GATEWAY_TEMPORARILY_UNAVAILABLE');
  ELSIF v_mode = 'SIMULATOR' THEN
    SELECT * INTO v_sim FROM trustride.fn_integration_payment_stk_simulate(v_amount);
    PERFORM trustride.fn_integration_circuit_record_result('PAYMENT_GATEWAY', v_sim.accepted, v_sim.latency_ms);
    IF v_sim.accepted THEN
      -- (the simulator's reference is second-resolution; suffix it so two
      -- prompts in the same second never collide)
      UPDATE trustride.integration_payment_gateway_transaction
      SET txn_status = 'PENDING_CALLBACK', provider_reference = v_sim.provider_reference || '-' || encode(extensions.gen_random_bytes(3), 'hex')
      WHERE gateway_txn_id = v_txn;
    ELSE
      PERFORM trustride.fn_integration_payment_fail(v_txn, 'GATEWAY_DECLINED');
    END IF;
  ELSE
    -- Daraja: ceil to whole shillings (STK accepts integers only).
    v_req := trustride.fn_integration_outbound_enqueue('PAYMENT_GATEWAY', 'STK_PUSH',
      jsonb_build_object('gateway_txn_id', v_txn, 'msisdn', v_msisdn, 'amount', ceil(v_amount)::int,
        'account_reference', v_account, 'description', 'TrustRide ' || v_account), 'PAYMENT_TXN', v_txn, v_corr);
    UPDATE trustride.integration_payment_gateway_transaction SET outbound_request_id = v_req WHERE gateway_txn_id = v_txn;
  END IF;

  UPDATE trustride.integration_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(),
    payload_out = jsonb_build_object('gateway_txn_id', v_txn, 'adapter', v_mode) WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

-- The gateway's answer to STK_PUSH: Safaricom accepted the request (the
-- customer's phone is prompting) or refused it.
CREATE OR REPLACE FUNCTION trustride.fn_integration_outbound_apply_outcome(p_request trustride.integration_outbound_request, p_final_success BOOLEAN, p_final_failure BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  IF p_request.operation LIKE 'NOTIFY\_%' THEN
    IF p_final_success THEN
      UPDATE trustride.integration_notification_dispatch_log
      SET status = 'DISPATCHED', provider_reference = p_request.provider_reference, dispatched_at = now()
      WHERE dispatch_id = p_request.ref_id AND status = 'QUEUED';
    ELSIF p_final_failure THEN
      UPDATE trustride.integration_notification_dispatch_log SET status = 'FAILED'
      WHERE dispatch_id = p_request.ref_id AND status IN ('QUEUED', 'DISPATCHED');
    END IF;
  ELSIF p_request.operation = 'STK_PUSH' THEN
    IF p_final_success THEN
      UPDATE trustride.integration_payment_gateway_transaction
      SET txn_status = 'PENDING_CALLBACK', provider_reference = p_request.provider_reference,
          result_code = p_request.response->>'ResponseCode', result_desc = p_request.response->>'CustomerMessage'
      WHERE gateway_txn_id = p_request.ref_id AND txn_status = 'INITIATED';
    ELSIF p_final_failure THEN
      PERFORM trustride.fn_integration_payment_fail(p_request.ref_id, 'STK_PUSH_REFUSED: ' || coalesce(p_request.last_error, 'unknown'));
    END IF;
  ELSIF p_request.operation = 'B2C_PAYOUT' THEN
    PERFORM trustride.fn_integration_payout_outcome(p_request, p_final_success, p_final_failure);
  END IF;
END;
$$;

-- Payouts are wired by the Marketplace migration; until then a payout
-- outcome has nowhere to land, so this placeholder records nothing.
CREATE OR REPLACE FUNCTION trustride.fn_integration_payout_outcome(p_request trustride.integration_outbound_request, p_final_success BOOLEAN, p_final_failure BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  NULL;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Engine 6: the Safaricom callback (via the gateway)
-- ---------------------------------------------------------------------------
-- Accepts Daraja's STK callback body exactly as Safaricom sends it:
--   {"Body":{"stkCallback":{"MerchantRequestID":..,"CheckoutRequestID":..,
--     "ResultCode":0,"ResultDesc":..,"CallbackMetadata":{"Item":[{"Name":
--     "Amount","Value":..},{"Name":"MpesaReceiptNumber","Value":..}, ...]}}}}
CREATE OR REPLACE FUNCTION trustride.fn_integration_mpesa_callback_ingest(p_body JSONB)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_cb JSONB := p_body->'Body'->'stkCallback';
  v_checkout TEXT := v_cb->>'CheckoutRequestID';
  v_code TEXT := v_cb->>'ResultCode';
  v_txn RECORD;
  v_webhook UUID;
  v_receipt TEXT;
  v_amount NUMERIC;
BEGIN
  INSERT INTO trustride.integration_webhook_log (port_code, provider_reference, signature_valid, raw_payload, processed)
  VALUES ('PAYMENT_GATEWAY', v_checkout, TRUE, p_body, FALSE) RETURNING webhook_id INTO v_webhook;

  SELECT * INTO v_txn FROM trustride.integration_payment_gateway_transaction WHERE provider_reference = v_checkout FOR UPDATE;
  IF v_txn.gateway_txn_id IS NULL THEN
    UPDATE trustride.integration_webhook_log SET processed = TRUE, processed_at = now() WHERE webhook_id = v_webhook;
    RETURN 'UNKNOWN_CHECKOUT_REQUEST';
  END IF;
  IF v_txn.txn_status <> 'PENDING_CALLBACK' THEN  -- duplicate or late callback
    UPDATE trustride.integration_webhook_log SET processed = TRUE, processed_at = now() WHERE webhook_id = v_webhook;
    RETURN 'ALREADY_' || v_txn.txn_status::text;
  END IF;

  SELECT (i->>'Value') INTO v_receipt FROM jsonb_array_elements(coalesce(v_cb->'CallbackMetadata'->'Item', '[]'::jsonb)) i WHERE i->>'Name' = 'MpesaReceiptNumber';
  SELECT (i->>'Value')::numeric INTO v_amount FROM jsonb_array_elements(coalesce(v_cb->'CallbackMetadata'->'Item', '[]'::jsonb)) i WHERE i->>'Name' = 'Amount';
  UPDATE trustride.integration_payment_gateway_transaction
  SET result_code = v_code, result_desc = v_cb->>'ResultDesc', mpesa_receipt_number = v_receipt
  WHERE gateway_txn_id = v_txn.gateway_txn_id;

  IF v_code = '0' AND (v_amount IS NULL OR v_amount >= floor(v_txn.amount_kes)) THEN
    PERFORM trustride.fn_integration_payment_callback_process(v_txn.gateway_txn_id, coalesce(v_receipt, v_checkout), 'SETTLED', v_webhook);
    RETURN 'SETTLED';
  END IF;
  UPDATE trustride.integration_payment_gateway_transaction
  SET failure_reason = CASE v_code WHEN '1032' THEN 'CANCELLED_BY_CUSTOMER' WHEN '1037' THEN 'PHONE_UNREACHABLE'
    WHEN '2001' THEN 'WRONG_PIN' WHEN '1' THEN 'INSUFFICIENT_FUNDS' WHEN '0' THEN 'AMOUNT_MISMATCH' ELSE 'MPESA_RESULT_' || coalesce(v_code, '?') END
  WHERE gateway_txn_id = v_txn.gateway_txn_id;
  PERFORM trustride.fn_integration_payment_callback_process(v_txn.gateway_txn_id, v_checkout, 'FAILED', v_webhook);
  RETURN 'FAILED';
END;
$$;

-- The settlement/failure signal now names the order and the reason.
CREATE OR REPLACE FUNCTION trustride.fn_integration_payment_callback_process(p_gateway_txn_id uuid, p_provider_reference text, p_outcome trustride.integration_payment_txn_status_enum, p_webhook_id uuid DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_txn RECORD;
BEGIN
  UPDATE trustride.integration_payment_gateway_transaction
  SET txn_status = p_outcome, settled_at = now(),
      mpesa_receipt_number = CASE WHEN p_outcome = 'SETTLED' THEN coalesce(mpesa_receipt_number, p_provider_reference) ELSE mpesa_receipt_number END
  WHERE gateway_txn_id = p_gateway_txn_id AND txn_status = 'PENDING_CALLBACK'
  RETURNING * INTO v_txn;
  IF v_txn.gateway_txn_id IS NULL THEN
    RAISE EXCEPTION 'fn_integration_payment_callback_process: no PENDING_CALLBACK transaction %', p_gateway_txn_id;
  END IF;
  IF p_webhook_id IS NOT NULL THEN
    UPDATE trustride.integration_webhook_log SET processed = TRUE, processed_at = now() WHERE webhook_id = p_webhook_id;
  END IF;
  INSERT INTO trustride.integration_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v_txn.correlation_id, 'TRS026_ENG004_BUS', CASE WHEN p_outcome = 'SETTLED' THEN 'PAYMENT_SETTLED' ELSE 'PAYMENT_FAILED' END,
    jsonb_build_object('quote_id', v_txn.quote_id, 'order_id', v_txn.order_id, 'gateway_txn_id', p_gateway_txn_id,
      'provider_reference', p_provider_reference, 'mpesa_receipt_number', v_txn.mpesa_receipt_number, 'amount_kes', v_txn.amount_kes,
      'reason', coalesce(v_txn.failure_reason, CASE WHEN p_outcome <> 'SETTLED' THEN p_outcome::text END)),
    (CASE WHEN p_outcome = 'SETTLED' THEN 'PAYMENT_SETTLED' ELSE 'PAYMENT_FAILED' END) || ':' || p_gateway_txn_id::text);
END;
$$;

-- Staging only: the customer confirms their own simulated M-Pesa prompt.
CREATE OR REPLACE FUNCTION trustride.fn_integration_payment_simulator_confirm(p_gateway_txn_id UUID, p_success BOOLEAN DEFAULT TRUE)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_txn RECORD;
BEGIN
  SELECT * INTO v_txn FROM trustride.integration_payment_gateway_transaction WHERE gateway_txn_id = p_gateway_txn_id;
  IF v_txn.gateway_txn_id IS NULL OR v_txn.requester_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'No such payment on your identity';
  END IF;
  IF v_txn.adapter_type <> 'SIMULATOR' THEN
    RAISE EXCEPTION 'This is a real M-Pesa request -- confirm it on your phone';
  END IF;
  PERFORM trustride.fn_integration_payment_callback_simulate(p_gateway_txn_id, CASE WHEN p_success THEN 'SETTLED' ELSE 'FAILED' END::trustride.integration_payment_txn_status_enum);
  RETURN CASE WHEN p_success THEN 'SETTLED' ELSE 'FAILED' END;
END;
$$;

-- No callback in time: the payment is TIMED_OUT and the customer may retry.
CREATE OR REPLACE FUNCTION trustride.fn_integration_payment_timeout_sweep()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  r RECORD;
  n INTEGER := 0;
BEGIN
  FOR r IN SELECT gateway_txn_id FROM trustride.integration_payment_gateway_transaction
           WHERE txn_status = 'PENDING_CALLBACK' AND adapter_type <> 'SIMULATOR'
             AND initiated_at < now() - make_interval(mins => coalesce(nullif(trustride.fn_business_config('PAYMENT_CALLBACK_TIMEOUT_MIN'), '')::int, 3))
  LOOP
    UPDATE trustride.integration_payment_gateway_transaction SET failure_reason = 'NO_CALLBACK_FROM_MPESA' WHERE gateway_txn_id = r.gateway_txn_id;
    PERFORM trustride.fn_integration_payment_callback_process(r.gateway_txn_id, NULL, 'TIMED_OUT');
    n := n + 1;
  END LOOP;
  -- STK pushes the gateway never managed to send are failed explicitly too.
  FOR r IN SELECT t.gateway_txn_id FROM trustride.integration_payment_gateway_transaction t
           JOIN trustride.integration_outbound_request o ON o.request_id = t.outbound_request_id
           WHERE t.txn_status = 'INITIATED' AND o.status = 'FAILED' LOOP
    PERFORM trustride.fn_integration_payment_fail(r.gateway_txn_id, 'STK_PUSH_NOT_DELIVERED');
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Business: settlement, failure, retry, bank transfer
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_business_payment_request(p_order_id UUID, p_attempt SMALLINT DEFAULT 1)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_o RECORD;
  v_s RECORD;
BEGIN
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = p_order_id;
  SELECT * INTO v_s FROM trustride.business_settlement WHERE order_id = p_order_id;
  UPDATE trustride.business_settlement SET payment_status = 'INITIATED', initiated_at = now() WHERE order_id = p_order_id;
  INSERT INTO trustride.business_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v_o.correlation_id, 'TRS026_ENG006_INTG', 'PAYMENT_STK_TRIGGERED',
    jsonb_build_object('order_id', p_order_id, 'order_code', v_o.order_code, 'quote_id', v_o.quote_id,
      'computed_total_fare_kes', v_s.computed_total_fare_kes, 'currency', v_s.currency, 'requester_user_id', v_o.requester_user_id,
      'payment_rail', 'MPESA_C2B_STK', 'attempt', p_attempt),
    'PAYMENT_STK_TRIGGERED:BUS:' || p_order_id::text || ':' || p_attempt::text);
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_payment_failure_record(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_order_id UUID;
  v_failures INT;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'no RECEIVED signal %', p_signal_id; END IF;
  v_order_id := coalesce((v_payload->>'order_id')::uuid, (SELECT order_id FROM trustride.business_order WHERE quote_id = (v_payload->>'quote_id')::uuid));
  IF v_order_id IS NULL THEN
    UPDATE trustride.business_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'NO_ORDER_FOR_PAYMENT', accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END IF;
  UPDATE trustride.business_settlement SET payment_status = 'FAILED' WHERE order_id = v_order_id AND payment_status <> 'RECEIPT_GENERATED';
  PERFORM trustride.fn_audit_log_append('business_settlement', v_order_id, 'PAYMENT_FAILED', NULL, 'SYSTEM', NULL, NULL, NULL,
    jsonb_build_object('gateway_txn_id', v_payload->>'gateway_txn_id', 'reason', v_payload->>'reason'));
  SELECT count(*) INTO v_failures FROM trustride.business_event_inbox
  WHERE signal_type IN ('PAYMENT_FAILED', 'PAYMENT_STK_FAILED') AND payload_in->>'order_id' = v_order_id::text;
  PERFORM trustride.fn_business_progress_emit(v_order_id, 'PAYMENT_FAILED', jsonb_build_object('reason', v_payload->>'reason',
    'notify_office', v_failures >= 3 OR v_payload->>'reason' IN ('AMOUNT_ABOVE_MPESA_STK_LIMIT', 'NO_VERIFIED_PHONE')));
  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_payment_failed_accept(p_signal_id uuid)
RETURNS TEXT LANGUAGE sql SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT trustride.fn_business_payment_failure_record(p_signal_id);
$$;
CREATE OR REPLACE FUNCTION trustride.fn_business_payment_stk_failed_accept(p_signal_id uuid)
RETURNS TEXT LANGUAGE sql SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT trustride.fn_business_payment_failure_record(p_signal_id);
$$;

-- PAYMENT_SETTLED: prefer the order the payment names.
DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_business_payment_settled_accept(uuid)'::regprocedure) INTO v_def;
  IF position('fn_business_settled_followup' IN v_def) = 0 THEN
    v_def := replace(v_def, E'  UPDATE trustride.business_order SET status = ''SETTLED'' WHERE order_id = v_order_id;',
      E'  UPDATE trustride.business_order SET status = ''SETTLED'', order_stage = ''REVIEW_RATE_SUPPORT'' WHERE order_id = v_order_id AND order_root_type = ''SERVICE_ORDER'';\n'
      || E'  PERFORM trustride.fn_business_settled_followup(v_order_id, v_payload);');
    IF position('fn_business_settled_followup' IN v_def) = 0 THEN RAISE EXCEPTION 'payment settled patch did not apply'; END IF;
    EXECUTE v_def;
  END IF;
END;
$patch$;

-- What else a settlement sets in motion (Marketplace sale completion is
-- wired by the Marketplace migration).
CREATE OR REPLACE FUNCTION trustride.fn_business_settled_followup(p_order_id UUID, p_payload JSONB)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  UPDATE trustride.business_settlement SET payment_rail = CASE WHEN p_payload->>'payment_rail' = 'BANK_TRANSFER' THEN 'BANK_TRANSFER' ELSE payment_rail END::trustride.business_payment_rail_enum
  WHERE order_id = p_order_id;
END;
$$;

-- Customer: try paying again after a failed / timed-out / cancelled prompt.
CREATE OR REPLACE FUNCTION trustride.fn_business_payment_retry(p_order_id UUID, p_requester UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_o RECORD;
  v_attempts INT;
BEGIN
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = p_order_id AND requester_user_id = p_requester;
  IF v_o.order_id IS NULL THEN RAISE EXCEPTION 'No such order on your identity'; END IF;
  IF NOT EXISTS (SELECT 1 FROM trustride.business_settlement WHERE order_id = p_order_id AND payment_status = 'FAILED') THEN
    RAISE EXCEPTION 'There is no failed payment to retry on this order';
  END IF;
  SELECT count(*) INTO v_attempts FROM trustride.business_event_outbox WHERE signal_type = 'PAYMENT_STK_TRIGGERED' AND payload_in->>'order_id' = p_order_id::text;
  IF v_attempts + 1 > trustride.fn_business_config_num('PAYMENT_MAX_RETRIES', 5) THEN
    RAISE EXCEPTION 'Too many payment attempts -- contact TrustRide support to pay this order';
  END IF;
  PERFORM trustride.fn_business_payment_request(p_order_id, (v_attempts + 2)::smallint);
END;
$$;

-- Office records a bank transfer (Marketplace purchases above the STK
-- limit). Engine 6 holds the payment record; Business settles from it.
CREATE OR REPLACE FUNCTION trustride.fn_integration_payment_record_bank_transfer(p_order_id UUID, p_amount_kes NUMERIC, p_bank_reference TEXT, p_requester UUID, p_correlation UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_txn UUID;
BEGIN
  IF NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN
    RAISE EXCEPTION 'Only TrustRide Office records bank transfers';
  END IF;
  IF coalesce(trim(p_bank_reference), '') = '' THEN RAISE EXCEPTION 'Enter the bank reference'; END IF;
  INSERT INTO trustride.integration_payment_gateway_transaction (order_id, requester_user_id, amount_kes, currency, payment_rail, txn_status,
    provider_reference, adapter_type, correlation_id, account_reference)
  VALUES (p_order_id, p_requester, p_amount_kes, 'KES', 'BANK_TRANSFER', 'PENDING_CALLBACK', 'BANK:' || trim(p_bank_reference), 'PRODUCTION', p_correlation,
    'Recorded by ' || auth.uid())
  RETURNING gateway_txn_id INTO v_txn;
  PERFORM trustride.fn_integration_payment_callback_process(v_txn, 'BANK:' || trim(p_bank_reference), 'SETTLED');
  PERFORM trustride.fn_audit_log_append('integration_payment_gateway_transaction', v_txn, 'BANK_TRANSFER_RECORDED', auth.uid(), 'USER', NULL, 'TRUSTRIDE_OFFICE',
    NULL, jsonb_build_object('order_id', p_order_id, 'amount_kes', p_amount_kes, 'reference', p_bank_reference));
  RETURN v_txn;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Routes, schedules, Engine 11 verbs and messages
-- ---------------------------------------------------------------------------
INSERT INTO trustride.routing_rule (event_type, source_engine, target_engine, route_priority)
SELECT 'PAYMENT_STK_TRIGGERED', 'TRS026_ENG004_BUS', 'TRS026_ENG006_INTG', 0
WHERE NOT EXISTS (SELECT 1 FROM trustride.routing_rule WHERE event_type = 'PAYMENT_STK_TRIGGERED' AND source_engine = 'TRS026_ENG004_BUS');
SELECT trustride.fn_orch_destination_cache_sync();

SELECT cron.schedule('trustride_payment_timeout_sweep', '* * * * *', 'SELECT trustride.fn_integration_payment_timeout_sweep();');
SELECT cron.schedule('trustride_integration_outbound_retry_sweep', '* * * * *', 'SELECT trustride.fn_integration_outbound_retry_sweep();');

INSERT INTO trustride.present_shell_capability_registry (top_shell, sub_shell, command_type, permitted, requires_delegated_authority)
SELECT v.top::trustride.present_top_shell_enum, v.sub::trustride.present_sub_shell_enum, v.cmd, TRUE, FALSE
FROM (VALUES
  ('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RETRY_PAYMENT'),
  ('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'CONFIRM_SIMULATED_PAYMENT'),
  ('TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'RETRY_PAYMENT'),
  ('TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'CONFIRM_SIMULATED_PAYMENT'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RECORD_BANK_PAYMENT')
) AS v(top, sub, cmd)
WHERE NOT EXISTS (SELECT 1 FROM trustride.present_shell_capability_registry r WHERE r.sub_shell = v.sub::trustride.present_sub_shell_enum AND r.command_type = v.cmd);

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_retry_payment(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_business_payment_retry((p_payload->>'order_id')::uuid, (SELECT user_id FROM trustride.present_shell_session WHERE session_id = p_session));
  RETURN (p_payload->>'order_id')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_confirm_simulated_payment(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_txn UUID;
  v_user UUID := (SELECT user_id FROM trustride.present_shell_session WHERE session_id = p_session);
BEGIN
  SELECT gateway_txn_id INTO v_txn FROM trustride.integration_payment_gateway_transaction
  WHERE order_id = (p_payload->>'order_id')::uuid AND requester_user_id = v_user AND txn_status = 'PENDING_CALLBACK' ORDER BY initiated_at DESC LIMIT 1;
  IF v_txn IS NULL THEN RAISE EXCEPTION 'No M-Pesa prompt is waiting on this order'; END IF;
  PERFORM trustride.fn_integration_payment_simulator_confirm(v_txn, coalesce((p_payload->>'success')::boolean, true));
  RETURN v_txn;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_record_bank_payment(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_o RECORD;
BEGIN
  SELECT o.*, s.computed_total_fare_kes INTO v_o FROM trustride.business_order o JOIN trustride.business_settlement s ON s.order_id = o.order_id
  WHERE o.order_id = (p_payload->>'order_id')::uuid AND s.payment_status IN ('INITIATED', 'FAILED');
  IF v_o.order_id IS NULL THEN RAISE EXCEPTION 'No unpaid settlement on this order'; END IF;
  IF (p_payload->>'amount_kes')::numeric IS DISTINCT FROM v_o.computed_total_fare_kes THEN
    RAISE EXCEPTION 'The transfer must be the full amount due (KES %)', v_o.computed_total_fare_kes;
  END IF;
  RETURN trustride.fn_integration_payment_record_bank_transfer(v_o.order_id, v_o.computed_total_fare_kes, p_payload->>'bank_reference', v_o.requester_user_id, v_o.correlation_id);
END;
$$;

DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_present_order_progress_accept(uuid)'::regprocedure) INTO v_def;
  IF position('PAYMENT_FAILED' IN v_def) = 0 THEN
    v_def := replace(v_def, E'    ELSE\n      v_c_title := NULL;',
      E'    WHEN ''PAYMENT_FAILED'' THEN\n'
      || E'      v_c_title := ''Payment not completed'';\n'
      || E'      v_c_body := format(''%s: %s. Open My Orders to try again.'', v_code, CASE v_p->>''reason''\n'
      || E'        WHEN ''CANCELLED_BY_CUSTOMER'' THEN ''the M-Pesa prompt was cancelled'' WHEN ''WRONG_PIN'' THEN ''the M-Pesa PIN was wrong''\n'
      || E'        WHEN ''INSUFFICIENT_FUNDS'' THEN ''your M-Pesa balance was not enough'' WHEN ''PHONE_UNREACHABLE'' THEN ''your phone could not be reached''\n'
      || E'        WHEN ''NO_CALLBACK_FROM_MPESA'' THEN ''M-Pesa did not confirm in time'' WHEN ''NO_VERIFIED_PHONE'' THEN ''you have no verified phone number''\n'
      || E'        WHEN ''AMOUNT_ABOVE_MPESA_STK_LIMIT'' THEN ''the amount is above the M-Pesa limit -- TrustRide Office will send bank transfer details''\n'
      || E'        ELSE ''the payment did not go through'' END);\n'
      || E'      v_c_critical := TRUE;\n'
      || E'    WHEN ''PAYMENT_REQUESTED'' THEN\n'
      || E'      v_c_title := ''Check your phone: M-Pesa'';\n'
      || E'      v_c_body := format(''%s: approve the M-Pesa request for KES %s.'', v_code, v_p->>''amount_kes'');\n'
      || E'      v_c_critical := TRUE;\n'
      || E'    ELSE\n      v_c_title := NULL;');
    IF position('PAYMENT_FAILED' IN v_def) = 0 THEN RAISE EXCEPTION 'order progress patch did not apply'; END IF;
    EXECUTE v_def;
  END IF;
END;
$patch$;

-- ---------------------------------------------------------------------------
-- 6. Grants
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_integration_mpesa_callback_ingest(JSONB) TO service_role;

SELECT trustride.fn_platform_conformance_assert();
