# TRUSTRIDE SERVICES

# ENGINE 9 — AI/ML ADVISORY ENGINE
## Complete Architectural, Data, API, and Signal Specification

**[Parent Authority: TBOC v2.0.0 Genesis Edition · FDN-001 v3.0.0 §11.3 Layer 4]**

*More than a Ride — We Save You Time.*

## Document Control

| Document Control Field | Entry |
| --- | --- |
| Document Title | Engine 9 — AI/ML Advisory Engine: Complete Specification |
| Document Identifier | TRS026-ENG009-AIADV-001 |
| Version | 1.0.0 |
| Status | **ADOPTED** (2026-08-16, per Founder directive — build order FDN → Resources → Services → Business → Cost → Integration → Orchestration → Coordination → AI/ML Advisory) |
| Classification | Institutional Blueprint — Confidential |
| Schema | `trustride` (single canonical PostgreSQL schema; this engine's tables are prefixed `advisory_`) |
| Platform Code | TRS026 |
| Engine Code | `TRS026_ENG009_AIADV` |
| Engine No. | `ENGINE_009` |
| Installation Order | 009 |
| Constitutional Character | **ADVISORY ONLY.** Engine 9 holds zero authoritative state and zero write authority into any other engine's tables, under any urgency, without exception. Every output of this engine is a record, never a mutation. |
| Parent Authority | FDN-001 v3.0.0 §11.3 (Plate II, Layer 4 — AI Advisory: "Read lawful projections; write recommendations as records only" / prohibition: "Any write to authoritative state, ever, under any urgency"), §11.3 Layer Crossing Law ("Layer 4 → any: Advisory record referenced by correlation_id; a human or a lawful rule decides"); TBOC v2.0.0 Article 49.4 (financial position visible in the Sovereign Executive Console), Article 50 (The Quality Doctrine — continuous improvement), Article 55.3 (incident patterns feed risk review), Article 41 (Resource Lifecycle — the "evaluated" stage) |
| Architecture Lineage | Positioned as Engine 9 in the eleven-engine Constitutional Engine Registry (Annex C, FDN-001 v3.0.0); Layer 4 AI Advisory of the Backend/Frontend/Event-Signal Architecture Blueprint v1.1.0, alongside Engine 10 (Scenario Modelling) |

## Document Purpose & Constitutional Basis

This instrument specifies **Engine 9 — the AI/ML Advisory Engine**, TrustRide's sole source of predictive and pattern-based recommendation. It answers one constitutional question for the rest of the platform — **what does the data suggest, and to whom is that suggestion addressed?** — and it answers *only* that question. It never answers "what happens next," because that decision belongs to a human Governor or to a separately governed rule, never to this engine.

TBOC holds almost nothing on AI or advisory directly, and deliberately so (Article 8.2, the Zero-Pollution Rule: TBOC "contains no code, no schema syntax... no engineering specification"). Engine 9 therefore grounds primarily in FDN-001's own Plate II Layer 4 definition — itself lawfully descended from TBOC — with TBOC's own business-purpose hooks cited where they genuinely exist:

| This engine's function | Constitutional basis |
| --- | --- |
| Read lawful projections; write recommendations as records only | FDN-001 §11.3, Layer 4 obligation |
| Any write to authoritative state, ever, under any urgency, is forbidden absolutely | FDN-001 §11.3, Layer 4 prohibition |
| Advisory record referenced by `correlation_id`; a human or a lawful rule decides | FDN-001 §11.3, Layer Crossing Law "Layer 4 → any" |
| The financial position of every domain is visible in the Sovereign Executive Console | TBOC Article 49.4 |
| Quality is constitutional, not aspirational — every measurement teaches | TBOC Article 50, The Quality Doctrine |
| Incident patterns feed risk review, training content, and this Constitution's continuous improvement mandate | TBOC Article 55.3 |
| Every resource traverses ... evaluated ... reassigned or retired — capacity and fleet-replacement recommendation is this lifecycle stage made computable | TBOC Article 41, Resource Lifecycle |
| No engine reads or writes another engine's tables; cross-engine truth moves only as a signal | TBOC Article 33 |

Six sibling engines already named Engine 9 as their read-only observer before this instrument existed — Resources, Services, Business, Integration, Orchestration, and Coordination each declared a specific, lawful projection Engine 9 may read. This instrument does not invent new access; it formalizes exactly what those six documents already granted, word for word, and adds nothing beyond it.

---

# SECTION 1 — ARCHITECTURAL ROLE & BOUNDARIES

## 1.1 Mission

Engine 9 is the platform's single, deterministic source of predictive and pattern-based recommendation, built entirely from lawful read-only projections of other engines' historical and live state. It produces exactly one kind of output — an advisory record — and never any other kind.

## 1.2 Operational Duties

1. **Model governance.** Maintain `advisory_model_registry` — every deployed forecasting, recommendation, and anomaly-detection model, versioned and approved before use (§2.1–2.2).
2. **Read-source governance.** Maintain `advisory_read_source_registry` — the exhaustive, closed list of every table this engine is lawfully permitted to read, mirroring FDN-001's own projection discipline (C-III-3): a read that touches an unregistered source is non-conformant (§2.3).
3. **Recommendation production.** Generate `advisory_recommendation` rows — capacity-planning, fleet-replacement, service-mix, demand-pattern, demand-forecasting, revenue-pattern, and external-reliability recommendations — each with its supporting evidence and a confidence score, never a claim of certainty (§2.4–2.6).
4. **Forecasting.** Produce `advisory_forecast` rows — demand, capacity, and revenue projections over a declared period, with a declared confidence interval (§2.7).
5. **Anomaly and pattern detection.** Flag `advisory_anomaly_detection` events (including margin breaches reported directly by Cost) and `advisory_pattern_insight` rows for recurring operational patterns (§2.8–2.9).
6. **Outcome tracking.** Record whether a human Governor or a lawful rule accepted, rejected, or ignored each recommendation, in `advisory_recommendation_outcome` — the evidence that this engine influences nothing on its own (§2.6).
7. **Model performance evaluation.** Track `advisory_model_performance` continuously, so a model that degrades is caught and retired, never left silently wrong (§2.10).
8. **Advisory evidence.** Record every recommendation emission as immutable, hash-chained evidence, distinct from and complementary to Foundation's `audit_log` (§2.11).

## 1.3 Interfaces — Read-Only Projections, Named by the Engines That Granted Them

Engine 9 never calls another engine and never reads another engine's table directly at the SQL level — every projection below is delivered as a governed, read-only view or signal-carried snapshot, exactly as each source engine's own document already declares.

| Source engine | What Engine 9 reads | Feeds |
| --- | --- | --- |
| **Engine 2 — Resources** | `resource_availability_ledger` and historical `resource_maintenance_record` rows | Capacity-planning and fleet-replacement recommendations |
| **Engine 3 — Services** | `service_catalogue` and historical listing/lookup volume | Service-mix and demand-pattern recommendations |
| **Engine 4 — Business** | `business_order` and `business_settlement` history | Demand-forecasting and revenue-pattern recommendations |
| **Engine 5 — Cost** | Inbound signal only (not a table projection) — `COST_MARGIN_BREACHED` | Margin-breach anomaly review, routed here and to Engine 8 simultaneously |
| **Engine 6 — Integration** | `integration_circuit_breaker_status` and historical `integration_payment_gateway_transaction` outcomes | External-reliability and payment-success-rate recommendations |
| **Engine 7 — Orchestration** | `orch_queue_metrics`, `orch_routing_metrics`, `orch_capacity_snapshot` | Routing and capacity trend recommendations |
| **Engine 8 — Coordination** | `coord_coordination_health`, `coord_coordination_metrics`, `coord_runtime_alert` | Coordination health trend recommendations |
| **Engines 7/8** | Structural | The exclusive transport for `COST_MARGIN_BREACHED` in and every `ADVISORY_RECOMMENDATION_PUBLISHED` out |

## 1.4 Boundaries — What Engine 9 Never Does

1. **Never writes authoritative state.** Not one column of `advisory_*` overlaps with any other engine's domain table; every write stays inside this engine's own schema, always.
2. **Never decides.** A recommendation is a suggestion with a confidence score, never a command. FDN-001 §11.3 is explicit: a human or a lawful rule decides, never Engine 9.
3. **Never reads an unregistered source.** Every projection this engine consumes is named in `advisory_read_source_registry` (§2.3) before first use — the same discipline FDN-001 §11.4 applies to every rendered screen.
4. **Never claims certainty.** Every `advisory_recommendation` and `advisory_forecast` row carries a confidence score or interval; none is presented as fact.
5. **Never blocks an upstream engine.** Advisory generation is asynchronous and downstream of the event it observes; no domain engine ever waits on Engine 9 to complete an Order, a dispatch, or a settlement.
6. **Never operates under emergency exception.** The Layer 4 prohibition holds "under any urgency" — there is no incident, outage, or deadline that grants this engine write authority it does not otherwise have.

---

# SECTION 2 — PRODUCTION SQL DDL SCHEMA (PostgreSQL / Supabase-Ready)

## 2.0 Extensions & Enums (prerequisite)

```sql
-- Extensions (idempotent; already present platform-wide per Engine 001 Phase 0)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE advisory_model_type_enum AS ENUM (
  'FORECASTING', 'RECOMMENDATION', 'ANOMALY_DETECTION', 'CLASSIFICATION'
);

CREATE TYPE advisory_model_status_enum AS ENUM (
  'DRAFT', 'ACTIVE', 'DEPRECATED', 'RETIRED'
);

CREATE TYPE advisory_recommendation_type_enum AS ENUM (
  'CAPACITY_PLANNING', 'FLEET_REPLACEMENT', 'SERVICE_MIX', 'DEMAND_PATTERN',
  'DEMAND_FORECAST', 'REVENUE_PATTERN', 'EXTERNAL_RELIABILITY', 'PAYMENT_SUCCESS_RATE',
  'ROUTING_CAPACITY_TREND', 'COORDINATION_HEALTH_TREND'
);

CREATE TYPE advisory_outcome_enum AS ENUM (
  'PENDING', 'ACCEPTED', 'REJECTED', 'IGNORED'
);

CREATE TYPE advisory_forecast_type_enum AS ENUM (
  'DEMAND', 'CAPACITY', 'REVENUE'
);

CREATE TYPE advisory_anomaly_type_enum AS ENUM (
  'MARGIN_BREACH', 'PAYMENT_FAILURE_SPIKE', 'DEMAND_SPIKE', 'CAPACITY_SHORTFALL',
  'EXTERNAL_SYSTEM_DEGRADATION', 'COORDINATION_DEGRADATION'
);

CREATE TYPE advisory_severity_enum AS ENUM (
  'LOW', 'MEDIUM', 'HIGH', 'CRITICAL'
);
```

### 2.A — Model Governance

## 2.1 `advisory_model_registry` — Governed Catalogue of Deployed Models

```sql
-- [Trace: FDN-001 §11.3 | Layer 4 obligation — every recommendation traces to a governed model]
CREATE TABLE advisory_model_registry (
  model_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_code               TEXT NOT NULL UNIQUE,
  model_name               TEXT NOT NULL,
  model_type               advisory_model_type_enum NOT NULL,
  model_version             TEXT NOT NULL,
  training_data_description   TEXT NOT NULL,
  approved_by                    UUID,             -- reference only; identity lives in Foundation
  approved_request_id               UUID,           -- reference into TRS_FDN_GOVERNANCE.approval_request
  model_status                         advisory_model_status_enum NOT NULL DEFAULT 'DRAFT',
  deployed_at                             TIMESTAMPTZ,
  created_at                                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (model_code, model_version)
);

COMMENT ON TABLE advisory_model_registry IS
  'No model produces a recommendation without an ACTIVE row here; a model with no approved_request_id is inert, mirroring the Foundation rate-register discipline (TBOC Article 44).';

ALTER TABLE advisory_model_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_model_registry_platform_read ON advisory_model_registry
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_model_registry_service_write ON advisory_model_registry
  FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);
```

## 2.2 `advisory_model_version_history` — Append-Only Version Lineage

```sql
-- [Trace: FDN-001 §11.3 | C-I-5 pattern — correction is a new version, never an edit of history]
CREATE TABLE advisory_model_version_history (
  model_version_history_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id                    UUID NOT NULL REFERENCES advisory_model_registry (model_id),
  previous_version             TEXT,
  new_version                     TEXT NOT NULL,
  change_reason                      TEXT NOT NULL,
  changed_at                            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_advisory_model_version_history_model ON advisory_model_version_history (model_id, changed_at DESC);

REVOKE UPDATE, DELETE ON advisory_model_version_history FROM PUBLIC;
REVOKE UPDATE, DELETE ON advisory_model_version_history FROM trustride_authenticated;

ALTER TABLE advisory_model_version_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_model_version_history_platform_read ON advisory_model_version_history
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_model_version_history_service_write ON advisory_model_version_history
  FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);
```

### 2.B — Read-Source Governance

## 2.3 `advisory_read_source_registry` — The Closed List of Lawful Projections

```sql
-- [Trace: FDN-001 §11.4 C-III-3 | A read that touches an unregistered source is non-conformant]
CREATE TABLE advisory_read_source_registry (
  read_source_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source_engine_code   TEXT NOT NULL,
  source_table_name    TEXT NOT NULL,
  read_purpose         TEXT NOT NULL,
  granted_by_document  TEXT NOT NULL,          -- e.g. 'TRS026-ENG002-RESC-001 §1.3'
  active                BOOLEAN NOT NULL DEFAULT TRUE,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (source_engine_code, source_table_name)
);

COMMENT ON TABLE advisory_read_source_registry IS
  'Closed by design: this table is seeded once from the six sibling engines'' own already-adopted grants and is never expanded without the granting engine''s document naming Engine 9 first.';

ALTER TABLE advisory_read_source_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_read_source_registry_platform_read ON advisory_read_source_registry
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_read_source_registry_service_write ON advisory_read_source_registry
  FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);

INSERT INTO advisory_read_source_registry (source_engine_code, source_table_name, read_purpose, granted_by_document) VALUES
  ('TRS026_ENG002_RESC', 'resource_availability_ledger', 'Capacity-planning recommendations', 'TRS026-ENG002-RESC-001 §1.3'),
  ('TRS026_ENG002_RESC', 'resource_maintenance_record', 'Fleet-replacement recommendations', 'TRS026-ENG002-RESC-001 §1.3'),
  ('TRS026_ENG003_SERV', 'service_catalogue', 'Service-mix recommendations', 'TRS026-ENG003-SERV-001 §1.3'),
  ('TRS026_ENG004_BUS', 'business_order', 'Demand-forecasting recommendations', 'TRS026-ENG004-BUS-001 §1.3'),
  ('TRS026_ENG004_BUS', 'business_settlement', 'Revenue-pattern recommendations', 'TRS026-ENG004-BUS-001 §1.3'),
  ('TRS026_ENG006_INTG', 'integration_circuit_breaker_status', 'External-reliability recommendations', 'TRS026-ENG006-INTG-001 §1.3'),
  ('TRS026_ENG006_INTG', 'integration_payment_gateway_transaction', 'Payment-success-rate recommendations', 'TRS026-ENG006-INTG-001 §1.3'),
  ('TRS026_ENG007_ORCH', 'orch_queue_metrics', 'Routing/capacity trend recommendations', 'TRS026-ENG007-ORCH-001 §1.3'),
  ('TRS026_ENG007_ORCH', 'orch_routing_metrics', 'Routing/capacity trend recommendations', 'TRS026-ENG007-ORCH-001 §1.3'),
  ('TRS026_ENG007_ORCH', 'orch_capacity_snapshot', 'Routing/capacity trend recommendations', 'TRS026-ENG007-ORCH-001 §1.3'),
  ('TRS026_ENG008_COORD', 'coord_coordination_health', 'Coordination health trend recommendations', 'TRS026-ENG008-COORD-001 §1.3'),
  ('TRS026_ENG008_COORD', 'coord_coordination_metrics', 'Coordination health trend recommendations', 'TRS026-ENG008-COORD-001 §1.3'),
  ('TRS026_ENG008_COORD', 'coord_runtime_alert', 'Coordination health trend recommendations', 'TRS026-ENG008-COORD-001 §1.3');
```

### 2.C — Advisory Recommendations

## 2.4 `advisory_recommendation` — The Core Advisory Output

```sql
-- [Trace: FDN-001 §11.3 | Layer 4 — write recommendations as records only]
CREATE TABLE advisory_recommendation (
  recommendation_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id                UUID NOT NULL REFERENCES advisory_model_registry (model_id),
  recommendation_type     advisory_recommendation_type_enum NOT NULL,
  subject_engine_code     TEXT NOT NULL,        -- polymorphic, by value: which engine's domain this concerns
  subject_ref_id          UUID,                 -- polymorphic, by value: the specific row this concerns, where applicable
  correlation_id          UUID NOT NULL,         -- FDN-001 Layer Crossing Law: "referenced by correlation_id"
  recommendation_payload  JSONB NOT NULL,
  confidence_score        NUMERIC(5,2) NOT NULL CHECK (confidence_score BETWEEN 0 AND 100),
  generated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at                  TIMESTAMPTZ
);

CREATE INDEX idx_advisory_recommendation_subject ON advisory_recommendation (subject_engine_code, subject_ref_id);
CREATE INDEX idx_advisory_recommendation_correlation ON advisory_recommendation (correlation_id);
CREATE INDEX idx_advisory_recommendation_type ON advisory_recommendation (recommendation_type);

COMMENT ON TABLE advisory_recommendation IS
  'A suggestion with a confidence score, never a command. This row never causes a mutation anywhere; it is read by a human Governor or a separately governed rule, which decides.';

ALTER TABLE advisory_recommendation ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_recommendation_platform_read ON advisory_recommendation
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_recommendation_service_write ON advisory_recommendation
  FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);
```

## 2.5 `advisory_recommendation_evidence` — Explainability

```sql
-- [Trace: TBOC Article 50 | Every measurement teaches — the recommendation must show its work]
CREATE TABLE advisory_recommendation_evidence (
  evidence_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recommendation_id     UUID NOT NULL REFERENCES advisory_recommendation (recommendation_id),
  feature_name          TEXT NOT NULL,
  feature_value         JSONB NOT NULL,
  feature_weight        NUMERIC(6,4),
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_advisory_recommendation_evidence_recommendation ON advisory_recommendation_evidence (recommendation_id);

COMMENT ON TABLE advisory_recommendation_evidence IS
  'No recommendation is a black box: every contributing feature and its weight is recorded alongside the recommendation it produced.';

ALTER TABLE advisory_recommendation_evidence ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_recommendation_evidence_platform_read ON advisory_recommendation_evidence
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_recommendation_evidence_service_write ON advisory_recommendation_evidence
  FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);
```

## 2.6 `advisory_recommendation_outcome` — Human or Rule Decision Record

```sql
-- [Trace: FDN-001 §11.3 | Layer Crossing Law — a human or a lawful rule decides, never this engine]
CREATE TABLE advisory_recommendation_outcome (
  outcome_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recommendation_id      UUID NOT NULL UNIQUE REFERENCES advisory_recommendation (recommendation_id),
  outcome                advisory_outcome_enum NOT NULL DEFAULT 'PENDING',
  decided_by              UUID,                -- reference only; a Governor's user_id, or NULL if decided by a lawful rule
  decision_rule_ref          TEXT,             -- by value, if a lawful rule rather than a human decided
  decision_reason               TEXT,
  decided_at                       TIMESTAMPTZ
);

COMMENT ON TABLE advisory_recommendation_outcome IS
  'The proof that this engine influences nothing on its own: every recommendation''s eventual fate — accepted, rejected, or ignored — and by whom, is recorded here, never inferred.';

ALTER TABLE advisory_recommendation_outcome ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_recommendation_outcome_platform_read ON advisory_recommendation_outcome
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_recommendation_outcome_service_write ON advisory_recommendation_outcome
  FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);
```

### 2.D — Forecasting

## 2.7 `advisory_forecast` — Demand, Capacity, and Revenue Projections

```sql
-- [Trace: TBOC Article 56 | Business Continuity — foresight without a claim of certainty]
CREATE TABLE advisory_forecast (
  forecast_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id                UUID NOT NULL REFERENCES advisory_model_registry (model_id),
  forecast_type           advisory_forecast_type_enum NOT NULL,
  subject_scope           TEXT NOT NULL,        -- e.g. macro domain, jurisdiction, capacity class — by value
  forecast_period_start   DATE NOT NULL,
  forecast_period_end     DATE NOT NULL,
  forecast_value          NUMERIC(18,4) NOT NULL,
  confidence_interval_low  NUMERIC(18,4),
  confidence_interval_high    NUMERIC(18,4),
  generated_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_advisory_forecast_period CHECK (forecast_period_end > forecast_period_start)
);

CREATE INDEX idx_advisory_forecast_type_period ON advisory_forecast (forecast_type, forecast_period_start DESC);

ALTER TABLE advisory_forecast ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_forecast_platform_read ON advisory_forecast
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_forecast_service_write ON advisory_forecast
  FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);
```

### 2.E — Anomaly & Pattern Detection

## 2.8 `advisory_anomaly_detection` — Flagged Anomalies, Including Margin Breaches

```sql
-- [Trace: TBOC Article 55.3 | Incident patterns feed risk review]
CREATE TABLE advisory_anomaly_detection (
  anomaly_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id             UUID REFERENCES advisory_model_registry (model_id),
  anomaly_type         advisory_anomaly_type_enum NOT NULL,
  source_engine_code   TEXT NOT NULL,
  severity             advisory_severity_enum NOT NULL DEFAULT 'MEDIUM',
  description           TEXT NOT NULL,
  correlation_id           UUID,               -- carried from the triggering signal, e.g. COST_MARGIN_BREACHED
  detected_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_advisory_anomaly_detection_type_severity ON advisory_anomaly_detection (anomaly_type, severity);
CREATE INDEX idx_advisory_anomaly_detection_correlation ON advisory_anomaly_detection (correlation_id) WHERE correlation_id IS NOT NULL;

COMMENT ON TABLE advisory_anomaly_detection IS
  'A MARGIN_BREACH row here is written the instant Cost''s COST_MARGIN_BREACHED signal is accepted into this engine''s inbox (§4.1) — Cost''s own quote is never touched; this is observation, not intervention.';

ALTER TABLE advisory_anomaly_detection ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_anomaly_detection_platform_read ON advisory_anomaly_detection
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_anomaly_detection_service_write ON advisory_anomaly_detection
  FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);
```

## 2.9 `advisory_pattern_insight` — Recurring Operational Patterns

```sql
-- [Trace: TBOC Article 41 | Resource Lifecycle — the "evaluated" stage, made computable]
CREATE TABLE advisory_pattern_insight (
  pattern_insight_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id             UUID NOT NULL REFERENCES advisory_model_registry (model_id),
  pattern_code         TEXT NOT NULL,
  pattern_description  TEXT NOT NULL,
  subject_scope        TEXT NOT NULL,
  supporting_sample_size  INTEGER NOT NULL CHECK (supporting_sample_size >= 0),
  identified_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_advisory_pattern_insight_code ON advisory_pattern_insight (pattern_code);

ALTER TABLE advisory_pattern_insight ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_pattern_insight_platform_read ON advisory_pattern_insight
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_pattern_insight_service_write ON advisory_pattern_insight
  FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);
```

### 2.F — Model Performance

## 2.10 `advisory_model_performance` — Continuous Model Evaluation

```sql
-- [Trace: TBOC Article 50 | Non-conforming quality triggers correction, retraining, or discipline]
CREATE TABLE advisory_model_performance (
  model_performance_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id               UUID NOT NULL REFERENCES advisory_model_registry (model_id),
  evaluation_period_start DATE NOT NULL,
  evaluation_period_end   DATE NOT NULL,
  accuracy_metric_name    TEXT NOT NULL,
  metric_value             NUMERIC(10,4) NOT NULL,
  evaluated_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_advisory_model_performance_period CHECK (evaluation_period_end > evaluation_period_start)
);

CREATE INDEX idx_advisory_model_performance_model ON advisory_model_performance (model_id, evaluation_period_start DESC);

COMMENT ON TABLE advisory_model_performance IS
  'A model whose metric_value degrades below its governed threshold is transitioned to DEPRECATED (§2.1) — a wrong model is corrected, never left silently issuing recommendations.';

ALTER TABLE advisory_model_performance ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_model_performance_platform_read ON advisory_model_performance
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_model_performance_service_write ON advisory_model_performance
  FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);
```

### 2.G — Advisory Evidence

## 2.11 `advisory_decision_log` — Immutable, Hash-Chained Evidence

```sql
-- [Trace: FDN-001 Part IX pattern (TRS_FDN_AUDIT), applied to Engine 9's own recommendation emissions]
CREATE TABLE advisory_decision_log (
  decision_log_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recommendation_id    UUID REFERENCES advisory_recommendation (recommendation_id),
  event_type           TEXT NOT NULL,
  event_description    TEXT,
  prev_hash             CHAR(64),
  immutable_hash            CHAR(64) NOT NULL,
  recorded_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_advisory_decision_log_recommendation ON advisory_decision_log (recommendation_id);

REVOKE UPDATE, DELETE ON advisory_decision_log FROM PUBLIC;
REVOKE UPDATE, DELETE ON advisory_decision_log FROM trustride_authenticated;

ALTER TABLE advisory_decision_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_decision_log_platform_read ON advisory_decision_log
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY advisory_decision_log_service_write ON advisory_decision_log
  FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);
```

### 2.H — Engine Event Substrate (Constitutional Mandatory Tables)

## 2.12 Engine Event Substrate

Per Plate I (Station Law) and CC-03 of the platform Conformance Certificate, every engine — Engine 9 included — carries exactly one outbox and one inbox, in the standard signal envelope shape (FDN-001 §11.2).

```sql
-- [Trace: FDN-001 §11.2 — mandatory per-engine ledger tables]
CREATE TABLE advisory_event_outbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG009_AIADV',
  receiving_engine       TEXT NOT NULL,
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  signal_status               TEXT NOT NULL DEFAULT 'PENDING'
                                CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason              TEXT,
  idempotency_key                 TEXT NOT NULL UNIQUE,
  attempt_count                     INTEGER NOT NULL DEFAULT 0,
  emitted_at                         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_advisory_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_advisory_outbox_status ON advisory_event_outbox (signal_status);
CREATE INDEX idx_advisory_outbox_correlation ON advisory_event_outbox (correlation_id);

ALTER TABLE advisory_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_event_outbox_service_only ON advisory_event_outbox
  FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);

-- [Trace: FDN-001 §11.2 — mandatory per-engine ledger tables]
CREATE TABLE advisory_event_inbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL,
  receiving_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG009_AIADV',
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  payload_out                JSONB,
  signal_status                TEXT NOT NULL DEFAULT 'RECEIVED'
                                 CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason               TEXT,
  idempotency_key                  TEXT NOT NULL UNIQUE,
  received_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at                          TIMESTAMPTZ,
  CONSTRAINT chk_advisory_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_advisory_inbox_status ON advisory_event_inbox (signal_status);
CREATE INDEX idx_advisory_inbox_correlation ON advisory_event_inbox (correlation_id);

ALTER TABLE advisory_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY advisory_event_inbox_service_only ON advisory_event_inbox
  FOR ALL TO trs026_eng009_aiadv_service USING (true) WITH CHECK (true);
```

---

# SECTION 3 — SYSTEM API CONTRACTS

## 3.1 `GET /api/v1/advisory/recommendations`

**Request** (query parameters)

```
GET /api/v1/advisory/recommendations?recommendation_type=FLEET_REPLACEMENT&outcome=PENDING
```

**Response — `200 OK`**

```json
{
  "recommendations": [
    {
      "recommendation_id": "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e",
      "recommendation_type": "FLEET_REPLACEMENT",
      "subject_engine_code": "TRS026_ENG002_RESC",
      "subject_ref_id": "c3d4e5f6-a7b8-4c9d-0e1f-2a3b4c5d6e7f",
      "confidence_score": 82.50,
      "generated_at": "2026-08-16T09:00:00Z",
      "outcome": "PENDING"
    }
  ]
}
```

## 3.2 `POST /api/v1/advisory/recommendations/{recommendation_id}/decision`

**Request** (Governor-initiated, via the Sovereign Executive Console)

```json
{
  "outcome": "ACCEPTED",
  "decided_by": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "decision_reason": "Fleet unit exceeds maintenance cost threshold; scheduled for replacement."
}
```

**Response — `200 OK`**

```json
{
  "recommendation_id": "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e",
  "outcome": "ACCEPTED",
  "decided_at": "2026-08-16T09:14:00Z"
}
```

## 3.3 `GET /api/v1/advisory/forecasts`

**Request** (query parameters)

```
GET /api/v1/advisory/forecasts?forecast_type=DEMAND&subject_scope=KISUMU_COUNTY
```

**Response — `200 OK`**

```json
{
  "forecasts": [
    {
      "forecast_id": "d5e6f7a8-b9c0-4d1e-8f2a-3b4c5d6e7f8a",
      "forecast_type": "DEMAND",
      "forecast_period_start": "2026-09-01",
      "forecast_period_end": "2026-09-30",
      "forecast_value": 18400.0,
      "confidence_interval_low": 16900.0,
      "confidence_interval_high": 19800.0
    }
  ]
}
```

---

# SECTION 4 — EVENT-DRIVEN SIGNAL & INTEGRATION MATRIX

## 4.1 Inbound Signals — Listened To

| Signal | Emitting engine | Payload (key fields) | Effect inside Engine 9 |
| --- | --- | --- | --- |
| `COST_MARGIN_BREACHED` | Engine 5 (Cost), via Engines 7/8 | `rate_card_rule_id`, `computed_margin_pct`, `minimum_margin_pct`, `quote_id` | Writes an `advisory_anomaly_detection` row (`anomaly_type = 'MARGIN_BREACH'`); observation only — Cost's own quote and rate card are never touched |

Every other input to this engine is a read-only lawful projection (§1.3), not a signal — Engine 9 discovers and reads governed views on its own schedule; no domain engine is ever kept waiting on Engine 9's behalf.

## 4.2 Outbound Signals — Emitted

| Signal | Receiving engine | Payload (key fields) | Triggering condition |
| --- | --- | --- | --- |
| `ADVISORY_RECOMMENDATION_PUBLISHED` | Engine 11 (Presentation), via Engines 7/8 | `recommendation_id`, `recommendation_type`, `subject_engine_code`, `confidence_score` | Fired the instant a new `advisory_recommendation` row is written; Presentation renders it as a non-authoritative projection to the Sovereign Executive Console or Admin Console, never auto-applied |
| `ADVISORY_ANOMALY_FLAGGED` | Engine 8 (Coordination, for operator/administrator review) and Engine 11 (Presentation) | `anomaly_id`, `anomaly_type`, `severity` | Fired the instant a new `advisory_anomaly_detection` row is written |

## 4.3 The Signal Envelope (as applied to Engine 9)

Identical to the platform-wide envelope (Plate I, §11.2 of the Foundation instrument): `signal_id`, `correlation_id`, `causation_id`, `emitting_engine` = `TRS026_ENG009_AIADV`, `receiving_engine`, `signal_type`, `payload_in`, `payload_out`, `signal_status`, `rejection_reason`, `idempotency_key`, `attempt_count`, `emitted_at`, `received_at`, `accepted_at`. No field is added, renamed, or omitted.

---

# ANNEX — CONFORMANCE SELF-CERTIFICATION AGAINST THE THREE PLATES

Filed in the same discipline as the Foundation instrument's Part XI and the Engine 2/3/4/5/6/7/8 Annexes.

| Check | Requirement | Result | Evidence |
| --- | --- | --- | --- |
| CC-02 | Every table assigned to exactly one of the five stations | **PASS** | §2.1–2.11: domain tables = Domain State; `advisory_event_outbox` = Emission Ledger; `advisory_event_inbox` = Reception Ledger (§2.12) |
| CC-03 | Engine carries the four ledger tables with the standard envelope | **PASS** | §2.12, §4.3 |
| CC-04 | Every cross-engine interaction is a signal; no foreign table access | **PASS** | §1.3, §2.3 — every read source is a governed projection, registered before use, never a foreign key into another engine's schema |
| CC-06 | Idempotency, retry, dead-letter declared | **PASS** | `idempotency_key` UNIQUE on both ledger tables (§2.12) |
| CC-07 | Engine declares its layer, holds nothing belonging to another layer | **PASS** | §1 — Layer 4, AI Advisory; holds no identity, order, resource, pricing, or external-system authoritative state |
| **CC-09** | **Advisory outputs, if any, are records only** | **PASS — this is this engine's defining check** | Every table in §2.4–2.9 is a record with a `confidence_score` or interval, never a mutation path into another engine's schema; §2.6 `advisory_recommendation_outcome` proves a human or a lawful rule decided every single time |
| CC-12 | Every provision carries a trace tag | **PASS** | Every DDL block and table comment carries a `[Trace: ...]` tag |
| RLS Law | Row-Level Security enabled on every table | **PASS** | All twelve tables (§2.1–2.12) carry `ENABLE ROW LEVEL SECURITY` with an explicit policy |
| Immutability Law | Ledgers append-only where history must never be rewritten | **PASS** | `advisory_model_version_history` and `advisory_decision_log` carry `REVOKE UPDATE, DELETE` |
| Advisory-Only Law | Zero write authority into any other engine's authoritative state, under any urgency | **PASS** | No table, trigger, or function in this instrument references, writes, or holds a foreign key into any table outside the `advisory_` prefix |

---

**END OF SPECIFICATION**

*Engine 9 never decides. It watches, it measures, it explains its reasoning, and it hands every conclusion to a human Governor or a lawful rule — a suggestion, always signed with how sure it is, never mistaken for the truth it observes.*
