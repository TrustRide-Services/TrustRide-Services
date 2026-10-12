# Engine 7 / Engine 8 — engine-to-engine interaction inventory and coverage

Status 2026-10-12, migration `20261012000042`. Generated from the live database: function catalogue,
`routing_rule`, `coord_admission_policy`, `coord_dependency_rule` and `cron.job`. Construction Directive WP4.

## How a cross-engine interaction travels

1. The owning engine writes a signal into its own outbox. The envelope carries `signal_id`, `correlation_id`, `causation_id`, the emitting and receiving engines, the signal type, the payload and an idempotency key.
2. Engine 7's dispatch cycle (`trustride_dispatch_cycle`, every 10 s) discovers PENDING signals in emission order.
3. **If the signal type is coordinated** (it has a row in `coord_admission_policy`: the fan-out and fan-in executions below), Engine 8 decides first (`fn_coord_govern`):
   - **admission**, once per signal;
   - **exactly-once**: a repeated execution with the same content for the same destination and correlation is refused;
   - **context**: one workflow instance per correlation and one stage per coordinated delivery;
   - **dependencies** are held, released, failed or timed out;
   - **consensus** is held until COMMIT, refused on ABORT, and refused if no session is opened within the fan-in timeout.

   A held signal stays PENDING, is decided again next cycle, and writes nothing until its state changes. A refusal ends it DEAD_LETTER with the reason, a dead-letter review row and an Office notification.
4. **One-to-one signals do not enter Engine 8**, as specified: Engine 7 routes them alone.
5. Engine 7 routes the signal through `orch_destination_cache`, which is synced from Foundation's `routing_rule`. It queues it, writes it into the destination inbox, and calls the destination engine's inbox handler in the same transaction. If no route exists, the signal ends DEAD_LETTER with reason NO_ROUTE, a review row and an Office notification (migration 033).
6. After the handler, the queue entry ends COMPLETED, or FAILED if the handler raised (the inbox row is then DEAD_LETTER and the Office is notified). For a coordinated signal, Engine 8 then finalizes it (`fn_coord_finalize`):
   - the stage is marked completed or failed;
   - an execution completion is recorded, with a certificate when it completed;
   - the signal is released back to Engine 7 (`coord_execution_release`).

   A failed branch marks the workflow FAILED, records a TERMINATE recovery and raises a critical runtime alert, so partial completion is never silent.

Specification gap, recorded: the Engine 7 and 8 blueprints say the *routing rule* marks a signal one-to-many or many-to-one. Foundation's `routing_rule` (FDN-001) has no such column. Engine 8's own `coord_admission_policy` is used as the per-signal-type declaration, and no Foundation table was altered.

## Coordinated executions (Engine 8)

| Execution | Emitter | Signals (destination) | Engine 8 requirement |
|---|---|---|---|
| Order placed | `fn_business_order_place` (E04) | SERVICE_LOOKUP_REQUESTED (E03), ORDER_PLACED (E11) | fan-out: admission, context, finality |
| Service resolved | `fn_service_lookup_requested_accept` (E03) | SERVICE_RESOLVED (E04), SERVICE_CONTEXT_RESOLVED (E05) | fan-out |
| Resource assigned | `fn_resource_assign` (E02) | RESOURCE_ASSIGNED (E04), RESOURCE_DISPATCH_INITIATED (E05) | fan-out |
| Engine 5 pricing | — | RESOURCE_DISPATCH_INITIATED (E05) **requires** SERVICE_CONTEXT_RESOLVED (E05), same correlation, hold 300 s | **fan-in dependency** |
| Fleet verified | `fn_integration_fleet_verification_requested_accept` (E06) | FLEET_VERIFICATION_UPDATED (E02), OBJECT_VERIFICATION_UPDATED (E01) | fan-out |
| Marketplace item sold | `fn_service_marketplace_listing_sell` (E03) | MARKETPLACE_LISTING_SOLD (E04 and E02) | fan-out |
| Advisory anomaly | `fn_advisory_inbox_process` (E09) | ADVISORY_ANOMALY_FLAGGED (E08 and E11) | fan-out |

