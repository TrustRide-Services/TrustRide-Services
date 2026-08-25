-- ============================================================================
-- TRUSTRIDE SERVICES PLATFORM
-- ============================================================================
-- PLATFORM ID          : b302bb5d-7d20-41e9-a074-a18d8ebd2aa5
-- PLATFORM CODE        : TRS026
-- PLATFORM NAME        : TRUSTRIDE_SERVICES
-- SCHEMA               : trustride
-- ENGINE NO            : ENGINE_004
-- ENGINE ID            : c1a2b3c4-0004-4eng-8004-004business04
-- ENGINE CODE          : TRS026_ENG004_BUS
-- ENGINE DOMAIN        : TrustRide Business Domain
-- ENGINE CLASS         : Business Engine
-- ENGINE TYPE          : Commercial & Operational
-- ENGINE NAME          : TrustRide Business
-- ENGINE DESCRIPTION   : The platform's authoritative record of every
--                        commercial transaction and every business-layer
--                        relationship with the five User Type Domains.
-- ENGINE FUNCTION      : What was requested, by whom, under what terms, and
--                        is it settled?
-- PLATFORM VERSION     : 1.0.0
-- ENGINE VERSION       : 1.1.0
-- MIGRATION DATA
-- FILE NAME            : 20260823000008_engine004_business.sql
-- INSTALLATION ORDER   : 004
-- STATUS               : COMPLETE -- one single migration file, 15 tables,
--                        23 functions, hardened and aligned 2026-08-24
--                        against every engine built or elevated since this
--                        file was first written (Engine 5's 17-table
--                        rebuild, the Resources MNY-15 elevation, the
--                        Engines 1-5 reconciliation, and Engine 6
--                        Integration) -- never previously pushed live.
-- CREATED AT           : 2026-08-23 (hardened 2026-08-24)
-- CREATED BY           : Onyango Albert Chitayi (Founder) + Engineering
-- ============================================================================
--
-- HARDENING PASS, 2026-08-24 (Founder directive: "no new implementation,
-- just hardening, aligning, giving deeper meaning so that the platform
-- actually comes live after every engine installation... that engine must
-- 100% and fully do its work end to end on installation"). This file was
-- built 2026-08-23 against an earlier state of the platform and never
-- pushed live; the hardening pass below closes every real gap that state
-- change exposed, without adding any scope beyond what Article 19/20.2 and
-- this file's own prior design already called for:
--   9. THE CORE BUG, FOUND AND FIXED: fn_business_resource_reserved_accept
--      was a no-op (touched only updated_at), silently stalling every real
--      order at VALIDATED forever -- no business_job, no quote, no
--      settlement ever followed, because nothing ever converted a
--      reservation into a firm assignment. Fixed by emitting a new signal,
--      RESOURCE_ASSIGNMENT_CONFIRMED (Business -> Resources, auto-
--      confirmed, matching the same precedent already established by
--      Resources' own auto-pick in fn_resource_assignment_requested_accept
--      -- named as new because no adopted source document names this exact
--      transition), carrying real trip context read from the order's own
--      business_order_line.scope_detail (origin_zone_code,
--      destination_zone_code, distance_km, duration_min) -- Article 16's
--      "no scope, no Order" extended to its logical conclusion: no trip
--      context, no dispatch. A companion migration extends Engine 2 (the
--      established, safe pattern for one already-live engine's file adding
--      a new accept-handler for another engine's new signal) with fn_
--      resource_assignment_confirmed_accept, which receives this signal and
--      finally calls fn_resource_assign -- the real, complete Article 20.2
--      sequence, working end to end for the first time.
--   10. business_event_inbox gains emitted_at (nullable) -- Engine 6's own
--      hardening pass made the platform-wide dispatch cycle always supply
--      this column; without it, Business would fail on its very first real
--      received signal exactly the way Foundation once did.
--   11. fn_business_payment_settled_accept corrected: Integration's real
--      payload carries quote_id, never order_id (Integration has no
--      business knowing Business's internal order_id, Article 33) --
--      Business now resolves its own order_id from the quote_id it already
--      stored, rather than expecting a field Integration never sends.
--   12. Two new accept-handlers, fn_business_payment_failed_accept and
--      fn_business_payment_stk_failed_accept, for two real signals Engine 6
--      already emits that previously had no handler in Business at all --
--      a failed payment attempt marks the settlement FAILED without
--      touching the Order's own operational status (Money is not Payment;
--      the service already rendered is not undone by a payment retry).
--   13. order_line_id threaded through ASSIGNMENT_REQUESTED and the new
--      RESOURCE_ASSIGNMENT_CONFIRMED signal, matching the Resources MNY-15
--      elevation's own Order-Line-bound design.
--   14. routing_rule now registers RESOURCE_ASSIGNMENT_CONFIRMED (->
--      Resources) and PAYMENT_SETTLED/PAYMENT_FAILED/PAYMENT_STK_FAILED
--      (Integration -> Business, unregistered before since Engine 6 did not
--      yet exist when this file was first written).
--   15. fn_business_service_resolved_accept's ASSIGNMENT_REQUESTED payload
--      never carried a pickup_location, despite Resources' own fn_resource_
--      assignment_requested_accept having always expected one -- only zone
--      codes exist on the order line at that point, not a raw coordinate.
--      Fixed, not deferred: the origin zone's own centroid (cost_
--      operational_zones.boundary, real PostGIS geometry) is the correct,
--      non-invented resolution -- every engine's service role already has
--      cross-schema read access, so no new grant was needed. A zone_code
--      naming a row that does not exist is now a real rejection
--      (ORIGIN_ZONE_NOT_FOUND), never a silent NULL passed through to
--      Resources' discovery function.
--   16. fn_business_review_submit's own guard blocked its second,
--      documented-as-legitimate bi-directional call (the first call flips
--      the order to REVIEWED, which the guard then excluded) -- fixed by
--      accepting REVIEWED alongside COMPLETED/SETTLED. A real unique
--      constraint (uq_business_review_direction) now also blocks a genuine
--      duplicate in the same direction, which nothing previously prevented.
--
-- Source: TRS026-ENG004-BUS-001 v1.0.1 (ADOPTED 2026-08-16), Sections 2-4.
-- Founder ruling 2026-08-23 (Kisumu build plan, item 5): "MUST COMPLETELY
-- DEFINE AND IMPLEMENT END TO END: 1. SERVICE FLOW 2. ORDER FLOW... every
-- service has 2 roots -- a direct Service Order, or a Resource Partnership
-- Request (immediate/scheduled for normal services; the partnership root
-- always responds within 72 hours, its scope naming what resource is
-- offered and what the contributor expects)... implement all the tables
-- for our business environment -- Customers, Partners, Governors,
-- Intermediaries, Operators -- everything that practically falls under
-- this domain. COMPLETE FULL END TO END."
--
-- Corrections and Founder-directed additions applied in this compilation:
--   1. Schema-qualified every table/type/function as `trustride.*`, and
--      trs026_eng004_bus_service created immediately after Phase 1 Schema
--      -- same reasoning as every prior engine file.
--   2. REAL BUG FOUND AND FIXED (2026-08-23, caught while wiring RLS,
--      before any execution, affecting all seven requester/participant-
--      read policies in the source document): every one uses
--      current_setting('app.current_user_id', true)::uuid -- a session
--      setting nothing anywhere in this platform ever sets. Every other
--      engine's own working RLS uses Supabase's real auth.uid(). As
--      written, every "self can read their own row" policy in the source
--      document would silently return zero rows to every real
--      authenticated user, forever -- not a typo, a platform-wide defect
--      repeated seven times. Fixed by using auth.uid() throughout,
--      matching Foundation's own established, tested mechanism.
--   3. Founder-directed: business_order gains order_root_type
--      (SERVICE_ORDER | RESOURCE_PARTNERSHIP_REQUEST) -- the two-roots
--      model. A Service Order proceeds through the full Article 19 seven-
--      stage lifecycle exactly as the source document specifies,
--      unchanged. A Resource Partnership Request reuses the same Order/
--      Order Line primitive (Article 16's "no scope, no Order" law
--      applies universally, not just to service dispatch) but never
--      requests catalogue resolution or resource assignment -- there is
--      no resource TO assign; the whole point is someone offering one.
--      New table business_partnership_response (Founder-directed,
--      Correction 4) governs its own distinct, non-dispatch lifecycle:
--      SUBMITTED -> UNDER_REVIEW -> ACCEPTED/DECLINED, with a real 72-hour
--      response_due_at, exactly as directed ("response is after 72 hrs").
--      Order Line scope_detail carries {resource_type_offered,
--      expectation} -- "write the type of the resource you wish to
--      contribute and what you expect" -- using the existing JSONB
--      column, no new column needed for that part.
--   4. New table business_partnership_response (see Correction 3).
--   5. Founder-directed: business_intermediary_engagement and
--      business_governor_engagement -- the source document gives
--      Customers, Partners, and Operators each a dedicated business-layer
--      extension table (§2.2-2.4) but folds Intermediary and Governor
--      into a single generic terms_summary text field on business_actor_
--      registration. The Founder's own instruction names all five domains
--      as needing full implementation; these two new tables give
--      Intermediaries and Governors the same first-class treatment,
--      matching business_operator_engagement's shape (engagement terms,
--      status, a reference-by-value into the relevant governed registry)
--      rather than an unstructured text field.
--   6. Explicit per-function GRANTs, never a schema-wide blanket, and
--      lawful state-changing functions append to Foundation's shared audit
--      hash chain via fn_audit_log_append, granted explicitly -- same
--      reasoning as every prior engine file.
--   7. The source document's own Annex already self-corrected one
--      documentation defect (RLS Law row claiming eleven tables against
--      twelve declared) -- re-verified intact, no further action needed
--      beyond what v1.0.1 already fixed.
--   8. fn_business_order_place is the sole entry point that ever writes
--      business_order -- it inserts the Order and every Order Line in one
--      transaction, satisfying the deferred trg_business_order_scope_
--      exists trigger (Article 16) before commit, exactly as the source
--      document's own comment on business_order requires.
--
-- ============================================================================

