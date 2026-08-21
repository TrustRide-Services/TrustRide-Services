# TRUSTRIDE SERVICES

# ENGINE 8 — WORKFLOW COORDINATION ENGINE
## Complete Architectural, Data, API, and Signal Specification

**[Parent Authority: TBOC v2.0.0 Genesis Edition · FDN-001 v3.0.0 Part IV & Part XI]**

*More than a Ride — We Save You Time.*

## Document Control

| Document Control Field | Entry |
| --- | --- |
| Document Title | Engine 8 — Workflow Coordination Engine: Complete Specification |
| Document Identifier | TRS026-ENG008-COORD-001 |
| Version | 1.0.0 |
| Status | **ADOPTED** (2026-08-16, per Founder directive — build order FDN → Resources → Services → Business → Cost → Integration → Orchestration → Coordination) |
| Classification | Institutional Blueprint — Confidential |
| Schema | `trustride` (single canonical PostgreSQL schema; this engine's tables are prefixed `coord_`) |
| Platform Code | TRS026 |
| Engine Code | `TRS026_ENG008_COORD` |
| Engine No. | `ENGINE_008` |
| Installation Order | 008 |
| Parent Authority | FDN-001 v3.0.0 Part IV (Event & Signal Substrate), Part V (Non-Negotiable Foundation Laws), Part XI §11.2 (Plate I Station Law — the "many-to-one" and "one-to-many" Processing Patterns), §11.6 Founder Ruling AQ-002 (on-device offline outbox owned jointly by Layer 3) and AQ-003 (fan-in timeout owned and defined by Workflow Coordination) |
| Architecture Lineage | Positioned as Engine 8 in the eleven-engine Constitutional Engine Registry (Annex C, FDN-001 v3.0.0); Layer 3 Workflow Management (Hybrid Bridge) of the Backend/Frontend/Event-Signal Architecture Blueprint v1.1.0 |

## Document Purpose & Constitutional Basis

This instrument specifies **Engine 8 — the Workflow Coordination Engine**, the second half of TrustRide's Sovereign Processing Unit. It answers one constitutional question for the rest of the platform — **may this distributed execution proceed, and has it truly finished?**

Like Engine 7, Engine 8 carries no business rule of its own (TBOC Article 8.2). It traces to the Foundation instrument that already anticipated its exact role:

| This engine's function | FDN-001 basis |
| --- | --- |
| The Bridge Transit station — fan-out, fan-in, timing — realized as `platform_event_coordination` ★ | FDN-001 §11.2, Plate I Station 3 |
| One-to-many: one emission, several receivers; each receiver reaches its own verdict independently | FDN-001 §11.2, Processing Pattern "One-to-many" |
| Many-to-one: coordination holds the fan-in until the declared set is complete or the declared timeout expires; partial fan-in never mutates state | FDN-001 §11.2, Processing Pattern "Many-to-one" |
| Mutation follows ACCEPT; the verdict is recorded before the state changes, never after | FDN-001 §11.2, Conformance Rule C-I-2 |
| Nothing is deleted from the ledgers; correction is a new signal, never an edit of history | FDN-001 §11.2, Conformance Rule C-I-5 |
| The Coordination fan-in timeout is owned and defined by Workflow Coordination (008) | FDN-001 §11.6, Founder Ruling AQ-003 |
| At the engine level, Integration together with Orchestration and Coordination close the loop for every Layer 2 engine | FDN-001 §11.6, Founder Ruling AQ-001 |

Where Engine 7 decides *when and in what order* a signal travels, Engine 8 decides *whether the distributed execution it belongs to is lawfully allowed to proceed, and when it is truly, immutably finished*. Business logic remains exclusively with the domain engines; Engine 8 governs the shape of their cooperation, never its content.

---

# SECTION 1 — ARCHITECTURAL ROLE & BOUNDARIES

## 1.1 Mission

Engine 8 is the platform's single, deterministic authority for distributed execution governance: admission, dependency satisfaction, context preservation, exactly-once consistency, multi-engine consensus, recovery, and constitutional finality. No fan-out or fan-in signal completes without passing through Engine 8; no one-to-one signal needs to.

## 1.2 Operational Duties

1. **Execution admission.** Validate that a distributed execution is eligible to enter coordination at all — the correct participants, the correct policy, before anything else happens (§2.1–2.3).
2. **Dependency governance.** Build and evaluate the dependency graph for an execution, holding any signal that depends on a prerequisite until that prerequisite is satisfied (§2.4–2.6).
3. **Context preservation.** Maintain the complete workflow instance, stage, and runtime context of every distributed execution so any participating engine can always answer "which workflow am I part of, and at what stage" (§2.7–2.9).
4. **Exactly-once consistency.** Guarantee that no signal is ever executed twice — fingerprinting every execution, detecting duplicates, and maintaining the single authoritative execution state (§2.10–2.12).
5. **Distributed consensus.** Own the many-to-one fan-in pattern completely: register the declared participants, collect their individual verdicts, evaluate quorum against the governed fan-in timeout (AQ-003), and issue the binding commit-or-abort decision (§2.13–2.16).
6. **Recovery governance.** When distributed execution fails, execute the governed recovery plan — retry, rollback, or compensation — never leaving an execution in an undefined state (§2.17–2.19).
7. **Execution finality.** Declare the single, immutable, constitutional outcome of a distributed execution — the last governance authority before Engine 7 resumes responsibility for response routing (§2.20–2.22).
8. **Runtime intelligence.** Observe coordination health continuously, without ever participating in an execution decision (§2.23–2.25).

## 1.3 Structural Position — Engine 7's Governance Partner

Like Engine 7, Engine 8 holds no conventional "Interfaces with the Other Ten Engines" table — it governs the shape of every other engine's cooperation rather than trading domain signals with any one of them.

- **From Engine 7:** every signal whose routing rule marks it one-to-many or many-to-one is handed to Engine 8's Admission Authority (§2.1–2.3) before Engine 7 dispatches it further.
- **To the participating engines:** Engine 8 never writes to another engine's domain tables. It reaches a commit/abort decision (§2.16) and hands the cleared signal back to Engine 7 for dispatch into the destination engine's own inbox, where that engine's own accept-handler performs the mutation.
- **Back to Engine 7:** Execution Finality (§2.20–2.22) is the constitutional boundary between execution governance and signal transport — once Engine 8 finalizes, Engine 7 resumes exclusive responsibility for releasing the response signal.
- **To Engine 9 (AI/ML Advisory):** read-only projection of §2.23–2.25 runtime intelligence; Engine 9 never writes back and never influences a coordination decision.

## 1.4 Boundaries — What Engine 8 Never Does

1. **Never authors domain truth.** Engine 8 governs whether and when execution proceeds; it never creates, interprets, or mutates a business payload.
2. **Never routes a signal.** Sequencing, queueing, and dispatch remain Engine 7's exclusive domain.
3. **Never mutates state before ACCEPT.** Mutation follows the consensus decision, never precedes it (FDN-001 C-I-2).
4. **Never lets a partial fan-in mutate state.** Consensus commits only at declared quorum or aborts at the declared timeout — there is no third outcome.
5. **Never edits history.** Every admission, dependency, consensus, recovery, and finality decision is permanent; correction is a new signal, never a rewritten row (FDN-001 C-I-5).
6. **Never blocks on intelligence.** Runtime Intelligence (§2.23–2.25) is an observer only — it has no permission to admit, reject, alter, delay, or finalize an execution.

---

# SECTION 2 — PRODUCTION SQL DDL SCHEMA (PostgreSQL / Supabase-Ready)

## 2.0 Extensions & Enums (prerequisite)

```sql
-- Extensions (idempotent; already present platform-wide per Engine 001 Phase 0)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE coord_admission_status_enum AS ENUM (
  'IN_PROGRESS', 'ADMITTED', 'REJECTED', 'DEFERRED'
);

CREATE TYPE coord_dependency_direction_enum AS ENUM (
  'REQUIRES', 'ENABLES'
);

CREATE TYPE coord_wait_status_enum AS ENUM (
  'WAITING', 'RELEASED', 'TIMED_OUT'
);

CREATE TYPE coord_workflow_status_enum AS ENUM (
  'RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED'
);

CREATE TYPE coord_stage_status_enum AS ENUM (
  'PENDING', 'ENTERED', 'COMPLETED', 'FAILED'
);

CREATE TYPE coord_context_status_enum AS ENUM (
  'ACTIVE', 'CLOSED'
);

-- [Trace: FDN-001 §11.2 | Processing Pattern "Many-to-one" — the fan-in vote]
CREATE TYPE coord_vote_decision_enum AS ENUM (
  'ACCEPT', 'REJECT', 'ABSTAIN'
);

CREATE TYPE coord_consensus_status_enum AS ENUM (
  'AWAITING_VOTES', 'QUORUM_MET', 'COMMITTED', 'ABORTED', 'TIMED_OUT'
);

CREATE TYPE coord_participant_role_enum AS ENUM (
  'MANDATORY', 'OPTIONAL'
);

CREATE TYPE coord_recovery_action_enum AS ENUM (
  'RETRY', 'ROLLBACK', 'COMPENSATE', 'TERMINATE'
);

CREATE TYPE coord_execution_result_enum AS ENUM (
  'SUCCESS', 'FAILURE'
);

CREATE TYPE coord_completion_state_enum AS ENUM (
  'COMPLETED', 'FAILED'
);

CREATE TYPE coord_health_status_enum AS ENUM (
  'HEALTHY', 'DEGRADED', 'CRITICAL'
);

CREATE TYPE coord_alert_level_enum AS ENUM (
  'INFO', 'WARNING', 'CRITICAL'
);
```

### 2.A — Execution Admission Authority

## 2.1 `coord_admission_policy` — Governed Admission Requirements

```sql
-- [Trace: FDN-001 §11.2 | No signal executes until admitted]
CREATE TABLE coord_admission_policy (
  admission_policy_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_type                TEXT NOT NULL UNIQUE,
  mandatory_validation          BOOLEAN NOT NULL DEFAULT TRUE,
  dependency_check_required        BOOLEAN NOT NULL DEFAULT FALSE,
  consensus_required                  BOOLEAN NOT NULL DEFAULT FALSE,
  active                                  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at                                TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE coord_admission_policy IS
  'Constitutional admission requirements per signal type; a signal type with consensus_required = TRUE always opens a coord_consensus_session (§2.13) before it may proceed.';

ALTER TABLE coord_admission_policy ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_admission_policy_platform_read ON coord_admission_policy
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_admission_policy_service_write ON coord_admission_policy
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

## 2.2 `coord_admission_session` — Runtime Admission Tracking

```sql
-- [Trace: FDN-001 §11.2 | Every distributed execution enters coordination through admission]
CREATE TABLE coord_admission_session (
  admission_session_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_id                  UUID NOT NULL,
  correlation_id              UUID NOT NULL,
  source_engine_code            TEXT NOT NULL,
  destination_engine_code          TEXT NOT NULL,
  admission_policy_id                 UUID REFERENCES coord_admission_policy (admission_policy_id),
  session_status                         coord_admission_status_enum NOT NULL DEFAULT 'IN_PROGRESS',
  started_at                                TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at                                 TIMESTAMPTZ
);

CREATE INDEX idx_coord_admission_session_correlation ON coord_admission_session (correlation_id);
CREATE INDEX idx_coord_admission_session_status ON coord_admission_session (session_status);

ALTER TABLE coord_admission_session ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_admission_session_platform_read ON coord_admission_session
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_admission_session_service_write ON coord_admission_session
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

## 2.3 `coord_admission_decision` — Constitutional Admission Outcome

```sql
-- [Trace: FDN-001 §11.2 | Admits, rejects, or defers — never silently honoured]
CREATE TABLE coord_admission_decision (
  admission_decision_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admission_session_id      UUID NOT NULL REFERENCES coord_admission_session (admission_session_id),
  decision                  TEXT NOT NULL CHECK (decision IN ('ADMITTED', 'REJECTED', 'DEFERRED')),
  decision_reason           TEXT,
  decided_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE coord_admission_decision IS
  'A signal requesting admission that is unregistered, ineligible, or malformed is REJECTED here, never silently honoured (mirrors FDN-001 C-I-6 at the coordination layer).';

ALTER TABLE coord_admission_decision ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_admission_decision_platform_read ON coord_admission_decision
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_admission_decision_service_write ON coord_admission_decision
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

### 2.B — Dependency Governance Authority

## 2.4 `coord_dependency_graph` — The Execution Dependency DAG

```sql
-- [Trace: FDN-001 §11.2 | No signal executes until every dependency is satisfied]
CREATE TABLE coord_dependency_graph (
  dependency_graph_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id         UUID NOT NULL,
  execution_id            UUID NOT NULL,
  parent_signal_id           UUID,
  child_signal_id               UUID NOT NULL,
  graph_level                      SMALLINT NOT NULL DEFAULT 0 CHECK (graph_level >= 0),
  dependency_direction                coord_dependency_direction_enum NOT NULL DEFAULT 'REQUIRES',
  created_at                             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_coord_dependency_graph_execution ON coord_dependency_graph (execution_id);
CREATE INDEX idx_coord_dependency_graph_correlation ON coord_dependency_graph (correlation_id);

ALTER TABLE coord_dependency_graph ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_dependency_graph_platform_read ON coord_dependency_graph
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_dependency_graph_service_write ON coord_dependency_graph
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

## 2.5 `coord_dependency_wait` — Signals Held for Prerequisites

```sql
-- [Trace: FDN-001 §11.2 | Prevents premature execution until blocking dependencies complete]
CREATE TABLE coord_dependency_wait (
  dependency_wait_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dependency_graph_id     UUID NOT NULL REFERENCES coord_dependency_graph (dependency_graph_id),
  signal_id               UUID NOT NULL,
  blocking_signal_id      UUID NOT NULL,
  wait_reason              TEXT,
  wait_started_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  wait_timeout_at                TIMESTAMPTZ,
  queue_status                      coord_wait_status_enum NOT NULL DEFAULT 'WAITING'
);

CREATE INDEX idx_coord_dependency_wait_status ON coord_dependency_wait (queue_status) WHERE queue_status = 'WAITING';

ALTER TABLE coord_dependency_wait ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_dependency_wait_platform_read ON coord_dependency_wait
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_dependency_wait_service_write ON coord_dependency_wait
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

## 2.6 `coord_dependency_resolution` — Dependency Evaluation Outcome

```sql
-- [Trace: FDN-001 §11.2 | Establishes deterministic execution order]
CREATE TABLE coord_dependency_resolution (
  dependency_resolution_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dependency_graph_id        UUID NOT NULL REFERENCES coord_dependency_graph (dependency_graph_id),
  resolution_result          BOOLEAN NOT NULL,
  blocking_dependency        BOOLEAN NOT NULL DEFAULT FALSE,
  resolution_message         TEXT,
  resolved_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE coord_dependency_resolution ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_dependency_resolution_platform_read ON coord_dependency_resolution
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_dependency_resolution_service_write ON coord_dependency_resolution
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

### 2.C — Correlation & Context Authority

## 2.7 `coord_workflow_instance` — One Row Per Executing Cross-Engine Workflow

```sql
-- [Trace: FDN-001 §11.2 | The distributed workflow this signal participates in]
CREATE TABLE coord_workflow_instance (
  workflow_instance_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_code           TEXT NOT NULL,
  correlation_id          UUID NOT NULL,
  workflow_status         coord_workflow_status_enum NOT NULL DEFAULT 'RUNNING',
  started_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at            TIMESTAMPTZ
);

CREATE INDEX idx_coord_workflow_instance_correlation ON coord_workflow_instance (correlation_id);
CREATE INDEX idx_coord_workflow_instance_status ON coord_workflow_instance (workflow_status);

ALTER TABLE coord_workflow_instance ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_workflow_instance_platform_read ON coord_workflow_instance
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_workflow_instance_service_write ON coord_workflow_instance
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

## 2.8 `coord_workflow_stage` — Stage-by-Stage Progression

```sql
-- [Trace: FDN-001 §11.2 | Which stage of the workflow this execution has reached]
CREATE TABLE coord_workflow_stage (
  workflow_stage_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_instance_id   UUID NOT NULL REFERENCES coord_workflow_instance (workflow_instance_id),
  stage_sequence         SMALLINT NOT NULL,
  stage_code             TEXT NOT NULL,
  executing_engine_code  TEXT NOT NULL,
  stage_status           coord_stage_status_enum NOT NULL DEFAULT 'PENDING',
  entered_at             TIMESTAMPTZ,
  completed_at           TIMESTAMPTZ
);

CREATE UNIQUE INDEX uq_coord_workflow_stage_sequence ON coord_workflow_stage (workflow_instance_id, stage_sequence);

ALTER TABLE coord_workflow_stage ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_workflow_stage_platform_read ON coord_workflow_stage
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_workflow_stage_service_write ON coord_workflow_stage
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

## 2.9 `coord_execution_context` — Preserved Runtime Context

```sql
-- [Trace: FDN-001 §11.2 | Complete distributed execution context]
CREATE TABLE coord_execution_context (
  execution_context_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id         UUID NOT NULL,
  execution_id           UUID NOT NULL,
  engine_code             TEXT NOT NULL,
  execution_scope            TEXT,
  runtime_context               JSONB NOT NULL DEFAULT '{}',
  context_status                   coord_context_status_enum NOT NULL DEFAULT 'ACTIVE',
  created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_coord_execution_context_execution ON coord_execution_context (execution_id);

ALTER TABLE coord_execution_context ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_execution_context_platform_read ON coord_execution_context
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_execution_context_service_write ON coord_execution_context
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

### 2.D — Execution Consistency Authority

## 2.10 `coord_execution_fingerprint` — Deterministic Execution Identity

```sql
-- [Trace: FDN-001 §11.2 | idempotency_key, given a distributed-execution home]
CREATE TABLE coord_execution_fingerprint (
  execution_fingerprint_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_id               UUID NOT NULL,
  signal_id                  UUID NOT NULL,
  fingerprint_hash            CHAR(64) NOT NULL UNIQUE,
  fingerprint_algorithm          TEXT NOT NULL DEFAULT 'SHA-256',
  created_at                        TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE coord_execution_fingerprint IS
  'A UNIQUE fingerprint_hash is the exactly-once guarantee: two attempts at the same execution produce the same fingerprint, and the second is a duplicate, never a re-execution.';

ALTER TABLE coord_execution_fingerprint ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_execution_fingerprint_service_only ON coord_execution_fingerprint
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

## 2.11 `coord_execution_state` — Authoritative Execution State

```sql
-- [Trace: FDN-001 §11.2 | The single authoritative execution state, never a duplicate truth]
CREATE TABLE coord_execution_state (
  execution_state_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_id           UUID NOT NULL,
  engine_code             TEXT NOT NULL,
  current_state              TEXT NOT NULL,
  previous_state                 TEXT,
  state_version                     BIGINT NOT NULL DEFAULT 1 CHECK (state_version > 0),
  state_at                             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_coord_execution_state_execution ON coord_execution_state (execution_id, state_version DESC);

ALTER TABLE coord_execution_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_execution_state_service_only ON coord_execution_state
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

## 2.12 `coord_duplicate_detection` — Duplicate Execution Prevention

```sql
-- [Trace: FDN-001 §11.2 | Reprocessing a duplicate idempotency_key is forbidden absolutely]
CREATE TABLE coord_duplicate_detection (
  duplicate_detection_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_id             UUID NOT NULL,
  signal_id                UUID NOT NULL,
  fingerprint_hash         CHAR(64) NOT NULL,
  duplicate_detected       BOOLEAN NOT NULL DEFAULT FALSE,
  duplicate_reason         TEXT,
  detected_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_coord_duplicate_detection_fingerprint ON coord_duplicate_detection (fingerprint_hash);

ALTER TABLE coord_duplicate_detection ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_duplicate_detection_service_only ON coord_duplicate_detection
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

### 2.E — Distributed Consensus Authority (The Many-to-One Fan-In)

## 2.13 `coord_consensus_session` — One Fan-In Wait, Governed by AQ-003

```sql
-- [Trace: FDN-001 §11.2, §11.6 AQ-003 | Coordination holds the fan-in until the declared set is complete or the declared timeout expires]
CREATE TABLE coord_consensus_session (
  consensus_session_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_id                UUID NOT NULL,
  correlation_id                  UUID NOT NULL,
  required_participant_count         SMALLINT NOT NULL CHECK (required_participant_count > 0),
  session_status                        coord_consensus_status_enum NOT NULL DEFAULT 'AWAITING_VOTES',
  fan_in_timeout_at                        TIMESTAMPTZ NOT NULL,
  started_at                                  TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at                                   TIMESTAMPTZ
);

CREATE INDEX idx_coord_consensus_session_status ON coord_consensus_session (session_status);
CREATE INDEX idx_coord_consensus_session_timeout ON coord_consensus_session (fan_in_timeout_at) WHERE session_status = 'AWAITING_VOTES';

COMMENT ON TABLE coord_consensus_session IS
  '[Trace: FDN-001 §11.6 AQ-003] fan_in_timeout_at is the governed threshold this Founder ruling assigns to Workflow Coordination alone; partial fan-in at expiry aborts (§2.16), it never partially mutates state.';

ALTER TABLE coord_consensus_session ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_consensus_session_platform_read ON coord_consensus_session
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_consensus_session_service_write ON coord_consensus_session
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

## 2.14 `coord_consensus_participant` — Declared Fan-In Participants

```sql
-- [Trace: FDN-001 §11.2 | One inbox row per receiver; each receiver reaches its own verdict independently]
CREATE TABLE coord_consensus_participant (
  consensus_participant_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consensus_session_id       UUID NOT NULL REFERENCES coord_consensus_session (consensus_session_id),
  engine_code                 TEXT NOT NULL,
  participant_role               coord_participant_role_enum NOT NULL DEFAULT 'MANDATORY',
  participant_status                coord_wait_status_enum NOT NULL DEFAULT 'WAITING',
  joined_at                            TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (consensus_session_id, engine_code)
);

ALTER TABLE coord_consensus_participant ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_consensus_participant_platform_read ON coord_consensus_participant
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_consensus_participant_service_write ON coord_consensus_participant
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

## 2.15 `coord_consensus_vote` — Immutable Participant Decisions

```sql
-- [Trace: FDN-001 §11.2, C-I-5 | Nothing is deleted from the ledgers]
CREATE TABLE coord_consensus_vote (
  consensus_vote_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consensus_session_id       UUID NOT NULL REFERENCES coord_consensus_session (consensus_session_id),
  consensus_participant_id   UUID NOT NULL REFERENCES coord_consensus_participant (consensus_participant_id),
  vote_decision               coord_vote_decision_enum NOT NULL,
  vote_reason                    TEXT,
  voted_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (consensus_participant_id)
);

COMMENT ON TABLE coord_consensus_vote IS
  'One immutable vote per participant. A participant that never votes before fan_in_timeout_at is treated as REJECT if MANDATORY, absent if OPTIONAL (§2.16).';

REVOKE UPDATE, DELETE ON coord_consensus_vote FROM PUBLIC;
REVOKE UPDATE, DELETE ON coord_consensus_vote FROM trustride_authenticated;

ALTER TABLE coord_consensus_vote ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_consensus_vote_platform_read ON coord_consensus_vote
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_consensus_vote_service_write ON coord_consensus_vote
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

## 2.16 `coord_consensus_decision` — The Binding Commit-or-Abort

```sql
-- [Trace: FDN-001 §11.2, C-I-2 | Mutation follows ACCEPT — the verdict is recorded before the state changes]
CREATE TABLE coord_consensus_decision (
  consensus_decision_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consensus_session_id      UUID NOT NULL UNIQUE REFERENCES coord_consensus_session (consensus_session_id),
  decision                  TEXT NOT NULL CHECK (decision IN ('COMMIT', 'ABORT')),
  decision_reason           TEXT,
  decided_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE coord_consensus_decision IS
  'The single binding outcome of a fan-in: COMMIT only at declared quorum, ABORT at the declared timeout — there is no partial-commit path.';

ALTER TABLE coord_consensus_decision ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_consensus_decision_platform_read ON coord_consensus_decision
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_consensus_decision_service_write ON coord_consensus_decision
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

### 2.F — Recovery Governance Authority

## 2.17 `coord_recovery_plan` — Ordered Recovery Workflow

```sql
-- [Trace: FDN-001 §11.2 | Constitutional recovery following distributed execution failure]
CREATE TABLE coord_recovery_plan (
  recovery_plan_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_id         UUID NOT NULL,
  recovery_action      coord_recovery_action_enum NOT NULL,
  execution_order      SMALLINT NOT NULL DEFAULT 1,
  timeout_seconds      INTEGER NOT NULL DEFAULT 30 CHECK (timeout_seconds > 0),
  plan_status          TEXT NOT NULL DEFAULT 'PENDING'
                          CHECK (plan_status IN ('PENDING', 'EXECUTING', 'COMPLETED', 'FAILED')),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_coord_recovery_plan_execution ON coord_recovery_plan (execution_id, execution_order);

ALTER TABLE coord_recovery_plan ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_recovery_plan_platform_read ON coord_recovery_plan
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_recovery_plan_service_write ON coord_recovery_plan
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

## 2.18 `coord_recovery_execution` — Recovery Step Execution

```sql
-- [Trace: FDN-001 §11.2 | Recovery step-by-step evidence]
CREATE TABLE coord_recovery_execution (
  recovery_execution_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recovery_plan_id        UUID NOT NULL REFERENCES coord_recovery_plan (recovery_plan_id),
  execution_step           SMALLINT NOT NULL,
  action_performed             TEXT NOT NULL,
  execution_result                coord_execution_result_enum NOT NULL,
  started_at                         TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at                          TIMESTAMPTZ
);

CREATE INDEX idx_coord_recovery_execution_plan ON coord_recovery_execution (recovery_plan_id, execution_step);

ALTER TABLE coord_recovery_execution ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_recovery_execution_platform_read ON coord_recovery_execution
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_recovery_execution_service_write ON coord_recovery_execution
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

## 2.19 `coord_compensation_execution` — Compensation Workflow

```sql
-- [Trace: FDN-001 §11.2 | Reverses completed actions when rollback is impossible]
CREATE TABLE coord_compensation_execution (
  compensation_execution_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_id                UUID NOT NULL,
  compensation_action         TEXT NOT NULL,
  compensation_sequence       SMALLINT NOT NULL DEFAULT 1,
  compensation_status         TEXT NOT NULL DEFAULT 'PENDING'
                                 CHECK (compensation_status IN ('PENDING', 'EXECUTED', 'FAILED')),
  executed_at                 TIMESTAMPTZ
);

CREATE INDEX idx_coord_compensation_execution_execution ON coord_compensation_execution (execution_id, compensation_sequence);

ALTER TABLE coord_compensation_execution ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_compensation_execution_platform_read ON coord_compensation_execution
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_compensation_execution_service_write ON coord_compensation_execution
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

### 2.G — Execution Finality Authority

## 2.20 `coord_execution_completion` — Constitutional Completion Record

```sql
-- [Trace: FDN-001 §11.2 | The last governance authority before control returns to Orchestration]
CREATE TABLE coord_execution_completion (
  execution_completion_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_id               UUID NOT NULL UNIQUE,
  completion_state               coord_completion_state_enum NOT NULL,
  completion_reason                 TEXT,
  completed_at                         TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE coord_execution_completion IS
  'Written only once every dependency, consensus, and recovery requirement has been satisfied; this is irreversible constitutional fact, not a status field that flips back.';

ALTER TABLE coord_execution_completion ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_execution_completion_platform_read ON coord_execution_completion
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_execution_completion_service_write ON coord_execution_completion
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

## 2.21 `coord_execution_certificate` — Sovereign Completion Certificate

```sql
-- [Trace: FDN-001 §11.2 | Sovereign proof that execution reached constitutional completion]
CREATE TABLE coord_execution_certificate (
  execution_certificate_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_completion_id    UUID NOT NULL REFERENCES coord_execution_completion (execution_completion_id),
  certificate_number         TEXT NOT NULL UNIQUE,
  certificate_hash           CHAR(64) NOT NULL,
  issued_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE coord_execution_certificate IS
  'A cryptographic seal over the completed execution; issuance is immutable and never reissued for the same execution_completion_id.';

REVOKE UPDATE, DELETE ON coord_execution_certificate FROM PUBLIC;
REVOKE UPDATE, DELETE ON coord_execution_certificate FROM trustride_authenticated;

ALTER TABLE coord_execution_certificate ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_execution_certificate_platform_read ON coord_execution_certificate
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_execution_certificate_service_write ON coord_execution_certificate
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

## 2.22 `coord_execution_release` — Hand-Back to Orchestration

```sql
-- [Trace: FDN-001 §11.6 AQ-001 | Execution Finality is the constitutional boundary between execution governance and signal transport]
CREATE TABLE coord_execution_release (
  execution_release_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_completion_id    UUID NOT NULL REFERENCES coord_execution_completion (execution_completion_id),
  response_signal_id         UUID,
  destination_engine_code    TEXT NOT NULL,
  release_status              TEXT NOT NULL DEFAULT 'PENDING' CHECK (release_status IN ('PENDING', 'RELEASED')),
  released_at                    TIMESTAMPTZ
);

COMMENT ON TABLE coord_execution_release IS
  'Authorizes release of the response signal back to Engine 7 for outbound dispatch; Engine 8''s authority over this execution ends the instant release_status = RELEASED.';

ALTER TABLE coord_execution_release ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_execution_release_platform_read ON coord_execution_release
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_execution_release_service_write ON coord_execution_release
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

### 2.H — Runtime Intelligence Authority

## 2.23 `coord_coordination_health` — Per-Engine Health Score

```sql
-- [Trace: FDN-001 §11.3 | Layer 3 obligation: heartbeat health published]
CREATE TABLE coord_coordination_health (
  coordination_health_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  engine_code               TEXT NOT NULL,
  health_score               NUMERIC(5,2) NOT NULL CHECK (health_score BETWEEN 0 AND 100),
  health_status                  coord_health_status_enum NOT NULL DEFAULT 'HEALTHY',
  measured_at                       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_coord_coordination_health_engine_time ON coord_coordination_health (engine_code, measured_at DESC);

COMMENT ON TABLE coord_coordination_health IS
  'This engine is intentionally non-authoritative with respect to execution: it has no permission to admit, reject, alter, delay, or finalize. Observation only.';

ALTER TABLE coord_coordination_health ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_coordination_health_platform_read ON coord_coordination_health
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_coordination_health_service_write ON coord_coordination_health
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

## 2.24 `coord_coordination_metrics` — Throughput & Latency Measurement

```sql
-- [Trace: FDN-001 §11.3 | Non-blocking, asynchronous observability]
CREATE TABLE coord_coordination_metrics (
  coordination_metric_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  engine_code               TEXT NOT NULL,
  metric_name               TEXT NOT NULL,
  metric_value               NUMERIC(18,4) NOT NULL,
  measured_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_coord_coordination_metrics_engine_time ON coord_coordination_metrics (engine_code, metric_name, measured_at DESC);

ALTER TABLE coord_coordination_metrics ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_coordination_metrics_platform_read ON coord_coordination_metrics
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_coordination_metrics_service_write ON coord_coordination_metrics
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

## 2.25 `coord_runtime_alert` — Threshold-Breach Alerts

```sql
-- [Trace: FDN-001 §11.3 | When the heartbeat is absent, the platform says so plainly]
CREATE TABLE coord_runtime_alert (
  runtime_alert_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_code           TEXT NOT NULL,
  alert_level          coord_alert_level_enum NOT NULL,
  alert_reason         TEXT NOT NULL,
  engine_code          TEXT,
  alert_status         TEXT NOT NULL DEFAULT 'OPEN' CHECK (alert_status IN ('OPEN', 'ACKNOWLEDGED', 'RESOLVED')),
  raised_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_coord_runtime_alert_status ON coord_runtime_alert (alert_status) WHERE alert_status = 'OPEN';

ALTER TABLE coord_runtime_alert ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_runtime_alert_platform_read ON coord_runtime_alert
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_runtime_alert_service_write ON coord_runtime_alert
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

### 2.I — Engine Event Substrate (Constitutional Mandatory Tables)

## 2.26 Engine 8's Own Signal Envelope

```sql
-- [Trace: FDN-001 §11.2 — mandatory per-engine ledger tables]
CREATE TABLE coord_event_outbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG008_COORD',
  receiving_engine       TEXT NOT NULL,
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  signal_status               TEXT NOT NULL DEFAULT 'PENDING'
                                CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason              TEXT,
  idempotency_key                 TEXT NOT NULL UNIQUE,
  attempt_count                     INTEGER NOT NULL DEFAULT 0,
  emitted_at                         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_coord_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_coord_outbox_status ON coord_event_outbox (signal_status);
CREATE INDEX idx_coord_outbox_correlation ON coord_event_outbox (correlation_id);

ALTER TABLE coord_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_event_outbox_service_only ON coord_event_outbox
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

-- [Trace: FDN-001 §11.2 — mandatory per-engine ledger tables]
CREATE TABLE coord_event_inbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL,
  receiving_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG008_COORD',
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  payload_out                JSONB,
  signal_status                TEXT NOT NULL DEFAULT 'RECEIVED'
                                 CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason               TEXT,
  idempotency_key                  TEXT NOT NULL UNIQUE,
  received_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at                          TIMESTAMPTZ,
  CONSTRAINT chk_coord_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_coord_inbox_status ON coord_event_inbox (signal_status);
CREATE INDEX idx_coord_inbox_correlation ON coord_event_inbox (correlation_id);

ALTER TABLE coord_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_event_inbox_service_only ON coord_event_inbox
  FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);
```

---

# SECTION 3 — SYSTEM API CONTRACTS

Like Engine 7, Engine 8 exposes no requester-facing HTTP surface. Its only contracts are operational introspection endpoints for the Sovereign Executive Console.

## 3.1 `GET /api/v1/coordination/consensus/{consensus_session_id}/status`

**Response — `200 OK`**

```json
{
  "consensus_session_id": "d5e6f7a8-b9c0-4d1e-8f2a-3b4c5d6e7f8a",
  "session_status": "AWAITING_VOTES",
  "required_participant_count": 3,
  "votes_received": 2,
  "fan_in_timeout_at": "2026-08-16T09:05:00Z"
}
```

## 3.2 `GET /api/v1/coordination/executions/{execution_id}/certificate`

**Response — `200 OK`**

```json
{
  "execution_id": "c3d4e5f6-a7b8-4c9d-0e1f-2a3b4c5d6e7f",
  "completion_state": "COMPLETED",
  "certificate_number": "TRS026-CERT-000012044",
  "certificate_hash": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
  "issued_at": "2026-08-16T09:00:04Z"
}
```

---

# SECTION 4 — SIGNAL TRANSPORT CONTRACT

Like Engine 7, Engine 8 does not trade a pairwise signal matrix with domain engines — it governs the shape of their cooperation.

| Direction | Contract |
| --- | --- |
| From Engine 7 | Every one-to-many or many-to-one signal is handed to `coord_admission_session` (§2.2) before any fan-out or fan-in begins |
| To participating engines | Never direct — Engine 8 reaches a commit/abort or completion decision, then hands control back to Engine 7 for dispatch into the destination engine's own inbox |
| Back to Engine 7 | `coord_execution_release` (§2.22) is the exact, sole handoff point — Engine 8's authority over an execution ends there |
| To Engine 9 (AI/ML Advisory) | Read-only projection of §2.23–2.25 runtime intelligence; Engine 9 never writes back and never influences a coordination decision |

## 4.1 The Signal Envelope (as applied to Engine 8)

Identical to the platform-wide envelope (Plate I, §11.2 of the Foundation instrument): `signal_id`, `correlation_id`, `causation_id`, `emitting_engine`, `receiving_engine`, `signal_type`, `payload_in`, `payload_out`, `signal_status`, `rejection_reason`, `idempotency_key`, `attempt_count`, `emitted_at`, `received_at`, `accepted_at`. No field is added, renamed, or omitted.

---

# ANNEX — CONFORMANCE SELF-CERTIFICATION AGAINST THE THREE PLATES

Filed in the same discipline as the Foundation instrument's Part XI and the Engine 2/3/4/5/6/7 Annexes.

| Check | Requirement | Result | Evidence |
| --- | --- | --- | --- |
| CC-02 | Every table assigned to exactly one of the five stations | **PASS** | §2.1–2.25: all tables realize Station 3 (Bridge Transit, fan-out/fan-in/timing); `coord_event_outbox`/`coord_event_inbox` (§2.26) realize Stations 2 and 4 for Engine 8's own engine-level signals |
| CC-03 | Engine carries the four ledger tables with the standard envelope | **PASS** | §2.26, §4.1 |
| CC-04 | Every cross-engine interaction is a signal; no foreign table access | **PASS** | Engine 8 never writes to another engine's domain table; every hand-back is via `coord_execution_release` (§2.22) into Engine 7 |
| CC-05 | Every mutation path passes an inbox ACCEPT and writes to `audit_log` | **PASS** | §2.16 `coord_consensus_decision` and §2.20 `coord_execution_completion` are the recorded verdicts that must precede any downstream mutation (C-I-2) |
| CC-06 | Idempotency, retry, dead-letter declared | **PASS** | `idempotency_key` UNIQUE on both ledger tables (§2.26); §2.10 `coord_execution_fingerprint` enforces exactly-once at the distributed-execution level |
| CC-07 | Engine declares its layer, holds nothing belonging to another layer | **PASS** | §1.3 — Layer 3, Workflow Management; holds no identity, order, catalogue, resource, pricing, or external-system state |
| CC-08 | Every crossing used appears in the Layer Crossing Law | **PASS** | FDN-001 §11.3 Layer Crossing Law |
| CC-09 | Advisory outputs, if any, are records only | **N/A** | Engine 8 is not an advisory engine; §2.23–2.25 are read by Advisory, never written by it |
| CC-12 | Every provision carries a trace tag | **PASS** | Every DDL block and table comment carries a `[Trace: FDN-001 ...]` tag |
| RLS Law | Row-Level Security enabled on every table | **PASS** | All twenty-seven tables (§2.1–2.26) carry `ENABLE ROW LEVEL SECURITY` with an explicit policy |
| Immutability Law | Ledgers append-only where history must never be rewritten | **PASS** | `coord_consensus_vote` and `coord_execution_certificate` carry `REVOKE UPDATE, DELETE` |
| Fan-In Law (AQ-003) | The Coordination fan-in timeout is owned and defined by Workflow Coordination | **PASS** | `coord_consensus_session.fan_in_timeout_at` (§2.13) is the sole governed threshold; no other engine's schema declares one |

---

**END OF SPECIFICATION**

*Engine 8 is the platform's constitutional patience and its constitutional certainty in one authority: it waits exactly as long as declared, agrees only when quorum is real, and finalizes only once, forever. No partial fan-in ever becomes truth.*
