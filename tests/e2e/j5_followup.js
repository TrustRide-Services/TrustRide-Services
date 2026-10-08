// Follow-up: Journey E with the Office's reservation confirmation, and a
// company opening a Customer account and booking through its representative.
const { BASE, browser, actor, step, press, formError, poll, writeResults } = require("./lib");
const text = async (page) => (await page.locator("body").innerText()).replace(/\s+/g, " ");

(async () => {
  const b = await browser();
  const F = (await actor(b, "founder")).page;
  const cust = await actor(b, "customer"); const C = cust.page;
  const ven = await actor(b, "vendor"); const V = ven.page;

  // ---- Journey E: Office confirms the reservation (viewing) -> payment
  await F.goto(`${BASE}/office/requests`);
  const r = F.locator(".trs-card", { hasText: "Vehicle reservation" }).filter({ has: F.getByRole("button", { name: "Approve" }) }).first();
  step("Journey E: reservation reaches the Office queue", (await r.count()) > 0);
  if (await r.count()) { await r.locator('input[name="notes"]').first().fill("Viewing at Kisumu CBD Hub, Saturday 10:00"); await press(F, "Approve", r); }
  await C.goto(`${BASE}/marketplace/purchases`);
  const link = C.locator('a[href^="/marketplace/purchases/"]').first();
  await link.click(); await C.waitForURL(/purchases\/[0-9a-f-]{36}/);
  const url = C.url();
  const prompt = await poll(async () => { await C.goto(url); return (await C.getByRole("button", { name: "Approve (staging M-Pesa simulator)" }).count()) > 0; }, { tries: 20, every: 3000 });
  step("Journey E: buyer told; M-Pesa prompt for KES 95,000", !!prompt && /95,000/.test(await text(C)), (await text(C)).slice(0, 300));
  if (prompt) await press(C, "Approve (staging M-Pesa simulator)");
  const paid = await poll(async () => { await C.goto(url); return /Receipt/.test(await text(C)); }, { tries: 20, every: 3000 });
  step("Journey E: purchase paid, settled and receipted", !!paid, (await text(C)).slice(0, 300));
  const hand = await poll(async () => { await V.goto(`${BASE}/marketplace/vendor`); return (await V.getByRole("button", { name: "Confirm handover" }).count()) > 0; }, { tries: 10, every: 3000 });
  step("Journey E: vendor told the vehicle sold; handover offered", !!hand);
  if (hand) {
    const f = V.locator("form", { has: V.getByRole("button", { name: "Confirm handover" }) }).first();
    await f.locator('input[name="notes"]').fill("Logbook transferred, keys handed");
    await press(V, "Confirm handover", f);
  }
  const payout = await poll(async () => {
    await F.goto(`${BASE}/office/marketplace`);
    const c = F.locator(".trs-card", { hasText: "Wanjiru Vendor Test" }).filter({ hasText: "commission" }).first();
    return (await c.count()) && /PAID|Paid/.test(await c.textContent());
  }, { tries: 20, every: 3000 });
  step("Journey E: fulfilment complete — vendor paid 95% (KES 90,250) by M-Pesa B2C simulator", !!payout && /90,250/.test(await text(F)), (await text(F)).slice(-300));
  await C.goto(url);
  step("Journey E: purchase never routed to driver dispatch", !/YOUR OPERATOR|LIVE TRACKING/i.test(await text(C)));

  // ---- Company: open a Customer account at the Gate, act as it, book
  await C.goto(`${BASE}/verify`);
  const open = C.locator(".trs-card", { hasText: "Akinyi Logistics Ltd" }).getByRole("button", { name: "Open Customer account" });
  if (await open.count()) { await open.click(); await C.waitForLoadState("networkidle"); }
  await C.goto(`${BASE}/verify`);
  step("Entity: company holds an active Customer environment", /Akinyi Logistics Ltd.*Customer\s*Active/i.test(await text(C)), (await text(C)).slice(0, 600));
  await C.goto(`${BASE}/dashboard`);
  const v = await C.locator('select[name="acting"] option', { hasText: "Akinyi Logistics" }).getAttribute("value");
  await C.locator('select[name="acting"]').selectOption(v);
  await C.getByRole("button", { name: "Act as" }).click();
  await C.waitForLoadState("networkidle");
  await C.goto(`${BASE}/dashboard/book`);
  step("Entity: Customer App opens for the company (acting)", /Akinyi Logistics Ltd \(acting\)/.test(await text(C)) && (await C.getByRole("button", { name: /Request — we will show your fare/ }).count()) > 0, (await text(C)).slice(0, 300));
  const btn = C.getByRole("button", { name: /Request — we will show your fare/ });
  if (await btn.count() && await btn.isEnabled()) {
    await btn.click();
    await C.waitForURL(/\/dashboard\/orders\/[0-9a-f-]{36}/, { timeout: 30000 }).catch(() => {});
    step("Entity: representative placed an order in the company's name", /orders\/[0-9a-f-]{36}/.test(C.url()), C.url() + " " + (await text(C)).slice(0, 200));
  } else {
    step("Entity: company can book (needs a verified M-Pesa phone of its own)", false, (await text(C)).match(/Verify your phone[^.]*\./)?.[0] ?? "button disabled");
  }
  await C.locator('select[name="acting"]').selectOption("");
  await C.getByRole("button", { name: "Act as" }).click();

  await cust.save(); await ven.save();
  await b.close();
  writeResults("results.json");
})();
