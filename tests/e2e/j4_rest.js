// Journeys E (marketplace), F (executive assistant), H completion (Governor
// scope), support, company/entity acting, Executive Dashboard and health.
const { BASE, browser, actor, step, shot, press, formError, poll, writeResults } = require("./lib");
const text = async (page) => (await page.locator("body").innerText()).replace(/\s+/g, " ");
const card = (page, has, btn) => {
  let c = page.locator(".trs-card", { hasText: has });
  if (btn) c = c.filter({ has: page.getByRole("button", { name: btn, exact: true }) });
  return c.first();
};

(async () => {
  const b = await browser();
  const F = (await actor(b, "founder")).page;
  const cust = await actor(b, "customer"); const C = cust.page;
  const ven = await actor(b, "vendor"); const V = ven.page;
  const gov = await actor(b, "governor"); const G = gov.page;
  const ea = await actor(b, "eaworker"); const E = ea.page;

  // ================= Journey H completion: Governor approved, scope granted
  await F.goto(`${BASE}/office/requests`);
  const greq = card(F, "Kisumu County Revenue Test", "Approve");
  if (await greq.count()) {
    await greq.locator('input[name="notes"]').first().fill("Aggregate levy data only");
    await press(F, "Approve", greq);
  }
  await G.goto(`${BASE}/dashboard/governor`);
  step("Journey H: Governor approved; sees nothing before a scope grant (D4)", !/Granted data/.test(await text(G)) && !/is with TrustRide Office/.test(await text(G)), (await text(G)).slice(0, 250));
  await F.goto(`${BASE}/office/users?q=Kisumu`);
  const gcard = card(F, "Kisumu County Revenue Test");
  const scopeBtn = gcard.getByRole("button", { name: "aggregate service volumes" });
  if (await scopeBtn.count()) { F.once("dialog", (d) => d.accept()); await scopeBtn.click(); await F.waitForLoadState("networkidle"); await F.waitForTimeout(1500); }
  await G.goto(`${BASE}/dashboard/governor`);
  step("Journey H: after the grant, Governor sees aggregate service volumes only", /Granted data/i.test(await text(G)) && /Completed services by family/.test(await text(G)) && !/Settled revenue/.test(await text(G)), (await text(G)).slice(0, 400));
  await G.goto(`${BASE}/office`);
  step("Governor: TrustRide Office refused", G.url().includes("/verify"));

  // ================= Journey E: Marketplace
  await V.goto(`${BASE}/marketplace/vendor`);
  if (!/Honda Ace 125/.test(await text(V))) {
    const form = V.locator("form", { has: V.getByRole("button", { name: "Publish listing" }) });
    await form.locator('select[name="vehicle_category"]').selectOption("MOTORCYCLE");
    await form.locator('input[name="title"]').fill("Honda Ace 125, 2022");
    await form.locator('input[name="price_kes:n"]').fill("95000");
    await form.locator('textarea[name="description"]').fill("Serviced, logbook ready");
    await press(V, "Publish listing", form);
  }
  await V.goto(`${BASE}/marketplace/vendor`);
  step("Journey E: approved vendor published a listing", /Honda Ace 125/.test(await text(V)), await formError(V.locator("form").first()));

  await C.goto(`${BASE}/marketplace`);
  const lcard = card(C, "Honda Ace 125", "Reserve");
  step("Journey E: customer sees the listing in the Marketplace", (await lcard.count()) > 0, (await text(C)).slice(0, 300));
  if (await lcard.count()) {
    await press(C, "Reserve", lcard);
    await C.waitForURL(/\/marketplace\/purchases\/[0-9a-f-]{36}/, { timeout: 20000 }).catch(() => {});
  }
  const purchaseUrl = C.url();
  step("Journey E: reservation opens a purchase order", /purchases\/[0-9a-f-]{36}/.test(purchaseUrl), purchaseUrl);
  // Payment follows the Office's confirmation of the viewing (j5).
  await C.goto(purchaseUrl);
  step("Journey E: purchase never entered driver dispatch (no operator, no tracking)", !/YOUR OPERATOR|LIVE TRACKING/i.test(await text(C)));

  // ================= Journey F: Executive Assistant
  await E.goto(`${BASE}/office/operator`);
  if (await E.getByRole("button", { name: "Start shift" }).count()) await press(E, "Start shift");
  await E.goto(`${BASE}/office/operator`);
  step("Journey F: EA on duty", /AVAILABLE/.test(await text(E)), (await text(E)).slice(0, 200));

  async function bookEA(serviceName) {
    await C.goto(`${BASE}/dashboard/book`);
    await C.getByRole("button", { name: /Executive|Assistant/ }).first().click();
    await C.getByRole("button", { name: new RegExp(serviceName) }).first().click();
    await C.locator('input[type="number"]').fill("3");
    await C.getByRole("button", { name: /Request — we will show your fare/ }).click();
    await C.waitForURL(/\/dashboard\/orders\/[0-9a-f-]{36}/, { timeout: 30000 }).catch(() => {});
    return C.url();
  }
  // Ineligible first: school visitation needs a child-safeguarding certificate she lacks.
  const schoolUrl = await bookEA("School");
  const notMatched = await poll(async () => { await C.goto(schoolUrl); return /WAITING/i.test(await text(C)); }, { tries: 15, every: 3000 });
  step("Journey F: eligibility enforced — school visitation not given to an EA without safeguarding cert", !!notMatched && !/Achieng/.test(await text(C)), (await text(C)).slice(0, 300));
  const cancelForm = C.locator("form", { has: C.getByRole("button", { name: "Cancel order" }) });
  if (await cancelForm.count()) { C.once("dialog", (d) => d.accept()); await press(C, "Cancel order", cancelForm); }
  await C.goto(schoolUrl);
  step("Customer: cancelled the unmatched order", /CANCELLED|Cancelled/.test(await text(C)));

  const eaUrl = await bookEA("Errands");
  const eaQuote = await poll(async () => { await C.goto(eaUrl); return (await C.getByRole("button", { name: "Accept fare" }).count()) > 0; }, { tries: 30, every: 3000 });
  step("Journey F: vetted, skilled EA matched; hourly price quoted", !!eaQuote, (await text(C)).slice(0, 300));
  if (eaQuote) await press(C, "Accept fare");
  const eaJob = await poll(async () => { await E.goto(`${BASE}/office/operator`); return (await E.locator('a[href^="/office/operator/"]').count()) > 0; }, { tries: 15, every: 2000 });
  if (eaJob) {
    await E.locator('a[href^="/office/operator/"]').first().click();
    await E.waitForURL(/\/office\/operator\/[0-9a-f-]{36}/);
    const jobUrl = E.url();
    await poll(async () => { await E.goto(jobUrl); return (await E.getByRole("button", { name: "Accept job" }).count()) > 0; }, { tries: 10, every: 2000 });
    for (const label of ["Accept job", "Set off (dispatched)", "I'm on the way", "I've arrived", "Start service", "Complete this stop"]) {
      await E.goto(jobUrl);
      if (!(await E.getByRole("button", { name: label }).count())) { step(`Journey F: EA '${label}' offered`, false, (await text(E)).slice(0, 200)); break; }
      await press(E, label);
    }
  }
  const eaPay = await poll(async () => { await C.goto(eaUrl); return (await C.getByRole("button", { name: "Approve (staging M-Pesa simulator)" }).count()) > 0; }, { tries: 20, every: 3000 });
  if (eaPay) await press(C, "Approve (staging M-Pesa simulator)");
  const eaSettled = await poll(async () => { await C.goto(eaUrl); return /Receipt/.test(await text(C)); }, { tries: 20, every: 3000 });
  step("Journey F: EA service executed and settled", !!eaJob && !!eaSettled, (await text(C)).slice(0, 300));

  // ================= Support: customer -> Office -> resolution
  await C.goto(eaUrl);
  const sup = C.locator("form", { has: C.getByRole("button", { name: "Contact support" }) });
  await sup.locator('select[name="category"]').selectOption("ORDER_ISSUE");
  await sup.locator('input[name="subject"]').fill("Receipt copy needed for my employer").catch(() => {});
  await sup.locator('textarea[name="body"], input[name="body"]').first().fill("Please send the receipt by SMS too.").catch(() => {});
  await press(C, "Contact support", sup);
  step("Support: customer opened a case from the order", !(await formError(sup)), await formError(sup));
  await F.goto(`${BASE}/office/support`);
  const scase = card(F, "Receipt copy needed");
  if (await scase.getByRole("button", { name: "Take this case" }).count()) await press(F, "Take this case", scase);
  await F.goto(`${BASE}/office/support`);
  const rform = card(F, "Receipt copy needed").locator("form", { has: F.getByRole("button", { name: "Send" }) });
  if (await rform.count()) { await rform.locator('input[name="body"]').fill("Sent — check your SMS."); await press(F, "Send", rform); }
  await F.goto(`${BASE}/office/support`);
  const res = card(F, "Receipt copy needed").locator("form", { has: F.getByRole("button", { name: "Resolve" }) });
  if (await res.count()) { await res.locator('input[name="resolution"]').fill("Receipt re-sent by SMS"); await press(F, "Resolve", res); }
  await C.goto(`${BASE}/dashboard/support`);
  step("Support: customer sees the Office reply and the resolution", /Sent — check your SMS/.test(await text(C)) && /RESOLVED|Resolved/.test(await text(C)), (await text(C)).slice(0, 400));

  // ================= Company / entity: register, verify, act as
  await C.goto(`${BASE}/dashboard/profile`);
  if (!/Akinyi Logistics Ltd/.test(await text(C))) {
    const ef = C.locator("form", { has: C.getByRole("button", { name: "Register for verification" }) });
    await ef.locator('input[name="legal_name"]').fill("Akinyi Logistics Ltd");
    await ef.locator('select[name="entity_type"]').selectOption("COMPANY");
    await ef.locator('input[name="registration_number"]').fill("PVT-AB12CD34");
    await ef.locator('input[name="kra_pin"]').fill("P051234567X");
    await ef.locator('input[name="county_code"]').fill("42");
    await press(C, "Register for verification", ef);
    step("Entity: company submitted for BRS/KRA verification", !(await formError(ef)), await formError(ef));
  }
  const canAct = await poll(async () => { await C.goto(`${BASE}/dashboard`); return (await C.locator('select[name="acting"] option', { hasText: "Akinyi Logistics" }).count()) > 0; }, { tries: 20, every: 3000 });
  step("Entity: verified company offered in 'Act as'", !!canAct);
  if (canAct) {
    await C.locator('select[name="acting"]').selectOption({ label: "Akinyi Logistics Ltd" }).catch(async () => {
      const v = await C.locator('select[name="acting"] option', { hasText: "Akinyi Logistics" }).getAttribute("value");
      await C.locator('select[name="acting"]').selectOption(v);
    });
    await C.getByRole("button", { name: "Act as" }).click();
    await C.waitForLoadState("networkidle");
    await C.goto(`${BASE}/dashboard/profile`);
    step("Entity: representative now acting as the company (its own profile)", /Akinyi Logistics Ltd/.test(await text(C)) && /acting/i.test(await text(C)), (await text(C)).slice(0, 300));
    // back to self
    await C.locator('select[name="acting"]').selectOption("");
    await C.getByRole("button", { name: "Act as" }).click();
    await C.waitForLoadState("networkidle");
  }

  // ================= Executive Dashboard + health + overview
  await F.goto(`${BASE}/office/executive?days=7`);
  step("Executive: KPIs computed from the engines (orders placed > 0)", /Orders placed\s*[1-9]/.test(await text(F)), (await text(F)).slice(0, 400));
  const sform = F.locator("form", { has: F.getByRole("button", { name: "Run scenario" }) });
  if (await sform.count()) { await sform.locator('input[name="run_label"]').fill("UI journey run"); await press(F, "Run scenario", sform); }
  const ran = await poll(async () => { await F.goto(`${BASE}/office/executive?days=7`); return /UI journey run/.test(await text(F)); }, { tries: 15, every: 3000 });
  step("Executive: scenario run requested and its result listed", !!ran);
  await F.goto(`${BASE}/office/health`);
  step("Health: conformance shows no violations; background jobs listed", /No violations/.test(await text(F)) && /trustride_dispatch_cycle/.test(await text(F)), (await text(F)).slice(0, 300));
  await F.goto(`${BASE}/office`);
  step("Office overview renders live counts and alerts", /Orders waiting for a worker/.test(await text(F)));

  for (const a of [cust, ven, gov, ea]) await a.save();
  await b.close();
  writeResults("results.json");
})();
