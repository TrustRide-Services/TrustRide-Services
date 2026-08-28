-- ============================================================================
-- ENGINE 11 (PRESENTATION) v2.0.0 -- TWO-SHELL + SUB-SHELL ARCHITECTURE
-- [Trace: TRS026-ENG011-PRESENT-001 v2.0.0, ADOPTED FOR IMPLEMENTATION]
--
-- Supersedes v1.0.0's flat five-shell model (USER_HUB, OPERATOR_APP,
-- ADMIN_CONSOLE, SOVEREIGN_EXECUTIVE_CONSOLE, MARKETPLACE_HUB) with exactly
-- two sovereign top-shells, each owning a fixed set of sub-shells:
--   USER_HUB (external)         -> CUSTOMER_APP, PARTNER_APP, GOVERNOR_APP, INTERMEDIARY_APP
--   TRS_OPERATOR_HUB (internal) -> TRUSTRIDE_OPERATOR, TRUSTRIDE_ADMIN, TRUSTRIDE_EXECUTIVE_CONSOLE
--
-- This is a clean rebuild, not an in-place column migration: trustride-stagging
-- carries zero real users (auth.users confirmed empty) and zero real
-- present_* rows, so there is no data to preserve. Every present_* object is
-- dropped and recreated against the new shape rather than ALTERed piecemeal.
--
-- Sub-shell -> business_user_type_domain_enum mapping (Engine 4 already
-- defines CUSTOMER, PARTNER, OPERATOR, INTERMEDIARY, GOVERNOR -- this
-- migration does not invent new domains, it aligns Presentation's surface
-- taxonomy to a domain taxonomy Business already had):
--   CUSTOMER_APP <-> CUSTOMER   PARTNER_APP <-> PARTNER   GOVERNOR_APP <-> GOVERNOR
--   INTERMEDIARY_APP <-> INTERMEDIARY   TRUSTRIDE_OPERATOR <-> OPERATOR (now internal-only)
-- TRUSTRIDE_ADMIN / TRUSTRIDE_EXECUTIVE_CONSOLE have no business_user_type_domain
-- counterpart -- they are role-gated (fn_am_i_governor/fn_am_i_administrator),
-- not actor-type-gated, consistent with how ADMIN_CONSOLE/SOVEREIGN_EXECUTIVE_CONSOLE
-- already worked under v1.0.0.
-- ============================================================================

-- ============================================================================
-- PHASE 0 -- TEAR DOWN v1.0.0
-- ============================================================================
DROP FUNCTION IF EXISTS trustride.fn_present_inbox_process(UUID);
DROP FUNCTION IF EXISTS trustride.fn_present_heartbeat_sync(UUID);
DROP FUNCTION IF EXISTS trustride.fn_present_render_projection(UUID, TEXT);
DROP FUNCTION IF EXISTS trustride.fn_present_capture_command(UUID, TEXT, JSONB);
DROP FUNCTION IF EXISTS trustride.fn_present_shell_session_end(UUID);
DROP FUNCTION IF EXISTS trustride.fn_present_shell_session_open(trustride.present_shell_code_enum, UUID, trustride.present_channel_type_enum, UUID, UUID);

DROP TABLE IF EXISTS trustride.present_event_inbox;
DROP TABLE IF EXISTS trustride.present_event_outbox;
DROP TABLE IF EXISTS trustride.present_decision_log;
DROP TABLE IF EXISTS trustride.present_locale_preference;
DROP TABLE IF EXISTS trustride.present_notification_inbox;
DROP TABLE IF EXISTS trustride.present_heartbeat_status;
DROP TABLE IF EXISTS trustride.present_projection_cache;
DROP TABLE IF EXISTS trustride.present_projection_render;
DROP TABLE IF EXISTS trustride.present_command_capture;
DROP TABLE IF EXISTS trustride.present_shell_capability_registry;
DROP TABLE IF EXISTS trustride.present_device_channel_registration;
DROP TABLE IF EXISTS trustride.present_shell_session;

-- Table drops above cascade away trg_present_command_capability_check; the
-- function itself outlives its trigger and must be dropped separately.
DROP FUNCTION IF EXISTS trustride.fn_present_command_capability_check();

DROP TYPE IF EXISTS trustride.present_shell_code_enum;

