## Document Control

| Document Control Field | Entry |
| --- | --- |
| Document Title | System Architecture & Platform Constitution (SAPC) |
| Document Identifier | TRS026-SAPC-001 |
| Version | 1.0.0 |
| Edition | Genesis Edition |
| Status | ADOPTED — Sovereign Constitutional Instrument, Second of the Four-Sovereign Framework |
| Classification | Institutional Blueprint — Confidential |
| Constitutional Authority | Inherits from TBOC v2.0.0 Genesis Edition (TRS026-TBOC-001) per TBOC Article 58 — Lineage into SAPC |
| Framework Position | Second Sovereign — System Architecture & Platform Constitution |
| Derives From | TRS026-TBOC-001 v2.0.0 Genesis Edition, Article 58 |
| Governs | Digital-twin domain resolvers, modular monolith architecture, schema layouts, the sovereign eleven-engine registry |
| May Never Contain | Business rules not traceable to TBOC; execution-detail syntax belonging to TEES (data migrations, connection pooling, deployment scripts) |
| Jurisdiction | Republic of Kenya |
| Platform Code | TRS026 |
| Platform Name | TRUSTRIDE_SERVICES |
| Founder | Onyango Albert Chitayi, Founder & Chief Executive Officer |
| Date of Issue | 2026-08-16 |
| Constituent Instruments | This Master Instrument, plus the eleven full engine specifications it indexes (Part VI), each independently adopted and each carrying full traceability to TBOC |

---

## Constitutional Authority & Position in the Four-Sovereign Framework

This instrument is the **second** of TrustRide Services' four sovereign documents, subordinate to and wholly descended from TBOC v2.0.0 Genesis Edition (TRS026-TBOC-001), which is the Parent Root and supreme governing authority. SAPC governs *how the platform is architected* in service of what TBOC has already constituted; it invents nothing TBOC has not already named.

Per TBOC Article 58 (Lineage into SAPC), this instrument must express, in architecture language, six TBOC mandates — and does so in Parts I through V below, each Part naming its exact TBOC parent:

| SAPC governs | TBOC parent |
| --- | --- |
| The digital twin doctrine | TBOC Article 9, via Article 58.1 |
| The identity chain and five User Type Domains | TBOC Articles 11–12, via Article 58.2 |
| The five macro domains → service catalogue structure | TBOC Section 4, via Article 58.3 |
| The five presentation shells | TBOC Section 5, via Article 58.4 |
| The sovereign eleven-engine registry | TBOC Article 58.5, Annex I Amendment A-001 |
| The modular monolith principle | TBOC Article 58.6 |

Per TBOC Article 61 (The Inheritance Rules), every provision below names its parent TBOC article; no concept in this instrument originates here.

---

# PART I — THE DIGITAL TWIN DOCTRINE

*[Trace: TBOC Article 9, via Article 58.1]*

Every business process of TrustRide Services has exactly one digital representation. The platform does not exist independently of the business it represents — the physical estate, the fleet, the workforce, and every commercial transaction each have exactly one digital twin, held by exactly one engine, in exactly one table.

SAPC's architectural expression of this doctrine is the **domain resolver**: for any physical or business fact, there is exactly one engine whose schema is the lawful place that fact resolves to. FDN-001's Annex B, Rule "No concept without a home" (inherited from TBOC Article 8.3), is SAPC's own enforcement of this doctrine at the schema level — a concept appearing in two engines' schemas is a constitutional defect, not a design choice.

# PART II — THE IDENTITY CHAIN & FIVE USER TYPE DOMAINS

*[Trace: TBOC Articles 11–12, via Article 58.2]*

**Identity (Person / Entity / Thing) → User → User Type → Role → Intent → Engagement → Service / Order.**

This chain is realized entirely within Engine 1 (Foundation), TRS_FDN_IDENTITY sub-engine: `person_profile`, `entity_profile`, and `thing_registry` are each UNIQUE-bound to exactly one `platform_users` row, for life. The five User Type Domains — Customer, Partner, Operator, Intermediary, Governor — are never a second identity; they are the engagement-scoped context recorded in `user_type_binding`, per engagement, never per identity.

No engine downstream of Foundation is permitted to register a second identity root. Engine 4 (Business)'s `business_actor_registration` is the constitutional proof: every row there is a reference into Foundation's `platform_users`, never an independent identity.

# PART III — THE FIVE MACRO DOMAINS → SERVICE CATALOGUE STRUCTURE

*[Trace: TBOC Section 4 (Articles 23–29), via Article 58.3]*

Transport, Courier, Delivery, Executive Assistants, Marketplace — exactly five, no sixth without a TBOC amendment. SAPC's architectural expression is Engine 3 (Services)'s `service_macro_domain` table, seeded with exactly five rows and structurally protected: `service_pillar`'s deferred constraint trigger enforces that the Executive Assistants pillars (Errands, Driving, Caregiving, Cleaning, Chef, Shopping) remain permanently subordinate to their macro domain, never elevated to a sixth.

