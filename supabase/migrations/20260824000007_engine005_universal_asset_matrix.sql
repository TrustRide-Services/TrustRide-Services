-- ============================================================================
-- TRUSTRIDE SERVICES PLATFORM
-- ============================================================================
-- ENGINE CODE          : TRS026_ENG005_COST (extension)
-- MIGRATION DATA
-- FILE NAME            : 20260824000007_engine005_universal_asset_matrix.sql
-- STATUS               : COMPLETE -- additive, no destructive changes.
-- CREATED AT           : 2026-08-24
-- ============================================================================
--
-- FOUNDER DIRECTIVE: "Principal Enterprise Architect" executive directive --
-- Engine 5 hardened into a fully all-through-round cost determination
-- engine for every asset/resource TrustRide deploys, covering both a
-- Universal Vehicle Asset Matrix (2/3/4/6-wheelers, hardening the ALREADY-
-- UNIVERSAL fn_cost_fare_calculate equation with real multi-vehicle data --
-- explicitly NOT a re-engineering) and a genuinely NEW Executive
-- Assistant/Personal Shopper hourly labor cost path grounded in Kenyan
-- statutory minimum wage law.
--
-- ENUM ALIGNMENT (Founder-directed: "if the enums don't tally, use what we
-- had initially established"): the directive's own draft schema proposes
-- WHEELER_2_BODA/WHEELER_3_TUKTUK/WHEELER_4_SALOON/etc. -- these do NOT
-- match cost_asset_class_enum's real, live values (BODA_BODA, TUKTUK,
-- SEDAN, PICKUP_TOWN, VAN_CARGO, TRUCK_LIGHT, EXECUTIVE_ASSISTANT_HUMAN),
-- which themselves mirror resource_capacity_class_enum exactly, per the
-- Engines 1-5 reconciliation pass that fixed this precise mismatch class of
-- bug two increments ago. The already-established names are kept;
-- engine_capacity_enum gains two genuinely missing values (CC_1500_SALOON,
-- TON_7_0) needed for the 4-wheeler Saloon and heavier 6-wheeler Truck
-- classes -- additive, not a rename. jurisdiction_enum/quote_state_enum/
-- user_type_enum in the directive already match the live enums exactly, no
-- change needed there.
--
-- PARADIGM A -- Universal Vehicle Asset Matrix (hardening, not new logic):
-- fn_cost_fare_calculate's equation is already universal and untouched
-- here (per the directive's own explicit instruction not to re-engineer
-- it). What was genuinely missing: real cost_rate/cost_registry rows for
-- every vehicle class beyond BODA_BODA (TUKTUK, SEDAN, PICKUP_TOWN,
-- VAN_CARGO, TRUCK_LIGHT all had zero seeded data, meaning dispatch would
-- fail outright for six of Resources' seven real capacity classes); a new
-- statutory_fee_kes column on cost_registry realizing S_governance (a flat
-- add-on, distinct from the existing percentage-based overhead_pct, added
-- purely additively so every already-tested calculation is unchanged by
-- default); and a correction to return_trip_factor's own governed values
-- to the Founder's now-explicit authoritative figures (1.0 HIGH_DENSITY,
-- 1.3 SUBURB, 1.7 OUTSKIRT_DEADZONE -- the prior seed had Kondele at 1.30,
-- which the Founder's own directive corrects to 1.70 for a true
-- OUTSKIRT_DEADZONE). M_terrain (route_cost_factor, already built and
-- tested) is NOT seeded with fabricated road geometry here -- no real
-- surveyed road-surface data exists in this session; the mechanism is
-- complete and already defaults safely to 1.00 (asphalt-equivalent)
-- absent real data, named explicitly rather than faked.
--
-- PARADIGM B -- Executive Assistant/Personal Shopper hourly labor (new,
-- as the directive itself labels it): a dedicated equation, dedicated
-- governed tables (cost_ea_rate, cost_ea_shift_multiplier), and a
-- dedicated calculation function (fn_cost_ea_labor_calculate) producing
-- the SAME canonical fare_calculation/fare_quote records the vehicle path
-- produces -- fn_cost_fare_quote_issue and the entire quote lifecycle
-- (lock/mark_in_progress/finalize) already work unchanged for this path,
-- since they are asset-class-agnostic by design. Statutory_Monthly_Min for
-- PERSONAL_SHOPPER_ERRAND/HOUSE_MANAGER_DOMESTIC uses the Founder's own
-- supplied figure (KES 15,200, matching Kenya's real gazetted general
-- minimum wage order for urban municipalities); the other four skill
-- categories are seeded with clearly-labeled, reasonable governed
-- estimates for skilled-cadre municipal rates, not fabricated as verified
-- fact -- named explicitly as pending real Ministry of Labour gazette
-- confirmation, the same discipline already used for EPRA fuel/terrain
-- data elsewhere in this engine. fare_calculation.registry_id is NOT NULL
-- platform-wide -- found only by running the real function end to end, not
-- by inspection -- so fn_cost_ea_labor_calculate resolves its own real
-- cost_registry row too, one per skill category's real Services-catalogue
-- code, under macro_domain='EXECUTIVE_ASSISTANTS' (already anticipated in
-- cost_registry's own CHECK constraint since the original 17-table
-- design); cost_rate_id/cost_model_id stay NULL on these rows since EA
-- uses cost_ea_rate, not the vehicle rate-card mechanism.
--
-- fn_resource_assign (Engine 2, already live) gains a generic, additive
-- p_extra_context JSONB parameter so asset-specific dispatch context (EA
-- skill category, billed hours, shift type, etc., or any future asset
-- type's own fields) can flow through the real RESOURCE_DISPATCH_INITIATED
-- signal without inventing new named parameters per asset type.
-- fn_cost_resource_dispatch_initiated_accept now branches on asset_class:
-- EXECUTIVE_ASSISTANT_HUMAN routes to the new labor equation, every other
-- class keeps using the untouched, universal vehicle equation.
--
-- ============================================================================

-- ============================================================================
-- PHASE 1 -- ENUM ALIGNMENT (additive only; CC_1500_SALOON/TON_7_0 were
-- added to cost_engine_capacity_enum in the immediately-preceding migration
-- file, 20260824000006_engine005_engine_capacity_enum.sql, since a newly
-- added enum value cannot be referenced in the same transaction that added
-- it, and each migration file is its own transaction)
-- ============================================================================
CREATE TYPE trustride.ea_skill_category_enum AS ENUM (
  'PERSONAL_SHOPPER_ERRAND', 'HOUSE_MANAGER_DOMESTIC', 'PROFESSIONAL_CHAUFFEUR',
  'CERTIFIED_CHEF', 'PATIENT_ELDER_CAREGIVER', 'CORPORATE_REPRESENTATIVE'
);
CREATE TYPE trustride.cost_shift_type_enum AS ENUM ('DAY', 'NIGHT', 'SUNDAY_HOLIDAY');

-- ============================================================================
-- PHASE 2 -- SCHEMA (additive)
-- ============================================================================

-- S_governance: a flat statutory/municipal/safety-reserve fee, distinct
-- from the existing percentage-based overhead_pct -- DEFAULT 0 means every
-- already-tested calculation is completely unchanged unless explicitly
-- seeded otherwise.
ALTER TABLE trustride.cost_registry ADD COLUMN statutory_fee_kes NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (statutory_fee_kes >= 0);
COMMENT ON COLUMN trustride.cost_registry.statutory_fee_kes IS
  'S_governance: statutory fees, municipal parking, safety reserves -- a flat KES add-on applied after the floor, alongside (not instead of) the existing percentage overhead_pct.';

-- --- Paradigm B: the EA/Personal Shopper hourly labor rate card ---
CREATE TABLE trustride.cost_ea_rate (
  ea_rate_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ea_skill_category           trustride.ea_skill_category_enum NOT NULL,
  jurisdiction                trustride.cost_jurisdiction_enum NOT NULL,
  statutory_monthly_min_kes   NUMERIC(18,2) NOT NULL CHECK (statutory_monthly_min_kes >= 0),
  on_cost_pct                 NUMERIC(5,2) NOT NULL DEFAULT 22.00 CHECK (on_cost_pct >= 0),
  platform_margin_pct         NUMERIC(5,2) NOT NULL DEFAULT 25.00 CHECK (platform_margin_pct >= 0),
  queue_wait_rate_kes_per_min NUMERIC(18,2) NOT NULL DEFAULT 2.00 CHECK (queue_wait_rate_kes_per_min >= 0),
  minimum_engagement_hours    NUMERIC(4,2) NOT NULL CHECK (minimum_engagement_hours BETWEEN 1.0 AND 4.0),
  floor_price_kes             NUMERIC(18,2) NOT NULL CHECK (floor_price_kes >= 0),
  data_source                 TEXT NOT NULL DEFAULT 'GOVERNED_ESTIMATE' CHECK (data_source IN ('FOUNDER_SUPPLIED_GAZETTE_FIGURE', 'GOVERNED_ESTIMATE')),
  active                      BOOLEAN NOT NULL DEFAULT TRUE,
  effective_from              TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to                TIMESTAMPTZ,
  approved_request_id         UUID REFERENCES trustride.approval_request (request_id),
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_cost_ea_rate_active ON trustride.cost_ea_rate (ea_skill_category, jurisdiction) WHERE active = TRUE;
COMMENT ON TABLE trustride.cost_ea_rate IS
  'Paradigm B''s governed rate card: Client_Hourly_Rate = (statutory_monthly_min_kes / 208) * (1 + on_cost_pct/100) * (1 + platform_margin_pct/100), per Kenyan Labour Law and gazetted municipal minimum wage orders. data_source distinguishes a figure the Founder supplied directly from a governed estimate pending real gazette verification -- never silently presented as equally authoritative.';

-- --- Shift multiplier -- a cross-cutting time-of-day/day-of-week rule ---
CREATE TABLE trustride.cost_ea_shift_multiplier (
  shift_multiplier_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shift_type          trustride.cost_shift_type_enum NOT NULL UNIQUE,
  multiplier          NUMERIC(4,2) NOT NULL CHECK (multiplier >= 1.00),
  active              BOOLEAN NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.cost_ea_shift_multiplier IS
  'DAY=1.0, NIGHT (19:00-06:00)=1.5, SUNDAY_HOLIDAY=2.0, per the Founder''s own directive.';

-- Transparency: every other applied factor has its own _applied column on
-- fare_calculation; statutory_fee_kes gets the same treatment rather than
-- being silently folded into computed_total_fare_kes untraceably.
ALTER TABLE trustride.fare_calculation ADD COLUMN statutory_fee_applied NUMERIC(18,2) NOT NULL DEFAULT 0;

-- ============================================================================
-- PHASE 3 -- PARADIGM A: fn_cost_fare_calculate hardened with S_governance
-- (the universal equation itself is UNCHANGED, per the Founder's explicit
-- "do not re-engineer" instruction -- the only addition is the new flat
-- statutory_fee_kes term, additive and DEFAULT 0)
-- ============================================================================
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
      '2.1.0', extract(milliseconds FROM clock_timestamp() - v_start_time)::int, p_correlation_id)
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
  -- S_governance (hardening, 2026-08-24): a flat statutory/municipal fee
  -- added after the floor, alongside the existing percentage overhead --
  -- DEFAULT 0 on cost_registry means this term vanishes for every
  -- already-seeded registry unless explicitly governed otherwise.
  v_total_fare := v_total_expected_cost + v_overhead_kes + v_registry.statutory_fee_kes;

  IF v_total_fare > 0 THEN
    v_margin_pct := ((v_total_fare - (p_distance_km * v_rate.direct_per_km_rate_kes)) / v_total_fare) * 100;
  ELSE
    v_margin_pct := 0;
  END IF;

  INSERT INTO trustride.fare_calculation (
    registry_id, order_id, assignment_id, requester_user_id, requester_user_type, asset_class, engine_capacity, jurisdiction,
    origin_zone_id, destination_zone_id, distance_km, duration_min, waiting_min, base_dispatch_fee_kes, direct_per_km_rate_kes,
    time_rate_kes_per_min, waiting_rate_kes_per_min, return_multiplier_applied, route_factor_applied, empty_return_probability_applied,
    regional_factor_applied, resource_cost_factor_applied, operational_risk_factor_applied, overhead_pct_applied, statutory_fee_applied,
    minimum_fare_floor_kes, pre_floor_fare_kes, total_expected_cost_kes, computed_total_fare_kes, model_version, correlation_id
  ) VALUES (
    v_registry.registry_id, p_order_id, p_assignment_id, p_requester_user_id, p_requester_user_type, p_asset_class, p_engine_capacity, p_jurisdiction,
    v_origin_zone.zone_id, v_dest_zone.zone_id, p_distance_km, p_duration_min, p_waiting_min, v_rate.base_dispatch_fee_kes, v_rate.direct_per_km_rate_kes,
    v_rate.time_rate_kes_per_min, v_rate.waiting_rate_kes_per_min, v_return_mult, v_route_mult, v_empty_return_pct,
    v_regional_mult, v_resource_mult, v_risk_mult, v_registry.overhead_pct, v_registry.statutory_fee_kes,
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
    (v_calculation_id, 'OVERHEAD', NULL, v_registry.overhead_pct, 1.00, v_overhead_kes, 8),
    (v_calculation_id, 'STATUTORY_FEE', NULL, NULL, 1.00, v_registry.statutory_fee_kes, 9);

  INSERT INTO trustride.cost_record (calculation_id, registry_id, execution_outcome, input_snapshot, output_snapshot, engine_version, duration_ms, correlation_id)
  VALUES (v_calculation_id, v_registry.registry_id, 'CALCULATED',
    jsonb_build_object('distance_km', p_distance_km, 'duration_min', p_duration_min, 'waiting_min', p_waiting_min, 'asset_class', p_asset_class),
    jsonb_build_object('computed_total_fare_kes', v_total_fare, 'margin_pct', v_margin_pct),
    '2.1.0', extract(milliseconds FROM clock_timestamp() - v_start_time)::int, p_correlation_id);

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
  'TOTAL EXPECTED COST = resource cost + route cost + time cost + waiting exposure + return-trip exposure + empty-return probability + regional conditions + operational risk + overhead + S_governance -> floor -> approved margin check. Hardened 2026-08-24 with the statutory fee term; equation otherwise unchanged, per the Founder''s own explicit "do not re-engineer" directive. Universal across every vehicle class (2/3/4/6-wheelers) -- variance is purely data (cost_rate), never code.';

-- ============================================================================
-- PHASE 4 -- PARADIGM B: Executive Assistant / Personal Shopper hourly
-- labor cost (genuinely new, per the Founder's own directive)
-- ============================================================================
CREATE OR REPLACE FUNCTION trustride.fn_cost_ea_labor_calculate(
  p_ea_skill_category trustride.ea_skill_category_enum, p_jurisdiction trustride.cost_jurisdiction_enum, p_service_zone_code TEXT,
  p_billed_hours NUMERIC, p_shift_type trustride.cost_shift_type_enum, p_queue_wait_min NUMERIC, p_transit_delivery_fee_kes NUMERIC,
  p_requester_user_id UUID, p_correlation_id UUID, p_order_id UUID DEFAULT NULL, p_assignment_id UUID DEFAULT NULL,
  p_service_code TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public, extensions, pg_temp
AS $$
DECLARE
  v_start_time      TIMESTAMPTZ := clock_timestamp();
  v_ea_rate         RECORD;
  v_shift           RECORD;
  v_zone            RECORD;
  v_registry        RECORD;
  v_billed_hours_effective NUMERIC(6,2);
  v_client_hourly_rate     NUMERIC(18,2);
  v_labor_cost      NUMERIC(18,2);
  v_queue_wait_cost NUMERIC(18,2);
  v_pre_floor_fare  NUMERIC(18,2);
  v_total_expected_cost NUMERIC(18,2);
  v_floor_adjustment NUMERIC(18,2);
  v_calculation_id  UUID;
  v_ledger_id       UUID;
BEGIN
  SELECT * INTO v_ea_rate FROM trustride.cost_ea_rate
  WHERE ea_skill_category = p_ea_skill_category AND jurisdiction = p_jurisdiction AND active = TRUE;

  IF v_ea_rate IS NULL THEN
    INSERT INTO trustride.cost_record (execution_outcome, input_snapshot, engine_version, duration_ms, correlation_id)
    VALUES ('REJECTED_NO_REGISTRY', jsonb_build_object('ea_skill_category', p_ea_skill_category, 'jurisdiction', p_jurisdiction),
      '2.1.0', extract(milliseconds FROM clock_timestamp() - v_start_time)::int, p_correlation_id)
    RETURNING record_id INTO v_ledger_id;
    RAISE EXCEPTION 'fn_cost_ea_labor_calculate: no ACTIVE cost_ea_rate for skill_category=%, jurisdiction=% (record_id=%)', p_ea_skill_category, p_jurisdiction, v_ledger_id;
  END IF;

  -- fare_calculation.registry_id is NOT NULL platform-wide -- EA bookings
  -- resolve their own cost_registry row too, per skill category's real
  -- service code (macro_domain='EXECUTIVE_ASSISTANTS', already anticipated
  -- in cost_registry's own CHECK constraint since the original 17-table
  -- design). cost_rate_id/cost_model_id stay NULL on these rows -- EA uses
  -- cost_ea_rate, not the vehicle rate-card mechanism.
  IF p_service_code IS NULL THEN
    RAISE EXCEPTION 'fn_cost_ea_labor_calculate: p_service_code is required to resolve the governed cost_registry entry';
  END IF;

  SELECT * INTO v_registry FROM trustride.cost_registry
  WHERE macro_domain = 'EXECUTIVE_ASSISTANTS' AND service_code = p_service_code
    AND asset_class = 'EXECUTIVE_ASSISTANT_HUMAN' AND jurisdiction = p_jurisdiction AND status = 'ACTIVE';

  IF v_registry IS NULL THEN
    RAISE EXCEPTION 'fn_cost_ea_labor_calculate: no ACTIVE cost_registry for macro_domain=EXECUTIVE_ASSISTANTS, service_code=%, jurisdiction=%', p_service_code, p_jurisdiction;
  END IF;

  SELECT * INTO v_shift FROM trustride.cost_ea_shift_multiplier WHERE shift_type = p_shift_type AND active = TRUE;
  IF v_shift IS NULL THEN
    RAISE EXCEPTION 'fn_cost_ea_labor_calculate: no ACTIVE cost_ea_shift_multiplier for shift_type=%', p_shift_type;
  END IF;

  SELECT * INTO v_zone FROM trustride.cost_operational_zones WHERE zone_code = p_service_zone_code AND active = TRUE;
  IF v_zone IS NULL THEN
    RAISE EXCEPTION 'fn_cost_ea_labor_calculate: unknown or inactive service_zone_code %', p_service_zone_code;
  END IF;

  -- Minimum Engagement Block: enforced regardless of what was actually billed.
  v_billed_hours_effective := GREATEST(p_billed_hours, v_ea_rate.minimum_engagement_hours);

  -- Client_Hourly_Rate = (Statutory_Monthly_Min / 208 hrs) * (1 + On_Cost_Pct) * (1 + Platform_Margin_Pct)
  -- Platform_Margin_Pct is already folded in here, per the Founder's own
  -- formula -- no separate overhead step follows, unlike Paradigm A.
  v_client_hourly_rate := (v_ea_rate.statutory_monthly_min_kes / 208.0) * (1 + v_ea_rate.on_cost_pct / 100.0) * (1 + v_ea_rate.platform_margin_pct / 100.0);

  v_labor_cost := v_billed_hours_effective * v_client_hourly_rate * v_shift.multiplier;
  v_queue_wait_cost := p_queue_wait_min * v_ea_rate.queue_wait_rate_kes_per_min;

  v_pre_floor_fare := v_labor_cost + v_queue_wait_cost + p_transit_delivery_fee_kes;
  v_total_expected_cost := GREATEST(v_pre_floor_fare, v_ea_rate.floor_price_kes);
  v_floor_adjustment := v_total_expected_cost - v_pre_floor_fare;

  -- Reuses the SAME canonical fare_calculation record every vehicle
  -- calculation produces -- fn_cost_fare_quote_issue and the entire quote
  -- lifecycle work unchanged for this path, since both are asset-class-
  -- agnostic by design. Columns are populated for their most honest
  -- analog (waiting=queue-wait, time_rate=hourly rate per minute,
  -- base_dispatch_fee=transit/delivery fee, overhead_pct=platform margin,
  -- return_multiplier=shift multiplier) -- full clarity on what each term
  -- really means lives in fare_calculation_line, not in a forced re-use of
  -- the vehicle equation's own internal arithmetic.
  INSERT INTO trustride.fare_calculation (
    registry_id, order_id, assignment_id, requester_user_id, requester_user_type, asset_class, engine_capacity, jurisdiction,
    origin_zone_id, destination_zone_id, distance_km, duration_min, waiting_min, base_dispatch_fee_kes, direct_per_km_rate_kes,
    time_rate_kes_per_min, waiting_rate_kes_per_min, return_multiplier_applied, route_factor_applied, empty_return_probability_applied,
    regional_factor_applied, resource_cost_factor_applied, operational_risk_factor_applied, overhead_pct_applied, statutory_fee_applied,
    minimum_fare_floor_kes, pre_floor_fare_kes, total_expected_cost_kes, computed_total_fare_kes, model_version, correlation_id
  ) VALUES (
    v_registry.registry_id, p_order_id, p_assignment_id, p_requester_user_id, 'CUSTOMER', 'EXECUTIVE_ASSISTANT_HUMAN', 'NOT_APPLICABLE', p_jurisdiction,
    v_zone.zone_id, v_zone.zone_id, 0, v_billed_hours_effective * 60, p_queue_wait_min, p_transit_delivery_fee_kes, 0,
    v_client_hourly_rate / 60.0, v_ea_rate.queue_wait_rate_kes_per_min, v_shift.multiplier, 1.00, 0,
    1.00, 1.00, 1.00, v_ea_rate.platform_margin_pct, 0,
    v_ea_rate.floor_price_kes, v_pre_floor_fare, v_total_expected_cost, v_total_expected_cost, 'EA-LABOR-1.0.0', p_correlation_id
  ) RETURNING calculation_id INTO v_calculation_id;

  INSERT INTO trustride.fare_calculation_line (calculation_id, component_code, raw_input_value, rate_applied, multiplier_applied, line_amount_kes, sequence_no) VALUES
    (v_calculation_id, 'EA_TRANSIT_DELIVERY_FEE', NULL, NULL, 1.00, p_transit_delivery_fee_kes, 1),
    (v_calculation_id, 'EA_HOURLY_LABOR_COST', v_billed_hours_effective, v_client_hourly_rate, v_shift.multiplier, v_labor_cost, 2),
    (v_calculation_id, 'EA_QUEUE_WAIT_COST', p_queue_wait_min, v_ea_rate.queue_wait_rate_kes_per_min, 1.00, v_queue_wait_cost, 3),
    (v_calculation_id, 'EA_FLOOR_ADJUSTMENT', NULL, NULL, 1.00, v_floor_adjustment, 4);

  INSERT INTO trustride.cost_record (calculation_id, registry_id, execution_outcome, input_snapshot, output_snapshot, engine_version, duration_ms, correlation_id)
  VALUES (v_calculation_id, v_registry.registry_id, 'CALCULATED',
    jsonb_build_object('ea_skill_category', p_ea_skill_category, 'billed_hours', p_billed_hours, 'shift_type', p_shift_type),
    jsonb_build_object('computed_total_fare_kes', v_total_expected_cost, 'client_hourly_rate', v_client_hourly_rate),
    '2.1.0', extract(milliseconds FROM clock_timestamp() - v_start_time)::int, p_correlation_id);

  RETURN v_calculation_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_cost_ea_labor_calculate IS
  'Paradigm B: Total EA Cost = MAX((Billed_Hours * Client_Hourly_Rate * Shift_Multiplier) + Queue_Wait_Cost + Transit_Delivery_Fee, Floor_Price), Client_Hourly_Rate grounded in Kenyan gazetted municipal minimum wage + statutory on-costs + platform margin. Produces the same canonical fare_calculation/fare_quote the vehicle path produces -- the entire quote lifecycle works unchanged.';

-- ============================================================================
-- PHASE 5 -- fn_resource_assign gains a generic p_extra_context passthrough
-- (Engine 2, already live) so EA-specific dispatch context -- or any future
-- asset type's own fields -- can flow through RESOURCE_DISPATCH_INITIATED
-- without inventing new named parameters per asset type.
-- ============================================================================
DROP FUNCTION IF EXISTS trustride.fn_resource_assign(UUID, UUID, UUID, UUID, TEXT, TEXT, NUMERIC, NUMERIC, UUID, TEXT, TEXT, UUID);

CREATE FUNCTION trustride.fn_resource_assign(
  p_workforce_unit_id UUID, p_order_id UUID, p_correlation_id UUID, p_changed_by UUID,
  p_origin_zone_code TEXT DEFAULT NULL, p_destination_zone_code TEXT DEFAULT NULL,
  p_distance_km NUMERIC DEFAULT NULL, p_duration_min NUMERIC DEFAULT NULL,
  p_requester_user_id UUID DEFAULT NULL, p_jurisdiction TEXT DEFAULT NULL, p_engine_capacity TEXT DEFAULT NULL,
  p_order_line_id UUID DEFAULT NULL, p_extra_context JSONB DEFAULT '{}'::jsonb
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

  INSERT INTO trustride.resource_availability_ledger (resource_type, resource_ref_id, availability_state, reason_code, job_ref_id, order_line_id, changed_by)
  VALUES ('WORKFORCE_UNIT', p_workforce_unit_id, 'ASSIGNED', 'ORDER_ASSIGNMENT_CONFIRMED', p_order_id, p_order_line_id, p_changed_by)
  RETURNING availability_id INTO v_availability_id;

  INSERT INTO trustride.resource_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG004_BUS', 'RESOURCE_ASSIGNED',
    jsonb_build_object('order_id', p_order_id, 'order_line_id', p_order_line_id, 'workforce_unit_id', p_workforce_unit_id, 'capacity_class', v_capacity_class, 'engine_capacity', v_capacity_class, 'thing_id', v_thing_id),
    'RESOURCE_ASSIGNED:' || p_order_id::text || ':' || p_workforce_unit_id::text);

  INSERT INTO trustride.resource_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG005_COST', 'RESOURCE_DISPATCH_INITIATED',
    (jsonb_build_object('asset_class', v_capacity_class, 'engine_capacity', p_engine_capacity, 'order_id', p_order_id, 'order_line_id', p_order_line_id, 'assignment_id', v_availability_id,
      'origin_zone_code', p_origin_zone_code, 'destination_zone_code', p_destination_zone_code, 'distance_km', p_distance_km,
      'duration_min', p_duration_min, 'requester_user_id', p_requester_user_id, 'jurisdiction', p_jurisdiction) || coalesce(p_extra_context, '{}'::jsonb)),
    'RESOURCE_DISPATCH_INITIATED:' || p_order_id::text || ':' || p_workforce_unit_id::text);

  RETURN v_availability_id;
END;
$$;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_assign(UUID, UUID, UUID, UUID, TEXT, TEXT, NUMERIC, NUMERIC, UUID, TEXT, TEXT, UUID, JSONB) TO trs026_eng002_resc_service;
COMMENT ON FUNCTION trustride.fn_resource_assign(UUID, UUID, UUID, UUID, TEXT, TEXT, NUMERIC, NUMERIC, UUID, TEXT, TEXT, UUID, JSONB) IS
  'Hardening (2026-08-24): gains p_extra_context, a generic JSONB merged into RESOURCE_DISPATCH_INITIATED''s payload -- lets EA-specific dispatch fields (or any future asset type''s own fields) flow through without a new named parameter per asset type.';

-- ============================================================================
-- PHASE 6 -- fn_cost_resource_dispatch_initiated_accept branches by
-- asset_class: EXECUTIVE_ASSISTANT_HUMAN routes to the new labor equation,
-- every other class keeps using the untouched, universal vehicle equation.
-- ============================================================================
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
  v_asset_class trustride.cost_asset_class_enum;
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

  v_asset_class := (v_payload->>'asset_class')::trustride.cost_asset_class_enum;

  BEGIN
    IF v_asset_class = 'EXECUTIVE_ASSISTANT_HUMAN' THEN
      v_calculation_id := trustride.fn_cost_ea_labor_calculate(
        (v_payload->>'ea_skill_category')::trustride.ea_skill_category_enum,
        coalesce((v_payload->>'jurisdiction')::trustride.cost_jurisdiction_enum, 'KISUMU_COUNTY'),
        coalesce(v_payload->>'destination_zone_code', v_payload->>'origin_zone_code'),
        coalesce((v_payload->>'billed_hours')::numeric, 1),
        coalesce((v_payload->>'shift_type')::trustride.cost_shift_type_enum, 'DAY'),
        coalesce((v_payload->>'queue_wait_min')::numeric, 0),
        coalesce((v_payload->>'transit_delivery_fee_kes')::numeric, 0),
        coalesce((v_payload->>'requester_user_id')::uuid, '00000000-0000-0000-0000-000000000000'::uuid),
        v_correlation_id, (v_payload->>'order_id')::uuid, (v_payload->>'assignment_id')::uuid, v_context.service_code
      );
    ELSE
      v_calculation_id := trustride.fn_cost_fare_calculate(
        v_context.macro_domain, v_context.service_code, v_asset_class,
        coalesce((v_payload->>'engine_capacity')::trustride.cost_engine_capacity_enum, 'NOT_APPLICABLE'),
        coalesce((v_payload->>'jurisdiction')::trustride.cost_jurisdiction_enum, 'KISUMU_COUNTY'),
        v_payload->>'origin_zone_code', v_payload->>'destination_zone_code',
        coalesce((v_payload->>'distance_km')::numeric, 0), coalesce((v_payload->>'duration_min')::numeric, 0),
        coalesce((v_payload->>'requester_user_id')::uuid, '00000000-0000-0000-0000-000000000000'::uuid), 'CUSTOMER',
        v_correlation_id, (v_payload->>'order_id')::uuid, (v_payload->>'assignment_id')::uuid, NULL, 0, NULL
      );
    END IF;
    v_quote_id := trustride.fn_cost_fare_quote_issue(v_calculation_id);

    -- Auto-lock (hardening 2026-08-24) -- stand-in for a real requester
    -- decision until Engine 11 exists, same reasoning for both paradigms.
    PERFORM trustride.fn_cost_quote_lock(v_quote_id, v_correlation_id);
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
  'The real trigger for cost calculation, both paradigms. asset_class = EXECUTIVE_ASSISTANT_HUMAN routes to the hourly labor equation (fields read from p_extra_context, threaded through by fn_resource_assign); every other class keeps the universal vehicle equation, auto-locking the resulting quote in both cases (stand-in until Engine 11 exists).';

-- ============================================================================
-- PHASE 7 -- SEED DATA: every vehicle class gets a real rate card; the
-- zone return-multiplier correction; the EA rate card for all 6 skill
-- categories; the shift multiplier table.
-- ============================================================================

-- --- Correction: return_trip_factor's governed values, per the Founder's
-- own now-explicit authoritative figures (the prior seed had Kondele, a
-- true OUTSKIRT_DEADZONE, at 1.30 -- corrected to 1.70). ---
UPDATE trustride.return_trip_factor SET return_multiplier = 1.70
WHERE zone_id = (SELECT zone_id FROM trustride.cost_operational_zones WHERE zone_code = 'KSM-KONDELE-03') AND active = TRUE;

-- A real SUBURB-density example, completing the three-tier density model
-- (HIGH_DENSITY=1.0 already correct on KSM-CBD-01; OUTSKIRT_DEADZONE=1.7
-- just corrected above).
INSERT INTO trustride.cost_operational_zones (zone_code, zone_name, jurisdiction, density_class, boundary) VALUES
  ('KSM-MILIMANI-02', 'Milimani', 'KISUMU_COUNTY', 'SUBURB',
    ST_SetSRID(ST_GeomFromText('POLYGON((34.745 -0.108, 34.760 -0.108, 34.760 -0.095, 34.745 -0.095, 34.745 -0.108))'), 4326));

INSERT INTO trustride.return_trip_factor (zone_id, return_multiplier)
SELECT zone_id, 1.30 FROM trustride.cost_operational_zones WHERE zone_code = 'KSM-MILIMANI-02';

-- --- Vehicle rate cards: TUKTUK (3-wheeler), SEDAN (4-wheeler saloon),
-- PICKUP_TOWN (4-wheeler pickup), VAN_CARGO (4-wheeler van), TRUCK_LIGHT
-- (6-wheeler) -- BODA_BODA already seeded and untouched. Governed baseline
-- estimates, same discipline as the original BODA_BODA seed: adjustable by
-- ops, not fabricated as verified fact. Base fees and TRUCK_LIGHT's floor
-- match the Founder's own directive exactly (KES 120/150/350 base,
-- KES 450 truck floor); fuel/maintenance/per-km/time figures are governed
-- estimates scaled to real-world Kenyan vehicle-class operating economics.
-- ============================================================================
INSERT INTO trustride.cost_rate (
  asset_class, engine_capacity, base_dispatch_fee_kes, fuel_consumption_km_per_l,
  maintenance_rate_kes_per_km, direct_per_km_rate_kes, time_rate_kes_per_min, waiting_rate_kes_per_min, minimum_fare_floor_kes
) VALUES
  ('TUKTUK', 'CC_200', 120.00, 20.00, 4.50, 18.00, 3.00, 1.20, 150.00),
  ('SEDAN', 'CC_1500_SALOON', 150.00, 12.00, 6.00, 28.00, 4.00, 1.50, 250.00),
  ('PICKUP_TOWN', 'TON_1_0', 200.00, 9.00, 8.00, 35.00, 4.50, 1.80, 300.00),
  ('VAN_CARGO', 'TON_3_0', 250.00, 8.00, 10.00, 42.00, 5.00, 2.00, 380.00),
  ('TRUCK_LIGHT', 'TON_7_0', 350.00, 6.00, 15.00, 55.00, 6.00, 2.50, 450.00);

-- --- cost_model rows per new asset class (the equation is universal;
-- each asset class still gets its own governed model_version row, matching
-- the established one-row-per-asset_class convention). ---
INSERT INTO trustride.cost_model (model_version, asset_class, equation_definition, status) VALUES
  ('TRS026-COST-2.1.0', 'TUKTUK', '{"terms":["F_base","D*R_d*K_return*M_resource","T*R_t","W*R_w","D*R_d*K_return*P_empty_return"],"multiplier":"M_route*M_regional*M_risk","floor":"F_min","overhead":"S_overhead","statutory":"S_governance"}', 'ACTIVE'),
  ('TRS026-COST-2.1.0', 'SEDAN', '{"terms":["F_base","D*R_d*K_return*M_resource","T*R_t","W*R_w","D*R_d*K_return*P_empty_return"],"multiplier":"M_route*M_regional*M_risk","floor":"F_min","overhead":"S_overhead","statutory":"S_governance"}', 'ACTIVE'),
  ('TRS026-COST-2.1.0', 'PICKUP_TOWN', '{"terms":["F_base","D*R_d*K_return*M_resource","T*R_t","W*R_w","D*R_d*K_return*P_empty_return"],"multiplier":"M_route*M_regional*M_risk","floor":"F_min","overhead":"S_overhead","statutory":"S_governance"}', 'ACTIVE'),
  ('TRS026-COST-2.1.0', 'VAN_CARGO', '{"terms":["F_base","D*R_d*K_return*M_resource","T*R_t","W*R_w","D*R_d*K_return*P_empty_return"],"multiplier":"M_route*M_regional*M_risk","floor":"F_min","overhead":"S_overhead","statutory":"S_governance"}', 'ACTIVE'),
  ('TRS026-COST-2.1.0', 'TRUCK_LIGHT', '{"terms":["F_base","D*R_d*K_return*M_resource","T*R_t","W*R_w","D*R_d*K_return*P_empty_return"],"multiplier":"M_route*M_regional*M_risk","floor":"F_min","overhead":"S_overhead","statutory":"S_governance"}', 'ACTIVE');

-- --- cost_registry: real service codes, from Services' own live catalogue
-- (not invented) -- one clean mapping per new vehicle class, giving all
-- six vehicle classes complete, dispatchable coverage. ---
INSERT INTO trustride.cost_registry (registry_code, macro_domain, service_code, asset_class, jurisdiction, cost_rate_id, cost_model_id, overhead_pct, minimum_margin_pct)
SELECT 'TRANSPORT-TUKTUK-KISUMU', 'TRANSPORT', 'TRANSPORT-TUKTUK-STANDARD', 'TUKTUK', 'KISUMU_COUNTY', rt.rate_id, m.model_id, 2.00, 8.00
FROM trustride.cost_rate rt, trustride.cost_model m
WHERE rt.asset_class = 'TUKTUK' AND rt.active = TRUE AND m.asset_class = 'TUKTUK' AND m.model_version = 'TRS026-COST-2.1.0';

INSERT INTO trustride.cost_registry (registry_code, macro_domain, service_code, asset_class, jurisdiction, cost_rate_id, cost_model_id, overhead_pct, minimum_margin_pct)
SELECT 'TRANSPORT-SEDAN-KISUMU', 'TRANSPORT', 'TRANSPORT-SEDAN-STANDARD', 'SEDAN', 'KISUMU_COUNTY', rt.rate_id, m.model_id, 2.00, 8.00
FROM trustride.cost_rate rt, trustride.cost_model m
WHERE rt.asset_class = 'SEDAN' AND rt.active = TRUE AND m.asset_class = 'SEDAN' AND m.model_version = 'TRS026-COST-2.1.0';

INSERT INTO trustride.cost_registry (registry_code, macro_domain, service_code, asset_class, jurisdiction, cost_rate_id, cost_model_id, overhead_pct, minimum_margin_pct)
SELECT 'DELIVERY-PICKUP-KISUMU', 'DELIVERY', 'DELIVERY-GOODS-TOWN', 'PICKUP_TOWN', 'KISUMU_COUNTY', rt.rate_id, m.model_id, 2.00, 8.00
FROM trustride.cost_rate rt, trustride.cost_model m
WHERE rt.asset_class = 'PICKUP_TOWN' AND rt.active = TRUE AND m.asset_class = 'PICKUP_TOWN' AND m.model_version = 'TRS026-COST-2.1.0';

INSERT INTO trustride.cost_registry (registry_code, macro_domain, service_code, asset_class, jurisdiction, cost_rate_id, cost_model_id, overhead_pct, minimum_margin_pct)
SELECT 'COURIER-VAN-KISUMU', 'COURIER', 'COURIER-PARCEL', 'VAN_CARGO', 'KISUMU_COUNTY', rt.rate_id, m.model_id, 2.00, 8.00
FROM trustride.cost_rate rt, trustride.cost_model m
WHERE rt.asset_class = 'VAN_CARGO' AND rt.active = TRUE AND m.asset_class = 'VAN_CARGO' AND m.model_version = 'TRS026-COST-2.1.0';

INSERT INTO trustride.cost_registry (registry_code, macro_domain, service_code, asset_class, jurisdiction, cost_rate_id, cost_model_id, overhead_pct, minimum_margin_pct)
SELECT 'DELIVERY-TRUCK-KISUMU', 'DELIVERY', 'DELIVERY-CARGO-BULK', 'TRUCK_LIGHT', 'KISUMU_COUNTY', rt.rate_id, m.model_id, 2.00, 8.00
FROM trustride.cost_rate rt, trustride.cost_model m
WHERE rt.asset_class = 'TRUCK_LIGHT' AND rt.active = TRUE AND m.asset_class = 'TRUCK_LIGHT' AND m.model_version = 'TRS026-COST-2.1.0';

-- --- cost_ea_rate: all 6 skill categories, KISUMU_COUNTY. Statutory_
-- Monthly_Min for PERSONAL_SHOPPER_ERRAND/HOUSE_MANAGER_DOMESTIC uses the
-- Founder's own supplied figure (KES 15,200, matching Kenya's real
-- gazetted general minimum wage order for urban municipalities); the other
-- four use clearly-labeled governed estimates for skilled cadres, pending
-- real Ministry of Labour gazette confirmation. ---
INSERT INTO trustride.cost_ea_rate (ea_skill_category, jurisdiction, statutory_monthly_min_kes, on_cost_pct, platform_margin_pct, queue_wait_rate_kes_per_min, minimum_engagement_hours, floor_price_kes, data_source) VALUES
  ('PERSONAL_SHOPPER_ERRAND', 'KISUMU_COUNTY', 15200.00, 22.00, 25.00, 2.00, 1.00, 300.00, 'FOUNDER_SUPPLIED_GAZETTE_FIGURE'),
  ('HOUSE_MANAGER_DOMESTIC', 'KISUMU_COUNTY', 15200.00, 22.00, 25.00, 2.00, 2.00, 500.00, 'FOUNDER_SUPPLIED_GAZETTE_FIGURE'),
  ('PROFESSIONAL_CHAUFFEUR', 'KISUMU_COUNTY', 18500.00, 22.00, 25.00, 2.00, 2.00, 600.00, 'GOVERNED_ESTIMATE'),
  ('CERTIFIED_CHEF', 'KISUMU_COUNTY', 21000.00, 22.00, 25.00, 2.00, 3.00, 900.00, 'GOVERNED_ESTIMATE'),
  ('PATIENT_ELDER_CAREGIVER', 'KISUMU_COUNTY', 17500.00, 22.00, 25.00, 2.00, 4.00, 1200.00, 'GOVERNED_ESTIMATE'),
  ('CORPORATE_REPRESENTATIVE', 'KISUMU_COUNTY', 25000.00, 22.00, 25.00, 2.00, 2.00, 800.00, 'GOVERNED_ESTIMATE');

INSERT INTO trustride.cost_ea_shift_multiplier (shift_type, multiplier) VALUES
  ('DAY', 1.00), ('NIGHT', 1.50), ('SUNDAY_HOLIDAY', 2.00);

-- --- cost_registry rows for EA, one per skill category, using its real,
-- already-seeded Services catalogue code (macro_domain='EXECUTIVE_
-- ASSISTANTS', already anticipated in cost_registry's own CHECK
-- constraint). cost_rate_id/cost_model_id stay NULL -- EA uses cost_ea_
-- rate, not the vehicle rate-card mechanism; overhead_pct/statutory_
-- fee_kes stay at their 0 default since the Founder's own EA formula
-- already folds platform margin into Client_Hourly_Rate directly. ---
INSERT INTO trustride.cost_registry (registry_code, macro_domain, service_code, asset_class, jurisdiction, overhead_pct, minimum_margin_pct) VALUES
  ('EA-SHOPPER-KISUMU', 'EXECUTIVE_ASSISTANTS', 'EA-SHOPPING-GENERAL', 'EXECUTIVE_ASSISTANT_HUMAN', 'KISUMU_COUNTY', 0, 0),
  ('EA-HOUSEMANAGER-KISUMU', 'EXECUTIVE_ASSISTANTS', 'EA-CLEANING-GENERAL', 'EXECUTIVE_ASSISTANT_HUMAN', 'KISUMU_COUNTY', 0, 0),
  ('EA-CHAUFFEUR-KISUMU', 'EXECUTIVE_ASSISTANTS', 'EA-DRIVING-GENERAL', 'EXECUTIVE_ASSISTANT_HUMAN', 'KISUMU_COUNTY', 0, 0),
  ('EA-CHEF-KISUMU', 'EXECUTIVE_ASSISTANTS', 'EA-CHEF-GENERAL', 'EXECUTIVE_ASSISTANT_HUMAN', 'KISUMU_COUNTY', 0, 0),
  ('EA-CAREGIVER-KISUMU', 'EXECUTIVE_ASSISTANTS', 'EA-CAREGIVING-GENERAL', 'EXECUTIVE_ASSISTANT_HUMAN', 'KISUMU_COUNTY', 0, 0),
  ('EA-CORPREP-KISUMU', 'EXECUTIVE_ASSISTANTS', 'EA-SHOPPING-REPRESENTATION_DELIVERY', 'EXECUTIVE_ASSISTANT_HUMAN', 'KISUMU_COUNTY', 0, 0);

-- ============================================================================
-- PHASE 8 -- ROW LEVEL SECURITY (new tables only)
-- ============================================================================
ALTER TABLE trustride.cost_ea_rate ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_ea_rate_platform_read ON trustride.cost_ea_rate FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_ea_rate_service_write ON trustride.cost_ea_rate FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.cost_ea_shift_multiplier ENABLE ROW LEVEL SECURITY;
CREATE POLICY cost_ea_shift_multiplier_platform_read ON trustride.cost_ea_shift_multiplier FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY cost_ea_shift_multiplier_service_write ON trustride.cost_ea_shift_multiplier FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);

-- ============================================================================
-- PHASE 9 -- INDEXES
-- ============================================================================
CREATE INDEX idx_cost_ea_rate_lookup ON trustride.cost_ea_rate (ea_skill_category, jurisdiction) WHERE active = TRUE;

-- ============================================================================
-- PHASE 10 -- PRIVILEGE LOCKDOWN
-- ============================================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON trustride.cost_ea_rate, trustride.cost_ea_shift_multiplier TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_ea_labor_calculate(trustride.ea_skill_category_enum, trustride.cost_jurisdiction_enum, TEXT, NUMERIC, trustride.cost_shift_type_enum, NUMERIC, NUMERIC, UUID, UUID, UUID, UUID, TEXT) TO trs026_eng005_cost_service;

-- ============================================================================
-- PHASE 11 -- VALIDATION
-- ============================================================================
DO $$
DECLARE
  v_vehicle_rate_count INTEGER;
  v_ea_rate_count INTEGER;
  v_registry_count INTEGER;
BEGIN
  SELECT count(DISTINCT asset_class) INTO v_vehicle_rate_count FROM trustride.cost_rate WHERE active = TRUE AND asset_class <> 'EXECUTIVE_ASSISTANT_HUMAN';
  IF v_vehicle_rate_count <> 6 THEN
    RAISE EXCEPTION 'Engine 5 universal asset matrix validation failed: expected 6 active vehicle-class cost_rate rows (all of resource_capacity_class_enum bar EXECUTIVE_ASSISTANT_HUMAN), found %', v_vehicle_rate_count;
  END IF;

  SELECT count(*) INTO v_ea_rate_count FROM trustride.cost_ea_rate WHERE active = TRUE;
  IF v_ea_rate_count <> 6 THEN
    RAISE EXCEPTION 'Engine 5 universal asset matrix validation failed: expected 6 active cost_ea_rate rows (one per ea_skill_category_enum value), found %', v_ea_rate_count;
  END IF;

  SELECT count(DISTINCT asset_class) INTO v_registry_count FROM trustride.cost_registry WHERE status = 'ACTIVE' AND asset_class <> 'EXECUTIVE_ASSISTANT_HUMAN';
  IF v_registry_count <> 6 THEN
    RAISE EXCEPTION 'Engine 5 universal asset matrix validation failed: expected 6 dispatchable vehicle classes with an ACTIVE cost_registry row, found %', v_registry_count;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'fn_cost_ea_labor_calculate') THEN
    RAISE EXCEPTION 'Engine 5 universal asset matrix validation failed: fn_cost_ea_labor_calculate missing';
  END IF;

  RAISE NOTICE 'Engine 5 universal asset matrix validation passed: 6/6 vehicle classes dispatchable, 6/6 EA skill categories rated, labor calculation function present.';
END
$$;

UPDATE trustride.engine_registry SET engine_version = '2.1.0' WHERE engine_code = 'TRS026_ENG005_COST';
