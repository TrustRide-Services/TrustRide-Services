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

## WP5 — Orphan function `cost_quotes_block_illegal_mutation()` (D19) (2026-10-12)

**Scan (staging, `WP5_orphan_dependency_scan.txt`).**
- Nothing uses it: 0 pg_depend references, 0 triggers, 0 event triggers, 0 policies, 0 views, 0 cron jobs.
- No other function names it (including dynamic SQL), and no repository code does.
- No migration creates it (030 mentions it in a comment only), and the clean rebuild does not contain it.
- It is executable by its owner (postgres) only.

**Purpose.** It is the Engine 5 blueprint's quote-immutability guard, written for a table named
`cost_unit_price_quotes` that does not exist. The same invariant is enforced on the real `fare_quote`
by `fare_quote_block_illegal_mutation()` through `trg_fare_quote_block_illegal_mutation`, with
identical logic. Removing the orphan disables no protection.

**Removal (migration 043).** Guarded and repeatable:
- a no-op on a clean rebuild;
- refuses to drop if anything now depends on the function, or if the `fare_quote` guard is missing;
- the definition and ACL are kept in the migration as the forensic record.

**Evidence.**
- Suite 17 red on staging (3 of 4 passing; the orphan was present) → 4/4. Suites 10 and 04 green.
- Engine 5 fingerprint diff: exactly one entry removed (the orphan).
- Full catalogue comparison: staging = clean rebuild, 8,147 objects each. Nothing differs except the
  known presentation-only differences (policy text printing, ACL order).

**WP5 disposition: Implemented and verified.** D19 closed completely.

## WP6 — EPRA fuel prices and live routing as pricing inputs (2026-10-12)

**Research.**
- **EPRA** publishes no API and no machine-readable feed. Maximum retail prices are announced monthly
  for the cycle from the 15th to the 14th (Petroleum Act 2019 s.101(y), L.N. 192 of 2022), by press
  statement on its website and social channels.
- **Current Kisumu cycle** (15 Sep – 14 Oct 2026): super petrol KES 213.69, diesel 218.08, kerosene
  191.63 per litre, VAT inclusive. Sources: Citizen Digital and Kenyans.co.ke reporting of the EPRA
  review. The next review is due on 14 October.
- **Routing.** No provider account exists. Options: OpenRouteService (OSM, self-hostable, with a free
  hosted tier), HERE, Mapbox, Google. Official pricing and storage terms were not verified in this
  session. The provider choice is the Founder's.

**Found in Engine 5 (not changed; stopped per directive 4.5).** The blueprint's EPRA derivation is
already built: `fn_cost_epra_fuel_index_ingest` sets R_d = pump price ÷ km per litre + maintenance
per km and versions rates. But it applies **any** fuel type to **every** fuel-consuming rate and
ignores jurisdiction, because `cost_rate` carries neither. At the September Kisumu prices R_d would
fall 9–20%:

| Vehicle | R_d now | Derived from petrol | Derived from diesel |
|---|---|---|---|
| Boda | 12.00 | 9.61 | 9.73 |
| Tuk-tuk | 18.00 | 15.18 | 15.40 |
| Sedan | 28.00 | 23.81 | 24.17 |
| Pickup | 35.00 | 31.74 | 32.23 |
| Van | 42.00 | 36.71 | 37.26 |
| Truck | 55.00 | 50.62 | 51.35 |

**Defect found and fixed in Engine 6.** The EPRA simulator emitted `EPRA_FUEL_INDEX_UPDATED`, so a
simulated price re-derived live rates. Proven red on staging: boda R_d moved 12.00 → 9.36 inside the
rolled-back test.

**Migration 044.**
- **EPRA recording.** `RECORD_EPRA_PRICE_CYCLE` (Office) → `fn_integration_epra_cycle_record` stores
  each cycle with its source, URL, publication date and the person who recorded it. It validates the
  15th–14th cycle, the source, fuel type, jurisdiction, a plausible range (80–400 KES/L) and conflicts;
  a duplicate is idempotent; recording is audited.