Every catalogued Service (`service_catalogue`) resolves to exactly one of the five domains; every special intent (Academy training, employment application, vendor onboarding, resource contribution, Own Marketplace acquisition/listing/sale) resolves to a catalogue Service, per TBOC Article 18, never to an invented parallel path.

# PART IV — THE FIVE PRESENTATION SHELLS

*[Trace: TBOC Section 5, via Article 58.4]*

User Hub, Operator App, Admin Console, Sovereign Executive Console, Marketplace Hub — exactly five, registered in Foundation's `shell_registry` and structurally isolated in Engine 11 (Presentation). SAPC's architectural expression is the Surface Law (FDN-001 §11.4, restated in full at Part V.5 below): each shell's permitted verbs are enforced at the database level by Engine 11's `present_shell_capability_registry`, not left to client-side convention.

# PART V — THE SOVEREIGN ENGINE REGISTRY

*[Trace: TBOC Article 58.5, Annex I Amendment A-001]*

This Part is SAPC's core: the eleven-engine registry is constituted and held final within SAPC under TBOC's supremacy. It is a constitutional architectural constraint — expansion of implementation detail is authorized; structural redesign is not. Any apparent insufficiency escalates to the Founder and is never an invitation to redesign.

## 5.1 The Eleven-Engine Registry

**Canonical order:** 001 Foundation → 002 Resources → 003 Services → 004 Business → 005 Cost → 006 Integration → 007 Workflow Orchestration → 008 Workflow Coordination → 009 AI/ML Advisory → 010 Scenario Modelling → 011 Presentation.

All eleven engines attach to the single canonical `trustride` PostgreSQL schema; engine namespaces are logical ownership prefixes, not separate database schemas — the constitutional expression of Part V.2's modular monolith principle.

## 5.2 The Modular Monolith Principle

*[Trace: TBOC Article 58.6]*

One sovereign system. Engines are constitutional modules, never a fragmented service constellation. No engine is a separately deployable microservice with its own database; all eleven share one schema, one signal substrate, and one platform identity, distinguished only by table-name prefix and Row-Level Security policy.

## 5.3 Plate I — The Station Law

*[Trace: FDN-001 §11.2]*

Every engine — the Foundation included — is internally a **five-station machine**: Domain State Table → Emission Ledger (Outbox) → Bridge Transit (Orchestration order; Coordination fan-out/fan-in/timing) → Reception Ledger (Inbox) → Lawful State Mutation, executed only after inbox ACCEPT. No engine may add a sixth path or skip a station. Every table in every one of the 236 tables across the eleven engines carries the identical canonical Signal Envelope: `signal_id`, `correlation_id`, `causation_id`, `emitting_engine`, `receiving_engine`, `signal_type`, `payload_in`, `payload_out`, `signal_status`, `rejection_reason`, `idempotency_key`, `attempt_count`, `emitted_at`, `received_at`, `accepted_at`.

## 5.4 Plate II — The Five-Layer Register

*[Trace: FDN-001 §11.3]*

| Layer | Engines | Obligation | Prohibition |
| --- | --- | --- | --- |
| 1 — Foundation | 001 | Provide identity, authority, audit, vocabulary, geography, sequence, signal substrate to all layers | Holding business rules of resources, services, orders, or pricing |
| 2 — Business Runtime | 002, 003, 004, 005, 006 | Consume identity/authority from Layer 1; never re-implement it | Reading Layer 1 tables directly; owning a second user table |
| 3 — Workflow Management (Hybrid Bridge) | 007, 008 | Carry every cross-engine signal, in order, with heartbeat health published | Authoring domain truth; transforming a payload beyond routing metadata |
| 4 — AI Advisory | 009, 010 | Read lawful projections; write recommendations as records only | Any write to authoritative state, ever, under any urgency |
| 5 — Presentation | 011 and the five shells | Render lawful projections; convert user intent into signals | Any direct database write; holding truth the ledgers do not hold |

## 5.5 Plate III — The Surface Law

*[Trace: FDN-001 §11.4]*

Commands become signals; views are lawful projections, registered and non-authoritative; every shell displays bridge heartbeat honestly; offline emission is first-class, with the on-device queue owned jointly by Layer 3 (Founder Ruling AQ-002); one identity, one account, one lifetime — no shell ever creates an identity of its own.

---

# PART VI — THE ELEVEN-ENGINE INDEX

Each engine below is independently adopted, fully specified, and carries its own complete Document Control, DDL, API contracts, signal matrix, and Conformance Certificate. This index is a summary only; the full specification governs in the event of any discrepancy, per the ordinary rule that a summary never outranks its source.

## Engine 001 — Foundation (TRS_FDN)

**Mission:** The substrate every other engine depends on — Core, Identity, Governance, Audit, and the Shared Runtime Substrate. **Tables:** 92, across five sub-engines (Core 14, Identity 31, Governance 16, Audit 7, Substrate 15) plus 4 event tables and 5 conformance tables. **Status:** ADOPTED, migration-ready (Annex H full DDL compilation). **Full specification:** `Engine_Specifications/01_Engine1_FDN-001_Foundation/`

## Engine 002 — Resources (TRS026_ENG002_RESC)

