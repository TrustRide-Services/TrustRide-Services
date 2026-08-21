# TrustRide Operations Runbooks

Practical, command-level procedures — companion to `README.md`'s design-level index. Written
2026-08-19 as part of Production Closure, against the system as it actually exists (not an
aspirational design). Every command below has been exercised against `trustride-dev` this
session unless marked otherwise. `<ref>` = the target project ref
(`trustride-dev` = `rozeklhbnegvtuxbrdgm`; `trustride-production` is a separate, not-yet-wired
project — see "Environment separation" below before ever targeting it).

---

## Deployment

**Migrations:**
```bash
supabase link --project-ref <ref>          # confirm which project is linked before anything else
supabase migration list --linked           # confirm exactly which migrations are pending
supabase db push --linked                  # applies pending migrations only, in order
supabase migration list --linked           # confirm the push landed
```
The `db push` command reliably prints a non-fatal `pg-delta catalog caching` timeout warning
after migrations have already applied successfully — this is a known local quirk, not a real
failure. Always confirm via `migration list`, never trust the push command's own exit alone.

**Edge Functions:**
```bash
supabase functions deploy <slug> --project-ref <ref>              # verify_jwt=true functions
supabase functions deploy mpesa-callback --project-ref <ref> --no-verify-jwt   # MUST use this flag --
                                                                    # a plain deploy silently restores
                                                                    # JWT verification and breaks every
                                                                    # Safaricom callback (see config.toml's
                                                                    # own [functions.mpesa-callback] block,
                                                                    # which documents this explicitly but
                                                                    # does not by itself enforce it on deploy)
supabase functions list --project-ref <ref>                        # confirm ACTIVE status + verify_jwt
```

**Local verification before any deploy** (always do this first):
```bash
supabase stop --no-backup
supabase start --ignore-health-check
cd backend/tests && DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres" ./run_tests.sh
```
`storage`/`pg_meta`/`studio`/`realtime` reporting "unhealthy" briefly after `start` is a known,
harmless local quirk on this machine — not a real failure.

## Rollback

This codebase's own discipline (Build Plan Part VII.4): **forward-fix only, never destructive
rollback against live data.** There is no `down` migration mechanism. If a migration is wrong:
1. Do not attempt to reverse it via `db reset` or manual `DROP`/editing history.
2. Write a new, forward migration that corrects the specific defect (see this session's own
   `20260819100100_settlement_completion_and_reconciliation.sql` for the pattern: `CREATE OR
   REPLACE FUNCTION` supersedes the broken version cleanly).
3. If a migration broke something so badly that the database is in an inconsistent state, this
   is a genuine incident — do not guess a fix live; restore from backup (see below) to a
   known-good point, then reapply corrected migrations forward from there.

## Secret rotation

```bash
supabase secrets set --project-ref <ref> SECRET_NAME=<new value>
supabase secrets list --project-ref <ref>     # confirms the name and updated_at changed; NEVER
                                               # prints the value itself -- Supabase's own design
```
After rotating a secret an Edge Function reads via `Deno.env.get(...)`, **no redeploy is
required** — the function reads secrets at invocation time. Confirm the rotation took effect by
exercising the function's real behavior (e.g. for `MPESA_CALLBACK_TOKEN`, confirm the *old*
token now gets rejected and the *new* one is accepted, exactly as done during this session's own
P0.2 verification).

## Daraja failure

**Symptom: STK push request itself fails (never reaches PENDING_CALLBACK).**
- Check `integration_payment_gateway_transaction.txn_status` for the transaction — stuck at
  `INITIATED` means the Edge Function never successfully called Daraja.
- Check the five required secrets are set: `MPESA_CONSUMER_KEY`, `MPESA_CONSUMER_SECRET`,
  `MPESA_SHORTCODE`, `MPESA_PASSKEY`, `MPESA_ENV` — `supabase secrets list --project-ref <ref>`.
- Check Supabase's own Edge Function invocation logs (dashboard → Functions → mpesa-stk-push →
  Logs) for the actual HTTP error Daraja returned (invalid credentials, malformed request, etc).

**Symptom: STK push succeeds but the callback never arrives.**
- This is exactly what the payment timeout reconciliation sweep (below) exists for — a
  transaction stuck at `PENDING_CALLBACK` beyond 5 minutes is automatically transitioned to
  `TIMEOUT` and `PAYMENT_FAILED` is signaled back to Business, every minute
  (`cron.job` `payment-timeout-reconcile`).
