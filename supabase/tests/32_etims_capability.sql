-- Suite 32 -- KRA eTIMS as a separate capability (Construction Directive WP7, section 2.4).
-- Sales and purchase invoices with their statuses and reconciliation, answered by a simulator that never
-- imitates a KRA artefact. Nothing encodes whether a fare is taxable: the tax treatment is recorded as
-- undetermined until the legal determination, no KRA endpoint is invented, and no live submission is
-- possible while the determination is pending.
DO $$
DECLARE
  founder UUID; cust UUID; inv UUID; pur UUID; r JSONB; v TEXT; n INT; ok BOOLEAN; rec RECORD; ord UUID;
  ready BOOLEAN := to_regprocedure('trustride.fn_integration_etims_reconcile(date,date)') IS NOT NULL;
BEGIN
  -- ============ the existing simulator imitates KRA (checked whatever the build)
  inv := trustride.fn_integration_etims_invoice_submit(gen_random_uuid(), 650.40);
  SELECT * INTO rec FROM trustride.integration_etims_invoice_log WHERE etims_invoice_id = inv;
  PERFORM pg_temp.t_check('eTIMS: a simulated invoice never carries a KRA-looking control number or a kra.go.ke link',
    rec.cu_invoice_number NOT LIKE 'KRA%' AND coalesce(rec.qr_code_data, '') NOT ILIKE '%kra.go.ke%', coalesce(rec.cu_invoice_number, '') || ' ' || coalesce(rec.qr_code_data, ''));
  IF NOT ready THEN
    PERFORM pg_temp.t_check('eTIMS capability (sales, purchases, reconciliation) exists', false, 'fn_integration_etims_reconcile absent');
  ELSE
  founder := pg_temp.t_person('Etims Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  cust := pg_temp.t_customer('Etims Customer');

  -- ============ no tax assumption is encoded
  PERFORM pg_temp.t_check('eTIMS: the tax determination is recorded as pending (no default treatment)',
    trustride.fn_business_config('ETIMS_TAX_DETERMINATION') = 'PENDING_LEGAL_DETERMINATION');
  PERFORM pg_temp.t_check('eTIMS: a simulated sale records its tax treatment as UNDETERMINED and its basis explicitly',
    rec.tax_treatment = 'UNDETERMINED' AND rec.direction = 'SALE' AND rec.simulated, coalesce(rec.tax_treatment, 'none'));
  PERFORM pg_temp.t_check('eTIMS: no VAT or tax amount is computed by TrustRide', NOT EXISTS (
    SELECT 1 FROM information_schema.columns WHERE table_schema = 'trustride' AND table_name = 'integration_etims_invoice_log'
      AND column_name ~ '(vat|tax_amount|taxable)'));

  -- ============ sales: lifecycle and statuses
  inv := trustride.fn_integration_etims_sale_record(gen_random_uuid(), 'FULL_FARE', 1200.00, 'P051234567Z', 'Mwangaza Logistics Limited');
  SELECT * INTO rec FROM trustride.integration_etims_invoice_log WHERE etims_invoice_id = inv;
  PERFORM pg_temp.t_check('eTIMS: a sale is answered by the simulator (marked simulated, SIM- reference, no QR)',
    rec.status::text = 'ACCEPTED' AND rec.simulated AND rec.cu_invoice_number LIKE 'SIM-%' AND rec.qr_code_data IS NULL
    AND rec.amount_basis = 'FULL_FARE' AND rec.counterparty_pin = 'P051234567Z', rec.status::text);
  FOR rec IN SELECT * FROM (VALUES
      ('a sale with no amount basis', 'SELECT trustride.fn_integration_etims_sale_record(gen_random_uuid(), NULL, 100, NULL, NULL)'),
      ('an unknown amount basis', 'SELECT trustride.fn_integration_etims_sale_record(gen_random_uuid(), ''GUESS'', 100, NULL, NULL)'),
      ('a zero amount', 'SELECT trustride.fn_integration_etims_sale_record(gen_random_uuid(), ''FULL_FARE'', 0, NULL, NULL)'),
      ('a malformed buyer KRA PIN', 'SELECT trustride.fn_integration_etims_sale_record(gen_random_uuid(), ''FULL_FARE'', 100, ''12345'', NULL)')) x(label, sql) LOOP
    PERFORM pg_temp.t_check('eTIMS: ' || rec.label || ' is refused', pg_temp.t_fails(rec.sql));
  END LOOP;
  ord := gen_random_uuid();
  inv := trustride.fn_integration_etims_sale_record(ord, 'FULL_FARE', 500.00, NULL, NULL);
  PERFORM pg_temp.t_check('eTIMS: one sale invoice per order and basis (a repeat returns the same invoice)',
    trustride.fn_integration_etims_sale_record(ord, 'FULL_FARE', 500.00, NULL, NULL) = inv);
  PERFORM pg_temp.t_check('eTIMS: a repeat with a different amount is refused (a correction is a credit note, not an edit)',
    pg_temp.t_fails(format('SELECT trustride.fn_integration_etims_sale_record(%L, ''FULL_FARE'', 600, NULL, NULL)', ord)));
  inv := trustride.fn_integration_etims_sale_record(gen_random_uuid(), 'FULL_FARE', 100.00, NULL, NULL, 'SIMULATE_REJECT');
  SELECT status::text || '|' || coalesce(last_error, '') INTO v FROM trustride.integration_etims_invoice_log WHERE etims_invoice_id = inv;
  PERFORM pg_temp.t_check('eTIMS: a rejected submission is kept with its reason (never shown as issued)', v LIKE 'REJECTED|%', v);

  -- ============ purchases (supplier invoices received for TrustRide)
  pur := trustride.fn_integration_etims_purchase_record('P000111222A', 'Kisumu Fuel Station', 'CU0012345678', '2026-10-10', 4800.00, 'Fuel for fleet');
  SELECT * INTO rec FROM trustride.integration_etims_invoice_log WHERE etims_invoice_id = pur;
  PERFORM pg_temp.t_check('eTIMS: a supplier invoice is recorded as a PURCHASE with the supplier''s control unit number',
    rec.direction = 'PURCHASE' AND rec.cu_invoice_number = 'CU0012345678' AND rec.counterparty_pin = 'P000111222A', coalesce(rec.direction, 'none'));
  PERFORM pg_temp.t_check('eTIMS: the same supplier invoice cannot be recorded twice',
    pg_temp.t_fails('SELECT trustride.fn_integration_etims_purchase_record(''P000111222A'', ''Kisumu Fuel Station'', ''CU0012345678'', ''2026-10-10'', 4800, ''again'')'));
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RECORD_PURCHASE_INVOICE', '{"supplier_pin":"P000111222A","supplier_name":"Kisumu Fuel Station","cu_invoice_number":"CU0099999999","invoice_date":"2026-10-11","amount_kes":2500,"description":"Tyres"}');
  PERFORM pg_temp.t_check('eTIMS: the Office records a supplier invoice through the command gateway, attributed to the person',
    r->>'status' = 'TRANSLATED' AND EXISTS (SELECT 1 FROM trustride.integration_etims_invoice_log WHERE cu_invoice_number = 'CU0099999999' AND recorded_by = founder), r::text);
  PERFORM pg_temp.t_check('eTIMS: signed-in users cannot call the purchase function directly (the command is the only way in)',
    NOT has_function_privilege('authenticated', 'trustride.fn_integration_etims_purchase_record(text,text,text,date,numeric,text)', 'EXECUTE'));
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RECORD_PURCHASE_INVOICE', '{"supplier_pin":"P000111222A","supplier_name":"X","cu_invoice_number":"CU0088888888","invoice_date":"2026-10-11","amount_kes":1,"description":"x"}');
  PERFORM pg_temp.t_check('eTIMS: a customer cannot record supplier invoices', coalesce(r->>'status', '') <> 'TRANSLATED', r::text);

  -- ============ reconciliation
  SELECT count(*) INTO n FROM trustride.fn_integration_etims_reconcile(current_date - 1, current_date + 1) x WHERE x.finding = 'INVOICE_WITHOUT_SETTLEMENT';
  PERFORM pg_temp.t_check('eTIMS reconciliation: sale invoices with no settled order are reported', n >= 3, n::text);
  SELECT count(*) INTO n FROM trustride.fn_integration_etims_reconcile(current_date - 1, current_date + 1) x WHERE x.finding = 'REJECTED_INVOICE';
  PERFORM pg_temp.t_check('eTIMS reconciliation: rejected submissions are reported', n >= 1, n::text);
  SELECT count(*) INTO n FROM trustride.fn_integration_etims_reconcile(current_date - 1, current_date + 1) x WHERE x.finding = 'SETTLEMENT_WITHOUT_INVOICE';
  PERFORM pg_temp.t_check('eTIMS reconciliation: settled orders with no sale invoice are counted (report only; issuing waits for the determination)',
    n = (SELECT count(*) FROM trustride.business_settlement s WHERE s.settled_at::date BETWEEN current_date - 1 AND current_date + 1
         AND NOT EXISTS (SELECT 1 FROM trustride.integration_etims_invoice_log l WHERE l.order_id = s.order_id AND l.direction = 'SALE')), n::text);
  PERFORM pg_temp.t_check('eTIMS: reconciliation is for the Office and the service role only',
    NOT has_function_privilege('authenticated', 'trustride.fn_integration_etims_reconcile(date,date)', 'EXECUTE')
    AND has_function_privilege('service_role', 'trustride.fn_integration_etims_reconcile(date,date)', 'EXECUTE'));

  -- ============ no live activation without the legal determination
  PERFORM pg_temp.t_as(founder);
  BEGIN PERFORM trustride.fn_integration_adapter_set('ETIMS_SERVICE', 'SANDBOX', 'suite 32'); ok := false; v := 'switched';
  EXCEPTION WHEN OTHERS THEN ok := true; v := SQLERRM; END;
  PERFORM pg_temp.t_check('eTIMS: the port cannot leave the simulator', ok, left(v, 160));
  PERFORM pg_temp.t_admin();
  UPDATE trustride.integration_adapter_registry SET active = FALSE WHERE port_code = 'ETIMS_SERVICE' AND active;
  INSERT INTO trustride.integration_adapter_registry (port_code, adapter_type, active, notes) VALUES ('ETIMS_SERVICE', 'PRODUCTION', TRUE, 'suite 32');
  BEGIN PERFORM trustride.fn_integration_etims_sale_record(gen_random_uuid(), 'FULL_FARE', 100, NULL, NULL); ok := false; v := 'submitted';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'ETIMS_TAX_DETERMINATION_PENDING%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('eTIMS: in a live mode a sale is refused while the tax determination is pending (no KRA endpoint invented)', ok, left(v, 160));
  SELECT count(*) INTO n FROM trustride.integration_outbound_request WHERE port_code = 'ETIMS_SERVICE';
  PERFORM pg_temp.t_check('eTIMS: nothing is ever sent towards KRA', n = 0, n::text);
  END IF;
END
$$;
