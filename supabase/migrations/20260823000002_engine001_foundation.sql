-- ============================================================================
-- TRUSTRIDE SERVICES PLATFORM
-- ============================================================================
-- PLATFORM ID          : b302bb5d-7d20-41e9-a074-a18d8ebd2aa5
-- PLATFORM CODE        : TRS026
-- PLATFORM NAME        : TRUSTRIDE_SERVICES
-- SCHEMA               : trustride
-- ENGINE NO            : ENGINE_001
-- ENGINE ID            : 0fc9e941-4725-43bd-b5eb-6ea76a66046a
-- ENGINE CODE          : TRS026_ENG001_FDN
-- ENGINE DOMAIN        : Platform Foundation
-- ENGINE CLASS         : Foundation Engine
-- ENGINE TYPE          : Constitutional Runtime
-- ENGINE NAME          : TrustRide Foundation
-- ENGINE DESCRIPTION   : The sovereign platform brain -- identity, authority,
--                        audit, vocabulary, geography, sequence, and the
--                        signal substrate every one of the eleven engines
--                        depends on.
-- ENGINE FUNCTION      : Constitutes five sub-engines, installed in this
--                        exact order per Founder ruling 2026-08-21/23:
--                        Shared Runtime Substrate, TrustRide Core, TrustRide
--                        Identity, TrustRide Governance, TrustRide Audit.
-- PLATFORM VERSION     : 1.0.0
-- ENGINE VERSION       : 1.0.0
-- MIGRATION DATA
-- FILE NAME            : 20260823000002_engine001_foundation.sql
-- INSTALLATION ORDER   : 001
-- STATUS               : COMPLETE -- one single migration file, all five
--                        sub-engines, 92 tables, applied to a genuinely
--                        clean database after the 20260823000001 reset.
-- CREATED AT           : 2026-08-23
-- CREATED BY           : Onyango Albert Chitayi (Founder) + Engineering
-- ============================================================================
--
-- Corrections applied in this rewrite, relative to both the original Annex H
-- compilation and the superseded Substrate-only file (20260821000001):
--   1. Complete Annex D.1 manifest header (PLATFORM ID / ENGINE ID /
--      MIGRATION DATA), which Annex H's own worked example omitted.
--   2. Phase 9 (Indexes) compiled literally per table, not a "pattern".
--   3. Phase 6 (Functions) and Phase 7 (Triggers) populated wherever this
--      engine genuinely needs them -- sequence issuance, semantic
--      versioning, the audit hash-chain, role/authority checks -- none of
--      which existed anywhere in Annex H.
--   4. Phase 11 grants explicitly bridge the custom roles to Supabase's own
--      `authenticated` and `service_role`, or the RLS policies below are
--      unreachable through a normal client connection.
--   5. Role naming aligned to `trs026_eng{NNN}_{abbrev}_service`, matching
--      Engines 2-11, replacing Annex H's inconsistent short-form roles.
--   6. ENGINE CLASS / ENGINE TYPE reflect the Founder's Sovereign Engine
--      Registry, adopted 2026-08-21 as an amendment to FDN-001 Annex C.
--   7. REAL BUG FOUND AND FIXED (2026-08-23, caught by the live db push of
--      the superseded file): Annex E numbers RLS as Phase 8 and Privilege
--      Lockdown as Phase 11, but `CREATE POLICY ... TO <role>` requires the
--      role to physically exist first. The two custom roles are therefore
--      created immediately below (Phase 1), NOT at the numbered Phase 11
--      position -- Phase 11 below still carries the actual GRANT statements
--      (which correctly wait until every table exists), and this reordering
--      is documented here rather than silently applied.
--   8. RLS is scoped correctly this time, table by table: governed
--      reference/vocabulary data is blanket-readable (Substrate, most of
--      Governance); personal profile data (Identity) and sensitive event
--      data (Audit) are NOT blanket-readable, the exact mistake Annex H
--      made and applied indiscriminately to all 92 Foundation tables.
--   9. Registration & Authentication Flow (Founder ruling 2026-08-23) added
--      as five new Phase 6 functions -- fn_registration_capture_primary,
--      fn_verification_completed_accept, fn_registration_retry_primary,
--      fn_secondary_profile_submit, fn_my_registration_status -- hardening
--      fn_user_register with a mandatory Primary gate (Real Legal Names +
--      Person Status + KRA PIN, ALL must pass) before an account activates,
--      plus a soft, non-blocking Secondary reconciliation step. No new
--      tables; platform_users gains two new status values used as plain
--      TEXT (PENDING_VERIFICATION, VERIFICATION_FAILED), no schema change.
--      Article 33 respected throughout: the actual government identity call
--      stays behind Engine 6 Integration's boundary -- Foundation only
--      captures the request and consumes the VERIFICATION_COMPLETED result.
--   10. REAL BUG FOUND AND FIXED (2026-08-23, caught by actually invoking the
--      registration flow end-to-end against a live Postgres instance, then
--      independently re-walking the resulting chain -- not by inspection):
--      fn_audit_log_append picked its prev_hash via
--      `ORDER BY occurred_at DESC, audit_id DESC LIMIT 1`. occurred_at is
--      transaction_timestamp(), constant for an entire transaction, so any
--      two audit_log_append calls in the same transaction (the normal case
--      -- e.g. fn_user_register logs once, its caller logs again) always
--      tie; audit_id is a random UUID, so once two rows share an
--      occurred_at, a later call can pick the WRONG predecessor, silently
--      forking the hash chain. Fixed with a genuine monotonic chain_seq
--      identity column on audit_log; both fn_audit_log_append and
--      fn_audit_checkpoint_seal now key off chain_seq, never off
--      occurred_at/audit_id. This is exactly the kind of gap live testing
--      exists to catch -- CREATE FUNCTION never validates a chain's logic,
--      only calling it does.
--
-- Migration order within this file: Substrate -> Core -> Identity ->
-- Governance -> Audit, per the Founder's ruling that shared
-- vocabulary/event-envelope/conformance machinery must exist before the
-- engines that depend on its meaning -- superseding Annex H's originally
-- adopted "Core->Identity->Governance->Audit->Substrate" order. This
-- amendment must be reflected back into FDN-001 Annex H and Annex E's own
-- migration-order note once Foundation is fully adopted.

-- ============================================================================
-- PHASE 0 -- EXTENSIONS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- ============================================================================
-- PHASE 1 -- SCHEMA
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS trustride;
SET search_path = trustride, public;

-- Roles are Phase 11 (Privilege Lockdown) content by Annex E's own numbering,
-- but must physically exist before Phase 8's CREATE POLICY statements can
-- reference them (see Correction 7 above). Created here; GRANTed in Phase 11.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trustride_authenticated') THEN
    CREATE ROLE trustride_authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng001_fdn_service') THEN
    CREATE ROLE trs026_eng001_fdn_service NOLOGIN;
  END IF;
END
$$;

-- ============================================================================
-- PHASE 2 -- ENUMS
-- ============================================================================
-- Per the original constitutional design (Annex H), most fields across
-- Identity/Governance/Audit use TEXT + CHECK rather than a Postgres ENUM
-- type -- preserved here for fidelity. Only Substrate's event-envelope
-- vocabulary and Core's platform lifecycle state are true ENUM types.

-- Substrate
CREATE TYPE trustride.substrate_signal_status_outbox_enum AS ENUM (
  'PENDING', 'DISPATCHED', 'RECEIVED', 'ACCEPTED', 'REJECTED', 'DEAD_LETTER'
);
CREATE TYPE trustride.substrate_signal_status_inbox_enum AS ENUM (
  'RECEIVED', 'ACCEPTED', 'REJECTED', 'DEAD_LETTER'
);
CREATE TYPE trustride.substrate_calendar_day_type_enum AS ENUM (
  'BUSINESS', 'WEEKEND', 'PUBLIC_HOLIDAY'
);
CREATE TYPE trustride.substrate_zone_type_enum AS ENUM (
  'SERVICE_AREA', 'OPERATING_HUB_ZONE', 'RESTRICTED'
);
CREATE TYPE trustride.substrate_plate_code_enum AS ENUM (
  'PLATE_I', 'PLATE_II', 'PLATE_III'
);
CREATE TYPE trustride.substrate_conformance_result_enum AS ENUM (
  'PASS', 'PASS_WITH_EXCEPTION', 'FAIL'
);
CREATE TYPE trustride.substrate_founder_ruling_enum AS ENUM (
  'GRANTED', 'REFUSED', 'PENDING'
);

-- Core
-- [Trace: TBOC-v2.0.0 | Article 59] Never defined in the original Annex H
-- despite platform_status.state_code referencing it -- a real gap, closed
-- here (found during the 2026-08-20 corpus audit).
CREATE TYPE trustride.core_platform_state_enum AS ENUM (
  'INITIALIZING', 'OPERATIONAL', 'DEGRADED', 'MAINTENANCE', 'SUSPENDED'
);

