// FINAL INTEGRATED PROOF -- Company -> Boda, one continuous transaction.
// Actions are taken by the real actors through the real screens; evidence is
// read from the database and from the Data API as each actor. Nothing in the
// happy path is written to the database by hand. The only direct writes are
// the deliberate fault injections of Test C (replayed settlement signal) and
// Test D (a wrong-class reservation), which are labelled as such.
const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");
const { createClient } = require(path.join("C:/Users/ALBERT/TrustRide-Services/frontend/web/node_modules/@supabase/supabase-js"));
const { BASE, browser, actor, press, poll } = require("./lib");

const RUN = process.argv[2] || "run1";
const env = Object.fromEntries(fs.readFileSync(path.join(__dirname, "local.env"), "utf8").trim().split(/\r?\n/).map((l) => {
  const i = l.indexOf("="); return [l.slice(0, i), l.slice(i + 1).replace(/^"|"$/g, "")];
}));
const text = async (p) => (await p.locator("body").innerText()).replace(/\s+/g, " ");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------- evidence
const rows = [];
function row(stage, actorName, expected, actual, evidence, ok) {
  rows.push({ stage, actor: actorName, expected, actual, evidence, status: ok ? "PASS" : "FAIL" });
  console.log(`${ok ? "PASS" : "FAIL"}  ${stage} — ${actual}`);
}
function db(sql) {
  const out = execFileSync("docker", ["exec", "-i", "supabase_db_TrustRide-Services", "psql", "-U", "postgres", "-d", "postgres", "-At", "-q", "-v", "ON_ERROR_STOP=1"],
    { input: `SELECT coalesce(jsonb_agg(x), '[]'::jsonb) FROM (${sql}) x;`, encoding: "utf8" });
  return JSON.parse(out.trim().split("\n").pop());
}
const one = (sql) => db(sql)[0] ?? null;
function dbExec(sql) {
  return execFileSync("docker", ["exec", "-i", "supabase_db_TrustRide-Services", "psql", "-U", "postgres", "-d", "postgres", "-At", "-q"],
    { input: sql, encoding: "utf8" }).trim();
}

// ---------------------------------------------------------------- API as an actor
async function signIn(email) {
  const sb = createClient(env.API_URL, env.ANON_KEY, { db: { schema: "trustride" }, auth: { persistSession: false } });
  const { error } = await sb.auth.signInWithPassword({ email, password: "Trustride-e2e-2026" });
  if (error) throw error;
  sb.uid = (await sb.auth.getUser()).data.user.id;
  return sb;
}
async function session(sb, top, sub, userId) {
  const { data, error } = await sb.rpc("fn_present_shell_session_open", { p_top_shell: top, p_sub_shell: sub, p_user_id: userId, p_channel_type: "WEB", p_access_id: null });
  return { id: data, error: error?.message };
}
async function cmd(sb, sid, type, payload) {
  const { data, error } = await sb.rpc("fn_present_command_execute", { p_session: sid, p_command_type: type, p_payload: payload });
  if (error) return { status: "ERROR", reason: error.message };
  return data;
}
async function proj(sb, sid, code, params = {}) {
  const { data, error } = await sb.rpc("fn_present_projection", { p_session: sid, p_code: code, p_params: params });
  return error ? { error: error.message } : data;
}

