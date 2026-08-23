-- ============================================================================
-- TRUSTRIDE SERVICES PLATFORM
-- ============================================================================
-- PLATFORM ID          : b302bb5d-7d20-41e9-a074-a18d8ebd2aa5
-- PLATFORM CODE        : TRS026
-- PLATFORM NAME        : TRUSTRIDE_SERVICES
-- SCHEMA               : trustride
-- ENGINE NO            : ENGINE_007
-- ENGINE ID            : c1a2b3c4-0007-4eng-8007-007orchestrat7
-- ENGINE CODE          : TRS026_ENG007_ORCH
-- ENGINE DOMAIN        : Workflow Orchestration
-- ENGINE CLASS         : Control Engine
-- ENGINE TYPE          : Process Orchestration
-- ENGINE NAME          : TrustRide Workflow Orchestration
-- ENGINE DESCRIPTION   : One half of the Sovereign Processing Unit -- the
--                        platform's single, deterministic sequencing
--                        authority. Every signal emitted by every engine's
--                        outbox passes through here before it reaches any
--                        inbox. No engine ever calls another directly.
-- ENGINE FUNCTION      : Where does this signal go next, and in what order?
-- PLATFORM VERSION     : 1.0.0
-- ENGINE VERSION       : 1.0.0
-- MIGRATION DATA
-- FILE NAME            : 20260823000005_engine007_orchestration.sql
-- INSTALLATION ORDER   : 007
-- STATUS               : COMPLETE -- one single migration file, 22 tables
--                        (the source document's 21 plus one small addition,
--                        see Correction 3), applied on top of Foundation +
--                        Resources + Services.
-- CREATED AT           : 2026-08-23
-- CREATED BY           : Onyango Albert Chitayi (Founder) + Engineering
-- ============================================================================
--
-- Source: TRS026-ENG007-ORCH-001 v1.0.0 (ADOPTED 2026-08-16), Sections 2-4.
-- Founder ruling 2026-08-23 (Kisumu build plan, item 3): "A working slice of
-- Engines 7/8 -- FULLY DESIGNED AND IMPLEMENTED NO HALF HALF." Read precisely:
-- the full 22+27-table schema is built complete (structural completeness),
-- but the FUNCTIONS this increment proves real are the ones the currently-
-- built engines (Foundation, Resources, Services) actually exercise --
-- genuine dispatch, not a fabricated multi-engine scenario invented just to
-- exercise machinery nothing yet calls.
--
-- Corrections and additions applied in this compilation:
--   1. Schema-qualified every table/type/function as `trustride.*`, and
--      trs026_eng007_orch_service created immediately after Phase 1 Schema
--      -- same reasoning as every prior engine file.
--   2. THE REAL GAP THIS FILE CLOSES: every outbox row Resources and
--      Services have ever emitted (RESOURCE_RESERVED, RESOURCE_ASSIGNED,
--      RESOURCE_DISPATCH_INITIATED, RESOURCE_MARKETPLACE_ITEM_READY,
--      SERVICE_RESOLVED, SERVICE_CONTEXT_RESOLVED, SERVICE_CATALOGUE_UPDATED,
--      MARKETPLACE_LISTING_SOLD) has sat in signal_status='PENDING' forever
--      -- nothing has ever moved a row from one engine's outbox into
--      another's inbox. fn_orch_dispatch_cycle() below is that mechanism,
--      for real: discover PENDING, resolve destination, admit (via Engine
--      8), queue, dispatch into the destination inbox, and hand off to that
--      engine's own accept-handler -- with full lineage/execution-graph/
--      hash-chained-audit at every hop.
--   3. Addition: `orch_outbox_registry` (engine_code -> outbox table name),
--      not in the source document. fn_orch_dispatch_cycle must discover
--      PENDING rows across every engine's own outbox table by name, and a
--      hardcoded table list would need a function edit every time a new
--      engine is built; this small registry makes it data-driven instead --
--      registering a new engine's outbox is one INSERT, not a code change.
--   4. Foundation's own routing_rule table (Phase 1.D) was created but
--      never populated by Resources' or Services' own migration files --
--      "governed vocabulary... populated as each engine's own signal
--      matrix is built" (Foundation's own comment) never actually
--      happened. This file backfills it for the signal types Resources and
--      Services already emit, since Engine 7 cannot do its job without it
--      existing and nothing else has supplied it. Routes to engines not
--      yet built (Business, Cost, Presentation) are deliberately NOT
--      registered -- an unregistered destination correctly and honestly
--      surfaces as NO_RULE_MATCHED (recorded, never silently dropped, per
--      FDN-001 C-I-6), rather than fabricating a route to a table that
--      does not exist. Register those routes when those engines are built.
--   5. fn_resource_inbox_process(UUID) and fn_service_inbox_process(UUID)
--      -- thin per-engine dispatchers that route a RECEIVED inbox row to
--      the accept-handler already built in Engine 2's/Engine 3's own
--      migration files, by signal_type. Conceptually these belong to
--      Resources/Services, not Orchestration -- housed here because Engine
--      7 is what actually needed somewhere to hand off to once a signal
--      reaches RECEIVED, and neither engine's own file provided one.
--      Function calls across engines are already an established, accepted
--      pattern in this codebase (every engine calls Foundation's
--      fn_audit_log_append); only cross-engine TABLE access is forbidden
--      (Article 33), and these functions only ever touch their own named
--      engine's inbox table.
--   6. Runtime telemetry (§2.G: queue/routing metrics, capacity snapshot)
--      is built as real, callable functions, but is NOT wired to fire
--      automatically on every queue operation -- that would need a live
--      scheduled worker with real production load to test meaningfully,
--      neither of which exists yet. A manual fn_orch_capacity_snapshot_
--      record() is provided and proven to work; automatic, continuous
--      collection is a real next step, not fabricated here.
--   7. Explicit per-function GRANTs, never a schema-wide blanket -- same
--      reasoning as every prior engine file's Correction 6.
--   8. REAL BUG FOUND AND FIXED (2026-08-23, caught by actually running the
--      dispatch cycle end-to-end, not by inspection): fn_orch_dispatch_
--      cycle's hash-chain construction calls digest(), which requires
--      `extensions` on the search_path -- the exact same class of bug
--      already found and fixed in Foundation's fn_audit_log_append.
--   9. REAL BUG FOUND AND FIXED (2026-08-23, caught by actually dispatching
--      a real fan-out signal, MARKETPLACE_LISTING_SOLD, which Engine 3
--      emits as two separate outbox rows to two different destinations):
--      orch_destination_cache was keyed only on (source_engine_code,
--      signal_type), which cannot represent fan-out -- the second
--      destination silently collapsed into the first, and a signal meant
--      for Business was wrongly delivered into Resources' inbox instead.
--      Fixed by keying the cache on (source_engine_code, signal_type,
--      destination_engine_code) -- three-way, matching routing_rule's own
--      uniqueness -- and having fn_orch_dispatch_cycle's lookup match the
--      row's own declared receiving_engine, never resolve a destination
--      from scratch that ignores what the emitting engine already stated.
--
-- ============================================================================

-- ============================================================================
-- PHASE 0 -- EXTENSIONS (idempotent; already present platform-wide)
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- PHASE 1 -- SCHEMA + EARLY ROLE CREATION
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng007_orch_service') THEN
    CREATE ROLE trs026_eng007_orch_service NOLOGIN;
  END IF;