- Manually check sooner: `SELECT * FROM trustride.fn_payment_reconcile_report();`

## Callback failure

**Symptom: Safaricom's callback returns 401.** The `MPESA_CALLBACK_TOKEN` query parameter on the
callback URL Daraja was given doesn't match the current secret. Check whether the token was
rotated without redeploying `mpesa-stk-push` (which constructs the callback URL at STK-push
time using the *current* secret value — rotating the token mid-flight for an *already-initiated*
STK push will make that specific transaction's callback fail authentication, by design; this is
the correct tradeoff, not a bug — never weaken the check to work around it).

**Symptom: Safaricom's callback returns 200 but the payment never settles.** Check
`integration_webhook_inbound_log` for the callback's `processing_status` — `REJECTED` means the
`CheckoutRequestID` didn't match any known transaction (a genuine data-integrity concern, escalate);
`DUPLICATE` means this exact transaction was already processed (correct, idempotent, no action
needed); `RECEIVED` with no follow-up `PROCESSED` update means the RPC call itself failed —
check Edge Function logs for the exact error.

## Automatic payment dispatch

As of 2026-08-19 (`20260819110000_automatic_payment_dispatch.sql`), `PAYMENT_STK_TRIGGERED`
signals dispatch automatically -- no manual Edge Function call is needed. The flow:
`fn_orch_run_cycle` (every 10s, `pg_cron`) → `fn_integration_inbox_process` validates the signal,
resolves the requester's phone from `platform_user_phone`, and fires an async `pg_net.http_post`
to the deployed `mpesa-stk-push`, which is the sole caller of `fn_payment_stk_initiate` (this
avoids a double-insert -- see the migration's own header for why that split matters).

**Two things must be true for a dispatch to succeed:**
1. The requester has a phone number on file. As of 2026-08-19
   (`20260819140000_present_phone_capture.sql`), this is a real client-facing command, not just a
   direct RPC: `SET_PHONE_NUMBER` via `fn_present_capture_command`, available on `USER_HUB` and
   `OPERATOR_APP`, self-service, always the caller's own session user (never a payload-supplied
   one). Verified live end-to-end on both `trustride-dev` and `trustride-production` (real user,
   real session, real command → phone stored). The underlying RPC
   (`SELECT trustride.fn_user_phone_set(user_id, '254XXXXXXXXX');`) still exists and is what the
   command calls internally — use it directly only for manual/support intervention, not as the
   normal path once a client exists. No phone on file → the dispatch signal is REJECTED with an
   explicit reason, not silently dropped.
2. Two Vault secrets are provisioned (DB-side Vault, distinct from Edge Function secrets):
   `mpesa_dispatch_base_url` (the project's Functions URL, e.g.
   `https://<ref>.supabase.co/functions/v1`) and `mpesa_dispatch_auth_token` (a valid Supabase
   JWT satisfying `mpesa-stk-push`'s `verify_jwt=true` gate -- the service_role key is the
   correct choice, matching Supabase's own documented pattern for triggering Edge Functions from
   Postgres). Set/rotate via the service-role-only helper, value never touching a file:
   ```sql
   SELECT trustride.fn_admin_vault_secret_upsert('mpesa_dispatch_base_url', '<url>', 'functions base url');
   SELECT trustride.fn_admin_vault_secret_upsert('mpesa_dispatch_auth_token', '<token>', 'service_role JWT for internal dispatch');
   ```
   Missing either → every dispatch is REJECTED with an explicit "not configured" reason until set.

**Diagnosing a stuck dispatch**: `fn_payment_reconcile_report()` now includes a 4th anomaly class,
`DISPATCH_NEVER_INITIATED` -- a `PAYMENT_STK_TRIGGERED` signal ACCEPTED more than 5 minutes ago
with no resulting `integration_payment_gateway_transaction` row. This means the `pg_net` call
never reached `mpesa-stk-push` (network partition, function down, or misconfigured
`mpesa_dispatch_base_url`) -- check Vault config and Edge Function status, then re-fire manually
(see "Daraja failure" below) once the underlying cause is fixed; there is no automatic retry for
a dispatch that never landed.

## Structured logging

`mpesa-stk-push` and `mpesa-callback` emit one JSON line per significant event to stdout
(`_shared/logger.ts`) -- visible in the Supabase dashboard under Functions → *function* → Logs.
Every line has `timestamp`, `level`, `function`, `event`, plus non-sensitive identifiers
(`correlation_id`, `gateway_txn_id`, `checkout_request_id`). Never logged: tokens, keys,
credentials, raw phone numbers -- `logger.ts` redacts any field under a known-sensitive key name
as defense in depth, but callers are still expected to never pass a secret value in the first
place. Key events to search for: `stk_push_requested`, `stk_push_accepted_by_daraja`,
`daraja_stk_push_call_failed`, `unauthorized_callback_attempt`, `callback_processed`,
`fn_payment_callback_process_failed`.

