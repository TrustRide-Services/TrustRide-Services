-- ============================================================================
-- Engine 6 (Integration) + Engine 11 (Presentation): the integration gateway
-- boundary and the notification fabric
-- Implementation Completion -- Stage 3 (Contact + Notification), Sec.7,
-- Sec.10 (clean external boundaries), groundwork for G10 (real M-Pesa) and
-- Sec.9 (Protrack).
-- ============================================================================
-- The adapter boundary, precisely:
--   * Engine 6 is still the ONLY engine that talks to the outside world, and
--     it does so through one place: integration_outbound_request. Every
--     outbound call (SMS, WhatsApp, email, push, M-Pesa STK, ...) is a row
--     with an explicit state -- QUEUED, SENT, SUCCEEDED, FAILED_RETRYABLE,
--     FAILED, WAITING_CONFIGURATION. Nothing is fire-and-forget.
--   * Which adapter serves a port (SIMULATOR / SANDBOX / PRODUCTION) is data
--     in integration_adapter_registry, switched by TrustRide Office. In
--     SIMULATOR mode Engine 6 completes the request itself (honestly logged
--     as SIMULATOR). In SANDBOX/PRODUCTION mode it hands the request to the
--     integration gateway (a Supabase Edge Function) -- the only component
--     that ever holds provider credentials -- which reports back through
--     fn_integration_outbound_result.
--   * The database never stores a provider credential. It stores only the
--     gateway's URL and a shared secret, in Supabase Vault. Until those are
--     set, non-simulator requests wait in WAITING_CONFIGURATION -- visibly,
--     and they resume by themselves once configuration arrives.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ---------------------------------------------------------------------------
-- 1. Ports and adapters
-- ---------------------------------------------------------------------------
INSERT INTO trustride.integration_port_registry (port_code, responsibility, primary_vendor, secondary_vendor)
SELECT v.port, v.resp, v.vendor, v.secondary
FROM (VALUES
  ('PUSH_SERVICE'::trustride.integration_port_code_enum, 'Mobile/web push notifications', 'Firebase Cloud Messaging', NULL),
  ('EMAIL_SERVICE'::trustride.integration_port_code_enum, 'Transactional email', 'Not yet selected (Founder decision)', NULL),
  ('TELEMETRY_SERVICE'::trustride.integration_port_code_enum, 'Vehicle/device GPS telemetry ingestion', 'Protrack', NULL)
) AS v(port, resp, vendor, secondary)
WHERE NOT EXISTS (SELECT 1 FROM trustride.integration_port_registry p WHERE p.port_code = v.port);

INSERT INTO trustride.integration_adapter_registry (port_code, adapter_type, active, notes)
SELECT v.port, 'SIMULATOR', TRUE, 'Default until TrustRide Office switches the adapter'
FROM (VALUES ('PUSH_SERVICE'::trustride.integration_port_code_enum), ('EMAIL_SERVICE'), ('TELEMETRY_SERVICE')) AS v(port)
WHERE NOT EXISTS (SELECT 1 FROM trustride.integration_adapter_registry a WHERE a.port_code = v.port);

CREATE OR REPLACE FUNCTION trustride.fn_integration_adapter_mode(p_port_code trustride.integration_port_code_enum)
RETURNS trustride.integration_adapter_type_enum LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT coalesce(
    (SELECT adapter_type FROM trustride.integration_adapter_registry WHERE port_code = p_port_code AND active ORDER BY activated_at DESC LIMIT 1),
    'SIMULATOR'::trustride.integration_adapter_type_enum);
$$;

