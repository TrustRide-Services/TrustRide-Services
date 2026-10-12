-- ============================================================================
-- Engines 4 and 5 -- live Executive Assistant quotes use the statutory method
-- Construction Directive WP3 (section 2.1, D24) -- Founder-authorized, targeted
-- ============================================================================
-- The Founder authorized full adoption of the statutory remuneration method
-- (fn_cost_ea_engagement_rate, EA-STATUTORY-1.0.0, migration 024) for live EA
-- quotations. Until now the live path priced EAs with the established
-- EA-LABOR-1.0.0 equation (monthly minimum / 208, 2023 figures), which can price
-- below the gazetted minimum wage.
--
-- What changes (and nothing else in Engine 5):
--   Engine 4  fn_business_service_order_place -- an EA line records how it is
--             booked (HOURS, or DAYS 1-6 with hours per day) and when it starts,
--             so the method sees the real engagement; limits refused at the order.
--             fn_business_resource_reserved_accept -- each priced line also
--             carries its full scope_detail (additive key; transport ignores it).
--   Engine 5  fn_cost_ea_statutory_calculate (new) -- rates one EA line with the
--             statutory method and records the result in the canonical
--             fare_calculation (model_version EA-STATUTORY-1.0.0) with one
--             calculation line per cited price line, so quote, payment and
--             settlement are unchanged in shape.
--             fn_cost_resource_dispatch_initiated_accept -- its EA branch calls
--             the new function instead of fn_cost_ea_labor_calculate. The
--             transport branch is byte-for-byte unchanged.
--             fn_cost_ea_quote_statutory_guard (new) + triggers on fare_quote and
--             fare_quote_line -- an EA quote from any other equation is refused.
--             cost_ea_engagement_estimate.calculation_id (new column) -- links the
--             estimate to the calculation it priced.
--             cost_ea_rating_rule WORKER_ENGAGEMENT_BASIS -> IN_FORCE: human
--             Operators are employees under the approved model (directive 4.2),
--             which is the CASUAL_EMPLOYEE basis already configured.
--
-- Legal gate (directive 2.1): a trade whose gazetted occupation is still
-- NEAREST_OCCUPATION_PENDING_FOUNDER (patient/elder caregiver; corporate
-- representative) is NOT quoted. Its order fails with the reason through the
-- existing FARE_CALCULATION_FAILED path (worker released, customer told) until
-- the occupation is determined.
-- fn_cost_ea_labor_calculate remains in place, unchanged and no longer called.
-- ============================================================================

UPDATE trustride.cost_ea_rating_rule
SET status = 'IN_FORCE',
    description = description || ' Confirmed 2026-10-12: human Operators are employees under the approved model (Construction Directive 4.2).'
WHERE rule_code = 'WORKER_ENGAGEMENT_BASIS' AND value_text = 'CASUAL_EMPLOYEE' AND status = 'PENDING_FOUNDER_CONFIRMATION';

ALTER TABLE trustride.cost_ea_engagement_estimate ADD COLUMN calculation_id UUID REFERENCES trustride.fare_calculation (calculation_id);
CREATE INDEX idx_cost_ea_engagement_estimate_calculation ON trustride.cost_ea_engagement_estimate (calculation_id);

