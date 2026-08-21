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
-- ENGINE DOMAIN        : Foundation
-- ENGINE CLASS         : Constitutional / Sovereign
-- ENGINE TYPE          : Layer 1 -- Foundation (Plate II)
-- ENGINE NAME          : TrustRide Foundation
-- ENGINE DESCRIPTION   : The sovereign platform brain -- identity, authority,
--                        audit, vocabulary, geography, sequence, and the
--                        signal substrate every one of the eleven engines
--                        depends on.
-- ENGINE FUNCTION      : Constitutes five sub-engines: Shared Runtime
--                        Substrate, TrustRide Core, TrustRide Identity,
--                        TrustRide Governance, TrustRide Audit.
-- PLATFORM VERSION     : 1.0.0
-- ENGINE VERSION       : 1.0.0
-- MIGRATION DATA
-- FILE NAME            : 20260821000001_engine001_foundation_part1_substrate.sql
-- INSTALLATION ORDER   : 001 (Section 1 of 5 -- Shared Runtime Substrate)
-- STATUS               : IN_PROGRESS -- Substrate section only; Core,
--                        Identity, Governance, Audit follow in their own
--                        dated files, then are merged into one final
--                        TRS026_ENG001_FDN.sql per the Founder's standing
--                        instruction (2026-08-20/21 ruling: Substrate
--                        installs FIRST, ahead of Core/Identity/Governance/
--                        Audit -- this supersedes Annex H's originally
--                        adopted "Core->Identity->Governance->Audit->
--                        Substrate" order; the amendment is recorded here
--                        and must be reflected back into FDN-001 Annex H
--                        and Annex E's migration-order note once the full
--                        engine is complete).
-- CREATED AT           : 2026-08-21
-- CREATED BY           : Onyango Albert Chitayi (Founder) + Engineering
-- ============================================================================
--
-- Corrections applied in this rewrite, relative to the original Annex H
-- compilation (found during the 2026-08-20 full corpus audit and confirmed
-- by the Founder as the reason for starting fresh):
--   1. This header is the actual, complete Annex D.1 format -- the original
--      Annex H's own worked example header omitted the PLATFORM ID / ENGINE
--      ID / MIGRATION DATA fields entirely.
--   2. Phase 9 (Indexes) is compiled literally, per table, below -- not
--      described as a "pattern to apply" the way Annex H left it.
--   3. Phase 6 (Functions) and Phase 7 (Triggers) are populated where this
--      sub-engine genuinely needs them (sequence issuance); Annex H had
--      zero CREATE FUNCTION / CREATE TRIGGER statements anywhere.
--   4. Phase 11 (Privilege Lockdown) explicitly bridges the custom roles to
--      Supabase's own `authenticated` and `service_role` roles -- without
--      this, the RLS policies below are unreachable through Supabase's
--      normal client connection. Annex H created the custom roles but never
--      bridged them.
--   5. Role naming is aligned to the same `trs026_eng{NNN}_{abbrev}_service`
--      pattern Engines 2-11 already use, replacing the inconsistent
--      short-form `trs_fdn_service` / `trs_fdn_audit_service` Annex H used.

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

-- ============================================================================
-- PHASE 2 -- ENUMS (Substrate-scoped only; Core/Identity/Governance/Audit
-- enums are declared in their own sections)
-- ============================================================================
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

