// Company books through its representative: act as -> its own phone -> book.
const { BASE, browser, actor, step, press, formError, poll, writeResults } = require("./lib");
const text = async (page) => (await page.locator("body").innerText()).replace(/\s+/g, " ");
(async () => {
  const b = await browser();
  const cust = await actor(b, "customer"); const C = cust.page;
  await C.goto(`${BASE}/dashboard`);
  const v = await C.locator('select[name="acting"] option', { hasText: "Akinyi Logistics" }).getAttribute("value");
  await C.locator('select[name="acting"]').selectOption(v);
  await C.getByRole("button", { name: "Act as" }).click();
  await C.waitForLoadState("networkidle");
  await C.goto(`${BASE}/dashboard/profile`);
  step("Entity: profile shows the company's own identity while acting", /Akinyi Logistics Ltd/.test(await text(C)));
  const add = C.locator("form", { has: C.getByRole("button", { name: "Add and send code" }) });
  await add.locator('select[name="type"]').selectOption("PHONE");
  await add.locator('input[name="value"]').fill("0722000888").catch(() => {});
  await press(C, "Add and send code", add);
  step("Entity: representative added the company's M-Pesa phone", !(await formError(add)), await formError(add));
  const code = await poll(async () => { await C.goto(`${BASE}/dashboard/profile`); return /(\d{6})/.exec((await text(C)).split(/staging/i)[1] ?? "")?.[1]; }, { tries: 20, every: 3000 });
  step("Entity: code delivered to the company's number (simulated SMS)", !!code);
  if (code) {
    const vf = C.locator("form", { has: C.getByRole("button", { name: "Verify" }) }).first();
    await vf.locator('input[name="code"]').fill(code);
    await press(C, "Verify", vf);
  }
  await C.goto(`${BASE}/dashboard/book`);
  const btn = C.getByRole("button", { name: /Request — we will show your fare/ });
  step("Entity: booking enabled for the company (phone verified)", await btn.isEnabled());
  if (await btn.isEnabled()) {
    await btn.click();
    await C.waitForURL(/\/dashboard\/orders\/[0-9a-f-]{36}/, { timeout: 30000 }).catch(() => {});
    step("Entity: order placed in the company's name by its representative", /orders\/[0-9a-f-]{36}/.test(C.url()) && /Akinyi Logistics Ltd \(acting\)/.test(await text(C)), C.url());
    const c = C.locator("form", { has: C.getByRole("button", { name: "Cancel order" }) });
    if (await c.count()) { C.once("dialog", (d) => d.accept()); await press(C, "Cancel order", c); }
  }
  await C.locator('select[name="acting"]').selectOption("");
  await C.getByRole("button", { name: "Act as" }).click();
  await C.waitForLoadState("networkidle");
  await C.waitForTimeout(1500);
  await C.goto(`${BASE}/dashboard/profile`);
  step("Entity: switching back shows the person's own profile", /Akinyi Customer Test/.test(await text(C)) && !/\(acting\)/.test(await text(C)));
  await cust.save(); await b.close(); writeResults("results.json");
})();
