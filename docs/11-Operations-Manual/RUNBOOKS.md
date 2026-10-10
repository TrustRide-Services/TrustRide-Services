# TrustRide Operations Runbooks

Practical, command-level procedures — companion to `README.md`'s design-level index. Rewritten
2026-10-08 against the system as it exists in this repository and on `trustride-stagging`;
every function, table and cron job named below exists there today.

**Environments** (see `docs/10-Deployment-Architecture/README.md`):

| Name | Ref / URL | Use |
| --- | --- | --- |
| Local | `supabase start` (ports 54321/54322) | prove every change first |
| `trustride-stagging` | `fdkzewkogkujtwvonesn` | the linked project; all commands below target it unless stated |
| Web | https://trustride-services.vercel.app (Vercel team `trust-ride`, project `trustride-services`) | runs against `trustride-stagging` |
| `trustride-production` | — | provisioned, not wired; **never targeted without explicit Founder authorization** |

SQL below is run with `supabase db query --linked "<sql>"` from the repo root (or `-f file.sql`).
Never paste a secret value into a command line that is logged or committed.

---

## Deployment

**Before anything:** confirm the link — `cat supabase/.temp/project-ref` must print
`fdkzewkogkujtwvonesn`.

**Migrations:**
```bash
supabase migration list --linked           # what is pending
supabase db push --linked --yes            # applies pending migrations, in order
supabase migration list --linked           # confirm local = remote for every row
supabase/tests/run.sh linked               # 11 suites; must end with 0 failed
```
A "failed to cache migrations catalog" warning after `db push` is harmless when the migrations
themselves applied — confirm with `migration list` and the suites, never the push exit code alone.
Every migration ends with `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;` and
`SELECT trustride.fn_platform_conformance_assert();`, so a migration that breaks platform
conformance fails and rolls back by itself. Never run `supabase config push` (it would overwrite the
hosted Auth settings with the local `config.toml`).

**Edge Functions** (all three authenticate with their own secret or key, so all deploy without
JWT verification):
```bash
supabase functions deploy integration-gateway --project-ref fdkzewkogkujtwvonesn --no-verify-jwt
supabase functions deploy mpesa-callback      --project-ref fdkzewkogkujtwvonesn --no-verify-jwt
supabase functions deploy protrack-ingest     --project-ref fdkzewkogkujtwvonesn --no-verify-jwt
supabase functions list --project-ref fdkzewkogkujtwvonesn     # ACTIVE, verify_jwt false
```
A deploy without `--no-verify-jwt` makes Safaricom's callbacks and the database's gateway calls
fail with 401.

**Web application:** push to `main`. Vercel's GitHub integration builds `frontend/web` and
promotes it to production automatically; confirm the new deployment on the commit in GitHub
(Deployments → Production) and load the site.

## Rollback

Forward-fix only (Build Plan Part VII.4). There is no `down` migration mechanism.
1. Never reverse a migration with `db reset`, manual `DROP`, or by editing migration history.
2. Write a new migration that corrects the defect. To patch an existing function, start from its
   live definition (`SELECT pg_get_functiondef('trustride.<fn>'::regproc);`) and replace it — a
   plain `CREATE OR REPLACE` with a changed signature or defaults fails.
3. Prove it red→green: the failing check in `supabase/tests` first, then the fix, then
   `run.sh linked`, then the affected browser journey in `tests/e2e`.
4. **Web:** in Vercel → `trustride-services` → Deployments, promote the previous good deployment
   ("Instant Rollback"); then fix forward in git.

## Secrets

Where each kind lives:
- **Edge Function secrets** (`supabase secrets set/list --project-ref fdkzewkogkujtwvonesn`):
  `TRUSTRIDE_GATEWAY_SECRET`, `MPESA_CALLBACK_TOKEN`, `MPESA_CALLBACK_BASE_URL`, and — once
  supplied — the provider credentials (`MPESA_*`, `AT_*`, `WHATSAPP_*`, `PROTRACK_*`; the full
  list is in the header of `supabase/functions/integration-gateway/index.ts` and
  `protrack-ingest/index.ts`).
- **Supabase Vault** (database side): `trustride_integration_gateway_url`,
  `trustride_integration_gateway_secret` (must equal `TRUSTRIDE_GATEWAY_SECRET`),
  `trustride_protrack_poll_url`.
- **Vercel**: only `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` (public by design).

**Rotation:**
```bash
supabase secrets set --project-ref fdkzewkogkujtwvonesn NAME=<new value>
supabase secrets list --project-ref fdkzewkogkujtwvonesn   # shows names and digests, never values
```
Functions read secrets at invocation time — no redeploy needed. When rotating the gateway secret,
update the Vault copy in the same sitting (Supabase Dashboard → Vault, edit
`trustride_integration_gateway_secret`); until both match, outbound requests fail authentication
and are retried. When rotating `MPESA_CALLBACK_TOKEN`, payments already in flight will have their
callbacks rejected (403) and will time out — by design; rotate in a quiet window.

## Integration modes (SIMULATOR / SANDBOX / PRODUCTION)