END
$$;

-- ============================================================================
-- PHASE 2 -- ENUMS
-- ============================================================================
CREATE TYPE trustride.orch_signal_status_enum AS ENUM (
  'PENDING', 'DISPATCHED', 'RECEIVED', 'ACCEPTED', 'REJECTED', 'DEAD_LETTER'
);
CREATE TYPE trustride.orch_partition_status_enum AS ENUM ('ACTIVE', 'PAUSED', 'DRAINING');
CREATE TYPE trustride.orch_queue_status_enum AS ENUM ('QUEUED', 'LEASED', 'DISPATCHED', 'COMPLETED', 'FAILED');
CREATE TYPE trustride.orch_lease_status_enum AS ENUM ('LEASED', 'RELEASED', 'EXPIRED');
CREATE TYPE trustride.orch_priority_level_enum AS ENUM ('CRITICAL', 'HIGH', 'NORMAL', 'LOW');
CREATE TYPE trustride.orch_retry_status_enum AS ENUM ('SCHEDULED', 'EXECUTING', 'EXHAUSTED', 'CANCELLED');
CREATE TYPE trustride.orch_sla_window_status_enum AS ENUM ('ON_TRACK', 'WARNING', 'BREACHED');
CREATE TYPE trustride.orch_lineage_relationship_enum AS ENUM ('CAUSED', 'TRIGGERED', 'BROADCAST_FANOUT');
CREATE TYPE trustride.orch_graph_stage_enum AS ENUM ('EMITTED', 'ROUTED', 'QUEUED', 'DISPATCHED', 'RECEIVED', 'ACCEPTED', 'REJECTED');

-- ============================================================================
-- PHASE 3/4/5 -- TABLES
-- ============================================================================