-- ============================================================================
-- PHASE 3 -- TABLES · PHASE 4 -- CONSTRAINTS · PHASE 5 -- RELATIONSHIPS
-- (compiled together per table, as the corpus's own convention does)
-- ============================================================================

-- ############################################################################
-- SUB-ENGINE 1 -- SHARED RUNTIME SUBSTRATE (24 tables)
-- ############################################################################

-- ---------------------------------------------------------------------------
-- 1.A SEMANTIC LAYER
-- ---------------------------------------------------------------------------

CREATE TABLE trustride.semantic_dictionary (
  semantic_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  term_domain      TEXT NOT NULL,
  term_code        TEXT NOT NULL,
  term_label       TEXT NOT NULL,
  term_definition  TEXT NOT NULL,
  version          SMALLINT NOT NULL DEFAULT 1 CHECK (version > 0),
  effective_from   TIMESTAMPTZ NOT NULL DEFAULT now(),
  superseded_by    UUID REFERENCES trustride.semantic_dictionary (semantic_id),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (term_domain, term_code, version)
);
COMMENT ON TABLE trustride.semantic_dictionary IS
  '[Trace: TBOC-v2.0.0 Art.59] Canonical, append-only, versioned definitions for every status/outcome/severity/classification term used anywhere on the platform.';

CREATE TABLE trustride.domain_reference (
  reference_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  domain_code   TEXT NOT NULL,
  code_value    TEXT NOT NULL,
  code_label    TEXT NOT NULL,
  sort_order    SMALLINT NOT NULL DEFAULT 0,
  active        BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (domain_code, code_value)
);
COMMENT ON TABLE trustride.domain_reference IS
  '[Trace: TBOC-v2.0.0 Art.59] Governed reference codes -- user type codes, access modes, order stages, settlement states, cancellation stages, tracking statuses.';

CREATE TABLE trustride.unit_of_measure (
  unit_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  unit_code   TEXT NOT NULL UNIQUE,
  unit_name   TEXT NOT NULL,
  unit_class  TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.unit_of_measure IS
  '[Trace: TBOC-v2.0.0 Art.59] Canonical units (KM, KG, MIN) and conversion basis for catalogue, dispatch, and pricing.';

CREATE TABLE trustride.time_validity_rule (
  validity_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  validity_code  TEXT NOT NULL UNIQUE,
  description    TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.time_validity_rule IS
  '[Trace: TBOC-v2.0.0 Art.59] Canonical time-validity vocabulary for policies, prices, schedules, and standing jobs.';

-- ---------------------------------------------------------------------------
-- 1.B REFERENCE DATA
-- ---------------------------------------------------------------------------

CREATE TABLE trustride.geo_reference (
  geo_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  county_code      CHAR(2) NOT NULL,
  county_name      TEXT NOT NULL,
  sub_county_name  TEXT,
  active           BOOLEAN NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (county_code, sub_county_name)
);
COMMENT ON TABLE trustride.geo_reference IS
  '[Trace: TBOC-v2.0.0 Art.42.5] The 47 counties and sub-counties as governed reference data -- the jurisdictional grid of the business (Kisumu first).';

CREATE TABLE trustride.calendar_reference (
  calendar_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  calendar_date  DATE NOT NULL UNIQUE,
  day_type       trustride.substrate_calendar_day_type_enum NOT NULL,
  description    TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.calendar_reference IS
  '[Trace: TBOC-v2.0.0 Art.50] Kenyan public holidays and statutory calendar affecting pricing, scheduling, SLA, and statutory deadlines.';

CREATE TABLE trustride.sequence_generator (
  sequence_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sequence_code   TEXT NOT NULL UNIQUE,
  prefix          TEXT NOT NULL,
  current_value   BIGINT NOT NULL DEFAULT 0 CHECK (current_value >= 0),
  padding         SMALLINT NOT NULL DEFAULT 9 CHECK (padding > 0),
  reset_policy    TEXT NOT NULL DEFAULT 'NEVER' CHECK (reset_policy IN ('NEVER', 'ANNUAL', 'MONTHLY')),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.sequence_generator IS
  '[Trace: TBOC-v2.0.0 Art.42.5] Order numbers, receipt numbers, eTIMS invoice references, payout references, quote codes, completion certificates -- issued only from here, by fn_sequence_next().';

CREATE TABLE trustride.notification_template (
  template_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_code    TEXT NOT NULL UNIQUE,
  channel          TEXT NOT NULL CHECK (channel IN ('SMS', 'PUSH', 'WHATSAPP', 'EMAIL')),
  language_code    CHAR(2) NOT NULL DEFAULT 'en',
  subject          TEXT,
  body_template    TEXT NOT NULL,
  constitutional_ref  TEXT,
  version          SMALLINT NOT NULL DEFAULT 1 CHECK (version > 0),
  active           BOOLEAN NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.notification_template IS
  '[Trace: TBOC-v2.0.0 Art.50] Governed message templates inheriting constitutional vocabulary only -- served to Business/Presentation and dispatched via Integration.';

CREATE TABLE trustride.file_reference (
  file_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  file_class    TEXT NOT NULL,
  storage_uri   TEXT NOT NULL,
  content_hash  CHAR(64) NOT NULL,
  mime_type     TEXT,
  size_bytes    BIGINT CHECK (size_bytes IS NULL OR size_bytes >= 0),
  created_by    UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.file_reference IS
  '[Trace: TBOC-v2.0.0 Art.50] Canonical registry for institutional files (receipts, evidence exports, documents) -- storage pointer + hash, never the file itself.';

-- ---------------------------------------------------------------------------
-- 1.C GEOSPATIAL & TRACKING SUBSTRATE
-- ---------------------------------------------------------------------------

CREATE TABLE trustride.geo_zone (
  zone_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  zone_code    TEXT NOT NULL UNIQUE,
  zone_name    TEXT NOT NULL,
  zone_type    trustride.substrate_zone_type_enum NOT NULL,
  boundary     GEOMETRY(POLYGON, 4326),
  county_code  CHAR(2),
  active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.geo_zone IS
  '[Trace: TBOC-v2.0.0 Art.21] The governed spatial vocabulary and base geometries used by dispatch and tracking -- zones, service areas, named places.';

CREATE TABLE trustride.tracking_element_registry (
  element_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  element_code        TEXT NOT NULL UNIQUE CHECK (element_code IN ('RESOURCE_TYPE', 'RESOURCE_ID', 'ETA', 'STATUS', 'EXACT_LOCATION')),
  element_label       TEXT NOT NULL,
  element_definition  TEXT NOT NULL,
  mandatory           BOOLEAN NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.tracking_element_registry IS
  '[Trace: TBOC-v2.0.0 Art.21] The five constitutionally mandatory live-tracking data elements as governed vocabulary.';

CREATE TABLE trustride.tracking_session (
  tracking_session_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id               UUID NOT NULL,
  resource_thing_id    UUID,
  started_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at             TIMESTAMPTZ,
  status               TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'ENDED')),
  requester_user_id    UUID
);
COMMENT ON TABLE trustride.tracking_session IS
  '[Trace: TBOC-v2.0.0 Art.21] The session anchor binding live tracking to its Job -- active-session-only by construction.';

-- ---------------------------------------------------------------------------
-- 1.D EVENT SUBSTRATE MACHINERY (registries)
-- ---------------------------------------------------------------------------

CREATE TABLE trustride.routing_rule (
  route_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type      TEXT NOT NULL,
  source_engine   TEXT NOT NULL,
  target_engine   TEXT NOT NULL,
  route_priority  SMALLINT NOT NULL DEFAULT 0,
  active          BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (event_type, source_engine, target_engine)
);
COMMENT ON TABLE trustride.routing_rule IS
  '[Trace: TBOC-v2.0.0 Art.60] Central routing table consumed by Orchestration/Coordination -- which event types flow to which engines. Populated as each engine''s own signal matrix is built.';

CREATE TABLE trustride.idempotency_registry (
  idempotency_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  idempotency_key    TEXT NOT NULL UNIQUE,
  source_engine      TEXT NOT NULL,
  first_seen_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  outcome_ref        UUID
);
COMMENT ON TABLE trustride.idempotency_registry IS
  '[Trace: TBOC-v2.0.0 Art.60] Guarantees no event or trigger double-executes -- never double-charge, never double-notify.';

CREATE TABLE trustride.dead_letter_review (
  review_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id        UUID NOT NULL,
  source_engine   TEXT NOT NULL,
  target_engine   TEXT NOT NULL,
  failure_reason  TEXT NOT NULL,
  reviewed_by     UUID,
  resolution      TEXT,
  reviewed_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.dead_letter_review IS
  '[Trace: TBOC-v2.0.0 Art.60] Surfacing of dead-lettered events for governed resolution.';

-- ---------------------------------------------------------------------------
-- 1.E ENGINE 001 EVENT TABLES (the shared Signal Envelope, Plate I)
-- ---------------------------------------------------------------------------

CREATE TABLE trustride.platform_event_outbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id     UUID NOT NULL,
  causation_id       UUID,
  emitting_engine    TEXT NOT NULL,
  receiving_engine   TEXT NOT NULL,
  signal_type        TEXT NOT NULL,
  payload_in         JSONB NOT NULL,
  payload_out        JSONB,
  signal_status      trustride.substrate_signal_status_outbox_enum NOT NULL DEFAULT 'PENDING',
  rejection_reason   TEXT,
  idempotency_key    TEXT NOT NULL UNIQUE,
  attempt_count      INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  emitted_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  received_at        TIMESTAMPTZ,
  accepted_at        TIMESTAMPTZ,
  CONSTRAINT chk_platform_event_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
COMMENT ON TABLE trustride.platform_event_outbox IS
  '[Trace: FDN-001 §11.2] Station 2. Nothing is ever deleted from the ledgers (C-I-5).';

CREATE TABLE trustride.platform_event_orchestration (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id     UUID NOT NULL,
  causation_id       UUID,
  emitting_engine    TEXT NOT NULL,
  receiving_engine   TEXT NOT NULL,
  signal_type        TEXT NOT NULL,
  payload_in         JSONB NOT NULL,
  payload_out        JSONB,
  signal_status      trustride.substrate_signal_status_outbox_enum NOT NULL DEFAULT 'PENDING',
  rejection_reason   TEXT,
  idempotency_key    TEXT NOT NULL UNIQUE,
  attempt_count      INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  emitted_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  received_at        TIMESTAMPTZ,
  accepted_at        TIMESTAMPTZ,
  CONSTRAINT chk_platform_event_orch_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
COMMENT ON TABLE trustride.platform_event_orchestration IS
  '[Trace: FDN-001 §11.2] Station 3 (order). The bridge never authors domain truth of its own (C-I-4).';

CREATE TABLE trustride.platform_event_coordination (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id     UUID NOT NULL,
  causation_id       UUID,
  emitting_engine    TEXT NOT NULL,
  receiving_engine   TEXT NOT NULL,
  signal_type        TEXT NOT NULL,
  payload_in         JSONB NOT NULL,
  payload_out        JSONB,
  signal_status      trustride.substrate_signal_status_outbox_enum NOT NULL DEFAULT 'PENDING',
  rejection_reason   TEXT,
  idempotency_key    TEXT NOT NULL UNIQUE,
  attempt_count      INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  emitted_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  received_at        TIMESTAMPTZ,
  accepted_at        TIMESTAMPTZ,
  CONSTRAINT chk_platform_event_coord_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
COMMENT ON TABLE trustride.platform_event_coordination IS
  '[Trace: FDN-001 §11.2] Station 3 (fan-out/fan-in). Fan-in timeout is owned by Workflow Coordination (AQ-003); partial fan-in never mutates state.';

CREATE TABLE trustride.platform_event_inbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id     UUID NOT NULL,
  causation_id       UUID,
  emitting_engine    TEXT NOT NULL,
  receiving_engine   TEXT NOT NULL,
  signal_type        TEXT NOT NULL,
  payload_in         JSONB NOT NULL,
  payload_out        JSONB,
  signal_status      trustride.substrate_signal_status_inbox_enum NOT NULL DEFAULT 'RECEIVED',
  rejection_reason   TEXT,
  idempotency_key    TEXT NOT NULL UNIQUE,
  attempt_count      INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  emitted_at         TIMESTAMPTZ NOT NULL,
  received_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at        TIMESTAMPTZ,
  CONSTRAINT chk_platform_event_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
COMMENT ON TABLE trustride.platform_event_inbox IS
  '[Trace: FDN-001 §11.2] Station 4. Mutating state before the inbox verdict, or reprocessing a duplicate idempotency_key, is forbidden absolutely.';

-- ---------------------------------------------------------------------------
-- 1.F ENGINE 001 CONFORMANCE TABLES (Part XI self-certification machinery)
-- ---------------------------------------------------------------------------

CREATE TABLE trustride.plate_registry (
  plate_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plate_code       trustride.substrate_plate_code_enum NOT NULL UNIQUE,
  exhibit_filename TEXT NOT NULL,
  sha256_digest    TEXT NOT NULL,
  adopted_on       DATE NOT NULL,
  adopted_by       TEXT NOT NULL,
  page_position    INTEGER NOT NULL,
  superseded_by    UUID REFERENCES trustride.plate_registry (plate_id)
);
COMMENT ON TABLE trustride.plate_registry IS
  '[Trace: FDN-001 §11.1] Digest mismatch invalidates authority; a redrawn plate is a forgery unless the Founder amends the register.';

CREATE TABLE trustride.projection_registry (
  projection_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  projection_code   TEXT NOT NULL UNIQUE,
  shell             TEXT NOT NULL CHECK (shell IN ('USER_HUB', 'OPERATOR_APP', 'ADMIN_CONSOLE', 'SOVEREIGN_EXECUTIVE_CONSOLE', 'MARKETPLACE_HUB')),
  source_tables     JSONB NOT NULL,
  refresh_mode      TEXT NOT NULL CHECK (refresh_mode IN ('LIVE', 'ON_SIGNAL', 'PERIODIC')),
  is_authoritative  BOOLEAN NOT NULL DEFAULT FALSE CHECK (is_authoritative = FALSE)
);
COMMENT ON TABLE trustride.projection_registry IS
  '[Trace: FDN-001 §11.4] Every rendered screen is registered here and traceable to the domain tables it reads; is_authoritative is always FALSE.';

CREATE TABLE trustride.plate_conformance_register (
  conformance_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_code       TEXT NOT NULL,
  check_code          TEXT NOT NULL CHECK (check_code ~ '^CC-(0[1-9]|1[0-2])$'),
  result              trustride.substrate_conformance_result_enum NOT NULL,
  evidence_reference  TEXT NOT NULL,
  certified_on        TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.plate_conformance_register IS
  '[Trace: FDN-001 §11.6] No engine document is adopted without every check answered PASS, PASS_WITH_EXCEPTION, or FAIL.';

CREATE TABLE trustride.conformance_exception (
  exception_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plate_code      trustride.substrate_plate_code_enum NOT NULL,
  departure       TEXT NOT NULL,
  justification   TEXT NOT NULL,
  founder_ruling  trustride.substrate_founder_ruling_enum NOT NULL DEFAULT 'PENDING',
  expires_on      DATE
);

CREATE TABLE trustride.architect_query_register (
  query_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  raised_by            TEXT NOT NULL,
  constraint_statement TEXT NOT NULL,
  options_presented    JSONB NOT NULL,
  founder_ruling       TEXT NOT NULL DEFAULT 'PENDING',
  ruled_on             TIMESTAMPTZ
);

-- ############################################################################
-- SUB-ENGINE 2 -- TRUSTRIDE CORE (14 tables)
-- ############################################################################

-- [Trace: TBOC-v2.0.0 | Article 9] Exactly one row, written at genesis,
-- hash-sealed, never updated.
CREATE TABLE trustride.platform_registry (
  platform_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  platform_code             CHAR(6) NOT NULL DEFAULT 'TRS026',
  platform_name             TEXT NOT NULL DEFAULT 'TRUSTRIDE_SERVICES',
  business_legal_name       TEXT NOT NULL,
  business_registration_no  TEXT NOT NULL,
  kra_pin                   TEXT NOT NULL,
  county_code                CHAR(2) NOT NULL,
  motto                       TEXT,
  constitutional_root_doc      TEXT NOT NULL,
  root_hash                     CHAR(64) NOT NULL,
  sealed_at                       TIMESTAMPTZ NOT NULL DEFAULT now(),
  sealed_by                         UUID NOT NULL
);
COMMENT ON TABLE trustride.platform_registry IS
  '[Trace: TBOC-v2.0.0 Art.9] Genesis row -- one platform, one identity, sealed once.';

CREATE TABLE trustride.platform_configuration (
  config_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  config_key     TEXT NOT NULL,
  config_value   TEXT NOT NULL,
  environment    TEXT NOT NULL DEFAULT 'PRODUCTION',
  effective_from TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to   TIMESTAMPTZ,
  changed_by     UUID NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.platform_configuration IS
  '[Trace: TBOC-v2.0.0 Art.59] Governed, versioned platform configuration.';

CREATE TABLE trustride.platform_version (
  version_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  version_no        TEXT NOT NULL,
  release_label     TEXT,
  release_notes_ref UUID,
  released_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  released_by       UUID NOT NULL
);
COMMENT ON TABLE trustride.platform_version IS
  '[Trace: TBOC-v2.0.0 Art.59] Release history, append-only.';

CREATE TABLE trustride.platform_status (
  status_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  state_code          trustride.core_platform_state_enum NOT NULL,
  previous_state      trustride.core_platform_state_enum,
  transition_reason   TEXT NOT NULL,
  transitioned_by     UUID NOT NULL,
  transitioned_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.platform_status IS
  '[Trace: TBOC-v2.0.0 Art.59] Platform lifecycle transitions, append-only evidence.';

CREATE TABLE trustride.platform_metadata (
  metadata_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  metadata_key   TEXT NOT NULL,
  metadata_value TEXT,
  source         TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.platform_metadata IS
  '[Trace: TBOC-v2.0.0 Art.59] Extensible platform-level metadata.';

-- [Trace: TBOC-v2.0.0 | Article 60] Key references only, never secrets --
-- secrets exist only within Engine 006 Integration (Part V Law 12).
CREATE TABLE trustride.platform_security (
  security_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  security_domain    TEXT NOT NULL,
  policy_code        TEXT NOT NULL,
  policy_ref         UUID,
  enforcement_level  TEXT NOT NULL DEFAULT 'MANDATORY',
  active             BOOLEAN NOT NULL DEFAULT TRUE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.platform_security IS
  '[Trace: TBOC-v2.0.0 Art.60] Security policy references only -- no credential ever lives here.';

CREATE TABLE trustride.platform_diagnostics (
  diagnostic_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  check_code     TEXT NOT NULL,
  check_outcome  TEXT NOT NULL,
  detail         JSONB NOT NULL DEFAULT '{}',
  measured_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.platform_diagnostics IS
  '[Trace: TBOC-v2.0.0 Art.59] Platform-level health/diagnostic check results.';

-- [Trace: TBOC-v2.0.0 | Article 59] Append-only. Seeded with exactly eleven
-- rows in canonical order (Phase 13).
CREATE TABLE trustride.engine_registry (
  engine_id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  engine_no                   SMALLINT NOT NULL UNIQUE,
  engine_code                 TEXT NOT NULL UNIQUE,
  engine_domain                TEXT NOT NULL,
  engine_class                  TEXT NOT NULL,
  engine_type                    TEXT NOT NULL,
  engine_name                     TEXT NOT NULL,
  engine_description                TEXT,
  engine_function                     TEXT,
  platform_version                      TEXT NOT NULL,
  engine_version                          TEXT NOT NULL,
  migration_file                            TEXT,
  installation_order                          SMALLINT NOT NULL,
  status                                        TEXT NOT NULL DEFAULT 'REGISTERED',
  constitutional_mandate_ref                      TEXT,
  created_by                                        UUID NOT NULL,
  created_at                                          TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.engine_registry IS
  '[Trace: TBOC-v2.0.0 Art.59] The Sovereign Engine Registry -- final and binding; expansion of detail authorized, structural redesign not.';

CREATE TABLE trustride.engine_installation (
  installation_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  engine_id             UUID NOT NULL REFERENCES trustride.engine_registry (engine_id),
  current_phase          SMALLINT NOT NULL CHECK (current_phase BETWEEN 0 AND 13),
  phase_gate_evidence      JSONB NOT NULL DEFAULT '{}',
  certified_at               TIMESTAMPTZ,
  certified_by                 UUID,
  status                         TEXT NOT NULL DEFAULT 'IN_PROGRESS'
);
COMMENT ON TABLE trustride.engine_installation IS
  '[Trace: TBOC-v2.0.0 Art.59] Tracks each engine''s progress through the 14-phase installation contract.';

CREATE TABLE trustride.engine_dependency (
  dependency_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  engine_id              UUID NOT NULL REFERENCES trustride.engine_registry (engine_id),
  depends_on_engine_id     UUID NOT NULL REFERENCES trustride.engine_registry (engine_id),
  dependency_type            TEXT NOT NULL DEFAULT 'REQUIRED',
  constitutional_basis          TEXT,
  created_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.engine_dependency IS
  '[Trace: TBOC-v2.0.0 Art.59] Declared inter-engine dependencies.';

-- [Trace: TBOC-v2.0.0 | Article 30] Registers exactly the five constitutional
-- shells; no sixth shell exists.
CREATE TABLE trustride.shell_registry (
  shell_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shell_code          TEXT NOT NULL UNIQUE,
  shell_name          TEXT NOT NULL,
  serves_user_types   TEXT[] NOT NULL,
  isolation_class     TEXT NOT NULL,
  status              TEXT NOT NULL DEFAULT 'ACTIVE',
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.shell_registry IS
  '[Trace: TBOC-v2.0.0 Art.30] The five constitutional shells -- User Hub, Operator App, Admin Console, Sovereign Executive Console, Marketplace Hub.';

CREATE TABLE trustride.engine_health_status (
  health_status_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  engine_id         UUID NOT NULL REFERENCES trustride.engine_registry (engine_id),
  status_code       TEXT NOT NULL,
  measured_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  reported_by       UUID
);
COMMENT ON TABLE trustride.engine_health_status IS
  '[Trace: TBOC-v2.0.0 Art.55-56] Per-engine health telemetry snapshots.';

CREATE TABLE trustride.system_incident (
  incident_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  engine_id       UUID REFERENCES trustride.engine_registry (engine_id),
  severity        TEXT NOT NULL,
  incident_type   TEXT NOT NULL,
  started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at     TIMESTAMPTZ,
  summary         TEXT,
  aftercare_ref   UUID
);
COMMENT ON TABLE trustride.system_incident IS
  '[Trace: TBOC-v2.0.0 Art.55-56] Platform/engine incident record.';

CREATE TABLE trustride.system_metric (
  metric_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  engine_id     UUID REFERENCES trustride.engine_registry (engine_id),
  metric_name   TEXT NOT NULL,
  metric_value  NUMERIC NOT NULL,
  unit          TEXT,
  recorded_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.system_metric IS
  '[Trace: TBOC-v2.0.0 Art.55-56] Platform/engine metric time series.';

-- ############################################################################
-- SUB-ENGINE 3 -- TRUSTRIDE IDENTITY (31 tables)
-- ############################################################################

-- [Trace: TBOC-v2.0.0 | Article 10-11] One Identity. One User. One User Type.
-- One Account. One Lifetime Identity.
CREATE TABLE trustride.platform_users (
  user_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  global_uid          TEXT NOT NULL UNIQUE,
  identity_primitive  TEXT NOT NULL CHECK (identity_primitive IN ('PERSON','ENTITY','THING')),
  display_name        TEXT NOT NULL,
  status               TEXT NOT NULL DEFAULT 'ACTIVE',
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.platform_users IS
  '[Trace: TBOC-v2.0.0 Art.10-11] One row per subject, for life.';

CREATE TABLE trustride.user_registration (
  registration_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  registration_channel TEXT NOT NULL,
  registration_source    TEXT,
  registered_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  terms_version               TEXT NOT NULL,
  consent_record                JSONB NOT NULL DEFAULT '{}'
);

CREATE TABLE trustride.user_authentication (
  authentication_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  method              TEXT NOT NULL CHECK (method IN ('PIN','OTP','PASSWORD','HARDWARE_KEY')),
  device_id           UUID,
  outcome              TEXT NOT NULL,
  authenticated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  source_ip                  INET
);

CREATE TABLE trustride.user_authorization (
  authorization_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  user_type_code    TEXT NOT NULL CHECK (user_type_code IN ('CUSTOMER','PARTNER','OPERATOR','INTERMEDIARY','GOVERNOR')),
  role_code         TEXT NOT NULL,
  shell_code        TEXT NOT NULL,
  scope             JSONB NOT NULL DEFAULT '{}',
  granted_by        UUID NOT NULL,
  valid_from        TIMESTAMPTZ NOT NULL DEFAULT now(),
  valid_to          TIMESTAMPTZ
);

CREATE TABLE trustride.user_records (
  record_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  record_type   TEXT NOT NULL,
  record_ref    UUID NOT NULL,
  recorded_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- [Trace: TBOC-v2.0.0 | Article 11, 13] title/ward/estate carried directly in
-- the base build (not a later ALTER) -- already proven required by the live
-- ProfileActivationScreen registration flow.
CREATE TABLE trustride.person_profile (
  person_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL UNIQUE REFERENCES trustride.platform_users (user_id),
  title             TEXT,
  legal_name        TEXT NOT NULL,
  date_of_birth     DATE,
  gender_code       TEXT,
  national_id_ref   TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.user_identifier (
  identifier_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  identifier_type   TEXT NOT NULL CHECK (identifier_type IN ('NATIONAL_ID','PHONE','EMAIL','KRA_PIN','DRIVING_LICENCE','GOOD_CONDUCT_CERT')),
  identifier_value  TEXT NOT NULL,
  status            TEXT NOT NULL DEFAULT 'ACTIVE',
  confidence_score  NUMERIC(5,2),
  verified_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.user_contact (
  contact_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  contact_type   TEXT NOT NULL,
  contact_value  TEXT NOT NULL,
  is_primary     BOOLEAN NOT NULL DEFAULT FALSE,
  is_verified    BOOLEAN NOT NULL DEFAULT FALSE,
  verified_at    TIMESTAMPTZ,
  status         TEXT NOT NULL DEFAULT 'ACTIVE',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.user_contact_preference (
  preference_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  channel        TEXT NOT NULL CHECK (channel IN ('SMS','PUSH','WHATSAPP','EMAIL')),
  allowed        BOOLEAN NOT NULL DEFAULT TRUE,
  allowed_from   TIME,
  allowed_to     TIME,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.user_address (
  address_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  address_type    TEXT NOT NULL,
  address_line_1  TEXT NOT NULL,
  address_line_2  TEXT,
  town            TEXT,
  county_code     CHAR(2),
  ward            TEXT,
  estate          TEXT,
  country_code    CHAR(2) NOT NULL DEFAULT 'KE',
  postal_code     TEXT,
  latitude        NUMERIC(10,7),
  longitude       NUMERIC(10,7),
  is_primary      BOOLEAN NOT NULL DEFAULT FALSE,
  valid_from      DATE NOT NULL DEFAULT CURRENT_DATE,
  valid_to        DATE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.user_socioeconomic_profile (
  profile_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  income_band         TEXT,
  vulnerability_flag  BOOLEAN NOT NULL DEFAULT FALSE,
  disability_flag     BOOLEAN NOT NULL DEFAULT FALSE,
  household_size      SMALLINT,
  primary_language    TEXT,
  data_source         TEXT,
  last_assessed_at    TIMESTAMPTZ
);

CREATE TABLE trustride.user_education_profile (
  education_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  education_level          TEXT,
  institution              TEXT,
  qualification            TEXT,
  academy_accreditation_ref UUID,
  year_completed           SMALLINT,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.user_employment (
  employment_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  entity_id       UUID,
  role_title      TEXT,
  employment_type TEXT,
  start_date      DATE,
  end_date        DATE,
  is_primary      BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.user_societal_position (
  position_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  community_ref           TEXT,
  institutional_affiliation TEXT,
  civic_role              TEXT,
  vulnerability_context    TEXT,
  data_source             TEXT,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.user_relationship (
  relationship_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                    UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  related_user_id            UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  relationship_type          TEXT NOT NULL,
  guardian_authorization_ref UUID,
  valid_from                 DATE NOT NULL DEFAULT CURRENT_DATE,
  valid_to                   DATE,
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.user_device (
  device_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  device_type         TEXT,
  os_type             TEXT,
  device_fingerprint  TEXT NOT NULL,
  trusted             BOOLEAN NOT NULL DEFAULT FALSE,
  first_seen_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  status              TEXT NOT NULL DEFAULT 'ACTIVE'
);

CREATE TABLE trustride.user_lifecycle_event (
  lifecycle_event_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  event_type          TEXT NOT NULL,
  event_source        TEXT,
  occurred_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.user_note (
  note_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  note_text         TEXT NOT NULL,
  visibility_scope  TEXT NOT NULL DEFAULT 'GOVERNOR',
  created_by        UUID NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.user_metadata (
  metadata_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  metadata_key    TEXT NOT NULL,
  metadata_value  TEXT,
  source          TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.entity_profile (
  entity_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID NOT NULL UNIQUE REFERENCES trustride.platform_users (user_id),
  legal_name           TEXT NOT NULL,
  entity_type          TEXT NOT NULL,
  registration_number  TEXT,
  kra_pin              TEXT,
  county_code          CHAR(2),
  status               TEXT NOT NULL DEFAULT 'ACTIVE',
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.entity_registration (
  registration_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id            UUID NOT NULL REFERENCES trustride.entity_profile (entity_id),
  registration_type    TEXT NOT NULL,
  registration_value   TEXT NOT NULL,
  issuing_authority    TEXT,
  verified_at          TIMESTAMPTZ,
  verification_ref     UUID,
  status               TEXT NOT NULL DEFAULT 'PENDING'
);

CREATE TABLE trustride.entity_membership (
  membership_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_id         UUID NOT NULL REFERENCES trustride.entity_profile (entity_id),
  person_user_id    UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  membership_role   TEXT NOT NULL,
  valid_from        DATE NOT NULL DEFAULT CURRENT_DATE,
  valid_to          DATE,
  granted_by        UUID NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.thing_registry (
  thing_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL UNIQUE REFERENCES trustride.platform_users (user_id),
  thing_type          TEXT NOT NULL,
  make                TEXT,
  model               TEXT,
  year                SMALLINT,
  plate_number        TEXT,
  serial_number       TEXT,
  custody_entity_id   UUID REFERENCES trustride.entity_profile (entity_id),
  custody_user_id     UUID REFERENCES trustride.platform_users (user_id),
  status              TEXT NOT NULL DEFAULT 'ACTIVE',
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.thing_registration (
  thing_registration_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  thing_id               UUID NOT NULL REFERENCES trustride.thing_registry (thing_id),
  registration_type      TEXT NOT NULL CHECK (registration_type IN ('NTSA_REG','INSPECTION','INSURANCE')),
  registration_value     TEXT NOT NULL,
  issuing_authority      TEXT,
  valid_from             DATE,
  valid_to               DATE,
  verified_at            TIMESTAMPTZ,
  status                 TEXT NOT NULL DEFAULT 'PENDING'
);

CREATE TABLE trustride.user_type_binding (
  binding_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  engagement_id       UUID NOT NULL,
  user_type_code      TEXT NOT NULL CHECK (user_type_code IN ('CUSTOMER','PARTNER','OPERATOR','INTERMEDIARY','GOVERNOR')),
  primary_intent      TEXT NOT NULL,
  secondary_context   TEXT,
  bound_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  bound_by            UUID
);

CREATE TABLE trustride.platform_access_event (
  access_event_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID REFERENCES trustride.platform_users (user_id),
  visitor_ref      UUID,
  access_mode      TEXT NOT NULL CHECK (access_mode IN ('VISITOR','RETURNING','AUTHENTICATED')),
  channel          TEXT NOT NULL CHECK (channel IN ('ANDROID','WEB','OTHER')),
  access_source    TEXT,
  intent_signals   JSONB NOT NULL DEFAULT '{}',
  fraud_telemetry  JSONB NOT NULL DEFAULT '{}',
  occurred_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.auth_session (
  session_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  device_id    UUID REFERENCES trustride.user_device (device_id),
  shell_id     UUID REFERENCES trustride.shell_registry (shell_id),
  issued_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at   TIMESTAMPTZ NOT NULL,
  revoked_at   TIMESTAMPTZ,
  status       TEXT NOT NULL DEFAULT 'ACTIVE'
);

CREATE TABLE trustride.mfa_enrollment (
  mfa_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  method        TEXT NOT NULL CHECK (method IN ('SMS_OTP','TOTP','HARDWARE_KEY')),
  enrolled_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at  TIMESTAMPTZ,
  status        TEXT NOT NULL DEFAULT 'ACTIVE'
);

-- [Trace: TBOC-v2.0.0 | Article 14.5, 52] Vetting evidence -- requested via
-- Engine 006, recorded here by Foundation's own accept-handler only.
CREATE TABLE trustride.verification_record (
  verification_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_user_id    UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  subject_thing_id   UUID REFERENCES trustride.thing_registry (thing_id),
  verification_type  TEXT NOT NULL CHECK (verification_type IN ('NATIONAL_ID','GOOD_CONDUCT','GUARANTOR','MEDICAL','NTSA_LICENCE','NTSA_VEHICLE')),
  request_ref        UUID,
  outcome            TEXT NOT NULL DEFAULT 'PENDING',
  evidence_ref       UUID,
  verified_at        TIMESTAMPTZ,
  expires_at         TIMESTAMPTZ
);

CREATE TABLE trustride.role_definition (
  role_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role_code             TEXT NOT NULL UNIQUE,
  role_name             TEXT NOT NULL,
  user_type_code        TEXT NOT NULL CHECK (user_type_code IN ('CUSTOMER','PARTNER','OPERATOR','INTERMEDIARY','GOVERNOR')),
  constitutional_basis  TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.role_definition IS
  '[Trace: TBOC-v2.0.0 Art.12,14] Institutional roles within User Type contexts -- Founder, executive, safeguarding officer, dispatcher, administrator, etc.';

CREATE TABLE trustride.role_assignment (
  assignment_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  role_id        UUID NOT NULL REFERENCES trustride.role_definition (role_id),
  assigned_by    UUID NOT NULL,
  valid_from     TIMESTAMPTZ NOT NULL DEFAULT now(),
  valid_to       TIMESTAMPTZ,
  status         TEXT NOT NULL DEFAULT 'ACTIVE'
);
COMMENT ON TABLE trustride.role_assignment IS
  '[Trace: TBOC-v2.0.0 Art.12,14] Roles assigned with delegation visibility and expiry.';

-- Deferred FKs: Annex A's fixed 020-050 numbering means two Identity columns
-- reference a sibling table declared later in that same order.
ALTER TABLE trustride.user_authentication ADD CONSTRAINT fk_user_authentication_device_id FOREIGN KEY (device_id) REFERENCES trustride.user_device (device_id);
ALTER TABLE trustride.user_employment ADD CONSTRAINT fk_user_employment_entity_id FOREIGN KEY (entity_id) REFERENCES trustride.entity_profile (entity_id);

-- ############################################################################
-- SUB-ENGINE 4 -- TRUSTRIDE GOVERNANCE (16 tables)
-- ############################################################################

CREATE TABLE trustride.governance_policy (
  policy_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  policy_code         TEXT NOT NULL UNIQUE,
  policy_title        TEXT NOT NULL,
  constitutional_ref  TEXT NOT NULL,
  policy_body         TEXT NOT NULL,
  effective_from      TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to        TIMESTAMPTZ,
  status              TEXT NOT NULL DEFAULT 'ACTIVE',
  approved_by         UUID NOT NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.policy_rule (
  rule_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  policy_id           UUID NOT NULL REFERENCES trustride.governance_policy (policy_id),
  rule_code           TEXT NOT NULL,
  rule_type           TEXT NOT NULL CHECK (rule_type IN ('CONSTRAINT','THRESHOLD','DUAL_CONTROL','ESCALATION')),
  rule_expression     JSONB NOT NULL DEFAULT '{}',
  enforcement_point   TEXT,
  status              TEXT NOT NULL DEFAULT 'ACTIVE',
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.exception_record (
  exception_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_id         UUID NOT NULL REFERENCES trustride.policy_rule (rule_id),
  entity_type     TEXT NOT NULL,
  entity_id       UUID NOT NULL,
  justification   TEXT NOT NULL,
  approved_by     UUID NOT NULL,
  valid_from      TIMESTAMPTZ NOT NULL DEFAULT now(),
  valid_to        TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.approval_chain (
  chain_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chain_code    TEXT NOT NULL UNIQUE,
  action_class  TEXT NOT NULL,
  description   TEXT,
  status        TEXT NOT NULL DEFAULT 'ACTIVE',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.approval_step (
  step_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chain_id            UUID NOT NULL REFERENCES trustride.approval_chain (chain_id),
  step_no             SMALLINT NOT NULL,
  required_role_code  TEXT NOT NULL,
  quorum              SMALLINT NOT NULL DEFAULT 1,
  dual_control        BOOLEAN NOT NULL DEFAULT FALSE,
  timeout_hours       SMALLINT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.approval_request (
  request_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chain_id            UUID NOT NULL REFERENCES trustride.approval_chain (chain_id),
  target_entity_type  TEXT NOT NULL,
  target_entity_id    UUID NOT NULL,
  requested_by        UUID NOT NULL,
  request_payload     JSONB NOT NULL DEFAULT '{}',
  status              TEXT NOT NULL DEFAULT 'OPEN',
  opened_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at           TIMESTAMPTZ
);

CREATE TABLE trustride.approval_decision (
  decision_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id   UUID NOT NULL REFERENCES trustride.approval_request (request_id),
  step_id      UUID NOT NULL REFERENCES trustride.approval_step (step_id),
  decided_by   UUID NOT NULL,
  decision     TEXT NOT NULL CHECK (decision IN ('APPROVED','REJECTED','ABSTAINED')),
  rationale    TEXT,
  decided_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.dual_control_requirement (
  dual_control_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  action_class     TEXT NOT NULL,
  first_role_code  TEXT NOT NULL,
  second_role_code TEXT NOT NULL,
  active           BOOLEAN NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- [Trace: TBOC-v2.0.0 | Article 44] The only lawful source of pricing
-- authority; never applied retroactively to settled Orders.
CREATE TABLE trustride.rate_register (
  rate_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rate_code             TEXT NOT NULL UNIQUE,
  rate_class            TEXT NOT NULL CHECK (rate_class IN ('COMMISSION','SPLIT','CANCELLATION_FEE','ADMIN_FEE','PAYOUT','PRICING_RULE')),
  rate_value            NUMERIC(10,4) NOT NULL,
  currency              CHAR(3) NOT NULL DEFAULT 'KES',
  domain_code           TEXT,
  service_code          TEXT,
  effective_from        TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to          TIMESTAMPTZ,
  approved_request_id   UUID REFERENCES trustride.approval_request (request_id),
  created_by            UUID NOT NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.threshold_register (
  threshold_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  threshold_code        TEXT NOT NULL UNIQUE,
  threshold_class       TEXT NOT NULL,
  threshold_value       NUMERIC(18,2) NOT NULL,
  currency              CHAR(3),
  effective_from        TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to          TIMESTAMPTZ,
  approved_request_id   UUID REFERENCES trustride.approval_request (request_id),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.technology_decision_record (
  tdr_id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tdr_code                      TEXT NOT NULL UNIQUE,
  technology_domain             TEXT NOT NULL,
  decision                      TEXT NOT NULL CHECK (decision IN ('ADOPT','REJECT','REPLACE')),
  subject_technology            TEXT NOT NULL,
  rationale                     TEXT NOT NULL,
  constitutional_demonstration  TEXT NOT NULL,
  decided_by                    UUID NOT NULL,
  decided_at                    TIMESTAMPTZ NOT NULL DEFAULT now(),
  supersedes_tdr_id             UUID REFERENCES trustride.technology_decision_record (tdr_id),
  status                        TEXT NOT NULL DEFAULT 'ACTIVE'
);

CREATE TABLE trustride.regulatory_contact_register (
  rcr_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  regulator_name          TEXT NOT NULL,
  contact_name            TEXT,
  contact_channel         TEXT,
  touchpoint_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  assigned_to             UUID NOT NULL,
  severity                TEXT NOT NULL,
  outcome                 TEXT,
  assumption_shift_flag   BOOLEAN NOT NULL DEFAULT FALSE,
  founder_notified_flag   BOOLEAN NOT NULL DEFAULT FALSE,
  evidence_ref            UUID,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.assumption_impact_assessment (
  aia_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rcr_id               UUID NOT NULL REFERENCES trustride.regulatory_contact_register (rcr_id),
  affected_area        TEXT NOT NULL,
  impact_summary       TEXT NOT NULL,
  options              JSONB NOT NULL DEFAULT '{}',
  recommendation       TEXT,
  required_directive   TEXT,
  approved_by          UUID,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.escalation_case (
  escalation_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  origin_document   TEXT NOT NULL,
  origin_article    TEXT,
  question          TEXT NOT NULL,
  escalated_by      UUID NOT NULL,
  escalated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_by       UUID,
  resolution        TEXT,
  resolved_at       TIMESTAMPTZ,
  status            TEXT NOT NULL DEFAULT 'OPEN'
);

CREATE TABLE trustride.constitutional_amendment (
  amendment_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  document_code      TEXT NOT NULL,
  amendment_code     TEXT NOT NULL,
  authority          TEXT NOT NULL,
  rationale          TEXT NOT NULL,
  published_version  TEXT NOT NULL,
  published_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  recorded_by        UUID NOT NULL
);

CREATE TABLE trustride.delegation_of_authority (
  delegation_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delegator_user_id  UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  delegate_user_id   UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  authority_scope    TEXT NOT NULL,
  limits             JSONB NOT NULL DEFAULT '{}',
  valid_from         TIMESTAMPTZ NOT NULL DEFAULT now(),
  valid_to           TIMESTAMPTZ,
  status             TEXT NOT NULL DEFAULT 'ACTIVE'
);

-- ############################################################################
-- SUB-ENGINE 5 -- TRUSTRIDE AUDIT (7 tables)
-- ############################################################################

-- [Trace: TBOC-v2.0.0 | Article 49-51] Append-only, hash-chained. Never
-- updated or deleted at the database level. Written only through
-- fn_audit_log_append() (Phase 6) -- never a direct INSERT from a caller.
-- chain_seq (Correction 10, 2026-08-23): the true, gap-free chain order.
-- occurred_at is transaction_timestamp() -- constant for the whole
-- transaction, so two audit_log_append calls in the same transaction (the
-- normal case: fn_user_register logs once, its own caller logs again)
-- always tie on occurred_at. Found by actually chaining real calls and
-- independently re-walking the chain, not by inspection: with the
-- occurred_at/audit_id (a random UUID) tie-break this file shipped with
-- originally, a third call arriving after two same-instant rows exist can
-- pick the WRONG predecessor, silently forking the hash chain. chain_seq
-- is a real, strictly monotonic identity column -- fn_audit_log_append and
-- fn_audit_checkpoint_seal below key off it, never off occurred_at/audit_id.
CREATE TABLE trustride.audit_log (
  audit_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chain_seq         BIGINT GENERATED ALWAYS AS IDENTITY,
  entity_type       TEXT NOT NULL,
  entity_id         UUID NOT NULL,
  action            TEXT NOT NULL,
  actor_id          UUID,
  actor_type        TEXT NOT NULL,
  actor_user_type   TEXT,
  shell_code        TEXT,
  before_snapshot   JSONB,
  after_snapshot    JSONB,
  prev_hash         CHAR(64),
  immutable_hash    CHAR(64) NOT NULL,
  occurred_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.audit_checkpoint (
  checkpoint_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chain_head_audit_id       UUID NOT NULL REFERENCES trustride.audit_log (audit_id),
  checkpoint_hash           CHAR(64) NOT NULL,
  sealed_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  sealed_by                 UUID NOT NULL,
  external_attestation_ref  TEXT
);

CREATE TABLE trustride.security_event (
  security_event_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_user_id    UUID REFERENCES trustride.platform_users (user_id),
  access_event_id    UUID REFERENCES trustride.platform_access_event (access_event_id),
  event_type         TEXT NOT NULL,
  severity           TEXT NOT NULL,
  description        TEXT,
  source_ip          INET,
  device_id          UUID REFERENCES trustride.user_device (device_id),
  occurred_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  escalated          BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE trustride.privileged_action_log (
  privileged_action_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id              UUID NOT NULL,
  role_code             TEXT NOT NULL,
  action_type           TEXT NOT NULL,
  target_entity_type    TEXT NOT NULL,
  target_entity_id      UUID NOT NULL,
  parameters            JSONB NOT NULL DEFAULT '{}',
  justification         TEXT,
  performed_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.evidence_package (
  package_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  package_type          TEXT NOT NULL,
  subject_entity_type   TEXT NOT NULL,
  subject_entity_id     UUID NOT NULL,
  assembled_by          UUID NOT NULL,
  assembled_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  package_hash          CHAR(64) NOT NULL,
  status                TEXT NOT NULL DEFAULT 'ASSEMBLED'
);

CREATE TABLE trustride.evidence_item (
  item_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id   UUID NOT NULL REFERENCES trustride.evidence_package (package_id),
  source_table TEXT NOT NULL,
  source_id    UUID NOT NULL,
  item_hash    CHAR(64) NOT NULL,
  added_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.retention_policy (
  retention_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  record_class      TEXT NOT NULL,
  retention_years   SMALLINT NOT NULL,
  legal_basis       TEXT NOT NULL,
  purge_action      TEXT NOT NULL DEFAULT 'ARCHIVE',
  status            TEXT NOT NULL DEFAULT 'ACTIVE',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- Table count check: Substrate 24 + Core 14 + Identity 31 + Governance 16 +
-- Audit 7 = 92, matching Annex A exactly.
-- ============================================================================

-- ============================================================================
-- PHASE 6 -- FUNCTIONS
-- ============================================================================

-- --- Substrate ---

-- [Trace: TBOC-v2.0.0 | Article 42.5 | The Sequence Law]
CREATE OR REPLACE FUNCTION trustride.fn_sequence_next(p_sequence_code TEXT)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_prefix  TEXT;
  v_next    BIGINT;
  v_padding SMALLINT;
BEGIN
  UPDATE trustride.sequence_generator
  SET current_value = current_value + 1, updated_at = now()
  WHERE sequence_code = p_sequence_code
  RETURNING prefix, current_value, padding INTO v_prefix, v_next, v_padding;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_sequence_next: unregistered sequence_code % (Article 42.5 -- no engine generates its own numbering)', p_sequence_code;
  END IF;

  RETURN v_prefix || '-' || lpad(v_next::TEXT, v_padding, '0');
END;
$$;
COMMENT ON FUNCTION trustride.fn_sequence_next(TEXT) IS
  '[Trace: TBOC-v2.0.0 Art.42.5] Issues the next TRS026-prefixed institutional number for a registered sequence_code.';

-- [Trace: FDN-001 Part X §3.1 | Semantic Stability]
CREATE OR REPLACE FUNCTION trustride.fn_semantic_dictionary_supersede(
  p_term_domain TEXT, p_term_code TEXT, p_new_label TEXT, p_new_definition TEXT
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_old_id  UUID;
  v_old_ver SMALLINT;
  v_new_id  UUID;
BEGIN
  SELECT semantic_id, version INTO v_old_id, v_old_ver
  FROM trustride.semantic_dictionary
  WHERE term_domain = p_term_domain AND term_code = p_term_code AND superseded_by IS NULL
  ORDER BY version DESC LIMIT 1;

  INSERT INTO trustride.semantic_dictionary (term_domain, term_code, term_label, term_definition, version)
  VALUES (p_term_domain, p_term_code, p_new_label, p_new_definition, COALESCE(v_old_ver, 0) + 1)
  RETURNING semantic_id INTO v_new_id;

  IF v_old_id IS NOT NULL THEN
    UPDATE trustride.semantic_dictionary SET superseded_by = v_new_id WHERE semantic_id = v_old_id;
  END IF;
  RETURN v_new_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_semantic_dictionary_supersede(TEXT, TEXT, TEXT, TEXT) IS
  '[Trace: FDN-001 Part X §3.1] The only lawful way to change a semantic_dictionary definition.';

-- --- Audit ---

-- [Trace: TBOC-v2.0.0 | Article 49-51 | "Absence of evidence is system
-- failure"] The single lawful way any engine appends to the hash chain --
-- computes prev_hash/immutable_hash correctly, every time, so no caller
-- ever hand-rolls a hash and gets it wrong.
CREATE OR REPLACE FUNCTION trustride.fn_audit_log_append(
  p_entity_type TEXT, p_entity_id UUID, p_action TEXT, p_actor_id UUID,
  p_actor_type TEXT, p_actor_user_type TEXT, p_shell_code TEXT,
  p_before_snapshot JSONB, p_after_snapshot JSONB
)
RETURNS UUID
-- `extensions` is required here (and nowhere else in this file) because
-- Supabase always installs pgcrypto into the `extensions` schema, never
-- `public` or `trustride` -- this is the ONLY function in Foundation that
-- calls digest(). Found by actually invoking fn_user_register end-to-end
-- against a real Postgres instance (CREATE FUNCTION alone never validates
-- identifiers inside a plpgsql body), not by inspection.
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_prev_hash    CHAR(64);
  v_new_id       UUID := gen_random_uuid();
  v_new_hash     CHAR(64);
  v_canonical    TEXT;
  v_occurred_at  TIMESTAMPTZ := now();
BEGIN
  SELECT immutable_hash INTO v_prev_hash
  FROM trustride.audit_log ORDER BY chain_seq DESC LIMIT 1;

  v_canonical := coalesce(v_prev_hash, '') || '|' || p_entity_type || '|' || p_entity_id::text || '|' || p_action
    || '|' || coalesce(p_actor_id::text, '') || '|' || coalesce(p_before_snapshot::text, '')
    || '|' || coalesce(p_after_snapshot::text, '') || '|' || v_occurred_at::text;
  v_new_hash := encode(digest(v_canonical, 'sha256'), 'hex');

  INSERT INTO trustride.audit_log
    (audit_id, entity_type, entity_id, action, actor_id, actor_type, actor_user_type, shell_code,
     before_snapshot, after_snapshot, prev_hash, immutable_hash, occurred_at)
  VALUES
    (v_new_id, p_entity_type, p_entity_id, p_action, p_actor_id, p_actor_type, p_actor_user_type, p_shell_code,
     p_before_snapshot, p_after_snapshot, v_prev_hash, v_new_hash, v_occurred_at);

  RETURN v_new_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_audit_log_append(TEXT, UUID, TEXT, UUID, TEXT, TEXT, TEXT, JSONB, JSONB) IS
  '[Trace: TBOC-v2.0.0 Art.49-51] The one lawful way to append to the hash chain -- correct prev_hash/immutable_hash computation, every time.';

CREATE OR REPLACE FUNCTION trustride.fn_audit_checkpoint_seal(p_sealed_by UUID)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_head_id       UUID;
  v_head_hash     CHAR(64);
  v_checkpoint_id UUID;
BEGIN
  SELECT audit_id, immutable_hash INTO v_head_id, v_head_hash
  FROM trustride.audit_log ORDER BY chain_seq DESC LIMIT 1;

  IF v_head_id IS NULL THEN
    RAISE EXCEPTION 'fn_audit_checkpoint_seal: audit_log is empty, nothing to seal';
  END IF;

  INSERT INTO trustride.audit_checkpoint (chain_head_audit_id, checkpoint_hash, sealed_by)
  VALUES (v_head_id, v_head_hash, p_sealed_by)
  RETURNING checkpoint_id INTO v_checkpoint_id;

  RETURN v_checkpoint_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_audit_checkpoint_seal(UUID) IS
  '[Trace: TBOC-v2.0.0 Art.49-51] Seals the current chain head for external verification.';

-- --- Identity / Governance authority checks ---

-- [Trace: TBOC-v2.0.0 | Article 12, 14] Structural authority checks reused
-- throughout this file's own RLS policies, and by every downstream engine.
CREATE OR REPLACE FUNCTION trustride.fn_am_i_administrator()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM trustride.role_assignment ra
    JOIN trustride.role_definition rd ON rd.role_id = ra.role_id
    WHERE ra.user_id = auth.uid() AND ra.status = 'ACTIVE'
      AND (ra.valid_to IS NULL OR ra.valid_to > now())
      AND rd.role_code = 'ADMINISTRATOR'
  );
$$;

CREATE OR REPLACE FUNCTION trustride.fn_am_i_governor()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM trustride.role_assignment ra
    JOIN trustride.role_definition rd ON rd.role_id = ra.role_id
    WHERE ra.user_id = auth.uid() AND ra.status = 'ACTIVE'
      AND (ra.valid_to IS NULL OR ra.valid_to > now())
      AND rd.user_type_code = 'GOVERNOR'
  );
$$;

-- [Trace: TBOC-v2.0.0 | Article 10] The one lawful way a real authenticated
-- session becomes a platform_users row. user_id = auth.uid() by design --
-- no engine invents a second identity for the same session.
CREATE OR REPLACE FUNCTION trustride.fn_user_register(
  p_display_name TEXT,
  p_identity_primitive TEXT DEFAULT 'PERSON',
  p_registration_channel TEXT DEFAULT 'MOBILE_APP',
  p_registration_source TEXT DEFAULT NULL,
  p_terms_version TEXT DEFAULT 'v1.0',
  p_consent_record JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_user_id     UUID := auth.uid();
  v_global_uid  TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'fn_user_register: no authenticated session (Article 14.5 -- no interpretation without a Platform Access anchor)';
  END IF;
  IF EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'fn_user_register: user_id % is already registered (Article 10 -- One Identity, One Account, One Lifetime Identity)', v_user_id;
  END IF;

  v_global_uid := 'TRS026-U-' || upper(substr(v_user_id::text, 1, 8));

  INSERT INTO trustride.platform_users (user_id, global_uid, identity_primitive, display_name)
  VALUES (v_user_id, v_global_uid, p_identity_primitive, p_display_name);

  INSERT INTO trustride.user_registration (user_id, registration_channel, registration_source, terms_version, consent_record)
  VALUES (v_user_id, p_registration_channel, p_registration_source, p_terms_version, p_consent_record);

  PERFORM trustride.fn_audit_log_append('platform_users', v_user_id, 'USER_REGISTERED', v_user_id, 'USER', NULL, NULL,
    NULL, jsonb_build_object('user_id', v_user_id, 'display_name', p_display_name));

  RETURN v_user_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_user_register(TEXT, TEXT, TEXT, TEXT, TEXT, JSONB) IS
  '[Trace: TBOC-v2.0.0 Art.10] The one lawful way to register -- user_id is always auth.uid(), never a fabricated identity.';

-- [Trace: TBOC-v2.0.0 | Article 12.5] Governed role assignment -- gated to
-- existing Governors, with a one-time genesis exception below.
CREATE OR REPLACE FUNCTION trustride.fn_role_assign(p_user_id UUID, p_role_code TEXT)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_role_id       UUID;
  v_assignment_id UUID;
BEGIN
  IF NOT trustride.fn_am_i_governor() THEN
    RAISE EXCEPTION 'fn_role_assign: caller is not a Governor (Article 12.5)';
  END IF;
  SELECT role_id INTO v_role_id FROM trustride.role_definition WHERE role_code = p_role_code;
  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'fn_role_assign: unregistered role_code %', p_role_code;
  END IF;

  INSERT INTO trustride.role_assignment (user_id, role_id, assigned_by, status)
  VALUES (p_user_id, v_role_id, auth.uid(), 'ACTIVE')
  RETURNING assignment_id INTO v_assignment_id;

  PERFORM trustride.fn_audit_log_append('role_assignment', v_assignment_id, 'ROLE_ASSIGNED', auth.uid(), 'USER', NULL, NULL,
    NULL, jsonb_build_object('user_id', p_user_id, 'role_code', p_role_code));

  RETURN v_assignment_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_role_assign(UUID, TEXT) IS
  '[Trace: TBOC-v2.0.0 Art.12.5] Governor-gated role assignment; see fn_founder_bootstrap() for the one-time genesis exception.';

-- [Trace: TBOC-v2.0.0 | Article 10, 12.5] Solves the genesis paradox
-- (fn_role_assign requires a Governor to already exist): the FIRST caller,
-- once registered via fn_user_register, may claim the FOUNDER role --
-- exactly once, ever. This is the real, correct answer to "how do I make
-- sure I'm never locked out" -- tied to a real authenticated session, never
-- a fabricated UUID seeded blind into role_assignment.
CREATE OR REPLACE FUNCTION trustride.fn_founder_bootstrap()
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_role_id       UUID;
  v_assignment_id UUID;
  v_caller        UUID := auth.uid();
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'fn_founder_bootstrap: no authenticated session';
  END IF;
  IF EXISTS (
    SELECT 1 FROM trustride.role_assignment ra
    JOIN trustride.role_definition rd ON rd.role_id = ra.role_id
    WHERE rd.role_code = 'FOUNDER' AND ra.status = 'ACTIVE'
  ) THEN
    RAISE EXCEPTION 'fn_founder_bootstrap: a FOUNDER is already assigned -- this genesis function is one-time only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id = v_caller) THEN
    RAISE EXCEPTION 'fn_founder_bootstrap: caller must register via fn_user_register() first';
  END IF;

  SELECT role_id INTO v_role_id FROM trustride.role_definition WHERE role_code = 'FOUNDER';

  INSERT INTO trustride.role_assignment (user_id, role_id, assigned_by, status)
  VALUES (v_caller, v_role_id, v_caller, 'ACTIVE')
  RETURNING assignment_id INTO v_assignment_id;

  PERFORM trustride.fn_audit_log_append('role_assignment', v_assignment_id, 'FOUNDER_BOOTSTRAPPED', v_caller, 'USER', NULL, NULL,
    NULL, jsonb_build_object('user_id', v_caller));

  RETURN v_assignment_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_founder_bootstrap() IS
  '[Trace: TBOC-v2.0.0 Art.10, 12.5] One-time genesis: the first authenticated, registered caller becomes FOUNDER. Permanently disabled the instant one exists.';

-- ----------------------------------------------------------------------------
-- Registration & Authentication Flow (Foundation-Hardened) -- Founder ruling
-- 2026-08-23. No new tables: this hardens fn_user_register with a mandatory
-- government identity gate on top of it, using only platform_users,
-- person_profile, user_identifier, user_registration, verification_record,
-- user_authorization, user_address, user_socioeconomic_profile,
-- user_education_profile, user_note, and audit_log -- all already built
-- above. Article 33 engine boundary: Foundation NEVER calls an external
-- identity authority itself -- that call is Engine 6 Integration's exclusive
-- job, reached only via the platform_event_outbox/inbox signal envelope.
--
-- Sequencing note: the Founder's narrative places "creates the
-- platform_users record" at final activation (Step 3.4), after Secondary
-- data collection. That is not possible as written -- verification_record
-- and every secondary-data table carry a mandatory FK to platform_users, so
-- it must exist first. Resolved the only way the schema allows:
-- platform_users is created at capture (Step 3.1) in a new status value,
-- PENDING_VERIFICATION (no schema change -- status is already a bare TEXT
-- column). Primary passing (fn_verification_completed_accept) is what
-- flips it to ACTIVE and grants shell access; Secondary submission
-- (fn_secondary_profile_submit) is unblocked before or after that, exactly
-- matching "Secondary is soft -- never a hard block."
-- ----------------------------------------------------------------------------

-- Step 3.1/3.2 entry point: minimal capture + opens the Primary verification
-- gate. Reuses fn_user_register (the one lawful way to create platform_users)
-- then immediately downgrades status to PENDING_VERIFICATION -- the account
-- is not usable until Primary passes.
CREATE OR REPLACE FUNCTION trustride.fn_registration_capture_primary(
  p_full_legal_name TEXT,
  p_national_id TEXT,
  p_consent_given BOOLEAN
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_user_id          UUID;
  v_verification_id  UUID;
  v_signal_id        UUID;
BEGIN
  IF NOT p_consent_given THEN
    RAISE EXCEPTION 'fn_registration_capture_primary: Data Protection Act consent is required before registration may proceed';
  END IF;
  IF p_full_legal_name IS NULL OR length(trim(p_full_legal_name)) = 0 THEN
    RAISE EXCEPTION 'fn_registration_capture_primary: full legal name is required';
  END IF;
  IF p_national_id IS NULL OR length(trim(p_national_id)) = 0 THEN
    RAISE EXCEPTION 'fn_registration_capture_primary: national ID is required';
  END IF;

  v_user_id := trustride.fn_user_register(
    p_display_name => p_full_legal_name,
    p_identity_primitive => 'PERSON',
    p_registration_channel => 'MOBILE_APP',
    p_terms_version => 'DPA-2019-v1',
    p_consent_record => jsonb_build_object('data_protection_act_consent', true, 'consented_at', now())
  );

  UPDATE trustride.platform_users SET status = 'PENDING_VERIFICATION', updated_at = now() WHERE user_id = v_user_id;

  INSERT INTO trustride.person_profile (user_id, legal_name, national_id_ref)
  VALUES (v_user_id, p_full_legal_name, p_national_id);

  INSERT INTO trustride.user_identifier (user_id, identifier_type, identifier_value, status)
  VALUES (v_user_id, 'NATIONAL_ID', p_national_id, 'PENDING');

  INSERT INTO trustride.verification_record (subject_user_id, verification_type, outcome)
  VALUES (v_user_id, 'NATIONAL_ID', 'PENDING')
  RETURNING verification_id INTO v_verification_id;

  -- Hand off to Integration (Engine 6) -- Foundation never calls the
  -- government identity authority itself (Article 33).
  INSERT INTO trustride.platform_event_outbox
    (correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES
    (gen_random_uuid(), 'TRS026_ENG001_FDN', 'TRS026_ENG006_INTG', 'VERIFICATION_REQUESTED',
     jsonb_build_object('verification_id', v_verification_id, 'subject_user_id', v_user_id,
       'verification_type', 'NATIONAL_ID', 'full_legal_name', p_full_legal_name, 'national_id', p_national_id),
     'VERIFICATION_REQUESTED:' || v_verification_id::text)
  RETURNING signal_id INTO v_signal_id;

  PERFORM trustride.fn_audit_log_append('platform_users', v_user_id, 'REGISTRATION_PRIMARY_CAPTURED', v_user_id,
    'USER', NULL, NULL, NULL, jsonb_build_object('verification_id', v_verification_id, 'signal_id', v_signal_id));

  RETURN v_verification_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_registration_capture_primary(TEXT, TEXT, BOOLEAN) IS
  'Step 3.1/3.2: minimal capture + opens the Primary verification gate. platform_users starts PENDING_VERIFICATION, never ACTIVE, until fn_verification_completed_accept() confirms all three Primary checks.';

-- Foundation's own accept-handler for the VERIFICATION_COMPLETED signal --
-- Engine 6 never writes verification_record directly (Article 33 boundary).
-- The absolute, non-negotiable Primary gate: Real Legal Names, Person
-- Status, and KRA PIN must ALL be returned and correct, or registration is
-- blocked outright -- no partial pass, no manual override, no proceed-anyway.
CREATE OR REPLACE FUNCTION trustride.fn_verification_completed_accept(
  p_verification_id UUID,
  p_returned_legal_name TEXT,
  p_returned_status TEXT,     -- expected: 'ALIVE_VALID' | 'DECEASED' | 'RESTRICTED' | 'INVALID'
  p_returned_kra_pin TEXT,
  p_raw_response JSONB DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_subject_user_id  UUID;
  v_submitted_name   TEXT;
  v_names_match      BOOLEAN;
  v_status_valid     BOOLEAN;
  v_kra_present      BOOLEAN;
  v_outcome          TEXT;
  v_reasons          TEXT[] := ARRAY[]::TEXT[];
BEGIN
  SELECT subject_user_id INTO v_subject_user_id
  FROM trustride.verification_record WHERE verification_id = p_verification_id AND outcome = 'PENDING';

  IF v_subject_user_id IS NULL THEN
    RAISE EXCEPTION 'fn_verification_completed_accept: no PENDING verification_record for id %', p_verification_id;
  END IF;

  SELECT legal_name INTO v_submitted_name FROM trustride.person_profile WHERE user_id = v_subject_user_id;

  v_names_match  := (p_returned_legal_name IS NOT NULL AND lower(trim(p_returned_legal_name)) = lower(trim(v_submitted_name)));
  v_status_valid := (p_returned_status = 'ALIVE_VALID');
  v_kra_present  := (p_returned_kra_pin IS NOT NULL AND length(trim(p_returned_kra_pin)) > 0);

  IF NOT v_names_match  THEN v_reasons := array_append(v_reasons, 'REAL_LEGAL_NAMES_MISMATCH'); END IF;
  IF NOT v_status_valid THEN v_reasons := array_append(v_reasons, 'PERSON_STATUS_NOT_VALID'); END IF;
  IF NOT v_kra_present  THEN v_reasons := array_append(v_reasons, 'KRA_PIN_NOT_RETURNED'); END IF;

  IF v_names_match AND v_status_valid AND v_kra_present THEN
    v_outcome := 'VERIFIED';

    UPDATE trustride.verification_record
    SET outcome = 'VERIFIED', verified_at = now()
    WHERE verification_id = p_verification_id;

    UPDATE trustride.person_profile SET legal_name = p_returned_legal_name, updated_at = now() WHERE user_id = v_subject_user_id;
    UPDATE trustride.user_identifier SET status = 'ACTIVE', verified_at = now() WHERE user_id = v_subject_user_id AND identifier_type = 'NATIONAL_ID';

    INSERT INTO trustride.user_identifier (user_id, identifier_type, identifier_value, status, verified_at)
    VALUES (v_subject_user_id, 'KRA_PIN', p_returned_kra_pin, 'ACTIVE', now());

    -- Primary pass IS activation -- Secondary data (Step 3.3) is soft by
    -- design and must never gate access already lawfully earned here.
    UPDATE trustride.platform_users SET status = 'ACTIVE', updated_at = now() WHERE user_id = v_subject_user_id;

    INSERT INTO trustride.user_authorization (user_id, user_type_code, role_code, shell_code, scope, granted_by)
    VALUES (v_subject_user_id, 'CUSTOMER', 'CUSTOMER_DEFAULT', 'USER_HUB', '{}'::jsonb, v_subject_user_id);

    PERFORM trustride.fn_audit_log_append('platform_users', v_subject_user_id, 'REGISTRATION_PRIMARY_VERIFIED', v_subject_user_id,
      'SYSTEM', NULL, NULL, NULL, jsonb_build_object('verification_id', p_verification_id, 'raw_response', p_raw_response));
  ELSE
    v_outcome := 'FAILED';

    UPDATE trustride.verification_record SET outcome = 'FAILED' WHERE verification_id = p_verification_id;
    UPDATE trustride.platform_users SET status = 'VERIFICATION_FAILED', updated_at = now() WHERE user_id = v_subject_user_id;

    PERFORM trustride.fn_audit_log_append('platform_users', v_subject_user_id, 'REGISTRATION_PRIMARY_FAILED', v_subject_user_id,
      'SYSTEM', NULL, NULL, NULL, jsonb_build_object('verification_id', p_verification_id, 'reasons', to_jsonb(v_reasons), 'raw_response', p_raw_response));
  END IF;

  RETURN v_outcome;
END;
$$;
COMMENT ON FUNCTION trustride.fn_verification_completed_accept(UUID, TEXT, TEXT, TEXT, JSONB) IS
  'The absolute Primary gate: Real Legal Names + Person Status + KRA PIN must ALL pass. Service-role only -- called from Engine 6''s VERIFICATION_COMPLETED signal, never by a plain client. No shortcuts, no manual override.';

-- Retry path for a FAILED Primary verification -- "clear error message,
-- registration stops entirely" does not mean permanently; the user may
-- correct and resubmit.
CREATE OR REPLACE FUNCTION trustride.fn_registration_retry_primary()
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_user_id          UUID := auth.uid();
  v_legal_name       TEXT;
  v_national_id      TEXT;
  v_verification_id  UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'fn_registration_retry_primary: no authenticated session';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id = v_user_id AND status = 'VERIFICATION_FAILED') THEN
    RAISE EXCEPTION 'fn_registration_retry_primary: no failed verification on record for this user';
  END IF;

  SELECT legal_name, national_id_ref INTO v_legal_name, v_national_id FROM trustride.person_profile WHERE user_id = v_user_id;

  INSERT INTO trustride.verification_record (subject_user_id, verification_type, outcome)
  VALUES (v_user_id, 'NATIONAL_ID', 'PENDING')
  RETURNING verification_id INTO v_verification_id;

  UPDATE trustride.platform_users SET status = 'PENDING_VERIFICATION', updated_at = now() WHERE user_id = v_user_id;

  INSERT INTO trustride.platform_event_outbox
    (correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES
    (gen_random_uuid(), 'TRS026_ENG001_FDN', 'TRS026_ENG006_INTG', 'VERIFICATION_REQUESTED',
     jsonb_build_object('verification_id', v_verification_id, 'subject_user_id', v_user_id,
       'verification_type', 'NATIONAL_ID', 'full_legal_name', v_legal_name, 'national_id', v_national_id),
     'VERIFICATION_REQUESTED:' || v_verification_id::text);

  PERFORM trustride.fn_audit_log_append('platform_users', v_user_id, 'REGISTRATION_PRIMARY_RETRY', v_user_id,
    'USER', NULL, NULL, NULL, jsonb_build_object('verification_id', v_verification_id));

  RETURN v_verification_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_registration_retry_primary() IS
  'Lets a user whose Primary verification FAILED retry -- opens a fresh verification_record and re-emits VERIFICATION_REQUESTED to Engine 6.';

-- Step 3.3: secondary data, soft reconciliation. Never blocks -- a value
-- that differs from what is already on file is recorded as a
-- reconciliation note, never rejected. One dispatch function across the
-- four secondary categories named in the flow, each writing to its own
-- already-existing typed table.
CREATE OR REPLACE FUNCTION trustride.fn_secondary_profile_submit(
  p_field_category TEXT, -- 'ADDRESS' | 'SOCIOECONOMIC' | 'EDUCATION' | 'RELATIONSHIP'
  p_field_data JSONB
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_user_id                UUID := auth.uid();
  v_prior_value             TEXT;
  v_new_value               TEXT;
  v_reconciliation_needed   BOOLEAN := FALSE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'fn_secondary_profile_submit: no authenticated session';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id = v_user_id) THEN
    RAISE EXCEPTION 'fn_secondary_profile_submit: caller must complete Primary capture first';
  END IF;

  CASE p_field_category
    WHEN 'ADDRESS' THEN
      SELECT county_code INTO v_prior_value FROM trustride.user_address WHERE user_id = v_user_id AND is_primary = TRUE AND valid_to IS NULL;
      v_new_value := p_field_data->>'county_code';
      v_reconciliation_needed := (v_prior_value IS NOT NULL AND v_prior_value IS DISTINCT FROM v_new_value);

      UPDATE trustride.user_address SET valid_to = CURRENT_DATE, is_primary = FALSE
      WHERE user_id = v_user_id AND is_primary = TRUE AND valid_to IS NULL;

      INSERT INTO trustride.user_address (user_id, address_type, address_line_1, town, county_code, ward, estate, is_primary)
      VALUES (v_user_id, 'PRIMARY', coalesce(p_field_data->>'address_line_1', ''), p_field_data->>'town',
              p_field_data->>'county_code', p_field_data->>'ward', p_field_data->>'estate', TRUE);

    WHEN 'SOCIOECONOMIC' THEN
      INSERT INTO trustride.user_socioeconomic_profile (user_id, income_band, household_size, primary_language, data_source, last_assessed_at)
      VALUES (v_user_id, p_field_data->>'income_band', (p_field_data->>'household_size')::SMALLINT,
              p_field_data->>'primary_language', 'SELF_REPORTED', now());

    WHEN 'EDUCATION' THEN
      INSERT INTO trustride.user_education_profile (user_id, education_level, institution, qualification, year_completed)
      VALUES (v_user_id, p_field_data->>'education_level', p_field_data->>'institution',
              p_field_data->>'qualification', (p_field_data->>'year_completed')::SMALLINT);

    WHEN 'RELATIONSHIP' THEN
      -- Next of kin: the related person may not exist as a platform_users
      -- row at all, so a full user_relationship FK linkage isn't always
      -- possible at registration time. Recorded as a governed note instead
      -- (visible only to Governors), matching user_note's existing purpose.
      INSERT INTO trustride.user_note (user_id, note_text, visibility_scope, created_by)
      VALUES (v_user_id, 'Next of kin: ' || coalesce(p_field_data->>'name', '') || ' (' || coalesce(p_field_data->>'relationship_type', '') || '), contact: ' || coalesce(p_field_data->>'contact', ''),
              'GOVERNOR', v_user_id);

    ELSE
      RAISE EXCEPTION 'fn_secondary_profile_submit: unrecognized field_category %', p_field_category;
  END CASE;

  IF v_reconciliation_needed THEN
    PERFORM trustride.fn_audit_log_append('platform_users', v_user_id, 'SECONDARY_DATA_RECONCILIATION_NOTE', v_user_id,
      'USER', NULL, NULL, jsonb_build_object('field_category', p_field_category, 'prior_value', v_prior_value),
      jsonb_build_object('field_category', p_field_category, 'new_value', v_new_value));
  END IF;

  PERFORM trustride.fn_audit_log_append('platform_users', v_user_id, 'SECONDARY_DATA_SUBMITTED', v_user_id,
    'USER', NULL, NULL, NULL, jsonb_build_object('field_category', p_field_category));

  RETURN jsonb_build_object('accepted', true, 'reconciliation_flagged', v_reconciliation_needed);
END;
$$;
COMMENT ON FUNCTION trustride.fn_secondary_profile_submit(TEXT, JSONB) IS
  'Step 3.3: secondary data is always accepted and stored; a differing prior value is recorded as a reconciliation note, never a block. Registration always continues.';

-- Lets Presentation route Login correctly without re-running government
-- verification on every login -- primary is checked once, not repeated.
CREATE OR REPLACE FUNCTION trustride.fn_my_registration_status()
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
  SELECT status FROM trustride.platform_users WHERE user_id = auth.uid();
$$;
COMMENT ON FUNCTION trustride.fn_my_registration_status() IS
  'PENDING_VERIFICATION | ACTIVE | VERIFICATION_FAILED | SUSPENDED -- the one place Presentation checks to decide which screen/shell to route to on login.';

-- ============================================================================
-- PHASE 7 -- TRIGGERS
-- ============================================================================
-- No table across Core, Identity, Governance, or Audit requires a cross-row
-- CHECK-avoidance trigger (the pattern Engines 2/3/4 needed for fleet-
-- requirement/pillar-domain/order-scope rules): none of these 68 tables
-- carry a rule that depends on the state of a sibling row at insert/update
-- time. Immutability is enforced by Phase 8's REVOKE UPDATE/DELETE grants,
-- and audit_log's hash-chain integrity is enforced by convention -- callers
-- use fn_audit_log_append(), the same discipline fn_sequence_next() and
-- fn_semantic_dictionary_supersede() already established in Substrate --
-- stated explicitly rather than silently omitted, per the corrected
-- discipline this file follows throughout.

-- ============================================================================
-- PHASE 8 -- ROW LEVEL SECURITY (part 1 of 3: Substrate + Core)
-- ============================================================================
-- Scoping principle applied throughout, table by table -- this is the exact
-- correction the original Annex H got wrong (blanket-true reads applied
-- indiscriminately to all 92 tables, including personal profile data):
--   * Governed reference/vocabulary/policy data -> blanket authenticated-read
--   * Personal profile data (Identity)          -> self-read only
--   * Sensitive event/security data (Audit)      -> Governor-read only
--   * Internal-only ledgers (event envelope etc.) -> no read policy at all

-- --- SUBSTRATE (24 tables) ---

ALTER TABLE trustride.semantic_dictionary ENABLE ROW LEVEL SECURITY;
CREATE POLICY semantic_dictionary_platform_read ON trustride.semantic_dictionary FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY semantic_dictionary_service_write ON trustride.semantic_dictionary FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.semantic_dictionary FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.domain_reference ENABLE ROW LEVEL SECURITY;
CREATE POLICY domain_reference_platform_read ON trustride.domain_reference FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY domain_reference_service_write ON trustride.domain_reference FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.domain_reference FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.unit_of_measure ENABLE ROW LEVEL SECURITY;
CREATE POLICY unit_of_measure_platform_read ON trustride.unit_of_measure FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY unit_of_measure_service_write ON trustride.unit_of_measure FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.unit_of_measure FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.time_validity_rule ENABLE ROW LEVEL SECURITY;
CREATE POLICY time_validity_rule_platform_read ON trustride.time_validity_rule FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY time_validity_rule_service_write ON trustride.time_validity_rule FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.time_validity_rule FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.geo_reference ENABLE ROW LEVEL SECURITY;
CREATE POLICY geo_reference_platform_read ON trustride.geo_reference FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY geo_reference_service_write ON trustride.geo_reference FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.geo_reference FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.calendar_reference ENABLE ROW LEVEL SECURITY;
CREATE POLICY calendar_reference_platform_read ON trustride.calendar_reference FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY calendar_reference_service_write ON trustride.calendar_reference FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.calendar_reference FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.sequence_generator ENABLE ROW LEVEL SECURITY;
CREATE POLICY sequence_generator_platform_read ON trustride.sequence_generator FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY sequence_generator_service_write ON trustride.sequence_generator FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.sequence_generator FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.notification_template ENABLE ROW LEVEL SECURITY;
CREATE POLICY notification_template_platform_read ON trustride.notification_template FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY notification_template_service_write ON trustride.notification_template FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.notification_template FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.file_reference ENABLE ROW LEVEL SECURITY;
CREATE POLICY file_reference_platform_read ON trustride.file_reference FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY file_reference_service_write ON trustride.file_reference FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.file_reference FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.geo_zone ENABLE ROW LEVEL SECURITY;
CREATE POLICY geo_zone_platform_read ON trustride.geo_zone FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY geo_zone_service_write ON trustride.geo_zone FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.tracking_element_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY tracking_element_registry_platform_read ON trustride.tracking_element_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY tracking_element_registry_service_write ON trustride.tracking_element_registry FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.tracking_element_registry FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.tracking_session ENABLE ROW LEVEL SECURITY;
CREATE POLICY tracking_session_platform_read ON trustride.tracking_session FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY tracking_session_service_write ON trustride.tracking_session FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.routing_rule ENABLE ROW LEVEL SECURITY;
CREATE POLICY routing_rule_platform_read ON trustride.routing_rule FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY routing_rule_service_write ON trustride.routing_rule FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.routing_rule FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.idempotency_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY idempotency_registry_service_only ON trustride.idempotency_registry FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.idempotency_registry FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.dead_letter_review ENABLE ROW LEVEL SECURITY;
CREATE POLICY dead_letter_review_platform_read ON trustride.dead_letter_review FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY dead_letter_review_service_write ON trustride.dead_letter_review FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.platform_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY platform_event_outbox_service_only ON trustride.platform_event_outbox FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.platform_event_orchestration ENABLE ROW LEVEL SECURITY;
CREATE POLICY platform_event_orchestration_service_only ON trustride.platform_event_orchestration FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.platform_event_coordination ENABLE ROW LEVEL SECURITY;
CREATE POLICY platform_event_coordination_service_only ON trustride.platform_event_coordination FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.platform_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY platform_event_inbox_service_only ON trustride.platform_event_inbox FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.plate_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY plate_registry_platform_read ON trustride.plate_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY plate_registry_service_write ON trustride.plate_registry FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.plate_registry FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.projection_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY projection_registry_platform_read ON trustride.projection_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY projection_registry_service_write ON trustride.projection_registry FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.projection_registry FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.plate_conformance_register ENABLE ROW LEVEL SECURITY;
CREATE POLICY plate_conformance_register_platform_read ON trustride.plate_conformance_register FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY plate_conformance_register_service_write ON trustride.plate_conformance_register FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.plate_conformance_register FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.conformance_exception ENABLE ROW LEVEL SECURITY;
CREATE POLICY conformance_exception_platform_read ON trustride.conformance_exception FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY conformance_exception_service_write ON trustride.conformance_exception FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.architect_query_register ENABLE ROW LEVEL SECURITY;
CREATE POLICY architect_query_register_platform_read ON trustride.architect_query_register FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY architect_query_register_service_write ON trustride.architect_query_register FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

-- --- CORE (14 tables) -- all governed platform-level data, none personal ---

ALTER TABLE trustride.platform_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY platform_registry_platform_read ON trustride.platform_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY platform_registry_service_write ON trustride.platform_registry FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.platform_registry FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.platform_configuration ENABLE ROW LEVEL SECURITY;
CREATE POLICY platform_configuration_platform_read ON trustride.platform_configuration FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY platform_configuration_service_write ON trustride.platform_configuration FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.platform_version ENABLE ROW LEVEL SECURITY;
CREATE POLICY platform_version_platform_read ON trustride.platform_version FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY platform_version_service_write ON trustride.platform_version FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.platform_version FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.platform_status ENABLE ROW LEVEL SECURITY;
CREATE POLICY platform_status_platform_read ON trustride.platform_status FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY platform_status_service_write ON trustride.platform_status FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.platform_status FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.platform_metadata ENABLE ROW LEVEL SECURITY;
CREATE POLICY platform_metadata_platform_read ON trustride.platform_metadata FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY platform_metadata_service_write ON trustride.platform_metadata FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.platform_security ENABLE ROW LEVEL SECURITY;
CREATE POLICY platform_security_platform_read ON trustride.platform_security FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY platform_security_service_write ON trustride.platform_security FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.platform_diagnostics ENABLE ROW LEVEL SECURITY;
CREATE POLICY platform_diagnostics_platform_read ON trustride.platform_diagnostics FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY platform_diagnostics_service_write ON trustride.platform_diagnostics FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.engine_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY engine_registry_platform_read ON trustride.engine_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY engine_registry_service_write ON trustride.engine_registry FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.engine_registry FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.engine_installation ENABLE ROW LEVEL SECURITY;
CREATE POLICY engine_installation_platform_read ON trustride.engine_installation FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY engine_installation_service_write ON trustride.engine_installation FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.engine_dependency ENABLE ROW LEVEL SECURITY;
CREATE POLICY engine_dependency_platform_read ON trustride.engine_dependency FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY engine_dependency_service_write ON trustride.engine_dependency FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.shell_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY shell_registry_platform_read ON trustride.shell_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY shell_registry_service_write ON trustride.shell_registry FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.shell_registry FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.engine_health_status ENABLE ROW LEVEL SECURITY;
CREATE POLICY engine_health_status_platform_read ON trustride.engine_health_status FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY engine_health_status_service_write ON trustride.engine_health_status FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.system_incident ENABLE ROW LEVEL SECURITY;
CREATE POLICY system_incident_platform_read ON trustride.system_incident FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY system_incident_service_write ON trustride.system_incident FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.system_metric ENABLE ROW LEVEL SECURITY;
CREATE POLICY system_metric_platform_read ON trustride.system_metric FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY system_metric_service_write ON trustride.system_metric FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

-- --- IDENTITY (31 tables) -- personal profile data: self-read, NOT blanket.
-- This is the exact correction the original Annex H got wrong.

ALTER TABLE trustride.platform_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY platform_users_self_read ON trustride.platform_users FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY platform_users_service_write ON trustride.platform_users FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.platform_users FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.user_registration ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_registration_self_read ON trustride.user_registration FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY user_registration_service_write ON trustride.user_registration FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.user_registration FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.user_authentication ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_authentication_self_read ON trustride.user_authentication FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY user_authentication_service_write ON trustride.user_authentication FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.user_authentication FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.user_authorization ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_authorization_self_read ON trustride.user_authorization FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY user_authorization_service_write ON trustride.user_authorization FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.user_authorization FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.user_records ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_records_self_read ON trustride.user_records FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY user_records_service_write ON trustride.user_records FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.user_records FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.person_profile ENABLE ROW LEVEL SECURITY;
CREATE POLICY person_profile_self_read ON trustride.person_profile FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY person_profile_service_write ON trustride.person_profile FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.user_identifier ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_identifier_self_read ON trustride.user_identifier FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY user_identifier_service_write ON trustride.user_identifier FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.user_contact ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_contact_self_read ON trustride.user_contact FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY user_contact_service_write ON trustride.user_contact FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.user_contact_preference ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_contact_preference_self_read ON trustride.user_contact_preference FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY user_contact_preference_service_write ON trustride.user_contact_preference FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.user_address ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_address_self_read ON trustride.user_address FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY user_address_service_write ON trustride.user_address FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.user_socioeconomic_profile ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_socioeconomic_profile_self_read ON trustride.user_socioeconomic_profile FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY user_socioeconomic_profile_service_write ON trustride.user_socioeconomic_profile FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.user_education_profile ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_education_profile_self_read ON trustride.user_education_profile FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY user_education_profile_service_write ON trustride.user_education_profile FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.user_employment ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_employment_self_read ON trustride.user_employment FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY user_employment_service_write ON trustride.user_employment FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.user_societal_position ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_societal_position_self_read ON trustride.user_societal_position FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY user_societal_position_service_write ON trustride.user_societal_position FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.user_relationship ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_relationship_self_read ON trustride.user_relationship FOR SELECT TO trustride_authenticated USING (user_id = auth.uid() OR related_user_id = auth.uid());
CREATE POLICY user_relationship_service_write ON trustride.user_relationship FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.user_device ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_device_self_read ON trustride.user_device FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY user_device_service_write ON trustride.user_device FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.user_lifecycle_event ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_lifecycle_event_self_read ON trustride.user_lifecycle_event FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY user_lifecycle_event_service_write ON trustride.user_lifecycle_event FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

-- user_note: internal Governor-visibility annotations ABOUT a user -- not
-- self-readable by the user the note concerns.
ALTER TABLE trustride.user_note ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_note_governor_read ON trustride.user_note FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_governor());
CREATE POLICY user_note_service_write ON trustride.user_note FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.user_metadata ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_metadata_self_read ON trustride.user_metadata FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY user_metadata_service_write ON trustride.user_metadata FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.entity_profile ENABLE ROW LEVEL SECURITY;
CREATE POLICY entity_profile_self_read ON trustride.entity_profile FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY entity_profile_service_write ON trustride.entity_profile FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.entity_registration ENABLE ROW LEVEL SECURITY;
CREATE POLICY entity_registration_self_read ON trustride.entity_registration FOR SELECT TO trustride_authenticated
  USING (EXISTS (SELECT 1 FROM trustride.entity_profile e WHERE e.entity_id = entity_registration.entity_id AND e.user_id = auth.uid()));
CREATE POLICY entity_registration_service_write ON trustride.entity_registration FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.entity_membership ENABLE ROW LEVEL SECURITY;
CREATE POLICY entity_membership_self_read ON trustride.entity_membership FOR SELECT TO trustride_authenticated
  USING (person_user_id = auth.uid() OR EXISTS (SELECT 1 FROM trustride.entity_profile e WHERE e.entity_id = entity_membership.entity_id AND e.user_id = auth.uid()));
CREATE POLICY entity_membership_service_write ON trustride.entity_membership FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.thing_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY thing_registry_self_read ON trustride.thing_registry FOR SELECT TO trustride_authenticated USING (user_id = auth.uid() OR custody_user_id = auth.uid());
CREATE POLICY thing_registry_service_write ON trustride.thing_registry FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.thing_registration ENABLE ROW LEVEL SECURITY;
CREATE POLICY thing_registration_self_read ON trustride.thing_registration FOR SELECT TO trustride_authenticated
  USING (EXISTS (SELECT 1 FROM trustride.thing_registry t WHERE t.thing_id = thing_registration.thing_id AND (t.user_id = auth.uid() OR t.custody_user_id = auth.uid())));
CREATE POLICY thing_registration_service_write ON trustride.thing_registration FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.user_type_binding ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_type_binding_self_read ON trustride.user_type_binding FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY user_type_binding_service_write ON trustride.user_type_binding FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.platform_access_event ENABLE ROW LEVEL SECURITY;
CREATE POLICY platform_access_event_self_read ON trustride.platform_access_event FOR SELECT TO trustride_authenticated USING (user_id = auth.uid() OR trustride.fn_am_i_governor());
CREATE POLICY platform_access_event_service_write ON trustride.platform_access_event FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.auth_session ENABLE ROW LEVEL SECURITY;
CREATE POLICY auth_session_self_read ON trustride.auth_session FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY auth_session_service_write ON trustride.auth_session FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.mfa_enrollment ENABLE ROW LEVEL SECURITY;
CREATE POLICY mfa_enrollment_self_read ON trustride.mfa_enrollment FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY mfa_enrollment_service_write ON trustride.mfa_enrollment FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.verification_record ENABLE ROW LEVEL SECURITY;
CREATE POLICY verification_record_self_read ON trustride.verification_record FOR SELECT TO trustride_authenticated USING (subject_user_id = auth.uid() OR trustride.fn_am_i_governor());
CREATE POLICY verification_record_service_write ON trustride.verification_record FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

-- role_definition: governed vocabulary of what roles exist -- blanket-read
-- is correct here, this is not personal data.
ALTER TABLE trustride.role_definition ENABLE ROW LEVEL SECURITY;
CREATE POLICY role_definition_platform_read ON trustride.role_definition FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY role_definition_service_write ON trustride.role_definition FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.role_definition FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.role_assignment ENABLE ROW LEVEL SECURITY;
CREATE POLICY role_assignment_self_or_governor_read ON trustride.role_assignment FOR SELECT TO trustride_authenticated USING (user_id = auth.uid() OR trustride.fn_am_i_governor());
CREATE POLICY role_assignment_service_write ON trustride.role_assignment FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

-- --- GOVERNANCE (16 tables) ---

-- Policy/pricing/structural definitions: blanket-read (transparency,
-- matches the original design intent -- "the only lawful source of pricing
-- authority" needs to be widely readable by every downstream engine).

ALTER TABLE trustride.governance_policy ENABLE ROW LEVEL SECURITY;
CREATE POLICY governance_policy_platform_read ON trustride.governance_policy FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY governance_policy_service_write ON trustride.governance_policy FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.governance_policy FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.policy_rule ENABLE ROW LEVEL SECURITY;
CREATE POLICY policy_rule_platform_read ON trustride.policy_rule FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY policy_rule_service_write ON trustride.policy_rule FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

-- exception_record: who got a governed exception, and why -- Governor-only.
ALTER TABLE trustride.exception_record ENABLE ROW LEVEL SECURITY;
CREATE POLICY exception_record_governor_read ON trustride.exception_record FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_governor());
CREATE POLICY exception_record_service_write ON trustride.exception_record FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.exception_record FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.approval_chain ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_chain_platform_read ON trustride.approval_chain FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY approval_chain_service_write ON trustride.approval_chain FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.approval_chain FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.approval_step ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_step_platform_read ON trustride.approval_step FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY approval_step_service_write ON trustride.approval_step FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

-- approval_request/approval_decision: actual case instances -- requester or
-- Governor only, not blanket.
ALTER TABLE trustride.approval_request ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_request_requester_or_governor_read ON trustride.approval_request FOR SELECT TO trustride_authenticated USING (requested_by = auth.uid() OR trustride.fn_am_i_governor());
CREATE POLICY approval_request_service_write ON trustride.approval_request FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.approval_request FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.approval_decision ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_decision_requester_or_governor_read ON trustride.approval_decision FOR SELECT TO trustride_authenticated
  USING (trustride.fn_am_i_governor() OR EXISTS (SELECT 1 FROM trustride.approval_request r WHERE r.request_id = approval_decision.request_id AND r.requested_by = auth.uid()));
CREATE POLICY approval_decision_service_write ON trustride.approval_decision FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.approval_decision FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.dual_control_requirement ENABLE ROW LEVEL SECURITY;
CREATE POLICY dual_control_requirement_platform_read ON trustride.dual_control_requirement FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY dual_control_requirement_service_write ON trustride.dual_control_requirement FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.rate_register ENABLE ROW LEVEL SECURITY;
CREATE POLICY rate_register_platform_read ON trustride.rate_register FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY rate_register_service_write ON trustride.rate_register FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.rate_register FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.threshold_register ENABLE ROW LEVEL SECURITY;
CREATE POLICY threshold_register_platform_read ON trustride.threshold_register FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY threshold_register_service_write ON trustride.threshold_register FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.threshold_register FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.technology_decision_record ENABLE ROW LEVEL SECURITY;
CREATE POLICY technology_decision_record_platform_read ON trustride.technology_decision_record FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY technology_decision_record_service_write ON trustride.technology_decision_record FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.technology_decision_record FROM PUBLIC, trustride_authenticated;

-- regulatory_contact_register / assumption_impact_assessment: sensitive
-- legal/regulatory relationship data -- Governor-only.
ALTER TABLE trustride.regulatory_contact_register ENABLE ROW LEVEL SECURITY;
CREATE POLICY regulatory_contact_register_governor_read ON trustride.regulatory_contact_register FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_governor());
CREATE POLICY regulatory_contact_register_service_write ON trustride.regulatory_contact_register FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.regulatory_contact_register FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.assumption_impact_assessment ENABLE ROW LEVEL SECURITY;
CREATE POLICY assumption_impact_assessment_governor_read ON trustride.assumption_impact_assessment FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_governor());
CREATE POLICY assumption_impact_assessment_service_write ON trustride.assumption_impact_assessment FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

-- escalation_case: Founder-tier escalations -- Governor-only.
ALTER TABLE trustride.escalation_case ENABLE ROW LEVEL SECURITY;
CREATE POLICY escalation_case_governor_read ON trustride.escalation_case FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_governor());
CREATE POLICY escalation_case_service_write ON trustride.escalation_case FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.escalation_case FROM PUBLIC, trustride_authenticated;

-- constitutional_amendment: institutional transparency of what changed --
-- blanket-read.
ALTER TABLE trustride.constitutional_amendment ENABLE ROW LEVEL SECURITY;
CREATE POLICY constitutional_amendment_platform_read ON trustride.constitutional_amendment FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY constitutional_amendment_service_write ON trustride.constitutional_amendment FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.constitutional_amendment FROM PUBLIC, trustride_authenticated;

-- delegation_of_authority: who delegated to whom -- the two parties or a
-- Governor, not blanket.
ALTER TABLE trustride.delegation_of_authority ENABLE ROW LEVEL SECURITY;
CREATE POLICY delegation_of_authority_parties_or_governor_read ON trustride.delegation_of_authority FOR SELECT TO trustride_authenticated
  USING (delegator_user_id = auth.uid() OR delegate_user_id = auth.uid() OR trustride.fn_am_i_governor());
CREATE POLICY delegation_of_authority_service_write ON trustride.delegation_of_authority FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

-- --- AUDIT (7 tables) -- sensitive event/security data: Governor-only read
-- throughout, no blanket-read anywhere (unlike the original Annex H, which
-- wrongly made every one of these blanket-readable too).

ALTER TABLE trustride.audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_log_governor_read ON trustride.audit_log FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_governor());
CREATE POLICY audit_log_service_write ON trustride.audit_log FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.audit_log FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.audit_checkpoint ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_checkpoint_governor_read ON trustride.audit_checkpoint FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_governor());
CREATE POLICY audit_checkpoint_service_write ON trustride.audit_checkpoint FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.audit_checkpoint FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.security_event ENABLE ROW LEVEL SECURITY;
CREATE POLICY security_event_governor_read ON trustride.security_event FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_governor());
CREATE POLICY security_event_service_write ON trustride.security_event FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.security_event FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.privileged_action_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY privileged_action_log_governor_read ON trustride.privileged_action_log FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_governor());
CREATE POLICY privileged_action_log_service_write ON trustride.privileged_action_log FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.privileged_action_log FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.evidence_package ENABLE ROW LEVEL SECURITY;
CREATE POLICY evidence_package_governor_read ON trustride.evidence_package FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_governor());
CREATE POLICY evidence_package_service_write ON trustride.evidence_package FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.evidence_package FROM PUBLIC, trustride_authenticated;

ALTER TABLE trustride.evidence_item ENABLE ROW LEVEL SECURITY;
CREATE POLICY evidence_item_governor_read ON trustride.evidence_item FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_governor());
CREATE POLICY evidence_item_service_write ON trustride.evidence_item FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
REVOKE UPDATE, DELETE ON trustride.evidence_item FROM PUBLIC, trustride_authenticated;

-- retention_policy: policy-like reference data, not event data -- blanket-read.
ALTER TABLE trustride.retention_policy ENABLE ROW LEVEL SECURITY;
CREATE POLICY retention_policy_platform_read ON trustride.retention_policy FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY retention_policy_service_write ON trustride.retention_policy FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

-- ============================================================================
-- PHASE 9 -- INDEXES (literal, per table)
-- ============================================================================

-- Substrate
CREATE INDEX idx_semantic_dictionary_domain_code ON trustride.semantic_dictionary (term_domain, term_code) WHERE superseded_by IS NULL;
CREATE INDEX idx_domain_reference_domain_active ON trustride.domain_reference (domain_code) WHERE active = TRUE;
CREATE INDEX idx_geo_reference_county ON trustride.geo_reference (county_code) WHERE active = TRUE;
CREATE INDEX idx_calendar_reference_type ON trustride.calendar_reference (day_type);
CREATE INDEX idx_notification_template_channel ON trustride.notification_template (channel) WHERE active = TRUE;
CREATE INDEX idx_file_reference_class ON trustride.file_reference (file_class);
CREATE INDEX idx_geo_zone_boundary ON trustride.geo_zone USING GIST (boundary);
CREATE INDEX idx_geo_zone_type_active ON trustride.geo_zone (zone_type) WHERE active = TRUE;
CREATE INDEX idx_tracking_session_job ON trustride.tracking_session (job_id);
CREATE INDEX idx_tracking_session_active ON trustride.tracking_session (status) WHERE status = 'ACTIVE';
CREATE INDEX idx_routing_rule_event_type ON trustride.routing_rule (event_type) WHERE active = TRUE;
CREATE INDEX idx_dead_letter_review_unresolved ON trustride.dead_letter_review (source_engine, target_engine) WHERE resolution IS NULL;
CREATE INDEX idx_platform_event_outbox_correlation ON trustride.platform_event_outbox (correlation_id);
CREATE INDEX idx_platform_event_outbox_status ON trustride.platform_event_outbox (signal_status);
CREATE INDEX idx_platform_event_orch_correlation ON trustride.platform_event_orchestration (correlation_id);
CREATE INDEX idx_platform_event_orch_status ON trustride.platform_event_orchestration (signal_status);
CREATE INDEX idx_platform_event_coord_correlation ON trustride.platform_event_coordination (correlation_id);
CREATE INDEX idx_platform_event_coord_status ON trustride.platform_event_coordination (signal_status);
CREATE INDEX idx_platform_event_inbox_correlation ON trustride.platform_event_inbox (correlation_id);
CREATE INDEX idx_platform_event_inbox_status ON trustride.platform_event_inbox (signal_status);
CREATE INDEX idx_plate_conformance_document ON trustride.plate_conformance_register (document_code, check_code);
CREATE INDEX idx_conformance_exception_plate ON trustride.conformance_exception (plate_code);
CREATE INDEX idx_projection_registry_shell ON trustride.projection_registry (shell);

-- Core
CREATE INDEX idx_platform_configuration_key_env ON trustride.platform_configuration (config_key, environment) WHERE effective_to IS NULL;
CREATE INDEX idx_engine_installation_engine ON trustride.engine_installation (engine_id);
CREATE INDEX idx_engine_dependency_engine ON trustride.engine_dependency (engine_id);
CREATE INDEX idx_engine_health_status_engine_time ON trustride.engine_health_status (engine_id, measured_at DESC);
CREATE INDEX idx_system_incident_engine_open ON trustride.system_incident (engine_id) WHERE resolved_at IS NULL;
CREATE INDEX idx_system_metric_engine_name_time ON trustride.system_metric (engine_id, metric_name, recorded_at DESC);

-- Identity
CREATE UNIQUE INDEX uq_platform_users_global_uid ON trustride.platform_users (global_uid);
CREATE INDEX idx_user_identifier_user ON trustride.user_identifier (user_id, identifier_type);
CREATE INDEX idx_user_contact_user_primary ON trustride.user_contact (user_id) WHERE is_primary = TRUE;
CREATE INDEX idx_user_address_user_primary ON trustride.user_address (user_id) WHERE is_primary = TRUE;
CREATE INDEX idx_user_employment_user_primary ON trustride.user_employment (user_id) WHERE is_primary = TRUE;
CREATE INDEX idx_user_relationship_user ON trustride.user_relationship (user_id);
CREATE INDEX idx_user_relationship_related ON trustride.user_relationship (related_user_id);
CREATE INDEX idx_user_device_user ON trustride.user_device (user_id);
CREATE INDEX idx_user_lifecycle_event_user_time ON trustride.user_lifecycle_event (user_id, occurred_at DESC);
CREATE INDEX idx_entity_registration_entity ON trustride.entity_registration (entity_id);
CREATE INDEX idx_entity_membership_entity ON trustride.entity_membership (entity_id);
CREATE INDEX idx_entity_membership_person ON trustride.entity_membership (person_user_id);
CREATE INDEX idx_thing_registration_thing ON trustride.thing_registration (thing_id);
CREATE INDEX idx_user_type_binding_user ON trustride.user_type_binding (user_id);
CREATE INDEX idx_platform_access_event_user_time ON trustride.platform_access_event (user_id, occurred_at DESC);
CREATE INDEX idx_auth_session_user_active ON trustride.auth_session (user_id) WHERE status = 'ACTIVE';
CREATE INDEX idx_verification_record_subject ON trustride.verification_record (subject_user_id, verification_type);
CREATE INDEX idx_verification_record_outcome ON trustride.verification_record (outcome) WHERE outcome = 'PENDING';
CREATE INDEX idx_role_assignment_user_active ON trustride.role_assignment (user_id) WHERE status = 'ACTIVE';
CREATE INDEX idx_role_assignment_role ON trustride.role_assignment (role_id) WHERE status = 'ACTIVE';

-- Governance
CREATE INDEX idx_policy_rule_policy ON trustride.policy_rule (policy_id) WHERE status = 'ACTIVE';
CREATE INDEX idx_exception_record_rule ON trustride.exception_record (rule_id);
CREATE INDEX idx_approval_step_chain ON trustride.approval_step (chain_id, step_no);
CREATE INDEX idx_approval_request_status ON trustride.approval_request (status) WHERE status = 'OPEN';
CREATE INDEX idx_approval_request_requester ON trustride.approval_request (requested_by);
CREATE INDEX idx_approval_decision_request ON trustride.approval_decision (request_id);
CREATE INDEX idx_rate_register_lookup ON trustride.rate_register (rate_class, domain_code, service_code) WHERE effective_to IS NULL;
CREATE INDEX idx_threshold_register_class ON trustride.threshold_register (threshold_class) WHERE effective_to IS NULL;
CREATE INDEX idx_regulatory_contact_register_severity ON trustride.regulatory_contact_register (severity, touchpoint_at DESC);
CREATE INDEX idx_assumption_impact_assessment_rcr ON trustride.assumption_impact_assessment (rcr_id);
CREATE INDEX idx_escalation_case_status ON trustride.escalation_case (status) WHERE status = 'OPEN';
CREATE INDEX idx_delegation_of_authority_delegator ON trustride.delegation_of_authority (delegator_user_id) WHERE status = 'ACTIVE';
CREATE INDEX idx_delegation_of_authority_delegate ON trustride.delegation_of_authority (delegate_user_id) WHERE status = 'ACTIVE';

-- Audit
CREATE INDEX idx_audit_log_entity ON trustride.audit_log (entity_type, entity_id);
CREATE INDEX idx_audit_log_occurred_at ON trustride.audit_log (occurred_at DESC);
CREATE INDEX idx_audit_log_actor ON trustride.audit_log (actor_id);
CREATE UNIQUE INDEX idx_audit_log_chain_seq ON trustride.audit_log (chain_seq DESC);
CREATE INDEX idx_security_event_subject ON trustride.security_event (subject_user_id, occurred_at DESC);
CREATE INDEX idx_security_event_escalated ON trustride.security_event (escalated) WHERE escalated = TRUE;
CREATE INDEX idx_privileged_action_log_actor_time ON trustride.privileged_action_log (actor_id, performed_at DESC);
CREATE INDEX idx_evidence_item_package ON trustride.evidence_item (package_id);

-- ============================================================================
-- PHASE 10 -- VIEWS
-- ============================================================================

CREATE VIEW trustride.v_semantic_dictionary_current AS
  SELECT semantic_id, term_domain, term_code, term_label, term_definition, version, effective_from
  FROM trustride.semantic_dictionary WHERE superseded_by IS NULL;
COMMENT ON VIEW trustride.v_semantic_dictionary_current IS
  'The current (non-superseded) definition per term_domain/term_code.';

CREATE VIEW trustride.v_domain_reference_active AS
  SELECT reference_id, domain_code, code_value, code_label, sort_order
  FROM trustride.domain_reference WHERE active = TRUE ORDER BY domain_code, sort_order;

CREATE VIEW trustride.v_engine_registry_status AS
  SELECT er.engine_no, er.engine_code, er.engine_name, er.status, ei.current_phase, ei.status AS installation_status
  FROM trustride.engine_registry er
  LEFT JOIN trustride.engine_installation ei ON ei.engine_id = er.engine_id
  ORDER BY er.engine_no;
COMMENT ON VIEW trustride.v_engine_registry_status IS
  'One row per engine, its registration and its current installation phase together -- the Sovereign Executive Console''s own engine-status read surface.';

CREATE VIEW trustride.v_rate_register_active AS
  SELECT rate_id, rate_code, rate_class, rate_value, currency, domain_code, service_code
  FROM trustride.rate_register WHERE effective_to IS NULL;
COMMENT ON VIEW trustride.v_rate_register_active IS
  'Currently effective rates only -- the lawful read surface every downstream engine consults for pricing authority.';

GRANT SELECT ON
  trustride.v_semantic_dictionary_current, trustride.v_domain_reference_active,
  trustride.v_engine_registry_status, trustride.v_rate_register_active
TO trustride_authenticated;

-- ============================================================================
-- PHASE 11 -- PRIVILEGE LOCKDOWN
-- ============================================================================
-- Roles were already created in Phase 1 (see Correction 7 in the header);
-- this phase carries the actual GRANT statements, which correctly wait
-- until every table exists.

GRANT USAGE ON SCHEMA trustride TO trustride_authenticated, trs026_eng001_fdn_service;
GRANT SELECT ON ALL TABLES IN SCHEMA trustride TO trustride_authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA trustride TO trs026_eng001_fdn_service;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride TO trs026_eng001_fdn_service;

-- Bridge to Supabase's own built-in roles -- without this, the RLS policies
-- above are unreachable through a normal client connection.
GRANT trustride_authenticated TO authenticated;
GRANT trs026_eng001_fdn_service TO service_role;

-- Functions a real authenticated end user calls directly (all SECURITY
-- DEFINER, all internally gated where authority is required).
GRANT EXECUTE ON FUNCTION trustride.fn_user_register(TEXT, TEXT, TEXT, TEXT, TEXT, JSONB) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_founder_bootstrap() TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_role_assign(UUID, TEXT) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_am_i_administrator() TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_am_i_governor() TO trustride_authenticated;
-- Registration & Authentication Flow: user-facing entry points only.
-- fn_verification_completed_accept is deliberately NOT granted here -- it is
-- Foundation's own accept-handler for Engine 6's signal, service-role only,
-- already covered by the blanket "GRANT ... TO trs026_eng001_fdn_service" above.
GRANT EXECUTE ON FUNCTION trustride.fn_registration_capture_primary(TEXT, TEXT, BOOLEAN) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_registration_retry_primary() TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_secondary_profile_submit(TEXT, JSONB) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_my_registration_status() TO trustride_authenticated;

-- Functions only ever called internally by other functions (running as
-- definer), never directly by a plain client -- service role only. A plain
-- client calling fn_audit_log_append directly could forge audit entries;
-- this is deliberately not granted to trustride_authenticated.
GRANT EXECUTE ON FUNCTION trustride.fn_sequence_next(TEXT) TO trs026_eng001_fdn_service;
GRANT EXECUTE ON FUNCTION trustride.fn_semantic_dictionary_supersede(TEXT, TEXT, TEXT, TEXT) TO trs026_eng001_fdn_service;
GRANT EXECUTE ON FUNCTION trustride.fn_audit_log_append(TEXT, UUID, TEXT, UUID, TEXT, TEXT, TEXT, JSONB, JSONB) TO trs026_eng001_fdn_service;
GRANT EXECUTE ON FUNCTION trustride.fn_audit_checkpoint_seal(UUID) TO trs026_eng001_fdn_service;

-- ============================================================================
-- PHASE 12 -- VALIDATION
-- ============================================================================
DO $$
DECLARE
  v_table_count     INTEGER;
  v_function_count  INTEGER;
BEGIN
  SELECT count(*) INTO v_table_count
  FROM information_schema.tables
  WHERE table_schema = 'trustride' AND table_type = 'BASE TABLE';
  IF v_table_count <> 92 THEN
    RAISE EXCEPTION 'Foundation validation failed: expected 92 tables, found %', v_table_count;
  END IF;

  SELECT count(*) INTO v_function_count
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'trustride'
    AND p.proname IN ('fn_sequence_next','fn_semantic_dictionary_supersede','fn_audit_log_append',
                       'fn_audit_checkpoint_seal','fn_am_i_administrator','fn_am_i_governor',
                       'fn_user_register','fn_role_assign','fn_founder_bootstrap',
                       'fn_registration_capture_primary','fn_verification_completed_accept',
                       'fn_registration_retry_primary','fn_secondary_profile_submit','fn_my_registration_status');
  IF v_function_count <> 14 THEN
    RAISE EXCEPTION 'Foundation validation failed: expected 14 core functions, found %', v_function_count;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trustride_authenticated') THEN
    RAISE EXCEPTION 'Foundation validation failed: trustride_authenticated role missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng001_fdn_service') THEN
    RAISE EXCEPTION 'Foundation validation failed: trs026_eng001_fdn_service role missing';
  END IF;

  RAISE NOTICE 'Foundation validation passed: 92/92 tables, 14/14 core functions, both roles present.';
END
$$;

-- ============================================================================
-- PHASE 13 -- FINALIZATION & SEED DATA
-- ============================================================================
-- Note: `platform_registry` (Core) and `rate_register`/`threshold_register`
-- (Governance) are deliberately left EMPTY here -- they require real
-- business registration data (KRA PIN, registration number) and real
-- approved commercial figures this instrument does not have and will not
-- fabricate. `platform_registry` is genesis-sealed as a separate, deliberate
-- action once the Founder supplies the real values.

-- The three constitutional plates (FDN-001 §11.1, digests of record)
INSERT INTO trustride.plate_registry (plate_code, exhibit_filename, sha256_digest, adopted_on, adopted_by, page_position) VALUES
  ('PLATE_I',   'TRS026_ENGINE_EVENT_SIGNAL_FLOW.png', 'dcec3677fb0593f60adfb5a27191fd60098e1afc3e89921bf4b2751022497c85', '2026-08-16', 'Founder', 3),
  ('PLATE_II',  'TRS026_BACKEND_ARCHITECTURE.png',      '8466686aaffd34609703c097f959ae3816329a9db23ee881f094833b075b473e', '2026-08-16', 'Founder', 4),
  ('PLATE_III', 'TRS026_FRONTEND_ARCHITECTURE.png',     'a06435e0e26460a35d29b7cfa5226c219d2d2896d8554a3a108068f9dc7b91eb', '2026-08-16', 'Founder', 5);

INSERT INTO trustride.architect_query_register (raised_by, constraint_statement, options_presented, founder_ruling, ruled_on) VALUES
  ('FDN-001 Part XI', 'AQ-001: Plate I shows the Hybrid Bridge as heartbeat while Plate II lists Integration inside Layer 2.',
   '["006 INTG stays in Layer 2 and lends transport to the bridge", "006 INTG is dual-listed as Layer 2 owner and Layer 3 carrier", "transport moves wholly to 007/008"]'::jsonb,
   'BOTH ARE LAW -- engine-level (Plate I) transport vs platform-level (Plate II) ownership, per Founder ruling 2026-08-16', '2026-08-16'),
  ('FDN-001 Part XI', 'AQ-002: Plate III requires an on-device outbox -- who owns the physical queue.',
   '["Foundation defines envelope, Presentation owns device queue", "Foundation owns both envelope and queue as substrate"]'::jsonb,
   'GRANTED -- owned by Layer 3 (Orchestration 007 + Coordination 008), neither Substrate nor Presentation alone', '2026-08-16'),
  ('FDN-001 Part XI', 'AQ-003: Coordination fan-in requires a declared timeout -- where does the governed threshold live.',
   '["hold in threshold_register per signal type", "one platform-wide default with per-type override"]'::jsonb,
   'GRANTED -- owned and defined by Workflow Coordination (008)', '2026-08-16');

INSERT INTO trustride.unit_of_measure (unit_code, unit_name, unit_class) VALUES
  ('KM', 'Kilometre', 'DISTANCE'), ('KG', 'Kilogram', 'WEIGHT'), ('MIN', 'Minute', 'TIME');

INSERT INTO trustride.tracking_element_registry (element_code, element_label, element_definition) VALUES
  ('RESOURCE_TYPE',  'Resource Type',  'The class of resource performing the Job -- e.g. BODA_BODA, EXECUTIVE_ASSISTANT.'),
  ('RESOURCE_ID',    'Resource ID',    'The human-legible identity of the specific resource -- rider name, plate number, or Executive Assistant identity.'),
  ('ETA',            'ETA',            'Estimated time of arrival at the next milestone of the Job.'),
  ('STATUS',         'Status',         'The current dispatch/execution status of the Job.'),
  ('EXACT_LOCATION', 'Exact Location', 'The live geospatial position of the resource during an active Job.');

INSERT INTO trustride.sequence_generator (sequence_code, prefix, padding) VALUES
  ('TRS026-ORDER', 'TRS026-ORDER', 9), ('TRS026-RECEIPT', 'TRS026-RECEIPT', 9), ('TRS026-INV', 'TRS026-INV', 9),
  ('TRS026-PAYOUT', 'TRS026-PAYOUT', 9), ('TRS026-QUOTE', 'TRS026-QUOTE', 9), ('TRS026-CERT', 'TRS026-CERT', 9),
  ('TRS026-U', 'TRS026-U', 9);

INSERT INTO trustride.domain_reference (domain_code, code_value, code_label, sort_order) VALUES
  ('USER_TYPE_DOMAIN', 'CUSTOMER', 'Customer', 1), ('USER_TYPE_DOMAIN', 'PARTNER', 'Partner', 2),
  ('USER_TYPE_DOMAIN', 'OPERATOR', 'Operator', 3), ('USER_TYPE_DOMAIN', 'INTERMEDIARY', 'Intermediary', 4),
  ('USER_TYPE_DOMAIN', 'GOVERNOR', 'Governor', 5),
  ('ACCESS_MODE', 'VISITOR', 'Visitor', 1), ('ACCESS_MODE', 'RETURNING', 'Returning', 2), ('ACCESS_MODE', 'AUTHENTICATED', 'Authenticated', 3),
  ('SIGNAL_STATUS', 'PENDING', 'Pending', 1), ('SIGNAL_STATUS', 'DISPATCHED', 'Dispatched', 2), ('SIGNAL_STATUS', 'RECEIVED', 'Received', 3),
  ('SIGNAL_STATUS', 'ACCEPTED', 'Accepted', 4), ('SIGNAL_STATUS', 'REJECTED', 'Rejected', 5), ('SIGNAL_STATUS', 'DEAD_LETTER', 'Dead Letter', 6);

-- The 47 constitutional counties (Kisumu first, Article 38.1 / VTDR)
INSERT INTO trustride.geo_reference (county_code, county_name) VALUES
  ('42','Kisumu'), ('01','Mombasa'), ('02','Kwale'), ('03','Kilifi'), ('04','Tana River'),
  ('05','Lamu'), ('06','Taita-Taveta'), ('07','Garissa'), ('08','Wajir'), ('09','Mandera'),
  ('10','Marsabit'), ('11','Isiolo'), ('12','Meru'), ('13','Tharaka-Nithi'), ('14','Embu'),
  ('15','Kitui'), ('16','Machakos'), ('17','Makueni'), ('18','Nyandarua'), ('19','Nyeri'),
  ('20','Kirinyaga'), ('21','Murang''a'), ('22','Kiambu'), ('23','Turkana'), ('24','West Pokot'),
  ('25','Samburu'), ('26','Trans Nzoia'), ('27','Uasin Gishu'), ('28','Elgeyo-Marakwet'), ('29','Nandi'),
  ('30','Baringo'), ('31','Laikipia'), ('32','Nakuru'), ('33','Narok'), ('34','Kajiado'),
  ('35','Kericho'), ('36','Bomet'), ('37','Kakamega'), ('38','Vihiga'), ('39','Bungoma'),
  ('40','Busia'), ('41','Siaya'), ('43','Homa Bay'), ('44','Migori'), ('45','Kisii'),
  ('46','Nyamira'), ('47','Nairobi');

-- Fixed-date 2026 holidays only -- movable ones (Good Friday, Easter Monday,
-- Eid) are gazetted separately and deliberately not guessed here.
INSERT INTO trustride.calendar_reference (calendar_date, day_type, description) VALUES
  ('2026-01-01', 'PUBLIC_HOLIDAY', 'New Year''s Day'), ('2026-05-01', 'PUBLIC_HOLIDAY', 'Labour Day'),
  ('2026-06-01', 'PUBLIC_HOLIDAY', 'Madaraka Day'), ('2026-10-20', 'PUBLIC_HOLIDAY', 'Mashujaa Day'),
  ('2026-12-12', 'PUBLIC_HOLIDAY', 'Jamhuri Day'), ('2026-12-25', 'PUBLIC_HOLIDAY', 'Christmas Day'),
  ('2026-12-26', 'PUBLIC_HOLIDAY', 'Boxing Day');

-- The eleven-engine Constitutional Engine Registry (Annex C), in canonical
-- order, with the Sovereign Engine Registry's own Domain/Class/Type values
-- adopted 2026-08-21.
INSERT INTO trustride.engine_registry (engine_no, engine_code, engine_domain, engine_class, engine_type, engine_name, platform_version, engine_version, installation_order, status, created_by) VALUES
  (1,  'TRS026_ENG001_FDN',     'Platform Foundation',        'Foundation Engine',    'Constitutional Runtime',       'TrustRide Foundation',              '1.0.0', '1.0.0', 1,  'INSTALLED',  '00000000-0000-0000-0000-000000000000'),
  (2,  'TRS026_ENG002_RESC',    'Institutional Resources',    'Resource Engine',      'Resource Management',          'TrustRide Resources',               '1.0.0', '1.0.1', 2,  'REGISTERED', '00000000-0000-0000-0000-000000000000'),
  (3,  'TRS026_ENG003_SERV',    'TrustRide Service Domain',   'Service Engine',       'Business Service Catalogue',   'TrustRide Services',                '1.0.0', '1.0.1', 3,  'REGISTERED', '00000000-0000-0000-0000-000000000000'),
  (4,  'TRS026_ENG004_BUS',     'TrustRide Business Domain',  'Business Engine',      'Commercial & Operational',     'TrustRide Business',                '1.0.0', '1.0.1', 4,  'REGISTERED', '00000000-0000-0000-0000-000000000000'),
  (5,  'TRS026_ENG005_COST',    'Service Cost & Fare Economics','Cost Engine',        'Cost/Fare Determination',      'TrustRide Cost Buildup',            '1.0.0', '1.1.1', 5,  'REGISTERED', '00000000-0000-0000-0000-000000000000'),
  (6,  'TRS026_ENG006_INTG',    'Platform Integration',       'Integration Engine',   'External Systems Integration', 'TrustRide Integration',             '1.0.0', '1.0.0', 6,  'REGISTERED', '00000000-0000-0000-0000-000000000000'),
  (7,  'TRS026_ENG007_ORCH',    'Workflow Orchestration',     'Control Engine',       'Process Orchestration',        'TrustRide Workflow Orchestration',  '1.0.0', '1.0.0', 7,  'REGISTERED', '00000000-0000-0000-0000-000000000000'),
  (8,  'TRS026_ENG008_COORD',   'Workflow Coordination',      'Coordination Engine',  'Event & Execution Coordination','TrustRide Workflow Coordination',  '1.0.0', '1.0.0', 8,  'REGISTERED', '00000000-0000-0000-0000-000000000000'),
  (9,  'TRS026_ENG009_AIADV',   'Intelligence & Advisory',    'Advisory Intelligence Engine', 'AI/ML Advisory',       'TrustRide AI/ML Advisory',          '1.0.0', '1.0.0', 9,  'REGISTERED', '00000000-0000-0000-0000-000000000000'),
  (10, 'TRS026_ENG010_MODEL',   'Scenario Modelling',         'Analysis Engine',      'Digital Twin & Simulation',    'TrustRide Scenario Modelling',      '1.0.0', '1.0.0', 10, 'REGISTERED', '00000000-0000-0000-0000-000000000000'),
  (11, 'TRS026_ENG011_PRESENT', 'Presentation Domain',        'Experience Engine',    'UI/UX & Application Delivery', 'TrustRide Presentation',            '1.0.0', '1.0.0', 11, 'REGISTERED', '00000000-0000-0000-0000-000000000000');

-- The five constitutional shells -- no sixth exists.
INSERT INTO trustride.shell_registry (shell_code, shell_name, serves_user_types, isolation_class) VALUES
  ('USER_HUB',                    'User Hub',                    ARRAY['CUSTOMER','PARTNER'],              'EXTERNAL'),
  ('OPERATOR_APP',                'Operator App',                ARRAY['OPERATOR'],                        'INTERNAL'),
  ('ADMIN_CONSOLE',               'Admin Console',               ARRAY['GOVERNOR'],                        'INTERNAL'),
  ('SOVEREIGN_EXECUTIVE_CONSOLE', 'Sovereign Executive Console',  ARRAY['GOVERNOR'],                        'INTERNAL'),
  ('MARKETPLACE_HUB',             'Marketplace Hub',              ARRAY['CUSTOMER','PARTNER','INTERMEDIARY'], 'EXTERNAL');

-- Institutional roles named explicitly in FDN-001 Part VI §3.2 -- the
-- FOUNDER role is what fn_founder_bootstrap() grants to the first real
-- authenticated caller.
INSERT INTO trustride.role_definition (role_code, role_name, user_type_code, constitutional_basis) VALUES
  ('FOUNDER',              'Founder',                        'GOVERNOR', 'TBOC Art.12.5, 62'),
  ('EXECUTIVE',             'Executive',                      'GOVERNOR', 'TBOC Art.12.5'),
  ('ADMINISTRATOR',         'Administrator',                  'GOVERNOR', 'TBOC Art.12.5'),
  ('SAFEGUARDING_OFFICER',  'Safeguarding Officer',           'GOVERNOR', 'TBOC Art.12.5, 52'),
  ('SECURITY_OPERATIONS',   'Security Operations',            'GOVERNOR', 'TBOC Art.12.5, 54'),
  ('DISPATCHER',            'Dispatcher',                     'OPERATOR', 'TBOC Art.12.3');

-- ============================================================================
-- END OF ENGINE 001 -- FOUNDATION (Substrate + Core + Identity + Governance
-- + Audit, 92 tables, one single migration file, per Founder ruling
-- 2026-08-23). Next engine to build: 002 Resources -- only after this file
-- passes full verification live in trustride-stagging.
-- ============================================================================
