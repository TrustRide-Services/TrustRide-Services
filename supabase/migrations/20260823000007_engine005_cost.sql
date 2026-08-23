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
-- ENGINE DESCRIPTION   : The platform's single, deterministic authority for
--                        turning a trip's raw parameters into one lawful,
--                        immutable unit-price quote via the Sovereign
--                        Dynamic Cost Equation.
-- ENGINE FUNCTION      : No fare figure shown to a requester, posted to an
--                        Order, or handed to settlement may originate
--                        anywhere except a cost_unit_price_quotes row
--                        produced by this engine.
-- PLATFORM VERSION     : 1.0.0
-- ENGINE VERSION       : 1.1.1
-- MIGRATION DATA
-- FILE NAME            : 20260823000007_engine005_cost.sql
-- INSTALLATION ORDER   : 005
-- STATUS               : COMPLETE -- one single migration file, 12 tables,
--                        applied on top of Foundation + Resources +
--                        Services + Orchestration + Coordination.
-- CREATED AT           : 2026-08-23
-- CREATED BY           : Onyango Albert Chitayi (Founder) + Engineering
-- ============================================================================
--
-- Source: TRS026-ENG005-COST-001 v1.1.1 (ADOPTED 2026-08-16), Sections 2-5.
-- Founder ruling 2026-08-23 (Kisumu build plan, item 4): "FULLY DESIGNED AND
-- IMPLEMENTED, END TO END... apart from the real integrators in Engine 6."
-- The Founder's separately-proposed "Cost Buildup: 17-Table Core" merge
-- (agreed in principle -- fold in what the adopted blueprint is missing,
-- one unified engine, no yours-vs-mine framing) is EXPLICITLY DEFERRED: the
-- itemized comparison content is not reliably recoverable in this session
-- (pre-dates a context compaction, never persisted to a file), and the
-- Founder has directed proceeding with full completeness on the adopted
-- blueprint now rather than stall on it. This file is that build. The
-- Cost Buildup merge remains a named, open follow-up the moment that
-- document is re-shared -- not dropped, not silently absorbed here.
--
-- Corrections applied in this compilation:
--   1. Schema-qualified every table/type/function as `trustride.*`, and
--      trs026_eng005_cost_service created immediately after Phase 1 Schema
--      -- same reasoning as every prior engine file.
--   2. REAL BUG FOUND AND FIXED (2026-08-23, caught while wiring RLS, before
--      any execution): the source document's cost_execution_ledger audit-
--      read policy grants to `trs_fdn_audit_service` -- a role that does
--      not exist under the Founder's own standing naming ruling ("EVERYTHING
--      HENCE FORTH MUST USE trs026_eng{NNN}_service"), confirmed absent in
--      Foundation's actual installed roles. Fixed by granting to Foundation's
--      real service role, trs026_eng001_fdn_service, instead.
--   3. THE REAL, ALREADY-WAITING PAYOFF: Resources and Services have both
--      been emitting RESOURCE_DISPATCH_INITIATED and SERVICE_CONTEXT_
--      RESOLVED to TRS026_ENG005_COST since the day they were built --
--      every one has sat as NO_RULE_MATCHED because Cost did not exist.
--      This file gives both signals a real, working destination for the
--      first time.
--   4. REAL GAP FOUND AND CLOSED: the source document's own §5.1 never
--      explains how RESOURCE_DISPATCH_INITIATED (asset/zones, fired at
--      resource assignment) and SERVICE_CONTEXT_RESOLVED (macro_domain/
--      service_code, fired earlier at order placement, Article 19 Stage 1)
--      join into one quote calculation -- they are two independent
--      interfaces (§1.3) with no declared correlation mechanism. Closed
--      with a small addition, cost_pending_service_context, keyed by
--      correlation_id: the service-context signal caches its payload; the
--      dispatch-initiated signal (which actually triggers calculation,
--      matching Engine 2's own comment on RESOURCE_DISPATCH_INITIATED)
--      consumes it. Not in the source document's 12 tables; documented
--      here as the join mechanism the source text assumed but never named.
--   5. REAL GAP FOUND AND CLOSED: §1.2 duty 5 states Engine 5 owns the full
--      quote_state lifecycle through FARE_LOCKED, SERVICE_IN_PROGRESS, and
--      FARE_FINALIZED, but §5.1's inbound signal list names a trigger only
--      for quote creation (FARE_ESTIMATED) -- no signal_type is given
--      anywhere in the adopted text for locking, starting, or finalizing a
--      quote (Business, the natural emitter, does not exist yet in this
--      build). Rather than fabricate an unadopted signal_type name, the
--      lifecycle functions themselves (fn_cost_quote_lock, fn_cost_quote_
--      mark_in_progress, fn_cost_quote_finalize, fn_cost_quote_expire,
--      fn_cost_quote_cancel) are built complete and callable now, ready to
--      be wired to a real inbound signal the moment Business is built and
--      that signal is named -- the lifecycle is real and enforced, only
--      its wire trigger is pending a future engine.
--   6. cost_road_segments_override (terrain, M_terrain) requires a real
--      route LINESTRING to evaluate -- nothing upstream (Resources,
--      Services) currently produces or carries one; only scalar
--      distance_km/duration_min and zone codes exist in the real signal
--      payloads today. fn_cost_quote_calculate accepts an OPTIONAL route
--      geometry parameter; M_terrain correctly defaults to 1.00 (no
--      penalty) when none is supplied, rather than fabricating a route.
--   7. cost_operational_zones gained two small additive columns (surge_
--      multiplier_active, surge_valid_until) to make ZONE_SURGE_TRIGGERED
--      (§5.1) real rather than schema-only -- ties surge state directly to
--      the zone it modifies without inventing a whole separate ledger
--      table for a temporary, expiring override.
--   8. The source document pre-seeds only a BODA_BODA baseline and its
--      formula -- no operational zone, no rate card rule exists anywhere,
--      so the pre-seeded baseline could never actually be selected by a
--      real quote. Seeded two real Kisumu zones (CBD, outskirt) and one
--      real rate card rule against Engine 3's own already-live catalogue
--      service code (TRANSPORT-BODA-STANDARD), completing the chain the
--      source document's own worked example (§4.1) assumes exists.
--   9. Explicit per-function GRANTs, never a schema-wide blanket, and
--      lawful state-changing functions append to Foundation's shared audit
--      hash chain via fn_audit_log_append, granted explicitly -- same
--      reasoning as every prior engine file's Corrections 6/7.
--   12. REAL BUG FOUND AND FIXED (2026-08-23, caught by actually calling
--      fn_cost_quote_calculate, not by inspection): quote_code generation
--      called fn_sequence_next with an invented code ('cost_quote_code')
--      that was never registered, when Foundation had already seeded the
--      correct one (TRS026-QUOTE) for exactly this purpose -- and on top
--      of that, redundantly re-prefixed and re-padded fn_sequence_next's
--      already-complete return value. Fixed by calling fn_sequence_next
--      with the real registered code and using its return value directly,
--      unwrapped.
--   11. REAL GAP FOUND AND CLOSED before any execution: Engine 2's
--      RESOURCE_DISPATCH_INITIATED payload (fn_resource_assign) carries
--      only asset identity (asset_class, order_id, assignment_id) -- no
--      trip geometry (zones, distance, duration), because Resources never
--      knows a trip's geometry; only the caller (eventually Business, via
--      the Order it owns) does. Cost cannot calculate anything without it.
--      Extended fn_resource_assign with optional trailing trip-context
--      parameters (origin/destination zone code, distance_km, duration_min,
--      requester_user_id, jurisdiction) it threads into its own outbound
--      signal when supplied -- exactly what Business will have on hand the
--      moment it exists and calls this function for real. Used DROP
--      FUNCTION then CREATE (not bare CREATE OR REPLACE), since adding
--      parameters to an existing signature creates a second, stale
--      overload rather than truly replacing it -- a real, easy-to-miss
--      PostgreSQL behavior worth remembering for every future extension of
--      an already-shipped function.
--   13. REAL BUG FOUND AND FIXED (2026-08-23, caught by actually running the
--      real cross-engine dispatch this file exists to prove, not by
--      inspection): fn_orch_dispatch_cycle drained one registered outbox
--      table fully before moving to the next -- processing signals per
--      source engine, not in true chronological order across engines,
--      exactly backwards from Engine 7's own stated mission ("in what
--      order?"). This silently broke Correction 4's correlation join: a
--      RESOURCE_DISPATCH_INITIATED signal could be processed before the
--      SERVICE_CONTEXT_RESOLVED signal it depends on, even though the
--      latter was genuinely emitted first. Fixed by building one UNION ALL
--      across every registered outbox, ordered by emitted_at, and
--      iterating that single ordered result instead of nested per-table
--      loops -- a general correctness fix to Engine 7's own mechanism, not
--      a Cost-specific patch.
--   10. Engine 7's fn_orch_dispatch_cycle and fn_orch_destination_cache_sync
--      dispatch by an explicit per-engine CASE (destination_inbox_table,
--      and which processor function to hand off to) -- there was no way
--      for Engine 7's own file to know about Cost in advance. Established
--      convention, to be repeated by every future engine's own migration:
--      extend both functions via CREATE OR REPLACE to recognize the new
--      engine, adding fn_cost_inbox_process (this file's own equivalent of
--      Engine 2/3's fn_resource_inbox_process/fn_service_inbox_process) as
--      the hand-off target. This is what finally gives RESOURCE_DISPATCH_
--      INITIATED and SERVICE_CONTEXT_RESOLVED -- both emitted since the day
--      Resources and Services were built, both NO_RULE_MATCHED ever since
--      -- a real, working destination.
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

-- ============================================================================
-- PHASE 3/4/5 -- TABLES
-- ============================================================================

-- --- 2.1 cost_operational_zones (Correction 7: + surge columns) ---
CREATE TABLE trustride.cost_operational_zones (
  zone_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  zone_code              TEXT NOT NULL UNIQUE,
  zone_name              TEXT NOT NULL,
  jurisdiction           trustride.cost_jurisdiction_enum NOT NULL,
  density_class          TEXT NOT NULL CHECK (density_class IN ('HIGH_DENSITY', 'SUBURB', 'OUTSKIRT_DEADZONE')),
  return_multiplier      NUMERIC(4,2) NOT NULL DEFAULT 1.00 CHECK (return_multiplier >= 1.00 AND return_multiplier <= 3.00),
  surge_multiplier_active NUMERIC(4,2) CHECK (surge_multiplier_active IS NULL OR (surge_multiplier_active >= 1.00 AND surge_multiplier_active <= 5.00)),
  surge_valid_until      TIMESTAMPTZ,
  boundary               GEOMETRY(POLYGON, 4326) NOT NULL,
  active                 BOOLEAN NOT NULL DEFAULT TRUE,
  effective_from         TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to           TIMESTAMPTZ,
  created_by             UUID,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_cost_zone_validity CHECK (effective_to IS NULL OR effective_to > effective_from)
);
COMMENT ON TABLE trustride.cost_operational_zones IS
  '[Trace: TBOC-v1.0.0 | Article 45] Governed micro-zones supplying K_return to the Sovereign Dynamic Cost Equation. surge_multiplier_active/surge_valid_until (Correction 7) realize ZONE_SURGE_TRIGGERED for real.';

-- --- 2.2 cost_road_segments_override ---
CREATE TABLE trustride.cost_road_segments_override (
  segment_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  segment_code       TEXT NOT NULL UNIQUE,
  segment_name       TEXT,
  jurisdiction       trustride.cost_jurisdiction_enum NOT NULL,
  surface_class      TEXT NOT NULL CHECK (surface_class IN ('ASPHALT', 'MURRAM', 'MUD_STEEP')),
  terrain_multiplier NUMERIC(4,2) NOT NULL CHECK (terrain_multiplier >= 1.00 AND terrain_multiplier <= 2.50),
  path               GEOMETRY(LINESTRING, 4326) NOT NULL,
  buffer_meters      NUMERIC(6,1) NOT NULL DEFAULT 25.0 CHECK (buffer_meters > 0),
  active             BOOLEAN NOT NULL DEFAULT TRUE,
  effective_from     TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to       TIMESTAMPTZ,
  created_by         UUID,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_cost_segment_validity CHECK (effective_to IS NULL OR effective_to > effective_from)
);
COMMENT ON TABLE trustride.cost_road_segments_override IS
  '[Trace: TBOC-v1.0.0 | Article 45] Spatial overrides supplying M_terrain; requires a real route geometry to evaluate (Correction 6) -- defaults to no penalty when none is supplied.';

-- --- 2.3 cost_epra_fuel_registry ---
CREATE TABLE trustride.cost_epra_fuel_registry (
  epra_entry_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  price_period           DATE NOT NULL,
  fuel_type              TEXT NOT NULL CHECK (fuel_type IN ('PETROL_SUPER', 'DIESEL', 'ELECTRIC_TARIFF')),
  jurisdiction           trustride.cost_jurisdiction_enum NOT NULL,
  pump_price_kes         NUMERIC(18,2) NOT NULL CHECK (pump_price_kes >= 0),
  source_reference       TEXT NOT NULL,
  ingested_via_signal_id UUID,
  effective_from         TIMESTAMPTZ NOT NULL,
  effective_to           TIMESTAMPTZ,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (price_period, fuel_type, jurisdiction)
);
COMMENT ON TABLE trustride.cost_epra_fuel_registry IS
  '[Trace: TBOC-v1.0.0 | Article 45] Append-only regulatory record. R_d is derived from the latest effective row here, never invented locally.';

-- --- 2.4 cost_asset_engine_baselines ---
CREATE TABLE trustride.cost_asset_engine_baselines (
  baseline_id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_class                   trustride.cost_asset_class_enum NOT NULL,
  engine_capacity                trustride.cost_engine_capacity_enum NOT NULL,
  base_dispatch_fee_kes           NUMERIC(18,2) NOT NULL CHECK (base_dispatch_fee_kes >= 0),
  fuel_consumption_km_per_l         NUMERIC(6,2) CHECK (fuel_consumption_km_per_l IS NULL OR fuel_consumption_km_per_l > 0),
  energy_consumption_kwh_per_km       NUMERIC(6,3) CHECK (energy_consumption_kwh_per_km IS NULL OR energy_consumption_kwh_per_km > 0),
  maintenance_rate_kes_per_km           NUMERIC(18,2) NOT NULL CHECK (maintenance_rate_kes_per_km >= 0),
  direct_per_km_rate_kes                 NUMERIC(18,2) NOT NULL CHECK (direct_per_km_rate_kes >= 0),
  time_rate_kes_per_min                    NUMERIC(18,2) NOT NULL CHECK (time_rate_kes_per_min >= 0),
  minimum_fare_floor_kes                     NUMERIC(18,2) NOT NULL CHECK (minimum_fare_floor_kes >= 0),
  active                                        BOOLEAN NOT NULL DEFAULT TRUE,
  effective_from                                  TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to                                       TIMESTAMPTZ,
  approved_by                                           UUID,
  approved_request_id                                     UUID REFERENCES trustride.approval_request (request_id),
  created_at                                                 TIMESTAMPTZ NOT NULL DEFAULT now(),
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
COMMENT ON TABLE trustride.cost_asset_engine_baselines IS
  '[Trace: TBOC-v1.0.0 | Article 45] Governed, versioned mechanical baselines.';

-- --- 3.2 cost_formula_matrix ---
CREATE TABLE trustride.cost_formula_matrix (
  formula_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  formula_version      TEXT NOT NULL,
  asset_class          trustride.cost_asset_class_enum NOT NULL,
  equation_definition  JSONB NOT NULL,
  component_weights    JSONB NOT NULL DEFAULT '{}',
  status               TEXT NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT','ACTIVE','SUPERSEDED')),
  approved_by          UUID,
  approved_request_id  UUID REFERENCES trustride.approval_request (request_id),
  effective_from       TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to         TIMESTAMPTZ,
  superseded_by        UUID REFERENCES trustride.cost_formula_matrix (formula_id),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (formula_version, asset_class)
);
COMMENT ON TABLE trustride.cost_formula_matrix IS
  '[Trace: TBOC-v1.0.0 | Article 45] The governed, versioned binding of an equation shape to an asset class; exactly one ACTIVE row per asset_class.';

-- --- 3.4 cost_rate_card_rule ---
CREATE TABLE trustride.cost_rate_card_rule (
  rate_card_rule_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_code               TEXT NOT NULL UNIQUE,
  macro_domain            TEXT NOT NULL CHECK (macro_domain IN ('TRANSPORT','COURIER','DELIVERY','EXECUTIVE_ASSISTANTS','MARKETPLACE')),
  service_code            TEXT NOT NULL,
  asset_class             trustride.cost_asset_class_enum NOT NULL,
  jurisdiction            trustride.cost_jurisdiction_enum NOT NULL,
  baseline_id             UUID NOT NULL REFERENCES trustride.cost_asset_engine_baselines (baseline_id),
  formula_id              UUID NOT NULL REFERENCES trustride.cost_formula_matrix (formula_id),
  governance_surcharge_kes NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (governance_surcharge_kes >= 0),
  minimum_margin_pct      NUMERIC(5,2) NOT NULL DEFAULT 8.00 CHECK (minimum_margin_pct >= 0),
  status                  TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('DRAFT','ACTIVE','SUPERSEDED')),
  approved_request_id     UUID REFERENCES trustride.approval_request (request_id),
  effective_from          TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to            TIMESTAMPTZ,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_cost_rate_card_active
  ON trustride.cost_rate_card_rule (macro_domain, service_code, asset_class, jurisdiction) WHERE status = 'ACTIVE';
COMMENT ON TABLE trustride.cost_rate_card_rule IS
  '[Trace: TBOC-v1.0.0 | Article 44] The selector: given domain, service, asset class, jurisdiction, which baseline and formula apply.';

-- --- 2.5 cost_unit_price_quotes ---
CREATE TABLE trustride.cost_unit_price_quotes (
  quote_id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_code                   TEXT NOT NULL UNIQUE,
  order_id                     UUID,
  assignment_id                UUID,
  requester_user_id            UUID NOT NULL,
  requester_user_type          trustride.cost_user_type_enum NOT NULL,
  asset_class                  trustride.cost_asset_class_enum NOT NULL,
  engine_capacity               trustride.cost_engine_capacity_enum NOT NULL,
  jurisdiction                  trustride.cost_jurisdiction_enum NOT NULL,
  origin_zone_id                 UUID NOT NULL REFERENCES trustride.cost_operational_zones (zone_id),
  destination_zone_id             UUID NOT NULL REFERENCES trustride.cost_operational_zones (zone_id),
  distance_km                      NUMERIC(8,3) NOT NULL CHECK (distance_km >= 0),
  duration_min                      NUMERIC(8,2) NOT NULL CHECK (duration_min >= 0),
  base_dispatch_fee_kes               NUMERIC(18,2) NOT NULL CHECK (base_dispatch_fee_kes >= 0),
  direct_per_km_rate_kes               NUMERIC(18,2) NOT NULL CHECK (direct_per_km_rate_kes >= 0),
  return_multiplier_applied             NUMERIC(4,2) NOT NULL CHECK (return_multiplier_applied >= 1.00),
  time_rate_kes_per_min                  NUMERIC(18,2) NOT NULL CHECK (time_rate_kes_per_min >= 0),
  terrain_multiplier_applied              NUMERIC(4,2) NOT NULL CHECK (terrain_multiplier_applied >= 1.00),
  minimum_fare_floor_kes                   NUMERIC(18,2) NOT NULL CHECK (minimum_fare_floor_kes >= 0),
  governance_surcharge_kes                  NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (governance_surcharge_kes >= 0),
  pre_floor_fare_kes                          NUMERIC(18,2) NOT NULL CHECK (pre_floor_fare_kes >= 0),
  computed_total_fare_kes                       NUMERIC(18,2) NOT NULL CHECK (computed_total_fare_kes >= 0),
  currency                                       CHAR(3) NOT NULL DEFAULT 'KES',
  formula_version                                 TEXT NOT NULL,
  epra_entry_id                                    UUID REFERENCES trustride.cost_epra_fuel_registry (epra_entry_id),
  quote_state                                       trustride.cost_quote_state_enum NOT NULL DEFAULT 'FARE_ESTIMATED',
  quote_hash                                         CHAR(64) NOT NULL,
  prev_quote_hash                                     CHAR(64),
  locked_at                                            TIMESTAMPTZ,
  expires_at                                            TIMESTAMPTZ NOT NULL,
  finalized_at                                           TIMESTAMPTZ,
  cancelled_at                                            TIMESTAMPTZ,
  correlation_id                                           UUID NOT NULL,
  causation_id                                              UUID,
  created_at                                                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_cost_quote_fare_math
    CHECK (computed_total_fare_kes >= LEAST(pre_floor_fare_kes, minimum_fare_floor_kes) + governance_surcharge_kes - 0.01)
);
COMMENT ON TABLE trustride.cost_unit_price_quotes IS
  '[Trace: TBOC-v1.0.0 | Article 20.2, 42, 45] The single lawful source of computed fare truth.';

-- Append-only discipline once a quote is locked
CREATE OR REPLACE FUNCTION trustride.cost_quotes_block_illegal_mutation()
RETURNS trigger
LANGUAGE plpgsql SET search_path = trustride, pg_temp
AS $$
BEGIN
  IF OLD.quote_state IN ('FARE_LOCKED', 'SERVICE_IN_PROGRESS', 'FARE_FINALIZED', 'C2B_PAYMENT_TRIGGERED')
     AND (NEW.computed_total_fare_kes IS DISTINCT FROM OLD.computed_total_fare_kes
          OR NEW.quote_hash IS DISTINCT FROM OLD.quote_hash) THEN
    RAISE EXCEPTION 'cost_unit_price_quotes: fare and hash are immutable once quote_state = %; correction requires a new quote', OLD.quote_state;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_cost_quotes_block_illegal_mutation
  BEFORE UPDATE ON trustride.cost_unit_price_quotes
  FOR EACH ROW EXECUTE FUNCTION trustride.cost_quotes_block_illegal_mutation();

-- --- 3.3 cost_unit_price_buildup_entry ---
CREATE TABLE trustride.cost_unit_price_buildup_entry (
  buildup_entry_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id           UUID NOT NULL REFERENCES trustride.cost_unit_price_quotes (quote_id),
  component_code     TEXT NOT NULL CHECK (component_code IN
                        ('F_BASE','DISTANCE_COST','TIME_COST','TERRAIN_ADJUSTMENT','FLOOR_ADJUSTMENT','GOVERNANCE_SURCHARGE')),
  raw_input_value    NUMERIC(12,4),
  rate_applied       NUMERIC(10,4),
  multiplier_applied NUMERIC(4,2) NOT NULL DEFAULT 1.00,
  line_amount_kes    NUMERIC(18,2) NOT NULL CHECK (line_amount_kes >= 0),
  sequence_no        SMALLINT NOT NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.cost_unit_price_buildup_entry IS
  '[Trace: TBOC-v1.0.0 | Article 42, 45] The itemized, transparent receipt behind computed_total_fare_kes.';

-- --- 3.5 cost_execution_ledger ---
CREATE TABLE trustride.cost_execution_ledger (
  ledger_entry_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id            UUID REFERENCES trustride.cost_unit_price_quotes (quote_id),
  rate_card_rule_id   UUID REFERENCES trustride.cost_rate_card_rule (rate_card_rule_id),
  execution_outcome   TEXT NOT NULL CHECK (execution_outcome IN
                         ('CALCULATED','REJECTED_NO_RULE','REJECTED_MARGIN_BREACH','EXPIRED','RECALCULATED')),
  input_snapshot      JSONB NOT NULL,
  output_snapshot     JSONB,
  engine_version      TEXT NOT NULL,
  duration_ms         INTEGER NOT NULL CHECK (duration_ms >= 0),
  correlation_id      UUID NOT NULL,
  executed_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.cost_execution_ledger IS
  '[Trace: TBOC-v1.0.0 | Article 49] Append-only audit trail of every calculation, including recalculations and rejections.';
REVOKE UPDATE, DELETE ON trustride.cost_execution_ledger FROM PUBLIC;

-- --- 3.6 cost_component_primitive ---
CREATE TABLE trustride.cost_component_primitive (
  component_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  component_code       TEXT NOT NULL UNIQUE,
  component_label      TEXT NOT NULL,
  component_definition TEXT NOT NULL,
  unit_of_measure      TEXT NOT NULL CHECK (unit_of_measure IN ('KES','KES_PER_KM','KES_PER_MIN','MULTIPLIER','RATIO')),
  version              SMALLINT NOT NULL DEFAULT 1,
  superseded_by        UUID REFERENCES trustride.cost_component_primitive (component_id),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.cost_component_primitive IS
  '[Trace: TBOC-v1.0.0 | Article 8] Governed vocabulary so F_base/R_d/K_return/R_t/M_terrain/F_min/S_governance are never spelled inconsistently.';

-- --- Correction 4: the cross-signal join, not in the source document ---
CREATE TABLE trustride.cost_pending_service_context (
  correlation_id UUID PRIMARY KEY,
  macro_domain   TEXT NOT NULL,
  service_code   TEXT NOT NULL,
  cached_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.cost_pending_service_context IS
  'Correction 4 (not in the source document): SERVICE_CONTEXT_RESOLVED arrives before RESOURCE_DISPATCH_INITIATED (Article 19 Stage 1 precedes assignment); this bridges the two by correlation_id since the source document never names the join.';

-- --- 2.6 Engine Event Substrate ---
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

-- ============================================================================
-- PHASE 6 -- FUNCTIONS
-- ============================================================================

-- --- The Sovereign Dynamic Cost Equation, implemented for real (§3.1) ---
CREATE OR REPLACE FUNCTION trustride.fn_cost_quote_calculate(
  p_macro_domain TEXT, p_service_code TEXT, p_asset_class trustride.cost_asset_class_enum, p_engine_capacity trustride.cost_engine_capacity_enum,
  p_jurisdiction trustride.cost_jurisdiction_enum, p_origin_zone_code TEXT, p_destination_zone_code TEXT,
  p_distance_km NUMERIC, p_duration_min NUMERIC, p_requester_user_id UUID, p_requester_user_type trustride.cost_user_type_enum,
  p_correlation_id UUID, p_order_id UUID DEFAULT NULL, p_assignment_id UUID DEFAULT NULL, p_route_path GEOMETRY DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public, extensions, pg_temp
AS $$
DECLARE
  v_start_time      TIMESTAMPTZ := clock_timestamp();
  v_rule            RECORD;
  v_baseline        RECORD;
  v_formula         RECORD;
  v_origin_zone     RECORD;
  v_dest_zone       RECORD;
  v_terrain_mult    NUMERIC(4,2) := 1.00;
  v_return_mult     NUMERIC(4,2);
  v_distance_cost   NUMERIC(18,2);
  v_time_cost       NUMERIC(18,2);
  v_pre_floor_fare  NUMERIC(18,2);
  v_floor_adjustment NUMERIC(18,2);
  v_post_floor_fare NUMERIC(18,2);
  v_total_fare      NUMERIC(18,2);
  v_quote_id        UUID;
  v_quote_code      TEXT;
  v_quote_hash      CHAR(64);
  v_prev_hash       CHAR(64);
  v_margin_pct      NUMERIC(6,2);
  v_ledger_id       UUID;
BEGIN
  SELECT * INTO v_rule FROM trustride.cost_rate_card_rule
  WHERE macro_domain = p_macro_domain AND service_code = p_service_code AND asset_class = p_asset_class
    AND jurisdiction = p_jurisdiction AND status = 'ACTIVE';

  IF v_rule IS NULL THEN
    INSERT INTO trustride.cost_execution_ledger (execution_outcome, input_snapshot, engine_version, duration_ms, correlation_id)
    VALUES ('REJECTED_NO_RULE', jsonb_build_object('macro_domain', p_macro_domain, 'service_code', p_service_code, 'asset_class', p_asset_class, 'jurisdiction', p_jurisdiction),
      '1.1.1', extract(milliseconds FROM clock_timestamp() - v_start_time)::int, p_correlation_id)
    RETURNING ledger_entry_id INTO v_ledger_id;
    RAISE EXCEPTION 'fn_cost_quote_calculate: no ACTIVE cost_rate_card_rule for domain=%, service=%, asset_class=%, jurisdiction=% (ledger_entry_id=%)',
      p_macro_domain, p_service_code, p_asset_class, p_jurisdiction, v_ledger_id;
  END IF;

  SELECT * INTO v_baseline FROM trustride.cost_asset_engine_baselines WHERE baseline_id = v_rule.baseline_id;
  SELECT * INTO v_formula FROM trustride.cost_formula_matrix WHERE formula_id = v_rule.formula_id;
  SELECT * INTO v_origin_zone FROM trustride.cost_operational_zones WHERE zone_code = p_origin_zone_code AND active = TRUE;
  SELECT * INTO v_dest_zone FROM trustride.cost_operational_zones WHERE zone_code = p_destination_zone_code AND active = TRUE;

  IF v_origin_zone IS NULL OR v_dest_zone IS NULL THEN
    RAISE EXCEPTION 'fn_cost_quote_calculate: unknown or inactive zone_code (origin=%, destination=%)', p_origin_zone_code, p_destination_zone_code;
  END IF;

  -- K_return: destination zone's governed multiplier, elevated by any
  -- currently-active surge (Correction 7).
  v_return_mult := GREATEST(
    v_dest_zone.return_multiplier,
    CASE WHEN v_dest_zone.surge_valid_until IS NOT NULL AND v_dest_zone.surge_valid_until > now()
      THEN coalesce(v_dest_zone.surge_multiplier_active, v_dest_zone.return_multiplier) ELSE v_dest_zone.return_multiplier END
  );

  -- M_terrain: only evaluated if a real route was supplied (Correction 6).
  IF p_route_path IS NOT NULL THEN
    SELECT max(terrain_multiplier) INTO v_terrain_mult FROM trustride.cost_road_segments_override
    WHERE active = TRUE AND jurisdiction = p_jurisdiction AND ST_DWithin(path, p_route_path, buffer_meters);
    v_terrain_mult := coalesce(v_terrain_mult, 1.00);
  END IF;

  v_distance_cost := p_distance_km * v_baseline.direct_per_km_rate_kes * v_return_mult;
  v_time_cost := p_duration_min * v_baseline.time_rate_kes_per_min;
  v_pre_floor_fare := (v_baseline.base_dispatch_fee_kes + v_distance_cost + v_time_cost) * v_terrain_mult;
  v_post_floor_fare := GREATEST(v_pre_floor_fare, v_baseline.minimum_fare_floor_kes);
  v_floor_adjustment := v_post_floor_fare - v_pre_floor_fare;
  v_total_fare := v_post_floor_fare + v_rule.governance_surcharge_kes;

  -- Margin protection (§1.2 duty 7): margin over the raw distance-based
  -- operational cost, per the source document's own "margin over
  -- direct_per_km_rate_kes cost" wording.
  IF v_total_fare > 0 THEN
    v_margin_pct := ((v_total_fare - (p_distance_km * v_baseline.direct_per_km_rate_kes)) / v_total_fare) * 100;
  ELSE
    v_margin_pct := 0;
  END IF;

  -- fn_sequence_next already returns the complete, formatted code
  -- (prefix || '-' || padded number) -- it does not need re-wrapping.
  -- Found before this bug reached a real database: an earlier draft
  -- re-prefixed and re-padded an already-complete code, and used an
  -- unregistered sequence_code besides.
  v_quote_code := trustride.fn_sequence_next('TRS026-QUOTE');

  SELECT quote_hash INTO v_prev_hash FROM trustride.cost_unit_price_quotes ORDER BY created_at DESC LIMIT 1;
  v_quote_hash := encode(digest(coalesce(v_prev_hash,'') || v_quote_code || v_total_fare::text || now()::text, 'sha256'), 'hex');

  INSERT INTO trustride.cost_unit_price_quotes (
    quote_code, order_id, assignment_id, requester_user_id, requester_user_type, asset_class, engine_capacity, jurisdiction,
    origin_zone_id, destination_zone_id, distance_km, duration_min, base_dispatch_fee_kes, direct_per_km_rate_kes,
    return_multiplier_applied, time_rate_kes_per_min, terrain_multiplier_applied, minimum_fare_floor_kes,
    governance_surcharge_kes, pre_floor_fare_kes, computed_total_fare_kes, formula_version, quote_hash, prev_quote_hash,
    expires_at, correlation_id
  ) VALUES (
    v_quote_code, p_order_id, p_assignment_id, p_requester_user_id, p_requester_user_type, p_asset_class, p_engine_capacity, p_jurisdiction,
    v_origin_zone.zone_id, v_dest_zone.zone_id, p_distance_km, p_duration_min, v_baseline.base_dispatch_fee_kes, v_baseline.direct_per_km_rate_kes,
    v_return_mult, v_baseline.time_rate_kes_per_min, v_terrain_mult, v_baseline.minimum_fare_floor_kes,
    v_rule.governance_surcharge_kes, v_pre_floor_fare, v_total_fare, v_formula.formula_version, v_quote_hash, v_prev_hash,
    now() + interval '5 minutes', p_correlation_id
  ) RETURNING quote_id INTO v_quote_id;

  INSERT INTO trustride.cost_unit_price_buildup_entry (quote_id, component_code, raw_input_value, rate_applied, multiplier_applied, line_amount_kes, sequence_no) VALUES
    (v_quote_id, 'F_BASE', NULL, NULL, 1.00, v_baseline.base_dispatch_fee_kes, 1),
    (v_quote_id, 'DISTANCE_COST', p_distance_km, v_baseline.direct_per_km_rate_kes, v_return_mult, v_distance_cost, 2),
    (v_quote_id, 'TIME_COST', p_duration_min, v_baseline.time_rate_kes_per_min, 1.00, v_time_cost, 3),
    (v_quote_id, 'TERRAIN_ADJUSTMENT', NULL, NULL, v_terrain_mult, v_pre_floor_fare - (v_baseline.base_dispatch_fee_kes + v_distance_cost + v_time_cost), 4),
    (v_quote_id, 'FLOOR_ADJUSTMENT', NULL, NULL, 1.00, v_floor_adjustment, 5),
    (v_quote_id, 'GOVERNANCE_SURCHARGE', NULL, NULL, 1.00, v_rule.governance_surcharge_kes, 6);

  INSERT INTO trustride.cost_execution_ledger (quote_id, rate_card_rule_id, execution_outcome, input_snapshot, output_snapshot, engine_version, duration_ms, correlation_id)
  VALUES (v_quote_id, v_rule.rate_card_rule_id, 'CALCULATED',
    jsonb_build_object('distance_km', p_distance_km, 'duration_min', p_duration_min, 'asset_class', p_asset_class),
    jsonb_build_object('computed_total_fare_kes', v_total_fare, 'margin_pct', v_margin_pct),
    '1.1.1', extract(milliseconds FROM clock_timestamp() - v_start_time)::int, p_correlation_id);

  IF v_margin_pct < v_rule.minimum_margin_pct THEN
    INSERT INTO trustride.cost_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (p_correlation_id, 'TRS026_ENG009_AIADV', 'COST_MARGIN_BREACHED',
      jsonb_build_object('rate_card_rule_id', v_rule.rate_card_rule_id, 'computed_margin_pct', v_margin_pct, 'minimum_margin_pct', v_rule.minimum_margin_pct, 'quote_id', v_quote_id),
      'COST_MARGIN_BREACHED:' || v_quote_id::text);
  END IF;

  RETURN v_quote_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_cost_quote_calculate(TEXT, TEXT, trustride.cost_asset_class_enum, trustride.cost_engine_capacity_enum, trustride.cost_jurisdiction_enum, TEXT, TEXT, NUMERIC, NUMERIC, UUID, trustride.cost_user_type_enum, UUID, UUID, UUID, GEOMETRY) IS
  '[Trace: §3.1] The Sovereign Dynamic Cost Equation, implemented, not restated. The quote is still produced on a margin breach -- the requester is never left without a fare -- but the breach is flagged, never silently absorbed.';

-- --- Quote lifecycle custody (§1.2 duty 5; Correction 5: callable now, wire trigger TBD) ---
CREATE OR REPLACE FUNCTION trustride.fn_cost_quote_lock(p_quote_id UUID, p_correlation_id UUID DEFAULT gen_random_uuid())
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_quote RECORD;
BEGIN
  UPDATE trustride.cost_unit_price_quotes SET quote_state = 'FARE_LOCKED', locked_at = now()
  WHERE quote_id = p_quote_id AND quote_state = 'FARE_ESTIMATED' AND expires_at > now()
  RETURNING * INTO v_quote;

  IF v_quote IS NULL THEN
    RAISE EXCEPTION 'fn_cost_quote_lock: quote % is not a live FARE_ESTIMATED quote (expired, wrong state, or does not exist)', p_quote_id;
  END IF;

  INSERT INTO trustride.cost_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG004_BUS', 'UNIT_PRICE_LOCKED',
    jsonb_build_object('quote_id', v_quote.quote_id, 'quote_code', v_quote.quote_code, 'computed_total_fare_kes', v_quote.computed_total_fare_kes,
      'currency', v_quote.currency, 'expires_at', v_quote.expires_at, 'order_id', v_quote.order_id),
    'UNIT_PRICE_LOCKED:' || p_quote_id::text);
END;
$$;
COMMENT ON FUNCTION trustride.fn_cost_quote_lock(UUID, UUID) IS
  '[Trace: §5.2] FARE_ESTIMATED -> FARE_LOCKED, "the requester has accepted the posted fee" (Article 20.2). Emits UNIT_PRICE_LOCKED to Business.';

CREATE OR REPLACE FUNCTION trustride.fn_cost_quote_mark_in_progress(p_quote_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
BEGIN
  UPDATE trustride.cost_unit_price_quotes SET quote_state = 'SERVICE_IN_PROGRESS'
  WHERE quote_id = p_quote_id AND quote_state = 'FARE_LOCKED';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_cost_quote_mark_in_progress: quote % is not FARE_LOCKED (or does not exist)', p_quote_id;
  END IF;
END;
$$;
COMMENT ON FUNCTION trustride.fn_cost_quote_mark_in_progress(UUID) IS
  '[Trace: §1.2 duty 5] FARE_LOCKED -> SERVICE_IN_PROGRESS. Wire trigger pending Business (Correction 5).';

CREATE OR REPLACE FUNCTION trustride.fn_cost_quote_finalize(p_quote_id UUID, p_correlation_id UUID DEFAULT gen_random_uuid())
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_quote RECORD;
BEGIN
  UPDATE trustride.cost_unit_price_quotes SET quote_state = 'FARE_FINALIZED', finalized_at = now()
  WHERE quote_id = p_quote_id AND quote_state = 'SERVICE_IN_PROGRESS'
  RETURNING * INTO v_quote;

  IF v_quote IS NULL THEN
    RAISE EXCEPTION 'fn_cost_quote_finalize: quote % is not SERVICE_IN_PROGRESS (or does not exist)', p_quote_id;
  END IF;

  UPDATE trustride.cost_unit_price_quotes SET quote_state = 'C2B_PAYMENT_TRIGGERED' WHERE quote_id = p_quote_id;

  INSERT INTO trustride.cost_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG006_INTG', 'PAYMENT_STK_TRIGGERED',
    jsonb_build_object('quote_id', v_quote.quote_id, 'computed_total_fare_kes', v_quote.computed_total_fare_kes, 'currency', v_quote.currency,
      'requester_user_id', v_quote.requester_user_id, 'payment_rail', 'MPESA_C2B_STK'),
    'PAYMENT_STK_TRIGGERED:' || p_quote_id::text);
END;
$$;
COMMENT ON FUNCTION trustride.fn_cost_quote_finalize(UUID, UUID) IS
  '[Trace: §5.2] SERVICE_IN_PROGRESS -> FARE_FINALIZED -> C2B_PAYMENT_TRIGGERED. Emits PAYMENT_STK_TRIGGERED to Integration -- Engine 5 never calls M-Pesa/Flutterwave itself.';

CREATE OR REPLACE FUNCTION trustride.fn_cost_quote_expire_sweep()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_expired INTEGER;
BEGIN
  UPDATE trustride.cost_unit_price_quotes SET quote_state = 'EXPIRED'
  WHERE quote_state = 'FARE_ESTIMATED' AND expires_at < now();
  GET DIAGNOSTICS v_expired = ROW_COUNT;

  INSERT INTO trustride.cost_execution_ledger (execution_outcome, input_snapshot, engine_version, duration_ms, correlation_id)
  SELECT 'EXPIRED', jsonb_build_object('quote_id', quote_id), '1.1.1', 0, correlation_id
  FROM trustride.cost_unit_price_quotes WHERE quote_state = 'EXPIRED' AND quote_id NOT IN (SELECT quote_id FROM trustride.cost_execution_ledger WHERE execution_outcome = 'EXPIRED');

  RETURN v_expired;
END;
$$;
COMMENT ON FUNCTION trustride.fn_cost_quote_expire_sweep() IS
  'A quote left FARE_ESTIMATED past its expiry never silently disappears -- it is marked EXPIRED and ledgered.';

CREATE OR REPLACE FUNCTION trustride.fn_cost_quote_cancel(p_quote_id UUID, p_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
BEGIN
  UPDATE trustride.cost_unit_price_quotes SET quote_state = 'CANCELLED', cancelled_at = now()
  WHERE quote_id = p_quote_id AND quote_state IN ('FARE_ESTIMATED', 'FARE_LOCKED');
  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_cost_quote_cancel: quote % cannot be cancelled from its current state (or does not exist)', p_quote_id;
  END IF;
END;
$$;

-- --- EPRA fuel ingestion (§1.2 duty 3) ---
CREATE OR REPLACE FUNCTION trustride.fn_cost_epra_fuel_index_ingest(
  p_price_period DATE, p_fuel_type TEXT, p_jurisdiction trustride.cost_jurisdiction_enum, p_pump_price_kes NUMERIC, p_source_reference TEXT, p_signal_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_epra_entry_id UUID;
  v_baseline RECORD;
  v_new_rate NUMERIC(18,2);
  v_new_baseline_id UUID;
BEGIN
  INSERT INTO trustride.cost_epra_fuel_registry (price_period, fuel_type, jurisdiction, pump_price_kes, source_reference, ingested_via_signal_id, effective_from)
  VALUES (p_price_period, p_fuel_type, p_jurisdiction, p_pump_price_kes, p_source_reference, p_signal_id, p_price_period::timestamptz)
  RETURNING epra_entry_id INTO v_epra_entry_id;

  -- Recompute R_d for every ACTIVE baseline whose consumption profile this
  -- fuel type feeds, by superseding with a new baseline row -- never
  -- overwriting history (matches the constitutional "never invented
  -- locally, never silently drifts" requirement for R_d).
  FOR v_baseline IN
    SELECT * FROM trustride.cost_asset_engine_baselines
    WHERE active = TRUE
      AND ((p_fuel_type IN ('PETROL_SUPER','DIESEL') AND fuel_consumption_km_per_l IS NOT NULL)
        OR (p_fuel_type = 'ELECTRIC_TARIFF' AND energy_consumption_kwh_per_km IS NOT NULL))
  LOOP
    v_new_rate := CASE
      WHEN v_baseline.fuel_consumption_km_per_l IS NOT NULL THEN round((p_pump_price_kes / v_baseline.fuel_consumption_km_per_l) + v_baseline.maintenance_rate_kes_per_km, 2)
      ELSE round((p_pump_price_kes * v_baseline.energy_consumption_kwh_per_km) + v_baseline.maintenance_rate_kes_per_km, 2)
    END;

    UPDATE trustride.cost_asset_engine_baselines SET active = FALSE, effective_to = now() WHERE baseline_id = v_baseline.baseline_id;

    INSERT INTO trustride.cost_asset_engine_baselines (
      asset_class, engine_capacity, base_dispatch_fee_kes, fuel_consumption_km_per_l, energy_consumption_kwh_per_km,
      maintenance_rate_kes_per_km, direct_per_km_rate_kes, time_rate_kes_per_min, minimum_fare_floor_kes
    ) VALUES (
      v_baseline.asset_class, v_baseline.engine_capacity, v_baseline.base_dispatch_fee_kes, v_baseline.fuel_consumption_km_per_l, v_baseline.energy_consumption_kwh_per_km,
      v_baseline.maintenance_rate_kes_per_km, v_new_rate, v_baseline.time_rate_kes_per_min, v_baseline.minimum_fare_floor_kes
    ) RETURNING baseline_id INTO v_new_baseline_id;

    -- Real gap closed here, found before any execution: without this, a
    -- superseded baseline's recomputed rate would never actually reach a
    -- live quote -- every ACTIVE rate_card_rule still referencing the
    -- just-superseded baseline_id is repointed to the new one.
    UPDATE trustride.cost_rate_card_rule SET baseline_id = v_new_baseline_id
    WHERE baseline_id = v_baseline.baseline_id AND status = 'ACTIVE';
  END LOOP;

  RETURN v_epra_entry_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_cost_epra_fuel_index_ingest(DATE, TEXT, trustride.cost_jurisdiction_enum, NUMERIC, TEXT, UUID) IS
  '[Trace: §1.2 duty 3] Absorbs an EPRA fuel index publication and recomputes R_d via a governed baseline supersession, never a silent drift.';

-- --- Zone surge (§5.1 ZONE_SURGE_TRIGGERED, Correction 7) ---
CREATE OR REPLACE FUNCTION trustride.fn_cost_zone_surge_apply(p_zone_code TEXT, p_surge_multiplier NUMERIC, p_valid_until TIMESTAMPTZ)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
BEGIN
  UPDATE trustride.cost_operational_zones SET surge_multiplier_active = p_surge_multiplier, surge_valid_until = p_valid_until
  WHERE zone_code = p_zone_code AND active = TRUE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_cost_zone_surge_apply: unknown or inactive zone_code %', p_zone_code;
  END IF;
END;
$$;
COMMENT ON FUNCTION trustride.fn_cost_zone_surge_apply(TEXT, NUMERIC, TIMESTAMPTZ) IS
  '[Trace: §5.1 ZONE_SURGE_TRIGGERED] Every quote computed under surge carries the elevated return_multiplier_applied transparently.';

-- --- Inbound signal accept-handlers (§5.1) ---
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
COMMENT ON FUNCTION trustride.fn_cost_service_context_resolved_accept(UUID) IS
  '[Trace: §5.1 SERVICE_CONTEXT_RESOLVED] Caches the domain/service context by correlation_id (Correction 4) for the later RESOURCE_DISPATCH_INITIATED signal to consume.';

CREATE OR REPLACE FUNCTION trustride.fn_cost_resource_dispatch_initiated_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public, extensions, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_correlation_id UUID;
  v_context RECORD;
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
    v_quote_id := trustride.fn_cost_quote_calculate(
      v_context.macro_domain, v_context.service_code,
      (v_payload->>'asset_class')::trustride.cost_asset_class_enum,
      coalesce((v_payload->>'engine_capacity')::trustride.cost_engine_capacity_enum, 'NOT_APPLICABLE'),
      coalesce((v_payload->>'jurisdiction')::trustride.cost_jurisdiction_enum, 'KISUMU_COUNTY'),
      v_payload->>'origin_zone_code', v_payload->>'destination_zone_code',
      coalesce((v_payload->>'distance_km')::numeric, 0), coalesce((v_payload->>'duration_min')::numeric, 0),
      coalesce((v_payload->>'requester_user_id')::uuid, '00000000-0000-0000-0000-000000000000'::uuid), 'CUSTOMER',
      v_correlation_id, (v_payload->>'order_id')::uuid, (v_payload->>'assignment_id')::uuid
    );
  EXCEPTION WHEN OTHERS THEN
    UPDATE trustride.cost_event_inbox SET signal_status = 'REJECTED', rejection_reason = SQLERRM, accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END;

  DELETE FROM trustride.cost_pending_service_context WHERE correlation_id = v_correlation_id;

  UPDATE trustride.cost_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('quote_id', v_quote_id) WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_cost_resource_dispatch_initiated_accept(UUID) IS
  '[Trace: §5.1 RESOURCE_DISPATCH_INITIATED] The real trigger for quote calculation -- joins with the cached service context (Correction 4) and produces a FARE_ESTIMATED quote.';

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
COMMENT ON FUNCTION trustride.fn_cost_epra_fuel_index_updated_accept(UUID) IS
  '[Trace: §5.1 EPRA_FUEL_INDEX_UPDATED] Regulatory feed ingestion via Integration''s external-system boundary.';

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
COMMENT ON FUNCTION trustride.fn_cost_zone_surge_triggered_accept(UUID) IS
  '[Trace: §5.1 ZONE_SURGE_TRIGGERED] Coordination-aggregated demand telemetry (Engine 7/8) elevating a zone''s return multiplier until valid_until.';

-- --- Correction 10: Cost's own inbox processor, matching the fn_resource_
-- inbox_process/fn_service_inbox_process convention Engine 7's file established ---
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
COMMENT ON FUNCTION trustride.fn_cost_inbox_process(UUID) IS
  'Dispatches a RECEIVED cost_event_inbox row to the matching accept-handler by signal_type -- Cost''s own equivalent of Engine 2/3''s inbox processors.';

-- ============================================================================
-- PHASE 7 -- TRIGGERS
-- ============================================================================
-- trg_cost_quotes_block_illegal_mutation is created inline with its table
-- above (Phase 3/4/5) -- no additional cross-row CHECK-avoidance triggers
-- are required by any other table in this engine.

-- ============================================================================
-- PHASE 8 -- ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE trustride.cost_operational_zones ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_operational_zones_platform_read ON trustride.cost_operational_zones FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_operational_zones_service_write ON trustride.cost_operational_zones FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_road_segments_override ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_road_segments_override_platform_read ON trustride.cost_road_segments_override FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_road_segments_override_service_write ON trustride.cost_road_segments_override FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_epra_fuel_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_epra_fuel_registry_platform_read ON trustride.cost_epra_fuel_registry FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_epra_fuel_registry_service_write ON trustride.cost_epra_fuel_registry FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_asset_engine_baselines ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_asset_engine_baselines_platform_read ON trustride.cost_asset_engine_baselines FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_asset_engine_baselines_service_write ON trustride.cost_asset_engine_baselines FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_formula_matrix ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_formula_matrix_platform_read ON trustride.cost_formula_matrix FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_formula_matrix_service_write ON trustride.cost_formula_matrix FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_rate_card_rule ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_rate_card_rule_platform_read ON trustride.cost_rate_card_rule FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_rate_card_rule_service_write ON trustride.cost_rate_card_rule FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_unit_price_quotes ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_unit_price_quotes_requester_read ON trustride.cost_unit_price_quotes FOR SELECT TO trustride_authenticated USING (requester_user_id = auth.uid());
CREATE POLICY cost_unit_price_quotes_service_write ON trustride.cost_unit_price_quotes FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_unit_price_buildup_entry ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_unit_price_buildup_entry_requester_read ON trustride.cost_unit_price_buildup_entry FOR SELECT TO trustride_authenticated
  USING (EXISTS (SELECT 1 FROM trustride.cost_unit_price_quotes q WHERE q.quote_id = cost_unit_price_buildup_entry.quote_id AND q.requester_user_id = auth.uid()));
CREATE POLICY cost_unit_price_buildup_entry_service_write ON trustride.cost_unit_price_buildup_entry FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_execution_ledger ENABLE ROW LEVEL SECURITY;
-- Correction 2: trs_fdn_audit_service does not exist under the Founder's
-- own naming ruling; grants to Foundation's real service role instead.
CREATE POLICY cost_execution_ledger_audit_read ON trustride.cost_execution_ledger FOR SELECT TO trs026_eng001_fdn_service USING (true);
CREATE POLICY cost_execution_ledger_service_write ON trustride.cost_execution_ledger FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_component_primitive ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_component_primitive_platform_read ON trustride.cost_component_primitive FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_component_primitive_service_write ON trustride.cost_component_primitive FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

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
CREATE INDEX idx_cost_operational_zones_jurisdiction ON trustride.cost_operational_zones (jurisdiction) WHERE active = TRUE;
CREATE UNIQUE INDEX uq_cost_operational_zones_code_active ON trustride.cost_operational_zones (zone_code) WHERE active = TRUE;

CREATE INDEX idx_cost_road_segments_path ON trustride.cost_road_segments_override USING GIST (path);
CREATE INDEX idx_cost_road_segments_jurisdiction ON trustride.cost_road_segments_override (jurisdiction) WHERE active = TRUE;

CREATE INDEX idx_cost_epra_fuel_lookup ON trustride.cost_epra_fuel_registry (fuel_type, jurisdiction, price_period DESC);

CREATE UNIQUE INDEX uq_cost_asset_baselines_active ON trustride.cost_asset_engine_baselines (asset_class, engine_capacity) WHERE active = TRUE;
CREATE INDEX idx_cost_asset_baselines_lookup ON trustride.cost_asset_engine_baselines (asset_class, engine_capacity);

CREATE UNIQUE INDEX uq_cost_formula_matrix_active ON trustride.cost_formula_matrix (asset_class) WHERE status = 'ACTIVE';
CREATE INDEX idx_cost_formula_matrix_lookup ON trustride.cost_formula_matrix (asset_class, status);

CREATE INDEX idx_cost_quotes_state ON trustride.cost_unit_price_quotes (quote_state);
CREATE INDEX idx_cost_quotes_order ON trustride.cost_unit_price_quotes (order_id);
CREATE INDEX idx_cost_quotes_requester ON trustride.cost_unit_price_quotes (requester_user_id);
CREATE INDEX idx_cost_quotes_correlation ON trustride.cost_unit_price_quotes (correlation_id);
CREATE INDEX idx_cost_quotes_expiry ON trustride.cost_unit_price_quotes (expires_at) WHERE quote_state = 'FARE_ESTIMATED';

CREATE INDEX idx_cost_buildup_quote ON trustride.cost_unit_price_buildup_entry (quote_id, sequence_no);

CREATE INDEX idx_cost_ledger_quote ON trustride.cost_execution_ledger (quote_id);
CREATE INDEX idx_cost_ledger_outcome_time ON trustride.cost_execution_ledger (execution_outcome, executed_at DESC);

CREATE INDEX idx_cost_outbox_status ON trustride.cost_event_outbox (signal_status);
CREATE INDEX idx_cost_outbox_correlation ON trustride.cost_event_outbox (correlation_id);
CREATE INDEX idx_cost_inbox_status ON trustride.cost_event_inbox (signal_status);
CREATE INDEX idx_cost_inbox_correlation ON trustride.cost_event_inbox (correlation_id);

-- ============================================================================
-- PHASE 10 -- VIEWS
-- ============================================================================
CREATE VIEW trustride.v_cost_rate_card_active AS
SELECT rc.rate_card_rule_id, rc.rule_code, rc.macro_domain, rc.service_code, rc.asset_class, rc.jurisdiction,
  b.base_dispatch_fee_kes, b.direct_per_km_rate_kes, b.time_rate_kes_per_min, b.minimum_fare_floor_kes,
  f.formula_version, rc.governance_surcharge_kes, rc.minimum_margin_pct, rc.effective_from, rc.effective_to
FROM trustride.cost_rate_card_rule rc
JOIN trustride.cost_asset_engine_baselines b ON b.baseline_id = rc.baseline_id
JOIN trustride.cost_formula_matrix f ON f.formula_id = rc.formula_id
WHERE rc.status = 'ACTIVE';
COMMENT ON VIEW trustride.v_cost_rate_card_active IS '[Trace: §4.2] The rate-card evaluation endpoint, realized as a queryable view.';

-- ============================================================================
-- PHASE 11 -- PRIVILEGE LOCKDOWN
-- ============================================================================
GRANT USAGE ON SCHEMA trustride TO trs026_eng005_cost_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA trustride TO trs026_eng005_cost_service;
GRANT SELECT ON trustride.v_cost_rate_card_active TO trustride_authenticated;

GRANT EXECUTE ON FUNCTION trustride.fn_cost_quote_calculate(TEXT, TEXT, trustride.cost_asset_class_enum, trustride.cost_engine_capacity_enum, trustride.cost_jurisdiction_enum, TEXT, TEXT, NUMERIC, NUMERIC, UUID, trustride.cost_user_type_enum, UUID, UUID, UUID, GEOMETRY) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_quote_lock(UUID, UUID) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_quote_mark_in_progress(UUID) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_quote_finalize(UUID, UUID) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_quote_expire_sweep() TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_quote_cancel(UUID, TEXT) TO trs026_eng005_cost_service;
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
  WHERE table_schema = 'trustride' AND table_type = 'BASE TABLE' AND table_name LIKE 'cost_%';
  IF v_table_count <> 13 THEN
    RAISE EXCEPTION 'Engine 5 validation failed: expected 13 cost_ tables (12 adopted + 1 join fix, Correction 4), found %', v_table_count;
  END IF;

  SELECT count(*) INTO v_function_count
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'trustride' AND p.proname LIKE 'fn_cost%';
  IF v_function_count <> 13 THEN
    RAISE EXCEPTION 'Engine 5 validation failed: expected 13 fn_cost%% functions, found %', v_function_count;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng005_cost_service') THEN
    RAISE EXCEPTION 'Engine 5 validation failed: trs026_eng005_cost_service role missing';
  END IF;

  RAISE NOTICE 'Engine 5 validation passed: 13/13 cost_ tables, 13/13 fn_cost%% functions, service role present.';
END
$$;

-- ============================================================================
-- PHASE 13 -- FINALIZATION & SEED DATA
-- ============================================================================

-- --- Governed vocabulary (§3.6), verbatim from the adopted blueprint ---
INSERT INTO trustride.cost_component_primitive (component_code, component_label, component_definition, unit_of_measure) VALUES
  ('F_BASE',       'Base Dispatch Fee',                 'Fixed fee charged at dispatch, independent of distance or time.', 'KES'),
  ('R_D',          'Direct Per-Km Operational Rate',    'Derived from the EPRA fuel index and maintenance baseline for the asset class.', 'KES_PER_KM'),
  ('K_RETURN',     'Zone Return/Deadhead Multiplier',   'Multiplier applied to distance cost reflecting the likelihood and cost of an empty return leg from the destination zone.', 'MULTIPLIER'),
  ('R_T',          'Time Rate',                          'Rate charged per minute of trip duration.', 'KES_PER_MIN'),
  ('M_TERRAIN',    'Surface Penalty Multiplier',          'Multiplier applied to the full pre-floor fare reflecting road surface difficulty along the route.', 'MULTIPLIER'),
  ('F_MIN',        'Absolute Floor Threshold',             'The minimum lawful total fare for the asset class, applied after the terrain multiplier.', 'KES'),
  ('S_GOVERNANCE', 'Statutory & Governance Surcharge',      'Statutory fees, municipal parking, and safety reserves added after the floor is applied.', 'KES');

-- --- Baseline: BODA_BODA/CC_125, verbatim from the adopted blueprint ---
INSERT INTO trustride.cost_asset_engine_baselines (
  asset_class, engine_capacity, base_dispatch_fee_kes, fuel_consumption_km_per_l,
  maintenance_rate_kes_per_km, direct_per_km_rate_kes, time_rate_kes_per_min, minimum_fare_floor_kes
) VALUES (
  'BODA_BODA', 'CC_125', 30.00, 35.00, 3.50, 12.00, 2.50, 70.00
);

-- --- Formula: the Sovereign Dynamic Cost Equation for BODA_BODA, verbatim ---
INSERT INTO trustride.cost_formula_matrix (formula_version, asset_class, equation_definition, status, effective_from) VALUES (
  'FDN-COST-1.0.0', 'BODA_BODA',
  '{"terms":["F_base","D*R_d*K_return","T*R_t"],"multiplier":"M_terrain","floor":"F_min","addend":"S_governance"}',
  'ACTIVE', now()
);

-- --- Correction 8: the zones and rate card the adopted blueprint's own
-- worked example (§4.1) assumes exist, but never seeds ---
INSERT INTO trustride.cost_operational_zones (zone_code, zone_name, jurisdiction, density_class, return_multiplier, boundary) VALUES
  ('KSM-CBD-01', 'Kisumu CBD', 'KISUMU_COUNTY', 'HIGH_DENSITY', 1.00,
    ST_SetSRID(ST_GeomFromText('POLYGON((34.755 -0.100, 34.780 -0.100, 34.780 -0.082, 34.755 -0.082, 34.755 -0.100))'), 4326)),
  ('KSM-KONDELE-03', 'Kondele / Outskirts', 'KISUMU_COUNTY', 'OUTSKIRT_DEADZONE', 1.30,
    ST_SetSRID(ST_GeomFromText('POLYGON((34.780 -0.090, 34.800 -0.090, 34.800 -0.065, 34.780 -0.065, 34.780 -0.090))'), 4326));

INSERT INTO trustride.cost_rate_card_rule (rule_code, macro_domain, service_code, asset_class, jurisdiction, baseline_id, formula_id, governance_surcharge_kes, minimum_margin_pct)
SELECT 'TRANSPORT-BODA-KISUMU', 'TRANSPORT', 'TRANSPORT-BODA-STANDARD', 'BODA_BODA', 'KISUMU_COUNTY', b.baseline_id, f.formula_id, 5.00, 8.00
FROM trustride.cost_asset_engine_baselines b, trustride.cost_formula_matrix f
WHERE b.asset_class = 'BODA_BODA' AND b.engine_capacity = 'CC_125' AND b.active = TRUE
  AND f.asset_class = 'BODA_BODA' AND f.formula_version = 'FDN-COST-1.0.0';

-- --- Correction 11: extend Resources' fn_resource_assign with optional trip
-- context so RESOURCE_DISPATCH_INITIATED can actually carry what Cost
-- needs. DROP first -- adding parameters via bare CREATE OR REPLACE would
-- create a second, stale overload rather than truly replacing the
-- original (a real PostgreSQL behavior, not a bug in the original file). ---
DROP FUNCTION IF EXISTS trustride.fn_resource_assign(UUID, UUID, UUID, UUID);

CREATE FUNCTION trustride.fn_resource_assign(
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

  -- Correction 11: trip context (zones/distance/duration/requester/
  -- jurisdiction) threaded through when the caller supplies it -- Resources
  -- itself never knows trip geometry, only whoever placed the Order does
  -- (Business, once built). engine_capacity is also optional and separate
  -- from capacity_class (Resources tracks no cc-rating anywhere yet on
  -- resource_fleet_register -- a real, named, deferred data-model gap,
  -- not silently worked around here).
  INSERT INTO trustride.resource_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG005_COST', 'RESOURCE_DISPATCH_INITIATED',
    jsonb_build_object('asset_class', v_capacity_class, 'engine_capacity', p_engine_capacity, 'order_id', p_order_id, 'assignment_id', v_availability_id,
      'origin_zone_code', p_origin_zone_code, 'destination_zone_code', p_destination_zone_code, 'distance_km', p_distance_km,
      'duration_min', p_duration_min, 'requester_user_id', p_requester_user_id, 'jurisdiction', p_jurisdiction),
    'RESOURCE_DISPATCH_INITIATED:' || p_order_id::text || ':' || p_workforce_unit_id::text);

  RETURN v_availability_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_assign(UUID, UUID, UUID, UUID, TEXT, TEXT, NUMERIC, NUMERIC, UUID, TEXT, TEXT) IS
  'Extended by Engine 5''s own migration (Correction 11) with optional trailing trip-context parameters so RESOURCE_DISPATCH_INITIATED can actually carry what Cost needs to calculate a fare.';
GRANT EXECUTE ON FUNCTION trustride.fn_resource_assign(UUID, UUID, UUID, UUID, TEXT, TEXT, NUMERIC, NUMERIC, UUID, TEXT, TEXT) TO trs026_eng002_resc_service;

-- --- Correction 10: extend Engine 7's dispatch mechanism to recognize Cost ---
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
      WHEN 'TRS026_ENG005_COST' THEN 'cost_event_inbox'
      ELSE NULL
    END,
    rr.target_engine || ':DEFAULT',
    rr.route_id::text, 'ACTIVE', now()
  FROM trustride.routing_rule rr
  WHERE rr.active = TRUE
    AND CASE rr.target_engine
      WHEN 'TRS026_ENG001_FDN' THEN TRUE WHEN 'TRS026_ENG002_RESC' THEN TRUE WHEN 'TRS026_ENG003_SERV' THEN TRUE
      WHEN 'TRS026_ENG005_COST' THEN TRUE ELSE FALSE
    END
  ON CONFLICT (source_engine_code, signal_type, destination_engine_code) DO UPDATE
    SET destination_inbox_table = EXCLUDED.destination_inbox_table,
        cache_status = 'ACTIVE', last_synced_at = now();

  GET DIAGNOSTICS v_synced = ROW_COUNT;
  RETURN v_synced;
END;
$$;
COMMENT ON FUNCTION trustride.fn_orch_destination_cache_sync() IS
  'Refreshes orch_destination_cache from Foundation''s routing_rule, for destination engines whose inbox table is known to actually exist. Extended by Engine 5''s own migration (Correction 10) to recognize Cost -- the established convention every future engine repeats.';

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
  -- Real ordering bug found and fixed here (2026-08-23), caught by
  -- Engine 5's own real cross-engine test: draining one registered
  -- outbox fully before moving to the next processes signals per source
  -- engine, not in true chronological order across engines -- exactly
  -- backwards from Engine 7's own mission ("in what order?"). A signal
  -- correctly emitted earlier by one engine could still be processed
  -- AFTER a later signal from a different engine, breaking anything that
  -- depends on true arrival order (e.g. Cost's SERVICE_CONTEXT_RESOLVED /
  -- RESOURCE_DISPATCH_INITIATED correlation join, Correction 4). Fixed by
  -- building one UNION ALL across every registered outbox table, ordered
  -- by emitted_at, and iterating that single ordered result instead of
  -- nested per-table loops.
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
COMMENT ON FUNCTION trustride.fn_orch_dispatch_cycle() IS
  'The heartbeat itself: discover every PENDING row across every registered outbox in true chronological (emitted_at) order, route, admit (Engine 8), queue, dispatch into the destination inbox, and hand off to that engine''s own processor. Idempotent per idempotency_key. Extended by Engine 5''s own migration (Corrections 10 and 13) to recognize Cost and to fix a real cross-engine ordering bug.';

-- Correction 10: register Cost's own outbox so its outbound signals
-- (UNIT_PRICE_LOCKED, PAYMENT_STK_TRIGGERED, COST_MARGIN_BREACHED) are
-- discovered too -- correctly NO_RULE_MATCHED until Business/Integration/
-- Advisory exist, never silently ignored.
INSERT INTO trustride.orch_outbox_registry (engine_code, outbox_table_name) VALUES ('TRS026_ENG005_COST', 'cost_event_outbox');

-- Correction 3/4 continuation: the routing law for the two signals
-- Resources and Services have been emitting to Cost since the day each
-- was built.
INSERT INTO trustride.routing_rule (event_type, source_engine, target_engine, route_priority) VALUES
  ('RESOURCE_DISPATCH_INITIATED', 'TRS026_ENG002_RESC', 'TRS026_ENG005_COST', 0),
  ('SERVICE_CONTEXT_RESOLVED',    'TRS026_ENG003_SERV', 'TRS026_ENG005_COST', 0);
-- Not yet registered (destination/source engine not yet built):
-- EPRA_FUEL_INDEX_UPDATED (Integration -> Cost), ZONE_SURGE_TRIGGERED
-- (Coordination -> Cost, no real demand-telemetry emitter exists yet),
-- UNIT_PRICE_LOCKED (Cost -> Business), PAYMENT_STK_TRIGGERED
-- (Cost -> Integration), COST_MARGIN_BREACHED (Cost -> Advisory).

SELECT trustride.fn_orch_destination_cache_sync();

UPDATE trustride.engine_registry SET status = 'INSTALLED', engine_version = '1.1.1' WHERE engine_code = 'TRS026_ENG005_COST';