## Alerting

As of 2026-08-19 (`20260819130000_alerting_incident_sweep.sql`), detection now produces real,
queryable incidents instead of requiring a human to remember to run a report. `pg_cron` calls
`fn_admin_alert_sweep()` every 5 minutes, which sweeps 3 of `fn_payment_reconcile_report()`'s 4
anomaly classes (`SETTLED_WITHOUT_BUSINESS_SETTLEMENT`, `DUPLICATE_SETTLED_COLLECTION` — both
`CRITICAL`; `DISPATCH_NEVER_INITIATED` — `WARNING`) into Foundation's `system_incident` table,
deduplicated against any already-open incident for the same anomaly.
`PENDING_BEYOND_NORMAL` is deliberately not swept — it fires for every briefly in-flight payment
by design and is already self-healing within ~5-6 minutes via the existing timeout sweep;
alerting on it would be pure noise, not a real gap.

```sql
SELECT * FROM trustride.system_incident WHERE resolved_at IS NULL ORDER BY started_at DESC;
SELECT trustride.fn_admin_incident_resolve('<incident_id>');   -- after you've acted on it
```

`mpesa-callback` also now writes a `security_event` row (`MPESA_CALLBACK_UNAUTHORIZED_ATTEMPT`)
on a genuine wrong/missing-token attempt (never on a server misconfiguration, which is our own
fault, not a caller-attributable signal) — a repeated pattern here means someone is probing or
guessing the callback URL, previously visible only in stdout logs.

**This is not yet real-time paging.** No Slack/email/SMS/PagerDuty integration exists anywhere in
this codebase, and none has been fabricated — nobody has those credentials. `system_incident` and
`security_event` are real, live, queryable tables (`fn_admin_alert_sweep`/
`fn_admin_security_event_log` proven working identically on `trustride-dev` and
`trustride-production`), but reaching them today still means running the query above or checking
the Admin Console once it reads from these tables. The natural next increment, once a channel is
chosen, is a trigger on `system_incident` INSERT (`WHERE severity = 'CRITICAL'`) firing
`net.http_post` to that channel — the same `pg_net` mechanism already proven for payment dispatch.

## Pending payment

See "Daraja failure" above — the reconciliation sweep (`fn_payment_reconcile_timeouts()`, cron
job `payment-timeout-reconcile`, every minute) is the automated first line. For manual
investigation of a specific order: `SELECT * FROM trustride.integration_payment_gateway_transaction
WHERE order_id = '<order_id>' ORDER BY created_at DESC;`

## Reconciliation

```sql
SELECT * FROM trustride.fn_payment_reconcile_report();
```
Returns three anomaly classes: `PENDING_BEYOND_NORMAL` (still-pending transactions, informational),
`SETTLED_WITHOUT_BUSINESS_SETTLEMENT` (should be structurally impossible — treat any row here as a
genuine incident, investigate the signal pipeline immediately), `DUPLICATE_SETTLED_COLLECTION`
(more than one settled collection for one order — investigate before taking any action; this
function only reports, it never auto-corrects). Any real correction goes through the governed
`business_financial_remedy` mechanism (`fn_financial_remedy_propose` → `fn_financial_remedy_authorize`),
never a direct `UPDATE` — the settled fare and settlement rows are immutable by design.

## Duplicate callback

Already handled automatically — see "Callback failure" above (`DUPLICATE` processing_status).
No manual action needed; this is proof the idempotency design is working, not an incident.

## WhatsApp failure

As of Production Closure (2026-08-19), the WhatsApp adapter (`_shared/whatsapp.ts`,
`whatsapp-send`) is self-flagged unverified against a live number and does not yet persist sends
to `integration_message_dispatch_log` — there is no dispatch history to investigate yet. If
`whatsapp-send` returns an error, check `WHATSAPP_ACCESS_TOKEN`/`WHATSAPP_PHONE_NUMBER_ID` are
set, and check whether the access token (a 60-day temporary token per its own label) has expired
— replace with a permanent System User token before relying on this in production.

## Provider outage (any external system)