Also declared since Engine 8's first build: RESOURCE_MARKETPLACE_ITEM_READY, ASSIGNMENT_REQUESTED, JOB_COMPLETED and VENDOR_VERIFICATION_UPDATED. No signal type currently requires consensus. The consensus path is proven with a temporary policy in suite 27.

## Route coverage — every active route has a consumer

All 48 active routes name a destination engine whose inbox handler explicitly handles that signal type. This was checked against each handler's source, 48 of 48.

| Signal | From | To | Engine 8 | Prerequisite |
|---|---|---|---|---|
| CONTACT_VERIFICATION_REQUESTED | E01 | E06 | one-to-one |  |
| VERIFICATION_REQUESTED | E01 | E06 | one-to-one |  |
| FLEET_VERIFICATION_REQUESTED | E02 | E06 | one-to-one |  |
| RESOURCE_ASSIGNED | E02 | E04 | coordinated |  |
| RESOURCE_DISPATCH_INITIATED | E02 | E05 | coordinated | SERVICE_CONTEXT_RESOLVED |
| RESOURCE_LOCATION_UPDATED | E02 | E04 | one-to-one |  |
| RESOURCE_MARKETPLACE_ITEM_READY | E02 | E03 | coordinated |  |
| RESOURCE_RESERVED | E02 | E04 | one-to-one |  |
| RESOURCE_UNAVAILABLE | E02 | E04 | one-to-one |  |
| MARKETPLACE_LISTING_SOLD | E03 | E02 | coordinated |  |
| MARKETPLACE_LISTING_SOLD | E03 | E04 | coordinated |  |
| SERVICE_CATALOGUE_UPDATED | E03 | E11 | one-to-one |  |
| SERVICE_CONTEXT_RESOLVED | E03 | E05 | coordinated |  |
| SERVICE_RESOLVED | E03 | E04 | coordinated |  |
| ACTOR_REQUEST_DECIDED | E04 | E11 | one-to-one |  |
| ACTOR_REQUEST_ESCALATED | E04 | E11 | one-to-one |  |
| ASSIGNMENT_RELEASED | E04 | E02 | one-to-one |  |
| ASSIGNMENT_REQUESTED | E04 | E02 | coordinated |  |
| JOB_COMPLETED | E04 | E02 | coordinated |  |
| ORDER_PLACED | E04 | E11 | coordinated |  |
| ORDER_PROGRESS | E04 | E11 | one-to-one |  |
| ORDER_SETTLED | E04 | E11 | one-to-one |  |
| PAYMENT_STK_TRIGGERED | E04 | E06 | one-to-one |  |
| RESOURCE_ASSIGNMENT_CONFIRMED | E04 | E02 | one-to-one |  |
| SERVICE_LOOKUP_REQUESTED | E04 | E03 | coordinated |  |
| VENDOR_PAYOUT_REQUESTED | E04 | E06 | one-to-one |  |
| COST_MARGIN_BREACHED | E05 | E09 | one-to-one |  |
| FARE_CALCULATION_FAILED | E05 | E04 | one-to-one |  |
| FARE_QUOTED | E05 | E04 | one-to-one |  |
| PAYMENT_STK_TRIGGERED | E05 | E06 | one-to-one |  |
| QUOTE_EXPIRED | E05 | E04 | one-to-one |  |
| UNIT_PRICE_LOCKED | E05 | E04 | one-to-one |  |
| EPRA_FUEL_INDEX_UPDATED | E06 | E05 | one-to-one |  |
| FLEET_VERIFICATION_UPDATED | E06 | E02 | coordinated |  |
| OBJECT_VERIFICATION_UPDATED | E06 | E01 | coordinated |  |
| PAYMENT_FAILED | E06 | E04 | one-to-one |  |
| PAYMENT_SETTLED | E06 | E04 | one-to-one |  |
| PAYMENT_STK_FAILED | E06 | E04 | one-to-one |  |
| TELEMETRY_BATCH_NORMALIZED | E06 | E02 | one-to-one |  |
| VENDOR_PAYOUT_COMPLETED | E06 | E04 | one-to-one |  |
| VENDOR_PAYOUT_FAILED | E06 | E04 | one-to-one |  |
| VERIFICATION_COMPLETED | E06 | E01 | one-to-one |  |
| ADVISORY_ANOMALY_FLAGGED | E09 | E11 | coordinated |  |
| ADVISORY_ANOMALY_FLAGGED | E09 | E08 | coordinated |  |
| ADVISORY_RECOMMENDATION_PUBLISHED | E09 | E11 | one-to-one |  |
| SCENARIO_RUN_COMPLETED | E10 | E11 | one-to-one |  |
| NOTIFICATION_DISPATCH_REQUESTED | E11 | E06 | one-to-one |  |
| SCENARIO_RUN_REQUESTED | E11 | E10 | one-to-one |  |

