-- ============================================================================
-- TRS026 Construction Directive WP7 (section 2.4) -- payroll / PAYE as a
-- capability separate from eTIMS. Operators are employees (section 4); Engine 4
-- (Business) owns pay and payouts, so it owns the statutory calculation.
--
-- The statutory rates are versioned data with their legal sources, never code:
--   business_payroll_statutory_set   one set per period in force; PROVISIONAL until
--                                    the Founder records a professional confirmation
--   business_payroll_statutory_item  PAYE bands, personal relief, NSSF, SHIF and the
--                                    Affordable Housing Levy; immutable (a change is a
--                                    new set)
--   fn_business_payroll_calculate    monthly gross -> employee deductions, PAYE, net
--                                    pay and the employer's statutory costs
--
-- Whether the Housing Levy is deductible before PAYE is UNCONFIRMED: published
-- sources conflict. The calculator refuses unless the caller states the
-- treatment (the result is then PROVISIONAL), or the Founder has recorded the
-- professional confirmation (CONFIRM_PAYROLL_STATUTORY_SET), after which results
-- are final. No payroll run, P10 return or bank file is built: those need the
-- payroll model (who is paid what, when) decided first.
--
-- Rates in force from 1 February 2026 (to be confirmed by a payroll professional):
--   PAYE monthly bands (Income Tax Act, Third Schedule, as amended by the Finance Act 2023):
--     10% to 24,000; 25% to 32,333; 30% to 500,000; 32.5% to 800,000; 35% above
--   personal relief KES 2,400 a month (Income Tax Act s.30)
--   NSSF 6% employee + 6% employer of pensionable pay up to the upper earnings
--     limit KES 108,000 (NSSF Act 2013, year-4 limits from February 2026)
--   SHIF 2.75% of gross, minimum KES 300 (Social Health Insurance Act 2023)
--   Affordable Housing Levy 1.5% employee + 1.5% employer (Affordable Housing Act 2024)
--   NSSF and SHIF deductible before PAYE (Tax Laws (Amendment) Act 2024)
-- ============================================================================

CREATE TABLE trustride.business_payroll_statutory_set (
  set_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  label TEXT NOT NULL,
  effective_from DATE NOT NULL,
  effective_to DATE,
  status TEXT NOT NULL DEFAULT 'PROVISIONAL' CHECK (status IN ('PROVISIONAL', 'CONFIRMED')),
  ahl_deductible_confirmed BOOLEAN,
  confirmation_reference TEXT,
  confirmed_by UUID,
  confirmed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (effective_to IS NULL OR effective_to >= effective_from),
  CHECK (status = 'PROVISIONAL' OR (ahl_deductible_confirmed IS NOT NULL AND confirmation_reference IS NOT NULL AND confirmed_by IS NOT NULL))
);
ALTER TABLE trustride.business_payroll_statutory_set ENABLE ROW LEVEL SECURITY;

CREATE TABLE trustride.business_payroll_statutory_item (
  item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  set_id UUID NOT NULL REFERENCES trustride.business_payroll_statutory_set(set_id),
  item_code TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('PAYE_BAND', 'RELIEF', 'CONTRIBUTION')),
  seq SMALLINT NOT NULL DEFAULT 1,
  upper_kes NUMERIC(18,2),
  rate NUMERIC(8,5),
  employer_rate NUMERIC(8,5),
  fixed_kes NUMERIC(18,2),
  minimum_kes NUMERIC(18,2),
  deductible_before_paye TEXT CHECK (deductible_before_paye IN ('YES', 'NO', 'UNCONFIRMED')),
  source TEXT NOT NULL,
  UNIQUE (set_id, item_code, seq)
);
ALTER TABLE trustride.business_payroll_statutory_item ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER trg_business_payroll_statutory_item_append_only BEFORE UPDATE OR DELETE ON trustride.business_payroll_statutory_item
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_platform_audit_chain_append_only();