-- TrustRide Office switches a port between SIMULATOR, SANDBOX and PRODUCTION.
CREATE OR REPLACE FUNCTION trustride.fn_integration_adapter_set(p_port_code trustride.integration_port_code_enum, p_adapter_type trustride.integration_adapter_type_enum, p_notes TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  IF NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN
    RAISE EXCEPTION 'Only TrustRide Office (Founder or Administrator) may switch integration adapters';
  END IF;
  UPDATE trustride.integration_adapter_registry SET active = FALSE WHERE port_code = p_port_code AND active;
  INSERT INTO trustride.integration_adapter_registry (port_code, adapter_type, active, activated_by, notes)
  VALUES (p_port_code, p_adapter_type, TRUE, auth.uid(), p_notes);
  PERFORM trustride.fn_audit_log_append('integration_adapter_registry', gen_random_uuid(), 'ADAPTER_SWITCHED', auth.uid(), 'USER', NULL, 'TRUSTRIDE_OFFICE',
    NULL, jsonb_build_object('port', p_port_code, 'adapter', p_adapter_type, 'notes', p_notes));
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. The outbound request ledger
-- ---------------------------------------------------------------------------
CREATE TABLE trustride.integration_outbound_request (
  request_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  port_code         trustride.integration_port_code_enum NOT NULL,
  operation         TEXT NOT NULL CHECK (operation IN ('NOTIFY_SMS', 'NOTIFY_WHATSAPP', 'NOTIFY_EMAIL', 'NOTIFY_PUSH', 'STK_PUSH')),
  adapter_type      trustride.integration_adapter_type_enum NOT NULL,
  payload           JSONB NOT NULL,
  status            TEXT NOT NULL DEFAULT 'QUEUED'
                    CHECK (status IN ('QUEUED', 'SENT', 'SUCCEEDED', 'FAILED_RETRYABLE', 'FAILED', 'WAITING_CONFIGURATION')),
  attempts          SMALLINT NOT NULL DEFAULT 0,
  max_attempts      SMALLINT NOT NULL DEFAULT 5,
  next_attempt_at   TIMESTAMPTZ,
  last_error        TEXT,
  provider_reference TEXT,
  response          JSONB,
  ref_type          TEXT NOT NULL,
  ref_id            UUID NOT NULL,
  correlation_id    UUID,
  net_request_id    BIGINT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at           TIMESTAMPTZ,
  completed_at      TIMESTAMPTZ
);
CREATE INDEX idx_integration_outbound_request_due ON trustride.integration_outbound_request (status, next_attempt_at);
CREATE INDEX idx_integration_outbound_request_ref ON trustride.integration_outbound_request (ref_type, ref_id);
COMMENT ON TABLE trustride.integration_outbound_request IS
  '[Trace: TRS026-ENG006-INTG-001; Implementation Completion Sec.10] Every call TrustRide makes to an external provider, with an explicit state. SIMULATOR requests complete inside Engine 6; SANDBOX/PRODUCTION requests are carried by the integration gateway, which reports back via fn_integration_outbound_result.';
ALTER TABLE trustride.integration_outbound_request ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_outbound_request_service_write ON trustride.integration_outbound_request
  FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);
CREATE POLICY integration_outbound_request_office_read ON trustride.integration_outbound_request
  FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));
GRANT SELECT ON trustride.integration_outbound_request TO trustride_authenticated;

-- Gateway configuration lives in Supabase Vault: never a provider key, only
-- where the gateway is and the secret it shares with this database.
CREATE OR REPLACE FUNCTION trustride.fn_integration_gateway_config()
RETURNS TABLE (gateway_url TEXT, gateway_secret TEXT) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT
    (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'trustride_integration_gateway_url' LIMIT 1),
    (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'trustride_integration_gateway_secret' LIMIT 1);
$$;

CREATE OR REPLACE FUNCTION trustride.fn_integration_gateway_configured()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT gateway_url IS NOT NULL AND gateway_secret IS NOT NULL FROM trustride.fn_integration_gateway_config();
$$;

-- ---------------------------------------------------------------------------
-- 3. Completing a request (the one door back in from the gateway)
-- ---------------------------------------------------------------------------
-- Downstream effects per operation. Payments are wired in by the payment
-- completion migration; notifications are wired here.
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
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_integration_outbound_result(p_request_id UUID, p_success BOOLEAN, p_provider_reference TEXT, p_response JSONB, p_error TEXT)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_req trustride.integration_outbound_request;
  v_port trustride.integration_port_code_enum;
