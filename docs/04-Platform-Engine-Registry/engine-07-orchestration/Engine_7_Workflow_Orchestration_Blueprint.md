# TRUSTRIDE SERVICES

# ENGINE 7 — WORKFLOW ORCHESTRATION ENGINE
## Complete Architectural, Data, API, and Signal Specification

**[Parent Authority: TBOC v2.0.0 Genesis Edition · FDN-001 v3.0.0 Part IV & Part XI]**

*More than a Ride — We Save You Time.*

## Document Control

| Document Control Field | Entry |
| --- | --- |
| Document Title | Engine 7 — Workflow Orchestration Engine: Complete Specification |
| Document Identifier | TRS026-ENG007-ORCH-001 |
| Version | 1.0.0 |
| Status | **ADOPTED** (2026-08-16, per Founder directive — build order FDN → Resources → Services → Business → Cost → Integration → Orchestration) |
| Classification | Institutional Blueprint — Confidential |
| Schema | `trustride` (single canonical PostgreSQL schema; this engine's tables are prefixed `orch_`) |
| Platform Code | TRS026 |
| Engine Code | `TRS026_ENG007_ORCH` |
| Engine No. | `ENGINE_007` |
| Installation Order | 007 |
| Parent Authority | FDN-001 v3.0.0 Part IV (Event & Signal Substrate), Part V (Non-Negotiable Foundation Laws), Part XI §11.2 (Plate I Station Law — the canonical Signal Envelope), §11.6 Founder Ruling AQ-001 (Orchestration sequences, alongside Coordination and Integration, at the engine level of Plate I) |
| Architecture Lineage | Positioned as Engine 7 in the eleven-engine Constitutional Engine Registry (Annex C, FDN-001 v3.0.0); Layer 3 Workflow Management (Hybrid Bridge) of the Backend/Frontend/Event-Signal Architecture Blueprint v1.1.0 |

## Document Purpose & Constitutional Basis

This instrument specifies **Engine 7 — the Workflow Orchestration Engine**, one half of TrustRide's Sovereign Processing Unit. It answers one constitutional question for the rest of the platform — **where does this signal go next, and in what order?**

TBOC deliberately holds no engineering specification (Article 8.2 — "no code, no schema syntax... no engineering specification... integration mechanics remain downstream in the technical sovereigns"). Engine 7 therefore carries no business rule of its own and traces instead to the Foundation instrument that already anticipated it:

| This engine's function | FDN-001 basis |
| --- | --- |
| Carrying every cross-engine signal, in order, with heartbeat health published — the Layer 3 Workflow Management obligation | FDN-001 §11.3, Layer 3 |
| The Bridge Transit station — sequencing and routing, the heartbeat — realized as `platform_event_orchestration` ★ | FDN-001 §11.2, Plate I Station 3 |
| No engine authors domain truth of its own; no silent drops; transit without an audit trace is forbidden absolutely | FDN-001 §11.2, Station 3 "Forbidden absolutely" column |
| Engines queue in their outbox; they do not improvise direct calls, if the bridge stops | FDN-001 §11.2, Conformance Rule C-I-4 |
| Every signal type is registered before first use; the inbox rejects the unregistered | FDN-001 §11.2, Conformance Rule C-I-6 |
| At the engine level, emission must leave through an external pipeline — Integration together with Orchestration and Coordination close the loop for every Layer 2 engine | FDN-001 §11.6, Founder Ruling AQ-001 |
| The signal envelope is one shape for the whole platform; no field added, renamed, or omitted | FDN-001 §11.2 |

Foundation's own `routing_rule` table (TRS_FDN_SUBSTRATE) declares *which event types flow to which engines* as governed vocabulary. Engine 7 never duplicates that authority — it consumes Foundation's routing law by signal and operates the runtime machinery: the queue, the lease, the retry schedule, the priority, the audit trail. Foundation states the law; Engine 7 executes it, deterministically, at scale, without becoming a bottleneck.

---

# SECTION 1 — ARCHITECTURAL ROLE & BOUNDARIES

## 1.1 Mission

Engine 7 is the platform's single, deterministic sequencing authority. Every signal emitted by every engine's outbox passes through Engine 7 before it reaches any inbox. No engine ever calls another engine directly; Engine 7 is the only lawful path between them.

## 1.2 Operational Duties

1. **Signal routing.** Resolve, for every discovered signal, its destination engine and destination inbox — sourced from Foundation's `routing_rule` vocabulary, cached for constant-time lookup (§2.1–2.2).
2. **Queue custody.** Buffer every routed signal in a partitioned, priority-ordered queue until a worker leases it; queue ownership is never permanent, only leased (§2.3–2.6).
3. **Lineage preservation.** Record the complete parent-child ancestry and hop-by-hop execution path of every signal, append-only, forever (§2.7–2.8).
4. **Retry & compensation governance.** Reschedule a failed dispatch according to a governed retry policy, execute registered compensation actions on exhaustion, and hand terminal failures to Foundation's `dead_letter_review` (§2.9–2.11).
5. **Priority & SLA governance.** Assign execution priority and service-level targets before a signal ever reaches a queue, so urgent signals are never starved behind routine ones (§2.12–2.14).
6. **Orchestration evidence.** Record every routing and execution-stage decision as immutable, hash-chained evidence, distinct from and complementary to Foundation's `audit_log` (§2.15–2.16).
7. **Runtime telemetry.** Measure queue depth, routing throughput, and overall capacity continuously and asynchronously, feeding Advisory (Engine 9) as lawful projections, never blocking a single signal on their account (§2.17–2.19).

## 1.3 Structural Position — Not a Peer, the Bridge Itself

Engine 7 does not maintain a conventional "Interfaces with the Other Ten Engines" table, because it is not a peer domain engine — it is the transport every peer engine depends on. Concretely:

- **Every engine's outbox** (`resource_event_outbox`, `service_event_outbox`, `business_event_outbox`, `cost_event_outbox`, `integration_event_outbox`, and Foundation's `platform_event_outbox`) is discovered and drained by Engine 7, never read by any other engine.
- **Every engine's inbox** (`resource_event_inbox`, `service_event_inbox`, `business_event_inbox`, `cost_event_inbox`, `integration_event_inbox`, `platform_event_inbox`) is written to only by Engine 7 (ordering) working with Engine 8 (fan-out/fan-in), never by the emitting engine directly.
- **Engine 8 (Workflow Coordination)** is Engine 7's structural sibling: Engine 7 decides *when and in what order* a signal moves; Engine 8 decides *whether the distributed execution it belongs to may proceed*. A one-to-one signal passes through Engine 7 alone; a one-to-many or many-to-one signal passes through Engine 7 first, then Engine 8's admission, dependency, and consensus authorities, before delivery.
- **Engine 9 (AI/ML Advisory)** reads Engine 7's telemetry tables (§2.17–2.19) as lawful, read-only projections; it never writes back and never influences a routing decision.