-- ============================================================================
-- PHASE 1 -- NEW ENUMS [Trace: Sec.1.2, Sec.2.0]
-- ============================================================================
CREATE TYPE trustride.present_top_shell_enum AS ENUM ('USER_HUB', 'TRS_OPERATOR_HUB');

CREATE TYPE trustride.present_sub_shell_enum AS ENUM (
  'CUSTOMER_APP', 'PARTNER_APP', 'GOVERNOR_APP', 'INTERMEDIARY_APP',
  'TRUSTRIDE_OPERATOR', 'TRUSTRIDE_ADMIN', 'TRUSTRIDE_EXECUTIVE_CONSOLE'
);

-- present_channel_type_enum, present_session_status_enum,
-- present_translation_status_enum, present_cache_status_enum,
-- present_bridge_health_enum, present_read_status_enum are unchanged from
-- v1.0.0 and are not touched by this migration.

-- ============================================================================
-- PHASE 2 -- TABLES [Trace: Sec.2.1-2.11]
-- ============================================================================

CREATE TABLE trustride.present_shell_session (
  session_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  top_shell        trustride.present_top_shell_enum NOT NULL,
  sub_shell        trustride.present_sub_shell_enum NOT NULL,
  user_id          UUID NOT NULL,
  device_id        UUID,
  channel_type     trustride.present_channel_type_enum NOT NULL,
  auth_session_ref UUID,
  started_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at         TIMESTAMPTZ,
  session_status   trustride.present_session_status_enum NOT NULL DEFAULT 'ACTIVE',
  CONSTRAINT chk_sub_shell_ownership CHECK (
    (top_shell = 'USER_HUB' AND sub_shell IN ('CUSTOMER_APP', 'PARTNER_APP', 'GOVERNOR_APP', 'INTERMEDIARY_APP'))
    OR
    (top_shell = 'TRS_OPERATOR_HUB' AND sub_shell IN ('TRUSTRIDE_OPERATOR', 'TRUSTRIDE_ADMIN', 'TRUSTRIDE_EXECUTIVE_CONSOLE'))
  )
);
CREATE INDEX idx_present_shell_session_user ON trustride.present_shell_session (user_id);
CREATE INDEX idx_present_shell_session_shell_status ON trustride.present_shell_session (top_shell, sub_shell, session_status);
COMMENT ON TABLE trustride.present_shell_session IS
  '[Trace: FDN-001 Sec.11.4] No shell registers or authenticates on its own; every session references an identity Foundation already sealed and is bound to exactly one top-shell and one sub-shell.';
ALTER TABLE trustride.present_shell_session ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_shell_session_self_read ON trustride.present_shell_session FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY present_shell_session_service_write ON trustride.present_shell_session FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.present_device_channel_registration (
  device_channel_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id           UUID NOT NULL,
  channel_type        trustride.present_channel_type_enum NOT NULL,
  registered_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_active_at       TIMESTAMPTZ,
  registration_status  TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (registration_status IN ('ACTIVE', 'REVOKED')),
  UNIQUE (device_id, channel_type)
);
ALTER TABLE trustride.present_device_channel_registration ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_device_channel_registration_platform_read ON trustride.present_device_channel_registration FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY present_device_channel_registration_service_write ON trustride.present_device_channel_registration FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.present_shell_capability_registry (
  capability_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  top_shell                     trustride.present_top_shell_enum NOT NULL,
  sub_shell                     trustride.present_sub_shell_enum NOT NULL,
  command_type                  TEXT NOT NULL,
  permitted                     BOOLEAN NOT NULL DEFAULT TRUE,
  requires_delegated_authority  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at                    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (sub_shell, command_type)
);
COMMENT ON TABLE trustride.present_shell_capability_registry IS
  '[Trace: FDN-001 Sec.11.4] The Surface Law''s per-sub-shell permitted-verbs table, made executable: a command not found here as permitted=TRUE is rejected at command capture.';
ALTER TABLE trustride.present_shell_capability_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_shell_capability_registry_platform_read ON trustride.present_shell_capability_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY present_shell_capability_registry_service_write ON trustride.present_shell_capability_registry FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

