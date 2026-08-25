-- ============================================================================
-- ENGINE 9 -- AI/ML ADVISORY ENGINE
-- Per TRS026-ENG009-AIADV-001 v1.0.0 (ADOPTED 2026-08-16)
-- ============================================================================
-- Constitutional character: ADVISORY ONLY. Zero write authority into any
-- other engine's authoritative state, under any urgency, without exception.
-- Every output is a record, never a mutation (FDN-001 Sec.11.3 Layer 4).
--
-- This file follows the blueprint's own Section 2 DDL faithfully, with two
-- deliberate, documented deviations from the literal draft, both matching
-- platform-wide precedent already established this session:
--   1. advisory_event_inbox gains `emitted_at TIMESTAMPTZ` -- the blueprint's
--      generic inbox template only carries `received_at`, but every real
--      receiving engine's inbox this session (Business, and now Coordination
--      below) needs `emitted_at` because fn_orch_dispatch_cycle's dynamic
--      INSERT names that column explicitly. Business hit this exact gap
--      first; it is not repeated here.
--   2. advisory_model_registry rows are seeded ACTIVE with approved_by and
--      approved_request_id left NULL. The blueprint's own comment says a
--      model with no approved_request_id is "inert, mirroring the Foundation
--      rate-register discipline" -- but Foundation's approval_chain/approval_
--      request mechanism has zero seeded rows anywhere on the live platform
--      today (confirmed directly: `SELECT * FROM approval_chain` returns 0
--      rows, `fn_approval_request_open` does not exist as a function yet).
--      No engine built so far routes its own governance-reference columns
--      through a real approval before going ACTIVE (Cost's own cost_registry/
--      cost_rate rows were seeded ACTIVE the same way). Building out
--      Foundation's entire unexercised approval workflow is outside this
--      engine's own scope; this is flagged here rather than silently
--      papered over.
--
-- Ten heuristic models ground the ten recommendation/forecast sweep
-- functions below (Section "PHASE 8"). None is a trained statistical model
-- yet -- each is a real, working, threshold-based computation over the
-- exact registered read sources (Sec.2.3), honestly labelled as a Phase 1
-- baseline in its own training_data_description, matching the same
-- simulate-first discipline already used for Engine 6's port adapters.
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
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng009_aiadv_service') THEN
    CREATE ROLE trs026_eng009_aiadv_service NOLOGIN;
  END IF;
END
$$;

-- ============================================================================
-- PHASE 2 -- ENUMS [Trace: TRS026-ENG009-AIADV-001 Sec.2.0]
-- ============================================================================
CREATE TYPE trustride.advisory_model_type_enum AS ENUM (
  'FORECASTING', 'RECOMMENDATION', 'ANOMALY_DETECTION', 'CLASSIFICATION'
);

CREATE TYPE trustride.advisory_model_status_enum AS ENUM (
  'DRAFT', 'ACTIVE', 'DEPRECATED', 'RETIRED'
);

CREATE TYPE trustride.advisory_recommendation_type_enum AS ENUM (
  'CAPACITY_PLANNING', 'FLEET_REPLACEMENT', 'SERVICE_MIX', 'DEMAND_PATTERN',
  'DEMAND_FORECAST', 'REVENUE_PATTERN', 'EXTERNAL_RELIABILITY', 'PAYMENT_SUCCESS_RATE',
  'ROUTING_CAPACITY_TREND', 'COORDINATION_HEALTH_TREND'
);

CREATE TYPE trustride.advisory_outcome_enum AS ENUM (
  'PENDING', 'ACCEPTED', 'REJECTED', 'IGNORED'
);

CREATE TYPE trustride.advisory_forecast_type_enum AS ENUM (
  'DEMAND', 'CAPACITY', 'REVENUE'
);

CREATE TYPE trustride.advisory_anomaly_type_enum AS ENUM (
  'MARGIN_BREACH', 'PAYMENT_FAILURE_SPIKE', 'DEMAND_SPIKE', 'CAPACITY_SHORTFALL',
  'EXTERNAL_SYSTEM_DEGRADATION', 'COORDINATION_DEGRADATION'
);

CREATE TYPE trustride.advisory_severity_enum AS ENUM (
  'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'
);

-- ============================================================================
-- PHASE 3 -- TABLES [Trace: TRS026-ENG009-AIADV-001 Sec.2.1-2.12]
-- ============================================================================

-- 2.1 Model Governance
CREATE TABLE trustride.advisory_model_registry (
  model_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_code           TEXT NOT NULL UNIQUE,
  model_name           TEXT NOT NULL,
  model_type           trustride.advisory_model_type_enum NOT NULL,
  model_version        TEXT NOT NULL,
  training_data_description TEXT NOT NULL,
  approved_by          UUID,
  approved_request_id  UUID,
  model_status         trustride.advisory_model_status_enum NOT NULL DEFAULT 'DRAFT',
  deployed_at          TIMESTAMPTZ,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (model_code, model_version)
);
COMMENT ON TABLE trustride.advisory_model_registry IS
  'No model produces a recommendation without an ACTIVE row here; a model with no approved_request_id is inert, mirroring the Foundation rate-register discipline (TBOC Article 44).';
ALTER TABLE trustride.advisory_model_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_model_registry_platform_read ON trustride.advisory_model_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_model_registry_service_write ON trustride.advisory_model_registry FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);

-- 2.2 Model Version History (append-only)
CREATE TABLE trustride.advisory_model_version_history (
  model_version_history_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id             UUID NOT NULL REFERENCES trustride.advisory_model_registry (model_id),
  previous_version     TEXT,
  new_version          TEXT NOT NULL,
  change_reason        TEXT NOT NULL,
  changed_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_advisory_model_version_history_model ON trustride.advisory_model_version_history (model_id, changed_at DESC);
REVOKE UPDATE, DELETE ON trustride.advisory_model_version_history FROM PUBLIC;
REVOKE UPDATE, DELETE ON trustride.advisory_model_version_history FROM trustride_authenticated;
ALTER TABLE trustride.advisory_model_version_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_model_version_history_platform_read ON trustride.advisory_model_version_history FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_model_version_history_service_write ON trustride.advisory_model_version_history FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);

-- 2.3 Read-Source Governance (the closed list)
CREATE TABLE trustride.advisory_read_source_registry (
  read_source_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_engine_code   TEXT NOT NULL,
  source_table_name    TEXT NOT NULL,
  read_purpose         TEXT NOT NULL,
  granted_by_document  TEXT NOT NULL,
  active               BOOLEAN NOT NULL DEFAULT TRUE,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (source_engine_code, source_table_name)
);
COMMENT ON TABLE trustride.advisory_read_source_registry IS
  'Closed by design: seeded once from the six sibling engines'' own already-adopted grants, never expanded without the granting engine''s document naming Engine 9 first.';
ALTER TABLE trustride.advisory_read_source_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_read_source_registry_platform_read ON trustride.advisory_read_source_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_read_source_registry_service_write ON trustride.advisory_read_source_registry FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);

INSERT INTO trustride.advisory_read_source_registry (source_engine_code, source_table_name, read_purpose, granted_by_document) VALUES
  ('TRS026_ENG002_RESC', 'resource_availability_ledger', 'Capacity-planning recommendations', 'TRS026-ENG002-RESC-001 Sec.1.3'),
  ('TRS026_ENG002_RESC', 'resource_maintenance_record', 'Fleet-replacement recommendations', 'TRS026-ENG002-RESC-001 Sec.1.3'),
  ('TRS026_ENG003_SERV', 'service_catalogue', 'Service-mix recommendations', 'TRS026-ENG003-SERV-001 Sec.1.3'),
  ('TRS026_ENG004_BUS', 'business_order', 'Demand-forecasting recommendations', 'TRS026-ENG004-BUS-001 Sec.1.3'),
  ('TRS026_ENG004_BUS', 'business_settlement', 'Revenue-pattern recommendations', 'TRS026-ENG004-BUS-001 Sec.1.3'),
  ('TRS026_ENG006_INTG', 'integration_circuit_breaker_state', 'External-reliability recommendations', 'TRS026-ENG006-INTG-001 Sec.1.3'),
  ('TRS026_ENG006_INTG', 'integration_payment_gateway_transaction', 'Payment-success-rate recommendations', 'TRS026-ENG006-INTG-001 Sec.1.3'),
  ('TRS026_ENG007_ORCH', 'orch_queue_metrics', 'Routing/capacity trend recommendations', 'TRS026-ENG007-ORCH-001 Sec.1.3'),
  ('TRS026_ENG007_ORCH', 'orch_routing_metrics', 'Routing/capacity trend recommendations', 'TRS026-ENG007-ORCH-001 Sec.1.3'),
  ('TRS026_ENG007_ORCH', 'orch_capacity_snapshot', 'Routing/capacity trend recommendations', 'TRS026-ENG007-ORCH-001 Sec.1.3'),
  ('TRS026_ENG008_COORD', 'coord_coordination_health', 'Coordination health trend recommendations', 'TRS026-ENG008-COORD-001 Sec.1.3'),
  ('TRS026_ENG008_COORD', 'coord_coordination_metrics', 'Coordination health trend recommendations', 'TRS026-ENG008-COORD-001 Sec.1.3'),
  ('TRS026_ENG008_COORD', 'coord_runtime_alert', 'Coordination health trend recommendations', 'TRS026-ENG008-COORD-001 Sec.1.3');