Every external call in this codebase lives exclusively behind Engine 6 (`_shared/*.ts` +
the corresponding Edge Function) — confirmed structurally this session (zero cross-engine direct
calls, zero business-engine imports of an HTTP client). A provider outage therefore only ever
manifests as that one Edge Function failing; no other engine's behavior is directly affected.
Business/Cost/Resources continue operating on their own authoritative state regardless — the
order lifecycle up to the point requiring that provider simply stalls at the relevant signal
(e.g., `PAYMENT_STK_TRIGGERED` sitting unprocessed if Daraja itself is down platform-wide, not
just this integration).

## Dead-letter queue

```sql
SELECT * FROM trustride.orch_signal_queue WHERE queue_status = 'DEAD_LETTER';
```
Engine 7's retry policy (exponential backoff, 2s base / 60s cap / 20% jitter / 5 max attempts)
already governs this — a signal only reaches dead-letter after exhausting real retries. Each
dead-lettered signal needs individual investigation (check `orch_retry_history` for every
attempt's failure reason) before any decision to manually reprocess or discard.

## Backup / recovery

Verified 2026-08-19 via `supabase backups list --project-ref rozeklhbnegvtuxbrdgm` (read-only):
```json
{"region":"eu-central-1","walg_enabled":true,"pitr_enabled":false,"backups":[]}
```
**`trustride-dev` currently has no restorable backup of any kind.** `walg_enabled: true` means
the platform's backup *mechanism* (WAL-G) is present, but `pitr_enabled: false` and an empty
`backups` array mean there is nothing to restore from today -- this project is on a tier that
does not provision Point-In-Time Recovery or scheduled snapshots. `supabase backups restore`
requires PITR and was correctly never invoked here: even if it worked, restoring in place against
the only environment holding this project's proof-of-work data would be a destructive action with
no upside over prevention, never something to run without explicit Founder authorization and a
genuine incident.

**What this means operationally**: there is currently no recovery path from data loss or
corruption on `trustride-dev` beyond Foundation's own hash-chained `audit_log`
(`fn_audit_append`), which lets you *reconstruct* what happened but not *restore* prior state.
Enabling PITR requires upgrading the project's billing tier -- a Founder/billing decision, not a
technical one; this is tracked as an open item, not silently worked around.

**Recovery test procedure, once PITR is enabled** (do not run any of this against `trustride-dev`
directly -- restore into a new, separate project and verify there):
1. `supabase backups list --project-ref <ref>` to confirm a restorable point exists.
2. Restore into a **new** project (never in place on the only environment), or use Supabase's
   dashboard-driven restore-to-new-project flow if the CLI does not support a target-project flag.
3. Once restored, run `backend/tests/run_tests.sh` against the restored project's connection
   string as an automatic, objective content-integrity check, then spot-check row counts on a
   few key tables (`business_order`, `integration_payment_gateway_transaction`, `audit_log`)
   against what was expected at the recovery point.
4. Document the actual time-to-restore observed; do not assume it matches any target until timed.

## Database incident

1. Do not run destructive commands against `trustride-dev` or `trustride-production` without
   first confirming which project is linked (`supabase status` / check `supabase/.temp/project-ref`).
2. Foundation's `audit_log` (hash-chained, `fn_audit_append`) is the authoritative record of
   every governed mutation — use it to reconstruct what happened before considering any recovery
   action.
3. See "Backup / recovery" above — as of 2026-08-19 there is no restorable backup on
   `trustride-dev`; a genuine incident today has no path back except audit-log reconstruction.

## Emergency shutdown

There is no dedicated "kill switch" function in this codebase. The safest immediate action to
stop new financial activity without touching existing data:
```sql
-- Revoke the ability for new orders to be placed, without altering any existing state:
REVOKE EXECUTE ON FUNCTION trustride.fn_order_create(
  uuid, text, uuid, text, text, text, numeric, jsonb, uuid, text
) FROM trustride_authenticated;
```
This is a genuinely destructive-adjacent action (blocks all new business) — never do this without
explicit Founder authorization, and reverse it (re-`GRANT`) the moment the emergency is resolved.

**Corrected 2026-08-19 during runbook drilling**: the previously-documented 8-argument signature
(`uuid, text, uuid, text, text, text, numeric, jsonb`) no longer matches `fn_order_create`'s real
signature — it grew two parameters (`p_correlation_id`, `p_job_type`) since this runbook was first
written, and a `REVOKE` against a nonexistent signature fails outright (`function ... does not
exist`). This would have failed at the worst possible moment — mid-emergency. Verify against the
live signature before ever relying on this snippet again:
```sql
SELECT pg_get_function_identity_arguments(oid) FROM pg_proc
WHERE proname = 'fn_order_create' AND pronamespace = 'trustride'::regnamespace;
```

## Production verification

After any deploy to a live project, minimum verification (all commands proven this session):
```bash
supabase migration list --linked                              # migrations landed
supabase functions list --project-ref <ref>                    # functions ACTIVE, verify_jwt correct
supabase secrets list --project-ref <ref>                      # expected secret names present
```
Then a functional smoke test using the committed suite's own patterns (see
`backend/tests/sql/002_order_lifecycle_and_settlement.sql` for the exact real-order fixture
pattern) — run manually against the target project's connection string, never assume local
success transfers to a live deploy without checking (this session's own Daraja pipeline test
found a real, live-only defect — the `trustride` schema not being exposed via the live project's
PostgREST config — that no amount of local testing would ever have caught).

