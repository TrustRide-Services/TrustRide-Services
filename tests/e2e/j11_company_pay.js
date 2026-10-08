const { BASE, browser, actor, step, press, poll, writeResults } = require("./lib");
const text = async (p) => (await p.locator("body").innerText()).replace(/\s+/g, " ");
(async () => {
  const b = await browser(); const cust = await actor(b, "customer"); const C = cust.page;
  await C.goto(`${BASE}/dashboard`);
  const v = await C.locator('select[name="acting"] option', { hasText: "Akinyi Logistics" }).getAttribute("value");
  await C.locator('select[name="acting"]').selectOption(v); await C.getByRole("button", { name: "Act as" }).click(); await C.waitForLoadState("networkidle"); await C.waitForTimeout(1000);
  await C.goto(`${BASE}/dashboard/orders`);
  await C.locator('a[href^="/dashboard/orders/"]', { hasText: /COMPLETED|Completed/ }).first().click();
  await C.waitForURL(/orders\/[0-9a-f-]{36}/); const url = C.url();
  await press(C, "Approve (staging M-Pesa simulator)");
  const paid = await poll(async () => { await C.goto(url); return /Receipt/.test(await text(C)); }, { tries: 20, every: 3000 });
  step("Company: representative approves the company's prompt; paid and receipted in the company's name", !!paid && /Akinyi Logistics Ltd \(acting\)/.test(await text(C)), (await text(C)).slice(0, 300));
  await C.locator('select[name="acting"]').selectOption(""); await C.getByRole("button", { name: "Act as" }).click(); await C.waitForLoadState("networkidle");
  await cust.save(); await b.close(); writeResults("results.json");
})();