**Mission:** Custodian of every business resource — fleet, equipment, physical estate, workforce operating units, Own Marketplace inventory while held for trade. Answers: what capacity exists, and is it lawful to dispatch. **Tables:** 11. **Status:** ADOPTED v1.0.1. **Full specification:** `Engine_Specifications/02_Engine2_Resources/`

## Engine 003 — Services (TRS026_ENG003_SERV)

**Mission:** The authoritative catalogue of everything TrustRide may lawfully offer, across five macro domains. Answers: is this a registered Service, and under what terms. **Tables:** 10. **Status:** ADOPTED v1.0.1. **Full specification:** `Engine_Specifications/03_Engine3_Services/`

## Engine 004 — Business (TRS026_ENG004_BUS)

**Mission:** The Order primitive and the business-layer registration of the five User Type Domains, driven through the seven constitutional lifecycle stages. Answers: what was requested, by whom, under what terms, and is it settled. **Tables:** 12. **Status:** ADOPTED v1.0.1. **Full specification:** `Engine_Specifications/04_Engine4_Business/`

## Engine 005 — Cost (TRS026_ENG005_COST)

**Mission:** The dynamic financial calculation engine executing the Sovereign Dynamic Cost Equation, producing one immutable, hash-chained unit-price quote per trip. **Tables:** 12. **Status:** ADOPTED v1.1.1. **Full specification:** `Engine_Specifications/05_Engine5_Cost/`

## Engine 006 — Integration (TRS026_ENG006_INTG)

**Mission:** TrustRide's sole boundary with the outside world — payment rails, verification providers, the tax authority, the fuel-price regulator, messaging gateways. The only engine permitted to hold credential references. **Tables:** 13. **Status:** ADOPTED v1.0.0. **Full specification:** `Engine_Specifications/06_Engine6_Integration/`

## Engine 007 — Workflow Orchestration (TRS026_ENG007_ORCH)

**Mission:** The platform's sequencing authority — every signal, from every engine's outbox, resolved, queued, leased, and dispatched deterministically. Half of the Sovereign Processing Unit. **Tables:** 21. **Status:** ADOPTED v1.0.0. **Full specification:** `Engine_Specifications/07_Engine7_Orchestration/`

## Engine 008 — Workflow Coordination (TRS026_ENG008_COORD)

**Mission:** Distributed execution governance — admission, dependency, consistency, consensus (the many-to-one fan-in, governed by the Founder's own AQ-003 timeout ruling), recovery, and constitutional finality. The other half of the Sovereign Processing Unit. **Tables:** 27. **Status:** ADOPTED v1.0.0. **Full specification:** `Engine_Specifications/08_Engine8_Coordination/`

## Engine 009 — AI/ML Advisory (TRS026_ENG009_AIADV)

**Mission:** Predictive and pattern-based recommendation, built entirely from lawful read-only projections. Zero write authority into any other engine's schema, structurally enforced. **Tables:** 13. **Status:** ADOPTED v1.0.0. **Full specification:** `Engine_Specifications/09_Engine9_AIML_Advisory/`

## Engine 010 — Scenario Modelling (TRS026_ENG010_MODEL)

**Mission:** The sandbox for exploring a change before it is made — every consumed input snapshotted before analysis, every scenario a record, never a mutation. **Tables:** 13. **Status:** ADOPTED v1.0.0. **Full specification:** `Engine_Specifications/10_Engine10_Scenario_Modelling/`

## Engine 011 — Presentation (TRS026_ENG011_PRESENT)

**Mission:** The only engine a human touches — five constitutional shells, commands become signals, views are lawful projections, per-shell verbs enforced structurally. **Tables:** 12. **Status:** ADOPTED v1.0.0. **Full specification:** `Engine_Specifications/11_Engine11_Presentation/`

---

## Platform Totals

| Metric | Value |
| --- | --- |
| Total engines | 11 |
| Total tables | 236 |
| Money columns | 100% `NUMERIC(18,2)` compliant |
| Row-Level Security | 100% of tables carry an explicit policy |
| Cross-engine foreign keys | Zero — every cross-engine reference is by value only |
| Signal envelope conformance | 100% — every engine's outbox/inbox carries the identical fifteen-field envelope |

---

# ANNEX — TRACEABILITY MATRIX (SAPC PART → TBOC PARENT)

| SAPC Part | TBOC Parent Article |
| --- | --- |
| Part I (Digital Twin Doctrine) | Article 9, via Article 58.1 |
| Part II (Identity Chain) | Articles 11–12, via Article 58.2 |
| Part III (Five Macro Domains) | Section 4 (Articles 23–29), via Article 58.3 |
| Part IV (Five Presentation Shells) | Section 5, via Article 58.4 |
| Part V (Sovereign Engine Registry) | Article 58.5, Annex I A-001 |
| Part V.2 (Modular Monolith) | Article 58.6 |

---

**END OF INSTRUMENT**

*SAPC is the architecture TBOC's business law was built to stand on. Eleven engines, one schema, one signal shape, 236 tables, zero cross-engine writes — the digital twin made structurally, deterministically real.*