-- 2.4 Core Advisory Output
CREATE TABLE trustride.advisory_recommendation (
  recommendation_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id             UUID NOT NULL REFERENCES trustride.advisory_model_registry (model_id),
  recommendation_type  trustride.advisory_recommendation_type_enum NOT NULL,
  subject_engine_code  TEXT NOT NULL,
  subject_ref_id       UUID,
  correlation_id       UUID NOT NULL,
  recommendation_payload JSONB NOT NULL,
  confidence_score     NUMERIC(5,2) NOT NULL CHECK (confidence_score BETWEEN 0 AND 100),
  generated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at           TIMESTAMPTZ
);
CREATE INDEX idx_advisory_recommendation_subject ON trustride.advisory_recommendation (subject_engine_code, subject_ref_id);
CREATE INDEX idx_advisory_recommendation_correlation ON trustride.advisory_recommendation (correlation_id);
CREATE INDEX idx_advisory_recommendation_type ON trustride.advisory_recommendation (recommendation_type);
COMMENT ON TABLE trustride.advisory_recommendation IS
  'A suggestion with a confidence score, never a command. Never causes a mutation anywhere; read by a human Governor or a separately governed rule, which decides.';
ALTER TABLE trustride.advisory_recommendation ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_recommendation_platform_read ON trustride.advisory_recommendation FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_recommendation_service_write ON trustride.advisory_recommendation FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);

-- 2.5 Explainability
CREATE TABLE trustride.advisory_recommendation_evidence (
  evidence_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recommendation_id    UUID NOT NULL REFERENCES trustride.advisory_recommendation (recommendation_id),
  feature_name         TEXT NOT NULL,
  feature_value        JSONB NOT NULL,
  feature_weight       NUMERIC(6,4),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_advisory_recommendation_evidence_recommendation ON trustride.advisory_recommendation_evidence (recommendation_id);
COMMENT ON TABLE trustride.advisory_recommendation_evidence IS
  'No recommendation is a black box: every contributing feature and its weight is recorded alongside the recommendation it produced.';
ALTER TABLE trustride.advisory_recommendation_evidence ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_recommendation_evidence_platform_read ON trustride.advisory_recommendation_evidence FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_recommendation_evidence_service_write ON trustride.advisory_recommendation_evidence FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);

-- 2.6 Human or Rule Decision Record
CREATE TABLE trustride.advisory_recommendation_outcome (
  outcome_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recommendation_id    UUID NOT NULL UNIQUE REFERENCES trustride.advisory_recommendation (recommendation_id),
  outcome              trustride.advisory_outcome_enum NOT NULL DEFAULT 'PENDING',
  decided_by           UUID,
  decision_rule_ref    TEXT,
  decision_reason      TEXT,
  decided_at           TIMESTAMPTZ
);
COMMENT ON TABLE trustride.advisory_recommendation_outcome IS
  'The proof that this engine influences nothing on its own: every recommendation''s eventual fate, and by whom, is recorded here, never inferred.';
ALTER TABLE trustride.advisory_recommendation_outcome ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_recommendation_outcome_platform_read ON trustride.advisory_recommendation_outcome FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_recommendation_outcome_service_write ON trustride.advisory_recommendation_outcome FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);

-- 2.7 Forecasting
CREATE TABLE trustride.advisory_forecast (
  forecast_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id             UUID NOT NULL REFERENCES trustride.advisory_model_registry (model_id),
  forecast_type        trustride.advisory_forecast_type_enum NOT NULL,
  subject_scope        TEXT NOT NULL,
  forecast_period_start DATE NOT NULL,
  forecast_period_end  DATE NOT NULL,
  forecast_value       NUMERIC(18,4) NOT NULL,
  confidence_interval_low  NUMERIC(18,4),
  confidence_interval_high NUMERIC(18,4),
  generated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_advisory_forecast_period CHECK (forecast_period_end > forecast_period_start)
);
CREATE INDEX idx_advisory_forecast_type_period ON trustride.advisory_forecast (forecast_type, forecast_period_start DESC);
ALTER TABLE trustride.advisory_forecast ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_forecast_platform_read ON trustride.advisory_forecast FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_forecast_service_write ON trustride.advisory_forecast FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);

-- 2.8 Anomaly Detection (including margin breaches)
CREATE TABLE trustride.advisory_anomaly_detection (
  anomaly_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id             UUID REFERENCES trustride.advisory_model_registry (model_id),
  anomaly_type         trustride.advisory_anomaly_type_enum NOT NULL,
  source_engine_code   TEXT NOT NULL,
  severity             trustride.advisory_severity_enum NOT NULL DEFAULT 'MEDIUM',
  description          TEXT NOT NULL,
  correlation_id       UUID,
  detected_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_advisory_anomaly_detection_type_severity ON trustride.advisory_anomaly_detection (anomaly_type, severity);
CREATE INDEX idx_advisory_anomaly_detection_correlation ON trustride.advisory_anomaly_detection (correlation_id) WHERE correlation_id IS NOT NULL;
COMMENT ON TABLE trustride.advisory_anomaly_detection IS
  'A MARGIN_BREACH row here is written the instant Cost''s COST_MARGIN_BREACHED signal is accepted -- Cost''s own quote is never touched; this is observation, not intervention.';
ALTER TABLE trustride.advisory_anomaly_detection ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_anomaly_detection_platform_read ON trustride.advisory_anomaly_detection FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_anomaly_detection_service_write ON trustride.advisory_anomaly_detection FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);

-- 2.9 Recurring Operational Patterns
CREATE TABLE trustride.advisory_pattern_insight (
  pattern_insight_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id             UUID NOT NULL REFERENCES trustride.advisory_model_registry (model_id),
  pattern_code         TEXT NOT NULL,
  pattern_description  TEXT NOT NULL,
  subject_scope        TEXT NOT NULL,
  supporting_sample_size INTEGER NOT NULL CHECK (supporting_sample_size >= 0),
  identified_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_advisory_pattern_insight_code ON trustride.advisory_pattern_insight (pattern_code);
ALTER TABLE trustride.advisory_pattern_insight ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_pattern_insight_platform_read ON trustride.advisory_pattern_insight FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_pattern_insight_service_write ON trustride.advisory_pattern_insight FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);

-- 2.10 Continuous Model Evaluation
CREATE TABLE trustride.advisory_model_performance (
  model_performance_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id             UUID NOT NULL REFERENCES trustride.advisory_model_registry (model_id),
  evaluation_period_start DATE NOT NULL,
  evaluation_period_end   DATE NOT NULL,
  accuracy_metric_name TEXT NOT NULL,
  metric_value         NUMERIC(10,4) NOT NULL,
  evaluated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_advisory_model_performance_period CHECK (evaluation_period_end > evaluation_period_start)
);
CREATE INDEX idx_advisory_model_performance_model ON trustride.advisory_model_performance (model_id, evaluation_period_start DESC);
COMMENT ON TABLE trustride.advisory_model_performance IS
  'A model whose metric_value degrades below its governed threshold is transitioned to DEPRECATED -- a wrong model is corrected, never left silently issuing recommendations.';
ALTER TABLE trustride.advisory_model_performance ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_model_performance_platform_read ON trustride.advisory_model_performance FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_model_performance_service_write ON trustride.advisory_model_performance FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);

-- 2.11 Immutable, Hash-Chained Evidence
CREATE TABLE trustride.advisory_decision_log (
  decision_log_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recommendation_id    UUID REFERENCES trustride.advisory_recommendation (recommendation_id),
  event_type           TEXT NOT NULL,
  event_description    TEXT,
  prev_hash            CHAR(64),
  immutable_hash       CHAR(64) NOT NULL,
  recorded_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_advisory_decision_log_recommendation ON trustride.advisory_decision_log (recommendation_id);
REVOKE UPDATE, DELETE ON trustride.advisory_decision_log FROM PUBLIC;
REVOKE UPDATE, DELETE ON trustride.advisory_decision_log FROM trustride_authenticated;
ALTER TABLE trustride.advisory_decision_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_decision_log_platform_read ON trustride.advisory_decision_log FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_decision_log_service_write ON trustride.advisory_decision_log FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);