---

## Drill log — 2026-08-19 (runbook verification, non-Daraja)

Every runbook above was exercised against real or synthetic data — either live read-only checks
against both `trustride-dev` and `trustride-production`, or synthetic incidents run inside
`BEGIN...ROLLBACK` on the local stack (zero residue, same discipline as the committed pgTAP
suite). Deliberately out of scope: anything touching Daraja production credentials or config,
per standing instruction while awaiting Safaricom.

**Read-only, both environments — all clean, no drift:**
- Reconciliation report, dead-letter queue, open incidents: empty on both (no false positives).
- Backup/PITR status: unchanged (`pitr_enabled: false`, zero backups, both projects).
- Functions list: `ACTIVE`, correct `verify_jwt`, both projects.
- Production secrets (names only): confirmed **no Daraja production credentials exist on
  `trustride-production`** — the pause is holding.

**Synthetic drills, local stack:**
- **Duplicate callback**: two calls to `fn_payment_callback_process` with the same
  `CheckoutRequestID` → webhook log shows `PROCESSED, DUPLICATE` in order, final `txn_status`
  settles exactly once. Runbook is accurate.
- **Stuck payment → timeout sweep**: a `PENDING_CALLBACK` transaction backdated 10 minutes →
  `fn_payment_reconcile_timeouts()` correctly transitions it to `TIMEOUT`. First pass showed 0
  `PAYMENT_FAILED` signals reaching Business — investigated before concluding anything, not
  reported as a defect: this was an artifact of the drill script not calling
  `fn_orch_run_cycle()` afterward, not a real gap. Re-run with 10 cycles confirmed the signal
  reaches `business_event_inbox` and is `ACCEPTED`, exactly as documented.
- **Reconciliation report**: correctly surfaces a freshly-created pending transaction as
  `PENDING_BEYOND_NORMAL` — the query itself works, not just the schema.

**Real finding, fixed (documentation only, no code/grant change)**: the Emergency Shutdown
snippet's `REVOKE` command used `fn_order_create`'s 8-argument signature from when this runbook
was written — the function has since grown two parameters (`p_correlation_id`, `p_job_type`).
Running the documented command today would have failed with "function does not exist" during an
actual emergency. Corrected above; added a live signature-check command to run before ever
trusting this snippet again.

## Alerting hardening review — 2026-08-19

Reviewed `fn_admin_alert_sweep()` / `fn_admin_incident_resolve()` / `fn_admin_security_event_log()`
for gaps, per the Founder's explicit "identify, do not redesign" instruction. Two findings,
reported here rather than silently fixed:

1. **`fn_admin_incident_resolve()` does not call `fn_audit_append()`.** Every other governed
   mutation in this codebase writes to the hash-chained `audit_log` — resolving an incident
   currently doesn't, which is inconsistent with the project's own established discipline. Narrow,
   one-line fix if authorized (add the same `fn_audit_append` call every other mutation function
   uses); not applied without confirmation first.
