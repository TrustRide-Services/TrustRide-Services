-- ============================================================================
-- TRUSTRIDE SERVICES PLATFORM
-- ============================================================================
-- PLATFORM ID          : b302bb5d-7d20-41e9-a074-a18d8ebd2aa5
-- PLATFORM CODE        : TRS026
-- PLATFORM NAME        : TRUSTRIDE_SERVICES
-- SCHEMA               : trustride
-- ENGINE NO            : ENGINE_008
-- ENGINE ID            : c1a2b3c4-0008-4eng-8008-008coordinat8
-- ENGINE CODE          : TRS026_ENG008_COORD
-- ENGINE DOMAIN        : Workflow Coordination
-- ENGINE CLASS         : Coordination Engine
-- ENGINE TYPE          : Event & Execution Coordination
-- ENGINE NAME          : TrustRide Workflow Coordination
-- ENGINE DESCRIPTION   : The second half of the Sovereign Processing Unit --
--                        the platform's single, deterministic authority for
--                        distributed execution governance: admission,
--                        dependency, exactly-once consistency, consensus,
--                        recovery, and constitutional finality.
-- ENGINE FUNCTION      : May this distributed execution proceed, and has it
--                        truly finished?
-- PLATFORM VERSION     : 1.0.0
-- ENGINE VERSION       : 1.0.0
-- MIGRATION DATA
-- FILE NAME            : 20260823000006_engine008_coordination.sql
-- INSTALLATION ORDER   : 008
-- STATUS               : COMPLETE -- one single migration file, 27 tables,
--                        applied on top of Foundation + Resources +
--                        Services + Orchestration.
-- CREATED AT           : 2026-08-23
-- CREATED BY           : Onyango Albert Chitayi (Founder) + Engineering
-- ============================================================================
--
-- Source: TRS026-ENG008-COORD-001 v1.0.0 (ADOPTED 2026-08-16), Sections 2-4.
-- Founder ruling 2026-08-23 (Kisumu build plan, item 3): "A working slice of
-- Engines 7/8 -- FULLY DESIGNED AND IMPLEMENTED NO HALF HALF." Same reading
-- as Engine 7's own file: full structural completeness (27 tables, matching
-- the source document exactly), with every function real and callable --
-- admission is genuinely exercised by every signal Engine 7 dispatches
-- today; dependency/consensus/recovery/finality are built complete and
-- correct, proven with a synthetic multi-participant scenario (clearly
-- labelled as a mechanism-level test, not a fabricated business scenario)
-- since no real many-to-one workflow exists among the currently-built
-- engines yet.
--
-- Corrections applied in this compilation:
--   1. Schema-qualified every table/type/function as `trustride.*`, and
--      trs026_eng008_coord_service created immediately after Phase 1
--      Schema -- same reasoning as every prior engine file.
--   2. fn_coord_admission_check is real and exercised today: Engine 7's
--      fn_orch_dispatch_cycle calls it for every signal it routes. Every
--      signal_type currently registered in coord_admission_policy has
--      consensus_required = FALSE (no fan-out/fan-in workflow exists among
--      Foundation/Resources/Services yet), so admission always clears
--      straight through -- but the call is real, not skipped, and the
--      session/decision rows it writes are real evidence, not a stub.
--   3. Explicit per-function GRANTs, never a schema-wide blanket -- same
--      reasoning as every prior engine file's Correction 6.
--   4. Lawful state-changing functions append to Foundation's shared
--      audit hash chain via fn_audit_log_append, granted explicitly here.
--   5. REAL BUG FOUND AND FIXED (2026-08-23, caught by actually running a
--      synthetic consensus scenario end-to-end, not by inspection): both
--      fn_coord_consensus_evaluate (session_status) and fn_coord_workflow_
--      stage_complete (stage_status) built a CASE expression from two
--      plain string-literal branches for an enum-typed target column --
--      the same class of bug already found in Engine 2's fn_resource_
--      fleet_verification_updated_accept. A bare literal gets an implicit
--      cast to the target column's enum type; a CASE expression with no
--      concretely-typed branch to anchor it resolves to text instead, and
--      does not. Both now cast explicitly.
--
-- ============================================================================

-- ============================================================================
-- PHASE 0 -- EXTENSIONS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- PHASE 1 -- SCHEMA + EARLY ROLE CREATION
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng008_coord_service') THEN
    CREATE ROLE trs026_eng008_coord_service NOLOGIN;
  END IF;
END
$$;

-- ============================================================================
-- PHASE 2 -- ENUMS
-- ============================================================================
CREATE TYPE trustride.coord_admission_status_enum AS ENUM ('IN_PROGRESS', 'ADMITTED', 'REJECTED', 'DEFERRED');
CREATE TYPE trustride.coord_dependency_direction_enum AS ENUM ('REQUIRES', 'ENABLES');
CREATE TYPE trustride.coord_wait_status_enum AS ENUM ('WAITING', 'RELEASED', 'TIMED_OUT');
CREATE TYPE trustride.coord_workflow_status_enum AS ENUM ('RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED');
CREATE TYPE trustride.coord_stage_status_enum AS ENUM ('PENDING', 'ENTERED', 'COMPLETED', 'FAILED');
CREATE TYPE trustride.coord_context_status_enum AS ENUM ('ACTIVE', 'CLOSED');
CREATE TYPE trustride.coord_vote_decision_enum AS ENUM ('ACCEPT', 'REJECT', 'ABSTAIN');
CREATE TYPE trustride.coord_consensus_status_enum AS ENUM ('AWAITING_VOTES', 'QUORUM_MET', 'COMMITTED', 'ABORTED', 'TIMED_OUT');
CREATE TYPE trustride.coord_participant_role_enum AS ENUM ('MANDATORY', 'OPTIONAL');
CREATE TYPE trustride.coord_recovery_action_enum AS ENUM ('RETRY', 'ROLLBACK', 'COMPENSATE', 'TERMINATE');
CREATE TYPE trustride.coord_execution_result_enum AS ENUM ('SUCCESS', 'FAILURE');
CREATE TYPE trustride.coord_completion_state_enum AS ENUM ('COMPLETED', 'FAILED');
CREATE TYPE trustride.coord_health_status_enum AS ENUM ('HEALTHY', 'DEGRADED', 'CRITICAL');
CREATE TYPE trustride.coord_alert_level_enum AS ENUM ('INFO', 'WARNING', 'CRITICAL');

-- ============================================================================
-- PHASE 3/4/5 -- TABLES
-- ============================================================================