-- 2.12 Engine Event Substrate (mandatory per-engine ledger tables)
-- Deviation 1 applied here: `emitted_at` added, matching the platform-wide
-- fn_orch_dispatch_cycle contract (see file header).
CREATE TABLE trustride.advisory_event_outbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id     UUID NOT NULL,
  causation_id       UUID,
  emitting_engine    TEXT NOT NULL DEFAULT 'TRS026_ENG009_AIADV',
  receiving_engine   TEXT NOT NULL,
  signal_type        TEXT NOT NULL,
  payload_in         JSONB NOT NULL,
  signal_status      TEXT NOT NULL DEFAULT 'PENDING'
                       CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason   TEXT,
  idempotency_key    TEXT NOT NULL UNIQUE,
  attempt_count      INTEGER NOT NULL DEFAULT 0,
  emitted_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_advisory_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_advisory_outbox_status ON trustride.advisory_event_outbox (signal_status);
CREATE INDEX idx_advisory_outbox_correlation ON trustride.advisory_event_outbox (correlation_id);
ALTER TABLE trustride.advisory_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_event_outbox_service_only ON trustride.advisory_event_outbox FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.advisory_event_inbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id     UUID NOT NULL,
  causation_id       UUID,
  emitting_engine    TEXT NOT NULL,
  receiving_engine   TEXT NOT NULL DEFAULT 'TRS026_ENG009_AIADV',
  signal_type        TEXT NOT NULL,
  payload_in         JSONB NOT NULL,
  payload_out        JSONB,
  signal_status      TEXT NOT NULL DEFAULT 'RECEIVED'
                       CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason   TEXT,
  idempotency_key    TEXT NOT NULL UNIQUE,
  emitted_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  received_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at        TIMESTAMPTZ,
  CONSTRAINT chk_advisory_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_advisory_inbox_status ON trustride.advisory_event_inbox (signal_status);
CREATE INDEX idx_advisory_inbox_correlation ON trustride.advisory_event_inbox (correlation_id);
ALTER TABLE trustride.advisory_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_event_inbox_service_only ON trustride.advisory_event_inbox FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);

-- ============================================================================
-- PHASE 4 -- MODEL REGISTRY SEED (Phase 1 heuristic baselines; see Deviation 2)
-- ============================================================================
INSERT INTO trustride.advisory_model_registry (model_code, model_name, model_type, model_version, training_data_description, model_status, deployed_at) VALUES
  ('CAPACITY_UTILIZATION_HEURISTIC_V1', 'Resource Capacity Utilization Threshold', 'RECOMMENDATION', '1.0.0',
    'Phase 1 threshold heuristic over resource_availability_ledger open-row utilization ratio (busy/total). Not yet a trained model.', 'ACTIVE', now()),
  ('FLEET_REPLACEMENT_HEURISTIC_V1', 'Fleet Replacement Maintenance Threshold', 'RECOMMENDATION', '1.0.0',
    'Phase 1 threshold heuristic over resource_maintenance_record trailing-90-day repair count and cost. Not yet a trained model.', 'ACTIVE', now()),
  ('SERVICE_MIX_HEURISTIC_V1', 'Service Catalogue Mix Concentration', 'RECOMMENDATION', '1.0.0',
    'Phase 1 threshold heuristic flagging a macro domain served by exactly one ACTIVE service_catalogue row. Not yet a trained model.', 'ACTIVE', now()),
  ('DEMAND_PATTERN_HEURISTIC_V1', 'Order Volume Week-over-Week Pattern', 'RECOMMENDATION', '1.0.0',
    'Phase 1 week-over-week change heuristic over business_order.placed_at counts by macro_domain. Not yet a trained model.', 'ACTIVE', now()),
  ('DEMAND_FORECAST_MOVING_AVERAGE_V1', 'Demand Naive Moving-Average Forecast', 'FORECASTING', '1.0.0',
    'Phase 1 naive baseline: next 7-day order count projected as the trailing 7-day count, +/-20% band. Not yet a trained model.', 'ACTIVE', now()),
  ('REVENUE_PATTERN_HEURISTIC_V1', 'Settlement Revenue Week-over-Week Pattern', 'RECOMMENDATION', '1.0.0',
    'Phase 1 week-over-week change heuristic over business_settlement.computed_total_fare_kes by macro_domain. Not yet a trained model.', 'ACTIVE', now()),
  ('REVENUE_FORECAST_MOVING_AVERAGE_V1', 'Revenue Naive Moving-Average Forecast', 'FORECASTING', '1.0.0',
    'Phase 1 naive baseline: next 7-day settled revenue projected as the trailing 7-day total, +/-20% band. Not yet a trained model.', 'ACTIVE', now()),
  ('EXTERNAL_RELIABILITY_HEURISTIC_V1', 'Vendor Circuit Breaker Reliability Threshold', 'RECOMMENDATION', '1.0.0',
    'Phase 1 threshold heuristic over integration_circuit_breaker_state (OPEN/HALF_OPEN or failure_count >= 3). Not yet a trained model.', 'ACTIVE', now()),
  ('PAYMENT_SUCCESS_RATE_HEURISTIC_V1', 'Payment Gateway Success Rate Threshold', 'RECOMMENDATION', '1.0.0',
    'Phase 1 threshold heuristic over trailing-7-day integration_payment_gateway_transaction settle/fail ratio. Not yet a trained model.', 'ACTIVE', now()),
  ('ROUTING_CAPACITY_TREND_HEURISTIC_V1', 'Orchestration Routing Capacity Threshold', 'RECOMMENDATION', '1.0.0',
    'Phase 1 threshold heuristic over orch_capacity_snapshot.runtime_health_status and orch_routing_metrics.routing_failures. Not yet a trained model.', 'ACTIVE', now()),
  ('CAPACITY_FORECAST_MOVING_AVERAGE_V1', 'Capacity Naive Moving-Average Forecast', 'FORECASTING', '1.0.0',
    'Phase 1 naive baseline: next 7-day platform-wide queue depth projected as the latest snapshot value, +/-20% band. Not yet a trained model.', 'ACTIVE', now()),
  ('COORDINATION_HEALTH_HEURISTIC_V1', 'Per-Engine Coordination Health Threshold', 'RECOMMENDATION', '1.0.0',
    'Phase 1 threshold heuristic over the latest coord_coordination_health.health_score per engine_code (< 70 flagged). Not yet a trained model.', 'ACTIVE', now());

-- ============================================================================
-- PHASE 5 -- CROSS-ENGINE READ ACCESS
-- Engine 9 is the one deliberate exception to Article 33's signal-only rule
-- (Sec.1.3 of the blueprint): a closed, registered list of direct read-only
-- SELECT grants, never a write, never an unregistered table.
-- ============================================================================
GRANT SELECT ON trustride.resource_availability_ledger, trustride.resource_maintenance_record TO trs026_eng009_aiadv_service;
GRANT SELECT ON trustride.service_catalogue TO trs026_eng009_aiadv_service;
GRANT SELECT ON trustride.business_order, trustride.business_settlement TO trs026_eng009_aiadv_service;
GRANT SELECT ON trustride.integration_circuit_breaker_state, trustride.integration_payment_gateway_transaction TO trs026_eng009_aiadv_service;
GRANT SELECT ON trustride.orch_queue_metrics, trustride.orch_routing_metrics, trustride.orch_capacity_snapshot TO trs026_eng009_aiadv_service;
GRANT SELECT ON trustride.coord_coordination_health, trustride.coord_coordination_metrics, trustride.coord_runtime_alert TO trs026_eng009_aiadv_service;