Every external port answers through one adapter mode at a time
(`trustride.integration_adapter_registry`). As of 2026-10-08 **every port is `SIMULATOR`**: work
completes inside the database and nothing leaves the platform.
```sql
SELECT port_code, adapter_type FROM trustride.integration_adapter_registry WHERE active ORDER BY 1;
```
Switching a port is an Office decision made in the app (the `SET_ADAPTER` command, Founder or
Administrator), and only after that provider's credentials are set as Edge Function secrets.
Requests already queued pick up the new mode on their next attempt.

## Outbound requests (SMS, WhatsApp, email, push, STK push, B2C payout)

Engines queue work in `trustride.integration_outbound_request`; `fn_integration_outbound_dispatch`
posts it to `integration-gateway` (pg_net, with the gateway secret); the gateway calls the provider
and reports back through `fn_integration_outbound_result`. Statuses: `QUEUED → SENT → SUCCEEDED`,
or `FAILED_RETRYABLE` (retried with backoff), `FAILED` (final), `WAITING_CONFIGURATION`.

```sql
SELECT status, operation, count(*) FROM trustride.integration_outbound_request
GROUP BY 1, 2 ORDER BY 1, 2;
SELECT request_id, operation, attempts, last_error, created_at FROM trustride.integration_outbound_request
WHERE status IN ('FAILED', 'FAILED_RETRYABLE', 'WAITING_CONFIGURATION') ORDER BY created_at DESC LIMIT 50;
```
The cron job `trustride_integration_outbound_retry_sweep` (every minute):
- re-dispatches due retries and anything `WAITING_CONFIGURATION`;
- fails a notification with no answer after 10 minutes (then retried);
- fails an STK push or B2C payout with no final result (10 minutes, or 2 hours once Safaricom
  accepted it) **without re-sending**, and notifies Founder and Administrators to verify on the
  M-Pesa portal first. Never re-send money by hand before that check.

**`WAITING_CONFIGURATION`** means the two Vault entries above are missing — set them; the sweep
sends the waiting requests within a minute. **`CIRCUIT_OPEN`** in `last_error` means the port's
circuit breaker tripped after repeated provider failures; it retries by itself every 30 seconds.
Gateway errors are in Dashboard → Edge Functions → `integration-gateway` → Logs.

## Payments (M-Pesa)

