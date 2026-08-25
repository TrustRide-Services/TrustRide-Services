-- ============================================================================
-- ENGINE 10 -- SCENARIO MODELLING ENGINE
-- Per TRS026-ENG010-MODEL-001 v1.0.0 (ADOPTED 2026-08-16)
-- ============================================================================
-- Constitutional character: SANDBOXED ONLY. Zero write authority into any
-- other engine's tables. Every input is copied into model_input_snapshot
-- before analysis; no scenario ever joins a real domain table live.
--
-- Founder directive this increment: build and test locally, DO NOT migrate
-- (no supabase db push, no git commit) -- awaiting Founder review alongside
-- Engine 11 before either ships.
--
-- ALIGNMENT NOTE (same discipline as every prior engine when a blueprint's
-- table names don't match what this rebuild actually built): the blueprint's
-- own read grant (Sec.1.3) names `cost_formula_matrix`, `cost_rate_card_rule`,
-- and `cost_execution_ledger` -- none of which exist under those names in
-- this rebuild's Cost engine. The real equivalents are `cost_model` (the
-- formula/version reference), `cost_registry` + `cost_rate` (the governed
-- rate card), and `cost_record` (the execution ledger -- its own
-- `output_snapshot` JSONB already carries `computed_total_fare_kes` and
-- `margin_pct` per calculation, exactly the historical data this engine
-- needs). The grant is honoured in substance, not by literal table name.
--
-- SCOPE HONESTY: only PRICING_CHANGE and COST_VS_CAPACITY get real execution
-- logic -- both are grounded entirely in the one confirmed read grant (Cost).
-- FLEET_EXPANSION, PEAK_DEMAND, and ZONE_IMPACT remain registered templates
-- (per the blueprint's own literal seed data) but correctly FAIL on run --
-- no engine has granted Engine 10 a lawful read source for Resources or
-- Orchestration data yet (Sec.1.4.4, "never reads an ungranted source").
-- This is the constitutionally correct behavior, not a stub.
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
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng010_model_service') THEN
    CREATE ROLE trs026_eng010_model_service NOLOGIN;
  END IF;
END
$$;

-- ============================================================================
-- PHASE 2 -- ENUMS [Trace: TRS026-ENG010-MODEL-001 Sec.2.0]
-- ============================================================================
CREATE TYPE trustride.model_scenario_type_enum AS ENUM (
  'OPERATIONAL', 'COMMERCIAL', 'CAPACITY', 'FINANCIAL', 'REGULATORY'
);
CREATE TYPE trustride.model_run_status_enum AS ENUM (
  'QUEUED', 'RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED'
);
CREATE TYPE trustride.model_input_source_enum AS ENUM (
  'HISTORICAL_DATA', 'LIVE_SIGNAL', 'EXTERNAL_FEED', 'SIMULATION_PARAMETER', 'BUSINESS_RULE'
);
CREATE TYPE trustride.model_risk_severity_enum AS ENUM (
  'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'
);

-- ============================================================================
-- PHASE 3 -- TABLES [Trace: Sec.2.1-2.12]
-- ============================================================================

CREATE TABLE trustride.model_scenario_registry (
  scenario_registry_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scenario_code          TEXT NOT NULL UNIQUE,
  scenario_name          TEXT NOT NULL,
  scenario_type          trustride.model_scenario_type_enum NOT NULL,
  description            TEXT NOT NULL,
  input_schema           JSONB NOT NULL DEFAULT '{}',
  approved_by            UUID,
  approved_request_id    UUID,
  active                 BOOLEAN NOT NULL DEFAULT TRUE,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.model_scenario_registry IS
  'Example templates: Zone Impact, Pricing Change, Fleet Expansion, Peak Demand, Cost vs. Capacity. Only PRICING_CHANGE and COST_VS_CAPACITY execute for real in this rebuild -- see file header.';
ALTER TABLE trustride.model_scenario_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_scenario_registry_platform_read ON trustride.model_scenario_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_scenario_registry_service_write ON trustride.model_scenario_registry FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);

INSERT INTO trustride.model_scenario_registry (scenario_code, scenario_name, scenario_type, description) VALUES
  ('PRICING_CHANGE', 'Pricing Change Impact', 'FINANCIAL', 'Projects the revenue impact of a proposed rate change before it is adopted.'),
  ('FLEET_EXPANSION', 'Fleet Expansion Impact', 'CAPACITY', 'Projects capacity/utilization impact of adding fleet units.'),
  ('PEAK_DEMAND', 'Peak Demand Stress Test', 'OPERATIONAL', 'Projects dispatch and SLA outcomes under a hypothesized demand surge.'),
  ('ZONE_IMPACT', 'Zone Boundary Impact', 'OPERATIONAL', 'Projects dispatch efficiency impact of a proposed operational zone change.'),
  ('COST_VS_CAPACITY', 'Cost vs. Capacity Trade-off', 'CAPACITY', 'Compares governed rate-card cost between two asset classes.');

CREATE TABLE trustride.model_scenario_run (
  run_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scenario_registry_id  UUID NOT NULL REFERENCES trustride.model_scenario_registry (scenario_registry_id),
  run_status            trustride.model_run_status_enum NOT NULL DEFAULT 'QUEUED',
  requested_by          UUID NOT NULL,
  correlation_id        UUID NOT NULL,
  run_label             TEXT,
  failure_reason        TEXT,
  started_at            TIMESTAMPTZ,
  completed_at          TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_model_scenario_run_registry ON trustride.model_scenario_run (scenario_registry_id);
CREATE INDEX idx_model_scenario_run_correlation ON trustride.model_scenario_run (correlation_id);
CREATE INDEX idx_model_scenario_run_status ON trustride.model_scenario_run (run_status);
COMMENT ON TABLE trustride.model_scenario_run IS
  'One row per actual simulation execution. No column here, or anywhere in this schema, references a production table by foreign key -- the sandbox boundary is structural.';
ALTER TABLE trustride.model_scenario_run ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_scenario_run_platform_read ON trustride.model_scenario_run FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_scenario_run_service_write ON trustride.model_scenario_run FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.model_input_parameter (
  input_parameter_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id               UUID NOT NULL REFERENCES trustride.model_scenario_run (run_id),
  parameter_name       TEXT NOT NULL,
  parameter_value      JSONB NOT NULL,
  parameter_source     trustride.model_input_source_enum NOT NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_model_input_parameter_run ON trustride.model_input_parameter (run_id);
ALTER TABLE trustride.model_input_parameter ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_input_parameter_platform_read ON trustride.model_input_parameter FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_input_parameter_service_write ON trustride.model_input_parameter FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.model_input_snapshot (
  input_snapshot_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id               UUID NOT NULL REFERENCES trustride.model_scenario_run (run_id),
  source_engine_code   TEXT NOT NULL,
  source_table_name    TEXT NOT NULL,
  source_row_ref       UUID,
  snapshot_payload     JSONB NOT NULL,
  snapshot_hash        CHAR(64) NOT NULL,
  captured_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_model_input_snapshot_run ON trustride.model_input_snapshot (run_id);
COMMENT ON TABLE trustride.model_input_snapshot IS
  'The exact, immutable copy of every source row a scenario consumed at the moment it consumed it. A scenario''s result stays reproducible even after the real row it copied is superseded.';
REVOKE UPDATE, DELETE ON trustride.model_input_snapshot FROM PUBLIC;
REVOKE UPDATE, DELETE ON trustride.model_input_snapshot FROM trustride_authenticated;
ALTER TABLE trustride.model_input_snapshot ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_input_snapshot_platform_read ON trustride.model_input_snapshot FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_input_snapshot_service_write ON trustride.model_input_snapshot FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.model_projected_outcome (
  projected_outcome_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id                 UUID NOT NULL REFERENCES trustride.model_scenario_run (run_id),
  outcome_metric         TEXT NOT NULL,
  baseline_value         NUMERIC(18,4),
  projected_value        NUMERIC(18,4) NOT NULL,
  variance_pct           NUMERIC(8,4),
  generated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_model_projected_outcome_run ON trustride.model_projected_outcome (run_id);
ALTER TABLE trustride.model_projected_outcome ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_projected_outcome_platform_read ON trustride.model_projected_outcome FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_projected_outcome_service_write ON trustride.model_projected_outcome FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.model_performance_metric (
  performance_metric_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id                 UUID NOT NULL REFERENCES trustride.model_scenario_run (run_id),
  metric_name            TEXT NOT NULL,
  metric_value           NUMERIC(18,4) NOT NULL,
  metric_unit            TEXT,
  generated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_model_performance_metric_run ON trustride.model_performance_metric (run_id);
ALTER TABLE trustride.model_performance_metric ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_performance_metric_platform_read ON trustride.model_performance_metric FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_performance_metric_service_write ON trustride.model_performance_metric FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.model_risk_indicator (
  risk_indicator_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id              UUID NOT NULL REFERENCES trustride.model_scenario_run (run_id),
  risk_code           TEXT NOT NULL,
  risk_description    TEXT NOT NULL,
  severity            trustride.model_risk_severity_enum NOT NULL DEFAULT 'MEDIUM',
  generated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_model_risk_indicator_run ON trustride.model_risk_indicator (run_id);
ALTER TABLE trustride.model_risk_indicator ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_risk_indicator_platform_read ON trustride.model_risk_indicator FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_risk_indicator_service_write ON trustride.model_risk_indicator FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.model_comparative_view (
  comparative_view_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  base_run_id           UUID NOT NULL REFERENCES trustride.model_scenario_run (run_id),
  compared_run_id       UUID NOT NULL REFERENCES trustride.model_scenario_run (run_id),
  comparison_metric     TEXT NOT NULL,
  base_value            NUMERIC(18,4),
  compared_value        NUMERIC(18,4),
  delta                 NUMERIC(18,4),
  generated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_model_comparative_view_distinct CHECK (base_run_id <> compared_run_id)
);
CREATE INDEX idx_model_comparative_view_base ON trustride.model_comparative_view (base_run_id);
ALTER TABLE trustride.model_comparative_view ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_comparative_view_platform_read ON trustride.model_comparative_view FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_comparative_view_service_write ON trustride.model_comparative_view FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.model_actionable_insight (
  actionable_insight_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id                 UUID NOT NULL REFERENCES trustride.model_scenario_run (run_id),
  insight_text           TEXT NOT NULL,
  confidence_score       NUMERIC(5,2) CHECK (confidence_score IS NULL OR confidence_score BETWEEN 0 AND 100),
  reviewed_by            UUID,
  reviewed_at            TIMESTAMPTZ,
  generated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_model_actionable_insight_run ON trustride.model_actionable_insight (run_id);
COMMENT ON TABLE trustride.model_actionable_insight IS
  'A hypothesis''s consequence, in plain language -- never a command. reviewed_by/reviewed_at proves a human decides, this engine never does.';
ALTER TABLE trustride.model_actionable_insight ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_actionable_insight_platform_read ON trustride.model_actionable_insight FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_actionable_insight_service_write ON trustride.model_actionable_insight FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.model_sensitivity_analysis (
  sensitivity_analysis_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id                   UUID NOT NULL REFERENCES trustride.model_scenario_run (run_id),
  varied_parameter_name    TEXT NOT NULL,
  parameter_test_value     JSONB NOT NULL,
  resulting_outcome_metric TEXT NOT NULL,
  resulting_value          NUMERIC(18,4) NOT NULL,
  sequence_no              SMALLINT NOT NULL,
  generated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_model_sensitivity_analysis_run ON trustride.model_sensitivity_analysis (run_id, varied_parameter_name, sequence_no);
ALTER TABLE trustride.model_sensitivity_analysis ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_sensitivity_analysis_platform_read ON trustride.model_sensitivity_analysis FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_sensitivity_analysis_service_write ON trustride.model_sensitivity_analysis FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.model_decision_log (
  decision_log_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id             UUID REFERENCES trustride.model_scenario_run (run_id),
  event_type         TEXT NOT NULL,
  event_description  TEXT,
  prev_hash          CHAR(64),
  immutable_hash     CHAR(64) NOT NULL,
  recorded_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_model_decision_log_run ON trustride.model_decision_log (run_id);
REVOKE UPDATE, DELETE ON trustride.model_decision_log FROM PUBLIC;
REVOKE UPDATE, DELETE ON trustride.model_decision_log FROM trustride_authenticated;
ALTER TABLE trustride.model_decision_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_decision_log_platform_read ON trustride.model_decision_log FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_decision_log_service_write ON trustride.model_decision_log FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.model_event_outbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id     UUID NOT NULL,
  causation_id       UUID,
  emitting_engine    TEXT NOT NULL DEFAULT 'TRS026_ENG010_MODEL',
  receiving_engine   TEXT NOT NULL,
  signal_type        TEXT NOT NULL,
  payload_in         JSONB NOT NULL,
  signal_status      TEXT NOT NULL DEFAULT 'PENDING'
                       CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason   TEXT,
  idempotency_key    TEXT NOT NULL UNIQUE,
  attempt_count      INTEGER NOT NULL DEFAULT 0,
  emitted_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_model_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_model_outbox_status ON trustride.model_event_outbox (signal_status);
CREATE INDEX idx_model_outbox_correlation ON trustride.model_event_outbox (correlation_id);
ALTER TABLE trustride.model_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_event_outbox_service_only ON trustride.model_event_outbox FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);

CREATE TABLE trustride.model_event_inbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id     UUID NOT NULL,
  causation_id       UUID,
  emitting_engine    TEXT NOT NULL,
  receiving_engine   TEXT NOT NULL DEFAULT 'TRS026_ENG010_MODEL',
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
  CONSTRAINT chk_model_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_model_inbox_status ON trustride.model_event_inbox (signal_status);
CREATE INDEX idx_model_inbox_correlation ON trustride.model_event_inbox (correlation_id);
ALTER TABLE trustride.model_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_event_inbox_service_only ON trustride.model_event_inbox FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);

-- ============================================================================
-- PHASE 4 -- CROSS-ENGINE READ ACCESS (the one confirmed grant: Cost)
-- ============================================================================
GRANT SELECT ON trustride.cost_model, trustride.cost_registry, trustride.cost_rate, trustride.cost_record TO trs026_eng010_model_service;

CREATE POLICY cost_model_scenario_read ON trustride.cost_model FOR SELECT TO trs026_eng010_model_service USING (true);
CREATE POLICY cost_registry_scenario_read ON trustride.cost_registry FOR SELECT TO trs026_eng010_model_service USING (true);
CREATE POLICY cost_rate_scenario_read ON trustride.cost_rate FOR SELECT TO trs026_eng010_model_service USING (true);
CREATE POLICY cost_record_scenario_read ON trustride.cost_record FOR SELECT TO trs026_eng010_model_service USING (true);

-- ============================================================================
-- PHASE 5 -- SHARED HELPERS
-- ============================================================================
CREATE FUNCTION trustride.fn_model_input_parameter_text(p_run_id UUID, p_parameter_name TEXT)
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
  SELECT trim(both '"' from parameter_value::text) FROM trustride.model_input_parameter
  WHERE run_id = p_run_id AND parameter_name = p_parameter_name ORDER BY created_at DESC LIMIT 1;
$$;

CREATE FUNCTION trustride.fn_model_input_parameter_numeric(p_run_id UUID, p_parameter_name TEXT)
RETURNS NUMERIC LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
  SELECT (parameter_value)::text::numeric FROM trustride.model_input_parameter
  WHERE run_id = p_run_id AND parameter_name = p_parameter_name ORDER BY created_at DESC LIMIT 1;
$$;

CREATE FUNCTION trustride.fn_model_input_snapshot_write(
  p_run_id UUID, p_source_engine_code TEXT, p_source_table_name TEXT, p_source_row_ref UUID, p_snapshot_payload JSONB
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO trustride.model_input_snapshot (run_id, source_engine_code, source_table_name, source_row_ref, snapshot_payload, snapshot_hash)
  VALUES (p_run_id, p_source_engine_code, p_source_table_name, p_source_row_ref, p_snapshot_payload, encode(digest(p_snapshot_payload::text, 'sha256'), 'hex'))
  RETURNING input_snapshot_id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE FUNCTION trustride.fn_model_decision_log_write(p_run_id UUID, p_event_type TEXT, p_event_description TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp AS $$
DECLARE
  v_id UUID;
  v_prev_hash CHAR(64);
  v_new_hash CHAR(64);
BEGIN
  SELECT immutable_hash INTO v_prev_hash FROM trustride.model_decision_log ORDER BY recorded_at DESC LIMIT 1;
  v_new_hash := encode(digest(coalesce(v_prev_hash, '') || coalesce(p_run_id::text, 'NULL') || p_event_type, 'sha256'), 'hex');
  INSERT INTO trustride.model_decision_log (run_id, event_type, event_description, prev_hash, immutable_hash)
  VALUES (p_run_id, p_event_type, p_event_description, v_prev_hash, v_new_hash)
  RETURNING decision_log_id INTO v_id;
  RETURN v_id;
END;
$$;

-- Shared FAILED exit path: every failure branch inside fn_model_scenario_run_execute
-- calls this instead of returning directly, so SCENARIO_RUN_COMPLETED is emitted for
-- a FAILED run exactly as it is for a COMPLETED one (Sec.4.2: "fired when run_status
-- reaches COMPLETED or FAILED").
CREATE FUNCTION trustride.fn_model_scenario_run_fail(p_run_id UUID, p_reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp AS $$
DECLARE
  v_run RECORD;
BEGIN
  SELECT r.correlation_id, sr.scenario_code INTO v_run
  FROM trustride.model_scenario_run r JOIN trustride.model_scenario_registry sr ON sr.scenario_registry_id = r.scenario_registry_id
  WHERE r.run_id = p_run_id;

  UPDATE trustride.model_scenario_run SET run_status = 'FAILED', completed_at = now(), failure_reason = p_reason WHERE run_id = p_run_id;
  PERFORM trustride.fn_model_decision_log_write(p_run_id, 'RUN_FAILED', p_reason);

  INSERT INTO trustride.model_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v_run.correlation_id, 'TRS026_ENG011_PRESENT', 'SCENARIO_RUN_COMPLETED',
    jsonb_build_object('run_id', p_run_id, 'run_status', 'FAILED', 'scenario_code', v_run.scenario_code),
    'SCENARIO_RUN_COMPLETED:' || p_run_id::text);
END;
$$;

-- ============================================================================
-- PHASE 6 -- SCENARIO EXECUTION [Trace: Sec.1.2 duty 2, Sec.2.2]
-- ============================================================================
CREATE FUNCTION trustride.fn_model_scenario_run_execute(p_run_id UUID)
RETURNS trustride.model_run_status_enum
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_run           RECORD;
  v_registry      RECORD;
  v_macro_domain  TEXT;
  v_service_code  TEXT;
  v_asset_class   TEXT;
  v_asset_class_b TEXT;
  v_jurisdiction  TEXT;
  v_new_rate      NUMERIC;
  v_registry_row  RECORD;
  v_registry_row_b RECORD;
  v_rate_row      RECORD;
  v_rate_row_b    RECORD;
  v_baseline      NUMERIC;
  v_variance_pct  NUMERIC;
  v_projected     NUMERIC;
  v_sample_size   INTEGER;
  v_final_status  trustride.model_run_status_enum;
  v_test_pct      NUMERIC;
  v_seq           SMALLINT;
BEGIN
  SELECT r.*, sr.scenario_code, sr.scenario_type INTO v_run
  FROM trustride.model_scenario_run r
  JOIN trustride.model_scenario_registry sr ON sr.scenario_registry_id = r.scenario_registry_id
  WHERE r.run_id = p_run_id;

  IF v_run IS NULL THEN
    RAISE EXCEPTION 'fn_model_scenario_run_execute: no such run %', p_run_id;
  END IF;

  UPDATE trustride.model_scenario_run SET run_status = 'RUNNING', started_at = now() WHERE run_id = p_run_id;
  PERFORM trustride.fn_model_decision_log_write(p_run_id, 'RUN_STARTED', format('Scenario %s started', v_run.scenario_code));

  IF v_run.scenario_code = 'PRICING_CHANGE' THEN
    v_macro_domain := trustride.fn_model_input_parameter_text(p_run_id, 'macro_domain');
    v_service_code := trustride.fn_model_input_parameter_text(p_run_id, 'service_code');
    v_asset_class  := trustride.fn_model_input_parameter_text(p_run_id, 'asset_class');
    v_jurisdiction := trustride.fn_model_input_parameter_text(p_run_id, 'jurisdiction');
    v_new_rate     := trustride.fn_model_input_parameter_numeric(p_run_id, 'direct_per_km_rate_kes');

    SELECT reg.*, rt.direct_per_km_rate_kes, rt.rate_id INTO v_registry_row
    FROM trustride.cost_registry reg JOIN trustride.cost_rate rt ON rt.rate_id = reg.cost_rate_id
    WHERE reg.macro_domain = v_macro_domain AND reg.service_code = v_service_code
      AND reg.asset_class::text = v_asset_class AND reg.jurisdiction::text = v_jurisdiction AND reg.status = 'ACTIVE';

    IF v_registry_row IS NULL OR v_new_rate IS NULL THEN
      PERFORM trustride.fn_model_scenario_run_fail(p_run_id, 'MISSING_INPUT: no matching ACTIVE cost_registry row, or direct_per_km_rate_kes not supplied');
      RETURN 'FAILED';
    END IF;

    PERFORM trustride.fn_model_input_snapshot_write(p_run_id, 'TRS026_ENG005_COST', 'cost_registry', v_registry_row.registry_id, to_jsonb(v_registry_row));

    SELECT sum((output_snapshot->>'computed_total_fare_kes')::numeric), count(*)
    INTO v_baseline, v_sample_size
    FROM trustride.cost_record
    WHERE registry_id = v_registry_row.registry_id AND execution_outcome = 'CALCULATED'
      AND executed_at >= now() - INTERVAL '30 days';

    PERFORM trustride.fn_model_input_snapshot_write(p_run_id, 'TRS026_ENG005_COST', 'cost_record', NULL,
      jsonb_build_object('registry_id', v_registry_row.registry_id, 'sample_size', v_sample_size, 'baseline_revenue_kes', v_baseline));

    v_baseline := coalesce(v_baseline, 0);
    v_variance_pct := round(100.0 * (v_new_rate - v_registry_row.direct_per_km_rate_kes) / NULLIF(v_registry_row.direct_per_km_rate_kes, 0), 4);
    v_projected := round(v_baseline * (1 + coalesce(v_variance_pct, 0) / 100.0), 4);

    INSERT INTO trustride.model_projected_outcome (run_id, outcome_metric, baseline_value, projected_value, variance_pct)
    VALUES (p_run_id, 'trailing_30d_revenue_kes', v_baseline, v_projected, v_variance_pct);

    INSERT INTO trustride.model_risk_indicator (run_id, risk_code, risk_description, severity)
    VALUES (p_run_id, 'DEMAND_ELASTICITY',
      format('A %s%% change in direct_per_km_rate_kes may soften order volume by an unmeasured amount; this projection assumes constant demand.', v_variance_pct),
      CASE WHEN abs(coalesce(v_variance_pct,0)) > 15 THEN 'HIGH' WHEN abs(coalesce(v_variance_pct,0)) > 5 THEN 'MEDIUM' ELSE 'LOW' END::trustride.model_risk_severity_enum);

    INSERT INTO trustride.model_actionable_insight (run_id, insight_text, confidence_score)
    VALUES (p_run_id,
      format('Projected trailing-30-day revenue moves from %s to %s KES (%s%%) on a rate change from %s to %s KES/km, holding demand constant. Sample size: %s calculations.',
        v_baseline, v_projected, v_variance_pct, v_registry_row.direct_per_km_rate_kes, v_new_rate, v_sample_size),
      LEAST(90, 30 + v_sample_size * 5));

    v_seq := 0;
    FOR v_test_pct IN SELECT unnest(ARRAY[-10,-5,0,5,10]) LOOP
      v_seq := v_seq + 1;
      INSERT INTO trustride.model_sensitivity_analysis (run_id, varied_parameter_name, parameter_test_value, resulting_outcome_metric, resulting_value, sequence_no)
      VALUES (p_run_id, 'direct_per_km_rate_kes',
        to_jsonb(round(v_registry_row.direct_per_km_rate_kes * (1 + v_test_pct / 100.0), 4)),
        'trailing_30d_revenue_kes', round(v_baseline * (1 + v_test_pct / 100.0), 4), v_seq);
    END LOOP;

    v_final_status := 'COMPLETED';

  ELSIF v_run.scenario_code = 'COST_VS_CAPACITY' THEN
    -- Each asset class is registered under its own service_code in this
    -- rebuild's real Cost data (e.g. TRANSPORT-BODA-STANDARD/BODA_BODA vs
    -- TRANSPORT-SEDAN-STANDARD/SEDAN) -- a single shared service_code
    -- parameter cannot address two different asset classes at once.
    v_macro_domain   := trustride.fn_model_input_parameter_text(p_run_id, 'macro_domain');
    v_jurisdiction   := trustride.fn_model_input_parameter_text(p_run_id, 'jurisdiction');
    v_service_code   := trustride.fn_model_input_parameter_text(p_run_id, 'service_code_a');
    v_asset_class    := trustride.fn_model_input_parameter_text(p_run_id, 'asset_class_a');
    v_asset_class_b  := trustride.fn_model_input_parameter_text(p_run_id, 'asset_class_b');

    SELECT reg.*, rt.direct_per_km_rate_kes, rt.base_dispatch_fee_kes INTO v_registry_row
    FROM trustride.cost_registry reg JOIN trustride.cost_rate rt ON rt.rate_id = reg.cost_rate_id
    WHERE reg.macro_domain = v_macro_domain AND reg.service_code = v_service_code
      AND reg.asset_class::text = v_asset_class AND reg.jurisdiction::text = v_jurisdiction AND reg.status = 'ACTIVE';
    SELECT reg.*, rt.direct_per_km_rate_kes, rt.base_dispatch_fee_kes INTO v_registry_row_b
    FROM trustride.cost_registry reg JOIN trustride.cost_rate rt ON rt.rate_id = reg.cost_rate_id
    WHERE reg.macro_domain = v_macro_domain AND reg.service_code = trustride.fn_model_input_parameter_text(p_run_id, 'service_code_b')
      AND reg.asset_class::text = v_asset_class_b AND reg.jurisdiction::text = v_jurisdiction AND reg.status = 'ACTIVE';

    IF v_registry_row IS NULL OR v_registry_row_b IS NULL THEN
      PERFORM trustride.fn_model_scenario_run_fail(p_run_id, 'MISSING_INPUT: no matching ACTIVE cost_registry row for one or both asset classes');
      RETURN 'FAILED';
    END IF;

    PERFORM trustride.fn_model_input_snapshot_write(p_run_id, 'TRS026_ENG005_COST', 'cost_registry', v_registry_row.registry_id, to_jsonb(v_registry_row));
    PERFORM trustride.fn_model_input_snapshot_write(p_run_id, 'TRS026_ENG005_COST', 'cost_registry', v_registry_row_b.registry_id, to_jsonb(v_registry_row_b));

    INSERT INTO trustride.model_projected_outcome (run_id, outcome_metric, baseline_value, projected_value, variance_pct) VALUES
      (p_run_id, format('%s_direct_per_km_rate_kes', v_asset_class), NULL, v_registry_row.direct_per_km_rate_kes, NULL),
      (p_run_id, format('%s_direct_per_km_rate_kes', v_asset_class_b), NULL, v_registry_row_b.direct_per_km_rate_kes, NULL);

    INSERT INTO trustride.model_risk_indicator (run_id, risk_code, risk_description, severity)
    VALUES (p_run_id, 'CAPACITY_COST_DIFFERENTIAL',
      format('%s costs %s KES/km vs %s at %s KES/km -- a %s%% differential.', v_asset_class, v_registry_row.direct_per_km_rate_kes,
        v_asset_class_b, v_registry_row_b.direct_per_km_rate_kes,
        round(100.0 * abs(v_registry_row.direct_per_km_rate_kes - v_registry_row_b.direct_per_km_rate_kes) / NULLIF(LEAST(v_registry_row.direct_per_km_rate_kes, v_registry_row_b.direct_per_km_rate_kes), 0), 2)),
      'LOW');

    INSERT INTO trustride.model_actionable_insight (run_id, insight_text, confidence_score)
    VALUES (p_run_id, format('%s is the lower per-km cost basis; a capacity-mix decision should weigh this against demand coverage each asset class actually serves.',
      CASE WHEN v_registry_row.direct_per_km_rate_kes <= v_registry_row_b.direct_per_km_rate_kes THEN v_asset_class ELSE v_asset_class_b END), 75);

    v_final_status := 'COMPLETED';

  ELSE
    PERFORM trustride.fn_model_scenario_run_fail(p_run_id,
      format('NO_LAWFUL_READ_GRANT: scenario_code=%s requires data no engine has granted Engine 10 read access to yet (Sec.1.3/1.4.4)', v_run.scenario_code));
    RETURN 'FAILED';
  END IF;

  UPDATE trustride.model_scenario_run SET run_status = v_final_status, completed_at = now() WHERE run_id = p_run_id;
  PERFORM trustride.fn_model_decision_log_write(p_run_id, 'RUN_COMPLETED', format('Scenario %s finished with status %s', v_run.scenario_code, v_final_status));

  INSERT INTO trustride.model_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v_run.correlation_id, 'TRS026_ENG011_PRESENT', 'SCENARIO_RUN_COMPLETED',
    jsonb_build_object('run_id', p_run_id, 'run_status', v_final_status, 'scenario_code', v_run.scenario_code),
    'SCENARIO_RUN_COMPLETED:' || p_run_id::text);

  RETURN v_final_status;
END;
$$;

-- ============================================================================
-- PHASE 7 -- COMPARE + INBOUND SIGNAL
-- ============================================================================
CREATE FUNCTION trustride.fn_model_run_compare(p_base_run_id UUID, p_compared_run_id UUID, p_comparison_metric TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
DECLARE
  v_base_value NUMERIC;
  v_compared_value NUMERIC;
  v_id UUID;
BEGIN
  SELECT projected_value INTO v_base_value FROM trustride.model_projected_outcome
  WHERE run_id = p_base_run_id AND outcome_metric = p_comparison_metric ORDER BY generated_at DESC LIMIT 1;
  SELECT projected_value INTO v_compared_value FROM trustride.model_projected_outcome
  WHERE run_id = p_compared_run_id AND outcome_metric = p_comparison_metric ORDER BY generated_at DESC LIMIT 1;

  IF v_base_value IS NULL OR v_compared_value IS NULL THEN
    RAISE EXCEPTION 'fn_model_run_compare: metric % not found on both runs (base=%, compared=%)', p_comparison_metric, v_base_value, v_compared_value;
  END IF;

  INSERT INTO trustride.model_comparative_view (base_run_id, compared_run_id, comparison_metric, base_value, compared_value, delta)
  VALUES (p_base_run_id, p_compared_run_id, p_comparison_metric, v_base_value, v_compared_value, v_compared_value - v_base_value)
  RETURNING comparative_view_id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE FUNCTION trustride.fn_model_scenario_run_request_accept(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp AS $$
DECLARE
  v_signal_type TEXT;
  v_payload JSONB;
  v_correlation_id UUID;
  v_registry_id UUID;
  v_run_id UUID;
  v_param RECORD;
  v_result TEXT;
BEGIN
  SELECT signal_type, payload_in, correlation_id INTO v_signal_type, v_payload, v_correlation_id
  FROM trustride.model_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_signal_type IS NULL THEN
    RAISE EXCEPTION 'fn_model_scenario_run_request_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  IF v_signal_type <> 'SCENARIO_RUN_REQUESTED' THEN
    UPDATE trustride.model_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'UNREGISTERED_SIGNAL_TYPE:' || v_signal_type WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END IF;

  SELECT scenario_registry_id INTO v_registry_id FROM trustride.model_scenario_registry
  WHERE scenario_code = v_payload->>'scenario_code' AND active = TRUE;

  IF v_registry_id IS NULL THEN
    UPDATE trustride.model_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'UNKNOWN_SCENARIO_CODE:' || (v_payload->>'scenario_code') WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END IF;

  INSERT INTO trustride.model_scenario_run (scenario_registry_id, requested_by, correlation_id, run_label)
  VALUES (v_registry_id, (v_payload->>'requested_by')::uuid, v_correlation_id, v_payload->>'run_label')
  RETURNING run_id INTO v_run_id;

  FOR v_param IN SELECT * FROM jsonb_array_elements(coalesce(v_payload->'parameters', '[]'::jsonb))
  LOOP
    INSERT INTO trustride.model_input_parameter (run_id, parameter_name, parameter_value, parameter_source)
    VALUES (v_run_id, v_param.value->>'parameter_name', v_param.value->'parameter_value',
      (v_param.value->>'parameter_source')::trustride.model_input_source_enum);
  END LOOP;

  PERFORM trustride.fn_model_scenario_run_execute(v_run_id);

  v_result := 'ACCEPTED';
  UPDATE trustride.model_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('run_id', v_run_id) WHERE signal_id = p_signal_id;
  RETURN v_result;
END;
$$;

CREATE FUNCTION trustride.fn_model_inbox_process(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
DECLARE
  v_signal_type TEXT;
  v_result TEXT;
BEGIN
  SELECT signal_type INTO v_signal_type FROM trustride.model_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_signal_type IS NULL THEN
    RAISE EXCEPTION 'fn_model_inbox_process: no RECEIVED signal %', p_signal_id;
  END IF;

  CASE v_signal_type
    WHEN 'SCENARIO_RUN_REQUESTED' THEN v_result := trustride.fn_model_scenario_run_request_accept(p_signal_id);
    ELSE
      UPDATE trustride.model_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'UNREGISTERED_SIGNAL_TYPE:' || v_signal_type WHERE signal_id = p_signal_id;
      v_result := 'REJECTED';
  END CASE;

  RETURN v_result;
END;
$$;

-- ============================================================================
-- PHASE 8 -- EXTEND ORCHESTRATION (add ENG010_MODEL as a real destination)
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
      WHEN 'TRS026_ENG010_MODEL' THEN 'model_event_inbox'
      ELSE NULL
    END,
    rr.target_engine || ':DEFAULT',
    rr.route_id::text, 'ACTIVE', now()
  FROM trustride.routing_rule rr
  WHERE rr.active = TRUE
    AND CASE rr.target_engine
      WHEN 'TRS026_ENG001_FDN' THEN TRUE WHEN 'TRS026_ENG002_RESC' THEN TRUE WHEN 'TRS026_ENG003_SERV' THEN TRUE
      WHEN 'TRS026_ENG004_BUS' THEN TRUE WHEN 'TRS026_ENG005_COST' THEN TRUE WHEN 'TRS026_ENG006_INTG' THEN TRUE
      WHEN 'TRS026_ENG008_COORD' THEN TRUE WHEN 'TRS026_ENG009_AIADV' THEN TRUE WHEN 'TRS026_ENG010_MODEL' THEN TRUE ELSE FALSE
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
          WHEN 'TRS026_ENG010_MODEL' THEN PERFORM trustride.fn_model_inbox_process(v_row.signal_id);
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
-- PHASE 9 -- GRANTS
-- ============================================================================
GRANT USAGE ON SCHEMA trustride TO trs026_eng010_model_service;

GRANT EXECUTE ON FUNCTION trustride.fn_model_input_parameter_text(UUID, TEXT) TO trs026_eng010_model_service;
GRANT EXECUTE ON FUNCTION trustride.fn_model_input_parameter_numeric(UUID, TEXT) TO trs026_eng010_model_service;
GRANT EXECUTE ON FUNCTION trustride.fn_model_input_snapshot_write(UUID, TEXT, TEXT, UUID, JSONB) TO trs026_eng010_model_service;
GRANT EXECUTE ON FUNCTION trustride.fn_model_decision_log_write(UUID, TEXT, TEXT) TO trs026_eng010_model_service;
GRANT EXECUTE ON FUNCTION trustride.fn_model_scenario_run_fail(UUID, TEXT) TO trs026_eng010_model_service;
GRANT EXECUTE ON FUNCTION trustride.fn_model_scenario_run_execute(UUID) TO trs026_eng010_model_service;
GRANT EXECUTE ON FUNCTION trustride.fn_model_run_compare(UUID, UUID, TEXT) TO trustride_authenticated, trs026_eng010_model_service;
GRANT EXECUTE ON FUNCTION trustride.fn_model_scenario_run_request_accept(UUID) TO trs026_eng010_model_service;
GRANT EXECUTE ON FUNCTION trustride.fn_model_inbox_process(UUID) TO trs026_eng010_model_service, trs026_eng007_orch_service;

-- ============================================================================
-- PHASE 10 -- OUTBOX REGISTRATION
-- ============================================================================
INSERT INTO trustride.orch_outbox_registry (engine_code, outbox_table_name) VALUES ('TRS026_ENG010_MODEL', 'model_event_outbox');

-- ============================================================================
-- PHASE 11 -- ENGINE REGISTRY
-- ============================================================================
UPDATE trustride.engine_registry SET status = 'INSTALLED', engine_version = '1.0.0' WHERE engine_code = 'TRS026_ENG010_MODEL';

-- ============================================================================
-- PHASE 12 -- VALIDATION
-- ============================================================================
DO $$
DECLARE
  v_table_count INTEGER;
  v_registry_count INTEGER;
  v_status TEXT;
BEGIN
  SELECT count(*) INTO v_table_count FROM information_schema.tables WHERE table_schema = 'trustride' AND table_name LIKE 'model_%';
  IF v_table_count <> 13 THEN
    RAISE EXCEPTION 'ENGINE 10 VALIDATION FAILED: expected 13 model_* tables, found %', v_table_count;
  END IF;

  SELECT count(*) INTO v_registry_count FROM trustride.model_scenario_registry WHERE active = TRUE;
  IF v_registry_count <> 5 THEN
    RAISE EXCEPTION 'ENGINE 10 VALIDATION FAILED: expected 5 registered scenario templates, found %', v_registry_count;
  END IF;

  SELECT status INTO v_status FROM trustride.engine_registry WHERE engine_code = 'TRS026_ENG010_MODEL';
  IF v_status <> 'INSTALLED' THEN
    RAISE EXCEPTION 'ENGINE 10 VALIDATION FAILED: engine_registry status is %, expected INSTALLED', v_status;
  END IF;

  RAISE NOTICE 'ENGINE 10 (SCENARIO MODELLING) INSTALLATION VALIDATED: 13 tables, 5 registered templates, engine_registry INSTALLED.';
END;
$$;