- **Current price.** `fn_integration_epra_current` returns no price outside a cycle, so a stale value is
  never served. A daily freshness watch alerts the Office when the current cycle is missing.
- **Engine 5 gate.** Nothing is sent to Engine 5 while `EPRA_RATE_DERIVATION_ACTIVE` = FALSE. The
  simulator no longer emits.
- **Routing provenance.** Every route records provider, reference, retrieval time and whether it was
  simulated. Terrain is recorded as unknown for provider routes, never invented.
- **Live routing path.** Only a current, unsuperseded provider route from `integration_route_matrix`
  (fresh for 30 days) is used. Otherwise `ROUTING_UNAVAILABLE` is raised and a refresh requested,
  one in flight at a time. `fn_integration_route_matrix_apply` refuses malformed, unknown-zone or
  simulator responses as a whole and treats a repeated response as idempotent.
- **Register.** ROUTING stays NOT_BUILT, pending the provider choice. EPRA is recorded but not applied.

**Evidence.**
- Suite 28 red on staging (0 of 3 passing: simulated price re-derived rates, no recording, no
  provenance) → **25/25** locally and on staging.
- Suite 21 updated: routing's live path now fails with `ROUTING_UNAVAILABLE`.
- Staging: 28 suites, **651/651**.

**Noted, not changed (Engine 5).** `fn_cost_fare_calculate` labels any supplied terrain multiplier
`LIVE_ROUTING` in its cost record, including the simulator's hash-derived one (staging only). The
routing log now carries the true provenance.

**WP6 disposition.**
- **Partially implemented.** The Engine 6 side is implemented and verified.
- **Awaiting Founder decision:**
  1. approve the Engine 5 derivation correction (fuel type and jurisdiction per rate) and the fare impact before EPRA feeds pricing;
  2. choose the routing provider; its gateway adapter and account follow.
- **Pending (WP8):** the Office screen form for recording an EPRA cycle. The command works today.

## WP7 — Operating-company integrations (2026-10-12)

### WP7(a) Identity and business verification through MetaMap (decision 2.6)

**Facts verified (MetaMap GovChecks documentation).**
- `ke/iprs` takes a document number, first name and last name. It returns names, gender and date of birth, or
  `kenyanIprs.notFound`. It returns **no vital status and no KRA PIN**.
- `ke/brs` takes a registration number. It returns the company name, type, status, KRA PIN and shareholders
  (each with an identity number), or `kenyanBrs.notFound`.
- Authentication: OAuth client credentials, with a bearer token of about one hour. A callback URL is optional.
  No signature scheme is published for GovChecks callbacks, and no sandbox host is documented.
- MetaMap has no NTSA, driving-licence or KRA PIN check for Kenya.

**Migrations.**
- **045 (vocabulary).**
  - New identity outcomes: `RECORD_FOUND_STATUS_UNKNOWN`, `NOT_FOUND`, `PROVIDER_UNAVAILABLE`.
  - New outbound operations: `IDENTITY_VERIFY`, `ENTITY_VERIFY`, `VEHICLE_LOOKUP`.
- **046 (live path).**
  - With the port off the simulator, a verification becomes one IPRS or BRS request to the gateway and
    stays PENDING until the provider answers.
  - The answer is mapped factually:

    | Provider answer | Recorded as |
    |---|---|
    | Person found (IPRS) | `RECORD_FOUND_STATUS_UNKNOWN`, with no KRA PIN invented |
    | Company registered/active (BRS) | `VALID`, with the KRA PIN BRS returns |
    | notFound | `NOT_FOUND` |
    | systemError, or retries exhausted | `PROVIDER_UNAVAILABLE` |

  - Foundation's existing onboarding rules decide the outcome; they are unchanged.
  - Each answer is applied once.
  - Callbacks go to `fn_integration_metamap_webhook_ingest` (service role only).
  - The simulator path is unchanged.