Handled but never emitted and not routed: `VENDOR_VERIFICATION_UPDATED` (E03), `ZONE_SURGE_TRIGGERED` (E05). These are dormant handlers, not defects. If one is ever emitted without a route it ends DEAD_LETTER (NO_ROUTE).

## Direct cross-engine function calls (not signals)

From the function catalogue. Most are lawful by design:

- **Foundation substrate**, called by every engine: audit log, configuration (`fn_business_config` reads `platform_configuration`), sequences, role checks and Office notification recipients.
- **Engine 11's command and projection gateway.** Each command handler calls the owning engine's own function after the gateway has checked identity, session, surface law and authority. Projections are read models.
- **Engine 7's dispatch** calling each engine's inbox handler, and Engine 8's governance.

Synchronous calls that change another engine's state, retained deliberately:

| Caller (engine) | Callee (engine) | Why it stays synchronous |
|---|---|---|
| `fn_business_marketplace_reserve`, `_purchase_confirmed`, `fn_business_settled_followup`, `fn_business_order_close`, `fn_business_actor_request_decide` (E04) | `fn_service_marketplace_listing_reserve/_extend/_sell/_release` (E03) | Reservation and sale must be atomic with the order step, so one item cannot be sold twice |
| `fn_business_job_progress_advance`, `fn_business_fare_quoted_accept`, `fn_business_order_close`, `fn_business_withdraw_unaccepted_quote` (E04) | `fn_cost_quote_mark_in_progress/_finalize/_cancel` (E05) | The quote's lock and finalization must be atomic with the job transition the payment amount depends on. Making them asynchronous would leave a window where a job is completed but its quote is not final, and would change how Engine 5 is driven (protected) |
| `fn_business_actor_request_decide` (E04) | `fn_resource_office_fleet_register` (E02) | An Office decision registers the approved partner's fleet in the same governed transaction |
| `fn_business_service_order_place` (E04), `fn_cost_resource_dispatch_initiated_accept` (E05) | `fn_integration_routing_compute` (E06) | A synchronous read through Engine 6's port at the moment of placement and pricing. WP6 governs its provider and freshness |

Converting these to asynchronous signals would be an architecture change and is not done here. If strict signal-only crossing is wanted for them, that is a Founder decision.

## Background jobs (Engine 7 scheduling via pg_cron)