Flow: the customer accepts a quote → an `STK_PUSH` outbound request → `integration-gateway` →
Daraja → Safaricom calls `mpesa-callback?kind=stk&token=…` →
`fn_integration_mpesa_callback_ingest` settles the transaction in
`trustride.integration_payment_gateway_transaction` (`INITIATED → PENDING_CALLBACK → SETTLED` or
`FAILED`). In `SIMULATOR` mode the customer (or an organisation's representative) approves a
simulated prompt in the app instead.

```sql
SELECT gateway_txn_id, order_id, txn_status, adapter_type, failure_reason, initiated_at
FROM trustride.integration_payment_gateway_transaction
WHERE order_id = '<order_id>' ORDER BY initiated_at DESC;
```
- **Stuck at `PENDING_CALLBACK`**: the cron job `trustride_payment_timeout_sweep` (every minute)
  fails it as `NO_CALLBACK_FROM_MPESA` after `PAYMENT_CALLBACK_TIMEOUT_MIN` minutes (default 3,
  in `platform_configuration`). Simulator transactions are never timed out.
- **Stuck at `INITIATED`**: the STK push never reached Daraja — check the outbound request above;
  once it is `FAILED` the same sweep fails the payment as `STK_PUSH_NOT_DELIVERED`.
- **Callback answered 403**: the URL token does not match the current `MPESA_CALLBACK_TOKEN`
  (rotated mid-flight, or a stranger probing). Never weaken the check.
- **Duplicate callback**: absorbed — the transaction settles once; no action needed.
- **Corrections**: settled fares and settlements are immutable; a correction is a new governed
  record, never an `UPDATE`.

## Telemetry (Protrack)

`trustride_telemetry_poll` (every 30 seconds) asks `protrack-ingest` to poll Protrack for every
bound device; Protrack may also push to it with a TrustRide external-system key.
`trustride_telemetry_health_sweep` (every 2 minutes) marks a tracker `STALE` when it has sent
nothing for `TELEMETRY_STALE_AFTER_MIN` minutes (default 10).
Until `PROTRACK_*` secrets are set the poll has nothing to read; that is expected on staging.

## Background jobs and platform health

All scheduled work is `pg_cron` jobs named `trustride_*` (dispatch cycle every 10 seconds; quote
expiry, business dispatch, consensus timeout, payment timeout and outbound retry every minute;
SLA, marketplace and health sweeps every 2–15 minutes; advisory hourly/daily; conformance watch
daily).
```sql
SELECT * FROM trustride.fn_platform_job_health();          -- last run, last status, failures in 24h
SELECT * FROM trustride.fn_platform_conformance_violations(); -- must return no rows
```
The same picture is on the Office health screen. `trustride_platform_conformance_watch` notifies
the Office daily if any conformance drift appears. Old run history is trimmed after 7 days.

**Pausing a job** (Founder authorization; resume the moment the cause is fixed):
```sql
SELECT cron.alter_job(jobid, active := false) FROM cron.job WHERE jobname = '<jobname>';
SELECT cron.alter_job(jobid, active := true)  FROM cron.job WHERE jobname = '<jobname>';
```

## Signal queue

```sql
SELECT queue_status, count(*) FROM trustride.orch_signal_queue GROUP BY 1;
SELECT * FROM trustride.orch_signal_queue WHERE queue_status = 'FAILED' ORDER BY queued_at DESC LIMIT 50;
SELECT * FROM trustride.dead_letter_review ORDER BY created_at DESC LIMIT 50;
```
The dispatch cycle (every 10 seconds) hands each signal to its destination engine in the same
transaction. The queue entry ends `COMPLETED` when the handler ran, or `FAILED` when it raised; a
failed signal's inbox row is `DEAD_LETTER`, a `dead_letter_review` row is opened and the Office is
notified. A signal with no active route ends `DEAD_LETTER` in its outbox (reason `NO_ROUTE`), with
a review row and an Office notification — it is decided once, not on every cycle. There is no
automatic retry and no lease: `orch_retry_schedule`, `orch_retry_history` and `LEASED` are unused.
Reprocessing a dead letter is a deliberate Office decision after reading its reason. A queue entry
long `DISPATCHED` points to a stalled dispatch cycle — check `fn_platform_job_health()` for
`trustride_dispatch_cycle`.

## Incidents and security events

There is no incident table in use: `trustride.system_incident` and `trustride.security_event`
exist but no function writes them. What the system records:
- **Office notifications** (`present_notification_inbox`, categories `PAYMENT_EXCEPTION`,
  `PLATFORM_EXCEPTION`, `ORDER_EXCEPTION`, `SUPPORT`) reach Founder and Administrators in the app;
  critical ones also go out by SMS once the SMS provider is live. There is no other paging channel.
- **Dead letters** (`dead_letter_review`) — every failed or unroutable signal.
- **The audit chains** — `audit_log` (every governed change, including contact, identifier,
  credential, role, membership and Office-decision rows), `present_decision_log` (every command),
  `orch_routing_audit` / `orch_execution_audit` (every signal), `resource_ledger_event`,
  `advisory_decision_log`, `model_decision_log`. Each is append-only and hash-chained.
```sql
SELECT * FROM trustride.present_notification_inbox
WHERE top_shell = 'TRUSTRIDE_OFFICE' AND category LIKE '%EXCEPTION' ORDER BY delivered_at DESC LIMIT 50;
SELECT * FROM trustride.audit_log ORDER BY chain_seq DESC LIMIT 50;
SELECT * FROM trustride.fn_platform_audit_chain_verify(TRUE);   -- every chain; first_break_seq must be NULL
SELECT * FROM trustride.platform_audit_chain_seal ORDER BY chain_seq DESC LIMIT 8;  -- last daily seal
```
`trustride_audit_chain_seal` verifies every chain daily (00:15 UTC) and notifies the Office of any
break. Use the audit log to reconstruct what happened before considering any recovery action.
History written before 2026-10-11 is kept as found; its known breaks are recorded in
`platform_audit_chain.legacy_detail`.

## Emergency actions

There is no single kill switch. Every option below requires explicit Founder authorization and is
reversed as soon as the emergency is over.
- **One account**: suspend it from the Office app (the `SUSPEND_USER` command), which records the
  reason.
- **One provider misbehaving**: switch its port back to `SIMULATOR` (`SET_ADAPTER`) — no real
  traffic leaves the platform for that port.
- **One runaway job**: pause it (Background jobs, above).
- **Web application**: roll back to the previous Vercel deployment (Rollback, above).

## Backup and recovery

`supabase backups list --project-ref fdkzewkogkujtwvonesn` (read-only) on 2026-10-08:
`pitr_enabled: false`, no backups listed. **`trustride-stagging` has no restorable backup today.** The schema is fully reproducible from `supabase/migrations`; data is not. Enabling
daily backups / point-in-time recovery needs a paid Supabase plan — a Founder decision, and a
precondition for `trustride-production` carrying real data.

Recovery test, once backups exist: restore into a **new** project (never in place), run
`supabase/tests/run.sh` against it, spot-check row counts on `business_order`,
`integration_payment_gateway_transaction` and `audit_log`, and record the time taken.

## Verification after any deploy

```bash
supabase migration list --linked                               # local = remote
supabase/tests/run.sh linked                                   # 0 failed
supabase functions list --project-ref fdkzewkogkujtwvonesn     # 3 functions ACTIVE
curl -s -o /dev/null -w "%{http_code}\n" https://trustride-services.vercel.app   # 200
```
Then rerun the browser journey for any user flow the change touched (`tests/e2e/README.md`).
SQL suites roll back and never reach COMMIT, so anything checked at commit time (deferred
triggers) is only proven by a journey or a Data API call.