## 1.4 Boundaries — What Engine 7 Never Does

1. **Never authors domain truth.** Engine 7 moves signals; it never creates, interprets, or mutates the business meaning of a payload.
2. **Never decides whether execution may proceed.** Admission, dependency satisfaction, and consensus are Engine 8's exclusive domain; Engine 7 only sequences what Engine 8 has cleared.
3. **Never bypasses the queue.** No signal reaches an inbox without first being queued, leased, and dispatched through §2.3–2.6 — there is no direct-call shortcut, ever (FDN-001 C-I-4).
4. **Never drops a signal silently.** Every routing outcome — routed, unmatched, rejected — is recorded as evidence (§2.15).
5. **Never retries indefinitely.** Every signal type carries a governed retry policy; exhaustion routes to Foundation's `dead_letter_review`, never a silent infinite loop.
6. **Never lets telemetry block execution.** Health and capacity measurement is asynchronous and non-blocking, always (§1.2.7).

---

# SECTION 2 — PRODUCTION SQL DDL SCHEMA (PostgreSQL / Supabase-Ready)

## 2.0 Extensions & Enums (prerequisite)

```sql
-- Extensions (idempotent; already present platform-wide per Engine 001 Phase 0)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- [Trace: FDN-001 §11.2 | Plate I Station Law — the canonical Signal Envelope vocabulary]
CREATE TYPE orch_signal_status_enum AS ENUM (
  'PENDING', 'DISPATCHED', 'RECEIVED', 'ACCEPTED', 'REJECTED', 'DEAD_LETTER'
);

CREATE TYPE orch_partition_status_enum AS ENUM (
  'ACTIVE', 'PAUSED', 'DRAINING'
);

CREATE TYPE orch_queue_status_enum AS ENUM (
  'QUEUED', 'LEASED', 'DISPATCHED', 'COMPLETED', 'FAILED'
);

CREATE TYPE orch_lease_status_enum AS ENUM (
  'LEASED', 'RELEASED', 'EXPIRED'
);

CREATE TYPE orch_priority_level_enum AS ENUM (
  'CRITICAL', 'HIGH', 'NORMAL', 'LOW'
);

CREATE TYPE orch_retry_status_enum AS ENUM (
  'SCHEDULED', 'EXECUTING', 'EXHAUSTED', 'CANCELLED'
);

CREATE TYPE orch_sla_window_status_enum AS ENUM (
  'ON_TRACK', 'WARNING', 'BREACHED'
);

CREATE TYPE orch_lineage_relationship_enum AS ENUM (
  'CAUSED', 'TRIGGERED', 'BROADCAST_FANOUT'
);

CREATE TYPE orch_graph_stage_enum AS ENUM (
  'EMITTED', 'ROUTED', 'QUEUED', 'DISPATCHED', 'RECEIVED', 'ACCEPTED', 'REJECTED'
);
```

### 2.A — Signal Routing Authority

## 2.1 `orch_queue_partition` — Governed Queue Segmentation

