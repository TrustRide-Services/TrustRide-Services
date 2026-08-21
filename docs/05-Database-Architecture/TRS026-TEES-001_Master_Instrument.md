## Document Control

| Document Control Field | Entry |
| --- | --- |
| Document Title | Technical & Engineering Execution Standard (TEES) |
| Document Identifier | TRS026-TEES-001 |
| Version | 1.0.0 |
| Edition | Genesis Edition |
| Status | ADOPTED — Sovereign Constitutional Instrument, Third of the Four-Sovereign Framework |
| Classification | Institutional Blueprint — Confidential |
| Constitutional Authority | Inherits from TBOC v2.0.0 Genesis Edition through SAPC, per TBOC Article 59 — Lineage into TEES |
| Framework Position | Third Sovereign — Technical & Engineering Execution Standard |
| Derives From | TRS026-TBOC-001 v2.0.0 Genesis Edition, Article 59; TRS026-SAPC-001 v1.0.0 |
| Governs | Data schemas, migrations, connection management, state machines, the engine installation lifecycle |
| May Never Contain | Architecture contrary to SAPC; business invention |
| Jurisdiction | Republic of Kenya |
| Platform Code | TRS026 |
| Platform Name | TRUSTRIDE_SERVICES |
| Founder | Onyango Albert Chitayi, Founder & Chief Executive Officer |
| Date of Issue | 2026-08-16 |
| Compilation Note | Every standard below was already enforced, table by table, across the eleven adopted engine specifications before this instrument existed; TEES formalizes that practice as one binding standard rather than inventing a new one |

---

## Constitutional Authority & Position in the Four-Sovereign Framework

This instrument is the **third** of TrustRide Services' four sovereign documents. Per TBOC Article 59 (Lineage into TEES), it inherits from TBOC through SAPC and must express, in execution language, five mandates — the data homes of the constitutional registers, the Order lifecycle as a governed state machine, the fourteen-phase installation lifecycle, migration/connection/performance discipline, and the testing standard. Each Part below names its exact TBOC parent, per Article 61's Traceability rule.

---

# PART I — DATA HOMES OF THE CONSTITUTIONAL REGISTERS

*[Trace: TBOC Article 59.1]*

Every business register TBOC names has exactly one lawful data home. This table is TEES's binding resolution of "where does this register live":

| TBOC register | Lawful engine | Primary table(s) |
| --- | --- | --- |
| Identity | Engine 1, TRS_FDN_IDENTITY | `platform_users`, `person_profile`, `entity_profile`, `thing_registry` |
| User / User Type Profile | Engine 1, TRS_FDN_IDENTITY | `user_type_binding`, `user_identifier`, `user_contact`, `user_address` |
| Order | Engine 4, Business | `business_order`, `business_order_line` |
| Assignment | Engine 2, Resources (discovery/reservation) → Engine 4, Business (`business_job` on acceptance) | `resource_workforce_unit`, `resource_availability_ledger`, `business_job` |
| Dispatch | Engine 4, Business | `business_job`, `business_tracking_session` |
| Settlement | Engine 4, Business (record) → Engine 6, Integration (execution) | `business_settlement`, `integration_payment_gateway_transaction` |
| Rating | Engine 4, Business | `business_review` |
| Resource | Engine 2, Resources | `resource_fleet_register`, `resource_equipment_register` |
| Estate | Engine 2, Resources | `resource_estate_register` |
| Fleet | Engine 2, Resources | `resource_fleet_register`, `resource_maintenance_record` |
| Marketplace Item | Engine 2, Resources (physical custody) → Engine 3, Services (sellable listing) | `resource_marketplace_inventory`, `service_marketplace_listing` |
| Incident | Engine 1, TRS_FDN_AUDIT | `system_incident`, `security_event` |
| Safeguarding | Engine 3, Services | `service_line.safeguarding_tier`, `service_line.guardian_authorization_required` |

No register above has a second home anywhere else in the schema. A duplicate is a constitutional defect (TBOC Article 8.3), never a design choice.

---

# PART II — GOVERNED STATE MACHINES

*[Trace: TBOC Article 59.2]*

## 2.1 The Seven-Stage Universal Order Lifecycle

**Order Placement & Scope → Assignment Validation & Job Creation → Dispatch → Execution & Completion → Payment Prompting & Settlement → Review/Rate/Support → Resource Availability.**

Realized as `business_order_stage_enum` (Engine 4 §2.0) — an ordered PostgreSQL enum, never a free-text column — and enforced structurally: `business_order`'s `business_order_scope_exists()` deferred constraint trigger refuses to commit an Order with zero `business_order_line` rows, making "no scope, no Order" (TBOC Article 16) a database fact, not a code-review convention.