-- Seed: a first-pass verb mapping carried over from v1.0.0's proven registry
-- (USER_HUB's four verbs -> CUSTOMER_APP, mirrored onto PARTNER_APP since a
-- Partner also raises intents/accepts quotations/tracks fulfillment;
-- OPERATOR_APP's verbs -> TRUSTRIDE_OPERATOR; ADMIN_CONSOLE's verbs ->
-- TRUSTRIDE_ADMIN; SOVEREIGN_EXECUTIVE_CONSOLE's verbs -> TRUSTRIDE_EXECUTIVE_CONSOLE;
-- MARKETPLACE_HUB's verbs -> INTERMEDIARY_APP). GOVERNOR_APP is new: its
-- verbs are drawn from what fn_am_i_governor() already gates platform-wide
-- (audit_log, exception_record, regulatory_contact_register, security_event
-- all read-gate on this role) -- VIEW_REGISTER for that broad oversight read,
-- RULE_ON_EXCEPTION matching exception_record directly, EMIT_GOVERNANCE_SIGNAL
-- (delegated) matching the same verb ADMIN_CONSOLE already carried.
INSERT INTO trustride.present_shell_capability_registry (top_shell, sub_shell, command_type, requires_delegated_authority) VALUES
  ('USER_HUB', 'CUSTOMER_APP', 'VIEW_PROJECTION', FALSE),
  ('USER_HUB', 'CUSTOMER_APP', 'RAISE_INTENT', FALSE),
  ('USER_HUB', 'CUSTOMER_APP', 'ACCEPT_QUOTATION', FALSE),
  ('USER_HUB', 'CUSTOMER_APP', 'TRACK_ELEMENT', FALSE),
  ('USER_HUB', 'PARTNER_APP', 'VIEW_PROJECTION', FALSE),
  ('USER_HUB', 'PARTNER_APP', 'RAISE_INTENT', FALSE),
  ('USER_HUB', 'PARTNER_APP', 'ACCEPT_QUOTATION', FALSE),
  ('USER_HUB', 'PARTNER_APP', 'TRACK_ELEMENT', FALSE),
  ('USER_HUB', 'GOVERNOR_APP', 'VIEW_REGISTER', FALSE),
  ('USER_HUB', 'GOVERNOR_APP', 'RULE_ON_EXCEPTION', FALSE),
  ('USER_HUB', 'GOVERNOR_APP', 'EMIT_GOVERNANCE_SIGNAL', TRUE),
  ('USER_HUB', 'INTERMEDIARY_APP', 'VIEW_PROJECTION', FALSE),
  ('USER_HUB', 'INTERMEDIARY_APP', 'PUBLISH_OFFER', FALSE),
  ('USER_HUB', 'INTERMEDIARY_APP', 'RECEIVE_ORDER_SIGNAL', FALSE),
  ('USER_HUB', 'INTERMEDIARY_APP', 'SETTLE_LAWFUL_FLOW', FALSE),
  ('TRS_OPERATOR_HUB', 'TRUSTRIDE_OPERATOR', 'VIEW_ASSIGNMENT_PROJECTION', FALSE),
  ('TRS_OPERATOR_HUB', 'TRUSTRIDE_OPERATOR', 'EMIT_PROGRESS_SIGNAL', FALSE),
  ('TRS_OPERATOR_HUB', 'TRUSTRIDE_OPERATOR', 'CAPTURE_EVIDENCE', FALSE),
  ('TRS_OPERATOR_HUB', 'TRUSTRIDE_ADMIN', 'VIEW_REGISTER', FALSE),
  ('TRS_OPERATOR_HUB', 'TRUSTRIDE_ADMIN', 'EMIT_GOVERNANCE_SIGNAL', TRUE),
  ('TRS_OPERATOR_HUB', 'TRUSTRIDE_EXECUTIVE_CONSOLE', 'VIEW_WHOLE_ESTATE', FALSE),
  ('TRS_OPERATOR_HUB', 'TRUSTRIDE_EXECUTIVE_CONSOLE', 'RULE_ON_EXCEPTION', FALSE),
  ('TRS_OPERATOR_HUB', 'TRUSTRIDE_EXECUTIVE_CONSOLE', 'AMEND_REGISTER', FALSE),
  ('TRS_OPERATOR_HUB', 'TRUSTRIDE_EXECUTIVE_CONSOLE', 'RUN_SCENARIO', FALSE);

CREATE TABLE trustride.present_command_capture (
  command_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_session_id     UUID NOT NULL REFERENCES trustride.present_shell_session (session_id),
  top_shell            trustride.present_top_shell_enum NOT NULL,
  sub_shell            trustride.present_sub_shell_enum NOT NULL,
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
  '[Trace: FDN-001 Sec.11.4 C-III-1] The proof: every human action passed through here before any signal existed. translated_signal_id holds the resulting domain reference where the underlying call returns one -- not every wired command returns a UUID, so this column is best-effort evidence, not the sole proof; translation_status is.';

CREATE OR REPLACE FUNCTION trustride.fn_present_command_capability_check()
RETURNS trigger LANGUAGE plpgsql SET search_path = trustride, pg_temp AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM trustride.present_shell_capability_registry r
    WHERE r.sub_shell = NEW.sub_shell AND r.command_type = NEW.command_type AND r.permitted = TRUE
  ) THEN
    RAISE EXCEPTION 'present_command_capture %: command_type % is not a permitted verb for sub_shell % (FDN-001 Sec.11.4 Surface Law)',
      NEW.command_id, NEW.command_type, NEW.sub_shell;
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
  '[Trace: FDN-001 Sec.11.4 C-III-3] A screen that renders unregistered truth is non-conformant. Every projection_code here must resolve to a row in Foundation''s projection_registry.';
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
  '[Trace: FDN-001 Sec.11.4 C-III-4] Sourced from Orchestration''s own capacity telemetry as a lawful projection; when absent, the surface says so plainly and continues to queue.';
ALTER TABLE trustride.present_heartbeat_status ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_heartbeat_status_self_read ON trustride.present_heartbeat_status FOR SELECT TO trustride_authenticated
  USING (EXISTS (SELECT 1 FROM trustride.present_shell_session s WHERE s.session_id = present_heartbeat_status.shell_session_id AND s.user_id = auth.uid()));
CREATE POLICY present_heartbeat_status_service_write ON trustride.present_heartbeat_status FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.present_notification_inbox (
  notification_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_user_id             UUID NOT NULL,
  top_shell                     trustride.present_top_shell_enum NOT NULL,
  sub_shell                     trustride.present_sub_shell_enum NOT NULL,
  title                         TEXT NOT NULL,
  body                          TEXT NOT NULL,
  source_signal_correlation_id  UUID,
  read_status                   trustride.present_read_status_enum NOT NULL DEFAULT 'UNREAD',
  delivered_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
  read_at                       TIMESTAMPTZ
);
CREATE INDEX idx_present_notification_inbox_recipient ON trustride.present_notification_inbox (recipient_user_id, read_status);
COMMENT ON TABLE trustride.present_notification_inbox IS
  'The bell-icon feed inside a sub-shell -- distinct from Foundation''s contact preferences and Integration''s external dispatch log.';
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
  signal_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id    UUID NOT NULL,
  causation_id      UUID,
  emitting_engine   TEXT NOT NULL DEFAULT 'TRS026_ENG011_PRESENT',
  receiving_engine  TEXT NOT NULL,
  signal_type       TEXT NOT NULL,
  payload_in        JSONB NOT NULL,
  signal_status     TEXT NOT NULL DEFAULT 'PENDING'
    CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason  TEXT,
  idempotency_key   TEXT NOT NULL UNIQUE,
  attempt_count     INTEGER NOT NULL DEFAULT 0,
  emitted_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_present_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_present_outbox_status ON trustride.present_event_outbox (signal_status);
CREATE INDEX idx_present_outbox_correlation ON trustride.present_event_outbox (correlation_id);
ALTER TABLE trustride.present_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_event_outbox_service_only ON trustride.present_event_outbox FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.present_event_inbox (
  signal_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id    UUID NOT NULL,
  causation_id      UUID,
  emitting_engine   TEXT NOT NULL,
  receiving_engine  TEXT NOT NULL DEFAULT 'TRS026_ENG011_PRESENT',
  signal_type       TEXT NOT NULL,
  payload_in        JSONB NOT NULL,
  payload_out       JSONB,
  signal_status     TEXT NOT NULL DEFAULT 'RECEIVED'
    CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason  TEXT,
  idempotency_key   TEXT NOT NULL UNIQUE,
  emitted_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  received_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at       TIMESTAMPTZ,
  CONSTRAINT chk_present_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_present_inbox_status ON trustride.present_event_inbox (signal_status);
CREATE INDEX idx_present_inbox_correlation ON trustride.present_event_inbox (correlation_id);
ALTER TABLE trustride.present_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_event_inbox_service_only ON trustride.present_event_inbox FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

-- ============================================================================
-- PHASE 3 -- FOUNDATION'S shell_registry: TWO SOVEREIGN SHELLS, NOT FIVE
-- [Trace: TBOC-v2.0.0 Art.30, as reframed by TRS026-ENG011-PRESENT-001 v2.0.0
-- Sec.1.1 -- "exactly two top-level sovereign shells". Sub-shells are an
-- Engine-11-owned taxonomy (present_sub_shell_enum + present_shell_capability_registry),
-- not individually Foundation-registered; only the two sovereign top-shells
-- are constitutional shell_registry entries.]
-- ============================================================================
DELETE FROM trustride.shell_registry;

INSERT INTO trustride.shell_registry (shell_code, shell_name, serves_user_types, isolation_class) VALUES
  ('USER_HUB',         'User Hub',           ARRAY['CUSTOMER','PARTNER','GOVERNOR','INTERMEDIARY'], 'EXTERNAL'),
  ('TRS_OPERATOR_HUB', 'TRS Operator Hub',   ARRAY['OPERATOR','ADMINISTRATOR','EXECUTIVE'],          'INTERNAL');

COMMENT ON TABLE trustride.shell_registry IS
  '[Trace: TRS026-ENG011-PRESENT-001 v2.0.0 Sec.1.1] The two constitutional sovereign top-shells -- User Hub (external) and TRS Operator Hub (internal); no third exists. Sub-shells are governed by Engine 11''s own present_shell_capability_registry.';

-- ============================================================================
-- PHASE 4 -- SESSION LIFECYCLE [Trace: Sec.1.3.1]
-- ============================================================================
CREATE FUNCTION trustride.fn_present_shell_session_open(
  p_top_shell trustride.present_top_shell_enum, p_sub_shell trustride.present_sub_shell_enum,
  p_user_id UUID, p_channel_type trustride.present_channel_type_enum,
  p_device_id UUID DEFAULT NULL, p_auth_session_ref UUID DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
DECLARE
  v_session_id UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM trustride.shell_registry WHERE shell_code = p_top_shell::text AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'fn_present_shell_session_open: top_shell % is not a registered ACTIVE shell', p_top_shell;
  END IF;

  INSERT INTO trustride.present_shell_session (top_shell, sub_shell, user_id, device_id, channel_type, auth_session_ref)
  VALUES (p_top_shell, p_sub_shell, p_user_id, p_device_id, p_channel_type, p_auth_session_ref)
  RETURNING session_id INTO v_session_id;

  RETURN v_session_id;
END;
$$;

CREATE FUNCTION trustride.fn_present_shell_session_end(p_session_id UUID)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
  UPDATE trustride.present_shell_session SET session_status = 'ENDED', ended_at = now() WHERE session_id = p_session_id AND session_status = 'ACTIVE';
$$;

-- ============================================================================
-- PHASE 5 -- SUB-SHELL RESOLUTION HELPER
-- Not named by the blueprint's DDL directly, but required by
-- fn_present_inbox_process below: a broadcast signal (ORDER_PLACED etc.)
-- carries only requester_user_id, and a notification now requires a
-- sub_shell -- resolved here from the same business_actor_registration
-- row /verify already reads, by value, matching this codebase's established
-- cross-engine "resolve by value" discipline.
-- ============================================================================
CREATE FUNCTION trustride.fn_present_sub_shell_for_user(p_user_id UUID)
RETURNS trustride.present_sub_shell_enum LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
  SELECT CASE bar.user_type_domain
    WHEN 'CUSTOMER' THEN 'CUSTOMER_APP'
    WHEN 'PARTNER' THEN 'PARTNER_APP'
    WHEN 'GOVERNOR' THEN 'GOVERNOR_APP'
    WHEN 'INTERMEDIARY' THEN 'INTERMEDIARY_APP'
    WHEN 'OPERATOR' THEN 'TRUSTRIDE_OPERATOR'
    ELSE 'CUSTOMER_APP'
  END::trustride.present_sub_shell_enum
  FROM trustride.business_actor_registration bar
  WHERE bar.user_id = p_user_id AND bar.registration_status = 'ACTIVE'
  ORDER BY bar.registered_at DESC LIMIT 1;
$$;

-- ============================================================================
-- PHASE 6 -- COMMAND CAPTURE [Trace: Sec.2.4, Law C-III-1]
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
  WHERE sub_shell = v_session.sub_shell AND command_type = p_command_type AND permitted = TRUE;

  IF v_requires_authority IS NULL THEN
    RAISE EXCEPTION 'fn_present_capture_command: command_type % is not a permitted verb for sub_shell % (FDN-001 Sec.11.4 Surface Law)', p_command_type, v_session.sub_shell;
  END IF;

  IF v_requires_authority AND NOT (trustride.fn_am_i_governor() OR trustride.fn_am_i_administrator()) THEN
    RAISE EXCEPTION 'fn_present_capture_command: command_type % requires delegated authority; caller holds neither Governor nor Administrator role', p_command_type;
  END IF;

  INSERT INTO trustride.present_command_capture (shell_session_id, top_shell, sub_shell, command_type, command_payload)
  VALUES (p_shell_session_id, v_session.top_shell, v_session.sub_shell, p_command_type, p_command_payload)
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
  VALUES (v_command_id, 'COMMAND_CAPTURED', format('%s on sub_shell %s -> %s', p_command_type, v_session.sub_shell, v_translation_status), v_prev_hash, v_new_hash);

  RETURN v_command_id;
END;
$$;

-- ============================================================================
-- PHASE 7 -- PROJECTION RENDERING + HEARTBEAT [Trace: Sec.2.5-2.7]
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
-- PHASE 8 -- INBOUND SIGNALS [Trace: Sec.4.1]
-- ============================================================================
CREATE FUNCTION trustride.fn_present_inbox_process(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp AS $$
DECLARE
  v_signal_type TEXT;
  v_payload JSONB;
  v_correlation_id UUID;
  v_result TEXT := 'ACCEPTED';
  v_recipient UUID;
  v_recipient_sub_shell trustride.present_sub_shell_enum;
BEGIN
  SELECT signal_type, payload_in, correlation_id INTO v_signal_type, v_payload, v_correlation_id
  FROM trustride.present_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_signal_type IS NULL THEN
    RAISE EXCEPTION 'fn_present_inbox_process: no RECEIVED signal %', p_signal_id;
  END IF;

  CASE v_signal_type
    WHEN 'ORDER_PLACED' THEN
      v_recipient := (v_payload->>'requester_user_id')::uuid;
      v_recipient_sub_shell := trustride.fn_present_sub_shell_for_user(v_recipient);
      INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, source_signal_correlation_id)
      VALUES (v_recipient, 'USER_HUB', v_recipient_sub_shell, 'Order placed', format('Your order %s has been placed.', v_payload->>'order_code'), v_correlation_id);

    WHEN 'ORDER_SETTLED' THEN
      v_recipient := (v_payload->>'requester_user_id')::uuid;
      v_recipient_sub_shell := trustride.fn_present_sub_shell_for_user(v_recipient);
      INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, source_signal_correlation_id)
      VALUES (v_recipient, 'USER_HUB', v_recipient_sub_shell, 'Payment settled',
        format('Payment of %s KES settled, receipt %s.', v_payload->>'computed_total_fare_kes', v_payload->>'receipt_code'), v_correlation_id);

    WHEN 'SERVICE_CATALOGUE_UPDATED' THEN
      NULL; -- catalogue projections render fresh on next fn_present_render_projection call; no per-user notification needed

    WHEN 'ADVISORY_RECOMMENDATION_PUBLISHED' THEN
      NULL; -- no recipient_user_id carried in this payload (Sec.4.2); resolving "all Governors"
            -- would require reading Foundation's role_assignment/role_definition directly, an
            -- ungranted cross-engine read. Accepted as evidence the signal was received; a real
            -- TRUSTRIDE_EXECUTIVE_CONSOLE client renders it as an aggregate feed once one exists.

    WHEN 'ADVISORY_ANOMALY_FLAGGED' THEN
      NULL; -- same reasoning as ADVISORY_RECOMMENDATION_PUBLISHED above.

    WHEN 'SCENARIO_RUN_COMPLETED' THEN
      INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, source_signal_correlation_id)
      SELECT msr.requested_by, 'TRS_OPERATOR_HUB', 'TRUSTRIDE_EXECUTIVE_CONSOLE', 'Scenario run finished',
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
-- PHASE 9 -- GRANTS (tables re-created, so re-issued; not carried over from
-- the point-in-time GRANT ... ON ALL TABLES IN SCHEMA the original Engine 1
-- migration ran)
-- ============================================================================
GRANT SELECT ON trustride.present_shell_session, trustride.present_device_channel_registration,
  trustride.present_shell_capability_registry, trustride.present_command_capture,
  trustride.present_projection_render, trustride.present_projection_cache,
  trustride.present_heartbeat_status, trustride.present_notification_inbox,
  trustride.present_locale_preference, trustride.present_decision_log
  TO trustride_authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE ON trustride.present_shell_session, trustride.present_device_channel_registration,
  trustride.present_shell_capability_registry, trustride.present_command_capture,
  trustride.present_projection_render, trustride.present_projection_cache,
  trustride.present_heartbeat_status, trustride.present_notification_inbox,
  trustride.present_locale_preference, trustride.present_decision_log,
  trustride.present_event_outbox, trustride.present_event_inbox
  TO trs026_eng011_present_service;

GRANT EXECUTE ON FUNCTION trustride.fn_present_shell_session_open(trustride.present_top_shell_enum, trustride.present_sub_shell_enum, UUID, trustride.present_channel_type_enum, UUID, UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_shell_session_end(UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_capture_command(UUID, TEXT, JSONB) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_render_projection(UUID, TEXT) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_heartbeat_sync(UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_sub_shell_for_user(UUID) TO trustride_authenticated, trs026_eng011_present_service;
GRANT EXECUTE ON FUNCTION trustride.fn_present_inbox_process(UUID) TO trs026_eng011_present_service, trs026_eng007_orch_service;

REVOKE EXECUTE ON FUNCTION trustride.fn_present_shell_session_open(trustride.present_top_shell_enum, trustride.present_sub_shell_enum, UUID, trustride.present_channel_type_enum, UUID, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_present_shell_session_end(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_present_capture_command(UUID, TEXT, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_present_render_projection(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_present_heartbeat_sync(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_present_sub_shell_for_user(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_present_inbox_process(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_present_command_capability_check() FROM PUBLIC;

-- ============================================================================
-- PHASE 10 -- ENGINE REGISTRY
-- ============================================================================
UPDATE trustride.engine_registry SET engine_version = '2.0.0' WHERE engine_code = 'TRS026_ENG011_PRESENT';

-- ============================================================================
-- PHASE 11 -- VALIDATION
-- ============================================================================
DO $$
DECLARE
  v_table_count INTEGER;
  v_capability_count INTEGER;
  v_shell_count INTEGER;
  v_version TEXT;
BEGIN
  SELECT count(*) INTO v_table_count FROM information_schema.tables WHERE table_schema = 'trustride' AND table_name LIKE 'present_%';
  IF v_table_count <> 12 THEN
    RAISE EXCEPTION 'ENGINE 11 v2.0.0 VALIDATION FAILED: expected 12 present_* tables, found %', v_table_count;
  END IF;

  SELECT count(*) INTO v_capability_count FROM trustride.present_shell_capability_registry;
  IF v_capability_count <> 24 THEN
    RAISE EXCEPTION 'ENGINE 11 v2.0.0 VALIDATION FAILED: expected 24 shell capability rows across 7 sub-shells, found %', v_capability_count;
  END IF;

  SELECT count(*) INTO v_shell_count FROM trustride.shell_registry WHERE status = 'ACTIVE';
  IF v_shell_count <> 2 THEN
    RAISE EXCEPTION 'ENGINE 11 v2.0.0 VALIDATION FAILED: expected exactly 2 sovereign top-shells in shell_registry, found %', v_shell_count;
  END IF;

  SELECT engine_version INTO v_version FROM trustride.engine_registry WHERE engine_code = 'TRS026_ENG011_PRESENT';
  IF v_version <> '2.0.0' THEN
    RAISE EXCEPTION 'ENGINE 11 v2.0.0 VALIDATION FAILED: engine_registry version is %, expected 2.0.0', v_version;
  END IF;

  RAISE NOTICE 'ENGINE 11 (PRESENTATION) v2.0.0 TWO-SHELL ARCHITECTURE VALIDATED: 12 tables, 24 capability rows across 7 sub-shells, 2 sovereign top-shells, engine_registry at 2.0.0.';
END;
$$;
