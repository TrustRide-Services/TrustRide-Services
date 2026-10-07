-- ============================================================================
-- Engine 6: gateway acknowledgements, money-safe retries, Protrack polling
-- ============================================================================
-- 1. Some provider calls are accepted now and finished later (Daraja B2C
--    returns a ConversationID; the result arrives at the ResultURL). The
--    gateway records the acceptance with fn_integration_gateway_ack; the
--    request stays SENT until the final result.
-- 2. Money is never re-sent automatically. A notification the gateway never
--    answered may be retried (a duplicate SMS is harmless); an STK push or a
--    B2C payout that went unanswered is FAILED and TrustRide Office is told
--    to verify it with Safaricom -- a duplicate charge or payout is not
--    harmless.
-- 3. Protrack may push to us, or we poll it. Polling is triggered from here
--    only when its URL is configured in Vault; otherwise nothing runs and the
--    Office integrations surface shows telemetry as not configured.
-- ============================================================================

CREATE OR REPLACE FUNCTION trustride.fn_integration_gateway_ack(p_request_id UUID, p_provider_reference TEXT, p_response JSONB)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  UPDATE trustride.integration_outbound_request SET provider_reference = p_provider_reference, response = p_response
  WHERE request_id = p_request_id AND status = 'SENT';
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_integration_outbound_retry_sweep()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  r RECORD;
  n INTEGER := 0;
BEGIN
  -- Unanswered notifications: a failed attempt (retried with backoff).
  FOR r IN SELECT request_id FROM trustride.integration_outbound_request
           WHERE status = 'SENT' AND operation LIKE 'NOTIFY\_%' AND sent_at < now() - interval '10 minutes' LIMIT 200 LOOP
    PERFORM trustride.fn_integration_outbound_result(r.request_id, FALSE, NULL, NULL, 'NO_RESPONSE_FROM_GATEWAY_WITHIN_10_MINUTES');
  END LOOP;
  -- Unanswered money operations: final failure + Office verification, never
  -- an automatic re-send. (A B2C payout Safaricom accepted gets 2 hours for
  -- its result; anything never accepted gets 10 minutes.)
  FOR r IN SELECT request_id, operation, provider_reference FROM trustride.integration_outbound_request
           WHERE status = 'SENT' AND operation IN ('STK_PUSH', 'B2C_PAYOUT')
             AND sent_at < now() - CASE WHEN provider_reference IS NULL THEN interval '10 minutes' ELSE interval '2 hours' END LIMIT 200 LOOP
    UPDATE trustride.integration_outbound_request SET max_attempts = attempts WHERE request_id = r.request_id;
    PERFORM trustride.fn_integration_outbound_result(r.request_id, FALSE, NULL, NULL,
      'NO_FINAL_RESULT_FROM_MPESA -- verify on the Safaricom portal before any retry');
    PERFORM trustride.fn_present_notify_office('Verify ' || r.operation || ' with Safaricom',
      'TrustRide received no final result for ' || r.operation || coalesce(' (ref ' || r.provider_reference || ')', '') || '. Check the M-Pesa portal before retrying.',
      'PAYMENT_EXCEPTION', r.request_id, ARRAY['FOUNDER', 'ADMINISTRATOR'], TRUE);
  END LOOP;
  -- Due retries, and requests that were waiting for configuration.
  FOR r IN SELECT request_id FROM trustride.integration_outbound_request
           WHERE ((status = 'FAILED_RETRYABLE' AND next_attempt_at <= now()) OR status = 'WAITING_CONFIGURATION')
           ORDER BY created_at LIMIT 200 LOOP
    PERFORM trustride.fn_integration_outbound_dispatch(r.request_id);
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;

-- A failed STK/B2C attempt is never retried by backoff either: the
-- customer retries a payment themselves; Office retries a payout.
DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_integration_outbound_result(uuid,boolean,text,jsonb,text)'::regprocedure) INTO v_def;
  IF position('money operations are never retried' IN v_def) = 0 THEN
    v_def := replace(v_def, E'  ELSIF v_req.attempts < v_req.max_attempts THEN',
      E'  ELSIF v_req.attempts < v_req.max_attempts AND v_req.operation NOT IN (''STK_PUSH'', ''B2C_PAYOUT'') THEN  -- money operations are never retried by backoff');
    IF position('money operations are never retried' IN v_def) = 0 THEN RAISE EXCEPTION 'outbound result patch did not apply'; END IF;
    EXECUTE v_def;
  END IF;
END;
$patch$;

-- Devices the poller should ask Protrack about.
CREATE OR REPLACE FUNCTION trustride.fn_resource_telemetry_bound_devices(p_provider TEXT DEFAULT 'PROTRACK')
RETURNS TABLE (provider_device_ref TEXT) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT provider_device_ref FROM trustride.resource_telemetry_binding WHERE status = 'ACTIVE' AND provider_code = p_provider;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_integration_telemetry_poll_trigger()
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
DECLARE
  v_url TEXT := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'trustride_protrack_poll_url' LIMIT 1);
  v_secret TEXT := (SELECT gateway_secret FROM trustride.fn_integration_gateway_config());
BEGIN
  IF v_url IS NULL OR v_secret IS NULL OR trustride.fn_integration_adapter_mode('TELEMETRY_SERVICE') = 'SIMULATOR'
     OR NOT EXISTS (SELECT 1 FROM trustride.resource_telemetry_binding WHERE status = 'ACTIVE') THEN
    RETURN 'NOT_CONFIGURED_OR_NOTHING_BOUND';
  END IF;
  PERFORM net.http_post(url := v_url, body := '{"mode":"poll"}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-trustride-gateway-secret', v_secret), timeout_milliseconds := 20000);
  RETURN 'TRIGGERED';
END;
$$;
SELECT cron.schedule('trustride_telemetry_poll', '30 seconds', 'SELECT trustride.fn_integration_telemetry_poll_trigger();');

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_integration_gateway_ack(UUID, TEXT, JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_telemetry_bound_devices(TEXT) TO service_role;

SELECT trustride.fn_platform_conformance_assert();