## 2.2 The State Machine Standard

Every governed status column across all eleven engines follows one binding pattern: a PostgreSQL `ENUM` type (never free-text) naming every lawful state, a `DEFAULT` naming the initial state, and — where a transition must be structurally guarded — a deferred constraint trigger, never a CHECK constraint containing a subquery (PostgreSQL forbids the latter outright; every engine that once attempted it was corrected to the trigger pattern during conformity audit).

Worked examples already adopted across the platform:

| Engine | State machine | Enum |
| --- | --- | --- |
| Business | Order lifecycle | `business_order_stage_enum`, `business_order_status_enum` |
| Business | Job dispatch | `business_job_status_enum` |
| Cost | Quote lifecycle | `quote_state_enum` (`FARE_ESTIMATED → FARE_LOCKED → SERVICE_IN_PROGRESS → FARE_FINALIZED → C2B_PAYMENT_TRIGGERED`, or `EXPIRED`/`CANCELLED`) |
| Resources | Resource lifecycle | `resource_lifecycle_state_enum` (the ten TBOC Article 41 stages, verbatim) |
| Resources | Dispatch-facing availability | `resource_availability_state_enum` |
| Services | Catalogue lifecycle | `service_status_enum` |
| Integration | Payment execution | `integration_txn_status_enum` |
| Orchestration | Queue transit | `orch_queue_status_enum` |
| Coordination | Consensus fan-in | `coord_consensus_status_enum` |
| Scenario Modelling | Sandbox execution | `model_run_status_enum` |
| Presentation | Command translation | `present_translation_status_enum` |

No state machine anywhere on the platform reorders, skips, or bypasses a declared stage — the ordinal position of every enum value above is itself constitutional text, not incidental.

---

# PART III — THE FOURTEEN-PHASE ENGINE INSTALLATION LIFECYCLE

*[Trace: TBOC Article 59.3; FDN-001 Annex E]*

No engine is operational until all fourteen phases complete and installation certification is recorded. Reproduced here exactly as FDN-001 Annex E established it — unusual designations included, never "corrected" by assumption, per TBOC Article 59.3's own instruction:

**0 Extensions · 1 Schema · 2 Enums · 3 Tables (engine tables, engine event outbox, engine event inbox) · 4 Constraints · 5 Relationships · 6 Functions · 7 Triggers · 8 Row Level Security · 9 Indexes · 10 Views · 11 Privilege Lockdown · 12 Validation · 13 Finalization.**

Every one of the eleven engines' DDL sections (Section 2 of each engine specification) follows this exact phase order internally: extensions and enums first, domain tables next, then constraints/functions/triggers embedded per table, RLS immediately after each table's creation, and indexes, privilege lockdown, and validation gathered at the section's close — FDN-001's own Annex H is the fullest worked demonstration, compiling all 92 Foundation tables in this order for its own engine.

---

# PART IV — MIGRATION, CONNECTION & PERFORMANCE DISCIPLINE

*[Trace: TBOC Article 59.4; FDN-001 Annex B]*

## 4.1 The Nine Column Conventions (binding on every table, all eleven engines)

| Convention | Rule |
| --- | --- |
| Identity | Every identity primary key: `UUID PRIMARY KEY DEFAULT gen_random_uuid()` |
| Foreign keys | Always UUID, named `<table_singular>_id`; **same-engine only** — a cross-engine reference is always by value, never `REFERENCES` |
| Institutional numbers | TRS026-prefixed, issued only by `sequence_generator` (Foundation Substrate) |
| Money | `NUMERIC(18,2)`, paired with `currency CHAR(3) DEFAULT 'KES'` on every central ledger-of-record table |
| Time | `TIMESTAMPTZ NOT NULL DEFAULT now()` — no local time, anywhere |
| Immutability | Registries, audit trails, and evidence ledgers: `REVOKE UPDATE, DELETE` at the database level; operational ledgers that legitimately transition (availability ledgers, event envelopes) are correctly left mutable — immutability is applied by judgment, not blanket rule |
| Traceability | Every table carries a `-- [Trace: ...]` comment header naming its constitutional parent |
| Row-Level Security | Enabled on every table, no exception, with an explicit policy — never left to default-deny alone |
| Secrets | Never a raw value anywhere in the platform database; only `integration_credential_reference` (Engine 6) may hold a vault *pointer*, and even that table carries no `platform_read` policy |

## 4.2 Cross-Engine Reference Discipline