BEGIN
  SELECT * INTO v_req FROM trustride.integration_outbound_request WHERE request_id = p_request_id FOR UPDATE;
  IF v_req.request_id IS NULL THEN
    RAISE EXCEPTION 'fn_integration_outbound_result: unknown request %', p_request_id;
  END IF;
  -- Idempotent: a result for an already-final request changes nothing.
  IF v_req.status IN ('SUCCEEDED', 'FAILED') THEN
    RETURN v_req.status;
  END IF;
  v_port := v_req.port_code;

  IF p_success THEN
    UPDATE trustride.integration_outbound_request
    SET status = 'SUCCEEDED', provider_reference = p_provider_reference, response = p_response, completed_at = now(), last_error = NULL
    WHERE request_id = p_request_id RETURNING * INTO v_req;
    PERFORM trustride.fn_integration_circuit_check(v_port);
    PERFORM trustride.fn_integration_circuit_record_result(v_port, TRUE, 0);
    PERFORM trustride.fn_integration_outbound_apply_outcome(v_req, TRUE, FALSE);
  ELSIF v_req.attempts < v_req.max_attempts THEN
    UPDATE trustride.integration_outbound_request
    SET status = 'FAILED_RETRYABLE', response = p_response, last_error = p_error,
        next_attempt_at = now() + make_interval(secs => 30 * power(2, greatest(v_req.attempts - 1, 0)))
    WHERE request_id = p_request_id RETURNING * INTO v_req;
    PERFORM trustride.fn_integration_circuit_check(v_port);
    PERFORM trustride.fn_integration_circuit_record_result(v_port, FALSE, 0);
  ELSE
    UPDATE trustride.integration_outbound_request
    SET status = 'FAILED', response = p_response, last_error = p_error, completed_at = now()
    WHERE request_id = p_request_id RETURNING * INTO v_req;
    PERFORM trustride.fn_integration_circuit_check(v_port);
    PERFORM trustride.fn_integration_circuit_record_result(v_port, FALSE, 0);
    PERFORM trustride.fn_integration_outbound_apply_outcome(v_req, FALSE, TRUE);
  END IF;
  RETURN v_req.status;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Sending a request
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_integration_outbound_simulate(p_req trustride.integration_outbound_request)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
BEGIN
  PERFORM trustride.fn_integration_outbound_result(p_req.request_id, TRUE,
    'SIM-' || p_req.operation || '-' || encode(gen_random_bytes(4), 'hex'),
    jsonb_build_object('simulated', true, 'adapter', 'SIMULATOR'), NULL);
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_integration_outbound_dispatch(p_request_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
DECLARE
  v_req trustride.integration_outbound_request;
  v_cfg RECORD;
  v_net BIGINT;
BEGIN
  SELECT * INTO v_req FROM trustride.integration_outbound_request WHERE request_id = p_request_id FOR UPDATE;
  IF v_req.status NOT IN ('QUEUED', 'FAILED_RETRYABLE', 'WAITING_CONFIGURATION', 'SENT') THEN
    RETURN v_req.status;
  END IF;

  -- The adapter in force now (Office may have switched it since queueing).
  v_req.adapter_type := trustride.fn_integration_adapter_mode(v_req.port_code);
  UPDATE trustride.integration_outbound_request SET adapter_type = v_req.adapter_type, attempts = attempts + 1
  WHERE request_id = p_request_id RETURNING * INTO v_req;

  IF v_req.adapter_type = 'SIMULATOR' THEN
    PERFORM trustride.fn_integration_outbound_simulate(v_req);
    RETURN 'SUCCEEDED';
  END IF;

  IF trustride.fn_integration_circuit_check(v_req.port_code) = 'OPEN' THEN
    UPDATE trustride.integration_outbound_request
    SET status = 'FAILED_RETRYABLE', attempts = attempts - 1, last_error = 'CIRCUIT_OPEN', next_attempt_at = now() + interval '30 seconds'
    WHERE request_id = p_request_id;
    RETURN 'FAILED_RETRYABLE';
  END IF;

  SELECT * INTO v_cfg FROM trustride.fn_integration_gateway_config();
  IF v_cfg.gateway_url IS NULL OR v_cfg.gateway_secret IS NULL THEN
    UPDATE trustride.integration_outbound_request
    SET status = 'WAITING_CONFIGURATION', attempts = attempts - 1,
        last_error = 'Integration gateway is not configured (Vault: trustride_integration_gateway_url / _secret)'
    WHERE request_id = p_request_id;
    RETURN 'WAITING_CONFIGURATION';
  END IF;

  SELECT net.http_post(
    url := v_cfg.gateway_url,
    body := jsonb_build_object('request_id', v_req.request_id, 'port_code', v_req.port_code, 'operation', v_req.operation,
                               'adapter_type', v_req.adapter_type, 'payload', v_req.payload, 'attempt', v_req.attempts),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-trustride-gateway-secret', v_cfg.gateway_secret),
    timeout_milliseconds := 10000) INTO v_net;

  UPDATE trustride.integration_outbound_request SET status = 'SENT', sent_at = now(), net_request_id = v_net, last_error = NULL
  WHERE request_id = p_request_id;
  RETURN 'SENT';
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_integration_outbound_enqueue(p_port_code trustride.integration_port_code_enum, p_operation TEXT, p_payload JSONB, p_ref_type TEXT, p_ref_id UUID, p_correlation_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO trustride.integration_outbound_request (port_code, operation, adapter_type, payload, ref_type, ref_id, correlation_id)
  VALUES (p_port_code, p_operation, trustride.fn_integration_adapter_mode(p_port_code), p_payload, p_ref_type, p_ref_id, p_correlation_id)
  RETURNING request_id INTO v_id;
  PERFORM trustride.fn_integration_outbound_dispatch(v_id);
  RETURN v_id;
END;
$$;

-- Background: retry what is due, resume what was waiting for configuration,
-- and treat a request the gateway never answered (10 min) as a failed attempt.
CREATE OR REPLACE FUNCTION trustride.fn_integration_outbound_retry_sweep()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  r RECORD;
  n INTEGER := 0;
BEGIN
  FOR r IN SELECT request_id FROM trustride.integration_outbound_request
           WHERE status = 'SENT' AND sent_at < now() - interval '10 minutes' LIMIT 200 LOOP
    PERFORM trustride.fn_integration_outbound_result(r.request_id, FALSE, NULL, NULL, 'NO_RESPONSE_FROM_GATEWAY_WITHIN_10_MINUTES');
  END LOOP;
  FOR r IN SELECT request_id FROM trustride.integration_outbound_request
           WHERE (status = 'FAILED_RETRYABLE' AND next_attempt_at <= now()) OR status = 'WAITING_CONFIGURATION'
           ORDER BY created_at LIMIT 200 LOOP
    PERFORM trustride.fn_integration_outbound_dispatch(r.request_id);
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Notification delivery
-- ---------------------------------------------------------------------------
-- One template per code per channel per language (was: one per code).
ALTER TABLE trustride.notification_template DROP CONSTRAINT notification_template_template_code_key;
ALTER TABLE trustride.notification_template ADD CONSTRAINT notification_template_code_channel_lang_version_key
  UNIQUE (template_code, channel, language_code, version);

INSERT INTO trustride.notification_template (template_code, channel, language_code, subject, body_template, constitutional_ref)
SELECT v.code, v.channel, 'en', v.subject, v.body, 'Implementation Completion Sec.7'
FROM (VALUES
  ('CONTACT_VERIFICATION_CODE', 'SMS', NULL, 'TrustRide: your verification code is {{code}}. It expires in {{expires_minutes}} minutes. Never share it.'),
  ('CONTACT_VERIFICATION_CODE', 'WHATSAPP', NULL, 'TrustRide: your verification code is {{code}}. It expires in {{expires_minutes}} minutes. Never share it.'),
  ('CONTACT_VERIFICATION_CODE', 'EMAIL', 'Your TrustRide verification code', 'Your TrustRide verification code is {{code}}. It expires in {{expires_minutes}} minutes. If you did not ask for it, ignore this email.'),
  ('TRUSTRIDE_NOTICE', 'SMS', NULL, 'TrustRide: {{title}}. {{body}}'),
  ('TRUSTRIDE_NOTICE', 'WHATSAPP', NULL, '*TrustRide* -- {{title}}\n{{body}}'),
  ('TRUSTRIDE_NOTICE', 'EMAIL', 'TrustRide: {{title}}', '{{body}}'),
  ('TRUSTRIDE_NOTICE', 'PUSH', '{{title}}', '{{body}}')
) AS v(code, channel, subject, body)
WHERE NOT EXISTS (SELECT 1 FROM trustride.notification_template t WHERE t.template_code = v.code AND t.channel = v.channel AND t.language_code = 'en');

CREATE OR REPLACE FUNCTION trustride.fn_integration_template_render(p_template_code TEXT, p_channel TEXT, p_params JSONB)
RETURNS TABLE (subject TEXT, body TEXT) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_t RECORD;
  v_subject TEXT;
  v_body TEXT;
  k TEXT;
BEGIN
  SELECT * INTO v_t FROM trustride.notification_template
  WHERE template_code = p_template_code AND channel = p_channel AND active ORDER BY version DESC LIMIT 1;
  IF v_t.template_id IS NULL THEN
    RAISE EXCEPTION 'No active template % for channel %', p_template_code, p_channel;
  END IF;
  v_subject := v_t.subject;
  v_body := replace(v_t.body_template, '\n', E'\n');
  FOR k IN SELECT jsonb_object_keys(coalesce(p_params, '{}'::jsonb)) LOOP
    v_subject := replace(v_subject, '{{' || k || '}}', coalesce(p_params->>k, ''));
    v_body := replace(v_body, '{{' || k || '}}', coalesce(p_params->>k, ''));
  END LOOP;
  RETURN QUERY SELECT v_subject, v_body;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_integration_channel_port(p_channel TEXT)
RETURNS trustride.integration_port_code_enum LANGUAGE sql IMMUTABLE AS $$
  SELECT (CASE p_channel WHEN 'SMS' THEN 'SMS_SERVICE' WHEN 'WHATSAPP' THEN 'WHATSAPP_SERVICE'
    WHEN 'EMAIL' THEN 'EMAIL_SERVICE' WHEN 'PUSH' THEN 'PUSH_SERVICE' END)::trustride.integration_port_code_enum;
$$;

-- Deliver a rendered message to an explicit destination (used for contact
-- verification, where the destination is not yet a verified contact).
CREATE OR REPLACE FUNCTION trustride.fn_integration_notification_deliver(p_recipient_user_id UUID, p_channel TEXT, p_destination TEXT, p_template_code TEXT, p_params JSONB, p_correlation_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_dispatch_id UUID;
  v_msg RECORD;
BEGIN
  SELECT * INTO v_msg FROM trustride.fn_integration_template_render(p_template_code, p_channel, p_params);
  INSERT INTO trustride.integration_notification_dispatch_log (recipient_ref, channel, template_code, payload, status, adapter_type, correlation_id)
  VALUES (p_recipient_user_id, p_channel::trustride.integration_notification_channel_enum, p_template_code,
    jsonb_build_object('destination_masked', CASE WHEN length(p_destination) > 4 THEN repeat('*', length(p_destination) - 4) || right(p_destination, 4) ELSE '****' END,
                       'subject', v_msg.subject, 'body', v_msg.body),
    'QUEUED', trustride.fn_integration_adapter_mode(trustride.fn_integration_channel_port(p_channel)), p_correlation_id)
  RETURNING dispatch_id INTO v_dispatch_id;

  PERFORM trustride.fn_integration_outbound_enqueue(trustride.fn_integration_channel_port(p_channel), 'NOTIFY_' || p_channel,
    jsonb_build_object('destination', p_destination, 'subject', v_msg.subject, 'body', v_msg.body, 'template_code', p_template_code),
    'NOTIFICATION_DISPATCH', v_dispatch_id, p_correlation_id);
  RETURN v_dispatch_id;
END;
$$;

-- Deliver to a person on the first channel that reaches them, in the order
-- given. Foundation resolves the destination and the person's preference;
-- an unreachable or opted-out person is recorded as such, never guessed.
CREATE OR REPLACE FUNCTION trustride.fn_integration_notification_send(p_recipient_user_id UUID, p_channels TEXT[], p_template_code TEXT, p_params JSONB, p_correlation_id UUID, p_critical BOOLEAN DEFAULT FALSE)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_channel TEXT;
  v_c RECORD;
  v_outcome trustride.integration_notification_status_enum := 'UNREACHABLE';
  v_dispatch_id UUID;
BEGIN
  FOREACH v_channel IN ARRAY p_channels LOOP
    SELECT * INTO v_c FROM trustride.fn_user_contact_resolve(p_recipient_user_id, v_channel);
    IF v_c.destination IS NULL THEN
      CONTINUE;
    END IF;
    IF NOT v_c.channel_allowed OR (v_c.quiet_now AND NOT p_critical) THEN
      v_outcome := 'SUPPRESSED';
      CONTINUE;
    END IF;
    RETURN trustride.fn_integration_notification_deliver(p_recipient_user_id, v_channel, v_c.destination, p_template_code, p_params, p_correlation_id);
  END LOOP;

  INSERT INTO trustride.integration_notification_dispatch_log (recipient_ref, channel, template_code, payload, status, adapter_type, correlation_id)
  VALUES (p_recipient_user_id, coalesce(p_channels[1], 'SMS')::trustride.integration_notification_channel_enum, p_template_code,
    jsonb_build_object('channels_tried', p_channels, 'params', p_params - 'code'), v_outcome, 'SIMULATOR', p_correlation_id)
  RETURNING dispatch_id INTO v_dispatch_id;
  RETURN v_dispatch_id;
END;
$$;

-- The recipient may read their own simulated messages (staging only: it is
-- how a tester sees the SMS a real phone would have received). Real
-- provider deliveries are never readable here.
CREATE POLICY integration_notification_dispatch_log_simulated_self_read ON trustride.integration_notification_dispatch_log
  FOR SELECT TO trustride_authenticated USING (recipient_ref = auth.uid() AND adapter_type = 'SIMULATOR');
GRANT SELECT ON trustride.integration_notification_dispatch_log TO trustride_authenticated;

-- ---------------------------------------------------------------------------
-- 6. Engine 6 inbox: the two new delivery signals
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_integration_contact_verification_requested_accept(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_corr UUID;
  v_dispatch UUID;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_corr FROM trustride.integration_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'no RECEIVED signal %', p_signal_id; END IF;
  v_dispatch := trustride.fn_integration_notification_deliver((v_payload->>'recipient_user_id')::uuid, v_payload->>'channel',
    v_payload->>'destination', v_payload->>'template_code', v_payload->'params', v_corr);
  UPDATE trustride.integration_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(),
    payload_out = jsonb_build_object('dispatch_id', v_dispatch) WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_integration_notification_dispatch_requested_accept(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_corr UUID;
  v_dispatch UUID;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_corr FROM trustride.integration_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'no RECEIVED signal %', p_signal_id; END IF;
  v_dispatch := trustride.fn_integration_notification_send((v_payload->>'recipient_user_id')::uuid,
    ARRAY(SELECT jsonb_array_elements_text(coalesce(v_payload->'channels', '["SMS"]'::jsonb))),
    coalesce(v_payload->>'template_code', 'TRUSTRIDE_NOTICE'),
    jsonb_build_object('title', v_payload->>'title', 'body', v_payload->>'body'), v_corr,
    coalesce((v_payload->>'critical')::boolean, false));
  UPDATE trustride.integration_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(),
    payload_out = jsonb_build_object('dispatch_id', v_dispatch) WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_integration_inbox_process(p_signal_id uuid)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_signal_type TEXT;
  v_result TEXT;
BEGIN
  SELECT signal_type INTO v_signal_type FROM trustride.integration_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_signal_type IS NULL THEN
    RAISE EXCEPTION 'fn_integration_inbox_process: no RECEIVED signal %', p_signal_id;
  END IF;
  CASE v_signal_type
    WHEN 'VERIFICATION_REQUESTED' THEN v_result := trustride.fn_integration_verification_requested_accept(p_signal_id);
    WHEN 'PAYMENT_STK_TRIGGERED' THEN v_result := trustride.fn_integration_payment_stk_triggered_accept(p_signal_id);
    WHEN 'CONTACT_VERIFICATION_REQUESTED' THEN v_result := trustride.fn_integration_contact_verification_requested_accept(p_signal_id);
    WHEN 'NOTIFICATION_DISPATCH_REQUESTED' THEN v_result := trustride.fn_integration_notification_dispatch_requested_accept(p_signal_id);
    ELSE
      UPDATE trustride.integration_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'UNREGISTERED_SIGNAL_TYPE:' || v_signal_type WHERE signal_id = p_signal_id;
      v_result := 'REJECTED';
  END CASE;
  RETURN v_result;
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. Engine 6: entity verification (registrant class LEGAL_ENTITY)
-- ---------------------------------------------------------------------------
CREATE TABLE trustride.integration_entity_verification_log (
  entity_verification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  verification_id        UUID NOT NULL,
  subject_user_id        UUID NOT NULL,
  submitted_registration_number TEXT NOT NULL,
  submitted_legal_name   TEXT NOT NULL,
  submitted_kra_pin      TEXT,
  returned_legal_name    TEXT,
  returned_status        TEXT NOT NULL,
  returned_kra_pin       TEXT,
  adapter_type           trustride.integration_adapter_type_enum NOT NULL,
  raw_response           JSONB,
  responded_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE trustride.integration_entity_verification_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_entity_verification_log_service_write ON trustride.integration_entity_verification_log
  FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);
CREATE POLICY integration_entity_verification_log_office_read ON trustride.integration_entity_verification_log
  FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));
GRANT SELECT ON trustride.integration_entity_verification_log TO trustride_authenticated;

-- Business Registration Service + KRA PIN checker simulator. Test patterns:
-- a registration number beginning '00' is not found; otherwise the entity is
-- found under the submitted name with the submitted PIN.
CREATE OR REPLACE FUNCTION trustride.fn_integration_entity_verify_simulate(p_registration_number TEXT, p_legal_name TEXT, p_kra_pin TEXT)
RETURNS TABLE (returned_legal_name TEXT, returned_status TEXT, returned_kra_pin TEXT, raw_response JSONB)
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN left(p_registration_number, 2) = '00' THEN NULL ELSE p_legal_name END,
         CASE WHEN left(p_registration_number, 2) = '00' THEN 'NOT_FOUND' ELSE 'VALID' END,
         CASE WHEN left(p_registration_number, 2) = '00' THEN NULL ELSE p_kra_pin END,
         jsonb_build_object('simulated', true, 'source', 'BRS_KRA_SIMULATOR');
$$;

DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_integration_verification_requested_accept(uuid)'::regprocedure) INTO v_def;
  IF position('ENTITY_REGISTRATION' IN v_def) = 0 THEN
    v_def := replace(v_def,
      E'  v_verification_id := (v_payload->>''verification_id'')::uuid;',
      E'  v_verification_id := (v_payload->>''verification_id'')::uuid;\n'
      || E'  -- Legal entities: Business Registration Service + KRA PIN check.\n'
      || E'  IF v_payload->>''verification_type'' = ''ENTITY_REGISTRATION'' THEN\n'
      || E'    SELECT * INTO v_sim FROM trustride.fn_integration_entity_verify_simulate(v_payload->>''registration_number'', v_payload->>''full_legal_name'', v_payload->>''kra_pin'');\n'
      || E'    INSERT INTO trustride.integration_entity_verification_log (verification_id, subject_user_id, submitted_registration_number, submitted_legal_name, submitted_kra_pin, returned_legal_name, returned_status, returned_kra_pin, adapter_type, raw_response)\n'
      || E'    VALUES (v_verification_id, (v_payload->>''subject_user_id'')::uuid, v_payload->>''registration_number'', v_payload->>''full_legal_name'', v_payload->>''kra_pin'', v_sim.returned_legal_name, v_sim.returned_status, v_sim.returned_kra_pin, trustride.fn_integration_adapter_mode(''IDENTITY_AUTHORITY''), v_sim.raw_response);\n'
      || E'    INSERT INTO trustride.integration_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)\n'
      || E'    VALUES (v_correlation_id, ''TRS026_ENG001_FDN'', ''VERIFICATION_COMPLETED'', jsonb_build_object(''verification_id'', v_verification_id, ''returned_legal_name'', v_sim.returned_legal_name, ''returned_status'', v_sim.returned_status, ''returned_kra_pin'', v_sim.returned_kra_pin, ''raw_response'', v_sim.raw_response), ''VERIFICATION_COMPLETED:'' || v_verification_id::text);\n'
      || E'    UPDATE trustride.integration_event_inbox SET signal_status = ''ACCEPTED'', accepted_at = now() WHERE signal_id = p_signal_id;\n'
      || E'    RETURN ''ACCEPTED'';\n'
      || E'  END IF;');
    IF position('ENTITY_REGISTRATION' IN v_def) = 0 THEN
      RAISE EXCEPTION 'fn_integration_verification_requested_accept patch did not apply';
    END IF;
    EXECUTE v_def;
  END IF;
END;
$patch$;

-- ---------------------------------------------------------------------------
-- 8. Engine 11: in-app notifications also reach people outside the app
-- ---------------------------------------------------------------------------
ALTER TABLE trustride.present_notification_inbox
  ADD COLUMN category TEXT NOT NULL DEFAULT 'GENERAL',
  ADD COLUMN external_channels TEXT[] NOT NULL DEFAULT ARRAY['SMS']::TEXT[],
  ADD COLUMN critical BOOLEAN NOT NULL DEFAULT FALSE;

CREATE OR REPLACE FUNCTION trustride.fn_present_notification_fanout()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  IF cardinality(NEW.external_channels) > 0 THEN
    INSERT INTO trustride.present_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (coalesce(NEW.source_signal_correlation_id, NEW.notification_id), 'TRS026_ENG006_INTG', 'NOTIFICATION_DISPATCH_REQUESTED',
      jsonb_build_object('notification_id', NEW.notification_id, 'recipient_user_id', NEW.recipient_user_id,
        'title', NEW.title, 'body', NEW.body, 'channels', to_jsonb(NEW.external_channels), 'critical', NEW.critical,
        'template_code', 'TRUSTRIDE_NOTICE', 'category', NEW.category),
      'NOTIFICATION_DISPATCH_REQUESTED:' || NEW.notification_id::text);
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_present_notification_fanout AFTER INSERT ON trustride.present_notification_inbox
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_present_notification_fanout();

-- Foundation's lawful interface for "who holds these Office roles" --
-- Presentation never reads role_assignment itself.
CREATE OR REPLACE FUNCTION trustride.fn_office_recipients(p_role_codes TEXT[])
RETURNS SETOF UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT DISTINCT ra.user_id FROM trustride.role_assignment ra JOIN trustride.role_definition rd ON rd.role_id = ra.role_id
  WHERE rd.role_code = ANY (p_role_codes) AND ra.status = 'ACTIVE' AND (ra.valid_to IS NULL OR ra.valid_to > now());
$$;

-- Tell TrustRide Office about something that needs a person (an order that
-- cannot be served, a failed payment, a stuck signal).
CREATE OR REPLACE FUNCTION trustride.fn_present_notify_office(p_title TEXT, p_body TEXT, p_category TEXT, p_correlation_id UUID,
  p_roles TEXT[] DEFAULT ARRAY['FOUNDER', 'ADMINISTRATOR'], p_critical BOOLEAN DEFAULT FALSE)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  n INTEGER;
BEGIN
  INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, source_signal_correlation_id, category, external_channels, critical)
  SELECT r, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', p_title, p_body, p_correlation_id, p_category,
    CASE WHEN p_critical THEN ARRAY['SMS']::TEXT[] ELSE ARRAY[]::TEXT[] END, p_critical
  FROM trustride.fn_office_recipients(p_roles) r;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

-- ---------------------------------------------------------------------------
-- 9. Routes
-- ---------------------------------------------------------------------------
INSERT INTO trustride.routing_rule (event_type, source_engine, target_engine, route_priority)
SELECT v.e, v.s, v.t, 0
FROM (VALUES
  ('CONTACT_VERIFICATION_REQUESTED', 'TRS026_ENG001_FDN', 'TRS026_ENG006_INTG'),
  ('NOTIFICATION_DISPATCH_REQUESTED', 'TRS026_ENG011_PRESENT', 'TRS026_ENG006_INTG')
) AS v(e, s, t)
WHERE NOT EXISTS (SELECT 1 FROM trustride.routing_rule r WHERE r.event_type = v.e AND r.source_engine = v.s AND r.target_engine = v.t);
SELECT trustride.fn_orch_destination_cache_sync();

-- ---------------------------------------------------------------------------
-- 10. Grants
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_integration_adapter_set(trustride.integration_port_code_enum, trustride.integration_adapter_type_enum, TEXT) TO trustride_authenticated;
-- The integration gateway (service role) reports results back.
GRANT EXECUTE ON FUNCTION trustride.fn_integration_outbound_result(UUID, BOOLEAN, TEXT, JSONB, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION trustride.fn_office_recipients(TEXT[]) TO trs026_eng011_present_service;

SELECT trustride.fn_platform_conformance_assert();