-- ============================================================================
-- PHASE 3 -- TABLES · PHASE 4 -- CONSTRAINTS · PHASE 5 -- RELATIONSHIPS
-- (compiled together per table, as the corpus's own convention does)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 3.A SEMANTIC LAYER
-- ---------------------------------------------------------------------------

-- [Trace: TBOC-v2.0.0 | Article 59 | FDN-001 Part X SUBSYSTEM 1]
-- Append-only, versioned. No engine may invent, override, or reinterpret a
-- shared semantic concept once defined here.
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

-- [Trace: TBOC-v2.0.0 | Article 59 | FDN-001 Part X SUBSYSTEM 1]
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

-- [Trace: TBOC-v2.0.0 | Article 59]
CREATE TABLE trustride.unit_of_measure (
  unit_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  unit_code   TEXT NOT NULL UNIQUE,
  unit_name   TEXT NOT NULL,
  unit_class  TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.unit_of_measure IS
  '[Trace: TBOC-v2.0.0 Art.59] Canonical units (KM, KG, MIN) and conversion basis for catalogue, dispatch, and pricing.';

-- [Trace: TBOC-v2.0.0 | Article 59]
CREATE TABLE trustride.time_validity_rule (
  validity_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  validity_code  TEXT NOT NULL UNIQUE,
  description    TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.time_validity_rule IS
  '[Trace: TBOC-v2.0.0 Art.59] Canonical time-validity vocabulary for policies, prices, schedules, and standing jobs.';

-- ---------------------------------------------------------------------------
-- 3.B REFERENCE DATA
-- ---------------------------------------------------------------------------

-- [Trace: TBOC-v2.0.0 | Article 42.5 | FDN-001 Part X SUBSYSTEM 2]
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

-- [Trace: TBOC-v2.0.0 | Article 50]
CREATE TABLE trustride.calendar_reference (
  calendar_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  calendar_date  DATE NOT NULL UNIQUE,
  day_type       trustride.substrate_calendar_day_type_enum NOT NULL,
  description    TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.calendar_reference IS
  '[Trace: TBOC-v2.0.0 Art.50] Kenyan public holidays and statutory calendar affecting pricing, scheduling, SLA, and statutory deadlines.';

-- [Trace: TBOC-v2.0.0 | Article 42.5]
-- The single lawful source of TRS026-prefixed institutional numbers.
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

-- [Trace: TBOC-v2.0.0 | Article 50]
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

-- [Trace: TBOC-v2.0.0 | Article 50]
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
-- 3.C GEOSPATIAL & TRACKING SUBSTRATE
-- ---------------------------------------------------------------------------

-- [Trace: TBOC-v2.0.0 | Article 21 | FDN-001 Part X SUBSYSTEM 3]
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

-- [Trace: TBOC-v2.0.0 | Article 21]
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

-- [Trace: TBOC-v2.0.0 | Article 21]
-- Active-session-only by construction: created at job start, closed at
-- completion. Legitimately mutable (ended_at, status) -- not append-only.
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
-- 3.D EVENT SUBSTRATE MACHINERY (registries)
-- ---------------------------------------------------------------------------

-- [Trace: FDN-001 Part X SUBSYSTEM 4]
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

-- [Trace: FDN-001 Part X SUBSYSTEM 4]
CREATE TABLE trustride.idempotency_registry (
  idempotency_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  idempotency_key    TEXT NOT NULL UNIQUE,
  source_engine      TEXT NOT NULL,
  first_seen_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  outcome_ref        UUID
);
COMMENT ON TABLE trustride.idempotency_registry IS
  '[Trace: TBOC-v2.0.0 Art.60] Guarantees no event or trigger double-executes -- never double-charge, never double-notify.';

-- [Trace: FDN-001 Part X SUBSYSTEM 4]
-- Legitimately mutable: reviewed_by/resolution/reviewed_at get filled in.
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
-- 3.E ENGINE 001 EVENT TABLES (the shared Signal Envelope, Plate I)
-- ---------------------------------------------------------------------------

-- [Trace: FDN-001 Part XI §11.2 | Plate I Station 2 -- Emission Ledger]
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

-- [Trace: FDN-001 Part XI §11.2 | Plate I Station 3 -- Bridge Transit (order)]
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

-- [Trace: FDN-001 Part XI §11.2 | Plate I Station 3 -- Bridge Transit (fan-out/fan-in)]
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

-- [Trace: FDN-001 Part XI §11.2 | Plate I Station 4 -- Reception Ledger]
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
-- 3.F ENGINE 001 CONFORMANCE TABLES (Part XI self-certification machinery)
-- ---------------------------------------------------------------------------

-- [Trace: FDN-001 §11.1] A plate is law by identity, not by resemblance.
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

-- [Trace: FDN-001 §11.4 C-III-3] A projection is never truth.
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

-- [Trace: FDN-001 §11.6] Every engine document files CC-01..CC-12 here.
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

-- [Trace: FDN-001 §11.6] Every exception is temporary unless the plate is amended.
CREATE TABLE trustride.conformance_exception (
  exception_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plate_code      trustride.substrate_plate_code_enum NOT NULL,
  departure       TEXT NOT NULL,
  justification   TEXT NOT NULL,
  founder_ruling  trustride.substrate_founder_ruling_enum NOT NULL DEFAULT 'PENDING',
  expires_on      DATE
);

-- [Trace: FDN-001 §11.6] The ruling becomes law on entry.
CREATE TABLE trustride.architect_query_register (
  query_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  raised_by            TEXT NOT NULL,
  constraint_statement TEXT NOT NULL,
  options_presented    JSONB NOT NULL,
  founder_ruling       TEXT NOT NULL DEFAULT 'PENDING',
  ruled_on             TIMESTAMPTZ
);

-- ============================================================================
-- PHASE 6 -- FUNCTIONS
-- ============================================================================

-- [Trace: TBOC-v2.0.0 | Article 42.5 | The Sequence Law]
-- The single lawful way any engine obtains an institutional number. Atomic
-- (single UPDATE...RETURNING, no read-then-write race). SECURITY DEFINER so
-- callers never need direct UPDATE rights on sequence_generator itself.
CREATE OR REPLACE FUNCTION trustride.fn_sequence_next(p_sequence_code TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_prefix  TEXT;
  v_next    BIGINT;
  v_padding SMALLINT;
BEGIN
  UPDATE trustride.sequence_generator
  SET current_value = current_value + 1,
      updated_at = now()
  WHERE sequence_code = p_sequence_code
  RETURNING prefix, current_value, padding INTO v_prefix, v_next, v_padding;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_sequence_next: unregistered sequence_code %% (Article 42.5 -- no engine generates its own numbering)', p_sequence_code;
  END IF;

  RETURN v_prefix || '-' || lpad(v_next::TEXT, v_padding, '0');
END;
$$;
COMMENT ON FUNCTION trustride.fn_sequence_next(TEXT) IS
  '[Trace: TBOC-v2.0.0 Art.42.5] Issues the next TRS026-prefixed institutional number for a registered sequence_code. Raises if the code is unregistered rather than silently inventing one.';

-- [Trace: FDN-001 Part X §3.1 | Semantic Stability -- append-only, versioned]
-- Governed supersession: never edits a definition in place, only chains
-- forward via superseded_by, exactly as Rule 6 requires.
CREATE OR REPLACE FUNCTION trustride.fn_semantic_dictionary_supersede(
  p_term_domain TEXT,
  p_term_code TEXT,
  p_new_label TEXT,
  p_new_definition TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_old_id  UUID;
  v_old_ver SMALLINT;
  v_new_id  UUID;
BEGIN
  SELECT semantic_id, version INTO v_old_id, v_old_ver
  FROM trustride.semantic_dictionary
  WHERE term_domain = p_term_domain AND term_code = p_term_code AND superseded_by IS NULL
  ORDER BY version DESC
  LIMIT 1;

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
  '[Trace: FDN-001 Part X §3.1] The only lawful way to change a semantic_dictionary definition -- always a new versioned row, the old row chained forward, never an in-place edit.';

-- ============================================================================
-- PHASE 7 -- TRIGGERS
-- ============================================================================
-- No table in this section requires a cross-row CHECK (PostgreSQL forbids
-- subqueries in CHECK constraints, which is where Engines 2/3/4 needed
-- deferred constraint triggers). Substrate's tables are governed vocabulary
-- and event ledgers with no such cross-row rule -- stated here explicitly
-- rather than silently omitted, per the corrected discipline (Annex H left
-- this phase blank without saying why).

-- ============================================================================
-- PHASE 8 -- ROW LEVEL SECURITY
-- ============================================================================
-- All Substrate tables hold governed shared vocabulary or platform-internal
-- ledger state -- never personal or business-transaction data -- so a
-- blanket authenticated-read policy is the *correct* lawful-visibility
-- outcome here (unlike Foundation's Identity tables, where the same blanket
-- pattern was wrongly applied to personal profile data in the original
-- Annex H). Internal-only ledgers (event envelope, idempotency, dead-letter,
-- conformance workings) get no read policy for ordinary users at all.

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

-- ============================================================================
-- PHASE 9 -- INDEXES (literal, per table -- not a "pattern" comment)
-- ============================================================================
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

-- ============================================================================
-- PHASE 10 -- VIEWS
-- ============================================================================

-- [Trace: FDN-001 Part X §3.1] Every engine reads current definitions
-- through here, never by re-deriving "latest version" logic locally.
CREATE VIEW trustride.v_semantic_dictionary_current AS
  SELECT semantic_id, term_domain, term_code, term_label, term_definition, version, effective_from
  FROM trustride.semantic_dictionary
  WHERE superseded_by IS NULL;
COMMENT ON VIEW trustride.v_semantic_dictionary_current IS
  'The current (non-superseded) definition per term_domain/term_code -- the lawful read surface for semantic_dictionary.';

CREATE VIEW trustride.v_domain_reference_active AS
  SELECT reference_id, domain_code, code_value, code_label, sort_order
  FROM trustride.domain_reference
  WHERE active = TRUE
  ORDER BY domain_code, sort_order;
COMMENT ON VIEW trustride.v_domain_reference_active IS
  'Active reference codes only, pre-sorted for direct catalogue/dropdown rendering by Presentation.';

GRANT SELECT ON trustride.v_semantic_dictionary_current, trustride.v_domain_reference_active TO trustride_authenticated;

-- ============================================================================
-- PHASE 11 -- PRIVILEGE LOCKDOWN
-- ============================================================================
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

GRANT USAGE ON SCHEMA trustride TO trustride_authenticated, trs026_eng001_fdn_service;
GRANT SELECT ON ALL TABLES IN SCHEMA trustride TO trustride_authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA trustride TO trs026_eng001_fdn_service;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride TO trs026_eng001_fdn_service;

-- Correction over the original Annex H: bridge the custom roles to
-- Supabase's own built-in roles, or none of the RLS policies above are ever
-- actually reachable through a normal client connection.
GRANT trustride_authenticated TO authenticated;
GRANT trs026_eng001_fdn_service TO service_role;
GRANT EXECUTE ON FUNCTION trustride.fn_sequence_next(TEXT) TO trs026_eng001_fdn_service;
GRANT EXECUTE ON FUNCTION trustride.fn_semantic_dictionary_supersede(TEXT, TEXT, TEXT, TEXT) TO trs026_eng001_fdn_service;

-- ============================================================================
-- PHASE 12 -- VALIDATION
-- ============================================================================
DO $$
DECLARE
  v_table_count INTEGER;
BEGIN
  SELECT count(*) INTO v_table_count
  FROM information_schema.tables
  WHERE table_schema = 'trustride'
    AND table_name IN (
      'semantic_dictionary','domain_reference','unit_of_measure','time_validity_rule',
      'geo_reference','calendar_reference','sequence_generator','notification_template','file_reference',
      'geo_zone','tracking_element_registry','tracking_session',
      'routing_rule','idempotency_registry','dead_letter_review',
      'platform_event_outbox','platform_event_orchestration','platform_event_coordination','platform_event_inbox',
      'plate_registry','projection_registry','plate_conformance_register','conformance_exception','architect_query_register'
    );
  IF v_table_count <> 24 THEN
    RAISE EXCEPTION 'Substrate validation failed: expected 24 tables, found %', v_table_count;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_sequence_next') THEN
    RAISE EXCEPTION 'Substrate validation failed: fn_sequence_next is missing';
  END IF;

  RAISE NOTICE 'Substrate validation passed: 24/24 tables, functions present.';
END
$$;

-- ============================================================================
-- PHASE 13 -- FINALIZATION & SEED DATA
-- ============================================================================

-- The three constitutional plates (FDN-001 §11.1, digests of record)
INSERT INTO trustride.plate_registry (plate_code, exhibit_filename, sha256_digest, adopted_on, adopted_by, page_position) VALUES
  ('PLATE_I',   'TRS026_ENGINE_EVENT_SIGNAL_FLOW.png', 'dcec3677fb0593f60adfb5a27191fd60098e1afc3e89921bf4b2751022497c85', '2026-08-16', 'Founder', 3),
  ('PLATE_II',  'TRS026_BACKEND_ARCHITECTURE.png',      '8466686aaffd34609703c097f959ae3816329a9db23ee881f094833b075b473e', '2026-08-16', 'Founder', 4),
  ('PLATE_III', 'TRS026_FRONTEND_ARCHITECTURE.png',     'a06435e0e26460a35d29b7cfa5226c219d2d2896d8554a3a108068f9dc7b91eb', '2026-08-16', 'Founder', 5);

-- The three architect queries already ruled by the Founder (FDN-001 §11.6)
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

-- Units of measure named in FDN-001 Part X §2
INSERT INTO trustride.unit_of_measure (unit_code, unit_name, unit_class) VALUES
  ('KM',  'Kilometre', 'DISTANCE'),
  ('KG',  'Kilogram',  'WEIGHT'),
  ('MIN', 'Minute',    'TIME');

-- The five constitutionally mandatory tracking elements (Article 21)
INSERT INTO trustride.tracking_element_registry (element_code, element_label, element_definition) VALUES
  ('RESOURCE_TYPE',   'Resource Type',   'The class of resource performing the Job -- e.g. BODA_BODA, EXECUTIVE_ASSISTANT.'),
  ('RESOURCE_ID',     'Resource ID',     'The human-legible identity of the specific resource -- rider name, plate number, or Executive Assistant identity.'),
  ('ETA',             'ETA',             'Estimated time of arrival at the next milestone of the Job.'),
  ('STATUS',          'Status',          'The current dispatch/execution status of the Job.'),
  ('EXACT_LOCATION',  'Exact Location',  'The live geospatial position of the resource during an active Job.');

-- Institutional number sequences (Article 42.5, plus the codes named across
-- the corpus: TRS026-ORDER, TRS026-RECEIPT, TRS026-INV, TRS026-PAYOUT,
-- TRS026-QUOTE (Engine 5 §2.5), TRS026-CERT (Engine 8 §2.21))
INSERT INTO trustride.sequence_generator (sequence_code, prefix, padding) VALUES
  ('TRS026-ORDER',   'TRS026-ORDER',   9),
  ('TRS026-RECEIPT', 'TRS026-RECEIPT', 9),
  ('TRS026-INV',     'TRS026-INV',     9),
  ('TRS026-PAYOUT',  'TRS026-PAYOUT',  9),
  ('TRS026-QUOTE',   'TRS026-QUOTE',   9),
  ('TRS026-CERT',    'TRS026-CERT',    9);

-- Domain reference: the constitutional vocabulary already adopted in TBOC
-- Article 12 and FDN-001 §11.2, made governed data rather than re-typed
-- as a string literal in every downstream engine.
INSERT INTO trustride.domain_reference (domain_code, code_value, code_label, sort_order) VALUES
  ('USER_TYPE_DOMAIN', 'CUSTOMER',     'Customer',     1),
  ('USER_TYPE_DOMAIN', 'PARTNER',      'Partner',      2),
  ('USER_TYPE_DOMAIN', 'OPERATOR',     'Operator',     3),
  ('USER_TYPE_DOMAIN', 'INTERMEDIARY', 'Intermediary', 4),
  ('USER_TYPE_DOMAIN', 'GOVERNOR',     'Governor',     5),
  ('ACCESS_MODE', 'VISITOR',      'Visitor',      1),
  ('ACCESS_MODE', 'RETURNING',    'Returning',    2),
  ('ACCESS_MODE', 'AUTHENTICATED','Authenticated',3),
  ('SIGNAL_STATUS', 'PENDING',     'Pending',     1),
  ('SIGNAL_STATUS', 'DISPATCHED',  'Dispatched',  2),
  ('SIGNAL_STATUS', 'RECEIVED',    'Received',    3),
  ('SIGNAL_STATUS', 'ACCEPTED',    'Accepted',    4),
  ('SIGNAL_STATUS', 'REJECTED',    'Rejected',    5),
  ('SIGNAL_STATUS', 'DEAD_LETTER', 'Dead Letter', 6);

-- The 47 constitutional counties (Kisumu first, per Article 38.1 / VTDR).
-- Standard IEBC/constitutional numbering 01-47.
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

-- Fixed-date 2026 Kenyan public holidays only. Movable holidays (Good
-- Friday, Easter Monday, Eid ul-Fitr, Eid ul-Adha) are deliberately NOT
-- seeded here -- their dates depend on lunar sighting / are gazetted
-- separately, and guessing them would put an unverified date into
-- constitutional reference data. Governance adds those once gazetted.
INSERT INTO trustride.calendar_reference (calendar_date, day_type, description) VALUES
  ('2026-01-01', 'PUBLIC_HOLIDAY', 'New Year''s Day'),
  ('2026-05-01', 'PUBLIC_HOLIDAY', 'Labour Day'),
  ('2026-06-01', 'PUBLIC_HOLIDAY', 'Madaraka Day'),
  ('2026-10-20', 'PUBLIC_HOLIDAY', 'Mashujaa Day'),
  ('2026-12-12', 'PUBLIC_HOLIDAY', 'Jamhuri Day'),
  ('2026-12-25', 'PUBLIC_HOLIDAY', 'Christmas Day'),
  ('2026-12-26', 'PUBLIC_HOLIDAY', 'Boxing Day');

-- ============================================================================
-- END OF SECTION -- Shared Runtime Substrate (24 tables, 2 functions, 2 views)
-- Next section: TrustRide Core (platform_registry, engine_registry,
-- shell_registry, engine_installation, health/incident/metric).
-- ============================================================================