No engine reads or writes another engine's tables (TBOC Article 33). Verified programmatically across all eleven engines this platform-build: every `REFERENCES` clause in every `CREATE TABLE` statement resolves only to a table sharing its own engine's prefix. A polymorphic cross-engine subject (e.g. a resource, order, or user referenced from an audit or advisory table) is always a plain `UUID` column with a sibling `_type`/`_engine_code` discriminator, never a foreign key.

## 4.3 Row-Level Security Role Pattern

Two roles per engine, uniformly named `trs026_eng{NNN}_{abbrev}_service` (Foundation alone uses `trs_fdn_service`, and its Audit sub-engine `trs_fdn_audit_service`, since Foundation is not itself numbered among the eleven). Every table carries at minimum a service-write policy (`FOR ALL TO <engine>_service USING (true) WITH CHECK (true)`); governed reference data additionally carries a `platform_read` policy open to `trustride_authenticated`; personal or financial data instead carries a narrower `self_read`/`requester_read`/`recipient_read` policy scoped by `current_setting('app.current_user_id', true)::uuid`.

## 4.4 Index Discipline

Every foreign key column carries a supporting B-tree index; every `idempotency_key` and every `*_code`/`*_key` UNIQUE column is indexed by its UNIQUE constraint; every ledger table indexes its status and timestamp columns for operational querying — the pattern FDN-001 Annex H §N.9 established as the platform-wide default, applied identically in every engine built since.

## 4.5 The Deferred Constraint Trigger Standard

PostgreSQL forbids a subquery inside a `CHECK` constraint. Every cross-row validation on this platform — "an Order must have at least one line," "a workforce unit without fleet hardware must belong to a capacity class that does not require it," "a pillar must bind to the Executive Assistants domain," "a command must be a permitted verb for its shell" — is instead enforced by a `CREATE OR REPLACE FUNCTION ... RETURNS trigger` paired with a `CREATE CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED`, so the same transaction that inserts the parent row may insert its dependents before the check fires at commit.

---

# PART V — TESTING & CERTIFICATION STANDARD

*[Trace: TBOC Article 59.5; FDN-001 §11.5]*

No engine document may be adopted without publishing the twelve-line Conformance Certificate (CC-01 through CC-12) FDN-001 §11.5 established, each line answered PASS, PASS WITH EXCEPTION, or FAIL. A FAIL bars adoption. Every one of the eleven engine specifications carries this certificate as its own closing Annex.

## 5.1 The Structural Test Suite

Beyond the narrative certificate, every engine's DDL is mechanically verified before adoption, against four binding tests:

1. **FK ordering test** — every `REFERENCES` target must already be defined earlier in the same migration, or be a valid self-reference; a forward reference is a migration-blocking defect, caught before it reaches production.
2. **CHECK-subquery test** — no `CHECK (...)` clause anywhere may contain `SELECT`; any match is a hard defect requiring the Part IV.5 trigger pattern.
3. **Primary-key uniqueness test** — every table declares exactly one `PRIMARY KEY`.
4. **Money Law test** — every column matching `*_kes*` or paired with a `currency` column resolves to exactly `NUMERIC(18,2)`.

These four tests were run against every engine built this platform-cycle and found two real defects before adoption — a missing `CREATE TABLE` for a table already referenced by foreign key (Engine 5), and two CHECK-subquery violations (Engines 2 and 3) — both corrected under this same standard before certification.

## 5.2 Documentation-Accuracy Testing

Every numeric claim a document makes about itself (a stated table count, a stated "all N tables carry RLS") is verified by counting the actual `CREATE TABLE` statements and `ENABLE ROW LEVEL SECURITY` clauses, never asserted from memory. Two documentation-accuracy defects (a stale "twelve tables" claim in one engine, a stale "eleven tables" claim after another engine's own bug fix added a table) were caught this way and corrected.

---

# ANNEX — TRACEABILITY MATRIX (TEES PART → TBOC PARENT)

| TEES Part | TBOC Parent Article |
| --- | --- |
| Part I (Data Homes) | Article 59.1 |
| Part II (Governed State Machines) | Article 59.2 |
| Part III (Fourteen-Phase Installation Lifecycle) | Article 59.3 |
| Part IV (Migration, Connection & Performance Discipline) | Article 59.4 |
| Part V (Testing & Certification Standard) | Article 59.5 |

---

**END OF INSTRUMENT**

*TEES is not a new invention — it is the discipline already proven, table by table, across 236 tables and eleven engines, written down once so the next engineer never has to re-derive it.*
