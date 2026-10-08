// Company ride to receipt (paid from the company's own phone) and support
// from every remaining actor surface, answered by the Office.
const { BASE, browser, actor, step, press, poll, writeResults } = require("./lib");
const text = async (p) => (await p.locator("body").innerText()).replace(/\s+/g, " ");

(async () => {
  const b = await browser();
  const F = (await actor(b, "founder")).page;
  const cust = await actor(b, "customer"); const C = cust.page;
  const O = (await actor(b, "operator")).page;

  // ---- Company ride
  await O.goto(`${BASE}/office/operator`);
  if (await O.getByRole("button", { name: "Start shift" }).count()) await press(O, "Start shift");
  await C.goto(`${BASE}/dashboard`);
  const v = await C.locator('select[name="acting"] option', { hasText: "Akinyi Logistics" }).getAttribute("value");
  await C.locator('select[name="acting"]').selectOption(v);
  await C.getByRole("button", { name: "Act as" }).click(); await C.waitForLoadState("networkidle"); await C.waitForTimeout(1000);
  // Clear any order still waiting (e.g. a sedan nobody can serve)
  await C.goto(`${BASE}/dashboard/orders`);
  for (const a of await C.locator('a[href^="/dashboard/orders/"]').all()) {
    const href = await a.getAttribute("href");
    const P2 = await C.context().newPage(); await P2.goto(`${BASE}${href}`);
    if (/WAITING/i.test(await P2.locator("body").innerText())) {
      const cf = P2.locator("form", { has: P2.getByRole("button", { name: "Cancel order" }) });
      if (await cf.count()) { P2.once("dialog", (d) => d.accept()); await press(P2, "Cancel order", cf); }
    }
    await P2.close();
  }
  await C.goto(`${BASE}/dashboard/book`);
  await C.getByRole("button", { name: /Boda/ }).first().click();
  const zones = C.locator("form select"); await zones.nth(0).selectOption({ index: 0 }); await zones.nth(1).selectOption({ index: 1 });
  await C.getByRole("button", { name: /Request — we will show your fare/ }).click();
  await C.waitForURL(/\/dashboard\/orders\/[0-9a-f-]{36}/, { timeout: 30000 }).catch(() => {});
  const url = C.url();
  const q = await poll(async () => { await C.goto(url); return (await C.getByRole("button", { name: "Accept fare" }).count()) > 0; }, { tries: 30, every: 3000 });
  step("Company: fare quoted for the company's order", !!q);
  if (q) await press(C, "Accept fare");
  const job = await poll(async () => { await O.goto(`${BASE}/office/operator`); return (await O.locator('a[href^="/office/operator/"]').count()) > 0; }, { tries: 15, every: 2000 });
  if (job) {
    await O.locator('a[href^="/office/operator/"]').first().click(); await O.waitForURL(/operator\/[0-9a-f-]{36}/);
    const ju = O.url();
    await poll(async () => { await O.goto(ju); return (await O.getByRole("button", { name: "Accept job" }).count()) > 0; }, { tries: 10, every: 2000 });
    for (const l of ["Accept job", "Set off (dispatched)", "I'm on the way", "I've arrived", "Start service", "Complete this stop"]) {
      await O.goto(ju); if (!(await O.getByRole("button", { name: l }).count())) break; await press(O, l);
      if (l === "I'm on the way") {
        await C.goto(url);
        step("Company: representative sees the company's live trip", /LIVE TRACKING/i.test(await text(C)), (await text(C)).slice(0, 200));
      }
    }
  }
  const pay = await poll(async () => { await C.goto(url); return (await C.getByRole("button", { name: "Approve (staging M-Pesa simulator)" }).count()) > 0; }, { tries: 20, every: 3000 });
  step("Company: M-Pesa prompt goes to the company's own verified phone", !!pay);
  if (pay) await press(C, "Approve (staging M-Pesa simulator)");
  const paid = await poll(async () => { await C.goto(url); return /Receipt/.test(await text(C)); }, { tries: 20, every: 3000 });
  step("Company: order completed, paid and receipted in the company's name", !!paid && /Akinyi Logistics Ltd \(acting\)/.test(await text(C)));
  // The receipt went to the company's number, not the person's
  await C.goto(`${BASE}/dashboard/profile`);
  step("Company: payment SMS delivered to the company's own number", /payment|paid|receipt/i.test((await text(C)).split(/staging/i)[1] ?? ""), ((await text(C)).split(/staging/i)[1] ?? "").slice(0, 200));
  await C.locator('select[name="acting"]').selectOption(""); await C.getByRole("button", { name: "Act as" }).click(); await C.waitForLoadState("networkidle");
  await cust.save();

  // ---- Support from every other surface
  if (process.argv[2] === "company-only") { await b.close(); writeResults("results.json"); return; }
  const who = [["operator", "/dashboard/support", "Partner"], ["eaworker", "/dashboard/support", "Intermediary"], ["governor", "/dashboard/support", "Governor"], ["vendor", "/marketplace/support", "Vendor"]];
  for (const [k, path, label] of who) {
    const a = await actor(b, k); const P = a.page;
    await P.goto(`${BASE}${path}`);
    const f = P.locator("form", { has: P.getByRole("button", { name: "Send to TrustRide" }) });
    if (!(await f.count())) { step(`${label}: support form available`, false, (await text(P)).slice(0, 200)); continue; }
    await f.locator('input[name="subject"]').fill(`${label} question from UI journey`);
    await f.locator('textarea[name="body"]').fill("When is the next review of our engagement?");
    await press(P, "Send to TrustRide", f);
    await F.goto(`${BASE}/office/support`);
    const c = F.locator(".trs-card", { hasText: `${label} question from UI journey` }).first();
    const rf = c.locator("form", { has: F.getByRole("button", { name: "Send" }) });
    if (await rf.count()) { await rf.locator('input[name="body"]').fill(`Answer for ${label}`); await press(F, "Send", rf); }
    await P.goto(`${BASE}${path}`);
    step(`${label}: support case opened and the Office's answer received`, new RegExp(`Answer for ${label}`).test(await text(P)), (await text(P)).slice(0, 200));
    await a.ctx.close();
  }
  await b.close(); writeResults("results.json");
})();
