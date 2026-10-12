// Journey -- a customer books an Executive Assistant by the day through the real
// screen and sees the statutory fare (Construction Directive WP3, D24). Checks the
// fare on screen equals the EA-STATUTORY-1.0.0 estimate recorded for the order,
// that the order shows "2 days × 8 hours", then declines (nothing is charged).
// Runs after j2 (Achieng Assistant Test formed into an EA unit with SKILL_ERRANDS).
const { execSync } = require("child_process");
const { BASE, browser, actor, step, press, formError, poll, writeResults } = require("./lib");

const DB = process.env.TRS_DB_CONTAINER || "supabase_db_TrustRide-Services";
const sql = (q) => execSync(`docker exec -i ${DB} psql -U supabase_admin -d postgres -X -A -t -q`, { input: q, env: { ...process.env, MSYS_NO_PATHCONV: "1" } }).toString().trim();
const text = async (p) => (await p.locator("body").innerText()).replace(/\s+/g, " ");

(async () => {
  const b = await browser();
  // The assistant is on duty.
  const ea = await actor(b, "eaworker");
  await ea.page.goto(`${BASE}/office/operator`);
  const on = ea.page.getByRole("button", { name: /Start shift|Go on duty/i });
  if (await on.count()) await press(ea.page, await on.first().textContent());
  await ea.save(); await ea.ctx.close();

  const cust = await actor(b, "customer"); const C = cust.page;
  await C.goto(`${BASE}/dashboard/book`);
  await C.getByRole("button", { name: "Executive Assistants", exact: true }).click();
  await C.getByRole("button", { name: /Errands/i }).first().click();
  const form = C.locator("form", { has: C.getByRole("button", { name: /Request — we will show your fare/ }) });
  await form.locator("select").nth(1).selectOption("DAYS");                       // Book: by the day
  await form.getByLabel(/^Days/).fill("2");
  await form.getByLabel(/Hours each day/).fill("8");
  step("EA form offers booking by the day, with the legal basis stated", (await text(C)).includes("Regulation of Wages (General) Order"));
  await press(C, "Request — we will show your fare before anyone is dispatched", form);
  await C.waitForURL(/\/dashboard\/orders\/[0-9a-f-]{36}/, { timeout: 30000 }).catch(() => {});
  const url = C.url(); const orderId = /orders\/([0-9a-f-]{36})/.exec(url)?.[1];
  step("order placed", !!orderId, url + " " + (await formError(form)));
  if (orderId) {
    const fare = await poll(async () => { await C.goto(url); const m = /Your fare: KES ([\d,\.]+)/.exec(await text(C)); return m?.[1]; }, { tries: 30, every: 2000 });
    const db = sql(`SELECT e.total_kes || '|' || c.model_version || '|' || q.computed_total_fare_kes || '|' ||
        (SELECT count(*) FROM trustride.cost_ea_engagement_line l WHERE l.estimate_id = e.estimate_id AND l.component_code = 'EA_WORKER_PAY_DAILY' AND l.quantity = 2)
      FROM trustride.business_order o JOIN trustride.fare_quote q ON q.quote_id = o.quote_id
      JOIN trustride.fare_calculation c ON c.calculation_id = q.calculation_id
      JOIN trustride.cost_ea_engagement_estimate e ON e.calculation_id = c.calculation_id WHERE o.order_id = '${orderId}'`);
    const [estTotal, model, quoteTotal, dailyLines] = db.split("|");
    step("the fare shown is the statutory estimate (EA-STATUTORY-1.0.0)", !!fare && model === "EA-STATUTORY-1.0.0"
      && Number(fare.replace(/,/g, "")) === Number(quoteTotal) && Number(quoteTotal) === Number(estTotal), `screen ${fare} quote ${quoteTotal} estimate ${estTotal} ${model}`);
    step("priced on the gazetted daily rate for 2 days", dailyLines === "1", `daily lines ${dailyLines}`);
    step("the order shows 2 days × 8 hours", /2 days × 8 hours/.test(await text(C)));
    C.once("dialog", (d) => d.accept());
    if (await C.getByRole("button", { name: "Decline", exact: true }).count()) await press(C, "Decline");
    const st = await poll(async () => sql(`SELECT status FROM trustride.business_order WHERE order_id = '${orderId}'`).match(/CANCELLED|DECLINED/)?.[0], { tries: 10, every: 1500 });
    step("customer declines; the order ends without a charge", !!st && sql(`SELECT count(*) FROM trustride.integration_payment_gateway_transaction WHERE order_id = '${orderId}'`) === "0", st ?? "still open");
  }
  await cust.save(); await b.close();
  writeResults("results.json");
})();
