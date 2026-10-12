-- ============================================================================
-- TRS026 Construction Directive 2.11 (WP8) -- Executive scenario comparison.
--
-- Engine 10's fn_model_run_compare had no presentation path (D20) and direct
-- execution was revoked by D26. It is now reached only through the Executive
-- Dashboard command COMPARE_SCENARIOS (Engine 11 gateway; the Executive
-- Dashboard session opens only for Executives and the Founder, and the Engine 10
-- function keeps its own role check):
--   * both runs must exist, differ and be COMPLETED, and carry the metric;
--   * the same comparison is returned, not stored twice (completed runs are
--     immutable, so the result cannot differ);
--   * every comparison is audited (SCENARIO_COMPARED, by whom).
-- The scenarios projection now also lists each run's metrics, recent
-- comparisons, and the active pricing rows a PRICING_CHANGE run can address
-- (read from Engine 5, never changed). Defect: the Executive screen could not
-- supply scenario inputs, so no pricing run could ever complete from it.
-- ============================================================================

CREATE FUNCTION trustride.fn_present_cmd_compare_scenarios(p_session uuid, p_payload jsonb, p_command uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
DECLARE
  v_base UUID := nullif(p_payload->>'base_run_id', '')::uuid;
  v_cmp UUID := nullif(p_payload->>'compared_run_id', '')::uuid;
  v_metric TEXT := nullif(trim(coalesce(p_payload->>'comparison_metric', '')), '');
  v_existing UUID;
  v_id UUID;
  v_row RECORD;
BEGIN
  IF v_base IS NULL OR v_cmp IS NULL OR v_metric IS NULL THEN RAISE EXCEPTION 'Choose two runs and the metric to compare'; END IF;
  IF v_base = v_cmp THEN RAISE EXCEPTION 'Choose two different runs'; END IF;
  IF (SELECT count(*) FROM trustride.model_scenario_run WHERE run_id IN (v_base, v_cmp) AND run_status = 'COMPLETED') < 2 THEN
    RAISE EXCEPTION 'Both runs must exist and have completed';
  END IF;
  SELECT comparative_view_id INTO v_existing FROM trustride.model_comparative_view
  WHERE base_run_id = v_base AND compared_run_id = v_cmp AND comparison_metric = v_metric ORDER BY generated_at LIMIT 1;
  IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;
  v_id := trustride.fn_model_run_compare(v_base, v_cmp, v_metric);
  SELECT * INTO v_row FROM trustride.model_comparative_view WHERE comparative_view_id = v_id;
  PERFORM trustride.fn_audit_log_append('model_comparative_view', v_id, 'SCENARIO_COMPARED', auth.uid(), 'USER', NULL, 'TRUSTRIDE_OFFICE', NULL,
    jsonb_build_object('base_run_id', v_base, 'compared_run_id', v_cmp, 'metric', v_metric,
      'base_value', v_row.base_value, 'compared_value', v_row.compared_value, 'delta', v_row.delta, 'command_id', p_command));
  RETURN v_id;
END;
$function$;
INSERT INTO trustride.present_shell_capability_registry (top_shell, sub_shell, command_type, permitted, requires_delegated_authority)
VALUES ('TRUSTRIDE_OFFICE', 'EXECUTIVE_DASHBOARD', 'COMPARE_SCENARIOS', TRUE, FALSE);

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_exec_scenarios(p_session uuid, p_params jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
  SELECT jsonb_build_object(
    'scenarios', coalesce((SELECT jsonb_agg(jsonb_build_object('code', s.scenario_code, 'name', s.scenario_name, 'type', s.scenario_type,
        'description', s.description, 'input_schema', s.input_schema) ORDER BY s.scenario_name)
      FROM trustride.model_scenario_registry s WHERE s.active), '[]'::jsonb),
    'runs', coalesce((SELECT jsonb_agg(jsonb_build_object('run_id', r.run_id, 'scenario', s.scenario_code, 'label', r.run_label, 'status', r.run_status,
        'failure_reason', r.failure_reason, 'started_at', r.started_at, 'completed_at', r.completed_at,
        'metrics', (SELECT jsonb_object_agg(po.outcome_metric, po.projected_value) FROM trustride.model_projected_outcome po WHERE po.run_id = r.run_id),
        'inputs', (SELECT jsonb_object_agg(ip.parameter_name, ip.parameter_value) FROM trustride.model_input_parameter ip WHERE ip.run_id = r.run_id),
        'outcomes', (SELECT jsonb_agg(to_jsonb(po) - 'run_id') FROM trustride.model_projected_outcome po WHERE po.run_id = r.run_id),
        'insights', (SELECT jsonb_agg(to_jsonb(ai) - 'run_id') FROM trustride.model_actionable_insight ai WHERE ai.run_id = r.run_id))
        ORDER BY r.created_at DESC)
      FROM (SELECT * FROM trustride.model_scenario_run ORDER BY created_at DESC LIMIT 20) r JOIN trustride.model_scenario_registry s ON s.scenario_registry_id = r.scenario_registry_id), '[]'::jsonb),
    'comparisons', coalesce((SELECT jsonb_agg(jsonb_build_object('id', c.comparative_view_id, 'metric', c.comparison_metric,
        'base_label', rb.run_label, 'compared_label', rc.run_label, 'base_value', c.base_value, 'compared_value', c.compared_value,
        'delta', c.delta, 'at', c.generated_at) ORDER BY c.generated_at DESC)
      FROM (SELECT * FROM trustride.model_comparative_view ORDER BY generated_at DESC LIMIT 20) c
      JOIN trustride.model_scenario_run rb ON rb.run_id = c.base_run_id JOIN trustride.model_scenario_run rc ON rc.run_id = c.compared_run_id), '[]'::jsonb),
    'pricing_inputs', coalesce((SELECT jsonb_agg(jsonb_build_object('macro_domain', reg.macro_domain, 'service_code', reg.service_code,
        'asset_class', reg.asset_class, 'jurisdiction', reg.jurisdiction, 'current_rate_kes', rt.direct_per_km_rate_kes)
        ORDER BY reg.service_code, reg.asset_class)
      FROM trustride.cost_registry reg JOIN trustride.cost_rate rt ON rt.rate_id = reg.cost_rate_id
      WHERE reg.status = 'ACTIVE' AND rt.direct_per_km_rate_kes IS NOT NULL), '[]'::jsonb));
$function$;

UPDATE trustride.projection_registry
SET source_tables = '["model_scenario_registry", "model_scenario_run", "model_input_parameter", "model_projected_outcome", "model_actionable_insight", "model_comparative_view", "cost_registry", "cost_rate"]'::jsonb
WHERE projection_code = 'EXEC_SCENARIOS';

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