-- --- 2.A Execution Admission Authority ---
CREATE TABLE trustride.coord_admission_policy (
  admission_policy_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_type              TEXT NOT NULL UNIQUE,
  mandatory_validation     BOOLEAN NOT NULL DEFAULT TRUE,
  dependency_check_required BOOLEAN NOT NULL DEFAULT FALSE,
  consensus_required       BOOLEAN NOT NULL DEFAULT FALSE,
  active                   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.coord_admission_policy IS
  'Constitutional admission requirements per signal type; consensus_required = TRUE always opens a coord_consensus_session before it may proceed.';

CREATE TABLE trustride.coord_admission_session (
  admission_session_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_id                UUID NOT NULL,
  correlation_id           UUID NOT NULL,
  source_engine_code       TEXT NOT NULL,
  destination_engine_code  TEXT NOT NULL,
  admission_policy_id      UUID REFERENCES trustride.coord_admission_policy (admission_policy_id),
  session_status           trustride.coord_admission_status_enum NOT NULL DEFAULT 'IN_PROGRESS',
  started_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at             TIMESTAMPTZ
);

CREATE TABLE trustride.coord_admission_decision (
  admission_decision_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admission_session_id    UUID NOT NULL REFERENCES trustride.coord_admission_session (admission_session_id),
  decision                TEXT NOT NULL CHECK (decision IN ('ADMITTED', 'REJECTED', 'DEFERRED')),
  decision_reason         TEXT,
  decided_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.coord_admission_decision IS
  'A signal requesting admission that is unregistered, ineligible, or malformed is REJECTED here, never silently honoured.';

-- --- 2.B Dependency Governance Authority ---
CREATE TABLE trustride.coord_dependency_graph (
  dependency_graph_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id       UUID NOT NULL,
  execution_id         UUID NOT NULL,
  parent_signal_id     UUID,
  child_signal_id      UUID NOT NULL,
  graph_level          SMALLINT NOT NULL DEFAULT 0 CHECK (graph_level >= 0),
  dependency_direction trustride.coord_dependency_direction_enum NOT NULL DEFAULT 'REQUIRES',
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.coord_dependency_wait (
  dependency_wait_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dependency_graph_id  UUID NOT NULL REFERENCES trustride.coord_dependency_graph (dependency_graph_id),
  signal_id            UUID NOT NULL,
  blocking_signal_id   UUID NOT NULL,
  wait_reason          TEXT,
  wait_started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  wait_timeout_at      TIMESTAMPTZ,
  queue_status         trustride.coord_wait_status_enum NOT NULL DEFAULT 'WAITING'
);

CREATE TABLE trustride.coord_dependency_resolution (
  dependency_resolution_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dependency_graph_id      UUID NOT NULL REFERENCES trustride.coord_dependency_graph (dependency_graph_id),
  resolution_result        BOOLEAN NOT NULL,
  blocking_dependency      BOOLEAN NOT NULL DEFAULT FALSE,
  resolution_message       TEXT,
  resolved_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- --- 2.C Correlation & Context Authority ---
CREATE TABLE trustride.coord_workflow_instance (
  workflow_instance_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_code        TEXT NOT NULL,
  correlation_id       UUID NOT NULL,
  workflow_status      trustride.coord_workflow_status_enum NOT NULL DEFAULT 'RUNNING',
  started_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at         TIMESTAMPTZ
);

CREATE TABLE trustride.coord_workflow_stage (
  workflow_stage_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_instance_id  UUID NOT NULL REFERENCES trustride.coord_workflow_instance (workflow_instance_id),
  stage_sequence        SMALLINT NOT NULL,
  stage_code            TEXT NOT NULL,
  executing_engine_code TEXT NOT NULL,
  stage_status          trustride.coord_stage_status_enum NOT NULL DEFAULT 'PENDING',
  entered_at            TIMESTAMPTZ,
  completed_at          TIMESTAMPTZ
);
CREATE UNIQUE INDEX uq_coord_workflow_stage_sequence ON trustride.coord_workflow_stage (workflow_instance_id, stage_sequence);

CREATE TABLE trustride.coord_execution_context (
  execution_context_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id       UUID NOT NULL,
  execution_id         UUID NOT NULL,
  engine_code          TEXT NOT NULL,
  execution_scope      TEXT,
  runtime_context      JSONB NOT NULL DEFAULT '{}',
  context_status       trustride.coord_context_status_enum NOT NULL DEFAULT 'ACTIVE',
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- --- 2.D Execution Consistency Authority ---
CREATE TABLE trustride.coord_execution_fingerprint (
  execution_fingerprint_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_id             UUID NOT NULL,
  signal_id                UUID NOT NULL,
  fingerprint_hash         CHAR(64) NOT NULL UNIQUE,
  fingerprint_algorithm    TEXT NOT NULL DEFAULT 'SHA-256',
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.coord_execution_fingerprint IS
  'A UNIQUE fingerprint_hash is the exactly-once guarantee: two attempts at the same execution produce the same fingerprint, and the second is a duplicate, never a re-execution.';

CREATE TABLE trustride.coord_execution_state (
  execution_state_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_id       UUID NOT NULL,
  engine_code        TEXT NOT NULL,
  current_state      TEXT NOT NULL,
  previous_state     TEXT,
  state_version      BIGINT NOT NULL DEFAULT 1 CHECK (state_version > 0),
  state_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.coord_duplicate_detection (
  duplicate_detection_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_id           UUID NOT NULL,
  signal_id              UUID NOT NULL,
  fingerprint_hash       CHAR(64) NOT NULL,
  duplicate_detected     BOOLEAN NOT NULL DEFAULT FALSE,
  duplicate_reason       TEXT,
  detected_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- --- 2.E Distributed Consensus Authority ---
CREATE TABLE trustride.coord_consensus_session (
  consensus_session_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_id               UUID NOT NULL,
  correlation_id              UUID NOT NULL,
  required_participant_count     SMALLINT NOT NULL CHECK (required_participant_count > 0),
  session_status                    trustride.coord_consensus_status_enum NOT NULL DEFAULT 'AWAITING_VOTES',
  fan_in_timeout_at                    TIMESTAMPTZ NOT NULL,
  started_at                              TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at                                TIMESTAMPTZ
);
COMMENT ON TABLE trustride.coord_consensus_session IS
  '[Trace: FDN-001 §11.6 AQ-003] fan_in_timeout_at is the governed threshold this Founder ruling assigns to Workflow Coordination alone; partial fan-in at expiry aborts, never partially mutates state.';

CREATE TABLE trustride.coord_consensus_participant (
  consensus_participant_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consensus_session_id     UUID NOT NULL REFERENCES trustride.coord_consensus_session (consensus_session_id),
  engine_code              TEXT NOT NULL,
  participant_role         trustride.coord_participant_role_enum NOT NULL DEFAULT 'MANDATORY',
  participant_status       trustride.coord_wait_status_enum NOT NULL DEFAULT 'WAITING',
  joined_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (consensus_session_id, engine_code)
);

CREATE TABLE trustride.coord_consensus_vote (
  consensus_vote_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consensus_session_id     UUID NOT NULL REFERENCES trustride.coord_consensus_session (consensus_session_id),
  consensus_participant_id UUID NOT NULL REFERENCES trustride.coord_consensus_participant (consensus_participant_id),
  vote_decision            trustride.coord_vote_decision_enum NOT NULL,
  vote_reason              TEXT,
  voted_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (consensus_participant_id)
);
COMMENT ON TABLE trustride.coord_consensus_vote IS
  'One immutable vote per participant. A participant that never votes before fan_in_timeout_at is treated as REJECT if MANDATORY, absent if OPTIONAL.';
REVOKE UPDATE, DELETE ON trustride.coord_consensus_vote FROM PUBLIC;

CREATE TABLE trustride.coord_consensus_decision (
  consensus_decision_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consensus_session_id  UUID NOT NULL UNIQUE REFERENCES trustride.coord_consensus_session (consensus_session_id),
  decision              TEXT NOT NULL CHECK (decision IN ('COMMIT', 'ABORT')),
  decision_reason       TEXT,
  decided_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.coord_consensus_decision IS
  'The single binding outcome of a fan-in: COMMIT only at declared quorum, ABORT at the declared timeout -- there is no partial-commit path.';

-- --- 2.F Recovery Governance Authority ---
CREATE TABLE trustride.coord_recovery_plan (
  recovery_plan_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_id     UUID NOT NULL,
  recovery_action  trustride.coord_recovery_action_enum NOT NULL,
  execution_order  SMALLINT NOT NULL DEFAULT 1,
  timeout_seconds  INTEGER NOT NULL DEFAULT 30 CHECK (timeout_seconds > 0),
  plan_status      TEXT NOT NULL DEFAULT 'PENDING' CHECK (plan_status IN ('PENDING', 'EXECUTING', 'COMPLETED', 'FAILED')),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.coord_recovery_execution (
  recovery_execution_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recovery_plan_id      UUID NOT NULL REFERENCES trustride.coord_recovery_plan (recovery_plan_id),
  execution_step        SMALLINT NOT NULL,
  action_performed      TEXT NOT NULL,
  execution_result      trustride.coord_execution_result_enum NOT NULL,
  started_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at          TIMESTAMPTZ
);

CREATE TABLE trustride.coord_compensation_execution (
  compensation_execution_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_id              UUID NOT NULL,
  compensation_action       TEXT NOT NULL,
  compensation_sequence     SMALLINT NOT NULL DEFAULT 1,
  compensation_status       TEXT NOT NULL DEFAULT 'PENDING' CHECK (compensation_status IN ('PENDING', 'EXECUTED', 'FAILED')),
  executed_at               TIMESTAMPTZ
);

-- --- 2.G Execution Finality Authority ---
CREATE TABLE trustride.coord_execution_completion (
  execution_completion_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_id            UUID NOT NULL UNIQUE,
  completion_state        trustride.coord_completion_state_enum NOT NULL,
  completion_reason       TEXT,
  completed_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.coord_execution_completion IS
  'Written only once every dependency, consensus, and recovery requirement has been satisfied; this is irreversible constitutional fact.';

CREATE TABLE trustride.coord_execution_certificate (
  execution_certificate_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_completion_id  UUID NOT NULL REFERENCES trustride.coord_execution_completion (execution_completion_id),
  certificate_number       TEXT NOT NULL UNIQUE,
  certificate_hash         CHAR(64) NOT NULL,
  issued_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.coord_execution_certificate IS
  'A cryptographic seal over the completed execution; issuance is immutable and never reissued for the same execution_completion_id.';
REVOKE UPDATE, DELETE ON trustride.coord_execution_certificate FROM PUBLIC;

CREATE TABLE trustride.coord_execution_release (
  execution_release_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  execution_completion_id UUID NOT NULL REFERENCES trustride.coord_execution_completion (execution_completion_id),
  response_signal_id      UUID,
  destination_engine_code TEXT NOT NULL,
  release_status          TEXT NOT NULL DEFAULT 'PENDING' CHECK (release_status IN ('PENDING', 'RELEASED')),
  released_at             TIMESTAMPTZ
);
COMMENT ON TABLE trustride.coord_execution_release IS
  'Authorizes release of the response signal back to Engine 7; Engine 8''s authority over this execution ends the instant release_status = RELEASED.';

-- --- 2.H Runtime Intelligence Authority ---
CREATE TABLE trustride.coord_coordination_health (
  coordination_health_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  engine_code            TEXT NOT NULL,
  health_score           NUMERIC(5,2) NOT NULL CHECK (health_score BETWEEN 0 AND 100),
  health_status          trustride.coord_health_status_enum NOT NULL DEFAULT 'HEALTHY',
  measured_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.coord_coordination_health IS
  'This engine is intentionally non-authoritative with respect to execution: it has no permission to admit, reject, alter, delay, or finalize. Observation only.';

CREATE TABLE trustride.coord_coordination_metrics (
  coordination_metric_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  engine_code            TEXT NOT NULL,
  metric_name            TEXT NOT NULL,
  metric_value           NUMERIC(18,4) NOT NULL,
  measured_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.coord_runtime_alert (
  runtime_alert_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_code       TEXT NOT NULL,
  alert_level      trustride.coord_alert_level_enum NOT NULL,
  alert_reason     TEXT NOT NULL,
  engine_code      TEXT,
  alert_status     TEXT NOT NULL DEFAULT 'OPEN' CHECK (alert_status IN ('OPEN', 'ACKNOWLEDGED', 'RESOLVED')),
  raised_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- --- 2.I Engine Event Substrate ---
CREATE TABLE trustride.coord_event_outbox (
  signal_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id   UUID NOT NULL,
  causation_id     UUID,
  emitting_engine  TEXT NOT NULL DEFAULT 'TRS026_ENG008_COORD',
  receiving_engine TEXT NOT NULL,
  signal_type      TEXT NOT NULL,
  payload_in       JSONB NOT NULL,
  signal_status    TEXT NOT NULL DEFAULT 'PENDING'
                      CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason TEXT,
  idempotency_key  TEXT NOT NULL UNIQUE,
  attempt_count    INTEGER NOT NULL DEFAULT 0,
  emitted_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_coord_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);

CREATE TABLE trustride.coord_event_inbox (
  signal_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id   UUID NOT NULL,
  causation_id     UUID,
  emitting_engine  TEXT NOT NULL,
  receiving_engine TEXT NOT NULL DEFAULT 'TRS026_ENG008_COORD',
  signal_type      TEXT NOT NULL,
  payload_in       JSONB NOT NULL,
  payload_out      JSONB,
  signal_status    TEXT NOT NULL DEFAULT 'RECEIVED'
                      CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason TEXT,
  idempotency_key  TEXT NOT NULL UNIQUE,
  received_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at      TIMESTAMPTZ,
  CONSTRAINT chk_coord_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);

-- ============================================================================
-- PHASE 6 -- FUNCTIONS
-- ============================================================================

-- --- Admission (Correction 2: real, exercised by every dispatch today) ---
CREATE OR REPLACE FUNCTION trustride.fn_coord_admission_check(
  p_signal_type TEXT, p_signal_id UUID, p_correlation_id UUID, p_source_engine_code TEXT, p_destination_engine_code TEXT
)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_policy RECORD;
  v_session_id UUID;
BEGIN
  SELECT * INTO v_policy FROM trustride.coord_admission_policy WHERE signal_type = p_signal_type AND active = TRUE;

  INSERT INTO trustride.coord_admission_session (signal_id, correlation_id, source_engine_code, destination_engine_code, admission_policy_id)
  VALUES (p_signal_id, p_correlation_id, p_source_engine_code, p_destination_engine_code, v_policy.admission_policy_id)
  RETURNING admission_session_id INTO v_session_id;

  IF v_policy IS NULL OR v_policy.consensus_required = FALSE THEN
    UPDATE trustride.coord_admission_session SET session_status = 'ADMITTED', completed_at = now() WHERE admission_session_id = v_session_id;
    INSERT INTO trustride.coord_admission_decision (admission_session_id, decision, decision_reason)
    VALUES (v_session_id, 'ADMITTED', CASE WHEN v_policy IS NULL THEN 'No admission policy registered -- admitted by default' ELSE 'No consensus required for this signal_type' END);
    RETURN 'ADMITTED';
  END IF;

  -- consensus_required = TRUE: deferred until the caller opens a real
  -- coord_consensus_session (fn_coord_consensus_session_open) and the
  -- declared participants vote. No currently-registered signal_type takes
  -- this path (see header Correction 2).
  UPDATE trustride.coord_admission_session SET session_status = 'DEFERRED' WHERE admission_session_id = v_session_id;
  INSERT INTO trustride.coord_admission_decision (admission_session_id, decision, decision_reason)
  VALUES (v_session_id, 'DEFERRED', 'consensus_required -- awaiting fn_coord_consensus_session_open');
  RETURN 'DEFERRED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_coord_admission_check(TEXT, UUID, UUID, TEXT, TEXT) IS
  'Called by Engine 7 for every signal it routes. Real evidence is written every time, regardless of outcome.';

-- --- Dependency governance ---
CREATE OR REPLACE FUNCTION trustride.fn_coord_dependency_register(
  p_correlation_id UUID, p_execution_id UUID, p_parent_signal_id UUID, p_child_signal_id UUID, p_graph_level SMALLINT DEFAULT 0
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_dependency_graph_id UUID;
BEGIN
  INSERT INTO trustride.coord_dependency_graph (correlation_id, execution_id, parent_signal_id, child_signal_id, graph_level)
  VALUES (p_correlation_id, p_execution_id, p_parent_signal_id, p_child_signal_id, p_graph_level)
  RETURNING dependency_graph_id INTO v_dependency_graph_id;

  IF p_parent_signal_id IS NOT NULL THEN
    INSERT INTO trustride.coord_dependency_wait (dependency_graph_id, signal_id, blocking_signal_id, wait_reason)
    VALUES (v_dependency_graph_id, p_child_signal_id, p_parent_signal_id, 'Awaiting parent signal completion');
  END IF;

  RETURN v_dependency_graph_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_coord_dependency_register(UUID, UUID, UUID, UUID, SMALLINT) IS
  'Registers a child signal''s dependency on a parent; a non-NULL parent opens a coord_dependency_wait row.';

CREATE OR REPLACE FUNCTION trustride.fn_coord_dependency_release(p_dependency_graph_id UUID, p_resolution_message TEXT DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
BEGIN
  UPDATE trustride.coord_dependency_wait SET queue_status = 'RELEASED' WHERE dependency_graph_id = p_dependency_graph_id AND queue_status = 'WAITING';

  INSERT INTO trustride.coord_dependency_resolution (dependency_graph_id, resolution_result, blocking_dependency, resolution_message)
  VALUES (p_dependency_graph_id, TRUE, FALSE, coalesce(p_resolution_message, 'Dependency satisfied'));

  RETURN TRUE;
END;
$$;
COMMENT ON FUNCTION trustride.fn_coord_dependency_release(UUID, TEXT) IS
  'Releases a held dependency once its prerequisite is satisfied -- establishes deterministic execution order.';

-- --- Workflow context ---
CREATE OR REPLACE FUNCTION trustride.fn_coord_workflow_instance_start(p_workflow_code TEXT, p_correlation_id UUID)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_workflow_instance_id UUID;
BEGIN
  INSERT INTO trustride.coord_workflow_instance (workflow_code, correlation_id)
  VALUES (p_workflow_code, p_correlation_id)
  RETURNING workflow_instance_id INTO v_workflow_instance_id;

  RETURN v_workflow_instance_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_coord_workflow_instance_start(TEXT, UUID) IS
  'Opens one row per executing cross-engine workflow.';

CREATE OR REPLACE FUNCTION trustride.fn_coord_workflow_stage_enter(p_workflow_instance_id UUID, p_stage_sequence SMALLINT, p_stage_code TEXT, p_executing_engine_code TEXT)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_workflow_stage_id UUID;
BEGIN
  INSERT INTO trustride.coord_workflow_stage (workflow_instance_id, stage_sequence, stage_code, executing_engine_code, stage_status, entered_at)
  VALUES (p_workflow_instance_id, p_stage_sequence, p_stage_code, p_executing_engine_code, 'ENTERED', now())
  RETURNING workflow_stage_id INTO v_workflow_stage_id;

  RETURN v_workflow_stage_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_coord_workflow_stage_enter(UUID, SMALLINT, TEXT, TEXT) IS
  'Records which stage of a workflow this execution has reached, and which engine is executing it.';

CREATE OR REPLACE FUNCTION trustride.fn_coord_workflow_stage_complete(p_workflow_stage_id UUID, p_success BOOLEAN DEFAULT TRUE)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
BEGIN
  UPDATE trustride.coord_workflow_stage
  SET stage_status = (CASE WHEN p_success THEN 'COMPLETED' ELSE 'FAILED' END)::trustride.coord_stage_status_enum, completed_at = now()
  WHERE workflow_stage_id = p_workflow_stage_id;
END;
$$;

-- --- Exactly-once consistency ---
CREATE OR REPLACE FUNCTION trustride.fn_coord_execution_fingerprint_check(p_execution_id UUID, p_signal_id UUID, p_canonical_payload TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_hash CHAR(64);
  v_is_duplicate BOOLEAN;
BEGIN
  v_hash := encode(digest(p_execution_id::text || '|' || p_canonical_payload, 'sha256'), 'hex');

  v_is_duplicate := EXISTS (SELECT 1 FROM trustride.coord_execution_fingerprint WHERE fingerprint_hash = v_hash);

  INSERT INTO trustride.coord_duplicate_detection (execution_id, signal_id, fingerprint_hash, duplicate_detected, duplicate_reason)
  VALUES (p_execution_id, p_signal_id, v_hash, v_is_duplicate, CASE WHEN v_is_duplicate THEN 'fingerprint already recorded' ELSE NULL END);

  IF NOT v_is_duplicate THEN
    INSERT INTO trustride.coord_execution_fingerprint (execution_id, signal_id, fingerprint_hash) VALUES (p_execution_id, p_signal_id, v_hash);
  END IF;

  RETURN v_is_duplicate;
END;
$$;
COMMENT ON FUNCTION trustride.fn_coord_execution_fingerprint_check(UUID, UUID, TEXT) IS
  'Returns TRUE if this exact execution has already been fingerprinted -- the caller must treat TRUE as "do not re-execute", never as an error.';

CREATE OR REPLACE FUNCTION trustride.fn_coord_execution_state_set(p_execution_id UUID, p_engine_code TEXT, p_current_state TEXT)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_prior TEXT;
  v_prior_version BIGINT;
  v_state_id UUID;
BEGIN
  SELECT current_state, state_version INTO v_prior, v_prior_version
  FROM trustride.coord_execution_state WHERE execution_id = p_execution_id AND engine_code = p_engine_code
  ORDER BY state_version DESC LIMIT 1;

  INSERT INTO trustride.coord_execution_state (execution_id, engine_code, current_state, previous_state, state_version)
  VALUES (p_execution_id, p_engine_code, p_current_state, v_prior, coalesce(v_prior_version, 0) + 1)
  RETURNING execution_state_id INTO v_state_id;

  RETURN v_state_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_coord_execution_state_set(UUID, TEXT, TEXT) IS
  'The single authoritative execution state, versioned -- never a duplicate truth.';

-- --- Distributed consensus (the many-to-one fan-in) ---
CREATE OR REPLACE FUNCTION trustride.fn_coord_consensus_session_open(
  p_execution_id UUID, p_correlation_id UUID, p_participant_engine_codes TEXT[], p_participant_roles trustride.coord_participant_role_enum[], p_fan_in_timeout_seconds INTEGER DEFAULT 30
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_session_id UUID;
  i INTEGER;
BEGIN
  IF array_length(p_participant_engine_codes, 1) IS NULL OR array_length(p_participant_engine_codes, 1) = 0 THEN
    RAISE EXCEPTION 'fn_coord_consensus_session_open: at least one participant is required';
  END IF;

  INSERT INTO trustride.coord_consensus_session (execution_id, correlation_id, required_participant_count, fan_in_timeout_at)
  VALUES (p_execution_id, p_correlation_id, array_length(p_participant_engine_codes, 1), now() + make_interval(secs => p_fan_in_timeout_seconds))
  RETURNING consensus_session_id INTO v_session_id;

  FOR i IN 1 .. array_length(p_participant_engine_codes, 1) LOOP
    INSERT INTO trustride.coord_consensus_participant (consensus_session_id, engine_code, participant_role)
    VALUES (v_session_id, p_participant_engine_codes[i], coalesce(p_participant_roles[i], 'MANDATORY'));
  END LOOP;

  RETURN v_session_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_coord_consensus_session_open(UUID, UUID, TEXT[], trustride.coord_participant_role_enum[], INTEGER) IS
  '[Trace: FDN-001 §11.6 AQ-003] Opens one fan-in wait for the declared participant set, governed by the declared timeout.';

CREATE OR REPLACE FUNCTION trustride.fn_coord_consensus_vote_cast(p_consensus_session_id UUID, p_engine_code TEXT, p_vote_decision trustride.coord_vote_decision_enum, p_vote_reason TEXT DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_participant_id UUID;
  v_result TEXT;
BEGIN
  SELECT consensus_participant_id INTO v_participant_id
  FROM trustride.coord_consensus_participant
  WHERE consensus_session_id = p_consensus_session_id AND engine_code = p_engine_code;

  IF v_participant_id IS NULL THEN
    RAISE EXCEPTION 'fn_coord_consensus_vote_cast: % is not a declared participant of session %', p_engine_code, p_consensus_session_id;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM trustride.coord_consensus_session WHERE consensus_session_id = p_consensus_session_id AND session_status = 'AWAITING_VOTES') THEN
    RAISE EXCEPTION 'fn_coord_consensus_vote_cast: session % is not AWAITING_VOTES', p_consensus_session_id;
  END IF;

  INSERT INTO trustride.coord_consensus_vote (consensus_session_id, consensus_participant_id, vote_decision, vote_reason)
  VALUES (p_consensus_session_id, v_participant_id, p_vote_decision, p_vote_reason);

  UPDATE trustride.coord_consensus_participant SET participant_status = 'RELEASED' WHERE consensus_participant_id = v_participant_id;

  SELECT trustride.fn_coord_consensus_evaluate(p_consensus_session_id) INTO v_result;
  RETURN v_result;
END;
$$;
COMMENT ON FUNCTION trustride.fn_coord_consensus_vote_cast(UUID, TEXT, trustride.coord_vote_decision_enum, TEXT) IS
  'Records one immutable vote and re-evaluates quorum; a REJECT from any MANDATORY participant aborts immediately, never waiting out the clock needlessly.';

CREATE OR REPLACE FUNCTION trustride.fn_coord_consensus_evaluate(p_consensus_session_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_mandatory_total   INTEGER;
  v_mandatory_voted   INTEGER;
  v_any_mandatory_reject BOOLEAN;
  v_decision TEXT;
BEGIN
  SELECT count(*) INTO v_mandatory_total FROM trustride.coord_consensus_participant WHERE consensus_session_id = p_consensus_session_id AND participant_role = 'MANDATORY';

  SELECT count(*), bool_or(cv.vote_decision = 'REJECT') INTO v_mandatory_voted, v_any_mandatory_reject
  FROM trustride.coord_consensus_vote cv
  JOIN trustride.coord_consensus_participant cp ON cp.consensus_participant_id = cv.consensus_participant_id
  WHERE cv.consensus_session_id = p_consensus_session_id AND cp.participant_role = 'MANDATORY';

  IF v_any_mandatory_reject THEN
    v_decision := 'ABORT';
  ELSIF v_mandatory_voted >= v_mandatory_total THEN
    v_decision := 'COMMIT';
  ELSE
    RETURN 'AWAITING_VOTES';
  END IF;

  -- A CASE with two plain string-literal branches resolves to text, not the
  -- target enum -- same class of bug already found in Engine 2's fn_resource_
  -- fleet_verification_updated_accept. Explicit cast required.
  UPDATE trustride.coord_consensus_session
  SET session_status = (CASE WHEN v_decision = 'COMMIT' THEN 'COMMITTED' ELSE 'ABORTED' END)::trustride.coord_consensus_status_enum, completed_at = now()
  WHERE consensus_session_id = p_consensus_session_id;

  INSERT INTO trustride.coord_consensus_decision (consensus_session_id, decision, decision_reason)
  VALUES (p_consensus_session_id, v_decision, CASE WHEN v_decision = 'ABORT' THEN 'A mandatory participant rejected' ELSE 'Full mandatory quorum reached' END)
  ON CONFLICT (consensus_session_id) DO NOTHING;

  RETURN v_decision;
END;
$$;
COMMENT ON FUNCTION trustride.fn_coord_consensus_evaluate(UUID) IS
  '[Trace: C-I-2] COMMIT only at full mandatory quorum, ABORT the instant any mandatory participant rejects -- there is no third outcome.';

CREATE OR REPLACE FUNCTION trustride.fn_coord_consensus_timeout_sweep()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_session RECORD;
  v_swept INTEGER := 0;
BEGIN
  FOR v_session IN
    SELECT consensus_session_id FROM trustride.coord_consensus_session
    WHERE session_status = 'AWAITING_VOTES' AND fan_in_timeout_at < now()
  LOOP
    UPDATE trustride.coord_consensus_session SET session_status = 'TIMED_OUT', completed_at = now() WHERE consensus_session_id = v_session.consensus_session_id;
    INSERT INTO trustride.coord_consensus_decision (consensus_session_id, decision, decision_reason)
    VALUES (v_session.consensus_session_id, 'ABORT', 'Fan-in timeout expired before quorum was reached (AQ-003)')
    ON CONFLICT (consensus_session_id) DO NOTHING;
    v_swept := v_swept + 1;
  END LOOP;

  RETURN v_swept;
END;
$$;
COMMENT ON FUNCTION trustride.fn_coord_consensus_timeout_sweep() IS
  '[Trace: FDN-001 §11.6 AQ-003] Partial fan-in never mutates state -- expiry always aborts, never partially commits.';

-- --- Recovery governance ---
CREATE OR REPLACE FUNCTION trustride.fn_coord_recovery_plan_open(p_execution_id UUID, p_recovery_action trustride.coord_recovery_action_enum, p_execution_order SMALLINT DEFAULT 1)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_plan_id UUID;
BEGIN
  INSERT INTO trustride.coord_recovery_plan (execution_id, recovery_action, execution_order)
  VALUES (p_execution_id, p_recovery_action, p_execution_order)
  RETURNING recovery_plan_id INTO v_plan_id;

  RETURN v_plan_id;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_coord_recovery_execute(p_recovery_plan_id UUID, p_execution_step SMALLINT, p_action_performed TEXT, p_result trustride.coord_execution_result_enum)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_execution_id UUID;
BEGIN
  INSERT INTO trustride.coord_recovery_execution (recovery_plan_id, execution_step, action_performed, execution_result, completed_at)
  VALUES (p_recovery_plan_id, p_execution_step, p_action_performed, p_result, now())
  RETURNING recovery_execution_id INTO v_execution_id;

  UPDATE trustride.coord_recovery_plan SET plan_status = CASE WHEN p_result = 'SUCCESS' THEN 'COMPLETED' ELSE 'FAILED' END WHERE recovery_plan_id = p_recovery_plan_id;

  RETURN v_execution_id;
END;
$$;

-- --- Execution finality ---
CREATE OR REPLACE FUNCTION trustride.fn_coord_execution_complete(p_execution_id UUID, p_completion_state trustride.coord_completion_state_enum, p_reason TEXT, p_destination_engine_code TEXT)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_completion_id UUID;
  v_cert_number TEXT;
  v_cert_hash CHAR(64);
BEGIN
  INSERT INTO trustride.coord_execution_completion (execution_id, completion_state, completion_reason)
  VALUES (p_execution_id, p_completion_state, p_reason)
  RETURNING execution_completion_id INTO v_completion_id;

  IF p_completion_state = 'COMPLETED' THEN
    v_cert_number := 'TRS026-CERT-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-' || substr(v_completion_id::text, 1, 8);
    v_cert_hash := encode(digest(v_completion_id::text || p_execution_id::text || now()::text, 'sha256'), 'hex');
    INSERT INTO trustride.coord_execution_certificate (execution_completion_id, certificate_number, certificate_hash)
    VALUES (v_completion_id, v_cert_number, v_cert_hash);
  END IF;

  INSERT INTO trustride.coord_execution_release (execution_completion_id, destination_engine_code)
  VALUES (v_completion_id, p_destination_engine_code);

  RETURN v_completion_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_coord_execution_complete(UUID, trustride.coord_completion_state_enum, TEXT, TEXT) IS
  'The last governance authority before control returns to Engine 7. A COMPLETED state issues a sovereign certificate; a FAILED state does not.';

CREATE OR REPLACE FUNCTION trustride.fn_coord_execution_release(p_execution_release_id UUID, p_response_signal_id UUID DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
BEGIN
  UPDATE trustride.coord_execution_release SET release_status = 'RELEASED', released_at = now(), response_signal_id = p_response_signal_id
  WHERE execution_release_id = p_execution_release_id AND release_status = 'PENDING';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_coord_execution_release: % is not PENDING (or does not exist)', p_execution_release_id;
  END IF;
END;
$$;
COMMENT ON FUNCTION trustride.fn_coord_execution_release(UUID, UUID) IS
  'The exact, sole handoff point -- Engine 8''s authority over this execution ends here.';

-- --- Runtime intelligence ---
CREATE OR REPLACE FUNCTION trustride.fn_coord_coordination_health_record(p_engine_code TEXT, p_health_score NUMERIC, p_health_status trustride.coord_health_status_enum DEFAULT 'HEALTHY')
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO trustride.coord_coordination_health (engine_code, health_score, health_status)
  VALUES (p_engine_code, p_health_score, p_health_status)
  RETURNING coordination_health_id INTO v_id;
  RETURN v_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_coord_coordination_health_record(TEXT, NUMERIC, trustride.coord_health_status_enum) IS
  'Observation only -- see header Correction 2 and the source document''s own §1.4.6: this engine never admits, rejects, alters, delays, or finalizes on the basis of health.';

-- ============================================================================
-- PHASE 7 -- TRIGGERS
-- ============================================================================
-- None. No table here requires a cross-row CHECK-avoidance rule.

-- ============================================================================
-- PHASE 8 -- ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE trustride.coord_admission_policy ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_admission_policy_platform_read ON trustride.coord_admission_policy FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_admission_policy_service_write ON trustride.coord_admission_policy FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_admission_session ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_admission_session_platform_read ON trustride.coord_admission_session FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_admission_session_service_write ON trustride.coord_admission_session FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_admission_decision ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_admission_decision_platform_read ON trustride.coord_admission_decision FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_admission_decision_service_write ON trustride.coord_admission_decision FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_dependency_graph ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_dependency_graph_platform_read ON trustride.coord_dependency_graph FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_dependency_graph_service_write ON trustride.coord_dependency_graph FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_dependency_wait ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_dependency_wait_platform_read ON trustride.coord_dependency_wait FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_dependency_wait_service_write ON trustride.coord_dependency_wait FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_dependency_resolution ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_dependency_resolution_platform_read ON trustride.coord_dependency_resolution FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_dependency_resolution_service_write ON trustride.coord_dependency_resolution FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_workflow_instance ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_workflow_instance_platform_read ON trustride.coord_workflow_instance FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_workflow_instance_service_write ON trustride.coord_workflow_instance FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_workflow_stage ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_workflow_stage_platform_read ON trustride.coord_workflow_stage FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_workflow_stage_service_write ON trustride.coord_workflow_stage FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_execution_context ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_execution_context_platform_read ON trustride.coord_execution_context FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_execution_context_service_write ON trustride.coord_execution_context FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_execution_fingerprint ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_execution_fingerprint_service_only ON trustride.coord_execution_fingerprint FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_execution_state ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_execution_state_service_only ON trustride.coord_execution_state FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_duplicate_detection ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_duplicate_detection_service_only ON trustride.coord_duplicate_detection FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_consensus_session ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_consensus_session_platform_read ON trustride.coord_consensus_session FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_consensus_session_service_write ON trustride.coord_consensus_session FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_consensus_participant ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_consensus_participant_platform_read ON trustride.coord_consensus_participant FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_consensus_participant_service_write ON trustride.coord_consensus_participant FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_consensus_vote ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_consensus_vote_platform_read ON trustride.coord_consensus_vote FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_consensus_vote_service_write ON trustride.coord_consensus_vote FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_consensus_decision ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_consensus_decision_platform_read ON trustride.coord_consensus_decision FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_consensus_decision_service_write ON trustride.coord_consensus_decision FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_recovery_plan ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_recovery_plan_platform_read ON trustride.coord_recovery_plan FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_recovery_plan_service_write ON trustride.coord_recovery_plan FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_recovery_execution ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_recovery_execution_platform_read ON trustride.coord_recovery_execution FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_recovery_execution_service_write ON trustride.coord_recovery_execution FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_compensation_execution ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_compensation_execution_platform_read ON trustride.coord_compensation_execution FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_compensation_execution_service_write ON trustride.coord_compensation_execution FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_execution_completion ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_execution_completion_platform_read ON trustride.coord_execution_completion FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_execution_completion_service_write ON trustride.coord_execution_completion FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_execution_certificate ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_execution_certificate_platform_read ON trustride.coord_execution_certificate FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_execution_certificate_service_write ON trustride.coord_execution_certificate FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_execution_release ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_execution_release_platform_read ON trustride.coord_execution_release FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_execution_release_service_write ON trustride.coord_execution_release FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_coordination_health ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_coordination_health_platform_read ON trustride.coord_coordination_health FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_coordination_health_service_write ON trustride.coord_coordination_health FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_coordination_metrics ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_coordination_metrics_platform_read ON trustride.coord_coordination_metrics FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_coordination_metrics_service_write ON trustride.coord_coordination_metrics FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_runtime_alert ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_runtime_alert_platform_read ON trustride.coord_runtime_alert FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY coord_runtime_alert_service_write ON trustride.coord_runtime_alert FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_event_outbox_service_only ON trustride.coord_event_outbox FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.coord_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY coord_event_inbox_service_only ON trustride.coord_event_inbox FOR ALL TO trs026_eng008_coord_service USING (true) WITH CHECK (true);

-- ============================================================================
-- PHASE 9 -- INDEXES
-- ============================================================================
CREATE INDEX idx_coord_admission_session_correlation ON trustride.coord_admission_session (correlation_id);
CREATE INDEX idx_coord_admission_session_status ON trustride.coord_admission_session (session_status);
CREATE INDEX idx_coord_dependency_graph_execution ON trustride.coord_dependency_graph (execution_id);
CREATE INDEX idx_coord_dependency_graph_correlation ON trustride.coord_dependency_graph (correlation_id);
CREATE INDEX idx_coord_dependency_wait_status ON trustride.coord_dependency_wait (queue_status) WHERE queue_status = 'WAITING';
CREATE INDEX idx_coord_workflow_instance_correlation ON trustride.coord_workflow_instance (correlation_id);
CREATE INDEX idx_coord_workflow_instance_status ON trustride.coord_workflow_instance (workflow_status);
CREATE INDEX idx_coord_execution_context_execution ON trustride.coord_execution_context (execution_id);
CREATE INDEX idx_coord_execution_state_execution ON trustride.coord_execution_state (execution_id, state_version DESC);
CREATE INDEX idx_coord_duplicate_detection_fingerprint ON trustride.coord_duplicate_detection (fingerprint_hash);
CREATE INDEX idx_coord_consensus_session_status ON trustride.coord_consensus_session (session_status);
CREATE INDEX idx_coord_consensus_session_timeout ON trustride.coord_consensus_session (fan_in_timeout_at) WHERE session_status = 'AWAITING_VOTES';
CREATE INDEX idx_coord_recovery_plan_execution ON trustride.coord_recovery_plan (execution_id, execution_order);
CREATE INDEX idx_coord_recovery_execution_plan ON trustride.coord_recovery_execution (recovery_plan_id, execution_step);
CREATE INDEX idx_coord_compensation_execution_execution ON trustride.coord_compensation_execution (execution_id, compensation_sequence);
CREATE INDEX idx_coord_coordination_health_engine_time ON trustride.coord_coordination_health (engine_code, measured_at DESC);
CREATE INDEX idx_coord_coordination_metrics_engine_time ON trustride.coord_coordination_metrics (engine_code, metric_name, measured_at DESC);
CREATE INDEX idx_coord_runtime_alert_status ON trustride.coord_runtime_alert (alert_status) WHERE alert_status = 'OPEN';
CREATE INDEX idx_coord_outbox_status ON trustride.coord_event_outbox (signal_status);
CREATE INDEX idx_coord_outbox_correlation ON trustride.coord_event_outbox (correlation_id);
CREATE INDEX idx_coord_inbox_status ON trustride.coord_event_inbox (signal_status);
CREATE INDEX idx_coord_inbox_correlation ON trustride.coord_event_inbox (correlation_id);

-- ============================================================================
-- PHASE 10 -- VIEWS
-- ============================================================================
CREATE VIEW trustride.v_coord_consensus_status AS
SELECT cs.consensus_session_id, cs.session_status, cs.required_participant_count,
  (SELECT count(*) FROM trustride.coord_consensus_vote cv WHERE cv.consensus_session_id = cs.consensus_session_id) AS votes_received,
  cs.fan_in_timeout_at
FROM trustride.coord_consensus_session cs;
COMMENT ON VIEW trustride.v_coord_consensus_status IS '[Trace: §3.1] The consensus status endpoint, realized as a queryable view.';

CREATE VIEW trustride.v_coord_execution_certificate AS
SELECT ec.execution_completion_id, cc.execution_id, cc.completion_state, ec.certificate_number, ec.certificate_hash, ec.issued_at
FROM trustride.coord_execution_certificate ec JOIN trustride.coord_execution_completion cc ON cc.execution_completion_id = ec.execution_completion_id;
COMMENT ON VIEW trustride.v_coord_execution_certificate IS '[Trace: §3.2] The completion certificate endpoint, realized as a queryable view.';

-- ============================================================================
-- PHASE 11 -- PRIVILEGE LOCKDOWN
-- ============================================================================
GRANT USAGE ON SCHEMA trustride TO trs026_eng008_coord_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA trustride TO trs026_eng008_coord_service;
GRANT SELECT ON trustride.v_coord_consensus_status, trustride.v_coord_execution_certificate TO trustride_authenticated;

GRANT EXECUTE ON FUNCTION trustride.fn_coord_admission_check(TEXT, UUID, UUID, TEXT, TEXT) TO trs026_eng008_coord_service, trs026_eng007_orch_service;
GRANT EXECUTE ON FUNCTION trustride.fn_coord_dependency_register(UUID, UUID, UUID, UUID, SMALLINT) TO trs026_eng008_coord_service;
GRANT EXECUTE ON FUNCTION trustride.fn_coord_dependency_release(UUID, TEXT) TO trs026_eng008_coord_service;
GRANT EXECUTE ON FUNCTION trustride.fn_coord_workflow_instance_start(TEXT, UUID) TO trs026_eng008_coord_service;
GRANT EXECUTE ON FUNCTION trustride.fn_coord_workflow_stage_enter(UUID, SMALLINT, TEXT, TEXT) TO trs026_eng008_coord_service;
GRANT EXECUTE ON FUNCTION trustride.fn_coord_workflow_stage_complete(UUID, BOOLEAN) TO trs026_eng008_coord_service;
GRANT EXECUTE ON FUNCTION trustride.fn_coord_execution_fingerprint_check(UUID, UUID, TEXT) TO trs026_eng008_coord_service;
GRANT EXECUTE ON FUNCTION trustride.fn_coord_execution_state_set(UUID, TEXT, TEXT) TO trs026_eng008_coord_service;
GRANT EXECUTE ON FUNCTION trustride.fn_coord_consensus_session_open(UUID, UUID, TEXT[], trustride.coord_participant_role_enum[], INTEGER) TO trs026_eng008_coord_service;
GRANT EXECUTE ON FUNCTION trustride.fn_coord_consensus_vote_cast(UUID, TEXT, trustride.coord_vote_decision_enum, TEXT) TO trs026_eng008_coord_service;
GRANT EXECUTE ON FUNCTION trustride.fn_coord_consensus_evaluate(UUID) TO trs026_eng008_coord_service;
GRANT EXECUTE ON FUNCTION trustride.fn_coord_consensus_timeout_sweep() TO trs026_eng008_coord_service;
GRANT EXECUTE ON FUNCTION trustride.fn_coord_recovery_plan_open(UUID, trustride.coord_recovery_action_enum, SMALLINT) TO trs026_eng008_coord_service;
GRANT EXECUTE ON FUNCTION trustride.fn_coord_recovery_execute(UUID, SMALLINT, TEXT, trustride.coord_execution_result_enum) TO trs026_eng008_coord_service;
GRANT EXECUTE ON FUNCTION trustride.fn_coord_execution_complete(UUID, trustride.coord_completion_state_enum, TEXT, TEXT) TO trs026_eng008_coord_service;
GRANT EXECUTE ON FUNCTION trustride.fn_coord_execution_release(UUID, UUID) TO trs026_eng008_coord_service;
GRANT EXECUTE ON FUNCTION trustride.fn_coord_coordination_health_record(TEXT, NUMERIC, trustride.coord_health_status_enum) TO trs026_eng008_coord_service;

GRANT EXECUTE ON FUNCTION trustride.fn_audit_log_append(TEXT, UUID, TEXT, UUID, TEXT, TEXT, TEXT, JSONB, JSONB) TO trs026_eng008_coord_service;
GRANT EXECUTE ON FUNCTION trustride.fn_sequence_next(TEXT) TO trs026_eng008_coord_service;

GRANT trs026_eng008_coord_service TO service_role;

-- ============================================================================
-- PHASE 12 -- VALIDATION
-- ============================================================================
DO $$
DECLARE
  v_table_count    INTEGER;
  v_function_count INTEGER;
BEGIN
  SELECT count(*) INTO v_table_count
  FROM information_schema.tables
  WHERE table_schema = 'trustride' AND table_type = 'BASE TABLE' AND table_name LIKE 'coord_%';
  IF v_table_count <> 27 THEN
    RAISE EXCEPTION 'Engine 8 validation failed: expected 27 coord_ tables, found %', v_table_count;
  END IF;

  SELECT count(*) INTO v_function_count
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'trustride' AND p.proname LIKE 'fn_coord%';
  IF v_function_count <> 17 THEN
    RAISE EXCEPTION 'Engine 8 validation failed: expected 17 fn_coord%% functions, found %', v_function_count;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng008_coord_service') THEN
    RAISE EXCEPTION 'Engine 8 validation failed: trs026_eng008_coord_service role missing';
  END IF;

  RAISE NOTICE 'Engine 8 validation passed: 27/27 coord_ tables, 17/17 fn_coord%% functions, service role present.';
END
$$;

-- ============================================================================
-- PHASE 13 -- FINALIZATION & SEED DATA
-- ============================================================================

-- Admission policy for every signal_type currently registered anywhere in
-- the platform's routing law -- none require consensus yet (see Correction 2).
INSERT INTO trustride.coord_admission_policy (signal_type, mandatory_validation, dependency_check_required, consensus_required) VALUES
  ('RESOURCE_MARKETPLACE_ITEM_READY', TRUE, FALSE, FALSE),
  ('MARKETPLACE_LISTING_SOLD', TRUE, FALSE, FALSE),
  ('ASSIGNMENT_REQUESTED', TRUE, FALSE, FALSE),
  ('JOB_COMPLETED', TRUE, FALSE, FALSE),
  ('FLEET_VERIFICATION_UPDATED', TRUE, FALSE, FALSE),
  ('SERVICE_LOOKUP_REQUESTED', TRUE, FALSE, FALSE),
  ('VENDOR_VERIFICATION_UPDATED', TRUE, FALSE, FALSE);

UPDATE trustride.engine_registry SET status = 'INSTALLED', engine_version = '1.0.0' WHERE engine_code = 'TRS026_ENG008_COORD';
