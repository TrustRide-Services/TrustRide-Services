# TRUSTRIDE SERVICES

# ENGINE 3 — SERVICES ENGINE
## Complete Architectural, Data, API, and Signal Specification

**[Parent Authority: TBOC v2.0.0 Genesis Edition · Architecture Blueprint v1.1.0]**

*More than a Ride — We Save You Time.*

## Document Control

| Document Control Field | Entry |
| --- | --- |
| Document Title | Engine 3 — Services Engine: Complete Specification |
| Document Identifier | TRS026-ENG003-SERV-001 |
| Version | 1.0.1 |
| Status | **ADOPTED** (2026-08-16, per Founder directive — build order FDN → Resources → Services → Business) |
| Remediation | v1.0.1 corrects `service_pillar`'s Executive-Assistants subordination rule, which PostgreSQL cannot execute as written (a subquery inside a `CHECK` constraint is not permitted); replaced with a deferred constraint trigger (§2.3). Cross-checked against the now-finalized FDN-001 v3.0.0 Annex H DDL compilation and the remediated Engine 2 for alignment — no other deviation found |
| Classification | Institutional Blueprint — Confidential |
| Schema | `trustride` (single canonical PostgreSQL schema; this engine's tables are prefixed `service_`) |
| Platform Code | TRS026 |
| Engine Code | `TRS026_ENG003_SERV` |
| Engine No. | `ENGINE_003` |
| Installation Order | 003 |
| Parent Authority | TBOC v2.0.0 Genesis Edition — Article 15 (The Service Primitive), Article 18 (Catalogue-Driven Special Intents), Article 23 (The Five Domains), Article 24–28 (Transport, Courier, Delivery, Executive Assistants, Marketplace), Article 29 (Domain Integrity) |
| Architecture Lineage | Positioned as Engine 3 in the eleven-engine Constitutional Engine Registry (Annex C, FDN-001 v3.0.0); Layer 2 Business Runtime of the Backend/Frontend/Event-Signal Architecture Blueprint v1.1.0 |

## Document Purpose & Constitutional Basis

This instrument specifies **Engine 3 — the Services Engine**, TrustRide's authoritative catalogue of everything the platform may lawfully offer. It answers one constitutional question for the rest of the platform — **is this a registered Service, and under what terms may it be requested?**

TBOC does not permit a technical document to invent business concepts (Article 8, the Zero-Pollution Rule). Every mechanical rule in this document therefore traces to a standing TBOC provision:

| This engine's function | TBOC basis |
| --- | --- |
| Everything TrustRide offers is a Service, catalogued with definition, eligibility, requirements, pricing rules, availability, coverage, and lifecycle | Article 15 — The Service Primitive |
| No capability may be offered, promised, or delivered that is not a registered Service | Article 15 |
| Special intents (Academy, employment, vendor onboarding, resource contribution, Own Marketplace) always resolve through a catalogue Service | Article 18 — Catalogue-Driven Special Intents |
| Exactly five macro domains; no sixth without constitutional amendment | Article 23 — The Five Domains |
| Transport, Courier, Delivery, Executive Assistants, Marketplace — purpose, resources, business rules, experience | Article 24–28 |
| The six Executive Assistants pillars and their named service lines, never elevated to independent macro domains | Article 27.2.1 |
| Cross-domain Orders are composed of catalogue Services; domain-specific rules bind before assignment eligibility | Article 29 — Domain Integrity |
| No engine reads or writes another engine's tables; cross-engine truth moves only as a signal | Article 33 |

This engine owns the *definition* of what may be sold and under what conditions. It never owns a customer's request for it — that is Engine 4 (Business)'s Order. It never owns who or what fulfils it — that is Engine 2 (Resources)'s deployable capacity. Engine 3 is the contract between the two: the governed shelf from which Business selects, and against which Resources' eligibility is checked.

---

# SECTION 1 — ARCHITECTURAL ROLE & BOUNDARIES

## 1.1 Mission

Engine 3 is the platform's single, deterministic authority for the Service Catalogue — every macro domain, pillar, named service line, special intent, eligibility rule, coverage zone, and marketplace listing TrustRide may lawfully offer. No Order may reference a Service this engine has not registered as `ACTIVE`.

## 1.2 Operational Duties

1. **Macro domain custody.** Maintain `service_macro_domain` as the constitutional source of the five domains (Article 23) — Transport, Courier, Delivery, Executive Assistants, Marketplace. No sixth domain may be inserted without a constitutional amendment upstream in TBOC.
2. **Catalogue registration.** Maintain `service_catalogue` per Article 15 — every Service's definition, eligibility, requirements, coverage, and lifecycle status.
3. **Pillar and service-line custody.** Maintain `service_pillar` and `service_line` per Article 27 — the six Executive Assistants pillars (Errands, Driving, Caregiving, Cleaning, Chef, Shopping) and their named service lines (School Visitation, Student Pickup, Shopping Representation & Shopping Deliveries), each a micro-structure beneath its macro domain, never elevated above it.
4. **Special-intent resolution.** Maintain `service_special_intent` per Article 18 — Academy/training, employment application, vendor onboarding, resource contribution, and Own Marketplace acquisition/refurbishment/listing/sale intents, each resolving to a catalogue Service.
5. **Eligibility governance.** Maintain `service_eligibility_rule` per Article 29 — which capacity class, vetting tier, and certification a resource must hold before it may fulfil a Service, evaluated before assignment.
6. **Coverage governance.** Maintain `service_coverage_zone` — the jurisdictions in which a Service is lawfully offered.
7. **Marketplace listing custody.** Maintain `service_marketplace_listing` per Article 28 — both vendor-facilitated listings (Article 28.1) and TrustRide's Own Marketplace listings (Article 28.2), the sellable catalogue entry distinct from Resources' physical custody of the underlying item.
8. **Catalogue resolution.** Answer Business's `SERVICE_LOOKUP_REQUESTED` signal at Order placement (Article 19, Stage 1 — "Service selected from the catalogue") with the full resolved Service context.

## 1.3 Interfaces with the Other Ten Engines

Per Plate I of the Backend Architecture and the Event/Signal Architecture, Engine 3 **never** calls another engine directly. Every interface below is a signal, carried through Engines 7/8 (Workflow Orchestration & Coordination) — the Sovereign Processing Unit.

| Engine | Direction | What crosses the boundary |
| --- | --- | --- |
| **Engine 1 — Foundation** | Inbound (by reference) | `person_user_id` identity references only (e.g. a marketplace vendor); this engine never reads or writes `platform_users` directly |
| **Engine 2 — Resources** | Outbound (by value, never FK) | `required_capacity_class_code` on every `service_eligibility_rule` row is a value copied from Resources' capacity-class vocabulary, never a foreign key into Resources' tables |
| **Engine 4 — Business** | Bidirectional | Inbound: `SERVICE_LOOKUP_REQUESTED` at Order placement (Article 19, Stage 1). Outbound: `SERVICE_RESOLVED`, carrying the full catalogue context — eligibility, coverage, safeguarding tier — back to Business |
| **Engine 5 — Cost** | Outbound (via signal) | `SERVICE_CONTEXT_RESOLVED`, carrying `macro_domain` and `service_code` — the exact context Cost's own specification (§1.3) names as its inbound Engine 3 interface, used to select the applicable `cost_rate_card_rule` |
| **Engine 6 — Integration** | Inbound (via signal) | `VENDOR_VERIFICATION_UPDATED` — marketplace vendor KYC/commercial-agreement verification results ingested from the external-system boundary, gating `service_marketplace_listing` eligibility |
| **Engines 7/8 — Workflow Orchestration & Coordination** | Structural | The exclusive transport for every signal in and out of Engine 3's outbox/inbox |
| **Engine 9 — AI/ML Advisory** | Outbound (read-only) | Advisory reads `service_catalogue` and historical listing/lookup volume as lawful projections for service-mix and demand-pattern recommendations; it never writes back |

## 1.4 Boundaries — What Engine 3 Never Does

1. **Never places an Order.** Order placement, scope, Order Lines, and settlement remain Engine 4's exclusive domain.
2. **Never assigns a resource.** Whether a specific rider, vehicle, or Executive Assistant is available and dispatched is Engine 2's exclusive domain — this engine only states what a Service *requires*.
3. **Never computes a fare.** Engine 3 hands Cost (Engine 5) the resolved macro domain and service code; it never touches `cost_unit_price_quotes` or any pricing table.
4. **Never holds custody.** `service_marketplace_listing` references an inventory item by value; the physical custody, condition, and lifecycle of that item remain Engine 2's `resource_marketplace_inventory`.
5. **Never invents a sixth domain.** No Service may be catalogued outside the five macro domains and the authorized special intents (Article 29.1) without an upstream constitutional amendment to TBOC Article 23.
6. **Never elevates a pillar.** The Executive Assistants pillars and their named service lines are permanently subordinate to the Executive Assistants macro domain (Article 27.2.1); this engine enforces that subordination structurally, never as a convention only.

---

# SECTION 2 — PRODUCTION SQL DDL SCHEMA (PostgreSQL / Supabase-Ready)

## 2.0 Extensions & Enums (prerequisite)

```sql
-- Extensions (idempotent; already present platform-wide per Engine 001 Phase 0)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- [Trace: TBOC-v2.0.0 | Article 23 | The Five Domains — exactly five, no sixth without amendment]
CREATE TYPE service_macro_domain_enum AS ENUM (
  'TRANSPORT', 'COURIER', 'DELIVERY', 'EXECUTIVE_ASSISTANTS', 'MARKETPLACE'
);

CREATE TYPE service_status_enum AS ENUM (
  'DRAFT', 'ACTIVE', 'SUSPENDED', 'RETIRED'
);

-- [Trace: TBOC-v2.0.0 | Article 27 | The six Executive Assistants pillars, verbatim]
CREATE TYPE service_pillar_code_enum AS ENUM (
  'ERRANDS', 'DRIVING', 'CAREGIVING', 'CLEANING', 'CHEF', 'SHOPPING'
);

CREATE TYPE service_safeguarding_tier_enum AS ENUM (
  'STANDARD', 'ENHANCED'
);

-- [Trace: TBOC-v2.0.0 | Article 18 | Catalogue-Driven Special Intents]
CREATE TYPE service_special_intent_code_enum AS ENUM (
  'ACADEMY_TRAINING', 'EMPLOYMENT_APPLICATION', 'VENDOR_ONBOARDING',
  'RESOURCE_CONTRIBUTION', 'MARKETPLACE_ACQUISITION', 'MARKETPLACE_REFURBISHMENT',
  'MARKETPLACE_LISTING', 'MARKETPLACE_SALE'
);

-- [Trace: TBOC-v2.0.0 | Article 28 | Marketplace — the two lawful modes]
CREATE TYPE service_listing_type_enum AS ENUM (
  'VENDOR_FACILITATED', 'OWN_MARKETPLACE'
);

CREATE TYPE service_listing_status_enum AS ENUM (
  'DRAFT', 'LISTED', 'RESERVED', 'SOLD', 'DELISTED'
);
```

## 2.1 `service_macro_domain` — The Five Domains

```sql
-- [Trace: TBOC-v2.0.0 | Article 23 | The Five Domains]
CREATE TABLE service_macro_domain (
  macro_domain_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  domain_code         service_macro_domain_enum NOT NULL UNIQUE,
  domain_label        TEXT NOT NULL,
  domain_purpose      TEXT NOT NULL,
  active              BOOLEAN NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE service_macro_domain IS
  '[Trace: TBOC-v2.0.0 | Article 23] The constitutional source of the five macro domains; no sixth row may be inserted without an upstream TBOC amendment.';

ALTER TABLE service_macro_domain ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_macro_domain_platform_read ON service_macro_domain
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY service_macro_domain_service_write ON service_macro_domain
  FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);

INSERT INTO service_macro_domain (domain_code, domain_label, domain_purpose) VALUES
  ('TRANSPORT', 'Transport', 'Safe, tracked, professionally delivered movement of people (Article 24).'),
  ('COURIER', 'Courier', 'Fast, accountable movement of documents and parcels with chain of custody (Article 25).'),
  ('DELIVERY', 'Delivery', 'Reliable movement of goods from origin to recipient, including merchant-originated orders (Article 26).'),
  ('EXECUTIVE_ASSISTANTS', 'Executive Assistants', 'Human assistance services across six pillars: Errands, Driving, Caregiving, Cleaning, Chef, Shopping (Article 27).'),
  ('MARKETPLACE', 'Marketplace', 'Vendor-facilitated and TrustRide Own Marketplace trade (Article 28).');
```

## 2.2 `service_catalogue` — The Service Primitive

```sql
-- [Trace: TBOC-v2.0.0 | Article 15 | The Service Primitive]
CREATE TABLE service_catalogue (
  service_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_code         TEXT NOT NULL UNIQUE,
  service_name         TEXT NOT NULL,
  macro_domain_id      UUID NOT NULL REFERENCES service_macro_domain (macro_domain_id),
  description          TEXT NOT NULL,
  eligibility_rules_summary TEXT,               -- human-legible summary; the governed rules live in service_eligibility_rule
  requirements         JSONB NOT NULL DEFAULT '{}',
  status               service_status_enum NOT NULL DEFAULT 'DRAFT',
  approved_request_id  UUID,                     -- reference into TRS_FDN_GOVERNANCE.approval_request
  effective_from       TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to         TIMESTAMPTZ,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_service_catalogue_validity CHECK (effective_to IS NULL OR effective_to > effective_from)
);

CREATE INDEX idx_service_catalogue_domain ON service_catalogue (macro_domain_id) WHERE status = 'ACTIVE';
CREATE UNIQUE INDEX uq_service_catalogue_code_active ON service_catalogue (service_code) WHERE status = 'ACTIVE';

COMMENT ON TABLE service_catalogue IS
  '[Trace: TBOC-v2.0.0 | Article 15] No capability may be offered, promised, or delivered that is not a registered ACTIVE row here.';

ALTER TABLE service_catalogue ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_catalogue_platform_read ON service_catalogue
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY service_catalogue_service_write ON service_catalogue
  FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);
```

## 2.3 `service_pillar` — The Executive Assistants Pillars

```sql
-- [Trace: TBOC-v2.0.0 | Article 27 | Executive Assistants — six pillars, never elevated to independent macro domains]
CREATE TABLE service_pillar (
  pillar_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pillar_code          service_pillar_code_enum NOT NULL UNIQUE,
  macro_domain_id       UUID NOT NULL REFERENCES service_macro_domain (macro_domain_id),
  pillar_label            TEXT NOT NULL,
  description                TEXT NOT NULL,
  active                        BOOLEAN NOT NULL DEFAULT TRUE,
  created_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE service_pillar IS
  '[Trace: TBOC-v2.0.0 | Article 27.2.1] Structurally bound beneath Executive Assistants; enforced by a deferred constraint trigger, it is not a convention only.';

ALTER TABLE service_pillar ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_pillar_platform_read ON service_pillar
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY service_pillar_service_write ON service_pillar
  FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);

-- PostgreSQL forbids subqueries inside CHECK constraints; the structural subordination
-- rule (every pillar must bind to the Executive Assistants macro domain, never any other)
-- is therefore enforced as a deferred constraint trigger.
CREATE OR REPLACE FUNCTION service_pillar_domain_ea()
RETURNS trigger AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM service_macro_domain
    WHERE macro_domain_id = NEW.macro_domain_id AND domain_code = 'EXECUTIVE_ASSISTANTS'
  ) THEN
    RAISE EXCEPTION 'service_pillar % must bind to the EXECUTIVE_ASSISTANTS macro domain, got macro_domain_id %',
      NEW.pillar_code, NEW.macro_domain_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_service_pillar_domain_ea
  AFTER INSERT OR UPDATE ON service_pillar
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION service_pillar_domain_ea();

INSERT INTO service_pillar (pillar_code, macro_domain_id, pillar_label, description)
SELECT v.pillar_code::service_pillar_code_enum, d.macro_domain_id, v.pillar_label, v.description
FROM (VALUES
  ('ERRANDS', 'Errands', 'Office, banking, government, and personal errands executed on behalf of the requester.'),
  ('DRIVING', 'Driving', 'Personal and executive driving support, including chauffeur-style assignments.'),
  ('CAREGIVING', 'Caregiving', 'Vetted care support for children, the elderly, and vulnerable persons.'),
  ('CLEANING', 'Cleaning', 'Professional residential and commercial cleaning support.'),
  ('CHEF', 'Chef', 'Meal preparation and culinary support services.'),
  ('SHOPPING', 'Shopping', 'Personal shopping and procurement assistance.')
) AS v(pillar_code, pillar_label, description)
JOIN service_macro_domain d ON d.domain_code = 'EXECUTIVE_ASSISTANTS';
```

## 2.4 `service_line` — Named Service Lines

```sql
-- [Trace: TBOC-v2.0.0 | Article 27.1 | Named service lines within the Executive Assistants pillars]
CREATE TABLE service_line (
  service_line_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pillar_id              UUID NOT NULL REFERENCES service_pillar (pillar_id),
  line_code                TEXT NOT NULL UNIQUE,
  line_name                  TEXT NOT NULL,
  description                  TEXT NOT NULL,
  safeguarding_tier              service_safeguarding_tier_enum NOT NULL DEFAULT 'STANDARD',
  guardian_authorization_required  BOOLEAN NOT NULL DEFAULT FALSE,
  active                              BOOLEAN NOT NULL DEFAULT TRUE,
  created_at                            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_service_line_pillar ON service_line (pillar_id) WHERE active = TRUE;

COMMENT ON TABLE service_line IS
  '[Trace: TBOC-v2.0.0 | Article 27.1, 27.2.3] Child-facing lines (Student Pickup) carry ENHANCED safeguarding_tier and mandatory guardian authorization.';

ALTER TABLE service_line ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_line_platform_read ON service_line
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY service_line_service_write ON service_line
  FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);

INSERT INTO service_line (pillar_id, line_code, line_name, description, safeguarding_tier, guardian_authorization_required)
SELECT p.pillar_id, v.line_code, v.line_name, v.description, v.tier::service_safeguarding_tier_enum, v.guardian_req
FROM (VALUES
  ('ERRANDS', 'SCHOOL_VISITATION', 'School Visitation', 'Delegated school visits: delivery of fees, materials, and documents; representation at school appointments; check-ins on students.', 'ENHANCED', TRUE),
  ('DRIVING', 'STUDENT_PICKUP', 'Student Pickup', 'School runs: picking up students by motorcycle or car after closing and returning them to school, under guardian authorization.', 'ENHANCED', TRUE),
  ('SHOPPING', 'SHOPPING_REPRESENTATION_DELIVERY', 'Shopping Representation & Shopping Deliveries', 'Shopping executed on behalf of the requester and delivery of the purchased goods to the requester''s destination.', 'STANDARD', FALSE)
) AS v(pillar_code, line_code, line_name, description, tier, guardian_req)
JOIN service_pillar p ON p.pillar_code = v.pillar_code::service_pillar_code_enum;
```

## 2.5 `service_special_intent` — Catalogue-Driven Special Intents

```sql
-- [Trace: TBOC-v2.0.0 | Article 18 | Catalogue-Driven Special Intents]
CREATE TABLE service_special_intent (
  special_intent_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  intent_code             service_special_intent_code_enum NOT NULL UNIQUE,
  intent_label              TEXT NOT NULL,
  resolves_to_service_id      UUID NOT NULL REFERENCES service_catalogue (service_id),
  description                    TEXT NOT NULL,
  active                            BOOLEAN NOT NULL DEFAULT TRUE,
  created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE service_special_intent IS
  '[Trace: TBOC-v2.0.0 | Article 18] In every case the intent selects a catalogue Service; scope is described in the resulting Order''s Order Lines (Engine 4).';

ALTER TABLE service_special_intent ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_special_intent_platform_read ON service_special_intent
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY service_special_intent_service_write ON service_special_intent
  FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);
```

## 2.6 `service_eligibility_rule` — Assignment Eligibility

```sql
-- [Trace: TBOC-v2.0.0 | Article 29 | Domain-specific rules bind before assignment eligibility]
CREATE TABLE service_eligibility_rule (
  eligibility_rule_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id                  UUID NOT NULL REFERENCES service_catalogue (service_id),
  required_capacity_class_code  TEXT NOT NULL,     -- value copied from Engine 2's capacity-class vocabulary; never a foreign key
  required_vetting_tier           TEXT NOT NULL DEFAULT 'STANDARD',
  required_certifications           JSONB NOT NULL DEFAULT '[]',
  active                                BOOLEAN NOT NULL DEFAULT TRUE,
  created_at                              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_service_eligibility_service ON service_eligibility_rule (service_id) WHERE active = TRUE;

COMMENT ON TABLE service_eligibility_rule IS
  '[Trace: TBOC-v2.0.0 | Article 29] Evaluated by Engine 2 at resource discovery time; a resource lacking the required capacity class, vetting tier, or certification is excluded from candidacy.';

ALTER TABLE service_eligibility_rule ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_eligibility_rule_platform_read ON service_eligibility_rule
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY service_eligibility_rule_service_write ON service_eligibility_rule
  FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);
```

## 2.7 `service_coverage_zone` — Coverage Governance

```sql
-- [Trace: TBOC-v2.0.0 | Article 15 | Coverage area is a constitutional element of every Service]
CREATE TABLE service_coverage_zone (
  coverage_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id           UUID NOT NULL REFERENCES service_catalogue (service_id),
  jurisdiction          TEXT NOT NULL,             -- county/administrative reference, by value
  active                   BOOLEAN NOT NULL DEFAULT TRUE,
  effective_from             TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to                 TIMESTAMPTZ,
  created_at                     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_service_coverage_validity CHECK (effective_to IS NULL OR effective_to > effective_from)
);

CREATE INDEX idx_service_coverage_service_jurisdiction ON service_coverage_zone (service_id, jurisdiction) WHERE active = TRUE;

COMMENT ON TABLE service_coverage_zone IS
  '[Trace: TBOC-v2.0.0 | Article 15] A Service not covered in the requester''s jurisdiction is not offered there, regardless of catalogue status.';

ALTER TABLE service_coverage_zone ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_coverage_zone_platform_read ON service_coverage_zone
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY service_coverage_zone_service_write ON service_coverage_zone
  FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);
```

## 2.8 `service_marketplace_listing` — The Sellable Catalogue Entry

```sql
-- [Trace: TBOC-v2.0.0 | Article 28 | Marketplace — the two lawful modes]
CREATE TABLE service_marketplace_listing (
  listing_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id             UUID NOT NULL REFERENCES service_catalogue (service_id),
  listing_type             service_listing_type_enum NOT NULL,
  vendor_user_id              UUID,                 -- NULL for OWN_MARKETPLACE; by value, Partners per Article 12.7 for VENDOR_FACILITATED
  inventory_item_id              UUID,               -- by value reference to Engine 2's resource_marketplace_inventory, for OWN_MARKETPLACE only
  title                             TEXT NOT NULL,
  description                        TEXT NOT NULL,
  list_price_kes                       NUMERIC(18,2) NOT NULL CHECK (list_price_kes >= 0),
  listing_status                         service_listing_status_enum NOT NULL DEFAULT 'DRAFT',
  listed_at                                TIMESTAMPTZ,
  delisted_at                                TIMESTAMPTZ,
  created_at                                   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_service_listing_type_reference
    CHECK (
      (listing_type = 'OWN_MARKETPLACE' AND inventory_item_id IS NOT NULL AND vendor_user_id IS NULL)
      OR
      (listing_type = 'VENDOR_FACILITATED' AND vendor_user_id IS NOT NULL AND inventory_item_id IS NULL)
    )
);

CREATE INDEX idx_service_listing_status ON service_marketplace_listing (listing_status);
CREATE INDEX idx_service_listing_vendor ON service_marketplace_listing (vendor_user_id) WHERE vendor_user_id IS NOT NULL;

COMMENT ON TABLE service_marketplace_listing IS
  '[Trace: TBOC-v2.0.0 | Article 28.1, 28.2] The sellable catalogue entry; physical custody of an Own Marketplace item remains Engine 2''s resource_marketplace_inventory throughout.';

ALTER TABLE service_marketplace_listing ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_marketplace_listing_platform_read ON service_marketplace_listing
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY service_marketplace_listing_service_write ON service_marketplace_listing
  FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);
```

## 2.9 Engine Event Substrate (Constitutional Mandatory Tables)

Per Plate I (Station Law) and CC-03 of the platform Conformance Certificate, every engine — Engine 3 included — carries exactly one outbox and one inbox, in the standard signal envelope shape (FDN-001 §11.2).

```sql
-- [Trace: TBOC-v2.0.0 | Article 59-60 — mandatory per-engine ledger tables]
CREATE TABLE service_event_outbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG003_SERV',
  receiving_engine       TEXT NOT NULL,
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  signal_status               TEXT NOT NULL DEFAULT 'PENDING'
                                CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason              TEXT,
  idempotency_key                 TEXT NOT NULL UNIQUE,
  attempt_count                     INTEGER NOT NULL DEFAULT 0,
  emitted_at                         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_service_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_service_outbox_status ON service_event_outbox (signal_status);
CREATE INDEX idx_service_outbox_correlation ON service_event_outbox (correlation_id);

ALTER TABLE service_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_event_outbox_service_only ON service_event_outbox
  FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);

-- [Trace: TBOC-v2.0.0 | Article 59-60 — mandatory per-engine ledger tables]
CREATE TABLE service_event_inbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL,
  receiving_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG003_SERV',
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  payload_out                JSONB,
  signal_status                TEXT NOT NULL DEFAULT 'RECEIVED'
                                 CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason               TEXT,
  idempotency_key                  TEXT NOT NULL UNIQUE,
  received_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at                          TIMESTAMPTZ,
  CONSTRAINT chk_service_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_service_inbox_status ON service_event_inbox (signal_status);
CREATE INDEX idx_service_inbox_correlation ON service_event_inbox (correlation_id);

ALTER TABLE service_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_event_inbox_service_only ON service_event_inbox
  FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);
```

---

# SECTION 3 — SYSTEM API CONTRACTS & WORKFLOW ORCHESTRATION

All endpoints are fronted by Engine 3's own signal envelope (§4); the HTTP contracts below are the Integration-layer (Engine 6) surface that Presentation (Engine 11) and Business (Engine 4) call, which Engine 6 then translates into the constitutional emit → orchestrate → respond pattern before Engine 3 ever sees the request.

## 3.1 `GET /api/v1/services/catalogue`

**Request** (query parameters)

```
GET /api/v1/services/catalogue?macro_domain=TRANSPORT&jurisdiction=KISUMU_COUNTY&status=ACTIVE
```

**Response — `200 OK`**

```json
{
  "macro_domain": "TRANSPORT",
  "services": [
    {
      "service_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "service_code": "TRANSPORT-STANDARD-RIDE",
      "service_name": "Standard Ride",
      "status": "ACTIVE",
      "coverage_jurisdictions": ["KISUMU_COUNTY", "VIHIGA_COUNTY"]
    }
  ],
  "generated_at": "2026-08-16T09:00:00Z"
}
```

## 3.2 `POST /api/v1/services/resolve`

**Request**

```json
{
  "correlation_id": "5c6d7e8f-9a0b-4c1d-8e2f-3a4b5c6d7e8f",
  "service_code": "TRANSPORT-STANDARD-RIDE",
  "jurisdiction": "KISUMU_COUNTY"
}
```

**Response — `200 OK`**

```json
{
  "correlation_id": "5c6d7e8f-9a0b-4c1d-8e2f-3a4b5c6d7e8f",
  "service_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "macro_domain": "TRANSPORT",
  "eligibility": {
    "required_capacity_class_code": "BODA_BODA",
    "required_vetting_tier": "STANDARD",
    "required_certifications": []
  },
  "coverage_confirmed": true,
  "safeguarding_tier": null
}
```

**Response — `422 Unprocessable Entity`** (service not covered in the requested jurisdiction)

```json
{
  "correlation_id": "5c6d7e8f-9a0b-4c1d-8e2f-3a4b5c6d7e8f",
  "error_code": "SERVICE_NOT_COVERED",
  "error_message": "service_code=TRANSPORT-STANDARD-RIDE has no active service_coverage_zone row for jurisdiction=UASIN_GISHU_COUNTY."
}
```

## 3.3 `GET /api/v1/services/marketplace/listings`

**Request** (query parameters)

```
GET /api/v1/services/marketplace/listings?listing_type=OWN_MARKETPLACE&status=LISTED
```

**Response — `200 OK`**

```json
{
  "listings": [
    {
      "listing_id": "c4d5e6f7-a8b9-4c0d-9e1f-2a3b4c5d6e7f",
      "listing_type": "OWN_MARKETPLACE",
      "title": "Refurbished 2022 Bajaj Boxer 150cc",
      "list_price_kes": 145000.00,
      "listing_status": "LISTED"
    }
  ],
  "generated_at": "2026-08-16T09:00:00Z"
}
```

---

# SECTION 4 — EVENT-DRIVEN SIGNAL & INTEGRATION MATRIX

Every signal below travels the constitutional shape (Plate I): `service_event_outbox` → Engines 7/8 (Orchestration + Coordination) → target engine's inbox, or the reverse into `service_event_inbox`. Engine 3 never emits to, or receives directly from, another engine's outbox/inbox.

## 4.1 Inbound Signals — Listened To

| Signal | Emitting engine | Payload (key fields) | Effect inside Engine 3 |
| --- | --- | --- | --- |
| `SERVICE_LOOKUP_REQUESTED` | Engine 4 (Business), via Engines 7/8 | `service_code`, `jurisdiction` | Resolves the catalogue entry, confirms coverage, and returns eligibility — the Article 19 Stage 1 "Service selected from the catalogue" step |
| `VENDOR_VERIFICATION_UPDATED` | Engine 6 (Integration), via Engines 7/8 | `vendor_user_id`, `verification_status`, `verified_at` | Updates the eligibility of every `service_marketplace_listing` row where `vendor_user_id` matches; a vendor falling out of verification has listings transitioned to `DELISTED` |
| `RESOURCE_MARKETPLACE_ITEM_READY` | Engine 2 (Resources), via Engines 7/8 | `inventory_item_id`, `lifecycle_state` | Fired when an Own Marketplace item reaches `COMPLIANT` in Engine 2's Article 40 lifecycle; enables its `service_marketplace_listing` row to transition from `DRAFT` to `LISTED` |

## 4.2 Outbound Signals — Emitted

| Signal | Receiving engine | Payload (key fields) | Triggering condition |
| --- | --- | --- | --- |
| `SERVICE_RESOLVED` | Engine 4 (Business), via Engines 7/8 | `service_id`, `macro_domain`, `eligibility`, `safeguarding_tier`, `coverage_confirmed` | Fired in answer to `SERVICE_LOOKUP_REQUESTED` |
| `SERVICE_CONTEXT_RESOLVED` | Engine 5 (Cost), via Engines 7/8 | `macro_domain`, `service_code` | Fired alongside `SERVICE_RESOLVED`, carrying exactly the context Cost's own specification names as its inbound Engine 3 interface (§1.3 of the Cost Engine specification) |
| `SERVICE_CATALOGUE_UPDATED` | Broadcast — Engine 9 (AI/ML Advisory) and Engine 11 (Presentation), via Engines 7/8 | `service_id`, `status`, `effective_from` | Fired on every catalogue status transition; feeds live catalogue displays and service-mix advisory models |
| `MARKETPLACE_LISTING_SOLD` | Engine 4 (Business) and Engine 2 (Resources), via Engines 7/8 | `listing_id`, `inventory_item_id`, `list_price_kes` | Fired when a `service_marketplace_listing` transitions to `SOLD`; Business initiates settlement, Resources records the custody hand-off |

## 4.3 The Signal Envelope (as applied to Engine 3)

Identical to the platform-wide envelope (Plate I, §11.2 of the Foundation instrument): `signal_id`, `correlation_id`, `causation_id`, `emitting_engine` = `TRS026_ENG003_SERV`, `receiving_engine`, `signal_type`, `payload_in`, `payload_out`, `signal_status`, `rejection_reason`, `idempotency_key`, `attempt_count`, `emitted_at`, `received_at`, `accepted_at`. No field is added, renamed, or omitted — an engine that invents its own envelope shape is non-conformant.

---

# ANNEX — CONFORMANCE SELF-CERTIFICATION AGAINST THE THREE PLATES

Filed in the same discipline as the Foundation instrument's Part XI and the Engine 2/Engine 5 Annexes, so that Engine 3 can be certified on the same footing as its sibling engines.

| Check | Requirement | Result | Evidence |
| --- | --- | --- | --- |
| CC-02 | Every table assigned to exactly one of the five stations | **PASS** | §2.1–2.9: domain tables = Domain State; `service_event_outbox` = Emission Ledger; `service_event_inbox` = Reception Ledger; mutation only via the engine's own accept-handler |
| CC-03 | Engine carries the four ledger tables with the standard envelope | **PASS** | §2.9, §4.3 |
| CC-04 | Every cross-engine interaction is a signal; no foreign table access | **PASS** | §1.3, §4 — every interface listed is a named signal; `required_capacity_class_code` and `vendor_user_id`/`inventory_item_id` are by value, never a foreign key into another engine's schema |
| CC-06 | Idempotency, retry, dead-letter declared | **PASS** | `idempotency_key` UNIQUE on both ledger tables (§2.9) |
| CC-07 | Engine declares its layer, holds nothing belonging to another layer | **PASS** | §1 — Layer 2, Business Runtime; holds no identity, resource-availability, or pricing state |
| CC-09 | Advisory outputs, if any, are records only | **N/A** | Engine 3 is not an advisory engine; it is a Layer 2 runtime engine |
| CC-12 | Every provision carries a trace tag | **PASS** | Every DDL block and table comment carries a `[Trace: TBOC-v2.0.0 | Article ...]` tag |
| Money Law | Every KES-denominated column is `NUMERIC(18,2)` | **PASS** | `list_price_kes` (§2.8) |
| RLS Law | Row-Level Security enabled on every table | **PASS** | All ten tables (§2.1–2.9) carry `ENABLE ROW LEVEL SECURITY` with an explicit policy |
| Domain Integrity | No sixth macro domain; pillars structurally bound to Executive Assistants | **PASS** | `service_macro_domain` seeded with exactly five rows (§2.1); `trg_service_pillar_domain_ea` deferred constraint trigger (§2.3) |

---

**END OF SPECIFICATION**

*Engine 3 is the governed shelf from which every Order is built. Five domains, one catalogue, one eligibility truth per Service — the offer beneath everything TrustRide sells.*
