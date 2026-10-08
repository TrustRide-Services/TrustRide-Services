-- ============================================================================
-- Engine 5 (Cost) -- Executive Assistant statutory rating method (ADDED)
-- ============================================================================
-- Founder directive 2026-10-08: add how Executive Assistants are rated --
-- hourly, by shift, by the day, and the travel and other costs an engagement
-- may carry -- legally aligned and traceable, the customer giving the scope
-- of engagement as order lines exactly as for every other service.
--
-- Founder instruction (same day): nothing already established in Engine 5 is
-- touched -- it is the real deal for transport, courier and delivery. This
-- migration only CREATES new tables and two new functions. Established
-- objects are READ, never written: cost_ea_rate (the trade's margin, floor
-- and minimum hours), cost_ea_shift_multiplier (NIGHT), cost_rate (the
-- transport tariff, for travel lines), cost_registry and
-- cost_operational_zones. The established EA equation keeps quoting the live
-- order flow; whether it ever hands over to this method is a Founder decision.
--
-- The law applied (texts read 2026-10-08):
--   Regulation of Wages (General) Order, L.N. 120 of 1982, as amended to
--   L.N. 108 of 2026 (Kenya Law consolidation of 26 June 2026):
--     para 3 + First Schedule -- monthly, daily and hourly minimum rates per
--       occupation and wage area (daily/hourly INCLUSIVE of housing allowance);
--     para 5 -- normal week <= 52 h over six days (night work <= 60 h);
--     para 6(1)(a) overtime 1.5x; 6(1)(b) rest day/public holiday 2x;
--     para 6(3) -- normal + overtime <= 116 h in two weeks (night 144 h);
--     para 7 -- one whole rest day in each week;
--     para 14 -- subsistence and accommodation (safari) allowance when
--       working away from the principal area of employment.
--   Employment Act, 2007: s.2 casual employee; s.27(2) a rest day in every
--     seven days; s.37 conversion of casual engagement after an aggregate month.
--   Contributions (secondary sources, pending primary verification): NSSF Act
--     2013 (6% + 6%), Social Health Insurance Act 2023 (2.75%), Affordable
--     Housing Act 2024 (1.5% + 1.5%), Income Tax Act s.35 as amended by the
--     Tax Laws (Amendment) Act 2024 (5% digital-marketplace withholding).
--
-- The method (EA-STATUTORY-1.0.0), from the customer's order lines:
--   LABOUR lines   -- by the HOUR (minimum engagement of the trade applies) or
--                     by the DAY (1-6 days); worker pay = the gazetted hourly
--                     or daily minimum of the trade's occupation in the zone's
--                     wage area (+ any governed skill premium); per day: hours
--                     beyond 8 at 1.5x, night hours at the established NIGHT
--                     multiplier, Sundays and public holidays at 2x;
--                     employer contributions by engagement basis; platform
--                     margin (the trade's established margin) on labour only;
--                     the trade's established floor applies to labour.
--   TRAVEL lines   -- the worker's journey at TrustRide's own published
--                     transport tariff (base + per km, x2 for a return trip).
--   SUBSISTENCE    -- per Wages Order para 14 tier: at least the statutory
--                     amount (a TrustRide rate may be set above it).
--   ACCOMMODATION, DISBURSEMENT, MATERIALS -- at cost, on receipts, no margin.
-- Every line cites a provision_code. Worker deductions are shown, not charged.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. The law, as data
-- ----------------------------------------------------------------------------
CREATE TABLE trustride.cost_legal_instrument (
  instrument_code      TEXT PRIMARY KEY,
  title                TEXT NOT NULL,
  citation             TEXT NOT NULL,
  consolidated_as_at   DATE,
  source_url           TEXT NOT NULL,
  verification_status  TEXT NOT NULL CHECK (verification_status IN ('PRIMARY_TEXT_VERIFIED', 'SECONDARY_SOURCE_PENDING_VERIFICATION')),
  verified_on          DATE NOT NULL,
  notes                TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.cost_legal_instrument IS
  'Every Act, Order or Legal Notice Engine 5 rates against. verification_status separates law read in its official consolidated text from figures taken from secondary sources that still need the primary text.';

CREATE TABLE trustride.cost_legal_provision (
  provision_code   TEXT PRIMARY KEY,
  instrument_code  TEXT REFERENCES trustride.cost_legal_instrument (instrument_code),
  basis_type       TEXT NOT NULL CHECK (basis_type IN ('STATUTE', 'TRUSTRIDE_POLICY')),
  reference        TEXT NOT NULL,
  summary          TEXT NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (basis_type = 'TRUSTRIDE_POLICY' OR instrument_code IS NOT NULL)
);
COMMENT ON TABLE trustride.cost_legal_provision IS
  'The exact provision behind each rule and rated line. STATUTE rows cite an instrument; TRUSTRIDE_POLICY rows are TrustRide''s own governed choices, never presented as law, naming the statute they stay within.';

INSERT INTO trustride.cost_legal_instrument (instrument_code, title, citation, consolidated_as_at, source_url, verification_status, verified_on, notes) VALUES
  ('KE-LN120-1982-RWGO', 'Regulation of Wages (General) Order', 'Legal Notice 120 of 1982, as amended by L.N. 164 of 2024, L.N. 95 of 2026 and L.N. 108 of 2026',
   '2026-06-26', 'https://new.kenyalaw.org/akn/ke/act/ln/1982/120/eng@2026-06-26', 'PRIMARY_TEXT_VERIFIED', '2026-10-08',
   'First Schedule as substituted by L.N. 108/2026 s.2 (12% general increase announced 1 May 2026). Applies to all employees except the agricultural industry (para 2).'),
  ('KE-ACT11-2007-EMPLOYMENT', 'Employment Act', 'Act No. 11 of 2007', '2024-04-26',
   'https://new.kenyalaw.org/akn/ke/act/2007/11/eng@2024-04-26', 'PRIMARY_TEXT_VERIFIED', '2026-10-08', NULL),
  ('KE-CAP110-PUBLIC-HOLIDAYS', 'Public Holidays Act', 'Cap. 110, as amended by the Statute Law (Miscellaneous Amendments) Act, No. 3 of 2024', '2024-04-26',
   'https://new.kenyalaw.org/akn/ke/act/1912/21/eng@2024-04-26', 'PRIMARY_TEXT_VERIFIED', '2026-10-08',
   'Moon-dependent holidays (Idd-ul-Fitr) and one-off holidays declared by Gazette notice are added when gazetted.'),
  ('KE-ACT45-2013-NSSF', 'National Social Security Fund Act', 'Act No. 45 of 2013, Third Schedule (phased limits)', NULL,
   'https://assets.kpmg.com/content/dam/kpmgsites/ke/pdf/thought_leaderships/tax/2026/Phase-4-of-NSSF-Contribution-Rates-effective-February-2026.pdf.coredownload.inline.pdf',
   'SECONDARY_SOURCE_PENDING_VERIFICATION', '2026-10-08',
   'From February 2026: 6% employer + 6% employee of pensionable pay, lower limit KES 9,000, upper limit KES 108,000 a month. Limits are subject to pending Court of Appeal proceedings.'),
  ('KE-2023-SOCIAL-HEALTH-INSURANCE', 'Social Health Insurance Act', 'Social Health Insurance Act, 2023', NULL,
   'https://serrarigroup.com/kenya-statutory-deductions-2026-nssf-shif-paye-guide/', 'SECONDARY_SOURCE_PENDING_VERIFICATION', '2026-10-08',
   'SHIF: 2.75% of gross pay deducted from the employee (KES 300 monthly minimum); no employer rate.'),
  ('KE-2024-AFFORDABLE-HOUSING', 'Affordable Housing Act', 'Affordable Housing Act, 2024', NULL,
   'https://serrarigroup.com/kenya-statutory-deductions-2026-nssf-shif-paye-guide/', 'SECONDARY_SOURCE_PENDING_VERIFICATION', '2026-10-08',
   'Affordable Housing Levy: 1.5% of gross pay from the employee and 1.5% from the employer.'),
  ('KE-CAP470-INCOME-TAX', 'Income Tax Act', 'Cap. 470, section 35 as amended by the Tax Laws (Amendment) Act, 2024', NULL,
   'https://pwc.com/ke/en/pdf/key-changes-tax-amendment-tax-alert.pdf', 'SECONDARY_SOURCE_PENDING_VERIFICATION', '2026-10-08',
   'Withholding tax on payments made or facilitated by a digital marketplace operator: 5% to residents, 20% to non-residents.');

INSERT INTO trustride.cost_legal_provision (provision_code, instrument_code, basis_type, reference, summary) VALUES
  ('RWGO-P3-SCH1', 'KE-LN120-1982-RWGO', 'STATUTE', 'para 3 and First Schedule',
   'Basic minimum wage per occupation and wage area: monthly (exclusive of housing allowance), daily and hourly (inclusive of housing allowance).'),
  ('RWGO-P5', 'KE-LN120-1982-RWGO', 'STATUTE', 'para 5', 'Normal working week: not more than 52 hours over six days; night work not more than 60 hours.'),
  ('RWGO-P6-1A', 'KE-LN120-1982-RWGO', 'STATUTE', 'para 6(1)(a)', 'Overtime beyond normal hours at one and one-half times the normal hourly rate.'),
  ('RWGO-P6-1B', 'KE-LN120-1982-RWGO', 'STATUTE', 'para 6(1)(b)', 'Work on the normal rest day or a public holiday at twice the normal hourly rate.'),
  ('RWGO-P6-3', 'KE-LN120-1982-RWGO', 'STATUTE', 'para 6(3)', 'Normal plus overtime hours: not more than 116 in two consecutive weeks (144 for night work).'),
  ('RWGO-P7', 'KE-LN120-1982-RWGO', 'STATUTE', 'para 7', 'One whole rest day in each week.'),
  ('RWGO-P14', 'KE-LN120-1982-RWGO', 'STATUTE', 'para 14',
   'Subsistence and accommodation (safari) allowance for duty away from the principal area of employment, by duration and overnight stop.'),
  ('EA-S2-CASUAL', 'KE-ACT11-2007-EMPLOYMENT', 'STATUTE', 's.2 (definition)',
   'Casual employee: paid at the end of each day and not engaged for longer than twenty-four hours at a time.'),
  ('EA-S27-2', 'KE-ACT11-2007-EMPLOYMENT', 'STATUTE', 's.27(2)', 'At least one rest day in every period of seven days.'),
  ('EA-S37', 'KE-ACT11-2007-EMPLOYMENT', 'STATUTE', 's.37',
   'Casual work aggregating to a month of continuous working days (or work of three months or more) converts to a monthly-paid contract.'),
  ('PHA-SCHEDULE', 'KE-CAP110-PUBLIC-HOLIDAYS', 'STATUTE', 'Schedule, Part I, and the Sunday rule',
   'Part I holidays; a Part I holiday falling on a Sunday moves to the first following day that is not a public holiday.'),
  ('NSSF-CONTRIBUTION', 'KE-ACT45-2013-NSSF', 'STATUTE', 'Third Schedule', '6% employer and 6% employee of pensionable pay within the lower and upper earnings limits.'),
  ('SHIA-CONTRIBUTION', 'KE-2023-SOCIAL-HEALTH-INSURANCE', 'STATUTE', 'contribution rate', '2.75% of gross pay, deducted from the employee.'),
  ('AHA-LEVY', 'KE-2024-AFFORDABLE-HOUSING', 'STATUTE', 'Affordable Housing Levy', '1.5% of gross pay from the employee and 1.5% from the employer.'),
  ('ITA-S35-DIGITAL-MARKETPLACE', 'KE-CAP470-INCOME-TAX', 'STATUTE', 's.35',
   'Payments made or facilitated by a digital marketplace operator to a resident person: 5% withholding tax.'),
  ('TR-NIGHT-UPLIFT', NULL, 'TRUSTRIDE_POLICY', 'established EA shift multiplier (NIGHT)',
   'Hours between 19:00 and 06:00 carry the established NIGHT multiplier. More favourable to the worker than the Order, which sets no night premium.'),
  ('TR-DAILY-OVERTIME', 'KE-LN120-1982-RWGO', 'TRUSTRIDE_POLICY', 'within para 5 and para 6(1)(a)',
   'Hours beyond 8 in a day are paid at the statutory overtime rate (1.5x) -- earlier than the Order''s weekly threshold, so never less favourable.'),
  ('TR-MAX-HOURS-DAY', 'KE-LN120-1982-RWGO', 'TRUSTRIDE_POLICY', 'within para 6(3)', 'At most 12 hours in one day of engagement.'),
  ('TR-ENGAGEMENT-BASIS', 'KE-ACT11-2007-EMPLOYMENT', 'TRUSTRIDE_POLICY', 's.2 casual employee (pending Founder confirmation)',
   'Executive Assistants engaged per order as casual employees, paid for each day worked, employer contributions priced in. The alternative basis is INDEPENDENT_CONTRACTOR.'),
  ('TR-OCCUPATION-MAPPING', 'KE-LN120-1982-RWGO', 'TRUSTRIDE_POLICY', 'First Schedule occupations',
   'The gazetted occupation each TrustRide trade is paid as; where the Schedule has no exact occupation, the nearest one, pending Founder confirmation.'),
  ('TR-SKILL-PREMIUM', NULL, 'TRUSTRIDE_POLICY', 'governed rating card', 'An optional premium above the statutory minimum for a trade''s skill; never below the minimum.'),
  ('TR-PLATFORM-MARGIN', NULL, 'TRUSTRIDE_POLICY', 'established EA rate card (platform_margin_pct)', 'TrustRide''s platform margin, charged on labour only.'),
  ('TR-MIN-ENGAGEMENT', NULL, 'TRUSTRIDE_POLICY', 'established EA rate card (minimum_engagement_hours)', 'Minimum billable hours for an hourly booking of a trade.'),
  ('TR-FLOOR-PRICE', NULL, 'TRUSTRIDE_POLICY', 'established EA rate card (floor_price_kes)', 'Minimum price of the labour of a booking of a trade.'),
  ('TR-TRAVEL-TARIFF', NULL, 'TRUSTRIDE_POLICY', 'established transport tariff (cost_rate)',
   'The worker''s journey to and from the engagement, at TrustRide''s own published transport tariff for the mode: base fee plus per-km rate, per leg.'),
  ('TR-SUBSISTENCE-RATE', 'KE-LN120-1982-RWGO', 'TRUSTRIDE_POLICY', 'at least para 14',
   'Subsistence per tier: the TrustRide rate when set (pending Founder), never below the para 14 amount.'),
  ('TR-AT-COST', NULL, 'TRUSTRIDE_POLICY', 'disbursements',
   'Accommodation, out-of-pocket disbursements and materials: passed through at cost, on receipts, with no margin; the order-time figure is the customer''s estimate.');

-- ----------------------------------------------------------------------------
-- 2. Wage areas and the First Schedule (L.N. 108/2026), verbatim
-- ----------------------------------------------------------------------------
CREATE TABLE trustride.cost_labour_wage_area (
  wage_area_code  TEXT PRIMARY KEY CHECK (wage_area_code IN ('CITIES', 'FORMER_MUNICIPALITIES', 'ALL_OTHER_AREAS')),
  area_label      TEXT NOT NULL,
  provision_code  TEXT NOT NULL REFERENCES trustride.cost_legal_provision (provision_code),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO trustride.cost_labour_wage_area (wage_area_code, area_label, provision_code) VALUES
  ('CITIES', 'Nairobi, Mombasa, Kisumu, Nakuru and Eldoret Cities', 'RWGO-P3-SCH1'),
  ('FORMER_MUNICIPALITIES', 'All former municipalities and the town councils of Mavoko, Ruiru and Limuru', 'RWGO-P3-SCH1'),
  ('ALL_OTHER_AREAS', 'All other areas', 'RWGO-P3-SCH1');

CREATE TABLE trustride.cost_labour_zone_wage_area (
  zone_id         UUID PRIMARY KEY REFERENCES trustride.cost_operational_zones (zone_id),
  wage_area_code  TEXT NOT NULL REFERENCES trustride.cost_labour_wage_area (wage_area_code),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.cost_labour_zone_wage_area IS
  'The statutory wage area each service zone falls in. A zone without one cannot be rated -- refused, never guessed.';
INSERT INTO trustride.cost_labour_zone_wage_area (zone_id, wage_area_code)
SELECT zone_id, 'CITIES' FROM trustride.cost_operational_zones WHERE jurisdiction = 'KISUMU_COUNTY';   -- all lie within Kisumu City

CREATE TABLE trustride.cost_labour_statutory_wage (
  statutory_wage_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  occupation_row     SMALLINT NOT NULL CHECK (occupation_row BETWEEN 1 AND 15),
  occupation_label   TEXT NOT NULL,
  wage_area_code     TEXT NOT NULL REFERENCES trustride.cost_labour_wage_area (wage_area_code),
  monthly_kes        NUMERIC(18,2) NOT NULL CHECK (monthly_kes > 0),
  daily_kes          NUMERIC(18,2) NOT NULL CHECK (daily_kes > 0),
  hourly_kes         NUMERIC(18,2) NOT NULL CHECK (hourly_kes > 0),
  provision_code     TEXT NOT NULL REFERENCES trustride.cost_legal_provision (provision_code),
  effective_from     DATE NOT NULL,
  effective_to       DATE,
  active             BOOLEAN NOT NULL DEFAULT TRUE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_cost_labour_statutory_wage_active ON trustride.cost_labour_statutory_wage (occupation_row, wage_area_code) WHERE active;
COMMENT ON TABLE trustride.cost_labour_statutory_wage IS
  'The First Schedule of the Regulation of Wages (General) Order exactly as gazetted (L.N. 108/2026). A new Order adds rows and retires these; history is never edited.';

INSERT INTO trustride.cost_labour_statutory_wage (occupation_row, occupation_label, wage_area_code, monthly_kes, daily_kes, hourly_kes, provision_code, effective_from)
SELECT v.row_no, v.label, a.area, a.m, a.d, a.h, 'RWGO-P3-SCH1', DATE '2026-06-26'
FROM (VALUES
  (1, 'General labourer including cleaner, sweeper, gardener, children''s ayah, house servant, day watchman, messenger',
      18047.40, 868.44, 161.34, 16650.95, 797.80, 147.45, 9628.07, 487.94, 90.17),
  (2, 'Miner, stone cutter, turnboy, waiter, cook, logger, line cutter',
      19491.33, 936.88, 175.46, 17046.83, 828.55, 149.47, 11124.42, 549.91, 100.56),
  (3, 'Night watchman', 20133.72, 966.02, 181.64, 18665.88, 900.31, 165.26, 11483.43, 554.07, 105.90),
  (4, 'Machine attendant, sawmill sawyer, machine assistant, mass production machinist, shoe cutter, bakery worker, bakery assistant, tailors assistant',
      20454.86, 982.70, 188.47, 19034.56, 920.44, 166.86, 15427.97, 745.15, 138.66),
  (5, 'Machinist (made to measure), shoe upper preparer, chaplis maker, vehicle service worker (petrol and service stations), bakery plant hand, laundry operator, junior clerk, wheel tractor driver (light)',
      23350.21, 1125.23, 209.54, 21844.12, 1051.62, 175.65, 17859.17, 863.75, 161.34),
  (6, 'Printing machine operator, bakery machine operator, plywood machine operator, sawmill dresser, shop assistant, machine tool operator, dough maker, table hand baker or confectioner, copy typist, driver (cars and light vans)',
      24358.73, 1170.46, 219.28, 22481.83, 1080.47, 199.98, 18582.41, 892.89, 165.14),
  (7, 'Pattern designer (draughtsman), garment and dress cutter, single hand oven man, charge-hand baker, general clerk, telephone operator, receptionist, storekeeper',
      27796.51, 1336.43, 250.38, 25412.61, 1222.22, 201.35, 21668.18, 1038.68, 194.58),
  (8, 'Tailor, driver (medium sized vehicle)', 30634.69, 1474.32, 272.70, 28155.87, 1356.02, 250.74, 25105.72, 1225.84, 225.03),
  (9, 'Dyer, crawler tractor driver, salesman', 33820.24, 1621.95, 303.92, 31555.31, 1518.43, 282.67, 28479.38, 1367.54, 251.09),
  (10, 'Saw doctor, caretaker (buildings)', 37426.84, 1802.29, 336.69, 34947.96, 1682.74, 313.54, 32556.94, 1564.97, 291.10),
  (11, 'Cashier, driver (heavy commercial vehicles), salesman driver', 40724.23, 1960.60, 366.96, 38323.71, 1844.79, 346.42, 35932.75, 1727.26, 323.16),
  (12, 'Ungraded artisan', 24358.79, 1171.35, 219.28, 22481.83, 1080.47, 199.98, 18582.77, 892.89, 166.15),
  (13, 'Artisan Grade III', 30634.74, 1474.32, 272.64, 28155.87, 1356.02, 250.74, 25058.23, 1225.90, 225.15),
  (14, 'Artisan Grade II', 33087.44, 1592.27, 303.92, 31555.31, 1518.54, 282.67, 28479.38, 1367.06, 251.39),
  (15, 'Artisan Grade I', 40724.23, 1960.60, 366.96, 38323.71, 1844.79, 346.42, 35932.86, 1727.14, 323.27)
) AS v(row_no, label, cm, cd, ch, fm, fd, fh, om, od, oh)
CROSS JOIN LATERAL (VALUES ('CITIES', v.cm, v.cd, v.ch), ('FORMER_MUNICIPALITIES', v.fm, v.fd, v.fh), ('ALL_OTHER_AREAS', v.om, v.od, v.oh)) AS a(area, m, d, h);

-- ----------------------------------------------------------------------------
-- 3. Trades, rules, contributions, and the costs an engagement may carry
-- ----------------------------------------------------------------------------
CREATE TABLE trustride.cost_ea_trade_occupation (
  ea_skill_category  trustride.ea_skill_category_enum PRIMARY KEY,
  occupation_row     SMALLINT NOT NULL CHECK (occupation_row BETWEEN 1 AND 15),
  occupation_mapping TEXT NOT NULL,
  mapping_status     TEXT NOT NULL CHECK (mapping_status IN ('GAZETTED_OCCUPATION', 'NEAREST_OCCUPATION_PENDING_FOUNDER')),
  skill_premium_pct  NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (skill_premium_pct >= 0),
  provision_code     TEXT NOT NULL REFERENCES trustride.cost_legal_provision (provision_code),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.cost_ea_trade_occupation IS
  'The gazetted occupation (First Schedule row) each Executive Assistant trade is paid as, plus any governed skill premium above the statutory minimum.';
INSERT INTO trustride.cost_ea_trade_occupation (ea_skill_category, occupation_row, occupation_mapping, mapping_status, provision_code) VALUES
  ('PERSONAL_SHOPPER_ERRAND', 1, 'messenger', 'GAZETTED_OCCUPATION', 'TR-OCCUPATION-MAPPING'),
  ('HOUSE_MANAGER_DOMESTIC', 1, 'house servant / cleaner', 'GAZETTED_OCCUPATION', 'TR-OCCUPATION-MAPPING'),
  ('PATIENT_ELDER_CAREGIVER', 1, 'children''s ayah (the Schedule has no caregiver occupation)', 'NEAREST_OCCUPATION_PENDING_FOUNDER', 'TR-OCCUPATION-MAPPING'),
  ('CERTIFIED_CHEF', 2, 'cook', 'GAZETTED_OCCUPATION', 'TR-OCCUPATION-MAPPING'),
  ('PROFESSIONAL_CHAUFFEUR', 6, 'driver (cars and light vans)', 'GAZETTED_OCCUPATION', 'TR-OCCUPATION-MAPPING'),
  ('CORPORATE_REPRESENTATIVE', 7, 'general clerk / receptionist (the Schedule has no representative occupation)', 'NEAREST_OCCUPATION_PENDING_FOUNDER', 'TR-OCCUPATION-MAPPING');

CREATE TABLE trustride.cost_ea_rating_rule (
  rule_code       TEXT PRIMARY KEY,
  value_num       NUMERIC(10,2),
  value_text      TEXT,
  unit            TEXT NOT NULL,
  provision_code  TEXT NOT NULL REFERENCES trustride.cost_legal_provision (provision_code),
  status          TEXT NOT NULL DEFAULT 'IN_FORCE' CHECK (status IN ('IN_FORCE', 'PENDING_FOUNDER_CONFIRMATION')),
  description     TEXT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (value_num IS NOT NULL OR value_text IS NOT NULL)
);
INSERT INTO trustride.cost_ea_rating_rule (rule_code, value_num, value_text, unit, provision_code, status, description) VALUES
  ('NORMAL_HOURS_PER_DAY', 8, NULL, 'HOURS', 'TR-DAILY-OVERTIME', 'IN_FORCE', 'Hours of a day paid at the normal rate; the rest of the day is overtime.'),
  ('OVERTIME_MULTIPLIER', 1.50, NULL, 'MULTIPLIER', 'RWGO-P6-1A', 'IN_FORCE', 'Overtime hours at one and one-half times the normal hourly rate.'),
  ('REST_DAY_HOLIDAY_MULTIPLIER', 2.00, NULL, 'MULTIPLIER', 'RWGO-P6-1B', 'IN_FORCE', 'Work on a Sunday (the weekly rest day) or a public holiday at twice the normal rate.'),
  ('NIGHT_WINDOW', NULL, '19:00-06:00', 'LOCAL_TIME', 'TR-NIGHT-UPLIFT', 'IN_FORCE', 'Hours in this window carry the established NIGHT multiplier.'),
  ('MAX_HOURS_PER_DAY', 12, NULL, 'HOURS', 'TR-MAX-HOURS-DAY', 'IN_FORCE', 'Longest single day of engagement.'),
  ('MAX_DAYS_PER_ENGAGEMENT', 6, NULL, 'DAYS', 'EA-S27-2', 'IN_FORCE', 'Longest engagement in one order line: six days, then a rest day.'),
  ('DEFAULT_TRAVEL_MODE', NULL, 'BODA_BODA', 'ASSET_CLASS', 'TR-TRAVEL-TARIFF', 'IN_FORCE', 'Mode used for a travel line that names none.'),
  ('WORKER_ENGAGEMENT_BASIS', NULL, 'CASUAL_EMPLOYEE', 'BASIS', 'TR-ENGAGEMENT-BASIS', 'PENDING_FOUNDER_CONFIRMATION',
   'CASUAL_EMPLOYEE prices in employer NSSF and Housing Levy; INDEPENDENT_CONTRACTOR prices none and shows the 5% digital-marketplace withholding instead.');

CREATE TABLE trustride.cost_labour_oncost (
  component_code    TEXT PRIMARY KEY,
  side              TEXT NOT NULL CHECK (side IN ('EMPLOYER_CONTRIBUTION', 'WORKER_DEDUCTION', 'WORKER_WITHHOLDING')),
  rate_pct          NUMERIC(5,2) NOT NULL CHECK (rate_pct >= 0),
  applies_to_basis  TEXT NOT NULL CHECK (applies_to_basis IN ('CASUAL_EMPLOYEE', 'INDEPENDENT_CONTRACTOR')),
  provision_code    TEXT NOT NULL REFERENCES trustride.cost_legal_provision (provision_code),
  active            BOOLEAN NOT NULL DEFAULT TRUE,
  description       TEXT NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.cost_labour_oncost IS
  'Statutory contributions on an EA worker''s pay, itemised. EMPLOYER_CONTRIBUTION rows are part of the price; WORKER_DEDUCTION and WORKER_WITHHOLDING rows come out of the worker''s pay and are shown, never charged to the customer.';
INSERT INTO trustride.cost_labour_oncost (component_code, side, rate_pct, applies_to_basis, provision_code, description) VALUES
  ('EA_EMPLOYER_NSSF', 'EMPLOYER_CONTRIBUTION', 6.00, 'CASUAL_EMPLOYEE', 'NSSF-CONTRIBUTION', 'Employer NSSF contribution (within the monthly upper earnings limit).'),
  ('EA_EMPLOYER_HOUSING_LEVY', 'EMPLOYER_CONTRIBUTION', 1.50, 'CASUAL_EMPLOYEE', 'AHA-LEVY', 'Employer Affordable Housing Levy.'),
  ('EA_WORKER_DEDUCT_NSSF', 'WORKER_DEDUCTION', 6.00, 'CASUAL_EMPLOYEE', 'NSSF-CONTRIBUTION', 'Worker NSSF contribution.'),
  ('EA_WORKER_DEDUCT_SHIF', 'WORKER_DEDUCTION', 2.75, 'CASUAL_EMPLOYEE', 'SHIA-CONTRIBUTION', 'Worker SHIF contribution.'),
  ('EA_WORKER_DEDUCT_HOUSING_LEVY', 'WORKER_DEDUCTION', 1.50, 'CASUAL_EMPLOYEE', 'AHA-LEVY', 'Worker Affordable Housing Levy.'),
  ('EA_WORKER_WITHHOLDING_TAX', 'WORKER_WITHHOLDING', 5.00, 'INDEPENDENT_CONTRACTOR', 'ITA-S35-DIGITAL-MARKETPLACE', 'Digital-marketplace withholding tax on a resident contractor''s pay.');

CREATE TABLE trustride.cost_ea_expense_type (
  line_type           TEXT PRIMARY KEY CHECK (line_type IN ('TRAVEL', 'SUBSISTENCE', 'ACCOMMODATION', 'DISBURSEMENT', 'MATERIALS')),
  computation_method  TEXT NOT NULL CHECK (computation_method IN ('TRANSPORT_TARIFF', 'STATUTORY_TABLE', 'AT_COST_RECEIPTED')),
  margin_applies      BOOLEAN NOT NULL DEFAULT FALSE,
  provision_code      TEXT NOT NULL REFERENCES trustride.cost_legal_provision (provision_code),
  scope_fields        TEXT NOT NULL,
  description         TEXT NOT NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.cost_ea_expense_type IS
  'The costs an EA engagement may carry beyond labour, how each is reached, and the order-line fields the customer gives for it.';
INSERT INTO trustride.cost_ea_expense_type (line_type, computation_method, margin_applies, provision_code, scope_fields, description) VALUES
  ('TRAVEL', 'TRANSPORT_TARIFF', FALSE, 'TR-TRAVEL-TARIFF', 'distance_km, mode (optional), round_trip (optional)',
   'The worker''s journey to and from the engagement, at TrustRide''s published transport tariff (its margin is already in the tariff).'),
  ('SUBSISTENCE', 'STATUTORY_TABLE', FALSE, 'TR-SUBSISTENCE-RATE', 'tier, quantity',
   'Meals and incidentals when the worker is on duty away from their principal area (Wages Order para 14).'),
  ('ACCOMMODATION', 'AT_COST_RECEIPTED', FALSE, 'TR-AT-COST', 'description, estimated_kes', 'Lodging for an overnight engagement away from base, at cost.'),
  ('DISBURSEMENT', 'AT_COST_RECEIPTED', FALSE, 'TR-AT-COST', 'description, estimated_kes',
   'Out-of-pocket costs spent for the customer: parking, entry or document fees, purchases made on the customer''s behalf.'),
  ('MATERIALS', 'AT_COST_RECEIPTED', FALSE, 'TR-AT-COST', 'description, estimated_kes', 'Ingredients, cleaning materials and similar supplies bought for the job.');

CREATE TABLE trustride.cost_ea_subsistence_rate (
  tier_code            TEXT PRIMARY KEY,
  tier_label           TEXT NOT NULL,
  statutory_floor_kes  NUMERIC(18,2) NOT NULL CHECK (statutory_floor_kes >= 0),
  trustride_rate_kes   NUMERIC(18,2) CHECK (trustride_rate_kes IS NULL OR trustride_rate_kes >= statutory_floor_kes),
  provision_code       TEXT NOT NULL REFERENCES trustride.cost_legal_provision (provision_code),
  status               TEXT NOT NULL DEFAULT 'PENDING_FOUNDER_CONFIRMATION' CHECK (status IN ('IN_FORCE', 'PENDING_FOUNDER_CONFIRMATION')),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.cost_ea_subsistence_rate IS
  'Wages Order para 14 tiers. statutory_floor_kes is the gazetted amount (unrevised for decades); trustride_rate_kes, once the Founder sets it, is charged instead -- never below the floor.';
INSERT INTO trustride.cost_ea_subsistence_rate (tier_code, tier_label, statutory_floor_kes, provision_code) VALUES
  ('OVER_6H_UP_TO_12H', 'Duty away for more than six and up to twelve hours', 5.00, 'RWGO-P14'),
  ('OVER_12H_NO_OVERNIGHT', 'Duty away for more than twelve hours, no overnight stop', 10.00, 'RWGO-P14'),
  ('OVER_12H_OVERNIGHT_NAIROBI_MOMBASA', 'More than twelve hours with an overnight stop in the Nairobi Area or Mombasa', 25.00, 'RWGO-P14'),
  ('OVER_12H_OVERNIGHT_ELSEWHERE', 'More than twelve hours with an overnight stop elsewhere', 20.00, 'RWGO-P14'),
  ('OVERNIGHT_ACCOMMODATION_PROVIDED', 'An overnight stop where accommodation is provided', 10.00, 'RWGO-P14');

-- ----------------------------------------------------------------------------
-- 4. The rated engagement (its own record; fare_calculation is untouched)
-- ----------------------------------------------------------------------------
CREATE TABLE trustride.cost_ea_engagement_estimate (
  estimate_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id                    UUID,
  requester_user_id           UUID,
  ea_skill_category           trustride.ea_skill_category_enum NOT NULL,
  service_code                TEXT NOT NULL,
  zone_id                     UUID NOT NULL,
  jurisdiction                trustride.cost_jurisdiction_enum NOT NULL,
  wage_area_code              TEXT NOT NULL,
  occupation_row              SMALLINT NOT NULL,
  engagement_basis            TEXT NOT NULL,
  scope_lines                 JSONB NOT NULL,
  worker_pay_kes              NUMERIC(18,2) NOT NULL DEFAULT 0,
  employer_contributions_kes  NUMERIC(18,2) NOT NULL DEFAULT 0,
  platform_margin_kes         NUMERIC(18,2) NOT NULL DEFAULT 0,
  floor_adjustment_kes        NUMERIC(18,2) NOT NULL DEFAULT 0,
  travel_kes                  NUMERIC(18,2) NOT NULL DEFAULT 0,
  subsistence_kes             NUMERIC(18,2) NOT NULL DEFAULT 0,
  at_cost_kes                 NUMERIC(18,2) NOT NULL DEFAULT 0,
  total_kes                   NUMERIC(18,2) NOT NULL DEFAULT 0,
  method_version              TEXT NOT NULL DEFAULT 'EA-STATUTORY-1.0.0',
  correlation_id              UUID NOT NULL,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.cost_ea_engagement_estimate IS
  'An Executive Assistant engagement rated by the statutory method from the customer''s order lines. Totals are the sum of its PRICE lines.';

CREATE TABLE trustride.cost_ea_engagement_line (
  line_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  estimate_id     UUID NOT NULL REFERENCES trustride.cost_ea_engagement_estimate (estimate_id),
  order_line_no   SMALLINT,
  component_code  TEXT NOT NULL,
  description     TEXT,
  quantity        NUMERIC(10,2),
  unit            TEXT,
  rate_kes        NUMERIC(18,2),
  multiplier      NUMERIC(6,2) NOT NULL DEFAULT 1.00,
  amount_kes      NUMERIC(18,2) NOT NULL CHECK (amount_kes >= 0),
  line_role       TEXT NOT NULL CHECK (line_role IN ('PRICE', 'WORKER_INFO')),
  provision_code  TEXT NOT NULL REFERENCES trustride.cost_legal_provision (provision_code),
  sequence_no     SMALLINT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_cost_ea_engagement_line_estimate ON trustride.cost_ea_engagement_line (estimate_id, sequence_no);
COMMENT ON TABLE trustride.cost_ea_engagement_line IS
  'One rated term of an engagement, citing its provision. PRICE lines make the total; WORKER_INFO lines (deductions, withholding, net pay) explain the worker''s side.';

-- ----------------------------------------------------------------------------
-- 5. The method
-- ----------------------------------------------------------------------------
-- Hours of [p_start, p_start + p_hours) inside the night window.
CREATE FUNCTION trustride.fn_cost_ea_night_hours(p_start TIMESTAMPTZ, p_hours NUMERIC)
RETURNS NUMERIC
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_window TEXT := coalesce((SELECT value_text FROM trustride.cost_ea_rating_rule WHERE rule_code = 'NIGHT_WINDOW'), '19:00-06:00');
  v_from TIME := split_part(v_window, '-', 1)::time;
  v_to TIME := split_part(v_window, '-', 2)::time;
  v_end TIMESTAMPTZ := p_start + make_interval(secs => p_hours * 3600);
  v_day DATE;
  v_sec NUMERIC := 0;
BEGIN
  IF p_hours IS NULL OR p_hours <= 0 THEN RETURN 0; END IF;
  FOR v_day IN SELECT generate_series((p_start AT TIME ZONE 'Africa/Nairobi')::date - 1, (v_end AT TIME ZONE 'Africa/Nairobi')::date, interval '1 day')::date LOOP
    v_sec := v_sec + greatest(0, extract(epoch FROM least(v_end, ((v_day + 1) + v_to) AT TIME ZONE 'Africa/Nairobi')
                                                  - greatest(p_start, (v_day + v_from) AT TIME ZONE 'Africa/Nairobi')));
  END LOOP;
  RETURN round(v_sec / 3600.0, 2);
END;
$$;

CREATE FUNCTION trustride.fn_cost_ea_engagement_rate(
  p_ea_skill_category trustride.ea_skill_category_enum, p_service_code TEXT, p_service_zone_code TEXT,
  p_order_lines JSONB, p_requester_user_id UUID, p_correlation_id UUID, p_order_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_zone RECORD; v_rate RECORD; v_trade RECORD; v_wage RECORD; v_tier RECORD; v_tariff RECORD;
  v_basis TEXT; v_normal_day NUMERIC; v_ot NUMERIC; v_rest NUMERIC; v_night NUMERIC; v_max_h NUMERIC; v_max_d NUMERIC; v_mode TEXT;
  v_hourly NUMERIC(18,2); v_daily NUMERIC(18,2);
  v_est UUID; v_seq SMALLINT := 0; v_line JSONB; v_no INT; v_type TEXT; v_labour_lines INT := 0;
  v_unit TEXT; v_hours NUMERIC; v_days INT; v_start TIMESTAMPTZ; v_dates DATE[]; v_day DATE; v_day_start TIMESTAMPTZ;
  v_norm NUMERIC; v_over NUMERIC; v_night_norm NUMERIC; v_night_over NUMERIC;
  h_normal NUMERIC; a_normal NUMERIC; h_night NUMERIC; a_night NUMERIC; d_daily INT; a_daily NUMERIC;
  h_uplift NUMERIC; a_uplift NUMERIC; h_over NUMERIC; a_over NUMERIC; q_rest NUMERIC; a_rest NUMERIC;
  v_worker NUMERIC(18,2) := 0; v_employer NUMERIC(18,2) := 0; v_margin NUMERIC(18,2); v_floor_adj NUMERIC(18,2);
  v_travel NUMERIC(18,2) := 0; v_subs NUMERIC(18,2) := 0; v_atcost NUMERIC(18,2) := 0; v_deducted NUMERIC(18,2) := 0;
  v_km NUMERIC; v_legs INT; v_qty NUMERIC; v_amt NUMERIC(18,2); c RECORD;
BEGIN
  SELECT z.zone_id, z.jurisdiction, m.wage_area_code INTO v_zone FROM trustride.cost_operational_zones z
  LEFT JOIN trustride.cost_labour_zone_wage_area m ON m.zone_id = z.zone_id
  WHERE z.zone_code = p_service_zone_code AND z.active;
  IF v_zone.zone_id IS NULL THEN RAISE EXCEPTION 'fn_cost_ea_engagement_rate: unknown or inactive service zone %', p_service_zone_code; END IF;
  IF v_zone.wage_area_code IS NULL THEN RAISE EXCEPTION 'fn_cost_ea_engagement_rate: service zone % has no statutory wage area', p_service_zone_code; END IF;

  -- The established EA rate card supplies margin, floor and minimum engagement (read only).
  SELECT * INTO v_rate FROM trustride.cost_ea_rate WHERE ea_skill_category = p_ea_skill_category AND jurisdiction = v_zone.jurisdiction AND active;
  IF v_rate IS NULL THEN RAISE EXCEPTION 'fn_cost_ea_engagement_rate: no active EA rate card for % in %', p_ea_skill_category, v_zone.jurisdiction; END IF;
  IF NOT EXISTS (SELECT 1 FROM trustride.cost_registry WHERE macro_domain = 'EXECUTIVE_ASSISTANTS' AND service_code = p_service_code
                 AND asset_class = 'EXECUTIVE_ASSISTANT_HUMAN' AND jurisdiction = v_zone.jurisdiction AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'fn_cost_ea_engagement_rate: % is not a priced Executive Assistant service in %', p_service_code, v_zone.jurisdiction;
  END IF;
  SELECT * INTO v_trade FROM trustride.cost_ea_trade_occupation WHERE ea_skill_category = p_ea_skill_category;
  SELECT * INTO v_wage FROM trustride.cost_labour_statutory_wage WHERE occupation_row = v_trade.occupation_row AND wage_area_code = v_zone.wage_area_code AND active;
  IF v_wage IS NULL THEN RAISE EXCEPTION 'fn_cost_ea_engagement_rate: no gazetted minimum wage for % in %', p_ea_skill_category, v_zone.wage_area_code; END IF;

  SELECT max(value_num) FILTER (WHERE rule_code = 'NORMAL_HOURS_PER_DAY'), max(value_num) FILTER (WHERE rule_code = 'OVERTIME_MULTIPLIER'),
         max(value_num) FILTER (WHERE rule_code = 'REST_DAY_HOLIDAY_MULTIPLIER'), max(value_num) FILTER (WHERE rule_code = 'MAX_HOURS_PER_DAY'),
         max(value_num) FILTER (WHERE rule_code = 'MAX_DAYS_PER_ENGAGEMENT'), max(value_text) FILTER (WHERE rule_code = 'WORKER_ENGAGEMENT_BASIS'),
         max(value_text) FILTER (WHERE rule_code = 'DEFAULT_TRAVEL_MODE')
  INTO v_normal_day, v_ot, v_rest, v_max_h, v_max_d, v_basis, v_mode FROM trustride.cost_ea_rating_rule;
  v_night := coalesce((SELECT multiplier FROM trustride.cost_ea_shift_multiplier WHERE shift_type = 'NIGHT' AND active), 1.00);
  v_hourly := round(v_wage.hourly_kes * (1 + v_trade.skill_premium_pct / 100.0), 2);
  v_daily := round(v_wage.daily_kes * (1 + v_trade.skill_premium_pct / 100.0), 2);

  IF p_order_lines IS NULL OR jsonb_typeof(p_order_lines) <> 'array' OR jsonb_array_length(p_order_lines) = 0 THEN
    RAISE EXCEPTION 'fn_cost_ea_engagement_rate: the scope of engagement must be given as order lines';
  END IF;

  INSERT INTO trustride.cost_ea_engagement_estimate (order_id, requester_user_id, ea_skill_category, service_code, zone_id, jurisdiction,
    wage_area_code, occupation_row, engagement_basis, scope_lines, correlation_id)
  VALUES (p_order_id, p_requester_user_id, p_ea_skill_category, p_service_code, v_zone.zone_id, v_zone.jurisdiction,
    v_zone.wage_area_code, v_trade.occupation_row, v_basis, p_order_lines, p_correlation_id)
  RETURNING estimate_id INTO v_est;

  FOR v_line, v_no IN SELECT x, n::int FROM jsonb_array_elements(p_order_lines) WITH ORDINALITY AS t(x, n) LOOP
    v_line := coalesce(v_line->'scope_detail', '{}'::jsonb) || (v_line - 'scope_detail');   -- an order line or its scope_detail
    v_type := upper(coalesce(nullif(v_line->>'line_type', ''), CASE WHEN v_line ? 'billed_hours' THEN 'LABOUR' END, ''));

    IF v_type = 'LABOUR' THEN
      v_labour_lines := v_labour_lines + 1;
      v_unit := upper(coalesce(nullif(v_line->>'engagement_unit', ''), 'HOURS'));
      v_hours := (v_line->>'billed_hours')::numeric;
      IF v_unit NOT IN ('HOURS', 'DAYS') THEN RAISE EXCEPTION 'Line %: book by the hour or by the day', v_no; END IF;
      IF v_hours IS NULL OR v_hours <= 0 OR v_hours > v_max_h THEN
        RAISE EXCEPTION 'Line %: between 1 and % hours a day', v_no, v_max_h;
      END IF;
      IF v_unit = 'HOURS' THEN
        v_hours := greatest(v_hours, v_rate.minimum_engagement_hours);  v_days := 1;
      ELSE
        v_days := coalesce((v_line->>'billed_days')::int, 0);
        IF v_days < 1 OR v_days > v_max_d THEN
          RAISE EXCEPTION 'Line %: 1 to % days in one engagement -- a rest day in every seven (Employment Act s.27(2))', v_no, v_max_d;
        END IF;
      END IF;
      v_start := coalesce((v_line->>'start_at')::timestamptz, now());
      IF jsonb_typeof(v_line->'service_dates') = 'array' AND jsonb_array_length(v_line->'service_dates') = v_days THEN
        SELECT array_agg(x::date ORDER BY x::date) INTO v_dates FROM jsonb_array_elements_text(v_line->'service_dates') x;
      ELSE
        SELECT array_agg((v_start AT TIME ZONE 'Africa/Nairobi')::date + i) INTO v_dates FROM generate_series(0, v_days - 1) i;
      END IF;

      h_normal := 0; a_normal := 0; h_night := 0; a_night := 0; d_daily := 0; a_daily := 0;
      h_uplift := 0; a_uplift := 0; h_over := 0; a_over := 0; q_rest := 0; a_rest := 0;
      FOREACH v_day IN ARRAY v_dates LOOP
        v_day_start := (v_day + (v_start AT TIME ZONE 'Africa/Nairobi')::time) AT TIME ZONE 'Africa/Nairobi';
        v_norm := least(v_hours, v_normal_day);
        v_over := v_hours - v_norm;
        IF extract(isodow FROM v_day) = 7 OR EXISTS (SELECT 1 FROM trustride.calendar_reference WHERE calendar_date = v_day AND day_type = 'PUBLIC_HOLIDAY') THEN
          IF v_unit = 'DAYS' THEN
            q_rest := q_rest + 1;  a_rest := a_rest + v_daily * v_rest + v_over * v_hourly * v_rest;
          ELSE
            q_rest := q_rest + v_hours;  a_rest := a_rest + v_hours * v_hourly * v_rest;
          END IF;
        ELSE
          v_night_norm := trustride.fn_cost_ea_night_hours(v_day_start, v_norm);
          v_night_over := trustride.fn_cost_ea_night_hours(v_day_start + make_interval(secs => v_norm * 3600), v_over);
          IF v_unit = 'DAYS' THEN
            d_daily := d_daily + 1;  a_daily := a_daily + v_daily;
            h_uplift := h_uplift + v_night_norm;  a_uplift := a_uplift + v_night_norm * v_hourly * (v_night - 1);
          ELSE
            h_normal := h_normal + (v_norm - v_night_norm);  a_normal := a_normal + (v_norm - v_night_norm) * v_hourly;
            h_night := h_night + v_night_norm;  a_night := a_night + v_night_norm * v_hourly * v_night;
          END IF;
          h_over := h_over + v_over;
          a_over := a_over + (v_over - v_night_over) * v_hourly * v_ot + v_night_over * v_hourly * greatest(v_ot, v_night);
        END IF;
      END LOOP;

      a_normal := round(a_normal, 2); a_night := round(a_night, 2); a_daily := round(a_daily, 2);
      a_uplift := round(a_uplift, 2); a_over := round(a_over, 2); a_rest := round(a_rest, 2);
      v_worker := v_worker + a_normal + a_night + a_daily + a_uplift + a_over + a_rest;
      IF a_normal > 0 THEN v_seq := v_seq + 1;
        INSERT INTO trustride.cost_ea_engagement_line (estimate_id, order_line_no, component_code, quantity, unit, rate_kes, multiplier, amount_kes, line_role, provision_code, sequence_no)
        VALUES (v_est, v_no, 'EA_WORKER_PAY_NORMAL', h_normal, 'HOURS', v_hourly, 1.00, a_normal, 'PRICE', 'RWGO-P3-SCH1', v_seq); END IF;
      IF a_night > 0 THEN v_seq := v_seq + 1;
        INSERT INTO trustride.cost_ea_engagement_line (estimate_id, order_line_no, component_code, quantity, unit, rate_kes, multiplier, amount_kes, line_role, provision_code, sequence_no)
        VALUES (v_est, v_no, 'EA_WORKER_PAY_NIGHT', h_night, 'HOURS', v_hourly, v_night, a_night, 'PRICE', 'TR-NIGHT-UPLIFT', v_seq); END IF;
      IF a_daily > 0 THEN v_seq := v_seq + 1;
        INSERT INTO trustride.cost_ea_engagement_line (estimate_id, order_line_no, component_code, quantity, unit, rate_kes, multiplier, amount_kes, line_role, provision_code, sequence_no)
        VALUES (v_est, v_no, 'EA_WORKER_PAY_DAILY', d_daily, 'DAYS', v_daily, 1.00, a_daily, 'PRICE', 'RWGO-P3-SCH1', v_seq); END IF;
      IF a_uplift > 0 THEN v_seq := v_seq + 1;
        INSERT INTO trustride.cost_ea_engagement_line (estimate_id, order_line_no, component_code, quantity, unit, rate_kes, multiplier, amount_kes, line_role, provision_code, sequence_no)
        VALUES (v_est, v_no, 'EA_WORKER_NIGHT_UPLIFT', h_uplift, 'HOURS', v_hourly, v_night - 1, a_uplift, 'PRICE', 'TR-NIGHT-UPLIFT', v_seq); END IF;
      IF a_over > 0 THEN v_seq := v_seq + 1;
        INSERT INTO trustride.cost_ea_engagement_line (estimate_id, order_line_no, component_code, quantity, unit, rate_kes, multiplier, amount_kes, line_role, provision_code, sequence_no)
        VALUES (v_est, v_no, 'EA_WORKER_PAY_OVERTIME', h_over, 'HOURS', v_hourly, v_ot, a_over, 'PRICE', 'TR-DAILY-OVERTIME', v_seq); END IF;
      IF a_rest > 0 THEN v_seq := v_seq + 1;
        INSERT INTO trustride.cost_ea_engagement_line (estimate_id, order_line_no, component_code, quantity, unit, rate_kes, multiplier, amount_kes, line_role, provision_code, sequence_no)
        VALUES (v_est, v_no, 'EA_WORKER_PAY_REST_DAY_HOLIDAY', q_rest, CASE WHEN v_unit = 'DAYS' THEN 'DAYS' ELSE 'HOURS' END,
          CASE WHEN v_unit = 'DAYS' THEN v_daily ELSE v_hourly END, v_rest, a_rest, 'PRICE', 'RWGO-P6-1B', v_seq); END IF;

    ELSIF v_type = 'TRAVEL' THEN
      v_km := (v_line->>'distance_km')::numeric;
      IF v_km IS NULL OR v_km <= 0 THEN RAISE EXCEPTION 'Line %: give the travel distance in km', v_no; END IF;
      SELECT * INTO v_tariff FROM trustride.cost_rate WHERE asset_class::text = upper(coalesce(nullif(v_line->>'mode', ''), v_mode)) AND active
      ORDER BY direct_per_km_rate_kes LIMIT 1;
      IF v_tariff IS NULL THEN RAISE EXCEPTION 'Line %: no published transport tariff for %', v_no, coalesce(v_line->>'mode', v_mode); END IF;
      v_legs := CASE WHEN coalesce((v_line->>'round_trip')::boolean, false) THEN 2 ELSE 1 END;
      v_amt := round((v_tariff.base_dispatch_fee_kes + v_tariff.direct_per_km_rate_kes * v_km) * v_legs, 2);
      v_travel := v_travel + v_amt;  v_seq := v_seq + 1;
      INSERT INTO trustride.cost_ea_engagement_line (estimate_id, order_line_no, component_code, description, quantity, unit, rate_kes, multiplier, amount_kes, line_role, provision_code, sequence_no)
      VALUES (v_est, v_no, 'EA_TRAVEL', v_tariff.asset_class::text || ': base ' || v_tariff.base_dispatch_fee_kes || ' + ' || v_tariff.direct_per_km_rate_kes || '/km',
        v_km, 'KM', v_tariff.direct_per_km_rate_kes, v_legs, v_amt, 'PRICE', 'TR-TRAVEL-TARIFF', v_seq);

    ELSIF v_type = 'SUBSISTENCE' THEN
      SELECT * INTO v_tier FROM trustride.cost_ea_subsistence_rate WHERE tier_code = upper(v_line->>'tier');
      IF v_tier IS NULL THEN RAISE EXCEPTION 'Line %: choose a subsistence tier', v_no; END IF;
      v_qty := coalesce((v_line->>'quantity')::numeric, 1);
      IF v_qty <= 0 THEN RAISE EXCEPTION 'Line %: subsistence quantity must be positive', v_no; END IF;
      v_amt := round(coalesce(v_tier.trustride_rate_kes, v_tier.statutory_floor_kes) * v_qty, 2);
      v_subs := v_subs + v_amt;  v_seq := v_seq + 1;
      INSERT INTO trustride.cost_ea_engagement_line (estimate_id, order_line_no, component_code, description, quantity, unit, rate_kes, multiplier, amount_kes, line_role, provision_code, sequence_no)
      VALUES (v_est, v_no, 'EA_SUBSISTENCE', v_tier.tier_label, v_qty, 'TIMES', coalesce(v_tier.trustride_rate_kes, v_tier.statutory_floor_kes), 1.00, v_amt, 'PRICE',
        CASE WHEN v_tier.trustride_rate_kes IS NULL THEN v_tier.provision_code ELSE 'TR-SUBSISTENCE-RATE' END, v_seq);

    ELSIF v_type IN ('ACCOMMODATION', 'DISBURSEMENT', 'MATERIALS') THEN
      v_amt := round((v_line->>'estimated_kes')::numeric, 2);
      IF v_amt IS NULL OR v_amt < 0 THEN RAISE EXCEPTION 'Line %: give the estimated cost in KES', v_no; END IF;
      v_atcost := v_atcost + v_amt;  v_seq := v_seq + 1;
      INSERT INTO trustride.cost_ea_engagement_line (estimate_id, order_line_no, component_code, description, quantity, unit, rate_kes, multiplier, amount_kes, line_role, provision_code, sequence_no)
      VALUES (v_est, v_no, 'EA_' || v_type, coalesce(nullif(v_line->>'description', ''), initcap(v_type)) || ' (at cost, on receipts)',
        1, 'ITEM', v_amt, 1.00, v_amt, 'PRICE', 'TR-AT-COST', v_seq);

    ELSE
      RAISE EXCEPTION 'Line %: unknown scope line type "%" (LABOUR, TRAVEL, SUBSISTENCE, ACCOMMODATION, DISBURSEMENT, MATERIALS)', v_no, coalesce(v_line->>'line_type', '');
    END IF;
  END LOOP;

  IF v_labour_lines = 0 THEN
    RAISE EXCEPTION 'fn_cost_ea_engagement_rate: the scope needs at least one labour line (hours or days of the assistant''s time)';
  END IF;

  -- Employer contributions, margin on labour, the trade's floor on labour.
  FOR c IN SELECT * FROM trustride.cost_labour_oncost WHERE side = 'EMPLOYER_CONTRIBUTION' AND applies_to_basis = v_basis AND active ORDER BY component_code DESC LOOP
    v_amt := round(v_worker * c.rate_pct / 100.0, 2);  v_employer := v_employer + v_amt;  v_seq := v_seq + 1;
    INSERT INTO trustride.cost_ea_engagement_line (estimate_id, component_code, quantity, unit, rate_kes, multiplier, amount_kes, line_role, provision_code, sequence_no, description)
    VALUES (v_est, c.component_code, c.rate_pct, 'PERCENT', v_worker, 1.00, v_amt, 'PRICE', c.provision_code, v_seq, c.description);
  END LOOP;
  v_margin := round((v_worker + v_employer) * v_rate.platform_margin_pct / 100.0, 2);
  v_floor_adj := greatest(0, v_rate.floor_price_kes - (v_worker + v_employer + v_margin));
  v_seq := v_seq + 1;
  INSERT INTO trustride.cost_ea_engagement_line (estimate_id, component_code, quantity, unit, rate_kes, multiplier, amount_kes, line_role, provision_code, sequence_no) VALUES
    (v_est, 'EA_PLATFORM_MARGIN', v_rate.platform_margin_pct, 'PERCENT', v_worker + v_employer, 1.00, v_margin, 'PRICE', 'TR-PLATFORM-MARGIN', v_seq);
  IF v_floor_adj > 0 THEN v_seq := v_seq + 1;
    INSERT INTO trustride.cost_ea_engagement_line (estimate_id, component_code, quantity, unit, rate_kes, multiplier, amount_kes, line_role, provision_code, sequence_no)
    VALUES (v_est, 'EA_FLOOR_ADJUSTMENT', NULL, NULL, v_rate.floor_price_kes, 1.00, v_floor_adj, 'PRICE', 'TR-FLOOR-PRICE', v_seq); END IF;

  -- The worker's side: shown, never charged.
  FOR c IN SELECT * FROM trustride.cost_labour_oncost WHERE side IN ('WORKER_DEDUCTION', 'WORKER_WITHHOLDING') AND applies_to_basis = v_basis AND active ORDER BY component_code LOOP
    v_amt := round(v_worker * c.rate_pct / 100.0, 2);  v_deducted := v_deducted + v_amt;  v_seq := v_seq + 1;
    INSERT INTO trustride.cost_ea_engagement_line (estimate_id, component_code, quantity, unit, rate_kes, multiplier, amount_kes, line_role, provision_code, sequence_no, description)
    VALUES (v_est, c.component_code, c.rate_pct, 'PERCENT', v_worker, 1.00, v_amt, 'WORKER_INFO', c.provision_code, v_seq, c.description);
  END LOOP;
  v_seq := v_seq + 1;
  INSERT INTO trustride.cost_ea_engagement_line (estimate_id, component_code, quantity, unit, rate_kes, multiplier, amount_kes, line_role, provision_code, sequence_no, description)
  VALUES (v_est, 'EA_WORKER_NET_PAY', NULL, NULL, v_worker, 1.00, greatest(v_worker - v_deducted, 0), 'WORKER_INFO', 'RWGO-P3-SCH1', v_seq,
    'Worker pay after deductions (travel, subsistence and at-cost items are reimbursed separately)');

  UPDATE trustride.cost_ea_engagement_estimate SET
    worker_pay_kes = v_worker, employer_contributions_kes = v_employer, platform_margin_kes = v_margin, floor_adjustment_kes = v_floor_adj,
    travel_kes = v_travel, subsistence_kes = v_subs, at_cost_kes = v_atcost,
    total_kes = v_worker + v_employer + v_margin + v_floor_adj + v_travel + v_subs + v_atcost
  WHERE estimate_id = v_est;
  RETURN v_est;
END;
$$;
COMMENT ON FUNCTION trustride.fn_cost_ea_engagement_rate IS
  'EA-STATUTORY-1.0.0: rates an Executive Assistant engagement from the customer''s order lines (LABOUR by HOURS or DAYS, TRAVEL, SUBSISTENCE, ACCOMMODATION, DISBURSEMENT, MATERIALS) against the gazetted minimum wage of the trade''s occupation in the zone''s wage area, statutory overtime and rest-day/holiday rates, the established night multiplier, statutory contributions, the established margin and floor (labour only), TrustRide''s transport tariff and at-cost pass-through. Every line cites its provision. Added beside the established EA equation, which it does not change.';

GRANT EXECUTE ON FUNCTION trustride.fn_cost_ea_night_hours(TIMESTAMPTZ, NUMERIC) TO trs026_eng005_cost_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_ea_engagement_rate(trustride.ea_skill_category_enum, TEXT, TEXT, JSONB, UUID, UUID, UUID) TO trs026_eng005_cost_service;

-- ----------------------------------------------------------------------------
-- 6. Security
-- ----------------------------------------------------------------------------
-- Every table here is Engine 5's own and private to its service role; no
-- existing table, function, policy or allowlist is altered.
DO $sec$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['cost_legal_instrument', 'cost_legal_provision', 'cost_labour_wage_area', 'cost_labour_zone_wage_area',
                           'cost_labour_statutory_wage', 'cost_ea_trade_occupation', 'cost_ea_rating_rule', 'cost_labour_oncost',
                           'cost_ea_expense_type', 'cost_ea_subsistence_rate', 'cost_ea_engagement_estimate', 'cost_ea_engagement_line'] LOOP
    EXECUTE format('ALTER TABLE trustride.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY %I ON trustride.%I FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true)', t || '_service_write', t);
    EXECUTE format('REVOKE ALL ON trustride.%I FROM PUBLIC, anon, trustride_authenticated', t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON trustride.%I TO trs026_eng005_cost_service', t);
  END LOOP;
END;
$sec$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