- **047 (defects found by suite 29 on staging after 046, fixed forward).**
  - Shareholder identity numbers were still kept, in the outbound request's stored answer and in the callback
    log. Only the shareholder count is kept now (Data Protection Act s.25(c)).
  - A callback arriving after TrustRide had given up was answered APPLIED. It is now `ALREADY_FINAL`.

**Gateway (Edge Functions, deployed to staging).**
- `integration-gateway/metamap.ts`: OAuth with token reuse and early renewal, then the documented IPRS and BRS
  requests, with a 20 s timeout.
  - A record or a notFound is a definitive answer.
  - A timeout, a network failure, HTTP 5xx, systemError or an OAuth rejection is retried.
  - SANDBOX refuses to run without a host supplied by MetaMap.
- `index.ts`: routes the two operations and gains a default branch, `OPERATION_NOT_SUPPORTED`.
- `metamap-webhook`: the callback endpoint, protected by a URL token (`METAMAP_WEBHOOK_TOKEN`).
- No MetaMap secrets exist. On staging, the gateway and the webhook both answer 403 to unauthenticated calls.

**Evidence.**
- Suite 29 red on staging (live path absent; then the 2 defects fixed in 047) → **16/16** locally and on staging.
  It covers:
  - the request payload;
  - PENDING until the provider answers;
  - the found / notFound / unavailable mapping;
  - retry before failing;
  - one application per answer;
  - late and unknown callbacks;
  - BRS verified;
  - shareholders kept nowhere;
  - a simulator answer is never a verification;
  - only the service role can ingest callbacks.
- Adapter tests (Node, mocked fetch): **13/13**. Type-check of the edge code: clean.
- Staging after 045/046: 29 suites, **664/664**.
- Engine 5 fingerprint before and after: identical (463 rows).

**Disposition.**
- **Implemented to the extent the documentation supports.** It has not been exercised against MetaMap, because
  no account exists.
- **Register.** IDENTITY_AUTHORITY: MetaMap is the vendor, the live adapter stays NOT_BUILT and readiness is
  NOT_WIRED_PENDING_DECISION. The port cannot be switched live (suite 21).
- **Awaiting a Founder decision.** The person onboarding rule requires `ALIVE_VALID` and a returned KRA PIN,
  but MetaMap IPRS supplies neither. Until the rule is decided, every live person verification would fail.
- **External prerequisites:**
  - a MetaMap account (client ID and secret);
  - the webhook token;
  - ODPC registration;
  - MetaMap's written confirmation of a sandbox host and of its callback format.

### WP7(b) NTSA vehicle identification by VIN or chassis number (decision 2.7)

**Facts.**
- NTSA publishes no API for plate or VIN/chassis lookup; access to its records needs an agreement with NTSA or a
  licensed gateway. No endpoint is invented and nothing is scraped.
- TrustRide records no VIN or chassis number on vehicles today; the NTSA port checked plates only (simulator).

**Migrations.**
- **048:** check type `VEHICLE_IDENTIFICATION` (own transaction).
- **049:** `fn_integration_ntsa_vehicle_identify(type, identifier)`, the Engine 6 boundary.
  - Validates before any lookup:
    - VIN: 17 characters without I, O or Q (ISO 3779). The check digit is not enforced, since it is North American only.
    - Chassis/frame number: 5–25 letters, digits and hyphens (e.g. NZE141-6012345).
  - Normalises the identifier.
  - Answers from the simulator: marked simulated, no make, model, owner or plate invented; the `00` suffix means not found.
  - Logs every lookup.
  - Refuses with `PROVIDER_NOT_INTEGRATED` in a live mode.
  - Office command `NTSA_VEHICLE_LOOKUP` (Founder or Administrator); the function is not callable by signed-in users directly.
  - Register: NTSA stays NOT_BUILT / SIMULATOR_ONLY_PENDING_PROVIDER; the blocking dependency names the VIN/chassis lookup.

**Evidence.** Suite 30 red on staging (boundary absent) → **19/19** locally and on staging. Suites 01, 03, 13,
17 and 21 are green on staging.

