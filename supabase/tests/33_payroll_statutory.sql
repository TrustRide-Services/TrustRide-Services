-- Suite 33 -- payroll / PAYE statutory calculation as data (Construction Directive WP7, section 2.4).
-- Operators are employees. The statutory rates are versioned data with their sources, not code; the
-- calculator reproduces worked examples; the Affordable Housing Levy's PAYE deductibility is flagged for
-- professional confirmation, so no final figure is produced until it is confirmed (or the caller states the
-- treatment explicitly, which marks the result provisional).
DO $$
DECLARE
  founder UUID; admin UUID; r JSONB; v TEXT; ok BOOLEAN; s UUID; cmd JSONB;
  ready BOOLEAN := to_regprocedure('trustride.fn_business_payroll_calculate(numeric,date,boolean)') IS NOT NULL;
BEGIN
  IF NOT ready THEN
    PERFORM pg_temp.t_check('payroll statutory calculation exists', false, 'fn_business_payroll_calculate absent');
  ELSE
  founder := pg_temp.t_person('Pay Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  admin := pg_temp.t_person('Pay Admin', NULL);  PERFORM pg_temp.t_role(admin, 'ADMINISTRATOR');

  -- ============ rates are data with provenance
  SELECT set_id INTO s FROM trustride.business_payroll_statutory_set WHERE effective_from <= '2026-10-12' AND (effective_to IS NULL OR effective_to >= '2026-10-12');
  PERFORM pg_temp.t_check('payroll: one statutory set is in force, provisional until professionally confirmed',
    (SELECT status FROM trustride.business_payroll_statutory_set WHERE set_id = s) = 'PROVISIONAL', coalesce(s::text, 'none'));
  PERFORM pg_temp.t_check('payroll: every item carries its legal source', NOT EXISTS (
    SELECT 1 FROM trustride.business_payroll_statutory_item WHERE set_id = s AND coalesce(trim(source), '') = ''));
  PERFORM pg_temp.t_check('payroll: the Housing Levy''s PAYE deductibility is flagged UNCONFIRMED (not assumed)',
    (SELECT deductible_before_paye FROM trustride.business_payroll_statutory_item WHERE set_id = s AND item_code = 'AHL') = 'UNCONFIRMED');

  -- ============ no final figure while a treatment is unconfirmed
  BEGIN r := trustride.fn_business_payroll_calculate(50000, '2026-10-12'); ok := false; v := r::text;
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM LIKE 'PAYROLL_TREATMENT_UNCONFIRMED%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('payroll: without a stated Housing Levy treatment the calculator refuses', ok, left(v, 160));

  -- ============ worked examples (KES per month)
  r := trustride.fn_business_payroll_calculate(50000, '2026-10-12', TRUE);
  PERFORM pg_temp.t_check('payroll: 50,000 gross, levy deductible -> NSSF 3,000, SHIF 1,375, levy 750, taxable 44,875, PAYE 5,845.85, net 39,029.15',
    (r->>'nssf_employee')::numeric = 3000 AND (r->>'shif')::numeric = 1375 AND (r->>'ahl_employee')::numeric = 750
    AND (r->>'taxable_pay')::numeric = 44875 AND (r->>'paye')::numeric = 5845.85 AND (r->>'net_pay')::numeric = 39029.15, r::text);
  PERFORM pg_temp.t_check('payroll: a result using a stated (unconfirmed) treatment is provisional, never final',
    (r->>'final')::boolean = false AND r->>'status' = 'PROVISIONAL' AND r->'unconfirmed_choices' ? 'AHL', r::text);
  r := trustride.fn_business_payroll_calculate(50000, '2026-10-12', FALSE);
  PERFORM pg_temp.t_check('payroll: 50,000 gross, levy not deductible -> taxable 45,625, PAYE 6,070.85, net 38,804.15',
    (r->>'taxable_pay')::numeric = 45625 AND (r->>'paye')::numeric = 6070.85 AND (r->>'net_pay')::numeric = 38804.15, r::text);
  r := trustride.fn_business_payroll_calculate(20000, '2026-10-12', TRUE);
  PERFORM pg_temp.t_check('payroll: below the relief threshold PAYE is nil, never negative', (r->>'paye')::numeric = 0 AND (r->>'net_pay')::numeric = 17950, r::text);
  r := trustride.fn_business_payroll_calculate(10000, '2026-10-12', TRUE);
  PERFORM pg_temp.t_check('payroll: SHIF has its KES 300 minimum', (r->>'shif')::numeric = 300, r::text);
  r := trustride.fn_business_payroll_calculate(1000000, '2026-10-12', TRUE);
  PERFORM pg_temp.t_check('payroll: NSSF stops at the upper earnings limit (6,480) and all five bands apply (PAYE 292,740.35)',
    (r->>'nssf_employee')::numeric = 6480 AND (r->>'paye')::numeric = 292740.35, r::text);
  PERFORM pg_temp.t_check('payroll: the employer''s statutory costs are shown separately (NSSF 6,480 and levy 15,000 at 1,000,000)',
    (r->>'nssf_employer')::numeric = 6480 AND (r->>'ahl_employer')::numeric = 15000, r::text);
  PERFORM pg_temp.t_check('payroll: zero or negative pay is refused', pg_temp.t_fails('SELECT trustride.fn_business_payroll_calculate(0, ''2026-10-12'', TRUE)'));
  PERFORM pg_temp.t_check('payroll: a date with no statutory set in force is refused, never guessed',
    pg_temp.t_fails('SELECT trustride.fn_business_payroll_calculate(50000, ''2019-01-01'', TRUE)'));

  -- ============ the rates cannot be edited in place
  PERFORM pg_temp.t_check('payroll: a statutory rate cannot be edited in place (a change is a new set)',
    pg_temp.t_fails(format('UPDATE trustride.business_payroll_statutory_item SET rate = 0.05 WHERE set_id = %L AND item_code = ''NSSF''', s)));

  -- ============ professional confirmation, by the Founder only
  cmd := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'CONFIRM_PAYROLL_STATUTORY_SET',
    jsonb_build_object('set_id', s, 'ahl_deductible', true, 'confirmation_reference', 'Tax adviser opinion ref X'));
  PERFORM pg_temp.t_check('payroll: an Administrator cannot confirm the statutory set', coalesce(cmd->>'status', '') <> 'TRANSLATED', cmd::text);
  cmd := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'CONFIRM_PAYROLL_STATUTORY_SET',
    jsonb_build_object('set_id', s, 'ahl_deductible', true));
  PERFORM pg_temp.t_check('payroll: confirmation needs the professional''s reference', cmd->>'status' = 'REJECTED', cmd::text);
  cmd := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'CONFIRM_PAYROLL_STATUTORY_SET',
    jsonb_build_object('set_id', s, 'ahl_deductible', true, 'confirmation_reference', 'Tax adviser opinion ref X'));
  r := trustride.fn_business_payroll_calculate(50000, '2026-10-12');
  PERFORM pg_temp.t_check('payroll: once the Founder records the professional confirmation, results are final with no stated treatment',
    cmd->>'status' = 'TRANSLATED' AND (r->>'final')::boolean AND (r->>'paye')::numeric = 5845.85, cmd::text || ' ' || coalesce(r::text, ''));
  PERFORM pg_temp.t_check('payroll: the calculator is not callable by signed-in users directly',
    NOT has_function_privilege('authenticated', 'trustride.fn_business_payroll_calculate(numeric,date,boolean)', 'EXECUTE'));
  END IF;
END
$$;
