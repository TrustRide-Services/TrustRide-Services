# TRS026 Construction Ledger — Master Construction Directive (Remediation Closure)

Directive: *Master Construction Directive — Remediation Closure, System-Wide Orchestration, Engine 006
Integration and Production Readiness* (Founder, received 2026-10-12). Production deployment is **not
authorized** by it. This ledger records, per work package, what was done, changed objects, tests and
results, evidence, blockers and the next step. It is updated after every work package so execution can
resume without repeating work.

Evidence outside the repository: `%TEMP%\audit\wp\` on the build machine (copied into the final report's
evidence folder at WP11).

## WP0 — Baseline (2026-10-12)

| Fact | Verified value | Source |
|---|---|---|
| Repository | `main` at `e80c6ad`; clean except `frontend/web/.gitignore` (pre-existing, adds `.env*`) and two untracked e2e artefacts | `git status`, `git log` |
| Migrations | 66 files, `20260823000001` … `20261011000037`; local = remote on staging | `supabase migration list --linked` |
| Staging identity | ref `fdkzewkogkujtwvonesn`, name `trustride-stagging`, eu-central-1, org `tbcxcgtlkrmxwuhbkzhf`, **linked**; production `iesmxwbcskceajjaqyan` exists and is **not linked, not touched** | `supabase projects list` (by ref, not display name) |
| Engine 5 baseline (staging) | 456 fingerprint entries (455 + the staging-only orphan function), sha256 prefix `dc768cf01dc031c` | `E5_staging_baseline_WP0.csv` |
| Engine 7/8 specifications | `docs/04-Platform-Engine-Registry/engine-07-orchestration/…Blueprint.md` (806 lines), `engine-08-coordination/…Blueprint.md` (878 lines) | repository |
| Local stack | Docker Desktop was not running at start (machine restarted); started | — |
| Staging suites at baseline | 23 suites, 562 passed, 0 failed | `supabase/tests/run.sh linked` (2026-10-12) |

Engine 8 scope, from its blueprint §1.1 and §4: *"No fan-out or fan-in signal completes without passing
through Engine 8; no one-to-one signal needs to."* Engine 8 never routes a signal, never writes another
engine's tables, never authors business truth; it admits, holds dependencies, governs consensus, recovery
and finality, and hands back to Engine 7 through `coord_execution_release`.

**WP0 disposition: Implemented and verified** (baseline matches the 11 October report).

## WP1 — Residual forensic exceptions (2026-10-12)

| Exception (11 Oct) | Root cause found | Disposition | Evidence |
|---|---|---|---|
| A3 I3 "advancing a completed job again is refused" → TRANSLATED | **Probe assertion wrong.** The job was COMPLETED; the assigned operator's next step to VERIFIED is the designed lifecycle (proof row "Verification + release", Operator → System). | Correct invariant encoded: another operator cannot advance; the assigned operator verifies; nothing advances a VERIFIED job | Suite 24 (3 checks) green on staging and local |
| A3 I4 "approval settles the order" → RECEIPT_GENERATED | **Probe assertion wrong.** `business_payment_status_enum` = INITIATED > AUTHORIZED > SETTLED > LEDGER_POSTED > RECEIPT_GENERATED > FAILED; RECEIPT_GENERATED is the final success state. | Correct invariant encoded: final state RECEIPT_GENERATED, exactly one settled transaction, second approval and retry refused | Suite 24 (3 checks) |
| A7 "revoked key refused at ingestion" | **Probe assertion wrong** (looked for "unauthor"; outcome is `UNAUTHENTICATED`). The key was refused. | Correct invariant encoded: UNAUTHENTICATED and no location event written | Suite 24 (2 checks) |
| Browser j5 8/9 | **Test logic wrong for a fresh run**: it asserted the company could book before j6 adds the company's phone. The system correctly refuses (one verified phone per identity incl. organisations, D3). | j5 now asserts the refusal and its reason; j6 asserts booking is enabled once the phone is verified | `tests/e2e/j5_followup.js`; full fresh run at WP11 |
| Proof 43/44 (Database integrity) | **Assertion compared incidental text**: the Boda fleet ledger *reason* had to equal `BOUND_TO_WORKFORCE_UNIT` verbatim; after Office maintenance (j15) it reads `OFFICE: Service completed`. The proof's own stated invariant is "motorcycle still bound to its unit". | Assertion now checks state ASSIGNED **and** binding to Otieno's active unit | Proof rerun: **44/44 PASS**, TRS026-ORDER-000000017 (`proof-wp1.json`) |
| Six historical queue entries without inbox record | **Real effect found**: the capacity snapshot counted all DISPATCHED entries as in flight, so these six inflated `signals_in_flight` permanently. | Migration 038: `orch_queue_historical_exception` (append-only) registers them (staging: exactly 6, 26/28 Aug, Engine 11); in-flight count excludes registered entries. Rows kept DISPATCHED; no outcome invented | Suite 24 (2 checks); staging query: 6 registered = 6 DISPATCHED |
| audit_log 2 dangling links; orch audits 19 forks each | Historical, recorded in `platform_audit_chain.legacy_detail` (029). | Kept as unrecoverable historical evidence; verification and seals start at each chain's rebase point, so they cannot affect current verification (suite 16) | `fn_platform_audit_chain_verify(TRUE)` clean on staging |

Changed: `supabase/migrations/20261012000038_engine007_historical_queue_exceptions.sql`, `supabase/tests/24_residual_invariants.sql`,
`tests/e2e/j5_followup.js`, `tests/e2e/proof.js`.
Suite 24: red on staging (9/10 — only the new register missing; I3/I4/A7 invariants already hold), green 11/11 local and staging.

**WP1 disposition: Implemented and verified**, except j5's corrected step, which is exercised in the WP11 fresh regression.

## WP2 — External audit seals (2026-10-12)

| Item | Result |
|---|---|
| Migration 039 `platform_external_audit_seal` | Seal record `trustride.audit-seal/v1`; export, receipt (payload hash must match, retention must be in the future), event (failures alert the Office, critical), chain rows with canonical text, hourly watchdog (silent until a destination is activated). Service-role only. Receipts and events append-only |
| Suite 25 | Red on staging (functions absent) → **15/15** local and staging |
| Publisher / verifier | `ops/audit-seal/` (Node, AWS SDK v3 `@aws-sdk/client-s3` 3.637.0), designed to run in a separate administrative domain |
| End-to-end proof | `ops/audit-seal/e2e-local.mjs` against MinIO DEVELOPMENT.2025-05-24 (image `bitnamilegacy/minio@sha256:451fe685…a349c`), Object Lock COMPLIANCE: **11/11 PASS** — publish+receipt; verify 8 chains; delete, retention-shortening and replacement refused; failed write reported and alerted, never receipted; retry succeeded; consistent owner-level rewrite invisible in-database but **detected by the external seal** (VERIFY_MISMATCH at the sealed position); restored and re-verified. Evidence `WP2_external_seal_e2e_result.json` |
| AWS S3 destination | **Not activated** — no AWS account or credentials exist on this machine or in the project. Activation steps, IAM policy and limits in `ops/audit-seal/README.md` |
| Retention | Proposal: COMPLIANCE, 2,555 days (7 years) — awaiting Founder approval |

**WP2 disposition: Implemented and verified (simulator-backed, independent S3-compatible store); Blocked by external dependency for the AWS destination** (AWS account, bucket with Object Lock, IAM role, scheduler). Independent tamper detection is **not** operational on staging until a real seal is retained and verified there.

## WP3 — Statutory EA pricing on the live path (D24) (2026-10-12)

**Live path traced.**

1. BookingForm (EA services take a zone and hours).
2. `RAISE_INTENT` → `fn_business_service_order_place` (Engine 4: validates, stamps the shift).
3. Matching → `fn_business_resource_reserved_accept` (builds the pricing lines).
4. Engine 2 `fn_resource_assign` passes the lines on unchanged.
5. Engine 5 `fn_cost_resource_dispatch_initiated_accept`. Its EA branch called the established
   `fn_cost_ea_labor_calculate` (EA-LABOR-1.0.0).
6. `fare_quote` → `FARE_QUOTED` → the customer accepts.
7. Payment: the STK amount is `ceil(quote)`.
8. Settlement is for the quote total.

**Change (migration 040, Founder-authorized §2.1).**
- **Engine 4.** An EA line records its booking unit (HOURS, or DAYS 1–6 with hours per day) and
  its real start (`start_at`). Limits are refused at the order. Pricing lines now carry the full
  `scope_detail`.
- **Engine 5.** New `fn_cost_ea_statutory_calculate` rates each EA line with `fn_cost_ea_engagement_rate`
  (EA-STATUTORY-1.0.0). It writes the canonical `fare_calculation` (model `EA-STATUTORY-1.0.0`), one
  calculation line per cited price line, a `cost_record`, and links the estimate.
- **Dispatch accept.** The EA branch of `fn_cost_resource_dispatch_initiated_accept` now calls it.
  Text diff: only lines 60–65 changed; the transport branch is identical (`dispatch_accept_diff.txt`).
- **Non-bypass.** The `fn_cost_ea_quote_statutory_guard` triggers on `fare_quote` and `fare_quote_line`
  refuse any EA quote from another equation.
- **Engagement basis.** `WORKER_ENGAGEMENT_BASIS` = CASUAL_EMPLOYEE is set IN_FORCE: Operators are
  employees (directive §4.2).
- **Migration 041 (Engine 11).** The order view and job card show days. The booking form adds
  "by the hour / by the day" and states the legal basis.

**Legal gate.** Patient/elder caregiver and corporate representative have no gazetted occupation
(mapping `NEAREST_OCCUPATION_PENDING_FOUNDER`). Their services (EA-CAREGIVING-GENERAL,
EA-ERRANDS-SCHOOL_VISITATION, EA-SHOPPING-REPRESENTATION_DELIVERY) are **refused with the reason, not
priced**, until the occupation is determined.

**Evidence.**
- Suite 26 red on staging (live quote EA-LABOR 334.32 for 3 h errands) → **17/17** locally and on staging.
- Suite 04 now expects the gate for the three services. All 26 suites on staging: **606/606**.
- Browser j16 **6/6**: 2 days × 8 h booked on screen, KES 3,812.51 = statutory estimate, shown as
  "2 days × 8 hours", declined without charge.

Before and after on staging, same inputs (`EA_before_after_examples.txt`):

| Booking | EA-LABOR (old) | EA-STATUTORY | Worker legal pay |
|---|---|---|---|
| Errands 3 h | 334.32 | 650.40 | 484.02 |
| Cleaning 4 h | 500.00 | 867.20 | 645.36 |
| Driving 3 h | 600.00 | 883.98 | 657.84 |
| Chef 8 h | 1,231.76 | 1,886.20 | 1,403.68 |
| Errands 2 days × 8 h | not bookable | 2,333.93 | 1,736.88 |

**Engine 5 change report** (staging fingerprint, WP0 → after): 456 → 464 entries.
- **Added 8:** `fn_cost_ea_statutory_calculate` and its ACL, `fn_cost_ea_quote_statutory_guard` and its
  ACL, the two triggers, the estimate→calculation FK and its index.
- **Changed 2:** `fn_cost_resource_dispatch_initiated_accept` (EA branch only), and the
  `cost_ea_engagement_estimate` columns (+`calculation_id`).
- **Removed 0.** Every transport function, rate, registry, zone, model and component is identical.
- Outside the fingerprint: one `cost_ea_rating_rule` row status.

**WP3 disposition: Implemented and verified** for the six trades with a gazetted occupation.
**Awaiting Founder/legal decision**: the occupation for patient/elder caregiver and corporate
representative (recommendation in the final report).
Not yet surfaced in the booking form: the statutory method's TRAVEL, SUBSISTENCE and at-cost lines
(supported by Engine 5; the form offers labour by hour or day).

## WP4 — System-wide Engine 7/8 coordination (2026-10-12)

**Specifications read.** Engine 7 blueprint (806 lines), Engine 8 blueprint (878 lines), FDN-001 `routing_rule`.
Engine 8 governs only fan-out and fan-in executions; one-to-one signals pass through Engine 7 alone.

**Inventory (live function catalogue).**
- 55 outbox emission sites and 48 active routes. All 48 are handled by their destination inbox (checked against the handler source).
- Six fan-out executions (order placed, service resolved, resource assigned, fleet verified, marketplace sale, advisory anomaly) and one fan-in (Engine 5 pricing needs the service context).
- Direct cross-engine calls were classified. Synchronous state-changing calls kept, with reasons: marketplace listing (atomic sale), quote lock and finalize (atomic with the job; Engine 5 protected), Office fleet registration, routing read.
- Two dormant handlers (`VENDOR_VERIFICATION_UPDATED`, `ZONE_SURGE_TRIGGERED`) are never emitted.
- Document: `docs/15-Engine-Interaction-Inventory/ENGINE_7_8_INTERACTION_INVENTORY.md`.

**Defects found.**
- The dispatch cycle called `fn_coord_admission_check` for every signal and **ignored its answer**: a DEFERRED signal was dispatched anyway.
- 14 of 18 Engine 8 runtime functions were never called.
- Engine 5 pricing failed an order (NO_SERVICE_CONTEXT_CACHED) if the dispatch arrived before the service context.
- Duplicate executions ran twice.

**Specification gap, recorded.** The blueprints say the routing rule marks fan-out and fan-in, but
FDN-001 `routing_rule` has no such column. Engine 8's own `coord_admission_policy` is used as the
declaration; no Foundation table was altered.

**Migration 042.**
- **Declarations.** Policies for the fan-out signal types; `coord_dependency_rule` (RESOURCE_DISPATCH_INITIATED → E05 requires SERVICE_CONTEXT_RESOLVED → E05, hold 300 s).
- **`fn_coord_govern`.** Admission once per signal; exactly-once fingerprint; workflow context and stages; dependency hold, release, failure and timeout; consensus hold, commit, abort and not-opened timeout. It writes nothing while a signal stays held.
- **`fn_coord_finalize`.** Stage outcome, execution completion with certificate, release to Engine 7. A failed branch marks the workflow FAILED and records a TERMINATE recovery and a critical runtime alert.
- **`fn_orch_dispatch_cycle`.** Engine 8 decides first. HELD stays PENDING; a refusal goes to DEAD_LETTER with a dead-letter review row and an Office alert; the unconditional admission call is removed; finalize runs after every handler.

**Evidence.**
- Suite 27: red on staging (3 of 8 passing: a dispatch was delivered without its context, duplicates ran twice, no hold) → **17/17** locally and on staging. Covered: delayed delivery held then released, refused prerequisite, overdue prerequisite, duplicate refused, consumer failure finalized and alerted, consensus COMMIT and ABORT, nothing written while held, a real order fully coordinated with one-to-one signals bypassing Engine 8, and every routed signal terminal.
- Staging: 27 suites **623/623**; the live dispatch cycle succeeded 89 of 89 times in the first 15 minutes after the push.
- Integrated proof **44/44** on TRS026-ORDER-000000022 (`proof-wp4.json`). The first attempt failed at its precondition (the rider was still AVAILABLE after the "End shift" step). It was not reproducible: "End shift" was verified by hand and the rerun passed.

**WP4 disposition: Implemented and verified.** Engines 7 and 8 coordinate every declared fan-out and fan-in.
Retained synchronous cross-engine calls are documented. Converting them to signals would be an
architecture decision for the Founder, not done here.