**Disposition.**
- **Implemented (boundary and simulator).**
- **External prerequisite:** an NTSA access agreement or a licensed gateway, then the gateway adapter.
- **Pending (WP8):** an Office form for the lookup. Capturing VIN/chassis at vehicle registration is a Foundation
  change not requested by the directive; noted for the Founder.

### WP7(c) Google email (decision 2.8)

**Facts.** The database side already existed: an EMAIL notification becomes `NOTIFY_EMAIL` on EMAIL_SERVICE, and the
gateway refused it with "provider not selected".

**Built.** `integration-gateway/gmail.ts` sends through the Gmail API (`users.messages.send`, `gmail.send` scope).
- **Authentication, two modes:**
  - a Google Workspace service account with domain-wide delegation (RS256 assertion);
  - an OAuth refresh token, which works for any Google mailbox, including @gmail.com.
- **Message format:** RFC 5322 text, UTF-8 base64, RFC 2047 subjects.
- **Refused before any call:** header injection (line breaks) and malformed recipients.
- **SANDBOX:** Gmail has none, so the adapter delivers only to `GMAIL_SANDBOX_RECIPIENT` and refuses without it.
- **Failures:** every failure is reported as a failure; a 401 drops the token.

**Migration 050.** EMAIL_SERVICE becomes BUILT / LIVE_READY_PENDING_CREDENTIALS (vendor Google). The port stays on the
simulator until the Office switches it.

**Evidence.** Adapter tests 10/10; suite 31 email checks red → green on staging.

**External prerequisites.**
- The mailbox, and which mode applies: Workspace or consumer Gmail.
- The credentials as Edge secrets.
- If consumer Gmail: a sending limit of about 500 a day, and the OAuth app must be published, or refresh tokens
  expire after 7 days.

### WP7(e) Hardening: Daraja, Africa's Talking, WhatsApp, Protrack

**Defects found and fixed (gateway).**
1. **Money lost on an ambiguous outcome.** Any error after an M-Pesa request had been sent (timeout, dropped
   connection) was reported as a definite failure. A B2C payout Safaricom had accepted would be recorded FAILED with
   no Office alert, and its later result ignored as already final.
   - Fixed: such an outcome is now "unknown" and is not reported. The request stays SENT, so Safaricom's result can
     still settle it; otherwise Engine 6's sweep closes it and tells the Office to verify on the M-Pesa portal.
     Nothing is re-sent.
   - The database side of this path was correct but untested. Suite 31 now covers it.
2. **No timeouts.** No provider call had one; every call now has 20 s.
3. **Protrack poll failed open.** With credentials missing it signed `md5("undefined")` and called Protrack. It now
   fails closed.
4. **Malformed Protrack push.** It returned 502 and half-read the body; it now returns 400.
5. **Validation before money or messages move:**
   - Kenyan mobile numbers (E.164 for SMS and WhatsApp; 2547/2541 for Daraja);
   - Daraja amounts must be whole shillings of at least 1, sent as a JSON number;
   - configuration is checked before any call.
6. **Gateway secret and router.** The gateway refuses when its own secret is unset. The router gains
   `OPERATION_NOT_SUPPORTED` for unknown operations.

**Structure.** Provider code moved unchanged into `providers.ts`, `router.ts` and `protrack-ingest/protrack.ts`, free
of Deno globals so it is testable. `index.ts` keeps only HTTP and reporting.

**Evidence.**
- Edge tests (Node, mocked fetch): **50/50** across MetaMap, Gmail, providers/router and Protrack. Type-check of all
  edge functions: clean.
- Suite 31: **12/12** on staging (the 9 money checks were green before any change; they now guard the gateway's new
  reliance on them).
- Suites 02, 05, 15 and 21 are green on staging.
- Deployed to staging (Docker bundler; the API bundler returned an internal error). Probes:

  | Call | Result |
  |---|---|
  | Gateway, no secret | 403 |
  | Protrack push, no key | 401 |
  | Protrack push, bad key | 401 |
  | Protrack push, malformed | 400 |
  | Protrack poll, no secret | 403 |
  | MetaMap webhook, no token | 403 |

