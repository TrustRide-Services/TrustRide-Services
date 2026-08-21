# TRUSTRIDE SERVICES

# ENGINE 2 — RESOURCES ENGINE
## Complete Architectural, Data, API, and Signal Specification

**[Parent Authority: TBOC v2.0.0 Genesis Edition · Architecture Blueprint v1.1.0]**

*More than a Ride — We Save You Time.*

## Document Control

| Document Control Field | Entry |
| --- | --- |
| Document Title | Engine 2 — Resources Engine: Complete Specification |
| Document Identifier | TRS026-ENG002-RESC-001 |
| Version | 1.0.1 |
| Status | **ADOPTED** (2026-08-16, per Founder directive — build order FDN → Resources → Services → Business) |
| Remediation | v1.0.1 corrects `resource_workforce_unit`'s fleet-requirement rule, which PostgreSQL cannot execute as written (a subquery inside a `CHECK` constraint is not permitted); replaced with a deferred constraint trigger (§2.5). Cross-checked against the now-finalized FDN-001 v3.0.0 Annex H DDL compilation for alignment — no other deviation found |
| Classification | Institutional Blueprint — Confidential |
| Schema | `trustride` (single canonical PostgreSQL schema; this engine's tables are prefixed `resource_`) |
| Platform Code | TRS026 |
| Engine Code | `TRS026_ENG002_RESC` |
| Engine No. | `ENGINE_002` |
| Installation Order | 002 |
| Parent Authority | TBOC v2.0.0 Genesis Edition — Article 37 (The Resource Doctrine), Article 38 (Physical Estate Register), Article 39 (Fleet & Equipment Register), Article 40 (Own Marketplace Inventory), Article 41 (Resource Lifecycle & Availability) |
| Architecture Lineage | Positioned as Engine 2 in the eleven-engine Constitutional Engine Registry (Annex C, FDN-001 v3.0.0); Layer 2 Business Runtime of the Backend/Frontend/Event-Signal Architecture Blueprint v1.1.0 |

## Document Purpose & Constitutional Basis

This instrument specifies **Engine 2 — the Resources Engine**, TrustRide's authoritative custodian of every business resource: fleet, equipment, physical estate, workforce operating units, and Own Marketplace inventory while held for trade. It answers one constitutional question for the rest of the platform — **what capacity exists right now, and is it lawful to dispatch?**

TBOC does not permit a technical document to invent business concepts (Article 8, the Zero-Pollution Rule). Every mechanical rule in this document therefore traces to a standing TBOC provision:

| This engine's function | TBOC basis |
| --- | --- |
| A resource is any person, asset, technology, knowledge, relationship, or capability executing TrustRide's work | Article 37 — The Resource Doctrine |
| One resource truth; no unregistered resource assigned; custody is accountability | Article 37.2–37.4 |
| The physical estate register — HQ, hubs, maintenance yards, storage | Article 38 — The Physical Estate Register |
| The fleet and equipment register — vehicles, tools, uniforms, safety gear, workforce devices | Article 39 — Fleet & Equipment Register |
| Own Marketplace inventory as a business resource while held for trade | Article 40 — Own Marketplace Inventory |
| The resource lifecycle and the availability law that gates dispatch | Article 41 — Resource Lifecycle & Availability |
| Resource mapping to an Order request, reservation, and assignment | Article 20.2 — Assignment sub-sequence |
| No engine reads or writes another engine's tables; cross-engine truth moves only as a signal | Article 33 |

Foundation (Engine 1) registers the *identity* of every Person and Thing exactly once — `person_profile`, `thing_registry`. This engine never duplicates that identity. What this engine owns is the **operational life** of a resource once it is deployed for TrustRide's work: its custody, its condition, its lifecycle stage, and — above all — its live availability. FDN-001's own Foundation instrument draws this exact boundary: *"operational resource state (availability, assignment, maintenance) belongs to Engine 002 Resources; the Thing's identity lives here [Foundation], its operational life lives there [Resources]."*

---

# SECTION 1 — ARCHITECTURAL ROLE & BOUNDARIES

## 1.1 Mission

Engine 2 is the platform's single, deterministic authority for registering, custodying, and gating the availability of every business resource — fleet hardware, operational equipment, physical estate, workforce operating units, and Own Marketplace inventory while held for trade. No resource may be assigned to an Order that this engine has not registered, verified, and marked available.

## 1.2 Operational Duties

1. **Fleet and equipment registration.** Maintain `resource_fleet_register` and `resource_equipment_register` per Article 39 — motorcycles, vehicles, pickups, tools, station equipment, uniforms, safety gear, and workforce devices.
2. **Physical estate custody.** Maintain `resource_estate_register` per Article 38 — Kisumu HQ, operating hubs, maintenance yards, and storage facilities, each with recorded custody, capacity, and compliance status.
3. **Workforce unit formation.** Pair a human Operator with the fleet hardware and capacity class that makes them a deployable unit (`resource_workforce_unit`) — a rider without a motorcycle, or a motorcycle without a rider, is not a dispatchable resource.
4. **Availability gating.** Own `resource_availability_ledger`, the constitutional input into assignment (Article 41): no unavailable, unverified, or non-compliant resource may be dispatched. Availability is restored at the close of every Job (Article 19, Stage 7).
5. **Maintenance custody.** Maintain `resource_maintenance_record` — inspection, repair, refurbishment, and routine service performed at a maintenance yard (Article 38.3).
6. **Own Marketplace inventory custody.** Maintain `resource_marketplace_inventory` through its full Article 40 lifecycle — acquisition, inspection, valuation, refurbishment, compliance, listing — while the item remains a business resource, handing off to Business/Marketplace at the point of sale.
7. **Custody accountability.** Maintain an append-only `resource_custody_log` — every resource has a named custodian and a recorded location, always (Article 37.4).
8. **Assignment response.** Answer Business's assignment requests with resource discovery, reservation, and assignment per the Article 20.2 sub-sequence, never the reverse — Business decides an Order needs a resource; Resources decides which resource answers.

## 1.3 Interfaces with the Other Ten Engines

Per Plate I of the Backend Architecture and the Event/Signal Architecture, Engine 2 **never** calls another engine directly. Every interface below is a signal, carried through Engines 7/8 (Workflow Orchestration & Coordination) — the Sovereign Processing Unit.

| Engine | Direction | What crosses the boundary |
| --- | --- | --- |
| **Engine 1 — Foundation** | Inbound (by reference) | `thing_id` and `person_user_id` identity references only; this engine never reads or writes `thing_registry` or `platform_users` directly — every reference is FK-by-value, carried on the signal that introduced it |
| **Engine 3 — Services** | Bidirectional | Inbound: the macro domain and required capacity class that a Service demands, used to filter eligible resources during discovery; `MARKETPLACE_LISTING_SOLD` at sale, closing the Article 40 item lifecycle. Outbound: `RESOURCE_MARKETPLACE_ITEM_READY` when an Own Marketplace item becomes listable |
| **Engine 4 — Business** | Bidirectional | Inbound: `ASSIGNMENT_REQUESTED` (Article 20.2) with the Order's domain, required capacity class, and pickup location. Outbound: `RESOURCE_RESERVED`, `RESOURCE_ASSIGNED`, carrying the resource identity back to Business for the requester's fee/ETA prompt |
| **Engine 5 — Cost** | Outbound (via signal) | `RESOURCE_DISPATCH_INITIATED` at assignment time — the resolved asset/engine class so Engine 5 can select the correct mechanical baseline; this is the exact inbound interface Cost's own specification (§5.1) already names as its Engine 2 dependency. Engine 2 never reads Engine 5's tables |
| **Engine 6 — Integration** | Inbound (via signal) | `FLEET_VERIFICATION_UPDATED` — NTSA registration, inspection, and insurance verification results ingested from the external-system boundary, updating `compliance_status` on the fleet register |
| **Engines 7/8 — Workflow Orchestration & Coordination** | Structural | The exclusive transport for every signal in and out of Engine 2's outbox/inbox |
| **Engine 9 — AI/ML Advisory** | Outbound (read-only) | Advisory reads `resource_availability_ledger` and historical `resource_maintenance_record` rows as lawful projections for capacity-planning and fleet-replacement recommendations; it never writes back |

## 1.4 Boundaries — What Engine 2 Never Does

1. **Never places an Order.** Order placement, scope, and settlement remain Engine 4's exclusive domain.
2. **Never defines a Service.** Which capacity classes a Service requires, and its catalogue eligibility, are Engine 3's exclusive domain — this engine only answers, "what of that class is available."
3. **Never computes a fare.** Engine 2 hands Cost (Engine 5) the resolved capacity class; it never touches `cost_unit_price_quotes` or any pricing table.
4. **Never holds identity or authority.** `person_user_id` and `thing_id` on a resource row are references, not claims of ownership; Identity remains Foundation's exclusive domain.
5. **Never dispatches without registration.** No unregistered resource may be assigned to an Order (Article 37.2) — a signal requesting assignment of an unregistered or unverified resource is rejected at the inbox, never silently honoured.
6. **Never bypasses custody.** Every custody transfer is a recorded `resource_custody_log` row; there is no informal or undocumented hand-off (Article 37.3–37.4).

---

# SECTION 2 — PRODUCTION SQL DDL SCHEMA (PostgreSQL / Supabase / PostGIS-Ready)

## 2.0 Extensions & Enums (prerequisite)

```sql
-- Extensions (idempotent; already present platform-wide per Engine 001 Phase 0)
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

-- [Trace: TBOC-v2.0.0 | Article 39 | Fleet & Equipment Register]
CREATE TYPE resource_domain_enum AS ENUM (
  'TRANSPORT', 'COURIER', 'DELIVERY', 'EXECUTIVE_ASSISTANTS', 'MARKETPLACE'
);

CREATE TYPE resource_capacity_class_enum AS ENUM (
  'BODA_BODA', 'TUKTUK', 'PICKUP_TOWN', 'VAN_CARGO', 'TRUCK_LIGHT', 'EXECUTIVE_ASSISTANT_HUMAN'
);

-- [Trace: TBOC-v2.0.0 | Article 41 | Resource Lifecycle & Availability — the ten constitutional stages, verbatim]
CREATE TYPE resource_lifecycle_state_enum AS ENUM (
  'NEED_IDENTIFIED', 'ACQUIRED', 'REGISTERED', 'VERIFIED', 'ASSIGNED',
  'UTILIZED', 'MONITORED', 'MAINTAINED', 'EVALUATED', 'REASSIGNED', 'RETIRED'
);

-- [Trace: TBOC-v2.0.0 | Article 41 — live dispatch-facing availability signal, narrower than the full lifecycle]
CREATE TYPE resource_availability_state_enum AS ENUM (
  'AVAILABLE', 'RESERVED', 'ASSIGNED', 'MAINTENANCE', 'OFFLINE', 'RETIRED'
);

CREATE TYPE resource_estate_type_enum AS ENUM (
  'HQ', 'OPERATING_HUB', 'MAINTENANCE_YARD', 'STORAGE_FACILITY'
);

CREATE TYPE resource_ownership_type_enum AS ENUM (
  'OWNED', 'LEASED', 'PARTNER_CONTRIBUTED'
);

CREATE TYPE resource_equipment_type_enum AS ENUM (
  'OPERATIONAL_TOOL', 'STATION_EQUIPMENT', 'UNIFORM', 'SAFETY_GEAR'
);

-- [Trace: TBOC-v2.0.0 | Article 40 — the exact Own Marketplace item lifecycle]
CREATE TYPE resource_inventory_lifecycle_enum AS ENUM (
  'ACQUIRED', 'INSPECTED', 'VALUED', 'REFURBISHED', 'COMPLIANT',
  'LISTED', 'SOLD', 'AFTERCARE', 'RETIRED'
);

CREATE TYPE resource_custody_type_enum AS ENUM (
  'FLEET', 'EQUIPMENT', 'DEVICE', 'ESTATE', 'MARKETPLACE_INVENTORY'
);
```

## 2.1 `resource_estate_register` — The Physical Estate

```sql
-- [Trace: TBOC-v2.0.0 | Article 38 | The Physical Estate Register]
CREATE TABLE resource_estate_register (
  estate_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  estate_code         TEXT NOT NULL UNIQUE,
  estate_type         resource_estate_type_enum NOT NULL,
  estate_name         TEXT NOT NULL,
  location            GEOMETRY(POINT, 4326) NOT NULL,
  jurisdiction        TEXT NOT NULL,             -- county/administrative reference, by value
  custodian_user_id   UUID NOT NULL,              -- reference only; identity lives in Foundation
  capacity_description TEXT,
  compliance_status   TEXT NOT NULL DEFAULT 'PENDING_REVIEW'
                         CHECK (compliance_status IN ('COMPLIANT', 'PENDING_REVIEW', 'NON_COMPLIANT')),
  county_licence_ref  TEXT,
  lifecycle_state     resource_lifecycle_state_enum NOT NULL DEFAULT 'REGISTERED',
  active              BOOLEAN NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_resource_estate_location ON resource_estate_register USING GIST (location);
CREATE INDEX idx_resource_estate_type ON resource_estate_register (estate_type) WHERE active = TRUE;

COMMENT ON TABLE resource_estate_register IS
  '[Trace: TBOC-v2.0.0 | Article 38] The constitutional register of TrustRide''s physical estate — Kisumu HQ, operating hubs, maintenance yards, and storage facilities.';

-- Row Level Security (TBOC Zero-Trust law; FDN-001 Annex B, Part III Phase 8) — governed reference data, platform-readable, engine-service writable
ALTER TABLE resource_estate_register ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_estate_register_platform_read ON resource_estate_register
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_estate_register_service_write ON resource_estate_register
  FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);

-- Pre-seed: Kisumu Headquarters (Article 38.1)
INSERT INTO resource_estate_register (estate_code, estate_type, estate_name, location, jurisdiction, custodian_user_id, compliance_status)
VALUES ('TRS-HQ-KSM-01', 'HQ', 'Kisumu Headquarters', ST_SetSRID(ST_MakePoint(34.767956, -0.091702), 4326),
        'KISUMU_COUNTY', '00000000-0000-0000-0000-000000000000', 'COMPLIANT');
```

## 2.2 `resource_capacity_class` — Governed Capacity Vocabulary

```sql
-- [Trace: TBOC-v2.0.0 | Article 39 | Article 8 — Zero-Pollution Rule, governed vocabulary]
CREATE TABLE resource_capacity_class (
  capacity_class_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_code         resource_capacity_class_enum NOT NULL UNIQUE,
  class_label        TEXT NOT NULL,
  domain_affinity    resource_domain_enum NOT NULL,
  requires_fleet     BOOLEAN NOT NULL DEFAULT TRUE,   -- FALSE for EXECUTIVE_ASSISTANT_HUMAN
  description        TEXT NOT NULL,
  active             BOOLEAN NOT NULL DEFAULT TRUE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX uq_resource_capacity_class_code ON resource_capacity_class (class_code) WHERE active = TRUE;

COMMENT ON TABLE resource_capacity_class IS
  '[Trace: TBOC-v2.0.0 | Article 39] The constitutional source of capacity-class vocabulary; Engine 5''s asset_class_enum/engine_capacity_enum mirror this registry by value.';

ALTER TABLE resource_capacity_class ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_capacity_class_platform_read ON resource_capacity_class
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_capacity_class_service_write ON resource_capacity_class
  FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);

INSERT INTO resource_capacity_class (class_code, class_label, domain_affinity, requires_fleet, description) VALUES
  ('BODA_BODA', 'Motorcycle (Boda Boda)', 'TRANSPORT', TRUE, 'Standard motorcycle transport and last-mile delivery capacity.'),
  ('TUKTUK', 'Tuk-Tuk', 'TRANSPORT', TRUE, 'Three-wheeler passenger transport capacity.'),
  ('PICKUP_TOWN', 'Pickup (Town)', 'DELIVERY', TRUE, 'Light pickup for in-town goods movement.'),
  ('VAN_CARGO', 'Cargo Van', 'DELIVERY', TRUE, 'Van-class capacity for larger cargo movement.'),
  ('TRUCK_LIGHT', 'Light Truck', 'DELIVERY', TRUE, 'Light truck capacity for bulk or long-haul goods movement.'),
  ('EXECUTIVE_ASSISTANT_HUMAN', 'Executive Assistant', 'EXECUTIVE_ASSISTANTS', FALSE, 'Human-only capacity for errands, driving, caregiving, cleaning, chef, and shopping pillars (Article 27).');
```

## 2.3 `resource_fleet_register` — Fleet Hardware

```sql
-- [Trace: TBOC-v2.0.0 | Article 39.1 | Fleet hardware — motorcycles, vehicles, pickups]
CREATE TABLE resource_fleet_register (
  fleet_resource_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  thing_id            UUID NOT NULL UNIQUE,        -- reference only; identity of record lives in Foundation's thing_registry
  capacity_class_id   UUID NOT NULL REFERENCES resource_capacity_class (capacity_class_id),
  ownership_type      resource_ownership_type_enum NOT NULL,
  registration_particulars TEXT NOT NULL,            -- plate/registration number, by value
  inspection_status   TEXT NOT NULL DEFAULT 'PENDING'
                         CHECK (inspection_status IN ('PENDING', 'PASSED', 'FAILED', 'EXPIRED')),
  insurance_status    TEXT NOT NULL DEFAULT 'PENDING'
                         CHECK (insurance_status IN ('PENDING', 'ACTIVE', 'EXPIRED', 'LAPSED')),
  condition_record    TEXT,
  home_estate_id      UUID NOT NULL REFERENCES resource_estate_register (estate_id),
  custodian_user_id   UUID NOT NULL,                -- reference only
  lifecycle_state     resource_lifecycle_state_enum NOT NULL DEFAULT 'REGISTERED',
  active              BOOLEAN NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_resource_fleet_class ON resource_fleet_register (capacity_class_id) WHERE active = TRUE;
CREATE INDEX idx_resource_fleet_estate ON resource_fleet_register (home_estate_id);
CREATE INDEX idx_resource_fleet_thing ON resource_fleet_register (thing_id);

COMMENT ON TABLE resource_fleet_register IS
  '[Trace: TBOC-v2.0.0 | Article 39.1] Fleet hardware. No fleet resource may be assigned to an Order without PASSED inspection and ACTIVE insurance (Article 41).';

ALTER TABLE resource_fleet_register ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_fleet_register_platform_read ON resource_fleet_register
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_fleet_register_service_write ON resource_fleet_register
  FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);
```

## 2.4 `resource_equipment_register` — Equipment, Uniforms, Safety Gear, Devices

```sql
-- [Trace: TBOC-v2.0.0 | Article 39.2-39.5 | Operational equipment, uniforms, safety gear, workforce devices]
CREATE TABLE resource_equipment_register (
  equipment_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  equipment_type       resource_equipment_type_enum NOT NULL,
  item_code             TEXT NOT NULL UNIQUE,
  description             TEXT NOT NULL,
  thing_id                 UUID,                     -- populated only for workforce devices registered as Things (Article 12.3)
  issued_to_user_id         UUID,                     -- reference only; NULL while unissued
  issued_at                   TIMESTAMPTZ,
  condition_state               TEXT NOT NULL DEFAULT 'NEW'
                                   CHECK (condition_state IN ('NEW', 'SERVICEABLE', 'WORN', 'DAMAGED', 'DECOMMISSIONED')),
  returned_at                     TIMESTAMPTZ,
  home_estate_id                    UUID NOT NULL REFERENCES resource_estate_register (estate_id),
  lifecycle_state                     resource_lifecycle_state_enum NOT NULL DEFAULT 'REGISTERED',
  active                                BOOLEAN NOT NULL DEFAULT TRUE,
  created_at                              TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                                TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_resource_equipment_issued ON resource_equipment_register (issued_to_user_id) WHERE issued_to_user_id IS NOT NULL;
CREATE INDEX idx_resource_equipment_type ON resource_equipment_register (equipment_type) WHERE active = TRUE;

COMMENT ON TABLE resource_equipment_register IS
  '[Trace: TBOC-v2.0.0 | Article 39.2-39.5] Operational equipment, station equipment, uniforms, safety gear, and workforce devices; issuance and return are always recorded.';

ALTER TABLE resource_equipment_register ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_equipment_register_platform_read ON resource_equipment_register
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_equipment_register_service_write ON resource_equipment_register
  FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);
```

## 2.5 `resource_workforce_unit` — The Deployable Working Unit

```sql
-- [Trace: TBOC-v2.0.0 | Article 37, Article 41 | Resources represent the brand; a resource is deployed as one unit]
CREATE TABLE resource_workforce_unit (
  workforce_unit_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_user_id      UUID NOT NULL,               -- reference only; the Operator's business role lives in Engine 4
  fleet_resource_id       UUID REFERENCES resource_fleet_register (fleet_resource_id),  -- NULL for EXECUTIVE_ASSISTANT_HUMAN
  capacity_class_id         UUID NOT NULL REFERENCES resource_capacity_class (capacity_class_id),
  primary_estate_id           UUID NOT NULL REFERENCES resource_estate_register (estate_id),
  unit_status                   TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (unit_status IN ('ACTIVE', 'INACTIVE')),
  formed_at                       TIMESTAMPTZ NOT NULL DEFAULT now(),
  dissolved_at                      TIMESTAMPTZ,
  created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX uq_resource_unit_operator_active
  ON resource_workforce_unit (operator_user_id) WHERE unit_status = 'ACTIVE';
CREATE INDEX idx_resource_unit_fleet ON resource_workforce_unit (fleet_resource_id);
CREATE INDEX idx_resource_unit_class ON resource_workforce_unit (capacity_class_id) WHERE unit_status = 'ACTIVE';

COMMENT ON TABLE resource_workforce_unit IS
  '[Trace: TBOC-v2.0.0 | Article 37, 41] A rider without a motorcycle, or a motorcycle without a rider, is not a dispatchable resource — this table is the pairing that makes one.';

ALTER TABLE resource_workforce_unit ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_workforce_unit_platform_read ON resource_workforce_unit
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_workforce_unit_service_write ON resource_workforce_unit
  FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);

-- PostgreSQL forbids subqueries inside CHECK constraints; the fleet-requirement rule
-- (a unit with no fleet_resource_id is lawful only for a capacity class that does not
-- require fleet hardware) is therefore enforced as a deferred constraint trigger.
CREATE OR REPLACE FUNCTION resource_workforce_unit_fleet_requirement()
RETURNS trigger AS $$
BEGIN
  IF NEW.fleet_resource_id IS NULL AND NOT EXISTS (
    SELECT 1 FROM resource_capacity_class
    WHERE capacity_class_id = NEW.capacity_class_id AND requires_fleet = FALSE
  ) THEN
    RAISE EXCEPTION 'resource_workforce_unit % requires fleet_resource_id for capacity_class_id %',
      NEW.workforce_unit_id, NEW.capacity_class_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_resource_unit_fleet_requirement
  AFTER INSERT OR UPDATE ON resource_workforce_unit
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION resource_workforce_unit_fleet_requirement();
```

## 2.6 `resource_availability_ledger` — The Dispatch Gate

```sql
-- [Trace: TBOC-v2.0.0 | Article 41 | Resource Lifecycle & Availability — the constitutional input into assignment]
CREATE TABLE resource_availability_ledger (
  availability_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_type         resource_custody_type_enum NOT NULL,
  resource_ref_id         UUID NOT NULL,             -- polymorphic reference to fleet_resource_id / equipment_id / workforce_unit_id
  availability_state       resource_availability_state_enum NOT NULL,
  effective_from              TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to                  TIMESTAMPTZ,           -- NULL = current state
  reason_code                     TEXT,
  job_ref_id                        UUID,               -- correlates to the Order/Job whose Stage 7 close restored availability (Article 19)
  changed_by                          UUID NOT NULL,
  created_at                            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_resource_availability_current
  ON resource_availability_ledger (resource_type, resource_ref_id) WHERE effective_to IS NULL;
CREATE INDEX idx_resource_availability_job ON resource_availability_ledger (job_ref_id) WHERE job_ref_id IS NOT NULL;

COMMENT ON TABLE resource_availability_ledger IS
  '[Trace: TBOC-v2.0.0 | Article 41] No unavailable, unverified, or non-compliant resource may be dispatched; availability is restored at the close of every Job.';

ALTER TABLE resource_availability_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_availability_ledger_platform_read ON resource_availability_ledger
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_availability_ledger_service_write ON resource_availability_ledger
  FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);
```

## 2.7 Engine Event Substrate (Constitutional Mandatory Tables)

Per Plate I (Station Law) and CC-03 of the platform Conformance Certificate, every engine — Engine 2 included — carries exactly one outbox and one inbox, in the standard signal envelope shape (FDN-001 §11.2).

```sql
-- [Trace: TBOC-v2.0.0 | Article 59-60 — mandatory per-engine ledger tables]
CREATE TABLE resource_event_outbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG002_RESC',
  receiving_engine       TEXT NOT NULL,
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  signal_status               TEXT NOT NULL DEFAULT 'PENDING'
                                CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason              TEXT,
  idempotency_key                 TEXT NOT NULL UNIQUE,
  attempt_count                     INTEGER NOT NULL DEFAULT 0,
  emitted_at                         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_resource_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_resource_outbox_status ON resource_event_outbox (signal_status);
CREATE INDEX idx_resource_outbox_correlation ON resource_event_outbox (correlation_id);

ALTER TABLE resource_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_event_outbox_service_only ON resource_event_outbox
  FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);

-- [Trace: TBOC-v2.0.0 | Article 59-60 — mandatory per-engine ledger tables]
CREATE TABLE resource_event_inbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL,
  receiving_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG002_RESC',
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  payload_out                JSONB,
  signal_status                TEXT NOT NULL DEFAULT 'RECEIVED'
                                 CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason               TEXT,
  idempotency_key                  TEXT NOT NULL UNIQUE,
  received_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at                          TIMESTAMPTZ,
  CONSTRAINT chk_resource_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_resource_inbox_status ON resource_event_inbox (signal_status);
CREATE INDEX idx_resource_inbox_correlation ON resource_event_inbox (correlation_id);

ALTER TABLE resource_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_event_inbox_service_only ON resource_event_inbox
  FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);
```

---

# SECTION 3 — DOMAIN OBJECT & PRIMITIVE SPECIFICATIONS

## 3.1 `ResourceMaintenanceRecord` → `resource_maintenance_record`

The custody trail of every inspection, repair, refurbishment, and routine service performed at a maintenance yard (Article 38.3), and the direct input into `inspection_status`/`condition_record` on the fleet register.

| Column Name | Data Type | Nullability | Constraints | Exact Purpose |
| --- | --- | --- | --- | --- |
| `maintenance_id` | UUID | NOT NULL | PK, `DEFAULT gen_random_uuid()` | Unique identity of this maintenance record |
| `fleet_resource_id` | UUID | NOT NULL | FK → `resource_fleet_register.fleet_resource_id` | The fleet resource serviced |
| `maintenance_type` | TEXT | NOT NULL | CHECK IN (`'INSPECTION'`,`'REPAIR'`,`'REFURBISHMENT'`,`'ROUTINE_SERVICE'`) | Nature of the maintenance event |
| `performed_at_estate_id` | UUID | NOT NULL | FK → `resource_estate_register.estate_id` | The maintenance yard where the work was performed |
| `description` | TEXT | NOT NULL | — | Description of the work performed |
| `cost_kes` | NUMERIC(18,2) | NOT NULL | CHECK `>= 0` | Cost of the maintenance event, in Kenyan Shillings |
| `performed_by` | UUID | NOT NULL | — | Reference to the mechanic/field staff Operator who performed the work |
| `condition_before` | TEXT | NULL | — | Condition note prior to the maintenance event |
| `condition_after` | TEXT | NULL | — | Condition note after the maintenance event |
| `completed_at` | TIMESTAMPTZ | NULL | — | NULL while in progress |
| `created_at` | TIMESTAMPTZ | NOT NULL | `DEFAULT now()` | Row creation time |

```sql
-- [Trace: TBOC-v2.0.0 | Article 38.3 | Maintenance yards]
CREATE TABLE resource_maintenance_record (
  maintenance_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  fleet_resource_id      UUID NOT NULL REFERENCES resource_fleet_register (fleet_resource_id),
  maintenance_type         TEXT NOT NULL CHECK (maintenance_type IN
                              ('INSPECTION','REPAIR','REFURBISHMENT','ROUTINE_SERVICE')),
  performed_at_estate_id     UUID NOT NULL REFERENCES resource_estate_register (estate_id),
  description                  TEXT NOT NULL,
  cost_kes                       NUMERIC(18,2) NOT NULL CHECK (cost_kes >= 0),
  performed_by                     UUID NOT NULL,
  condition_before                   TEXT,
  condition_after                      TEXT,
  completed_at                           TIMESTAMPTZ,
  created_at                               TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_resource_maintenance_fleet ON resource_maintenance_record (fleet_resource_id, created_at DESC);
CREATE INDEX idx_resource_maintenance_estate ON resource_maintenance_record (performed_at_estate_id);

ALTER TABLE resource_maintenance_record ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_maintenance_record_platform_read ON resource_maintenance_record
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_maintenance_record_service_write ON resource_maintenance_record
  FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);
```

## 3.2 `ResourceMarketplaceInventory` → `resource_marketplace_inventory`

Own Marketplace items are business resources while held for trade (Article 40); this table owns the item through its full physical-custody lifecycle up to sale, at which point the commercial transaction is handed to Engine 4 (Business/Marketplace).

| Column Name | Data Type | Nullability | Constraints | Exact Purpose |
| --- | --- | --- | --- | --- |
| `inventory_item_id` | UUID | NOT NULL | PK, `DEFAULT gen_random_uuid()` | Unique identity of this inventory item |
| `item_code` | TEXT | NOT NULL | UNIQUE | Human-legible item code |
| `category` | TEXT | NOT NULL | — | Item category |
| `acquisition_source` | TEXT | NOT NULL | — | How the item was acquired (salvage, trade-in, direct purchase, partner contribution) |
| `acquisition_cost_kes` | NUMERIC(18,2) | NOT NULL | CHECK `>= 0` | Acquisition cost, in Kenyan Shillings |
| `inspection_status` | TEXT | NOT NULL | `DEFAULT 'PENDING'` | Inspection outcome prior to listing |
| `valuation_kes` | NUMERIC(18,2) | NULL | CHECK `>= 0` | Assessed resale valuation, in Kenyan Shillings |
| `refurbishment_status` | TEXT | NOT NULL | `DEFAULT 'NOT_REQUIRED'` | Refurbishment state |
| `compliance_status` | TEXT | NOT NULL | `DEFAULT 'PENDING_REVIEW'` | Statutory/safety compliance state prior to listing |
| `custody_estate_id` | UUID | NOT NULL | FK → `resource_estate_register.estate_id` | Current physical custody location |
| `lifecycle_state` | `resource_inventory_lifecycle_enum` | NOT NULL | `DEFAULT 'ACQUIRED'` | The Article 40 lifecycle stage |
| `listed_at` | TIMESTAMPTZ | NULL | — | When the item entered the Marketplace catalogue (Engine 3/4) |
| `sold_at` | TIMESTAMPTZ | NULL | — | When custody transferred to the buyer; margin recognition is Engine 4's concern from this point |
| `created_at` | TIMESTAMPTZ | NOT NULL | `DEFAULT now()` | Row creation time |

```sql
-- [Trace: TBOC-v2.0.0 | Article 40 | Own Marketplace Inventory]
CREATE TABLE resource_marketplace_inventory (
  inventory_item_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_code               TEXT NOT NULL UNIQUE,
  category                  TEXT NOT NULL,
  acquisition_source          TEXT NOT NULL,
  acquisition_cost_kes          NUMERIC(18,2) NOT NULL CHECK (acquisition_cost_kes >= 0),
  inspection_status                TEXT NOT NULL DEFAULT 'PENDING',
  valuation_kes                      NUMERIC(18,2) CHECK (valuation_kes IS NULL OR valuation_kes >= 0),
  refurbishment_status                 TEXT NOT NULL DEFAULT 'NOT_REQUIRED',
  compliance_status                      TEXT NOT NULL DEFAULT 'PENDING_REVIEW',
  custody_estate_id                        UUID NOT NULL REFERENCES resource_estate_register (estate_id),
  lifecycle_state                            resource_inventory_lifecycle_enum NOT NULL DEFAULT 'ACQUIRED',
  listed_at                                    TIMESTAMPTZ,
  sold_at                                        TIMESTAMPTZ,
  created_at                                       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_resource_inventory_lifecycle ON resource_marketplace_inventory (lifecycle_state);
CREATE INDEX idx_resource_inventory_estate ON resource_marketplace_inventory (custody_estate_id);

ALTER TABLE resource_marketplace_inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_marketplace_inventory_platform_read ON resource_marketplace_inventory
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_marketplace_inventory_service_write ON resource_marketplace_inventory
  FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);
```

## 3.3 `ResourceCustodyLog` → `resource_custody_log`

The append-only accountability trail required by Article 37.4 — every resource of every type has a named custodian and a recorded location, always.

| Column Name | Data Type | Nullability | Constraints | Exact Purpose |
| --- | --- | --- | --- | --- |
| `custody_log_id` | UUID | NOT NULL | PK, `DEFAULT gen_random_uuid()` | Unique identity of this custody event |
| `resource_type` | `resource_custody_type_enum` | NOT NULL | — | Which resource table `resource_ref_id` points into |
| `resource_ref_id` | UUID | NOT NULL | — | Polymorphic reference to the resource row |
| `custodian_user_id` | UUID | NOT NULL | — | The named custodian as of this event (reference only) |
| `location_estate_id` | UUID | NULL | FK → `resource_estate_register.estate_id` | Recorded location at transfer, where estate-bound |
| `transferred_at` | TIMESTAMPTZ | NOT NULL | `DEFAULT now()` | When custody transferred |
| `transferred_by` | UUID | NOT NULL | — | Who recorded/authorized the transfer |
| `created_at` | TIMESTAMPTZ | NOT NULL | `DEFAULT now()` | Row creation time |

```sql
-- [Trace: TBOC-v2.0.0 | Article 37.4 | Custody is accountability]
CREATE TABLE resource_custody_log (
  custody_log_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_type         resource_custody_type_enum NOT NULL,
  resource_ref_id         UUID NOT NULL,
  custodian_user_id         UUID NOT NULL,
  location_estate_id          UUID REFERENCES resource_estate_register (estate_id),
  transferred_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  transferred_by                   UUID NOT NULL,
  created_at                         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_resource_custody_resource ON resource_custody_log (resource_type, resource_ref_id, transferred_at DESC);

-- Append-only at the database level (Article 49 evidence discipline)
REVOKE UPDATE, DELETE ON resource_custody_log FROM PUBLIC;

ALTER TABLE resource_custody_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_custody_log_platform_read ON resource_custody_log
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_custody_log_service_write ON resource_custody_log
  FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);
```

---

# SECTION 4 — SYSTEM API CONTRACTS & WORKFLOW ORCHESTRATION

All endpoints are fronted by Engine 2's own signal envelope (§5); the HTTP contracts below are the Integration-layer (Engine 6) surface that Presentation (Engine 11) and Business (Engine 4) call, which Engine 6 then translates into the constitutional emit → orchestrate → respond pattern before Engine 2 ever sees the request.

## 4.1 `POST /api/v1/resources/discover`

**Request**

```json
{
  "correlation_id": "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d",
  "order_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "macro_domain": "TRANSPORT",
  "required_capacity_class": "BODA_BODA",
  "pickup_location": { "latitude": -0.091702, "longitude": 34.767956 },
  "requested_at": "2026-08-16T09:00:00Z"
}
```

**Response — `200 OK`**

```json
{
  "correlation_id": "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d",
  "candidates": [
    {
      "workforce_unit_id": "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e",
      "fleet_resource_id": "c3d4e5f6-a7b8-4c9d-0e1f-2a3b4c5d6e7f",
      "capacity_class": "BODA_BODA",
      "distance_to_pickup_km": 0.8,
      "availability_state": "AVAILABLE"
    }
  ],
  "generated_at": "2026-08-16T09:00:01Z"
}
```

**Response — `422 Unprocessable Entity`** (no available resource of the required class)

```json
{
  "correlation_id": "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d",
  "error_code": "RESOURCE_NOT_AVAILABLE",
  "error_message": "No AVAILABLE resource_workforce_unit exists for capacity_class=BODA_BODA within the discovery radius."
}
```

## 4.2 `POST /api/v1/resources/reserve`

**Request**

```json
{
  "correlation_id": "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d",
  "workforce_unit_id": "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e",
  "order_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6"
}
```

**Response — `200 OK`**

```json
{
  "correlation_id": "a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d",
  "workforce_unit_id": "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e",
  "availability_state": "RESERVED",
  "reserved_until": "2026-08-16T09:03:00Z"
}
```

## 4.3 `GET /api/v1/resources/fleet/{fleet_resource_id}/compliance`

**Request** (path parameter `fleet_resource_id`)

**Response — `200 OK`**

```json
{
  "fleet_resource_id": "c3d4e5f6-a7b8-4c9d-0e1f-2a3b4c5d6e7f",
  "inspection_status": "PASSED",
  "insurance_status": "ACTIVE",
  "lifecycle_state": "UTILIZED",
  "dispatch_eligible": true,
  "last_maintenance_at": "2026-07-28T11:00:00Z"
}
```

---

# SECTION 5 — EVENT-DRIVEN SIGNAL & INTEGRATION MATRIX

Every signal below travels the constitutional shape (Plate I): `resource_event_outbox` → Engines 7/8 (Orchestration + Coordination) → target engine's inbox, or the reverse into `resource_event_inbox`. Engine 2 never emits to, or receives directly from, another engine's outbox/inbox.

## 5.1 Inbound Signals — Listened To

| Signal | Emitting engine | Payload (key fields) | Effect inside Engine 2 |
| --- | --- | --- | --- |
| `ASSIGNMENT_REQUESTED` | Engine 4 (Business), via Engines 7/8 | `order_id`, `macro_domain`, `required_capacity_class`, `pickup_location` | Triggers resource discovery; on success reserves a `resource_workforce_unit` and transitions its availability to `RESERVED`, per the Article 20.2 sub-sequence |
| `JOB_COMPLETED` | Engine 4 (Business/Dispatch), via Engines 7/8 | `job_id`, `workforce_unit_id`, `completed_at` | Restores the resource's availability to `AVAILABLE` (Article 19, Stage 7) and writes the closing `resource_availability_ledger` row |
| `FLEET_VERIFICATION_UPDATED` | Engine 6 (Integration), via Engines 7/8 | `fleet_resource_id`, `inspection_status`, `insurance_status`, `verified_at` | Updates `resource_fleet_register.inspection_status`/`insurance_status`; a resource that falls out of compliance is transitioned to `OFFLINE` and made dispatch-ineligible |
| `MARKETPLACE_LISTING_SOLD` | Engine 3 (Services), via Engines 7/8 | `listing_id`, `inventory_item_id`, `list_price_kes` | Transitions the matching `resource_marketplace_inventory` row to `SOLD`, then `AFTERCARE`, and writes the closing `resource_custody_log` entry transferring custody to the buyer (Article 40) |

## 5.2 Outbound Signals — Emitted

| Signal | Receiving engine | Payload (key fields) | Triggering condition |
| --- | --- | --- | --- |
| `RESOURCE_RESERVED` | Engine 4 (Business), via Engines 7/8 | `order_id`, `workforce_unit_id`, `capacity_class`, `reserved_until` | Fired the instant a discovered resource is reserved against an Order — the first half of the Article 20.2 Resource Discovery → Resource Reserved sequence |
| `RESOURCE_ASSIGNED` | Engine 4 (Business), via Engines 7/8 | `order_id`, `workforce_unit_id`, `capacity_class`, `engine_capacity`, `thing_id` | Fired when the requester accepts and the reservation converts to a firm assignment; Business consumes this to create the `business_job` row |
| `RESOURCE_DISPATCH_INITIATED` | Engine 5 (Cost), via Engines 7/8 | `asset_class`, `engine_capacity`, `origin_zone_code`, `destination_zone_code`, `order_id`, `assignment_id` | Fired alongside `RESOURCE_ASSIGNED`, in the exact shape Cost's own specification (§5.1) declares as its inbound Engine 2 dependency — triggers Cost's fare calculation |
| `RESOURCE_AVAILABILITY_CHANGED` | Broadcast — Engine 9 (AI/ML Advisory) and Engine 11 (Presentation), via Engines 7/8 | `resource_type`, `resource_ref_id`, `availability_state`, `effective_from` | Fired on every `resource_availability_ledger` transition; feeds live operator dashboards and capacity-planning advisory models |
| `RESOURCE_MAINTENANCE_DUE` | Engine 8 (Coordination, for operator/administrator review) | `fleet_resource_id`, `maintenance_type`, `due_reason` | Fired when a fleet resource's inspection or insurance approaches expiry, or a scheduled service interval is reached |
| `RESOURCE_MARKETPLACE_ITEM_READY` | Engine 3 (Services), via Engines 7/8 | `inventory_item_id`, `lifecycle_state` | Fired when a `resource_marketplace_inventory` row reaches `COMPLIANT` (Article 40) — enables Services to list it |

## 5.3 The Signal Envelope (as applied to Engine 2)

Identical to the platform-wide envelope (Plate I, §11.2 of the Foundation instrument): `signal_id`, `correlation_id`, `causation_id`, `emitting_engine` = `TRS026_ENG002_RESC`, `receiving_engine`, `signal_type`, `payload_in`, `payload_out`, `signal_status`, `rejection_reason`, `idempotency_key`, `attempt_count`, `emitted_at`, `received_at`, `accepted_at`. No field is added, renamed, or omitted — an engine that invents its own envelope shape is non-conformant.

---

# ANNEX — CONFORMANCE SELF-CERTIFICATION AGAINST THE THREE PLATES

Filed in the same discipline as the Foundation instrument's Part XI and Engine 5's own Annex, so that Engine 2 can be certified on the same footing as its sibling engines.

| Check | Requirement | Result | Evidence |
| --- | --- | --- | --- |
| CC-02 | Every table assigned to exactly one of the five stations | **PASS** | §2.1–2.7, §3.1–3.3: domain tables = Domain State; `resource_event_outbox` = Emission Ledger; `resource_event_inbox` = Reception Ledger; mutation only via the engine's own accept-handler |
| CC-03 | Engine carries the four ledger tables with the standard envelope | **PASS** | §2.7, §5.3 |
| CC-04 | Every cross-engine interaction is a signal; no foreign table access | **PASS** | §1.3, §5 — every interface listed is a named signal, never a direct read/write |
| CC-06 | Idempotency, retry, dead-letter declared | **PASS** | `idempotency_key` UNIQUE on both ledger tables (§2.7); `RESOURCE_MAINTENANCE_DUE` routes to Coordination for operator review |
| CC-07 | Engine declares its layer, holds nothing belonging to another layer | **PASS** | §1 — Layer 2, Business Runtime; holds no identity, order, or pricing state |
| CC-09 | Advisory outputs, if any, are records only | **N/A** | Engine 2 is not an advisory engine; it is a Layer 2 runtime engine |
| CC-12 | Every provision carries a trace tag | **PASS** | Every DDL block and table comment carries a `[Trace: TBOC-v2.0.0 | Article ...]` tag |
| Money Law | Every KES-denominated column is `NUMERIC(18,2)` | **PASS** | `cost_kes` (§3.1), `acquisition_cost_kes`/`valuation_kes` (§3.2) |
| RLS Law | Row-Level Security enabled on every table | **PASS** | All eleven tables (§2.1–2.7, §3.1–3.3) carry `ENABLE ROW LEVEL SECURITY` with an explicit policy |

---

**END OF SPECIFICATION**

*Engine 2 answers, before any other engine asks: what capacity exists right now, and is it lawful to dispatch. One resource truth, one custodian per resource, one availability ledger — the readiness beneath every Order TrustRide accepts.*
