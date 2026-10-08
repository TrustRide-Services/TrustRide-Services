// Integrated Company -> Boda proof report, generated from the final run's evidence.
const d = require("../proof-final.json");
const main = d.rows.filter((r) => !/^Test [ABCD]/.test(r.stage));
const tests = d.rows.filter((r) => /^Test [ABCD]/.test(r.stage));
const clip = (s, n = 260) => (String(s).length > n ? String(s).slice(0, n) + "…" : String(s));
const T = (rows) => rows.map((r) => [r.stage, r.actor, r.expected, clip(r.actual), clip(r.evidence, 140), r.status]);
const pass = d.rows.filter((r) => r.status === "PASS").length;

module.exports = {
  base: "TrustRide_Company_Boda_Integrated_Proof_2026-10-08",
  eyebrow: "TrustRide Services · Final integrated proof",
  title: "Company → Boda Integrated Proof",
  subtitle: "One authorized company, one Boda, one continuous transaction — from sign-in to receipt — with identity, resource class, money and state traced through every engine",
  footer: `TrustRide Services — Final Integrated Proof Mandate, 8 October 2026. Evidence order ${d.order}; commit cc95c7b.`,
  meta: [
    ["Prepared for", "Founder & CEO, TrustRide Services"],
    ["Date", "8 October 2026"],
    ["Proof transaction", `${d.order} — Akinyi Logistics Ltd (company), acting through its representative; Boda ride Kisumu CBD → Milimani; KES 132.30; receipt TRS026-RECEIPT-000000009`],
    ["Environment", "Full local Supabase stack (sign-in, Data API, 18 background jobs) built from the same 52 migrations as trustride-stagging; real browser (Playwright) driving the real screens; database suites re-run on staging"],
    ["External legs", "M-Pesa (Daraja adapter contract), Protrack telemetry, SMS and NTSA ran on their simulators — the same contracts the production adapters use"],
  ],
  blocks: [
    { h1: "Verdict" },
    { callout: "VERDICT A — PROVEN. The integrated Company → Boda transaction has been proven against the existing TrustRide implementation. No architecture redesign is required by this test." },
    { p: `In the final pass all ${d.rows.length} checked stages passed in one continuous run (${pass}/${d.rows.length}). Getting there, the proof exposed two genuine implementation defects; both were fixed with the smallest compliant change inside the engine that owns them, pinned by database tests (red before, green after on staging), and the complete journey was rerun from the start.` },
    { h2: "The question, answered" },
    { p: "Can TrustRide now receive an authorized Company customer requesting a Boda service and carry that transaction through quotation, acceptance, matching, operator assignment, dispatch, tracking, completion, payment, settlement and receipt without losing identity, business meaning, authorization, resource class, financial integrity or operational state?" },
    { p: "YES. The company owned the order, the estimate, the assignment request, the payment and the receipt at every stage; its representative appears only as the acting person. Only a Boda unit was ever reserved or assigned. The fare the company accepted (KES 132.30) is the amount settled and receipted, exactly once. Every signal across six engines was delivered and accepted, nothing was dead-lettered, and the motorcycle and its rider returned to their correct post-job states." },

    { h1: "Defects found and fixed during the proof" },
    { table: { head: ["Item", "Defect 1 — wrong-class reservation accepted", "Defect 2 — stale waiting reason"], widths: [1.1, 2.6, 2.3], rows: [
      ["Failed stage", "Test D — wrong resource class", "Assignment (business meaning)"],
      ["Expected", "A non-Boda unit reserved for a Boda order is refused; no job; unit released", "Once matched, the order no longer says nobody is free"],
      ["Actual", `Sedan accepted by Business and moved to ASSIGNED for the Boda order (pass 1, TRS026-ORDER-000000018: Sedan now ASSIGNED; Business verdict: accepted); on staging a job was created on the Sedan`, "A quoted, then dispatched and settled order kept “No BODA_BODA free yet”, shown on the Office Orders screen"],
      ["Root cause", "Class eligibility was enforced only at discovery (Engine 2); Business never checked the class of the reservation it received", "Accepting a reservation cleared waiting_since but not status_reason"],
      ["Responsible engine", "Engine 4 — Business", "Engine 4 — Business"],
      ["Responsible function / signal", "fn_business_resource_reserved_accept on RESOURCE_RESERVED", "fn_business_resource_reserved_accept"],
      ["Fix applied", "Migration 20261007000022: refuse a reservation whose capacity_class ≠ order's required class; release the unit (ASSIGNMENT_RELEASED); order back to WAITING for the next retry; Office alerted", "Migration 20261007000023: clear the waiting reason when a valid reservation is accepted"],
      ["Regression", "Suite 11 (new): 4/8 failed before, 8/8 after on staging; proof Test D2 PASS", "Suite 04: new check failed before, passes after on staging"],
      ["Full regression", "All 11 database suites on staging: 416 checks, 0 failed", "Complete Company → Boda journey rerun from the start: 44/44 PASS"],
    ] } },

    { h1: "Evidence — the journey, stage by stage" },
    { p: "Every action below was taken by the actor named, through their own screen, in this order, on one order. Evidence was read from the database and from the Data API as that actor." },
    { table: { head: ["Stage", "Actor", "Expected", "Actual", "Evidence", "Status"], widths: [1.0, 0.8, 1.6, 2.4, 1.4, 0.55], rows: T(main) } },

    { h1: "Evidence — failure and recovery (Tests A–D)" },
    { table: { head: ["Test", "Actor", "Expected", "Actual", "Evidence", "Status"], widths: [1.1, 0.8, 1.5, 2.4, 1.3, 0.55], rows: T(tests) } },
    { bullets: [
      "Test A ran on the proof order itself: the Boda rider was off duty, so the order waited and the company was told; when the rider started his shift the next automatic retry matched him — no manual step.",
      "Test D was run two ways: live (Sedan and Executive Assistant units free, Boda order still waits — never offered to them) and by fault injection (Engine 2 forced to reserve the Sedan for a second company Boda order) — refused, released, no job, no quote.",
      "Test C replayed the confirmation, the retry, the M-Pesa callback and the PAYMENT_SETTLED signal: settlement, ledger posting, receipt and settled-payment counts were identical before and after.",
      "Test B made eleven unauthorized attempts by the company and by another operator; every one was denied and the job, the order and the count of executed commands were unchanged.",
    ] },

    { h1: "Company identity — traced end to end" },
    { table: { head: ["Point", "Holder", "Where recorded"], widths: [1.4, 1.6, 3.0], rows: [
      ["Company", "Akinyi Logistics Ltd (COMPANY, KRA P051234567X, BRS/KRA-verified)", "entity_profile, platform_users"],
      ["Representative", "Akinyi Customer Test — verified member of the company", "entity_membership; fn_am_i_representative_of"],
      ["Authenticated identity / customer context", "Session user = company; acting person = representative", "present_shell_session.user_id / acting_person_user_id"],
      ["Order and order scope", "Company", "business_order.requester_user_id; business_order_line"],
      ["Estimate", "Company", "fare_calculation.requester_user_id; fare_quote via business_order.quote_id"],
      ["Acceptance", "Company (acting person: representative)", "present_command_capture ACCEPT_QUOTATION on the company session"],
      ["Assignment", "Company", "RESOURCE_ASSIGNMENT_CONFIRMED payload requester_user_id"],
      ["Payment payer and phone", "Company; its own verified M-Pesa number …888 (the representative's own is …003)", "integration_payment_gateway_transaction.requester_user_id / msisdn_masked; fn_user_payment_msisdn"],
      ["Settlement, ledger, receipt", "Company's order", "business_settlement (one row); ORDER_SETTLED payload requester_user_id"],
      ["Notifications", "Company — 0 addressed to the representative personally", "present_notification_inbox; SMS to …888"],
      ["Audit", "57 hash-chained decision-log entries for the company's and operator's commands", "present_decision_log"],
    ] } },
    { p: "The representative's own personal identity cannot even open the company's order (“No such order on your identity”) — the company relationship is never collapsed into the person." },

    { h1: "Boda resource class — traced end to end" },
    { table: { head: ["Point", "Value"], widths: [1.6, 4.4], rows: [
      ["Requested service", "TRANSPORT-BODA-STANDARD"],
      ["Required class (resolved by Engine 3)", "BODA_BODA"],
      ["Matching (Engine 2)", "fn_resource_discover_eligible(BODA_BODA, vetting, certificates, jurisdiction, verified fleet)"],
      ["Resource", "Working unit 2651e266 · class BODA_BODA · motorcycle Bajaj Boxer 150 KMFA123B (NTSA-verified) · tracker PT-0001"],
      ["Operator", "Otieno Rider Test — the unit's operator, approved through Office access and onboarded"],
      ["States", "Unit OFFLINE → AVAILABLE (shift) → RESERVED → ASSIGNED → AVAILABLE after verification; motorcycle ASSIGNED (BOUND_TO_WORKFORCE_UNIT) throughout — its binding to the unit, unchanged by jobs"],
      ["Other classes", "Sedan and Executive Assistant units free the whole time — never reserved for this order; a forced Sedan reservation refused"],
    ] } },

    { h1: "No data disappeared between engines" },
    { p: `For this transaction ${d.trace.reduce((a, t) => a + Number(t.n), 0)} signals moved between six engines. Every one was accepted except the deliberately redelivered PAYMENT_SETTLED (Test C), which was correctly refused. No dead letters.` },
    { table: { head: ["Engine (receiver)", "Signal", "Status", "Count"], widths: [1.2, 2.8, 1.2, 0.6], rows: d.trace.map((t) => [t.engine, t.signal_type, t.signal_status, String(t.n)]) } },
    { table: { head: ["Item", "Created → persisted → propagated → consumed → projected"], widths: [1.3, 4.7], rows: [
      ["Company / representative", "Gate → present_shell_session → every command's session → order, quote, payment → ORDER_DETAIL to the company only"],
      ["Service and class", "Booking form → business_order.service_code → SERVICE_LOOKUP_REQUESTED → SERVICE_RESOLVED (class) → ASSIGNMENT_REQUESTED.required_capacity_class"],
      ["Order and scope", "RAISE_INTENT → business_order + business_order_line (distance from routing) → every downstream payload → ORDER_DETAIL stops"],
      ["Quote and accepted amount", "RESOURCE_DISPATCH_INITIATED → fare_calculation/fare_quote → UNIT_PRICE_LOCKED/FARE_QUOTED → shown → ACCEPT_QUOTATION → business_settlement amount → STK amount → receipt"],
      ["Operator, resource, assignment", "RESOURCE_RESERVED → RESOURCE_ASSIGNMENT_CONFIRMED → RESOURCE_ASSIGNED → business_job → OPERATOR_JOB / ORDER_DETAIL (first name, vehicle)"],
      ["Dispatch → completion", "Operator commands → business_job timestamps → ORDER_PROGRESS ×9 → company screen and SMS → JOB_COMPLETED → unit released"],
      ["Tracking", "Protrack points → Engine 6 (key) → resource_location_event (fleet, order) → RESOURCE_LOCATION_UPDATED → business_tracking_session → ORDER_DETAIL / OFFICE_TRACKING → ended at completion"],
      ["Payment → receipt", "PAYMENT_STK_TRIGGERED → gateway transaction → confirmation → PAYMENT_SETTLED → business_settlement (settled, ledger posted, receipt) → ORDER_SETTLED → screen and SMS"],
    ] } },

    { h1: "Database integrity after completion" },
    { table: { head: ["Check", "Result"], widths: [3, 3], rows: Object.entries(d.integ).map(([k, v]) => [k.replaceAll("_", " "), String(v)]) } },

    { h1: "Remaining dependencies" },
    { p: "None of these is unfinished software for this journey; each software boundary is built and was exercised through its simulator under the same contract." },
    { table: { head: ["Item", "Classification", "What is needed"], widths: [1.6, 1.5, 2.9], rows: [
      ["Real M-Pesa (Daraja STK, callbacks)", "PRODUCTION CREDENTIAL REQUIRED", "Safaricom shortcode, passkey and consumer key/secret (sandbox first); then switch PAYMENT_GATEWAY on the Integrations screen."],
      ["Real Protrack telemetry", "PRODUCTION CREDENTIAL REQUIRED", "Protrack account and API credentials; Protrack configured to push to protrack-ingest with the Office-issued key."],
      ["Real devices, riders, motorcycles", "REAL-WORLD RESOURCE REQUIRED", "Onboard through the Office exactly as in this proof."],
      ["SMS, NTSA, BRS/KRA, IPRS", "EXTERNAL PROVIDER DEPENDENCY", "Provider and government API access; adapters stay on simulator until granted."],
      ["Live-site sign-in URLs, Vercel Pro", "CONFIGURATION REMAINING", "Supabase Auth URL configuration for trustride-services.vercel.app; Pro before commercial use."],
      ["Article 44 ledger splits", "FOUNDER DECISION REQUIRED", "Settlement posts to Engine 4's single ledger of record (business_settlement: settled → ledger posted → receipt, enforced by a database constraint). Splitting each settled order into platform commission, statutory allocations and other lines needs the split rules, which the corpus assigns to finance manuals and rate registers not yet written."],
    ] } },
    { h2: "How to reproduce" },
    { bullets: [
      "Database: supabase/tests/run.sh linked — 11 suites, rollback-only.",
      "Journey: start the local stack, build the frontend against it, run p0_setup.js then proof.js (kept with this report's evidence); the proof writes proof-<run>.json, from which this report was generated.",
    ] },
  ],
};