**Open item (security).** Protrack's documented API base is plain `http://`, so the access token travels unencrypted in
the query string. `PROTRACK_API_BASE` switches to HTTPS once Protrack confirms it is served there.

**Noted.** STK amounts are rounded up to whole shillings (e.g. 650.40 → 651) by Engine 6, as before; the customer pays
up to 99 cents more than the quote. Unchanged, for the Founder's awareness.

### WP7(d) eTIMS and payroll/PAYE as separate capabilities (decision 2.4)

**eTIMS: defect found.** The existing simulator imitated KRA. It minted "KRACU…" control-unit numbers and a
`https://etims.kra.go.ke/verify?…` link, a simulation that looked like a real KRA document. Proven red on staging.
No flow called it.

**Migrations 051 and 052 (Engine 6).**
- **Tax treatment.** Every invoice records `tax_treatment = UNDETERMINED`, the only value allowed. The caller must
  state the amount basis (FULL_FARE, COMMISSION or OTHER); none is assumed. TrustRide computes no VAT.
- **Determination gate.** `ETIMS_TAX_DETERMINATION = PENDING_LEGAL_DETERMINATION`. Outside the simulator a sale is
  refused with `ETIMS_TAX_DETERMINATION_PENDING`. Nothing is sent towards KRA and no KRA endpoint is assumed.
- **Simulator.** References are now `SIM-…`, with no QR code and no KRA link. Rows written earlier were relabelled
  the same way.
- **Sales.** One invoice per order and basis; a repeat with a different amount is refused, because a correction is a
  credit note, not an edit. A rejected submission is kept with its reason.
- **Purchases.** Supplier invoices are recorded with the supplier's control-unit number, once each (Office command
  `RECORD_PURCHASE_INVOICE`, audited).
- **Reconciliation.** `fn_integration_etims_reconcile` reports four findings:
  - invoices without a settlement;
  - rejected submissions;
  - full-fare amount mismatches;
  - settled orders without an invoice. These are reported, not issued; what to issue waits for the determination.
- Suite 21's eTIMS check now accepts the determination refusal, which is the governing one.

**Payroll/PAYE.** The system holds no payroll data today: no salaries, pay runs or P10 returns.
- **Migration 053 (Engine 4, which owns pay and payouts).** Statutory rates are versioned, immutable data, each item
  with its legal source:
  - PAYE bands: 10 / 25 / 30 / 32.5 / 35%, with band limits at 24,000 / 32,333 / 500,000 / 800,000;
  - personal relief: 2,400;
  - NSSF: 6% + 6% up to 108,000;
  - SHIF: 2.75%, minimum 300;
  - Housing Levy: 1.5% + 1.5%.
- **Housing Levy deductibility is UNCONFIRMED.** Without a stated treatment the calculator refuses; with one, the
  result is PROVISIONAL.
- **Confirmation.** The Founder alone records the professional confirmation, with its reference
  (`CONFIRM_PAYROLL_STATUTORY_SET`). Results are final only after that.
- Rates cannot be edited in place; a change is a new set.

**Evidence.**
- Suite 32 red on staging (KRA imitation; capability absent) → **24/24** locally and on staging.
- Suite 33 red on staging → **18/18** locally and on staging. Its worked examples were computed by hand first
  (e.g. 50,000 gross, levy deductible: PAYE 5,845.85, net 39,029.15).
- Suites 01, 05, 13, 14, 17, 18, 19 and 21 are green.

**Disposition.** Both capabilities are implemented as far as decision 2.4 allows.
- **Awaiting the Founder:**
  - the eTIMS legal and tax determination;
  - professional confirmation of the payroll rates, including the Housing Levy treatment;
  - the payroll model (who is paid what, and when) before pay runs, P10 and bank files are built.
- **External prerequisites:** KRA eTIMS OSCU/VSCU onboarding, sandbox testing and certification against KRA's
  published specification.
