-- Suite 23 -- the Office records vehicle maintenance, equipment and financial assets
-- through its own commands (TRS026-ENG-REMEDIATION-001: D20).
DO $$
DECLARE
  founder UUID; est UUID; unit UUID; fleet UUID; r JSONB; m UUID; v TEXT; n INT; cust UUID;
BEGIN
  PERFORM pg_temp.t_open_all_hours();
  founder := pg_temp.t_person('Res Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  cust := pg_temp.t_customer('Res Cust');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"RES-23","estate_name":"Res Hub","estate_type":"OPERATING_HUB","lat":-0.09,"lon":34.76}');
  est := (r->>'signal')::uuid;
  unit := pg_temp.t_ready_unit(founder, 'BODA_BODA', est, 'Res Rider');
  SELECT fleet_resource_id INTO fleet FROM trustride.resource_workforce_unit WHERE workforce_unit_id = unit;

  -- ============ equipment and financial assets
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_EQUIPMENT',
    jsonb_build_object('equipment_type', 'SAFETY_GEAR', 'item_code', 'hel-001', 'description', 'Helmet, size L', 'home_estate_id', est));
  PERFORM pg_temp.t_check('D20 Office registers equipment', r->>'status' = 'TRANSLATED'
    AND EXISTS (SELECT 1 FROM trustride.resource_equipment_register WHERE item_code = 'HEL-001' AND home_estate_id = est), r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_FINANCIAL_ASSET',
    jsonb_build_object('asset_code', 'float-01', 'asset_type', 'CASH_FLOAT', 'ownership_type', 'OWNED', 'principal_amount_kes', 5000, 'home_estate_id', est));
  PERFORM pg_temp.t_check('D20 Office registers a financial asset', r->>'status' = 'TRANSLATED'
    AND EXISTS (SELECT 1 FROM trustride.resource_financial_asset WHERE asset_code = 'FLOAT-01' AND principal_amount_kes = 5000), r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_FINANCIAL_ASSET',
    jsonb_build_object('asset_code', 'float-02', 'asset_type', 'CASH_FLOAT', 'ownership_type', 'OWNED', 'principal_amount_kes', 0, 'home_estate_id', est));
  PERFORM pg_temp.t_check('D20 a zero-value financial asset is refused with a reason', r->>'status' = 'REJECTED' AND r->>'reason' ILIKE '%more than zero%', r::text);

  -- ============ vehicle maintenance
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'OPEN_FLEET_MAINTENANCE',
    jsonb_build_object('fleet_resource_id', fleet, 'maintenance_type', 'ROUTINE_SERVICE', 'description', '5,000 km service', 'cost_kes', 2500, 'estate_id', est));
  SELECT maintenance_id INTO m FROM trustride.resource_maintenance_record WHERE fleet_resource_id = fleet AND completed_at IS NULL;
  PERFORM pg_temp.t_check('D20 Office opens maintenance on a vehicle', r->>'status' = 'TRANSLATED' AND m IS NOT NULL, r::text);
  v := trustride.fn_resource_unit_availability(unit)::text;
  PERFORM pg_temp.t_check('D20 the vehicle''s working unit is taken off service', v = 'MAINTENANCE', v);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'OPEN_FLEET_MAINTENANCE',
    jsonb_build_object('fleet_resource_id', fleet, 'maintenance_type', 'ROUTINE_SERVICE', 'description', 'again'));
  PERFORM pg_temp.t_check('D20 a second open maintenance is refused', r->>'status' = 'REJECTED' AND r->>'reason' ILIKE '%already has open maintenance%', r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'COMPLETE_FLEET_MAINTENANCE',
    jsonb_build_object('maintenance_id', m, 'condition_after', 'Good'));
  PERFORM pg_temp.t_check('D20 Office completes maintenance', r->>'status' = 'TRANSLATED'
    AND EXISTS (SELECT 1 FROM trustride.resource_maintenance_record WHERE maintenance_id = m AND completed_at IS NOT NULL), r::text);
  SELECT count(*) INTO n FROM trustride.audit_log WHERE entity_id = m AND action IN ('MAINTENANCE_OPENED', 'MAINTENANCE_COMPLETED') AND actor_id = founder;
  PERFORM pg_temp.t_check('D20 maintenance is on the audit record with the Founder as actor', n = 2, n::text);

  -- ============ projection and authority
  r := pg_temp.t_proj(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'OFFICE_RESOURCES', '{}');
  PERFORM pg_temp.t_check('D20 OFFICE_RESOURCES lists equipment and financial assets',
    jsonb_array_length(r->'equipment') >= 1 AND jsonb_array_length(r->'financial_assets') >= 1, left(r::text, 200));
  PERFORM pg_temp.t_as(cust);
  PERFORM pg_temp.t_check('D20 a customer cannot record maintenance',
    pg_temp.t_fails(format('SELECT trustride.fn_resource_office_maintenance_open(%L, ''REPAIR'', NULL, ''x'')', fleet)));
  PERFORM pg_temp.t_admin();
END
$$;