(async () => {
  const b = await browser();
  const cust = await actor(b, "customer"); const C = cust.page;
  const opA = await actor(b, "operator"); const O = opA.page;
  const F = (await actor(b, "founder")).page;

  const company = one(`SELECT p.user_id, p.display_name, e.entity_type, e.kra_pin FROM trustride.platform_users p JOIN trustride.entity_profile e USING (user_id) WHERE p.display_name = 'Akinyi Logistics Ltd'`);
  const rep = one(`SELECT user_id, display_name FROM trustride.platform_users WHERE display_name = 'Akinyi Customer Test'`);
  const otieno = one(`SELECT wu.workforce_unit_id unit, wu.operator_user_id op, wu.fleet_resource_id fleet FROM trustride.resource_workforce_unit wu JOIN trustride.platform_users p ON p.user_id = wu.operator_user_id WHERE p.display_name = 'Otieno Rider Test' AND wu.unit_status = 'ACTIVE'`);
  const sedan = one(`SELECT wu.workforce_unit_id unit FROM trustride.resource_workforce_unit wu JOIN trustride.resource_capacity_class cc USING (capacity_class_id) WHERE cc.class_code = 'SEDAN' AND wu.unit_status = 'ACTIVE'`);
  const ea = one(`SELECT wu.workforce_unit_id unit FROM trustride.resource_workforce_unit wu JOIN trustride.resource_capacity_class cc USING (capacity_class_id) WHERE cc.class_code = 'EXECUTIVE_ASSISTANT_HUMAN' AND wu.unit_status = 'ACTIVE'`);
  const companyPhone = one(`SELECT contact_value FROM trustride.user_contact WHERE user_id = '${company.user_id}' AND contact_type = 'PHONE' AND is_verified AND status = 'ACTIVE'`);
  const repPhone = one(`SELECT contact_value FROM trustride.user_contact WHERE user_id = '${rep.user_id}' AND contact_type = 'PHONE' AND is_verified AND status = 'ACTIVE'`);

  // ------------------------------------------------ housekeeping: the company cancels its own leftover open orders
  for (const lo of db(`SELECT order_id FROM trustride.business_order WHERE requester_user_id = '${company.user_id}' AND status IN ('WAITING','QUOTED','VALIDATED','PLACED')`)) {
    await C.goto(`${BASE}/dashboard`);
    const av = await C.locator('select[name="acting"] option', { hasText: "Akinyi Logistics" }).getAttribute("value");
    await C.locator('select[name="acting"]').selectOption(av); await C.getByRole("button", { name: "Act as" }).click(); await C.waitForLoadState("networkidle"); await sleep(800);
    await C.goto(`${BASE}/dashboard/orders/${lo.order_id}`);
    const lf = C.locator("form", { has: C.getByRole("button", { name: "Cancel order" }) });
    if (await lf.count()) { C.once("dialog", (d) => d.accept()); await press(C, "Cancel order", lf); }
  }
  await poll(async () => one(`SELECT trustride.fn_resource_unit_availability('${otieno.unit}') a`).a !== "ASSIGNED", { tries: 15, every: 2000 });

  // ------------------------------------------------ 0. Boda unavailable (Test A precondition)
  await O.goto(`${BASE}/office/operator`);
  if (await O.getByRole("button", { name: "End shift" }).count()) await press(O, "End shift");
  const pre = one(`SELECT trustride.fn_resource_unit_availability('${otieno.unit}') boda, trustride.fn_resource_unit_availability('${sedan.unit}') sedan, trustride.fn_resource_unit_availability('${ea.unit}') ea`);

  // ------------------------------------------------ 1. Company authentication + context
  await C.goto(`${BASE}/dashboard`);
  const actVal = await C.locator('select[name="acting"] option', { hasText: "Akinyi Logistics" }).getAttribute("value");
  await C.locator('select[name="acting"]').selectOption(actVal);
  await C.getByRole("button", { name: "Act as" }).click(); await C.waitForLoadState("networkidle"); await sleep(800);
  await C.goto(`${BASE}/dashboard/book`);
  const acting = /Akinyi Logistics Ltd \(acting\)/.test(await text(C));
  const sess = one(`SELECT session_id, user_id, acting_person_user_id, sub_shell, top_shell FROM trustride.present_shell_session WHERE user_id = '${company.user_id}' AND acting_person_user_id = '${rep.user_id}' AND sub_shell = 'CUSTOMER_APP' AND session_status = 'ACTIVE' ORDER BY started_at DESC LIMIT 1`);
  row("Company authentication", "Company (via representative)", "Representative signs in; Customer App opens as the company",
    acting ? `Shell shows "Akinyi Logistics Ltd (acting)"; session ${sess?.session_id?.slice(0, 8)} user=company, acting_person=representative` : "not acting",
    `present_shell_session: user_id=${company.user_id.slice(0, 8)} (${company.entity_type}, KRA ${company.kra_pin}), acting_person_user_id=${rep.user_id.slice(0, 8)}, sub_shell=${sess?.sub_shell}`,
    acting && sess && sess.user_id === company.user_id && sess.acting_person_user_id === rep.user_id);

  // ------------------------------------------------ 2-3. Boda selection + service form
  await C.getByRole("button", { name: /Boda/ }).first().click();
  const bookForm = () => C.locator("form", { has: C.getByRole("button", { name: /Request — we will show your fare/ }) });
  const sel = bookForm().locator("select");
  await sel.nth(0).selectOption("KSM-CBD-01"); await sel.nth(1).selectOption("KSM-MILIMANI-02");
  const notes = `Proof ${RUN}: deliver tender documents`;
  await bookForm().locator('input[maxlength="140"]').fill(notes);
  await C.getByRole("button", { name: /Request — we will show your fare/ }).click();
  await C.waitForURL(/\/dashboard\/orders\/[0-9a-f-]{36}/, { timeout: 30000 }).catch(() => {});
  const orderId = C.url().split("/").pop();
  const ord = await poll(async () => one(`SELECT o.order_id, o.order_code, o.correlation_id, o.service_code, o.requester_user_id, o.status, o.macro_domain, o.fulfilment_requirements->>'required_capacity_class_code' cls, o.dispatch_mode FROM trustride.business_order o WHERE o.order_id = '${orderId}' AND o.fulfilment_requirements ? 'required_capacity_class_code'`), { tries: 15, every: 2000 });
  row("Boda selection", "Company", "Service TRANSPORT-BODA-STANDARD; Engine 3 resolves required class BODA_BODA",
    `${ord?.order_code}: service ${ord?.service_code}, required class ${ord?.cls}`, `business_order.service_code, fulfilment_requirements.required_capacity_class_code`,
    ord?.service_code === "TRANSPORT-BODA-STANDARD" && ord?.cls === "BODA_BODA");
  await sleep(4000);
  const line = one(`SELECT line_sequence, line_description, scope_detail FROM trustride.business_order_line WHERE order_id = '${orderId}'`);
  row("Service form", "Company", "One stop CBD → Milimani with the company's note; distance and duration computed by TrustRide (not typed)",
    `${line?.scope_detail?.origin_zone_code} → ${line?.scope_detail?.destination_zone_code}, ${line?.scope_detail?.distance_km ?? "?"} km, ${line?.scope_detail?.duration_min ?? "?"} min; "${line?.line_description}"`,
    `business_order_line.scope_detail (distance from Engine 6 routing)`,
    line?.scope_detail?.origin_zone_code === "KSM-CBD-01" && line?.scope_detail?.destination_zone_code === "KSM-MILIMANI-02" && line?.line_description === notes);
  row("Order", "Company", "Order created owned by the company, not the representative",
    `${ord.order_code} requester=${ord.requester_user_id === company.user_id ? "Akinyi Logistics Ltd" : ord.requester_user_id}`,
    `business_order.requester_user_id = ${ord.requester_user_id.slice(0, 8)}; correlation ${ord.correlation_id.slice(0, 8)} = the RAISE_INTENT command`,
    ord.requester_user_id === company.user_id);

  // ------------------------------------------------ Test A: no eligible Boda -> WAITING (+ Test D1)
  const waiting = await poll(async () => one(`SELECT status FROM trustride.business_order WHERE order_id = '${orderId}'`).status === "WAITING", { tries: 20, every: 3000 });
  const unavailable = one(`SELECT count(*) n FROM trustride.business_event_inbox WHERE correlation_id = '${ord.correlation_id}' AND signal_type = 'RESOURCE_UNAVAILABLE'`);
  const told = await poll(async () => one(`SELECT title, body FROM trustride.present_notification_inbox WHERE recipient_user_id = '${company.user_id}' AND source_signal_correlation_id = '${ord.correlation_id}' AND title LIKE 'Finding you a%'`), { tries: 15, every: 2000 });
  await C.goto(`${BASE}/dashboard/orders/${orderId}`);
  row("Test A — unavailable Boda", "System", "No Boda on duty → RESOURCE_UNAVAILABLE → WAITING → company notified",
    `Boda unit ${pre.boda}; order ${waiting ? "WAITING" : "not waiting"}; ${unavailable.n} RESOURCE_UNAVAILABLE signal(s); company told "${told?.title}"; screen: ${/WAITING FOR A WORKER/i.test(await text(C)) ? "Waiting for a worker" : "?"}`,
    `business_event_inbox RESOURCE_UNAVAILABLE; present_notification_inbox to the company`, !!waiting && unavailable.n > 0 && !!told);
  const wrongReserved = one(`SELECT count(*) n FROM trustride.resource_availability_ledger WHERE job_ref_id = '${orderId}' AND resource_ref_id IN ('${sedan.unit}', '${ea.unit}')`);
  row("Test D1 — other classes free", "System", "Sedan and EA units are AVAILABLE, yet neither is reserved for the Boda order",
    `Sedan ${pre.sedan}, EA ${pre.ea}; reservations of either for this order: ${wrongReserved.n}`, `resource_availability_ledger by job_ref_id`, wrongReserved.n === 0 && pre.sedan === "AVAILABLE");

  // ------------------------------------------------ Test D2: inject a wrong-class reservation on a second company Boda order
  await C.goto(`${BASE}/dashboard/book`);
  await C.getByRole("button", { name: /Boda/ }).first().click();
  await bookForm().locator("select").nth(0).selectOption("KSM-CBD-01"); await bookForm().locator("select").nth(1).selectOption("KSM-KONDELE-03");
  await C.getByRole("button", { name: /Request — we will show your fare/ }).click();
  await C.waitForURL(/\/dashboard\/orders\/[0-9a-f-]{36}/, { timeout: 30000 }).catch(() => {});
  const xId = C.url().split("/").pop();
  await poll(async () => one(`SELECT status FROM trustride.business_order WHERE order_id = '${xId}'`).status === "WAITING", { tries: 20, every: 3000 });
  const x = one(`SELECT order_code, correlation_id, (SELECT order_line_id FROM trustride.business_order_line WHERE order_id = '${xId}' LIMIT 1) line FROM trustride.business_order WHERE order_id = '${xId}'`);
  // FAULT INJECTION: Engine 2 is made to reserve the SEDAN for this Boda order.
  dbExec(`SELECT trustride.fn_resource_reserve('${sedan.unit}', '${xId}', '${x.correlation_id}', '00000000-0000-0000-0000-000000000000', '${x.line}');`);
  await poll(async () => one(`SELECT count(*) n FROM trustride.business_event_inbox WHERE correlation_id = '${x.correlation_id}' AND signal_type = 'RESOURCE_RESERVED' AND signal_status <> 'RECEIVED'`).n > 0, { tries: 15, every: 2000 });
  await sleep(12000);
  const xs = one(`SELECT o.status, o.reserved_workforce_unit_id = '${sedan.unit}' sedan_held, (SELECT count(*) FROM trustride.business_job j WHERE j.order_id = o.order_id AND j.workforce_unit_id = '${sedan.unit}' AND j.status NOT IN ('CANCELLED','FAILED')) sedan_jobs, (SELECT count(*) FROM trustride.fare_quote q WHERE q.quote_id = o.quote_id) quotes, trustride.fn_resource_unit_availability('${sedan.unit}') sedan_now, (SELECT payload_out->>'rejected' FROM trustride.business_event_inbox WHERE correlation_id = o.correlation_id AND signal_type = 'RESOURCE_RESERVED' ORDER BY received_at DESC LIMIT 1) verdict FROM trustride.business_order o WHERE o.order_id = '${xId}'`);
  row("Test D2 — wrong-class reservation injected", "System (fault injection)", "A Sedan reserved for a Boda order is refused by Business: no job, no quote, Sedan released, order still waiting",
    `${x.order_code}: status ${xs.status}; Sedan jobs ${xs.sedan_jobs}; quotes ${xs.quotes}; Sedan now ${xs.sedan_now}; Business verdict: ${xs.verdict ?? "accepted"}`,
    `business_job / fare_quote / resource_availability_ledger after RESOURCE_RESERVED(capacity_class=SEDAN)`,
    xs.sedan_jobs === 0 && xs.quotes === 0 && xs.sedan_now === "AVAILABLE" && !xs.sedan_held);
  // clean up X through the company's own screen
  await C.goto(`${BASE}/dashboard/orders/${xId}`);
  const cf = C.locator("form", { has: C.getByRole("button", { name: "Cancel order" }) });
  if (await cf.count()) { C.once("dialog", (d) => d.accept()); await press(C, "Cancel order", cf); }

  // ------------------------------------------------ Boda becomes available -> retry -> matching -> assignment
  await O.goto(`${BASE}/office/operator`);
  await press(O, "Start shift");
  const quoted = await poll(async () => one(`SELECT status FROM trustride.business_order WHERE order_id = '${orderId}'`).status === "QUOTED", { tries: 100, every: 3000 });
  const asg = one(`SELECT j.job_id, j.status job_status, j.dispatched_at, wu.workforce_unit_id unit, cc.class_code cls, p.display_name operator, ob.plate_number plate, ob.object_type, trustride.fn_resource_unit_availability(wu.workforce_unit_id) avail,
      (SELECT availability_state FROM trustride.resource_availability_ledger WHERE resource_type='WORKFORCE_UNIT' AND resource_ref_id = wu.workforce_unit_id AND effective_to IS NULL) ledger_state,
      (SELECT count(*) FROM trustride.business_event_inbox WHERE correlation_id = '${ord.correlation_id}' AND signal_type = 'RESOURCE_UNAVAILABLE') unavailable_attempts,
      (SELECT status_reason FROM trustride.business_order WHERE order_id = '${orderId}') reason
    FROM trustride.business_job j JOIN trustride.resource_workforce_unit wu USING (workforce_unit_id) JOIN trustride.resource_capacity_class cc ON cc.capacity_class_id = wu.capacity_class_id
    JOIN trustride.platform_users p ON p.user_id = wu.operator_user_id JOIN trustride.resource_fleet_register f ON f.fleet_resource_id = wu.fleet_resource_id JOIN trustride.object_registry ob ON ob.object_id = f.object_id
    WHERE j.order_id = '${orderId}' AND j.status NOT IN ('CANCELLED','FAILED')`);
  row("Test A — retry after availability", "System", "Rider starts shift → next retry matches without any manual step",
    `${asg?.unavailable_attempts} unavailable attempt(s), then matched; order ${quoted ? "QUOTED" : "not quoted"}`, `dispatch sweep retry; ASSIGNMENT_REQUESTED/RESOURCE_RESERVED signals on the order's correlation`, !!quoted && !!asg);
  row("Matching", "System (Engine 2)", "Eligible Boda resource selected",
    `unit ${asg?.unit?.slice(0, 8)} class ${asg?.cls}; vehicle ${asg?.object_type} ${asg?.plate}`, `fn_resource_discover_eligible(BODA_BODA, …) → resource_workforce_unit / resource_fleet_register`, asg?.cls === "BODA_BODA" && asg?.object_type === "MOTORCYCLE");
  row("Assignment", "System (Engine 4)", "One job on the Boda unit + its operator; unit held for this order",
    `job ${asg?.job_id?.slice(0, 8)} ${asg?.job_status} → ${asg?.operator} on ${asg?.plate}; unit ${asg?.avail} (ledger ${asg?.ledger_state}); waiting reason now ${asg?.reason ?? "cleared"}`, `business_job.workforce_unit_id; resource_availability_ledger current row; business_order.status_reason`,
    asg?.operator === "Otieno Rider Test" && ["RESERVED", "ASSIGNED"].includes(asg?.avail) && !asg?.reason);

  // ------------------------------------------------ Quote + acceptance
  const q = one(`SELECT q.quote_id, q.quote_state, q.computed_total_fare_kes total, fc.requester_user_id calc_owner FROM trustride.business_order o JOIN trustride.fare_quote q ON q.quote_id = o.quote_id LEFT JOIN trustride.fare_calculation fc ON fc.calculation_id = q.calculation_id WHERE o.order_id = '${orderId}'`);
  await C.goto(`${BASE}/dashboard/orders/${orderId}`);
  const seen = (await text(C)).match(/Your fare: KES [\d,.]+/)?.[0];
  row("Quote", "Company", "Estimate persisted, owned by the company's order, shown to the company before anyone is dispatched",
    `${q.quote_state} KES ${q.total}; calculation owner ${q.calc_owner === company.user_id ? "company" : q.calc_owner}; screen: "${seen}"`,
    `fare_quote ${q.quote_id.slice(0, 8)} (Engine 5) ↔ business_order.quote_id; fare_calculation.requester_user_id`,
    q.quote_state === "FARE_ESTIMATED" && q.calc_owner === company.user_id && seen?.replace(/,/g, "").includes(String(Number(q.total))));
  // dispatch must not happen before acceptance
  const opApi = await signIn("operator@trustride.test");
  const opSess = await session(opApi, "TRUSTRIDE_OFFICE", "OPERATOR_APP", opApi.uid);
  const early = await cmd(opApi, opSess.id, "ACKNOWLEDGE_JOB", { job_id: asg.job_id });
  const jobBefore = one(`SELECT status, dispatched_at FROM trustride.business_job WHERE job_id = '${asg.job_id}'`);
  row("No dispatch before acceptance", "Operator", "Operator cannot accept/start before the company accepts the fare",
    `ACKNOWLEDGE_JOB → ${early.status}: ${early.reason}; job still ${jobBefore.status}, dispatched_at ${jobBefore.dispatched_at ?? "null"}`, `fn_present_command_execute as the operator`,
    early.status === "REJECTED" && jobBefore.status === "CREATED" && !jobBefore.dispatched_at);
  await press(C, "Accept fare");
  await poll(async () => one(`SELECT status FROM trustride.business_order WHERE order_id = '${orderId}'`).status !== "QUOTED", { tries: 20, every: 2000 });
  const acc = one(`SELECT q.quote_state, o.status, (SELECT row_to_json(c) FROM (SELECT c.command_type, c.translation_status, s.user_id, s.acting_person_user_id FROM trustride.present_command_capture c JOIN trustride.present_shell_session s ON s.session_id = c.shell_session_id WHERE c.command_type = 'ACCEPT_QUOTATION' AND c.command_payload->>'quote_id' = q.quote_id::text ORDER BY c.captured_at DESC LIMIT 1) c) cap, (SELECT computed_total_fare_kes FROM trustride.business_settlement WHERE order_id = o.order_id) settle_amt FROM trustride.business_order o JOIN trustride.fare_quote q ON q.quote_id = o.quote_id WHERE o.order_id = '${orderId}'`);
  row("Quote acceptance", "Company", "Company explicitly accepts; acceptance recorded against the company with the representative as actor; amount carried unchanged",
    `quote ${acc.quote_state}; order ${acc.status}; command ${acc.cap?.command_type} ${acc.cap?.translation_status} by session user ${acc.cap?.user_id === company.user_id ? "company" : "?"} acting person ${acc.cap?.acting_person_user_id === rep.user_id ? "representative" : "?"}; settlement amount KES ${acc.settle_amt}`,
    `present_command_capture + present_shell_session; business_settlement.computed_total_fare_kes`,
    acc.quote_state === "FARE_LOCKED" && acc.cap?.user_id === company.user_id && acc.cap?.acting_person_user_id === rep.user_id && Number(acc.settle_amt) === Number(q.total));

  // ------------------------------------------------ Operator notification + acceptance + progression
  const opNote = await poll(async () => one(`SELECT title, body FROM trustride.present_notification_inbox WHERE recipient_user_id = '${otieno.op}' AND source_signal_correlation_id = '${ord.correlation_id}' ORDER BY delivered_at DESC LIMIT 1`), { tries: 15, every: 2000 });
  row("Operator notification", "Operator", "Assigned operator told of the job (in-app + SMS)", `"${opNote?.title}" — ${opNote?.body?.slice(0, 80)}`, `present_notification_inbox recipient = Otieno`, !!opNote);
  await O.goto(`${BASE}/office/operator/${orderId}`);
  await poll(async () => { await O.goto(`${BASE}/office/operator/${orderId}`); return (await O.getByRole("button", { name: "Accept job" }).count()) > 0; }, { tries: 15, every: 2000 });
  const steps = [["Accept job", "ACKNOWLEDGED", "Operator acceptance"], ["Set off (dispatched)", "DISPATCHED", "Dispatch"], ["I'm on the way", "EN_ROUTE", "En route"]];
  async function advance(label, expect, stage) {
    await O.goto(`${BASE}/office/operator/${orderId}`);
    await press(O, label);
    const j = await poll(async () => { const r = one(`SELECT j.status, o.status ostatus, j.acknowledged_at, j.dispatched_at, j.arrived_at, j.completed_at, j.verified_at FROM trustride.business_job j JOIN trustride.business_order o USING (order_id) WHERE j.job_id = '${asg.job_id}'`); return r.status === expect ? r : null; }, { tries: 10, every: 1500 });
    const cap = one(`SELECT c.translation_status, s.user_id = '${otieno.op}' by_operator FROM trustride.present_command_capture c JOIN trustride.present_shell_session s ON s.session_id = c.shell_session_id WHERE c.command_payload->>'job_id' = '${asg.job_id}' ORDER BY c.captured_at DESC LIMIT 1`);
    await C.goto(`${BASE}/dashboard/orders/${orderId}`);
    const custView = (await text(C)).match(/(ACKNOWLEDGED|DISPATCHED|ON THE WAY|EN ROUTE|ARRIVED|IN PROGRESS|EXECUTING|COMPLETED|CONFIRMED)/i)?.[0];
    row(stage, "Operator", `Job → ${expect}, by the assigned operator, reflected in order and customer view`,
      `job ${j?.status ?? "?"}; order ${j?.ostatus}; command ${cap?.translation_status} by ${cap?.by_operator ? "Otieno" : "?"}; company screen shows "${custView}"`,
      `business_job timestamps; present_command_capture/session; ORDER_DETAIL projection`, !!j && cap?.translation_status === "TRANSLATED" && cap?.by_operator);
    return j;
  }
  for (const [l, e, s] of steps) await advance(l, e, s);

  // ------------------------------------------------ Tracking (Protrack -> Engine 6 -> Engine 2 -> Engine 4 -> projections)
  const key = fs.readFileSync(path.join(__dirname, "protrack.key"), "utf8").trim();
  const pts = [[-0.0917, 34.7680], [-0.0965, 34.7610], [-0.1002, 34.7562]].map(([lat, lng], i) => ({ imei: "PT-0001", lat, lng, gpstime: Math.floor(Date.now() / 1000) - (2 - i) * 15, speed: 31, course: 205, acc: 1 }));
  const ing = await fetch(`${env.API_URL}/rest/v1/rpc/fn_integration_telemetry_ingest`, { method: "POST",
    headers: { apikey: env.SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SERVICE_ROLE_KEY}`, "Content-Type": "application/json", "Content-Profile": "trustride" },
    body: JSON.stringify({ p_key: key, p_records: pts }) }).then((r) => r.json());
  const tr = await poll(async () => { const r = one(`SELECT t.tracking_status, t.resource_id_display, ST_Y(t.exact_location) lat, ST_X(t.exact_location) lon, (SELECT count(*) FROM trustride.resource_location_event le WHERE le.order_id = '${orderId}') events, (SELECT count(DISTINCT le.fleet_resource_id) FROM trustride.resource_location_event le WHERE le.order_id = '${orderId}') fleets, (SELECT bool_and(le.fleet_resource_id = '${otieno.fleet}') FROM trustride.resource_location_event le WHERE le.order_id = '${orderId}') right_fleet FROM trustride.business_tracking_session t WHERE t.job_id = '${asg.job_id}' AND t.ended_at IS NULL`); return r && r.events >= 3 && r.lat ? r : null; }, { tries: 15, every: 2000 });
  const custSb = await signIn("customer@trustride.test");
  const cSess = await session(custSb, "TRUSTRIDE_BUSINESS", "CUSTOMER_APP", company.user_id);
  const cView = await proj(custSb, cSess.id, "ORDER_DETAIL", { order_id: orderId });
  const fSb = await signIn("founder@trustride.test");
  const fSess = await session(fSb, "TRUSTRIDE_OFFICE", "ADMIN_CONSOLE", fSb.uid);
  const fView = await proj(fSb, fSess.id, "OFFICE_TRACKING");
  const selfSess = await session(custSb, "TRUSTRIDE_BUSINESS", "CUSTOMER_APP", rep.user_id);
  const selfView = await proj(custSb, selfSess.id, "ORDER_DETAIL", { order_id: orderId });
  const trackCmd = await cmd(custSb, cSess.id, "TRACK_ELEMENT", { job_id: asg.job_id, lat: -0.1, lon: 34.7 });
  row("Tracking", "System → Company/Office", "Protrack points → Engine 6 (key) → Boda's fleet resource → location events on this order → tracking session → company sees its own trip; Office sees device; nobody else; customer cannot write telemetry",
    `ingest ${ing.outcome} ${ing.accepted} pts; ${tr?.events} location events, all on KMFA123B's fleet: ${tr?.right_fleet}; session ${tr?.tracking_status} at ${tr?.lat},${tr?.lon}; company projection lat ${cView?.tracking?.lat}; Office device ${(fView?.vehicles ?? []).find((v) => v.device === "PT-0001")?.status}; representative's personal identity: "${selfView?.error ?? "SAW IT"}"; customer TRACK_ELEMENT: ${trackCmd.status}`,
    `integration_telemetry_ingest_log; resource_location_event.order_id/fleet_resource_id; business_tracking_session; ORDER_DETAIL / OFFICE_TRACKING projections`,
    ing.outcome === "ACCEPTED" && tr?.right_fleet && Number(cView?.tracking?.lat) === Number(tr?.lat) && !!selfView?.error && trackCmd.status !== "TRANSLATED");

  // ------------------------------------------------ Test B: unauthorized actions mid-journey (no mutation)
  const snapBefore = one(`SELECT (SELECT status FROM trustride.business_job WHERE job_id = '${asg.job_id}') job, (SELECT status FROM trustride.business_order WHERE order_id = '${orderId}') ord, (SELECT count(*) FROM trustride.present_command_capture WHERE translation_status = 'TRANSLATED') translated`);
  const b1 = await cmd(custSb, cSess.id, "EMIT_PROGRESS_SIGNAL", { job_id: asg.job_id });
  const otherOrder = one(`SELECT order_id FROM trustride.business_order WHERE requester_user_id = '${rep.user_id}' AND order_root_type = 'SERVICE_ORDER' LIMIT 1`);
  const b2 = await proj(custSb, cSess.id, "ORDER_DETAIL", { order_id: otherOrder.order_id });
  const b3 = await proj(custSb, cSess.id, "OFFICE_ORDERS");
  const b4 = await session(custSb, "TRUSTRIDE_OFFICE", "ADMIN_CONSOLE", company.user_id);
  const pay = await custSb.from("integration_payment_gateway_transaction").select("requester_user_id");
  const units = await custSb.from("resource_workforce_unit").select("operator_user_id");
  const eaSb = await signIn("eaworker@trustride.test");
  const eaSess = await session(eaSb, "TRUSTRIDE_OFFICE", "OPERATOR_APP", eaSb.uid);
  const b5 = await cmd(eaSb, eaSess.id, "EMIT_PROGRESS_SIGNAL", { job_id: asg.job_id });
  const b6 = await proj(eaSb, eaSess.id, "OPERATOR_JOB", { order_id: orderId });
  const b7 = await opApi.from("business_order").select("requester_user_id").eq("order_id", orderId);
  const b8 = await proj(opApi, opSess.id, "OFFICE_USERS");
  const b9 = await session(opApi, "TRUSTRIDE_OFFICE", "ADMIN_CONSOLE", opApi.uid);
  const snapAfter = one(`SELECT (SELECT status FROM trustride.business_job WHERE job_id = '${asg.job_id}') job, (SELECT status FROM trustride.business_order WHERE order_id = '${orderId}') ord, (SELECT count(*) FROM trustride.present_command_capture WHERE translation_status = 'TRANSLATED') translated`);
  const denied = [
    ["company operates the job (EMIT_PROGRESS_SIGNAL)", b1.status !== "TRANSLATED", b1.reason],
    ["company opens another customer's order", !!b2.error, b2.error],
    ["company reads Office orders", !!b3.error, b3.error],
    ["company opens the Admin Console", !!b4.error, b4.error],
    ["company reads other customers' payments", (pay.data ?? []).every((r) => r.requester_user_id === company.user_id || r.requester_user_id === rep.user_id), `${(pay.data ?? []).length} own rows only`],
    ["company reads operator records", (units.data ?? []).length === 0 || !!units.error, units.error?.message ?? `${(units.data ?? []).length} rows`],
    ["another operator progresses Otieno's job", b5.status !== "TRANSLATED", b5.reason],
    ["another operator opens Otieno's job", !!b6.error, b6.error],
    ["operator reads the company's order table row", (b7.data ?? []).length === 0, `${(b7.data ?? []).length} rows`],
    ["operator reads Office users", !!b8.error, b8.error],
    ["operator opens the Admin Console", !!b9.error, b9.error],
  ];
  const noMut = snapBefore.job === snapAfter.job && snapBefore.ord === snapAfter.ord && snapBefore.translated === snapAfter.translated;
  for (const [what, ok, why] of denied) row(`Test B — ${what}`, what.startsWith("company") ? "Company" : "Operator", "DENIED", ok ? `denied: ${String(why).slice(0, 110)}` : `ALLOWED: ${why}`, "Data API as that actor", ok);
  row("Test B — no unauthorized mutation", "System", "Job, order and translated-command count unchanged by every denied attempt", `before ${JSON.stringify(snapBefore)} after ${JSON.stringify(snapAfter)}`, "database snapshot", noMut);

  // ------------------------------------------------ Arrival, execution, completion, verification
  await advance("I've arrived", "ARRIVED", "Arrival");
  await advance("Start service", "EXECUTING", "Execution");
  await advance("Complete this stop", "COMPLETED", "Completion");
  await O.goto(`${BASE}/office/operator/${orderId}`);
  const vb = O.getByRole("button", { name: /Verify and close/ });
  if (await vb.count()) await press(O, await vb.first().textContent());
  const ver = await poll(async () => one(`SELECT j.status, j.verified_at, trustride.fn_resource_unit_availability('${otieno.unit}') unit_now, (SELECT ended_at FROM trustride.business_tracking_session WHERE job_id = j.job_id) track_end FROM trustride.business_job j WHERE j.job_id = '${asg.job_id}' AND j.status = 'VERIFIED' AND trustride.fn_resource_unit_availability('${otieno.unit}') = 'AVAILABLE'`), { tries: 20, every: 2000 });
  const cAfter = await proj(custSb, cSess.id, "ORDER_DETAIL", { order_id: orderId });
  row("Verification + release", "Operator → System", "Job VERIFIED; Boda unit back to AVAILABLE; tracking ended and no longer projected",
    `job ${ver?.status}; unit ${ver?.unit_now}; tracking ended ${ver?.track_end ? "yes" : "no"}; company projection tracking=${cAfter?.tracking === null ? "none" : JSON.stringify(cAfter?.tracking)}`,
    `business_job.verified_at; fn_resource_unit_availability; business_tracking_session.ended_at`, ver?.unit_now === "AVAILABLE" && !!ver?.track_end && cAfter?.tracking === null);

  // ------------------------------------------------ Payment
  const txn = await poll(async () => one(`SELECT gateway_txn_id, requester_user_id, amount_kes, msisdn_masked, txn_status, adapter_type, payment_rail, account_reference FROM trustride.integration_payment_gateway_transaction WHERE order_id = '${orderId}' ORDER BY initiated_at DESC LIMIT 1`), { tries: 20, every: 2000 });
  const phoneTail = (companyPhone?.contact_value ?? "").slice(-3);
  row("Payment", "System → Company", "M-Pesa STK request for the accepted amount, payer = the company, to the company's own verified phone (not the representative's)",
    `${txn?.payment_rail} ${txn?.adapter_type} KES ${txn?.amount_kes} to ${txn?.msisdn_masked}; payer ${txn?.requester_user_id === company.user_id ? "Akinyi Logistics Ltd" : txn?.requester_user_id}; company phone …${phoneTail}, representative phone …${(repPhone?.contact_value ?? "").slice(-3)}; ${txn?.txn_status}`,
    `integration_payment_gateway_transaction (Engine 6 payment port); fn_user_payment_msisdn(company)`,
    txn?.requester_user_id === company.user_id && Number(txn?.amount_kes) === Number(q.total) && txn?.msisdn_masked?.endsWith(phoneTail) && txn?.txn_status === "PENDING_CALLBACK");
  await C.goto(`${BASE}/dashboard/orders/${orderId}`);
  await poll(async () => { await C.goto(`${BASE}/dashboard/orders/${orderId}`); return (await C.getByRole("button", { name: "Approve (staging M-Pesa simulator)" }).count()) > 0; }, { tries: 10, every: 2000 });
  await press(C, "Approve (staging M-Pesa simulator)");
  const st = await poll(async () => one(`SELECT s.payment_status, s.computed_total_fare_kes amt, s.initiated_at, s.settled_at, s.ledger_posted_at, s.receipt_code, s.receipt_generated_at, o.status ostatus, t.txn_status, t.mpesa_receipt_number, t.settled_at t_settled FROM trustride.business_settlement s JOIN trustride.business_order o USING (order_id) JOIN trustride.integration_payment_gateway_transaction t ON t.order_id = o.order_id WHERE s.order_id = '${orderId}' AND s.payment_status = 'RECEIPT_GENERATED'`), { tries: 20, every: 2000 });
  row("M-Pesa payment state", "Company → Engine 6", "Callback/confirmation moves the payment PENDING_CALLBACK → SETTLED", `txn ${st?.txn_status} at ${st?.t_settled}; provider ref ${st?.mpesa_receipt_number ?? "(simulator)"}`, `integration_payment_gateway_transaction; PAYMENT_SETTLED signal`, st?.txn_status === "SETTLED");
  row("Settlement", "System (Engine 4)", "Settlement for the same order and amount", `settled ${st?.settled_at}; KES ${st?.amt}; order ${st?.ostatus}`, `business_settlement`, !!st?.settled_at && Number(st?.amt) === Number(q.total) && st?.ostatus === "SETTLED");
  row("Ledger", "System (Engine 4)", "Ledger posted before the receipt (Article 43)", `ledger_posted_at ${st?.ledger_posted_at}`, `business_settlement.ledger_posted_at; CHECK chk_business_settlement_receipt forbids a receipt without it`, !!st?.ledger_posted_at);
  await C.goto(`${BASE}/dashboard/orders/${orderId}`);
  const rcScreen = (await text(C)).match(/TRS026-RECEIPT-\d+/)?.[0];
  const sms = await poll(async () => one(`SELECT d.payload->>'destination_masked' destination, d.payload->>'body' body FROM trustride.integration_notification_dispatch_log d WHERE d.recipient_ref = '${company.user_id}' AND d.payload->>'body' ILIKE '%${st?.receipt_code}%' ORDER BY d.created_at DESC LIMIT 1`), { tries: 20, every: 3000 });
  row("Receipt", "Company", "Receipt generated for the company's order; shown to the company; payment SMS to the company's number",
    `${st?.receipt_code} on screen: ${rcScreen === st?.receipt_code}; SMS to …${(sms?.destination ?? "").slice(-3)}: "${sms?.body?.slice(0, 60)}"`,
    `business_settlement.receipt_code; ORDER_DETAIL; integration_notification_dispatch_log`, !!st?.receipt_code && rcScreen === st?.receipt_code && (sms?.destination ?? "").endsWith(phoneTail) && (sms?.body ?? "").includes(st?.receipt_code));

  // ------------------------------------------------ Test C: duplicate payment
  const cnt = () => one(`SELECT (SELECT count(*) FROM trustride.business_settlement WHERE order_id = '${orderId}') settlements, (SELECT count(*) FROM trustride.business_settlement WHERE order_id = '${orderId}' AND receipt_code IS NOT NULL) receipts, (SELECT receipt_code FROM trustride.business_settlement WHERE order_id = '${orderId}') receipt, (SELECT ledger_posted_at FROM trustride.business_settlement WHERE order_id = '${orderId}') ledger, (SELECT count(*) FROM trustride.integration_payment_gateway_transaction WHERE order_id = '${orderId}' AND txn_status = 'SETTLED') settled_txns, (SELECT count(*) FROM trustride.business_event_outbox WHERE correlation_id = '${ord.correlation_id}' AND signal_type = 'ORDER_SETTLED') settled_signals, (SELECT count(*) FROM trustride.business_event_inbox WHERE signal_type = 'PAYMENT_SETTLED' AND payload_in->>'order_id' = '${orderId}' AND signal_status = 'ACCEPTED') accepted_settlements`);
  const c0 = cnt();
  const c1 = await cmd(custSb, cSess.id, "CONFIRM_SIMULATED_PAYMENT", { order_id: orderId });
  const c2 = await cmd(custSb, cSess.id, "RETRY_PAYMENT", { order_id: orderId });
  // FAULT INJECTION: Engine 6 delivers the callback again, and the PAYMENT_SETTLED signal is redelivered to Business.
  let c3 = "";
  try { c3 = dbExec(`SELECT trustride.fn_integration_payment_callback_simulate('${txn.gateway_txn_id}', 'SETTLED');`); } catch (e) { c3 = "refused: " + String(e.stderr || e.message).split("\n")[0].slice(0, 120); }
  const redeliver = dbExec(`WITH s AS (SELECT * FROM trustride.business_event_inbox WHERE signal_type = 'PAYMENT_SETTLED' AND payload_in->>'order_id' = '${orderId}' ORDER BY received_at LIMIT 1),
    ins AS (INSERT INTO trustride.business_event_inbox (correlation_id, causation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key, emitted_at)
      SELECT correlation_id, causation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key || ':REPLAY:${RUN}', now() FROM s RETURNING signal_id)
    SELECT trustride.fn_business_payment_settled_accept(signal_id) FROM ins;`);
  await sleep(12000);
  const c4 = cnt();
  row("Test C — duplicate payment", "Company / Engine 6 (replay)", "Second confirmation and retry refused; replayed callback and redelivered PAYMENT_SETTLED change nothing",
    `confirm again → ${c1.status} (${c1.reason}); retry → ${c2.status} (${c2.reason}); callback replay → ${c3 || "no-op"}; redelivered settlement → ${redeliver}; counts before ${JSON.stringify(c0)} after ${JSON.stringify(c4)}`,
    `business_settlement / receipts / settled txns / ORDER_SETTLED signals`,
    c1.status !== "TRANSLATED" && c2.status !== "TRANSLATED" && JSON.stringify(c0) === JSON.stringify(c4) && c4.settlements === 1 && c4.receipts === 1);

  // ------------------------------------------------ Identity survival
  const ident = one(`SELECT
     (SELECT requester_user_id FROM trustride.business_order WHERE order_id = '${orderId}') order_owner,
     (SELECT fc.requester_user_id FROM trustride.fare_quote q JOIN trustride.fare_calculation fc ON fc.calculation_id = q.calculation_id WHERE q.quote_id = '${q.quote_id}') quote_owner,
     (SELECT payload_in->>'requester_user_id' FROM trustride.business_event_outbox WHERE correlation_id = '${ord.correlation_id}' AND signal_type = 'RESOURCE_ASSIGNMENT_CONFIRMED' ORDER BY emitted_at DESC LIMIT 1) assignment_requester,
     (SELECT requester_user_id FROM trustride.integration_payment_gateway_transaction WHERE gateway_txn_id = '${txn.gateway_txn_id}') payer,
     (SELECT payload_in->>'requester_user_id' FROM trustride.business_event_outbox WHERE correlation_id = '${ord.correlation_id}' AND signal_type = 'ORDER_SETTLED' LIMIT 1) receipt_owner,
     (SELECT count(DISTINCT recipient_user_id) FROM trustride.present_notification_inbox WHERE source_signal_correlation_id = '${ord.correlation_id}' AND recipient_user_id = '${rep.user_id}') rep_notified,
     (SELECT count(*) FROM trustride.present_command_capture c JOIN trustride.present_shell_session s ON s.session_id = c.shell_session_id WHERE s.user_id = '${company.user_id}' AND s.acting_person_user_id = '${rep.user_id}' AND (c.command_payload->>'order_id' = '${orderId}' OR c.command_payload->>'quote_id' = '${q.quote_id}' OR c.translated_signal_id = '${orderId}' OR c.command_id = '${ord.correlation_id}')) company_commands`);
  const allCo = ["order_owner", "quote_owner", "assignment_requester", "payer", "receipt_owner"].every((k) => ident[k] === company.user_id);
  row("Identity survival", "All engines", "Company identity at order, quote, assignment, payment and receipt; representative recorded as the acting person, never as owner",
    `order/quote/assignment/payer/receipt all = company: ${allCo}; company commands with representative as acting person: ${ident.company_commands}; notifications addressed to the representative personally: ${ident.rep_notified}`,
    `business_order, fare_calculation, RESOURCE_ASSIGNMENT_CONFIRMED payload, payment txn, ORDER_SETTLED payload, present_shell_session.acting_person_user_id`,
    allCo && ident.company_commands >= 2 && ident.rep_notified === 0);

  // ------------------------------------------------ Cross-engine trace
  const trace = db(`SELECT engine, signal_type, signal_status, count(*) n FROM (
      ${["business", "resource", "service", "cost", "integration", "present"].map((e) => `SELECT '${e}' engine, signal_type, signal_status::text FROM trustride.${e}_event_inbox WHERE correlation_id = '${ord.correlation_id}' OR payload_in->>'order_id' = '${orderId}'`).join(" UNION ALL ")}) s
    GROUP BY 1, 2, 3 ORDER BY 1, 2, 3`);
  const badSignals = trace.filter((t) => !["ACCEPTED"].includes(t.signal_status) && !(t.signal_type === "PAYMENT_SETTLED" && t.signal_status === "REJECTED"));
  const dead = one(`SELECT count(*) n FROM trustride.dead_letter_review d WHERE d.event_id IN (SELECT signal_id FROM trustride.business_event_inbox WHERE correlation_id = '${ord.correlation_id}' UNION SELECT signal_id FROM trustride.resource_event_inbox WHERE correlation_id = '${ord.correlation_id}' UNION SELECT signal_id FROM trustride.cost_event_inbox WHERE correlation_id = '${ord.correlation_id}' UNION SELECT signal_id FROM trustride.integration_event_inbox WHERE correlation_id = '${ord.correlation_id}' UNION SELECT signal_id FROM trustride.present_event_inbox WHERE correlation_id = '${ord.correlation_id}' UNION SELECT signal_id FROM trustride.service_event_inbox WHERE correlation_id = '${ord.correlation_id}')`);
  row("Cross-engine continuity", "Engines 2,3,4,5,6,11", "Every signal on this transaction delivered and accepted (only the deliberately replayed settlement rejected); nothing dead-lettered",
    `${trace.reduce((a, t) => a + Number(t.n), 0)} signals across ${new Set(trace.map((t) => t.engine)).size} engines; not accepted: ${badSignals.length ? JSON.stringify(badSignals) : "none"}; dead letters: ${dead.n}`,
    `*_event_inbox by correlation_id ${ord.correlation_id.slice(0, 8)}`, badSignals.length === 0 && dead.n === 0);

  // ------------------------------------------------ Database integrity
  const integ = one(`SELECT
    (SELECT count(*) FROM trustride.business_order WHERE order_id = '${orderId}') orders,
    (SELECT count(*) FROM trustride.business_order_line WHERE order_id = '${orderId}') lines,
    (SELECT count(*) FROM trustride.fare_quote q JOIN trustride.business_order o ON o.quote_id = q.quote_id WHERE o.order_id = '${orderId}' AND q.quote_state IN ('FARE_LOCKED','SERVICE_IN_PROGRESS','FARE_FINALIZED','C2B_PAYMENT_TRIGGERED')) accepted_quotes,
    (SELECT count(*) FROM trustride.business_job WHERE order_id = '${orderId}' AND status NOT IN ('CANCELLED','FAILED')) live_jobs,
    (SELECT count(*) FROM trustride.business_job WHERE order_id = '${orderId}' AND status = 'VERIFIED') verified_jobs,
    (SELECT count(*) FROM trustride.business_job j JOIN trustride.resource_workforce_unit wu USING (workforce_unit_id) JOIN trustride.resource_capacity_class cc ON cc.capacity_class_id = wu.capacity_class_id WHERE j.order_id = '${orderId}' AND cc.class_code <> 'BODA_BODA') wrong_class_jobs,
    (SELECT count(DISTINCT workforce_unit_id) FROM trustride.business_job WHERE order_id = '${orderId}') units,
    (SELECT count(*) FROM trustride.integration_payment_gateway_transaction WHERE order_id = '${orderId}') payments,
    (SELECT count(*) FROM trustride.integration_payment_gateway_transaction WHERE order_id = '${orderId}' AND txn_status = 'SETTLED') settled_payments,
    (SELECT count(*) FROM trustride.business_settlement WHERE order_id = '${orderId}') settlements,
    (SELECT count(*) FROM trustride.business_settlement WHERE order_id = '${orderId}' AND ledger_posted_at IS NOT NULL) ledger_postings,
    (SELECT count(*) FROM trustride.business_settlement WHERE order_id = '${orderId}' AND receipt_code IS NOT NULL) receipts,
    (SELECT count(*) FROM trustride.resource_availability_ledger WHERE job_ref_id = '${orderId}' AND effective_to IS NULL AND availability_state IN ('RESERVED','ASSIGNED')) stale_reservations,
    (SELECT count(*) FROM trustride.business_tracking_session t JOIN trustride.business_job j USING (job_id) WHERE j.order_id = '${orderId}' AND t.ended_at IS NULL) open_tracking,
    (SELECT status FROM trustride.business_order WHERE order_id = '${orderId}') final_status,
    trustride.fn_resource_unit_availability('${otieno.unit}') boda_unit,
    (SELECT availability_state || ' (' || reason_code || ')' FROM trustride.resource_availability_ledger WHERE resource_type = 'FLEET' AND resource_ref_id = '${otieno.fleet}' AND effective_to IS NULL) boda_fleet,
    (SELECT count(*) FROM trustride.business_job j WHERE j.order_id IN ('${orderId}', '${xId}') AND j.status NOT IN ('VERIFIED','CANCELLED','FAILED')) orphan_jobs,
    (SELECT count(*) FROM trustride.integration_payment_gateway_transaction t WHERE t.order_id = '${orderId}' AND t.txn_status = 'PENDING_CALLBACK') open_payments,
    (SELECT status FROM trustride.business_order WHERE order_id = '${xId}') injected_order_status`);
  const integOk = integ.orders === 1 && integ.lines === 1 && integ.accepted_quotes === 1 && integ.live_jobs === 1 && integ.verified_jobs === 1 && integ.wrong_class_jobs === 0 && integ.units === 1
    && integ.payments === 1 && integ.settled_payments === 1 && integ.settlements === 1 && integ.ledger_postings === 1 && integ.receipts === 1
    && integ.stale_reservations === 0 && integ.open_tracking === 0 && integ.boda_fleet === "ASSIGNED (BOUND_TO_WORKFORCE_UNIT)" && integ.final_status === "SETTLED" && integ.boda_unit === "AVAILABLE" && integ.orphan_jobs === 0 && integ.open_payments === 0;
  row("Database integrity", "System", "1 order, 1 scope line, 1 accepted estimate, 1 Boda job (verified) on 1 unit, 1 payment, 1 settlement, 1 ledger posting, 1 receipt; no stale reservation, orphan, duplicate or open state; Boda unit back to AVAILABLE; motorcycle still bound to its unit",
    JSON.stringify(integ), `direct counts after completion`, integOk);

  // audit trail
  const audit = db(`SELECT action, count(*) n FROM trustride.audit_log WHERE occurred_at > now() - interval '1 hour' AND (entity_id IN ('${orderId}', '${txn.gateway_txn_id}', '${asg.job_id}', '${company.user_id}') OR after_snapshot::text LIKE '%${orderId}%') GROUP BY 1 ORDER BY 1`);
  const decisions = one(`SELECT count(*) n FROM trustride.present_decision_log d JOIN trustride.present_command_capture c USING (command_id) JOIN trustride.present_shell_session s ON s.session_id = c.shell_session_id WHERE s.user_id IN ('${company.user_id}', '${otieno.op}') AND c.captured_at > now() - interval '1 hour'`);
  row("Audit trail", "System", "Every command by the company and the operator is in the hash-chained decision log; key changes audited",
    `${decisions.n} decision-log entries for company/operator commands this hour; audit actions: ${audit.map((a) => `${a.action}×${a.n}`).join(", ") || "none"}`, `present_decision_log (hash chain), audit_log`, decisions.n >= 8);

  fs.writeFileSync(path.join(__dirname, `proof-${RUN}.json`), JSON.stringify({ order: ord.order_code, orderId, injected: x.order_code, rows, trace, integ, audit }, null, 1));
  await C.locator('select[name="acting"]').selectOption(""); await C.getByRole("button", { name: "Act as" }).click(); await C.waitForLoadState("networkidle");
  await cust.save(); await opA.save();
  await b.close();
  const failed = rows.filter((r) => r.status === "FAIL");
  console.log(`\n${rows.length - failed.length}/${rows.length} PASS — ${ord.order_code}`);
})().catch((e) => { console.error("PROOF ABORTED:", e); process.exit(1); });
