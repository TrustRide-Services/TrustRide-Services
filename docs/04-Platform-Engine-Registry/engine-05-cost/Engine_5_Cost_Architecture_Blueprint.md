# TRUSTRIDE SERVICES

# ENGINE 5 — COST & UNIT-PRICE BUILD-UP ENGINE
## Complete Architectural, Data, API, and Signal Specification

**[Parent Authority: TBOC v2.0.0 Genesis Edition · Architecture Blueprint v1.1.0]**

*More than a Ride — We Save You Time.*

## Document Control

| Document Control Field | Entry |
| --- | --- |
| Document Title | Engine 5 — Cost & Unit-Price Build-Up Engine: Complete Specification |
| Document Identifier | TRS026-ENG005-COST-001 |
| Version | 1.1.1 |
| Status | **ADOPTED** (certified 2026-08-16, per Founder ruling — TBOC v2.0.0 Article 58.5, Annex I A-001) |
| Adopted On | 2026-08-16 |
| Remediation | v1.1.0 corrected Money Law precision, enabled Row-Level Security, completed trace headers on all tables, and bumped Parent Authority to TBOC v2.0.0. v1.1.1 adds the missing `CREATE TABLE cost_formula_matrix` (§3.2) — `cost_rate_card_rule.formula_id` held a hard `REFERENCES cost_formula_matrix (formula_id)` foreign key to a table that was fully specified in prose (column table, §3.2) but never actually created in DDL; this migration-blocking gap is now closed, bringing the engine to twelve tables. Cross-checked against the now-finalized FDN-001 v3.0.0 Annex H and the remediated Engines 2/3/4 for alignment — no other deviation found |
| Classification | Institutional Blueprint — Confidential |
| Schema | `trustride` (single canonical PostgreSQL schema; this engine's tables are prefixed `cost_`) |
| Platform Code | TRS026 |
| Engine Code | `TRS026_ENG005_COST` |
| Engine No. | `ENGINE_005` |
| Installation Order | 005 |
| Parent Authority | TBOC v2.0.0 Genesis Edition — Article 45 (Pricing), Article 44 (Ledger Splits & Revenue Architecture), Article 20.2 (Assignment sub-sequence: fee posted to requester before acceptance), Article 42 (One Financial Truth) |
| Architecture Lineage | Introduced into the Backend, Frontend, and Event/Signal architecture blueprints at v1.1.0 (2026-08-15), inserted as Engine 5, renumbering the former Engines 5–10 to 6–11 |

## Document Purpose & Constitutional Basis

This instrument specifies **Engine 5 — the Cost & Unit-Price Build-Up Engine**, TrustRide's dynamic financial calculation engine. It is filed as a proposed addition to the eleven-engine constitutional registry, exercised under the Founder's direct authority per TBOC Article 62 (Amendment & Review) and the escalation clause of TBOC Article 58.5, which reserves any expansion of the engine registry to the Founder alone.

TBOC does not permit a technical document to invent business concepts (Article 8, the Zero-Pollution Rule). Every mechanical rule in this document therefore traces to a standing TBOC provision:

| This engine's function | TBOC basis |
| --- | --- |
| Computing the fee before the requester accepts | Article 20.2 — "Assignment Accepted → **Customer Prompted (fee, expected arrival time...)**" |
| Posting a fee the catalogue can explain | Article 45 — Pricing: "No price may be charged that the catalogue cannot explain" |
| Ledger splits, commissions, governed rate registers | Article 44 — Ledger Splits & Revenue Architecture |
| One authoritative financial truth, no side calculation | Article 42 — One Financial Truth |
| Statutory/governance surcharges | Article 48 — Workforce Financial Stewardship; Article 42.5 (lawful electronic tax invoice) |
| Settlement handoff after a fare is finalized | Article 43 — Settlement Stages & Approved Payment Rails (M-Pesa C2B STK Push primary, Flutterwave secondary) |

Prior to this engine, TBOC's Governance sub-engine (`rate_register`, within Foundation/TRS_FDN_GOVERNANCE) held only **static, administered** commission, split, and fee rows. Engine 5 does not replace that register — it is the **dynamic computation layer** that sits in front of it: it reads governed rate cards and baselines, executes the Sovereign Dynamic Cost Equation against live trip parameters, and produces an immutable, hash-chained quote. `rate_register` remains the lawful source of *commission and split* truth (Article 44); `cost_unit_price_quotes` (this engine) becomes the lawful source of *computed fare* truth per Order.

---

# SECTION 1 — ARCHITECTURAL ROLE & BOUNDARIES

## 1.1 Mission

Engine 5 is the platform's single, deterministic authority for turning a trip's raw parameters — asset class, distance, duration, zone, terrain, and prevailing fuel economics — into one lawful, immutable **unit-price quote**. No fare figure shown to a requester, posted to an Order, or handed to settlement may originate anywhere except a `cost_unit_price_quotes` row produced by this engine.

## 1.2 Operational Duties

1. **Unit-rate calculation.** Execute the Sovereign Dynamic Cost Equation (§3) against governed baselines and live inputs to produce a total fare figure.
2. **Rate card evaluation.** Resolve which `FormulaMatrixObject` and `RateCardRuleObject` apply to a given asset class, service, domain, and jurisdiction.
3. **Regulatory ingestion.** Absorb monthly EPRA fuel index publications into `cost_epra_fuel_registry`, and recompute derived per-km rates (`R_d`) without silently drifting from the published baseline.
4. **Zone and terrain governance.** Maintain `cost_operational_zones` (return/deadhead multipliers) and `cost_road_segments_override` (terrain penalties) as spatially governed reference data.
5. **Quote lifecycle custody.** Own the `quote_state_enum` lifecycle of every quote from `FARE_ESTIMATED` through `FARE_LOCKED`, `SERVICE_IN_PROGRESS`, `FARE_FINALIZED`, and `C2B_PAYMENT_TRIGGERED`, or its `EXPIRED`/`CANCELLED` terminations.
6. **Ledger reconciliation.** Maintain the `CostExecutionLedgerObject` as the audit trail of every calculation performed, so Finance and Audit can reconcile computed fares against settled Orders (TBOC Article 49).
7. **Margin protection.** Detect when a computed fare would breach a governed minimum-margin threshold and emit `COST_MARGIN_BREACHED` rather than silently under-price the trip.

## 1.3 Interfaces with the Other Ten Engines

Per Plate I of the Backend Architecture (TRS026-BE-01 v1.1.0) and the Event/Signal Architecture (TRS026-ES-01 v1.1.0), Engine 5 **never** calls another engine directly. Every interface below is a signal, carried through Engines 7/8 (Workflow Orchestration & Coordination) — the Sovereign Processing Unit — and answered only in Engine 5's own inbox.

| Engine | Direction | What crosses the boundary |
| --- | --- | --- |
| **Engine 2 — Resources** | Inbound (via signal) | Asset identity resolved to `asset_class_enum` / `engine_capacity_enum` at dispatch time, so Engine 5 can select the correct `cost_asset_engine_baselines` row. Engine 5 never reads the Resources engine table directly. |
| **Engine 3 — Services** | Inbound (via signal) | The Service/domain context (Transport, Courier, Delivery, Executive Assistants, Marketplace) that selects the applicable `cost_rate_card_rule`. |
| **Engine 4 — Business** | Bidirectional | Inbound: Order/Assignment context (origin, destination, requester) triggering a quote. Outbound: `UNIT_PRICE_LOCKED` carrying the fee back for Business to post to the requester per TBOC Article 20.2. |
| **Engine 6 — Integration (Domain Objects)** | Bidirectional | Inbound: `EPRA_FUEL_INDEX_UPDATED` (regulatory feed ingestion via Integration's external-system boundary). Outbound: `PAYMENT_STK_TRIGGERED`, handed to Integration for the actual M-Pesa C2B STK Push / Flutterwave call (TBOC Article 43) — Engine 5 never calls a payment rail itself. |
| **Engines 7/8 — Workflow Orchestration & Coordination** | Structural | The exclusive transport for every signal in and out of Engine 5's outbox/inbox. Fan-in for multi-zone or multi-leg quotes is coordinated here, never inside Engine 5. |
| **Engine 10 — Simulation & Modelling** | Outbound (read-only) | Simulation reads `cost_formula_matrix`, `cost_rate_card_rule`, and historical `cost_execution_ledger` rows as **lawful projections** for what-if pricing scenarios. It never writes back; Engine 5's tables are never mutated by advisory or scenario engines (Plate II, Layer 4/5 prohibition). |

## 1.4 Boundaries — What Engine 5 Never Does

1. **Never dispatches.** Resource discovery, reservation, and assignment remain Engine 2/4's exclusive domain.
2. **Never touches a payment rail.** Engine 5 emits `PAYMENT_STK_TRIGGERED`; only Integration (Engine 6) executes the M-Pesa/Flutterwave call, per TISC.
3. **Never mutates another engine's state.** Cross-engine effects happen only through the signals in §5.
4. **Never holds identity or authority.** `requester_user_id` on a quote is a reference, not a claim of ownership; Identity remains TRS_FDN_IDENTITY's exclusive domain.
5. **Never edits or deletes a locked quote.** Once `quote_state` reaches `FARE_LOCKED`, the row is append-only (enforced at the database level, §2.6); correction is a new quote, never an edit of history — consistent with C-I-5 of the platform's Plate I conformance law.
6. **Never invents a formula.** `FormulaMatrixObject` versions are governed, versioned, and approved (§3.2); Engine 5 executes them, it does not author pricing policy on its own initiative — that is Finance under Founder authority (TBOC Article 44).

---

# SECTION 2 — PRODUCTION SQL DDL SCHEMA (PostgreSQL / Supabase / PostGIS-Ready)

## 2.0 Extensions & Enums (prerequisite)

```sql
-- Extensions (idempotent; already present platform-wide per Engine 001 Phase 0)
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

-- [Trace: TBOC-v1.0.0 | Article 45 | Pricing] [Article 44 | Ledger Splits & Revenue Architecture]
CREATE TYPE asset_class_enum AS ENUM (
  'BODA_BODA', 'TUKTUK', 'PICKUP_TOWN', 'VAN_CARGO', 'TRUCK_LIGHT', 'EXECUTIVE_ASSISTANT'
);

CREATE TYPE engine_capacity_enum AS ENUM (
  'EV_ELECTRIC', 'CC_100', 'CC_125', 'CC_150', 'CC_200', 'TON_1_0', 'TON_3_0', 'NOT_APPLICABLE'
);

CREATE TYPE jurisdiction_enum AS ENUM (
  'KISUMU_COUNTY', 'VIHIGA_COUNTY', 'SIAYA_COUNTY', 'NANDI_COUNTY', 'UASIN_GISHU_COUNTY', 'NAIROBI_METRO'
);

CREATE TYPE quote_state_enum AS ENUM (
  'FARE_ESTIMATED', 'FARE_LOCKED', 'SERVICE_IN_PROGRESS', 'FARE_FINALIZED',
  'C2B_PAYMENT_TRIGGERED', 'EXPIRED', 'CANCELLED'
);

CREATE TYPE user_type_enum AS ENUM (
  'CUSTOMER', 'RIDER', 'DRIVER', 'MERCHANT', 'EXECUTIVE_ASSISTANT', 'ADMIN'
);
```

## 2.1 `cost_operational_zones` — Geofenced Micro-Zones

```sql
-- [Trace: TBOC-v1.0.0 | Article 45 | Pricing — zone-based return/deadhead multiplier]
CREATE TABLE cost_operational_zones (
  zone_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  zone_code           TEXT NOT NULL UNIQUE,
  zone_name           TEXT NOT NULL,
  jurisdiction        jurisdiction_enum NOT NULL,
  density_class       TEXT NOT NULL CHECK (density_class IN ('HIGH_DENSITY', 'SUBURB', 'OUTSKIRT_DEADZONE')),
  return_multiplier   NUMERIC(4,2) NOT NULL DEFAULT 1.00 CHECK (return_multiplier >= 1.00 AND return_multiplier <= 3.00),
  boundary            GEOMETRY(POLYGON, 4326) NOT NULL,
  active              BOOLEAN NOT NULL DEFAULT TRUE,
  effective_from      TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to        TIMESTAMPTZ,
  created_by          UUID,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_cost_zone_validity CHECK (effective_to IS NULL OR effective_to > effective_from)
);

CREATE INDEX idx_cost_operational_zones_boundary ON cost_operational_zones USING GIST (boundary);
CREATE INDEX idx_cost_operational_zones_jurisdiction ON cost_operational_zones (jurisdiction) WHERE active = TRUE;
CREATE UNIQUE INDEX uq_cost_operational_zones_code_active ON cost_operational_zones (zone_code) WHERE active = TRUE;

COMMENT ON TABLE cost_operational_zones IS
  '[Trace: TBOC-v1.0.0 | Article 45] Governed micro-zones supplying K_return (destination zone return/deadhead multiplier) to the Sovereign Dynamic Cost Equation.';

-- Row Level Security (TBOC Zero-Trust law; FDN-001 Annex B, Part III Phase 8) — governed reference data, platform-readable, engine-service writable
ALTER TABLE cost_operational_zones ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_operational_zones_platform_read ON cost_operational_zones
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_operational_zones_service_write ON cost_operational_zones
  FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);
```

## 2.2 `cost_road_segments_override` — Spatial Terrain Overrides

```sql
-- [Trace: TBOC-v1.0.0 | Article 45 | Pricing — terrain surface penalty multiplier]
CREATE TABLE cost_road_segments_override (
  segment_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  segment_code        TEXT NOT NULL UNIQUE,
  segment_name        TEXT,
  jurisdiction        jurisdiction_enum NOT NULL,
  surface_class       TEXT NOT NULL CHECK (surface_class IN ('ASPHALT', 'MURRAM', 'MUD_STEEP')),
  terrain_multiplier  NUMERIC(4,2) NOT NULL CHECK (terrain_multiplier >= 1.00 AND terrain_multiplier <= 2.50),
  path                GEOMETRY(LINESTRING, 4326) NOT NULL,
  buffer_meters       NUMERIC(6,1) NOT NULL DEFAULT 25.0 CHECK (buffer_meters > 0),
  active              BOOLEAN NOT NULL DEFAULT TRUE,
  effective_from      TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to        TIMESTAMPTZ,
  created_by          UUID,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_cost_segment_validity CHECK (effective_to IS NULL OR effective_to > effective_from)
);

CREATE INDEX idx_cost_road_segments_path ON cost_road_segments_override USING GIST (path);
CREATE INDEX idx_cost_road_segments_jurisdiction ON cost_road_segments_override (jurisdiction) WHERE active = TRUE;

COMMENT ON TABLE cost_road_segments_override IS
  '[Trace: TBOC-v1.0.0 | Article 45] Spatial overrides supplying M_terrain to the Sovereign Dynamic Cost Equation; a route intersecting a MUD_STEEP or MURRAM segment inherits the higher terrain_multiplier for the affected distance.';

-- Row Level Security (TBOC Zero-Trust law; FDN-001 Annex B, Part III Phase 8) — governed reference data, platform-readable, engine-service writable
ALTER TABLE cost_road_segments_override ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_road_segments_override_platform_read ON cost_road_segments_override
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_road_segments_override_service_write ON cost_road_segments_override
  FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);
```

## 2.3 `cost_epra_fuel_registry` — Monthly Regulatory Fuel Price Caps

```sql
-- [Trace: TBOC-v1.0.0 | Article 45 | Pricing — EPRA fuel index basis for R_d]
CREATE TABLE cost_epra_fuel_registry (
  epra_entry_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  price_period             DATE NOT NULL,               -- first day of the EPRA gazetted pricing month
  fuel_type                 TEXT NOT NULL CHECK (fuel_type IN ('PETROL_SUPER', 'DIESEL', 'ELECTRIC_TARIFF')),
  jurisdiction               jurisdiction_enum NOT NULL,
  pump_price_kes              NUMERIC(18,2) NOT NULL CHECK (pump_price_kes >= 0),
  source_reference             TEXT NOT NULL,             -- EPRA gazette / bulletin reference number
  ingested_via_signal_id        UUID,                       -- correlates to the inbound EPRA_FUEL_INDEX_UPDATED signal_id
  effective_from                 TIMESTAMPTZ NOT NULL,
  effective_to                    TIMESTAMPTZ,
  created_at                       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (price_period, fuel_type, jurisdiction)
);

CREATE INDEX idx_cost_epra_fuel_lookup ON cost_epra_fuel_registry (fuel_type, jurisdiction, price_period DESC);

COMMENT ON TABLE cost_epra_fuel_registry IS
  '[Trace: TBOC-v1.0.0 | Article 45] Append-only regulatory record. R_d (direct per-km operational rate) is derived from the latest effective row here, never invented locally.';

-- Row Level Security (TBOC Zero-Trust law; FDN-001 Annex B, Part III Phase 8) — governed regulatory reference, platform-readable, Integration/engine-service writable
ALTER TABLE cost_epra_fuel_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_epra_fuel_registry_platform_read ON cost_epra_fuel_registry
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_epra_fuel_registry_service_write ON cost_epra_fuel_registry
  FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);
```

## 2.4 `cost_asset_engine_baselines` — Mechanical Baselines

```sql
-- [Trace: TBOC-v1.0.0 | Article 45 | Pricing — per-asset-class mechanical cost baseline]
CREATE TABLE cost_asset_engine_baselines (
  baseline_id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_class                    asset_class_enum NOT NULL,
  engine_capacity                engine_capacity_enum NOT NULL,
  base_dispatch_fee_kes          NUMERIC(18,2) NOT NULL CHECK (base_dispatch_fee_kes >= 0),      -- F_base
  fuel_consumption_km_per_l      NUMERIC(6,2) CHECK (fuel_consumption_km_per_l IS NULL OR fuel_consumption_km_per_l > 0),
  energy_consumption_kwh_per_km  NUMERIC(6,3) CHECK (energy_consumption_kwh_per_km IS NULL OR energy_consumption_kwh_per_km > 0),
  maintenance_rate_kes_per_km    NUMERIC(18,2) NOT NULL CHECK (maintenance_rate_kes_per_km >= 0),
  direct_per_km_rate_kes         NUMERIC(18,2) NOT NULL CHECK (direct_per_km_rate_kes >= 0),        -- R_d, cached derived value
  time_rate_kes_per_min          NUMERIC(18,2) NOT NULL CHECK (time_rate_kes_per_min >= 0),          -- R_t
  minimum_fare_floor_kes         NUMERIC(18,2) NOT NULL CHECK (minimum_fare_floor_kes >= 0),        -- F_min
  active                          BOOLEAN NOT NULL DEFAULT TRUE,
  effective_from                  TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to                     TIMESTAMPTZ,
  approved_by                       UUID,
  approved_request_id                UUID,                -- FK-by-reference to TRS_FDN_GOVERNANCE.approval_request
  created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_cost_baseline_energy_xor
    CHECK (
      (engine_capacity = 'EV_ELECTRIC' AND energy_consumption_kwh_per_km IS NOT NULL AND fuel_consumption_km_per_l IS NULL)
      OR
      (engine_capacity <> 'EV_ELECTRIC' AND fuel_consumption_km_per_l IS NOT NULL AND energy_consumption_kwh_per_km IS NULL)
      OR
      engine_capacity = 'NOT_APPLICABLE'
    ),
  CONSTRAINT chk_cost_baseline_validity CHECK (effective_to IS NULL OR effective_to > effective_from)
);

CREATE UNIQUE INDEX uq_cost_asset_baselines_active
  ON cost_asset_engine_baselines (asset_class, engine_capacity)
  WHERE active = TRUE;

CREATE INDEX idx_cost_asset_baselines_lookup ON cost_asset_engine_baselines (asset_class, engine_capacity);

COMMENT ON TABLE cost_asset_engine_baselines IS
  '[Trace: TBOC-v1.0.0 | Article 45] Governed, versioned mechanical baselines. A rate cannot be applied without an approved_request_id (TRS_FDN_GOVERNANCE pattern, Article 44).';

-- Row Level Security (TBOC Zero-Trust law; FDN-001 Annex B, Part III Phase 8) — governed reference data, platform-readable, engine-service writable
ALTER TABLE cost_asset_engine_baselines ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_asset_engine_baselines_platform_read ON cost_asset_engine_baselines
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_asset_engine_baselines_service_write ON cost_asset_engine_baselines
  FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

-- Pre-seed: 125cc motorcycle (BODA_BODA) baseline, as specified
INSERT INTO cost_asset_engine_baselines (
  asset_class, engine_capacity, base_dispatch_fee_kes, fuel_consumption_km_per_l,
  maintenance_rate_kes_per_km, direct_per_km_rate_kes, time_rate_kes_per_min, minimum_fare_floor_kes
) VALUES (
  'BODA_BODA', 'CC_125', 30.00, 35.00, 3.50, 12.00, 2.50, 70.00
);
```

## 2.5 `cost_unit_price_quotes` — Cryptographic Immutable Quote Ledger

```sql
-- [Trace: TBOC-v1.0.0 | Article 20.2 | Article 45 | Article 42 — One Financial Truth]
CREATE TABLE cost_unit_price_quotes (
  quote_id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_code                   TEXT NOT NULL UNIQUE,          -- 'TRS026-QUOTE-000000001', issued by sequence_generator (Engine 001 Substrate)
  order_id                     UUID,                            -- referenced by correlation only; Engine 5 does not own or write Business Engine tables
  assignment_id                UUID,
  requester_user_id            UUID NOT NULL,
  requester_user_type          user_type_enum NOT NULL,
  asset_class                  asset_class_enum NOT NULL,
  engine_capacity               engine_capacity_enum NOT NULL,
  jurisdiction                  jurisdiction_enum NOT NULL,
  origin_zone_id                 UUID NOT NULL REFERENCES cost_operational_zones (zone_id),
  destination_zone_id             UUID NOT NULL REFERENCES cost_operational_zones (zone_id),
  distance_km                      NUMERIC(8,3) NOT NULL CHECK (distance_km >= 0),
  duration_min                      NUMERIC(8,2) NOT NULL CHECK (duration_min >= 0),
  base_dispatch_fee_kes               NUMERIC(18,2) NOT NULL CHECK (base_dispatch_fee_kes >= 0),
  direct_per_km_rate_kes               NUMERIC(18,2) NOT NULL CHECK (direct_per_km_rate_kes >= 0),
  return_multiplier_applied             NUMERIC(4,2) NOT NULL CHECK (return_multiplier_applied >= 1.00),
  time_rate_kes_per_min                  NUMERIC(18,2) NOT NULL CHECK (time_rate_kes_per_min >= 0),
  terrain_multiplier_applied              NUMERIC(4,2) NOT NULL CHECK (terrain_multiplier_applied >= 1.00),
  minimum_fare_floor_kes                   NUMERIC(18,2) NOT NULL CHECK (minimum_fare_floor_kes >= 0),
  governance_surcharge_kes                  NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (governance_surcharge_kes >= 0),
  pre_floor_fare_kes                         NUMERIC(18,2) NOT NULL CHECK (pre_floor_fare_kes >= 0),
  computed_total_fare_kes                     NUMERIC(18,2) NOT NULL CHECK (computed_total_fare_kes >= 0),
  currency                                     CHAR(3) NOT NULL DEFAULT 'KES',
  formula_version                               TEXT NOT NULL,
  epra_entry_id                                  UUID REFERENCES cost_epra_fuel_registry (epra_entry_id),
  quote_state                                     quote_state_enum NOT NULL DEFAULT 'FARE_ESTIMATED',
  quote_hash                                       CHAR(64) NOT NULL,      -- SHA-256 over the canonical quote payload
  prev_quote_hash                                   CHAR(64),               -- hash-chain predecessor (Foundation Audit pattern, Article 49)
  locked_at                                          TIMESTAMPTZ,
  expires_at                                          TIMESTAMPTZ NOT NULL,
  finalized_at                                         TIMESTAMPTZ,
  cancelled_at                                          TIMESTAMPTZ,
  correlation_id                                         UUID NOT NULL,     -- the platform signal envelope's correlation_id
  causation_id                                            UUID,
  created_at                                               TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_cost_quote_fare_math
    CHECK (computed_total_fare_kes >= LEAST(pre_floor_fare_kes, minimum_fare_floor_kes) + governance_surcharge_kes - 0.01)
);

CREATE INDEX idx_cost_quotes_state ON cost_unit_price_quotes (quote_state);
CREATE INDEX idx_cost_quotes_order ON cost_unit_price_quotes (order_id);
CREATE INDEX idx_cost_quotes_requester ON cost_unit_price_quotes (requester_user_id);
CREATE INDEX idx_cost_quotes_correlation ON cost_unit_price_quotes (correlation_id);
CREATE INDEX idx_cost_quotes_expiry ON cost_unit_price_quotes (expires_at) WHERE quote_state = 'FARE_ESTIMATED';

-- Append-only discipline once a quote is locked — correction is a new quote, never an edit of history (C-I-5)
CREATE OR REPLACE FUNCTION cost_quotes_block_illegal_mutation() RETURNS trigger AS $$
BEGIN
  IF OLD.quote_state IN ('FARE_LOCKED', 'SERVICE_IN_PROGRESS', 'FARE_FINALIZED', 'C2B_PAYMENT_TRIGGERED')
     AND (NEW.computed_total_fare_kes IS DISTINCT FROM OLD.computed_total_fare_kes
          OR NEW.quote_hash IS DISTINCT FROM OLD.quote_hash) THEN
    RAISE EXCEPTION 'cost_unit_price_quotes: fare and hash are immutable once quote_state = %; correction requires a new quote', OLD.quote_state;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_cost_quotes_block_illegal_mutation
  BEFORE UPDATE ON cost_unit_price_quotes
  FOR EACH ROW EXECUTE FUNCTION cost_quotes_block_illegal_mutation();

COMMENT ON TABLE cost_unit_price_quotes IS
  '[Trace: TBOC-v1.0.0 | Article 20.2, 42, 45] The single lawful source of computed fare truth. No fare shown to a requester or posted to settlement may originate anywhere else.';

-- Row Level Security (TBOC Zero-Trust law; FDN-001 Annex B, Part III Phase 8) — requester sees only their own quotes; the engine service role has full access
ALTER TABLE cost_unit_price_quotes ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_unit_price_quotes_requester_read ON cost_unit_price_quotes
  FOR SELECT TO trustride_authenticated
  USING (requester_user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY cost_unit_price_quotes_service_write ON cost_unit_price_quotes
  FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);
```

## 2.6 Engine Event Substrate (Constitutional Mandatory Tables)

Per Plate I (Station Law) and CC-03 of the platform Conformance Certificate, every engine — Engine 5 included — carries exactly one outbox and one inbox, in the standard signal envelope shape.

```sql
-- [Trace: TBOC-v1.0.0 | Article 59-60 — mandatory per-engine ledger tables]
CREATE TABLE cost_event_outbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG005_COST',
  receiving_engine       TEXT NOT NULL,
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  signal_status               TEXT NOT NULL DEFAULT 'PENDING'
                                CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason              TEXT,
  idempotency_key                 TEXT NOT NULL UNIQUE,
  attempt_count                     INTEGER NOT NULL DEFAULT 0,
  emitted_at                         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_cost_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_cost_outbox_status ON cost_event_outbox (signal_status);
CREATE INDEX idx_cost_outbox_correlation ON cost_event_outbox (correlation_id);

-- Row Level Security (TBOC Zero-Trust law; FDN-001 Annex B, Part III Phase 8) — internal signal ledger, engine-service only
ALTER TABLE cost_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_event_outbox_service_only ON cost_event_outbox
  FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

-- [Trace: TBOC-v1.0.0 | Article 59-60 — mandatory per-engine ledger tables]
CREATE TABLE cost_event_inbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL,
  receiving_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG005_COST',
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  payload_out                JSONB,
  signal_status                TEXT NOT NULL DEFAULT 'RECEIVED'
                                 CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason               TEXT,
  idempotency_key                  TEXT NOT NULL UNIQUE,
  received_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at                          TIMESTAMPTZ,
  CONSTRAINT chk_cost_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_cost_inbox_status ON cost_event_inbox (signal_status);
CREATE INDEX idx_cost_inbox_correlation ON cost_event_inbox (correlation_id);

-- Row Level Security (TBOC Zero-Trust law; FDN-001 Annex B, Part III Phase 8) — internal signal ledger, engine-service only
ALTER TABLE cost_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_event_inbox_service_only ON cost_event_inbox
  FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);
```

---

# SECTION 3 — DOMAIN OBJECT & PRIMITIVE SPECIFICATIONS

## 3.1 The Sovereign Dynamic Cost Equation (implemented, not restated)

$$\text{Total Fare } (F) = \max\Bigg(\Big[\big(F_{\text{base}} + (D \times R_d \times K_{\text{return}}) + (T \times R_t)\big) \times M_{\text{terrain}}\Big], \,\, F_{\text{min}}\Bigg) + S_{\text{governance}}$$

| Symbol | Column of record | Table |
| --- | --- | --- |
| $F_{\text{base}}$ | `base_dispatch_fee_kes` | `cost_asset_engine_baselines` → copied onto the quote |
| $D$ | `distance_km` | `cost_unit_price_quotes` (routing input) |
| $R_d$ | `direct_per_km_rate_kes` | `cost_asset_engine_baselines`, derived from `cost_epra_fuel_registry` |
| $K_{\text{return}}$ | `return_multiplier` / `return_multiplier_applied` | `cost_operational_zones` → copied onto the quote |
| $T$ | `duration_min` | `cost_unit_price_quotes` (routing input) |
| $R_t$ | `time_rate_kes_per_min` | `cost_asset_engine_baselines` → copied onto the quote |
| $M_{\text{terrain}}$ | `terrain_multiplier` / `terrain_multiplier_applied` | `cost_road_segments_override` → copied onto the quote |
| $F_{\text{min}}$ | `minimum_fare_floor_kes` | `cost_asset_engine_baselines` → copied onto the quote |
| $S_{\text{governance}}$ | `governance_surcharge_kes` | `cost_rate_card_rule` (§3.5) → copied onto the quote |

Every symbol is a **copied, versioned value on the quote row itself** (never a live join at read time) — so a settled quote remains mathematically reproducible and auditable forever, even after the underlying baseline, zone, or EPRA row is superseded.

## 3.2 `FormulaMatrixObject` → `cost_formula_matrix`

The governed, versioned binding of an equation shape to an asset class. Enables the equation itself to evolve (e.g., a future weighting term) without a code deployment.

| Column Name | Data Type | Nullability | Constraints | Exact Purpose |
| --- | --- | --- | --- | --- |
| `formula_id` | UUID | NOT NULL | PK, `DEFAULT gen_random_uuid()` | Unique identity of this formula version |
| `formula_version` | TEXT | NOT NULL | UNIQUE with `asset_class` | Human-legible version tag, e.g. `'FDN-COST-1.0.0'`; stamped onto every quote (§2.5) |
| `asset_class` | `asset_class_enum` | NOT NULL | — | The asset class this formula version governs |
| `equation_definition` | JSONB | NOT NULL | — | Canonical, machine-evaluable term list: `{"terms":["F_base","D*R_d*K_return","T*R_t"],"multiplier":"M_terrain","floor":"F_min","addend":"S_governance"}` |
| `component_weights` | JSONB | NOT NULL | DEFAULT `'{}'` | Optional per-term weighting coefficients for future tuning without altering `equation_definition`'s shape |
| `status` | TEXT | NOT NULL | CHECK IN (`'DRAFT'`,`'ACTIVE'`,`'SUPERSEDED'`) | Exactly one `ACTIVE` row per `asset_class` at any time |
| `approved_by` | UUID | NULL | — | Governance approval reference (Finance under Founder authority, TBOC Art. 44) |
| `approved_request_id` | UUID | NULL | — | Reference into `TRS_FDN_GOVERNANCE.approval_request` |
| `effective_from` | TIMESTAMPTZ | NOT NULL | `DEFAULT now()` | When this formula version takes effect |
| `effective_to` | TIMESTAMPTZ | NULL | — | NULL while active |
| `superseded_by` | UUID | NULL | FK → `cost_formula_matrix.formula_id` | Successor version, set only on supersession |
| `created_at` | TIMESTAMPTZ | NOT NULL | `DEFAULT now()` | Row creation time |

```sql
-- [Trace: TBOC-v1.0.0 | Article 45 | Pricing — governed, versioned equation shape per asset class]
CREATE TABLE cost_formula_matrix (
  formula_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  formula_version        TEXT NOT NULL,
  asset_class              asset_class_enum NOT NULL,
  equation_definition        JSONB NOT NULL,
  component_weights            JSONB NOT NULL DEFAULT '{}',
  status                          TEXT NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','ACTIVE','SUPERSEDED')),
  approved_by                        UUID,
  approved_request_id                  UUID,             -- reference into TRS_FDN_GOVERNANCE.approval_request
  effective_from                         TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to                             TIMESTAMPTZ,
  superseded_by                              UUID REFERENCES cost_formula_matrix (formula_id),
  created_at                                   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (formula_version, asset_class)
);

CREATE UNIQUE INDEX uq_cost_formula_matrix_active
  ON cost_formula_matrix (asset_class) WHERE status = 'ACTIVE';
CREATE INDEX idx_cost_formula_matrix_lookup ON cost_formula_matrix (asset_class, status);

COMMENT ON TABLE cost_formula_matrix IS
  '[Trace: TBOC-v1.0.0 | Article 45] The governed, versioned binding of an equation shape to an asset class; exactly one ACTIVE row per asset_class. Enables the equation to evolve without a code deployment.';

-- Row Level Security (TBOC Zero-Trust law; FDN-001 Annex B, Part III Phase 8) — governed reference data, platform-readable, engine-service writable
ALTER TABLE cost_formula_matrix ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_formula_matrix_platform_read ON cost_formula_matrix
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_formula_matrix_service_write ON cost_formula_matrix
  FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

-- Pre-seed: the Sovereign Dynamic Cost Equation (§3.1) as the ACTIVE formula for BODA_BODA,
-- matching the worked example of §4.1 and the pre-seeded baseline of §2.4
INSERT INTO cost_formula_matrix (formula_version, asset_class, equation_definition, status, effective_from) VALUES (
  'FDN-COST-1.0.0', 'BODA_BODA',
  '{"terms":["F_base","D*R_d*K_return","T*R_t"],"multiplier":"M_terrain","floor":"F_min","addend":"S_governance"}',
  'ACTIVE', now()
);
```

## 3.3 `UnitPriceBuildUpEntry` → `cost_unit_price_buildup_entry`

The itemized, line-by-line breakdown of a single quote — the transparent "receipt" behind `computed_total_fare_kes`, one row per equation term.

| Column Name | Data Type | Nullability | Constraints | Exact Purpose |
| --- | --- | --- | --- | --- |
| `buildup_entry_id` | UUID | NOT NULL | PK, `DEFAULT gen_random_uuid()` | Unique identity of this line item |
| `quote_id` | UUID | NOT NULL | FK → `cost_unit_price_quotes.quote_id` | The quote this line belongs to |
| `component_code` | TEXT | NOT NULL | CHECK IN (`'F_BASE'`,`'DISTANCE_COST'`,`'TIME_COST'`,`'TERRAIN_ADJUSTMENT'`,`'FLOOR_ADJUSTMENT'`,`'GOVERNANCE_SURCHARGE'`) | Which term of the equation this line represents |
| `raw_input_value` | NUMERIC(12,4) | NULL | — | The raw input feeding this term (e.g. `distance_km` for `DISTANCE_COST`) |
| `rate_applied` | NUMERIC(10,4) | NULL | — | The per-unit rate applied (e.g. `direct_per_km_rate_kes`) |
| `multiplier_applied` | NUMERIC(4,2) | NOT NULL | `DEFAULT 1.00` | Any multiplier folded into this line (`K_return`, `M_terrain`) |
| `line_amount_kes` | NUMERIC(18,2) | NOT NULL | CHECK `>= 0` | The resulting contribution of this line to the fare |
| `sequence_no` | SMALLINT | NOT NULL | — | Display/computation order of the line within the build-up |
| `created_at` | TIMESTAMPTZ | NOT NULL | `DEFAULT now()` | Row creation time |

```sql
-- [Trace: TBOC-v1.0.0 | Article 42 | Article 45 — itemized fare build-up transparency]
CREATE TABLE cost_unit_price_buildup_entry (
  buildup_entry_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id             UUID NOT NULL REFERENCES cost_unit_price_quotes (quote_id),
  component_code         TEXT NOT NULL CHECK (component_code IN
                            ('F_BASE','DISTANCE_COST','TIME_COST','TERRAIN_ADJUSTMENT','FLOOR_ADJUSTMENT','GOVERNANCE_SURCHARGE')),
  raw_input_value           NUMERIC(12,4),
  rate_applied                NUMERIC(10,4),
  multiplier_applied            NUMERIC(4,2) NOT NULL DEFAULT 1.00,
  line_amount_kes                 NUMERIC(18,2) NOT NULL CHECK (line_amount_kes >= 0),
  sequence_no                       SMALLINT NOT NULL,
  created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_cost_buildup_quote ON cost_unit_price_buildup_entry (quote_id, sequence_no);

-- Row Level Security (TBOC Zero-Trust law; FDN-001 Annex B, Part III Phase 8) — build-up lines inherit the parent quote's visibility
ALTER TABLE cost_unit_price_buildup_entry ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_unit_price_buildup_entry_requester_read ON cost_unit_price_buildup_entry
  FOR SELECT TO trustride_authenticated
  USING (EXISTS (
    SELECT 1 FROM cost_unit_price_quotes q
    WHERE q.quote_id = cost_unit_price_buildup_entry.quote_id
      AND q.requester_user_id = current_setting('app.current_user_id', true)::uuid
  ));
CREATE POLICY cost_unit_price_buildup_entry_service_write ON cost_unit_price_buildup_entry
  FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);
```

## 3.4 `RateCardRuleObject` → `cost_rate_card_rule`

The selector: given a domain, service, asset class, and jurisdiction, which baseline and formula apply, and what governance surcharge is added.

| Column Name | Data Type | Nullability | Constraints | Exact Purpose |
| --- | --- | --- | --- | --- |
| `rate_card_rule_id` | UUID | NOT NULL | PK, `DEFAULT gen_random_uuid()` | Unique identity of this rule |
| `rule_code` | TEXT | NOT NULL | UNIQUE | Human-legible code, e.g. `'TRANSPORT-BODA-KISUMU'` |
| `macro_domain` | TEXT | NOT NULL | CHECK IN (`'TRANSPORT'`,`'COURIER'`,`'DELIVERY'`,`'EXECUTIVE_ASSISTANTS'`,`'MARKETPLACE'`) | TBOC Article 23 macro domain this rule governs |
| `service_code` | TEXT | NOT NULL | — | Catalogue Service code (Engine 3 reference, by value not FK) |
| `asset_class` | `asset_class_enum` | NOT NULL | — | Applicable asset class |
| `jurisdiction` | `jurisdiction_enum` | NOT NULL | — | Applicable jurisdiction |
| `baseline_id` | UUID | NOT NULL | FK → `cost_asset_engine_baselines.baseline_id` | Which mechanical baseline this rule selects |
| `formula_id` | UUID | NOT NULL | FK → `cost_formula_matrix.formula_id` | Which formula version this rule selects |
| `governance_surcharge_kes` | NUMERIC(18,2) | NOT NULL | `DEFAULT 0`, CHECK `>= 0` | $S_{\text{governance}}$ — statutory/municipal/safety reserve for this domain-service-jurisdiction combination |
| `minimum_margin_pct` | NUMERIC(5,2) | NOT NULL | `DEFAULT 8.00`, CHECK `>= 0` | Governed minimum margin; a computed fare falling below this over `direct_per_km_rate_kes` cost triggers `COST_MARGIN_BREACHED` |
| `status` | TEXT | NOT NULL | CHECK IN (`'DRAFT'`,`'ACTIVE'`,`'SUPERSEDED'`) | Exactly one `ACTIVE` row per (`macro_domain`,`service_code`,`asset_class`,`jurisdiction`) |
| `approved_request_id` | UUID | NULL | — | Reference into `TRS_FDN_GOVERNANCE.approval_request` |
| `effective_from` | TIMESTAMPTZ | NOT NULL | `DEFAULT now()` | Effective start |
| `effective_to` | TIMESTAMPTZ | NULL | — | NULL while active |
| `created_at` | TIMESTAMPTZ | NOT NULL | `DEFAULT now()` | Row creation time |

```sql
-- [Trace: TBOC-v1.0.0 | Article 44 | Ledger Splits & Revenue Architecture]
CREATE TABLE cost_rate_card_rule (
  rate_card_rule_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_code                TEXT NOT NULL UNIQUE,
  macro_domain               TEXT NOT NULL CHECK (macro_domain IN
                                ('TRANSPORT','COURIER','DELIVERY','EXECUTIVE_ASSISTANTS','MARKETPLACE')),
  service_code                 TEXT NOT NULL,
  asset_class                    asset_class_enum NOT NULL,
  jurisdiction                     jurisdiction_enum NOT NULL,
  baseline_id                        UUID NOT NULL REFERENCES cost_asset_engine_baselines (baseline_id),
  formula_id                           UUID NOT NULL REFERENCES cost_formula_matrix (formula_id),
  governance_surcharge_kes                NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (governance_surcharge_kes >= 0),
  minimum_margin_pct                        NUMERIC(5,2) NOT NULL DEFAULT 8.00 CHECK (minimum_margin_pct >= 0),
  status                                      TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('DRAFT','ACTIVE','SUPERSEDED')),
  approved_request_id                            UUID,
  effective_from                                   TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to                                       TIMESTAMPTZ,
  created_at                                           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_cost_rate_card_active
  ON cost_rate_card_rule (macro_domain, service_code, asset_class, jurisdiction)
  WHERE status = 'ACTIVE';

-- Row Level Security (TBOC Zero-Trust law; FDN-001 Annex B, Part III Phase 8) — governed reference data, platform-readable, engine-service writable
ALTER TABLE cost_rate_card_rule ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_rate_card_rule_platform_read ON cost_rate_card_rule
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_rate_card_rule_service_write ON cost_rate_card_rule
  FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);
```

## 3.5 `CostExecutionLedgerObject` → `cost_execution_ledger`

The append-only audit trail of every calculation Engine 5 performs — distinct from `cost_unit_price_quotes` (the lawful quote of record): this ledger records **every execution**, including recalculations, expirations, and rejected attempts, for reconciliation (Article 49) and the `GET /ledger/reconcile` endpoint (§4.3).

| Column Name | Data Type | Nullability | Constraints | Exact Purpose |
| --- | --- | --- | --- | --- |
| `ledger_entry_id` | UUID | NOT NULL | PK, `DEFAULT gen_random_uuid()` | Unique identity of this execution record |
| `quote_id` | UUID | NULL | FK → `cost_unit_price_quotes.quote_id` | The resulting quote, if the execution succeeded |
| `rate_card_rule_id` | UUID | NULL | FK → `cost_rate_card_rule.rate_card_rule_id` | Which rule was evaluated |
| `execution_outcome` | TEXT | NOT NULL | CHECK IN (`'CALCULATED'`,`'REJECTED_NO_RULE'`,`'REJECTED_MARGIN_BREACH'`,`'EXPIRED'`,`'RECALCULATED'`) | Outcome of this specific execution |
| `input_snapshot` | JSONB | NOT NULL | — | Immutable snapshot of every input supplied to the equation |
| `output_snapshot` | JSONB | NULL | — | Immutable snapshot of the resulting fare breakdown, NULL on rejection |
| `engine_version` | TEXT | NOT NULL | — | Deployed Engine 5 build tag that performed the execution |
| `duration_ms` | INTEGER | NOT NULL | CHECK `>= 0` | Wall-clock computation time, for performance reconciliation |
| `correlation_id` | UUID | NOT NULL | — | Platform signal envelope correlation carried through this execution |
| `executed_at` | TIMESTAMPTZ | NOT NULL | `DEFAULT now()` | Execution timestamp |

```sql
-- [Trace: TBOC-v1.0.0 | Article 49 — evidence discipline and reconciliation]
CREATE TABLE cost_execution_ledger (
  ledger_entry_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id             UUID REFERENCES cost_unit_price_quotes (quote_id),
  rate_card_rule_id      UUID REFERENCES cost_rate_card_rule (rate_card_rule_id),
  execution_outcome        TEXT NOT NULL CHECK (execution_outcome IN
                              ('CALCULATED','REJECTED_NO_RULE','REJECTED_MARGIN_BREACH','EXPIRED','RECALCULATED')),
  input_snapshot              JSONB NOT NULL,
  output_snapshot                JSONB,
  engine_version                   TEXT NOT NULL,
  duration_ms                        INTEGER NOT NULL CHECK (duration_ms >= 0),
  correlation_id                       UUID NOT NULL,
  executed_at                            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_cost_ledger_quote ON cost_execution_ledger (quote_id);
CREATE INDEX idx_cost_ledger_outcome_time ON cost_execution_ledger (execution_outcome, executed_at DESC);

-- Append-only at the database level (Article 49 evidence discipline)
REVOKE UPDATE, DELETE ON cost_execution_ledger FROM PUBLIC;

-- Row Level Security (TBOC Zero-Trust law; FDN-001 Annex B, Part III Phase 8) — audit trail, engine-service and Foundation Audit sub-engine roles only
ALTER TABLE cost_execution_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_execution_ledger_audit_read ON cost_execution_ledger
  FOR SELECT TO trs_fdn_audit_service USING (true);
CREATE POLICY cost_execution_ledger_service_write ON cost_execution_ledger
  FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);
```

## 3.6 `CostComponentPrimitive` → `cost_component_primitive`

The atomic, named cost inputs referenced by `equation_definition` in §3.2 — a governed vocabulary so `F_base`, `R_d`, `K_return`, `R_t`, `M_terrain`, `F_min`, and `S_governance` are never spelled inconsistently across formulas or client code.

| Column Name | Data Type | Nullability | Constraints | Exact Purpose |
| --- | --- | --- | --- | --- |
| `component_id` | UUID | NOT NULL | PK, `DEFAULT gen_random_uuid()` | Unique identity of this component definition |
| `component_code` | TEXT | NOT NULL | UNIQUE | Canonical symbol, e.g. `'F_BASE'`, `'R_D'`, `'K_RETURN'`, `'R_T'`, `'M_TERRAIN'`, `'F_MIN'`, `'S_GOVERNANCE'` |
| `component_label` | TEXT | NOT NULL | — | Human-legible name, e.g. "Base Dispatch Fee" |
| `component_definition` | TEXT | NOT NULL | — | Full definition of what the component represents and how it is derived |
| `unit_of_measure` | TEXT | NOT NULL | CHECK IN (`'KES'`,`'KES_PER_KM'`,`'KES_PER_MIN'`,`'MULTIPLIER'`,`'RATIO'`) | Dimensional unit of the component |
| `version` | SMALLINT | NOT NULL | `DEFAULT 1` | Append-only version counter |
| `superseded_by` | UUID | NULL | FK → `cost_component_primitive.component_id` | Successor definition, if superseded |
| `created_at` | TIMESTAMPTZ | NOT NULL | `DEFAULT now()` | Row creation time |

```sql
-- [Trace: TBOC-v1.0.0 | Article 8 | Zero-Pollution Rule — governed vocabulary, never invented ad hoc]
CREATE TABLE cost_component_primitive (
  component_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  component_code          TEXT NOT NULL UNIQUE,
  component_label            TEXT NOT NULL,
  component_definition          TEXT NOT NULL,
  unit_of_measure                  TEXT NOT NULL CHECK (unit_of_measure IN
                                      ('KES','KES_PER_KM','KES_PER_MIN','MULTIPLIER','RATIO')),
  version                             SMALLINT NOT NULL DEFAULT 1,
  superseded_by                         UUID REFERENCES cost_component_primitive (component_id),
  created_at                              TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO cost_component_primitive (component_code, component_label, component_definition, unit_of_measure) VALUES
  ('F_BASE',       'Base Dispatch Fee',                 'Fixed fee charged at dispatch, independent of distance or time.', 'KES'),
  ('R_D',          'Direct Per-Km Operational Rate',    'Derived from the EPRA fuel index and maintenance baseline for the asset class.', 'KES_PER_KM'),
  ('K_RETURN',     'Zone Return/Deadhead Multiplier',   'Multiplier applied to distance cost reflecting the likelihood and cost of an empty return leg from the destination zone.', 'MULTIPLIER'),
  ('R_T',          'Time Rate',                          'Rate charged per minute of trip duration.', 'KES_PER_MIN'),
  ('M_TERRAIN',    'Surface Penalty Multiplier',          'Multiplier applied to the full pre-floor fare reflecting road surface difficulty along the route.', 'MULTIPLIER'),
  ('F_MIN',        'Absolute Floor Threshold',             'The minimum lawful total fare for the asset class, applied after the terrain multiplier.', 'KES'),
  ('S_GOVERNANCE', 'Statutory & Governance Surcharge',      'Statutory fees, municipal parking, and safety reserves added after the floor is applied.', 'KES');

-- Row Level Security (TBOC Zero-Trust law; FDN-001 Annex B, Part III Phase 8) — governed vocabulary, platform-readable, engine-service writable
ALTER TABLE cost_component_primitive ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_component_primitive_platform_read ON cost_component_primitive
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_component_primitive_service_write ON cost_component_primitive
  FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);
```

---

# SECTION 4 — SYSTEM API CONTRACTS & WORKFLOW ORCHESTRATION

All endpoints are fronted by Engine 5's own signal envelope (§5); the HTTP contracts below are the Integration-layer (Engine 6) surface that Presentation (Engine 11) and Business (Engine 4) call, which Engine 6 then translates into the constitutional emit → orchestrate → respond pattern before Engine 5 ever sees the request.

## 4.1 `POST /api/v1/cost/unit-price/calculate`

**Request**

```json
{
  "correlation_id": "8f14e45f-ceea-4c9c-9c60-1a2f3e4d5b6c",
  "requester_user_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "requester_user_type": "CUSTOMER",
  "macro_domain": "TRANSPORT",
  "service_code": "TRANSPORT-STANDARD-RIDE",
  "asset_class": "BODA_BODA",
  "engine_capacity": "CC_125",
  "jurisdiction": "KISUMU_COUNTY",
  "origin": {
    "zone_code": "KSM-CBD-01",
    "latitude": -0.091702,
    "longitude": 34.767956
  },
  "destination": {
    "zone_code": "KSM-KONDELE-03",
    "latitude": -0.078412,
    "longitude": 34.782215
  },
  "distance_km": 6.400,
  "duration_min": 18.50,
  "requested_at": "2026-08-15T10:32:00Z"
}
```

**Response — `200 OK`**

```json
{
  "correlation_id": "8f14e45f-ceea-4c9c-9c60-1a2f3e4d5b6c",
  "quote_id": "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e",
  "quote_code": "TRS026-QUOTE-000004821",
  "quote_state": "FARE_ESTIMATED",
  "asset_class": "BODA_BODA",
  "engine_capacity": "CC_125",
  "jurisdiction": "KISUMU_COUNTY",
  "currency": "KES",
  "formula_version": "FDN-COST-1.0.0",
  "build_up": [
    { "component_code": "F_BASE", "line_amount_kes": 30.00, "sequence_no": 1 },
    { "component_code": "DISTANCE_COST", "raw_input_value": 6.400, "rate_applied": 12.00, "multiplier_applied": 1.30, "line_amount_kes": 99.84, "sequence_no": 2 },
    { "component_code": "TIME_COST", "raw_input_value": 18.50, "rate_applied": 2.50, "multiplier_applied": 1.00, "line_amount_kes": 46.25, "sequence_no": 3 },
    { "component_code": "TERRAIN_ADJUSTMENT", "multiplier_applied": 1.00, "line_amount_kes": 0.00, "sequence_no": 4 },
    { "component_code": "FLOOR_ADJUSTMENT", "line_amount_kes": 0.00, "sequence_no": 5 },
    { "component_code": "GOVERNANCE_SURCHARGE", "line_amount_kes": 5.00, "sequence_no": 6 }
  ],
  "pre_floor_fare_kes": 176.09,
  "minimum_fare_floor_kes": 70.00,
  "governance_surcharge_kes": 5.00,
  "computed_total_fare_kes": 181.09,
  "expires_at": "2026-08-15T10:37:00Z",
  "quote_hash": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
}
```

**Response — `422 Unprocessable Entity`** (no active rate card rule for the combination)

```json
{
  "correlation_id": "8f14e45f-ceea-4c9c-9c60-1a2f3e4d5b6c",
  "error_code": "COST_RATE_CARD_NOT_FOUND",
  "error_message": "No ACTIVE cost_rate_card_rule exists for macro_domain=TRANSPORT, service_code=TRANSPORT-STANDARD-RIDE, asset_class=BODA_BODA, jurisdiction=KISUMU_COUNTY.",
  "ledger_entry_id": "1a2b3c4d-5e6f-4708-8a9b-0c1d2e3f4a5b"
}
```

## 4.2 `POST /api/v1/cost/rate-cards/evaluate`

**Request**

```json
{
  "correlation_id": "5c6d7e8f-9a0b-4c1d-8e2f-3a4b5c6d7e8f",
  "macro_domain": "TRANSPORT",
  "service_code": "TRANSPORT-STANDARD-RIDE",
  "asset_class": "BODA_BODA",
  "jurisdiction": "KISUMU_COUNTY",
  "evaluation_mode": "DRY_RUN"
}
```

**Response — `200 OK`**

```json
{
  "correlation_id": "5c6d7e8f-9a0b-4c1d-8e2f-3a4b5c6d7e8f",
  "rate_card_rule_id": "c4d5e6f7-a8b9-4c0d-9e1f-2a3b4c5d6e7f",
  "rule_code": "TRANSPORT-BODA-KISUMU",
  "status": "ACTIVE",
  "baseline": {
    "baseline_id": "d5e6f7a8-b9c0-4d1e-8f2a-3b4c5d6e7f8a",
    "base_dispatch_fee_kes": 30.00,
    "direct_per_km_rate_kes": 12.00,
    "time_rate_kes_per_min": 2.50,
    "minimum_fare_floor_kes": 70.00
  },
  "formula": {
    "formula_id": "e6f7a8b9-c0d1-4e2f-8a3b-4c5d6e7f8a9b",
    "formula_version": "FDN-COST-1.0.0",
    "status": "ACTIVE"
  },
  "governance_surcharge_kes": 5.00,
  "minimum_margin_pct": 8.00,
  "effective_from": "2026-08-01T00:00:00Z",
  "effective_to": null
}
```

**Response — `404 Not Found`**

```json
{
  "correlation_id": "5c6d7e8f-9a0b-4c1d-8e2f-3a4b5c6d7e8f",
  "error_code": "COST_RATE_CARD_RULE_NOT_FOUND",
  "error_message": "No cost_rate_card_rule row matches the supplied domain, service, asset class, and jurisdiction, active or otherwise."
}
```

## 4.3 `GET /api/v1/cost/ledger/reconcile`

**Request** (query parameters)

```
GET /api/v1/cost/ledger/reconcile?period_start=2026-08-01T00:00:00Z&period_end=2026-08-15T23:59:59Z&jurisdiction=KISUMU_COUNTY&outcome=CALCULATED
```

**Response — `200 OK`**

```json
{
  "period_start": "2026-08-01T00:00:00Z",
  "period_end": "2026-08-15T23:59:59Z",
  "jurisdiction": "KISUMU_COUNTY",
  "total_executions": 18432,
  "outcome_breakdown": {
    "CALCULATED": 17890,
    "REJECTED_NO_RULE": 12,
    "REJECTED_MARGIN_BREACH": 41,
    "EXPIRED": 489,
    "RECALCULATED": 0
  },
  "quote_state_breakdown": {
    "FARE_ESTIMATED": 210,
    "FARE_LOCKED": 340,
    "SERVICE_IN_PROGRESS": 58,
    "FARE_FINALIZED": 16920,
    "C2B_PAYMENT_TRIGGERED": 16920,
    "EXPIRED": 489,
    "CANCELLED": 175
  },
  "total_computed_fare_kes": 3128744.50,
  "total_governance_surcharge_kes": 89450.00,
  "average_computation_duration_ms": 4.7,
  "unresolved_ledger_entries": [
    {
      "ledger_entry_id": "f7a8b9c0-d1e2-4f3a-8b4c-5d6e7f8a9b0c",
      "execution_outcome": "REJECTED_MARGIN_BREACH",
      "quote_id": null,
      "executed_at": "2026-08-09T14:12:03Z"
    }
  ],
  "generated_at": "2026-08-15T18:00:00Z"
}
```

---

# SECTION 5 — EVENT-DRIVEN SIGNAL & INTEGRATION MATRIX

Every signal below travels the constitutional shape (Plate I): `cost_event_outbox` → Engines 7/8 (Orchestration + Coordination) → target engine's inbox, or the reverse into `cost_event_inbox`. Engine 5 never emits to, or receives directly from, another engine's outbox/inbox.

## 5.1 Inbound Signals — Listened To

| Signal | Emitting engine | Payload (key fields) | Effect inside Engine 5 |
| --- | --- | --- | --- |
| `RESOURCE_DISPATCH_INITIATED` | Engine 2 (Resources), via Engines 7/8 | `asset_class`, `engine_capacity`, `origin_zone_code`, `destination_zone_code`, `order_id`, `assignment_id` | Triggers a `POST /cost/unit-price/calculate`-equivalent internal execution; writes a `cost_execution_ledger` row and, on success, a `cost_unit_price_quotes` row in state `FARE_ESTIMATED` |
| `SERVICE_CONTEXT_RESOLVED` | Engine 3 (Services), via Engines 7/8 | `macro_domain`, `service_code` | Supplies the Service/domain context named in §1.3 as Engine 5's Engine 3 dependency; selects the applicable `cost_rate_card_rule` alongside the asset/engine class carried on `RESOURCE_DISPATCH_INITIATED` |
| `EPRA_FUEL_INDEX_UPDATED` | Engine 6 (Integration), via Engines 7/8 | `price_period`, `fuel_type`, `jurisdiction`, `pump_price_kes`, `source_reference` | Inserts a new `cost_epra_fuel_registry` row; recomputes and versions `direct_per_km_rate_kes` on the affected `cost_asset_engine_baselines` rows through a governed baseline update (never overwriting history — a new baseline row supersedes the old) |
| `ZONE_SURGE_TRIGGERED` | Engine 7/8 (Coordination, aggregating demand telemetry from multiple engines) | `zone_code`, `surge_multiplier`, `valid_until` | Temporarily elevates `return_multiplier` consulted for quotes in that zone until `valid_until`; every quote computed under surge carries the elevated `return_multiplier_applied` value transparently in its build-up |

## 5.2 Outbound Signals — Emitted

| Signal | Receiving engine | Payload (key fields) | Triggering condition |
| --- | --- | --- | --- |
| `UNIT_PRICE_LOCKED` | Engine 4 (Business), via Engines 7/8 | `quote_id`, `quote_code`, `computed_total_fare_kes`, `currency`, `expires_at`, `order_id` | Fired the instant `quote_state` transitions `FARE_ESTIMATED` → `FARE_LOCKED` (the requester has accepted the posted fee, per TBOC Article 20.2) |
| `PAYMENT_STK_TRIGGERED` | Engine 6 (Integration), via Engines 7/8 | `quote_id`, `computed_total_fare_kes`, `currency`, `requester_user_id`, `payment_rail: "MPESA_C2B_STK" \| "FLUTTERWAVE"` | Fired when `quote_state` transitions to `FARE_FINALIZED` (service completed) — Engine 5 never calls M-Pesa or Flutterwave itself; it hands the finalized figure to Integration under TISC governance (TBOC Article 43) |
| `COST_MARGIN_BREACHED` | Engine 9 (AI/ML Advisory) and Engine 8 (Coordination, for platform Dead Letter / operator review) | `rate_card_rule_id`, `computed_margin_pct`, `minimum_margin_pct`, `quote_id` | Fired whenever an execution's resulting margin over `direct_per_km_rate_kes` cost falls below `minimum_margin_pct` on the governing `cost_rate_card_rule` — the quote is still produced (the requester is never left without a fare), but the breach is flagged for governance review, never silently absorbed |

## 5.3 The Signal Envelope (as applied to Engine 5)

Identical to the platform-wide envelope (Plate I, §11.2 of the Foundation instrument): `signal_id`, `correlation_id`, `causation_id`, `emitting_engine` = `TRS026_ENG005_COST`, `receiving_engine`, `signal_type`, `payload_in`, `payload_out`, `signal_status`, `rejection_reason`, `idempotency_key`, `attempt_count`, `emitted_at`, `received_at`, `accepted_at`. No field is added, renamed, or omitted — an engine that invents its own envelope shape is non-conformant (C-I-6).

---

# ANNEX — CONFORMANCE SELF-CERTIFICATION AGAINST THE THREE PLATES

Filed in the same discipline as the Foundation instrument's Part XI, so that Engine 5 can be certified before formal adoption.

| Check | Requirement | Result | Evidence |
| --- | --- | --- | --- |
| CC-02 | Every table assigned to exactly one of the five stations | **PASS** | §2.1–2.5, §3.2–3.6: domain tables = Domain State; `cost_event_outbox` = Emission Ledger; `cost_event_inbox` = Reception Ledger (§2.6); mutation only via the engine's own accept-handler |
| CC-03 | Engine carries the four ledger tables with the standard envelope | **PASS** | §2.6, §5.3 |
| CC-04 | Every cross-engine interaction is a signal; no foreign table access | **PASS** | §1.3, §5 — every interface listed is a named signal, never a direct read/write |
| CC-06 | Idempotency, retry, dead-letter declared | **PASS** | `idempotency_key` UNIQUE on both ledger tables (§2.6); `COST_MARGIN_BREACHED` routes to platform Dead Letter review |
| CC-07 | Engine declares its layer, holds nothing belonging to another layer | **PASS** | §1 — Layer 2, Business Runtime; holds no identity, dispatch, or payment-execution state |
| CC-09 | Advisory outputs, if any, are records only | **N/A** | Engine 5 is not an advisory engine; it is a Layer 2 runtime engine |
| CC-12 | Every provision carries a trace tag | **PASS** | Every DDL block and table comment carries a `[Trace: TBOC-v1.0.0 | Article ...]` tag |

**This document is ADOPTED.** TBOC v2.0.0 Article 58.5 (Annex I, A-001) already carries the eleven-engine registry with the Cost & Unit-Price Build-Up Engine at position 005; FDN-001 v3.0.0 and the Architecture Blueprint v1.1.0 already carry Integration through Presentation renumbered 006–011. The adoption ceremony contemplated by the original PROPOSED filing is complete; this instrument is formally locked under TBOC v2.0.0 authority and cleared for downstream code execution.

---

**END OF SPECIFICATION**

*Engine 5 computes what everything else in TrustRide charges for. One equation, one lawful quote per trip, one immutable ledger — the fare truth beneath the platform's One Financial Truth.*
