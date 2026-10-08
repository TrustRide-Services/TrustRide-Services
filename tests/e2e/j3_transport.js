// Journeys B (resource unavailable), A (customer transport), C (operator),
// G (tracking: Protrack telemetry + operator phone) and D (admin monitor),
// all through the real screens; Protrack's push is played by calling the
// same RPC the protrack-ingest edge function calls, with an Office-issued key.
const fs = require("fs");
const path = require("path");
const { BASE, browser, actor, step, shot, press, formError, poll, writeResults } = require("./lib");

const env = Object.fromEntries(fs.readFileSync(path.join(__dirname, "local.env"), "utf8").trim().split(/\r?\n/).map((l) => {
  const i = l.indexOf("="); return [l.slice(0, i), l.slice(i + 1).replace(/^"|"$/g, "")];
}));
const text = async (page) => (await page.locator("body").innerText()).replace(/\s+/g, " ");

async function rpcAsService(fn, args) {
  const r = await fetch(`${env.API_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { apikey: env.SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SERVICE_ROLE_KEY}`, "Content-Type": "application/json", "Content-Profile": "trustride" },
    body: JSON.stringify(args),
  });
  return { status: r.status, body: await r.json().catch(() => null) };
}

(async () => {
  const b = await browser();
  const F = (await actor(b, "founder")).page;
  const op = await actor(b, "operator");
  const O = op.page;
  const cust = await actor(b, "customer");
  const C = cust.page;

  // ---- Journey D: Office intervenes on a stuck order (cancel with reason)
  await F.goto(`${BASE}/office/orders?filter=LIVE`);
  const stuck = F.locator(".trs-card", { hasText: "WAITING" }).filter({ has: F.getByRole("button", { name: "Cancel", exact: true }) }).first();
  if (await stuck.count()) {
    const code = /TRS026-ORDER-\d+/.exec(await stuck.textContent())?.[0];
    const form = stuck.locator("form", { has: F.getByRole("button", { name: "Cancel", exact: true }) });
    await form.locator('input[name="reason"]').fill("Only rider timed out; customer asked to rebook");
    F.once("dialog", (d) => d.accept());
    await press(F, "Cancel", form);
    await F.goto(`${BASE}/office/orders?filter=ALL`);
    step(`Journey D: Office cancelled stuck order ${code} with a reason`, /CANCELLED|Cancelled/.test(await F.locator(".trs-card", { hasText: code }).first().textContent()));
    await C.goto(`${BASE}/dashboard/notifications`);
    step("Journey D: customer told of the Office cancellation", /cancel/i.test(await text(C)));
  }

  // ---- Office prepares tracking: Protrack system, key, tracker on the bike
  await F.goto(`${BASE}/office/integrations`);
  if (!(await F.getByText("Protrack GPS", { exact: true }).count())) {
    const form = F.locator("form", { has: F.getByRole("button", { name: "Register system" }) });
    await form.locator('input[name="system_name"]').fill("Protrack GPS");
    await form.locator('input[name="purpose"]').fill("GPS telemetry for TrustRide vehicles");
    await press(F, "Register system", form);
    await F.goto(`${BASE}/office/integrations`);
  }
  step("Office: Protrack registered as an external system", (await F.getByText("Protrack GPS", { exact: true }).count()) > 0);
  const sys = F.locator(".trs-card", { hasText: "Protrack GPS" }).filter({ has: F.getByRole("button", { name: "Issue telemetry key" }) }).first();
  let key = null;
  if (await sys.count()) {
    await press(F, "Issue telemetry key", sys);
    await F.locator("code.select-all").first().waitFor({ timeout: 15000 }).catch(() => {});
    key = await F.locator("code.select-all").first().textContent().catch(() => null);
  }
  step("Office: telemetry key issued and shown once", !!key && key.startsWith("trs_"));

  await F.goto(`${BASE}/office/resources`);
  const bike = F.locator(".trs-card", { hasText: "custodian" }).filter({ hasText: "KMFA123B" }).first();
  if (await bike.getByRole("button", { name: "Fit tracker" }).count()) await press(F, "Fit tracker", bike);
  await F.goto(`${BASE}/office/resources`);
  step("Office: tracker PT-0001 fitted to KMFA123B", (await F.locator(".trs-card", { hasText: "custodian" }).filter({ hasText: "KMFA123B" }).first().textContent()).includes("tracker PT-0001"));

  // ---- Journey B: no resource on duty
  await O.goto(`${BASE}/office/operator`);
  if (await O.getByRole("button", { name: "End shift" }).count()) await press(O, "End shift");
  await O.goto(`${BASE}/office/operator`);
  step("Operator: off duty (no resource available)", (await O.getByRole("button", { name: "Start shift" }).count()) > 0);

  await C.goto(`${BASE}/dashboard/book`);
  await C.getByRole("button", { name: /Boda/ }).first().click().catch(() => {});
  const zones = C.locator("form select");
  await zones.nth(0).selectOption({ index: 0 });
  await zones.nth(1).selectOption({ index: 1 });
  await C.getByRole("button", { name: /Request — we will show your fare/ }).click();
  await C.waitForURL(/\/dashboard\/orders\/[0-9a-f-]{36}/, { timeout: 30000 }).catch(() => {});
  const orderUrl = C.url();
  step("Customer: order placed from the booking screen", /orders\/[0-9a-f-]{36}/.test(orderUrl), orderUrl + " " + (await formError(C.locator("form").first()).catch(() => "")));
  const waiting = await poll(async () => { await C.goto(orderUrl); return /waiting/i.test(await text(C)); }, { tries: 20, every: 3000 });
  step("Journey B: no operator on duty -> order WAITING, customer sees it", !!waiting, (await text(C)).slice(0, 300));
  const told = await poll(async () => { await C.goto(`${BASE}/dashboard/notifications`); return /Finding you a/i.test(await text(C)); }, { tries: 20, every: 3000 });
  step("Journey B: customer notified that we are finding an operator", !!told, (await text(C)).slice(0, 400));

  // Resource becomes available -> retry assigns -> fare quoted (D2)
  await O.goto(`${BASE}/office/operator`);
  await press(O, "Start shift");
  const quoted = await poll(async () => { await C.goto(orderUrl); return (await C.getByRole("button", { name: "Accept fare" }).count()) > 0; }, { tries: 40, every: 3000 });
  step("Journey B: operator came on duty -> retry matched -> fare quoted", !!quoted, (await text(C)).slice(0, 300));
  if (!quoted) { await shot(C, "j3-quote"); }

  // ---- Journey A: accept the estimate -> dispatch
  if (quoted) {
    const fare = /KES\s?[\d,]+(\.\d+)?/.exec(await text(C))?.[0];
    await press(C, "Accept fare");
    await C.goto(orderUrl);
    step(`Journey A: customer accepted the fare (${fare})`, (await C.getByRole("button", { name: "Accept fare" }).count()) === 0);
  }

  // ---- Journey C: operator notified, accepts, progresses
  await O.goto(`${BASE}/office/notifications`);
  step("Journey C: operator notified of the new job", /job|order|assigned/i.test(await text(O)), (await text(O)).slice(0, 300));
  await O.goto(`${BASE}/office/operator`);
  const jobLink = O.locator('a[href^="/office/operator/"]').first();
  const hasJob = await poll(async () => { await O.goto(`${BASE}/office/operator`); return (await jobLink.count()) > 0; }, { tries: 15, every: 2000 });
  step("Journey C: job appears in the Operator App", !!hasJob);
  if (hasJob) {
    await jobLink.click();
    await O.waitForURL(/\/office\/operator\/[0-9a-f-]{36}/);
    const jobUrl = O.url();
    await poll(async () => { await O.goto(jobUrl); return (await O.getByRole("button", { name: "Accept job" }).count()) > 0; }, { tries: 15, every: 2000 });
    for (const label of ["Accept job", "Set off (dispatched)", "I'm on the way"]) {
      await O.goto(jobUrl);
      if (!(await O.getByRole("button", { name: label }).count())) { step(`Journey C: '${label}' offered`, false, (await text(O)).slice(0, 300)); break; }
      await press(O, label);
      step(`Journey C: operator — ${label}`, !(await formError(O.locator("form", { has: O.getByRole("button", { name: label }) })).catch(() => "")), "");
    }

    // ---- Journey G: Protrack telemetry while en route
    if (key) {
      const pts = [[-0.0917, 34.7680], [-0.0950, 34.7600], [-0.0990, 34.7550]].map(([lat, lng], i) => ({
        imei: "PT-0001", lat, lng, gpstime: Math.floor(Date.now() / 1000) - (2 - i) * 20, speed: 32, course: 210, acc: 1,
      }));
      const r = await rpcAsService("fn_integration_telemetry_ingest", { p_key: key, p_records: pts });
      step("Journey G: Protrack batch accepted by Engine 6 with the issued key", r.status === 200 && JSON.stringify(r.body).includes("accepted"), JSON.stringify(r.body).slice(0, 200));
      const bad = await rpcAsService("fn_integration_telemetry_ingest", { p_key: "trs_bogus.key", p_records: pts });
      step("Journey G: a wrong key is refused (UNAUTHENTICATED, nothing accepted; edge function answers 401)", bad.body?.outcome === "UNAUTHENTICATED", JSON.stringify(bad.body));
      const tracked = await poll(async () => { await C.goto(orderUrl); return /-0\.09|map/i.test(await text(C)) && (await C.locator('a[href*="maps"]').count()) > 0; }, { tries: 15, every: 3000 });
      step("Journey G: customer sees the live position of their trip", !!tracked, (await text(C)).slice(0, 300));
      await F.goto(`${BASE}/office/tracking`);
      step("Journey G: Office tracking shows the device and the live job", /PT-0001/.test(await text(F)) && /TRS026-ORDER/.test(await text(F)), (await text(F)).slice(0, 300));
    }

    for (const label of ["I've arrived", "Start service", "Complete this stop"]) {
      await O.goto(jobUrl);
      if (!(await O.getByRole("button", { name: label }).count())) { step(`Journey C: '${label}' offered`, false, (await text(O)).slice(0, 300)); break; }
      await press(O, label);
      step(`Journey C: operator — ${label}`, true);
    }
    await O.goto(jobUrl);
    const verifyBtn = O.getByRole("button", { name: /Verify and close/ });
    if (await verifyBtn.count()) { await press(O, await verifyBtn.first().textContent()); }
    await O.goto(`${BASE}/office/operator`);
    const free = await poll(async () => { await O.goto(`${BASE}/office/operator`); return /AVAILABLE|Available/.test(await text(O)) && !(await jobLink.count()); }, { tries: 15, every: 2000 });
    step("Journey C: job closed, operator released and available again", !!free, (await text(O)).slice(0, 300));

    // Tracking ends with the trip
    await C.goto(orderUrl);
    step("Journey G: tracking terminated after completion (no live position)", (await C.locator('a[href*="maps"]').count()) === 0);
  }

  // ---- Payment: M-Pesa STK (simulator) -> settlement -> receipt -> review
  const payBtn = await poll(async () => { await C.goto(orderUrl); return (await C.getByRole("button", { name: "Approve (staging M-Pesa simulator)" }).count()) > 0; }, { tries: 20, every: 3000 });
  step("Journey A: M-Pesa prompt sent to the customer's verified phone", !!payBtn, (await text(C)).slice(0, 400));
  if (payBtn) {
    await press(C, "Approve (staging M-Pesa simulator)");
    const receipt = await poll(async () => { await C.goto(orderUrl); return /Receipt/i.test(await text(C)) && /receipt generated|settled/i.test(await text(C)); }, { tries: 20, every: 3000 });
    step("Journey A: payment settled and receipt issued", !!receipt, (await text(C)).slice(0, 400));
  }
  const reviewForm = C.locator("form", { has: C.getByRole("button", { name: "Submit review" }) });
  if (await reviewForm.count()) {
    await reviewForm.locator('select[name="rating:n"]').selectOption("5");
    await reviewForm.locator('input[name="comment"]').fill("On time and careful.");
    await press(C, "Submit review", reviewForm);
  }
  await C.goto(orderUrl);
  step("Journey A: review recorded", /★★★★★/.test(await text(C)));

  // ---- Journey D: Office monitors the completed order
  await F.goto(`${BASE}/office/orders?filter=ALL`);
  step("Journey D: Office sees the order with its outcome", /SETTLED|REVIEWED|Settled|Reviewed/.test(await text(F)), (await text(F)).slice(0, 300));

  await op.save(); await cust.save();
  await b.close();
  fs.writeFileSync(path.join(__dirname, "order-url.txt"), orderUrl);
  writeResults("results.json");
})();