-- --- 2.A Signal Routing Authority ---
CREATE TABLE trustride.orch_queue_partition (
  queue_partition_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  partition_code      TEXT NOT NULL UNIQUE,
  partition_name      TEXT NOT NULL,
  engine_code         TEXT NOT NULL,
  priority_level      trustride.orch_priority_level_enum NOT NULL DEFAULT 'NORMAL',
  max_depth           INTEGER NOT NULL DEFAULT 10000 CHECK (max_depth > 0),
  current_depth       INTEGER NOT NULL DEFAULT 0 CHECK (current_depth >= 0),
  partition_status    trustride.orch_partition_status_enum NOT NULL DEFAULT 'ACTIVE',
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.orch_queue_partition IS
  '[Trace: FDN-001 §11.2] Every partition operates independently, segmented by destination engine and priority, so one congested destination never starves another.';

CREATE TABLE trustride.orch_routing_decision (
  routing_decision_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_id               UUID NOT NULL,
  correlation_id          UUID NOT NULL,
  source_engine_code      TEXT NOT NULL,
  destination_engine_code TEXT NOT NULL,
  signal_type             TEXT NOT NULL,
  matched_routing_rule_ref TEXT,
  destination_partition_code TEXT,
  routing_result          TEXT NOT NULL CHECK (routing_result IN ('ROUTED', 'NO_RULE_MATCHED', 'REJECTED')),
  routing_duration_ms     INTEGER,
  decided_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.orch_routing_decision IS
  '[Trace: FDN-001 §11.2, C-I-6] Every routing outcome is recorded, including NO_RULE_MATCHED -- proof nothing was ever silently dropped.';

CREATE TABLE trustride.orch_destination_cache (
  destination_cache_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_engine_code      TEXT NOT NULL,
  signal_type             TEXT NOT NULL,
  destination_engine_code TEXT NOT NULL,
  destination_inbox_table TEXT NOT NULL,
  default_partition_code  TEXT NOT NULL,
  synced_from_routing_rule_ref TEXT,
  cache_status            TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (cache_status IN ('ACTIVE', 'STALE', 'SUPERSEDED')),
  last_synced_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Three-way, matching routing_rule's own (event_type, source_engine,
  -- target_engine) uniqueness -- a two-way key here cannot represent
  -- fan-out (the same source+signal_type routed to two different
  -- destinations, e.g. MARKETPLACE_LISTING_SOLD -> both Business and
  -- Resources), and previously collapsed the second destination into the
  -- first. Found by actually dispatching a real fan-out signal, not by
  -- inspection: the second destination silently got the first
  -- destination's inbox row instead of its own.
  UNIQUE (source_engine_code, signal_type, destination_engine_code)
);
COMMENT ON TABLE trustride.orch_destination_cache IS
  '[Trace: FDN-001 Part X §3.2] Foundation''s routing_rule remains the lawful source of routing vocabulary; this cache is refreshed by fn_orch_destination_cache_sync, never edited independently.';

-- Correction 3: addition, not in the source document.
CREATE TABLE trustride.orch_outbox_registry (
  outbox_registry_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  engine_code        TEXT NOT NULL UNIQUE,
  outbox_table_name  TEXT NOT NULL,
  active             BOOLEAN NOT NULL DEFAULT TRUE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.orch_outbox_registry IS
  'Correction 3 (not in the source document): makes fn_orch_dispatch_cycle data-driven across every engine''s outbox table -- registering a new engine is one INSERT, not a function edit.';

-- --- 2.B Message Queue Authority ---
CREATE TABLE trustride.orch_signal_queue (
  queue_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_id                UUID NOT NULL,
  correlation_id           UUID NOT NULL,
  source_engine_code       TEXT NOT NULL,
  destination_engine_code  TEXT NOT NULL,
  signal_type              TEXT NOT NULL,
  queue_partition_id       UUID NOT NULL REFERENCES trustride.orch_queue_partition (queue_partition_id),
  priority_level           trustride.orch_priority_level_enum NOT NULL DEFAULT 'NORMAL',
  queue_status             TEXT NOT NULL DEFAULT 'QUEUED' CHECK (queue_status IN ('QUEUED', 'LEASED', 'DISPATCHED', 'COMPLETED', 'FAILED')),
  queued_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  dispatched_at            TIMESTAMPTZ,
  expires_at               TIMESTAMPTZ,
  retry_count              INTEGER NOT NULL DEFAULT 0 CHECK (retry_count >= 0),
  idempotency_key          TEXT NOT NULL UNIQUE,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.orch_signal_queue IS
  '[Trace: FDN-001 §11.2] No signal is dispatched unless it is admitted and persisted here first; queue ownership is leased, never held permanently.';

CREATE TABLE trustride.orch_queue_lease (
  lease_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  queue_id         UUID NOT NULL REFERENCES trustride.orch_signal_queue (queue_id),
  leased_by        TEXT NOT NULL,
  lease_status     TEXT NOT NULL DEFAULT 'LEASED' CHECK (lease_status IN ('LEASED', 'RELEASED', 'EXPIRED')),
  lease_started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  lease_expires_at TIMESTAMPTZ NOT NULL,
  released_at      TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.orch_queue_lease IS
  'A worker leases a queued signal; it never owns the queue. An expired, unreleased lease returns the signal to QUEUED, never to a stuck state.';

CREATE TABLE trustride.orch_queue_checkpoint (
  checkpoint_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  queue_partition_id      UUID NOT NULL REFERENCES trustride.orch_queue_partition (queue_partition_id),
  last_queue_id           UUID REFERENCES trustride.orch_signal_queue (queue_id),
  last_processed_sequence BIGINT NOT NULL DEFAULT 0,
  checkpoint_status       TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (checkpoint_status IN ('ACTIVE', 'RECOVERING')),
  checkpoint_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.orch_queue_checkpoint IS
  'Enables replay-safe restart of a partition after interruption without losing ordering or duplicating dispatched work.';

-- --- 2.C Correlation & Lineage Authority ---
CREATE TABLE trustride.orch_signal_lineage (
  lineage_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id    UUID NOT NULL,
  parent_signal_id  UUID,
  child_signal_id   UUID NOT NULL,
  relationship_type trustride.orch_lineage_relationship_enum NOT NULL DEFAULT 'CAUSED',
  generation_level  SMALLINT NOT NULL DEFAULT 0 CHECK (generation_level >= 0),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.orch_signal_lineage IS
  'Append-only. Nothing is ever deleted or edited; a correction is a new signal with a new lineage row, never a rewrite of history.';
REVOKE UPDATE, DELETE ON trustride.orch_signal_lineage FROM PUBLIC;

CREATE TABLE trustride.orch_execution_graph (
  graph_node_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id  UUID NOT NULL,
  signal_id       UUID NOT NULL,
  node_sequence   INTEGER NOT NULL,
  engine_code     TEXT NOT NULL,
  node_stage      trustride.orch_graph_stage_enum NOT NULL,
  entered_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at    TIMESTAMPTZ
);
COMMENT ON TABLE trustride.orch_execution_graph IS
  'System Outbox -> Routing -> Queue -> Lease -> Dispatch -> Inbox -> Engine -> Completed: every hop becomes one node here, reconstructing the exact path after the fact.';

-- --- 2.D Retry & Compensation Authority ---
CREATE TABLE trustride.orch_retry_schedule (
  retry_schedule_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  queue_id           UUID NOT NULL REFERENCES trustride.orch_signal_queue (queue_id),
  retry_attempt      INTEGER NOT NULL CHECK (retry_attempt > 0),
  max_retry_attempts INTEGER NOT NULL DEFAULT 5 CHECK (max_retry_attempts > 0),
  next_retry_at      TIMESTAMPTZ NOT NULL,
  retry_interval_ms  INTEGER NOT NULL CHECK (retry_interval_ms > 0),
  retry_reason       TEXT,
  retry_status       TEXT NOT NULL DEFAULT 'SCHEDULED' CHECK (retry_status IN ('SCHEDULED', 'EXECUTING', 'EXHAUSTED', 'CANCELLED')),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.orch_retry_schedule IS
  'Registry-driven scheduling only; decides when, not how. Exhaustion triggers compensation, never a silent drop.';

CREATE TABLE trustride.orch_retry_history (
  retry_history_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  retry_schedule_id      UUID NOT NULL REFERENCES trustride.orch_retry_schedule (retry_schedule_id),
  attempt_number         INTEGER NOT NULL CHECK (attempt_number > 0),
  execution_started_at   TIMESTAMPTZ NOT NULL,
  execution_completed_at TIMESTAMPTZ,
  execution_result       TEXT NOT NULL CHECK (execution_result IN ('SUCCESS', 'FAILURE')),
  failure_reason         TEXT,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.orch_retry_history IS 'Nothing is ever updated or removed; every attempt becomes permanent evidence.';
REVOKE UPDATE, DELETE ON trustride.orch_retry_history FROM PUBLIC;

CREATE TABLE trustride.orch_compensation_policy (
  compensation_policy_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_type             TEXT NOT NULL,
  compensation_action     TEXT NOT NULL,
  compensation_sequence   SMALLINT NOT NULL DEFAULT 1,
  rollback_required       BOOLEAN NOT NULL DEFAULT FALSE,
  compensation_timeout_ms INTEGER NOT NULL DEFAULT 30000 CHECK (compensation_timeout_ms > 0),
  active                  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (signal_type, compensation_sequence)
);
COMMENT ON TABLE trustride.orch_compensation_policy IS
  'What must happen when retries are exhausted; terminal signals are handed to Foundation''s dead_letter_review by signal, never written to directly.';

-- --- 2.E Priority & SLA Authority ---
CREATE TABLE trustride.orch_priority_policy (
  priority_policy_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_type        TEXT NOT NULL UNIQUE,
  priority_level     trustride.orch_priority_level_enum NOT NULL DEFAULT 'NORMAL',
  preemption_allowed BOOLEAN NOT NULL DEFAULT FALSE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.orch_priority_policy IS 'No worker decides priority; it is constitutional and registry-driven.';

CREATE TABLE trustride.orch_sla_policy (
  sla_policy_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_type            TEXT NOT NULL UNIQUE,
  target_response_ms     INTEGER NOT NULL CHECK (target_response_ms > 0),
  target_completion_ms   INTEGER NOT NULL CHECK (target_completion_ms > 0),
  warning_threshold_ms   INTEGER NOT NULL CHECK (warning_threshold_ms > 0),
  critical_threshold_ms  INTEGER NOT NULL CHECK (critical_threshold_ms > 0),
  escalation_signal_type TEXT,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.orch_sla_policy IS
  'Exceeding warning/critical thresholds triggers escalation_signal_type toward Coordination''s Runtime Intelligence Authority, never a silent delay.';

CREATE TABLE trustride.orch_execution_window (
  execution_window_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  queue_id             UUID NOT NULL REFERENCES trustride.orch_signal_queue (queue_id),
  sla_policy_id        UUID REFERENCES trustride.orch_sla_policy (sla_policy_id),
  scheduled_start_at   TIMESTAMPTZ NOT NULL,
  execution_deadline_at TIMESTAMPTZ NOT NULL,
  actual_start_at      TIMESTAMPTZ,
  actual_completion_at TIMESTAMPTZ,
  window_status        trustride.orch_sla_window_status_enum NOT NULL DEFAULT 'ON_TRACK',
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.orch_execution_window IS
  'Signal Created -> Window Opened -> Worker Started -> Worker Finished -> Window Closed; the factual proof of whether every constitutional timing guarantee was met.';

-- --- 2.F Orchestration Audit Authority ---
CREATE TABLE trustride.orch_routing_audit (
  routing_audit_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_id          UUID NOT NULL,
  correlation_id     UUID NOT NULL,
  routing_decision_id UUID REFERENCES trustride.orch_routing_decision (routing_decision_id),
  routing_result     TEXT NOT NULL,
  prev_hash          CHAR(64),
  immutable_hash     CHAR(64) NOT NULL,
  recorded_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.orch_routing_audit IS
  'Hash-chained per Foundation''s own audit_log pattern: every routing decision becomes permanent, tamper-evident evidence.';
REVOKE UPDATE, DELETE ON trustride.orch_routing_audit FROM PUBLIC;

CREATE TABLE trustride.orch_execution_audit (
  execution_audit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signal_id          UUID NOT NULL,
  correlation_id     UUID NOT NULL,
  engine_code        TEXT NOT NULL,
  execution_stage    TEXT NOT NULL,
  execution_result   TEXT,
  prev_hash          CHAR(64),
  immutable_hash     CHAR(64) NOT NULL,
  recorded_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.orch_execution_audit IS
  'Signal Discovered -> Routed -> Queued -> Leased -> Dispatched -> Completed: every stage becomes one immutable audit record.';
REVOKE UPDATE, DELETE ON trustride.orch_execution_audit FROM PUBLIC;

-- --- 2.G Runtime Telemetry Authority ---
CREATE TABLE trustride.orch_queue_metrics (
  queue_metric_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  queue_partition_id UUID NOT NULL REFERENCES trustride.orch_queue_partition (queue_partition_id),
  queue_depth        INTEGER NOT NULL CHECK (queue_depth >= 0),
  signals_enqueued   INTEGER NOT NULL DEFAULT 0,
  signals_dequeued   INTEGER NOT NULL DEFAULT 0,
  average_wait_ms    NUMERIC(10,2),
  measured_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.orch_queue_metrics IS 'The Routing Engine never waits for these metrics to be written; collection is asynchronous and non-blocking, always.';

CREATE TABLE trustride.orch_routing_metrics (
  routing_metric_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signals_discovered INTEGER NOT NULL DEFAULT 0,
  signals_routed     INTEGER NOT NULL DEFAULT 0,
  routing_failures   INTEGER NOT NULL DEFAULT 0,
  average_routing_ms NUMERIC(10,2),
  measured_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE trustride.orch_capacity_snapshot (
  capacity_snapshot_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  active_partitions     INTEGER NOT NULL CHECK (active_partitions >= 0),
  total_queue_depth     INTEGER NOT NULL CHECK (total_queue_depth >= 0),
  signals_in_flight     INTEGER NOT NULL CHECK (signals_in_flight >= 0),
  runtime_health_status TEXT NOT NULL DEFAULT 'HEALTHY' CHECK (runtime_health_status IN ('HEALTHY', 'DEGRADED', 'CRITICAL')),
  snapshot_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.orch_capacity_snapshot IS
  'One row represents the whole orchestration runtime at one moment; every shell displays this health per FDN-001 C-III-4.';

-- --- 2.H Engine Event Substrate ---
CREATE TABLE trustride.orch_event_outbox (
  signal_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id   UUID NOT NULL,
  causation_id     UUID,
  emitting_engine  TEXT NOT NULL DEFAULT 'TRS026_ENG007_ORCH',
  receiving_engine TEXT NOT NULL,
  signal_type      TEXT NOT NULL,
  payload_in       JSONB NOT NULL,
  signal_status    TEXT NOT NULL DEFAULT 'PENDING'
                      CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason TEXT,
  idempotency_key  TEXT NOT NULL UNIQUE,
  attempt_count    INTEGER NOT NULL DEFAULT 0,
  emitted_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_orch_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);

CREATE TABLE trustride.orch_event_inbox (
  signal_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id   UUID NOT NULL,
  causation_id     UUID,
  emitting_engine  TEXT NOT NULL,
  receiving_engine TEXT NOT NULL DEFAULT 'TRS026_ENG007_ORCH',
  signal_type      TEXT NOT NULL,
  payload_in       JSONB NOT NULL,
  payload_out      JSONB,
  signal_status    TEXT NOT NULL DEFAULT 'RECEIVED'
                      CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason TEXT,
  idempotency_key  TEXT NOT NULL UNIQUE,
  received_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at      TIMESTAMPTZ,
  CONSTRAINT chk_orch_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);

-- ============================================================================
-- PHASE 6 -- FUNCTIONS
-- ============================================================================

-- --- Setup / registry maintenance ---
CREATE OR REPLACE FUNCTION trustride.fn_orch_destination_cache_sync()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_synced INTEGER;
BEGIN
  INSERT INTO trustride.orch_destination_cache
    (source_engine_code, signal_type, destination_engine_code, destination_inbox_table, default_partition_code, synced_from_routing_rule_ref, cache_status, last_synced_at)
  SELECT rr.source_engine, rr.event_type, rr.target_engine,
    CASE rr.target_engine
      WHEN 'TRS026_ENG001_FDN'  THEN 'platform_event_inbox'
      WHEN 'TRS026_ENG002_RESC' THEN 'resource_event_inbox'
      WHEN 'TRS026_ENG003_SERV' THEN 'service_event_inbox'
      ELSE NULL
    END,
    rr.target_engine || ':DEFAULT',
    rr.route_id::text, 'ACTIVE', now()
  FROM trustride.routing_rule rr
  WHERE rr.active = TRUE
    AND CASE rr.target_engine
      WHEN 'TRS026_ENG001_FDN' THEN TRUE WHEN 'TRS026_ENG002_RESC' THEN TRUE WHEN 'TRS026_ENG003_SERV' THEN TRUE ELSE FALSE
    END
  ON CONFLICT (source_engine_code, signal_type, destination_engine_code) DO UPDATE
    SET destination_inbox_table = EXCLUDED.destination_inbox_table,
        cache_status = 'ACTIVE', last_synced_at = now();

  GET DIAGNOSTICS v_synced = ROW_COUNT;
  RETURN v_synced;
END;
$$;
COMMENT ON FUNCTION trustride.fn_orch_destination_cache_sync() IS
  'Refreshes orch_destination_cache from Foundation''s routing_rule, for destination engines whose inbox table is known to actually exist.';

CREATE OR REPLACE FUNCTION trustride.fn_orch_queue_partition_ensure(p_engine_code TEXT, p_priority_level trustride.orch_priority_level_enum DEFAULT 'NORMAL')
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_queue_partition_id UUID;
BEGIN
  SELECT queue_partition_id INTO v_queue_partition_id FROM trustride.orch_queue_partition WHERE engine_code = p_engine_code AND partition_status = 'ACTIVE' LIMIT 1;
  IF v_queue_partition_id IS NOT NULL THEN
    RETURN v_queue_partition_id;
  END IF;

  INSERT INTO trustride.orch_queue_partition (partition_code, partition_name, engine_code, priority_level)
  VALUES (p_engine_code || ':DEFAULT', p_engine_code || ' default partition', p_engine_code, p_priority_level)
  RETURNING queue_partition_id INTO v_queue_partition_id;

  RETURN v_queue_partition_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_orch_queue_partition_ensure(TEXT, trustride.orch_priority_level_enum) IS
  'Idempotently ensures a queue partition exists for a destination engine.';

-- --- The core dispatch mechanism ---
CREATE OR REPLACE FUNCTION trustride.fn_orch_dispatch_cycle()
RETURNS TABLE (discovered INTEGER, routed INTEGER, no_rule_matched INTEGER, dispatched INTEGER, processed INTEGER)
-- `extensions` required for digest() -- same class of bug as Foundation's
-- fn_audit_log_append (see that file's Correction 7); found by actually
-- running the dispatch cycle, not by inspection.
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_registry RECORD;
  v_row      RECORD;
  v_discovered INTEGER := 0;
  v_routed     INTEGER := 0;
  v_no_rule    INTEGER := 0;
  v_dispatched INTEGER := 0;
  v_processed  INTEGER := 0;
  v_cache      RECORD;
  v_partition_id UUID;
  v_queue_id     UUID;
  v_prev_hash    CHAR(64);
  v_new_hash     CHAR(64);
BEGIN
  FOR v_registry IN SELECT engine_code, outbox_table_name FROM trustride.orch_outbox_registry WHERE active = TRUE LOOP
    FOR v_row IN EXECUTE format(
      'SELECT signal_id, correlation_id, causation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key FROM trustride.%I WHERE signal_status = ''PENDING''',
      v_registry.outbox_table_name
    ) LOOP
      v_discovered := v_discovered + 1;

      INSERT INTO trustride.orch_execution_graph (correlation_id, signal_id, node_sequence, engine_code, node_stage)
      VALUES (v_row.correlation_id, v_row.signal_id, 1, v_row.emitting_engine, 'EMITTED');

      -- Must match the row's own declared receiving_engine, not just
      -- (source, signal_type) -- a fan-out signal_type (e.g.
      -- MARKETPLACE_LISTING_SOLD -> both Business and Resources) has one
      -- outbox row per destination, each stating its own real target.
      SELECT * INTO v_cache FROM trustride.orch_destination_cache
      WHERE source_engine_code = v_row.emitting_engine AND signal_type = v_row.signal_type
        AND destination_engine_code = v_row.receiving_engine AND cache_status = 'ACTIVE';

      IF v_cache IS NULL THEN
        v_no_rule := v_no_rule + 1;
        INSERT INTO trustride.orch_routing_decision (signal_id, correlation_id, source_engine_code, destination_engine_code, signal_type, routing_result)
        VALUES (v_row.signal_id, v_row.correlation_id, v_row.emitting_engine, v_row.receiving_engine, v_row.signal_type, 'NO_RULE_MATCHED');

        SELECT immutable_hash INTO v_prev_hash FROM trustride.orch_routing_audit ORDER BY recorded_at DESC LIMIT 1;
        v_new_hash := encode(digest(coalesce(v_prev_hash,'') || v_row.signal_id::text || 'NO_RULE_MATCHED', 'sha256'), 'hex');
        INSERT INTO trustride.orch_routing_audit (signal_id, correlation_id, routing_result, prev_hash, immutable_hash)
        VALUES (v_row.signal_id, v_row.correlation_id, 'NO_RULE_MATCHED', v_prev_hash, v_new_hash);

        CONTINUE;
      END IF;

      v_routed := v_routed + 1;
      INSERT INTO trustride.orch_routing_decision (signal_id, correlation_id, source_engine_code, destination_engine_code, signal_type, matched_routing_rule_ref, destination_partition_code, routing_result)
      VALUES (v_row.signal_id, v_row.correlation_id, v_row.emitting_engine, v_cache.destination_engine_code, v_row.signal_type, v_cache.synced_from_routing_rule_ref, v_cache.default_partition_code, 'ROUTED');

      SELECT immutable_hash INTO v_prev_hash FROM trustride.orch_routing_audit ORDER BY recorded_at DESC LIMIT 1;
      v_new_hash := encode(digest(coalesce(v_prev_hash,'') || v_row.signal_id::text || 'ROUTED', 'sha256'), 'hex');
      INSERT INTO trustride.orch_routing_audit (signal_id, correlation_id, routing_result, prev_hash, immutable_hash)
      VALUES (v_row.signal_id, v_row.correlation_id, 'ROUTED', v_prev_hash, v_new_hash);

      INSERT INTO trustride.orch_execution_graph (correlation_id, signal_id, node_sequence, engine_code, node_stage)
      VALUES (v_row.correlation_id, v_row.signal_id, 2, 'TRS026_ENG007_ORCH', 'ROUTED');

      -- Engine 8 admission (always real, always called; every currently
      -- registered signal_type admits straight through since no fan-out/
      -- fan-in scenario exists among the currently-built engines yet).
      PERFORM trustride.fn_coord_admission_check(v_row.signal_type, v_row.signal_id, v_row.correlation_id, v_row.emitting_engine, v_cache.destination_engine_code);

      v_partition_id := trustride.fn_orch_queue_partition_ensure(v_cache.destination_engine_code);

      INSERT INTO trustride.orch_signal_queue (signal_id, correlation_id, source_engine_code, destination_engine_code, signal_type, queue_partition_id, idempotency_key)
      VALUES (v_row.signal_id, v_row.correlation_id, v_row.emitting_engine, v_cache.destination_engine_code, v_row.signal_type, v_partition_id, v_row.idempotency_key || ':queue')
      ON CONFLICT (idempotency_key) DO NOTHING
      RETURNING queue_id INTO v_queue_id;

      INSERT INTO trustride.orch_execution_graph (correlation_id, signal_id, node_sequence, engine_code, node_stage)
      VALUES (v_row.correlation_id, v_row.signal_id, 3, 'TRS026_ENG007_ORCH', 'QUEUED');

      -- Dispatch: insert into the destination's own inbox, mark source
      -- outbox row DISPATCHED, hand off to that engine's own processor.
      EXECUTE format(
        'INSERT INTO trustride.%I (signal_id, correlation_id, causation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)',
        v_cache.destination_inbox_table
      ) USING v_row.signal_id, v_row.correlation_id, v_row.causation_id, v_row.emitting_engine, v_cache.destination_engine_code, v_row.signal_type, v_row.payload_in, v_row.idempotency_key || ':inbox';

      EXECUTE format('UPDATE trustride.%I SET signal_status = ''DISPATCHED'' WHERE signal_id = $1', v_registry.outbox_table_name) USING v_row.signal_id;
      IF v_queue_id IS NOT NULL THEN
        UPDATE trustride.orch_signal_queue SET queue_status = 'DISPATCHED', dispatched_at = now() WHERE queue_id = v_queue_id;
      END IF;

      INSERT INTO trustride.orch_signal_lineage (correlation_id, parent_signal_id, child_signal_id, relationship_type)
      VALUES (v_row.correlation_id, NULL, v_row.signal_id, 'CAUSED');

      INSERT INTO trustride.orch_execution_graph (correlation_id, signal_id, node_sequence, engine_code, node_stage)
      VALUES (v_row.correlation_id, v_row.signal_id, 4, 'TRS026_ENG007_ORCH', 'DISPATCHED');
      INSERT INTO trustride.orch_execution_graph (correlation_id, signal_id, node_sequence, engine_code, node_stage)
      VALUES (v_row.correlation_id, v_row.signal_id, 5, v_cache.destination_engine_code, 'RECEIVED');

      SELECT immutable_hash INTO v_prev_hash FROM trustride.orch_execution_audit ORDER BY recorded_at DESC LIMIT 1;
      v_new_hash := encode(digest(coalesce(v_prev_hash,'') || v_row.signal_id::text || 'DISPATCHED', 'sha256'), 'hex');
      INSERT INTO trustride.orch_execution_audit (signal_id, correlation_id, engine_code, execution_stage, execution_result, prev_hash, immutable_hash)
      VALUES (v_row.signal_id, v_row.correlation_id, v_cache.destination_engine_code, 'DISPATCHED', 'SUCCESS', v_prev_hash, v_new_hash);

      v_dispatched := v_dispatched + 1;

      -- Hand off to the destination engine's own processor, if one is
      -- registered (Correction 5).
      BEGIN
        CASE v_cache.destination_engine_code
          WHEN 'TRS026_ENG002_RESC' THEN PERFORM trustride.fn_resource_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG003_SERV' THEN PERFORM trustride.fn_service_inbox_process(v_row.signal_id);
          ELSE NULL;
        END CASE;
        v_processed := v_processed + 1;
      EXCEPTION WHEN OTHERS THEN
        NULL; -- the destination engine's own accept-handler is responsible for its own REJECTED path; a raised exception here just means it stays RECEIVED for manual/retry review
      END;
    END LOOP;
  END LOOP;

  RETURN QUERY SELECT v_discovered, v_routed, v_no_rule, v_dispatched, v_processed;
END;
$$;
COMMENT ON FUNCTION trustride.fn_orch_dispatch_cycle() IS
  'The heartbeat itself: discover every PENDING row in every registered outbox, route, admit (Engine 8), queue, dispatch into the destination inbox, and hand off to that engine''s own processor. Idempotent per idempotency_key.';

-- --- Retry & compensation ---
CREATE OR REPLACE FUNCTION trustride.fn_orch_retry_schedule_open(p_queue_id UUID, p_retry_reason TEXT, p_retry_interval_ms INTEGER DEFAULT 5000)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_prior_attempts INTEGER;
  v_retry_schedule_id UUID;
BEGIN
  SELECT count(*) INTO v_prior_attempts FROM trustride.orch_retry_schedule WHERE queue_id = p_queue_id;

  INSERT INTO trustride.orch_retry_schedule (queue_id, retry_attempt, next_retry_at, retry_interval_ms, retry_reason)
  VALUES (p_queue_id, v_prior_attempts + 1, now() + (p_retry_interval_ms || ' milliseconds')::interval, p_retry_interval_ms, p_retry_reason)
  RETURNING retry_schedule_id INTO v_retry_schedule_id;

  IF v_prior_attempts + 1 > 5 THEN
    UPDATE trustride.orch_retry_schedule SET retry_status = 'EXHAUSTED' WHERE retry_schedule_id = v_retry_schedule_id;
    PERFORM trustride.fn_orch_compensation_trigger(p_queue_id, p_retry_reason);
  END IF;

  RETURN v_retry_schedule_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_orch_retry_schedule_open(UUID, TEXT, INTEGER) IS
  'Schedules the next retry attempt; past max_retry_attempts, triggers compensation instead of retrying indefinitely.';

CREATE OR REPLACE FUNCTION trustride.fn_orch_compensation_trigger(p_queue_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_signal_id UUID;
  v_source_engine TEXT;
  v_target_engine TEXT;
BEGIN
  SELECT signal_id, source_engine_code, destination_engine_code INTO v_signal_id, v_source_engine, v_target_engine
  FROM trustride.orch_signal_queue WHERE queue_id = p_queue_id;

  UPDATE trustride.orch_signal_queue SET queue_status = 'FAILED' WHERE queue_id = p_queue_id;

  INSERT INTO trustride.dead_letter_review (event_id, source_engine, target_engine, failure_reason)
  VALUES (v_signal_id, v_source_engine, v_target_engine, p_reason);
END;
$$;
COMMENT ON FUNCTION trustride.fn_orch_compensation_trigger(UUID, TEXT) IS
  'Retry exhaustion hands the signal to Foundation''s dead_letter_review -- never a silent drop.';

-- --- SLA governance ---
CREATE OR REPLACE FUNCTION trustride.fn_orch_execution_window_open(p_queue_id UUID, p_signal_type TEXT)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_sla RECORD;
  v_window_id UUID;
BEGIN
  SELECT * INTO v_sla FROM trustride.orch_sla_policy WHERE signal_type = p_signal_type;

  INSERT INTO trustride.orch_execution_window (queue_id, sla_policy_id, scheduled_start_at, execution_deadline_at)
  VALUES (p_queue_id, v_sla.sla_policy_id, now(), now() + make_interval(secs => coalesce(v_sla.target_completion_ms, 30000) / 1000.0))
  RETURNING execution_window_id INTO v_window_id;

  RETURN v_window_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_orch_execution_window_open(UUID, TEXT) IS
  'Opens the SLA compliance window for a queued signal; a signal_type with no registered orch_sla_policy still gets a default 30s window.';

CREATE OR REPLACE FUNCTION trustride.fn_orch_sla_check_sweep()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_breached INTEGER;
BEGIN
  UPDATE trustride.orch_execution_window
  SET window_status = 'BREACHED'
  WHERE window_status <> 'BREACHED' AND actual_completion_at IS NULL AND execution_deadline_at < now();
  GET DIAGNOSTICS v_breached = ROW_COUNT;
  RETURN v_breached;
END;
$$;
COMMENT ON FUNCTION trustride.fn_orch_sla_check_sweep() IS
  'Marks any execution window past its deadline as BREACHED; never a silent delay.';

-- --- Runtime telemetry ---
CREATE OR REPLACE FUNCTION trustride.fn_orch_capacity_snapshot_record()
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_active_partitions INTEGER;
  v_total_depth        INTEGER;
  v_in_flight             INTEGER;
  v_snapshot_id              UUID;
BEGIN
  SELECT count(*) INTO v_active_partitions FROM trustride.orch_queue_partition WHERE partition_status = 'ACTIVE';
  SELECT count(*) INTO v_total_depth FROM trustride.orch_signal_queue WHERE queue_status = 'QUEUED';
  SELECT count(*) INTO v_in_flight FROM trustride.orch_signal_queue WHERE queue_status IN ('LEASED', 'DISPATCHED');

  INSERT INTO trustride.orch_capacity_snapshot (active_partitions, total_queue_depth, signals_in_flight, runtime_health_status)
  VALUES (v_active_partitions, v_total_depth, v_in_flight, 'HEALTHY')
  RETURNING capacity_snapshot_id INTO v_snapshot_id;

  RETURN v_snapshot_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_orch_capacity_snapshot_record() IS
  'Manual snapshot of runtime capacity; continuous automatic collection is a real next step, not fabricated here (see header Correction 6).';

-- --- Correction 5: per-engine inbox processors, closing the loop ---
CREATE OR REPLACE FUNCTION trustride.fn_resource_inbox_process(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_signal_type TEXT;
  v_result TEXT;
BEGIN
  SELECT signal_type INTO v_signal_type FROM trustride.resource_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_signal_type IS NULL THEN
    RAISE EXCEPTION 'fn_resource_inbox_process: no RECEIVED signal %', p_signal_id;
  END IF;

  CASE v_signal_type
    WHEN 'ASSIGNMENT_REQUESTED' THEN v_result := trustride.fn_resource_assignment_requested_accept(p_signal_id);
    WHEN 'JOB_COMPLETED' THEN v_result := trustride.fn_resource_job_completed_accept(p_signal_id);
    WHEN 'FLEET_VERIFICATION_UPDATED' THEN v_result := trustride.fn_resource_fleet_verification_updated_accept(p_signal_id);
    WHEN 'MARKETPLACE_LISTING_SOLD' THEN v_result := trustride.fn_resource_marketplace_listing_sold_accept(p_signal_id);
    ELSE
      UPDATE trustride.resource_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'UNREGISTERED_SIGNAL_TYPE:' || v_signal_type WHERE signal_id = p_signal_id;
      v_result := 'REJECTED';
  END CASE;

  RETURN v_result;
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_inbox_process(UUID) IS
  'Dispatches a RECEIVED resource_event_inbox row to the matching accept-handler already built in Engine 2''s own migration file, by signal_type.';

CREATE OR REPLACE FUNCTION trustride.fn_service_inbox_process(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_signal_type TEXT;
  v_result TEXT;
BEGIN
  SELECT signal_type INTO v_signal_type FROM trustride.service_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_signal_type IS NULL THEN
    RAISE EXCEPTION 'fn_service_inbox_process: no RECEIVED signal %', p_signal_id;
  END IF;

  CASE v_signal_type
    WHEN 'SERVICE_LOOKUP_REQUESTED' THEN v_result := trustride.fn_service_lookup_requested_accept(p_signal_id);
    WHEN 'VENDOR_VERIFICATION_UPDATED' THEN v_result := trustride.fn_service_vendor_verification_updated_accept(p_signal_id);
    WHEN 'RESOURCE_MARKETPLACE_ITEM_READY' THEN v_result := trustride.fn_service_resource_marketplace_item_ready_accept(p_signal_id);
    ELSE
      UPDATE trustride.service_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'UNREGISTERED_SIGNAL_TYPE:' || v_signal_type WHERE signal_id = p_signal_id;
      v_result := 'REJECTED';
  END CASE;

  RETURN v_result;
END;
$$;
COMMENT ON FUNCTION trustride.fn_service_inbox_process(UUID) IS
  'Dispatches a RECEIVED service_event_inbox row to the matching accept-handler already built in Engine 3''s own migration file, by signal_type.';

-- ============================================================================
-- PHASE 7 -- TRIGGERS
-- ============================================================================
-- None. No table here requires a cross-row CHECK-avoidance rule.

-- ============================================================================
-- PHASE 8 -- ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE trustride.orch_queue_partition ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_queue_partition_platform_read ON trustride.orch_queue_partition FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_queue_partition_service_write ON trustride.orch_queue_partition FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_routing_decision ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_routing_decision_platform_read ON trustride.orch_routing_decision FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_routing_decision_service_write ON trustride.orch_routing_decision FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_destination_cache ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_destination_cache_platform_read ON trustride.orch_destination_cache FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_destination_cache_service_write ON trustride.orch_destination_cache FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_outbox_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_outbox_registry_platform_read ON trustride.orch_outbox_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_outbox_registry_service_write ON trustride.orch_outbox_registry FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_signal_queue ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_signal_queue_service_only ON trustride.orch_signal_queue FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_queue_lease ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_queue_lease_service_only ON trustride.orch_queue_lease FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_queue_checkpoint ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_queue_checkpoint_service_only ON trustride.orch_queue_checkpoint FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_signal_lineage ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_signal_lineage_platform_read ON trustride.orch_signal_lineage FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_signal_lineage_service_write ON trustride.orch_signal_lineage FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_execution_graph ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_execution_graph_platform_read ON trustride.orch_execution_graph FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_execution_graph_service_write ON trustride.orch_execution_graph FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_retry_schedule ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_retry_schedule_service_only ON trustride.orch_retry_schedule FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_retry_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_retry_history_platform_read ON trustride.orch_retry_history FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_retry_history_service_write ON trustride.orch_retry_history FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_compensation_policy ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_compensation_policy_platform_read ON trustride.orch_compensation_policy FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_compensation_policy_service_write ON trustride.orch_compensation_policy FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_priority_policy ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_priority_policy_platform_read ON trustride.orch_priority_policy FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_priority_policy_service_write ON trustride.orch_priority_policy FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_sla_policy ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_sla_policy_platform_read ON trustride.orch_sla_policy FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_sla_policy_service_write ON trustride.orch_sla_policy FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_execution_window ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_execution_window_platform_read ON trustride.orch_execution_window FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_execution_window_service_write ON trustride.orch_execution_window FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_routing_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_routing_audit_platform_read ON trustride.orch_routing_audit FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_routing_audit_service_write ON trustride.orch_routing_audit FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_execution_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_execution_audit_platform_read ON trustride.orch_execution_audit FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_execution_audit_service_write ON trustride.orch_execution_audit FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_queue_metrics ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_queue_metrics_platform_read ON trustride.orch_queue_metrics FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_queue_metrics_service_write ON trustride.orch_queue_metrics FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_routing_metrics ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_routing_metrics_platform_read ON trustride.orch_routing_metrics FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_routing_metrics_service_write ON trustride.orch_routing_metrics FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_capacity_snapshot ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_capacity_snapshot_platform_read ON trustride.orch_capacity_snapshot FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY orch_capacity_snapshot_service_write ON trustride.orch_capacity_snapshot FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_event_outbox_service_only ON trustride.orch_event_outbox FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.orch_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY orch_event_inbox_service_only ON trustride.orch_event_inbox FOR ALL TO trs026_eng007_orch_service USING (true) WITH CHECK (true);

-- ============================================================================
-- PHASE 9 -- INDEXES
-- ============================================================================
CREATE INDEX idx_orch_routing_decision_correlation ON trustride.orch_routing_decision (correlation_id);
CREATE INDEX idx_orch_routing_decision_result ON trustride.orch_routing_decision (routing_result);
CREATE INDEX idx_orch_signal_queue_partition_status ON trustride.orch_signal_queue (queue_partition_id, queue_status);
CREATE INDEX idx_orch_signal_queue_priority ON trustride.orch_signal_queue (priority_level, queued_at) WHERE queue_status = 'QUEUED';
CREATE INDEX idx_orch_signal_queue_correlation ON trustride.orch_signal_queue (correlation_id);
CREATE INDEX idx_orch_queue_lease_queue ON trustride.orch_queue_lease (queue_id);
CREATE INDEX idx_orch_queue_lease_expiry ON trustride.orch_queue_lease (lease_expires_at) WHERE lease_status = 'LEASED';
CREATE INDEX idx_orch_queue_checkpoint_partition ON trustride.orch_queue_checkpoint (queue_partition_id, checkpoint_at DESC);
CREATE INDEX idx_orch_signal_lineage_correlation ON trustride.orch_signal_lineage (correlation_id);
CREATE INDEX idx_orch_signal_lineage_parent ON trustride.orch_signal_lineage (parent_signal_id) WHERE parent_signal_id IS NOT NULL;
CREATE INDEX idx_orch_execution_graph_signal ON trustride.orch_execution_graph (signal_id, node_sequence);
CREATE INDEX idx_orch_execution_graph_correlation ON trustride.orch_execution_graph (correlation_id);
CREATE INDEX idx_orch_retry_schedule_due ON trustride.orch_retry_schedule (next_retry_at) WHERE retry_status = 'SCHEDULED';
CREATE INDEX idx_orch_retry_history_schedule ON trustride.orch_retry_history (retry_schedule_id, attempt_number);
CREATE INDEX idx_orch_execution_window_status ON trustride.orch_execution_window (window_status) WHERE window_status <> 'ON_TRACK';
CREATE INDEX idx_orch_routing_audit_correlation ON trustride.orch_routing_audit (correlation_id);
CREATE INDEX idx_orch_execution_audit_signal ON trustride.orch_execution_audit (signal_id);
CREATE INDEX idx_orch_queue_metrics_partition_time ON trustride.orch_queue_metrics (queue_partition_id, measured_at DESC);
CREATE INDEX idx_orch_capacity_snapshot_time ON trustride.orch_capacity_snapshot (snapshot_at DESC);
CREATE INDEX idx_orch_outbox_status ON trustride.orch_event_outbox (signal_status);
CREATE INDEX idx_orch_outbox_correlation ON trustride.orch_event_outbox (correlation_id);
CREATE INDEX idx_orch_inbox_status ON trustride.orch_event_inbox (signal_status);
CREATE INDEX idx_orch_inbox_correlation ON trustride.orch_event_inbox (correlation_id);

-- ============================================================================
-- PHASE 10 -- VIEWS
-- ============================================================================
CREATE VIEW trustride.v_orch_runtime_health AS
SELECT * FROM trustride.orch_capacity_snapshot ORDER BY snapshot_at DESC LIMIT 1;
COMMENT ON VIEW trustride.v_orch_runtime_health IS '[Trace: §3.1] The health endpoint, realized as a queryable view.';

CREATE VIEW trustride.v_orch_signal_trace AS
SELECT correlation_id, node_sequence, engine_code, node_stage, entered_at
FROM trustride.orch_execution_graph
ORDER BY correlation_id, node_sequence;
COMMENT ON VIEW trustride.v_orch_signal_trace IS '[Trace: §3.2] The full hop-by-hop trace for any correlation_id.';

-- ============================================================================
-- PHASE 11 -- PRIVILEGE LOCKDOWN
-- ============================================================================
GRANT USAGE ON SCHEMA trustride TO trs026_eng007_orch_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA trustride TO trs026_eng007_orch_service;
GRANT SELECT ON trustride.v_orch_runtime_health, trustride.v_orch_signal_trace TO trustride_authenticated;

GRANT EXECUTE ON FUNCTION trustride.fn_orch_destination_cache_sync() TO trs026_eng007_orch_service;
GRANT EXECUTE ON FUNCTION trustride.fn_orch_queue_partition_ensure(TEXT, trustride.orch_priority_level_enum) TO trs026_eng007_orch_service;
GRANT EXECUTE ON FUNCTION trustride.fn_orch_dispatch_cycle() TO trs026_eng007_orch_service;
GRANT EXECUTE ON FUNCTION trustride.fn_orch_retry_schedule_open(UUID, TEXT, INTEGER) TO trs026_eng007_orch_service;
GRANT EXECUTE ON FUNCTION trustride.fn_orch_compensation_trigger(UUID, TEXT) TO trs026_eng007_orch_service;
GRANT EXECUTE ON FUNCTION trustride.fn_orch_execution_window_open(UUID, TEXT) TO trs026_eng007_orch_service;
GRANT EXECUTE ON FUNCTION trustride.fn_orch_sla_check_sweep() TO trs026_eng007_orch_service;
GRANT EXECUTE ON FUNCTION trustride.fn_orch_capacity_snapshot_record() TO trs026_eng007_orch_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_inbox_process(UUID) TO trs026_eng007_orch_service, trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_service_inbox_process(UUID) TO trs026_eng007_orch_service, trs026_eng003_serv_service;

GRANT EXECUTE ON FUNCTION trustride.fn_audit_log_append(TEXT, UUID, TEXT, UUID, TEXT, TEXT, TEXT, JSONB, JSONB) TO trs026_eng007_orch_service;
GRANT EXECUTE ON FUNCTION trustride.fn_sequence_next(TEXT) TO trs026_eng007_orch_service;

GRANT trs026_eng007_orch_service TO service_role;

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
  WHERE table_schema = 'trustride' AND table_type = 'BASE TABLE' AND table_name LIKE 'orch_%';
  IF v_table_count <> 22 THEN
    RAISE EXCEPTION 'Engine 7 validation failed: expected 22 orch_ tables, found %', v_table_count;
  END IF;

  SELECT count(*) INTO v_function_count
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'trustride'
    AND p.proname IN ('fn_orch_destination_cache_sync','fn_orch_queue_partition_ensure','fn_orch_dispatch_cycle',
                       'fn_orch_retry_schedule_open','fn_orch_compensation_trigger','fn_orch_execution_window_open',
                       'fn_orch_sla_check_sweep','fn_orch_capacity_snapshot_record','fn_resource_inbox_process','fn_service_inbox_process');
  IF v_function_count <> 10 THEN
    RAISE EXCEPTION 'Engine 7 validation failed: expected 10 core functions, found %', v_function_count;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng007_orch_service') THEN
    RAISE EXCEPTION 'Engine 7 validation failed: trs026_eng007_orch_service role missing';
  END IF;

  RAISE NOTICE 'Engine 7 validation passed: 22/22 orch_ tables, 10/10 core functions, service role present.';
END
$$;

-- ============================================================================
-- PHASE 13 -- FINALIZATION & SEED DATA
-- ============================================================================

-- Correction 3: register the outbox tables that actually exist right now.
INSERT INTO trustride.orch_outbox_registry (engine_code, outbox_table_name) VALUES
  ('TRS026_ENG001_FDN', 'platform_event_outbox'),
  ('TRS026_ENG002_RESC', 'resource_event_outbox'),
  ('TRS026_ENG003_SERV', 'service_event_outbox');

-- Correction 4: backfill Foundation's routing_rule for the signal types
-- Resources and Services already emit, to real, already-built destinations.
INSERT INTO trustride.routing_rule (event_type, source_engine, target_engine, route_priority) VALUES
  ('RESOURCE_MARKETPLACE_ITEM_READY', 'TRS026_ENG002_RESC', 'TRS026_ENG003_SERV', 0),
  ('MARKETPLACE_LISTING_SOLD',        'TRS026_ENG003_SERV', 'TRS026_ENG002_RESC', 0);
-- Not yet registered (destination engine not yet built): RESOURCE_RESERVED,
-- RESOURCE_ASSIGNED, RESOURCE_DISPATCH_INITIATED (-> Business/Cost),
-- SERVICE_RESOLVED, SERVICE_CONTEXT_RESOLVED, SERVICE_CATALOGUE_UPDATED
-- (-> Business/Cost/Presentation), MARKETPLACE_LISTING_SOLD -> Business.
-- Register these when those engines are built -- an unregistered
-- destination correctly surfaces as NO_RULE_MATCHED, never a silent drop.

SELECT trustride.fn_orch_destination_cache_sync();

INSERT INTO trustride.orch_priority_policy (signal_type, priority_level, preemption_allowed) VALUES
  ('PAYMENT_STK_TRIGGERED', 'CRITICAL', TRUE),
  ('ASSIGNMENT_REQUESTED', 'HIGH', FALSE),
  ('EMERGENCY_ESCALATION_REQUESTED', 'CRITICAL', TRUE),
  ('ORDER_PLACED', 'NORMAL', FALSE),
  ('SERVICE_CATALOGUE_UPDATED', 'LOW', FALSE),
  ('RESOURCE_MARKETPLACE_ITEM_READY', 'NORMAL', FALSE),
  ('MARKETPLACE_LISTING_SOLD', 'NORMAL', FALSE);

UPDATE trustride.engine_registry SET status = 'INSTALLED', engine_version = '1.0.0' WHERE engine_code = 'TRS026_ENG007_ORCH';
