-- Suite 12 -- Executive Assistant statutory rating method (Engine 5, added
-- alongside the established EA equation, which stays exactly as it was).
-- The customer's scope of engagement arrives as order lines -- labour by the
-- hour or by the day, travel, subsistence, disbursements -- and every line of
-- the result cites the Kenyan law (or the TrustRide policy) it rests on:
-- Regulation of Wages (General) Order as amended to L.N. 108/2026,
-- Employment Act 2007, Public Holidays Act (Cap. 110), contribution Acts.
-- Also: Flutterwave is gone from the payment rails (Engine 4).
DO $$
DECLARE
  cust UUID; n INT; total NUMERIC; s NUMERIC; e UUID; mon DATE; sat DATE;
BEGIN
  -- ============================ the established EA equation is untouched
  PERFORM pg_temp.t_check('the established EA equation (fn_cost_ea_labor_calculate, 12 arguments) is unchanged',
    (SELECT pronargs FROM pg_proc WHERE proname = 'fn_cost_ea_labor_calculate' AND pronamespace = 'trustride'::regnamespace) = 12
    AND obj_description('trustride.fn_cost_ea_labor_calculate'::regproc, 'pg_proc') LIKE 'Paradigm B:%');
  PERFORM pg_temp.t_check('the established EA rate card is unchanged (6 Kisumu trades, monthly figures as set)', (SELECT count(*) FROM trustride.cost_ea_rate
    WHERE active AND jurisdiction = 'KISUMU_COUNTY' AND statutory_monthly_min_kes IN (15200, 18500, 21000, 17500, 25000)) = 6);

  -- ============================ the law, as data
  SELECT count(*) INTO n FROM trustride.cost_legal_instrument;
  PERFORM pg_temp.t_check('legal instruments recorded (Wages Order, Employment Act, Public Holidays Act, NSSF, SHIF, Housing Levy, Income Tax)', n >= 7, n::text);
  SELECT count(*) INTO n FROM trustride.cost_labour_statutory_wage WHERE active;
  PERFORM pg_temp.t_check('First Schedule loaded: 15 occupations x 3 wage areas', n = 45, n::text);
  PERFORM pg_temp.t_check('cook, Cities: KES 19,491.33 / 936.88 / 175.46 (L.N. 108/2026)', EXISTS (SELECT 1 FROM trustride.cost_labour_statutory_wage
    WHERE active AND occupation_row = 2 AND wage_area_code = 'CITIES' AND monthly_kes = 19491.33 AND daily_kes = 936.88 AND hourly_kes = 175.46));
  PERFORM pg_temp.t_check('driver (cars and light vans), Cities: hourly KES 219.28', EXISTS (SELECT 1 FROM trustride.cost_labour_statutory_wage
    WHERE active AND occupation_row = 6 AND wage_area_code = 'CITIES' AND hourly_kes = 219.28));
  PERFORM pg_temp.t_check('general labourer, all other areas: monthly KES 9,628.07', EXISTS (SELECT 1 FROM trustride.cost_labour_statutory_wage
    WHERE active AND occupation_row = 1 AND wage_area_code = 'ALL_OTHER_AREAS' AND monthly_kes = 9628.07));
  SELECT count(*) INTO n FROM trustride.cost_ea_trade_occupation;
  PERFORM pg_temp.t_check('every EA trade is mapped to a gazetted occupation', n = 6, n::text);
  PERFORM pg_temp.t_check('every service zone has a statutory wage area', NOT EXISTS (SELECT 1 FROM trustride.cost_operational_zones z
    WHERE z.active AND NOT EXISTS (SELECT 1 FROM trustride.cost_labour_zone_wage_area m WHERE m.zone_id = z.zone_id)));
  PERFORM pg_temp.t_check('every rating rule, contribution, expense type and subsistence tier cites its basis',
    NOT EXISTS (SELECT 1 FROM trustride.cost_ea_rating_rule WHERE provision_code IS NULL)
    AND NOT EXISTS (SELECT 1 FROM trustride.cost_labour_oncost WHERE provision_code IS NULL)
    AND NOT EXISTS (SELECT 1 FROM trustride.cost_ea_expense_type WHERE provision_code IS NULL)
    AND NOT EXISTS (SELECT 1 FROM trustride.cost_ea_subsistence_rate WHERE provision_code IS NULL));

  -- ============================ rating from order lines (a working Monday, Kisumu Milimani)
  cust := pg_temp.t_customer('Rating Customer');
  mon := (date_trunc('week', now() AT TIME ZONE 'Africa/Nairobi') + interval '7 days')::date;
  DELETE FROM trustride.calendar_reference WHERE calendar_date BETWEEN mon - 3 AND mon + 10 AND day_type = 'PUBLIC_HOLIDAY';

  -- Chef, 6 hours from 10:00: 6 x 175.46 = 1,052.76; NSSF 6% 63.17; Housing Levy 1.5% 15.79; margin 25% 282.93.
  e := trustride.fn_cost_ea_engagement_rate('CERTIFIED_CHEF', 'EA-CHEF-GENERAL', 'KSM-MILIMANI-02', jsonb_build_array(
    jsonb_build_object('line_type', 'LABOUR', 'engagement_unit', 'HOURS', 'billed_hours', 6, 'start_at', (mon + time '10:00') AT TIME ZONE 'Africa/Nairobi')),
    cust, gen_random_uuid());
  SELECT total_kes INTO total FROM trustride.cost_ea_engagement_estimate WHERE estimate_id = e;
  PERFORM pg_temp.t_check('chef 6 h: worker paid the gazetted cook hourly rate', EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line
    WHERE estimate_id = e AND component_code = 'EA_WORKER_PAY_NORMAL' AND amount_kes = 1052.76));
  PERFORM pg_temp.t_check('chef 6 h: employer NSSF 63.17 and Housing Levy 15.79', EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line
      WHERE estimate_id = e AND component_code = 'EA_EMPLOYER_NSSF' AND amount_kes = 63.17)
    AND EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line WHERE estimate_id = e AND component_code = 'EA_EMPLOYER_HOUSING_LEVY' AND amount_kes = 15.79));
  PERFORM pg_temp.t_check('chef 6 h: KES 1,414.65', total = 1414.65, total::text);
  SELECT sum(amount_kes) INTO s FROM trustride.cost_ea_engagement_line WHERE estimate_id = e AND line_role = 'PRICE';
  PERFORM pg_temp.t_check('price lines add up to the total exactly', s = total, s::text || ' vs ' || total::text);
  PERFORM pg_temp.t_check('every line cites its legal or policy basis', NOT EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line WHERE estimate_id = e AND provision_code IS NULL));
  PERFORM pg_temp.t_check('worker deductions (NSSF, SHIF, Housing Levy) shown, not charged', (SELECT count(*) FROM trustride.cost_ea_engagement_line
    WHERE estimate_id = e AND line_role = 'WORKER_INFO' AND component_code IN ('EA_WORKER_DEDUCT_NSSF', 'EA_WORKER_DEDUCT_SHIF', 'EA_WORKER_DEDUCT_HOUSING_LEVY')) = 3);

  -- The established order-line format (origin zone + billed hours) is read as an hourly labour line.
  e := trustride.fn_cost_ea_engagement_rate('CERTIFIED_CHEF', 'EA-CHEF-GENERAL', 'KSM-MILIMANI-02',
    '[{"origin_zone_code":"KSM-MILIMANI-02","billed_hours":6}]'::jsonb, cust, gen_random_uuid());
  PERFORM pg_temp.t_check('an established order line (billed_hours) is rated as hourly labour', EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line
    WHERE estimate_id = e AND component_code IN ('EA_WORKER_PAY_NORMAL', 'EA_WORKER_PAY_NIGHT', 'EA_WORKER_PAY_REST_DAY_HOLIDAY')));

  -- Chauffeur, 10 hours from 07:00: 8 x 219.28 = 1,754.24; 2 overtime x 219.28 x 1.5 = 657.84.
  e := trustride.fn_cost_ea_engagement_rate('PROFESSIONAL_CHAUFFEUR', 'EA-DRIVING-GENERAL', 'KSM-MILIMANI-02', jsonb_build_array(
    jsonb_build_object('line_type', 'LABOUR', 'engagement_unit', 'HOURS', 'billed_hours', 10, 'start_at', (mon + time '07:00') AT TIME ZONE 'Africa/Nairobi')),
    cust, gen_random_uuid());
  PERFORM pg_temp.t_check('chauffeur 10 h: 8 normal hours at the gazetted driver rate', EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line
    WHERE estimate_id = e AND component_code = 'EA_WORKER_PAY_NORMAL' AND amount_kes = 1754.24));
  PERFORM pg_temp.t_check('chauffeur 10 h: hours beyond 8 at one and one-half times', EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line
    WHERE estimate_id = e AND component_code = 'EA_WORKER_PAY_OVERTIME' AND amount_kes = 657.84 AND multiplier = 1.50));

  -- Errand, 3 hours from 18:00: 1 day hour 161.34 + 2 night hours at the established night multiplier (1.5) = 484.02.
  e := trustride.fn_cost_ea_engagement_rate('PERSONAL_SHOPPER_ERRAND', 'EA-ERRANDS-GENERAL', 'KSM-MILIMANI-02', jsonb_build_array(
    jsonb_build_object('line_type', 'LABOUR', 'engagement_unit', 'HOURS', 'billed_hours', 3, 'start_at', (mon + time '18:00') AT TIME ZONE 'Africa/Nairobi')),
    cust, gen_random_uuid());
  PERFORM pg_temp.t_check('errand into the night: only the night hours carry the night rate', EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line
      WHERE estimate_id = e AND component_code = 'EA_WORKER_PAY_NORMAL' AND amount_kes = 161.34)
    AND EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line WHERE estimate_id = e AND component_code = 'EA_WORKER_PAY_NIGHT' AND amount_kes = 484.02));

  -- Representation (corporate representative), 2 days x 8 h: 2 x the gazetted daily rate 1,336.43 = 2,672.86; with travel, subsistence and a disbursement.
  e := trustride.fn_cost_ea_engagement_rate('CORPORATE_REPRESENTATIVE', 'EA-SHOPPING-REPRESENTATION_DELIVERY', 'KSM-MILIMANI-02', jsonb_build_array(
    jsonb_build_object('line_type', 'LABOUR', 'engagement_unit', 'DAYS', 'billed_days', 2, 'billed_hours', 8, 'start_at', (mon + time '09:00') AT TIME ZONE 'Africa/Nairobi'),
    jsonb_build_object('line_type', 'TRAVEL', 'distance_km', 8, 'mode', 'BODA_BODA', 'round_trip', true),
    jsonb_build_object('line_type', 'SUBSISTENCE', 'tier', 'OVER_12H_OVERNIGHT_NAIROBI_MOMBASA', 'quantity', 1),
    jsonb_build_object('line_type', 'DISBURSEMENT', 'description', 'Conference entry fee', 'estimated_kes', 200)),
    cust, gen_random_uuid());
  PERFORM pg_temp.t_check('2-day representation: two gazetted daily rates', EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line
    WHERE estimate_id = e AND component_code = 'EA_WORKER_PAY_DAILY' AND amount_kes = 2672.86 AND quantity = 2));
  PERFORM pg_temp.t_check('travel at TrustRide''s published boda tariff: (30 + 12 x 8) x 2 = 252', EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line
    WHERE estimate_id = e AND component_code = 'EA_TRAVEL' AND amount_kes = 252.00));
  PERFORM pg_temp.t_check('subsistence at least the Wages Order para 14 amount (KES 25, overnight Nairobi)', EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line
    WHERE estimate_id = e AND component_code = 'EA_SUBSISTENCE' AND amount_kes = 25.00));
  PERFORM pg_temp.t_check('disbursement passed through at cost, no margin', EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line
    WHERE estimate_id = e AND component_code = 'EA_DISBURSEMENT' AND amount_kes = 200.00 AND line_role = 'PRICE'));
  SELECT total_kes, platform_margin_kes INTO total, s FROM trustride.cost_ea_engagement_estimate WHERE estimate_id = e;
  PERFORM pg_temp.t_check('margin is charged on labour only (25% of 2,672.86 + 6% + 1.5%)', s = round((2672.86 + 160.37 + 40.09) * 0.25, 2), s::text);
  PERFORM pg_temp.t_check('total = labour + margin + travel + subsistence + disbursement',
    total = 2672.86 + 160.37 + 40.09 + round((2672.86 + 160.37 + 40.09) * 0.25, 2) + 252 + 25 + 200, total::text);

  e := trustride.fn_cost_ea_engagement_rate('CORPORATE_REPRESENTATIVE', 'EA-SHOPPING-REPRESENTATION_DELIVERY', 'KSM-MILIMANI-02', jsonb_build_array(
    jsonb_build_object('line_type', 'LABOUR', 'engagement_unit', 'DAYS', 'billed_days', 2, 'billed_hours', 10, 'start_at', (mon + time '09:00') AT TIME ZONE 'Africa/Nairobi')),
    cust, gen_random_uuid());
  PERFORM pg_temp.t_check('2 days x 10 h: 4 overtime hours x 250.38 x 1.5 = 1,502.28', EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line
    WHERE estimate_id = e AND component_code = 'EA_WORKER_PAY_OVERTIME' AND amount_kes = 1502.28));

  -- A Sunday (rest day) or public holiday: twice the rate (Wages Order para 6(1)(b)).
  sat := mon + 5;
  e := trustride.fn_cost_ea_engagement_rate('CORPORATE_REPRESENTATIVE', 'EA-SHOPPING-REPRESENTATION_DELIVERY', 'KSM-MILIMANI-02', jsonb_build_array(
    jsonb_build_object('line_type', 'LABOUR', 'engagement_unit', 'DAYS', 'billed_days', 2, 'billed_hours', 8, 'start_at', (sat + time '09:00') AT TIME ZONE 'Africa/Nairobi')),
    cust, gen_random_uuid());
  PERFORM pg_temp.t_check('Saturday + Sunday: Saturday at the daily rate, Sunday at twice it', EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line
      WHERE estimate_id = e AND component_code = 'EA_WORKER_PAY_DAILY' AND amount_kes = 1336.43)
    AND EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line WHERE estimate_id = e AND component_code = 'EA_WORKER_PAY_REST_DAY_HOLIDAY' AND amount_kes = 2672.86));
  INSERT INTO trustride.calendar_reference (calendar_date, day_type, description) VALUES (mon + 1, 'PUBLIC_HOLIDAY', 'Test holiday');
  e := trustride.fn_cost_ea_engagement_rate('CERTIFIED_CHEF', 'EA-CHEF-GENERAL', 'KSM-MILIMANI-02', jsonb_build_array(
    jsonb_build_object('line_type', 'LABOUR', 'engagement_unit', 'HOURS', 'billed_hours', 3, 'start_at', ((mon + 1) + time '10:00') AT TIME ZONE 'Africa/Nairobi')),
    cust, gen_random_uuid());
  PERFORM pg_temp.t_check('public holiday: 3 h x 175.46 x 2 = 1,052.76', EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line
    WHERE estimate_id = e AND component_code = 'EA_WORKER_PAY_REST_DAY_HOLIDAY' AND amount_kes = 1052.76 AND multiplier = 2.00));
  DELETE FROM trustride.calendar_reference WHERE calendar_date = mon + 1 AND description = 'Test holiday';

  -- Limits: a rest day in every seven (Employment Act s.27(2)); at most 12 hours a day; known line types only.
  PERFORM pg_temp.t_check('more than 6 consecutive days in one engagement is refused', pg_temp.t_fails(format(
    $q$SELECT trustride.fn_cost_ea_engagement_rate('CORPORATE_REPRESENTATIVE', 'EA-SHOPPING-REPRESENTATION_DELIVERY', 'KSM-MILIMANI-02',
       '[{"line_type":"LABOUR","engagement_unit":"DAYS","billed_days":7,"billed_hours":8}]'::jsonb, %L, gen_random_uuid())$q$, cust)));
  PERFORM pg_temp.t_check('more than 12 hours in a day is refused', pg_temp.t_fails(format(
    $q$SELECT trustride.fn_cost_ea_engagement_rate('CERTIFIED_CHEF', 'EA-CHEF-GENERAL', 'KSM-MILIMANI-02',
       '[{"line_type":"LABOUR","billed_hours":13}]'::jsonb, %L, gen_random_uuid())$q$, cust)));
  PERFORM pg_temp.t_check('an unknown line type is refused', pg_temp.t_fails(format(
    $q$SELECT trustride.fn_cost_ea_engagement_rate('CERTIFIED_CHEF', 'EA-CHEF-GENERAL', 'KSM-MILIMANI-02',
       '[{"line_type":"TIP","estimated_kes":500}]'::jsonb, %L, gen_random_uuid())$q$, cust)));
  PERFORM pg_temp.t_check('a scope with no labour line is refused', pg_temp.t_fails(format(
    $q$SELECT trustride.fn_cost_ea_engagement_rate('CERTIFIED_CHEF', 'EA-CHEF-GENERAL', 'KSM-MILIMANI-02',
       '[{"line_type":"DISBURSEMENT","estimated_kes":500}]'::jsonb, %L, gen_random_uuid())$q$, cust)));

  -- Independent-contractor basis: no employer contributions; 5% digital-marketplace withholding shown.
  UPDATE trustride.cost_ea_rating_rule SET value_text = 'INDEPENDENT_CONTRACTOR' WHERE rule_code = 'WORKER_ENGAGEMENT_BASIS';
  e := trustride.fn_cost_ea_engagement_rate('CERTIFIED_CHEF', 'EA-CHEF-GENERAL', 'KSM-MILIMANI-02', jsonb_build_array(
    jsonb_build_object('line_type', 'LABOUR', 'engagement_unit', 'HOURS', 'billed_hours', 6, 'start_at', (mon + time '10:00') AT TIME ZONE 'Africa/Nairobi')),
    cust, gen_random_uuid());
  PERFORM pg_temp.t_check('contractor basis: no employer contributions; 5% withholding (52.64) shown', NOT EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line
      WHERE estimate_id = e AND component_code LIKE 'EA_EMPLOYER_%')
    AND EXISTS (SELECT 1 FROM trustride.cost_ea_engagement_line WHERE estimate_id = e AND component_code = 'EA_WORKER_WITHHOLDING_TAX' AND amount_kes = 52.64));
  UPDATE trustride.cost_ea_rating_rule SET value_text = 'CASUAL_EMPLOYEE' WHERE rule_code = 'WORKER_ENGAGEMENT_BASIS';

  -- ============================ Flutterwave removed (Founder ruling 2026-10-08)
  PERFORM pg_temp.t_check('no FLUTTERWAVE payment rail remains', NOT EXISTS (SELECT 1 FROM pg_enum en JOIN pg_type t ON t.oid = en.enumtypid
    WHERE t.typname = 'business_payment_rail_enum' AND en.enumlabel = 'FLUTTERWAVE'));

  SELECT count(*) INTO n FROM trustride.fn_platform_conformance_violations();
  PERFORM pg_temp.t_check('platform conformance holds', n = 0, n::text);
END
$$;