-- ============================================================================
-- PHASE 0 -- EXTENSIONS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

-- ============================================================================
-- PHASE 1 -- SCHEMA + EARLY ROLE CREATION
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng004_bus_service') THEN
    CREATE ROLE trs026_eng004_bus_service NOLOGIN;
  END IF;
END
$$;

-- ============================================================================
-- PHASE 2 -- ENUMS
-- ============================================================================
CREATE TYPE trustride.business_user_type_domain_enum AS ENUM ('CUSTOMER', 'PARTNER', 'OPERATOR', 'INTERMEDIARY', 'GOVERNOR');
CREATE TYPE trustride.business_partner_category_enum AS ENUM ('FINANCIER', 'FLEET_CONTRIBUTOR', 'AMBASSADOR', 'VENDOR', 'STRATEGIC_COLLABORATOR');
-- [Trace: TBOC-v2.0.0 | Article 19 | The Seven-Stage Universal Order Lifecycle, verbatim]
CREATE TYPE trustride.business_order_stage_enum AS ENUM (
  'ORDER_PLACEMENT_SCOPE', 'ASSIGNMENT_VALIDATION_JOB_CREATION', 'DISPATCH',
  'EXECUTION_COMPLETION', 'PAYMENT_SETTLEMENT', 'REVIEW_RATE_SUPPORT', 'RESOURCE_AVAILABILITY'
);
CREATE TYPE trustride.business_order_status_enum AS ENUM (
  'PLACED', 'VALIDATED', 'JOB_CREATED', 'DECLINED', 'DISPATCHED',
  'EXECUTING', 'COMPLETED', 'SETTLED', 'REVIEWED', 'CLOSED', 'CANCELLED'
);
CREATE TYPE trustride.business_job_type_enum AS ENUM ('IMMEDIATE', 'SCHEDULED');
-- [Trace: TBOC-v2.0.0 | Article 20.3 | Dispatch sub-sequence, verbatim]
CREATE TYPE trustride.business_job_status_enum AS ENUM ('CREATED', 'DISPATCHED', 'EN_ROUTE', 'ARRIVED', 'EXECUTING', 'COMPLETED', 'VERIFIED', 'CANCELLED');
CREATE TYPE trustride.business_payment_rail_enum AS ENUM ('MPESA_C2B_STK', 'FLUTTERWAVE');
CREATE TYPE trustride.business_payment_status_enum AS ENUM ('INITIATED', 'AUTHORIZED', 'SETTLED', 'LEDGER_POSTED', 'RECEIPT_GENERATED', 'FAILED');
-- Correction 3: the two-roots model, Founder-directed.
CREATE TYPE trustride.business_order_root_enum AS ENUM ('SERVICE_ORDER', 'RESOURCE_PARTNERSHIP_REQUEST');
-- Correction 4: the partnership response lifecycle, Founder-directed.
CREATE TYPE trustride.business_partnership_response_status_enum AS ENUM ('SUBMITTED', 'UNDER_REVIEW', 'ACCEPTED', 'DECLINED');

-- ============================================================================
-- PHASE 3/4/5 -- TABLES
-- ============================================================================

-- --- 2.1 business_actor_registration ---
CREATE TABLE trustride.business_actor_registration (
  actor_registration_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID NOT NULL,
  user_type_domain      trustride.business_user_type_domain_enum NOT NULL,
  registration_status   TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (registration_status IN ('PENDING', 'ACTIVE', 'SUSPENDED', 'TERMINATED')),
  terms_summary         TEXT,
  registered_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_business_actor_user_domain ON trustride.business_actor_registration (user_id, user_type_domain);
COMMENT ON TABLE trustride.business_actor_registration IS
  '[Trace: TBOC-v2.0.0 | Article 12.9] Each domain is a User Type of a User -- none creates a second identity root; a single User may hold multiple domain registrations.';

-- --- 2.2 business_customer_profile ---
CREATE TABLE trustride.business_customer_profile (
  customer_profile_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_registration_id UUID NOT NULL UNIQUE REFERENCES trustride.business_actor_registration (actor_registration_id),
  order_count           INTEGER NOT NULL DEFAULT 0 CHECK (order_count >= 0),
  lifetime_value_kes    NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (lifetime_value_kes >= 0),
  preferred_payment_rail trustride.business_payment_rail_enum,
  loyalty_tier          TEXT NOT NULL DEFAULT 'STANDARD',
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.business_customer_profile IS
  '[Trace: TBOC-v2.0.0 | Article 12.1] lifetime_value_kes is a maintained rollup, never the ledger of record.';

-- --- 2.3 business_partner_agreement ---
CREATE TABLE trustride.business_partner_agreement (
  partner_agreement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_registration_id UUID NOT NULL REFERENCES trustride.business_actor_registration (actor_registration_id),
  partner_category      trustride.business_partner_category_enum NOT NULL,
  agreement_type        TEXT NOT NULL,
  agreement_terms       JSONB NOT NULL DEFAULT '{}',
  start_date            DATE NOT NULL,
  end_date              DATE,
  status                TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'EXPIRED', 'TERMINATED')),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_business_partner_agreement_dates CHECK (end_date IS NULL OR end_date > start_date)
);
COMMENT ON TABLE trustride.business_partner_agreement IS
  '[Trace: TBOC-v2.0.0 | Article 12.2] A partner may also become a customer in a different relationship; the domain is determined per engagement, never fused.';