```sql
-- [Trace: FDN-001 §11.2 | Station 3 Bridge Transit — sequencing without a sixth path]
CREATE TABLE orch_queue_partition (
  queue_partition_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  partition_code        TEXT NOT NULL UNIQUE,
  partition_name        TEXT NOT NULL,
  engine_code           TEXT NOT NULL,          -- the destination engine this partition feeds, by value against Annex C
  priority_level        orch_priority_level_enum NOT NULL DEFAULT 'NORMAL',
  max_depth             INTEGER NOT NULL DEFAULT 10000 CHECK (max_depth > 0),
  current_depth         INTEGER NOT NULL DEFAULT 0 CHECK (current_depth >= 0),
  partition_status      orch_partition_status_enum NOT NULL DEFAULT 'ACTIVE',
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE orch_queue_partition IS
  '[Trace: FDN-001 §11.2] Every partition operates independently, segmented by destination engine and priority, so one congested destination never starves another.';

ALTER TABLE orch_queue_partition ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_queue_partition_platform_read ON orch_queue_partition
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_queue_partition_service_write ON orch_queue_partition
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

## 2.2 `orch_routing_decision` — Per-Signal Routing Outcome

```sql
-- [Trace: FDN-001 §11.2 | Station 2→3 — emission leaving the engine, resolved to its next hop]
CREATE TABLE orch_routing_decision (
  routing_decision_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_id                 UUID NOT NULL,        -- by value; the signal_id from the emitting engine's own outbox row
  correlation_id            UUID NOT NULL,
  source_engine_code        TEXT NOT NULL,
  destination_engine_code   TEXT NOT NULL,
  signal_type                TEXT NOT NULL,
  matched_routing_rule_ref      TEXT,             -- by value; Foundation's routing_rule.route_id, never a foreign key across engines
  destination_partition_code       TEXT,          -- by value; orch_queue_partition.partition_code
  routing_result                     TEXT NOT NULL CHECK (routing_result IN ('ROUTED', 'NO_RULE_MATCHED', 'REJECTED')),
  routing_duration_ms                   INTEGER,
  decided_at                               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orch_routing_decision_correlation ON orch_routing_decision (correlation_id);
CREATE INDEX idx_orch_routing_decision_result ON orch_routing_decision (routing_result);

COMMENT ON TABLE orch_routing_decision IS
  '[Trace: FDN-001 §11.2, C-I-6] Every routing outcome is recorded, including NO_RULE_MATCHED — the inbox rejects the unregistered, and this table proves it was never silently dropped.';

ALTER TABLE orch_routing_decision ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_routing_decision_platform_read ON orch_routing_decision
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_routing_decision_service_write ON orch_routing_decision
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

## 2.3 `orch_destination_cache` — Foundation Routing Law, Cached for O(1) Lookup

```sql
-- [Trace: FDN-001 Part X §3.2 | The Sequence Law's sibling — Foundation states routing law once, Engine 7 executes it fast]
CREATE TABLE orch_destination_cache (
  destination_cache_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_engine_code      TEXT NOT NULL,
  signal_type              TEXT NOT NULL,
  destination_engine_code    TEXT NOT NULL,
  destination_inbox_table       TEXT NOT NULL,    -- e.g. 'business_event_inbox'
  default_partition_code           TEXT NOT NULL,
  synced_from_routing_rule_ref        TEXT,       -- by value; Foundation's routing_rule.route_id
  cache_status                           TEXT NOT NULL DEFAULT 'ACTIVE'
                                            CHECK (cache_status IN ('ACTIVE', 'STALE', 'SUPERSEDED')),
  last_synced_at                            TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at                                   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (source_engine_code, signal_type)
);

COMMENT ON TABLE orch_destination_cache IS
  '[Trace: FDN-001 Part X §3.2] Foundation''s routing_rule remains the lawful source of routing vocabulary; this cache is refreshed by governed signal, never edited independently, and never a foreign key into Foundation''s own schema.';

ALTER TABLE orch_destination_cache ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_destination_cache_platform_read ON orch_destination_cache
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_destination_cache_service_write ON orch_destination_cache
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

### 2.B — Message Queue Authority

## 2.4 `orch_signal_queue` — The Constitutional Execution Queue

```sql
-- [Trace: FDN-001 §11.2 | Station 3 — the heartbeat itself]
CREATE TABLE orch_signal_queue (
  queue_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_id                UUID NOT NULL,
  correlation_id           UUID NOT NULL,
  source_engine_code       TEXT NOT NULL,
  destination_engine_code  TEXT NOT NULL,
  signal_type              TEXT NOT NULL,
  queue_partition_id       UUID NOT NULL REFERENCES orch_queue_partition (queue_partition_id),
  priority_level            orch_priority_level_enum NOT NULL DEFAULT 'NORMAL',
  queue_status                TEXT NOT NULL DEFAULT 'QUEUED'
                                 CHECK (queue_status IN ('QUEUED', 'LEASED', 'DISPATCHED', 'COMPLETED', 'FAILED')),
  queued_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
  dispatched_at                     TIMESTAMPTZ,
  expires_at                           TIMESTAMPTZ,
  retry_count                             INTEGER NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
  idempotency_key                            TEXT NOT NULL UNIQUE,
  created_at                                    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orch_signal_queue_partition_status ON orch_signal_queue (queue_partition_id, queue_status);
CREATE INDEX idx_orch_signal_queue_priority ON orch_signal_queue (priority_level, queued_at) WHERE queue_status = 'QUEUED';
CREATE INDEX idx_orch_signal_queue_correlation ON orch_signal_queue (correlation_id);

COMMENT ON TABLE orch_signal_queue IS
  '[Trace: FDN-001 §11.2] No signal is dispatched unless it is admitted through §2.2 and persisted here first; queue ownership is leased (§2.5), never held by a single worker permanently.';

ALTER TABLE orch_signal_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_signal_queue_service_only ON orch_signal_queue
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

## 2.5 `orch_queue_lease` — Stateless Worker Leasing

```sql
-- [Trace: FDN-001 §11.2 | Horizontal scalability without a sixth path]
CREATE TABLE orch_queue_lease (
  lease_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  queue_id              UUID NOT NULL REFERENCES orch_signal_queue (queue_id),
  leased_by             TEXT NOT NULL,           -- worker/process identifier; stateless, never a claim of ownership
  lease_status           TEXT NOT NULL DEFAULT 'LEASED' CHECK (lease_status IN ('LEASED', 'RELEASED', 'EXPIRED')),
  lease_started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  lease_expires_at            TIMESTAMPTZ NOT NULL,
  released_at                    TIMESTAMPTZ,
  created_at                        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orch_queue_lease_queue ON orch_queue_lease (queue_id);
CREATE INDEX idx_orch_queue_lease_expiry ON orch_queue_lease (lease_expires_at) WHERE lease_status = 'LEASED';

COMMENT ON TABLE orch_queue_lease IS
  'A worker leases a queued signal; it never owns the queue. An expired, unreleased lease returns the signal to QUEUED, never to a stuck state.';

ALTER TABLE orch_queue_lease ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_queue_lease_service_only ON orch_queue_lease
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

## 2.6 `orch_queue_checkpoint` — Deterministic Recovery Position

```sql
-- [Trace: FDN-001 §11.2 | C-I-5 — correction is a new signal, never an edit of history]
CREATE TABLE orch_queue_checkpoint (
  checkpoint_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  queue_partition_id        UUID NOT NULL REFERENCES orch_queue_partition (queue_partition_id),
  last_queue_id             UUID REFERENCES orch_signal_queue (queue_id),
  last_processed_sequence   BIGINT NOT NULL DEFAULT 0,
  checkpoint_status         TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (checkpoint_status IN ('ACTIVE', 'RECOVERING')),
  checkpoint_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orch_queue_checkpoint_partition ON orch_queue_checkpoint (queue_partition_id, checkpoint_at DESC);

COMMENT ON TABLE orch_queue_checkpoint IS
  'Enables replay-safe restart of a partition after interruption without losing ordering or duplicating dispatched work.';

ALTER TABLE orch_queue_checkpoint ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_queue_checkpoint_service_only ON orch_queue_checkpoint
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

### 2.C — Correlation & Lineage Authority

## 2.7 `orch_signal_lineage` — Append-Only Parent-Child Ancestry

```sql
-- [Trace: FDN-001 §11.2 | correlation_id/causation_id, given a permanent structural home]
CREATE TABLE orch_signal_lineage (
  lineage_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id       UUID NOT NULL,
  parent_signal_id     UUID,
  child_signal_id      UUID NOT NULL,
  relationship_type    orch_lineage_relationship_enum NOT NULL DEFAULT 'CAUSED',
  generation_level     SMALLINT NOT NULL DEFAULT 0 CHECK (generation_level >= 0),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orch_signal_lineage_correlation ON orch_signal_lineage (correlation_id);
CREATE INDEX idx_orch_signal_lineage_parent ON orch_signal_lineage (parent_signal_id) WHERE parent_signal_id IS NOT NULL;

COMMENT ON TABLE orch_signal_lineage IS
  'Append-only. Nothing is ever deleted or edited; a correction is a new signal with a new lineage row, never a rewrite of history.';

-- Append-only at the database level
REVOKE UPDATE, DELETE ON orch_signal_lineage FROM PUBLIC;
REVOKE UPDATE, DELETE ON orch_signal_lineage FROM trustride_authenticated;

ALTER TABLE orch_signal_lineage ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_signal_lineage_platform_read ON orch_signal_lineage
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_signal_lineage_service_write ON orch_signal_lineage
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

## 2.8 `orch_execution_graph` — The Hop-by-Hop Path a Signal Travelled

```sql
-- [Trace: FDN-001 §11.2 | Every station a signal actually visited]
CREATE TABLE orch_execution_graph (
  graph_node_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  signal_id            UUID NOT NULL,
  node_sequence          INTEGER NOT NULL,
  engine_code               TEXT NOT NULL,
  node_stage                   orch_graph_stage_enum NOT NULL,
  entered_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at                       TIMESTAMPTZ
);

CREATE INDEX idx_orch_execution_graph_signal ON orch_execution_graph (signal_id, node_sequence);
CREATE INDEX idx_orch_execution_graph_correlation ON orch_execution_graph (correlation_id);

COMMENT ON TABLE orch_execution_graph IS
  'System Outbox -> Routing -> Queue -> Lease -> Dispatch -> Inbox -> Engine -> Completed: every hop becomes one node here, reconstructing the exact path after the fact.';

ALTER TABLE orch_execution_graph ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_execution_graph_platform_read ON orch_execution_graph
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_execution_graph_service_write ON orch_execution_graph
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

### 2.D — Retry & Compensation Authority

## 2.9 `orch_retry_schedule` — Governed Retry Timing

```sql
-- [Trace: FDN-001 §11.2 | attempt_count, given a scheduling home]
CREATE TABLE orch_retry_schedule (
  retry_schedule_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  queue_id              UUID NOT NULL REFERENCES orch_signal_queue (queue_id),
  retry_attempt         INTEGER NOT NULL CHECK (retry_attempt > 0),
  max_retry_attempts    INTEGER NOT NULL DEFAULT 5 CHECK (max_retry_attempts > 0),
  next_retry_at         TIMESTAMPTZ NOT NULL,
  retry_interval_ms     INTEGER NOT NULL CHECK (retry_interval_ms > 0),
  retry_reason          TEXT,
  retry_status          TEXT NOT NULL DEFAULT 'SCHEDULED'
                           CHECK (retry_status IN ('SCHEDULED', 'EXECUTING', 'EXHAUSTED', 'CANCELLED')),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orch_retry_schedule_due ON orch_retry_schedule (next_retry_at) WHERE retry_status = 'SCHEDULED';

COMMENT ON TABLE orch_retry_schedule IS
  'Registry-driven scheduling only; this table decides when, not how. Exhaustion (retry_status = EXHAUSTED) is a trigger for §2.11 compensation, never a silent drop.';

ALTER TABLE orch_retry_schedule ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_retry_schedule_service_only ON orch_retry_schedule
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

## 2.10 `orch_retry_history` — Immutable Retry Evidence

```sql
-- [Trace: FDN-001 §11.2 | C-I-5 — nothing deleted from the ledgers]
CREATE TABLE orch_retry_history (
  retry_history_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  retry_schedule_id          UUID NOT NULL REFERENCES orch_retry_schedule (retry_schedule_id),
  attempt_number              INTEGER NOT NULL CHECK (attempt_number > 0),
  execution_started_at           TIMESTAMPTZ NOT NULL,
  execution_completed_at            TIMESTAMPTZ,
  execution_result                     TEXT NOT NULL CHECK (execution_result IN ('SUCCESS', 'FAILURE')),
  failure_reason                          TEXT,
  created_at                                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orch_retry_history_schedule ON orch_retry_history (retry_schedule_id, attempt_number);

COMMENT ON TABLE orch_retry_history IS
  'Nothing is ever updated or removed here; every attempt, successful or not, becomes permanent evidence.';

REVOKE UPDATE, DELETE ON orch_retry_history FROM PUBLIC;
REVOKE UPDATE, DELETE ON orch_retry_history FROM trustride_authenticated;

ALTER TABLE orch_retry_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_retry_history_platform_read ON orch_retry_history
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_retry_history_service_write ON orch_retry_history
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

## 2.11 `orch_compensation_policy` — Registry-Driven Recovery Actions

```sql
-- [Trace: FDN-001 §11.2 | Recovery bound to registry, never to embedded logic]
CREATE TABLE orch_compensation_policy (
  compensation_policy_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_type              TEXT NOT NULL,
  compensation_action      TEXT NOT NULL,
  compensation_sequence    SMALLINT NOT NULL DEFAULT 1,
  rollback_required        BOOLEAN NOT NULL DEFAULT FALSE,
  compensation_timeout_ms  INTEGER NOT NULL DEFAULT 30000 CHECK (compensation_timeout_ms > 0),
  active                   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (signal_type, compensation_sequence)
);

COMMENT ON TABLE orch_compensation_policy IS
  'What must happen when retries are exhausted; the worker executes this policy, never embedded application logic. Terminal, unrecoverable signals are handed to Foundation''s dead_letter_review by signal, never written to directly.';

ALTER TABLE orch_compensation_policy ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_compensation_policy_platform_read ON orch_compensation_policy
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_compensation_policy_service_write ON orch_compensation_policy
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

### 2.E — Priority & SLA Authority

## 2.12 `orch_priority_policy` — Constitutional Execution Priority

```sql
-- [Trace: FDN-001 §11.2 | fairness ahead of dispatch, never decided by a worker]
CREATE TABLE orch_priority_policy (
  priority_policy_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_type          TEXT NOT NULL UNIQUE,
  priority_level       orch_priority_level_enum NOT NULL DEFAULT 'NORMAL',
  preemption_allowed   BOOLEAN NOT NULL DEFAULT FALSE,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE orch_priority_policy IS
  'No worker decides priority; it is constitutional and registry-driven, assigned before a signal ever enters §2.4.';

ALTER TABLE orch_priority_policy ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_priority_policy_platform_read ON orch_priority_policy
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_priority_policy_service_write ON orch_priority_policy
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

INSERT INTO orch_priority_policy (signal_type, priority_level, preemption_allowed) VALUES
  ('PAYMENT_STK_TRIGGERED', 'CRITICAL', TRUE),
  ('ASSIGNMENT_REQUESTED', 'HIGH', FALSE),
  ('EMERGENCY_ESCALATION_REQUESTED', 'CRITICAL', TRUE),
  ('ORDER_PLACED', 'NORMAL', FALSE),
  ('SERVICE_CATALOGUE_UPDATED', 'LOW', FALSE);
```

## 2.13 `orch_sla_policy` — Constitutional Service-Level Targets

```sql
-- [Trace: FDN-001 §11.2 | timing discipline behind the heartbeat]
CREATE TABLE orch_sla_policy (
  sla_policy_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_type              TEXT NOT NULL UNIQUE,
  target_response_ms       INTEGER NOT NULL CHECK (target_response_ms > 0),
  target_completion_ms     INTEGER NOT NULL CHECK (target_completion_ms > 0),
  warning_threshold_ms     INTEGER NOT NULL CHECK (warning_threshold_ms > 0),
  critical_threshold_ms    INTEGER NOT NULL CHECK (critical_threshold_ms > 0),
  escalation_signal_type   TEXT,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE orch_sla_policy IS
  'Exceeding warning_threshold_ms or critical_threshold_ms triggers escalation_signal_type toward Coordination''s Runtime Intelligence Authority (Engine 8 §2.23-25), never a silent delay.';

ALTER TABLE orch_sla_policy ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_sla_policy_platform_read ON orch_sla_policy
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_sla_policy_service_write ON orch_sla_policy
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

## 2.14 `orch_execution_window` — Runtime SLA Compliance Record

```sql
-- [Trace: FDN-001 §11.2 | the factual record of timing compliance]
CREATE TABLE orch_execution_window (
  execution_window_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  queue_id                UUID NOT NULL REFERENCES orch_signal_queue (queue_id),
  sla_policy_id            UUID REFERENCES orch_sla_policy (sla_policy_id),
  scheduled_start_at          TIMESTAMPTZ NOT NULL,
  execution_deadline_at          TIMESTAMPTZ NOT NULL,
  actual_start_at                   TIMESTAMPTZ,
  actual_completion_at                 TIMESTAMPTZ,
  window_status                           orch_sla_window_status_enum NOT NULL DEFAULT 'ON_TRACK',
  created_at                                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orch_execution_window_status ON orch_execution_window (window_status) WHERE window_status <> 'ON_TRACK';

COMMENT ON TABLE orch_execution_window IS
  'Signal Created -> Window Opened -> Worker Started -> Worker Finished -> Window Closed; the factual proof of whether every constitutional timing guarantee was met.';

ALTER TABLE orch_execution_window ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_execution_window_platform_read ON orch_execution_window
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_execution_window_service_write ON orch_execution_window
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

### 2.F — Orchestration Audit Authority

## 2.15 `orch_routing_audit` — Immutable Routing Evidence

```sql
-- [Trace: FDN-001 Part IX pattern (TRS_FDN_AUDIT), applied to Engine 7's own routing decisions]
CREATE TABLE orch_routing_audit (
  routing_audit_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_id              UUID NOT NULL,
  correlation_id          UUID NOT NULL,
  routing_decision_id        UUID REFERENCES orch_routing_decision (routing_decision_id),
  routing_result                 TEXT NOT NULL,
  prev_hash                         CHAR(64),
  immutable_hash                       CHAR(64) NOT NULL,
  recorded_at                             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orch_routing_audit_correlation ON orch_routing_audit (correlation_id);

COMMENT ON TABLE orch_routing_audit IS
  'Hash-chained per Foundation''s own audit_log pattern (Part IX): every routing decision becomes permanent, tamper-evident evidence, distinct from Foundation''s business-level audit trail.';

REVOKE UPDATE, DELETE ON orch_routing_audit FROM PUBLIC;
REVOKE UPDATE, DELETE ON orch_routing_audit FROM trustride_authenticated;

ALTER TABLE orch_routing_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_routing_audit_platform_read ON orch_routing_audit
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_routing_audit_service_write ON orch_routing_audit
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

## 2.16 `orch_execution_audit` — Immutable Execution-Stage Evidence

```sql
-- [Trace: FDN-001 Part IX pattern (TRS_FDN_AUDIT), applied to Engine 7's own execution stages]
CREATE TABLE orch_execution_audit (
  execution_audit_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_id              UUID NOT NULL,
  correlation_id          UUID NOT NULL,
  engine_code               TEXT NOT NULL,
  execution_stage              TEXT NOT NULL,
  execution_result                TEXT,
  prev_hash                          CHAR(64),
  immutable_hash                        CHAR(64) NOT NULL,
  recorded_at                              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orch_execution_audit_signal ON orch_execution_audit (signal_id);

COMMENT ON TABLE orch_execution_audit IS
  'Signal Discovered -> Routed -> Queued -> Leased -> Dispatched -> Completed: every stage becomes one immutable audit record.';

REVOKE UPDATE, DELETE ON orch_execution_audit FROM PUBLIC;
REVOKE UPDATE, DELETE ON orch_execution_audit FROM trustride_authenticated;

ALTER TABLE orch_execution_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_execution_audit_platform_read ON orch_execution_audit
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_execution_audit_service_write ON orch_execution_audit
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

### 2.G — Runtime Telemetry Authority

## 2.17 `orch_queue_metrics` — Queue Health Measurement

```sql
-- [Trace: FDN-001 §11.3 | Layer 3 obligation: heartbeat health published]
CREATE TABLE orch_queue_metrics (
  queue_metric_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  queue_partition_id   UUID NOT NULL REFERENCES orch_queue_partition (queue_partition_id),
  queue_depth          INTEGER NOT NULL CHECK (queue_depth >= 0),
  signals_enqueued     INTEGER NOT NULL DEFAULT 0,
  signals_dequeued     INTEGER NOT NULL DEFAULT 0,
  average_wait_ms      NUMERIC(10,2),
  measured_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orch_queue_metrics_partition_time ON orch_queue_metrics (queue_partition_id, measured_at DESC);

COMMENT ON TABLE orch_queue_metrics IS
  'The Routing Engine never waits for these metrics to be written; collection is asynchronous and non-blocking, always.';

ALTER TABLE orch_queue_metrics ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_queue_metrics_platform_read ON orch_queue_metrics
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_queue_metrics_service_write ON orch_queue_metrics
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

## 2.18 `orch_routing_metrics` — Routing Subsystem Health

```sql
-- [Trace: FDN-001 §11.3 | Layer 3 obligation: heartbeat health published]
CREATE TABLE orch_routing_metrics (
  routing_metric_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signals_discovered   INTEGER NOT NULL DEFAULT 0,
  signals_routed       INTEGER NOT NULL DEFAULT 0,
  routing_failures     INTEGER NOT NULL DEFAULT 0,
  average_routing_ms   NUMERIC(10,2),
  measured_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE orch_routing_metrics ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_routing_metrics_platform_read ON orch_routing_metrics
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_routing_metrics_service_write ON orch_routing_metrics
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

## 2.19 `orch_capacity_snapshot` — Periodic Runtime Capacity State

```sql
-- [Trace: FDN-001 §11.3 | when the heartbeat is absent, the platform says so plainly]
CREATE TABLE orch_capacity_snapshot (
  capacity_snapshot_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  active_partitions         INTEGER NOT NULL CHECK (active_partitions >= 0),
  total_queue_depth         INTEGER NOT NULL CHECK (total_queue_depth >= 0),
  signals_in_flight         INTEGER NOT NULL CHECK (signals_in_flight >= 0),
  runtime_health_status     TEXT NOT NULL DEFAULT 'HEALTHY' CHECK (runtime_health_status IN ('HEALTHY', 'DEGRADED', 'CRITICAL')),
  snapshot_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orch_capacity_snapshot_time ON orch_capacity_snapshot (snapshot_at DESC);

COMMENT ON TABLE orch_capacity_snapshot IS
  'One row represents the whole orchestration runtime at one moment; every shell displays this health per FDN-001 C-III-4.';

ALTER TABLE orch_capacity_snapshot ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_capacity_snapshot_platform_read ON orch_capacity_snapshot
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_capacity_snapshot_service_write ON orch_capacity_snapshot
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

### 2.H — Engine Event Substrate (Constitutional Mandatory Tables)

## 2.20 Engine 7's Own Signal Envelope

Per Plate I (Station Law) and CC-03 of the platform Conformance Certificate, every engine — Engine 7 included — carries exactly one outbox and one inbox, in the standard signal envelope shape (FDN-001 §11.2), distinct from `orch_signal_queue` (§2.4), which is the operational transit mechanism for *every other engine's* signals, not Engine 7's own engine-level signals (SLA breach escalations, capacity alerts).

```sql
-- [Trace: FDN-001 §11.2 — mandatory per-engine ledger tables]
CREATE TABLE orch_event_outbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG007_ORCH',
  receiving_engine       TEXT NOT NULL,
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  signal_status               TEXT NOT NULL DEFAULT 'PENDING'
                                CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason              TEXT,
  idempotency_key                 TEXT NOT NULL UNIQUE,
  attempt_count                     INTEGER NOT NULL DEFAULT 0,
  emitted_at                         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_orch_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_orch_outbox_status ON orch_event_outbox (signal_status);
CREATE INDEX idx_orch_outbox_correlation ON orch_event_outbox (correlation_id);

ALTER TABLE orch_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_event_outbox_service_only ON orch_event_outbox
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

-- [Trace: FDN-001 §11.2 — mandatory per-engine ledger tables]
CREATE TABLE orch_event_inbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL,
  receiving_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG007_ORCH',
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  payload_out                JSONB,
  signal_status                TEXT NOT NULL DEFAULT 'RECEIVED'
                                 CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason               TEXT,
  idempotency_key                  TEXT NOT NULL UNIQUE,
  received_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at                          TIMESTAMPTZ,
  CONSTRAINT chk_orch_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_orch_inbox_status ON orch_event_inbox (signal_status);
CREATE INDEX idx_orch_inbox_correlation ON orch_event_inbox (correlation_id);

ALTER TABLE orch_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_event_inbox_service_only ON orch_event_inbox
  FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);
```

---

# SECTION 3 — SYSTEM API CONTRACTS

Engine 7 exposes no requester-facing HTTP surface — it is pure transport, never called from Presentation (Engine 11) or Integration (Engine 6) directly. Its only contracts are operational introspection endpoints for the Sovereign Executive Console.

## 3.1 `GET /api/v1/orchestration/health`

**Response — `200 OK`**

```json
{
  "runtime_health_status": "HEALTHY",
  "active_partitions": 14,
  "total_queue_depth": 212,
  "signals_in_flight": 47,
  "snapshot_at": "2026-08-16T09:00:00Z"
}
```

## 3.2 `GET /api/v1/orchestration/signals/{correlation_id}/trace`

**Request** (path parameter `correlation_id`)

**Response — `200 OK`**

```json
{
  "correlation_id": "8f14e45f-ceea-4c9c-9c60-1a2f3e4d5b6c",
  "graph": [
    { "node_sequence": 1, "engine_code": "TRS026_ENG004_BUS", "node_stage": "EMITTED" },
    { "node_sequence": 2, "engine_code": "TRS026_ENG007_ORCH", "node_stage": "ROUTED" },
    { "node_sequence": 3, "engine_code": "TRS026_ENG007_ORCH", "node_stage": "QUEUED" },
    { "node_sequence": 4, "engine_code": "TRS026_ENG007_ORCH", "node_stage": "DISPATCHED" },
    { "node_sequence": 5, "engine_code": "TRS026_ENG002_RESC", "node_stage": "ACCEPTED" }
  ]
}
```

---

# SECTION 4 — SIGNAL TRANSPORT CONTRACT

Engine 7 does not participate in a pairwise inbound/outbound signal matrix the way a domain engine does — it *is* the matrix. Its contract with every one of the other ten engines is structural, not signal-by-signal:

| Direction | Contract |
| --- | --- |
| From every engine's outbox | Engine 7 discovers every `PENDING` row, resolves its destination (§2.2–2.3), and admits it to the queue (§2.4) |
| To Engine 8 | A signal whose routing rule marks it as one-to-many or many-to-one is handed to Engine 8's Admission Authority before dispatch; a plain one-to-one signal proceeds directly |
| To every engine's inbox | Engine 7 (having received Engine 8's clearance where required) dispatches the leased signal (§2.5) directly into the destination engine's own inbox table, never any other table |
| To Engine 9 (AI/ML Advisory) | Read-only projection of §2.17–2.19 telemetry; Engine 9 never writes back and never influences a routing or priority decision |

## 4.1 The Signal Envelope (as applied to Engine 7)

Identical to the platform-wide envelope (Plate I, §11.2 of the Foundation instrument): `signal_id`, `correlation_id`, `causation_id`, `emitting_engine`, `receiving_engine`, `signal_type`, `payload_in`, `payload_out`, `signal_status`, `rejection_reason`, `idempotency_key`, `attempt_count`, `emitted_at`, `received_at`, `accepted_at`. No field is added, renamed, or omitted — an engine that invents its own envelope shape is non-conformant.

---

# ANNEX — CONFORMANCE SELF-CERTIFICATION AGAINST THE THREE PLATES

Filed in the same discipline as the Foundation instrument's Part XI and the Engine 2/3/4/5/6 Annexes.

| Check | Requirement | Result | Evidence |
| --- | --- | --- | --- |
| CC-02 | Every table assigned to exactly one of the five stations | **PASS** | §2.1–2.19: all tables realize Station 3 (Bridge Transit); `orch_event_outbox`/`orch_event_inbox` (§2.20) realize Stations 2 and 4 for Engine 7's own engine-level signals |
| CC-03 | Engine carries the four ledger tables with the standard envelope | **PASS** | §2.20, §4.1 |
| CC-04 | Every cross-engine interaction is a signal; no foreign table access | **PASS** | §2.3 — `synced_from_routing_rule_ref` and every destination reference is by value, never a foreign key across engines |
| CC-05 | Every mutation path passes an inbox ACCEPT and writes to `audit_log` | **PASS** | §2.15–2.16 record Engine 7's own routing/execution decisions as immutable evidence, complementing Foundation's `audit_log` |
| CC-06 | Idempotency, retry, dead-letter declared | **PASS** | `idempotency_key` UNIQUE on `orch_signal_queue` (§2.4) and both ledger tables (§2.20); §2.9–2.11 govern retry and compensation; exhaustion routes to Foundation's `dead_letter_review` |
| CC-07 | Engine declares its layer, holds nothing belonging to another layer | **PASS** | §1.3 — Layer 3, Workflow Management; holds no identity, order, catalogue, resource, pricing, or external-system state |
| CC-08 | Every crossing used appears in the Layer Crossing Law | **PASS** | FDN-001 §11.3 Layer Crossing Law, "Layer 2 -> Layer 2: Outbox -> bridge -> inbox -> ACCEPT -> mutation" — exactly Engine 7's role |
| CC-09 | Advisory outputs, if any, are records only | **N/A** | Engine 7 is not an advisory engine; §2.17–2.19 are read by Advisory, never written by it |
| CC-12 | Every provision carries a trace tag | **PASS** | Every DDL block and table comment carries a `[Trace: FDN-001 ...]` tag |
| RLS Law | Row-Level Security enabled on every table | **PASS** | All twenty-one tables (§2.1–2.20) carry `ENABLE ROW LEVEL SECURITY` with an explicit policy |
| Immutability Law | Ledgers append-only where history must never be rewritten | **PASS** | `orch_signal_lineage`, `orch_retry_history`, `orch_routing_audit`, `orch_execution_audit` carry `REVOKE UPDATE, DELETE` |

---

**END OF SPECIFICATION**

*Engine 7 is the heartbeat. If it stops, the platform stops — every engine queues in its outbox and waits, never improvising a direct call. Deterministic routing, leased queues, append-only lineage, registry-driven recovery, constitutional priority — the sequencing beneath every signal TrustRide moves.*
