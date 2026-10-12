-- Suite 37 -- Executive scenario comparison (Construction Directive 2.11, WP8). Executives (and the Founder) run
-- pricing scenarios with their inputs and compare two completed runs on one metric, through the Executive
-- Dashboard command gateway only. D26 is preserved: no signed-in direct call, no other role. Comparisons are
-- validated, audited and not duplicated; Engine 5 is read, never changed.
DO $$
DECLARE
  exec_ UUID; admin UUID; cust UUID; r JSONB; v TEXT; n INT; run_a UUID; run_b UUID; run_f UUID; cmp UUID; rate_before NUMERIC;
  params JSONB;
  ready BOOLEAN := to_regprocedure('trustride.fn_present_cmd_compare_scenarios(uuid,jsonb,uuid)') IS NOT NULL;
BEGIN
  exec_ := pg_temp.t_person('Scen Exec', NULL);  PERFORM pg_temp.t_role(exec_, 'EXECUTIVE');
  admin := pg_temp.t_person('Scen Admin', NULL);  PERFORM pg_temp.t_role(admin, 'ADMINISTRATOR');
  cust := pg_temp.t_customer('Scen Customer');
  SELECT rt.direct_per_km_rate_kes INTO rate_before FROM trustride.cost_registry reg JOIN trustride.cost_rate rt ON rt.rate_id = reg.cost_rate_id
  WHERE reg.service_code = 'TRANSPORT-BODA-STANDARD' AND reg.status = 'ACTIVE' LIMIT 1;

  -- ============ runs with inputs (the screen supplies them)
  FOR v IN SELECT unnest(ARRAY['11.00', '13.50']) LOOP
    params := (SELECT jsonb_agg(jsonb_build_object('parameter_name', k, 'parameter_value', val, 'parameter_source', 'SIMULATION_PARAMETER'))
               FROM (VALUES ('macro_domain', to_jsonb(reg.macro_domain)), ('service_code', to_jsonb(reg.service_code)), ('asset_class', to_jsonb(reg.asset_class::text)),
                            ('jurisdiction', to_jsonb(reg.jurisdiction::text)), ('direct_per_km_rate_kes', to_jsonb(v::numeric))) x(k, val))
      FROM trustride.cost_registry reg WHERE reg.service_code = 'TRANSPORT-BODA-STANDARD' AND reg.status = 'ACTIVE' LIMIT 1;
    r := pg_temp.t_cmd(exec_, 'TRUSTRIDE_OFFICE', 'EXECUTIVE_DASHBOARD', 'RUN_SCENARIO',
      jsonb_build_object('scenario_code', 'PRICING_CHANGE', 'run_label', 'boda at ' || v, 'parameters', params));
  END LOOP;
  PERFORM pg_temp.t_cycle(6);
  SELECT run_id INTO run_a FROM trustride.model_scenario_run WHERE run_label = 'boda at 11.00' ORDER BY created_at DESC LIMIT 1;
  SELECT run_id INTO run_b FROM trustride.model_scenario_run WHERE run_label = 'boda at 13.50' ORDER BY created_at DESC LIMIT 1;
  PERFORM pg_temp.t_check('scenario: pricing runs with their inputs complete',
    (SELECT count(*) FROM trustride.model_scenario_run WHERE run_id IN (run_a, run_b) AND run_status = 'COMPLETED') = 2);
  PERFORM pg_temp.t_check('scenario: running scenarios changes no Engine 5 rate',
    (SELECT rt.direct_per_km_rate_kes FROM trustride.cost_registry reg JOIN trustride.cost_rate rt ON rt.rate_id = reg.cost_rate_id
     WHERE reg.service_code = 'TRANSPORT-BODA-STANDARD' AND reg.status = 'ACTIVE' LIMIT 1) = rate_before);
  r := pg_temp.t_cmd(exec_, 'TRUSTRIDE_OFFICE', 'EXECUTIVE_DASHBOARD', 'RUN_SCENARIO', '{"scenario_code":"PEAK_DEMAND","run_label":"no grant"}');
  PERFORM pg_temp.t_cycle(4);
  SELECT run_id INTO run_f FROM trustride.model_scenario_run WHERE run_label = 'no grant' ORDER BY created_at DESC LIMIT 1;

  IF NOT ready THEN
    PERFORM pg_temp.t_check('scenario comparison command exists', false, 'fn_present_cmd_compare_scenarios absent');
  ELSE
  -- ============ comparison through the Executive Dashboard
  r := pg_temp.t_cmd(exec_, 'TRUSTRIDE_OFFICE', 'EXECUTIVE_DASHBOARD', 'COMPARE_SCENARIOS',
    jsonb_build_object('base_run_id', run_a, 'compared_run_id', run_b, 'comparison_metric', 'trailing_30d_revenue_kes'));
  cmp := (r->>'signal')::uuid;
  SELECT to_jsonb(c) INTO r FROM trustride.model_comparative_view c WHERE comparative_view_id = cmp;
  PERFORM pg_temp.t_check('scenario: an Executive compares two completed runs and the difference is stored',
    r->>'base_run_id' = run_a::text AND (r->>'delta')::numeric = (r->>'compared_value')::numeric - (r->>'base_value')::numeric, coalesce(r::text, 'none'));
  PERFORM pg_temp.t_check('scenario: the comparison is audited with who made it',
    EXISTS (SELECT 1 FROM trustride.audit_log WHERE entity_id = cmp AND action = 'SCENARIO_COMPARED' AND actor_id = exec_));
  r := pg_temp.t_cmd(exec_, 'TRUSTRIDE_OFFICE', 'EXECUTIVE_DASHBOARD', 'COMPARE_SCENARIOS',
    jsonb_build_object('base_run_id', run_a, 'compared_run_id', run_b, 'comparison_metric', 'trailing_30d_revenue_kes'));
  SELECT count(*) INTO n FROM trustride.model_comparative_view WHERE base_run_id = run_a AND compared_run_id = run_b;
  PERFORM pg_temp.t_check('scenario: repeating the same comparison returns it, it is not stored twice', n = 1 AND (r->>'signal')::uuid = cmp, n::text);
  r := (SELECT trustride.fn_present_proj_exec_scenarios(NULL, '{}'));
  PERFORM pg_temp.t_check('scenario: the dashboard lists the comparison and the pricing inputs it can offer',
    jsonb_array_length(r->'comparisons') >= 1 AND jsonb_array_length(r->'pricing_inputs') >= 1
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(r->'runs') x WHERE x->>'run_id' = run_a::text AND x->'metrics' ? 'trailing_30d_revenue_kes'), left(r::text, 200));

  -- ============ validation
  FOR v IN SELECT unnest(ARRAY[
      format('{"base_run_id":"%s","compared_run_id":"%s","comparison_metric":"trailing_30d_revenue_kes"}', run_a, run_a),
      format('{"base_run_id":"%s","compared_run_id":"%s","comparison_metric":"trailing_30d_revenue_kes"}', run_a, run_f),
      format('{"base_run_id":"%s","compared_run_id":"%s","comparison_metric":"no_such_metric"}', run_a, run_b),
      format('{"base_run_id":"%s","compared_run_id":"%s","comparison_metric":"trailing_30d_revenue_kes"}', run_a, gen_random_uuid())]) LOOP
    r := pg_temp.t_cmd(exec_, 'TRUSTRIDE_OFFICE', 'EXECUTIVE_DASHBOARD', 'COMPARE_SCENARIOS', v::jsonb);
    PERFORM pg_temp.t_check('scenario: an invalid comparison is rejected with a reason ' || left(v, 60), r->>'status' = 'REJECTED' AND r->>'reason' IS NOT NULL, r::text);
  END LOOP;

  -- ============ D26: only Executives and the Founder, only through the gateway
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'EXECUTIVE_DASHBOARD', 'COMPARE_SCENARIOS',
    jsonb_build_object('base_run_id', run_a, 'compared_run_id', run_b, 'comparison_metric', 'trailing_30d_revenue_kes'));
  PERFORM pg_temp.t_check('D26 an Administrator cannot compare scenarios', coalesce(r->>'status', '') <> 'TRANSLATED', r::text);
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'COMPARE_SCENARIOS',
    jsonb_build_object('base_run_id', run_a, 'compared_run_id', run_b, 'comparison_metric', 'trailing_30d_revenue_kes'));
  PERFORM pg_temp.t_check('D26 the command is not available on the Admin Console', coalesce(r->>'status', '') <> 'TRANSLATED', r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'COMPARE_SCENARIOS',
    jsonb_build_object('base_run_id', run_a, 'compared_run_id', run_b, 'comparison_metric', 'trailing_30d_revenue_kes'));
  PERFORM pg_temp.t_check('D26 a customer cannot compare scenarios', coalesce(r->>'status', '') <> 'TRANSLATED', r::text);
  PERFORM pg_temp.t_check('D26 direct execution stays revoked (compare and the new handler)',
    NOT has_function_privilege('authenticated', 'trustride.fn_model_run_compare(uuid,uuid,text)', 'EXECUTE')
    AND NOT has_function_privilege('authenticated', 'trustride.fn_present_cmd_compare_scenarios(uuid,jsonb,uuid)', 'EXECUTE'));
  END IF;
END
$$;
