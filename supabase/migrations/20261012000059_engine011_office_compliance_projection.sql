-- ============================================================================
-- TRS026 Construction Directive WP8 -- the Office compliance screen: EPRA price
-- cycles, NTSA vehicle lookups, supplier invoices (eTIMS purchases) and payroll
-- confirmation. The commands exist (RECORD_EPRA_PRICE_CYCLE, NTSA_VEHICLE_LOOKUP,
-- RECORD_PURCHASE_INVOICE, CONFIRM_PAYROLL_STATUTORY_SET); this projection
-- (Admin Console only) shows what was recorded, the state in force, simulator
-- marking and each capability's activation dependency, read from the owning
-- engines (6 and 4). Nothing is written.
-- ============================================================================

CREATE FUNCTION trustride.fn_present_proj_office_compliance(p_session uuid, p_params jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
  WITH d AS (SELECT coalesce(nullif(p_params->>'on', '')::date, (now() AT TIME ZONE 'Africa/Nairobi')::date) AS on_date)
  SELECT jsonb_build_object(
    'founder', coalesce((SELECT EXISTS (SELECT 1 FROM trustride.role_assignment ra JOIN trustride.role_definition rd ON rd.role_id = ra.role_id
                                        WHERE ra.user_id = trustride.fn_present_session_user(p_session) AND rd.role_code = 'FOUNDER' AND ra.status = 'ACTIVE')), false),
    'epra', jsonb_build_object(
      'applied_to_pricing', coalesce(upper(trustride.fn_business_config('EPRA_RATE_DERIVATION_ACTIVE')) = 'TRUE', false),
      'current', coalesce((SELECT jsonb_agg(jsonb_build_object('jurisdiction', j, 'fuel_type', f, 'pump_price_kes', c.pump_price_kes,
                                    'cycle_start', c.price_cycle_start, 'cycle_end', c.price_cycle_end, 'source_reference', c.source_reference, 'status', c.status))
                           FROM d, unnest(string_to_array(coalesce(trustride.fn_business_config('EPRA_WATCH_JURISDICTIONS'), 'KISUMU_COUNTY'), ',')) j,
                                unnest(ARRAY['PETROL_SUPER', 'DIESEL']) f,
                                LATERAL trustride.fn_integration_epra_current(f, trim(j)::trustride.cost_jurisdiction_enum, d.on_date) c), '[]'::jsonb),
      'recent', coalesce((SELECT jsonb_agg(x ORDER BY x->>'recorded_at' DESC) FROM (
          SELECT jsonb_build_object('jurisdiction', l.jurisdiction, 'fuel_type', l.fuel_type, 'pump_price_kes', l.pump_price_kes,
            'cycle_start', l.price_cycle_start, 'cycle_end', l.price_cycle_end, 'source_reference', l.source_reference, 'status', l.status,
            'recorded_at', l.ingested_at) x
          FROM trustride.integration_epra_fuel_ingestion_log l WHERE l.status <> 'SIMULATED' ORDER BY l.ingested_at DESC LIMIT 12) t), '[]'::jsonb),
      'watch_jurisdictions', trustride.fn_business_config('EPRA_WATCH_JURISDICTIONS')),
    'ntsa_lookups', coalesce((SELECT jsonb_agg(x ORDER BY x->>'at' DESC) FROM (
        SELECT jsonb_build_object('reference_number', n.reference_number, 'identifier_type', n.details->>'identifier_type', 'outcome', n.outcome,
          'simulated', coalesce((n.details->>'simulated')::boolean, n.adapter_type = 'SIMULATOR'), 'at', n.created_at) x
        FROM trustride.integration_ntsa_verification_log n WHERE n.check_type = 'VEHICLE_IDENTIFICATION' ORDER BY n.created_at DESC LIMIT 20) t), '[]'::jsonb),
    'purchases', coalesce((SELECT jsonb_agg(x ORDER BY x->>'recorded_at' DESC) FROM (
        SELECT jsonb_build_object('supplier_pin', e.counterparty_pin, 'supplier_name', e.counterparty_name, 'cu_invoice_number', e.cu_invoice_number,
          'invoice_date', e.invoice_date, 'amount_kes', e.amount_kes, 'description', e.description, 'status', e.status, 'recorded_at', e.submitted_at) x
        FROM trustride.integration_etims_invoice_log e WHERE e.direction = 'PURCHASE' ORDER BY e.submitted_at DESC LIMIT 20) t), '[]'::jsonb),
    'etims', jsonb_build_object('determination', trustride.fn_business_config('ETIMS_TAX_DETERMINATION'),
      'reconciliation_30d', coalesce((SELECT jsonb_object_agg(finding, n) FROM (
          SELECT r.finding, count(*) n FROM d, trustride.fn_integration_etims_reconcile(d.on_date - 30, d.on_date) r GROUP BY r.finding) t), '{}'::jsonb)),
    'payroll_sets', coalesce((SELECT jsonb_agg(jsonb_build_object('set_id', s.set_id, 'label', s.label, 'effective_from', s.effective_from,
        'effective_to', s.effective_to, 'status', s.status, 'ahl_deductible_confirmed', s.ahl_deductible_confirmed,
        'confirmation_reference', s.confirmation_reference, 'confirmed_at', s.confirmed_at,
        'items', (SELECT jsonb_agg(jsonb_build_object('item_code', i.item_code, 'kind', i.kind, 'seq', i.seq, 'upper_kes', i.upper_kes, 'rate', i.rate,
                    'employer_rate', i.employer_rate, 'fixed_kes', i.fixed_kes, 'minimum_kes', i.minimum_kes,
                    'deductible_before_paye', i.deductible_before_paye, 'source', i.source) ORDER BY i.kind, i.item_code, i.seq)
                  FROM trustride.business_payroll_statutory_item i WHERE i.set_id = s.set_id))
        ORDER BY s.effective_from DESC)
      FROM trustride.business_payroll_statutory_set s), '[]'::jsonb),
    'dependencies', coalesce((SELECT jsonb_agg(jsonb_build_object('port', p.port_code, 'status_level', p.status_level,
        'readiness', p.readiness, 'blocking_dependency', p.blocking_dependency) ORDER BY p.port_code)
      FROM trustride.integration_port_registry p WHERE p.active AND p.port_code::text IN ('EPRA_SERVICE', 'NTSA_SERVICE', 'ETIMS_SERVICE')), '[]'::jsonb))
  FROM d;
$function$;

INSERT INTO trustride.projection_registry (projection_code, shell, source_tables, refresh_mode, is_authoritative, sub_shells, description)
SELECT 'OFFICE_COMPLIANCE', 'TRUSTRIDE_OFFICE',
  '["integration_epra_fuel_ingestion_log", "integration_ntsa_verification_log", "integration_etims_invoice_log", "business_payroll_statutory_set", "business_payroll_statutory_item", "integration_port_registry", "platform_configuration"]'::jsonb,
  refresh_mode, FALSE, ARRAY['ADMIN_CONSOLE'], 'EPRA cycles, NTSA lookups, supplier invoices and payroll statutory sets'
FROM trustride.projection_registry WHERE projection_code = 'OFFICE_INTEGRATIONS';

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