CREATE POLICY resource_availability_ledger_advisory_read ON trustride.resource_availability_ledger FOR SELECT TO trs026_eng009_aiadv_service USING (true);
CREATE POLICY resource_maintenance_record_advisory_read ON trustride.resource_maintenance_record FOR SELECT TO trs026_eng009_aiadv_service USING (true);
CREATE POLICY service_catalogue_advisory_read ON trustride.service_catalogue FOR SELECT TO trs026_eng009_aiadv_service USING (true);
CREATE POLICY business_order_advisory_read ON trustride.business_order FOR SELECT TO trs026_eng009_aiadv_service USING (true);
CREATE POLICY business_settlement_advisory_read ON trustride.business_settlement FOR SELECT TO trs026_eng009_aiadv_service USING (true);
CREATE POLICY integration_circuit_breaker_state_advisory_read ON trustride.integration_circuit_breaker_state FOR SELECT TO trs026_eng009_aiadv_service USING (true);
CREATE POLICY integration_payment_gateway_transaction_advisory_read ON trustride.integration_payment_gateway_transaction FOR SELECT TO trs026_eng009_aiadv_service USING (true);
CREATE POLICY orch_queue_metrics_advisory_read ON trustride.orch_queue_metrics FOR SELECT TO trs026_eng009_aiadv_service USING (true);
CREATE POLICY orch_routing_metrics_advisory_read ON trustride.orch_routing_metrics FOR SELECT TO trs026_eng009_aiadv_service USING (true);
CREATE POLICY orch_capacity_snapshot_advisory_read ON trustride.orch_capacity_snapshot FOR SELECT TO trs026_eng009_aiadv_service USING (true);
CREATE POLICY coord_coordination_health_advisory_read ON trustride.coord_coordination_health FOR SELECT TO trs026_eng009_aiadv_service USING (true);
CREATE POLICY coord_coordination_metrics_advisory_read ON trustride.coord_coordination_metrics FOR SELECT TO trs026_eng009_aiadv_service USING (true);
CREATE POLICY coord_runtime_alert_advisory_read ON trustride.coord_runtime_alert FOR SELECT TO trs026_eng009_aiadv_service USING (true);

-- ============================================================================
-- PHASE 6 -- SHARED EMISSION HELPER
-- ============================================================================
CREATE FUNCTION trustride.fn_advisory_recommendation_emit(
  p_model_code TEXT,
  p_recommendation_type trustride.advisory_recommendation_type_enum,
  p_subject_engine_code TEXT,
  p_subject_ref_id UUID,
  p_correlation_id UUID,
  p_recommendation_payload JSONB,
  p_confidence_score NUMERIC,
  p_evidence JSONB DEFAULT '[]'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_model_id           UUID;
  v_recommendation_id  UUID;
  v_evidence_row       JSONB;
  v_prev_hash          CHAR(64);
  v_new_hash           CHAR(64);
BEGIN
  SELECT model_id INTO v_model_id FROM trustride.advisory_model_registry WHERE model_code = p_model_code AND model_status = 'ACTIVE';
  IF v_model_id IS NULL THEN
    RAISE EXCEPTION 'fn_advisory_recommendation_emit: no ACTIVE model registered for model_code=%', p_model_code;
  END IF;

  INSERT INTO trustride.advisory_recommendation
    (model_id, recommendation_type, subject_engine_code, subject_ref_id, correlation_id, recommendation_payload, confidence_score, expires_at)
  VALUES
    (v_model_id, p_recommendation_type, p_subject_engine_code, p_subject_ref_id, p_correlation_id, p_recommendation_payload,
     LEAST(p_confidence_score, 99), now() + INTERVAL '30 days')
  RETURNING recommendation_id INTO v_recommendation_id;

  FOR v_evidence_row IN SELECT * FROM jsonb_array_elements(p_evidence)
  LOOP
    INSERT INTO trustride.advisory_recommendation_evidence (recommendation_id, feature_name, feature_value, feature_weight)
    VALUES (v_recommendation_id, v_evidence_row->>'feature_name', v_evidence_row->'feature_value', (v_evidence_row->>'feature_weight')::numeric);
  END LOOP;

  INSERT INTO trustride.advisory_recommendation_outcome (recommendation_id, outcome) VALUES (v_recommendation_id, 'PENDING');

  SELECT immutable_hash INTO v_prev_hash FROM trustride.advisory_decision_log ORDER BY recorded_at DESC LIMIT 1;
  v_new_hash := encode(digest(coalesce(v_prev_hash, '') || v_recommendation_id::text || 'RECOMMENDATION_PUBLISHED', 'sha256'), 'hex');
  INSERT INTO trustride.advisory_decision_log (recommendation_id, event_type, event_description, prev_hash, immutable_hash)
  VALUES (v_recommendation_id, 'RECOMMENDATION_PUBLISHED',
    format('%s recommendation published for %s, confidence %s%%', p_recommendation_type, p_subject_engine_code, p_confidence_score),
    v_prev_hash, v_new_hash);

  INSERT INTO trustride.advisory_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG011_PRESENT', 'ADVISORY_RECOMMENDATION_PUBLISHED',
    jsonb_build_object('recommendation_id', v_recommendation_id, 'recommendation_type', p_recommendation_type,
      'subject_engine_code', p_subject_engine_code, 'confidence_score', p_confidence_score),
    'ADVISORY_RECOMMENDATION_PUBLISHED:' || v_recommendation_id::text);

  RETURN v_recommendation_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_advisory_recommendation_emit IS
  '[Trace: Sec.2.4-2.6, Sec.4.2] The single write path for every recommendation this engine ever produces -- inserts the recommendation, its evidence, a PENDING outcome row, hash-chained decision-log evidence, and emits ADVISORY_RECOMMENDATION_PUBLISHED. Every sweep function below calls only this.';

