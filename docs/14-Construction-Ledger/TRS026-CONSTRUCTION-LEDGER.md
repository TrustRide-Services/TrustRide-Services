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
