-- ============================================================================
-- TRS026 Construction Directive WP7 (section 2.4) -- KRA eTIMS as a separate
-- Engine 6 capability: sales and purchase invoices, statuses, reconciliation and
-- a simulator.
--
-- Founder decision 2.4: do not encode whether fares are taxable; no invented
-- KRA endpoint; no live activation without a legal determination. Therefore:
--   * every invoice records tax_treatment = UNDETERMINED (the only value allowed
--     until the determination) and an explicit amount basis (FULL_FARE,
--     COMMISSION or OTHER) chosen by the caller -- TrustRide computes no VAT;
--   * ETIMS_TAX_DETERMINATION = PENDING_LEGAL_DETERMINATION; outside the
--     simulator a sale is refused with ETIMS_TAX_DETERMINATION_PENDING;
--   * nothing is sent towards KRA (no gateway operation exists for eTIMS);
--   * the simulator no longer imitates KRA: its references are SIM-..., with no
--     QR code and no kra.go.ke link (defect: it minted "KRACU..." numbers and an
--     etims.kra.go.ke verification URL);
--   * no sale is issued automatically for settled orders: reconciliation reports
--     them until the determination says what to issue.
-- Purchases: supplier invoices TrustRide receives (with the supplier's control
-- unit number), recorded by the Office (RECORD_PURCHASE_INVOICE), once each.
-- ============================================================================

-- Legal and tax determination of what TrustRide issues on eTIMS for a fare (who, on which amount, which tax type).
-- Until the Founder sets it, no live eTIMS submission is possible and no tax treatment is assumed.
INSERT INTO trustride.platform_configuration (config_key, config_value, environment, effective_from, changed_by)
VALUES ('ETIMS_TAX_DETERMINATION', 'PENDING_LEGAL_DETERMINATION', 'ALL', now(), '00000000-0000-0000-0000-000000000000');

ALTER TABLE trustride.integration_etims_invoice_log
  ADD COLUMN direction TEXT NOT NULL DEFAULT 'SALE' CHECK (direction IN ('SALE', 'PURCHASE')),
  ADD COLUMN amount_basis TEXT NOT NULL DEFAULT 'UNSPECIFIED' CHECK (amount_basis IN ('FULL_FARE', 'COMMISSION', 'OTHER', 'UNSPECIFIED', 'SUPPLIER_INVOICE')),
  ADD COLUMN tax_treatment TEXT NOT NULL DEFAULT 'UNDETERMINED' CHECK (tax_treatment = 'UNDETERMINED'),
  ADD COLUMN counterparty_pin TEXT,
  ADD COLUMN counterparty_name TEXT,
  ADD COLUMN invoice_date DATE,
  ADD COLUMN description TEXT,
  ADD COLUMN simulated BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN last_error TEXT,
  ADD COLUMN recorded_by UUID;

-- Simulated rows written before this migration carried an imitation KRA reference; mark them as simulations.
UPDATE trustride.integration_etims_invoice_log SET qr_code_data = NULL, cu_invoice_number = 'SIM-' || cu_invoice_number
WHERE adapter_type = 'SIMULATOR' AND cu_invoice_number LIKE 'KRACU%';

CREATE UNIQUE INDEX integration_etims_sale_once ON trustride.integration_etims_invoice_log (order_id, amount_basis)
  WHERE direction = 'SALE' AND status <> 'REJECTED' AND order_id IS NOT NULL;
CREATE UNIQUE INDEX integration_etims_purchase_once ON trustride.integration_etims_invoice_log (counterparty_pin, cu_invoice_number)
  WHERE direction = 'PURCHASE';
CREATE INDEX integration_etims_invoice_log_submitted_at ON trustride.integration_etims_invoice_log (submitted_at);

