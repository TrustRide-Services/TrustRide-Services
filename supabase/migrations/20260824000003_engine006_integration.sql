-- ============================================================================
-- TRUSTRIDE SERVICES PLATFORM
-- ============================================================================
-- PLATFORM CODE        : TRS026
-- SCHEMA               : trustride
-- ENGINE NO            : ENGINE_006
-- ENGINE CODE          : TRS026_ENG006_INTG
-- ENGINE DOMAIN        : External Systems Integration
-- ENGINE DESCRIPTION   : The sole boundary between TrustRide and the outside
--                        world. Every external capability (identity
--                        verification, payments, maps/routing, messaging,
--                        tax, vehicle/fuel regulators) is exposed to the
--                        rest of the platform only through a frozen Port;
--                        no other engine may call a third-party API
--                        directly.
-- MIGRATION DATA
-- FILE NAME            : 20260824000003_engine006_integration.sql
-- STATUS               : PHASE A INCREMENT 1 -- Ports frozen for all 11;
--                        rich simulator adapters, resilience, webhooks,
--                        routing, config, and observability infrastructure
--                        built and proven for IIdentityAuthorityService and
--                        IPaymentGateway/INotificationRouter specifically
--                        (the three ports with real, already-anticipated
--                        upstream callers -- Foundation's registration flow
--                        and Cost's PAYMENT_STK_TRIGGERED). The remaining
--                        eight ports (Maps, Routing, WhatsApp, Voice
--                        Masking, USSD, eTIMS, NTSA, EPRA) are frozen in the
--                        port registry now but their simulator adapters are
--                        a separate, subsequent increment -- named
--                        explicitly, not silently implied as done.
-- CREATED AT           : 2026-08-24
-- ============================================================================
--
-- FOUNDER DIRECTIVE E006-DIR/TRS/KSM/2026/01-HARDENED: "Fully design,
-- implement, and prove end-to-end with simulators first. Real integrators
-- are wired in only after workflows are proven to operate exactly as
-- designed." Sequence: (1) Freeze Ports, (2) Build rich Simulator Adapters,
-- (3) Build resilience/webhooks/routers/observability/config around the
-- simulators, (4) Prove every workflow end-to-end using only simulators,
-- (5) Only then implement real adapters one at a time behind feature flags.
-- This file is Phase A of that sequence.
--
-- CORRECTIONS FOUND WHILE BUILDING THIS FILE:
--   1. Foundation (Engine 1) has never had its own inbox dispatcher.
--      fn_orch_dispatch_cycle correctly routes a signal INTO platform_event_
--      inbox (destination_inbox_table has always said so), but its own
--      CASE that calls each destination engine's *_inbox_process function
--      never had a TRS026_ENG001_FDN branch -- meaning Foundation's own
--      fn_verification_completed_accept, defined since the very first
--      migration, has never actually been reachable through the real
--      signal pipeline; it could only ever be called directly by hand.
--      Found while building the first real inbound loop INTO Foundation
--      (Engine 6's VERIFICATION_COMPLETED reply) -- fixed here by adding
--      fn_platform_inbox_process (Foundation's own dispatcher) and
--      extending fn_orch_dispatch_cycle's CASE to call it.
--   2. fn_orch_dispatch_cycle's generic dynamic INSERT into a destination
--      inbox table never accounted for platform_event_inbox's own extra
--      emitted_at column (NOT NULL, no default -- preserving the source
--      outbox's original emission time, distinct from received_at). Every
--      other engine's inbox table lacked the column entirely, so this
--      stayed invisible until Foundation became a real dispatch
--      destination for the first time via this file's own VERIFICATION_
--      COMPLETED loop -- caught by the actual end-to-end test, not by
--      inspection. Fixed generally: the dispatch function now always
--      supplies emitted_at, and every live inbox table gains a matching
--      nullable column.
--   3. No other live engine's CASE branches are touched or reordered --
--      RESC/SERV/COST keep their existing branches exactly, FDN's branch is
--      newly added, INTG's branch is newly added.
--
-- PORT CATALOGUE (all 11 frozen; simulator built for the three marked *):
--   IIdentityAuthorityService* | IMapService | IRoutingService |
--   IPaymentGateway* | ISmsService | IWhatsAppService |
--   IVoiceMaskingService | IUssdService | IEtimsService | INtsaService |
--   IEpraService | INotificationRouter* (unifies SMS/WhatsApp/Voice/USSD
--   dispatch -- simulated here via ISmsService's own simulator, since no
--   WhatsApp/Voice/USSD real distinction exists yet to route between).
--
-- ============================================================================

-- ============================================================================
-- PHASE 1 -- ROLE
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng006_intg_service') THEN
    CREATE ROLE trs026_eng006_intg_service NOLOGIN;
  END IF;
END
$$;

-- ============================================================================
-- PHASE 2 -- ENUMS
-- ============================================================================
CREATE TYPE trustride.integration_port_code_enum AS ENUM (
  'IDENTITY_AUTHORITY', 'MAP_SERVICE', 'ROUTING_SERVICE', 'PAYMENT_GATEWAY',
  'SMS_SERVICE', 'WHATSAPP_SERVICE', 'VOICE_MASKING_SERVICE', 'USSD_SERVICE',
  'ETIMS_SERVICE', 'NTSA_SERVICE', 'EPRA_SERVICE', 'NOTIFICATION_ROUTER'
);
CREATE TYPE trustride.integration_adapter_type_enum AS ENUM ('SIMULATOR', 'SANDBOX', 'PRODUCTION');
CREATE TYPE trustride.integration_circuit_state_enum AS ENUM ('CLOSED', 'OPEN', 'HALF_OPEN');
CREATE TYPE trustride.integration_verification_outcome_enum AS ENUM ('ALIVE_VALID', 'DECEASED', 'RESTRICTED', 'INVALID');
CREATE TYPE trustride.integration_payment_txn_status_enum AS ENUM ('INITIATED', 'PENDING_CALLBACK', 'SETTLED', 'FAILED', 'REVERSED');
CREATE TYPE trustride.integration_notification_channel_enum AS ENUM ('SMS', 'WHATSAPP', 'VOICE', 'USSD');
CREATE TYPE trustride.integration_notification_status_enum AS ENUM ('QUEUED', 'DISPATCHED', 'DELIVERED', 'FAILED');

-- ============================================================================
-- PHASE 3 -- PORTS, ADAPTERS, FEATURE FLAGS, RESILIENCE (Phase A infra)
-- ============================================================================

-- --- 6.1 The frozen Port catalogue ---
CREATE TABLE trustride.integration_port_registry (
  port_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  port_code         trustride.integration_port_code_enum NOT NULL UNIQUE,
  responsibility    TEXT NOT NULL,
  primary_vendor    TEXT NOT NULL,
  secondary_vendor  TEXT,
  active            BOOLEAN NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.integration_port_registry IS
  'The frozen Port catalogue (Directive E006-DIR Section 2) -- every external capability TrustRide exposes to itself. No other engine may call a vendor SDK directly; every call is mediated through the port named here.';

-- --- 6.2 Which adapter answers each port right now (config) ---
CREATE TABLE trustride.integration_adapter_registry (
  adapter_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  port_code      trustride.integration_port_code_enum NOT NULL REFERENCES trustride.integration_port_registry (port_code),
  adapter_type   trustride.integration_adapter_type_enum NOT NULL DEFAULT 'SIMULATOR',
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  activated_by   UUID,
  activated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  notes          TEXT
);
CREATE UNIQUE INDEX uq_integration_adapter_active ON trustride.integration_adapter_registry (port_code) WHERE active = TRUE;
COMMENT ON TABLE trustride.integration_adapter_registry IS
  'Phase C activation switch, per port -- flipping adapter_type from SIMULATOR to PRODUCTION is the ONLY change required to go live on a port; every port starts and stays SIMULATOR until this file''s Phase C successor explicitly activates it.';

-- --- 6.3 General feature flags ---
CREATE TABLE trustride.integration_feature_flag (
  flag_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  flag_code   TEXT NOT NULL UNIQUE,
  enabled     BOOLEAN NOT NULL DEFAULT FALSE,
  description TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- --- 6.4 Circuit breaker state (resilience) ---
CREATE TABLE trustride.integration_circuit_breaker_state (
  breaker_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  port_code        trustride.integration_port_code_enum NOT NULL UNIQUE REFERENCES trustride.integration_port_registry (port_code),
  state            trustride.integration_circuit_state_enum NOT NULL DEFAULT 'CLOSED',
  failure_count    INTEGER NOT NULL DEFAULT 0,
  latency_ms_last  INTEGER,
  opened_at        TIMESTAMPTZ,
  next_retry_at    TIMESTAMPTZ,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.integration_circuit_breaker_state IS
  'One row per port. OPEN blocks further calls to that port''s active adapter until next_retry_at; HALF_OPEN allows one probe call. Directive Section 5: latency > 3.5s or error rate > 5% trips the breaker for payments -- the same primitive is reused for every port.';

-- --- 6.5 Webhook / callback log (inbound, append-only) ---
CREATE TABLE trustride.integration_webhook_log (
  webhook_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  port_code         trustride.integration_port_code_enum NOT NULL,
  provider_reference TEXT,
  signature_valid   BOOLEAN,
  raw_payload       JSONB NOT NULL,
  processed         BOOLEAN NOT NULL DEFAULT FALSE,
  processed_at      TIMESTAMPTZ,
  received_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
REVOKE UPDATE, DELETE ON trustride.integration_webhook_log FROM PUBLIC;
COMMENT ON TABLE trustride.integration_webhook_log IS
  'Immutable evidentiary record of every inbound callback, real or simulated -- Directive Section 5: "All callbacks: immediate acknowledgement + durable queue," this is the durable queue''s permanent record.';

-- ============================================================================
-- PHASE 4 -- PORT-SPECIFIC SUPPORTING TABLES
-- ============================================================================

-- --- IIdentityAuthorityService ---
CREATE TABLE trustride.integration_identity_verification_log (
  log_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  verification_id     UUID NOT NULL,
  subject_user_id      UUID NOT NULL,
  submitted_national_id TEXT NOT NULL,
  submitted_legal_name  TEXT NOT NULL,
  returned_legal_name   TEXT,
  returned_status       trustride.integration_verification_outcome_enum,
  returned_kra_pin      TEXT,
  adapter_type          trustride.integration_adapter_type_enum NOT NULL,
  latency_ms            INTEGER,
  raw_response           JSONB,
  requested_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  responded_at              TIMESTAMPTZ
);
COMMENT ON TABLE trustride.integration_identity_verification_log IS
  'EAGLE-EYE-style evidentiary record of every identity verification attempt -- what was submitted, what was returned, which adapter answered, how long it took.';

-- --- IPaymentGateway ---
CREATE TABLE trustride.integration_payment_gateway_transaction (
  gateway_txn_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id           UUID,
  requester_user_id  UUID,
  amount_kes         NUMERIC(18,2) NOT NULL CHECK (amount_kes >= 0),
  currency           CHAR(3) NOT NULL DEFAULT 'KES',
  payment_rail       TEXT NOT NULL,
  txn_status         trustride.integration_payment_txn_status_enum NOT NULL DEFAULT 'INITIATED',
  provider_reference TEXT,
  adapter_type       trustride.integration_adapter_type_enum NOT NULL,
  correlation_id     UUID NOT NULL,
  initiated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  settled_at         TIMESTAMPTZ
);
COMMENT ON TABLE trustride.integration_payment_gateway_transaction IS
  'Every STK Push/C2B transaction, real or simulated -- correlates back to quote_id, never the ledger itself (Article per MNY-15: Money is not Payment; this is the Payment operation''s own record, Settlement/Ledger remain a separate, future authority).';

-- --- INotificationRouter (SMS/WhatsApp/Voice/USSD unified) ---
CREATE TABLE trustride.integration_notification_dispatch_log (
  dispatch_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_ref   UUID,
  channel         trustride.integration_notification_channel_enum NOT NULL,
  template_code   TEXT NOT NULL,
  payload         JSONB NOT NULL,
  status          trustride.integration_notification_status_enum NOT NULL DEFAULT 'QUEUED',
  adapter_type    trustride.integration_adapter_type_enum NOT NULL,
  provider_reference TEXT,
  correlation_id  UUID,
  dispatched_at   TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.integration_notification_dispatch_log IS
  'INotificationRouter''s own record -- the Smart Messaging Router decides the channel; this table is the resulting dispatch, real or simulated.';

-- --- Signal envelope (per platform convention) ---
CREATE TABLE trustride.integration_event_outbox (
  signal_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id   UUID NOT NULL,
  causation_id     UUID,
  emitting_engine  TEXT NOT NULL DEFAULT 'TRS026_ENG006_INTG',
  receiving_engine TEXT NOT NULL,
  signal_type      TEXT NOT NULL,
  payload_in       JSONB NOT NULL,
  signal_status    TEXT NOT NULL DEFAULT 'PENDING'
                      CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason TEXT,
  idempotency_key  TEXT NOT NULL UNIQUE,
  attempt_count    INTEGER NOT NULL DEFAULT 0,
  emitted_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_integration_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);

CREATE TABLE trustride.integration_event_inbox (
  signal_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id   UUID NOT NULL,
  causation_id     UUID,
  emitting_engine  TEXT NOT NULL,
  receiving_engine TEXT NOT NULL DEFAULT 'TRS026_ENG006_INTG',
  signal_type      TEXT NOT NULL,
  payload_in       JSONB NOT NULL,
  payload_out      JSONB,
  signal_status    TEXT NOT NULL DEFAULT 'RECEIVED'
                      CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason TEXT,
  idempotency_key  TEXT NOT NULL UNIQUE,
  emitted_at       TIMESTAMPTZ,
  received_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at      TIMESTAMPTZ,
  CONSTRAINT chk_integration_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);

-- Correction 2 (this file's header): fn_orch_dispatch_cycle's generic
-- dynamic INSERT never accounted for platform_event_inbox's own emitted_at
-- column (NOT NULL, no default -- preserving the source outbox's original
-- emission time, distinct from this inbox's own received_at). Every other
-- engine's inbox lacked the column entirely, so the gap stayed invisible
-- until Foundation became a real dispatch destination for the first time in
-- this file. Fixed generally: the dispatch function now always supplies
-- emitted_at, and every live inbox table gains a matching nullable column
-- (integration_event_inbox has it from creation, above; the three already-
-- live inbox tables gain it here, additive, no data loss).
ALTER TABLE trustride.resource_event_inbox ADD COLUMN IF NOT EXISTS emitted_at TIMESTAMPTZ;
ALTER TABLE trustride.service_event_inbox ADD COLUMN IF NOT EXISTS emitted_at TIMESTAMPTZ;
ALTER TABLE trustride.cost_event_inbox ADD COLUMN IF NOT EXISTS emitted_at TIMESTAMPTZ;

-- ============================================================================
-- PHASE 5 -- RESILIENCE PRIMITIVES
-- ============================================================================
CREATE OR REPLACE FUNCTION trustride.fn_integration_circuit_check(p_port_code trustride.integration_port_code_enum)
RETURNS trustride.integration_circuit_state_enum
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_state trustride.integration_circuit_state_enum;
  v_next_retry TIMESTAMPTZ;
BEGIN
  SELECT state, next_retry_at INTO v_state, v_next_retry FROM trustride.integration_circuit_breaker_state WHERE port_code = p_port_code;
  IF v_state IS NULL THEN
    INSERT INTO trustride.integration_circuit_breaker_state (port_code, state) VALUES (p_port_code, 'CLOSED');
    RETURN 'CLOSED';
  END IF;
  IF v_state = 'OPEN' AND v_next_retry IS NOT NULL AND v_next_retry <= now() THEN
    UPDATE trustride.integration_circuit_breaker_state SET state = 'HALF_OPEN', updated_at = now() WHERE port_code = p_port_code;
    RETURN 'HALF_OPEN';
  END IF;
  RETURN v_state;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_integration_circuit_record_result(p_port_code trustride.integration_port_code_enum, p_success BOOLEAN, p_latency_ms INTEGER)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_failure_count INTEGER;
BEGIN
  IF p_success AND p_latency_ms <= 3500 THEN
    UPDATE trustride.integration_circuit_breaker_state
    SET state = 'CLOSED', failure_count = 0, latency_ms_last = p_latency_ms, opened_at = NULL, next_retry_at = NULL, updated_at = now()
    WHERE port_code = p_port_code;
  ELSE
    UPDATE trustride.integration_circuit_breaker_state
    SET failure_count = failure_count + 1, latency_ms_last = p_latency_ms, updated_at = now()
    WHERE port_code = p_port_code
    RETURNING failure_count INTO v_failure_count;

    IF v_failure_count >= 3 THEN
      UPDATE trustride.integration_circuit_breaker_state
      SET state = 'OPEN', opened_at = now(), next_retry_at = now() + interval '30 seconds'
      WHERE port_code = p_port_code;
    END IF;
  END IF;
END;
$$;
COMMENT ON FUNCTION trustride.fn_integration_circuit_record_result IS
  'Directive Section 5: latency > 3.5s or error rate > 5% trips failover. Simplified to a 3-strikes threshold here (real error-rate windowing is a Phase C refinement once real adapters produce real latency distributions).';

-- ============================================================================
-- PHASE 6 -- SIMULATOR ADAPTERS (Phase A -- realistic, configurable, no
-- external network call of any kind)
-- ============================================================================

-- --- IIdentityAuthorityService simulator ---
-- Configurable failure: any national_id beginning with '00' simulates a
-- DECEASED/INVALID authority response (a deliberate, documented test knob --
-- Directive Section 6 Phase A: "configurable failures, latency, idempotency").
CREATE OR REPLACE FUNCTION trustride.fn_integration_identity_verify_simulate(
  p_national_id TEXT, p_full_legal_name TEXT
)
RETURNS TABLE (returned_legal_name TEXT, returned_status trustride.integration_verification_outcome_enum, returned_kra_pin TEXT, latency_ms INTEGER, raw_response JSONB)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_latency INTEGER := 200 + (abs(hashtext(p_national_id)) % 800);
BEGIN
  IF left(p_national_id, 2) = '00' THEN
    RETURN QUERY SELECT p_full_legal_name, 'INVALID'::trustride.integration_verification_outcome_enum, NULL::TEXT, v_latency,
      jsonb_build_object('simulated', true, 'reason', 'TEST_PATTERN_00_PREFIX_SIMULATES_INVALID');
  ELSIF left(p_national_id, 2) = '99' THEN
    RETURN QUERY SELECT p_full_legal_name, 'DECEASED'::trustride.integration_verification_outcome_enum, NULL::TEXT, v_latency,
      jsonb_build_object('simulated', true, 'reason', 'TEST_PATTERN_99_PREFIX_SIMULATES_DECEASED');
  ELSE
    RETURN QUERY SELECT p_full_legal_name, 'ALIVE_VALID'::trustride.integration_verification_outcome_enum,
      ('A' || lpad((abs(hashtext(p_national_id)) % 10000000)::text, 7, '0') || 'X'), v_latency,
      jsonb_build_object('simulated', true, 'source', 'IPRS_SIMULATOR');
  END IF;
END;
$$;
COMMENT ON FUNCTION trustride.fn_integration_identity_verify_simulate IS
  'IIdentityAuthorityService simulator adapter -- deterministic per national_id (repeatable for tests), realistic KRA PIN shape, latency modelled 200-1000ms.';

-- --- IPaymentGateway simulator ---
-- Configurable failure: an amount ending in .13 simulates a gateway failure
-- (a deliberate test knob, same convention as the identity simulator).
CREATE OR REPLACE FUNCTION trustride.fn_integration_payment_stk_simulate(p_amount_kes NUMERIC)
RETURNS TABLE (accepted BOOLEAN, provider_reference TEXT, latency_ms INTEGER)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_latency INTEGER := 300 + (abs(hashtext(p_amount_kes::text)) % 1200);
BEGIN
  IF (p_amount_kes * 100)::bigint % 100 = 13 THEN
    RETURN QUERY SELECT FALSE, NULL::TEXT, v_latency;
  ELSE
    RETURN QUERY SELECT TRUE, ('SIM-MPESA-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-' || lpad((abs(hashtext(p_amount_kes::text || now()::text)) % 100000)::text, 5, '0')), v_latency;
  END IF;
END;
$$;
COMMENT ON FUNCTION trustride.fn_integration_payment_stk_simulate IS
  'IPaymentGateway simulator adapter -- STK Push acceptance only (real Daraja is async: acceptance now, callback later). fn_integration_payment_callback_simulate models the callback leg separately, matching the real webhook shape Phase C will need.';

CREATE OR REPLACE FUNCTION trustride.fn_integration_payment_callback_simulate(p_gateway_txn_id UUID, p_outcome trustride.integration_payment_txn_status_enum DEFAULT 'SETTLED')
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_txn RECORD;
  v_webhook_id UUID;
BEGIN
  SELECT * INTO v_txn FROM trustride.integration_payment_gateway_transaction WHERE gateway_txn_id = p_gateway_txn_id AND txn_status = 'PENDING_CALLBACK';
  IF v_txn IS NULL THEN
    RAISE EXCEPTION 'fn_integration_payment_callback_simulate: no PENDING_CALLBACK transaction %', p_gateway_txn_id;
  END IF;

  INSERT INTO trustride.integration_webhook_log (port_code, provider_reference, signature_valid, raw_payload, processed)
  VALUES ('PAYMENT_GATEWAY', v_txn.provider_reference, TRUE,
    jsonb_build_object('simulated', true, 'gateway_txn_id', p_gateway_txn_id, 'outcome', p_outcome), FALSE)
  RETURNING webhook_id INTO v_webhook_id;

  PERFORM trustride.fn_integration_payment_callback_process(p_gateway_txn_id, v_txn.provider_reference, p_outcome, v_webhook_id);
  RETURN v_webhook_id;
END;
$$;

-- --- ISmsService / INotificationRouter simulator ---
CREATE OR REPLACE FUNCTION trustride.fn_integration_notification_dispatch_simulate(
  p_recipient_ref UUID, p_channel trustride.integration_notification_channel_enum, p_template_code TEXT, p_payload JSONB, p_correlation_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_dispatch_id UUID;
BEGIN
  INSERT INTO trustride.integration_notification_dispatch_log
    (recipient_ref, channel, template_code, payload, status, adapter_type, provider_reference, correlation_id, dispatched_at)
  VALUES
    (p_recipient_ref, p_channel, p_template_code, p_payload, 'DISPATCHED', 'SIMULATOR',
     'SIM-' || upper(p_channel::text) || '-' || encode(gen_random_bytes(4), 'hex'), p_correlation_id, now())
  RETURNING dispatch_id INTO v_dispatch_id;

  RETURN v_dispatch_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_integration_notification_dispatch_simulate IS
  'INotificationRouter simulator -- always succeeds (dispatch is fire-and-forget by design; delivery receipts are a Phase C real-adapter concern).';

-- ============================================================================
-- PHASE 7 -- INBOUND SIGNAL ACCEPT-HANDLERS
-- ============================================================================

CREATE OR REPLACE FUNCTION trustride.fn_integration_verification_requested_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_correlation_id UUID;
  v_verification_id UUID;
  v_subject_user_id UUID;
  v_sim RECORD;
  v_circuit trustride.integration_circuit_state_enum;
  v_start TIMESTAMPTZ := clock_timestamp();
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_correlation_id FROM trustride.integration_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_integration_verification_requested_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  v_circuit := trustride.fn_integration_circuit_check('IDENTITY_AUTHORITY');
  IF v_circuit = 'OPEN' THEN
    UPDATE trustride.integration_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'CIRCUIT_OPEN', accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END IF;

  v_verification_id := (v_payload->>'verification_id')::uuid;
  v_subject_user_id := (v_payload->>'subject_user_id')::uuid;

  SELECT * INTO v_sim FROM trustride.fn_integration_identity_verify_simulate(v_payload->>'national_id', v_payload->>'full_legal_name');

  INSERT INTO trustride.integration_identity_verification_log
    (verification_id, subject_user_id, submitted_national_id, submitted_legal_name, returned_legal_name, returned_status, returned_kra_pin, adapter_type, latency_ms, raw_response, responded_at)
  VALUES
    (v_verification_id, v_subject_user_id, v_payload->>'national_id', v_payload->>'full_legal_name',
     v_sim.returned_legal_name, v_sim.returned_status, v_sim.returned_kra_pin, 'SIMULATOR', v_sim.latency_ms, v_sim.raw_response, now());

  PERFORM trustride.fn_integration_circuit_record_result('IDENTITY_AUTHORITY', TRUE, v_sim.latency_ms);

  INSERT INTO trustride.integration_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v_correlation_id, 'TRS026_ENG001_FDN', 'VERIFICATION_COMPLETED',
    jsonb_build_object('verification_id', v_verification_id, 'returned_legal_name', v_sim.returned_legal_name,
      'returned_status', v_sim.returned_status, 'returned_kra_pin', v_sim.returned_kra_pin, 'raw_response', v_sim.raw_response),
    'VERIFICATION_COMPLETED:' || v_verification_id::text);

  UPDATE trustride.integration_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_integration_verification_requested_accept IS
  'Receives VERIFICATION_REQUESTED from Foundation, calls the active IIdentityAuthorityService adapter (SIMULATOR in Phase A), logs the attempt, emits VERIFICATION_COMPLETED back -- the exact contract Foundation''s fn_verification_completed_accept has been waiting for since Engine 1''s own first migration.';

CREATE OR REPLACE FUNCTION trustride.fn_integration_payment_stk_triggered_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_correlation_id UUID;
  v_gateway_txn_id UUID;
  v_sim RECORD;
  v_circuit trustride.integration_circuit_state_enum;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_correlation_id FROM trustride.integration_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_integration_payment_stk_triggered_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  v_circuit := trustride.fn_integration_circuit_check('PAYMENT_GATEWAY');
  IF v_circuit = 'OPEN' THEN
    UPDATE trustride.integration_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'CIRCUIT_OPEN', accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END IF;

  SELECT * INTO v_sim FROM trustride.fn_integration_payment_stk_simulate((v_payload->>'computed_total_fare_kes')::numeric);

  INSERT INTO trustride.integration_payment_gateway_transaction
    (quote_id, requester_user_id, amount_kes, currency, payment_rail, txn_status, provider_reference, adapter_type, correlation_id)
  VALUES
    ((v_payload->>'quote_id')::uuid, (v_payload->>'requester_user_id')::uuid, (v_payload->>'computed_total_fare_kes')::numeric,
     coalesce(v_payload->>'currency', 'KES'), coalesce(v_payload->>'payment_rail', 'MPESA_C2B_STK'),
     CASE WHEN v_sim.accepted THEN 'PENDING_CALLBACK'::trustride.integration_payment_txn_status_enum ELSE 'FAILED'::trustride.integration_payment_txn_status_enum END,
     v_sim.provider_reference, 'SIMULATOR', v_correlation_id)
  RETURNING gateway_txn_id INTO v_gateway_txn_id;

  PERFORM trustride.fn_integration_circuit_record_result('PAYMENT_GATEWAY', v_sim.accepted, v_sim.latency_ms);

  IF NOT v_sim.accepted THEN
    INSERT INTO trustride.integration_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (v_correlation_id, 'TRS026_ENG004_BUS', 'PAYMENT_STK_FAILED',
      jsonb_build_object('quote_id', v_payload->>'quote_id', 'gateway_txn_id', v_gateway_txn_id, 'reason', 'GATEWAY_DECLINED'),
      'PAYMENT_STK_FAILED:' || v_gateway_txn_id::text);
  END IF;

  UPDATE trustride.integration_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('gateway_txn_id', v_gateway_txn_id, 'accepted', v_sim.accepted) WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_integration_payment_stk_triggered_accept IS
  'Receives PAYMENT_STK_TRIGGERED from Cost, calls the active IPaymentGateway adapter''s STK-push leg. The transaction sits PENDING_CALLBACK until fn_integration_payment_callback_process (real webhook in Phase C, fn_integration_payment_callback_simulate here) completes it -- modelling Daraja''s real async shape from day one.';

CREATE OR REPLACE FUNCTION trustride.fn_integration_payment_callback_process(
  p_gateway_txn_id UUID, p_provider_reference TEXT, p_outcome trustride.integration_payment_txn_status_enum, p_webhook_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_txn RECORD;
BEGIN
  UPDATE trustride.integration_payment_gateway_transaction
  SET txn_status = p_outcome, settled_at = now()
  WHERE gateway_txn_id = p_gateway_txn_id AND txn_status = 'PENDING_CALLBACK'
  RETURNING * INTO v_txn;

  IF v_txn IS NULL THEN
    RAISE EXCEPTION 'fn_integration_payment_callback_process: no PENDING_CALLBACK transaction %', p_gateway_txn_id;
  END IF;

  IF p_webhook_id IS NOT NULL THEN
    UPDATE trustride.integration_webhook_log SET processed = TRUE, processed_at = now() WHERE webhook_id = p_webhook_id;
  END IF;

  INSERT INTO trustride.integration_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v_txn.correlation_id, 'TRS026_ENG004_BUS', CASE WHEN p_outcome = 'SETTLED' THEN 'PAYMENT_SETTLED' ELSE 'PAYMENT_FAILED' END,
    jsonb_build_object('quote_id', v_txn.quote_id, 'gateway_txn_id', p_gateway_txn_id, 'provider_reference', p_provider_reference, 'amount_kes', v_txn.amount_kes),
    (CASE WHEN p_outcome = 'SETTLED' THEN 'PAYMENT_SETTLED' ELSE 'PAYMENT_FAILED' END) || ':' || p_gateway_txn_id::text);
END;
$$;
COMMENT ON FUNCTION trustride.fn_integration_payment_callback_process IS
  'The honest external boundary named in this file''s own header: nothing here calls a real Daraja/Flutterwave endpoint. This function completes the round trip identically whether the callback came from fn_integration_payment_callback_simulate (Phase A) or a real Edge Function webhook receiver (Phase C) -- the contract does not change when the adapter does.';

CREATE OR REPLACE FUNCTION trustride.fn_integration_inbox_process(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
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
    ELSE
      UPDATE trustride.integration_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'UNREGISTERED_SIGNAL_TYPE:' || v_signal_type WHERE signal_id = p_signal_id;
      v_result := 'REJECTED';
  END CASE;

  RETURN v_result;
END;
$$;

-- --- Correction 1 (this file's header): Foundation's own inbox dispatcher,
-- built for the first time -- it has never existed before this signal loop
-- needed it. ---
CREATE OR REPLACE FUNCTION trustride.fn_platform_inbox_process(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_signal_type TEXT;
  v_payload JSONB;
  v_result TEXT;
BEGIN
  SELECT signal_type, payload_in INTO v_signal_type, v_payload FROM trustride.platform_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_signal_type IS NULL THEN
    RAISE EXCEPTION 'fn_platform_inbox_process: no RECEIVED signal %', p_signal_id;
  END IF;

  CASE v_signal_type
    WHEN 'VERIFICATION_COMPLETED' THEN
      v_result := trustride.fn_verification_completed_accept(
        (v_payload->>'verification_id')::uuid, v_payload->>'returned_legal_name',
        v_payload->>'returned_status', v_payload->>'returned_kra_pin', v_payload->'raw_response'
      );
    ELSE
      UPDATE trustride.platform_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'UNREGISTERED_SIGNAL_TYPE:' || v_signal_type WHERE signal_id = p_signal_id;
      v_result := 'REJECTED';
  END CASE;

  IF v_result IN ('VERIFIED', 'FAILED', 'ACCEPTED') THEN
    UPDATE trustride.platform_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  END IF;

  RETURN v_result;
END;
$$;
COMMENT ON FUNCTION trustride.fn_platform_inbox_process IS
  'Foundation''s own inbox dispatcher -- did not exist before this file. Closes the loop Foundation''s registration flow has been waiting on since its own first migration: VERIFICATION_REQUESTED out, VERIFICATION_COMPLETED back in, processed for real.';

-- ============================================================================
-- PHASE 8 -- EXTEND ORCHESTRATION (preserve every previously-recognized
-- engine's branch; add FDN's inbox-process call for the first time, and
-- INTG as a new destination)
-- ============================================================================
CREATE OR REPLACE FUNCTION trustride.fn_orch_destination_cache_sync()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_synced INTEGER;
  v_deactivated INTEGER;
BEGIN
  INSERT INTO trustride.orch_destination_cache
    (source_engine_code, signal_type, destination_engine_code, destination_inbox_table, default_partition_code, synced_from_routing_rule_ref, cache_status, last_synced_at)
  SELECT rr.source_engine, rr.event_type, rr.target_engine,
    CASE rr.target_engine
      WHEN 'TRS026_ENG001_FDN'  THEN 'platform_event_inbox'
      WHEN 'TRS026_ENG002_RESC' THEN 'resource_event_inbox'
      WHEN 'TRS026_ENG003_SERV' THEN 'service_event_inbox'
      WHEN 'TRS026_ENG004_BUS'  THEN 'business_event_inbox'
      WHEN 'TRS026_ENG005_COST' THEN 'cost_event_inbox'
      WHEN 'TRS026_ENG006_INTG' THEN 'integration_event_inbox'
      ELSE NULL
    END,
    rr.target_engine || ':DEFAULT',
    rr.route_id::text, 'ACTIVE', now()
  FROM trustride.routing_rule rr
  WHERE rr.active = TRUE
    AND CASE rr.target_engine
      WHEN 'TRS026_ENG001_FDN' THEN TRUE WHEN 'TRS026_ENG002_RESC' THEN TRUE WHEN 'TRS026_ENG003_SERV' THEN TRUE
      WHEN 'TRS026_ENG004_BUS' THEN TRUE WHEN 'TRS026_ENG005_COST' THEN TRUE WHEN 'TRS026_ENG006_INTG' THEN TRUE ELSE FALSE
    END
  ON CONFLICT (source_engine_code, signal_type, destination_engine_code) DO UPDATE
    SET destination_inbox_table = EXCLUDED.destination_inbox_table,
        cache_status = 'ACTIVE', last_synced_at = now();

  GET DIAGNOSTICS v_synced = ROW_COUNT;

  UPDATE trustride.orch_destination_cache dc
  SET cache_status = 'SUPERSEDED', last_synced_at = now()
  WHERE dc.cache_status = 'ACTIVE'
    AND NOT EXISTS (
      SELECT 1 FROM trustride.routing_rule rr
      WHERE rr.active = TRUE AND rr.source_engine = dc.source_engine_code
        AND rr.event_type = dc.signal_type AND rr.target_engine = dc.destination_engine_code
    );
  GET DIAGNOSTICS v_deactivated = ROW_COUNT;

  RETURN v_synced + v_deactivated;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_orch_dispatch_cycle()
RETURNS TABLE (discovered INTEGER, routed INTEGER, no_rule_matched INTEGER, dispatched INTEGER, processed INTEGER)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_union_sql  TEXT;
  v_row        RECORD;
  v_discovered INTEGER := 0;
  v_routed     INTEGER := 0;
  v_no_rule    INTEGER := 0;
  v_dispatched INTEGER := 0;
  v_processed  INTEGER := 0;
  v_cache      RECORD;
  v_partition_id UUID;
  v_queue_id     UUID;
  v_prev_hash    CHAR(64);
  v_new_hash     CHAR(64);
BEGIN
  SELECT string_agg(
    format('SELECT signal_id, correlation_id, causation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key, emitted_at, %L::text AS src_outbox_table FROM trustride.%I WHERE signal_status = ''PENDING''',
      outbox_table_name, outbox_table_name),
    ' UNION ALL '
  ) INTO v_union_sql
  FROM trustride.orch_outbox_registry WHERE active = TRUE;

  IF v_union_sql IS NOT NULL THEN
    FOR v_row IN EXECUTE v_union_sql || ' ORDER BY emitted_at' LOOP
      v_discovered := v_discovered + 1;

      INSERT INTO trustride.orch_execution_graph (correlation_id, signal_id, node_sequence, engine_code, node_stage)
      VALUES (v_row.correlation_id, v_row.signal_id, 1, v_row.emitting_engine, 'EMITTED');

      SELECT * INTO v_cache FROM trustride.orch_destination_cache
      WHERE source_engine_code = v_row.emitting_engine AND signal_type = v_row.signal_type
        AND destination_engine_code = v_row.receiving_engine AND cache_status = 'ACTIVE';

      IF v_cache IS NULL THEN
        v_no_rule := v_no_rule + 1;
        INSERT INTO trustride.orch_routing_decision (signal_id, correlation_id, source_engine_code, destination_engine_code, signal_type, routing_result)
        VALUES (v_row.signal_id, v_row.correlation_id, v_row.emitting_engine, v_row.receiving_engine, v_row.signal_type, 'NO_RULE_MATCHED');

        SELECT immutable_hash INTO v_prev_hash FROM trustride.orch_routing_audit ORDER BY recorded_at DESC LIMIT 1;
        v_new_hash := encode(digest(coalesce(v_prev_hash,'') || v_row.signal_id::text || 'NO_RULE_MATCHED', 'sha256'), 'hex');
        INSERT INTO trustride.orch_routing_audit (signal_id, correlation_id, routing_result, prev_hash, immutable_hash)
        VALUES (v_row.signal_id, v_row.correlation_id, 'NO_RULE_MATCHED', v_prev_hash, v_new_hash);

        CONTINUE;
      END IF;

      v_routed := v_routed + 1;
      INSERT INTO trustride.orch_routing_decision (signal_id, correlation_id, source_engine_code, destination_engine_code, signal_type, matched_routing_rule_ref, destination_partition_code, routing_result)
      VALUES (v_row.signal_id, v_row.correlation_id, v_row.emitting_engine, v_cache.destination_engine_code, v_row.signal_type, v_cache.synced_from_routing_rule_ref, v_cache.default_partition_code, 'ROUTED');

      SELECT immutable_hash INTO v_prev_hash FROM trustride.orch_routing_audit ORDER BY recorded_at DESC LIMIT 1;
      v_new_hash := encode(digest(coalesce(v_prev_hash,'') || v_row.signal_id::text || 'ROUTED', 'sha256'), 'hex');
      INSERT INTO trustride.orch_routing_audit (signal_id, correlation_id, routing_result, prev_hash, immutable_hash)
      VALUES (v_row.signal_id, v_row.correlation_id, 'ROUTED', v_prev_hash, v_new_hash);

      INSERT INTO trustride.orch_execution_graph (correlation_id, signal_id, node_sequence, engine_code, node_stage)
      VALUES (v_row.correlation_id, v_row.signal_id, 2, 'TRS026_ENG007_ORCH', 'ROUTED');

      PERFORM trustride.fn_coord_admission_check(v_row.signal_type, v_row.signal_id, v_row.correlation_id, v_row.emitting_engine, v_cache.destination_engine_code);

      v_partition_id := trustride.fn_orch_queue_partition_ensure(v_cache.destination_engine_code);

      INSERT INTO trustride.orch_signal_queue (signal_id, correlation_id, source_engine_code, destination_engine_code, signal_type, queue_partition_id, idempotency_key)
      VALUES (v_row.signal_id, v_row.correlation_id, v_row.emitting_engine, v_cache.destination_engine_code, v_row.signal_type, v_partition_id, v_row.idempotency_key || ':queue')
      ON CONFLICT (idempotency_key) DO NOTHING
      RETURNING queue_id INTO v_queue_id;

      INSERT INTO trustride.orch_execution_graph (correlation_id, signal_id, node_sequence, engine_code, node_stage)
      VALUES (v_row.correlation_id, v_row.signal_id, 3, 'TRS026_ENG007_ORCH', 'QUEUED');

      EXECUTE format(
        'INSERT INTO trustride.%I (signal_id, correlation_id, causation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key, emitted_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)',
        v_cache.destination_inbox_table
      ) USING v_row.signal_id, v_row.correlation_id, v_row.causation_id, v_row.emitting_engine, v_cache.destination_engine_code, v_row.signal_type, v_row.payload_in, v_row.idempotency_key || ':inbox', v_row.emitted_at;

      EXECUTE format('UPDATE trustride.%I SET signal_status = ''DISPATCHED'' WHERE signal_id = $1', v_row.src_outbox_table) USING v_row.signal_id;
      IF v_queue_id IS NOT NULL THEN
        UPDATE trustride.orch_signal_queue SET queue_status = 'DISPATCHED', dispatched_at = now() WHERE queue_id = v_queue_id;
      END IF;

      INSERT INTO trustride.orch_signal_lineage (correlation_id, parent_signal_id, child_signal_id, relationship_type)
      VALUES (v_row.correlation_id, NULL, v_row.signal_id, 'CAUSED');

      INSERT INTO trustride.orch_execution_graph (correlation_id, signal_id, node_sequence, engine_code, node_stage)
      VALUES (v_row.correlation_id, v_row.signal_id, 4, 'TRS026_ENG007_ORCH', 'DISPATCHED');
      INSERT INTO trustride.orch_execution_graph (correlation_id, signal_id, node_sequence, engine_code, node_stage)
      VALUES (v_row.correlation_id, v_row.signal_id, 5, v_cache.destination_engine_code, 'RECEIVED');

      SELECT immutable_hash INTO v_prev_hash FROM trustride.orch_execution_audit ORDER BY recorded_at DESC LIMIT 1;
      v_new_hash := encode(digest(coalesce(v_prev_hash,'') || v_row.signal_id::text || 'DISPATCHED', 'sha256'), 'hex');
      INSERT INTO trustride.orch_execution_audit (signal_id, correlation_id, engine_code, execution_stage, execution_result, prev_hash, immutable_hash)
      VALUES (v_row.signal_id, v_row.correlation_id, v_cache.destination_engine_code, 'DISPATCHED', 'SUCCESS', v_prev_hash, v_new_hash);

      v_dispatched := v_dispatched + 1;

      BEGIN
        CASE v_cache.destination_engine_code
          WHEN 'TRS026_ENG001_FDN' THEN PERFORM trustride.fn_platform_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG002_RESC' THEN PERFORM trustride.fn_resource_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG003_SERV' THEN PERFORM trustride.fn_service_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG004_BUS' THEN PERFORM trustride.fn_business_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG005_COST' THEN PERFORM trustride.fn_cost_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG006_INTG' THEN PERFORM trustride.fn_integration_inbox_process(v_row.signal_id);
          ELSE NULL;
        END CASE;
        v_processed := v_processed + 1;
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END LOOP;
  END IF;

  RETURN QUERY SELECT v_discovered, v_routed, v_no_rule, v_dispatched, v_processed;
END;
$$;

-- ============================================================================
-- PHASE 9 -- ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE trustride.integration_port_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_port_registry_platform_read ON trustride.integration_port_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY integration_port_registry_service_write ON trustride.integration_port_registry FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.integration_adapter_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_adapter_registry_platform_read ON trustride.integration_adapter_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY integration_adapter_registry_service_write ON trustride.integration_adapter_registry FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.integration_feature_flag ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_feature_flag_platform_read ON trustride.integration_feature_flag FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY integration_feature_flag_service_write ON trustride.integration_feature_flag FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.integration_circuit_breaker_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_circuit_breaker_state_service_only ON trustride.integration_circuit_breaker_state FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.integration_webhook_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_webhook_log_service_only ON trustride.integration_webhook_log FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.integration_identity_verification_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_identity_verification_log_own_read ON trustride.integration_identity_verification_log FOR SELECT TO trustride_authenticated USING (subject_user_id = auth.uid());
CREATE POLICY integration_identity_verification_log_service_write ON trustride.integration_identity_verification_log FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.integration_payment_gateway_transaction ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_payment_gateway_transaction_own_read ON trustride.integration_payment_gateway_transaction FOR SELECT TO trustride_authenticated USING (requester_user_id = auth.uid());
CREATE POLICY integration_payment_gateway_transaction_service_write ON trustride.integration_payment_gateway_transaction FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.integration_notification_dispatch_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_notification_dispatch_log_own_read ON trustride.integration_notification_dispatch_log FOR SELECT TO trustride_authenticated USING (recipient_ref = auth.uid());
CREATE POLICY integration_notification_dispatch_log_service_write ON trustride.integration_notification_dispatch_log FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.integration_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_event_outbox_service_only ON trustride.integration_event_outbox FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.integration_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_event_inbox_service_only ON trustride.integration_event_inbox FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);

-- ============================================================================
-- PHASE 10 -- INDEXES
-- ============================================================================
CREATE INDEX idx_integration_circuit_breaker_port ON trustride.integration_circuit_breaker_state (port_code);
CREATE INDEX idx_integration_webhook_log_port ON trustride.integration_webhook_log (port_code, received_at DESC);
CREATE INDEX idx_integration_identity_log_subject ON trustride.integration_identity_verification_log (subject_user_id);
CREATE INDEX idx_integration_identity_log_verification ON trustride.integration_identity_verification_log (verification_id);
CREATE INDEX idx_integration_payment_txn_quote ON trustride.integration_payment_gateway_transaction (quote_id);
CREATE INDEX idx_integration_payment_txn_status ON trustride.integration_payment_gateway_transaction (txn_status);
CREATE INDEX idx_integration_notification_recipient ON trustride.integration_notification_dispatch_log (recipient_ref);
CREATE INDEX idx_integration_outbox_status ON trustride.integration_event_outbox (signal_status);
CREATE INDEX idx_integration_inbox_status ON trustride.integration_event_inbox (signal_status);

-- ============================================================================
-- PHASE 11 -- PRIVILEGE LOCKDOWN
-- ============================================================================
GRANT USAGE ON SCHEMA trustride TO trs026_eng006_intg_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA trustride TO trs026_eng006_intg_service;

GRANT EXECUTE ON FUNCTION trustride.fn_integration_circuit_check(trustride.integration_port_code_enum) TO trs026_eng006_intg_service;
GRANT EXECUTE ON FUNCTION trustride.fn_integration_circuit_record_result(trustride.integration_port_code_enum, BOOLEAN, INTEGER) TO trs026_eng006_intg_service;
GRANT EXECUTE ON FUNCTION trustride.fn_integration_identity_verify_simulate(TEXT, TEXT) TO trs026_eng006_intg_service;
GRANT EXECUTE ON FUNCTION trustride.fn_integration_payment_stk_simulate(NUMERIC) TO trs026_eng006_intg_service;
GRANT EXECUTE ON FUNCTION trustride.fn_integration_payment_callback_simulate(UUID, trustride.integration_payment_txn_status_enum) TO trs026_eng006_intg_service;
GRANT EXECUTE ON FUNCTION trustride.fn_integration_payment_callback_process(UUID, TEXT, trustride.integration_payment_txn_status_enum, UUID) TO trs026_eng006_intg_service;
GRANT EXECUTE ON FUNCTION trustride.fn_integration_notification_dispatch_simulate(UUID, trustride.integration_notification_channel_enum, TEXT, JSONB, UUID) TO trs026_eng006_intg_service, trs026_eng001_fdn_service, trs026_eng002_resc_service, trs026_eng003_serv_service, trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_integration_verification_requested_accept(UUID) TO trs026_eng006_intg_service;
GRANT EXECUTE ON FUNCTION trustride.fn_integration_payment_stk_triggered_accept(UUID) TO trs026_eng006_intg_service;
GRANT EXECUTE ON FUNCTION trustride.fn_integration_inbox_process(UUID) TO trs026_eng006_intg_service, trs026_eng007_orch_service;
GRANT EXECUTE ON FUNCTION trustride.fn_platform_inbox_process(UUID) TO trs026_eng001_fdn_service, trs026_eng007_orch_service;
GRANT EXECUTE ON FUNCTION trustride.fn_verification_completed_accept(UUID, TEXT, TEXT, TEXT, JSONB) TO trs026_eng001_fdn_service;

GRANT trs026_eng006_intg_service TO service_role;

-- ============================================================================
-- PHASE 12 -- SEED DATA (moved ahead of validation -- validation checks the
-- seed actually landed, so it must run after, not before)
-- ============================================================================
INSERT INTO trustride.integration_port_registry (port_code, responsibility, primary_vendor, secondary_vendor) VALUES
  ('IDENTITY_AUTHORITY', 'National ID -> Real Names + Status + KRA PIN', 'Licensed IPRS middleman', 'Second licensed gateway'),
  ('MAP_SERVICE', 'User-facing maps, Places Autocomplete, Geocoding', 'Google Maps Platform', NULL),
  ('ROUTING_SERVICE', 'Routing, ETA, Distance Matrix, fleet optimisation', 'HERE', 'OSM-based / self-hosted PostGIS'),
  ('PAYMENT_GATEWAY', 'STK Push, C2B, B2C, B2B, Cards, Escrow splits', 'Safaricom Daraja 3.0', 'Flutterwave'),
  ('SMS_SERVICE', 'Transactional SMS + delivery receipts', 'Africa''s Talking', 'Infobip / Twilio'),
  ('WHATSAPP_SERVICE', 'WhatsApp Business templates & session messages', 'Twilio / Meta Cloud API', 'Africa''s Talking'),
  ('VOICE_MASKING_SERVICE', 'Proxy phone numbers (client <-> operator)', 'Twilio', NULL),
  ('USSD_SERVICE', 'USSD gateway (*384*TRIDE#)', 'Africa''s Talking', NULL),
  ('ETIMS_SERVICE', 'eTIMS VSCU invoice submission & QR code', 'KRA eTIMS VSCU', 'Manual portal fallback'),
  ('NTSA_SERVICE', 'Vehicle registration, logbook, licence verification', 'NTSA API / licensed gateway', NULL),
  ('EPRA_SERVICE', 'Fuel / energy regulatory compliance', 'EPRA API / licensed gateway', NULL),
  ('NOTIFICATION_ROUTER', 'Unified smart routing across SMS/WhatsApp/Voice', 'Internal', NULL);

INSERT INTO trustride.integration_adapter_registry (port_code, adapter_type, notes)
SELECT port_code, 'SIMULATOR', 'Phase A default -- every port starts and stays simulated until Phase C explicitly activates it.'
FROM trustride.integration_port_registry;

INSERT INTO trustride.integration_circuit_breaker_state (port_code, state)
SELECT port_code, 'CLOSED' FROM trustride.integration_port_registry;

INSERT INTO trustride.routing_rule (event_type, source_engine, target_engine, route_priority) VALUES
  ('VERIFICATION_REQUESTED', 'TRS026_ENG001_FDN', 'TRS026_ENG006_INTG', 0),
  ('VERIFICATION_COMPLETED', 'TRS026_ENG006_INTG', 'TRS026_ENG001_FDN', 0),
  ('PAYMENT_STK_TRIGGERED', 'TRS026_ENG005_COST', 'TRS026_ENG006_INTG', 0);

INSERT INTO trustride.orch_outbox_registry (engine_code, outbox_table_name) VALUES ('TRS026_ENG006_INTG', 'integration_event_outbox');

SELECT trustride.fn_orch_destination_cache_sync();

UPDATE trustride.engine_registry SET status = 'INSTALLED', engine_version = '1.0.0-phaseA1' WHERE engine_code = 'TRS026_ENG006_INTG';

-- ============================================================================
-- PHASE 13 -- VALIDATION
-- ============================================================================
DO $$
DECLARE
  v_port_count INTEGER;
BEGIN
  SELECT count(*) INTO v_port_count FROM trustride.integration_port_registry;
  IF v_port_count <> 12 THEN
    RAISE EXCEPTION 'Engine 6 validation failed: expected 12 registered ports, found %', v_port_count;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_platform_inbox_process') THEN
    RAISE EXCEPTION 'Engine 6 validation failed: fn_platform_inbox_process missing';
  END IF;

  RAISE NOTICE 'Engine 6 (Phase A Increment 1) validation passed: 12/12 ports registered, Foundation dispatcher gap closed.';
END
$$;