-- A set may only move PROVISIONAL -> CONFIRMED (or be closed with effective_to); nothing else changes.
CREATE FUNCTION trustride.fn_business_payroll_statutory_set_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'A statutory payroll set is never deleted'; END IF;
  IF NEW.set_id <> OLD.set_id OR NEW.label <> OLD.label OR NEW.effective_from <> OLD.effective_from OR NEW.created_at <> OLD.created_at
     OR (OLD.effective_to IS NOT NULL AND NEW.effective_to IS DISTINCT FROM OLD.effective_to)
     OR (OLD.status = 'CONFIRMED' AND (NEW.status, NEW.ahl_deductible_confirmed, NEW.confirmation_reference, NEW.confirmed_by, NEW.confirmed_at)
                                    IS DISTINCT FROM (OLD.status, OLD.ahl_deductible_confirmed, OLD.confirmation_reference, OLD.confirmed_by, OLD.confirmed_at)) THEN
    RAISE EXCEPTION 'A statutory payroll set only moves from PROVISIONAL to CONFIRMED or is closed; a change of rates is a new set';
  END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER trg_business_payroll_statutory_set_guard BEFORE UPDATE OR DELETE ON trustride.business_payroll_statutory_set
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_business_payroll_statutory_set_guard();

WITH s AS (
  INSERT INTO trustride.business_payroll_statutory_set (label, effective_from)
  VALUES ('Kenya statutory payroll from 1 February 2026 (NSSF year-4 limits)', '2026-02-01') RETURNING set_id
)
INSERT INTO trustride.business_payroll_statutory_item (set_id, item_code, kind, seq, upper_kes, rate, employer_rate, fixed_kes, minimum_kes, deductible_before_paye, source)
SELECT s.set_id, v.* FROM s, (VALUES
  ('PAYE', 'PAYE_BAND', 1::smallint, 24000::numeric, 0.10::numeric, NULL::numeric, NULL::numeric, NULL::numeric, NULL::text, 'Income Tax Act (Cap. 470) Third Schedule, monthly bands as amended by the Finance Act 2023'),
  ('PAYE', 'PAYE_BAND', 2, 32333, 0.25, NULL, NULL, NULL, NULL, 'Income Tax Act (Cap. 470) Third Schedule, monthly bands as amended by the Finance Act 2023'),
  ('PAYE', 'PAYE_BAND', 3, 500000, 0.30, NULL, NULL, NULL, NULL, 'Income Tax Act (Cap. 470) Third Schedule, monthly bands as amended by the Finance Act 2023'),
  ('PAYE', 'PAYE_BAND', 4, 800000, 0.325, NULL, NULL, NULL, NULL, 'Income Tax Act (Cap. 470) Third Schedule, monthly bands as amended by the Finance Act 2023'),
  ('PAYE', 'PAYE_BAND', 5, NULL, 0.35, NULL, NULL, NULL, NULL, 'Income Tax Act (Cap. 470) Third Schedule, monthly bands as amended by the Finance Act 2023'),
  ('PERSONAL_RELIEF', 'RELIEF', 1, NULL, NULL, NULL, 2400, NULL, NULL, 'Income Tax Act (Cap. 470) s.30: personal relief KES 28,800 a year'),
  ('NSSF', 'CONTRIBUTION', 1, 108000, 0.06, 0.06, NULL, NULL, 'YES', 'NSSF Act 2013 s.20 (6% employee + 6% employer of pensionable pay to the upper earnings limit; year-4 limit KES 108,000 from February 2026); deductible per Income Tax Act as amended'),
  ('SHIF', 'CONTRIBUTION', 1, NULL, 0.0275, NULL, NULL, 300, 'YES', 'Social Health Insurance Act 2023 and Regulations 2024 (2.75% of gross, minimum KES 300); deductible before PAYE per the Tax Laws (Amendment) Act 2024'),
  ('AHL', 'CONTRIBUTION', 1, NULL, 0.015, 0.015, NULL, NULL, 'UNCONFIRMED', 'Affordable Housing Act 2024 s.4 (1.5% employee + 1.5% employer of gross); PAYE deductibility: published sources conflict -- professional confirmation required')
) v(item_code, kind, seq, upper_kes, rate, employer_rate, fixed_kes, minimum_kes, deductible_before_paye, source);

