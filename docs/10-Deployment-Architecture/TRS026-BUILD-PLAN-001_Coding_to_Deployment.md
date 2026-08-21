## Document Control

| Document Control Field | Entry |
| --- | --- |
| Document Title | TrustRide Services — Coding & Deployment Plan: From Specification to Production |
| Document Identifier | TRS026-BUILD-PLAN-001 |
| Version | 1.0.0 |
| Status | PROPOSED — Engineering Execution Plan, for Founder review and phase-gate approval |
| Classification | Institutional Blueprint — Confidential |
| Basis | Built entirely from the eleven adopted engine specifications and the Four-Sovereign Framework (TBOC/SAPC/TEES/TISC); introduces no new business rule — every technology and sequencing choice below serves an already-constituted requirement |
| Platform Code | TRS026 |
| Founder | Onyango Albert Chitayi, Founder & Chief Executive Officer |
| Date of Issue | 2026-08-16 |
| Companion Document | TRS026-FINAL-REPORT-001 (Corpus Validation & Platform Readiness) |

---

# PART I — TECHNOLOGY STACK

Every choice below is selected because it directly serves a constitutional requirement already in the specification, not for its own sake.

| Layer | Choice | Why this, per the specification |
| --- | --- | --- |
| **Database** | PostgreSQL 15+, via **Supabase** | Every table already assumes `gen_random_uuid()`, native `ENUM` types, `JSONB`, Row-Level Security, and PostgreSQL's own trigger/function model — this is Postgres-native DDL throughout, not an ORM abstraction. Supabase gives managed Postgres, RLS-aware client libraries, built-in Auth (mappable to Foundation's `platform_users`/`auth_session`), and Edge Functions for the service-role logic each engine's `_service` role needs. |
| **Backend runtime** | TypeScript on Node.js (Supabase Edge Functions + a small set of always-on services for Orchestration/Coordination) | Matches the signal-envelope JSON payload model directly; strong typing for the ~236 table shapes reduces the single largest class of integration bugs. |
| **API layer** | REST, matching each engine's own Section 3 API contracts verbatim | The specification already defines every endpoint's request/response shape — implement it as written, not as a fresh design exercise. |
| **Signal transport (Engines 7/8)** | Postgres `LISTEN/NOTIFY` + a small dedicated worker process for queue leasing (`orch_signal_queue`, `orch_queue_lease`), backed by Postgres row-locking (`FOR UPDATE SKIP LOCKED`) for the lease mechanism | The specification's queue/lease/checkpoint tables are already the durable source of truth; Postgres-native locking gives exactly the "workers lease, never own" semantics §2.5 of Engine 7 requires, without introducing a second system of record (Kafka/RabbitMQ) that would violate "one sovereign system" (SAPC Part V.2). |
| **Frontend** | React (web shells: Admin Console, Sovereign Executive Console, Marketplace Hub) + React Native (mobile shells: User Hub, Operator App) | Five shells, two form factors — a shared TypeScript type layer generated from the Postgres schema (via `supabase gen types typescript`) keeps all five in sync with the same 236-table ground truth. |
| **Hosting** | Supabase (managed Postgres + Auth + Storage + Edge Functions); Vercel or similar for the web shells; standard app-store distribution for the two mobile shells | Minimizes infrastructure surface area TISC would otherwise have to separately constitute. |
| **Payment/verification/messaging rails** | Exactly as TISC/Engine 6 name them: M-Pesa C2B STK Push (primary), Flutterwave (secondary), NTSA verification API, KRA eTIMS, SMS/WhatsApp/Push gateways | No substitution — these are constitutional business law (TBOC Article 43), not implementation choices. |

---

# PART II — REPOSITORY STRUCTURE (THE MODULAR MONOLITH, IN CODE)

**This is not a greenfield decision.** The repository already exists — `omnex-ke` (GitHub: `omnex-ke/omnex-ke`), specifically `enterprise-account/technologies-research/research-engineering-office/04-projects/TrustRide Services Platform/` — governed by the Engineering Office's own `PROJECT_REPOSITORY_STANDARD.md` (ADR 0001, revised by ADR 0002). That standard already mandates the canonical top-level shape:

```
TrustRide Services Platform/
├── docs/            # the twelve-document governed hierarchy this Build Plan itself lives in (docs/10-Deployment-Architecture/)
├── database/        # schema, migrations, functions, procedures, triggers, views, enums, policies, seed data — see Part IV
├── backend/         # APIs, services, business logic, auth, integrations, background jobs, event processing, validation, tests
├── frontend/         # web, mobile, desktop, components, pages, themes, assets, UX — the five shells
├── shared/           # DTOs, contracts, shared types, utilities, constants, validation
├── infrastructure/   # Docker, CI/CD, GitHub workflows, Terraform, monitoring, deployment, logging, backup, DR
├── tech-stack/       # the stack decisions this Part I records, split across the already-scaffolded *_STACK.md files
├── ai/               # prompts, skills, agents, context, memory — AI engineering assets for this project
└── supabase/         # already linked locally (config.toml, migrations/, .branches) — see Part III
```

**Engine boundary inside `backend/services/`:** since the constitutional modular-monolith principle (SAPC Part V.2) forbids a fragmented service constellation, the eleven engines are **subfolders of one deployable backend**, not eleven repositories or eleven Supabase projects — `backend/services/engine-01-foundation/` through `engine-11-presentation/`, each holding that engine's service-role functions, Edge Function handlers, and triggers. `backend/integrations/` is the **only** location permitted to import an external HTTP client library — the literal enforcement of TISC's "only Integration touches the outside world" law, checked by lint rule, not convention alone.

