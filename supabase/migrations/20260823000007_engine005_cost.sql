-- ============================================================================
-- TRUSTRIDE SERVICES PLATFORM
-- ============================================================================
-- PLATFORM ID          : b302bb5d-7d20-41e9-a074-a18d8ebd2aa5
-- PLATFORM CODE        : TRS026
-- PLATFORM NAME        : TRUSTRIDE_SERVICES
-- SCHEMA               : trustride
-- ENGINE NO            : ENGINE_005
-- ENGINE ID            : c1a2b3c4-0005-4eng-8005-005cost0000005
-- ENGINE CODE          : TRS026_ENG005_COST
-- ENGINE DOMAIN        : Service Cost & Fare Economics
-- ENGINE CLASS         : Cost Engine
-- ENGINE TYPE          : Cost/Fare Determination
-- ENGINE NAME          : TrustRide Cost Buildup
-- ENGINE DESCRIPTION   : Determines the economically defensible cost and
--                        proposed fare for each service by constructing the
--                        full expected cost of fulfilment -- resource cost,
--                        route, time, waiting, return-trip exposure, empty-
--                        return probability, regional conditions, resource-
--                        specific cost, operational risk, overhead, and
--                        approved margin -- never a bare distance x rate.
-- ENGINE FUNCTION      : Protects TrustRide from underpricing and
--                        uncontrolled cost leakage while preventing
--                        unjustified overcharging. Supplies the
--                        economically justified proposed price to Business;
--                        never approves the contract, executes the job,
--                        receives payment, or posts the ledger.
-- PLATFORM VERSION     : 1.0.0
-- ENGINE VERSION       : 2.0.0
-- MIGRATION DATA
-- FILE NAME            : 20260823000007_engine005_cost.sql
-- INSTALLATION ORDER   : 005
-- STATUS               : COMPLETE -- one single migration file, 22 tables,
--                        applied on top of Foundation + Resources +
--                        Services + Orchestration + Coordination. SUPERSEDES
--                        the prior 13-table Engine 5 (same filename,
--                        reset to clean slate -- see Correction 0).
-- CREATED AT           : 2026-08-23
-- CREATED BY           : Onyango Albert Chitayi (Founder) + Engineering
-- ============================================================================
--
-- Source: "Engine 005 SPECIFICATIONS.docx" and "TRUSTRIDE MONEY_FINANCIAL
-- CONSTITUTION.docx" (MNY-15), both supplied directly by the Founder,
-- 2026-08-23, with the explicit instruction "IMPLEMENT ENGINE 005 EXACTLY
-- FROM THE DOCUMENTS I HAVE PROVIDED."
--
--   0. SUPERSESSION: this file replaces the prior TRS026-ENG005-COST-001
--      v1.1.1-based 13-table Engine 5 (committed, pushed, live on
--      trustride-stagging as of this same day) with the Founder's own
--      17-table Cost Buildup core, per the Engine 005 SPECIFICATIONS
--      document. trustride-stagging's prior Engine 5 objects are reset to
--      clean slate by the Founder before this file applies (same pattern
--      as Foundation's own 2026-08-23 reset) -- the destructive DROP is
--      the Founder's own action, per the platform's standing safety rule.
--      Engine 2's fn_resource_assign extension and Engine 7's
--      fn_orch_dispatch_cycle/fn_orch_destination_cache_sync extensions
--      from the prior Engine 5 file are UNCHANGED and re-declared here
--      identically (idempotent CREATE OR REPLACE) -- they belong to
--      Resources/Orchestration, not to Cost's own redesign.
--   1. THE 17 PRIMARY TABLES, exactly per the Founder's own document,
--      mapped from (and, where noted, replacing) the prior 13-table
--      design: cost_registry (was cost_rate_card_rule -- the selector),
--      cost_model (was cost_formula_matrix), cost_model_version (new --
--      dedicated version history, previously inline via effective_to/
--      superseded_by), cost_component (was cost_component_primitive),
--      cost_component_rule (new -- each component's OWN calculation rule,
--      independently versioned, rather than living inside one combined
--      equation_definition JSON blob), cost_rate (was cost_asset_engine_
--      baselines), cost_rate_version (new -- dedicated version history),
--      route_cost_factor (was cost_road_segments_override, broadened
--      beyond terrain alone), return_trip_factor (was cost_operational_
--      zones.return_multiplier, given its own governed, versioned table),
--      empty_return_probability (new -- the Founder's own words, "the real
--      substantive upgrade in your proposal"), regional_cost_factor (new
--      -- a standing regional dimension, distinct from ZONE_SURGE_
--      TRIGGERED's temporary override), resource_cost_factor (new --
--      per-individual-resource cost differentiation, by value reference
--      into Engine 2), operational_risk_factor (new -- an explicit risk/
--      safety cost line), fare_calculation (was half of cost_unit_price_
--      quotes -- the computation record), fare_quote (the other half --
--      the customer-facing, lifecycle-managed artifact), cost_record (was
--      cost_execution_ledger), cost_event (kept as two tables,
--      cost_event_outbox/cost_event_inbox, per this platform's own
--      constitutional Signal Envelope law -- Article 59-60 requires
--      exactly one outbox and one inbox per engine; "cost_event" in the
--      Founder's document is the conceptual category, not a literal
--      single-table demand overriding the platform's own adopted
--      envelope shape used identically by all ten other engines).
--   2. Supporting reference infrastructure, not among the headline 17 but
--      structurally required underneath them (named as such, not silently
--      smuggled in): cost_operational_zones (pure geo/jurisdiction
--      reference that return_trip_factor/empty_return_probability/
--      regional_cost_factor key off of), cost_epra_fuel_registry
--      (regulatory fuel-price reference feeding cost_rate), fare_
--      calculation_line (the itemized, transparent receipt behind a
--      fare_calculation -- the "line-by-line fare transparency" the
--      Founder's own comparison confirms is already covered, kept as
--      fare_calculation's companion rather than folded into a JSON blob),
--      cost_pending_service_context (this file's own Correction, unchanged
--      from the prior design -- the cross-signal join RESOURCE_DISPATCH_
--      INITIATED/SERVICE_CONTEXT_RESOLVED needs, which no source document
--      anywhere names).
--   3. THE EQUATION ITSELF, extended per the Founder's own model:
--      TOTAL EXPECTED COST = resource cost (cost_rate, adjusted by
--      resource_cost_factor for the specific unit) + route cost
--      (route_cost_factor) + time cost + waiting exposure (NEW -- no
--      waiting_min input exists anywhere upstream yet; defaults to 0,
--      honestly, rather than fabricated) + return-trip exposure
--      (return_trip_factor) + empty-return probability (empty_return_
--      probability, applied as an additional cost loading) + regional
--      conditions (regional_cost_factor) + operational risk
--      (operational_risk_factor) + overhead (a governed pct on
--      cost_registry) -> floor -> + approved margin check (minimum_
--      margin_pct on cost_registry, unchanged in spirit from before).
--      "Resource availability" and "repositioning cost" from the
--      Founder's own equation prose are not given their own tables in the
--      17-list -- resource availability is Engine 2's own exclusive
--      domain (Cost never gates on it, only consumes the dispatch that
--      already passed that gate); repositioning cost is treated as what
--      return_trip_factor and empty_return_probability already compute
--      together, not a third overlapping table.
--   4. EXPLICIT, NAMED CAVEAT (the Founder's own words, preserved
--      verbatim in spirit): empty_return_probability, resource_cost_
--      factor, regional_cost_factor, and operational_risk_factor are
--      GOVERNED, STATIC inputs in this increment -- administered like
--      cost_rate always was, not yet computed by anything. Making them
--      genuinely dynamic requires Engine 9 (Advisory) or Engine 10
--      (Modelling) feeding real predictions in, which neither engine yet
--      does (both unbuilt) -- named as real, deferred scope, not silently
--      implied as "already intelligent."
--   5. MNY-15 (the Money Specification) read in full and deliberately NOT
--      absorbed into this file: its own source document (the Engine 005
--      SPECIFICATIONS doc, same delivery) states plainly that "Cost
--      Buildup is not Payment and is not Finance... cannot create or
--      approve the commercial contract, execute the job, receive payment
--      or post the ledger." MNY-15's Payment/Settlement/Ledger/Treasury/
--      Payroll/Taxation domain confirms and reinforces Engine 5's own
--      boundary rather than expanding it -- it is real, adopted,
--      constitutional law for a future engine/extension (most likely
--      Business's settlement machinery and a not-yet-built Ledger
--      authority), not fabricated into Cost Buildup here. Flagged
--      explicitly per the Founder's own instruction to read both
--      documents, rather than silently picking an interpretation.
--   6. All corrections from the prior 13-table file that are still
--      structurally relevant carry forward unchanged: the digest()/
--      extensions search_path fix, the CASE-to-enum cast discipline, the
--      trs_fdn_audit_service role-naming fix, explicit per-function
--      GRANTs (never a schema-wide blanket), and the Engine 7 dispatch-
--      cycle ordering fix (UNION ALL by emitted_at across every
--      registered outbox) -- re-verified intact in this rebuild, not
--      re-broken by the redesign.
--
-- ============================================================================

-- ============================================================================
-- PHASE 0 -- EXTENSIONS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

-- ============================================================================
-- PHASE 1 -- SCHEMA + EARLY ROLE CREATION
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng005_cost_service') THEN
    CREATE ROLE trs026_eng005_cost_service NOLOGIN;
  END IF;
END
$$;

-- Correction 12: the prior reset (DROP TABLE/TYPE/ROLE for Cost's own
-- objects) never touched Cost's own FUNCTIONS -- dropping a table does not
-- cascade to an unrelated function whose body merely references it by name.
-- Several of this rebuild's function names intentionally match the prior
-- 13-table design's names (fn_cost_quote_lock/finalize/mark_in_progress/
-- expire_sweep/cancel, fn_cost_zone_surge_apply, fn_cost_inbox_process, the
-- accept-handlers); CREATE OR REPLACE only overwrites when the argument
-- signature is IDENTICAL -- a signature change (fn_cost_quote_cancel lost
-- its old p_reason parameter) instead creates a second, stale overload
-- sitting alongside the new one, exactly the "ADDED parameters creates a
-- stale overload" class of bug already seen this session on Resources'
-- fn_resource_assign. Rather than enumerate every old signature by hand,
-- sweep every fn_cost_* function that exists right now, unconditionally,
-- before creating any of this file's own -- this makes the migration
-- correct regardless of what a prior manual reset did or didn't cover.
DO $$
DECLARE
  v_fn RECORD;
BEGIN
  FOR v_fn IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'trustride' AND p.proname LIKE 'fn_cost_%'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %s CASCADE', v_fn.signature);
  END LOOP;
END
$$;

-- ============================================================================
-- PHASE 2 -- ENUMS
-- ============================================================================
CREATE TYPE trustride.cost_asset_class_enum AS ENUM (
  'BODA_BODA', 'TUKTUK', 'PICKUP_TOWN', 'VAN_CARGO', 'TRUCK_LIGHT', 'EXECUTIVE_ASSISTANT'
);
CREATE TYPE trustride.cost_engine_capacity_enum AS ENUM (
  'EV_ELECTRIC', 'CC_100', 'CC_125', 'CC_150', 'CC_200', 'TON_1_0', 'TON_3_0', 'NOT_APPLICABLE'
);
CREATE TYPE trustride.cost_jurisdiction_enum AS ENUM (
  'KISUMU_COUNTY', 'VIHIGA_COUNTY', 'SIAYA_COUNTY', 'NANDI_COUNTY', 'UASIN_GISHU_COUNTY', 'NAIROBI_METRO'
);
CREATE TYPE trustride.cost_quote_state_enum AS ENUM (
  'FARE_ESTIMATED', 'FARE_LOCKED', 'SERVICE_IN_PROGRESS', 'FARE_FINALIZED',
  'C2B_PAYMENT_TRIGGERED', 'EXPIRED', 'CANCELLED'
);
CREATE TYPE trustride.cost_user_type_enum AS ENUM (
  'CUSTOMER', 'RIDER', 'DRIVER', 'MERCHANT', 'EXECUTIVE_ASSISTANT', 'ADMIN'
);
CREATE TYPE trustride.cost_governance_status_enum AS ENUM ('DRAFT', 'ACTIVE', 'SUPERSEDED');
CREATE TYPE trustride.cost_component_unit_enum AS ENUM ('KES', 'KES_PER_KM', 'KES_PER_MIN', 'MULTIPLIER', 'RATIO', 'PERCENT');
CREATE TYPE trustride.cost_execution_outcome_enum AS ENUM ('CALCULATED', 'REJECTED_NO_REGISTRY', 'REJECTED_MARGIN_BREACH', 'EXPIRED', 'RECALCULATED');
CREATE TYPE trustride.cost_factor_data_source_enum AS ENUM ('GOVERNED', 'ADVISORY_PREDICTED');

-- ============================================================================
-- PHASE 3/4/5 -- TABLES
-- ============================================================================

-- --- Supporting reference: geo zones (not one of the 17, structurally required) ---
CREATE TABLE trustride.cost_operational_zones (
  zone_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  zone_code      TEXT NOT NULL UNIQUE,
  zone_name      TEXT NOT NULL,
  jurisdiction   trustride.cost_jurisdiction_enum NOT NULL,
  density_class  TEXT NOT NULL CHECK (density_class IN ('HIGH_DENSITY', 'SUBURB', 'OUTSKIRT_DEADZONE')),
  boundary       GEOMETRY(POLYGON, 4326) NOT NULL,
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.cost_operational_zones IS
  'Pure geo/jurisdiction reference; return_trip_factor, empty_return_probability, and regional_cost_factor key off zone_id -- the governed economic value lives in those tables, not here.';

-- --- Supporting reference: EPRA fuel index (not one of the 17, structurally required) ---
CREATE TABLE trustride.cost_epra_fuel_registry (
  epra_entry_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  price_period           DATE NOT NULL,
  fuel_type              TEXT NOT NULL CHECK (fuel_type IN ('PETROL_SUPER', 'DIESEL', 'ELECTRIC_TARIFF')),
  jurisdiction           trustride.cost_jurisdiction_enum NOT NULL,
  pump_price_kes         NUMERIC(18,2) NOT NULL CHECK (pump_price_kes >= 0),
  source_reference       TEXT NOT NULL,
  ingested_via_signal_id UUID,
  effective_from         TIMESTAMPTZ NOT NULL,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (price_period, fuel_type, jurisdiction)
);
COMMENT ON TABLE trustride.cost_epra_fuel_registry IS
  'Append-only regulatory record feeding cost_rate; never invented locally.';

-- --- 1. cost_registry -- the central selector (was cost_rate_card_rule) ---
CREATE TABLE trustride.cost_registry (
  registry_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  registry_code        TEXT NOT NULL UNIQUE,
  macro_domain         TEXT NOT NULL CHECK (macro_domain IN ('TRANSPORT','COURIER','DELIVERY','EXECUTIVE_ASSISTANTS','MARKETPLACE')),
  service_code         TEXT NOT NULL,
  asset_class          trustride.cost_asset_class_enum NOT NULL,
  jurisdiction         trustride.cost_jurisdiction_enum NOT NULL,
  cost_rate_id         UUID,
  cost_model_id        UUID,
  overhead_pct         NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (overhead_pct >= 0),
  minimum_margin_pct   NUMERIC(5,2) NOT NULL DEFAULT 8.00 CHECK (minimum_margin_pct >= 0),
  status               trustride.cost_governance_status_enum NOT NULL DEFAULT 'ACTIVE',
  approved_request_id  UUID REFERENCES trustride.approval_request (request_id),
  effective_from       TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to         TIMESTAMPTZ,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_cost_registry_active ON trustride.cost_registry (macro_domain, service_code, asset_class, jurisdiction) WHERE status = 'ACTIVE';
COMMENT ON TABLE trustride.cost_registry IS
  'Registry of all active/inactive cost-build configurations -- given domain+service+asset+jurisdiction, which rate and model apply, and what overhead/margin govern this combination.';

-- --- 2. cost_model -- equation shape (was cost_formula_matrix) ---
CREATE TABLE trustride.cost_model (
  model_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_version      TEXT NOT NULL,
  asset_class        trustride.cost_asset_class_enum NOT NULL,
  equation_definition JSONB NOT NULL,
  component_weights  JSONB NOT NULL DEFAULT '{}',
  status             trustride.cost_governance_status_enum NOT NULL DEFAULT 'ACTIVE',
  approved_request_id UUID REFERENCES trustride.approval_request (request_id),
  effective_from     TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to       TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (model_version, asset_class)
);
CREATE UNIQUE INDEX uq_cost_model_active ON trustride.cost_model (asset_class) WHERE status = 'ACTIVE';
COMMENT ON TABLE trustride.cost_model IS
  'Defines the economic model used for a service/asset class -- an equation today; component_weights leaves room for a future non-equation model without a code deployment.';

-- --- 3. cost_model_version -- immutable version history (NEW) ---
CREATE TABLE trustride.cost_model_version (
  model_version_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id         UUID NOT NULL REFERENCES trustride.cost_model (model_id),
  version_number   INTEGER NOT NULL,
  equation_snapshot JSONB NOT NULL,
  superseded_at    TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (model_id, version_number)
);
COMMENT ON TABLE trustride.cost_model_version IS
  'Immutable versioning of cost models for historical reconstruction -- a settled fare_calculation stays mathematically reproducible even after cost_model itself changes.';
REVOKE UPDATE, DELETE ON trustride.cost_model_version FROM PUBLIC;

-- --- 4. cost_component -- governed vocabulary (was cost_component_primitive) ---
CREATE TABLE trustride.cost_component (
  component_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  component_code       TEXT NOT NULL UNIQUE,
  component_label      TEXT NOT NULL,
  component_definition TEXT NOT NULL,
  unit_of_measure      trustride.cost_component_unit_enum NOT NULL,
  version              SMALLINT NOT NULL DEFAULT 1,
  superseded_by        UUID REFERENCES trustride.cost_component (component_id),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.cost_component IS
  'Defines individual cost components -- fuel, labor, distance, waiting, tolls, overhead -- a governed vocabulary, never spelled inconsistently.';

-- --- 5. cost_component_rule -- HOW each component is calculated (NEW) ---
CREATE TABLE trustride.cost_component_rule (
  component_rule_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  component_id          UUID NOT NULL REFERENCES trustride.cost_component (component_id),
  calculation_expression TEXT NOT NULL,
  rule_version          INTEGER NOT NULL DEFAULT 1,
  status                trustride.cost_governance_status_enum NOT NULL DEFAULT 'ACTIVE',
  effective_from        TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to          TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_cost_component_rule_active ON trustride.cost_component_rule (component_id) WHERE status = 'ACTIVE';
COMMENT ON TABLE trustride.cost_component_rule IS
  'Each component''s calculation rule, independently versioned and audited -- rather than living inside one combined equation_definition JSON blob on cost_model.';

-- --- 6. cost_rate -- mechanical baseline (was cost_asset_engine_baselines) ---
CREATE TABLE trustride.cost_rate (
  rate_id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_class                  trustride.cost_asset_class_enum NOT NULL,
  engine_capacity               trustride.cost_engine_capacity_enum NOT NULL,
  base_dispatch_fee_kes          NUMERIC(18,2) NOT NULL CHECK (base_dispatch_fee_kes >= 0),
  fuel_consumption_km_per_l       NUMERIC(6,2) CHECK (fuel_consumption_km_per_l IS NULL OR fuel_consumption_km_per_l > 0),
  energy_consumption_kwh_per_km    NUMERIC(6,3) CHECK (energy_consumption_kwh_per_km IS NULL OR energy_consumption_kwh_per_km > 0),
  maintenance_rate_kes_per_km       NUMERIC(18,2) NOT NULL CHECK (maintenance_rate_kes_per_km >= 0),
  direct_per_km_rate_kes             NUMERIC(18,2) NOT NULL CHECK (direct_per_km_rate_kes >= 0),
  time_rate_kes_per_min                NUMERIC(18,2) NOT NULL CHECK (time_rate_kes_per_min >= 0),
  waiting_rate_kes_per_min                NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (waiting_rate_kes_per_min >= 0),
  minimum_fare_floor_kes                     NUMERIC(18,2) NOT NULL CHECK (minimum_fare_floor_kes >= 0),
  active                                        BOOLEAN NOT NULL DEFAULT TRUE,
  effective_from                                  TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to                                       TIMESTAMPTZ,
  approved_by                                           UUID,
  approved_request_id                                     UUID REFERENCES trustride.approval_request (request_id),
  created_at                                                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_cost_rate_energy_xor
    CHECK (
      (engine_capacity = 'EV_ELECTRIC' AND energy_consumption_kwh_per_km IS NOT NULL AND fuel_consumption_km_per_l IS NULL)
      OR (engine_capacity <> 'EV_ELECTRIC' AND fuel_consumption_km_per_l IS NOT NULL AND energy_consumption_kwh_per_km IS NULL)
      OR engine_capacity = 'NOT_APPLICABLE'
    )
);
CREATE UNIQUE INDEX uq_cost_rate_active ON trustride.cost_rate (asset_class, engine_capacity) WHERE active = TRUE;
COMMENT ON TABLE trustride.cost_rate IS
  'Governed, versioned mechanical baseline -- adds waiting_rate_kes_per_min (Founder-directed: "waiting exposure" is a real equation term with no prior column anywhere).';

-- --- 7. cost_rate_version -- immutable version history (NEW) ---
CREATE TABLE trustride.cost_rate_version (
  rate_version_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rate_id         UUID NOT NULL REFERENCES trustride.cost_rate (rate_id),
  version_number  INTEGER NOT NULL,
  rate_snapshot   JSONB NOT NULL,
  superseded_at   TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (rate_id, version_number)
);
COMMENT ON TABLE trustride.cost_rate_version IS 'Preserves historical rate versions, e.g. across EPRA-driven supersessions.';
REVOKE UPDATE, DELETE ON trustride.cost_rate_version FROM PUBLIC;

-- --- 8. route_cost_factor -- route-specific economics (was cost_road_segments_override, broadened) ---
CREATE TABLE trustride.route_cost_factor (
  route_factor_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  factor_code     TEXT NOT NULL UNIQUE,
  factor_name     TEXT,
  jurisdiction    trustride.cost_jurisdiction_enum NOT NULL,
  factor_type     TEXT NOT NULL CHECK (factor_type IN ('TERRAIN', 'TOLL', 'CONGESTION')),
  factor_multiplier NUMERIC(4,2) NOT NULL CHECK (factor_multiplier >= 1.00 AND factor_multiplier <= 3.00),
  path            GEOMETRY(LINESTRING, 4326) NOT NULL,
  buffer_meters   NUMERIC(6,1) NOT NULL DEFAULT 25.0 CHECK (buffer_meters > 0),
  active          BOOLEAN NOT NULL DEFAULT TRUE,
  effective_from  TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.route_cost_factor IS
  'Captures route-specific economic factors -- terrain, tolls, congestion -- broader than the prior terrain-only cost_road_segments_override.';

-- --- 9. return_trip_factor -- K_return, dedicated and governed (was cost_operational_zones.return_multiplier) ---
CREATE TABLE trustride.return_trip_factor (
  return_trip_factor_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  zone_id                UUID NOT NULL REFERENCES trustride.cost_operational_zones (zone_id),
  return_multiplier      NUMERIC(4,2) NOT NULL DEFAULT 1.00 CHECK (return_multiplier >= 1.00 AND return_multiplier <= 3.00),
  surge_multiplier_active NUMERIC(4,2) CHECK (surge_multiplier_active IS NULL OR (surge_multiplier_active >= 1.00 AND surge_multiplier_active <= 5.00)),
  surge_valid_until      TIMESTAMPTZ,
  active                 BOOLEAN NOT NULL DEFAULT TRUE,
  effective_from         TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to           TIMESTAMPTZ,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_return_trip_factor_zone_active ON trustride.return_trip_factor (zone_id) WHERE active = TRUE;
COMMENT ON TABLE trustride.return_trip_factor IS
  'Models the economic exposure of a resource returning without another job -- ZONE_SURGE_TRIGGERED temporarily elevates surge_multiplier_active on this table, not on the zone itself.';

-- --- 10. empty_return_probability -- NEW, the Founder''s own "real substantive upgrade" ---
CREATE TABLE trustride.empty_return_probability (
  empty_return_probability_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  zone_id           UUID NOT NULL REFERENCES trustride.cost_operational_zones (zone_id),
  time_band         TEXT CHECK (time_band IS NULL OR time_band IN ('PEAK', 'OFF_PEAK', 'NIGHT')),
  probability_pct   NUMERIC(5,2) NOT NULL CHECK (probability_pct >= 0 AND probability_pct <= 100),
  data_source       trustride.cost_factor_data_source_enum NOT NULL DEFAULT 'GOVERNED',
  active            BOOLEAN NOT NULL DEFAULT TRUE,
  effective_from    TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_empty_return_probability_active ON trustride.empty_return_probability (zone_id, coalesce(time_band, '')) WHERE active = TRUE;
COMMENT ON TABLE trustride.empty_return_probability IS
  'Estimates the probability a resource returns empty after fulfilment. data_source is GOVERNED (administered, like every other factor here) until Engine 9/10 exist to feed ADVISORY_PREDICTED values -- named explicitly, not silently implied as already intelligent.';

-- --- 11. regional_cost_factor -- NEW, standing regional economics ---
CREATE TABLE trustride.regional_cost_factor (
  regional_cost_factor_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  jurisdiction    trustride.cost_jurisdiction_enum NOT NULL,
  factor_multiplier NUMERIC(4,2) NOT NULL DEFAULT 1.00 CHECK (factor_multiplier >= 0.50 AND factor_multiplier <= 3.00),
  reason          TEXT,
  data_source     trustride.cost_factor_data_source_enum NOT NULL DEFAULT 'GOVERNED',
  active          BOOLEAN NOT NULL DEFAULT TRUE,
  effective_from  TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_regional_cost_factor_active ON trustride.regional_cost_factor (jurisdiction) WHERE active = TRUE;
COMMENT ON TABLE trustride.regional_cost_factor IS
  'Models regional operating conditions, demand, supply, and geographic economics -- a standing dimension, distinct from ZONE_SURGE_TRIGGERED''s temporary override on return_trip_factor.';

-- --- 12. resource_cost_factor -- NEW, per-individual-resource ---
CREATE TABLE trustride.resource_cost_factor (
  resource_cost_factor_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  fleet_resource_id       UUID NOT NULL,
  cost_adjustment_multiplier NUMERIC(4,2) NOT NULL DEFAULT 1.00 CHECK (cost_adjustment_multiplier >= 0.50 AND cost_adjustment_multiplier <= 2.00),
  reason                  TEXT,
  active                  BOOLEAN NOT NULL DEFAULT TRUE,
  effective_from          TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to            TIMESTAMPTZ,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_resource_cost_factor_active ON trustride.resource_cost_factor (fleet_resource_id) WHERE active = TRUE;
COMMENT ON TABLE trustride.resource_cost_factor IS
  'Captures resource-specific cost characteristics -- fleet_resource_id is a by-value reference into Engine 2''s resource_fleet_register, never a foreign key across engines (Article 33). Absent a row, a resource costs exactly its asset-class baseline (multiplier 1.00).';

-- --- 13. operational_risk_factor -- NEW ---
CREATE TABLE trustride.operational_risk_factor (
  operational_risk_factor_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_class     trustride.cost_asset_class_enum NOT NULL,
  jurisdiction    trustride.cost_jurisdiction_enum NOT NULL,
  risk_category   TEXT NOT NULL,
  risk_multiplier NUMERIC(4,2) NOT NULL DEFAULT 1.00 CHECK (risk_multiplier >= 1.00 AND risk_multiplier <= 2.00),
  active          BOOLEAN NOT NULL DEFAULT TRUE,
  effective_from  TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_operational_risk_factor_active ON trustride.operational_risk_factor (asset_class, jurisdiction) WHERE active = TRUE;
COMMENT ON TABLE trustride.operational_risk_factor IS
  'Models operational risk and its associated cost exposure -- today an explicit, governed fare input, where before risk was not modelled at all.';

-- --- 14. fare_calculation -- the computation record (was half of cost_unit_price_quotes) ---
CREATE TABLE trustride.fare_calculation (
  calculation_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  registry_id        UUID NOT NULL REFERENCES trustride.cost_registry (registry_id),
  order_id           UUID,
  assignment_id      UUID,
  requester_user_id  UUID NOT NULL,
  requester_user_type trustride.cost_user_type_enum NOT NULL,
  asset_class        trustride.cost_asset_class_enum NOT NULL,
  engine_capacity    trustride.cost_engine_capacity_enum NOT NULL,
  jurisdiction       trustride.cost_jurisdiction_enum NOT NULL,
  origin_zone_id     UUID NOT NULL REFERENCES trustride.cost_operational_zones (zone_id),
  destination_zone_id UUID NOT NULL REFERENCES trustride.cost_operational_zones (zone_id),
  distance_km        NUMERIC(8,3) NOT NULL CHECK (distance_km >= 0),
  duration_min       NUMERIC(8,2) NOT NULL CHECK (duration_min >= 0),
  waiting_min        NUMERIC(8,2) NOT NULL DEFAULT 0 CHECK (waiting_min >= 0),
  base_dispatch_fee_kes NUMERIC(18,2) NOT NULL CHECK (base_dispatch_fee_kes >= 0),
  direct_per_km_rate_kes NUMERIC(18,2) NOT NULL CHECK (direct_per_km_rate_kes >= 0),
  time_rate_kes_per_min NUMERIC(18,2) NOT NULL CHECK (time_rate_kes_per_min >= 0),
  waiting_rate_kes_per_min NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (waiting_rate_kes_per_min >= 0),
  return_multiplier_applied NUMERIC(4,2) NOT NULL CHECK (return_multiplier_applied >= 1.00),
  route_factor_applied NUMERIC(4,2) NOT NULL DEFAULT 1.00 CHECK (route_factor_applied >= 1.00),
  empty_return_probability_applied NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (empty_return_probability_applied >= 0),
  regional_factor_applied NUMERIC(4,2) NOT NULL DEFAULT 1.00,
  resource_cost_factor_applied NUMERIC(4,2) NOT NULL DEFAULT 1.00,
  operational_risk_factor_applied NUMERIC(4,2) NOT NULL DEFAULT 1.00,
  overhead_pct_applied NUMERIC(5,2) NOT NULL DEFAULT 0,
  minimum_fare_floor_kes NUMERIC(18,2) NOT NULL CHECK (minimum_fare_floor_kes >= 0),
  pre_floor_fare_kes NUMERIC(18,2) NOT NULL CHECK (pre_floor_fare_kes >= 0),
  total_expected_cost_kes NUMERIC(18,2) NOT NULL CHECK (total_expected_cost_kes >= 0),
  computed_total_fare_kes NUMERIC(18,2) NOT NULL CHECK (computed_total_fare_kes >= 0),
  currency           CHAR(3) NOT NULL DEFAULT 'KES',
  model_version      TEXT NOT NULL,
  correlation_id     UUID NOT NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.fare_calculation IS
  'Complete calculation record for a proposed fare -- every term of TOTAL EXPECTED COST captured as a copied, versioned value, never a live join at read time, so a settled calculation remains mathematically reproducible forever.';

-- --- 15. fare_calculation_line -- itemized transparency (companion, was cost_unit_price_buildup_entry) ---
CREATE TABLE trustride.fare_calculation_line (
  line_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  calculation_id    UUID NOT NULL REFERENCES trustride.fare_calculation (calculation_id),
  component_code    TEXT NOT NULL,
  raw_input_value   NUMERIC(12,4),
  rate_applied      NUMERIC(10,4),
  multiplier_applied NUMERIC(4,2) NOT NULL DEFAULT 1.00,
  line_amount_kes   NUMERIC(18,2) NOT NULL CHECK (line_amount_kes >= 0),
  sequence_no       SMALLINT NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.fare_calculation_line IS
  'The itemized, transparent receipt behind total_expected_cost_kes -- one row per equation term.';

-- --- 16. fare_quote -- the customer-facing, lifecycle-managed artifact ---
CREATE TABLE trustride.fare_quote (
  quote_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  calculation_id          UUID NOT NULL UNIQUE REFERENCES trustride.fare_calculation (calculation_id),
  quote_code              TEXT NOT NULL UNIQUE,
  computed_total_fare_kes NUMERIC(18,2) NOT NULL CHECK (computed_total_fare_kes >= 0),
  currency                CHAR(3) NOT NULL DEFAULT 'KES',
  quote_state             trustride.cost_quote_state_enum NOT NULL DEFAULT 'FARE_ESTIMATED',
  quote_hash              CHAR(64) NOT NULL,
  prev_quote_hash         CHAR(64),
  locked_at               TIMESTAMPTZ,
  expires_at              TIMESTAMPTZ NOT NULL,
  finalized_at            TIMESTAMPTZ,
  cancelled_at            TIMESTAMPTZ,
  correlation_id          UUID NOT NULL,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.fare_quote IS
  'The single lawful source of quote-of-record truth -- no fare shown to a requester or posted to settlement may originate anywhere else. Separated from fare_calculation: this is the lifecycle-managed, customer-facing artifact; fare_calculation is the computation it derives from.';

CREATE OR REPLACE FUNCTION trustride.fare_quote_block_illegal_mutation()
RETURNS trigger
LANGUAGE plpgsql SET search_path = trustride, pg_temp
AS $$
BEGIN
  IF OLD.quote_state IN ('FARE_LOCKED', 'SERVICE_IN_PROGRESS', 'FARE_FINALIZED', 'C2B_PAYMENT_TRIGGERED')
     AND (NEW.computed_total_fare_kes IS DISTINCT FROM OLD.computed_total_fare_kes
          OR NEW.quote_hash IS DISTINCT FROM OLD.quote_hash) THEN
    RAISE EXCEPTION 'fare_quote: fare and hash are immutable once quote_state = %; correction requires a new quote', OLD.quote_state;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_fare_quote_block_illegal_mutation
  BEFORE UPDATE ON trustride.fare_quote
  FOR EACH ROW EXECUTE FUNCTION trustride.fare_quote_block_illegal_mutation();

-- --- 17. cost_record -- audit ledger (was cost_execution_ledger) ---
CREATE TABLE trustride.cost_record (
  record_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  calculation_id   UUID REFERENCES trustride.fare_calculation (calculation_id),
  quote_id         UUID REFERENCES trustride.fare_quote (quote_id),
  registry_id      UUID REFERENCES trustride.cost_registry (registry_id),
  execution_outcome trustride.cost_execution_outcome_enum NOT NULL,
  input_snapshot   JSONB NOT NULL,
  output_snapshot  JSONB,
  engine_version   TEXT NOT NULL,
  duration_ms      INTEGER NOT NULL CHECK (duration_ms >= 0),
  correlation_id   UUID NOT NULL,
  executed_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.cost_record IS
  'Immutable evidentiary record of every calculation performed -- including recalculations, expirations, and rejected attempts -- distinct from fare_quote, the lawful quote of record.';
REVOKE UPDATE, DELETE ON trustride.cost_record FROM PUBLIC;

-- --- Correction 4 (carried forward): the cross-signal join ---
CREATE TABLE trustride.cost_pending_service_context (
  correlation_id UUID PRIMARY KEY,
  macro_domain   TEXT NOT NULL,
  service_code   TEXT NOT NULL,
  cached_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.cost_pending_service_context IS
  'SERVICE_CONTEXT_RESOLVED arrives before RESOURCE_DISPATCH_INITIATED (Article 19 Stage 1 precedes assignment); bridges the two by correlation_id, since no source document names this join.';

-- --- cost_event: outbox/inbox (per platform Signal Envelope law) ---
CREATE TABLE trustride.cost_event_outbox (
  signal_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id   UUID NOT NULL,
  causation_id     UUID,
  emitting_engine  TEXT NOT NULL DEFAULT 'TRS026_ENG005_COST',
  receiving_engine TEXT NOT NULL,
  signal_type      TEXT NOT NULL,
  payload_in       JSONB NOT NULL,
  signal_status    TEXT NOT NULL DEFAULT 'PENDING'
                      CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason TEXT,
  idempotency_key  TEXT NOT NULL UNIQUE,
  attempt_count    INTEGER NOT NULL DEFAULT 0,
  emitted_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_cost_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);

CREATE TABLE trustride.cost_event_inbox (
  signal_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id   UUID NOT NULL,
  causation_id     UUID,
  emitting_engine  TEXT NOT NULL,
  receiving_engine TEXT NOT NULL DEFAULT 'TRS026_ENG005_COST',
  signal_type      TEXT NOT NULL,
  payload_in       JSONB NOT NULL,
  payload_out      JSONB,
  signal_status    TEXT NOT NULL DEFAULT 'RECEIVED'
                      CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason TEXT,
  idempotency_key  TEXT NOT NULL UNIQUE,
  received_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at      TIMESTAMPTZ,
  CONSTRAINT chk_cost_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);

-- Deferred FKs (registry -> rate/model declared after both exist)
ALTER TABLE trustride.cost_registry ADD CONSTRAINT fk_cost_registry_rate FOREIGN KEY (cost_rate_id) REFERENCES trustride.cost_rate (rate_id);
ALTER TABLE trustride.cost_registry ADD CONSTRAINT fk_cost_registry_model FOREIGN KEY (cost_model_id) REFERENCES trustride.cost_model (model_id);

-- ============================================================================
-- PHASE 6 -- FUNCTIONS
-- ============================================================================

-- --- The equation itself, extended per the Founder's own model ---
CREATE OR REPLACE FUNCTION trustride.fn_cost_fare_calculate(
  p_macro_domain TEXT, p_service_code TEXT, p_asset_class trustride.cost_asset_class_enum, p_engine_capacity trustride.cost_engine_capacity_enum,
  p_jurisdiction trustride.cost_jurisdiction_enum, p_origin_zone_code TEXT, p_destination_zone_code TEXT,
  p_distance_km NUMERIC, p_duration_min NUMERIC, p_requester_user_id UUID, p_requester_user_type trustride.cost_user_type_enum,
  p_correlation_id UUID, p_order_id UUID DEFAULT NULL, p_assignment_id UUID DEFAULT NULL, p_fleet_resource_id UUID DEFAULT NULL,
  p_waiting_min NUMERIC DEFAULT 0, p_route_path GEOMETRY DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public, extensions, pg_temp
AS $$
DECLARE
  v_start_time      TIMESTAMPTZ := clock_timestamp();
  v_registry        RECORD;
  v_rate            RECORD;
  v_model           RECORD;
  v_origin_zone     RECORD;
  v_dest_zone       RECORD;
  v_route_mult      NUMERIC(4,2) := 1.00;
  v_return_mult     NUMERIC(4,2);
  v_empty_return_pct NUMERIC(5,2) := 0;
  v_regional_mult   NUMERIC(4,2) := 1.00;
  v_resource_mult   NUMERIC(4,2) := 1.00;
  v_risk_mult       NUMERIC(4,2) := 1.00;
  v_distance_cost   NUMERIC(18,2);
  v_time_cost       NUMERIC(18,2);
  v_waiting_cost    NUMERIC(18,2);
  v_empty_return_loading NUMERIC(18,2);
  v_pre_floor_fare  NUMERIC(18,2);
  v_floor_adjustment NUMERIC(18,2);
  v_total_expected_cost NUMERIC(18,2);
  v_total_fare      NUMERIC(18,2);
  v_overhead_kes    NUMERIC(18,2);
  v_calculation_id  UUID;
  v_margin_pct      NUMERIC(6,2);
  v_ledger_id       UUID;
BEGIN
  SELECT * INTO v_registry FROM trustride.cost_registry
  WHERE macro_domain = p_macro_domain AND service_code = p_service_code AND asset_class = p_asset_class
    AND jurisdiction = p_jurisdiction AND status = 'ACTIVE';

  IF v_registry IS NULL THEN
    INSERT INTO trustride.cost_record (execution_outcome, input_snapshot, engine_version, duration_ms, correlation_id)
    VALUES ('REJECTED_NO_REGISTRY', jsonb_build_object('macro_domain', p_macro_domain, 'service_code', p_service_code, 'asset_class', p_asset_class, 'jurisdiction', p_jurisdiction),
      '2.0.0', extract(milliseconds FROM clock_timestamp() - v_start_time)::int, p_correlation_id)
    RETURNING record_id INTO v_ledger_id;
    RAISE EXCEPTION 'fn_cost_fare_calculate: no ACTIVE cost_registry for domain=%, service=%, asset_class=%, jurisdiction=% (record_id=%)',
      p_macro_domain, p_service_code, p_asset_class, p_jurisdiction, v_ledger_id;
  END IF;

  SELECT * INTO v_rate FROM trustride.cost_rate WHERE rate_id = v_registry.cost_rate_id;
  SELECT * INTO v_model FROM trustride.cost_model WHERE model_id = v_registry.cost_model_id;
  SELECT * INTO v_origin_zone FROM trustride.cost_operational_zones WHERE zone_code = p_origin_zone_code AND active = TRUE;
  SELECT * INTO v_dest_zone FROM trustride.cost_operational_zones WHERE zone_code = p_destination_zone_code AND active = TRUE;

  IF v_origin_zone IS NULL OR v_dest_zone IS NULL THEN
    RAISE EXCEPTION 'fn_cost_fare_calculate: unknown or inactive zone_code (origin=%, destination=%)', p_origin_zone_code, p_destination_zone_code;
  END IF;

  -- Return-trip exposure (K_return), elevated by any currently-active surge.
  SELECT return_multiplier, CASE WHEN surge_valid_until IS NOT NULL AND surge_valid_until > now() THEN coalesce(surge_multiplier_active, return_multiplier) ELSE return_multiplier END
  INTO v_return_mult, v_return_mult
  FROM trustride.return_trip_factor WHERE zone_id = v_dest_zone.zone_id AND active = TRUE;
  v_return_mult := coalesce(v_return_mult, 1.00);

  -- Empty-return probability, applied as an additional cost loading (Founder-directed, new).
  SELECT max(probability_pct) INTO v_empty_return_pct FROM trustride.empty_return_probability WHERE zone_id = v_dest_zone.zone_id AND active = TRUE;
  v_empty_return_pct := coalesce(v_empty_return_pct, 0);

  -- Regional conditions (standing, distinct from surge).
  SELECT factor_multiplier INTO v_regional_mult FROM trustride.regional_cost_factor WHERE jurisdiction = p_jurisdiction AND active = TRUE;
  v_regional_mult := coalesce(v_regional_mult, 1.00);

  -- Resource-specific cost (per-individual fleet unit, by value reference).
  IF p_fleet_resource_id IS NOT NULL THEN
    SELECT cost_adjustment_multiplier INTO v_resource_mult FROM trustride.resource_cost_factor WHERE fleet_resource_id = p_fleet_resource_id AND active = TRUE;
    v_resource_mult := coalesce(v_resource_mult, 1.00);
  END IF;

  -- Operational risk.
  SELECT risk_multiplier INTO v_risk_mult FROM trustride.operational_risk_factor WHERE asset_class = p_asset_class AND jurisdiction = p_jurisdiction AND active = TRUE;
  v_risk_mult := coalesce(v_risk_mult, 1.00);

  -- Route cost (terrain/toll/congestion) -- only evaluated if a real route was supplied.
  IF p_route_path IS NOT NULL THEN
    SELECT max(factor_multiplier) INTO v_route_mult FROM trustride.route_cost_factor
    WHERE active = TRUE AND jurisdiction = p_jurisdiction AND ST_DWithin(path, p_route_path, buffer_meters);
    v_route_mult := coalesce(v_route_mult, 1.00);
  END IF;

  v_distance_cost := p_distance_km * v_rate.direct_per_km_rate_kes * v_return_mult * v_resource_mult;
  v_time_cost := p_duration_min * v_rate.time_rate_kes_per_min;
  v_waiting_cost := p_waiting_min * v_rate.waiting_rate_kes_per_min;
  v_empty_return_loading := v_distance_cost * (v_empty_return_pct / 100.0);

  v_pre_floor_fare := (v_rate.base_dispatch_fee_kes + v_distance_cost + v_time_cost + v_waiting_cost + v_empty_return_loading)
                       * v_route_mult * v_regional_mult * v_risk_mult;

  v_total_expected_cost := GREATEST(v_pre_floor_fare, v_rate.minimum_fare_floor_kes);
  v_floor_adjustment := v_total_expected_cost - v_pre_floor_fare;
  v_overhead_kes := v_total_expected_cost * (v_registry.overhead_pct / 100.0);
  v_total_fare := v_total_expected_cost + v_overhead_kes;

  IF v_total_fare > 0 THEN
    v_margin_pct := ((v_total_fare - (p_distance_km * v_rate.direct_per_km_rate_kes)) / v_total_fare) * 100;
  ELSE
    v_margin_pct := 0;
  END IF;

  INSERT INTO trustride.fare_calculation (
    registry_id, order_id, assignment_id, requester_user_id, requester_user_type, asset_class, engine_capacity, jurisdiction,
    origin_zone_id, destination_zone_id, distance_km, duration_min, waiting_min, base_dispatch_fee_kes, direct_per_km_rate_kes,
    time_rate_kes_per_min, waiting_rate_kes_per_min, return_multiplier_applied, route_factor_applied, empty_return_probability_applied,
    regional_factor_applied, resource_cost_factor_applied, operational_risk_factor_applied, overhead_pct_applied,
    minimum_fare_floor_kes, pre_floor_fare_kes, total_expected_cost_kes, computed_total_fare_kes, model_version, correlation_id
  ) VALUES (
    v_registry.registry_id, p_order_id, p_assignment_id, p_requester_user_id, p_requester_user_type, p_asset_class, p_engine_capacity, p_jurisdiction,
    v_origin_zone.zone_id, v_dest_zone.zone_id, p_distance_km, p_duration_min, p_waiting_min, v_rate.base_dispatch_fee_kes, v_rate.direct_per_km_rate_kes,
    v_rate.time_rate_kes_per_min, v_rate.waiting_rate_kes_per_min, v_return_mult, v_route_mult, v_empty_return_pct,
    v_regional_mult, v_resource_mult, v_risk_mult, v_registry.overhead_pct,
    v_rate.minimum_fare_floor_kes, v_pre_floor_fare, v_total_expected_cost, v_total_fare, v_model.model_version, p_correlation_id
  ) RETURNING calculation_id INTO v_calculation_id;

  INSERT INTO trustride.fare_calculation_line (calculation_id, component_code, raw_input_value, rate_applied, multiplier_applied, line_amount_kes, sequence_no) VALUES
    (v_calculation_id, 'F_BASE', NULL, NULL, 1.00, v_rate.base_dispatch_fee_kes, 1),
    (v_calculation_id, 'DISTANCE_COST', p_distance_km, v_rate.direct_per_km_rate_kes, v_return_mult * v_resource_mult, v_distance_cost, 2),
    (v_calculation_id, 'TIME_COST', p_duration_min, v_rate.time_rate_kes_per_min, 1.00, v_time_cost, 3),
    (v_calculation_id, 'WAITING_COST', p_waiting_min, v_rate.waiting_rate_kes_per_min, 1.00, v_waiting_cost, 4),
    (v_calculation_id, 'EMPTY_RETURN_LOADING', v_empty_return_pct, NULL, 1.00, v_empty_return_loading, 5),
    (v_calculation_id, 'ROUTE_REGIONAL_RISK_ADJUSTMENT', NULL, NULL, v_route_mult * v_regional_mult * v_risk_mult,
      v_pre_floor_fare - (v_rate.base_dispatch_fee_kes + v_distance_cost + v_time_cost + v_waiting_cost + v_empty_return_loading), 6),
    (v_calculation_id, 'FLOOR_ADJUSTMENT', NULL, NULL, 1.00, v_floor_adjustment, 7),
    (v_calculation_id, 'OVERHEAD', NULL, v_registry.overhead_pct, 1.00, v_overhead_kes, 8);

  INSERT INTO trustride.cost_record (calculation_id, registry_id, execution_outcome, input_snapshot, output_snapshot, engine_version, duration_ms, correlation_id)
  VALUES (v_calculation_id, v_registry.registry_id, 'CALCULATED',
    jsonb_build_object('distance_km', p_distance_km, 'duration_min', p_duration_min, 'waiting_min', p_waiting_min, 'asset_class', p_asset_class),
    jsonb_build_object('computed_total_fare_kes', v_total_fare, 'margin_pct', v_margin_pct),
    '2.0.0', extract(milliseconds FROM clock_timestamp() - v_start_time)::int, p_correlation_id);

  IF v_margin_pct < v_registry.minimum_margin_pct THEN
    INSERT INTO trustride.cost_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (p_correlation_id, 'TRS026_ENG009_AIADV', 'COST_MARGIN_BREACHED',
      jsonb_build_object('registry_id', v_registry.registry_id, 'computed_margin_pct', v_margin_pct, 'minimum_margin_pct', v_registry.minimum_margin_pct, 'calculation_id', v_calculation_id),
      'COST_MARGIN_BREACHED:' || v_calculation_id::text);
  END IF;

  RETURN v_calculation_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_cost_fare_calculate(TEXT, TEXT, trustride.cost_asset_class_enum, trustride.cost_engine_capacity_enum, trustride.cost_jurisdiction_enum, TEXT, TEXT, NUMERIC, NUMERIC, UUID, trustride.cost_user_type_enum, UUID, UUID, UUID, UUID, NUMERIC, GEOMETRY) IS
  'TOTAL EXPECTED COST = resource cost + route cost + time cost + waiting exposure + return-trip exposure + empty-return probability + regional conditions + operational risk + overhead -> floor -> approved margin check. The calculation is still produced on a margin breach -- the requester is never left without a fare -- but the breach is flagged, never silently absorbed.';

-- --- Quote lifecycle (customer-facing, lawful, immutable once locked) ---
CREATE OR REPLACE FUNCTION trustride.fn_cost_fare_quote_issue(p_calculation_id UUID)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_calc RECORD;
  v_quote_code TEXT;
  v_prev_hash CHAR(64);
  v_quote_hash CHAR(64);
  v_quote_id UUID;
BEGIN
  SELECT * INTO v_calc FROM trustride.fare_calculation WHERE calculation_id = p_calculation_id;
  IF v_calc IS NULL THEN
    RAISE EXCEPTION 'fn_cost_fare_quote_issue: unknown calculation_id %', p_calculation_id;
  END IF;

  v_quote_code := trustride.fn_sequence_next('TRS026-QUOTE');
  SELECT quote_hash INTO v_prev_hash FROM trustride.fare_quote ORDER BY created_at DESC LIMIT 1;
  v_quote_hash := encode(digest(coalesce(v_prev_hash,'') || v_quote_code || v_calc.computed_total_fare_kes::text || now()::text, 'sha256'), 'hex');

  INSERT INTO trustride.fare_quote (calculation_id, quote_code, computed_total_fare_kes, currency, quote_hash, prev_quote_hash, expires_at, correlation_id)
  VALUES (p_calculation_id, v_quote_code, v_calc.computed_total_fare_kes, v_calc.currency, v_quote_hash, v_prev_hash, now() + interval '5 minutes', v_calc.correlation_id)
  RETURNING quote_id INTO v_quote_id;

  RETURN v_quote_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_cost_fare_quote_issue(UUID) IS
  'Issues the lawful, customer-facing fare_quote from an already-produced fare_calculation.';

CREATE OR REPLACE FUNCTION trustride.fn_cost_quote_lock(p_quote_id UUID, p_correlation_id UUID DEFAULT gen_random_uuid())
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_quote RECORD;
  v_calc RECORD;
BEGIN
  UPDATE trustride.fare_quote SET quote_state = 'FARE_LOCKED', locked_at = now()
  WHERE quote_id = p_quote_id AND quote_state = 'FARE_ESTIMATED' AND expires_at > now()
  RETURNING * INTO v_quote;

  IF v_quote IS NULL THEN
    RAISE EXCEPTION 'fn_cost_quote_lock: quote % is not a live FARE_ESTIMATED quote (expired, wrong state, or does not exist)', p_quote_id;
  END IF;

  SELECT * INTO v_calc FROM trustride.fare_calculation WHERE calculation_id = v_quote.calculation_id;

  INSERT INTO trustride.cost_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG004_BUS', 'UNIT_PRICE_LOCKED',
    jsonb_build_object('quote_id', v_quote.quote_id, 'quote_code', v_quote.quote_code, 'computed_total_fare_kes', v_quote.computed_total_fare_kes,
      'currency', v_quote.currency, 'expires_at', v_quote.expires_at, 'order_id', v_calc.order_id),
    'UNIT_PRICE_LOCKED:' || p_quote_id::text);
END;
$$;
COMMENT ON FUNCTION trustride.fn_cost_quote_lock(UUID, UUID) IS
  'FARE_ESTIMATED -> FARE_LOCKED, "the requester has accepted the posted fee" (Article 20.2). Emits UNIT_PRICE_LOCKED to Business, unchanged from the prior design.';

CREATE OR REPLACE FUNCTION trustride.fn_cost_quote_mark_in_progress(p_quote_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
BEGIN
  UPDATE trustride.fare_quote SET quote_state = 'SERVICE_IN_PROGRESS' WHERE quote_id = p_quote_id AND quote_state = 'FARE_LOCKED';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_cost_quote_mark_in_progress: quote % is not FARE_LOCKED (or does not exist)', p_quote_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_cost_quote_finalize(p_quote_id UUID, p_correlation_id UUID DEFAULT gen_random_uuid())
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_quote RECORD;
BEGIN
  UPDATE trustride.fare_quote SET quote_state = 'FARE_FINALIZED', finalized_at = now()
  WHERE quote_id = p_quote_id AND quote_state = 'SERVICE_IN_PROGRESS'
  RETURNING * INTO v_quote;

  IF v_quote IS NULL THEN
    RAISE EXCEPTION 'fn_cost_quote_finalize: quote % is not SERVICE_IN_PROGRESS (or does not exist)', p_quote_id;
  END IF;

  UPDATE trustride.fare_quote SET quote_state = 'C2B_PAYMENT_TRIGGERED' WHERE quote_id = p_quote_id;

  INSERT INTO trustride.cost_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG006_INTG', 'PAYMENT_STK_TRIGGERED',
    jsonb_build_object('quote_id', v_quote.quote_id, 'computed_total_fare_kes', v_quote.computed_total_fare_kes, 'currency', v_quote.currency,
      'requester_user_id', (SELECT requester_user_id FROM trustride.fare_calculation WHERE calculation_id = v_quote.calculation_id), 'payment_rail', 'MPESA_C2B_STK'),
    'PAYMENT_STK_TRIGGERED:' || p_quote_id::text);
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_cost_quote_expire_sweep()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_expired INTEGER;
BEGIN
  UPDATE trustride.fare_quote SET quote_state = 'EXPIRED' WHERE quote_state = 'FARE_ESTIMATED' AND expires_at < now();
  GET DIAGNOSTICS v_expired = ROW_COUNT;
  RETURN v_expired;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_cost_quote_cancel(p_quote_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
BEGIN
  UPDATE trustride.fare_quote SET quote_state = 'CANCELLED', cancelled_at = now()
  WHERE quote_id = p_quote_id AND quote_state IN ('FARE_ESTIMATED', 'FARE_LOCKED');
  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_cost_quote_cancel: quote % cannot be cancelled from its current state (or does not exist)', p_quote_id;
  END IF;
END;
$$;

-- --- EPRA fuel ingestion, now versioning through cost_rate_version too ---
CREATE OR REPLACE FUNCTION trustride.fn_cost_epra_fuel_index_ingest(
  p_price_period DATE, p_fuel_type TEXT, p_jurisdiction trustride.cost_jurisdiction_enum, p_pump_price_kes NUMERIC, p_source_reference TEXT, p_signal_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_epra_entry_id UUID;
  v_rate RECORD;
  v_new_rate NUMERIC(18,2);
  v_new_rate_id UUID;
  v_next_version INTEGER;
BEGIN
  INSERT INTO trustride.cost_epra_fuel_registry (price_period, fuel_type, jurisdiction, pump_price_kes, source_reference, ingested_via_signal_id, effective_from)
  VALUES (p_price_period, p_fuel_type, p_jurisdiction, p_pump_price_kes, p_source_reference, p_signal_id, p_price_period::timestamptz)
  RETURNING epra_entry_id INTO v_epra_entry_id;

  FOR v_rate IN
    SELECT * FROM trustride.cost_rate
    WHERE active = TRUE
      AND ((p_fuel_type IN ('PETROL_SUPER','DIESEL') AND fuel_consumption_km_per_l IS NOT NULL)
        OR (p_fuel_type = 'ELECTRIC_TARIFF' AND energy_consumption_kwh_per_km IS NOT NULL))
  LOOP
    v_new_rate := CASE
      WHEN v_rate.fuel_consumption_km_per_l IS NOT NULL THEN round((p_pump_price_kes / v_rate.fuel_consumption_km_per_l) + v_rate.maintenance_rate_kes_per_km, 2)
      ELSE round((p_pump_price_kes * v_rate.energy_consumption_kwh_per_km) + v_rate.maintenance_rate_kes_per_km, 2)
    END;

    SELECT coalesce(max(version_number), 0) + 1 INTO v_next_version FROM trustride.cost_rate_version WHERE rate_id = v_rate.rate_id;
    INSERT INTO trustride.cost_rate_version (rate_id, version_number, rate_snapshot, superseded_at)
    VALUES (v_rate.rate_id, v_next_version, to_jsonb(v_rate), now());

    UPDATE trustride.cost_rate SET active = FALSE, effective_to = now() WHERE rate_id = v_rate.rate_id;

    INSERT INTO trustride.cost_rate (
      asset_class, engine_capacity, base_dispatch_fee_kes, fuel_consumption_km_per_l, energy_consumption_kwh_per_km,
      maintenance_rate_kes_per_km, direct_per_km_rate_kes, time_rate_kes_per_min, waiting_rate_kes_per_min, minimum_fare_floor_kes
    ) VALUES (
      v_rate.asset_class, v_rate.engine_capacity, v_rate.base_dispatch_fee_kes, v_rate.fuel_consumption_km_per_l, v_rate.energy_consumption_kwh_per_km,
      v_rate.maintenance_rate_kes_per_km, v_new_rate, v_rate.time_rate_kes_per_min, v_rate.waiting_rate_kes_per_min, v_rate.minimum_fare_floor_kes
    ) RETURNING rate_id INTO v_new_rate_id;

    UPDATE trustride.cost_registry SET cost_rate_id = v_new_rate_id WHERE cost_rate_id = v_rate.rate_id AND status = 'ACTIVE';
  END LOOP;

  RETURN v_epra_entry_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_cost_epra_fuel_index_ingest(DATE, TEXT, trustride.cost_jurisdiction_enum, NUMERIC, TEXT, UUID) IS
  'Absorbs an EPRA fuel index publication, recomputes direct_per_km_rate_kes via a governed cost_rate supersession (versioned into cost_rate_version), and repoints every ACTIVE cost_registry row that referenced the old rate.';

-- --- Zone surge (still real, now on return_trip_factor) ---
CREATE OR REPLACE FUNCTION trustride.fn_cost_zone_surge_apply(p_zone_code TEXT, p_surge_multiplier NUMERIC, p_valid_until TIMESTAMPTZ)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
BEGIN
  UPDATE trustride.return_trip_factor SET surge_multiplier_active = p_surge_multiplier, surge_valid_until = p_valid_until
  WHERE zone_id = (SELECT zone_id FROM trustride.cost_operational_zones WHERE zone_code = p_zone_code) AND active = TRUE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_cost_zone_surge_apply: unknown zone_code % or no active return_trip_factor row for it', p_zone_code;
  END IF;
END;
$$;

-- --- Inbound signal accept-handlers ---
CREATE OR REPLACE FUNCTION trustride.fn_cost_service_context_resolved_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_correlation_id UUID;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_correlation_id FROM trustride.cost_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_cost_service_context_resolved_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  INSERT INTO trustride.cost_pending_service_context (correlation_id, macro_domain, service_code)
  VALUES (v_correlation_id, v_payload->>'macro_domain', v_payload->>'service_code')
  ON CONFLICT (correlation_id) DO UPDATE SET macro_domain = EXCLUDED.macro_domain, service_code = EXCLUDED.service_code, cached_at = now();

  UPDATE trustride.cost_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_cost_resource_dispatch_initiated_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public, extensions, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_correlation_id UUID;
  v_context RECORD;
  v_calculation_id UUID;
  v_quote_id UUID;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_correlation_id FROM trustride.cost_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_cost_resource_dispatch_initiated_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  SELECT * INTO v_context FROM trustride.cost_pending_service_context WHERE correlation_id = v_correlation_id;
  IF v_context IS NULL THEN
    UPDATE trustride.cost_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'NO_SERVICE_CONTEXT_CACHED', accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END IF;

  BEGIN
    v_calculation_id := trustride.fn_cost_fare_calculate(
      v_context.macro_domain, v_context.service_code,
      (v_payload->>'asset_class')::trustride.cost_asset_class_enum,
      coalesce((v_payload->>'engine_capacity')::trustride.cost_engine_capacity_enum, 'NOT_APPLICABLE'),
      coalesce((v_payload->>'jurisdiction')::trustride.cost_jurisdiction_enum, 'KISUMU_COUNTY'),
      v_payload->>'origin_zone_code', v_payload->>'destination_zone_code',
      coalesce((v_payload->>'distance_km')::numeric, 0), coalesce((v_payload->>'duration_min')::numeric, 0),
      coalesce((v_payload->>'requester_user_id')::uuid, '00000000-0000-0000-0000-000000000000'::uuid), 'CUSTOMER',
      v_correlation_id, (v_payload->>'order_id')::uuid, (v_payload->>'assignment_id')::uuid, NULL, 0, NULL
    );
    v_quote_id := trustride.fn_cost_fare_quote_issue(v_calculation_id);
  EXCEPTION WHEN OTHERS THEN
    UPDATE trustride.cost_event_inbox SET signal_status = 'REJECTED', rejection_reason = SQLERRM, accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END;

  DELETE FROM trustride.cost_pending_service_context WHERE correlation_id = v_correlation_id;

  UPDATE trustride.cost_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('calculation_id', v_calculation_id, 'quote_id', v_quote_id) WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_cost_resource_dispatch_initiated_accept(UUID) IS
  'The real trigger for fare calculation -- joins with the cached service context and produces a FARE_ESTIMATED fare_quote, ready for Business to lock.';

CREATE OR REPLACE FUNCTION trustride.fn_cost_epra_fuel_index_updated_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_payload JSONB;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.cost_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_cost_epra_fuel_index_updated_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  PERFORM trustride.fn_cost_epra_fuel_index_ingest(
    (v_payload->>'price_period')::date, v_payload->>'fuel_type', (v_payload->>'jurisdiction')::trustride.cost_jurisdiction_enum,
    (v_payload->>'pump_price_kes')::numeric, v_payload->>'source_reference', p_signal_id
  );

  UPDATE trustride.cost_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_cost_zone_surge_triggered_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_payload JSONB;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.cost_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_cost_zone_surge_triggered_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  PERFORM trustride.fn_cost_zone_surge_apply(v_payload->>'zone_code', (v_payload->>'surge_multiplier')::numeric, (v_payload->>'valid_until')::timestamptz);

  UPDATE trustride.cost_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_cost_inbox_process(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_signal_type TEXT;
  v_result TEXT;
BEGIN
  SELECT signal_type INTO v_signal_type FROM trustride.cost_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_signal_type IS NULL THEN
    RAISE EXCEPTION 'fn_cost_inbox_process: no RECEIVED signal %', p_signal_id;
  END IF;

  CASE v_signal_type
    WHEN 'SERVICE_CONTEXT_RESOLVED' THEN v_result := trustride.fn_cost_service_context_resolved_accept(p_signal_id);
    WHEN 'RESOURCE_DISPATCH_INITIATED' THEN v_result := trustride.fn_cost_resource_dispatch_initiated_accept(p_signal_id);
    WHEN 'EPRA_FUEL_INDEX_UPDATED' THEN v_result := trustride.fn_cost_epra_fuel_index_updated_accept(p_signal_id);
    WHEN 'ZONE_SURGE_TRIGGERED' THEN v_result := trustride.fn_cost_zone_surge_triggered_accept(p_signal_id);
    ELSE
      UPDATE trustride.cost_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'UNREGISTERED_SIGNAL_TYPE:' || v_signal_type WHERE signal_id = p_signal_id;
      v_result := 'REJECTED';
  END CASE;

  RETURN v_result;
END;
$$;

-- --- Correction 11 (carried forward unchanged): Resources' fn_resource_assign trip-context extension ---
-- The 4-param signature was already superseded by the prior Engine 5 push
-- (commit 6b8b632); this reset intentionally left Resources' own function
-- untouched, so the 11-param signature is already live. CREATE OR REPLACE
-- keeps it idempotent either way (fresh install or already-extended).
DROP FUNCTION IF EXISTS trustride.fn_resource_assign(UUID, UUID, UUID, UUID);

CREATE OR REPLACE FUNCTION trustride.fn_resource_assign(
  p_workforce_unit_id UUID, p_order_id UUID, p_correlation_id UUID, p_changed_by UUID,
  p_origin_zone_code TEXT DEFAULT NULL, p_destination_zone_code TEXT DEFAULT NULL,
  p_distance_km NUMERIC DEFAULT NULL, p_duration_min NUMERIC DEFAULT NULL,
  p_requester_user_id UUID DEFAULT NULL, p_jurisdiction TEXT DEFAULT NULL, p_engine_capacity TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_availability_id UUID;
  v_capacity_class  trustride.resource_capacity_class_enum;
  v_fleet_resource_id UUID;
  v_thing_id        UUID;
BEGIN
  SELECT cc.class_code, wu.fleet_resource_id INTO v_capacity_class, v_fleet_resource_id
  FROM trustride.resource_workforce_unit wu JOIN trustride.resource_capacity_class cc ON cc.capacity_class_id = wu.capacity_class_id
  WHERE wu.workforce_unit_id = p_workforce_unit_id;

  IF v_fleet_resource_id IS NOT NULL THEN
    SELECT thing_id INTO v_thing_id FROM trustride.resource_fleet_register WHERE fleet_resource_id = v_fleet_resource_id;
  END IF;

  UPDATE trustride.resource_availability_ledger SET effective_to = now()
  WHERE resource_type = 'WORKFORCE_UNIT' AND resource_ref_id = p_workforce_unit_id AND effective_to IS NULL AND availability_state = 'RESERVED';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_resource_assign: workforce_unit % is not currently RESERVED', p_workforce_unit_id;
  END IF;

  INSERT INTO trustride.resource_availability_ledger (resource_type, resource_ref_id, availability_state, reason_code, job_ref_id, changed_by)
  VALUES ('WORKFORCE_UNIT', p_workforce_unit_id, 'ASSIGNED', 'ORDER_ASSIGNMENT_CONFIRMED', p_order_id, p_changed_by)
  RETURNING availability_id INTO v_availability_id;

  INSERT INTO trustride.resource_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG004_BUS', 'RESOURCE_ASSIGNED',
    jsonb_build_object('order_id', p_order_id, 'workforce_unit_id', p_workforce_unit_id, 'capacity_class', v_capacity_class, 'engine_capacity', v_capacity_class, 'thing_id', v_thing_id),
    'RESOURCE_ASSIGNED:' || p_order_id::text || ':' || p_workforce_unit_id::text);

  INSERT INTO trustride.resource_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG005_COST', 'RESOURCE_DISPATCH_INITIATED',
    jsonb_build_object('asset_class', v_capacity_class, 'engine_capacity', p_engine_capacity, 'order_id', p_order_id, 'assignment_id', v_availability_id,
      'origin_zone_code', p_origin_zone_code, 'destination_zone_code', p_destination_zone_code, 'distance_km', p_distance_km,
      'duration_min', p_duration_min, 'requester_user_id', p_requester_user_id, 'jurisdiction', p_jurisdiction),
    'RESOURCE_DISPATCH_INITIATED:' || p_order_id::text || ':' || p_workforce_unit_id::text);

  RETURN v_availability_id;
END;
$$;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_assign(UUID, UUID, UUID, UUID, TEXT, TEXT, NUMERIC, NUMERIC, UUID, TEXT, TEXT) TO trs026_eng002_resc_service;

-- ============================================================================
-- PHASE 7 -- TRIGGERS
-- ============================================================================
-- trg_fare_quote_block_illegal_mutation is created inline with its table
-- above (Phase 3/4/5).

-- ============================================================================
-- PHASE 8 -- ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE trustride.cost_operational_zones ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_operational_zones_platform_read ON trustride.cost_operational_zones FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_operational_zones_service_write ON trustride.cost_operational_zones FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_epra_fuel_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_epra_fuel_registry_platform_read ON trustride.cost_epra_fuel_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_epra_fuel_registry_service_write ON trustride.cost_epra_fuel_registry FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_registry_platform_read ON trustride.cost_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_registry_service_write ON trustride.cost_registry FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_model ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_model_platform_read ON trustride.cost_model FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_model_service_write ON trustride.cost_model FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_model_version ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_model_version_platform_read ON trustride.cost_model_version FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_model_version_service_write ON trustride.cost_model_version FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_component ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_component_platform_read ON trustride.cost_component FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_component_service_write ON trustride.cost_component FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_component_rule ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_component_rule_platform_read ON trustride.cost_component_rule FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_component_rule_service_write ON trustride.cost_component_rule FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_rate ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_rate_platform_read ON trustride.cost_rate FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_rate_service_write ON trustride.cost_rate FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_rate_version ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_rate_version_platform_read ON trustride.cost_rate_version FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_rate_version_service_write ON trustride.cost_rate_version FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.route_cost_factor ENABLE ROW LEVEL SECURITY;
CREATE POLICY route_cost_factor_platform_read ON trustride.route_cost_factor FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY route_cost_factor_service_write ON trustride.route_cost_factor FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.return_trip_factor ENABLE ROW LEVEL SECURITY;
CREATE POLICY return_trip_factor_platform_read ON trustride.return_trip_factor FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY return_trip_factor_service_write ON trustride.return_trip_factor FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.empty_return_probability ENABLE ROW LEVEL SECURITY;
CREATE POLICY empty_return_probability_platform_read ON trustride.empty_return_probability FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY empty_return_probability_service_write ON trustride.empty_return_probability FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.regional_cost_factor ENABLE ROW LEVEL SECURITY;
CREATE POLICY regional_cost_factor_platform_read ON trustride.regional_cost_factor FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY regional_cost_factor_service_write ON trustride.regional_cost_factor FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.resource_cost_factor ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_cost_factor_platform_read ON trustride.resource_cost_factor FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_cost_factor_service_write ON trustride.resource_cost_factor FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.operational_risk_factor ENABLE ROW LEVEL SECURITY;
CREATE POLICY operational_risk_factor_platform_read ON trustride.operational_risk_factor FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY operational_risk_factor_service_write ON trustride.operational_risk_factor FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.fare_calculation ENABLE ROW LEVEL SECURITY;
CREATE POLICY fare_calculation_requester_read ON trustride.fare_calculation FOR SELECT TO trustride_authenticated USING (requester_user_id = auth.uid());
CREATE POLICY fare_calculation_service_write ON trustride.fare_calculation FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.fare_calculation_line ENABLE ROW LEVEL SECURITY;
CREATE POLICY fare_calculation_line_requester_read ON trustride.fare_calculation_line FOR SELECT TO trustride_authenticated
  USING (EXISTS (SELECT 1 FROM trustride.fare_calculation c WHERE c.calculation_id = fare_calculation_line.calculation_id AND c.requester_user_id = auth.uid()));
CREATE POLICY fare_calculation_line_service_write ON trustride.fare_calculation_line FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.fare_quote ENABLE ROW LEVEL SECURITY;
CREATE POLICY fare_quote_requester_read ON trustride.fare_quote FOR SELECT TO trustride_authenticated
  USING (EXISTS (SELECT 1 FROM trustride.fare_calculation c WHERE c.calculation_id = fare_quote.calculation_id AND c.requester_user_id = auth.uid()));
CREATE POLICY fare_quote_service_write ON trustride.fare_quote FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_record ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_record_audit_read ON trustride.cost_record FOR SELECT TO trs026_eng001_fdn_service USING (true);
CREATE POLICY cost_record_service_write ON trustride.cost_record FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_pending_service_context ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_pending_service_context_service_only ON trustride.cost_pending_service_context FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_event_outbox_service_only ON trustride.cost_event_outbox FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_event_inbox_service_only ON trustride.cost_event_inbox FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

-- ============================================================================
-- PHASE 9 -- INDEXES
-- ============================================================================
CREATE INDEX idx_cost_operational_zones_boundary ON trustride.cost_operational_zones USING GIST (boundary);
CREATE INDEX idx_cost_epra_fuel_lookup ON trustride.cost_epra_fuel_registry (fuel_type, jurisdiction, price_period DESC);
CREATE INDEX idx_cost_rate_lookup ON trustride.cost_rate (asset_class, engine_capacity);
CREATE INDEX idx_route_cost_factor_path ON trustride.route_cost_factor USING GIST (path);
CREATE INDEX idx_fare_calculation_order ON trustride.fare_calculation (order_id);
CREATE INDEX idx_fare_calculation_requester ON trustride.fare_calculation (requester_user_id);
CREATE INDEX idx_fare_calculation_correlation ON trustride.fare_calculation (correlation_id);
CREATE INDEX idx_fare_calculation_line_calc ON trustride.fare_calculation_line (calculation_id, sequence_no);
CREATE INDEX idx_fare_quote_state ON trustride.fare_quote (quote_state);
CREATE INDEX idx_fare_quote_expiry ON trustride.fare_quote (expires_at) WHERE quote_state = 'FARE_ESTIMATED';
CREATE INDEX idx_cost_record_calculation ON trustride.cost_record (calculation_id);
CREATE INDEX idx_cost_record_outcome_time ON trustride.cost_record (execution_outcome, executed_at DESC);
CREATE INDEX idx_cost_outbox_status ON trustride.cost_event_outbox (signal_status);
CREATE INDEX idx_cost_outbox_correlation ON trustride.cost_event_outbox (correlation_id);
CREATE INDEX idx_cost_inbox_status ON trustride.cost_event_inbox (signal_status);
CREATE INDEX idx_cost_inbox_correlation ON trustride.cost_event_inbox (correlation_id);

-- ============================================================================
-- PHASE 10 -- VIEWS
-- ============================================================================
CREATE VIEW trustride.v_cost_registry_active AS
SELECT r.registry_id, r.registry_code, r.macro_domain, r.service_code, r.asset_class, r.jurisdiction,
  rt.base_dispatch_fee_kes, rt.direct_per_km_rate_kes, rt.time_rate_kes_per_min, rt.waiting_rate_kes_per_min, rt.minimum_fare_floor_kes,
  m.model_version, r.overhead_pct, r.minimum_margin_pct, r.effective_from, r.effective_to
FROM trustride.cost_registry r
JOIN trustride.cost_rate rt ON rt.rate_id = r.cost_rate_id
JOIN trustride.cost_model m ON m.model_id = r.cost_model_id
WHERE r.status = 'ACTIVE';
COMMENT ON VIEW trustride.v_cost_registry_active IS 'The rate-card evaluation endpoint, realized as a queryable view.';

-- ============================================================================
-- PHASE 11 -- PRIVILEGE LOCKDOWN
-- ============================================================================
GRANT USAGE ON SCHEMA trustride TO trs026_eng005_cost_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA trustride TO trs026_eng005_cost_service;
GRANT SELECT ON trustride.v_cost_registry_active TO trustride_authenticated;

GRANT EXECUTE ON FUNCTION trustride.fn_cost_fare_calculate(TEXT, TEXT, trustride.cost_asset_class_enum, trustride.cost_engine_capacity_enum, trustride.cost_jurisdiction_enum, TEXT, TEXT, NUMERIC, NUMERIC, UUID, trustride.cost_user_type_enum, UUID, UUID, UUID, UUID, NUMERIC, GEOMETRY) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_fare_quote_issue(UUID) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_quote_lock(UUID, UUID) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_quote_mark_in_progress(UUID) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_quote_finalize(UUID, UUID) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_quote_expire_sweep() TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_quote_cancel(UUID) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_epra_fuel_index_ingest(DATE, TEXT, trustride.cost_jurisdiction_enum, NUMERIC, TEXT, UUID) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_zone_surge_apply(TEXT, NUMERIC, TIMESTAMPTZ) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_service_context_resolved_accept(UUID) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_resource_dispatch_initiated_accept(UUID) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_epra_fuel_index_updated_accept(UUID) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_zone_surge_triggered_accept(UUID) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_inbox_process(UUID) TO trs026_eng005_cost_service, trs026_eng007_orch_service;

GRANT EXECUTE ON FUNCTION trustride.fn_audit_log_append(TEXT, UUID, TEXT, UUID, TEXT, TEXT, TEXT, JSONB, JSONB) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_sequence_next(TEXT) TO trs026_eng005_cost_service;

GRANT trs026_eng005_cost_service TO service_role;

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
  WHERE table_schema = 'trustride' AND table_type = 'BASE TABLE'
    AND table_name IN (
      'cost_operational_zones','cost_epra_fuel_registry','cost_registry','cost_model','cost_model_version',
      'cost_component','cost_component_rule','cost_rate','cost_rate_version','route_cost_factor','return_trip_factor',
      'empty_return_probability','regional_cost_factor','resource_cost_factor','operational_risk_factor',
      'fare_calculation','fare_calculation_line','fare_quote','cost_record','cost_pending_service_context',
      'cost_event_outbox','cost_event_inbox'
    );
  IF v_table_count <> 22 THEN
    RAISE EXCEPTION 'Engine 5 validation failed: expected 22 tables (17 primary, where cost_event is realized as an outbox+inbox pair per platform Signal Envelope law -- 18 tables -- plus 4 supporting: cost_operational_zones, cost_epra_fuel_registry, fare_calculation_line, cost_pending_service_context), found %', v_table_count;
  END IF;

  SELECT count(*) INTO v_function_count
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'trustride'
    AND p.proname IN (
      'fn_cost_fare_calculate','fn_cost_fare_quote_issue','fn_cost_quote_lock','fn_cost_quote_mark_in_progress',
      'fn_cost_quote_finalize','fn_cost_quote_expire_sweep','fn_cost_quote_cancel','fn_cost_epra_fuel_index_ingest',
      'fn_cost_zone_surge_apply','fn_cost_service_context_resolved_accept','fn_cost_resource_dispatch_initiated_accept',
      'fn_cost_epra_fuel_index_updated_accept','fn_cost_zone_surge_triggered_accept','fn_cost_inbox_process'
    );
  IF v_function_count <> 14 THEN
    RAISE EXCEPTION 'Engine 5 validation failed: expected 14 core functions, found %', v_function_count;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng005_cost_service') THEN
    RAISE EXCEPTION 'Engine 5 validation failed: trs026_eng005_cost_service role missing';
  END IF;

  RAISE NOTICE 'Engine 5 validation passed: 22/22 tables, 14/14 core functions, service role present.';
END
$$;

-- ============================================================================
-- PHASE 13 -- FINALIZATION & SEED DATA
-- ============================================================================

INSERT INTO trustride.cost_component (component_code, component_label, component_definition, unit_of_measure) VALUES
  ('F_BASE',       'Base Dispatch Fee', 'Fixed fee charged at dispatch, independent of distance or time.', 'KES'),
  ('R_D',          'Direct Per-Km Operational Rate', 'Derived from the EPRA fuel index and maintenance baseline for the asset class.', 'KES_PER_KM'),
  ('R_T',          'Time Rate', 'Rate charged per minute of trip duration.', 'KES_PER_MIN'),
  ('R_W',          'Waiting Rate', 'Rate charged per minute of waiting exposure.', 'KES_PER_MIN'),
  ('K_RETURN',     'Zone Return/Deadhead Multiplier', 'Multiplier reflecting the likelihood and cost of an empty return leg from the destination zone.', 'MULTIPLIER'),
  ('P_EMPTY_RETURN','Empty-Return Probability', 'Estimated probability the resource returns empty after fulfilment.', 'PERCENT'),
  ('M_ROUTE',      'Route Cost Factor', 'Multiplier for terrain, toll, or congestion conditions along the route.', 'MULTIPLIER'),
  ('M_REGIONAL',   'Regional Cost Factor', 'Standing regional operating-conditions multiplier.', 'MULTIPLIER'),
  ('M_RESOURCE',   'Resource Cost Factor', 'Per-individual-resource cost adjustment multiplier.', 'MULTIPLIER'),
  ('M_RISK',       'Operational Risk Factor', 'Multiplier for explicit operational risk/safety cost exposure.', 'MULTIPLIER'),
  ('F_MIN',        'Absolute Floor Threshold', 'The minimum lawful total expected cost for the asset class.', 'KES'),
  ('S_OVERHEAD',   'Overhead', 'Governed overhead percentage applied after the floor.', 'PERCENT');

INSERT INTO trustride.cost_rate (
  asset_class, engine_capacity, base_dispatch_fee_kes, fuel_consumption_km_per_l,
  maintenance_rate_kes_per_km, direct_per_km_rate_kes, time_rate_kes_per_min, waiting_rate_kes_per_min, minimum_fare_floor_kes
) VALUES (
  'BODA_BODA', 'CC_125', 30.00, 35.00, 3.50, 12.00, 2.50, 1.00, 70.00
);

INSERT INTO trustride.cost_model (model_version, asset_class, equation_definition, status) VALUES (
  'TRS026-COST-2.0.0', 'BODA_BODA',
  '{"terms":["F_base","D*R_d*K_return*M_resource","T*R_t","W*R_w","D*R_d*K_return*P_empty_return"],"multiplier":"M_route*M_regional*M_risk","floor":"F_min","overhead":"S_overhead"}',
  'ACTIVE'
);

INSERT INTO trustride.cost_operational_zones (zone_code, zone_name, jurisdiction, density_class, boundary) VALUES
  ('KSM-CBD-01', 'Kisumu CBD', 'KISUMU_COUNTY', 'HIGH_DENSITY',
    ST_SetSRID(ST_GeomFromText('POLYGON((34.755 -0.100, 34.780 -0.100, 34.780 -0.082, 34.755 -0.082, 34.755 -0.100))'), 4326)),
  ('KSM-KONDELE-03', 'Kondele / Outskirts', 'KISUMU_COUNTY', 'OUTSKIRT_DEADZONE',
    ST_SetSRID(ST_GeomFromText('POLYGON((34.780 -0.090, 34.800 -0.090, 34.800 -0.065, 34.780 -0.065, 34.780 -0.090))'), 4326));

INSERT INTO trustride.return_trip_factor (zone_id, return_multiplier)
SELECT zone_id, CASE WHEN zone_code = 'KSM-KONDELE-03' THEN 1.30 ELSE 1.00 END FROM trustride.cost_operational_zones;

INSERT INTO trustride.empty_return_probability (zone_id, probability_pct)
SELECT zone_id, CASE WHEN zone_code = 'KSM-KONDELE-03' THEN 15.00 ELSE 2.00 END FROM trustride.cost_operational_zones;

INSERT INTO trustride.regional_cost_factor (jurisdiction, factor_multiplier, reason) VALUES ('KISUMU_COUNTY', 1.00, 'Baseline regional conditions, Kisumu launch market');

INSERT INTO trustride.operational_risk_factor (asset_class, jurisdiction, risk_category, risk_multiplier) VALUES ('BODA_BODA', 'KISUMU_COUNTY', 'STANDARD_ROAD_RISK', 1.00);

INSERT INTO trustride.cost_registry (registry_code, macro_domain, service_code, asset_class, jurisdiction, cost_rate_id, cost_model_id, overhead_pct, minimum_margin_pct)
SELECT 'TRANSPORT-BODA-KISUMU', 'TRANSPORT', 'TRANSPORT-BODA-STANDARD', 'BODA_BODA', 'KISUMU_COUNTY', rt.rate_id, m.model_id, 2.00, 8.00
FROM trustride.cost_rate rt, trustride.cost_model m
WHERE rt.asset_class = 'BODA_BODA' AND rt.engine_capacity = 'CC_125' AND rt.active = TRUE
  AND m.asset_class = 'BODA_BODA' AND m.model_version = 'TRS026-COST-2.0.0';

-- --- Extend Engine 7's dispatch mechanism to recognize Cost (Correction 10, carried forward) ---
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
      WHEN 'TRS026_ENG004_BUS'  THEN 'business_event_inbox'
      WHEN 'TRS026_ENG005_COST' THEN 'cost_event_inbox'
      ELSE NULL
    END,
    rr.target_engine || ':DEFAULT',
    rr.route_id::text, 'ACTIVE', now()
  FROM trustride.routing_rule rr
  WHERE rr.active = TRUE
    AND CASE rr.target_engine
      WHEN 'TRS026_ENG001_FDN' THEN TRUE WHEN 'TRS026_ENG002_RESC' THEN TRUE WHEN 'TRS026_ENG003_SERV' THEN TRUE
      WHEN 'TRS026_ENG004_BUS' THEN TRUE WHEN 'TRS026_ENG005_COST' THEN TRUE ELSE FALSE
    END
  ON CONFLICT (source_engine_code, signal_type, destination_engine_code) DO UPDATE
    SET destination_inbox_table = EXCLUDED.destination_inbox_table,
        cache_status = 'ACTIVE', last_synced_at = now();

  GET DIAGNOSTICS v_synced = ROW_COUNT;
  RETURN v_synced;
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
        'INSERT INTO trustride.%I (signal_id, correlation_id, causation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)',
        v_cache.destination_inbox_table
      ) USING v_row.signal_id, v_row.correlation_id, v_row.causation_id, v_row.emitting_engine, v_cache.destination_engine_code, v_row.signal_type, v_row.payload_in, v_row.idempotency_key || ':inbox';

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
          WHEN 'TRS026_ENG002_RESC' THEN PERFORM trustride.fn_resource_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG003_SERV' THEN PERFORM trustride.fn_service_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG004_BUS' THEN PERFORM trustride.fn_business_inbox_process(v_row.signal_id);
          WHEN 'TRS026_ENG005_COST' THEN PERFORM trustride.fn_cost_inbox_process(v_row.signal_id);
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

INSERT INTO trustride.orch_outbox_registry (engine_code, outbox_table_name) VALUES ('TRS026_ENG005_COST', 'cost_event_outbox');

INSERT INTO trustride.routing_rule (event_type, source_engine, target_engine, route_priority) VALUES
  ('RESOURCE_DISPATCH_INITIATED', 'TRS026_ENG002_RESC', 'TRS026_ENG005_COST', 0),
  ('SERVICE_CONTEXT_RESOLVED',    'TRS026_ENG003_SERV', 'TRS026_ENG005_COST', 0);

SELECT trustride.fn_orch_destination_cache_sync();

UPDATE trustride.engine_registry SET status = 'INSTALLED', engine_version = '2.0.0' WHERE engine_code = 'TRS026_ENG005_COST';