CREATE OR REPLACE FUNCTION trustride.fn_integration_etims_invoice_submit_simulate(p_amount_kes numeric, p_buyer_pin text)
 RETURNS TABLE(cu_invoice_number text, qr_code_data text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'extensions', 'pg_temp'
AS $function$
BEGIN
  -- A simulation never imitates a KRA artefact: no control-unit style number, no QR, no kra.go.ke link.
  RETURN QUERY SELECT 'SIM-' || to_char(now(), 'YYYYMMDD') || '-' || upper(encode(gen_random_bytes(4), 'hex')), NULL::text;
END;
$function$;

CREATE FUNCTION trustride.fn_integration_etims_sale_submit(p_order_id uuid, p_basis text, p_amount_kes numeric, p_buyer_pin text,
  p_buyer_name text, p_correlation_id uuid, p_simulate text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_sim RECORD;
  v_id UUID;
  v_existing RECORD;
  v_pin TEXT := nullif(upper(trim(coalesce(p_buyer_pin, ''))), '');
  v_reject BOOLEAN;
BEGIN
  IF p_amount_kes IS NULL OR p_amount_kes <= 0 THEN RAISE EXCEPTION 'eTIMS: the invoice amount must be positive'; END IF;
  IF v_pin IS NOT NULL AND v_pin !~ '^[AP][0-9]{9}[A-Z]$' THEN RAISE EXCEPTION 'eTIMS: % is not a KRA PIN (letter, 9 digits, letter)', v_pin; END IF;
  IF trustride.fn_integration_adapter_mode('ETIMS_SERVICE') <> 'SIMULATOR'
     AND coalesce(trustride.fn_business_config('ETIMS_TAX_DETERMINATION'), 'PENDING_LEGAL_DETERMINATION') = 'PENDING_LEGAL_DETERMINATION' THEN
    RAISE EXCEPTION 'ETIMS_TAX_DETERMINATION_PENDING: no eTIMS invoice is submitted to KRA until the Founder records the legal and tax determination';
  END IF;
  PERFORM trustride.fn_integration_port_assert_simulated('ETIMS_SERVICE');

  IF p_order_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM trustride.integration_etims_invoice_log
    WHERE direction = 'SALE' AND order_id = p_order_id AND amount_basis = p_basis AND status <> 'REJECTED';
    IF v_existing.etims_invoice_id IS NOT NULL THEN
      IF v_existing.amount_kes = p_amount_kes THEN RETURN v_existing.etims_invoice_id; END IF;
      RAISE EXCEPTION 'eTIMS: order % already has a % invoice of KES % -- a correction is a credit note, not an edit', p_order_id, p_basis, v_existing.amount_kes;
    END IF;
  END IF;
  IF trustride.fn_integration_circuit_check('ETIMS_SERVICE') = 'OPEN' THEN
    RAISE EXCEPTION 'eTIMS: ETIMS_SERVICE circuit is OPEN';
  END IF;

  v_reject := p_simulate = 'SIMULATE_REJECT';
  SELECT * INTO v_sim FROM trustride.fn_integration_etims_invoice_submit_simulate(p_amount_kes, v_pin);
  PERFORM trustride.fn_integration_circuit_record_result('ETIMS_SERVICE', TRUE, 500);
  INSERT INTO trustride.integration_etims_invoice_log (order_id, amount_kes, buyer_pin, cu_invoice_number, qr_code_data, status, adapter_type,
    correlation_id, direction, amount_basis, counterparty_pin, counterparty_name, invoice_date, simulated, last_error)
  VALUES (p_order_id, p_amount_kes, v_pin, CASE WHEN v_reject THEN NULL ELSE v_sim.cu_invoice_number END, NULL,
    CASE WHEN v_reject THEN 'REJECTED' ELSE 'ACCEPTED' END::trustride.integration_etims_invoice_status_enum, 'SIMULATOR',
    p_correlation_id, 'SALE', p_basis, v_pin, nullif(trim(coalesce(p_buyer_name, '')), ''), (now() AT TIME ZONE 'Africa/Nairobi')::date, TRUE,
    CASE WHEN v_reject THEN 'SIMULATED_REJECTION: the simulator was asked to reject this submission' END)
  RETURNING etims_invoice_id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE FUNCTION trustride.fn_integration_etims_sale_record(p_order_id uuid, p_basis text, p_amount_kes numeric, p_buyer_pin text,
  p_buyer_name text, p_simulate text DEFAULT NULL, p_correlation_id uuid DEFAULT NULL)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF p_basis IS NULL OR p_basis NOT IN ('FULL_FARE', 'COMMISSION', 'OTHER') THEN
    RAISE EXCEPTION 'eTIMS: the amount basis must be stated (FULL_FARE, COMMISSION or OTHER) -- TrustRide assumes none (got %)', coalesce(p_basis, 'nothing');
  END IF;
  RETURN trustride.fn_integration_etims_sale_submit(p_order_id, p_basis, p_amount_kes, p_buyer_pin, p_buyer_name, p_correlation_id, p_simulate);
END;
$function$;

-- The original entry point keeps its signature; its basis was never stated, so it is recorded as UNSPECIFIED.
CREATE OR REPLACE FUNCTION trustride.fn_integration_etims_invoice_submit(p_order_id uuid, p_amount_kes numeric, p_buyer_pin text DEFAULT NULL::text, p_correlation_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'extensions', 'pg_temp'
AS $function$
BEGIN
  RETURN trustride.fn_integration_etims_sale_submit(p_order_id, 'UNSPECIFIED', p_amount_kes, p_buyer_pin, NULL, p_correlation_id, NULL);
END;
$function$;

CREATE FUNCTION trustride.fn_integration_etims_purchase_record(p_supplier_pin text, p_supplier_name text, p_cu_invoice_number text,
  p_invoice_date date, p_amount_kes numeric, p_description text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_by UUID := auth.uid();
  v_pin TEXT := upper(trim(coalesce(p_supplier_pin, '')));
  v_cu TEXT := upper(trim(coalesce(p_cu_invoice_number, '')));
  v_id UUID;
BEGIN
  IF v_by IS NOT NULL AND NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN
    RAISE EXCEPTION 'Only the Office records supplier invoices';
  END IF;
  IF v_pin !~ '^[AP][0-9]{9}[A-Z]$' THEN RAISE EXCEPTION 'eTIMS: % is not a KRA PIN (letter, 9 digits, letter)', v_pin; END IF;
  IF length(v_cu) < 5 OR v_cu !~ '^[A-Z0-9/-]+$' THEN RAISE EXCEPTION 'eTIMS: the supplier''s control unit invoice number is required as printed on the invoice'; END IF;
  IF coalesce(trim(p_supplier_name), '') = '' THEN RAISE EXCEPTION 'eTIMS: the supplier name is required'; END IF;
  IF p_amount_kes IS NULL OR p_amount_kes <= 0 THEN RAISE EXCEPTION 'eTIMS: the invoice amount must be positive'; END IF;
  IF p_invoice_date IS NULL OR p_invoice_date > (now() AT TIME ZONE 'Africa/Nairobi')::date THEN RAISE EXCEPTION 'eTIMS: the invoice date is required and cannot be in the future'; END IF;
  IF EXISTS (SELECT 1 FROM trustride.integration_etims_invoice_log WHERE direction = 'PURCHASE' AND counterparty_pin = v_pin AND cu_invoice_number = v_cu) THEN
    RAISE EXCEPTION 'eTIMS: supplier invoice % from % is already recorded', v_cu, v_pin;
  END IF;
  INSERT INTO trustride.integration_etims_invoice_log (order_id, amount_kes, buyer_pin, cu_invoice_number, status, adapter_type,
    direction, amount_basis, counterparty_pin, counterparty_name, invoice_date, description, simulated, recorded_by)
  VALUES (NULL, p_amount_kes, NULL, v_cu, 'RECEIVED', 'SIMULATOR', 'PURCHASE', 'SUPPLIER_INVOICE', v_pin, trim(p_supplier_name),
    p_invoice_date, nullif(trim(coalesce(p_description, '')), ''), FALSE, v_by)
  RETURNING etims_invoice_id INTO v_id;
  PERFORM trustride.fn_audit_log_append('integration_etims_invoice_log', v_id, 'ETIMS_PURCHASE_RECORDED', v_by, CASE WHEN v_by IS NULL THEN 'SYSTEM' ELSE 'USER' END,
    NULL, 'TRUSTRIDE_OFFICE', NULL, jsonb_build_object('supplier_pin', v_pin, 'cu_invoice_number', v_cu, 'amount_kes', p_amount_kes));
  RETURN v_id;
END;
$function$;

CREATE FUNCTION trustride.fn_integration_etims_reconcile(p_from date, p_to date)
 RETURNS TABLE(finding text, etims_invoice_id uuid, order_id uuid, amount_kes numeric, detail text)
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
  -- Sale invoices whose order is not settled.
  SELECT 'INVOICE_WITHOUT_SETTLEMENT', l.etims_invoice_id, l.order_id, l.amount_kes, 'basis ' || l.amount_basis
  FROM trustride.integration_etims_invoice_log l
  WHERE l.direction = 'SALE' AND l.status <> 'REJECTED' AND l.submitted_at::date BETWEEN p_from AND p_to
    AND NOT EXISTS (SELECT 1 FROM trustride.business_settlement s WHERE s.order_id = l.order_id AND s.settled_at IS NOT NULL)
  UNION ALL
  -- Rejected submissions still to be resolved.
  SELECT 'REJECTED_INVOICE', l.etims_invoice_id, l.order_id, l.amount_kes, coalesce(l.last_error, 'rejected')
  FROM trustride.integration_etims_invoice_log l
  WHERE l.direction = 'SALE' AND l.status = 'REJECTED' AND l.submitted_at::date BETWEEN p_from AND p_to
  UNION ALL
  -- Full-fare invoices whose amount differs from the settled fare.
  SELECT 'AMOUNT_MISMATCH', l.etims_invoice_id, l.order_id, l.amount_kes, 'settled KES ' || s.computed_total_fare_kes
  FROM trustride.integration_etims_invoice_log l JOIN trustride.business_settlement s ON s.order_id = l.order_id AND s.settled_at IS NOT NULL
  WHERE l.direction = 'SALE' AND l.status <> 'REJECTED' AND l.amount_basis = 'FULL_FARE' AND l.amount_kes <> s.computed_total_fare_kes
    AND l.submitted_at::date BETWEEN p_from AND p_to
  UNION ALL
  -- Settled orders with no sale invoice (report only: what to issue awaits the determination).
  SELECT 'SETTLEMENT_WITHOUT_INVOICE', NULL::uuid, s.order_id, s.computed_total_fare_kes, 'settled ' || s.settled_at::date
  FROM trustride.business_settlement s
  WHERE s.settled_at::date BETWEEN p_from AND p_to
    AND NOT EXISTS (SELECT 1 FROM trustride.integration_etims_invoice_log l WHERE l.order_id = s.order_id AND l.direction = 'SALE');
$function$;

CREATE FUNCTION trustride.fn_present_cmd_record_purchase_invoice(p_session uuid, p_payload jsonb, p_command uuid)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'trustride', 'public'
AS $function$
BEGIN
  RETURN trustride.fn_integration_etims_purchase_record(p_payload->>'supplier_pin', p_payload->>'supplier_name', p_payload->>'cu_invoice_number',
    (p_payload->>'invoice_date')::date, (p_payload->>'amount_kes')::numeric, p_payload->>'description');
END;
$function$;
INSERT INTO trustride.present_shell_capability_registry (top_shell, sub_shell, command_type, permitted, requires_delegated_authority)
VALUES ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RECORD_PURCHASE_INVOICE', TRUE, FALSE);

UPDATE trustride.integration_port_registry SET
  consumers = 'Sales invoices (simulator; basis stated by the caller, tax treatment undetermined), supplier purchase invoices (Office), reconciliation against settlements',
  blocking_dependency = 'Legal and tax determination (ETIMS_TAX_DETERMINATION): who issues the eTIMS invoice for a TrustRide fare, on which amount (commission or full fare as agent) and with which tax type; then KRA eTIMS OSCU/VSCU onboarding, sandbox testing and certification against KRA''s published specification (from the eTIMS portal), and the gateway adapter. No KRA endpoint is assumed.'
WHERE port_code = 'ETIMS_SERVICE' AND active;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_integration_etims_reconcile(date, date) TO service_role;
SELECT trustride.fn_platform_conformance_assert();