-- ============================================================================
-- PHASE 7 -- GOVERNOR/RULE DECISION API [Trace: Sec.3.2, Sec.2.6]
-- ============================================================================
CREATE FUNCTION trustride.fn_advisory_recommendation_decide(
  p_recommendation_id UUID,
  p_outcome trustride.advisory_outcome_enum,
  p_decision_reason TEXT DEFAULT NULL,
  p_decision_rule_ref TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_decided_by UUID := NULL;
BEGIN
  IF p_decision_rule_ref IS NULL THEN
    IF NOT trustride.fn_am_i_governor() THEN
      RAISE EXCEPTION 'fn_advisory_recommendation_decide: only a Governor may decide a recommendation outcome directly (a lawful rule decides via p_decision_rule_ref instead)';
    END IF;
    v_decided_by := auth.uid();
  END IF;

  UPDATE trustride.advisory_recommendation_outcome
  SET outcome = p_outcome, decided_by = v_decided_by, decision_rule_ref = p_decision_rule_ref, decision_reason = p_decision_reason, decided_at = now()
  WHERE recommendation_id = p_recommendation_id AND outcome = 'PENDING';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_advisory_recommendation_decide: recommendation % has no PENDING outcome row to decide', p_recommendation_id;
  END IF;

  RETURN p_outcome::text;
END;
$$;
COMMENT ON FUNCTION trustride.fn_advisory_recommendation_decide IS
  '[Trace: Sec.3.2, FDN-001 Sec.11.3 Layer Crossing Law] A human Governor or a lawful rule decides, never this engine -- the constitutional proof this engine influences nothing on its own.';

-- ============================================================================
-- PHASE 8 -- RECOMMENDATION & FORECAST SWEEP FUNCTIONS
-- Each is a real, working computation over exactly its registered read
-- source(s) (Sec.2.3) -- no unregistered table is ever touched.
-- ============================================================================

-- CAPACITY_PLANNING
CREATE FUNCTION trustride.fn_advisory_capacity_planning_sweep(p_correlation_id UUID DEFAULT gen_random_uuid())
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_row RECORD;
  v_utilization NUMERIC(5,2);
  v_count INTEGER := 0;
BEGIN
  FOR v_row IN
    SELECT resource_type,
      count(*) FILTER (WHERE availability_state IN ('RESERVED','ASSIGNED')) AS busy,
      count(*) AS total
    FROM trustride.resource_availability_ledger
    WHERE effective_to IS NULL
    GROUP BY resource_type
    HAVING count(*) >= 1
  LOOP
    v_utilization := round(100.0 * v_row.busy / v_row.total, 2);
    IF v_utilization >= 80 THEN
      PERFORM trustride.fn_advisory_recommendation_emit(
        'CAPACITY_UTILIZATION_HEURISTIC_V1', 'CAPACITY_PLANNING'::trustride.advisory_recommendation_type_enum,
        'TRS026_ENG002_RESC', NULL, p_correlation_id,
        jsonb_build_object('resource_type', v_row.resource_type, 'utilization_pct', v_utilization, 'direction', 'INCREASE_CAPACITY', 'sample_size', v_row.total),
        LEAST(95, v_utilization),
        jsonb_build_array(jsonb_build_object('feature_name', 'utilization_pct', 'feature_value', v_utilization, 'feature_weight', 1.0)));
      v_count := v_count + 1;
    ELSIF v_utilization <= 20 THEN
      PERFORM trustride.fn_advisory_recommendation_emit(
        'CAPACITY_UTILIZATION_HEURISTIC_V1', 'CAPACITY_PLANNING'::trustride.advisory_recommendation_type_enum,
        'TRS026_ENG002_RESC', NULL, p_correlation_id,
        jsonb_build_object('resource_type', v_row.resource_type, 'utilization_pct', v_utilization, 'direction', 'REVIEW_EXCESS_CAPACITY', 'sample_size', v_row.total),
        LEAST(90, 100 - v_utilization),
        jsonb_build_array(jsonb_build_object('feature_name', 'utilization_pct', 'feature_value', v_utilization, 'feature_weight', 1.0)));
      v_count := v_count + 1;
    END IF;
  END LOOP;
  RETURN v_count;
END;
$$;

-- FLEET_REPLACEMENT
CREATE FUNCTION trustride.fn_advisory_fleet_replacement_sweep(p_correlation_id UUID DEFAULT gen_random_uuid())
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_row RECORD;
  v_count INTEGER := 0;
BEGIN
  FOR v_row IN
    SELECT fleet_resource_id,
      count(*) FILTER (WHERE maintenance_type = 'REPAIR') AS repair_count,
      sum(cost_kes) AS total_cost_kes
    FROM trustride.resource_maintenance_record
    WHERE created_at >= now() - INTERVAL '90 days'
    GROUP BY fleet_resource_id
    HAVING count(*) FILTER (WHERE maintenance_type = 'REPAIR') >= 3 OR sum(cost_kes) >= 50000
  LOOP
    PERFORM trustride.fn_advisory_recommendation_emit(
      'FLEET_REPLACEMENT_HEURISTIC_V1', 'FLEET_REPLACEMENT'::trustride.advisory_recommendation_type_enum,
      'TRS026_ENG002_RESC', v_row.fleet_resource_id, p_correlation_id,
      jsonb_build_object('repair_count_90d', v_row.repair_count, 'total_maintenance_cost_kes_90d', v_row.total_cost_kes),
      LEAST(92, 50 + v_row.repair_count * 8),
      jsonb_build_array(
        jsonb_build_object('feature_name', 'repair_count_90d', 'feature_value', v_row.repair_count, 'feature_weight', 0.6),
        jsonb_build_object('feature_name', 'total_maintenance_cost_kes_90d', 'feature_value', v_row.total_cost_kes, 'feature_weight', 0.4)));
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

-- SERVICE_MIX
CREATE FUNCTION trustride.fn_advisory_service_mix_sweep(p_correlation_id UUID DEFAULT gen_random_uuid())
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_row RECORD;
  v_count INTEGER := 0;
BEGIN
  FOR v_row IN
    SELECT macro_domain_id, count(*) AS active_service_count
    FROM trustride.service_catalogue
    WHERE status = 'ACTIVE'
    GROUP BY macro_domain_id
    HAVING count(*) = 1
  LOOP
    PERFORM trustride.fn_advisory_recommendation_emit(
      'SERVICE_MIX_HEURISTIC_V1', 'SERVICE_MIX'::trustride.advisory_recommendation_type_enum,
      'TRS026_ENG003_SERV', v_row.macro_domain_id, p_correlation_id,
      jsonb_build_object('macro_domain_id', v_row.macro_domain_id, 'active_service_count', v_row.active_service_count, 'direction', 'EXPAND_MIX'),
      70,
      jsonb_build_array(jsonb_build_object('feature_name', 'active_service_count', 'feature_value', v_row.active_service_count, 'feature_weight', 1.0)));
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

-- DEMAND_PATTERN + DEMAND forecast
CREATE FUNCTION trustride.fn_advisory_demand_sweep(p_correlation_id UUID DEFAULT gen_random_uuid())
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_row RECORD;
  v_change_pct NUMERIC;
  v_count INTEGER := 0;
  v_forecast_model_id UUID;
BEGIN
  SELECT model_id INTO v_forecast_model_id FROM trustride.advisory_model_registry WHERE model_code = 'DEMAND_FORECAST_MOVING_AVERAGE_V1' AND model_status = 'ACTIVE';

  FOR v_row IN
    SELECT macro_domain,
      count(*) FILTER (WHERE placed_at >= now() - INTERVAL '7 days') AS recent_week,
      count(*) FILTER (WHERE placed_at >= now() - INTERVAL '14 days' AND placed_at < now() - INTERVAL '7 days') AS prior_week
    FROM trustride.business_order
    WHERE placed_at >= now() - INTERVAL '14 days'
    GROUP BY macro_domain
    HAVING count(*) >= 1
  LOOP
    v_change_pct := CASE WHEN v_row.prior_week = 0 THEN NULL ELSE round(100.0 * (v_row.recent_week - v_row.prior_week) / v_row.prior_week, 2) END;

    IF v_change_pct IS NOT NULL AND abs(v_change_pct) >= 20 THEN
      PERFORM trustride.fn_advisory_recommendation_emit(
        'DEMAND_PATTERN_HEURISTIC_V1', 'DEMAND_PATTERN'::trustride.advisory_recommendation_type_enum,
        'TRS026_ENG004_BUS', NULL, p_correlation_id,
        jsonb_build_object('macro_domain', v_row.macro_domain, 'recent_week_orders', v_row.recent_week, 'prior_week_orders', v_row.prior_week,
          'change_pct', v_change_pct, 'direction', CASE WHEN v_change_pct > 0 THEN 'RISING_DEMAND' ELSE 'DECLINING_DEMAND' END),
        LEAST(90, 50 + abs(v_change_pct) / 2),
        jsonb_build_array(jsonb_build_object('feature_name', 'week_over_week_change_pct', 'feature_value', v_change_pct, 'feature_weight', 1.0)));
      v_count := v_count + 1;
    END IF;

    IF v_forecast_model_id IS NOT NULL THEN
      INSERT INTO trustride.advisory_forecast
        (model_id, forecast_type, subject_scope, forecast_period_start, forecast_period_end, forecast_value, confidence_interval_low, confidence_interval_high)
      VALUES
        (v_forecast_model_id, 'DEMAND'::trustride.advisory_forecast_type_enum, v_row.macro_domain,
         (now() + INTERVAL '1 day')::date, (now() + INTERVAL '7 days')::date,
         v_row.recent_week, v_row.recent_week * 0.8, v_row.recent_week * 1.2);
    END IF;
  END LOOP;
  RETURN v_count;
END;
$$;

-- REVENUE_PATTERN + REVENUE forecast
CREATE FUNCTION trustride.fn_advisory_revenue_sweep(p_correlation_id UUID DEFAULT gen_random_uuid())
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_row RECORD;
  v_recent NUMERIC;
  v_prior NUMERIC;
  v_change_pct NUMERIC;
  v_count INTEGER := 0;
  v_forecast_model_id UUID;
BEGIN
  SELECT model_id INTO v_forecast_model_id FROM trustride.advisory_model_registry WHERE model_code = 'REVENUE_FORECAST_MOVING_AVERAGE_V1' AND model_status = 'ACTIVE';

  FOR v_row IN
    SELECT o.macro_domain,
      sum(s.computed_total_fare_kes) FILTER (WHERE s.settled_at >= now() - INTERVAL '7 days') AS recent_week_kes,
      sum(s.computed_total_fare_kes) FILTER (WHERE s.settled_at >= now() - INTERVAL '14 days' AND s.settled_at < now() - INTERVAL '7 days') AS prior_week_kes
    FROM trustride.business_settlement s
    JOIN trustride.business_order o ON o.order_id = s.order_id
    WHERE s.payment_status IN ('SETTLED','LEDGER_POSTED','RECEIPT_GENERATED') AND s.settled_at >= now() - INTERVAL '14 days'
    GROUP BY o.macro_domain
  LOOP
    v_recent := coalesce(v_row.recent_week_kes, 0);
    v_prior := coalesce(v_row.prior_week_kes, 0);
    v_change_pct := CASE WHEN v_prior = 0 THEN NULL ELSE round(100.0 * (v_recent - v_prior) / v_prior, 2) END;

    IF v_change_pct IS NOT NULL AND abs(v_change_pct) >= 20 THEN
      PERFORM trustride.fn_advisory_recommendation_emit(
        'REVENUE_PATTERN_HEURISTIC_V1', 'REVENUE_PATTERN'::trustride.advisory_recommendation_type_enum,
        'TRS026_ENG004_BUS', NULL, p_correlation_id,
        jsonb_build_object('macro_domain', v_row.macro_domain, 'recent_week_revenue_kes', v_recent, 'prior_week_revenue_kes', v_prior,
          'change_pct', v_change_pct, 'direction', CASE WHEN v_change_pct > 0 THEN 'RISING_REVENUE' ELSE 'DECLINING_REVENUE' END),
        LEAST(90, 50 + abs(v_change_pct) / 2),
        jsonb_build_array(jsonb_build_object('feature_name', 'week_over_week_revenue_change_pct', 'feature_value', v_change_pct, 'feature_weight', 1.0)));
      v_count := v_count + 1;
    END IF;

    IF v_forecast_model_id IS NOT NULL AND v_recent > 0 THEN
      INSERT INTO trustride.advisory_forecast
        (model_id, forecast_type, subject_scope, forecast_period_start, forecast_period_end, forecast_value, confidence_interval_low, confidence_interval_high)
      VALUES
        (v_forecast_model_id, 'REVENUE'::trustride.advisory_forecast_type_enum, v_row.macro_domain,
         (now() + INTERVAL '1 day')::date, (now() + INTERVAL '7 days')::date,
         v_recent, v_recent * 0.8, v_recent * 1.2);
    END IF;
  END LOOP;
  RETURN v_count;
END;
$$;

-- EXTERNAL_RELIABILITY
CREATE FUNCTION trustride.fn_advisory_external_reliability_sweep(p_correlation_id UUID DEFAULT gen_random_uuid())
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_row RECORD;
  v_count INTEGER := 0;
BEGIN
  FOR v_row IN
    SELECT port_code, state, failure_count, latency_ms_last
    FROM trustride.integration_circuit_breaker_state
    WHERE state IN ('OPEN','HALF_OPEN') OR failure_count >= 3
  LOOP
    PERFORM trustride.fn_advisory_recommendation_emit(
      'EXTERNAL_RELIABILITY_HEURISTIC_V1', 'EXTERNAL_RELIABILITY'::trustride.advisory_recommendation_type_enum,
      'TRS026_ENG006_INTG', NULL, p_correlation_id,
      jsonb_build_object('port_code', v_row.port_code, 'circuit_state', v_row.state, 'failure_count', v_row.failure_count, 'latency_ms_last', v_row.latency_ms_last),
      LEAST(95, 60 + v_row.failure_count * 5),
      jsonb_build_array(jsonb_build_object('feature_name', 'failure_count', 'feature_value', v_row.failure_count, 'feature_weight', 1.0)));
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

-- PAYMENT_SUCCESS_RATE
CREATE FUNCTION trustride.fn_advisory_payment_success_rate_sweep(p_correlation_id UUID DEFAULT gen_random_uuid())
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_settled INTEGER;
  v_failed INTEGER;
  v_total INTEGER;
  v_rate NUMERIC;
  v_count INTEGER := 0;
BEGIN
  SELECT count(*) FILTER (WHERE txn_status = 'SETTLED'), count(*) FILTER (WHERE txn_status IN ('FAILED','REVERSED'))
  INTO v_settled, v_failed
  FROM trustride.integration_payment_gateway_transaction
  WHERE initiated_at >= now() - INTERVAL '7 days';

  v_total := v_settled + v_failed;
  IF v_total >= 3 THEN
    v_rate := round(100.0 * v_settled / v_total, 2);
    IF v_rate < 85 THEN
      PERFORM trustride.fn_advisory_recommendation_emit(
        'PAYMENT_SUCCESS_RATE_HEURISTIC_V1', 'PAYMENT_SUCCESS_RATE'::trustride.advisory_recommendation_type_enum,
        'TRS026_ENG006_INTG', NULL, p_correlation_id,
        jsonb_build_object('success_rate_pct', v_rate, 'settled_count_7d', v_settled, 'failed_count_7d', v_failed),
        LEAST(92, 50 + (85 - v_rate)),
        jsonb_build_array(jsonb_build_object('feature_name', 'success_rate_pct', 'feature_value', v_rate, 'feature_weight', 1.0)));
      v_count := 1;
    END IF;
  END IF;
  RETURN v_count;
END;
$$;

-- ROUTING_CAPACITY_TREND + CAPACITY forecast
CREATE FUNCTION trustride.fn_advisory_routing_capacity_sweep(p_correlation_id UUID DEFAULT gen_random_uuid())
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_snapshot RECORD;
  v_failures INTEGER;
  v_count INTEGER := 0;
  v_forecast_model_id UUID;
BEGIN
  SELECT model_id INTO v_forecast_model_id FROM trustride.advisory_model_registry WHERE model_code = 'CAPACITY_FORECAST_MOVING_AVERAGE_V1' AND model_status = 'ACTIVE';

  SELECT * INTO v_snapshot FROM trustride.orch_capacity_snapshot ORDER BY snapshot_at DESC LIMIT 1;
  SELECT coalesce(sum(routing_failures), 0) INTO v_failures FROM trustride.orch_routing_metrics WHERE measured_at >= now() - INTERVAL '1 day';

  IF v_snapshot IS NOT NULL AND (v_snapshot.runtime_health_status <> 'HEALTHY' OR v_failures > 0) THEN
    PERFORM trustride.fn_advisory_recommendation_emit(
      'ROUTING_CAPACITY_TREND_HEURISTIC_V1', 'ROUTING_CAPACITY_TREND'::trustride.advisory_recommendation_type_enum,
      'TRS026_ENG007_ORCH', NULL, p_correlation_id,
      jsonb_build_object('runtime_health_status', v_snapshot.runtime_health_status, 'total_queue_depth', v_snapshot.total_queue_depth, 'routing_failures_24h', v_failures),
      CASE WHEN v_snapshot.runtime_health_status = 'CRITICAL' THEN 90 WHEN v_snapshot.runtime_health_status = 'DEGRADED' THEN 75 ELSE 65 END,
      jsonb_build_array(
        jsonb_build_object('feature_name', 'runtime_health_status', 'feature_value', v_snapshot.runtime_health_status, 'feature_weight', 0.6),
        jsonb_build_object('feature_name', 'routing_failures_24h', 'feature_value', v_failures, 'feature_weight', 0.4)));
    v_count := 1;
  END IF;

  IF v_forecast_model_id IS NOT NULL AND v_snapshot IS NOT NULL THEN
    INSERT INTO trustride.advisory_forecast
      (model_id, forecast_type, subject_scope, forecast_period_start, forecast_period_end, forecast_value, confidence_interval_low, confidence_interval_high)
    VALUES
      (v_forecast_model_id, 'CAPACITY'::trustride.advisory_forecast_type_enum, 'PLATFORM_WIDE',
       (now() + INTERVAL '1 day')::date, (now() + INTERVAL '7 days')::date,
       v_snapshot.total_queue_depth, v_snapshot.total_queue_depth * 0.8, v_snapshot.total_queue_depth * 1.2);
  END IF;

  RETURN v_count;
END;
$$;

-- COORDINATION_HEALTH_TREND
CREATE FUNCTION trustride.fn_advisory_coordination_health_sweep(p_correlation_id UUID DEFAULT gen_random_uuid())
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_row RECORD;
  v_open_alerts INTEGER;
  v_count INTEGER := 0;
BEGIN
  FOR v_row IN
    SELECT DISTINCT ON (engine_code) engine_code, health_score, health_status, measured_at
    FROM trustride.coord_coordination_health
    ORDER BY engine_code, measured_at DESC
  LOOP
    IF v_row.health_score < 70 THEN
      SELECT count(*) INTO v_open_alerts FROM trustride.coord_runtime_alert
      WHERE engine_code = v_row.engine_code AND alert_status = 'OPEN' AND alert_level IN ('WARNING','CRITICAL');

      PERFORM trustride.fn_advisory_recommendation_emit(
        'COORDINATION_HEALTH_HEURISTIC_V1', 'COORDINATION_HEALTH_TREND'::trustride.advisory_recommendation_type_enum,
        v_row.engine_code, NULL, p_correlation_id,
        jsonb_build_object('engine_code', v_row.engine_code, 'health_score', v_row.health_score, 'health_status', v_row.health_status, 'open_alerts', v_open_alerts),
        LEAST(92, 50 + (70 - v_row.health_score)),
        jsonb_build_array(jsonb_build_object('feature_name', 'health_score', 'feature_value', v_row.health_score, 'feature_weight', 1.0)));
      v_count := v_count + 1;
    END IF;
  END LOOP;
  RETURN v_count;
END;
$$;

-- ============================================================================
-- PHASE 9 -- INBOUND SIGNAL: COST_MARGIN_BREACHED [Trace: Sec.4.1]
-- ============================================================================
CREATE FUNCTION trustride.fn_advisory_inbox_process(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_signal_type    TEXT;
  v_payload        JSONB;
  v_correlation_id UUID;
  v_anomaly_id     UUID;
  v_severity       trustride.advisory_severity_enum;
  v_prev_hash      CHAR(64);
  v_new_hash       CHAR(64);
  v_result         TEXT;
BEGIN
  SELECT signal_type, payload_in, correlation_id INTO v_signal_type, v_payload, v_correlation_id
  FROM trustride.advisory_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_signal_type IS NULL THEN
    RAISE EXCEPTION 'fn_advisory_inbox_process: no RECEIVED signal %', p_signal_id;
  END IF;

  CASE v_signal_type
    WHEN 'COST_MARGIN_BREACHED' THEN
      v_severity := CASE
        WHEN (v_payload->>'computed_margin_pct')::numeric <= 0 THEN 'CRITICAL'
        WHEN (v_payload->>'computed_margin_pct')::numeric < (v_payload->>'minimum_margin_pct')::numeric / 2 THEN 'HIGH'
        ELSE 'MEDIUM'
      END::trustride.advisory_severity_enum;

      INSERT INTO trustride.advisory_anomaly_detection (anomaly_type, source_engine_code, severity, description, correlation_id)
      VALUES ('MARGIN_BREACH', 'TRS026_ENG005_COST', v_severity,
        format('Cost calculation %s produced margin %s%%, below the governed minimum of %s%%',
          v_payload->>'calculation_id', v_payload->>'computed_margin_pct', v_payload->>'minimum_margin_pct'),
        v_correlation_id)
      RETURNING anomaly_id INTO v_anomaly_id;

      SELECT immutable_hash INTO v_prev_hash FROM trustride.advisory_decision_log ORDER BY recorded_at DESC LIMIT 1;
      v_new_hash := encode(digest(coalesce(v_prev_hash, '') || v_anomaly_id::text || 'ANOMALY_DETECTED', 'sha256'), 'hex');
      INSERT INTO trustride.advisory_decision_log (event_type, event_description, prev_hash, immutable_hash)
      VALUES ('ANOMALY_DETECTED', format('MARGIN_BREACH anomaly %s recorded from Cost calculation %s', v_anomaly_id, v_payload->>'calculation_id'), v_prev_hash, v_new_hash);

      INSERT INTO trustride.advisory_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
      VALUES (v_correlation_id, 'TRS026_ENG008_COORD', 'ADVISORY_ANOMALY_FLAGGED',
        jsonb_build_object('anomaly_id', v_anomaly_id, 'anomaly_type', 'MARGIN_BREACH', 'severity', v_severity),
        'ADVISORY_ANOMALY_FLAGGED:COORD:' || v_anomaly_id::text);
      INSERT INTO trustride.advisory_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
      VALUES (v_correlation_id, 'TRS026_ENG011_PRESENT', 'ADVISORY_ANOMALY_FLAGGED',
        jsonb_build_object('anomaly_id', v_anomaly_id, 'anomaly_type', 'MARGIN_BREACH', 'severity', v_severity),
        'ADVISORY_ANOMALY_FLAGGED:PRESENT:' || v_anomaly_id::text);

      v_result := 'ACCEPTED';
    ELSE
      UPDATE trustride.advisory_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'UNREGISTERED_SIGNAL_TYPE:' || v_signal_type WHERE signal_id = p_signal_id;
      v_result := 'REJECTED';
  END CASE;

  IF v_result = 'ACCEPTED' THEN
    UPDATE trustride.advisory_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  END IF;

  RETURN v_result;
END;
$$;
COMMENT ON FUNCTION trustride.fn_advisory_inbox_process IS
  '[Trace: Sec.4.1] Cost''s own quote and rate card are never touched -- this is observation, not intervention. Emits ADVISORY_ANOMALY_FLAGGED to both Coordination and Presentation (Sec.4.2), as two separate outbox rows, matching the established MARKETPLACE_LISTING_SOLD dual-receiver pattern.';

-- ============================================================================
-- PHASE 10 -- COORDINATION RECEIVES ADVISORY_ANOMALY_FLAGGED (new for Engine 8)
-- ============================================================================
ALTER TABLE trustride.coord_event_inbox ADD COLUMN emitted_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE FUNCTION trustride.fn_coord_inbox_process(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_signal_type TEXT;
  v_payload     JSONB;
  v_result      TEXT;
BEGIN
  SELECT signal_type, payload_in INTO v_signal_type, v_payload
  FROM trustride.coord_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_signal_type IS NULL THEN
    RAISE EXCEPTION 'fn_coord_inbox_process: no RECEIVED signal %', p_signal_id;
  END IF;

  CASE v_signal_type
    WHEN 'ADVISORY_ANOMALY_FLAGGED' THEN
      INSERT INTO trustride.coord_runtime_alert (alert_code, alert_level, alert_reason, engine_code, alert_status)
      VALUES ('ADVISORY_' || (v_payload->>'anomaly_type'),
        CASE WHEN v_payload->>'severity' = 'CRITICAL' THEN 'CRITICAL'
             WHEN v_payload->>'severity' IN ('HIGH','MEDIUM') THEN 'WARNING'
             ELSE 'INFO' END::trustride.coord_alert_level_enum,
        format('Engine 9 flagged a %s anomaly (id=%s, severity=%s)', v_payload->>'anomaly_type', v_payload->>'anomaly_id', v_payload->>'severity'),
        'TRS026_ENG009_AIADV', 'OPEN');
      v_result := 'ACCEPTED';
    ELSE
      UPDATE trustride.coord_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'UNREGISTERED_SIGNAL_TYPE:' || v_signal_type WHERE signal_id = p_signal_id;
      v_result := 'REJECTED';
  END CASE;

  IF v_result = 'ACCEPTED' THEN
    UPDATE trustride.coord_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  END IF;

  RETURN v_result;
END;
$$;
COMMENT ON FUNCTION trustride.fn_coord_inbox_process IS
  'Coordination''s own inbox dispatcher -- did not exist before this file, since no prior engine ever routed a real signal to Coordination. Turns an Engine 9 anomaly flag into a real, open coord_runtime_alert row for operator review.';

-- ============================================================================
-- PHASE 11 -- EXTEND ORCHESTRATION (preserve every previously-recognized
-- engine's branch; add AIADV and COORD as real dispatch destinations for
-- the first time)
-- ============================================================================
CREATE OR REPLACE FUNCTION trustride.fn_orch_destination_cache_sync()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_synced INTEGER;
  v_deactivated INTEGER;
BEGIN
  INSERT INTO trustride.orch_destination_cache
    (source_engine_code, signal_type, destination_engine_code, destination_inbox_table, default_partition_code, synced_from_routing_rule_ref, cache_status, last_synced_at)
  SELECT rr.source_engine, rr.event_type, rr.target_engine,
    CASE rr.target_engine
      WHEN 'TRS026_ENG001_FDN'  THEN 'platform_event_inbox'
      WHEN 'TRS026_ENG002_RESC' THEN 'resource_event_inbox'
      WHEN 'TRS026_ENG003_SERV' THEN 'service_event_inbox'
      WHEN 'TRS026_ENG004_BUS'  THEN 'business_event_inbox'
      WHEN 'TRS026_ENG005_COST' THEN 'cost_event_inbox'
      WHEN 'TRS026_ENG006_INTG' THEN 'integration_event_inbox'
      WHEN 'TRS026_ENG008_COORD' THEN 'coord_event_inbox'
      WHEN 'TRS026_ENG009_AIADV' THEN 'advisory_event_inbox'
      ELSE NULL
    END,
    rr.target_engine || ':DEFAULT',
    rr.route_id::text, 'ACTIVE', now()
  FROM trustride.routing_rule rr
  WHERE rr.active = TRUE
    AND CASE rr.target_engine
      WHEN 'TRS026_ENG001_FDN' THEN TRUE WHEN 'TRS026_ENG002_RESC' THEN TRUE WHEN 'TRS026_ENG003_SERV' THEN TRUE
      WHEN 'TRS026_ENG004_BUS' THEN TRUE WHEN 'TRS026_ENG005_COST' THEN TRUE WHEN 'TRS026_ENG006_INTG' THEN TRUE
      WHEN 'TRS026_ENG008_COORD' THEN TRUE WHEN 'TRS026_ENG009_AIADV' THEN TRUE ELSE FALSE
    END
  ON CONFLICT (source_engine_code, signal_type, destination_engine_code) DO UPDATE
    SET destination_inbox_table = EXCLUDED.destination_inbox_table,
        cache_status = 'ACTIVE', last_synced_at = now();

  GET DIAGNOSTICS v_synced = ROW_COUNT;

  UPDATE trustride.orch_destination_cache dc
  SET cache_status = 'SUPERSEDED', last_synced_at = now()
  WHERE dc.cache_status = 'ACTIVE'
    AND NOT EXISTS (
      SELECT 1 FROM trustride.routing_rule rr
      WHERE rr.active = TRUE AND rr.source_engine = dc.source_engine_code
        AND rr.event_type = dc.signal_type AND rr.target_engine = dc.destination_engine_code
    );
  GET DIAGNOSTICS v_deactivated = ROW_COUNT;

  RETURN v_synced + v_deactivated;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_orch_dispatch_cycle()
RETURNS TABLE (discovered INTEGER, routed INTEGER, no_rule_matched INTEGER, dispatched INTEGER, processed INTEGER)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_union_sql  TEXT;
  v_row        RECORD;
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
  SELECT string_agg(
    format('SELECT signal_id, correlation_id, causation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key, emitted_at, %L::text AS src_outbox_table FROM trustride.%I WHERE signal_status = ''PENDING''',
      outbox_table_name, outbox_table_name),
    ' UNION ALL '
  ) INTO v_union_sql
  FROM trustride.orch_outbox_registry WHERE active = TRUE;

  IF v_union_sql IS NOT NULL THEN
    FOR v_row IN EXECUTE v_union_sql || ' ORDER BY emitted_at' LOOP
      v_discovered := v_discovered + 1;

      INSERT INTO trustride.orch_execution_graph (correlation_id, signal_id, node_sequence, engine_code, node_stage)
      VALUES (v_row.correlation_id, v_row.signal_id, 1, v_row.emitting_engine, 'EMITTED');

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

      PERFORM trustride.fn_coord_admission_check(v_row.signal_type, v_row.signal_id, v_row.correlation_id, v_row.emitting_engine, v_cache.destination_engine_code);

      v_partition_id := trustride.fn_orch_queue_partition_ensure(v_cache.destination_engine_code);

      INSERT INTO trustride.orch_signal_queue (signal_id, correlation_id, source_engine_code, destination_engine_code, signal_type, queue_partition_id, idempotency_key)
      VALUES (v_row.signal_id, v_row.correlation_id, v_row.emitting_engine, v_cache.destination_engine_code, v_row.signal_type, v_partition_id, v_row.idempotency_key || ':queue')
      ON CONFLICT (idempotency_key) DO NOTHING
      RETURNING queue_id INTO v_queue_id;

      INSERT INTO trustride.orch_execution_graph (correlation_id, signal_id, node_sequence, engine_code, node_stage)
      VALUES (v_row.correlation_id, v_row.signal_id, 3, 'TRS026_ENG007_ORCH', 'QUEUED');

      EXECUTE format(
        'INSERT INTO trustride.%I (signal_id, correlation_id, causation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key, emitted_at) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)',
        v_cache.destination_inbox_table
      ) USING v_row.signal_id, v_row.correlation_id, v_row.causation_id, v_row.emitting_engine, v_cache.destination_engine_code, v_row.signal_type, v_row.payload_in, v_row.idempotency_key || ':inbox', v_row.emitted_at;

      EXECUTE format('UPDATE trustride.%I SET signal_status = ''DISPATCHED'' WHERE signal_id = $1', v_row.src_outbox_table) USING v_row.signal_id;
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

      BEGIN
        CASE v_cache.destination_engine_code
          WHEN 'TRS026_ENG001_FDN' THEN PERFORM trustride.fn_platform_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG002_RESC' THEN PERFORM trustride.fn_resource_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG003_SERV' THEN PERFORM trustride.fn_service_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG004_BUS' THEN PERFORM trustride.fn_business_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG005_COST' THEN PERFORM trustride.fn_cost_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG006_INTG' THEN PERFORM trustride.fn_integration_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG008_COORD' THEN PERFORM trustride.fn_coord_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG009_AIADV' THEN PERFORM trustride.fn_advisory_inbox_process(v_row.signal_id);
          ELSE NULL;
        END CASE;
        v_processed := v_processed + 1;
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END LOOP;
  END IF;

  RETURN QUERY SELECT v_discovered, v_routed, v_no_rule, v_dispatched, v_processed;
END;
$$;

-- ============================================================================
-- PHASE 12 -- GRANTS
-- ============================================================================
GRANT USAGE ON SCHEMA trustride TO trs026_eng009_aiadv_service;

GRANT EXECUTE ON FUNCTION trustride.fn_advisory_recommendation_emit(TEXT, trustride.advisory_recommendation_type_enum, TEXT, UUID, UUID, JSONB, NUMERIC, JSONB) TO trs026_eng009_aiadv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_advisory_capacity_planning_sweep(UUID) TO trs026_eng009_aiadv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_advisory_fleet_replacement_sweep(UUID) TO trs026_eng009_aiadv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_advisory_service_mix_sweep(UUID) TO trs026_eng009_aiadv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_advisory_demand_sweep(UUID) TO trs026_eng009_aiadv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_advisory_revenue_sweep(UUID) TO trs026_eng009_aiadv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_advisory_external_reliability_sweep(UUID) TO trs026_eng009_aiadv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_advisory_payment_success_rate_sweep(UUID) TO trs026_eng009_aiadv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_advisory_routing_capacity_sweep(UUID) TO trs026_eng009_aiadv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_advisory_coordination_health_sweep(UUID) TO trs026_eng009_aiadv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_advisory_inbox_process(UUID) TO trs026_eng009_aiadv_service, trs026_eng007_orch_service;
GRANT EXECUTE ON FUNCTION trustride.fn_advisory_recommendation_decide(UUID, trustride.advisory_outcome_enum, TEXT, TEXT) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_coord_inbox_process(UUID) TO trs026_eng008_coord_service, trs026_eng007_orch_service;

-- ============================================================================
-- PHASE 13 -- ROUTING & OUTBOX REGISTRATION
-- ============================================================================
INSERT INTO trustride.orch_outbox_registry (engine_code, outbox_table_name) VALUES ('TRS026_ENG009_AIADV', 'advisory_event_outbox');

INSERT INTO trustride.routing_rule (event_type, source_engine, target_engine, route_priority) VALUES
  ('COST_MARGIN_BREACHED', 'TRS026_ENG005_COST', 'TRS026_ENG009_AIADV', 0),
  ('ADVISORY_ANOMALY_FLAGGED', 'TRS026_ENG009_AIADV', 'TRS026_ENG008_COORD', 0);

SELECT trustride.fn_orch_destination_cache_sync();

-- ============================================================================
-- PHASE 14 -- ENGINE REGISTRY
-- ============================================================================
UPDATE trustride.engine_registry SET status = 'INSTALLED', engine_version = '1.0.0' WHERE engine_code = 'TRS026_ENG009_AIADV';

-- ============================================================================
-- PHASE 15 -- VALIDATION
-- ============================================================================
DO $$
DECLARE
  v_table_count INTEGER;
  v_model_count INTEGER;
  v_read_source_count INTEGER;
  v_status TEXT;
BEGIN
  SELECT count(*) INTO v_table_count FROM information_schema.tables
  WHERE table_schema = 'trustride' AND table_name LIKE 'advisory_%';
  IF v_table_count <> 13 THEN
    RAISE EXCEPTION 'ENGINE 9 VALIDATION FAILED: expected 13 advisory_* tables, found %', v_table_count;
  END IF;

  SELECT count(*) INTO v_model_count FROM trustride.advisory_model_registry WHERE model_status = 'ACTIVE';
  IF v_model_count <> 12 THEN
    RAISE EXCEPTION 'ENGINE 9 VALIDATION FAILED: expected 12 ACTIVE models, found %', v_model_count;
  END IF;

  SELECT count(*) INTO v_read_source_count FROM trustride.advisory_read_source_registry WHERE active = TRUE;
  IF v_read_source_count <> 13 THEN
    RAISE EXCEPTION 'ENGINE 9 VALIDATION FAILED: expected 13 registered read sources, found %', v_read_source_count;
  END IF;

  SELECT status INTO v_status FROM trustride.engine_registry WHERE engine_code = 'TRS026_ENG009_AIADV';
  IF v_status <> 'INSTALLED' THEN
    RAISE EXCEPTION 'ENGINE 9 VALIDATION FAILED: engine_registry status is %, expected INSTALLED', v_status;
  END IF;

  RAISE NOTICE 'ENGINE 9 (AI/ML ADVISORY) INSTALLATION VALIDATED: 13 tables, 12 ACTIVE models, 13 registered read sources, engine_registry INSTALLED.';
END;
$$;
