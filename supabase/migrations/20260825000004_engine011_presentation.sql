-- ============================================================================
-- ENGINE 11 -- PRESENTATION ENGINE
-- Per TRS026-ENG011-PRESENT-001 v1.0.0 (ADOPTED 2026-08-16)
-- ============================================================================
-- Constitutional character: PROJECTION ONLY. Holds zero authoritative state.
-- Converts human intent into signals and renders lawful projections back --
-- never writes to any other engine's tables.
--
-- With this file, all eleven constitutional engines have real schema in this
-- rebuild. Founder directive this increment: build and test locally, DO NOT
-- migrate (no supabase db push, no git commit) -- awaiting Founder review
-- alongside Engine 10 before either ships.
--
-- SCOPE HONESTY on command translation (Sec.2.4): five command_types get a
-- real, live domain-function translation in this rebuild --
-- RAISE_INTENT->fn_business_order_place, ACCEPT_QUOTATION->fn_cost_quote_lock,
-- TRACK_ELEMENT->fn_business_tracking_location_update,
-- EMIT_PROGRESS_SIGNAL->fn_business_job_progress_advance, and the new
-- RUN_SCENARIO->SCENARIO_RUN_REQUESTED (Engine 10, built alongside this file).
-- Every other registered verb (VIEW_*, CAPTURE_EVIDENCE, EMIT_GOVERNANCE_
-- SIGNAL, RULE_ON_EXCEPTION, AMEND_REGISTER, PUBLISH_OFFER,
-- RECEIVE_ORDER_SIGNAL, SETTLE_LAWFUL_FLOW) is captured for real -- proving
-- Law C-III-1 -- but has no live domain handler anywhere in this rebuild yet,
-- so it stays CAPTURED rather than fabricating a translation nothing else on
-- the platform can act on. ACCEPT_QUOTATION's real precondition (a
-- FARE_ESTIMATED quote) is today already consumed by Cost's own auto-lock
-- stand-in (built explicitly "for when Engine 11 exists" -- see the Engine 6
-- full-port-coverage migration) -- this command is wired to the real,
-- correct function and will correctly reject until that stand-in is
-- separately retired; retiring it is a bigger, cross-cutting decision on
-- Cost's own dispatch flow, out of this increment's scope.
--
-- ADDITIVE COMPLETION: the blueprint seeds SOVEREIGN_EXECUTIVE_CONSOLE with
-- VIEW_WHOLE_ESTATE/RULE_ON_EXCEPTION/AMEND_REGISTER, but its own Sec.4.2
-- requires a verb that fires SCENARIO_RUN_REQUESTED ("issues a what-if
-- command") -- no such verb exists in its own literal seed data. Adding
-- RUN_SCENARIO completes the blueprint's own signal matrix, it does not
-- deviate from it.
--
-- REAL GAP FOUND AND FIXED IN THE SAME FILE: fn_business_order_place's real
-- ORDER_PLACED payload and fn_business_payment_settled_accept's real
-- ORDER_SETTLED payload both omit requester_user_id -- Engine 11 needs it to
-- know who to notify, and fetching it via a live cross-engine table read
-- would violate the "carry values in the payload, never fetch cross-engine"
-- discipline already established this session. Both extended here
-- (CREATE OR REPLACE, unchanged signatures, safe) to add it additively.
-- ============================================================================

-- ============================================================================
-- PHASE 0 -- EXTENSIONS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- PHASE 1 -- SCHEMA + EARLY ROLE CREATION
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng011_present_service') THEN
    CREATE ROLE trs026_eng011_present_service NOLOGIN;
  END IF;
END
$$;

-- ============================================================================
-- PHASE 2 -- ENUMS [Trace: Sec.2.0]
-- ============================================================================
CREATE TYPE trustride.present_shell_code_enum AS ENUM (
  'USER_HUB', 'OPERATOR_APP', 'ADMIN_CONSOLE', 'SOVEREIGN_EXECUTIVE_CONSOLE', 'MARKETPLACE_HUB'
);
CREATE TYPE trustride.present_channel_type_enum AS ENUM ('MOBILE', 'WEB', 'TABLET', 'KIOSK');
CREATE TYPE trustride.present_session_status_enum AS ENUM ('ACTIVE', 'ENDED', 'EXPIRED');
CREATE TYPE trustride.present_translation_status_enum AS ENUM ('CAPTURED', 'TRANSLATED', 'REJECTED');
CREATE TYPE trustride.present_cache_status_enum AS ENUM ('FRESH', 'STALE');
CREATE TYPE trustride.present_bridge_health_enum AS ENUM ('HEALTHY', 'DEGRADED', 'OFFLINE');
CREATE TYPE trustride.present_read_status_enum AS ENUM ('UNREAD', 'READ');

-- ============================================================================
-- PHASE 3 -- TABLES [Trace: Sec.2.1-2.11]
-- ============================================================================

CREATE TABLE trustride.present_shell_session (
  session_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_code       trustride.present_shell_code_enum NOT NULL,
  user_id          UUID NOT NULL,
  device_id        UUID,
  channel_type     trustride.present_channel_type_enum NOT NULL,
  auth_session_ref UUID,
  started_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at         TIMESTAMPTZ,
  session_status   trustride.present_session_status_enum NOT NULL DEFAULT 'ACTIVE'
);
CREATE INDEX idx_present_shell_session_user ON trustride.present_shell_session (user_id);
CREATE INDEX idx_present_shell_session_shell_status ON trustride.present_shell_session (shell_code, session_status);
COMMENT ON TABLE trustride.present_shell_session IS
  'No shell registers or authenticates on its own; every session references an identity Foundation already sealed.';
ALTER TABLE trustride.present_shell_session ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_shell_session_self_read ON trustride.present_shell_session FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY present_shell_session_service_write ON trustride.present_shell_session FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.present_device_channel_registration (
  device_channel_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id            UUID NOT NULL,
  channel_type         trustride.present_channel_type_enum NOT NULL,
  registered_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_active_at       TIMESTAMPTZ,
  registration_status  TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (registration_status IN ('ACTIVE', 'REVOKED')),
  UNIQUE (device_id, channel_type)
);
ALTER TABLE trustride.present_device_channel_registration ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_device_channel_registration_platform_read ON trustride.present_device_channel_registration FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY present_device_channel_registration_service_write ON trustride.present_device_channel_registration FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.present_shell_capability_registry (
  capability_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_code                   trustride.present_shell_code_enum NOT NULL,
  command_type                 TEXT NOT NULL,
  permitted                    BOOLEAN NOT NULL DEFAULT TRUE,
  requires_delegated_authority BOOLEAN NOT NULL DEFAULT FALSE,
  created_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (shell_code, command_type)
);
COMMENT ON TABLE trustride.present_shell_capability_registry IS
  'The Surface Law''s per-shell permitted-verbs table, made executable: a command not found here as permitted=TRUE is rejected, never left to client-side discipline alone.';
ALTER TABLE trustride.present_shell_capability_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_shell_capability_registry_platform_read ON trustride.present_shell_capability_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY present_shell_capability_registry_service_write ON trustride.present_shell_capability_registry FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

INSERT INTO trustride.present_shell_capability_registry (shell_code, command_type, requires_delegated_authority) VALUES
  ('USER_HUB', 'VIEW_PROJECTION', FALSE),
  ('USER_HUB', 'RAISE_INTENT', FALSE),
  ('USER_HUB', 'ACCEPT_QUOTATION', FALSE),
  ('USER_HUB', 'TRACK_ELEMENT', FALSE),
  ('OPERATOR_APP', 'VIEW_ASSIGNMENT_PROJECTION', FALSE),
  ('OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', FALSE),
  ('OPERATOR_APP', 'CAPTURE_EVIDENCE', FALSE),
  ('ADMIN_CONSOLE', 'VIEW_REGISTER', FALSE),
  ('ADMIN_CONSOLE', 'EMIT_GOVERNANCE_SIGNAL', TRUE),
  ('SOVEREIGN_EXECUTIVE_CONSOLE', 'VIEW_WHOLE_ESTATE', FALSE),
  ('SOVEREIGN_EXECUTIVE_CONSOLE', 'RULE_ON_EXCEPTION', FALSE),
  ('SOVEREIGN_EXECUTIVE_CONSOLE', 'AMEND_REGISTER', FALSE),
  ('SOVEREIGN_EXECUTIVE_CONSOLE', 'RUN_SCENARIO', FALSE),
  ('MARKETPLACE_HUB', 'PUBLISH_OFFER', FALSE),
  ('MARKETPLACE_HUB', 'RECEIVE_ORDER_SIGNAL', FALSE),
  ('MARKETPLACE_HUB', 'SETTLE_LAWFUL_FLOW', FALSE);

CREATE TABLE trustride.present_command_capture (
  command_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_session_id     UUID NOT NULL REFERENCES trustride.present_shell_session (session_id),
  command_type         TEXT NOT NULL,
  command_payload      JSONB NOT NULL,
  captured_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  translated_signal_id UUID,
  translation_status   trustride.present_translation_status_enum NOT NULL DEFAULT 'CAPTURED',
  rejection_reason     TEXT
);
CREATE INDEX idx_present_command_capture_session ON trustride.present_command_capture (shell_session_id);
CREATE INDEX idx_present_command_capture_status ON trustride.present_command_capture (translation_status);
COMMENT ON TABLE trustride.present_command_capture IS
  'The proof: every human action passed through here before any signal existed. translated_signal_id here holds the resulting domain reference (an order_id, a signal_id) where the underlying call returns one -- not every wired command returns a UUID, so this column is best-effort evidence, not the sole proof; translation_status is.';

CREATE OR REPLACE FUNCTION trustride.fn_present_command_capability_check()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM trustride.present_shell_capability_registry r
    JOIN trustride.present_shell_session s ON s.session_id = NEW.shell_session_id
    WHERE r.shell_code = s.shell_code AND r.command_type = NEW.command_type AND r.permitted = TRUE
  ) THEN
    RAISE EXCEPTION 'present_command_capture %: command_type % is not a permitted verb for this shell (FDN-001 Sec.11.4 Surface Law)', NEW.command_id, NEW.command_type;
  END IF;
  RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_present_command_capability_check
  AFTER INSERT ON trustride.present_command_capture
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_present_command_capability_check();