-- --- 2.4 business_operator_engagement ---
CREATE TABLE trustride.business_operator_engagement (
  operator_engagement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_registration_id  UUID NOT NULL UNIQUE REFERENCES trustride.business_actor_registration (actor_registration_id),
  employment_type        TEXT NOT NULL DEFAULT 'EMPLOYEE' CHECK (employment_type IN ('EMPLOYEE', 'TECHNICAL_OPERATOR')),
  compensation_structure_ref UUID,
  engagement_start       DATE NOT NULL,
  engagement_status      TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (engagement_status IN ('ACTIVE', 'SUSPENDED', 'TERMINATED')),
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.business_operator_engagement IS
  '[Trace: TBOC-v2.0.0 | Article 12.3] Technical Operators are registered Things under Engine 2 custody; this row records only the employment_type distinction.';

-- --- Correction 5: business_intermediary_engagement (Founder-directed) ---
CREATE TABLE trustride.business_intermediary_engagement (
  intermediary_engagement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_registration_id      UUID NOT NULL UNIQUE REFERENCES trustride.business_actor_registration (actor_registration_id),
  intermediary_type          TEXT NOT NULL CHECK (intermediary_type IN ('BROKER', 'AGENT', 'REFERRAL_PARTNER')),
  commission_structure_ref   UUID,
  engagement_start           DATE NOT NULL,
  engagement_status          TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (engagement_status IN ('ACTIVE', 'SUSPENDED', 'TERMINATED')),
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.business_intermediary_engagement IS
  'Correction 5 (Founder-directed, not in the source document): gives the Intermediary domain the same first-class business-layer engagement record as Customer/Partner/Operator, rather than a generic text field.';

-- --- Correction 5: business_governor_engagement (Founder-directed) ---
CREATE TABLE trustride.business_governor_engagement (
  governor_engagement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_registration_id  UUID NOT NULL UNIQUE REFERENCES trustride.business_actor_registration (actor_registration_id),
  governance_role_ref    UUID,
  oversight_scope        TEXT,
  engagement_start       DATE NOT NULL,
  engagement_status      TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (engagement_status IN ('ACTIVE', 'SUSPENDED', 'TERMINATED')),
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.business_governor_engagement IS
  'Correction 5 (Founder-directed, not in the source document): governance_role_ref is a by-value reference into Foundation''s role_definition/role_assignment -- gives the Governor domain the same first-class engagement record as every other domain.';

-- --- 2.5 business_order (Correction 3: + order_root_type) ---
CREATE TABLE trustride.business_order (
  order_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_code        TEXT NOT NULL UNIQUE,
  order_root_type   trustride.business_order_root_enum NOT NULL DEFAULT 'SERVICE_ORDER',
  requester_user_id UUID NOT NULL,
  user_type_domain  trustride.business_user_type_domain_enum NOT NULL,
  service_id        UUID NOT NULL,
  service_code      TEXT NOT NULL,
  macro_domain      TEXT NOT NULL,
  order_stage       trustride.business_order_stage_enum NOT NULL DEFAULT 'ORDER_PLACEMENT_SCOPE',
  status            trustride.business_order_status_enum NOT NULL DEFAULT 'PLACED',
  quote_id          UUID,
  placed_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at         TIMESTAMPTZ,
  correlation_id    UUID NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.business_order IS
  '[Trace: TBOC-v2.0.0 | Article 16] An Order without scope is constitutionally void, enforced by the deferred trg_business_order_scope_exists trigger below. order_root_type (Correction 3) distinguishes a direct Service Order from a Resource Partnership Request -- both still require scope (Article 16 is universal), but only a Service Order proceeds through catalogue resolution and resource assignment.';

CREATE OR REPLACE FUNCTION trustride.business_order_scope_exists()
RETURNS trigger
LANGUAGE plpgsql SET search_path = trustride, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM trustride.business_order_line WHERE order_id = NEW.order_id) THEN
    RAISE EXCEPTION 'business_order %: an Order without scope is constitutionally void (Article 16); at least one business_order_line row is required in the same transaction', NEW.order_id;
  END IF;
  RETURN NEW;
END;
$$;
CREATE CONSTRAINT TRIGGER trg_business_order_scope_exists
  AFTER INSERT ON trustride.business_order
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trustride.business_order_scope_exists();

-- --- 2.6 business_order_line ---
CREATE TABLE trustride.business_order_line (
  order_line_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id         UUID NOT NULL REFERENCES trustride.business_order (order_id),
  line_sequence    SMALLINT NOT NULL,
  line_description TEXT NOT NULL,
  quantity         NUMERIC(10,2) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  scope_detail     JSONB NOT NULL DEFAULT '{}',
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_business_order_line_sequence ON trustride.business_order_line (order_id, line_sequence);
COMMENT ON TABLE trustride.business_order_line IS
  '[Trace: TBOC-v2.0.0 | Article 16] For a RESOURCE_PARTNERSHIP_REQUEST, scope_detail carries {resource_type_offered, expectation} -- Founder-directed, Correction 3.';

-- --- Correction 4: business_partnership_response ---
CREATE TABLE trustride.business_partnership_response (
  partnership_response_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id                UUID NOT NULL UNIQUE REFERENCES trustride.business_order (order_id),
  response_status         trustride.business_partnership_response_status_enum NOT NULL DEFAULT 'SUBMITTED',
  response_due_at         TIMESTAMPTZ NOT NULL,
  responded_at            TIMESTAMPTZ,
  responded_by            UUID,
  response_notes          TEXT,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.business_partnership_response IS
  'Correction 4 (Founder-directed, not in the source document): the Resource Partnership Request''s own lifecycle, distinct from Article 19''s dispatch stages -- response_due_at is always 72 hours from submission, exactly as directed.';

-- --- 2.7 business_job ---
CREATE TABLE trustride.business_job (
  job_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id               UUID NOT NULL REFERENCES trustride.business_order (order_id),
  job_type               trustride.business_job_type_enum NOT NULL,
  scheduled_window_start TIMESTAMPTZ,
  scheduled_window_end   TIMESTAMPTZ,
  workforce_unit_id      UUID,
  status                 trustride.business_job_status_enum NOT NULL DEFAULT 'CREATED',
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  dispatched_at          TIMESTAMPTZ,
  completed_at           TIMESTAMPTZ,
  verified_at            TIMESTAMPTZ,
  CONSTRAINT chk_business_job_schedule
    CHECK (job_type = 'IMMEDIATE' OR (scheduled_window_start IS NOT NULL AND scheduled_window_end IS NOT NULL AND scheduled_window_end > scheduled_window_start))
);
COMMENT ON TABLE trustride.business_job IS
  '[Trace: TBOC-v2.0.0 | Article 22] Immediate Jobs dispatch at once upon acceptance; Scheduled Jobs bind a future time window and are reconfirmed before dispatch. No Job exists without acceptance.';

-- --- 2.8 business_tracking_session ---
CREATE TABLE trustride.business_tracking_session (
  tracking_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id              UUID NOT NULL UNIQUE REFERENCES trustride.business_job (job_id),
  resource_type       TEXT NOT NULL,
  resource_id_display TEXT NOT NULL,
  eta                 TIMESTAMPTZ,
  tracking_status     TEXT NOT NULL DEFAULT 'EN_ROUTE',
  exact_location      GEOMETRY(POINT, 4326),
  started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at            TIMESTAMPTZ,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.business_tracking_session IS
  '[Trace: TBOC-v2.0.0 | Article 21] Active-session only: begins when the Job starts, ends when the Job completes. All five constitutionally mandatory data elements are present as columns.';

-- --- 2.9 business_settlement ---
CREATE TABLE trustride.business_settlement (
  settlement_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id                UUID NOT NULL UNIQUE REFERENCES trustride.business_order (order_id),
  computed_total_fare_kes NUMERIC(18,2) NOT NULL CHECK (computed_total_fare_kes >= 0),
  currency                CHAR(3) NOT NULL DEFAULT 'KES',
  payment_rail            trustride.business_payment_rail_enum NOT NULL,
  payment_status          trustride.business_payment_status_enum NOT NULL DEFAULT 'INITIATED',
  initiated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  authorized_at           TIMESTAMPTZ,
  settled_at              TIMESTAMPTZ,
  ledger_posted_at        TIMESTAMPTZ,
  receipt_code            TEXT UNIQUE,
  receipt_generated_at    TIMESTAMPTZ,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_business_settlement_receipt
    CHECK (payment_status <> 'RECEIPT_GENERATED' OR (receipt_code IS NOT NULL AND ledger_posted_at IS NOT NULL))
);
COMMENT ON TABLE trustride.business_settlement IS
  '[Trace: TBOC-v2.0.0 | Article 43] Settlement is not complete until the ledger is posted and the receipt is generated.';

CREATE OR REPLACE FUNCTION trustride.business_settlement_block_illegal_mutation()
RETURNS trigger
LANGUAGE plpgsql SET search_path = trustride, pg_temp
AS $$
BEGIN
  IF OLD.payment_status = 'RECEIPT_GENERATED'
     AND (NEW.computed_total_fare_kes IS DISTINCT FROM OLD.computed_total_fare_kes
          OR NEW.receipt_code IS DISTINCT FROM OLD.receipt_code) THEN
    RAISE EXCEPTION 'business_settlement: fare and receipt are immutable once RECEIPT_GENERATED; correction requires a governed reversal (Article 42.4)';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_business_settlement_block_illegal_mutation
  BEFORE UPDATE ON trustride.business_settlement
  FOR EACH ROW EXECUTE FUNCTION trustride.business_settlement_block_illegal_mutation();

-- --- 2.10 business_review ---
CREATE TABLE trustride.business_review (
  review_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id         UUID NOT NULL REFERENCES trustride.business_order (order_id),
  reviewer_user_id UUID NOT NULL,
  reviewee_user_id UUID NOT NULL,
  rating           SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment          TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.business_review IS
  '[Trace: TBOC-v2.0.0 | Article 19 Stage 6, Article 51] Bi-directional -- the requester rates the resource and the resource rates the requester, each a separate row against the same Order.';

-- --- 2.11 Engine Event Substrate ---
CREATE TABLE trustride.business_event_outbox (
  signal_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id   UUID NOT NULL,
  causation_id     UUID,
  emitting_engine  TEXT NOT NULL DEFAULT 'TRS026_ENG004_BUS',
  receiving_engine TEXT NOT NULL,
  signal_type      TEXT NOT NULL,
  payload_in       JSONB NOT NULL,
  signal_status    TEXT NOT NULL DEFAULT 'PENDING'
                      CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason TEXT,
  idempotency_key  TEXT NOT NULL UNIQUE,
  attempt_count    INTEGER NOT NULL DEFAULT 0,
  emitted_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_business_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);

CREATE TABLE trustride.business_event_inbox (
  signal_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id   UUID NOT NULL,
  causation_id     UUID,
  emitting_engine  TEXT NOT NULL,
  receiving_engine TEXT NOT NULL DEFAULT 'TRS026_ENG004_BUS',
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
  CONSTRAINT chk_business_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);

-- ============================================================================
-- PHASE 6 -- FUNCTIONS
-- ============================================================================

-- --- Actor / domain registration ---
CREATE OR REPLACE FUNCTION trustride.fn_business_actor_register(p_user_id UUID, p_user_type_domain trustride.business_user_type_domain_enum, p_terms_summary TEXT DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_actor_registration_id UUID;
BEGIN
  INSERT INTO trustride.business_actor_registration (user_id, user_type_domain, terms_summary)
  VALUES (p_user_id, p_user_type_domain, p_terms_summary)
  ON CONFLICT (user_id, user_type_domain) DO UPDATE SET registration_status = 'ACTIVE'
  RETURNING actor_registration_id INTO v_actor_registration_id;

  PERFORM trustride.fn_audit_log_append('business_actor_registration', v_actor_registration_id, 'ACTOR_REGISTERED', p_user_id,
    'USER', NULL, NULL, NULL, jsonb_build_object('user_type_domain', p_user_type_domain));

  RETURN v_actor_registration_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_actor_register(UUID, trustride.business_user_type_domain_enum, TEXT) IS
  '[Trace: Article 12.9] A single User may hold multiple domain registrations -- idempotent per (user_id, domain).';

CREATE OR REPLACE FUNCTION trustride.fn_business_customer_profile_ensure(p_actor_registration_id UUID)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO trustride.business_customer_profile (actor_registration_id)
  VALUES (p_actor_registration_id)
  ON CONFLICT (actor_registration_id) DO UPDATE SET updated_at = now()
  RETURNING customer_profile_id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_partner_agreement_open(
  p_actor_registration_id UUID, p_partner_category trustride.business_partner_category_enum, p_agreement_type TEXT, p_start_date DATE, p_agreement_terms JSONB DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO trustride.business_partner_agreement (actor_registration_id, partner_category, agreement_type, agreement_terms, start_date)
  VALUES (p_actor_registration_id, p_partner_category, p_agreement_type, p_agreement_terms, p_start_date)
  RETURNING partner_agreement_id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_operator_engagement_open(p_actor_registration_id UUID, p_employment_type TEXT, p_engagement_start DATE, p_compensation_structure_ref UUID DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO trustride.business_operator_engagement (actor_registration_id, employment_type, compensation_structure_ref, engagement_start)
  VALUES (p_actor_registration_id, p_employment_type, p_compensation_structure_ref, p_engagement_start)
  RETURNING operator_engagement_id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_intermediary_engagement_open(p_actor_registration_id UUID, p_intermediary_type TEXT, p_engagement_start DATE, p_commission_structure_ref UUID DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO trustride.business_intermediary_engagement (actor_registration_id, intermediary_type, commission_structure_ref, engagement_start)
  VALUES (p_actor_registration_id, p_intermediary_type, p_commission_structure_ref, p_engagement_start)
  RETURNING intermediary_engagement_id INTO v_id;
  RETURN v_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_intermediary_engagement_open(UUID, TEXT, DATE, UUID) IS
  'Correction 5 (Founder-directed): registers an Intermediary''s business-layer engagement terms.';

CREATE OR REPLACE FUNCTION trustride.fn_business_governor_engagement_open(p_actor_registration_id UUID, p_engagement_start DATE, p_governance_role_ref UUID DEFAULT NULL, p_oversight_scope TEXT DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO trustride.business_governor_engagement (actor_registration_id, governance_role_ref, oversight_scope, engagement_start)
  VALUES (p_actor_registration_id, p_governance_role_ref, p_oversight_scope, p_engagement_start)
  RETURNING governor_engagement_id INTO v_id;
  RETURN v_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_governor_engagement_open(UUID, DATE, UUID, TEXT) IS
  'Correction 5 (Founder-directed): registers a Governor''s business-layer engagement terms.';

-- --- Order placement: the sole entry point that ever writes business_order ---
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
    -- Correction 3: a Resource Partnership Request never requests
    -- catalogue resolution or resource assignment -- it opens its own
    -- 72-hour response lifecycle instead (Correction 4).
    INSERT INTO trustride.business_partnership_response (order_id, response_due_at)
    VALUES (v_order_id, now() + interval '72 hours');
  END IF;

  INSERT INTO trustride.business_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG011_PRESENT', 'ORDER_PLACED',
    jsonb_build_object('order_id', v_order_id, 'order_code', v_order_code, 'service_code', p_service_code, 'placed_at', now()),
    'ORDER_PLACED:' || v_order_id::text);

  PERFORM trustride.fn_audit_log_append('business_order', v_order_id, 'ORDER_PLACED', p_requester_user_id,
    'USER', p_user_type_domain::text, NULL, NULL, jsonb_build_object('order_code', v_order_code, 'order_root_type', p_order_root_type));

  RETURN v_order_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_order_place(UUID, trustride.business_user_type_domain_enum, TEXT, TEXT, JSONB, trustride.business_order_root_enum, TEXT, UUID) IS
  '[Trace: Article 16, 19 Stage 1] Writes the Order and every Order Line in one transaction, satisfying the deferred scope-exists trigger before commit. A SERVICE_ORDER requests catalogue resolution; a RESOURCE_PARTNERSHIP_REQUEST opens its own 72-hour response lifecycle instead (Correction 3).';

CREATE OR REPLACE FUNCTION trustride.fn_business_order_cancel(p_order_id UUID, p_requester_user_id UUID, p_reason TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
BEGIN
  -- Ownership check first, deliberately, before any state check -- a
  -- caller who does not own this Order gets the same rejection regardless
  -- of the Order's actual state, never leaking state to a non-owner.
  UPDATE trustride.business_order SET status = 'CANCELLED', closed_at = now()
  WHERE order_id = p_order_id AND requester_user_id = p_requester_user_id
    AND status NOT IN ('SETTLED', 'REVIEWED', 'CLOSED', 'CANCELLED');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_business_order_cancel: order % cannot be cancelled by % (not the owner, already closed, or does not exist)', p_order_id, p_requester_user_id;
  END IF;

  PERFORM trustride.fn_audit_log_append('business_order', p_order_id, 'ORDER_CANCELLED', p_requester_user_id,
    'USER', NULL, NULL, NULL, jsonb_build_object('reason', p_reason));
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_order_cancel(UUID, UUID, TEXT) IS
  'Ownership is checked before any state check -- a non-owner never learns whether the order exists or what state it is in.';

-- --- Resource Partnership decision (Correction 4) ---
CREATE OR REPLACE FUNCTION trustride.fn_business_partnership_response_decide(p_order_id UUID, p_decision trustride.business_partnership_response_status_enum, p_decided_by UUID, p_notes TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
BEGIN
  IF p_decision NOT IN ('ACCEPTED', 'DECLINED') THEN
    RAISE EXCEPTION 'fn_business_partnership_response_decide: decision must be ACCEPTED or DECLINED, got %', p_decision;
  END IF;

  UPDATE trustride.business_partnership_response
  SET response_status = p_decision, responded_at = now(), responded_by = p_decided_by, response_notes = p_notes
  WHERE order_id = p_order_id AND response_status IN ('SUBMITTED', 'UNDER_REVIEW');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_business_partnership_response_decide: order % has no open partnership response to decide', p_order_id;
  END IF;

  UPDATE trustride.business_order SET status = CASE WHEN p_decision = 'ACCEPTED' THEN 'CLOSED' ELSE 'DECLINED' END::trustride.business_order_status_enum, closed_at = now()
  WHERE order_id = p_order_id;

  PERFORM trustride.fn_audit_log_append('business_partnership_response', p_order_id, 'PARTNERSHIP_RESPONSE_DECIDED', p_decided_by,
    'USER', NULL, NULL, NULL, jsonb_build_object('decision', p_decision, 'notes', p_notes));

  -- Provisioning an ACCEPTED contribution into Engine 2's own registers
  -- (Article 37 partner-contributed resources) needs a named, adopted
  -- signal_type nothing in the current corpus defines yet -- deliberately
  -- not fabricated here (same discipline as Engine 5's Correction 5); the
  -- decision is recorded as real, governed fact regardless.
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_partnership_response_decide(UUID, trustride.business_partnership_response_status_enum, UUID, TEXT) IS
  'Correction 4: governs ACCEPT/DECLINE of a Resource Partnership Request. Wiring an accepted contribution into Engine 2 is a named next step, not fabricated here -- no adopted signal_type exists for it yet.';

CREATE OR REPLACE FUNCTION trustride.fn_business_partnership_response_timeout_sweep()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_swept INTEGER;
BEGIN
  UPDATE trustride.business_partnership_response SET response_status = 'DECLINED', responded_at = now(), response_notes = 'Auto-declined: 72-hour response window elapsed without a decision'
  WHERE response_status IN ('SUBMITTED', 'UNDER_REVIEW') AND response_due_at < now();
  GET DIAGNOSTICS v_swept = ROW_COUNT;

  UPDATE trustride.business_order o SET status = 'DECLINED', closed_at = now()
  FROM trustride.business_partnership_response r
  WHERE r.order_id = o.order_id AND r.response_status = 'DECLINED' AND r.responded_at >= now() - interval '1 minute' AND o.status NOT IN ('DECLINED','CANCELLED','CLOSED');

  RETURN v_swept;
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_partnership_response_timeout_sweep() IS
  'Correction 4: "response is after 72 hrs" is a real deadline, not a suggestion -- a request never answered within the window is auto-declined, never left open indefinitely.';

-- --- Job progress (Article 20.3 Dispatch sub-sequence) ---
CREATE OR REPLACE FUNCTION trustride.fn_business_job_progress_advance(p_job_id UUID, p_operator_user_id UUID, p_correlation_id UUID DEFAULT gen_random_uuid())
RETURNS trustride.business_job_status_enum
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_job RECORD;
  v_next trustride.business_job_status_enum;
  v_sequence trustride.business_job_status_enum[] := ARRAY['CREATED','DISPATCHED','EN_ROUTE','ARRIVED','EXECUTING','COMPLETED','VERIFIED']::trustride.business_job_status_enum[];
  v_cur_idx INTEGER;
BEGIN
  SELECT j.*, wu.operator_user_id INTO v_job
  FROM trustride.business_job j LEFT JOIN trustride.resource_workforce_unit wu ON wu.workforce_unit_id = j.workforce_unit_id
  WHERE j.job_id = p_job_id;

  IF v_job IS NULL THEN
    RAISE EXCEPTION 'fn_business_job_progress_advance: unknown job_id %', p_job_id;
  END IF;
  IF v_job.operator_user_id IS DISTINCT FROM p_operator_user_id THEN
    RAISE EXCEPTION 'fn_business_job_progress_advance: % is not the assigned operator for job %', p_operator_user_id, p_job_id;
  END IF;

  v_cur_idx := array_position(v_sequence, v_job.status);
  IF v_cur_idx IS NULL OR v_cur_idx >= array_length(v_sequence, 1) THEN
    RAISE EXCEPTION 'fn_business_job_progress_advance: job % cannot advance past %', p_job_id, v_job.status;
  END IF;
  v_next := v_sequence[v_cur_idx + 1];

  UPDATE trustride.business_job SET status = v_next,
    dispatched_at = CASE WHEN v_next = 'DISPATCHED' THEN now() ELSE dispatched_at END,
    completed_at = CASE WHEN v_next = 'COMPLETED' THEN now() ELSE completed_at END,
    verified_at = CASE WHEN v_next = 'VERIFIED' THEN now() ELSE verified_at END
  WHERE job_id = p_job_id;

  IF v_next = 'DISPATCHED' THEN
    UPDATE trustride.business_order SET status = 'DISPATCHED', order_stage = 'DISPATCH' WHERE order_id = v_job.order_id;
    PERFORM trustride.fn_business_tracking_session_open(p_job_id);
  ELSIF v_next IN ('EN_ROUTE', 'ARRIVED') THEN
    UPDATE trustride.business_tracking_session SET tracking_status = v_next::text, updated_at = now() WHERE job_id = p_job_id AND ended_at IS NULL;
  ELSIF v_next = 'EXECUTING' THEN
    UPDATE trustride.business_order SET status = 'EXECUTING', order_stage = 'EXECUTION_COMPLETION' WHERE order_id = v_job.order_id;
    -- Hardening (2026-08-24): mirrors the real, physically-happening
    -- service onto Cost's own quote lifecycle -- SERVICE_IN_PROGRESS had no
    -- caller anywhere until now.
    PERFORM trustride.fn_cost_quote_mark_in_progress(quote_id) FROM trustride.business_order WHERE order_id = v_job.order_id AND quote_id IS NOT NULL;
  ELSIF v_next = 'COMPLETED' THEN
    UPDATE trustride.business_order SET status = 'COMPLETED' WHERE order_id = v_job.order_id;
    UPDATE trustride.business_tracking_session SET ended_at = now(), tracking_status = 'COMPLETED' WHERE job_id = p_job_id AND ended_at IS NULL;
    -- Hardening (2026-08-24): the service is physically done -- this is
    -- what triggers PAYMENT_STK_TRIGGERED, never before the service is
    -- actually finished.
    PERFORM trustride.fn_cost_quote_finalize(quote_id, p_correlation_id) FROM trustride.business_order WHERE order_id = v_job.order_id AND quote_id IS NOT NULL;
  ELSIF v_next = 'VERIFIED' THEN
    INSERT INTO trustride.business_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (p_correlation_id, 'TRS026_ENG002_RESC', 'JOB_COMPLETED',
      jsonb_build_object('job_id', p_job_id, 'workforce_unit_id', v_job.workforce_unit_id, 'completed_at', now()),
      'JOB_COMPLETED:' || p_job_id::text);
  END IF;

  RETURN v_next;
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_job_progress_advance(UUID, UUID, UUID) IS
  '[Trace: Article 20.3] Walks the Dispatch sub-sequence one step at a time, ownership-checked via the real workforce_unit_id -> operator_user_id chain. VERIFIED emits JOB_COMPLETED to Resources (Article 19 Stage 7).';

-- --- Live tracking (Article 21) ---
CREATE OR REPLACE FUNCTION trustride.fn_business_tracking_session_open(p_job_id UUID)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_tracking_id UUID;
  v_capacity_class TEXT;
  v_operator_user_id UUID;
BEGIN
  SELECT cc.class_code::text, wu.operator_user_id INTO v_capacity_class, v_operator_user_id
  FROM trustride.business_job j
  JOIN trustride.resource_workforce_unit wu ON wu.workforce_unit_id = j.workforce_unit_id
  JOIN trustride.resource_capacity_class cc ON cc.capacity_class_id = wu.capacity_class_id
  WHERE j.job_id = p_job_id;

  INSERT INTO trustride.business_tracking_session (job_id, resource_type, resource_id_display, tracking_status)
  VALUES (p_job_id, coalesce(v_capacity_class, 'UNKNOWN'), 'Operator: ' || coalesce(v_operator_user_id::text, 'unassigned'), 'EN_ROUTE')
  ON CONFLICT (job_id) DO NOTHING
  RETURNING tracking_id INTO v_tracking_id;

  RETURN v_tracking_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_tracking_session_open(UUID) IS
  '[Trace: Article 21] Begins the live tracking contract the instant a Job dispatches.';

CREATE OR REPLACE FUNCTION trustride.fn_business_tracking_location_update(p_job_id UUID, p_lat NUMERIC, p_lon NUMERIC, p_eta TIMESTAMPTZ DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public, pg_temp
AS $$
BEGIN
  UPDATE trustride.business_tracking_session
  SET exact_location = ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326), eta = coalesce(p_eta, eta), updated_at = now()
  WHERE job_id = p_job_id AND ended_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_business_tracking_location_update: no active tracking session for job %', p_job_id;
  END IF;
END;
$$;

-- --- Inbound signal accept-handlers (§4.1) ---
CREATE OR REPLACE FUNCTION trustride.fn_business_service_resolved_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_correlation_id UUID;
  v_order_id UUID;
  v_order_line_id UUID;
  v_scope_detail JSONB;
  v_pickup_lat NUMERIC;
  v_pickup_lon NUMERIC;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_correlation_id FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_business_service_resolved_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  SELECT order_id INTO v_order_id FROM trustride.business_order WHERE correlation_id = v_correlation_id ORDER BY created_at DESC LIMIT 1;

  IF v_order_id IS NOT NULL AND coalesce((v_payload->>'coverage_confirmed')::boolean, false) THEN
    UPDATE trustride.business_order SET status = 'VALIDATED', order_stage = 'ASSIGNMENT_VALIDATION_JOB_CREATION' WHERE order_id = v_order_id;

    -- Hardening correction (2026-08-24): thread order_line_id through, per
    -- the Resources MNY-15 elevation's own Order-Line binding (Article 16's
    -- scope is per Order Line, not merely per Order) -- a Service Order's
    -- first line is the one carrying the dispatchable scope.
    SELECT order_line_id, scope_detail INTO v_order_line_id, v_scope_detail
    FROM trustride.business_order_line WHERE order_id = v_order_id ORDER BY line_sequence ASC LIMIT 1;

    -- Hardening correction (2026-08-24, Founder-directed -- fixed now, not
    -- deferred): fn_resource_assignment_requested_accept has always
    -- expected a pickup_location {latitude, longitude} in this payload, but
    -- nothing ever supplied one -- only zone codes exist on the order line
    -- at this point, and Resources' discovery function needs a real
    -- coordinate. Zones already carry a real geometry (cost_operational_
    -- zones.boundary); this platform's own service role already has
    -- cross-schema read access (every engine's blanket GRANT), so the
    -- correct, non-invented resolution is the zone's own centroid -- a
    -- representative point, not a fabricated coordinate. A Service Order
    -- that names a zone with no matching row is a genuine data error, not
    -- something to silently proceed past, so it is rejected here rather
    -- than dispatched with a missing pickup point.
    SELECT ST_Y(ST_Centroid(boundary)), ST_X(ST_Centroid(boundary))
    INTO v_pickup_lat, v_pickup_lon
    FROM trustride.cost_operational_zones WHERE zone_code = v_scope_detail->>'origin_zone_code' AND active = TRUE;

    IF v_pickup_lat IS NULL THEN
      UPDATE trustride.business_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'ORIGIN_ZONE_NOT_FOUND:' || coalesce(v_scope_detail->>'origin_zone_code', 'NULL'), accepted_at = now() WHERE signal_id = p_signal_id;
      RETURN 'REJECTED';
    END IF;

    INSERT INTO trustride.business_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (v_correlation_id, 'TRS026_ENG002_RESC', 'ASSIGNMENT_REQUESTED',
      jsonb_build_object('order_id', v_order_id, 'order_line_id', v_order_line_id, 'macro_domain', v_payload->>'macro_domain',
        'required_capacity_class', v_payload->'eligibility'->>'required_capacity_class_code',
        'pickup_location', jsonb_build_object('latitude', v_pickup_lat, 'longitude', v_pickup_lon)),
      'ASSIGNMENT_REQUESTED:' || v_order_id::text);
  END IF;

  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_service_resolved_accept(UUID) IS
  '[Trace: §4.1 SERVICE_RESOLVED, Article 19 Stage 1] Confirms the catalogue selection; on confirmed coverage, opens the Article 20.2 assignment sub-sequence.';

CREATE OR REPLACE FUNCTION trustride.fn_business_resource_reserved_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_payload         JSONB;
  v_correlation_id  UUID;
  v_order_id        UUID;
  v_workforce_unit_id UUID;
  v_capacity_class  TEXT;
  v_line            RECORD;
  v_requester_user_id UUID;
  v_engine_capacity TEXT;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_correlation_id FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_business_resource_reserved_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  v_order_id := (v_payload->>'order_id')::uuid;
  v_workforce_unit_id := (v_payload->>'workforce_unit_id')::uuid;
  v_capacity_class := v_payload->>'capacity_class';

  SELECT requester_user_id INTO v_requester_user_id FROM trustride.business_order WHERE order_id = v_order_id;

  -- Article 20.2's second step: "the reservation converts to a firm
  -- assignment once the requester accepts." Auto-confirmed here, matching
  -- the same precedent already established by Resources' own auto-pick in
  -- fn_resource_assignment_requested_accept -- no separate human-in-the-loop
  -- step exists anywhere in the adopted corpus for this transition.
  -- Trip context comes from the order's own scope -- Article 16's "no
  -- scope, no Order" extended to its logical conclusion: no trip context,
  -- no dispatch. A real dispatchable Service Order line must carry it.
  SELECT scope_detail, order_line_id INTO v_line FROM trustride.business_order_line
  WHERE order_id = v_order_id ORDER BY line_sequence ASC LIMIT 1;

  IF v_line.scope_detail IS NULL
     OR v_line.scope_detail->>'origin_zone_code' IS NULL
     OR v_line.scope_detail->>'destination_zone_code' IS NULL
     OR v_line.scope_detail->>'distance_km' IS NULL
     OR v_line.scope_detail->>'duration_min' IS NULL THEN
    UPDATE trustride.business_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'ORDER_LINE_MISSING_TRIP_SCOPE', accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END IF;

  v_engine_capacity := CASE WHEN v_capacity_class = 'BODA_BODA' THEN 'CC_125' ELSE 'NOT_APPLICABLE' END;

  INSERT INTO trustride.business_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v_correlation_id, 'TRS026_ENG002_RESC', 'RESOURCE_ASSIGNMENT_CONFIRMED',
    jsonb_build_object(
      'order_id', v_order_id, 'order_line_id', v_line.order_line_id, 'workforce_unit_id', v_workforce_unit_id,
      'origin_zone_code', v_line.scope_detail->>'origin_zone_code', 'destination_zone_code', v_line.scope_detail->>'destination_zone_code',
      'distance_km', v_line.scope_detail->>'distance_km', 'duration_min', v_line.scope_detail->>'duration_min',
      'requester_user_id', v_requester_user_id, 'jurisdiction', 'KISUMU_COUNTY', 'engine_capacity', v_engine_capacity
    ),
    'RESOURCE_ASSIGNMENT_CONFIRMED:' || v_order_id::text || ':' || v_workforce_unit_id::text);

  UPDATE trustride.business_order SET updated_at = now() WHERE order_id = v_order_id;

  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_resource_reserved_accept(UUID) IS
  '[Trace: §4.1 RESOURCE_RESERVED, Article 20.2] Hardening correction (2026-08-24): was a no-op, silently stalling every order at VALIDATED forever -- the real, documented gap this platform had at Engine 4''s prior state. Now converts the reservation into a firm assignment by emitting RESOURCE_ASSIGNMENT_CONFIRMED (a new signal, since none of the adopted source documents name this exact transition), auto-confirmed, carrying real trip context read from the order''s own scope_detail -- the firm Job is only created once RESOURCE_ASSIGNED comes back.';

CREATE OR REPLACE FUNCTION trustride.fn_business_resource_assigned_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_order_id UUID;
  v_job_id UUID;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_business_resource_assigned_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  v_order_id := (v_payload->>'order_id')::uuid;

  INSERT INTO trustride.business_job (order_id, job_type, workforce_unit_id)
  VALUES (v_order_id, 'IMMEDIATE', (v_payload->>'workforce_unit_id')::uuid)
  RETURNING job_id INTO v_job_id;

  UPDATE trustride.business_order SET status = 'JOB_CREATED', order_stage = 'ASSIGNMENT_VALIDATION_JOB_CREATION' WHERE order_id = v_order_id;

  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('job_id', v_job_id) WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_resource_assigned_accept(UUID) IS
  '[Trace: §4.1 RESOURCE_ASSIGNED, Article 19 Stage 2] Creates the firm business_job row -- no Job exists before this.';

CREATE OR REPLACE FUNCTION trustride.fn_business_unit_price_locked_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_order_id UUID;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_business_unit_price_locked_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  v_order_id := (v_payload->>'order_id')::uuid;

  UPDATE trustride.business_order SET quote_id = (v_payload->>'quote_id')::uuid, updated_at = now() WHERE order_id = v_order_id;

  INSERT INTO trustride.business_settlement (order_id, computed_total_fare_kes, payment_rail)
  VALUES (v_order_id, (v_payload->>'computed_total_fare_kes')::numeric, 'MPESA_C2B_STK')
  ON CONFLICT (order_id) DO NOTHING;

  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_unit_price_locked_accept(UUID) IS
  '[Trace: §4.1 UNIT_PRICE_LOCKED, Article 20.5.4] Posts the fee back onto the Order and opens the settlement record -- the fee is posted before acceptance, never after.';

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

  -- Hardening correction (2026-08-24): Integration's own real payload
  -- carries quote_id, never order_id -- Integration has no business knowing
  -- Business's internal order_id (Article 33 boundary); Business itself
  -- already stores the quote_id<->order_id mapping (fn_business_unit_
  -- price_locked_accept), so Business resolves it, not the other way round.
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
    jsonb_build_object('order_id', v_order_id, 'computed_total_fare_kes', (SELECT computed_total_fare_kes FROM trustride.business_settlement WHERE order_id = v_order_id), 'receipt_code', v_receipt_code),
    'ORDER_SETTLED:' || v_order_id::text
  FROM trustride.business_order WHERE order_id = v_order_id;

  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_payment_settled_accept(UUID) IS
  '[Trace: §4.1 PAYMENT_SETTLED, Article 43] Settlement is not complete until the ledger is posted AND the receipt is generated -- both happen atomically here, never partially.';

-- Hardening correction (2026-08-24): PAYMENT_FAILED and PAYMENT_STK_FAILED
-- are both real signals Engine 6 (Integration) already emits, and had
-- nowhere to go in Business until now -- a failed payment attempt was a
-- silent dead end (NO_RULE_MATCHED at best, an unhandled signal_type
-- rejection at worst). A failed payment does not undo the service already
-- rendered (Article per MNY-15: Money is not Payment -- the settlement
-- record, not the Order's own operational status, carries the failure);
-- the order stays exactly where it was, and the requester can be prompted
-- to retry through the same settlement row.
CREATE OR REPLACE FUNCTION trustride.fn_business_payment_failed_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_order_id UUID;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_business_payment_failed_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  v_order_id := (v_payload->>'order_id')::uuid;
  IF v_order_id IS NULL THEN
    SELECT order_id INTO v_order_id FROM trustride.business_order WHERE quote_id = (v_payload->>'quote_id')::uuid;
  END IF;
  IF v_order_id IS NULL THEN
    UPDATE trustride.business_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'NO_ORDER_FOR_QUOTE_ID', accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END IF;

  UPDATE trustride.business_settlement SET payment_status = 'FAILED' WHERE order_id = v_order_id AND payment_status <> 'RECEIPT_GENERATED';

  PERFORM trustride.fn_audit_log_append('business_settlement', v_order_id, 'PAYMENT_FAILED', NULL,
    'SYSTEM', NULL, NULL, NULL, jsonb_build_object('gateway_txn_id', v_payload->>'gateway_txn_id'));

  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_payment_failed_accept(UUID) IS
  '[Trace: §4.1 PAYMENT_FAILED] The callback-leg failure -- STK was accepted but the actual payment did not settle. Marks the settlement FAILED; the Order''s own operational status is untouched (the service was already rendered).';

CREATE OR REPLACE FUNCTION trustride.fn_business_payment_stk_failed_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_order_id UUID;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_business_payment_stk_failed_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  v_order_id := (v_payload->>'order_id')::uuid;
  IF v_order_id IS NULL THEN
    SELECT order_id INTO v_order_id FROM trustride.business_order WHERE quote_id = (v_payload->>'quote_id')::uuid;
  END IF;
  IF v_order_id IS NULL THEN
    UPDATE trustride.business_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'NO_ORDER_FOR_QUOTE_ID', accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END IF;

  UPDATE trustride.business_settlement SET payment_status = 'FAILED' WHERE order_id = v_order_id AND payment_status <> 'RECEIPT_GENERATED';

  PERFORM trustride.fn_audit_log_append('business_settlement', v_order_id, 'PAYMENT_STK_FAILED', NULL,
    'SYSTEM', NULL, NULL, NULL, jsonb_build_object('gateway_txn_id', v_payload->>'gateway_txn_id', 'reason', v_payload->>'reason'));

  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_payment_stk_failed_accept(UUID) IS
  '[Trace: §4.1 PAYMENT_STK_FAILED] The gateway-decline leg -- the STK push itself was never accepted by the rail (Integration''s own simulator/real adapter declined before reaching PENDING_CALLBACK). Same treatment as PAYMENT_FAILED: settlement marked FAILED, Order left untouched.';

CREATE OR REPLACE FUNCTION trustride.fn_business_marketplace_listing_sold_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_correlation_id UUID;
  v_order_id UUID;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_correlation_id FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_business_marketplace_listing_sold_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  v_order_id := trustride.fn_business_order_place(
    '00000000-0000-0000-0000-000000000000'::uuid, 'CUSTOMER', 'MARKETPLACE-ITEM-SALE', 'MARKETPLACE',
    jsonb_build_array(jsonb_build_object('line_description', 'Marketplace item sale', 'scope_detail', jsonb_build_object('listing_id', v_payload->>'listing_id'))),
    'SERVICE_ORDER', 'KISUMU_COUNTY', v_correlation_id
  );

  INSERT INTO trustride.business_settlement (order_id, computed_total_fare_kes, payment_rail)
  VALUES (v_order_id, (v_payload->>'list_price_kes')::numeric, 'MPESA_C2B_STK')
  ON CONFLICT (order_id) DO NOTHING;

  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('order_id', v_order_id) WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_marketplace_listing_sold_accept(UUID) IS
  '[Trace: §4.1 MARKETPLACE_LISTING_SOLD] Initiates settlement for a Marketplace Order under the same Article 43 sequence, per the source document''s own §4.1 note. requester_user_id is a placeholder until a real buyer identity is carried on this signal -- named, not silently guessed.';

-- --- Review (Article 19 Stage 6) ---
CREATE OR REPLACE FUNCTION trustride.fn_business_review_submit(p_order_id UUID, p_reviewer_user_id UUID, p_reviewee_user_id UUID, p_rating SMALLINT, p_comment TEXT DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_review_id UUID;
BEGIN
  -- Hardening (2026-08-24): REVIEWED is included because this function is
  -- bi-directional by construction (its own documented design) -- the
  -- FIRST call flips the order to REVIEWED, so a guard that only accepted
  -- COMPLETED/SETTLED would make the SECOND, equally legitimate call
  -- (the other direction) fail against the function's own stated intent.
  IF NOT EXISTS (SELECT 1 FROM trustride.business_order WHERE order_id = p_order_id AND status IN ('COMPLETED', 'SETTLED', 'REVIEWED')) THEN
    RAISE EXCEPTION 'fn_business_review_submit: order % is not COMPLETED/SETTLED/REVIEWED (or does not exist) -- a review requires a finished order', p_order_id;
  END IF;

  INSERT INTO trustride.business_review (order_id, reviewer_user_id, reviewee_user_id, rating, comment)
  VALUES (p_order_id, p_reviewer_user_id, p_reviewee_user_id, p_rating, p_comment)
  RETURNING review_id INTO v_review_id;

  UPDATE trustride.business_order SET status = 'REVIEWED', order_stage = 'REVIEW_RATE_SUPPORT' WHERE order_id = p_order_id AND status <> 'REVIEWED';

  RETURN v_review_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_review_submit(UUID, UUID, UUID, SMALLINT, TEXT) IS
  '[Trace: Article 19 Stage 6, Article 51] Bi-directional by construction -- call twice, once per direction, against the same order_id.';

-- --- Per-engine inbox processor, matching the established convention ---
CREATE OR REPLACE FUNCTION trustride.fn_business_inbox_process(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_signal_type TEXT;
  v_result TEXT;
BEGIN
  SELECT signal_type INTO v_signal_type FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_signal_type IS NULL THEN
    RAISE EXCEPTION 'fn_business_inbox_process: no RECEIVED signal %', p_signal_id;
  END IF;

  CASE v_signal_type
    WHEN 'SERVICE_RESOLVED' THEN v_result := trustride.fn_business_service_resolved_accept(p_signal_id);
    WHEN 'RESOURCE_RESERVED' THEN v_result := trustride.fn_business_resource_reserved_accept(p_signal_id);
    WHEN 'RESOURCE_ASSIGNED' THEN v_result := trustride.fn_business_resource_assigned_accept(p_signal_id);
    WHEN 'UNIT_PRICE_LOCKED' THEN v_result := trustride.fn_business_unit_price_locked_accept(p_signal_id);
    WHEN 'PAYMENT_SETTLED' THEN v_result := trustride.fn_business_payment_settled_accept(p_signal_id);
    WHEN 'PAYMENT_FAILED' THEN v_result := trustride.fn_business_payment_failed_accept(p_signal_id);
    WHEN 'PAYMENT_STK_FAILED' THEN v_result := trustride.fn_business_payment_stk_failed_accept(p_signal_id);
    WHEN 'MARKETPLACE_LISTING_SOLD' THEN v_result := trustride.fn_business_marketplace_listing_sold_accept(p_signal_id);
    ELSE
      UPDATE trustride.business_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'UNREGISTERED_SIGNAL_TYPE:' || v_signal_type WHERE signal_id = p_signal_id;
      v_result := 'REJECTED';
  END CASE;

  RETURN v_result;
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_inbox_process(UUID) IS
  'Dispatches a RECEIVED business_event_inbox row to the matching accept-handler by signal_type.';

-- ============================================================================
-- PHASE 7 -- TRIGGERS
-- ============================================================================
-- trg_business_order_scope_exists and trg_business_settlement_block_
-- illegal_mutation are created inline with their tables above (Phase 3/4/5).

-- ============================================================================
-- PHASE 8 -- ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE trustride.business_actor_registration ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_actor_registration_self_read ON trustride.business_actor_registration FOR SELECT TO trustride_authenticated USING (user_id = auth.uid());
CREATE POLICY business_actor_registration_service_write ON trustride.business_actor_registration FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.business_customer_profile ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_customer_profile_self_read ON trustride.business_customer_profile FOR SELECT TO trustride_authenticated
  USING (actor_registration_id IN (SELECT actor_registration_id FROM trustride.business_actor_registration WHERE user_id = auth.uid()));
CREATE POLICY business_customer_profile_service_write ON trustride.business_customer_profile FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.business_partner_agreement ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_partner_agreement_self_read ON trustride.business_partner_agreement FOR SELECT TO trustride_authenticated
  USING (actor_registration_id IN (SELECT actor_registration_id FROM trustride.business_actor_registration WHERE user_id = auth.uid()));
CREATE POLICY business_partner_agreement_service_write ON trustride.business_partner_agreement FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.business_operator_engagement ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_operator_engagement_self_read ON trustride.business_operator_engagement FOR SELECT TO trustride_authenticated
  USING (actor_registration_id IN (SELECT actor_registration_id FROM trustride.business_actor_registration WHERE user_id = auth.uid()));
CREATE POLICY business_operator_engagement_service_write ON trustride.business_operator_engagement FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.business_intermediary_engagement ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_intermediary_engagement_self_read ON trustride.business_intermediary_engagement FOR SELECT TO trustride_authenticated
  USING (actor_registration_id IN (SELECT actor_registration_id FROM trustride.business_actor_registration WHERE user_id = auth.uid()));
CREATE POLICY business_intermediary_engagement_service_write ON trustride.business_intermediary_engagement FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.business_governor_engagement ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_governor_engagement_self_read ON trustride.business_governor_engagement FOR SELECT TO trustride_authenticated
  USING (actor_registration_id IN (SELECT actor_registration_id FROM trustride.business_actor_registration WHERE user_id = auth.uid()));
CREATE POLICY business_governor_engagement_service_write ON trustride.business_governor_engagement FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.business_order ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_order_requester_read ON trustride.business_order FOR SELECT TO trustride_authenticated USING (requester_user_id = auth.uid());
CREATE POLICY business_order_service_write ON trustride.business_order FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.business_order_line ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_order_line_requester_read ON trustride.business_order_line FOR SELECT TO trustride_authenticated
  USING (EXISTS (SELECT 1 FROM trustride.business_order o WHERE o.order_id = business_order_line.order_id AND o.requester_user_id = auth.uid()));
CREATE POLICY business_order_line_service_write ON trustride.business_order_line FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.business_partnership_response ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_partnership_response_requester_read ON trustride.business_partnership_response FOR SELECT TO trustride_authenticated
  USING (EXISTS (SELECT 1 FROM trustride.business_order o WHERE o.order_id = business_partnership_response.order_id AND o.requester_user_id = auth.uid()));
CREATE POLICY business_partnership_response_service_write ON trustride.business_partnership_response FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.business_job ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_job_requester_read ON trustride.business_job FOR SELECT TO trustride_authenticated
  USING (EXISTS (SELECT 1 FROM trustride.business_order o WHERE o.order_id = business_job.order_id AND o.requester_user_id = auth.uid()));
CREATE POLICY business_job_service_write ON trustride.business_job FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.business_tracking_session ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_tracking_session_requester_read ON trustride.business_tracking_session FOR SELECT TO trustride_authenticated
  USING (EXISTS (SELECT 1 FROM trustride.business_job j JOIN trustride.business_order o ON o.order_id = j.order_id WHERE j.job_id = business_tracking_session.job_id AND o.requester_user_id = auth.uid()));
CREATE POLICY business_tracking_session_service_write ON trustride.business_tracking_session FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.business_settlement ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_settlement_requester_read ON trustride.business_settlement FOR SELECT TO trustride_authenticated
  USING (EXISTS (SELECT 1 FROM trustride.business_order o WHERE o.order_id = business_settlement.order_id AND o.requester_user_id = auth.uid()));
CREATE POLICY business_settlement_service_write ON trustride.business_settlement FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.business_review ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_review_participant_read ON trustride.business_review FOR SELECT TO trustride_authenticated
  USING (reviewer_user_id = auth.uid() OR reviewee_user_id = auth.uid());
CREATE POLICY business_review_service_write ON trustride.business_review FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.business_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_event_outbox_service_only ON trustride.business_event_outbox FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.business_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_event_inbox_service_only ON trustride.business_event_inbox FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);

-- ============================================================================
-- PHASE 9 -- INDEXES
-- ============================================================================
CREATE INDEX idx_business_actor_domain ON trustride.business_actor_registration (user_type_domain) WHERE registration_status = 'ACTIVE';
CREATE INDEX idx_business_partner_actor ON trustride.business_partner_agreement (actor_registration_id) WHERE status = 'ACTIVE';
CREATE INDEX idx_business_order_requester ON trustride.business_order (requester_user_id);
CREATE INDEX idx_business_order_status ON trustride.business_order (status);
CREATE INDEX idx_business_order_correlation ON trustride.business_order (correlation_id);
CREATE INDEX idx_business_order_root_type ON trustride.business_order (order_root_type);
CREATE INDEX idx_business_partnership_response_due ON trustride.business_partnership_response (response_due_at) WHERE response_status IN ('SUBMITTED', 'UNDER_REVIEW');
CREATE INDEX idx_business_job_order ON trustride.business_job (order_id);
CREATE INDEX idx_business_job_status ON trustride.business_job (status);
CREATE INDEX idx_business_job_workforce_unit ON trustride.business_job (workforce_unit_id) WHERE workforce_unit_id IS NOT NULL;
CREATE INDEX idx_business_tracking_active ON trustride.business_tracking_session (job_id) WHERE ended_at IS NULL;
CREATE INDEX idx_business_tracking_location ON trustride.business_tracking_session USING GIST (exact_location);
CREATE INDEX idx_business_settlement_status ON trustride.business_settlement (payment_status);
CREATE INDEX idx_business_review_order ON trustride.business_review (order_id);
CREATE INDEX idx_business_review_reviewee ON trustride.business_review (reviewee_user_id);
-- Hardening (2026-08-24): nothing prevented the same reviewer submitting a
-- second review in the same direction against the same order -- a real
-- constraint, not just application logic, matching this platform's own
-- established discipline.
CREATE UNIQUE INDEX uq_business_review_direction ON trustride.business_review (order_id, reviewer_user_id, reviewee_user_id);
CREATE INDEX idx_business_outbox_status ON trustride.business_event_outbox (signal_status);
CREATE INDEX idx_business_outbox_correlation ON trustride.business_event_outbox (correlation_id);
CREATE INDEX idx_business_inbox_status ON trustride.business_event_inbox (signal_status);
CREATE INDEX idx_business_inbox_correlation ON trustride.business_event_inbox (correlation_id);

-- ============================================================================
-- PHASE 10 -- VIEWS
-- ============================================================================
CREATE VIEW trustride.v_business_order_status AS
SELECT o.order_id, o.order_code, o.order_root_type, o.status, o.order_stage, o.requester_user_id,
  j.job_id, j.status AS job_status, s.payment_status, s.receipt_code
FROM trustride.business_order o
LEFT JOIN trustride.business_job j ON j.order_id = o.order_id
LEFT JOIN trustride.business_settlement s ON s.order_id = o.order_id;
COMMENT ON VIEW trustride.v_business_order_status IS 'One-row view of an Order''s full lifecycle status across job and settlement.';

-- ============================================================================
-- PHASE 11 -- PRIVILEGE LOCKDOWN
-- ============================================================================
GRANT USAGE ON SCHEMA trustride TO trs026_eng004_bus_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA trustride TO trs026_eng004_bus_service;
GRANT SELECT ON trustride.v_business_order_status TO trustride_authenticated;

GRANT EXECUTE ON FUNCTION trustride.fn_business_actor_register(UUID, trustride.business_user_type_domain_enum, TEXT) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_customer_profile_ensure(UUID) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_partner_agreement_open(UUID, trustride.business_partner_category_enum, TEXT, DATE, JSONB) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_operator_engagement_open(UUID, TEXT, DATE, UUID) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_intermediary_engagement_open(UUID, TEXT, DATE, UUID) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_governor_engagement_open(UUID, DATE, UUID, TEXT) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_order_place(UUID, trustride.business_user_type_domain_enum, TEXT, TEXT, JSONB, trustride.business_order_root_enum, TEXT, UUID) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_order_cancel(UUID, UUID, TEXT) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_partnership_response_decide(UUID, trustride.business_partnership_response_status_enum, UUID, TEXT) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_partnership_response_timeout_sweep() TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_job_progress_advance(UUID, UUID, UUID) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_tracking_session_open(UUID) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_tracking_location_update(UUID, NUMERIC, NUMERIC, TIMESTAMPTZ) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_service_resolved_accept(UUID) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_resource_reserved_accept(UUID) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_resource_assigned_accept(UUID) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_unit_price_locked_accept(UUID) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_payment_settled_accept(UUID) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_payment_failed_accept(UUID) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_payment_stk_failed_accept(UUID) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_marketplace_listing_sold_accept(UUID) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_review_submit(UUID, UUID, UUID, SMALLINT, TEXT) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_business_inbox_process(UUID) TO trs026_eng004_bus_service, trs026_eng007_orch_service;

GRANT EXECUTE ON FUNCTION trustride.fn_audit_log_append(TEXT, UUID, TEXT, UUID, TEXT, TEXT, TEXT, JSONB, JSONB) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_sequence_next(TEXT) TO trs026_eng004_bus_service;

GRANT trs026_eng004_bus_service TO service_role;

-- ============================================================================
-- PHASE 12 -- VALIDATION
-- ============================================================================
DO $$
DECLARE
  v_table_count    INTEGER;
  v_function_count INTEGER;
BEGIN
  SELECT count(*) INTO v_table_count
  FROM information_schema.tables
  WHERE table_schema = 'trustride' AND table_type = 'BASE TABLE' AND table_name LIKE 'business_%';
  IF v_table_count <> 15 THEN
    RAISE EXCEPTION 'Engine 4 validation failed: expected 15 business_ tables (12 adopted + 3 Founder-directed additions), found %', v_table_count;
  END IF;

  SELECT count(*) INTO v_function_count
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'trustride' AND p.proname LIKE 'fn_business%';
  IF v_function_count <> 23 THEN
    RAISE EXCEPTION 'Engine 4 validation failed: expected 23 fn_business%% functions (21 original + fn_business_payment_failed_accept + fn_business_payment_stk_failed_accept, hardening 2026-08-24), found %', v_function_count;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng004_bus_service') THEN
    RAISE EXCEPTION 'Engine 4 validation failed: trs026_eng004_bus_service role missing';
  END IF;

  RAISE NOTICE 'Engine 4 validation passed: 15/15 business_ tables, 23/23 fn_business%% functions, service role present.';
END
$$;

-- ============================================================================
-- PHASE 13 -- FINALIZATION
-- ============================================================================

-- --- Extend Engine 7's dispatch mechanism to recognize Business (same
-- convention established by Engine 5's own Correction 10) ---
CREATE OR REPLACE FUNCTION trustride.fn_orch_destination_cache_sync()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_synced INTEGER;
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
      ELSE NULL
    END,
    rr.target_engine || ':DEFAULT',
    rr.route_id::text, 'ACTIVE', now()
  FROM trustride.routing_rule rr
  WHERE rr.active = TRUE
    AND CASE rr.target_engine
      WHEN 'TRS026_ENG001_FDN' THEN TRUE WHEN 'TRS026_ENG002_RESC' THEN TRUE WHEN 'TRS026_ENG003_SERV' THEN TRUE
      WHEN 'TRS026_ENG004_BUS' THEN TRUE WHEN 'TRS026_ENG005_COST' THEN TRUE ELSE FALSE
    END
  ON CONFLICT (source_engine_code, signal_type, destination_engine_code) DO UPDATE
    SET destination_inbox_table = EXCLUDED.destination_inbox_table,
        cache_status = 'ACTIVE', last_synced_at = now();

  GET DIAGNOSTICS v_synced = ROW_COUNT;
  RETURN v_synced;
END;
$$;
COMMENT ON FUNCTION trustride.fn_orch_destination_cache_sync() IS
  'Refreshes orch_destination_cache from Foundation''s routing_rule. Extended by Engine 4''s own migration to recognize Business, following Engine 5''s established convention.';

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
        'INSERT INTO trustride.%I (signal_id, correlation_id, causation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)',
        v_cache.destination_inbox_table
      ) USING v_row.signal_id, v_row.correlation_id, v_row.causation_id, v_row.emitting_engine, v_cache.destination_engine_code, v_row.signal_type, v_row.payload_in, v_row.idempotency_key || ':inbox';

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
          WHEN 'TRS026_ENG002_RESC' THEN PERFORM trustride.fn_resource_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG003_SERV' THEN PERFORM trustride.fn_service_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG004_BUS' THEN PERFORM trustride.fn_business_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG005_COST' THEN PERFORM trustride.fn_cost_inbox_process(v_row.signal_id);
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
COMMENT ON FUNCTION trustride.fn_orch_dispatch_cycle() IS
  'The heartbeat itself: discover every PENDING row across every registered outbox in true chronological order, route, admit, queue, dispatch, and hand off. Extended by Engine 4''s own migration to recognize Business.';

INSERT INTO trustride.orch_outbox_registry (engine_code, outbox_table_name) VALUES ('TRS026_ENG004_BUS', 'business_event_outbox');

-- The routing law for every signal now flowing to/from Business, across
-- every engine already built.
INSERT INTO trustride.routing_rule (event_type, source_engine, target_engine, route_priority) VALUES
  ('SERVICE_RESOLVED', 'TRS026_ENG003_SERV', 'TRS026_ENG004_BUS', 0),
  ('RESOURCE_RESERVED', 'TRS026_ENG002_RESC', 'TRS026_ENG004_BUS', 0),
  ('RESOURCE_ASSIGNED', 'TRS026_ENG002_RESC', 'TRS026_ENG004_BUS', 0),
  ('UNIT_PRICE_LOCKED', 'TRS026_ENG005_COST', 'TRS026_ENG004_BUS', 0),
  ('MARKETPLACE_LISTING_SOLD', 'TRS026_ENG003_SERV', 'TRS026_ENG004_BUS', 0),
  ('SERVICE_LOOKUP_REQUESTED', 'TRS026_ENG004_BUS', 'TRS026_ENG003_SERV', 0),
  ('ASSIGNMENT_REQUESTED', 'TRS026_ENG004_BUS', 'TRS026_ENG002_RESC', 0),
  ('JOB_COMPLETED', 'TRS026_ENG004_BUS', 'TRS026_ENG002_RESC', 0),
  ('RESOURCE_ASSIGNMENT_CONFIRMED', 'TRS026_ENG004_BUS', 'TRS026_ENG002_RESC', 0),
  ('PAYMENT_SETTLED', 'TRS026_ENG006_INTG', 'TRS026_ENG004_BUS', 0),
  ('PAYMENT_FAILED', 'TRS026_ENG006_INTG', 'TRS026_ENG004_BUS', 0),
  ('PAYMENT_STK_FAILED', 'TRS026_ENG006_INTG', 'TRS026_ENG004_BUS', 0);
-- Hardening (2026-08-24): Engine 6 (Integration) is now built, so PAYMENT_
-- SETTLED/PAYMENT_FAILED/PAYMENT_STK_FAILED are registered above.
-- Still not yet registered (destination engine not yet built): ORDER_PLACED/
-- ORDER_SETTLED (-> Presentation, awaiting Engine 11).

SELECT trustride.fn_orch_destination_cache_sync();

UPDATE trustride.engine_registry SET status = 'INSTALLED', engine_version = '1.1.0' WHERE engine_code = 'TRS026_ENG004_BUS';