CREATE FUNCTION trustride.fn_business_payroll_calculate(p_gross_kes numeric, p_on date DEFAULT (now() AT TIME ZONE 'Africa/Nairobi')::date, p_ahl_deductible boolean DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_set trustride.business_payroll_statutory_set;
  i RECORD;
  v_nssf NUMERIC := 0; v_nssf_er NUMERIC := 0; v_shif NUMERIC := 0; v_ahl NUMERIC := 0; v_ahl_er NUMERIC := 0;
  v_deductible NUMERIC := 0; v_taxable NUMERIC; v_tax NUMERIC := 0; v_lower NUMERIC := 0; v_relief NUMERIC := 0; v_paye NUMERIC;
  v_amount NUMERIC; v_treat TEXT; v_unconfirmed JSONB := '{}'::jsonb;
BEGIN
  IF p_gross_kes IS NULL OR p_gross_kes <= 0 THEN RAISE EXCEPTION 'payroll: gross pay must be positive'; END IF;
  SELECT * INTO v_set FROM trustride.business_payroll_statutory_set
  WHERE effective_from <= p_on AND (effective_to IS NULL OR effective_to >= p_on) ORDER BY effective_from DESC LIMIT 1;
  IF v_set.set_id IS NULL THEN RAISE EXCEPTION 'payroll: no statutory set is in force on % -- rates are never guessed', p_on; END IF;

  FOR i IN SELECT * FROM trustride.business_payroll_statutory_item WHERE set_id = v_set.set_id AND kind = 'CONTRIBUTION' LOOP
    v_amount := greatest(round(least(p_gross_kes, coalesce(i.upper_kes, p_gross_kes)) * i.rate, 2), coalesce(i.minimum_kes, 0));
    v_treat := i.deductible_before_paye;
    IF v_treat = 'UNCONFIRMED' THEN
      IF v_set.status = 'CONFIRMED' AND i.item_code = 'AHL' THEN
        v_treat := CASE WHEN v_set.ahl_deductible_confirmed THEN 'YES' ELSE 'NO' END;
      ELSIF i.item_code = 'AHL' AND p_ahl_deductible IS NOT NULL THEN
        v_treat := CASE WHEN p_ahl_deductible THEN 'YES' ELSE 'NO' END;
        v_unconfirmed := v_unconfirmed || jsonb_build_object(i.item_code, v_treat);
      ELSE
        RAISE EXCEPTION 'PAYROLL_TREATMENT_UNCONFIRMED: whether % is deductible before PAYE awaits professional confirmation -- state the treatment for a provisional figure', i.item_code;
      END IF;
    END IF;
    IF v_treat = 'YES' THEN v_deductible := v_deductible + v_amount; END IF;
    CASE i.item_code
      WHEN 'NSSF' THEN v_nssf := v_amount; v_nssf_er := round(least(p_gross_kes, coalesce(i.upper_kes, p_gross_kes)) * coalesce(i.employer_rate, 0), 2);
      WHEN 'SHIF' THEN v_shif := v_amount;
      WHEN 'AHL' THEN v_ahl := v_amount; v_ahl_er := round(p_gross_kes * coalesce(i.employer_rate, 0), 2);
      ELSE RAISE EXCEPTION 'payroll: unknown contribution % in the statutory set', i.item_code;
    END CASE;
  END LOOP;

  v_taxable := greatest(p_gross_kes - v_deductible, 0);
  FOR i IN SELECT * FROM trustride.business_payroll_statutory_item WHERE set_id = v_set.set_id AND kind = 'PAYE_BAND' ORDER BY seq LOOP
    EXIT WHEN v_taxable <= v_lower;
    v_tax := v_tax + (least(v_taxable, coalesce(i.upper_kes, v_taxable)) - v_lower) * i.rate;
    v_lower := coalesce(i.upper_kes, v_taxable);
  END LOOP;
  SELECT coalesce(sum(fixed_kes), 0) INTO v_relief FROM trustride.business_payroll_statutory_item WHERE set_id = v_set.set_id AND kind = 'RELIEF';
  v_paye := greatest(round(v_tax - v_relief, 2), 0);

  RETURN jsonb_build_object(
    'gross_pay', p_gross_kes, 'statutory_set_id', v_set.set_id, 'statutory_set', v_set.label,
    'nssf_employee', v_nssf, 'shif', v_shif, 'ahl_employee', v_ahl,
    'deductible_before_paye', v_deductible, 'taxable_pay', v_taxable, 'tax_before_relief', round(v_tax, 2), 'personal_relief', v_relief,
    'paye', v_paye, 'net_pay', round(p_gross_kes - v_nssf - v_shif - v_ahl - v_paye, 2),
    'nssf_employer', v_nssf_er, 'ahl_employer', v_ahl_er,
    'unconfirmed_choices', v_unconfirmed,
    'final', v_set.status = 'CONFIRMED' AND v_unconfirmed = '{}'::jsonb,
    'status', CASE WHEN v_set.status = 'CONFIRMED' AND v_unconfirmed = '{}'::jsonb THEN 'FINAL' ELSE 'PROVISIONAL' END);
END;
$function$;

CREATE FUNCTION trustride.fn_business_payroll_statutory_confirm(p_set_id uuid, p_ahl_deductible boolean, p_reference text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_by UUID := auth.uid();
BEGIN
  IF v_by IS NULL OR NOT trustride.fn_am_i_role(ARRAY['FOUNDER']) THEN
    RAISE EXCEPTION 'Only the Founder records the professional confirmation of statutory payroll rates';
  END IF;
  IF p_ahl_deductible IS NULL THEN RAISE EXCEPTION 'State whether the Housing Levy is deductible before PAYE'; END IF;
  IF coalesce(trim(p_reference), '') = '' THEN RAISE EXCEPTION 'The confirming professional''s reference (opinion, letter or KRA ruling) is required'; END IF;
  UPDATE trustride.business_payroll_statutory_set SET status = 'CONFIRMED', ahl_deductible_confirmed = p_ahl_deductible,
    confirmation_reference = trim(p_reference), confirmed_by = v_by, confirmed_at = now()
  WHERE set_id = p_set_id AND status = 'PROVISIONAL';
  IF NOT FOUND THEN RAISE EXCEPTION 'No provisional statutory set %', p_set_id; END IF;
  PERFORM trustride.fn_audit_log_append('business_payroll_statutory_set', p_set_id, 'PAYROLL_STATUTORY_SET_CONFIRMED', v_by, 'USER', NULL, 'TRUSTRIDE_OFFICE', NULL,
    jsonb_build_object('ahl_deductible', p_ahl_deductible, 'reference', trim(p_reference)));
  RETURN p_set_id;
END;
$function$;

CREATE FUNCTION trustride.fn_present_cmd_confirm_payroll_statutory_set(p_session uuid, p_payload jsonb, p_command uuid)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'trustride', 'public'
AS $function$
BEGIN
  RETURN trustride.fn_business_payroll_statutory_confirm((p_payload->>'set_id')::uuid, (p_payload->>'ahl_deductible')::boolean, p_payload->>'confirmation_reference');
END;
$function$;
INSERT INTO trustride.present_shell_capability_registry (top_shell, sub_shell, command_type, permitted, requires_delegated_authority)
VALUES ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'CONFIRM_PAYROLL_STATUTORY_SET', TRUE, FALSE);

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_business_payroll_calculate(numeric, date, boolean) TO service_role;
SELECT trustride.fn_platform_conformance_assert();