ALTER TABLE trustride.present_command_capture ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_command_capture_self_read ON trustride.present_command_capture FOR SELECT TO trustride_authenticated
  USING (EXISTS (SELECT 1 FROM trustride.present_shell_session s WHERE s.session_id = present_command_capture.shell_session_id AND s.user_id = auth.uid()));
CREATE POLICY present_command_capture_service_write ON trustride.present_command_capture FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.present_projection_render (
  render_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_session_id      UUID NOT NULL REFERENCES trustride.present_shell_session (session_id),
  projection_code       TEXT NOT NULL,
  source_correlation_id UUID,
  rendered_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_present_projection_render_session ON trustride.present_projection_render (shell_session_id);
CREATE INDEX idx_present_projection_render_code ON trustride.present_projection_render (projection_code);
COMMENT ON TABLE trustride.present_projection_render IS
  'A screen that renders unregistered truth is non-conformant. Every projection_code here must resolve to a row in Foundation''s projection_registry.';
ALTER TABLE trustride.present_projection_render ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_projection_render_self_read ON trustride.present_projection_render FOR SELECT TO trustride_authenticated
  USING (EXISTS (SELECT 1 FROM trustride.present_shell_session s WHERE s.session_id = present_projection_render.shell_session_id AND s.user_id = auth.uid()));
CREATE POLICY present_projection_render_service_write ON trustride.present_projection_render FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.present_projection_cache (
  cache_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_session_id UUID NOT NULL REFERENCES trustride.present_shell_session (session_id),
  projection_code  TEXT NOT NULL,
  cached_payload   JSONB NOT NULL,
  cached_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  cache_status     trustride.present_cache_status_enum NOT NULL DEFAULT 'FRESH',
  UNIQUE (shell_session_id, projection_code)
);
COMMENT ON TABLE trustride.present_projection_cache IS
  'Distinct from the on-device offline outbox (Layer 3, AQ-002): this is what the surface shows while disconnected, never what it queues to send.';
ALTER TABLE trustride.present_projection_cache ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_projection_cache_self_read ON trustride.present_projection_cache FOR SELECT TO trustride_authenticated
  USING (EXISTS (SELECT 1 FROM trustride.present_shell_session s WHERE s.session_id = present_projection_cache.shell_session_id AND s.user_id = auth.uid()));
CREATE POLICY present_projection_cache_service_write ON trustride.present_projection_cache FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.present_heartbeat_status (
  heartbeat_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_session_id     UUID NOT NULL REFERENCES trustride.present_shell_session (session_id),
  bridge_health_status trustride.present_bridge_health_enum NOT NULL DEFAULT 'HEALTHY',
  last_heartbeat_at    TIMESTAMPTZ,
  displayed_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_present_heartbeat_status_session ON trustride.present_heartbeat_status (shell_session_id, displayed_at DESC);
COMMENT ON TABLE trustride.present_heartbeat_status IS
  'Sourced from Orchestration''s own capacity telemetry as a lawful projection; when absent, the surface says so plainly and continues to queue.';
ALTER TABLE trustride.present_heartbeat_status ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_heartbeat_status_self_read ON trustride.present_heartbeat_status FOR SELECT TO trustride_authenticated
  USING (EXISTS (SELECT 1 FROM trustride.present_shell_session s WHERE s.session_id = present_heartbeat_status.shell_session_id AND s.user_id = auth.uid()));
CREATE POLICY present_heartbeat_status_service_write ON trustride.present_heartbeat_status FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.present_notification_inbox (
  notification_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_user_id         UUID NOT NULL,
  shell_code                trustride.present_shell_code_enum NOT NULL,
  title                     TEXT NOT NULL,
  body                      TEXT NOT NULL,
  source_signal_correlation_id UUID,
  read_status               trustride.present_read_status_enum NOT NULL DEFAULT 'UNREAD',
  delivered_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  read_at                   TIMESTAMPTZ
);
CREATE INDEX idx_present_notification_inbox_recipient ON trustride.present_notification_inbox (recipient_user_id, read_status);
COMMENT ON TABLE trustride.present_notification_inbox IS
  'The bell-icon feed inside a shell -- distinct from Foundation''s contact preferences and Integration''s external dispatch log.';
ALTER TABLE trustride.present_notification_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_notification_inbox_recipient_read ON trustride.present_notification_inbox FOR SELECT TO trustride_authenticated USING (recipient_user_id = auth.uid());
CREATE POLICY present_notification_inbox_service_write ON trustride.present_notification_inbox FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.present_locale_preference (
  locale_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL UNIQUE,
  language_code TEXT NOT NULL DEFAULT 'en',
  region_code   TEXT,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE trustride.present_locale_preference ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_locale_preference_self_read ON trustride.present_locale_preference FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY present_locale_preference_service_write ON trustride.present_locale_preference FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.present_decision_log (
  decision_log_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  command_id        UUID REFERENCES trustride.present_command_capture (command_id),
  event_type        TEXT NOT NULL,
  event_description TEXT,
  prev_hash         CHAR(64),
  immutable_hash    CHAR(64) NOT NULL,
  recorded_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_present_decision_log_command ON trustride.present_decision_log (command_id);
REVOKE UPDATE, DELETE ON trustride.present_decision_log FROM PUBLIC;
REVOKE UPDATE, DELETE ON trustride.present_decision_log FROM trustride_authenticated;
ALTER TABLE trustride.present_decision_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_decision_log_platform_read ON trustride.present_decision_log FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY present_decision_log_service_write ON trustride.present_decision_log FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.present_event_outbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG011_PRESENT',
  receiving_engine       TEXT NOT NULL,
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  signal_status               TEXT NOT NULL DEFAULT 'PENDING'
                                CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason              TEXT,
  idempotency_key                 TEXT NOT NULL UNIQUE,
  attempt_count                     INTEGER NOT NULL DEFAULT 0,
  emitted_at                         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_present_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_present_outbox_status ON trustride.present_event_outbox (signal_status);
CREATE INDEX idx_present_outbox_correlation ON trustride.present_event_outbox (correlation_id);
ALTER TABLE trustride.present_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_event_outbox_service_only ON trustride.present_event_outbox FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.present_event_inbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL,
  receiving_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG011_PRESENT',
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  payload_out                JSONB,
  signal_status                TEXT NOT NULL DEFAULT 'RECEIVED'
                                 CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason               TEXT,
  idempotency_key                  TEXT NOT NULL UNIQUE,
  emitted_at                         TIMESTAMPTZ NOT NULL DEFAULT now(),
  received_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at                          TIMESTAMPTZ,
  CONSTRAINT chk_present_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_present_inbox_status ON trustride.present_event_inbox (signal_status);
CREATE INDEX idx_present_inbox_correlation ON trustride.present_event_inbox (correlation_id);
ALTER TABLE trustride.present_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_event_inbox_service_only ON trustride.present_event_inbox FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

-- ============================================================================
-- PHASE 4 -- SEED FOUNDATION'S PROJECTION_REGISTRY (owned by Foundation,
-- was empty -- Engine 11's own CC-10 conformance check is unenforceable
-- without at least one real registered projection)
-- ============================================================================
INSERT INTO trustride.projection_registry (projection_code, shell, source_tables, refresh_mode, is_authoritative) VALUES
  ('USER_ORDER_STATUS_CARD', 'USER_HUB', jsonb_build_array('business_order'), 'ON_SIGNAL', false)
ON CONFLICT (projection_code) DO NOTHING;

-- ============================================================================
-- PHASE 5 -- REAL GAP FIX: requester_user_id in ORDER_PLACED/ORDER_SETTLED
-- (unchanged signatures, safe CREATE OR REPLACE -- see file header)
-- ============================================================================
CREATE OR REPLACE FUNCTION trustride.fn_business_order_place(
  p_requester_user_id UUID, p_user_type_domain trustride.business_user_type_domain_enum, p_service_code TEXT, p_macro_domain TEXT,
  p_order_lines JSONB, p_order_root_type trustride.business_order_root_enum DEFAULT 'SERVICE_ORDER', p_jurisdiction TEXT DEFAULT 'KISUMU_COUNTY',
  p_correlation_id UUID DEFAULT gen_random_uuid()
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_order_id UUID;
  v_order_code TEXT;
  v_line JSONB;
  v_seq SMALLINT := 1;
BEGIN
  IF jsonb_array_length(p_order_lines) < 1 THEN
    RAISE EXCEPTION 'fn_business_order_place: at least one order line is required (Article 16 -- an Order without scope is constitutionally void)';
  END IF;

  v_order_code := trustride.fn_sequence_next('TRS026-ORDER');

  INSERT INTO trustride.business_order (order_code, order_root_type, requester_user_id, user_type_domain, service_id, service_code, macro_domain, correlation_id)
  VALUES (v_order_code, p_order_root_type, p_requester_user_id, p_user_type_domain, gen_random_uuid(), p_service_code, p_macro_domain, p_correlation_id)
  RETURNING order_id INTO v_order_id;

  FOR v_line IN SELECT * FROM jsonb_array_elements(p_order_lines) LOOP
    INSERT INTO trustride.business_order_line (order_id, line_sequence, line_description, quantity, scope_detail)
    VALUES (v_order_id, v_seq, v_line->>'line_description', coalesce((v_line->>'quantity')::numeric, 1), coalesce(v_line->'scope_detail', '{}'::jsonb));
    v_seq := v_seq + 1;
  END LOOP;

  IF p_order_root_type = 'SERVICE_ORDER' THEN
    INSERT INTO trustride.business_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (p_correlation_id, 'TRS026_ENG003_SERV', 'SERVICE_LOOKUP_REQUESTED',
      jsonb_build_object('service_code', p_service_code, 'jurisdiction', p_jurisdiction, 'order_id', v_order_id),
      'SERVICE_LOOKUP_REQUESTED:' || v_order_id::text);
  ELSE
    INSERT INTO trustride.business_partnership_response (order_id, response_due_at)
    VALUES (v_order_id, now() + interval '72 hours');
  END IF;

  INSERT INTO trustride.business_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG011_PRESENT', 'ORDER_PLACED',
    jsonb_build_object('order_id', v_order_id, 'order_code', v_order_code, 'service_code', p_service_code, 'placed_at', now(), 'requester_user_id', p_requester_user_id),
    'ORDER_PLACED:' || v_order_id::text);

  PERFORM trustride.fn_audit_log_append('business_order', v_order_id, 'ORDER_PLACED', p_requester_user_id,
    'USER', p_user_type_domain::text, NULL, NULL, jsonb_build_object('order_code', v_order_code, 'order_root_type', p_order_root_type));

  RETURN v_order_id;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_payment_settled_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_order_id UUID;
  v_receipt_code TEXT;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_business_payment_settled_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  v_order_id := (v_payload->>'order_id')::uuid;
  IF v_order_id IS NULL THEN
    SELECT order_id INTO v_order_id FROM trustride.business_order WHERE quote_id = (v_payload->>'quote_id')::uuid;
  END IF;
  IF v_order_id IS NULL THEN
    UPDATE trustride.business_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'NO_ORDER_FOR_QUOTE_ID', accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END IF;
  v_receipt_code := trustride.fn_sequence_next('TRS026-RECEIPT');

  UPDATE trustride.business_settlement
  SET payment_status = 'RECEIPT_GENERATED', settled_at = coalesce(settled_at, now()), ledger_posted_at = now(),
      receipt_code = v_receipt_code, receipt_generated_at = now()
  WHERE order_id = v_order_id AND payment_status <> 'RECEIPT_GENERATED';

  IF NOT FOUND THEN
    UPDATE trustride.business_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'NO_OPEN_SETTLEMENT_OR_ALREADY_RECEIPTED', accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END IF;

  UPDATE trustride.business_order SET status = 'SETTLED' WHERE order_id = v_order_id;

  INSERT INTO trustride.business_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  SELECT correlation_id, 'TRS026_ENG011_PRESENT', 'ORDER_SETTLED',
    jsonb_build_object('order_id', v_order_id, 'computed_total_fare_kes', (SELECT computed_total_fare_kes FROM trustride.business_settlement WHERE order_id = v_order_id),
      'receipt_code', v_receipt_code, 'requester_user_id', business_order.requester_user_id),
    'ORDER_SETTLED:' || v_order_id::text
  FROM trustride.business_order WHERE order_id = v_order_id;

  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

-- ============================================================================
-- PHASE 6 -- CROSS-ENGINE READ ACCESS (Orchestration's capacity telemetry,
-- for the heartbeat; Business's own order table, "by value" identity/status
-- resolution matching CC-04's own cited pattern for Foundation-adjacent reads)
-- ============================================================================
GRANT SELECT ON trustride.orch_capacity_snapshot TO trs026_eng011_present_service;
CREATE POLICY orch_capacity_snapshot_present_read ON trustride.orch_capacity_snapshot FOR SELECT TO trs026_eng011_present_service USING (true);
GRANT SELECT ON trustride.business_order TO trs026_eng011_present_service;
CREATE POLICY business_order_present_read ON trustride.business_order FOR SELECT TO trs026_eng011_present_service USING (true);
GRANT SELECT ON trustride.model_scenario_run TO trs026_eng011_present_service;

-- ============================================================================
-- PHASE 7 -- SESSION LIFECYCLE (necessary completion -- the blueprint gives
-- the table, not a writer function; matches the pattern already used for
-- every other engine's own "_open" functions this session)
-- ============================================================================
CREATE FUNCTION trustride.fn_present_shell_session_open(
  p_shell_code trustride.present_shell_code_enum, p_user_id UUID, p_channel_type trustride.present_channel_type_enum,
  p_device_id UUID DEFAULT NULL, p_auth_session_ref UUID DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
DECLARE
  v_session_id UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM trustride.shell_registry WHERE shell_code = p_shell_code::text AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'fn_present_shell_session_open: shell % is not a registered ACTIVE shell', p_shell_code;
  END IF;

  INSERT INTO trustride.present_shell_session (shell_code, user_id, device_id, channel_type, auth_session_ref)
  VALUES (p_shell_code, p_user_id, p_device_id, p_channel_type, p_auth_session_ref)
  RETURNING session_id INTO v_session_id;

  RETURN v_session_id;
END;
$$;

CREATE FUNCTION trustride.fn_present_shell_session_end(p_session_id UUID)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
  UPDATE trustride.present_shell_session SET session_status = 'ENDED', ended_at = now() WHERE session_id = p_session_id AND session_status = 'ACTIVE';
$$;

-- ============================================================================
-- PHASE 8 -- COMMAND CAPTURE [Trace: Sec.2.4, Law C-III-1]
-- ============================================================================
CREATE FUNCTION trustride.fn_present_capture_command(p_shell_session_id UUID, p_command_type TEXT, p_command_payload JSONB)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_session RECORD;
  v_command_id UUID;
  v_translated_signal_id UUID;
  v_translation_status trustride.present_translation_status_enum := 'CAPTURED';
  v_rejection_reason TEXT;
  v_requires_authority BOOLEAN;
  v_prev_hash CHAR(64);
  v_new_hash CHAR(64);
BEGIN
  SELECT * INTO v_session FROM trustride.present_shell_session WHERE session_id = p_shell_session_id AND session_status = 'ACTIVE';
  IF v_session IS NULL THEN
    RAISE EXCEPTION 'fn_present_capture_command: no ACTIVE session %', p_shell_session_id;
  END IF;

  SELECT requires_delegated_authority INTO v_requires_authority FROM trustride.present_shell_capability_registry
  WHERE shell_code = v_session.shell_code AND command_type = p_command_type AND permitted = TRUE;

  IF v_requires_authority IS NULL THEN
    RAISE EXCEPTION 'fn_present_capture_command: command_type % is not a permitted verb for shell % (FDN-001 Sec.11.4 Surface Law)', p_command_type, v_session.shell_code;
  END IF;

  IF v_requires_authority AND NOT (trustride.fn_am_i_governor() OR trustride.fn_am_i_administrator()) THEN
    RAISE EXCEPTION 'fn_present_capture_command: command_type % requires delegated authority; caller holds neither Governor nor Administrator role', p_command_type;
  END IF;

  INSERT INTO trustride.present_command_capture (shell_session_id, command_type, command_payload)
  VALUES (p_shell_session_id, p_command_type, p_command_payload)
  RETURNING command_id INTO v_command_id;

  BEGIN
    CASE p_command_type
      WHEN 'RAISE_INTENT' THEN
        v_translated_signal_id := trustride.fn_business_order_place(
          v_session.user_id,
          (p_command_payload->>'user_type_domain')::trustride.business_user_type_domain_enum,
          p_command_payload->>'service_code', p_command_payload->>'macro_domain', p_command_payload->'order_lines',
          coalesce((p_command_payload->>'order_root_type')::trustride.business_order_root_enum, 'SERVICE_ORDER'),
          coalesce(p_command_payload->>'jurisdiction', 'KISUMU_COUNTY'), v_command_id);
        v_translation_status := 'TRANSLATED';

      WHEN 'ACCEPT_QUOTATION' THEN
        PERFORM trustride.fn_cost_quote_lock((p_command_payload->>'quote_id')::uuid, v_command_id);
        v_translation_status := 'TRANSLATED';

      WHEN 'TRACK_ELEMENT' THEN
        PERFORM trustride.fn_business_tracking_location_update(
          (p_command_payload->>'job_id')::uuid, (p_command_payload->>'lat')::numeric,
          (p_command_payload->>'lon')::numeric, (p_command_payload->>'eta')::timestamptz);
        v_translation_status := 'TRANSLATED';

      WHEN 'EMIT_PROGRESS_SIGNAL' THEN
        PERFORM trustride.fn_business_job_progress_advance((p_command_payload->>'job_id')::uuid, v_session.user_id, v_command_id);
        v_translation_status := 'TRANSLATED';

      WHEN 'RUN_SCENARIO' THEN
        INSERT INTO trustride.present_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
        VALUES (v_command_id, 'TRS026_ENG010_MODEL', 'SCENARIO_RUN_REQUESTED',
          jsonb_build_object('scenario_code', p_command_payload->>'scenario_code', 'requested_by', v_session.user_id,
            'run_label', p_command_payload->>'run_label', 'parameters', coalesce(p_command_payload->'parameters', '[]'::jsonb)),
          'SCENARIO_RUN_REQUESTED:' || v_command_id::text)
        RETURNING signal_id INTO v_translated_signal_id;
        v_translation_status := 'TRANSLATED';

      ELSE
        NULL; -- registered verb, no live domain handler in this rebuild yet -- see file header
    END CASE;
  EXCEPTION WHEN OTHERS THEN
    v_translation_status := 'REJECTED';
    v_rejection_reason := SQLERRM;
  END;

  UPDATE trustride.present_command_capture
  SET translated_signal_id = v_translated_signal_id, translation_status = v_translation_status, rejection_reason = v_rejection_reason
  WHERE command_id = v_command_id;

  SELECT immutable_hash INTO v_prev_hash FROM trustride.present_decision_log ORDER BY recorded_at DESC LIMIT 1;
  v_new_hash := encode(digest(coalesce(v_prev_hash, '') || v_command_id::text || v_translation_status::text, 'sha256'), 'hex');
  INSERT INTO trustride.present_decision_log (command_id, event_type, event_description, prev_hash, immutable_hash)
  VALUES (v_command_id, 'COMMAND_CAPTURED', format('%s on shell %s -> %s', p_command_type, v_session.shell_code, v_translation_status), v_prev_hash, v_new_hash);

  RETURN v_command_id;
END;
$$;

-- ============================================================================
-- PHASE 9 -- PROJECTION RENDERING + HEARTBEAT [Trace: Sec.2.5-2.7]
-- ============================================================================
CREATE FUNCTION trustride.fn_present_render_projection(p_shell_session_id UUID, p_projection_code TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
DECLARE
  v_session RECORD;
  v_registry RECORD;
  v_payload JSONB;
BEGIN
  SELECT * INTO v_session FROM trustride.present_shell_session WHERE session_id = p_shell_session_id AND session_status = 'ACTIVE';
  IF v_session IS NULL THEN
    RAISE EXCEPTION 'fn_present_render_projection: no ACTIVE session %', p_shell_session_id;
  END IF;

  SELECT * INTO v_registry FROM trustride.projection_registry WHERE projection_code = p_projection_code;
  IF v_registry IS NULL THEN
    RAISE EXCEPTION 'fn_present_render_projection: % is not a registered projection (FDN-001 Sec.11.4 C-III-3)', p_projection_code;
  END IF;

  IF p_projection_code = 'USER_ORDER_STATUS_CARD' THEN
    SELECT jsonb_build_object('order_code', order_code, 'order_stage', order_stage, 'status', status)
    INTO v_payload FROM trustride.business_order WHERE requester_user_id = v_session.user_id ORDER BY placed_at DESC LIMIT 1;
  END IF;
  v_payload := coalesce(v_payload, '{}'::jsonb);

  INSERT INTO trustride.present_projection_render (shell_session_id, projection_code) VALUES (p_shell_session_id, p_projection_code);
  INSERT INTO trustride.present_projection_cache (shell_session_id, projection_code, cached_payload, cache_status)
  VALUES (p_shell_session_id, p_projection_code, v_payload, 'FRESH')
  ON CONFLICT (shell_session_id, projection_code) DO UPDATE SET cached_payload = EXCLUDED.cached_payload, cached_at = now(), cache_status = 'FRESH';

  RETURN v_payload;
END;
$$;

CREATE FUNCTION trustride.fn_present_heartbeat_sync(p_shell_session_id UUID)
RETURNS trustride.present_bridge_health_enum LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
DECLARE
  v_snapshot RECORD;
  v_health trustride.present_bridge_health_enum;
BEGIN
  SELECT * INTO v_snapshot FROM trustride.orch_capacity_snapshot ORDER BY snapshot_at DESC LIMIT 1;
  v_health := (CASE
    WHEN v_snapshot IS NULL THEN 'OFFLINE'
    WHEN v_snapshot.runtime_health_status = 'HEALTHY' THEN 'HEALTHY'
    WHEN v_snapshot.runtime_health_status = 'DEGRADED' THEN 'DEGRADED'
    ELSE 'OFFLINE'
  END)::trustride.present_bridge_health_enum;

  INSERT INTO trustride.present_heartbeat_status (shell_session_id, bridge_health_status, last_heartbeat_at)
  VALUES (p_shell_session_id, v_health, v_snapshot.snapshot_at);

  RETURN v_health;
END;
$$;

-- ============================================================================
-- PHASE 10 -- INBOUND SIGNALS [Trace: Sec.4.1]
-- ============================================================================
CREATE FUNCTION trustride.fn_present_inbox_process(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp AS $$
DECLARE
  v_signal_type TEXT;
  v_payload JSONB;
  v_correlation_id UUID;
  v_result TEXT := 'ACCEPTED';
BEGIN
  SELECT signal_type, payload_in, correlation_id INTO v_signal_type, v_payload, v_correlation_id
  FROM trustride.present_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_signal_type IS NULL THEN
    RAISE EXCEPTION 'fn_present_inbox_process: no RECEIVED signal %', p_signal_id;
  END IF;

  CASE v_signal_type
    WHEN 'ORDER_PLACED' THEN
      INSERT INTO trustride.present_notification_inbox (recipient_user_id, shell_code, title, body, source_signal_correlation_id)
      VALUES ((v_payload->>'requester_user_id')::uuid, 'USER_HUB', 'Order placed', format('Your order %s has been placed.', v_payload->>'order_code'), v_correlation_id);

    WHEN 'ORDER_SETTLED' THEN
      INSERT INTO trustride.present_notification_inbox (recipient_user_id, shell_code, title, body, source_signal_correlation_id)
      VALUES ((v_payload->>'requester_user_id')::uuid, 'USER_HUB', 'Payment settled',
        format('Payment of %s KES settled, receipt %s.', v_payload->>'computed_total_fare_kes', v_payload->>'receipt_code'), v_correlation_id);

    WHEN 'SERVICE_CATALOGUE_UPDATED' THEN
      NULL; -- catalogue projections render fresh on next fn_present_render_projection call; no per-user notification needed

    WHEN 'ADVISORY_RECOMMENDATION_PUBLISHED' THEN
      NULL; -- no recipient_user_id is carried in this payload (Sec.4.2); resolving "all Governors"
            -- would require reading Foundation's role_assignment/role_definition directly, an
            -- ungranted cross-engine read. Accepted as evidence the signal was received; a real
            -- Sovereign Executive Console client renders it as an aggregate feed, not a
            -- per-user notification, once one exists.

    WHEN 'ADVISORY_ANOMALY_FLAGGED' THEN
      NULL; -- same reasoning as ADVISORY_RECOMMENDATION_PUBLISHED above.

    WHEN 'SCENARIO_RUN_COMPLETED' THEN
      INSERT INTO trustride.present_notification_inbox (recipient_user_id, shell_code, title, body, source_signal_correlation_id)
      SELECT msr.requested_by, 'SOVEREIGN_EXECUTIVE_CONSOLE', 'Scenario run finished',
        format('Scenario %s finished with status %s.', v_payload->>'scenario_code', v_payload->>'run_status'), msr.correlation_id
      FROM trustride.model_scenario_run msr WHERE msr.run_id = (v_payload->>'run_id')::uuid;

    ELSE
      UPDATE trustride.present_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'UNREGISTERED_SIGNAL_TYPE:' || v_signal_type WHERE signal_id = p_signal_id;
      v_result := 'REJECTED';
  END CASE;

  IF v_result = 'ACCEPTED' THEN
    UPDATE trustride.present_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  END IF;

  RETURN v_result;
END;
$$;

-- ============================================================================
-- PHASE 11 -- EXTEND ORCHESTRATION (preserve ENG010_MODEL's branch just
-- added; add ENG011_PRESENT for the first time)
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
      WHEN 'TRS026_ENG008_COORD' THEN 'coord_event_inbox'
      WHEN 'TRS026_ENG009_AIADV' THEN 'advisory_event_inbox'
      WHEN 'TRS026_ENG010_MODEL' THEN 'model_event_inbox'
      WHEN 'TRS026_ENG011_PRESENT' THEN 'present_event_inbox'
      ELSE NULL
    END,
    rr.target_engine || ':DEFAULT',
    rr.route_id::text, 'ACTIVE', now()
  FROM trustride.routing_rule rr
  WHERE rr.active = TRUE
    AND CASE rr.target_engine
      WHEN 'TRS026_ENG001_FDN' THEN TRUE WHEN 'TRS026_ENG002_RESC' THEN TRUE WHEN 'TRS026_ENG003_SERV' THEN TRUE
      WHEN 'TRS026_ENG004_BUS' THEN TRUE WHEN 'TRS026_ENG005_COST' THEN TRUE WHEN 'TRS026_ENG006_INTG' THEN TRUE
      WHEN 'TRS026_ENG008_COORD' THEN TRUE WHEN 'TRS026_ENG009_AIADV' THEN TRUE WHEN 'TRS026_ENG010_MODEL' THEN TRUE
      WHEN 'TRS026_ENG011_PRESENT' THEN TRUE ELSE FALSE
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
          WHEN 'TRS026_ENG008_COORD' THEN PERFORM trustride.fn_coord_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG009_AIADV' THEN PERFORM trustride.fn_advisory_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG010_MODEL' THEN PERFORM trustride.fn_model_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG011_PRESENT' THEN PERFORM trustride.fn_present_inbox_process(v_row.signal_id);
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
-- PHASE 12 -- GRANTS
-- ============================================================================
GRANT USAGE ON SCHEMA trustride TO trs026_eng011_present_service;

GRANT EXECUTE ON FUNCTION trustride.fn_present_shell_session_open(trustride.present_shell_code_enum, UUID, trustride.present_channel_type_enum, UUID, UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_shell_session_end(UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_capture_command(UUID, TEXT, JSONB) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_render_projection(UUID, TEXT) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_heartbeat_sync(UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_inbox_process(UUID) TO trs026_eng011_present_service, trs026_eng007_orch_service;

-- ============================================================================
-- PHASE 13 -- ROUTING & OUTBOX REGISTRATION
-- ============================================================================
INSERT INTO trustride.orch_outbox_registry (engine_code, outbox_table_name) VALUES ('TRS026_ENG011_PRESENT', 'present_event_outbox');

INSERT INTO trustride.routing_rule (event_type, source_engine, target_engine, route_priority) VALUES
  ('ORDER_PLACED', 'TRS026_ENG004_BUS', 'TRS026_ENG011_PRESENT', 0),
  ('ORDER_SETTLED', 'TRS026_ENG004_BUS', 'TRS026_ENG011_PRESENT', 0),
  ('SERVICE_CATALOGUE_UPDATED', 'TRS026_ENG003_SERV', 'TRS026_ENG011_PRESENT', 0),
  ('ADVISORY_RECOMMENDATION_PUBLISHED', 'TRS026_ENG009_AIADV', 'TRS026_ENG011_PRESENT', 0),
  ('ADVISORY_ANOMALY_FLAGGED', 'TRS026_ENG009_AIADV', 'TRS026_ENG011_PRESENT', 0),
  ('SCENARIO_RUN_REQUESTED', 'TRS026_ENG011_PRESENT', 'TRS026_ENG010_MODEL', 0),
  ('SCENARIO_RUN_COMPLETED', 'TRS026_ENG010_MODEL', 'TRS026_ENG011_PRESENT', 0);

SELECT trustride.fn_orch_destination_cache_sync();

-- ============================================================================
-- PHASE 14 -- ENGINE REGISTRY
-- ============================================================================
UPDATE trustride.engine_registry SET status = 'INSTALLED', engine_version = '1.0.0' WHERE engine_code = 'TRS026_ENG011_PRESENT';

-- ============================================================================
-- PHASE 15 -- VALIDATION
-- ============================================================================
DO $$
DECLARE
  v_table_count INTEGER;
  v_capability_count INTEGER;
  v_projection_count INTEGER;
  v_status TEXT;
BEGIN
  SELECT count(*) INTO v_table_count FROM information_schema.tables WHERE table_schema = 'trustride' AND table_name LIKE 'present_%';
  IF v_table_count <> 12 THEN
    RAISE EXCEPTION 'ENGINE 11 VALIDATION FAILED: expected 12 present_* tables, found %', v_table_count;
  END IF;

  SELECT count(*) INTO v_capability_count FROM trustride.present_shell_capability_registry;
  IF v_capability_count <> 16 THEN
    RAISE EXCEPTION 'ENGINE 11 VALIDATION FAILED: expected 16 shell capability rows (15 blueprint + 1 RUN_SCENARIO completion), found %', v_capability_count;
  END IF;

  SELECT count(*) INTO v_projection_count FROM trustride.projection_registry WHERE projection_code = 'USER_ORDER_STATUS_CARD';
  IF v_projection_count <> 1 THEN
    RAISE EXCEPTION 'ENGINE 11 VALIDATION FAILED: USER_ORDER_STATUS_CARD projection not seeded';
  END IF;

  SELECT status INTO v_status FROM trustride.engine_registry WHERE engine_code = 'TRS026_ENG011_PRESENT';
  IF v_status <> 'INSTALLED' THEN
    RAISE EXCEPTION 'ENGINE 11 VALIDATION FAILED: engine_registry status is %, expected INSTALLED', v_status;
  END IF;

  RAISE NOTICE 'ENGINE 11 (PRESENTATION) INSTALLATION VALIDATED: 12 tables, 16 capability rows, USER_ORDER_STATUS_CARD projection seeded, engine_registry INSTALLED. ALL ELEVEN CONSTITUTIONAL ENGINES NOW HAVE REAL SCHEMA.';
END;
$$;
