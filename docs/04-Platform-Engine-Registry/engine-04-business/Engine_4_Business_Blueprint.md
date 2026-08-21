# TRUSTRIDE SERVICES

# ENGINE 4 — BUSINESS ENGINE
## Complete Architectural, Data, API, and Signal Specification

**[Parent Authority: TBOC v2.0.0 Genesis Edition · Architecture Blueprint v1.1.0]**

*More than a Ride — We Save You Time.*

## Document Control

| Document Control Field | Entry |
| --- | --- |
| Document Title | Engine 4 — Business Engine: Complete Specification |
| Document Identifier | TRS026-ENG004-BUS-001 |
| Version | 1.0.1 |
| Status | **ADOPTED** (2026-08-16, per Founder directive — build order FDN → Resources → Services → Business) |
| Remediation | v1.0.1 corrects the Annex conformance table's RLS Law row, which claimed "eleven tables" while §2.1–2.11 declare twelve (§2.11 alone carries two: `business_event_outbox` and `business_event_inbox`) — a documentation-accuracy defect, same class as one found and fixed in Engine 2. The pre-existing `business_order_scope_exists` deferred-trigger fix (§2.5, applied in an earlier remediation pass) was re-verified intact; no CHECK-constraint-with-subquery remains anywhere in this instrument. Cross-checked against the now-finalized FDN-001 v3.0.0 Annex H DDL compilation and the remediated Engines 2 and 3 for alignment — no other deviation found |
| Classification | Institutional Blueprint — Confidential |
| Schema | `trustride` (single canonical PostgreSQL schema; this engine's tables are prefixed `business_`) |
| Platform Code | TRS026 |
| Engine Code | `TRS026_ENG004_BUS` |
| Engine No. | `ENGINE_004` |
| Installation Order | 004 |
| Parent Authority | TBOC v2.0.0 Genesis Edition — Article 12 (The Five User Type Domains), Article 16 (The Order Primitive), Article 17 (User Type Domains and Their Business Roles), Article 19 (Seven-Stage Universal Order Lifecycle), Article 20 (The Universal Service Flow), Article 21 (Live Tracking Information Contract), Article 22 (Scheduling Discipline), Article 43 (Settlement Stages & Approved Payment Rails) |
| Architecture Lineage | Positioned as Engine 4 in the eleven-engine Constitutional Engine Registry (Annex C, FDN-001 v3.0.0); Layer 2 Business Runtime of the Backend/Frontend/Event-Signal Architecture Blueprint v1.1.0, panel "Business / Actors" |

## Document Purpose & Constitutional Basis

This instrument specifies **Engine 4 — the Business Engine**, TrustRide's authoritative record of every commercial transaction and every business-layer relationship with the five User Type Domains. It answers one constitutional question for the rest of the platform — **what was requested, by whom, under what terms, and is it settled?**

TBOC does not permit a technical document to invent business concepts (Article 8, the Zero-Pollution Rule). Every mechanical rule in this document therefore traces to a standing TBOC provision:

| This engine's function | TBOC basis |
| --- | --- |
| Customers, Partners, Operators, Intermediaries, Governors — five domains, one identity root each | Article 12 — The Five User Type Domains |
| Everything commercially requested or undertaken is an Order, with Order Lines and Scope | Article 16 — The Order Primitive |
| The business role each User Type Domain plays on the platform | Article 17 |
| Exactly seven constitutional stages; no Order may skip, reorder, or bypass a stage | Article 19 — The Seven-Stage Universal Order Lifecycle |
| The full execution sequence binding identity, catalogue, order, assignment, dispatch, settlement, review | Article 20 — The Universal Service Flow |
| The five data elements mandatory wherever live tracking is active | Article 21 — The Live Tracking Information Contract |
| Immediate versus scheduled Jobs | Article 22 — Scheduling Discipline |
| Payment Initiated → Authorized → Settled → Ledger Posted → Receipt Generated, on the named approved rails | Article 43 — Settlement Stages & Approved Payment Rails |
| No engine reads or writes another engine's tables; cross-engine truth moves only as a signal | Article 33 |

Foundation (Engine 1) binds every engagement to exactly one User Type Domain (`user_type_binding`) — the *fact* of the role. This engine never duplicates that binding. What this engine owns is the **business life** of that role: a Customer's commercial relationship, a Partner's agreement, an Operator's engagement terms — and, at the centre of all of it, the Order itself, from placement through the seven constitutional stages to settlement and review.

---

# SECTION 1 — ARCHITECTURAL ROLE & BOUNDARIES

## 1.1 Mission

Engine 4 is the platform's single, deterministic authority for the commercial transaction — the Order and every stage it lawfully traverses — and for the business-layer registration of the five User Type Domains. No commercial fact about a request exists anywhere else on the platform.

## 1.2 Operational Duties

1. **Actor registration.** Maintain `business_actor_registration` and its per-domain extensions per Article 12/17 — the business terms under which a Customer, Partner, Operator, Intermediary, or Governor engages TrustRide, distinct from Foundation's bare identity binding.
2. **Order custody.** Maintain `business_order` and `business_order_line` per Article 16 — every Order carries scope; an Order without scope is constitutionally void.
3. **Seven-stage lifecycle enforcement.** Drive every Order through Article 19's seven stages in strict sequence — Order Placement & Scope, Assignment Validation & Job Creation, Dispatch, Execution & Completion, Payment Prompting & Settlement, Review/Rate/Support, Resource Availability — never skipping, reordering, or bypassing a stage.
4. **Job custody.** Maintain `business_job` per Article 22 — immediate Jobs dispatch at once upon acceptance; scheduled Jobs bind a future time window and are reconfirmed before dispatch.
5. **Live tracking contract.** Maintain `business_tracking_session` per Article 21 — Resource Type, Resource ID, ETA, Status, and Exact Location, active-session-only, from Job start to Job completion.
6. **Settlement custody.** Maintain `business_settlement` per Article 43 — Payment Initiated → Authorized → Settled → Ledger Posted → Receipt Generated. Settlement is not complete until both the ledger is posted and the receipt is generated.
7. **Review custody.** Maintain `business_review` per Article 19, Stage 6 — bi-directional rating, support, and dispute intake.
8. **Assignment orchestration.** Request resource discovery, reservation, and assignment from Engine 2 per the Article 20.2 sub-sequence, and post the fee, scope, and expected arrival back to the requester before acceptance (Article 20.5.4) — never after.

## 1.3 Interfaces with the Other Ten Engines

Per Plate I of the Backend Architecture and the Event/Signal Architecture, Engine 4 **never** calls another engine directly. Every interface below is a signal, carried through Engines 7/8 (Workflow Orchestration & Coordination) — the Sovereign Processing Unit.

| Engine | Direction | What crosses the boundary |
| --- | --- | --- |
| **Engine 1 — Foundation** | Inbound (by reference) | `user_id` identity and `user_type_binding` references only; this engine never reads or writes `platform_users` directly |
| **Engine 2 — Resources** | Bidirectional | Outbound: `ASSIGNMENT_REQUESTED` (Article 20.2), `JOB_COMPLETED` (Article 19, Stage 7). Inbound: `RESOURCE_RESERVED`, `RESOURCE_ASSIGNED` |
| **Engine 3 — Services** | Bidirectional | Outbound: `SERVICE_LOOKUP_REQUESTED` (Article 19, Stage 1). Inbound: `SERVICE_RESOLVED`, `MARKETPLACE_LISTING_SOLD` |
| **Engine 5 — Cost** | Inbound (via signal) | `UNIT_PRICE_LOCKED`, carrying the computed fare Cost's own specification (§5.2) already names as fired to "Engine 4 (Business)" the instant a quote is accepted |
| **Engine 6 — Integration** | Inbound (via signal) | `PAYMENT_SETTLED` — the settlement outcome of the M-Pesa C2B STK Push or Flutterwave call that Integration executed after Cost's `PAYMENT_STK_TRIGGERED`; Engine 4 never calls a payment rail itself |
| **Engines 7/8 — Workflow Orchestration & Coordination** | Structural | The exclusive transport for every signal in and out of Engine 4's outbox/inbox |
| **Engine 9 — AI/ML Advisory** | Outbound (read-only) | Advisory reads `business_order` and `business_settlement` history as lawful projections for demand-forecasting and revenue-pattern recommendations; it never writes back |

## 1.4 Boundaries — What Engine 4 Never Does

1. **Never defines a Service.** Catalogue definition, eligibility, and coverage remain Engine 3's exclusive domain.
2. **Never discovers or assigns a resource directly.** Engine 4 requests; Engine 2 decides which resource answers.
3. **Never computes a fare.** Engine 4 receives `UNIT_PRICE_LOCKED` from Cost; it never invents or recalculates a fare figure.
4. **Never calls a payment rail.** Payment execution is Integration's exclusive domain under TISC; Engine 4 only records the settlement outcome.
5. **Never skips a constitutional stage.** No Job exists without acceptance; no assignment exists without an Order; no Order exists without scope (Article 20.5.3) — enforced structurally, never by convention only.
6. **Never holds identity.** `requester_user_id`, `operator_user_id`, and every actor reference are values, not claims of ownership; Identity remains Foundation's exclusive domain.

---

# SECTION 2 — PRODUCTION SQL DDL SCHEMA (PostgreSQL / Supabase / PostGIS-Ready)

## 2.0 Extensions & Enums (prerequisite)

```sql
-- Extensions (idempotent; already present platform-wide per Engine 001 Phase 0)
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

-- [Trace: TBOC-v2.0.0 | Article 12 | The Five User Type Domains]
CREATE TYPE business_user_type_domain_enum AS ENUM (
  'CUSTOMER', 'PARTNER', 'OPERATOR', 'INTERMEDIARY', 'GOVERNOR'
);

CREATE TYPE business_partner_category_enum AS ENUM (
  'FINANCIER', 'FLEET_CONTRIBUTOR', 'AMBASSADOR', 'VENDOR', 'STRATEGIC_COLLABORATOR'
);

-- [Trace: TBOC-v2.0.0 | Article 19 | The Seven-Stage Universal Order Lifecycle, verbatim]
CREATE TYPE business_order_stage_enum AS ENUM (
  'ORDER_PLACEMENT_SCOPE', 'ASSIGNMENT_VALIDATION_JOB_CREATION', 'DISPATCH',
  'EXECUTION_COMPLETION', 'PAYMENT_SETTLEMENT', 'REVIEW_RATE_SUPPORT', 'RESOURCE_AVAILABILITY'
);

CREATE TYPE business_order_status_enum AS ENUM (
  'PLACED', 'VALIDATED', 'JOB_CREATED', 'DECLINED', 'DISPATCHED',
  'EXECUTING', 'COMPLETED', 'SETTLED', 'REVIEWED', 'CLOSED', 'CANCELLED'
);

CREATE TYPE business_job_type_enum AS ENUM (
  'IMMEDIATE', 'SCHEDULED'
);

-- [Trace: TBOC-v2.0.0 | Article 20.3 | Dispatch sub-sequence, verbatim]
CREATE TYPE business_job_status_enum AS ENUM (
  'CREATED', 'DISPATCHED', 'EN_ROUTE', 'ARRIVED', 'EXECUTING', 'COMPLETED', 'VERIFIED', 'CANCELLED'
);

-- [Trace: TBOC-v2.0.0 | Article 43 | Approved Payment Rails, named as constitutional business law]
CREATE TYPE business_payment_rail_enum AS ENUM (
  'MPESA_C2B_STK', 'FLUTTERWAVE'
);

-- [Trace: TBOC-v2.0.0 | Article 43 | Payment Initiated -> Authorized -> Settled -> Ledger Posted -> Receipt Generated]
CREATE TYPE business_payment_status_enum AS ENUM (
  'INITIATED', 'AUTHORIZED', 'SETTLED', 'LEDGER_POSTED', 'RECEIPT_GENERATED', 'FAILED'
);
```

## 2.1 `business_actor_registration` — The Five User Type Domains

```sql
-- [Trace: TBOC-v2.0.0 | Article 12, 17 | The Five User Type Domains and Their Business Roles]
CREATE TABLE business_actor_registration (
  actor_registration_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 UUID NOT NULL,           -- reference only; identity lives in Foundation's platform_users
  user_type_domain          business_user_type_domain_enum NOT NULL,
  registration_status         TEXT NOT NULL DEFAULT 'ACTIVE'
                                 CHECK (registration_status IN ('PENDING', 'ACTIVE', 'SUSPENDED', 'TERMINATED')),
  terms_summary                  TEXT,               -- descriptive terms for INTERMEDIARY/GOVERNOR domains
  registered_at                    TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at                         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX uq_business_actor_user_domain ON business_actor_registration (user_id, user_type_domain);
CREATE INDEX idx_business_actor_domain ON business_actor_registration (user_type_domain) WHERE registration_status = 'ACTIVE';

COMMENT ON TABLE business_actor_registration IS
  '[Trace: TBOC-v2.0.0 | Article 12.9] Each domain is a User Type of a User — none creates a second identity root; a single User may hold multiple domain registrations across different engagements.';

ALTER TABLE business_actor_registration ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_actor_registration_self_read ON business_actor_registration
  FOR SELECT TO trustride_authenticated
  USING (user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY business_actor_registration_service_write ON business_actor_registration
  FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);
```

## 2.2 `business_customer_profile` — Customer Commercial Relationship

```sql
-- [Trace: TBOC-v2.0.0 | Article 12.1 | Customers]
CREATE TABLE business_customer_profile (
  customer_profile_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_registration_id     UUID NOT NULL UNIQUE REFERENCES business_actor_registration (actor_registration_id),
  order_count                 INTEGER NOT NULL DEFAULT 0 CHECK (order_count >= 0),
  lifetime_value_kes             NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (lifetime_value_kes >= 0),
  preferred_payment_rail            business_payment_rail_enum,
  loyalty_tier                        TEXT NOT NULL DEFAULT 'STANDARD',
  created_at                            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                              TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE business_customer_profile IS
  '[Trace: TBOC-v2.0.0 | Article 12.1] The commercial relationship summary for a Customer domain registration; lifetime_value_kes is a maintained rollup, never the ledger of record (Article 42 — the ledger of record is Engine 6/Foundation Governance financial infrastructure).';

ALTER TABLE business_customer_profile ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_customer_profile_self_read ON business_customer_profile
  FOR SELECT TO trustride_authenticated
  USING (actor_registration_id IN (
    SELECT actor_registration_id FROM business_actor_registration
    WHERE user_id = current_setting('app.current_user_id', true)::uuid
  ));
CREATE POLICY business_customer_profile_service_write ON business_customer_profile
  FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);
```

## 2.3 `business_partner_agreement` — Partner Commercial Agreements

```sql
-- [Trace: TBOC-v2.0.0 | Article 12.2 | Partners]
CREATE TABLE business_partner_agreement (
  partner_agreement_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_registration_id     UUID NOT NULL REFERENCES business_actor_registration (actor_registration_id),
  partner_category             business_partner_category_enum NOT NULL,
  agreement_type                  TEXT NOT NULL,
  agreement_terms                    JSONB NOT NULL DEFAULT '{}',
  start_date                            DATE NOT NULL,
  end_date                                DATE,
  status                                     TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'EXPIRED', 'TERMINATED')),
  created_at                                   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_business_partner_agreement_dates CHECK (end_date IS NULL OR end_date > start_date)
);

CREATE INDEX idx_business_partner_actor ON business_partner_agreement (actor_registration_id) WHERE status = 'ACTIVE';

COMMENT ON TABLE business_partner_agreement IS
  '[Trace: TBOC-v2.0.0 | Article 12.2] A partner may also become a customer in a different relationship; the domain is determined per engagement, never fused (Article 12.2).';

ALTER TABLE business_partner_agreement ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_partner_agreement_self_read ON business_partner_agreement
  FOR SELECT TO trustride_authenticated
  USING (actor_registration_id IN (
    SELECT actor_registration_id FROM business_actor_registration
    WHERE user_id = current_setting('app.current_user_id', true)::uuid
  ));
CREATE POLICY business_partner_agreement_service_write ON business_partner_agreement
  FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);
```

## 2.4 `business_operator_engagement` — Operator Employment Terms

```sql
-- [Trace: TBOC-v2.0.0 | Article 12.3 | Operators — Human Operators are TrustRide employees]
CREATE TABLE business_operator_engagement (
  operator_engagement_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_registration_id     UUID NOT NULL UNIQUE REFERENCES business_actor_registration (actor_registration_id),
  employment_type              TEXT NOT NULL DEFAULT 'EMPLOYEE' CHECK (employment_type IN ('EMPLOYEE', 'TECHNICAL_OPERATOR')),
  compensation_structure_ref      UUID,               -- reference into Foundation Governance's rate_register (Article 44.1); by value
  engagement_start                  DATE NOT NULL,
  engagement_status                    TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (engagement_status IN ('ACTIVE', 'SUSPENDED', 'TERMINATED')),
  created_at                             TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE business_operator_engagement IS
  '[Trace: TBOC-v2.0.0 | Article 12.3] Technical Operators — devices, software, automated agents — are registered Things under institutional custody (Engine 2), with no independent authority; this row records only the employment_type distinction.';

ALTER TABLE business_operator_engagement ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_operator_engagement_self_read ON business_operator_engagement
  FOR SELECT TO trustride_authenticated
  USING (actor_registration_id IN (
    SELECT actor_registration_id FROM business_actor_registration
    WHERE user_id = current_setting('app.current_user_id', true)::uuid
  ));
CREATE POLICY business_operator_engagement_service_write ON business_operator_engagement
  FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);
```

## 2.5 `business_order` — The Order Primitive

```sql
-- [Trace: TBOC-v2.0.0 | Article 16 | The Order Primitive]
CREATE TABLE business_order (
  order_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_code            TEXT NOT NULL UNIQUE,        -- 'TRS026-ORDER-000000001', issued by sequence_generator (Engine 001 Substrate)
  requester_user_id     UUID NOT NULL,                -- reference only
  user_type_domain      business_user_type_domain_enum NOT NULL,
  service_id            UUID NOT NULL,                -- by value reference to Engine 3's service_catalogue.service_id
  service_code          TEXT NOT NULL,
  macro_domain          TEXT NOT NULL,
  order_stage           business_order_stage_enum NOT NULL DEFAULT 'ORDER_PLACEMENT_SCOPE',
  status                business_order_status_enum NOT NULL DEFAULT 'PLACED',
  quote_id              UUID,                          -- by value reference to Engine 5's cost_unit_price_quotes.quote_id, set once resolved
  placed_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at             TIMESTAMPTZ,
  correlation_id        UUID NOT NULL,                  -- the platform signal envelope's correlation_id for this Order's lifecycle
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_business_order_requester ON business_order (requester_user_id);
CREATE INDEX idx_business_order_status ON business_order (status);
CREATE INDEX idx_business_order_correlation ON business_order (correlation_id);

COMMENT ON TABLE business_order IS
  '[Trace: TBOC-v2.0.0 | Article 16] An Order without scope is constitutionally void. PostgreSQL CHECK constraints cannot express a cross-row "at least one Order Line exists" rule; this is enforced by the accept-handler function (fn_business_order_place), which writes the Order and its Order Lines in one transaction and refuses to commit an Order with zero lines, per §2.6.';

-- Enforcement of the Article 16 "no scope, no Order" law: the Order and its first Order Line
-- commit atomically. No standalone INSERT into business_order is granted to trustride_authenticated;
-- only trs026_eng004_bus_service may write, and its accept-handler is the sole entry point.
CREATE OR REPLACE FUNCTION business_order_scope_exists() RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM business_order_line WHERE order_id = NEW.order_id) THEN
    RAISE EXCEPTION 'business_order %: an Order without scope is constitutionally void (Article 16); at least one business_order_line row is required in the same transaction', NEW.order_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Deferred so the same transaction that inserts the Order may insert its Order Lines before commit
CREATE CONSTRAINT TRIGGER trg_business_order_scope_exists
  AFTER INSERT ON business_order
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION business_order_scope_exists();

ALTER TABLE business_order ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_order_requester_read ON business_order
  FOR SELECT TO trustride_authenticated
  USING (requester_user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY business_order_service_write ON business_order
  FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);
```

## 2.6 `business_order_line` — Order Lines & Scope

```sql
-- [Trace: TBOC-v2.0.0 | Article 16 | Order Lines and Scope — the true nature and extent of the request]
CREATE TABLE business_order_line (
  order_line_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id              UUID NOT NULL REFERENCES business_order (order_id),
  line_sequence         SMALLINT NOT NULL,
  line_description      TEXT NOT NULL,
  quantity              NUMERIC(10,2) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  scope_detail          JSONB NOT NULL DEFAULT '{}',
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX uq_business_order_line_sequence ON business_order_line (order_id, line_sequence);

COMMENT ON TABLE business_order_line IS
  '[Trace: TBOC-v2.0.0 | Article 16] Every Order carries at least one Order Line describing the true nature and extent of the request.';

ALTER TABLE business_order_line ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_order_line_requester_read ON business_order_line
  FOR SELECT TO trustride_authenticated
  USING (EXISTS (
    SELECT 1 FROM business_order o
    WHERE o.order_id = business_order_line.order_id
      AND o.requester_user_id = current_setting('app.current_user_id', true)::uuid
  ));
CREATE POLICY business_order_line_service_write ON business_order_line
  FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);
```

## 2.7 `business_job` — Job Creation, Scheduling & Dispatch

```sql
-- [Trace: TBOC-v2.0.0 | Article 19 Stage 2-4, Article 22 | Job Creation, Scheduling Discipline, Dispatch]
CREATE TABLE business_job (
  job_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id              UUID NOT NULL REFERENCES business_order (order_id),
  job_type              business_job_type_enum NOT NULL,
  scheduled_window_start TIMESTAMPTZ,                 -- NULL for IMMEDIATE
  scheduled_window_end  TIMESTAMPTZ,
  workforce_unit_id     UUID,                          -- by value reference to Engine 2's resource_workforce_unit.workforce_unit_id
  status                business_job_status_enum NOT NULL DEFAULT 'CREATED',
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  dispatched_at         TIMESTAMPTZ,
  completed_at          TIMESTAMPTZ,
  verified_at           TIMESTAMPTZ,
  CONSTRAINT chk_business_job_schedule
    CHECK (job_type = 'IMMEDIATE' OR (scheduled_window_start IS NOT NULL AND scheduled_window_end IS NOT NULL AND scheduled_window_end > scheduled_window_start))
);

CREATE INDEX idx_business_job_order ON business_job (order_id);
CREATE INDEX idx_business_job_status ON business_job (status);
CREATE INDEX idx_business_job_workforce_unit ON business_job (workforce_unit_id) WHERE workforce_unit_id IS NOT NULL;

COMMENT ON TABLE business_job IS
  '[Trace: TBOC-v2.0.0 | Article 22] Immediate Jobs dispatch at once upon acceptance; Scheduled Jobs bind a future time window and are reconfirmed before dispatch. No Job exists without acceptance.';

ALTER TABLE business_job ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_job_requester_read ON business_job
  FOR SELECT TO trustride_authenticated
  USING (EXISTS (
    SELECT 1 FROM business_order o
    WHERE o.order_id = business_job.order_id
      AND o.requester_user_id = current_setting('app.current_user_id', true)::uuid
  ));
CREATE POLICY business_job_service_write ON business_job
  FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);
```

## 2.8 `business_tracking_session` — The Live Tracking Information Contract

```sql
-- [Trace: TBOC-v2.0.0 | Article 21 | The Live Tracking Information Contract — five mandatory data elements]
CREATE TABLE business_tracking_session (
  tracking_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id                UUID NOT NULL UNIQUE REFERENCES business_job (job_id),
  resource_type         TEXT NOT NULL,               -- "Resource Type" (Article 21)
  resource_id_display   TEXT NOT NULL,               -- "Resource ID" — rider/driver name, plate number, or Executive Assistant identity
  eta                   TIMESTAMPTZ,                  -- "ETA"
  tracking_status       TEXT NOT NULL DEFAULT 'EN_ROUTE',  -- "Status"
  exact_location        GEOMETRY(POINT, 4326),         -- "Exact Location"
  started_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at              TIMESTAMPTZ,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_business_tracking_active ON business_tracking_session (job_id) WHERE ended_at IS NULL;
CREATE INDEX idx_business_tracking_location ON business_tracking_session USING GIST (exact_location);

COMMENT ON TABLE business_tracking_session IS
  '[Trace: TBOC-v2.0.0 | Article 21] Active-session only: begins when the Job starts, ends when the Job completes. All five constitutionally mandatory data elements are present as columns, never optional.';

ALTER TABLE business_tracking_session ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_tracking_session_requester_read ON business_tracking_session
  FOR SELECT TO trustride_authenticated
  USING (EXISTS (
    SELECT 1 FROM business_job j JOIN business_order o ON o.order_id = j.order_id
    WHERE j.job_id = business_tracking_session.job_id
      AND o.requester_user_id = current_setting('app.current_user_id', true)::uuid
  ));
CREATE POLICY business_tracking_session_service_write ON business_tracking_session
  FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);
```

## 2.9 `business_settlement` — Settlement Stages & Approved Payment Rails

```sql
-- [Trace: TBOC-v2.0.0 | Article 43 | Settlement Stages & Approved Payment Rails]
CREATE TABLE business_settlement (
  settlement_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id               UUID NOT NULL UNIQUE REFERENCES business_order (order_id),
  computed_total_fare_kes NUMERIC(18,2) NOT NULL CHECK (computed_total_fare_kes >= 0),   -- copied by value from Engine 5's quote at UNIT_PRICE_LOCKED
  currency                CHAR(3) NOT NULL DEFAULT 'KES',
  payment_rail            business_payment_rail_enum NOT NULL,
  payment_status           business_payment_status_enum NOT NULL DEFAULT 'INITIATED',
  initiated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  authorized_at               TIMESTAMPTZ,
  settled_at                    TIMESTAMPTZ,
  ledger_posted_at                TIMESTAMPTZ,
  receipt_code                      TEXT UNIQUE,        -- 'TRS026-RECEIPT-000000001', issued by sequence_generator (Engine 001 Substrate)
  receipt_generated_at                TIMESTAMPTZ,
  created_at                            TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_business_settlement_receipt
    CHECK (payment_status <> 'RECEIPT_GENERATED' OR (receipt_code IS NOT NULL AND ledger_posted_at IS NOT NULL))
);

CREATE INDEX idx_business_settlement_status ON business_settlement (payment_status);

COMMENT ON TABLE business_settlement IS
  '[Trace: TBOC-v2.0.0 | Article 43] Settlement is not complete until the ledger is posted and the receipt is generated. No second financial truth (Article 42).';

-- Append-only once RECEIPT_GENERATED (Article 42.4 — corrections occur by governed reversal, never deletion)
CREATE OR REPLACE FUNCTION business_settlement_block_illegal_mutation() RETURNS trigger AS $$
BEGIN
  IF OLD.payment_status = 'RECEIPT_GENERATED'
     AND (NEW.computed_total_fare_kes IS DISTINCT FROM OLD.computed_total_fare_kes
          OR NEW.receipt_code IS DISTINCT FROM OLD.receipt_code) THEN
    RAISE EXCEPTION 'business_settlement: fare and receipt are immutable once RECEIPT_GENERATED; correction requires a governed reversal (Article 42.4)';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_business_settlement_block_illegal_mutation
  BEFORE UPDATE ON business_settlement
  FOR EACH ROW EXECUTE FUNCTION business_settlement_block_illegal_mutation();

ALTER TABLE business_settlement ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_settlement_requester_read ON business_settlement
  FOR SELECT TO trustride_authenticated
  USING (EXISTS (
    SELECT 1 FROM business_order o
    WHERE o.order_id = business_settlement.order_id
      AND o.requester_user_id = current_setting('app.current_user_id', true)::uuid
  ));
CREATE POLICY business_settlement_service_write ON business_settlement
  FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);
```

## 2.10 `business_review` — Review / Rate / Support

```sql
-- [Trace: TBOC-v2.0.0 | Article 19 Stage 6 | Review / Rate / Support]
CREATE TABLE business_review (
  review_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id              UUID NOT NULL REFERENCES business_order (order_id),
  reviewer_user_id      UUID NOT NULL,               -- reference only
  reviewee_user_id      UUID NOT NULL,               -- reference only; bi-directional (Article 51)
  rating                SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment               TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_business_review_order ON business_review (order_id);
CREATE INDEX idx_business_review_reviewee ON business_review (reviewee_user_id);

COMMENT ON TABLE business_review IS
  '[Trace: TBOC-v2.0.0 | Article 19 Stage 6, Article 51] Bi-directional — the requester rates the resource and the resource rates the requester, each as a separate row against the same Order.';

ALTER TABLE business_review ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_review_participant_read ON business_review
  FOR SELECT TO trustride_authenticated
  USING (reviewer_user_id = current_setting('app.current_user_id', true)::uuid
         OR reviewee_user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY business_review_service_write ON business_review
  FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);
```

## 2.11 Engine Event Substrate (Constitutional Mandatory Tables)

Per Plate I (Station Law) and CC-03 of the platform Conformance Certificate, every engine — Engine 4 included — carries exactly one outbox and one inbox, in the standard signal envelope shape (FDN-001 §11.2).

```sql
-- [Trace: TBOC-v2.0.0 | Article 59-60 — mandatory per-engine ledger tables]
CREATE TABLE business_event_outbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG004_BUS',
  receiving_engine       TEXT NOT NULL,
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  signal_status               TEXT NOT NULL DEFAULT 'PENDING'
                                CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason              TEXT,
  idempotency_key                 TEXT NOT NULL UNIQUE,
  attempt_count                     INTEGER NOT NULL DEFAULT 0,
  emitted_at                         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_business_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_business_outbox_status ON business_event_outbox (signal_status);
CREATE INDEX idx_business_outbox_correlation ON business_event_outbox (correlation_id);

ALTER TABLE business_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_event_outbox_service_only ON business_event_outbox
  FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);

-- [Trace: TBOC-v2.0.0 | Article 59-60 — mandatory per-engine ledger tables]
CREATE TABLE business_event_inbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL,
  receiving_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG004_BUS',
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  payload_out                JSONB,
  signal_status                TEXT NOT NULL DEFAULT 'RECEIVED'
                                 CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason               TEXT,
  idempotency_key                  TEXT NOT NULL UNIQUE,
  received_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at                          TIMESTAMPTZ,
  CONSTRAINT chk_business_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_business_inbox_status ON business_event_inbox (signal_status);
CREATE INDEX idx_business_inbox_correlation ON business_event_inbox (correlation_id);

ALTER TABLE business_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_event_inbox_service_only ON business_event_inbox
  FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);
```

---

# SECTION 3 — SYSTEM API CONTRACTS & WORKFLOW ORCHESTRATION

All endpoints are fronted by Engine 4's own signal envelope (§4); the HTTP contracts below are the Integration-layer (Engine 6) surface that Presentation (Engine 11) calls, which Engine 6 then translates into the constitutional emit → orchestrate → respond pattern before Engine 4 ever sees the request.

## 3.1 `POST /api/v1/orders`

**Request**

```json
{
  "correlation_id": "8f14e45f-ceea-4c9c-9c60-1a2f3e4d5b6c",
  "requester_user_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "service_code": "TRANSPORT-STANDARD-RIDE",
  "order_lines": [
    { "line_description": "Passenger transport, CBD to Kondele", "quantity": 1,
      "scope_detail": { "origin": "KSM-CBD-01", "destination": "KSM-KONDELE-03" } }
  ]
}
```

**Response — `201 Created`**

```json
{
  "correlation_id": "8f14e45f-ceea-4c9c-9c60-1a2f3e4d5b6c",
  "order_id": "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e",
  "order_code": "TRS026-ORDER-000004821",
  "order_stage": "ORDER_PLACEMENT_SCOPE",
  "status": "PLACED"
}
```

## 3.2 `POST /api/v1/orders/{order_id}/accept`

**Request** (path parameter `order_id`; body confirms acceptance of the posted fee and ETA per Article 20.5.4)

```json
{
  "correlation_id": "8f14e45f-ceea-4c9c-9c60-1a2f3e4d5b6c",
  "quote_id": "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e"
}
```

**Response — `200 OK`**

```json
{
  "correlation_id": "8f14e45f-ceea-4c9c-9c60-1a2f3e4d5b6c",
  "order_id": "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e",
  "job_id": "c3d4e5f6-a7b8-4c9d-0e1f-2a3b4c5d6e7f",
  "order_stage": "ASSIGNMENT_VALIDATION_JOB_CREATION",
  "status": "JOB_CREATED"
}
```

## 3.3 `GET /api/v1/orders/{order_id}/tracking`

**Request** (path parameter `order_id`)

**Response — `200 OK`**

```json
{
  "order_id": "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e",
  "resource_type": "BODA_BODA",
  "resource_id_display": "Rider: J. Otieno · KMEA 245X",
  "eta": "2026-08-16T09:14:00Z",
  "tracking_status": "EN_ROUTE",
  "exact_location": { "latitude": -0.089500, "longitude": 34.771200 }
}
```

## 3.4 `GET /api/v1/orders/{order_id}/settlement`

**Request** (path parameter `order_id`)

**Response — `200 OK`**

```json
{
  "order_id": "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e",
  "computed_total_fare_kes": 181.09,
  "currency": "KES",
  "payment_rail": "MPESA_C2B_STK",
  "payment_status": "RECEIPT_GENERATED",
  "receipt_code": "TRS026-RECEIPT-000104211",
  "receipt_generated_at": "2026-08-16T09:22:10Z"
}
```

---

# SECTION 4 — EVENT-DRIVEN SIGNAL & INTEGRATION MATRIX

Every signal below travels the constitutional shape (Plate I): `business_event_outbox` → Engines 7/8 (Orchestration + Coordination) → target engine's inbox, or the reverse into `business_event_inbox`. Engine 4 never emits to, or receives directly from, another engine's outbox/inbox.

## 4.1 Inbound Signals — Listened To

| Signal | Emitting engine | Payload (key fields) | Effect inside Engine 4 |
| --- | --- | --- | --- |
| `SERVICE_RESOLVED` | Engine 3 (Services), via Engines 7/8 | `service_id`, `macro_domain`, `eligibility`, `coverage_confirmed` | Confirms the catalogue selection at Order placement (Article 19, Stage 1) |
| `RESOURCE_RESERVED` | Engine 2 (Resources), via Engines 7/8 | `order_id`, `workforce_unit_id`, `reserved_until` | Advances `order_stage` toward `ASSIGNMENT_VALIDATION_JOB_CREATION` |
| `RESOURCE_ASSIGNED` | Engine 2 (Resources), via Engines 7/8 | `order_id`, `workforce_unit_id`, `capacity_class` | Creates the `business_job` row and transitions `business_order.status` to `JOB_CREATED` |
| `UNIT_PRICE_LOCKED` | Engine 5 (Cost), via Engines 7/8 | `quote_id`, `computed_total_fare_kes`, `expires_at` | Posts the fee and ETA back to the requester before acceptance (Article 20.5.4); populates `business_order.quote_id` |
| `PAYMENT_SETTLED` | Engine 6 (Integration), via Engines 7/8 | `order_id`, `settlement_reference`, `settled_at` | Transitions `business_settlement.payment_status` to `SETTLED`, posts the ledger, and requests a receipt number from `sequence_generator` |
| `MARKETPLACE_LISTING_SOLD` | Engine 3 (Services), via Engines 7/8 | `listing_id`, `list_price_kes` | Initiates settlement for a Marketplace Order under the same Article 43 sequence |

## 4.2 Outbound Signals — Emitted

| Signal | Receiving engine | Payload (key fields) | Triggering condition |
| --- | --- | --- | --- |
| `SERVICE_LOOKUP_REQUESTED` | Engine 3 (Services), via Engines 7/8 | `service_code`, `jurisdiction` | Fired at Order placement, before scope is confirmed (Article 19, Stage 1) |
| `ASSIGNMENT_REQUESTED` | Engine 2 (Resources), via Engines 7/8 | `order_id`, `macro_domain`, `required_capacity_class`, `pickup_location` | Fired once the Order and its Order Lines are validated — the Article 20.2 sub-sequence opening move |
| `ORDER_PLACED` | Broadcast — Engine 9 (AI/ML Advisory) and Engine 11 (Presentation), via Engines 7/8 | `order_id`, `order_code`, `service_code`, `placed_at` | Fired the instant a `business_order` row is created |
| `JOB_COMPLETED` | Engine 2 (Resources), via Engines 7/8 | `job_id`, `workforce_unit_id`, `completed_at` | Fired when `business_job.status` reaches `VERIFIED` — restores resource availability (Article 19, Stage 7) |
| `ORDER_SETTLED` | Broadcast — Engine 9 (AI/ML Advisory), Engine 11 (Presentation), via Engines 7/8 | `order_id`, `computed_total_fare_kes`, `receipt_code` | Fired when `business_settlement.payment_status` reaches `RECEIPT_GENERATED` |

## 4.3 The Signal Envelope (as applied to Engine 4)

Identical to the platform-wide envelope (Plate I, §11.2 of the Foundation instrument): `signal_id`, `correlation_id`, `causation_id`, `emitting_engine` = `TRS026_ENG004_BUS`, `receiving_engine`, `signal_type`, `payload_in`, `payload_out`, `signal_status`, `rejection_reason`, `idempotency_key`, `attempt_count`, `emitted_at`, `received_at`, `accepted_at`. No field is added, renamed, or omitted — an engine that invents its own envelope shape is non-conformant.

---

# ANNEX — CONFORMANCE SELF-CERTIFICATION AGAINST THE THREE PLATES

Filed in the same discipline as the Foundation instrument's Part XI and the Engine 2/Engine 3/Engine 5 Annexes, so that Engine 4 can be certified on the same footing as its sibling engines.

| Check | Requirement | Result | Evidence |
| --- | --- | --- | --- |
| CC-02 | Every table assigned to exactly one of the five stations | **PASS** | §2.1–2.11: domain tables = Domain State; `business_event_outbox` = Emission Ledger; `business_event_inbox` = Reception Ledger; mutation only via the engine's own accept-handler |
| CC-03 | Engine carries the four ledger tables with the standard envelope | **PASS** | §2.11, §4.3 |
| CC-04 | Every cross-engine interaction is a signal; no foreign table access | **PASS** | §1.3, §4 — every interface listed is a named signal; `service_id`, `quote_id`, and `workforce_unit_id` are by value, never a foreign key into another engine's schema |
| CC-06 | Idempotency, retry, dead-letter declared | **PASS** | `idempotency_key` UNIQUE on both ledger tables (§2.11) |
| CC-07 | Engine declares its layer, holds nothing belonging to another layer | **PASS** | §1 — Layer 2, Business Runtime; holds no identity, resource-availability, catalogue, or pricing-computation state |
| CC-09 | Advisory outputs, if any, are records only | **N/A** | Engine 4 is not an advisory engine; it is a Layer 2 runtime engine |
| CC-12 | Every provision carries a trace tag | **PASS** | Every DDL block and table comment carries a `[Trace: TBOC-v2.0.0 | Article ...]` tag |
| Money Law | Every KES-denominated column is `NUMERIC(18,2)` | **PASS** | `lifetime_value_kes` (§2.2), `computed_total_fare_kes` (§2.9) |
| RLS Law | Row-Level Security enabled on every table | **PASS** | All twelve tables (§2.1–2.11 — §2.11 carries two: `business_event_outbox` and `business_event_inbox`) carry `ENABLE ROW LEVEL SECURITY` with an explicit policy |
| Article 19 | No Order may skip, reorder, or bypass a lifecycle stage | **PASS** | `business_order_stage_enum` (§2.0) enumerates exactly the seven stages, in order; `business_order.order_stage` is the single field of record |

---

**END OF SPECIFICATION**

*Engine 4 is where TrustRide's word becomes binding. One Order, seven stages, one ledger of record — the commercial truth beneath every service the platform delivers.*
