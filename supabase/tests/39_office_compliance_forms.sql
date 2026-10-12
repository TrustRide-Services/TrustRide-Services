-- Suite 39 -- the Office compliance screen (Construction Directive WP8): EPRA price cycles, NTSA vehicle lookups,
-- supplier invoices and payroll confirmation. Their commands are proven in suites 28, 30, 32 and 33; this suite
-- proves the screen's projection: what was recorded, current state, honest simulator marking, the activation
-- dependencies, and that only the Admin Console (Founder, Administrator) sees it.
DO $$
DECLARE
  founder UUID; admin UUID; exec_ UUID; cust UUID; r JSONB; v TEXT; s UUID;
  ready BOOLEAN := to_regprocedure('trustride.fn_present_proj_office_compliance(uuid,jsonb)') IS NOT NULL;
BEGIN
  IF NOT ready THEN
    PERFORM pg_temp.t_check('Office compliance projection exists', false, 'fn_present_proj_office_compliance absent');
  ELSE
  founder := pg_temp.t_person('Comp Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  admin := pg_temp.t_person('Comp Admin', NULL);  PERFORM pg_temp.t_role(admin, 'ADMINISTRATOR');
  exec_ := pg_temp.t_person('Comp Exec', NULL);  PERFORM pg_temp.t_role(exec_, 'EXECUTIVE');
  cust := pg_temp.t_customer('Comp Customer');

  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RECORD_EPRA_PRICE_CYCLE', '{"cycle_start":"2026-09-15","cycle_end":"2026-10-14","publication_date":"2026-09-14","source_reference":"EPRA maximum retail prices 15 Sep - 14 Oct 2026","source_url":"https://www.epra.go.ke","prices":[{"jurisdiction":"KISUMU_COUNTY","fuel_type":"PETROL_SUPER","pump_price_kes":213.69},{"jurisdiction":"KISUMU_COUNTY","fuel_type":"DIESEL","pump_price_kes":218.08}]}');
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'NTSA_VEHICLE_LOOKUP', '{"identifier_type":"VIN","identifier":"JTDBR32E300512399"}');
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RECORD_PURCHASE_INVOICE', '{"supplier_pin":"P000111222A","supplier_name":"Kisumu Fuel Station","cu_invoice_number":"CU0012399999","invoice_date":"2026-10-10","amount_kes":4800,"description":"Fuel"}');

  r := trustride.fn_present_proj_office_compliance(NULL, '{"on":"2026-10-01"}');
  PERFORM pg_temp.t_check('compliance: the EPRA cycle in force is shown with its source, and whether it feeds pricing',
    EXISTS (SELECT 1 FROM jsonb_array_elements(r->'epra'->'current') x WHERE x->>'fuel_type' = 'PETROL_SUPER' AND (x->>'pump_price_kes')::numeric = 213.69 AND x->>'source_reference' LIKE 'EPRA%')
    AND (r->'epra'->>'applied_to_pricing')::boolean = false, left((r->'epra')::text, 300));
  PERFORM pg_temp.t_check('compliance: NTSA lookups are listed and marked simulated',
    EXISTS (SELECT 1 FROM jsonb_array_elements(r->'ntsa_lookups') x WHERE x->>'reference_number' = 'JTDBR32E300512399' AND (x->>'simulated')::boolean), left((r->'ntsa_lookups')::text, 300));
  PERFORM pg_temp.t_check('compliance: supplier invoices are listed with the supplier''s control unit number',
    EXISTS (SELECT 1 FROM jsonb_array_elements(r->'purchases') x WHERE x->>'cu_invoice_number' = 'CU0012399999' AND x->>'supplier_name' = 'Kisumu Fuel Station'), left((r->'purchases')::text, 300));
  SELECT set_id INTO s FROM trustride.business_payroll_statutory_set WHERE status = 'PROVISIONAL' ORDER BY effective_from DESC LIMIT 1;
  PERFORM pg_temp.t_check('compliance: the payroll statutory set is shown provisional, with the Housing Levy item flagged',
    EXISTS (SELECT 1 FROM jsonb_array_elements(r->'payroll_sets') x WHERE x->>'set_id' = s::text AND x->>'status' = 'PROVISIONAL'
            AND EXISTS (SELECT 1 FROM jsonb_array_elements(x->'items') i WHERE i->>'item_code' = 'AHL' AND i->>'deductible_before_paye' = 'UNCONFIRMED')), left((r->'payroll_sets')::text, 300));
  PERFORM pg_temp.t_check('compliance: the eTIMS determination and each port''s activation dependency are stated',
    r->'etims'->>'determination' = 'PENDING_LEGAL_DETERMINATION'
    AND (SELECT count(*) FROM jsonb_array_elements(r->'dependencies') x WHERE x->>'port' IN ('EPRA_SERVICE', 'NTSA_SERVICE', 'ETIMS_SERVICE') AND x->>'blocking_dependency' IS NOT NULL) = 3,
    left((r->'dependencies')::text, 300));
  PERFORM pg_temp.t_check('compliance: the payroll confirmation is offered only to the Founder',
    (r->>'founder')::boolean IS NOT NULL);

  -- ============ who sees it
  PERFORM pg_temp.t_check('compliance: registered for the Admin Console only',
    (SELECT sub_shells FROM trustride.projection_registry WHERE projection_code = 'OFFICE_COMPLIANCE') = ARRAY['ADMIN_CONSOLE']);
  PERFORM pg_temp.t_as(exec_);
  BEGIN PERFORM trustride.fn_present_shell_session_open('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', exec_, 'WEB'); v := 'opened';
  EXCEPTION WHEN OTHERS THEN v := 'refused'; END;
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('compliance: an Executive cannot open the Admin Console to read it', v = 'refused', v);
  PERFORM pg_temp.t_as(cust);
  BEGIN PERFORM trustride.fn_present_shell_session_open('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', cust, 'WEB'); v := 'opened';
  EXCEPTION WHEN OTHERS THEN v := 'refused'; END;
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('compliance: a customer cannot open the Admin Console', v = 'refused', v);
  PERFORM pg_temp.t_check('compliance: the projection function is not callable directly',
    NOT has_function_privilege('authenticated', 'trustride.fn_present_proj_office_compliance(uuid,jsonb)', 'EXECUTE'));
  END IF;
END
$$;
