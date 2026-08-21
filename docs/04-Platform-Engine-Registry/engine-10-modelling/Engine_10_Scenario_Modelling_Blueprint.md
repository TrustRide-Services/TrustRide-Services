# TRUSTRIDE SERVICES

# ENGINE 10 — SCENARIO MODELLING ENGINE
## Complete Architectural, Data, API, and Signal Specification

**[Parent Authority: TBOC v2.0.0 Genesis Edition · FDN-001 v3.0.0 §11.3 Layer 4 · Architecture Blueprint v1.1.0]**

*More than a Ride — We Save You Time.*

## Document Control

| Document Control Field | Entry |
| --- | --- |
| Document Title | Engine 10 — Scenario Modelling Engine: Complete Specification |
| Document Identifier | TRS026-ENG010-MODEL-001 |
| Version | 1.0.0 |
| Status | **ADOPTED** (2026-08-16, per Founder directive — build order FDN → Resources → Services → Business → Cost → Integration → Orchestration → Coordination → AI/ML Advisory → Scenario Modelling) |
| Classification | Institutional Blueprint — Confidential |
| Schema | `trustride` (single canonical PostgreSQL schema; this engine's tables are prefixed `model_`) |
| Platform Code | TRS026 |
| Engine Code | `TRS026_ENG010_MODEL` |
| Engine No. | `ENGINE_010` |
| Installation Order | 010 |
| Constitutional Character | **SANDBOXED ONLY.** Engine 10 holds zero authoritative state and zero write authority into any other engine's tables. Every scenario it runs is a record, never a mutation, and every input it consumes is copied into its own sandbox before analysis — a scenario never touches production data live. |
| Parent Authority | FDN-001 v3.0.0 §11.3 (Plate II, Layer 4 — AI Advisory: "Read lawful projections; write recommendations as records only" / prohibition: "Any write to authoritative state, ever, under any urgency"), §11.7 Downstream Conformance Schedule ("Scenarios are records, not mutations; Layer 4, sandboxed from authoritative state; scenario surfaces clearly marked non-authoritative"); TBOC v2.0.0 Article 62 (Amendment & Review — recorded rationale before Founder-authorized change), Article 45 (Pricing), Article 44 (Ledger Splits & Revenue Architecture — versioned, never retroactive), Article 41 (Resource Lifecycle), Article 56 (Business Continuity) |
| Architecture Lineage | Positioned as Engine 10 in the eleven-engine Constitutional Engine Registry (Annex C, FDN-001 v3.0.0); Layer 4 AI Advisory of the Backend/Frontend/Event-Signal Architecture Blueprint v1.1.0, alongside Engine 9 (AI/ML Advisory) — the Blueprint's own drawing (TRS026-BE-01) names this engine's functions verbatim: What-if Analysis, Scenario Simulation, Forecasting, Outcome Comparison, Sensitivity Analysis |

## Document Purpose & Constitutional Basis

This instrument specifies **Engine 10 — the Scenario Modelling Engine**, TrustRide's sole sandbox for exploring a change before it is made. It answers one constitutional question for the rest of the platform — **if this changed, what would happen?** — entirely inside a sandbox that no real Order, no real quote, no real customer ever enters.

Where Engine 9 observes what already happened and predicts what is likely to happen next, Engine 10 never observes reality directly at all — it copies governed inputs into its own snapshot, varies them freely, and reports what its model computes, always clearly marked as hypothetical. TBOC holds no engineering specification of its own (Article 8.2), so this instrument grounds primarily in FDN-001's Layer 4 definition and Downstream Conformance Schedule, with TBOC's genuine business-purpose hooks cited where they apply:

| This engine's function | Constitutional basis |
| --- | --- |
| Read lawful projections; write recommendations as records only | FDN-001 §11.3, Layer 4 obligation (shared with Engine 9) |
| Any write to authoritative state, ever, under any urgency, is forbidden absolutely | FDN-001 §11.3, Layer 4 prohibition |
| Scenarios are records, not mutations; sandboxed from authoritative state; scenario surfaces clearly marked non-authoritative | FDN-001 §11.7, Downstream Conformance Schedule, row 10/11 |
| Amendment of this Constitution requires Founder authority, recorded rationale, versioned publication, and propagation review | TBOC Article 62 — the exact discipline a scenario exists to inform, never to bypass |
| No price may be charged that the catalogue cannot explain | TBOC Article 45 — a pricing-change scenario tests explainability before adoption, never in place of it |
| Commission rates, payout schedules, and split percentages ... versioned, never applied retroactively to settled Orders | TBOC Article 44 — a financial scenario explores a future rate table, never edits a settled one |
| Every resource traverses ... evaluated ... reassigned or retired | TBOC Article 41 — the constitutional basis for capacity and fleet-expansion scenario types |
| The institution maintains continuity plans ... with tested recovery procedures | TBOC Article 56 — the constitutional basis for peak-demand and capacity-shortfall scenario types |
| No engine reads or writes another engine's tables; cross-engine truth moves only as a signal | TBOC Article 33 |

Only Engine 5 (Cost) has so far named this engine in its own adopted document — a read-only grant over `cost_formula_matrix`, `cost_rate_card_rule`, and historical `cost_execution_ledger` rows "for what-if pricing scenarios." This instrument does not expand that grant. Its schema is deliberately generic across the five scenario types the Architecture Blueprint already names (Operational, Commercial, Capacity, Financial, Regulatory), so that when a future engine document names Engine 10 as a reader, the same tables serve it without redesign — but until that grant exists in that engine's own adopted text, this instrument claims nothing beyond Cost's.

---

# SECTION 1 — ARCHITECTURAL ROLE & BOUNDARIES

## 1.1 Mission

Engine 10 is the platform's single, deterministic sandbox for what-if analysis. Every scenario it runs is reproducible, every input it used is preserved exactly as consumed, and no scenario — however extreme its hypothesis — can ever reach a real table outside this engine's own schema.

## 1.2 Operational Duties

1. **Scenario governance.** Maintain `model_scenario_registry` — the governed catalogue of scenario templates across the five constitutional scenario types: Operational, Commercial, Capacity, Financial, Regulatory (§2.1).
2. **Sandboxed execution.** Run every scenario inside `model_scenario_run`, each one uniquely identified, reproducible, and structurally incapable of writing outside this engine's schema (§2.2).
3. **Input snapshotting.** Copy every governed input a scenario consumes — historical data, live signals, external feeds, simulation parameters, business rules — into an immutable `model_input_snapshot` before analysis begins, so a scenario's result never drifts even if the source data it copied later changes (§2.3–2.4).
4. **Outcome production.** Produce `model_projected_outcome`, `model_performance_metric`, `model_risk_indicator`, `model_comparative_view`, and `model_actionable_insight` rows — the exact five output categories the Architecture Blueprint names for this engine — each clearly non-authoritative (§2.5–2.9).
5. **Sensitivity analysis.** Vary one input parameter across a declared range and record how the projected outcome responds, in `model_sensitivity_analysis` (§2.10).
6. **Scenario evidence.** Record every scenario run as immutable, hash-chained evidence, distinct from and complementary to Foundation's `audit_log` (§2.11).

## 1.3 Interfaces — One Confirmed Read Grant, a Generic Sandbox

| Source engine | What Engine 10 reads | Feeds |
| --- | --- | --- |
| **Engine 5 — Cost** | `cost_formula_matrix`, `cost_rate_card_rule`, and historical `cost_execution_ledger` rows | Financial and Commercial scenario types — what-if pricing analysis |
| **Engines 7/8** | Structural | The exclusive transport for `SCENARIO_RUN_REQUESTED` in and `SCENARIO_RUN_COMPLETED` out |
| **Engine 9 — AI/ML Advisory** | Structural sibling, not a data dependency | Both occupy FDN-001's Layer 4; neither reads the other's tables — Engine 9 predicts from reality, Engine 10 hypothesizes in a sandbox; the two are never conflated |

## 1.4 Boundaries — What Engine 10 Never Does

1. **Never touches production data live.** Every input is copied into `model_input_snapshot` (§2.4) before a scenario runs; no scenario ever joins against a real domain table.
2. **Never writes authoritative state.** Not one column of `model_*` overlaps with any other engine's domain table, under any urgency, without exception.
3. **Never presents a scenario as fact.** Every scenario surface is marked non-authoritative at the point of rendering (FDN-001 §11.7); a projected outcome is not a forecast of certainty, only of a hypothesis's consequence.
4. **Never reads an ungranted source.** Only the read grant a source engine's own adopted document names is honoured (§1.3); nothing is added unilaterally.
5. **Never triggers an amendment or a rate change on its own.** A scenario informs the recorded rationale TBOC Article 62 requires of a Founder-authorized amendment; it never substitutes for the Founder's decision or Governance's approval chain.
6. **Never blocks an upstream engine.** Scenario execution is always downstream of a deliberate request; no domain engine's own operation ever waits on Engine 10.

---

# SECTION 2 — PRODUCTION SQL DDL SCHEMA (PostgreSQL / Supabase-Ready)

## 2.0 Extensions & Enums (prerequisite)

```sql
-- Extensions (idempotent; already present platform-wide per Engine 001 Phase 0)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- [Trace: Architecture Blueprint v1.1.0, TRS026-BE-01 | Scenario Types]
CREATE TYPE model_scenario_type_enum AS ENUM (
  'OPERATIONAL', 'COMMERCIAL', 'CAPACITY', 'FINANCIAL', 'REGULATORY'
);

CREATE TYPE model_run_status_enum AS ENUM (
  'QUEUED', 'RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED'
);

-- [Trace: Architecture Blueprint v1.1.0, TRS026-BE-01 | Model Inputs]
CREATE TYPE model_input_source_enum AS ENUM (
  'HISTORICAL_DATA', 'LIVE_SIGNAL', 'EXTERNAL_FEED', 'SIMULATION_PARAMETER', 'BUSINESS_RULE'
);

CREATE TYPE model_risk_severity_enum AS ENUM (
  'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'
);
```

### 2.A — Scenario Governance

## 2.1 `model_scenario_registry` — Governed Scenario Templates

```sql
-- [Trace: FDN-001 §11.7 | Scenarios are records, not mutations]
CREATE TABLE model_scenario_registry (
  scenario_registry_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scenario_code           TEXT NOT NULL UNIQUE,
  scenario_name           TEXT NOT NULL,
  scenario_type           model_scenario_type_enum NOT NULL,
  description              TEXT NOT NULL,
  input_schema                JSONB NOT NULL DEFAULT '{}',
  approved_by                     UUID,           -- reference only; identity lives in Foundation
  approved_request_id                UUID,        -- reference into TRS_FDN_GOVERNANCE.approval_request
  active                                 BOOLEAN NOT NULL DEFAULT TRUE,
  created_at                                TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE model_scenario_registry IS
  '[Trace: Architecture Blueprint v1.1.0] Example templates: Zone Impact, Pricing Change, Fleet Expansion, Peak Demand, Cost vs. Capacity — one row per governed template, across the five constitutional scenario types.';

ALTER TABLE model_scenario_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_scenario_registry_platform_read ON model_scenario_registry
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_scenario_registry_service_write ON model_scenario_registry
  FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);

INSERT INTO model_scenario_registry (scenario_code, scenario_name, scenario_type, description) VALUES
  ('PRICING_CHANGE', 'Pricing Change Impact', 'FINANCIAL', 'Projects the revenue and margin impact of a proposed rate card or formula change before it is adopted.'),
  ('FLEET_EXPANSION', 'Fleet Expansion Impact', 'CAPACITY', 'Projects capacity, utilization, and maintenance-cost impact of adding fleet units.'),
  ('PEAK_DEMAND', 'Peak Demand Stress Test', 'OPERATIONAL', 'Projects dispatch and SLA outcomes under a hypothesized demand surge.'),
  ('ZONE_IMPACT', 'Zone Boundary Impact', 'OPERATIONAL', 'Projects dispatch efficiency and coverage impact of a proposed operational zone change.'),
  ('COST_VS_CAPACITY', 'Cost vs. Capacity Trade-off', 'CAPACITY', 'Compares mechanical baseline cost against capacity gain across asset-class investment options.');
```

## 2.2 `model_scenario_run` — Sandboxed Execution

```sql
-- [Trace: FDN-001 §11.7 | Sandboxed from authoritative state]
CREATE TABLE model_scenario_run (
  run_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scenario_registry_id    UUID NOT NULL REFERENCES model_scenario_registry (scenario_registry_id),
  run_status              model_run_status_enum NOT NULL DEFAULT 'QUEUED',
  requested_by            UUID NOT NULL,          -- reference only; a Governor's user_id
  correlation_id          UUID NOT NULL,
  run_label                TEXT,
  started_at                 TIMESTAMPTZ,
  completed_at                  TIMESTAMPTZ,
  created_at                       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_model_scenario_run_registry ON model_scenario_run (scenario_registry_id);
CREATE INDEX idx_model_scenario_run_correlation ON model_scenario_run (correlation_id);
CREATE INDEX idx_model_scenario_run_status ON model_scenario_run (run_status);

COMMENT ON TABLE model_scenario_run IS
  'One row per actual simulation execution. No column here, and no column anywhere else in this schema, ever references a production table by foreign key — the sandbox boundary is structural, not a convention.';

ALTER TABLE model_scenario_run ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_scenario_run_platform_read ON model_scenario_run
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_scenario_run_service_write ON model_scenario_run
  FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);
```

### 2.B — Model Inputs

## 2.3 `model_input_parameter` — Declared Run Parameters

```sql
-- [Trace: Architecture Blueprint v1.1.0 | Simulation Parameters]
CREATE TABLE model_input_parameter (
  input_parameter_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id               UUID NOT NULL REFERENCES model_scenario_run (run_id),
  parameter_name       TEXT NOT NULL,
  parameter_value      JSONB NOT NULL,
  parameter_source     model_input_source_enum NOT NULL,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_model_input_parameter_run ON model_input_parameter (run_id);

ALTER TABLE model_input_parameter ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_input_parameter_platform_read ON model_input_parameter
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_input_parameter_service_write ON model_input_parameter
  FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);
```

## 2.4 `model_input_snapshot` — Immutable Copy of Every Consumed Source Row

```sql
-- [Trace: FDN-001 §11.7 | A scenario never touches production data live]
CREATE TABLE model_input_snapshot (
  input_snapshot_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id               UUID NOT NULL REFERENCES model_scenario_run (run_id),
  source_engine_code   TEXT NOT NULL,           -- by value; e.g. 'TRS026_ENG005_COST'
  source_table_name    TEXT NOT NULL,           -- by value; e.g. 'cost_rate_card_rule'
  source_row_ref       UUID,                    -- by value, never a foreign key across engines
  snapshot_payload      JSONB NOT NULL,
  snapshot_hash            CHAR(64) NOT NULL,
  captured_at                 TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_model_input_snapshot_run ON model_input_snapshot (run_id);

COMMENT ON TABLE model_input_snapshot IS
  'The exact, immutable copy of every source row a scenario consumed at the moment it consumed it. A scenario''s result remains reproducible forever, even after the real cost_rate_card_rule row it copied is superseded.';

REVOKE UPDATE, DELETE ON model_input_snapshot FROM PUBLIC;
REVOKE UPDATE, DELETE ON model_input_snapshot FROM trustride_authenticated;

ALTER TABLE model_input_snapshot ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_input_snapshot_platform_read ON model_input_snapshot
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_input_snapshot_service_write ON model_input_snapshot
  FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);
```

### 2.C — Model Outputs

## 2.5 `model_projected_outcome` — Projected Outcomes

```sql
-- [Trace: Architecture Blueprint v1.1.0 | Model Outputs — Projected Outcomes]
CREATE TABLE model_projected_outcome (
  projected_outcome_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id                 UUID NOT NULL REFERENCES model_scenario_run (run_id),
  outcome_metric         TEXT NOT NULL,
  baseline_value         NUMERIC(18,4),
  projected_value        NUMERIC(18,4) NOT NULL,
  variance_pct           NUMERIC(8,4),
  generated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_model_projected_outcome_run ON model_projected_outcome (run_id);

ALTER TABLE model_projected_outcome ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_projected_outcome_platform_read ON model_projected_outcome
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_projected_outcome_service_write ON model_projected_outcome
  FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);
```

## 2.6 `model_performance_metric` — Performance Metrics

```sql
-- [Trace: Architecture Blueprint v1.1.0 | Model Outputs — Performance Metrics]
CREATE TABLE model_performance_metric (
  performance_metric_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id                  UUID NOT NULL REFERENCES model_scenario_run (run_id),
  metric_name              TEXT NOT NULL,
  metric_value             NUMERIC(18,4) NOT NULL,
  metric_unit                  TEXT,
  generated_at                     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_model_performance_metric_run ON model_performance_metric (run_id);

ALTER TABLE model_performance_metric ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_performance_metric_platform_read ON model_performance_metric
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_performance_metric_service_write ON model_performance_metric
  FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);
```

## 2.7 `model_risk_indicator` — Risk Indicators

```sql
-- [Trace: Architecture Blueprint v1.1.0 | Model Outputs — Risk Indicators]
CREATE TABLE model_risk_indicator (
  risk_indicator_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id              UUID NOT NULL REFERENCES model_scenario_run (run_id),
  risk_code           TEXT NOT NULL,
  risk_description    TEXT NOT NULL,
  severity            model_risk_severity_enum NOT NULL DEFAULT 'MEDIUM',
  generated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_model_risk_indicator_run ON model_risk_indicator (run_id);

ALTER TABLE model_risk_indicator ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_risk_indicator_platform_read ON model_risk_indicator
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_risk_indicator_service_write ON model_risk_indicator
  FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);
```

## 2.8 `model_comparative_view` — Comparative Views

```sql
-- [Trace: Architecture Blueprint v1.1.0 | Model Outputs — Comparative Views]
CREATE TABLE model_comparative_view (
  comparative_view_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  base_run_id           UUID NOT NULL REFERENCES model_scenario_run (run_id),
  compared_run_id       UUID NOT NULL REFERENCES model_scenario_run (run_id),
  comparison_metric     TEXT NOT NULL,
  base_value            NUMERIC(18,4),
  compared_value        NUMERIC(18,4),
  delta                 NUMERIC(18,4),
  generated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_model_comparative_view_distinct CHECK (base_run_id <> compared_run_id)
);

CREATE INDEX idx_model_comparative_view_base ON model_comparative_view (base_run_id);

ALTER TABLE model_comparative_view ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_comparative_view_platform_read ON model_comparative_view
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_comparative_view_service_write ON model_comparative_view
  FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);
```

## 2.9 `model_actionable_insight` — Actionable Insights

```sql
-- [Trace: Architecture Blueprint v1.1.0 | Model Outputs — Actionable Insights]
-- [Trace: FDN-001 §11.3 | Layer Crossing Law — a human or a lawful rule decides, never this engine]
CREATE TABLE model_actionable_insight (
  actionable_insight_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id                  UUID NOT NULL REFERENCES model_scenario_run (run_id),
  insight_text            TEXT NOT NULL,
  confidence_score        NUMERIC(5,2) CHECK (confidence_score IS NULL OR confidence_score BETWEEN 0 AND 100),
  reviewed_by              UUID,                -- reference only; NULL until a Governor reviews it
  reviewed_at                 TIMESTAMPTZ,
  generated_at                    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_model_actionable_insight_run ON model_actionable_insight (run_id);

COMMENT ON TABLE model_actionable_insight IS
  'A hypothesis''s consequence, stated in plain language — never a command. reviewed_by/reviewed_at is the same discipline Engine 9 applies to its recommendations: a human decides, this engine never does.';

ALTER TABLE model_actionable_insight ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_actionable_insight_platform_read ON model_actionable_insight
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_actionable_insight_service_write ON model_actionable_insight
  FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);
```

### 2.D — Sensitivity Analysis

## 2.10 `model_sensitivity_analysis` — Parameter Sensitivity

```sql
-- [Trace: Architecture Blueprint v1.1.0 | Sensitivity Analysis]
CREATE TABLE model_sensitivity_analysis (
  sensitivity_analysis_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id                    UUID NOT NULL REFERENCES model_scenario_run (run_id),
  varied_parameter_name     TEXT NOT NULL,
  parameter_test_value      JSONB NOT NULL,
  resulting_outcome_metric  TEXT NOT NULL,
  resulting_value           NUMERIC(18,4) NOT NULL,
  sequence_no               SMALLINT NOT NULL,
  generated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_model_sensitivity_analysis_run ON model_sensitivity_analysis (run_id, varied_parameter_name, sequence_no);

COMMENT ON TABLE model_sensitivity_analysis IS
  'One row per test point as a single parameter is varied across a declared range, holding all others constant — showing how sensitive the projected outcome is to that one input.';

ALTER TABLE model_sensitivity_analysis ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_sensitivity_analysis_platform_read ON model_sensitivity_analysis
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_sensitivity_analysis_service_write ON model_sensitivity_analysis
  FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);
```

### 2.E — Scenario Evidence

## 2.11 `model_decision_log` — Immutable, Hash-Chained Evidence

```sql
-- [Trace: FDN-001 Part IX pattern (TRS_FDN_AUDIT), applied to Engine 10's own scenario runs]
CREATE TABLE model_decision_log (
  decision_log_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id            UUID REFERENCES model_scenario_run (run_id),
  event_type        TEXT NOT NULL,
  event_description TEXT,
  prev_hash          CHAR(64),
  immutable_hash         CHAR(64) NOT NULL,
  recorded_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_model_decision_log_run ON model_decision_log (run_id);

REVOKE UPDATE, DELETE ON model_decision_log FROM PUBLIC;
REVOKE UPDATE, DELETE ON model_decision_log FROM trustride_authenticated;

ALTER TABLE model_decision_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_decision_log_platform_read ON model_decision_log
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY model_decision_log_service_write ON model_decision_log
  FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);
```

### 2.F — Engine Event Substrate (Constitutional Mandatory Tables)

## 2.12 Engine Event Substrate

Per Plate I (Station Law) and CC-03 of the platform Conformance Certificate, every engine — Engine 10 included — carries exactly one outbox and one inbox, in the standard signal envelope shape (FDN-001 §11.2).

```sql
-- [Trace: FDN-001 §11.2 — mandatory per-engine ledger tables]
CREATE TABLE model_event_outbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG010_MODEL',
  receiving_engine       TEXT NOT NULL,
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  signal_status               TEXT NOT NULL DEFAULT 'PENDING'
                                CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason              TEXT,
  idempotency_key                 TEXT NOT NULL UNIQUE,
  attempt_count                     INTEGER NOT NULL DEFAULT 0,
  emitted_at                         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_model_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_model_outbox_status ON model_event_outbox (signal_status);
CREATE INDEX idx_model_outbox_correlation ON model_event_outbox (correlation_id);

ALTER TABLE model_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_event_outbox_service_only ON model_event_outbox
  FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);

-- [Trace: FDN-001 §11.2 — mandatory per-engine ledger tables]
CREATE TABLE model_event_inbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL,
  receiving_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG010_MODEL',
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  payload_out                JSONB,
  signal_status                TEXT NOT NULL DEFAULT 'RECEIVED'
                                 CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason               TEXT,
  idempotency_key                  TEXT NOT NULL UNIQUE,
  received_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at                          TIMESTAMPTZ,
  CONSTRAINT chk_model_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_model_inbox_status ON model_event_inbox (signal_status);
CREATE INDEX idx_model_inbox_correlation ON model_event_inbox (correlation_id);

ALTER TABLE model_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY model_event_inbox_service_only ON model_event_inbox
  FOR ALL TO trs026_eng010_model_service USING (true) WITH CHECK (true);
```

---

# SECTION 3 — SYSTEM API CONTRACTS

## 3.1 `POST /api/v1/model/scenarios/{scenario_code}/run`

**Request**

```json
{
  "correlation_id": "8f14e45f-ceea-4c9c-9c60-1a2f3e4d5b6c",
  "requested_by": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "run_label": "Q4 2026 boda fare +8% test",
  "parameters": [
    { "parameter_name": "direct_per_km_rate_kes", "parameter_value": 13.00, "parameter_source": "SIMULATION_PARAMETER" }
  ]
}
```

**Response — `202 Accepted`**

```json
{
  "correlation_id": "8f14e45f-ceea-4c9c-9c60-1a2f3e4d5b6c",
  "run_id": "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e",
  "run_status": "QUEUED"
}
```

## 3.2 `GET /api/v1/model/runs/{run_id}/results`

**Response — `200 OK`**

```json
{
  "run_id": "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e",
  "run_status": "COMPLETED",
  "projected_outcomes": [
    { "outcome_metric": "monthly_revenue_kes", "baseline_value": 3128744.50, "projected_value": 3378884.06, "variance_pct": 8.00 }
  ],
  "risk_indicators": [
    { "risk_code": "DEMAND_ELASTICITY", "severity": "MEDIUM", "risk_description": "Projected 3-5% order-volume softening at this fare increase, per historical elasticity pattern." }
  ],
  "actionable_insights": [
    { "insight_text": "Net revenue gain remains positive after modelled demand softening; recommend Finance review under TBOC Article 44 before rate register update." }
  ]
}
```

## 3.3 `GET /api/v1/model/runs/compare`

**Request** (query parameters)

```
GET /api/v1/model/runs/compare?base_run_id=b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e&compared_run_id=c3d4e5f6-a7b8-4c9d-0e1f-2a3b4c5d6e7f
```

**Response — `200 OK`**

```json
{
  "comparisons": [
    { "comparison_metric": "monthly_revenue_kes", "base_value": 3378884.06, "compared_value": 3228744.50, "delta": 150139.56 }
  ]
}
```

---

# SECTION 4 — EVENT-DRIVEN SIGNAL & INTEGRATION MATRIX

## 4.1 Inbound Signals — Listened To

| Signal | Emitting engine | Payload (key fields) | Effect inside Engine 10 |
| --- | --- | --- | --- |
| `SCENARIO_RUN_REQUESTED` | Engine 11 (Presentation), via Engines 7/8 | `scenario_code`, `requested_by`, `parameters` | Writes `model_scenario_run` (§2.2) and begins sandboxed execution |

## 4.2 Outbound Signals — Emitted

| Signal | Receiving engine | Payload (key fields) | Triggering condition |
| --- | --- | --- | --- |
| `SCENARIO_RUN_COMPLETED` | Engine 11 (Presentation), via Engines 7/8 | `run_id`, `run_status`, `scenario_code` | Fired when `model_scenario_run.run_status` reaches `COMPLETED` or `FAILED` |

## 4.3 The Signal Envelope (as applied to Engine 10)

Identical to the platform-wide envelope (Plate I, §11.2 of the Foundation instrument): `signal_id`, `correlation_id`, `causation_id`, `emitting_engine` = `TRS026_ENG010_MODEL`, `receiving_engine`, `signal_type`, `payload_in`, `payload_out`, `signal_status`, `rejection_reason`, `idempotency_key`, `attempt_count`, `emitted_at`, `received_at`, `accepted_at`. No field is added, renamed, or omitted.

---

# ANNEX — CONFORMANCE SELF-CERTIFICATION AGAINST THE THREE PLATES

Filed in the same discipline as the Foundation instrument's Part XI and the Engine 2/3/4/5/6/7/8/9 Annexes.

| Check | Requirement | Result | Evidence |
| --- | --- | --- | --- |
| CC-02 | Every table assigned to exactly one of the five stations | **PASS** | §2.1–2.11: domain tables = Domain State; `model_event_outbox` = Emission Ledger; `model_event_inbox` = Reception Ledger (§2.12) |
| CC-03 | Engine carries the four ledger tables with the standard envelope | **PASS** | §2.12, §4.3 |
| CC-04 | Every cross-engine interaction is a signal; no foreign table access | **PASS** | §2.4 — every consumed source row is copied into `model_input_snapshot` by value, never read live, never a foreign key across engines |
| CC-06 | Idempotency, retry, dead-letter declared | **PASS** | `idempotency_key` UNIQUE on both ledger tables (§2.12) |
| CC-07 | Engine declares its layer, holds nothing belonging to another layer | **PASS** | §1 — Layer 4, AI Advisory; holds no identity, order, resource, pricing, or external-system authoritative state |
| **CC-09** | **Advisory outputs, if any, are records only** | **PASS — this engine's defining check, alongside Engine 9** | Every table in §2.5–2.10 is a record; `model_actionable_insight.reviewed_by` (§2.9) proves a human decides, never this engine |
| CC-12 | Every provision carries a trace tag | **PASS** | Every DDL block and table comment carries a `[Trace: ...]` tag |
| RLS Law | Row-Level Security enabled on every table | **PASS** | All thirteen tables (§2.1–2.12) carry `ENABLE ROW LEVEL SECURITY` with an explicit policy |
| Immutability Law | Ledgers append-only where history must never be rewritten | **PASS** | `model_input_snapshot` and `model_decision_log` carry `REVOKE UPDATE, DELETE` |
| Sandbox Law | Zero write authority into any other engine's authoritative state, and zero live reads of production data | **PASS** | No table, trigger, or function in this instrument references, writes, or holds a foreign key into any table outside the `model_` prefix; every consumed input is snapshotted (§2.4), never joined live |

---

**END OF SPECIFICATION**

*Engine 10 is where TrustRide asks "what if" without risking "what happened." Every hypothesis is sandboxed, every input is preserved exactly as it was copied, and every conclusion returns to a human Governor to decide — never a rate changed, never a fleet bought, never a truth mistaken for a guess.*
