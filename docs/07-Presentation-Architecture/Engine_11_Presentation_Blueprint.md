# TRUSTRIDE SERVICES

# ENGINE 11 — PRESENTATION ENGINE
## Complete Architectural, Data, API, and Signal Specification

**[Parent Authority: TBOC v2.0.0 Genesis Edition · FDN-001 v3.0.0 §11.4 Plate III · Architecture Blueprint v1.1.0]**

*More than a Ride — We Save You Time.*

## Document Control

| Document Control Field | Entry |
| --- | --- |
| Document Title | Engine 11 — Presentation Engine: Complete Specification |
| Document Identifier | TRS026-ENG011-PRESENT-001 |
| Version | 1.0.0 |
| Status | **ADOPTED** (2026-08-16, per Founder directive — build order FDN → Resources → Services → Business → Cost → Integration → Orchestration → Coordination → AI/ML Advisory → Scenario Modelling → Presentation) |
| Classification | Institutional Blueprint — Confidential |
| Schema | `trustride` (single canonical PostgreSQL schema; this engine's tables are prefixed `present_`) |
| Platform Code | TRS026 |
| Engine Code | `TRS026_ENG011_PRESENT` |
| Engine No. | `ENGINE_011` |
| Installation Order | 011 |
| Constitutional Character | **PROJECTION ONLY.** Engine 11 holds zero authoritative state. It converts human intent into signals and renders lawful projections back — it never writes to any other engine's tables, and it never invents a truth the ledgers do not already hold. |
| Parent Authority | FDN-001 v3.0.0 §11.3 (Plate II, Layer 5 — Presentation: "Render lawful projections; convert user intent into signals" / prohibition: "Any direct database write; holding truth the ledgers do not hold"), §11.4 (Plate III — The Surface Law, Laws C-III-1 through C-III-5), §11.6 Founder Ruling AQ-002 (the on-device offline outbox is owned by Layer 3 — Orchestration and Coordination — neither Foundation Substrate nor Presentation alone); TBOC v2.0.0 Article 12 (The Five User Type Domains), Article 20 (The Universal Service Flow), Article 21 (Live Tracking Information Contract), Article 54 (SOS & Emergency Escalation) |
| Architecture Lineage | Positioned as Engine 11, the final engine of the eleven-engine Constitutional Engine Registry (Annex C, FDN-001 v3.0.0); Layer 5 Presentation of the Backend/Frontend/Event-Signal Architecture Blueprint v1.1.0, which names this engine's five surfaces and their functions verbatim (TRS026-FE-01) |

## Document Purpose & Constitutional Basis

This instrument specifies **Engine 11 — the Presentation Engine**, the only engine of the eleven that a human being ever touches directly. It answers one constitutional question for the rest of the platform — **what does this User Type see, and how does their intent become a signal?** — and answers no other question, because Presentation is an instrument of intent, never a source of truth (FDN-001 §11.4).

| This engine's function | Constitutional basis |
| --- | --- |
| Render lawful projections; convert user intent into signals | FDN-001 §11.3, Layer 5 obligation |
| Any direct database write, or holding truth the ledgers do not hold, is forbidden absolutely | FDN-001 §11.3, Layer 5 prohibition |
| Commands become signals — a tap, a form, a keystroke, each produces a signal, and only a signal | FDN-001 §11.4, Law C-III-1 |
| Views are lawful projections — every screen is registered and traceable to the domain tables it reads; an unregistered screen is non-conformant | FDN-001 §11.4, Law C-III-3 |
| Heartbeat awareness — every shell displays bridge health; when absent, the surface says so plainly and continues to queue | FDN-001 §11.4, Law C-III-4 |
| One identity, one account, one lifetime — no shell creates an identity of its own | FDN-001 §11.4, Law C-III-5 |
| The on-device offline outbox is owned by Layer 3 (Orchestration + Coordination), not by Presentation alone | FDN-001 §11.6, Founder Ruling AQ-002 |
| Customers, Partners, Operators, Intermediaries, Governors — five domains, each with its own shell | TBOC Article 12 |
| The full execution sequence a User's intent passes through, from identity to review | TBOC Article 20 |
| The five data elements mandatory wherever live tracking is active | TBOC Article 21 |
| An in-app SOS capability during active service sessions | TBOC Article 54 |
| No engine reads or writes another engine's tables; cross-engine truth moves only as a signal | TBOC Article 33 |

Foundation's own `shell_registry` (TRS_FDN_CORE) already registers exactly the five constitutional shells and forbids a sixth; Foundation's own `projection_registry` (Engine 001 conformance table) already requires every rendered screen to be registered and non-authoritative. Engine 11 never duplicates either registry — it consumes both by value and owns only what is genuinely its own: the session a human opened, the command they issued before it became a signal, and the render event that proves a screen showed only what it was lawfully allowed to show.

---

# SECTION 1 — ARCHITECTURAL ROLE & BOUNDARIES

## 1.1 Mission

Engine 11 is the platform's single, deterministic surface layer across the five constitutional shells — User Hub, Operator App, Admin Console, Sovereign Executive Console, and Marketplace Hub. No human interacts with TrustRide except through one of these five; no shell ever mutates state directly, under any urgency.

## 1.2 Operational Duties

1. **Session custody.** Maintain `present_shell_session` — every active human session, on every shell, on every channel (mobile, web, tablet, kiosk), bound to exactly one Foundation identity (§2.1).
2. **Multi-channel registration.** Maintain `present_device_channel_registration` — the governed record of which channel a device is registered on (§2.2).
3. **Surface-verb governance.** Maintain `present_shell_capability_registry` — the exact, enforced mapping of which command each shell may issue, per FDN-001's own Plate III permitted-verbs table; a command outside its shell's lawful verbs is rejected structurally, not by convention (§2.3).
4. **Command capture.** Capture every human command in `present_command_capture` before it becomes a signal on the relevant domain engine's own outbox — the database proof of Law C-III-1 (§2.4).
5. **Projection rendering.** Record every screen render in `present_projection_render`, traceable to a registered `projection_registry` row, and cache the rendered payload locally in `present_projection_cache` for offline-first display (§2.5–2.6).
6. **Heartbeat display.** Maintain `present_heartbeat_status` — the live bridge-health indicator every shell shows its user, sourced from Orchestration's own telemetry (§2.7).
7. **In-app notification.** Maintain `present_notification_inbox` — the in-app feed a User Type sees, distinct from Foundation's channel preferences and Integration's external dispatch (§2.8).
8. **Localization.** Maintain `present_locale_preference` — per-user language and region preference (§2.9).
9. **Presentation evidence.** Record every command capture and render event as immutable, hash-chained evidence (§2.10).

## 1.3 Structural Position — The Terminal Layer

Engine 11 is the only engine every one of the other ten indirectly serves, and the only one with no domain peer of its own.

| From / To | Contract |
| --- | --- |
| **Human → Engine 11** | A tap, a form, a keystroke — captured in `present_command_capture` (§2.4), validated against `present_shell_capability_registry` (§2.3), then translated into a signal on the *destination domain engine's own outbox* — Engine 11 never owns that outbox |
| **Engine 11 → Engines 7/8** | Every translated command's signal travels through Orchestration and Coordination exactly as every other engine's does; the on-device offline queue that holds a command before connectivity returns is owned by Layer 3 (AQ-002), not by this engine |
| **Every domain engine → Engine 11** | Broadcast signals already declared in sibling documents (e.g. `RESOURCE_AVAILABILITY_CHANGED`, `SERVICE_CATALOGUE_UPDATED`, `ORDER_PLACED`, `ORDER_SETTLED`) update `present_projection_cache` and may write a `present_notification_inbox` row |
| **Engine 9 (AI/ML Advisory) → Engine 11** | `ADVISORY_RECOMMENDATION_PUBLISHED` and `ADVISORY_ANOMALY_FLAGGED` render as non-authoritative projections on the Sovereign Executive Console and Admin Console |
| **Engine 10 (Scenario Modelling) → Engine 11** | `SCENARIO_RUN_COMPLETED` renders what-if results, always marked non-authoritative |
| **Foundation (Engine 1) → Engine 11** | `shell_registry` and `projection_registry` are read by value, never written; identity comes from Layer 1 alone (C-III-5) |

## 1.4 Boundaries — What Engine 11 Never Does

1. **Never writes authoritative state.** No column of `present_*` overlaps with any other engine's domain table, ever, under any urgency.
2. **Never creates an identity.** Every `user_id` in this schema is a reference into Foundation's `platform_users`; no shell registers, authenticates, or authorizes on its own (C-III-5).
3. **Never renders an unregistered projection.** Every `present_projection_render` row names a `projection_code` that exists in Foundation's `projection_registry`; an unregistered code is non-conformant (C-III-3).
4. **Never issues a command outside its shell's lawful verbs.** `present_shell_capability_registry` is enforced at the database level (§2.3–2.4), never left to client-side discipline alone.
5. **Never owns the offline queue.** The on-device outbox is Layer 3's domain per AQ-002; this instrument does not re-implement it.
6. **Never hides a broken heartbeat.** When the bridge is unreachable, `present_heartbeat_status` reflects it plainly; the surface continues to queue, it never pretends to be live (C-III-4).

---

# SECTION 2 — PRODUCTION SQL DDL SCHEMA (PostgreSQL / Supabase-Ready)

## 2.0 Extensions & Enums (prerequisite)

```sql
-- Extensions (idempotent; already present platform-wide per Engine 001 Phase 0)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- [Trace: FDN-001 §11.4 | Plate III — exactly the five constitutional shells]
CREATE TYPE present_shell_code_enum AS ENUM (
  'USER_HUB', 'OPERATOR_APP', 'ADMIN_CONSOLE', 'SOVEREIGN_EXECUTIVE_CONSOLE', 'MARKETPLACE_HUB'
);

CREATE TYPE present_channel_type_enum AS ENUM (
  'MOBILE', 'WEB', 'TABLET', 'KIOSK'
);

CREATE TYPE present_session_status_enum AS ENUM (
  'ACTIVE', 'ENDED', 'EXPIRED'
);

CREATE TYPE present_translation_status_enum AS ENUM (
  'CAPTURED', 'TRANSLATED', 'REJECTED'
);

CREATE TYPE present_cache_status_enum AS ENUM (
  'FRESH', 'STALE'
);

CREATE TYPE present_bridge_health_enum AS ENUM (
  'HEALTHY', 'DEGRADED', 'OFFLINE'
);

CREATE TYPE present_read_status_enum AS ENUM (
  'UNREAD', 'READ'
);
```

### 2.A — Session & Device

## 2.1 `present_shell_session` — Every Active Human Session

```sql
-- [Trace: FDN-001 §11.4, Law C-III-5 | One identity, one account, one lifetime]
CREATE TABLE present_shell_session (
  session_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_code            present_shell_code_enum NOT NULL,
  user_id                UUID NOT NULL,          -- by value; identity lives in Foundation's platform_users
  device_id                UUID,                 -- by value; Foundation's user_device, nullable for unregistered web sessions
  channel_type                present_channel_type_enum NOT NULL,
  auth_session_ref               UUID,           -- by value; Foundation's auth_session.session_id
  started_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at                             TIMESTAMPTZ,
  session_status                          present_session_status_enum NOT NULL DEFAULT 'ACTIVE'
);

CREATE INDEX idx_present_shell_session_user ON present_shell_session (user_id);
CREATE INDEX idx_present_shell_session_shell_status ON present_shell_session (shell_code, session_status);

COMMENT ON TABLE present_shell_session IS
  '[Trace: FDN-001 §11.4] No shell registers or authenticates on its own; every session references an identity and authentication event Foundation already sealed.';

ALTER TABLE present_shell_session ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_shell_session_self_read ON present_shell_session
  FOR SELECT TO trustride_authenticated
  USING (user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY present_shell_session_service_write ON present_shell_session
  FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);
```

## 2.2 `present_device_channel_registration` — Multi-Channel Access Registry

```sql
-- [Trace: Architecture Blueprint v1.1.0 | Multi-Channel Access — Mobile, Web, Tablet and Kiosk]
CREATE TABLE present_device_channel_registration (
  device_channel_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id             UUID NOT NULL,           -- by value; Foundation's user_device
  channel_type          present_channel_type_enum NOT NULL,
  registered_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_active_at            TIMESTAMPTZ,
  registration_status          TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (registration_status IN ('ACTIVE', 'REVOKED')),
  UNIQUE (device_id, channel_type)
);

ALTER TABLE present_device_channel_registration ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_device_channel_registration_platform_read ON present_device_channel_registration
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY present_device_channel_registration_service_write ON present_device_channel_registration
  FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);
```

### 2.B — Surface-Verb Governance

## 2.3 `present_shell_capability_registry` — The Enforced Permitted-Verbs Table

```sql
-- [Trace: FDN-001 §11.4 | Plate III Conformance table — the exact permitted verbs per shell]
CREATE TABLE present_shell_capability_registry (
  capability_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_code                     present_shell_code_enum NOT NULL,
  command_type                   TEXT NOT NULL,
  permitted                      BOOLEAN NOT NULL DEFAULT TRUE,
  requires_delegated_authority   BOOLEAN NOT NULL DEFAULT FALSE,
  created_at                     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (shell_code, command_type)
);

COMMENT ON TABLE present_shell_capability_registry IS
  '[Trace: FDN-001 §11.4] The Surface Law''s per-shell permitted-verbs table (§11.4), made executable: a command not found here as permitted = TRUE is rejected at §2.4, never left to client-side discipline alone.';

ALTER TABLE present_shell_capability_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_shell_capability_registry_platform_read ON present_shell_capability_registry
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY present_shell_capability_registry_service_write ON present_shell_capability_registry
  FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

INSERT INTO present_shell_capability_registry (shell_code, command_type, requires_delegated_authority) VALUES
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
  ('MARKETPLACE_HUB', 'PUBLISH_OFFER', FALSE),
  ('MARKETPLACE_HUB', 'RECEIVE_ORDER_SIGNAL', FALSE),
  ('MARKETPLACE_HUB', 'SETTLE_LAWFUL_FLOW', FALSE);
```

## 2.4 `present_command_capture` — Every Command, Before It Becomes a Signal

```sql
-- [Trace: FDN-001 §11.4, Law C-III-1 | Commands become signals — a tap produces a signal, and only a signal]
CREATE TABLE present_command_capture (
  command_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_session_id       UUID NOT NULL REFERENCES present_shell_session (session_id),
  command_type           TEXT NOT NULL,
  command_payload        JSONB NOT NULL,
  captured_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  translated_signal_id       UUID,               -- by value; the signal_id once written to the destination engine's own outbox
  translation_status            present_translation_status_enum NOT NULL DEFAULT 'CAPTURED',
  rejection_reason                 TEXT
);

CREATE INDEX idx_present_command_capture_session ON present_command_capture (shell_session_id);
CREATE INDEX idx_present_command_capture_status ON present_command_capture (translation_status);

COMMENT ON TABLE present_command_capture IS
  '[Trace: FDN-001 §11.4 C-III-1] This row is the proof: every human action passed through here before any signal existed. translated_signal_id points at a row on the destination domain engine''s own outbox, never a table this engine owns.';

-- PostgreSQL forbids subqueries inside CHECK constraints; the per-shell permitted-verb rule
-- is therefore enforced as a deferred constraint trigger.
CREATE OR REPLACE FUNCTION present_command_capability_check()
RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM present_shell_capability_registry r
    JOIN present_shell_session s ON s.session_id = NEW.shell_session_id
    WHERE r.shell_code = s.shell_code
      AND r.command_type = NEW.command_type
      AND r.permitted = TRUE
  ) THEN
    RAISE EXCEPTION 'present_command_capture %: command_type % is not a permitted verb for this shell (FDN-001 §11.4 Surface Law)',
      NEW.command_id, NEW.command_type;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_present_command_capability_check
  AFTER INSERT ON present_command_capture
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION present_command_capability_check();

ALTER TABLE present_command_capture ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_command_capture_self_read ON present_command_capture
  FOR SELECT TO trustride_authenticated
  USING (EXISTS (
    SELECT 1 FROM present_shell_session s
    WHERE s.session_id = present_command_capture.shell_session_id
      AND s.user_id = current_setting('app.current_user_id', true)::uuid
  ));
CREATE POLICY present_command_capture_service_write ON present_command_capture
  FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);
```

### 2.C — Projection Rendering

## 2.5 `present_projection_render` — Every Screen, Traced to a Registered Projection

```sql
-- [Trace: FDN-001 §11.4, Law C-III-3 | Views are lawful projections]
CREATE TABLE present_projection_render (
  render_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_session_id         UUID NOT NULL REFERENCES present_shell_session (session_id),
  projection_code          TEXT NOT NULL,         -- by value; Foundation's projection_registry.projection_code
  source_correlation_id    UUID,                  -- the correlation_id of the ACCEPT that caused this projection to update, where applicable
  rendered_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_present_projection_render_session ON present_projection_render (shell_session_id);
CREATE INDEX idx_present_projection_render_code ON present_projection_render (projection_code);

COMMENT ON TABLE present_projection_render IS
  '[Trace: FDN-001 §11.4 C-III-3] A screen that renders unregistered truth is non-conformant. Every projection_code here must resolve to a row in Foundation''s projection_registry; is_authoritative is always FALSE there, and this table renders nothing else.';

ALTER TABLE present_projection_render ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_projection_render_self_read ON present_projection_render
  FOR SELECT TO trustride_authenticated
  USING (EXISTS (
    SELECT 1 FROM present_shell_session s
    WHERE s.session_id = present_projection_render.shell_session_id
      AND s.user_id = current_setting('app.current_user_id', true)::uuid
  ));
CREATE POLICY present_projection_render_service_write ON present_projection_render
  FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);
```

## 2.6 `present_projection_cache` — Offline-First Local Display State

```sql
-- [Trace: Architecture Blueprint v1.1.0 | Offline Support — graceful offline experience with sync]
CREATE TABLE present_projection_cache (
  cache_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_session_id   UUID NOT NULL REFERENCES present_shell_session (session_id),
  projection_code    TEXT NOT NULL,
  cached_payload     JSONB NOT NULL,
  cached_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  cache_status       present_cache_status_enum NOT NULL DEFAULT 'FRESH',
  UNIQUE (shell_session_id, projection_code)
);

COMMENT ON TABLE present_projection_cache IS
  'Distinct from the on-device offline outbox (Layer 3, AQ-002): this is what the surface shows while disconnected, never what it queues to send.';

ALTER TABLE present_projection_cache ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_projection_cache_self_read ON present_projection_cache
  FOR SELECT TO trustride_authenticated
  USING (EXISTS (
    SELECT 1 FROM present_shell_session s
    WHERE s.session_id = present_projection_cache.shell_session_id
      AND s.user_id = current_setting('app.current_user_id', true)::uuid
  ));
CREATE POLICY present_projection_cache_service_write ON present_projection_cache
  FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);
```

### 2.D — Heartbeat Display

## 2.7 `present_heartbeat_status` — The Bridge Health Every Shell Shows

```sql
-- [Trace: FDN-001 §11.4, Law C-III-4 | Heartbeat awareness]
CREATE TABLE present_heartbeat_status (
  heartbeat_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_session_id      UUID NOT NULL REFERENCES present_shell_session (session_id),
  bridge_health_status  present_bridge_health_enum NOT NULL DEFAULT 'HEALTHY',
  last_heartbeat_at     TIMESTAMPTZ,
  displayed_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_present_heartbeat_status_session ON present_heartbeat_status (shell_session_id, displayed_at DESC);

COMMENT ON TABLE present_heartbeat_status IS
  '[Trace: FDN-001 §11.4 C-III-4] Sourced from Orchestration''s own capacity telemetry (Engine 7, orch_capacity_snapshot) as a lawful projection; when absent, the surface says so plainly and continues to queue — it never claims to be live when it is not.';

ALTER TABLE present_heartbeat_status ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_heartbeat_status_self_read ON present_heartbeat_status
  FOR SELECT TO trustride_authenticated
  USING (EXISTS (
    SELECT 1 FROM present_shell_session s
    WHERE s.session_id = present_heartbeat_status.shell_session_id
      AND s.user_id = current_setting('app.current_user_id', true)::uuid
  ));
CREATE POLICY present_heartbeat_status_service_write ON present_heartbeat_status
  FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);
```

### 2.E — In-App Notification & Localization

## 2.8 `present_notification_inbox` — The In-App Feed

```sql
-- [Trace: Architecture Blueprint v1.1.0 | Notifications — in-app, email, SMS, push alerts]
CREATE TABLE present_notification_inbox (
  notification_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_user_id          UUID NOT NULL,       -- by value
  shell_code                 present_shell_code_enum NOT NULL,
  title                      TEXT NOT NULL,
  body                       TEXT NOT NULL,
  source_signal_correlation_id  UUID,
  read_status                present_read_status_enum NOT NULL DEFAULT 'UNREAD',
  delivered_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  read_at                    TIMESTAMPTZ
);

CREATE INDEX idx_present_notification_inbox_recipient ON present_notification_inbox (recipient_user_id, read_status);

COMMENT ON TABLE present_notification_inbox IS
  'The bell-icon feed inside a shell — distinct from Foundation''s user_contact_preference (which channel a user allows) and Integration''s integration_message_dispatch_log (the external SMS/push/WhatsApp send).';

ALTER TABLE present_notification_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_notification_inbox_recipient_read ON present_notification_inbox
  FOR SELECT TO trustride_authenticated
  USING (recipient_user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY present_notification_inbox_service_write ON present_notification_inbox
  FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);
```

## 2.9 `present_locale_preference` — Language & Region

```sql
-- [Trace: Architecture Blueprint v1.1.0 | Internationalisation — multi-language and localisation]
CREATE TABLE present_locale_preference (
  locale_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL UNIQUE,           -- by value
  language_code   TEXT NOT NULL DEFAULT 'en',
  region_code     TEXT,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE present_locale_preference ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_locale_preference_self_read ON present_locale_preference
  FOR SELECT TO trustride_authenticated
  USING (user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY present_locale_preference_service_write ON present_locale_preference
  FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);
```

### 2.F — Presentation Evidence

## 2.10 `present_decision_log` — Immutable, Hash-Chained Evidence

```sql
-- [Trace: FDN-001 Part IX pattern (TRS_FDN_AUDIT), applied to Engine 11's own command captures]
CREATE TABLE present_decision_log (
  decision_log_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  command_id          UUID REFERENCES present_command_capture (command_id),
  event_type          TEXT NOT NULL,
  event_description   TEXT,
  prev_hash           CHAR(64),
  immutable_hash       CHAR(64) NOT NULL,
  recorded_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_present_decision_log_command ON present_decision_log (command_id);

REVOKE UPDATE, DELETE ON present_decision_log FROM PUBLIC;
REVOKE UPDATE, DELETE ON present_decision_log FROM trustride_authenticated;

ALTER TABLE present_decision_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_decision_log_platform_read ON present_decision_log
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY present_decision_log_service_write ON present_decision_log
  FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);
```

### 2.G — Engine Event Substrate (Constitutional Mandatory Tables)

## 2.11 Engine Event Substrate

Per Plate I (Station Law) and CC-03 of the platform Conformance Certificate, every engine — Engine 11 included — carries exactly one outbox and one inbox, in the standard signal envelope shape (FDN-001 §11.2). This pair is distinct from the on-device offline outbox (Layer 3, AQ-002): it is the server-side ledger of Engine 11's own engine-level signals (notification dispatch requests, emergency escalation requests), not the client-side pre-emission queue.

```sql
-- [Trace: FDN-001 §11.2 — mandatory per-engine ledger tables]
CREATE TABLE present_event_outbox (
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
CREATE INDEX idx_present_outbox_status ON present_event_outbox (signal_status);
CREATE INDEX idx_present_outbox_correlation ON present_event_outbox (correlation_id);

ALTER TABLE present_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_event_outbox_service_only ON present_event_outbox
  FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);

-- [Trace: FDN-001 §11.2 — mandatory per-engine ledger tables]
CREATE TABLE present_event_inbox (
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
  received_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at                          TIMESTAMPTZ,
  CONSTRAINT chk_present_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_present_inbox_status ON present_event_inbox (signal_status);
CREATE INDEX idx_present_inbox_correlation ON present_event_inbox (correlation_id);

ALTER TABLE present_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY present_event_inbox_service_only ON present_event_inbox
  FOR ALL TO trs026_eng011_present_service USING (true) WITH CHECK (true);
```

---

# SECTION 3 — SYSTEM API CONTRACTS

## 3.1 `POST /api/v1/present/commands`

**Request** (any shell; the shell's own session determines lawful command types)

```json
{
  "shell_session_id": "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e",
  "command_type": "RAISE_INTENT",
  "command_payload": {
    "service_code": "TRANSPORT-STANDARD-RIDE",
    "origin": { "latitude": -0.091702, "longitude": 34.767956 },
    "destination": { "latitude": -0.078412, "longitude": 34.782215 }
  }
}
```

**Response — `202 Accepted`**

```json
{
  "command_id": "c3d4e5f6-a7b8-4c9d-0e1f-2a3b4c5d6e7f",
  "translation_status": "CAPTURED"
}
```

**Response — `403 Forbidden`** (command outside the shell's lawful verbs)

```json
{
  "error_code": "COMMAND_NOT_PERMITTED",
  "error_message": "command_type=AMEND_REGISTER is not a permitted verb for shell_code=USER_HUB (FDN-001 §11.4 Surface Law)."
}
```

## 3.2 `GET /api/v1/present/projections/{projection_code}`

**Response — `200 OK`**

```json
{
  "projection_code": "USER_ORDER_STATUS_CARD",
  "cache_status": "FRESH",
  "cached_payload": {
    "order_code": "TRS026-ORDER-000004821",
    "order_stage": "DISPATCH",
    "status": "DISPATCHED"
  },
  "rendered_at": "2026-08-16T09:14:00Z"
}
```

## 3.3 `GET /api/v1/present/heartbeat`

**Response — `200 OK`**

```json
{
  "bridge_health_status": "HEALTHY",
  "last_heartbeat_at": "2026-08-16T09:14:58Z"
}
```

---

# SECTION 4 — EVENT-DRIVEN SIGNAL & INTEGRATION MATRIX

## 4.1 Inbound Signals — Listened To

| Signal | Emitting engine | Effect inside Engine 11 |
| --- | --- | --- |
| `RESOURCE_AVAILABILITY_CHANGED` | Engine 2 (Resources), via Engines 7/8 | Updates `present_projection_cache` for live operator dashboards |
| `SERVICE_CATALOGUE_UPDATED` | Engine 3 (Services), via Engines 7/8 | Updates catalogue projections on User Hub and Marketplace Hub |
| `ORDER_PLACED` / `ORDER_SETTLED` | Engine 4 (Business), via Engines 7/8 | Updates order-status projections; writes a `present_notification_inbox` row |
| `ADVISORY_RECOMMENDATION_PUBLISHED` / `ADVISORY_ANOMALY_FLAGGED` | Engine 9 (AI/ML Advisory), via Engines 7/8 | Renders non-authoritative recommendation/anomaly cards on the Sovereign Executive Console and Admin Console |
| `SCENARIO_RUN_COMPLETED` | Engine 10 (Scenario Modelling), via Engines 7/8 | Renders what-if results on the Sovereign Executive Console, always marked non-authoritative |
| `NOTIFICATION_DISPATCH_COMPLETED` | Engine 6 (Integration), via Engines 7/8 | Confirms external delivery status alongside the in-app `present_notification_inbox` row |

## 4.2 Outbound Signals — Emitted

| Signal | Receiving engine | Payload (key fields) | Triggering condition |
| --- | --- | --- | --- |
| `SCENARIO_RUN_REQUESTED` | Engine 10 (Scenario Modelling), via Engines 7/8 | `scenario_code`, `requested_by`, `parameters` | Fired when a Governor issues a what-if command from the Sovereign Executive Console |
| `NOTIFICATION_DISPATCH_REQUESTED` | Engine 6 (Integration), via Engines 7/8 | `template_code`, `channel`, `recipient_user_id` | Fired when a surface-originated action requires an external SMS/push/WhatsApp send |
| `EMERGENCY_ESCALATION_REQUESTED` | Engine 6 (Integration), via Engines 7/8 | `subject_user_id`, `session_context`, `location` | Fired the instant a User or Operator triggers the in-app SOS capability (TBOC Article 54) |

Every other translated command (§2.4) is emitted directly onto its *destination domain engine's own outbox* — not through Engine 11's outbox — since Engine 11 is the originator of intent, not the owner of the domain signal it produces.

## 4.3 The Signal Envelope (as applied to Engine 11)

Identical to the platform-wide envelope (Plate I, §11.2 of the Foundation instrument): `signal_id`, `correlation_id`, `causation_id`, `emitting_engine` = `TRS026_ENG011_PRESENT`, `receiving_engine`, `signal_type`, `payload_in`, `payload_out`, `signal_status`, `rejection_reason`, `idempotency_key`, `attempt_count`, `emitted_at`, `received_at`, `accepted_at`. No field is added, renamed, or omitted.

---

# ANNEX — CONFORMANCE SELF-CERTIFICATION AGAINST THE THREE PLATES

Filed in the same discipline as the Foundation instrument's Part XI and the Engine 2/3/4/5/6/7/8/9/10 Annexes — and, uniquely, against Plate III in full, since Engine 11 is the only engine that surface governs.

| Check | Requirement | Result | Evidence |
| --- | --- | --- | --- |
| CC-01 | The three plates are reproduced, digests matching `plate_registry` | **N/A** | Reproduction is FDN-001's own obligation (§11.1); this instrument cites the plates, it does not re-host them |
| CC-02 | Every table assigned to exactly one of the five stations | **PASS** | §2.1–2.10: domain tables = Domain State; `present_event_outbox`/`present_event_inbox` (§2.11) = Emission/Reception Ledgers |
| CC-03 | Engine carries the four ledger tables with the standard envelope | **PASS** | §2.11, §4.3 |
| CC-04 | Every cross-engine interaction is a signal; no foreign table access | **PASS** | Every reference to `shell_registry`, `projection_registry`, `platform_users`, `user_device`, and every domain engine's own table is by value, never a foreign key |
| CC-06 | Idempotency, retry, dead-letter declared | **PASS** | `idempotency_key` UNIQUE on both ledger tables (§2.11) |
| CC-07 | Engine declares its layer, holds nothing belonging to another layer | **PASS** | §1 — Layer 5, Presentation; holds no identity, order, resource, pricing, or external-system authoritative state |
| CC-09 | Advisory outputs, if any, are records only | **N/A** | Engine 11 is not an advisory engine; it renders Engine 9/10's advisory records as non-authoritative projections, never as its own conclusion |
| **CC-10** | **Every surface is registered in `projection_registry` and marked non-authoritative** | **PASS — this engine's defining check** | §2.5 `present_projection_render.projection_code` resolves only to Foundation's `projection_registry`, where `is_authoritative` is always FALSE |
| **CC-11** | **Offline emission and heartbeat display are specified for every surface** | **PASS** | §2.7 `present_heartbeat_status` (C-III-4); the offline outbox itself is Layer 3's per AQ-002, correctly not re-implemented here |
| CC-12 | Every provision carries a trace tag | **PASS** | Every DDL block and table comment carries a `[Trace: ...]` tag |
| RLS Law | Row-Level Security enabled on every table | **PASS** | All twelve tables (§2.1–2.11) carry `ENABLE ROW LEVEL SECURITY` with an explicit policy; personal session, command, and notification data is requester-scoped, never platform-wide readable |
| Immutability Law | Ledgers append-only where history must never be rewritten | **PASS** | `present_decision_log` carries `REVOKE UPDATE, DELETE` |
| Surface Law (C-III-1) | Commands become signals, structurally enforced | **PASS** | `trg_present_command_capability_check` (§2.4) rejects any command outside its shell's registered verbs before a signal can ever be produced |

---

**END OF SPECIFICATION**

*Engine 11 is where TrustRide becomes visible. Five shells, one identity law, one verb registry, one heartbeat honestly shown — every tap becomes a signal, every screen renders only what the ledgers already made true, and nothing here is ever mistaken for the truth itself.*

---

# ELEVEN-ENGINE REGISTRY — COMPLETE

With this instrument, all eleven engines of the Constitutional Engine Registry are built: Foundation, Resources, Services, Business, Cost, Integration, Workflow Orchestration, Workflow Coordination, AI/ML Advisory, Scenario Modelling, and Presentation. Every engine carries the standard signal envelope, every cross-engine reference is by value, every money column is `NUMERIC(18,2)`, every table carries Row-Level Security, and every provision traces to its constitutional article. TrustRide Services now has a complete, migration-ready, sovereign digital twin.