2. **`fn_admin_alert_sweep()` has no advisory-lock guard against overlapping runs.** `pg_cron`
   does not itself prevent two runs of the same job overlapping if one takes longer than the
   5-minute interval. Given the underlying query is cheap (a handful of `SELECT`s over what has
   so far always been zero or a few anomaly rows), the practical risk is low today, but is a real
   gap that would worsen if anomaly volume grows. A `pg_try_advisory_lock` guard around the sweep
   body is the standard, narrow fix (same pattern already used elsewhere in this codebase, e.g.
   `fn_present_write_decision_log`'s `pg_advisory_xact_lock(42007)`); not applied without
   confirmation first.

**Not findings, deliberately left as-is**: the dedup mechanism matches on a `LIKE` pattern against
`system_incident.summary` rather than a structured key — technically less precise than a foreign
key, but the practical collision risk (one anomaly's UUID appearing as a literal substring of an
unrelated anomaly's summary text) is astronomically low and not worth a schema change to close.
Severity is currently a fixed mapping per anomaly type with no escalation-on-recurrence logic —
a reasonable simplification for the current scale, not a defect.

## Environment separation

Two Supabase projects exist: `trustride-dev` (`rozeklhbnegvtuxbrdgm`) and `trustride-production`
(`phypuevxwdunesigcfgo`, created 2026-08-09, org `omnex-ke`). Prior versions of this manual and
the closure reports incorrectly stated no production project existed — it did, this repository's
configuration simply never referenced it (`supabase/.temp/project-ref` only ever pointed at dev)
because it had never been inspected against the organization's project list. Corrected 2026-08-19.

**Production promotion status (2026-08-19, complete except real Daraja credentials):**
- **Database**: all 58 migrations applied and confirmed (`supabase migration list --linked` shows
  `remote` populated for every entry). Schema, roles, RLS, functions, triggers, the P0 security
  fix, and the automatic-dispatch bridge are all live on `trustride-production` exactly as
  committed — no divergent or hand-applied state. One migration stalled transiently on first
  attempt (a network hang, not a real error); stopping and retrying resumed cleanly with no
  partial state, since each migration is its own transaction.
- **Edge Functions**: `mpesa-stk-push`, `mpesa-callback` (`--no-verify-jwt`, confirmed
  `verify_jwt=false`), `whatsapp-send` deployed and `ACTIVE`. `whatsapp-diag` deliberately not
  deployed — a throwaway local diagnostic by its own code comment, not part of Engine 6's real
  adapter surface.
- **Data API schema exposure**: fixed via dashboard (Settings → API → Data API → Exposed schemas
  → `trustride` added, matching dev) — confirmed live via a direct read-only REST call (200,
  real data returned). Took roughly 20 seconds to propagate after the dashboard change.
- **Secrets**: a fresh, production-specific `MPESA_CALLBACK_TOKEN` generated and set (never
  copied from dev, never printed). Two Vault secrets (`mpesa_dispatch_base_url`,
  `mpesa_dispatch_auth_token`) provisioned for the `pg_net` dispatch bridge, pointing at
  production's own Functions URL and its own service_role key — independent of dev's. **No M-Pesa
  Daraja credentials are set** (`MPESA_CONSUMER_KEY/SECRET`, `MPESA_SHORTCODE`, `MPESA_PASSKEY`,
  `MPESA_ENV`) — these must come from the Founder's real Safaricom Go-Live application; sandbox
  credentials were never copied into production.
- **Security posture verified identical to dev**: `fn_admin_security_posture_check()` (a new,
  REST-callable mirror of the committed pgTAP security suite, for environments without a stored
  DB password) returns all 6 checks PASS on both `trustride-dev` and `trustride-production` —
  RLS coverage, SECURITY DEFINER search_path pinning, the P0 queue-function privilege fix, the
  orchestration service role's retained access, and zero cross-engine foreign keys.
- **Non-financial E2E proven live on production**: a real `PAYMENT_STK_TRIGGERED` signal (test
  user, test phone, quote_id `d67cd287-6159-4643-95a4-51dbca1eb4d9`) was picked up automatically
  by `pg_cron` with zero manual intervention, dispatched via the Vault-backed `pg_net` bridge, and
  reached the deployed `mpesa-stk-push` — which correctly created an `INITIATED` transaction row
  and then failed safely and observably at the Daraja OAuth call (no credentials configured),
  never faking success. `mpesa-callback` confirmed rejecting an unauthenticated request (401),
  identical to dev. This proves cron dispatch, `pg_net` invocation, Vault config resolution, Edge
  Function execution, database writes, and the callback authenticity control all work correctly on
  production — everything except the actual outbound call to Safaricom, which requires real
  credentials nobody has fabricated here.

**Remaining before production can process a real payment**: real Safaricom Go-Live Daraja
credentials from the Founder (`MPESA_ENV=production` only once these exist), and explicit Founder
authorization before the first real-money transaction is attempted — per standing instruction,
this was correctly never attempted.

Every command in this manual works identically against `trustride-production` by substituting
`--project-ref phypuevxwdunesigcfgo` — nothing here required inventing new tooling.