| Job | Schedule | Command |
|---|---|---|
| trustride_actor_request_sla_sweep | `*/15 * * * *` | `SELECT trustride.fn_business_partnership_response_timeout_sweep();` |
| trustride_advisory_daily | `0 23 * * *` | `SELECT trustride.fn_advisory_run_sweeps('DAILY');` |
| trustride_advisory_hourly | `7 * * * *` | `SELECT trustride.fn_advisory_run_sweeps('HOURLY');` |
| trustride_audit_chain_seal | `15 0 * * *` | `SELECT trustride.fn_platform_audit_chain_seal();` |
| trustride_audit_seal_watch | `40 * * * *` | `SELECT trustride.fn_platform_audit_seal_watch();` |
| trustride_business_dispatch_sweep | `* * * * *` | `SELECT trustride.fn_business_dispatch_sweep();` |
| trustride_coord_consensus_timeout | `* * * * *` | `SELECT trustride.fn_coord_consensus_timeout_sweep();` |
| trustride_cost_quote_expire_sweep | `* * * * *` | `SELECT trustride.fn_cost_quote_expire_sweep();` |
| trustride_cron_log_trim | `30 0 * * *` | `DELETE FROM cron.job_run_details WHERE end_time < now() - interval '7 days'` |
| trustride_dispatch_cycle | `10 seconds` | `SELECT trustride.fn_orch_dispatch_cycle();` |
| trustride_engine_health_record | `*/5 * * * *` | `SELECT trustride.fn_platform_engine_health_record();` |
| trustride_integration_outbound_retry_sweep | `* * * * *` | `SELECT trustride.fn_integration_outbound_retry_sweep();` |
| trustride_marketplace_sweep | `*/5 * * * *` | `SELECT trustride.fn_business_marketplace_sweep();` |
| trustride_orch_capacity_snapshot | `* * * * *` | `SELECT trustride.fn_orch_capacity_snapshot_record();` |
| trustride_orch_sla_check | `*/5 * * * *` | `SELECT trustride.fn_orch_sla_check_sweep();` |
| trustride_payment_timeout_sweep | `* * * * *` | `SELECT trustride.fn_integration_payment_timeout_sweep();` |
| trustride_platform_conformance_watch | `0 0 * * *` | `SELECT trustride.fn_platform_conformance_watch();` |
| trustride_support_sla_sweep | `*/5 * * * *` | `SELECT trustride.fn_business_support_sla_sweep();` |
| trustride_telemetry_health_sweep | `*/2 * * * *` | `SELECT trustride.fn_resource_telemetry_health_sweep();` |
| trustride_telemetry_poll | `30 seconds` | `SELECT trustride.fn_integration_telemetry_poll_trigger();` |

## External callbacks

| Endpoint | Enters TrustRide through | Then |
|---|---|---|
| `mpesa-callback` (Safaricom) | `fn_integration_mpesa_callback_ingest`, `fn_integration_outbound_result` (E06) | PAYMENT_SETTLED / PAYMENT_FAILED signal to E04 via Engine 7 |
| `protrack-ingest` (Protrack) | `fn_integration_telemetry_ingest` (E06) | Location events to Engine 2; tracking projected by E11 |
| `integration-gateway` result | `fn_integration_gateway_ack`, `fn_integration_outbound_result` (E06) | Outcome applied per operation; failures explicit |

## Evidence

- Suite `supabase/tests/27_engine78_coordination.sql` covers:
  - delayed delivery: held and then released;
  - a refused prerequisite (DEPENDENCY_FAILED) and an overdue one (DEPENDENCY_TIMEOUT);
  - duplicate execution refused;
  - consumer failure: FAILED, workflow FAILED, TERMINATE recovery and a critical alert;
  - consensus COMMIT and ABORT;
  - nothing written while a signal is held;
  - a real order: every coordinated delivery admitted, certified and released, one-to-one signals bypassing Engine 8, and every routed signal terminal.

  Red on staging before migration 042 (3 of 8 passing: the dispatch was delivered without its context, and duplicates ran twice); green 17/17 afterwards.
- Suite 20: unrouted signal → NO_ROUTE dead letter, decided once.
- Staging after 042: 27 suites, 623 of 623; the live 10-second dispatch cycle succeeded 89 of 89 times in the first 15 minutes.