No new top-level folder is proposed here — the Engineering Office CLAUDE.md is explicit that the workspace (and each project's shape within it) is a closed baseline; this plan populates the existing structure, it does not redesign it.

---

# PART III — ENVIRONMENT SETUP (STEP BY STEP)

**Two Supabase projects, not three** — confirmed against the Supabase free-tier project limit, and already provisioned: `trustride-dev` and `trustride-production`, both under the `omnex-ke` organization, `eu-central-1`. There is no separate `trustride-staging` project. Staging-equivalent verification happens *inside* `trustride-dev` (a dedicated schema or a Supabase branch, promoted only after passing the full Part VI test suite) before anything reaches `trustride-production`. Revisit a third project only if/when the org upgrades off the free tier — not before.

1. **`trustride-dev`** — all Phase 1–6 implementation work, integration testing, and the pre-production verification pass all happen here. Never share its credentials with production.
2. **`trustride-production`** — receives only migrations and Edge Functions that have already passed the full Part VI suite against `trustride-dev`. No direct hand-edits.
3. **Local development**: `supabase start` (the CLI local stack) already exists at `TrustRide Services Platform/supabase/` — `config.toml`, `migrations/`, and `.branches/` are already present; extend `config.toml` with the platform's own extensions (`pgcrypto`, `postgis`) matching every engine's own §2.0 Extensions block, rather than reinitializing.
4. **Secrets**: Supabase service-role key, M-Pesa/Flutterwave sandbox credentials, NTSA/KRA API credentials — stored in Supabase's own Vault and the CI/CD provider's secret store, never in a `.env` file committed to the repository. This is the literal implementation of Engine 6's `integration_credential_reference` law: even in development, no raw secret lives in a table or a tracked file.
5. **Promotion discipline, two-project reality**: local → `trustride-dev` (every migration, every PR) → `trustride-production` (tagged release only, manual approval gate — see Part VII). No migration is ever written directly against `trustride-production`.

---

# PART IV — DATABASE MIGRATION EXECUTION ORDER

Migrations run in **exactly this order**, matching the constitutional build order and each engine's own Annex E fourteen-phase sequence internally:

| Step | Engine | Source of the DDL |
| --- | --- | --- |
| 1 | Extensions (`pgcrypto`, `postgis`) | Any engine's §2.0 — idempotent, run once |
| 2 | Engine 001 Foundation, full 92 tables | FDN-001 Annex H (already compiled, migration-ready) |
| 3 | Engine 002 Resources | Engine 2 §2.0–2.12 |
| 4 | Engine 003 Services | Engine 3 §2.0–2.9 |
| 5 | Engine 004 Business | Engine 4 §2.0–2.11 |
| 6 | Engine 005 Cost | Engine 5 §2.0–2.6, §3.2–3.6 (note: `cost_formula_matrix` must be created before `cost_rate_card_rule`, per the corrected table order) |
| 7 | Engine 006 Integration | Engine 6 §2.0–2.12 |
| 8 | Engine 007 Workflow Orchestration | Engine 7 §2.0–2.20 |
| 9 | Engine 008 Workflow Coordination | Engine 8 §2.0–2.26 |
| 10 | Engine 009 AI/ML Advisory | Engine 9 §2.0–2.12 |
| 11 | Engine 010 Scenario Modelling | Engine 10 §2.0–2.12 |
| 12 | Engine 011 Presentation | Engine 11 §2.0–2.11 |
| 13 | Privilege lockdown (Phase 11 of every engine) | Create every `trs026_eng{NNN}_{abbrev}_service` role, grant per Part IV.3 of TEES |
| 14 | Seed data | Every `INSERT` statement already embedded in each engine's own DDL (capacity classes, macro domains, priority policies, shell capability registry, etc.) |

Since every cross-engine reference is by value (never a foreign key), **this order is not strictly required for referential integrity** — but it is required for operational sanity (an engine's own seed data and internal self-references do have real FK dependencies, already validated forward-reference-clean within each engine in Part II of the Final Report). Deviating from it gains nothing and risks confusion; follow it exactly.

---

# PART V — BACKEND IMPLEMENTATION SEQUENCE

Build in the same order as the specification was written, because each engine's implementation is genuinely easier once its upstream dependencies exist to test against.

## Phase 1 — Foundation Services (Weeks 1–3)
Implement Foundation's service-role functions: user registration, authentication session issuance, the sequence generator (institutional numbering), the routing rule table, the audit log hash-chain function. **Exit criterion:** a test user can be created, authenticated, and produce one hash-chained audit row.

## Phase 2 — Core Business Runtime, Direct-Call Shim (Weeks 4–9)
Implement Engines 2 (Resources), 3 (Services), 4 (Business), 5 (Cost) **with a temporary direct-call shim standing in for Orchestration/Coordination** — i.e., one engine's Edge Function calls another's directly in this phase only, to unblock parallel development of business logic before the full Sovereign Processing Unit exists. **This shim must be explicitly flagged as temporary in code and removed before Phase 4.** Exit criterion: a full Order → Assignment → Quote flow works end-to-end via direct calls.

## Phase 3 — Integration (Weeks 8–11, parallel with Phase 2)
Implement Engine 6 against sandbox credentials for M-Pesa, Flutterwave, NTSA, KRA eTIMS, and an SMS/WhatsApp provider. Exit criterion: a sandbox STK push completes and produces a `PAYMENT_SETTLED` signal.

## Phase 4 — The Sovereign Processing Unit (Weeks 10–15)
Implement Engine 7 (queue, lease, retry, priority, audit, telemetry) and Engine 8 (admission, dependency, consensus, recovery, finality, intelligence) for real. **Remove the Phase 2 direct-call shim** and re-route every signal through the real outbox → queue → lease → dispatch → inbox → ACCEPT path. This is the highest-risk phase — budget the most review time here, and do not proceed to Phase 5 until the full signal envelope conformance tests (Part V below) pass on every engine pair.

## Phase 5 — Advisory & Modelling (Weeks 14–17, parallel with late Phase 4)
Implement Engines 9 and 10. These have no write access to any other engine's schema (verified structurally in the Final Report), so they carry the lowest integration risk and can be built in parallel with Phase 4's hardening.

## Phase 6 — Presentation & the Five Shells (Weeks 12–20, parallel start with Phase 4)
Implement Engine 11's command-capture/projection-render backend first, then build the five frontend shells against it, starting with User Hub and Operator App (the ride-hailing core), then Admin Console, then Sovereign Executive Console and Marketplace Hub.

---

# PART VI — TESTING STRATEGY

## 6.1 The Automated Structural Test Suite (run on every migration, every PR)

Exactly the five checks the Final Report ran manually — automate them as a CI gate using the same regex/parse approach, run against the actual migration files rather than the specification markdown once code exists:

1. FK ordering (no forward reference within a migration)
2. CHECK-subquery ban (fail the build if found)
3. Primary-key discipline (exactly one per table)
4. Cross-engine foreign-key ban (fail the build if any `REFERENCES` crosses an engine prefix)
5. Money Law (every `NUMERIC` column matching `*_kes*` must be `(18,2)`)

## 6.2 Unit Tests
Per engine, per table: every trigger function, every deferred constraint trigger (the fleet-requirement check, the Executive-Assistants subordination check, the shell-capability check, the Order-scope check), tested for both the pass and the fail path.

## 6.3 Integration Tests
Per signal pair already catalogued in the Final Report's signal matrix: emit the signal, assert it is queued, leased, dispatched, accepted, and produces the documented state change — for every one of the ~18 cross-engine signal pairs already verified consistent on paper.

## 6.4 Conformance Certification
Before any engine's code is marked production-ready, run its own Annex Conformance Certificate (CC-01 through CC-12) against the *running system*, not just the specification — e.g. CC-06 ("idempotency, retry, dead-letter declared") should be proven by actually sending a duplicate signal and confirming it is absorbed, not just citing the `idempotency_key UNIQUE` constraint.

## 6.5 End-to-End User Journeys
At minimum: (a) Customer places a Transport order, is assigned a Boda Boda, receives a quote, pays via M-Pesa sandbox, rates the trip; (b) Operator accepts a Job, updates status, completes it; (c) Governor reviews an AI/ML Advisory recommendation and accepts it; (d) a Cost margin breach triggers an anomaly flag visible on the Admin Console.

---

# PART VII — CI/CD PIPELINE

1. **On every pull request:** lint, structural test suite (Part VI.1), unit tests, migration dry-run against a fresh ephemeral Postgres instance.
2. **On merge to `main`:** deploy migrations + Edge Functions to `trustride-dev`; run the full integration and end-to-end suites there — `trustride-dev` is carrying both development and pre-production verification duty, since only two Supabase projects exist (Part III).
3. **On a tagged release:** deploy to `trustride-production`, gated by manual Founder/Governor approval — mirroring the Sovereign Executive Console's own "rule on exceptions" authority; no production deployment is fully automated end-to-end.
4. **Rollback discipline:** every migration is additive-only in production (matches the platform-wide "correction is a new signal/row, never an edit of history" law) — a bad migration is fixed forward with a new migration, never rolled back destructively against live data.

---

# PART VIII — ROLLOUT SEQUENCING

| Stage | Scope | Gate to proceed |
| --- | --- | --- |
| **Internal pilot** | Kisumu HQ staff only, Transport domain only, User Hub + Operator App | Phase 1–4 backend complete, structural + integration tests green |
| **Closed pilot** | Small cohort of real Kisumu riders/operators, Transport + Courier | 2 weeks incident-free on internal pilot; SOS/emergency path tested live |
| **Soft launch** | All five macro domains, Kisumu County only | Payment rail live (not sandbox); eTIMS invoice generation confirmed with KRA |
| **General availability** | Full Kisumu County rollout, Marketplace Hub live | 30 days soft-launch data reviewed by Engine 9 Advisory for anomalies |
| **Geographic expansion** | Additional counties, per `jurisdiction_enum`/`geo_zone` already governed in the schema | Founder decision, informed by Engine 10 Scenario Modelling capacity projections |

---

# PART IX — POST-LAUNCH OPERATIONS

- **Observability:** Orchestration's `orch_capacity_snapshot`/`orch_queue_metrics` and Coordination's `coord_coordination_health` feed a live operations dashboard on the Admin Console — this is not new work, it is wiring the already-specified telemetry tables to a chart.
- **Incident response:** Foundation's `system_incident` and `security_event` tables are the system of record; the Admin Console's "Operational Controls" surface is where Governors act on them.
- **Continuous conformance:** re-run the Part VI.1 structural suite on every schema change, forever — this is the TEES Part V.1 discipline, operationalized as a permanent CI gate rather than a one-time audit.
- **Amendment discipline:** any schema change discovered necessary in production is proposed as a new versioned amendment to the relevant engine specification first (mirroring FDN-001's own Amendment Register pattern), then implemented — never the reverse.

---

**END OF PLAN**

*Eleven engines were specified in order because the order matters less for the database than for the humans building it. Build Foundation first because everything needs it. Build the Sovereign Processing Unit fourth because it needs something to move before it's worth building. Ship Kisumu before the world, because that is what "more than a ride" actually requires: getting the first one right.*
