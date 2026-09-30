-- ============================================================================
-- ENGINE 11 (PRESENTATION) v3.0.0 -- SOVEREIGN GATE + THREE MAIN SHELLS
-- [Trace: TRS026-ENG011-PRESENT-003 FINAL (ADOPTED FOR IMPLEMENTATION,
--  2026-09-27) + TRS026-FE-01 Frontend Architecture FINAL]
--
-- Supersedes v2.0.0 (two shells: USER_HUB / TRS_OPERATOR_HUB, seven
-- sub-shells) entirely. Founder direction: remove everything about the prior
-- Engine 11 and implement this specification exactly. Clean rebuild -- no
-- present_* data survives; trustride-stagging carries no live present_* rows
-- (present_shell_session count confirmed 0 before this migration).
--
-- The main system is TrustRide Services, with exactly three main sovereign
-- shells and no other (Sec.2, Sec.7):
--   TRUSTRIDE_OFFICE      (internal)  -> OPERATOR_APP, ADMIN_CONSOLE, EXECUTIVE_DASHBOARD
--   TRUSTRIDE_BUSINESS    (external)  -> CUSTOMER_APP, PARTNER_APP, GOVERNOR_APP, INTERMEDIARY_APP
--   TRUSTRIDE_MARKETPLACE (external)  -> MARKETPLACE_APP, VENDOR_APP
-- (The Marketplace shell's own sub-shell, named "TrustRide_Marketplace" in
--  the drawing, is MARKETPLACE_APP here -- a sub_shell value cannot reuse
--  the top_shell value's spelling without the two enums reading as one.)
--
-- Sovereign Gate (Sec.3), in exact order, no step skipped or reordered:
--   System Access -> Registration -> Authentication (Engine 6 only) ->
--   Authorization (Engine 1, on a true result) -> Profile (Engine 1)
-- Engine 11's own part: record System Access as the first record of every
-- visit, capture registration input, route after authorization, open the
-- correct shell, capture commands, render projections. Engine 11 never
-- verifies identity itself (Sec.6) -- that stays in Engine 6, unchanged.
--
-- Business environments stay exactly five (Sec.5.2) and are Engine 4's own
-- business_user_type_domain_enum, unchanged: OPERATOR, CUSTOMER, PARTNER,
-- GOVERNOR, INTERMEDIARY. Sub-shell resolution maps onto them 1:1; no sixth
-- environment is introduced (Vendor_App is a Marketplace surface, not a
-- business environment, and has no self-service mapping in this increment).
-- ============================================================================

-- ============================================================================
-- PHASE 0 -- TEAR DOWN v2.0.0 COMPLETELY
-- ============================================================================
DROP FUNCTION IF EXISTS trustride.fn_present_inbox_process(UUID);
DROP FUNCTION IF EXISTS trustride.fn_present_heartbeat_sync(UUID);
DROP FUNCTION IF EXISTS trustride.fn_present_render_projection(UUID, TEXT);
DROP FUNCTION IF EXISTS trustride.fn_present_capture_command(UUID, TEXT, JSONB);
DROP FUNCTION IF EXISTS trustride.fn_present_sub_shell_for_user(UUID);
DROP FUNCTION IF EXISTS trustride.fn_present_shell_session_end(UUID);
DROP FUNCTION IF EXISTS trustride.fn_present_shell_session_open(trustride.present_top_shell_enum, trustride.present_sub_shell_enum, UUID, trustride.present_channel_type_enum, UUID, UUID);

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

-- Table drops cascade away its trigger; the trigger function outlives it.
DROP FUNCTION IF EXISTS trustride.fn_present_command_capability_check();

DROP TYPE IF EXISTS trustride.present_top_shell_enum;
DROP TYPE IF EXISTS trustride.present_sub_shell_enum;

-- present_channel_type_enum, present_session_status_enum,
-- present_translation_status_enum, present_cache_status_enum,
-- present_bridge_health_enum, present_read_status_enum carry no shell
-- structure and are unchanged by this specification; they are kept.

-- ============================================================================
-- PHASE 1 -- NEW ENUMS [Trace: Sec.2, Sec.3.2, Sec.7]
-- ============================================================================
CREATE TYPE trustride.present_top_shell_enum AS ENUM (
  'TRUSTRIDE_OFFICE', 'TRUSTRIDE_BUSINESS', 'TRUSTRIDE_MARKETPLACE'
);

CREATE TYPE trustride.present_sub_shell_enum AS ENUM (
  'OPERATOR_APP', 'ADMIN_CONSOLE', 'EXECUTIVE_DASHBOARD',
  'CUSTOMER_APP', 'PARTNER_APP', 'GOVERNOR_APP', 'INTERMEDIARY_APP',
  'MARKETPLACE_APP', 'VENDOR_APP'
);

-- The four registrant classes of the Sovereign Gate (Sec.3.2 A-D). Each
-- belongs to one of the three system characteristics -- User, Actor,
-- Object (Founder direction 2026-10-01; there is no "thing" on this
-- platform):
--   NATURAL_PERSON  -> USER    a person
--   LEGAL_ENTITY    -> ACTOR   a firm, organisation, company
--   EXTERNAL_SYSTEM -> ACTOR   an external system or application
--   OBJECT          -> OBJECT  an asset, vehicle, equipment, device, laptop
CREATE TYPE trustride.present_registrant_class_enum AS ENUM (
  'NATURAL_PERSON', 'LEGAL_ENTITY', 'EXTERNAL_SYSTEM', 'OBJECT'
);

-- ============================================================================
-- PHASE 2 -- TABLES
-- ============================================================================

-- 2.1 System Access -- the first and only lawful entry event (Sec.3.1, Rule 1).
-- What accessed (registrant_class and its system characteristic, once
-- declared), how (channel/device/mode), why (intent). Append-only: stored
-- permanently, never updated or deleted, except to bind the resolved
-- identity once registration completes.
CREATE TABLE trustride.present_system_access_event (
  access_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  registrant_class  trustride.present_registrant_class_enum,
  system_characteristic TEXT GENERATED ALWAYS AS (
    CASE registrant_class
      WHEN 'NATURAL_PERSON' THEN 'USER'
      WHEN 'LEGAL_ENTITY' THEN 'ACTOR'
      WHEN 'EXTERNAL_SYSTEM' THEN 'ACTOR'
      WHEN 'OBJECT' THEN 'OBJECT'
    END) STORED,
  channel_type      trustride.present_channel_type_enum NOT NULL,
  access_mode       TEXT NOT NULL DEFAULT 'INTERACTIVE' CHECK (access_mode IN ('INTERACTIVE', 'PROGRAMMATIC', 'DEVICE')),
  device_id         UUID,
  intent            TEXT NOT NULL CHECK (intent IN ('REGISTER', 'AUTHENTICATE', 'RESUME_SESSION')),
  resolved_user_id  UUID,
  occurred_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_present_system_access_occurred ON trustride.present_system_access_event (occurred_at DESC);
CREATE INDEX idx_present_system_access_resolved ON trustride.present_system_access_event (resolved_user_id) WHERE resolved_user_id IS NOT NULL;
COMMENT ON TABLE trustride.present_system_access_event IS
  '[Trace: TRS026-ENG011-PRESENT-003 Sec.3.1, Rule 1] The first record of every visit -- what accessed, how, and why. No further Sovereign Gate step exists without one. Append-only; the only permitted change is binding resolved_user_id once an identity is established.';
REVOKE DELETE ON trustride.present_system_access_event FROM PUBLIC;
ALTER TABLE trustride.present_system_access_event ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_system_access_event_self_read ON trustride.present_system_access_event FOR SELECT TO trustride_authenticated USING (resolved_user_id = auth.uid());
CREATE POLICY present_system_access_event_service_write ON trustride.present_system_access_event FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

-- 2.2 Shell session -- exactly one top-shell and one sub-shell, ownership
-- enforced structurally (Sec.7: surfaces never mix).
CREATE TABLE trustride.present_shell_session (
  session_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  top_shell        trustride.present_top_shell_enum NOT NULL,
  sub_shell        trustride.present_sub_shell_enum NOT NULL,
  user_id          UUID NOT NULL,
  access_id        UUID REFERENCES trustride.present_system_access_event (access_id),
  device_id        UUID,
  channel_type     trustride.present_channel_type_enum NOT NULL,
  auth_session_ref UUID,
  started_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at         TIMESTAMPTZ,
  session_status   trustride.present_session_status_enum NOT NULL DEFAULT 'ACTIVE',
  CONSTRAINT chk_sub_shell_ownership CHECK (
    (top_shell = 'TRUSTRIDE_OFFICE'      AND sub_shell IN ('OPERATOR_APP', 'ADMIN_CONSOLE', 'EXECUTIVE_DASHBOARD'))
    OR (top_shell = 'TRUSTRIDE_BUSINESS'    AND sub_shell IN ('CUSTOMER_APP', 'PARTNER_APP', 'GOVERNOR_APP', 'INTERMEDIARY_APP'))
    OR (top_shell = 'TRUSTRIDE_MARKETPLACE' AND sub_shell IN ('MARKETPLACE_APP', 'VENDOR_APP'))
  )
);
CREATE INDEX idx_present_shell_session_user ON trustride.present_shell_session (user_id);
CREATE INDEX idx_present_shell_session_shell_status ON trustride.present_shell_session (top_shell, sub_shell, session_status);
COMMENT ON TABLE trustride.present_shell_session IS
  '[Trace: TRS026-ENG011-PRESENT-003 Sec.7] Bound to exactly one of the three main sovereign shells and one of its sub-shells; no shell registers or authenticates on its own.';
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
  '[Trace: FDN-001 Sec.11.4] Per-sub-shell permitted verbs, made executable: a command not found here as permitted=TRUE is rejected at capture.';
ALTER TABLE trustride.present_shell_capability_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_shell_capability_registry_platform_read ON trustride.present_shell_capability_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY present_shell_capability_registry_service_write ON trustride.present_shell_capability_registry FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

-- Verbs per sub-shell, drawn from the drawing's own panel for each surface
-- (TRS026-FE-01 Layer 6). Every surface an actor is routed to has a real
-- submission verb with a live handler in fn_present_capture_command -- no
-- actor lands on a surface with nothing lawful to do:
--   Customer     RAISE_INTENT / ACCEPT_QUOTATION / TRACK_ELEMENT -> SERVICE_ORDER
--   Partner      SUBMIT_PARTNERSHIP_REQUEST   -> RESOURCE_PARTNERSHIP_REQUEST
--   Governor     SUBMIT_REGULATORY_REQUEST    -> REGULATORY_ACCESS_REQUEST
--   Intermediary SUBMIT_FACILITATION_REQUEST  -> FACILITATION_REQUEST
--   Buyer        RESERVE_VEHICLE              -> MARKETPLACE_PURCHASE_ORDER
--   Vendor       SUBMIT_VENDOR_LISTING        -> VENDOR_LISTING_REQUEST
--   Admin        REVIEW_ACTOR_REQUEST         -> fn_business_actor_request_decide
--   Operator     EMIT_PROGRESS_SIGNAL; Executive RUN_SCENARIO
-- The remaining verbs are post-approval operational features the drawing
-- names; they are registered (the surface law holds) and captured, but have
-- no domain handler yet -- never faked. Staff requesting Office access do so
-- at the Sovereign Gate itself (they have no Office session yet), through
-- fn_present_office_access_request below.
INSERT INTO trustride.present_shell_capability_registry (top_shell, sub_shell, command_type, requires_delegated_authority) VALUES
  ('TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'VIEW_ASSIGNMENT_PROJECTION', FALSE),
  ('TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', FALSE),
  ('TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'CAPTURE_EVIDENCE', FALSE),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'VIEW_REGISTER', FALSE),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REVIEW_ACTOR_REQUEST', FALSE),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'EMIT_GOVERNANCE_SIGNAL', TRUE),
  ('TRUSTRIDE_OFFICE', 'EXECUTIVE_DASHBOARD', 'VIEW_WHOLE_ESTATE', FALSE),
  ('TRUSTRIDE_OFFICE', 'EXECUTIVE_DASHBOARD', 'RULE_ON_EXCEPTION', FALSE),
  ('TRUSTRIDE_OFFICE', 'EXECUTIVE_DASHBOARD', 'RUN_SCENARIO', FALSE),
  ('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'VIEW_PROJECTION', FALSE),
  ('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', FALSE),
  ('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'ACCEPT_QUOTATION', FALSE),
  ('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'TRACK_ELEMENT', FALSE),
  ('TRUSTRIDE_BUSINESS', 'PARTNER_APP', 'VIEW_PROJECTION', FALSE),
  ('TRUSTRIDE_BUSINESS', 'PARTNER_APP', 'SUBMIT_PARTNERSHIP_REQUEST', FALSE),
  ('TRUSTRIDE_BUSINESS', 'GOVERNOR_APP', 'VIEW_PROJECTION', FALSE),
  ('TRUSTRIDE_BUSINESS', 'GOVERNOR_APP', 'SUBMIT_REGULATORY_REQUEST', FALSE),
  ('TRUSTRIDE_BUSINESS', 'INTERMEDIARY_APP', 'VIEW_PROJECTION', FALSE),
  ('TRUSTRIDE_BUSINESS', 'INTERMEDIARY_APP', 'SUBMIT_FACILITATION_REQUEST', FALSE),
  ('TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'VIEW_PROJECTION', FALSE),
  ('TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'RESERVE_VEHICLE', FALSE),
  ('TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'VIEW_PROJECTION', FALSE),
  ('TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'SUBMIT_VENDOR_LISTING', FALSE),
  ('TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'PUBLISH_OFFER', FALSE),
  ('TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'SETTLE_LAWFUL_FLOW', FALSE);

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
  '[Trace: FDN-001 Sec.11.4 C-III-1] The proof: every human action passed through here before any signal existed.';

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
  '[Trace: FDN-001 Sec.11.4 C-III-3] Views are lawful projections: every projection_code resolves to a row in Foundation''s projection_registry.';
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
  'What a surface shows while disconnected -- distinct from the on-device offline outbox (Layer 3, AQ-002), never what it queues to send.';
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

-- Every Sovereign Gate step and every command is logged immutably here
-- (Sec.8 "Every step ... must be logged immutably").
CREATE TABLE trustride.present_decision_log (
  decision_log_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  command_id        UUID REFERENCES trustride.present_command_capture (command_id),
  access_id         UUID REFERENCES trustride.present_system_access_event (access_id),
  event_type        TEXT NOT NULL,
  event_description TEXT,
  prev_hash         CHAR(64),
  immutable_hash    CHAR(64) NOT NULL,
  recorded_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_present_decision_log_command ON trustride.present_decision_log (command_id);
CREATE INDEX idx_present_decision_log_access ON trustride.present_decision_log (access_id);
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
-- PHASE 3 -- FOUNDATION'S shell_registry: THE THREE MAIN SOVEREIGN SHELLS
-- [Trace: Sec.2 "exactly three main sovereign shells ... No other shells
--  are permitted." Sub-shells are Engine 11's own taxonomy.]
-- ============================================================================
DELETE FROM trustride.shell_registry;

INSERT INTO trustride.shell_registry (shell_code, shell_name, serves_user_types, isolation_class) VALUES
  ('TRUSTRIDE_OFFICE',      'TrustRide Office',      ARRAY['OPERATOR','ADMINISTRATOR','EXECUTIVE'],            'INTERNAL'),
  ('TRUSTRIDE_BUSINESS',    'TrustRide Business',    ARRAY['CUSTOMER','PARTNER','GOVERNOR','INTERMEDIARY'],    'EXTERNAL'),
  ('TRUSTRIDE_MARKETPLACE', 'TrustRide Marketplace', ARRAY['MARKETPLACE_BUYER','VENDOR'],                      'EXTERNAL');

-- projection_registry.shell was still constrained to v1's flat five-shell
-- vocabulary (v2 never moved it either, leaving USER_ORDER_STATUS_CARD
-- pointing at a shell that no longer existed). Every registered projection
-- now names one of the three main shells, matching shell_registry.
ALTER TABLE trustride.projection_registry DROP CONSTRAINT projection_registry_shell_check;
UPDATE trustride.projection_registry SET shell = CASE shell
  WHEN 'USER_HUB' THEN 'TRUSTRIDE_BUSINESS'
  WHEN 'MARKETPLACE_HUB' THEN 'TRUSTRIDE_MARKETPLACE'
  WHEN 'OPERATOR_APP' THEN 'TRUSTRIDE_OFFICE'
  WHEN 'ADMIN_CONSOLE' THEN 'TRUSTRIDE_OFFICE'
  WHEN 'SOVEREIGN_EXECUTIVE_CONSOLE' THEN 'TRUSTRIDE_OFFICE'
  ELSE shell
END;
ALTER TABLE trustride.projection_registry ADD CONSTRAINT projection_registry_shell_check
  CHECK (shell IN ('TRUSTRIDE_OFFICE', 'TRUSTRIDE_BUSINESS', 'TRUSTRIDE_MARKETPLACE'));

COMMENT ON TABLE trustride.shell_registry IS
  '[Trace: TRS026-ENG011-PRESENT-003 Sec.2, Sec.7] The three main sovereign shells of TrustRide Services -- TrustRide Office (internal), TrustRide Business (external), TrustRide Marketplace (external); no fourth exists. Sub-shells are governed by Engine 11''s present_shell_capability_registry.';

-- ============================================================================
-- PHASE 4 -- SYSTEM ACCESS [Trace: Sec.3.1, Rules 1 and 19]
-- ============================================================================
CREATE FUNCTION trustride.fn_present_system_access_record(
  p_channel_type trustride.present_channel_type_enum,
  p_intent TEXT,
  p_registrant_class trustride.present_registrant_class_enum DEFAULT NULL,
  p_access_mode TEXT DEFAULT 'INTERACTIVE',
  p_device_id UUID DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp AS $$
DECLARE
  v_access_id UUID;
  v_prev_hash CHAR(64);
BEGIN
  INSERT INTO trustride.present_system_access_event (registrant_class, channel_type, access_mode, device_id, intent)
  VALUES (p_registrant_class, p_channel_type, p_access_mode, p_device_id, p_intent)
  RETURNING access_id INTO v_access_id;

  SELECT immutable_hash INTO v_prev_hash FROM trustride.present_decision_log ORDER BY recorded_at DESC LIMIT 1;
  INSERT INTO trustride.present_decision_log (access_id, event_type, event_description, prev_hash, immutable_hash)
  VALUES (v_access_id, 'SYSTEM_ACCESS', format('%s via %s (%s)', p_intent, p_channel_type, coalesce(p_registrant_class::text, 'CLASS_NOT_YET_DECLARED')),
    v_prev_hash, encode(digest(coalesce(v_prev_hash, '') || v_access_id::text || 'SYSTEM_ACCESS', 'sha256'), 'hex'));

  RETURN v_access_id;
END;
$$;

-- Binds a System Access event to the identity it produced -- the one
-- permitted change to an access record. Only an unbound event can be bound,
-- and only to the caller's own identity.
CREATE FUNCTION trustride.fn_present_system_access_bind(p_access_id UUID, p_gate_step TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp AS $$
DECLARE
  v_prev_hash CHAR(64);
BEGIN
  IF p_gate_step NOT IN ('REGISTRATION', 'AUTHENTICATED', 'SESSION_RESUMED') THEN
    RAISE EXCEPTION 'fn_present_system_access_bind: unknown gate step %', p_gate_step;
  END IF;

  UPDATE trustride.present_system_access_event
  SET resolved_user_id = auth.uid()
  WHERE access_id = p_access_id AND (resolved_user_id IS NULL OR resolved_user_id = auth.uid());

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_present_system_access_bind: access % does not exist or belongs to another identity', p_access_id;
  END IF;

  SELECT immutable_hash INTO v_prev_hash FROM trustride.present_decision_log ORDER BY recorded_at DESC LIMIT 1;
  INSERT INTO trustride.present_decision_log (access_id, event_type, event_description, prev_hash, immutable_hash)
  VALUES (p_access_id, p_gate_step, format('%s bound to identity', p_gate_step),
    v_prev_hash, encode(digest(coalesce(v_prev_hash, '') || p_access_id::text || p_gate_step, 'sha256'), 'hex'));
END;
$$;

-- ============================================================================
-- PHASE 5 -- SESSION LIFECYCLE [Trace: Sec.6 "Shell assignment ... Engine 11"]
-- ============================================================================
CREATE FUNCTION trustride.fn_present_shell_session_open(
  p_top_shell trustride.present_top_shell_enum, p_sub_shell trustride.present_sub_shell_enum,
  p_user_id UUID, p_channel_type trustride.present_channel_type_enum,
  p_access_id UUID DEFAULT NULL, p_device_id UUID DEFAULT NULL, p_auth_session_ref UUID DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
DECLARE
  v_session_id UUID;
  v_required_domain trustride.business_user_type_domain_enum;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM trustride.shell_registry WHERE shell_code = p_top_shell::text AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'fn_present_shell_session_open: % is not a registered ACTIVE main shell', p_top_shell;
  END IF;

  IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'fn_present_shell_session_open: a session can only be opened for the caller''s own identity';
  END IF;

  v_required_domain := (CASE p_sub_shell
    WHEN 'CUSTOMER_APP' THEN 'CUSTOMER'
    WHEN 'PARTNER_APP' THEN 'PARTNER'
    WHEN 'GOVERNOR_APP' THEN 'GOVERNOR'
    WHEN 'INTERMEDIARY_APP' THEN 'INTERMEDIARY'
    WHEN 'OPERATOR_APP' THEN 'OPERATOR'
  END)::trustride.business_user_type_domain_enum;

  -- External identities are completely blocked from internal operations
  -- (Sec.7). Each TrustRide Office surface opens only for the staff it
  -- serves: Admin_Console for Administrators, Executive_Dashboard for
  -- Executives, Operator_App for approved Operators (employed, per Article
  -- 44). The Founder holds genesis authority over all three.
  IF p_top_shell = 'TRUSTRIDE_OFFICE' THEN
    IF NOT (
      trustride.fn_am_i_role(ARRAY['FOUNDER'])
      OR (p_sub_shell = 'ADMIN_CONSOLE' AND trustride.fn_am_i_role(ARRAY['ADMINISTRATOR']))
      OR (p_sub_shell = 'EXECUTIVE_DASHBOARD' AND trustride.fn_am_i_role(ARRAY['EXECUTIVE']))
      OR (p_sub_shell = 'OPERATOR_APP' AND (trustride.fn_am_i_role(ARRAY['DISPATCHER']) OR EXISTS (
            SELECT 1 FROM trustride.business_actor_registration
            WHERE user_id = p_user_id AND user_type_domain = 'OPERATOR' AND registration_status = 'ACTIVE')))
    ) THEN
      RAISE EXCEPTION 'fn_present_shell_session_open: % is TrustRide Office -- internal staff only; request Office access at the Sovereign Gate', p_sub_shell;
    END IF;
  -- Post-authorization routing by role (Sec.4, Sec.8): a Business sub-shell
  -- opens only for an identity registered into that environment. A PENDING
  -- registration opens too -- a Partner, Governor or Intermediary awaiting
  -- approval must be able to submit and follow their request; what a pending
  -- actor may do is restricted at command capture, not by locking them out.
  ELSIF v_required_domain IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM trustride.business_actor_registration
      WHERE user_id = p_user_id AND user_type_domain = v_required_domain AND registration_status IN ('ACTIVE', 'PENDING')) THEN
    RAISE EXCEPTION 'fn_present_shell_session_open: % opens only for an identity registered as %', p_sub_shell, v_required_domain;
  END IF;

  INSERT INTO trustride.present_shell_session (top_shell, sub_shell, user_id, access_id, device_id, channel_type, auth_session_ref)
  VALUES (p_top_shell, p_sub_shell, p_user_id, p_access_id, p_device_id, p_channel_type, p_auth_session_ref)
  RETURNING session_id INTO v_session_id;

  RETURN v_session_id;
END;
$$;

CREATE FUNCTION trustride.fn_present_shell_session_end(p_session_id UUID)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
  UPDATE trustride.present_shell_session SET session_status = 'ENDED', ended_at = now() WHERE session_id = p_session_id AND session_status = 'ACTIVE';
$$;

-- TrustRide staff reach Office through the Sovereign Gate like everyone
-- else, then ask to be let in. They hold no Office session yet, so this is
-- a Gate-level request, not a shell command. It lands in the same governed
-- queue (Engine 4, OFFICE_ACCESS_REQUEST) with the same 2-3 working-day
-- clock; an approval provisions exactly the surface asked for.
CREATE FUNCTION trustride.fn_present_office_access_request(p_office_surface trustride.present_sub_shell_enum, p_justification TEXT, p_access_id UUID DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_order_id UUID;
  v_prev_hash CHAR(64);
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'fn_present_office_access_request: no authenticated session';
  END IF;
  IF p_office_surface NOT IN ('OPERATOR_APP', 'ADMIN_CONSOLE', 'EXECUTIVE_DASHBOARD') THEN
    RAISE EXCEPTION 'fn_present_office_access_request: % is not a TrustRide Office surface', p_office_surface;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id = v_caller AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'fn_present_office_access_request: complete identity verification first -- no step of the Sovereign Gate may be skipped';
  END IF;
  IF coalesce(trim(p_justification), '') = '' THEN
    RAISE EXCEPTION 'fn_present_office_access_request: state your TrustRide role or staff reference';
  END IF;

  v_order_id := trustride.fn_business_order_place(
    v_caller, 'OPERATOR', 'OFFICE-ACCESS', 'OFFICE',
    jsonb_build_array(jsonb_build_object(
      'line_description', 'TrustRide Office access: ' || p_office_surface::text,
      'quantity', 1,
      'scope_detail', jsonb_build_object('office_surface', p_office_surface::text, 'justification', p_justification))),
    'OFFICE_ACCESS_REQUEST', 'KISUMU_COUNTY', coalesce(p_access_id, gen_random_uuid()));

  SELECT immutable_hash INTO v_prev_hash FROM trustride.present_decision_log ORDER BY recorded_at DESC LIMIT 1;
  INSERT INTO trustride.present_decision_log (access_id, event_type, event_description, prev_hash, immutable_hash)
  VALUES (p_access_id, 'OFFICE_ACCESS_REQUESTED', format('%s requested by %s', p_office_surface, v_caller),
    v_prev_hash, encode(digest(coalesce(v_prev_hash, '') || v_order_id::text || 'OFFICE_ACCESS_REQUESTED', 'sha256'), 'hex'));

  RETURN v_order_id;
END;
$$;

-- Post-authorization routing (Sec.6: Engine 11). Each of the five business
-- environments resolves to exactly one sub-shell; the most recently
-- registered active environment wins when a User holds more than one
-- (Article 12.9 permits several).
CREATE FUNCTION trustride.fn_present_sub_shell_for_user(p_user_id UUID)
RETURNS trustride.present_sub_shell_enum LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
  SELECT CASE bar.user_type_domain
    WHEN 'CUSTOMER' THEN 'CUSTOMER_APP'
    WHEN 'PARTNER' THEN 'PARTNER_APP'
    WHEN 'GOVERNOR' THEN 'GOVERNOR_APP'
    WHEN 'INTERMEDIARY' THEN 'INTERMEDIARY_APP'
    WHEN 'OPERATOR' THEN 'OPERATOR_APP'
  END::trustride.present_sub_shell_enum
  FROM trustride.business_actor_registration bar
  WHERE bar.user_id = p_user_id AND bar.registration_status = 'ACTIVE'
  ORDER BY bar.registered_at DESC LIMIT 1;
$$;

-- ============================================================================
-- PHASE 6 -- COMMAND CAPTURE [Trace: FDN-001 Sec.11.4 C-III-1]
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

  -- A Business environment still awaiting approval may submit its request
  -- and view its own projections -- nothing operational until approved
  -- (Sec.4.2-4.4 "On approval -> ... surface activates").
  IF v_session.top_shell = 'TRUSTRIDE_BUSINESS'
     AND p_command_type NOT LIKE 'SUBMIT\_%' AND p_command_type <> 'VIEW_PROJECTION'
     AND EXISTS (
       SELECT 1 FROM trustride.business_actor_registration
       WHERE user_id = v_session.user_id AND registration_status = 'PENDING'
         AND user_type_domain = (CASE v_session.sub_shell
           WHEN 'PARTNER_APP' THEN 'PARTNER' WHEN 'GOVERNOR_APP' THEN 'GOVERNOR'
           WHEN 'INTERMEDIARY_APP' THEN 'INTERMEDIARY' END)::trustride.business_user_type_domain_enum)
     AND NOT EXISTS (
       SELECT 1 FROM trustride.business_actor_registration
       WHERE user_id = v_session.user_id AND registration_status = 'ACTIVE'
         AND user_type_domain = (CASE v_session.sub_shell
           WHEN 'PARTNER_APP' THEN 'PARTNER' WHEN 'GOVERNOR_APP' THEN 'GOVERNOR'
           WHEN 'INTERMEDIARY_APP' THEN 'INTERMEDIARY' END)::trustride.business_user_type_domain_enum) THEN
    RAISE EXCEPTION 'fn_present_capture_command: % becomes available once your request is approved', p_command_type;
  END IF;

  INSERT INTO trustride.present_command_capture (shell_session_id, top_shell, sub_shell, command_type, command_payload)
  VALUES (p_shell_session_id, v_session.top_shell, v_session.sub_shell, p_command_type, p_command_payload)
  RETURNING command_id INTO v_command_id;

  BEGIN
    CASE p_command_type
      -- Customer: Order + Order Lines, immediate or scheduled (Sec.4.1).
      WHEN 'RAISE_INTENT' THEN
        v_translated_signal_id := trustride.fn_business_order_place(
          v_session.user_id,
          (p_command_payload->>'user_type_domain')::trustride.business_user_type_domain_enum,
          p_command_payload->>'service_code', p_command_payload->>'macro_domain', p_command_payload->'order_lines',
          'SERVICE_ORDER',
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

      -- Partner / Governor / Intermediary requests (Sec.4.2-4.4): each lands
      -- on its own Engine 4 order root, which opens a governed response with
      -- a 2-3 working-day clock and an Office decision.
      WHEN 'SUBMIT_PARTNERSHIP_REQUEST' THEN
        v_translated_signal_id := trustride.fn_business_order_place(
          v_session.user_id, 'PARTNER', 'RESOURCE-PARTNERSHIP', 'PARTNERSHIP', p_command_payload->'scope_lines',
          'RESOURCE_PARTNERSHIP_REQUEST', coalesce(p_command_payload->>'jurisdiction', 'KISUMU_COUNTY'), v_command_id);
        v_translation_status := 'TRANSLATED';

      WHEN 'SUBMIT_REGULATORY_REQUEST' THEN
        v_translated_signal_id := trustride.fn_business_order_place(
          v_session.user_id, 'GOVERNOR', 'REGULATORY-ACCESS', 'GOVERNANCE', p_command_payload->'scope_lines',
          'REGULATORY_ACCESS_REQUEST', coalesce(p_command_payload->>'jurisdiction', 'KISUMU_COUNTY'), v_command_id);
        v_translation_status := 'TRANSLATED';

      WHEN 'SUBMIT_FACILITATION_REQUEST' THEN
        v_translated_signal_id := trustride.fn_business_order_place(
          v_session.user_id, 'INTERMEDIARY', 'FACILITATION', 'FACILITATION', p_command_payload->'scope_lines',
          'FACILITATION_REQUEST', coalesce(p_command_payload->>'jurisdiction', 'KISUMU_COUNTY'), v_command_id);
        v_translation_status := 'TRANSLATED';

      -- Marketplace: what is listed or bought must strictly align with what
      -- TrustRide offers the market -- motorcycles and cars, nothing else.
      WHEN 'SUBMIT_VENDOR_LISTING' THEN
        IF EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(p_command_payload->'scope_lines', '[]'::jsonb)) l
                   WHERE coalesce(l->'scope_detail'->>'vehicle_category', '') NOT IN ('MOTORCYCLE', 'CAR')) THEN
          RAISE EXCEPTION 'TrustRide Marketplace lists motorcycles and cars only';
        END IF;
        v_translated_signal_id := trustride.fn_business_order_place(
          v_session.user_id, 'PARTNER', 'MARKETPLACE-VENDOR-LISTING', 'MARKETPLACE', p_command_payload->'scope_lines',
          'VENDOR_LISTING_REQUEST', coalesce(p_command_payload->>'jurisdiction', 'KISUMU_COUNTY'), v_command_id);
        v_translation_status := 'TRANSLATED';

      WHEN 'RESERVE_VEHICLE' THEN
        IF EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(p_command_payload->'order_lines', '[]'::jsonb)) l
                   WHERE coalesce(l->'scope_detail'->>'vehicle_category', '') NOT IN ('MOTORCYCLE', 'CAR')) THEN
          RAISE EXCEPTION 'TrustRide Marketplace sells motorcycles and cars only';
        END IF;
        v_translated_signal_id := trustride.fn_business_order_place(
          v_session.user_id, 'CUSTOMER', 'MARKETPLACE-VEHICLE-PURCHASE', 'MARKETPLACE', p_command_payload->'order_lines',
          'MARKETPLACE_PURCHASE_ORDER', coalesce(p_command_payload->>'jurisdiction', 'KISUMU_COUNTY'), v_command_id);
        v_translation_status := 'TRANSLATED';

      -- Admin_Console: the Office decision on any actor request (Sec.6).
      WHEN 'REVIEW_ACTOR_REQUEST' THEN
        PERFORM trustride.fn_business_actor_request_decide(
          (p_command_payload->>'order_id')::uuid,
          (p_command_payload->>'decision')::trustride.business_partnership_response_status_enum,
          p_command_payload->>'notes');
        v_translated_signal_id := (p_command_payload->>'order_id')::uuid;
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
        NULL; -- registered verb, no live domain handler yet -- captured, never faked
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
  VALUES (v_command_id, 'COMMAND_CAPTURED', format('%s on %s/%s -> %s', p_command_type, v_session.top_shell, v_session.sub_shell, v_translation_status), v_prev_hash, v_new_hash);

  RETURN v_command_id;
END;
$$;

-- ============================================================================
-- PHASE 7 -- PROJECTIONS + HEARTBEAT
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
-- PHASE 8 -- INBOUND SIGNALS
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
    -- Every order root is placed through fn_business_order_place, whose
    -- service_code names the path; each actor hears back on their own surface.
    WHEN 'ORDER_PLACED' THEN
      v_recipient := (v_payload->>'requester_user_id')::uuid;
      INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, source_signal_correlation_id)
      SELECT v_recipient, s.top_shell::trustride.present_top_shell_enum, s.sub_shell::trustride.present_sub_shell_enum, s.title,
        format(s.body, v_payload->>'order_code'), v_correlation_id
      FROM (SELECT CASE v_payload->>'service_code'
          WHEN 'RESOURCE-PARTNERSHIP' THEN ARRAY['TRUSTRIDE_BUSINESS', 'PARTNER_APP', 'Partnership request received', 'Request %s is with TrustRide Office -- decision within 2-3 working days.']
          WHEN 'REGULATORY-ACCESS' THEN ARRAY['TRUSTRIDE_BUSINESS', 'GOVERNOR_APP', 'Regulatory access request received', 'Request %s is with TrustRide Office -- decision within 2-3 working days.']
          WHEN 'FACILITATION' THEN ARRAY['TRUSTRIDE_BUSINESS', 'INTERMEDIARY_APP', 'Facilitation request received', 'Request %s is with TrustRide Office -- decision within 2-3 working days.']
          WHEN 'MARKETPLACE-VENDOR-LISTING' THEN ARRAY['TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'Vendor application received', 'Application %s is with TrustRide Office -- decision within 2-3 working days.']
          WHEN 'MARKETPLACE-VEHICLE-PURCHASE' THEN ARRAY['TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'Vehicle reservation received', 'Reservation %s is being confirmed -- within 2-3 working days.']
          WHEN 'OFFICE-ACCESS' THEN ARRAY['TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'Office access request received', 'Request %s is with TrustRide Office -- decision within 2-3 working days.']
          ELSE ARRAY['TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'Order placed', 'Your order %s has been placed.']
        END AS a) x
      CROSS JOIN LATERAL (SELECT x.a[1] AS top_shell, x.a[2] AS sub_shell, x.a[3] AS title, x.a[4] AS body) s;

    WHEN 'ACTOR_REQUEST_DECIDED', 'ACTOR_REQUEST_ESCALATED' THEN
      v_recipient := (v_payload->>'requester_user_id')::uuid;
      INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, source_signal_correlation_id)
      SELECT v_recipient, s.top_shell::trustride.present_top_shell_enum, s.sub_shell::trustride.present_sub_shell_enum,
        CASE
          WHEN v_signal_type = 'ACTOR_REQUEST_ESCALATED' THEN 'Your request has been escalated'
          WHEN v_payload->>'decision' = 'ACCEPTED' THEN 'Your request was approved'
          ELSE 'Your request was not approved'
        END,
        CASE
          WHEN v_signal_type = 'ACTOR_REQUEST_ESCALATED'
            THEN format('%s passed its 3 working-day window and has been escalated within TrustRide Office. It remains open.', v_payload->>'order_code')
          WHEN v_payload->>'decision' = 'ACCEPTED'
            THEN format('%s approved -- your surface is now active.', v_payload->>'order_code')
          ELSE format('%s not approved%s. You may amend and re-submit.', v_payload->>'order_code',
                      coalesce(': ' || nullif(v_payload->>'notes', ''), ''))
        END,
        v_correlation_id
      FROM (SELECT CASE v_payload->>'order_root_type'
          WHEN 'RESOURCE_PARTNERSHIP_REQUEST' THEN ARRAY['TRUSTRIDE_BUSINESS', 'PARTNER_APP']
          WHEN 'REGULATORY_ACCESS_REQUEST' THEN ARRAY['TRUSTRIDE_BUSINESS', 'GOVERNOR_APP']
          WHEN 'FACILITATION_REQUEST' THEN ARRAY['TRUSTRIDE_BUSINESS', 'INTERMEDIARY_APP']
          WHEN 'VENDOR_LISTING_REQUEST' THEN ARRAY['TRUSTRIDE_MARKETPLACE', 'VENDOR_APP']
          WHEN 'MARKETPLACE_PURCHASE_ORDER' THEN ARRAY['TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP']
          ELSE ARRAY['TRUSTRIDE_OFFICE', 'OPERATOR_APP']
        END AS a) x
      CROSS JOIN LATERAL (SELECT x.a[1] AS top_shell, x.a[2] AS sub_shell) s;

    WHEN 'ORDER_SETTLED' THEN
      v_recipient := (v_payload->>'requester_user_id')::uuid;
      v_recipient_sub_shell := coalesce(trustride.fn_present_sub_shell_for_user(v_recipient), 'CUSTOMER_APP');
      INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, source_signal_correlation_id)
      VALUES (v_recipient, 'TRUSTRIDE_BUSINESS', v_recipient_sub_shell, 'Payment settled',
        format('Payment of %s KES settled, receipt %s.', v_payload->>'computed_total_fare_kes', v_payload->>'receipt_code'), v_correlation_id);

    WHEN 'SERVICE_CATALOGUE_UPDATED' THEN
      NULL; -- catalogue projections render fresh on the next render call

    WHEN 'ADVISORY_RECOMMENDATION_PUBLISHED' THEN
      NULL; -- no recipient carried; rendered as an aggregate Executive_Dashboard feed once built

    WHEN 'ADVISORY_ANOMALY_FLAGGED' THEN
      NULL; -- same as above

    WHEN 'SCENARIO_RUN_COMPLETED' THEN
      INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, source_signal_correlation_id)
      SELECT msr.requested_by, 'TRUSTRIDE_OFFICE', 'EXECUTIVE_DASHBOARD', 'Scenario run finished',
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
-- PHASE 9 -- GRANTS (tables re-created, so re-issued)
-- ============================================================================
GRANT SELECT ON trustride.present_system_access_event, trustride.present_shell_session,
  trustride.present_device_channel_registration, trustride.present_shell_capability_registry,
  trustride.present_command_capture, trustride.present_projection_render, trustride.present_projection_cache,
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
GRANT SELECT, INSERT, UPDATE ON trustride.present_system_access_event TO trs026_eng011_present_service;

-- System Access is recorded before any identity exists (Sec.3.1), so it is
-- the one function the anonymous role may call. Granting anon schema USAGE
-- is only safe if no function in the schema is executable by PUBLIC, so the
-- proven platform-wide sweep runs first (ALTER DEFAULT PRIVILEGES does not
-- suppress the PUBLIC grant -- see 20260826000001). Standing rule, now
-- load-bearing: every future function in trustride must REVOKE EXECUTE
-- FROM PUBLIC, or anon can reach it.
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT p.oid::regprocedure AS sig FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'trustride' LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.sig);
  END LOOP;
END;
$$;

GRANT USAGE ON SCHEMA trustride TO anon;
GRANT EXECUTE ON FUNCTION trustride.fn_present_system_access_record(trustride.present_channel_type_enum, TEXT, trustride.present_registrant_class_enum, TEXT, UUID) TO anon, trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_system_access_bind(UUID, TEXT) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_shell_session_open(trustride.present_top_shell_enum, trustride.present_sub_shell_enum, UUID, trustride.present_channel_type_enum, UUID, UUID, UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_shell_session_end(UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_office_access_request(trustride.present_sub_shell_enum, TEXT, UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_capture_command(UUID, TEXT, JSONB) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_render_projection(UUID, TEXT) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_heartbeat_sync(UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_sub_shell_for_user(UUID) TO trustride_authenticated, trs026_eng011_present_service;
GRANT EXECUTE ON FUNCTION trustride.fn_present_inbox_process(UUID) TO trs026_eng011_present_service, trs026_eng007_orch_service;

REVOKE EXECUTE ON FUNCTION trustride.fn_present_system_access_record(trustride.present_channel_type_enum, TEXT, trustride.present_registrant_class_enum, TEXT, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_present_system_access_bind(UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_present_shell_session_open(trustride.present_top_shell_enum, trustride.present_sub_shell_enum, UUID, trustride.present_channel_type_enum, UUID, UUID, UUID) FROM PUBLIC;
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
UPDATE trustride.engine_registry SET engine_version = '3.0.0' WHERE engine_code = 'TRS026_ENG011_PRESENT';

-- ============================================================================
-- PHASE 11 -- VALIDATION
-- ============================================================================
DO $$
DECLARE
  v_table_count INTEGER;
  v_capability_count INTEGER;
  v_subshell_count INTEGER;
  v_shell_count INTEGER;
  v_version TEXT;
BEGIN
  SELECT count(*) INTO v_table_count FROM information_schema.tables WHERE table_schema = 'trustride' AND table_name LIKE 'present_%';
  IF v_table_count <> 13 THEN
    RAISE EXCEPTION 'ENGINE 11 v3.0.0 VALIDATION FAILED: expected 13 present_* tables, found %', v_table_count;
  END IF;

  SELECT count(*), count(DISTINCT sub_shell) INTO v_capability_count, v_subshell_count FROM trustride.present_shell_capability_registry;
  IF v_capability_count <> 25 OR v_subshell_count <> 9 THEN
    RAISE EXCEPTION 'ENGINE 11 v3.0.0 VALIDATION FAILED: expected 25 capability rows across 9 sub-shells, found % across %', v_capability_count, v_subshell_count;
  END IF;

  SELECT count(*) INTO v_shell_count FROM trustride.shell_registry WHERE status = 'ACTIVE';
  IF v_shell_count <> 3 THEN
    RAISE EXCEPTION 'ENGINE 11 v3.0.0 VALIDATION FAILED: expected exactly 3 main sovereign shells, found %', v_shell_count;
  END IF;

  SELECT engine_version INTO v_version FROM trustride.engine_registry WHERE engine_code = 'TRS026_ENG011_PRESENT';
  IF v_version <> '3.0.0' THEN
    RAISE EXCEPTION 'ENGINE 11 v3.0.0 VALIDATION FAILED: engine_registry version is %, expected 3.0.0', v_version;
  END IF;

  RAISE NOTICE 'ENGINE 11 (PRESENTATION) v3.0.0 SOVEREIGN GATE VALIDATED: 13 tables, 25 capability rows across 9 sub-shells, 3 main sovereign shells, engine_registry at 3.0.0.';
END;
$$;
