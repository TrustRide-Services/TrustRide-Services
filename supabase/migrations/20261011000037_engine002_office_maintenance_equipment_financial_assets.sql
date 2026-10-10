-- ============================================================================
-- Engine 2 (Resources) + Engine 11 -- the Office records vehicle maintenance,
-- equipment and financial assets
-- TRS026-ENG-REMEDIATION-001, finding D20 (resource capabilities)
-- ============================================================================
-- Forensic audit 2026-10-08: fn_resource_maintenance_open/complete,
-- fn_resource_equipment_register and fn_resource_financial_asset_register
-- existed but no screen, command or job reached them, so the Office could
-- not record maintenance, equipment or financial assets without SQL.
--
-- Added (the established Engine 2 functions are used unchanged):
--   * Office wrappers behind fn_resource_office_gate (Founder or
--     Administrator), each on the audit record:
--       - maintenance (INSPECTION, REPAIR, REFURBISHMENT, ROUTINE_SERVICE; at
--         the vehicle's home base unless another is named) opens only on a vehicle with no open job and
--         no open maintenance; a vehicle in a working unit takes the unit off
--         service first (the unit-state rule refuses a unit on a job);
--       - completion closes the open record; the unit is returned to service
--         with the existing "Return to service" action;
--   * commands OPEN_FLEET_MAINTENANCE, COMPLETE_FLEET_MAINTENANCE,
--     REGISTER_EQUIPMENT, REGISTER_FINANCIAL_ASSET on the Admin Console;
--   * OFFICE_RESOURCES shows each vehicle's open maintenance, the equipment
--     register and the financial assets.
-- ============================================================================

CREATE FUNCTION trustride.fn_resource_office_maintenance_open(p_fleet_resource_id uuid, p_maintenance_type text, p_estate_id uuid,
  p_description text, p_cost_kes numeric DEFAULT NULL, p_condition_before text DEFAULT NULL)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
DECLARE
  v_by UUID := trustride.fn_resource_office_gate();
  v_fleet RECORD;
  v_unit UUID;
  v_id UUID;
BEGIN
  SELECT * INTO v_fleet FROM trustride.resource_fleet_register WHERE fleet_resource_id = p_fleet_resource_id AND active;
  IF v_fleet.fleet_resource_id IS NULL THEN RAISE EXCEPTION 'No active vehicle %', p_fleet_resource_id; END IF;
  IF upper(trim(coalesce(p_maintenance_type, ''))) NOT IN ('INSPECTION', 'REPAIR', 'REFURBISHMENT', 'ROUTINE_SERVICE') THEN
    RAISE EXCEPTION 'Maintenance is INSPECTION, REPAIR, REFURBISHMENT or ROUTINE_SERVICE';
  END IF;
  IF coalesce(trim(p_description), '') = '' THEN RAISE EXCEPTION 'Describe what is being done'; END IF;
  IF p_cost_kes IS NOT NULL AND p_cost_kes < 0 THEN RAISE EXCEPTION 'Cost cannot be negative'; END IF;
  IF EXISTS (SELECT 1 FROM trustride.resource_maintenance_record WHERE fleet_resource_id = p_fleet_resource_id AND completed_at IS NULL) THEN
    RAISE EXCEPTION 'This vehicle already has open maintenance -- complete it first';
  END IF;
  SELECT workforce_unit_id INTO v_unit FROM trustride.resource_workforce_unit WHERE fleet_resource_id = p_fleet_resource_id AND unit_status = 'ACTIVE';
  IF v_unit IS NOT NULL AND trustride.fn_resource_unit_availability(v_unit) <> 'MAINTENANCE' THEN
    PERFORM trustride.fn_resource_office_unit_state_set(v_unit, 'MAINTENANCE', 'Vehicle maintenance: ' || trim(p_maintenance_type));
  END IF;
  v_id := trustride.fn_resource_maintenance_open(p_fleet_resource_id, upper(trim(p_maintenance_type)), coalesce(p_estate_id, v_fleet.home_estate_id),
    trim(p_description), p_cost_kes, v_by, p_condition_before);
  PERFORM trustride.fn_audit_log_append('resource_maintenance_record', v_id, 'MAINTENANCE_OPENED', v_by, 'USER', NULL, 'TRUSTRIDE_OFFICE', NULL,
    jsonb_build_object('fleet_resource_id', p_fleet_resource_id, 'type', p_maintenance_type, 'cost_kes', p_cost_kes, 'unit_taken_off_service', v_unit));
  RETURN v_id;
END;
$function$;

CREATE FUNCTION trustride.fn_resource_office_maintenance_complete(p_maintenance_id uuid, p_condition_after text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
DECLARE
  v_by UUID := trustride.fn_resource_office_gate();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM trustride.resource_maintenance_record WHERE maintenance_id = p_maintenance_id AND completed_at IS NULL) THEN
    RAISE EXCEPTION 'No open maintenance %', p_maintenance_id;
  END IF;
  IF coalesce(trim(p_condition_after), '') = '' THEN RAISE EXCEPTION 'Record the vehicle''s condition after maintenance'; END IF;
  PERFORM trustride.fn_resource_maintenance_complete(p_maintenance_id, trim(p_condition_after), v_by);
  PERFORM trustride.fn_audit_log_append('resource_maintenance_record', p_maintenance_id, 'MAINTENANCE_COMPLETED', v_by, 'USER', NULL, 'TRUSTRIDE_OFFICE', NULL,
    jsonb_build_object('condition_after', p_condition_after));
  RETURN p_maintenance_id;
END;
$function$;

CREATE FUNCTION trustride.fn_resource_office_equipment_register(p_equipment_type trustride.resource_equipment_type_enum, p_item_code text,
  p_description text, p_home_estate_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
DECLARE
  v_by UUID := trustride.fn_resource_office_gate();
  v_id UUID;
BEGIN
  IF coalesce(trim(p_item_code), '') = '' THEN RAISE EXCEPTION 'Give the item a code'; END IF;
  IF NOT EXISTS (SELECT 1 FROM trustride.resource_estate_register WHERE estate_id = p_home_estate_id AND active) THEN
    RAISE EXCEPTION 'Choose the base that holds this item';
  END IF;
  v_id := trustride.fn_resource_equipment_register(p_equipment_type, upper(trim(p_item_code)), trim(p_description), p_home_estate_id, v_by);
  PERFORM trustride.fn_audit_log_append('resource_equipment_register', v_id, 'EQUIPMENT_REGISTERED', v_by, 'USER', NULL, 'TRUSTRIDE_OFFICE', NULL,
    jsonb_build_object('type', p_equipment_type, 'item_code', upper(trim(p_item_code)), 'home_estate_id', p_home_estate_id));
  RETURN v_id;
END;
$function$;

CREATE FUNCTION trustride.fn_resource_office_financial_asset_register(p_asset_code text, p_asset_type trustride.resource_financial_asset_type_enum,
  p_ownership_type trustride.resource_ownership_type_enum, p_principal_amount_kes numeric, p_home_estate_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
DECLARE
  v_by UUID := trustride.fn_resource_office_gate();
BEGIN
  IF coalesce(trim(p_asset_code), '') = '' THEN RAISE EXCEPTION 'Give the asset a code'; END IF;
  IF p_principal_amount_kes IS NULL OR p_principal_amount_kes <= 0 THEN RAISE EXCEPTION 'The amount must be more than zero'; END IF;
  IF NOT EXISTS (SELECT 1 FROM trustride.resource_estate_register WHERE estate_id = p_home_estate_id AND active) THEN
    RAISE EXCEPTION 'Choose the base that holds this asset';
  END IF;
  RETURN trustride.fn_resource_financial_asset_register(upper(trim(p_asset_code)), p_asset_type, p_ownership_type, p_principal_amount_kes, v_by, p_home_estate_id);
END;
$function$;

-- Engine 11 command handlers.
CREATE FUNCTION trustride.fn_present_cmd_open_fleet_maintenance(p_session uuid, p_payload jsonb, p_command uuid)
 RETURNS uuid LANGUAGE sql SECURITY DEFINER SET search_path TO 'trustride', 'public'
AS $function$
  SELECT trustride.fn_resource_office_maintenance_open((p_payload->>'fleet_resource_id')::uuid, p_payload->>'maintenance_type',
    nullif(p_payload->>'estate_id', '')::uuid, p_payload->>'description', nullif(p_payload->>'cost_kes', '')::numeric, p_payload->>'condition_before');
$function$;

CREATE FUNCTION trustride.fn_present_cmd_complete_fleet_maintenance(p_session uuid, p_payload jsonb, p_command uuid)
 RETURNS uuid LANGUAGE sql SECURITY DEFINER SET search_path TO 'trustride', 'public'
AS $function$
  SELECT trustride.fn_resource_office_maintenance_complete((p_payload->>'maintenance_id')::uuid, p_payload->>'condition_after');
$function$;

CREATE FUNCTION trustride.fn_present_cmd_register_equipment(p_session uuid, p_payload jsonb, p_command uuid)
 RETURNS uuid LANGUAGE sql SECURITY DEFINER SET search_path TO 'trustride', 'public'
AS $function$
  SELECT trustride.fn_resource_office_equipment_register((p_payload->>'equipment_type')::trustride.resource_equipment_type_enum,
    p_payload->>'item_code', p_payload->>'description', (p_payload->>'home_estate_id')::uuid);
$function$;

CREATE FUNCTION trustride.fn_present_cmd_register_financial_asset(p_session uuid, p_payload jsonb, p_command uuid)
 RETURNS uuid LANGUAGE sql SECURITY DEFINER SET search_path TO 'trustride', 'public'
AS $function$
  SELECT trustride.fn_resource_office_financial_asset_register(p_payload->>'asset_code', (p_payload->>'asset_type')::trustride.resource_financial_asset_type_enum,
    (p_payload->>'ownership_type')::trustride.resource_ownership_type_enum, (p_payload->>'principal_amount_kes')::numeric, (p_payload->>'home_estate_id')::uuid);
$function$;

INSERT INTO trustride.present_shell_capability_registry (top_shell, sub_shell, command_type, permitted, requires_delegated_authority)
VALUES ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'OPEN_FLEET_MAINTENANCE', TRUE, FALSE),
       ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'COMPLETE_FLEET_MAINTENANCE', TRUE, FALSE),
       ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_EQUIPMENT', TRUE, FALSE),
       ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_FINANCIAL_ASSET', TRUE, FALSE);

-- OFFICE_RESOURCES: open maintenance per vehicle, equipment, financial assets.
DO $patch$
DECLARE
  v_def TEXT;
  v_fleet_old TEXT := E'''bound_unit'', (SELECT wu.workforce_unit_id FROM trustride.resource_workforce_unit wu WHERE wu.fleet_resource_id = f.fleet_resource_id AND wu.unit_status = ''ACTIVE''),';
  v_tail_old TEXT := E'''capability_types'', (SELECT jsonb_agg(v) FROM unnest(enum_range(NULL::trustride.resource_capability_type_enum)) v));';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_present_proj_office_resources(uuid,jsonb)'::regprocedure) INTO v_def;
  IF position(v_fleet_old IN v_def) = 0 OR position(v_tail_old IN v_def) = 0 THEN RAISE EXCEPTION 'office resources projection anchors not found'; END IF;
  v_def := replace(v_def, v_fleet_old, v_fleet_old
    || E'\n              ''open_maintenance'', (SELECT jsonb_build_object(''maintenance_id'', m.maintenance_id, ''type'', m.maintenance_type, ''description'', m.description, ''opened_at'', m.created_at)\n'
    || E'                                   FROM trustride.resource_maintenance_record m WHERE m.fleet_resource_id = f.fleet_resource_id AND m.completed_at IS NULL ORDER BY m.created_at DESC LIMIT 1),');
  v_def := replace(v_def, v_tail_old,
       E'''capability_types'', (SELECT jsonb_agg(v) FROM unnest(enum_range(NULL::trustride.resource_capability_type_enum)) v),\n'
    || E'    ''equipment'', coalesce((SELECT jsonb_agg(jsonb_build_object(''equipment_id'', q.equipment_id, ''type'', q.equipment_type, ''code'', q.item_code, ''description'', q.description,\n'
    || E'         ''base'', (SELECT estate_name FROM trustride.resource_estate_register WHERE estate_id = q.home_estate_id), ''lifecycle'', q.lifecycle_state) ORDER BY q.created_at DESC)\n'
    || E'       FROM trustride.resource_equipment_register q WHERE q.active), ''[]''::jsonb),\n'
    || E'    ''financial_assets'', coalesce((SELECT jsonb_agg(jsonb_build_object(''financial_asset_id'', a.financial_asset_id, ''code'', a.asset_code, ''type'', a.asset_type,\n'
    || E'         ''ownership'', a.ownership_type, ''principal_kes'', a.principal_amount_kes, ''balance_kes'', a.current_balance_kes, ''compliance'', a.compliance_status,\n'
    || E'         ''base'', (SELECT estate_name FROM trustride.resource_estate_register WHERE estate_id = a.home_estate_id)) ORDER BY a.created_at DESC)\n'
    || E'       FROM trustride.resource_financial_asset a WHERE a.active), ''[]''::jsonb),\n'
    || E'    ''equipment_types'', (SELECT jsonb_agg(v) FROM unnest(enum_range(NULL::trustride.resource_equipment_type_enum)) v),\n'
    || E'    ''financial_asset_types'', (SELECT jsonb_agg(v) FROM unnest(enum_range(NULL::trustride.resource_financial_asset_type_enum)) v));');
  EXECUTE v_def;
END;
$patch$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
