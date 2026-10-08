// Single source of truth for the Readiness Report of 8 October 2026.
// Block types: h1, h2, p, bullets, table, callout

module.exports = {
  base: "TrustRide_Readiness_Report_2026-10-08",
  eyebrow: "TrustRide Services · Readiness",
  title: "Readiness Report",
  subtitle: "Where TrustRide stands today, how Executive Assistants are rated and priced under Kenyan law, and what remains before TrustRide is ready for work (Engine 6 providers excluded)",
  footer: "TrustRide Services — Readiness Report, 8 October 2026. Evidence: SQL suites on trustride-stagging, the live site at trustride-services.vercel.app, browser journeys on a full local stack built from the same migrations, and the official legal texts on Kenya Law.",
  meta: [
    ["Prepared for", "Founder & CEO, TrustRide Services"],
    ["Date", "8 October 2026"],
    ["Directive", "Comprehensive readiness report, except Engine 6 provider requirements (tracked by the Founder); confirm how Executive Assistants are ordered; research Kenyan labour law; add the legal EA cost method to Engine 5 without changing anything established; remove Flutterwave"],
    ["Environment", "trustride-stagging (Supabase, ref fdkzewkogkujtwvonesn) · repository TrustRide-Services (main, last commit 15337d8) · live at https://trustride-services.vercel.app (Vercel team trust-ride, project trustride-services)"],
    ["Not touched", "trustride-production; every established object of Engine 5 (proven by fingerprint, section I)"],
  ],
  blocks: [
    { h1: "The answer in one page" },
    { p: "TrustRide's software is complete and working on staging: all 11 engines, 12 database test suites (452 checks, 0 failed), and a live web application that people can now sign up to, log in to, recover a password on, and order from. Today the live site was brought fully under control — its automatic deployments had been failing since the new Vercel project was created, because of one setting; you fixed it, and every push since has built and gone live by itself. You claimed Founder authority on the live site." },
    { p: "Your concern about Executive Assistants was right. They are ordered exactly like transport, courier and delivery — the same booking, matching, estimate, acceptance and payment — but their pricing does not meet Kenyan law. The established method turns a monthly minimum wage into an hourly cost by dividing by 208, using a 2023 figure (KES 15,200), and four of the six trades use estimates. The Regulation of Wages (General) Order, as amended on 26 June 2026 (L.N. 108/2026), sets its own hourly and daily minimums: a cleaner or messenger in Kisumu or Nairobi must be paid at least KES 161.34 an hour, but the established method charges the customer KES 111.45 an hour for that work — less than the worker alone is owed. It also cannot book by the day (no 2-day meeting representation), carries no travel or other costs, and is set up for Kisumu only." },
    { p: "As you instructed, Engine 5 was not changed. A statutory rating method was added beside it: the law itself is recorded as data (every Act, Legal Notice and provision), the First Schedule is loaded verbatim (15 occupations × 3 wage areas), and a new function rates an engagement from the customer's order lines — labour by the hour or by the day, travel, subsistence, accommodation, disbursements and materials — citing the law for every line. A fingerprint of 374 established objects taken before and after shows 0 changed and 0 removed. The established method still quotes the live order flow; switching EA quotes to the statutory method is your decision." },
    { table: { head: ["Area", "Status", "In plain words"], rows: [
      ["Platform software — 11 engines", "GREEN", "Built and proven; 12 suites / 452 checks pass on staging; conformance 0 violations."],
      ["Live web application and deployment", "GREEN", "Root Directory fixed; every push builds and goes live automatically (last: 28830e0 → c8628d1 → 15337d8)."],
      ["Sign-up, log-in, password reset (live)", "GREEN", "Sign-up proven on the live site 5/5; reset flow built and proven 6/6; Auth URLs set by you."],
      ["Founder authority", "DONE", "Claimed on the live site at 10:37 UTC; Admin Console open."],
      ["Transport, courier, delivery pricing (Engine 5)", "GREEN", "Unchanged — fingerprint proves it; suite 04 prices every service end to end (85/85)."],
      ["Executive Assistant ordering", "GREEN", "Same order flow as every other service (section D)."],
      ["Executive Assistant pricing — legal", "RED", "The established quotes can fall below the gazetted minimum pay (section E). The statutory method is added and proven; not yet used for live quotes."],
      ["Holiday calendar", "AMBER", "Mazingira Day (10 October — in two days), Good Friday and Easter Monday 2026, and all of 2027 are missing (section J)."],
      ["Backups", "RED", "Staging has no restorable backup; production must have one before real data."],
      ["Engine 6 providers", "N/A", "Excluded from this report — tracked by the Founder (section K). Flutterwave removed."],
    ] } },
    { callout: "Verdict: TrustRide is ready for supervised operation on staging. Before paid public work it needs: your decision to quote Executive Assistants by the statutory method, the holiday calendar corrected, backups and paid plans for production, and the Engine 6 providers you are already securing." },

    // ------------------------------------------------------------------ A
    { h1: "A. Baseline verified before any change" },
    { table: { head: ["Check", "Expected", "Found", "Result"], rows: [
      ["Repository", "2e99537 at the top", "2e99537", "PASS"],
      ["Staging migrations", "up to 20261007000023", "52 of 52 applied, local = remote", "PASS"],
      ["SQL suites on staging", "11 suites, 416 checks, 0 failed", "11 suites, 416 passed, 0 failed", "PASS"],
      ["Live site", "responds", "200; signed-out visitors sent to /login", "PASS"],
    ] } },

    // ------------------------------------------------------------------ B
    { h1: "B. Fixed and delivered today" },
    { table: { head: ["What", "Evidence", "Status"], widths: [2.4, 2.8, 0.8], rows: [
      ["Deployment documents describe only the current TrustRide-Services setup (README, Build Plan v1.1.0, Runbooks rewritten against the live schema)", "commit 48682f6", "DONE"],
      ["Vercel builds had all failed (Root Directory '.' instead of frontend/web); fixed by you, newest build promoted, automatic deploys confirmed", "Vercel build logs; 3 later pushes built and went live", "DONE"],
      ["Founder claim hidden from a verified identity that also held Operator access", "commit 2907700; browser test j13 red 1/2 → green 4/4", "DONE"],
      ["A repeat click on the Founder claim showed a raw database error", "commit 28830e0; j13 red 4/5 → green 5/5", "DONE"],
      ["Supabase Auth: Site URL, redirect URLs, Confirm email off for staging (set by you)", "Auth settings read back; live sign-up 5/5", "DONE"],
      ["Forgot password: the emailed link had nowhere to set a new password", "commit c8628d1; j14 with a real email red 2/3 → green 6/6", "DONE"],
      ["Executive Assistant statutory rating method added to Engine 5 (nothing established changed)", "commit 15337d8; suite 12 red → green 36/36; fingerprint 0 changed", "DONE"],
      ["Flutterwave removed from the payment-rail vocabulary and the deployment documents", "commit 15337d8; suite 12", "DONE"],
    ] } },

    // ------------------------------------------------------------------ C
    { h1: "C. Engine-by-engine readiness (Engine 6 providers excluded)" },
    { table: { head: ["Engine", "Status", "Evidence"], widths: [1.7, 0.7, 3.6], rows: [
      ["1 Foundation (identity, roles, audit, calendar)", "GREEN", "Suites 01, 02, 10; one verified phone per identity; Founder claimed once. Calendar data incomplete (section J)."],
      ["2 Resources (bases, fleet, units, trackers)", "GREEN", "Suites 03, 11; wrong-class reservation refused."],
      ["3 Services (catalogue, eligibility)", "GREEN", "24 services; vetting and certificates enforced in matching (suite 04)."],
      ["4 Business (orders, quotes, settlement, marketplace, actors)", "GREEN", "Suites 04, 05, 06; Flutterwave rail removed."],
      ["5 Cost (pricing)", "GREEN", "Transport/courier/delivery unchanged and proven; EA statutory method added (suite 12). Live EA quotes still use the established method (section E)."],
      ["6 Integration — internal machinery", "GREEN", "Outbound queue, retries, simulator/sandbox/production switch per port, callbacks (suites 05, 07, 08). Providers excluded (section K)."],
      ["7 Orchestration", "GREEN", "Dispatch cycle every 10 s, dead-letter and SLA sweeps (suite 08)."],
      ["8 Coordination", "GREEN", "Consensus timeout sweep; signal routes proven through every order journey."],
      ["9 Advisory", "GREEN", "Hourly and daily sweeps; Executive Dashboard advisory projection (suite 09)."],
      ["10 Scenario Modelling", "GREEN", "Scenario templates listed (suite 09); a scenario run from the Executive Dashboard (browser journey j4)."],
      ["11 Presentation (shells, commands, projections)", "GREEN", "29 registered projections; every screen reads through them (suite 09); 35+ routes live."],
    ] } },

    // ------------------------------------------------------------------ D
    { h1: "D. Confirmed: Executive Assistants are ordered the same way as every other service" },
    { p: "There is one order path for every dispatched service. A customer opens Book a service, chooses the family (Transport, Delivery, Courier or Executive Assistants), the service and the place, and raises the order. The scope of engagement travels as order lines — for transport, the stops; for Executive Assistants, the place and the hours. TrustRide matches a worker with the right skill, certificates and vetting, Engine 5 prices the order line by line, the customer accepts the estimate within 10 minutes, the worker is dispatched, and the customer pays by M-Pesa. The only difference is the pricing branch inside Engine 5: distance and time for vehicles, labour for assistants." },
    { table: { head: ["EA service", "Trade it is priced as"], rows: [
      ["Errands; Shopping", "Personal shopper / errand"],
      ["Cleaning", "House manager / domestic"],
      ["Personal Driving; Student Pickup", "Professional chauffeur"],
      ["Chef", "Certified chef"],
      ["Caregiving", "Patient / elder caregiver"],
      ["School Visitation; Shopping Representation & Deliveries", "Corporate representative"],
    ] } },
    { p: "There is no catalogue service named Meeting Representation; the corporate-representative trade exists, but is reached today only through School Visitation and Shopping Representation (section J)." },

    // ------------------------------------------------------------------ E
    { h1: "E. How Executive Assistants are rated and priced today (established, unchanged)" },
    { p: "Client hourly rate = (monthly minimum ÷ 208 hours) × 1.22 (on-costs, one figure) × 1.25 (platform margin) × shift multiplier (Day 1.0, Night 1.5); total = hours × that rate + queue wait + transit fee, never below the trade's floor price. Hours only, 1 to 12, one shift rate for the whole job, Kisumu only." },
    { table: { head: ["Trade", "Paid as (gazetted occupation)", "Established labour basis per hour", "Established client rate per hour", "Law: minimum pay per hour (Cities)", "Law: minimum pay per day (Cities)"], rows: [
      ["Errand / shopper", "messenger", "73.08", "111.45", "161.34", "868.44"],
      ["House manager / cleaner", "house servant, cleaner", "73.08", "111.45", "161.34", "868.44"],
      ["Caregiver", "children's ayah (nearest)", "84.13", "128.30", "161.34", "868.44"],
      ["Chef", "cook", "100.96", "153.96", "175.46", "936.88"],
      ["Chauffeur", "driver (cars and light vans)", "88.94", "135.63", "219.28", "1,170.46"],
      ["Corporate representative", "general clerk / receptionist (nearest)", "120.19", "183.29", "250.38", "1,336.43"],
    ] } },
    { bullets: [
      "The customer's hourly rate in every trade is below the worker's legal minimum hourly pay — before employer contributions or TrustRide's margin are even counted.",
      "The monthly figures are out of date: KES 15,200 was the 2023 general minimum; it became 16,113.75 in November 2024 (L.N. 164/2024) and 18,047.40 in 2026 (L.N. 95 and 108/2026). Four trades used estimates (18,500 to 25,000).",
      "No booking by the day: a 2-day meeting representation cannot be ordered.",
      "One shift rate for the whole job, set by the start time; a job that runs into the night is not split; no overtime after a normal day.",
      "No travel, subsistence, accommodation, disbursement or materials lines.",
      "Contributions are one undifferentiated 22%; no line cites a law.",
      "Short jobs are carried by the floor price, which hides the shortfall on small bookings but not on longer ones (section H).",
    ] },

    // ------------------------------------------------------------------ F
    { h1: "F. What Kenyan law says" },
    { table: { head: ["Instrument", "What it settles", "How it was verified"], widths: [2.1, 2.6, 1.3], rows: [
      ["Regulation of Wages (General) Order, L.N. 120/1982 as amended to L.N. 108/2026", "Minimum monthly, daily and hourly pay per occupation and area (First Schedule); 52-hour week over six days; overtime 1.5×; rest day and public holiday 2×; one rest day a week; subsistence away from base (para 14)", "Official consolidated text, Kenya Law, version of 26 June 2026"],
      ["Employment Act, No. 11 of 2007", "Casual employee (paid daily, engaged ≤ 24 h at a time, s.2); a rest day in every seven (s.27(2)); casual work adding up to a month converts to monthly employment (s.37)", "Official consolidated text, Kenya Law"],
      ["Public Holidays Act, Cap. 110 (as amended 2024)", "The holidays, including Mazingira Day on 10 October; a holiday on a Sunday moves to the Monday", "Official consolidated text, Kenya Law"],
      ["NSSF Act 2013", "6% employer + 6% employee (from Feb 2026: limits KES 9,000 / 108,000; under appeal)", "Secondary source — verify"],
      ["Social Health Insurance Act 2023", "SHIF 2.75% from the employee", "Secondary source — verify"],
      ["Affordable Housing Act 2024", "1.5% employee + 1.5% employer", "Secondary source — verify"],
      ["Income Tax Act s.35 (Tax Laws (Amendment) Act 2024)", "5% withholding on payments a digital marketplace makes to a resident provider", "Secondary source — verify"],
    ] } },
    { h2: "The First Schedule rows used by EA trades (L.N. 108/2026, KES)" },
    { table: { head: ["Occupation (row)", "Cities: month / day / hour", "Former municipalities: month / day / hour", "All other areas: month / day / hour"], rows: [
      ["1 General labourer, cleaner, house servant, ayah, messenger", "18,047.40 / 868.44 / 161.34", "16,650.95 / 797.80 / 147.45", "9,628.07 / 487.94 / 90.17"],
      ["2 Cook, waiter", "19,491.33 / 936.88 / 175.46", "17,046.83 / 828.55 / 149.47", "11,124.42 / 549.91 / 100.56"],
      ["6 Driver (cars and light vans)", "24,358.73 / 1,170.46 / 219.28", "22,481.83 / 1,080.47 / 199.98", "18,582.41 / 892.89 / 165.14"],
      ["7 General clerk, receptionist", "27,796.51 / 1,336.43 / 250.38", "25,412.61 / 1,222.22 / 201.35", "21,668.18 / 1,038.68 / 194.58"],
    ] } },
    { p: "Cities are Nairobi, Mombasa, Kisumu, Nakuru and Eldoret: a Nairobi engagement is paid at the same statutory rates as a Kisumu one. Monthly rates exclude the 15% housing allowance; daily and hourly rates already include it. All 15 rows are loaded in Engine 5 exactly as gazetted." },

    // ------------------------------------------------------------------ G
    { h1: "G. The statutory rating method added to Engine 5" },
    { p: "Added, not changed: 12 new tables and 2 new functions. The established EA rate card is only read (for each trade's margin, floor and minimum hours), as are the night multiplier and the transport tariff." },
    { table: { head: ["New table", "What it holds"], rows: [
      ["cost_legal_instrument, cost_legal_provision", "Every Act and Legal Notice, and each provision used, marked statute or TrustRide policy and primary or secondary source"],
      ["cost_labour_wage_area, cost_labour_zone_wage_area", "The three statutory wage areas; each service zone's area (Kisumu zones: Cities)"],
      ["cost_labour_statutory_wage", "The First Schedule, verbatim — 45 rows"],
      ["cost_ea_trade_occupation", "Each EA trade's gazetted occupation and any skill premium (0% today)"],
      ["cost_ea_rating_rule", "8 hours a normal day; overtime 1.5×; Sunday/holiday 2×; night window 19:00–06:00; at most 12 hours a day and 6 days an engagement; engagement basis"],
      ["cost_labour_oncost", "Employer NSSF 6% and Housing Levy 1.5%; worker NSSF, SHIF, Housing Levy; 5% withholding for contractors"],
      ["cost_ea_expense_type, cost_ea_subsistence_rate", "The other costs an engagement may carry and how each is reached; para 14 subsistence tiers"],
      ["cost_ea_engagement_estimate, cost_ea_engagement_line", "Each rated engagement and its lines, every line citing its provision"],
    ] } },
    { h2: "How the cost is reached, from the customer's order lines" },
    { table: { head: ["Order line", "The customer gives", "How it is rated", "Basis"], widths: [1.0, 1.5, 2.4, 1.1], rows: [
      ["LABOUR — by the hour", "hours (1–12), start time", "Gazetted hourly rate of the trade's occupation in the zone's area; the trade's minimum hours apply; hours after 8 at 1.5×; night hours at the night multiplier; a Sunday or public holiday at 2×", "Wages Order para 3, 6; policy"],
      ["LABOUR — by the day", "days (1–6), hours a day, start", "Gazetted daily rate per day; hours after 8 at 1.5×; night uplift; Sunday or holiday days at 2×", "Wages Order para 3, 6, 7; Employment Act s.27(2)"],
      ["Contributions", "—", "Employer NSSF 6% + Housing Levy 1.5% on the worker's pay (casual-employee basis)", "NSSF Act; Affordable Housing Act"],
      ["Margin and floor", "—", "The trade's established margin (25%) on labour only; the trade's floor applies to labour", "TrustRide policy"],
      ["TRAVEL", "distance km, mode, return or not", "TrustRide's own published transport tariff: base + per km, per leg", "TrustRide policy"],
      ["SUBSISTENCE", "tier, how many", "At least the para 14 amount for the tier; a TrustRide rate once you set it", "Wages Order para 14"],
      ["ACCOMMODATION, DISBURSEMENT, MATERIALS", "description, estimated KES", "At cost, on receipts, no margin", "TrustRide policy"],
      ["Worker's side (shown, not charged)", "—", "NSSF 6%, SHIF 2.75%, Housing Levy 1.5% deducted; net pay shown", "Contribution Acts"],
    ] } },

    // ------------------------------------------------------------------ H
    { h1: "H. Your questions, priced both ways (Kisumu, a working Monday, 09:00 start, KES)" },
    { table: { head: ["Engagement", "Established method", "Statutory method", "Of which: worker's pay", "Note"], widths: [1.9, 0.9, 0.9, 0.9, 1.4], rows: [
      ["Meeting representation, 2 days × 8 h", "cannot be booked", "3,591.65", "2,672.86", "2 × daily rate 1,336.43"],
      ["…the same, plus boda 10 km return and a KES 500 entry fee", "cannot be booked", "4,391.65", "2,672.86", "travel 300 (tariff), fee 500 at cost"],
      ["Chauffeur, 2 hours", "600.00", "600.00", "438.56", "both at the trade's floor"],
      ["Chauffeur, 3 hours", "600.00", "883.98", "657.84", "established is below the worker's pay plus contributions"],
      ["Cook, 1 hour", "900.00", "900.00", "526.38", "3-hour minimum and floor apply"],
      ["Cook, 1 day (8 h)", "1,231.76", "1,258.93", "936.88", "daily rate"],
      ["Cleaner, 4 hours", "500.00", "867.20", "645.36", "the worker's legal pay alone exceeds the established price"],
      ["Caregiver, 1 day (8 h)", "1,200.00", "1,200.00", "868.44", "floor applies"],
    ] } },
    { p: "Computed on staging by both functions inside a rolled-back transaction; nothing was stored. Nairobi engagements carry the same labour figures (same statutory area); Nairobi is not yet a TrustRide service zone." },

    // ------------------------------------------------------------------ I
    { h1: "I. Proof that nothing established changed" },
    { bullets: [
      "Before pushing, a fingerprint was taken on staging of 374 established objects: 324 functions (Cost, Business, Resources, Integration, Presentation, Orchestration, Coordination, Services), the definitions and access policies of all 19 Engine 5 tables, and the data of the rate tables, registry, EA rate card, shift multipliers, zones, models, components, fuel registry, calendar and platform configuration.",
      "After the push: 0 changed, 0 removed. Added: 12 tables, their policies, and 2 functions.",
      "All 12 suites pass on staging: 452 checks, 0 failed — suite 04 still prices every transport, courier and delivery service end to end (85/85).",
      "An earlier draft that edited the established EA function was applied only to the local test database and fully reverted (text-identical to staging) before anything was committed; staging and the live site never saw it.",
    ] },

    // ------------------------------------------------------------------ J
    { h1: "J. What remains before TrustRide is ready for work (Engine 6 excluded)" },
    { table: { head: ["Item", "Classification", "What is needed"], widths: [1.7, 1.4, 2.9], rows: [
      ["Quote Executive Assistants by the statutory method", "FOUNDER DECISION REQUIRED", "Your go-ahead to route live EA quotes through the statutory method. Until then the established method quotes, and can price below the legal minimum pay (section E). Wiring it is a small change in the EA branch only; transport, courier and delivery stay untouched."],
      ["Booking by the day, travel and other costs on the EA booking screen", "CODE REMAINING", "After that decision: the booking form gains Hours / Days and optional travel, subsistence and expense lines."],
      ["Engagement basis", "FOUNDER DECISION REQUIRED", "Casual employee (contributions priced in; set today) or independent contractor (5% withholding). Take legal advice; Parliament is considering platform-worker rules."],
      ["Casual-work conversion (Employment Act s.37)", "CODE REMAINING", "A monitor for a worker repeatedly engaged by the same customer approaching a month of working days."],
      ["Occupation mapping and skill premiums", "FOUNDER DECISION REQUIRED", "Confirm caregiver → children's ayah and corporate representative → clerk/receptionist (the Schedule has no exact occupation); set any premium above the minimum."],
      ["Subsistence rates", "FOUNDER DECISION REQUIRED", "The para 14 amounts (KES 5–25) were set decades ago; set TrustRide's own rates (never below them)."],
      ["Meeting Representation service", "FOUNDER DECISION REQUIRED", "Add it to the catalogue (it needs one new Engine 5 registry row, which was not added without your approval)."],
      ["Holiday calendar", "FOUNDER DECISION REQUIRED", "Add Mazingira Day (10 Oct 2026 — this Saturday), the 2026 Easter dates already passed, and 2027 with Sunday substitution (11 Oct, 13 Dec, 27 Dec). This closes those days for every service, as the established working-hours rule does for holidays."],
      ["Verify secondary-source figures", "CONFIGURATION REMAINING", "Confirm NSSF limits (under appeal), SHIF, Housing Levy and the 5% withholding against the primary texts or your tax adviser."],
      ["VAT on TrustRide's fees", "FOUNDER DECISION REQUIRED", "Confirm TrustRide's VAT registration and how VAT applies to fees and margin."],
      ["New areas (e.g. Nairobi)", "REAL-WORLD RESOURCE REQUIRED", "Service zones, coverage and rates for each new area; the wage area follows automatically from the zone."],
      ["Backups", "CONFIGURATION REMAINING", "Staging has none; production needs a paid Supabase plan with daily backups before any real data."],
      ["trustride-production", "CONFIGURATION REMAINING", "Provisioned, not wired; migrate and connect only on your authorization."],
      ["Vercel plan", "CONFIGURATION REMAINING", "Hobby is non-commercial; move to Pro before commercial use."],
      ["Email provider; Confirm email", "FOUNDER DECISION REQUIRED", "Choose a provider; then turn Confirm email back on (off on staging today)."],
      ["Adopted documents still naming Flutterwave", "FOUNDER DECISION REQUIRED", "Constitution (TBOC Article 43), TISC, the Engine 4, 5 and 6 blueprints and the VTDR are adopted texts; amend them with your approval."],
      ["Older document notes", "FOUNDER DECISION REQUIRED", "Four documents still record a former development environment; 13 cite an old repository standard. Correct on your yes."],
      ["Open pricing decisions", "FOUNDER DECISION REQUIRED", "New price rows, multi-stop rule, cancellation fee, EA certificate lists, Article 44 ledger split."],
      ["Repository visibility", "FOUNDER DECISION REQUIRED", "Public or private."],
      ["Push notifications", "CODE REMAINING", "Belong to the mobile app; in-app and SMS/WhatsApp cover notifications today."],
      ["Real operators, vehicles, bases, devices", "REAL-WORLD RESOURCE REQUIRED", "Onboard through the Office screens."],
    ] } },

    // ------------------------------------------------------------------ K
    { h1: "K. Engine 6 — excluded, tracked by the Founder" },
    { p: "The integration machinery is built and proven on its simulator; each provider switches from simulator to production on the Integrations screen once its credentials and certifications arrive. Services you are securing include, but are not limited to: Safaricom (M-Pesa STK, B2C, B2B), Airtel, WhatsApp, push, SMS, IPRS, MetaMap, Google Maps, identity verification for devices, equipment and assets, Protrack, and Google services including email. Flutterwave is removed until the system grows." },

    // ------------------------------------------------------------------ L
    { h1: "L. Test evidence" },
    { table: { head: ["Suite", "Checks", "Result"], rows: [
      ["01 Permissions", "34", "PASS"], ["02 Identity, contacts, notifications", "52", "PASS"], ["03 Resources", "39", "PASS"],
      ["04 Order lifecycle (every service priced end to end)", "85", "PASS"], ["05 Payments", "25", "PASS"], ["06 Marketplace and actors", "56", "PASS"],
      ["07 Telemetry, support, reviews", "29", "PASS"], ["08 Background jobs and health", "26", "PASS"], ["09 Projections", "52", "PASS"],
      ["10 Commit-time integrity", "10", "PASS"], ["11 Resource-class integrity", "8", "PASS"],
      ["12 EA statutory rating (new)", "36", "PASS"],
      ["Browser: j13 Founder claim (local)", "5", "PASS"], ["Browser: j14 password reset with real email (local)", "6", "PASS"],
      ["Live site: sign-up to Customer home", "5", "PASS"],
    ] } },
    { h2: "How to reproduce" },
    { bullets: [
      "SQL suites: supabase/tests/run.sh linked — rollback-only, nothing stored.",
      "Browser journeys: tests/e2e/README.md (local stack with mailpit; j13 and j14 restore what they change).",
      "Legal texts: the source URLs are recorded in Engine 5 (cost_legal_instrument).",
    ] },
  ],
};