CREATE FUNCTION trustride.fn_cost_ea_statutory_calculate(p_ea_skill_category trustride.ea_skill_category_enum, p_jurisdiction trustride.cost_jurisdiction_enum,
  p_service_zone_code text, p_line jsonb, p_requester_user_id uuid, p_correlation_id uuid, p_order_id uuid, p_assignment_id uuid, p_service_code text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_start_time TIMESTAMPTZ := clock_timestamp();
  v_trade RECORD; v_rule RECORD; v_rate RECORD; v_registry RECORD; v_zone RECORD; e RECORD;
  v_scope JSONB; v_stat JSONB; v_est UUID; v_calc UUID; v_hours NUMERIC;
BEGIN
  SELECT * INTO v_trade FROM trustride.cost_ea_trade_occupation WHERE ea_skill_category = p_ea_skill_category;
  IF v_trade IS NULL OR v_trade.mapping_status <> 'GAZETTED_OCCUPATION' THEN
    RAISE EXCEPTION 'EA_RATING_AWAITING_DETERMINATION: % has no gazetted occupation in the Regulation of Wages Order (nearest: %); TrustRide does not quote it until the occupation is determined',
      p_ea_skill_category, coalesce(v_trade.occupation_mapping, 'none');
  END IF;
  SELECT * INTO v_rule FROM trustride.cost_ea_rating_rule WHERE rule_code = 'WORKER_ENGAGEMENT_BASIS';
  IF v_rule IS NULL OR v_rule.status <> 'IN_FORCE' THEN
    RAISE EXCEPTION 'EA_RATING_AWAITING_DETERMINATION: the worker engagement basis is not confirmed';
  END IF;

  -- The customer's scope for this line: the full scope_detail when Business sent it.
  v_scope := coalesce(p_line->'scope_detail', p_line);
  IF upper(coalesce(v_scope->>'line_type', 'LABOUR')) = 'LABOUR' THEN
    v_stat := jsonb_strip_nulls(jsonb_build_object('line_type', 'LABOUR',
      'engagement_unit', upper(coalesce(nullif(v_scope->>'engagement_unit', ''), 'HOURS')),
      'billed_hours', coalesce(v_scope->>'billed_hours', p_line->>'billed_hours'),
      'billed_days', v_scope->>'billed_days', 'start_at', v_scope->>'start_at', 'service_dates', v_scope->'service_dates'));
  ELSE
    v_stat := v_scope;
  END IF;

  v_est := trustride.fn_cost_ea_engagement_rate(p_ea_skill_category, p_service_code, p_service_zone_code, jsonb_build_array(v_stat),
    p_requester_user_id, p_correlation_id, p_order_id);
  SELECT * INTO e FROM trustride.cost_ea_engagement_estimate WHERE estimate_id = v_est;

  SELECT * INTO v_rate FROM trustride.cost_ea_rate WHERE ea_skill_category = p_ea_skill_category AND jurisdiction = e.jurisdiction AND active;
  SELECT * INTO v_registry FROM trustride.cost_registry WHERE macro_domain = 'EXECUTIVE_ASSISTANTS' AND service_code = p_service_code
    AND asset_class = 'EXECUTIVE_ASSISTANT_HUMAN' AND jurisdiction = e.jurisdiction AND status = 'ACTIVE';
  SELECT * INTO v_zone FROM trustride.cost_operational_zones WHERE zone_id = e.zone_id;
  SELECT coalesce(sum(quantity) FILTER (WHERE unit = 'HOURS' AND component_code LIKE 'EA_WORKER_PAY_%'), 0)
       + coalesce(sum(quantity) FILTER (WHERE unit = 'DAYS' AND component_code LIKE 'EA_WORKER_PAY_%'), 0) * 8
  INTO v_hours FROM trustride.cost_ea_engagement_line WHERE estimate_id = v_est AND line_role = 'PRICE';

  -- The canonical calculation record, as every pricing path writes it; the
  -- statutory estimate and its cited lines are the explanation.
  INSERT INTO trustride.fare_calculation (
    registry_id, order_id, assignment_id, requester_user_id, requester_user_type, asset_class, engine_capacity, jurisdiction,
    origin_zone_id, destination_zone_id, distance_km, duration_min, waiting_min, base_dispatch_fee_kes, direct_per_km_rate_kes,
    time_rate_kes_per_min, waiting_rate_kes_per_min, return_multiplier_applied, route_factor_applied, empty_return_probability_applied,
    regional_factor_applied, resource_cost_factor_applied, operational_risk_factor_applied, overhead_pct_applied, statutory_fee_applied,
    minimum_fare_floor_kes, pre_floor_fare_kes, total_expected_cost_kes, computed_total_fare_kes, model_version, correlation_id
  ) VALUES (
    v_registry.registry_id, p_order_id, p_assignment_id, p_requester_user_id, 'CUSTOMER', 'EXECUTIVE_ASSISTANT_HUMAN', 'NOT_APPLICABLE', e.jurisdiction,
    v_zone.zone_id, v_zone.zone_id, 0, v_hours * 60, 0, 0, 0,
    0, 0, 1.00, 1.00, 0,
    1.00, 1.00, 1.00, v_rate.platform_margin_pct, e.employer_contributions_kes,
    v_rate.floor_price_kes, e.total_kes - e.floor_adjustment_kes, e.total_kes, e.total_kes, e.method_version, p_correlation_id
  ) RETURNING calculation_id INTO v_calc;

  INSERT INTO trustride.fare_calculation_line (calculation_id, component_code, raw_input_value, rate_applied, multiplier_applied, line_amount_kes, sequence_no)
  SELECT v_calc, l.component_code, l.quantity, l.rate_kes, l.multiplier, l.amount_kes, row_number() OVER (ORDER BY l.sequence_no)
  FROM trustride.cost_ea_engagement_line l WHERE l.estimate_id = v_est AND l.line_role = 'PRICE';

  UPDATE trustride.cost_ea_engagement_estimate SET calculation_id = v_calc WHERE estimate_id = v_est;

  INSERT INTO trustride.cost_record (calculation_id, registry_id, execution_outcome, input_snapshot, output_snapshot, engine_version, duration_ms, correlation_id)
  VALUES (v_calc, v_registry.registry_id, 'CALCULATED',
    jsonb_build_object('ea_skill_category', p_ea_skill_category, 'scope', v_stat, 'service_zone_code', p_service_zone_code),
    jsonb_build_object('computed_total_fare_kes', e.total_kes, 'estimate_id', v_est, 'method_version', e.method_version,
      'worker_pay_kes', e.worker_pay_kes, 'employer_contributions_kes', e.employer_contributions_kes, 'platform_margin_kes', e.platform_margin_kes),
    e.method_version, extract(milliseconds FROM clock_timestamp() - v_start_time)::int, p_correlation_id);
  RETURN v_calc;
END;
$function$;
COMMENT ON FUNCTION trustride.fn_cost_ea_statutory_calculate IS
  'Live EA pricing (D24): rates one EA order line with fn_cost_ea_engagement_rate (EA-STATUTORY-1.0.0) and records it in fare_calculation; refuses a trade whose gazetted occupation awaits determination.';

-- The EA branch of the established dispatch pricing now calls the statutory method.
DO $patch$
DECLARE
  v_def TEXT;
  v_old TEXT := E'        v_calc := trustride.fn_cost_ea_labor_calculate(\n'
    || E'          (v_payload->>''ea_skill_category'')::trustride.ea_skill_category_enum, v_jur,\n'
    || E'          coalesce(v_line->>''origin_zone_code'', v_payload->>''origin_zone_code''),\n'
    || E'          coalesce((v_line->>''billed_hours'')::numeric, (v_payload->>''billed_hours'')::numeric),\n'
    || E'          coalesce(v_line->>''shift_type'', v_payload->>''shift_type'')::trustride.cost_shift_type_enum,\n'
    || E'          coalesce((v_payload->>''queue_wait_min'')::numeric, 0), coalesce((v_payload->>''transit_delivery_fee_kes'')::numeric, 0),\n'
    || E'          (v_payload->>''requester_user_id'')::uuid, v_corr, (v_payload->>''order_id'')::uuid, (v_payload->>''assignment_id'')::uuid, v_service_code);\n';
  v_new TEXT := E'        -- D24 (Construction Directive 2.1): statutory remuneration method.\n'
    || E'        v_calc := trustride.fn_cost_ea_statutory_calculate(\n'
    || E'          (v_payload->>''ea_skill_category'')::trustride.ea_skill_category_enum, v_jur,\n'
    || E'          coalesce(v_line->>''origin_zone_code'', v_payload->>''origin_zone_code''),\n'
    || E'          v_line || jsonb_build_object(''billed_hours'', coalesce(v_line->>''billed_hours'', v_payload->>''billed_hours'')),\n'
    || E'          (v_payload->>''requester_user_id'')::uuid, v_corr, (v_payload->>''order_id'')::uuid, (v_payload->>''assignment_id'')::uuid, v_service_code);\n';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_cost_resource_dispatch_initiated_accept(uuid)'::regprocedure) INTO v_def;
  IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'EA pricing call not found in dispatch accept'; END IF;
  v_def := replace(v_def, v_old, v_new);
  EXECUTE v_def;
END;
$patch$;

-- No EA quote from any other equation.
CREATE FUNCTION trustride.fn_cost_ea_quote_statutory_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
BEGIN
  IF EXISTS (SELECT 1 FROM trustride.fare_calculation c WHERE c.calculation_id = NEW.calculation_id
             AND c.asset_class = 'EXECUTIVE_ASSISTANT_HUMAN' AND c.model_version IS DISTINCT FROM 'EA-STATUTORY-1.0.0') THEN
    RAISE EXCEPTION 'An Executive Assistant quote must come from the statutory method (EA-STATUTORY-1.0.0)';
  END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER trg_fare_quote_ea_statutory_only BEFORE INSERT ON trustride.fare_quote
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_cost_ea_quote_statutory_guard();
CREATE TRIGGER trg_fare_quote_line_ea_statutory_only BEFORE INSERT ON trustride.fare_quote_line
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_cost_ea_quote_statutory_guard();

-- Engine 4: an EA line records how it is booked and when it starts.
DO $patch$
DECLARE
  v_def TEXT;
  v_old TEXT := E'      v_hours := (v_scope->>''billed_hours'')::numeric;\n'
    || E'      IF v_hours IS NULL OR v_hours < 1 OR v_hours > 12 THEN\n'
    || E'        RAISE EXCEPTION ''Say how many hours you need (1 to 12)'';\n'
    || E'      END IF;\n'
    || E'      v_scope := v_scope || jsonb_build_object(''destination_zone_code'', v_scope->>''origin_zone_code'', ''billed_hours'', v_hours,\n'
    || E'        ''shift_type'', v_shift, ''ea_skill_category'', v_req->>''ea_skill_category'', ''jurisdiction'', v_jurisdiction);\n';
  v_new TEXT := E'      v_hours := (v_scope->>''billed_hours'')::numeric;\n'
    || E'      IF v_hours IS NULL OR v_hours < 1 OR v_hours > 12 THEN\n'
    || E'        RAISE EXCEPTION ''Say how many hours you need (1 to 12)'';\n'
    || E'      END IF;\n'
    || E'      -- D24: by the hour, or by the day (1-6 days, hours per day); priced from the real start.\n'
    || E'      IF upper(coalesce(nullif(v_scope->>''engagement_unit'', ''''), ''HOURS'')) NOT IN (''HOURS'', ''DAYS'') THEN\n'
    || E'        RAISE EXCEPTION ''Book an assistant by the hour or by the day'';\n'
    || E'      END IF;\n'
    || E'      IF upper(coalesce(nullif(v_scope->>''engagement_unit'', ''''), ''HOURS'')) = ''DAYS''\n'
    || E'         AND (coalesce((v_scope->>''billed_days'')::int, 0) < 1 OR (v_scope->>''billed_days'')::int > 6) THEN\n'
    || E'        RAISE EXCEPTION ''Book 1 to 6 days -- a rest day in every seven (Employment Act s.27(2))'';\n'
    || E'      END IF;\n'
    || E'      v_scope := v_scope || jsonb_build_object(''destination_zone_code'', v_scope->>''origin_zone_code'', ''billed_hours'', v_hours,\n'
    || E'        ''shift_type'', v_shift, ''ea_skill_category'', v_req->>''ea_skill_category'', ''jurisdiction'', v_jurisdiction,\n'
    || E'        ''engagement_unit'', upper(coalesce(nullif(v_scope->>''engagement_unit'', ''''), ''HOURS'')),\n'
    || E'        ''billed_days'', CASE WHEN upper(coalesce(v_scope->>''engagement_unit'', '''')) = ''DAYS'' THEN (v_scope->>''billed_days'')::int END,\n'
    || E'        ''start_at'', v_effective_start);\n';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p WHERE p.pronamespace = 'trustride'::regnamespace AND p.proname = 'fn_business_service_order_place';
  IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'EA scope block not found in order placement'; END IF;
  EXECUTE replace(v_def, v_old, v_new);

  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p WHERE p.pronamespace = 'trustride'::regnamespace AND p.proname = 'fn_business_resource_reserved_accept';
  v_old := E'''shift_type'', l.scope_detail->>''shift_type'') ORDER BY l.line_sequence)';
  IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'pricing lines builder not found'; END IF;
  EXECUTE replace(v_def, v_old, E'''shift_type'', l.scope_detail->>''shift_type'', ''scope_detail'', l.scope_detail) ORDER BY l.line_sequence)');
END;
$patch$;

GRANT EXECUTE ON FUNCTION trustride.fn_cost_ea_statutory_calculate(trustride.ea_skill_category_enum, trustride.cost_jurisdiction_enum, text, jsonb, uuid, uuid, uuid, uuid, text) TO trs026_eng005_cost_service;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
