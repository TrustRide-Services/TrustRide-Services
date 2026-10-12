// Journey -- WP8 surfaces (Construction Directive 2.11): registration retry, secondary profile,
// service catalogue, Executive scenario comparison, and the Office compliance forms. Each is driven
// by the actor allowed to use it, and refused to an actor who is not. Re-runnable (unique codes).
const { BASE, browser, actor, step, press, formError, poll, writeResults } = require("./lib");

const N = String(Date.now() % 1000000).padStart(6, "0");
const RUN = Date.now().toString(36).slice(-4).toUpperCase();
const text = async (page) => (await page.locator("body").innerText()).replace(/\s+/g, " ");
const formWith = (page, button, scope) => (scope ?? page).locator("form", { has: page.getByRole("button", { name: button, exact: true }) }).first();
const ok = async (form) => (await form.locator(".text-success").count()) > 0;
// The Founder grants or revokes an Office role through Users & roles (as j8 does).
async function grant(F, name, role) {
  await F.goto(`${BASE}/office/users?q=${encodeURIComponent(name.split(" ")[0])}`);
  const f = F.locator(".trs-card", { hasText: name }).first().locator("form", { has: F.getByRole("button", { name: "Grant role" }) });
  await f.locator('select[name="role_code"]').selectOption(role);
  await press(F, "Grant role", f);
  return formError(f);
}
async function revoke(F, name, role) {
  await F.goto(`${BASE}/office/users?q=${encodeURIComponent(name.split(" ")[0])}`);
  const card = F.locator(".trs-card", { hasText: name }).first();
  const btn = card.getByRole("button", { name: `Revoke ${role.toLowerCase()}` });
  if (await btn.count()) { F.once("dialog", (d) => d.accept()); await btn.first().click(); await F.waitForLoadState("networkidle").catch(() => {}); }
}

(async () => {
  const b = await browser();

  // ================= 1. registration retry (a new person whose first check fails)
  {
    const a = await actor(b, `retry-${N}`);
    const P = a.page;
    await P.goto(`${BASE}/register`);
    await P.fill('input[name="legalName"]', "Retry Journey Person");
    await P.fill('input[name="nationalId"]', `00${N}`);          // simulator: 00 prefix is INVALID
    await P.fill('input[name="phone"]', `0799${N}`);
    await P.fill('input[name="email"]', `retry-${N}@trustride.test`);
    await P.fill('input[name="password"]', "Trustride-e2e-2026");
    await P.check('input[name="consent"]');
    await P.locator('button[type="submit"]').click();
    await P.waitForURL(/\/verify/, { timeout: 30000 }).catch(() => {});
    const failed = await poll(async () => { await P.goto(`${BASE}/verify`); return (await P.getByText("We couldn't verify this identity").count()) > 0; }, { tries: 30, every: 3000 });
    step("retry: a failed identity check shows why", !!failed && (await text(P)).includes("The ID number was not accepted by the register."));
    let form = formWith(P, "Correct and check again");
    step("retry: after a definitive answer the person is asked to correct the details", (await form.count()) > 0);
    await press(P, "Correct and check again", form);
    step("retry: sending the same details again is refused with a reason", /definitive answer/.test(await formError(form)), await formError(form));
    await form.locator('input[name="national_id"]').fill(`3${N}7`);
    await press(P, "Correct and check again", form);
    const verified = await poll(async () => { await P.goto(`${BASE}/verify`); return (await P.getByText("Welcome to TrustRide").count()) > 0; }, { tries: 30, every: 3000 });
    step("retry: corrected details are verified and the Gate opens", !!verified);
    await a.ctx.close();

    // one person, one identity: a verified ID cannot be registered again
    const d = await actor(b, `dup-${N}`);
    const Q = d.page;
    await Q.goto(`${BASE}/register`);
    await Q.fill('input[name="legalName"]', "Duplicate Claim Person");
    await Q.fill('input[name="nationalId"]', `3${N}7`);
    await Q.fill('input[name="phone"]', `0798${N}`);
    await Q.fill('input[name="email"]', `dup-${N}@trustride.test`);
    await Q.fill('input[name="password"]', "Trustride-e2e-2026");
    await Q.check('input[name="consent"]');
    await Q.locator('button[type="submit"]').click();
    await Q.waitForTimeout(4000);
    const t = await text(Q);
    step("identity: registering an ID another identity holds is refused on screen", /already registered to another identity/.test(t), t.slice(0, 200));
    await d.ctx.close();
  }

  // ================= 2. secondary profile (customer, own identity)
  {
    const { page: C, ctx } = await actor(b, "customer");
    await C.goto(`${BASE}/dashboard/profile`);
    step("profile: while acting for an organisation the person's own profile is not offered",
      (await C.getByText("About you (optional)").count()) === 0);
    await ctx.clearCookies({ name: "trs_acting" });            // act as oneself again, as "Act as" does (not saved: j6's state stays)
    await ctx.clearCookies({ name: /^trs_s_/ });
    await C.goto(`${BASE}/dashboard/profile`);
    let form = formWith(C, "Save address");
    await form.locator('input[name="address_line_1"]').fill(`Plot ${N}, Milimani Road`);
    await form.locator('input[name="town"]').fill("Kisumu");
    await form.locator('input[name="county_code"]').fill("42");
    await press(C, "Save address", form);
    await C.goto(`${BASE}/dashboard/profile`);
    step("profile: the customer records a home address", (await text(C)).includes(`Plot ${N}, Milimani Road, Kisumu · county 42`));
    form = formWith(C, "Save address");
    await form.locator('input[name="county_code"]').fill("48");
    await press(C, "Save address", form);
    step("profile: an invalid county code is refused with a reason", /01-47/.test(await formError(form)), await formError(form));
    await C.goto(`${BASE}/dashboard/profile`);
    form = formWith(C, "Save household");
    await form.locator('input[name="household_size:n"]').fill("4");
    await press(C, "Save household", form);
    step("profile: socio-economic data is refused without consent", /consent/.test(await formError(form)), await formError(form));
    await form.locator('input[name="household_size:n"]').fill("4");     // the form is reset after each submission
    await form.locator('input[name="consent:b"]').check();
    await press(C, "Save household", form);
    await C.goto(`${BASE}/dashboard/profile`);
    step("profile: with consent the household is recorded", (await text(C)).includes("Household of 4"));
    for (let i = 0; i < 2; i++) {
      form = formWith(C, "Add qualification");
      await form.locator('input[name="education_level"]').fill("Diploma");
      await form.locator('input[name="qualification"]').fill(`Automotive ${RUN}`);
      await press(C, "Add qualification", form);
      await C.goto(`${BASE}/dashboard/profile`);
    }
    const count = ((await text(C)).match(new RegExp(`Automotive ${RUN}`, "g")) ?? []).length;
    step("profile: the same qualification submitted twice is listed once", count === 1, String(count));
    await ctx.close();
  }

  // ================= 3. service catalogue (Administrator)
  {
    const { page: A, ctx } = await actor(b, "admin");
    await A.goto(`${BASE}/office/catalogue`);
    step("catalogue: the Office sees each live service with its Engine 5 pricing", /Engine 5 pricing: kisumu county boda boda KES/.test(await text(A)));
    let form = formWith(A, "Register as draft");
    await form.locator('input[name="service_code"]').fill(`TRANSPORT-BODA-E2E${RUN}`);
    await form.locator('input[name="service_name"]').fill(`E2E Ride ${RUN}`);
    await form.locator('input[name="description"]').fill("Journey test service");
    await press(A, "Register as draft", form);
    step("catalogue: a dispatched service is registered as a draft", await ok(form), await formError(form));
    await A.goto(`${BASE}/office/catalogue`);
    let card = A.locator(".trs-card", { hasText: `TRANSPORT-BODA-E2E${RUN}` }).first();
    step("catalogue: the draft states why it cannot go live (no coverage)", /No coverage/.test(await card.innerText()));
    form = formWith(A, "Add coverage", card);
    await form.locator('select[name="jurisdiction"]').selectOption("KISUMU_COUNTY");
    await press(A, "Add coverage", form);
    await A.goto(`${BASE}/office/catalogue`);
    card = A.locator(".trs-card", { hasText: `TRANSPORT-BODA-E2E${RUN}` }).first();
    A.once("dialog", (dlg) => dlg.accept());
    form = formWith(A, "Activate", card);
    await press(A, "Activate", form);
    step("catalogue: activation without an Engine 5 price is refused on screen", /No Engine 5 pricing/.test(await formError(form)), await formError(form));
    A.once("dialog", (dlg) => dlg.accept());
    form = formWith(A, "Retire", card);
    await form.locator('input[name="reason"]').fill("Journey test");
    await press(A, "Retire", form);
    await A.goto(`${BASE}/office/catalogue`);
    card = A.locator(".trs-card", { hasText: `TRANSPORT-BODA-E2E${RUN}` }).first();
    step("catalogue: the unused draft is retired", /Retired/i.test(await card.innerText()));

    card = A.locator(".trs-card", { hasText: "TRANSPORT-TUKTUK-STANDARD" }).first();
    A.once("dialog", (dlg) => dlg.accept());
    form = formWith(A, "Suspend", card);
    await form.locator('input[name="reason"]').fill("Journey test suspension");
    await press(A, "Suspend", form);
    await A.goto(`${BASE}/office/catalogue`);
    card = A.locator(".trs-card", { hasText: "TRANSPORT-TUKTUK-STANDARD" }).first();
    step("catalogue: a live service is suspended", (await card.getByRole("button", { name: "Reinstate", exact: true }).count()) > 0);
    A.once("dialog", (dlg) => dlg.accept());
    await press(A, "Reinstate", formWith(A, "Reinstate", card));
    await A.goto(`${BASE}/office/catalogue`);
    card = A.locator(".trs-card", { hasText: "TRANSPORT-TUKTUK-STANDARD" }).first();
    step("catalogue: it is reinstated (its Engine 5 price is in place)", (await card.getByRole("button", { name: "Suspend", exact: true }).count()) > 0);
    await ctx.close();

    const { page: C, ctx: c2 } = await actor(b, "customer");
    await C.goto(`${BASE}/office/catalogue`);
    step("catalogue: a customer cannot reach the catalogue screen", !C.url().includes("/office/catalogue"), C.url());
    await c2.close();
  }

  // ================= 4. Executive scenario comparison
  {
    const { page: F0, ctx: f0 } = await actor(b, "founder");
    const g = await grant(F0, "Esther Executive Test", "EXECUTIVE");
    step("scenario: the Founder grants the Executive role for the run", !g, g);
    const { page: E, ctx } = await actor(b, "executive");
    await E.goto(`${BASE}/office/executive`);
    for (const rate of ["11.00", "13.50"]) {
      const card = E.locator(".trs-card", { hasText: "Pricing" }).filter({ has: E.locator('input[name="__rate"]') }).first();
      const form = formWith(E, "Run scenario", card);
      await form.locator('select[name="__row_a"]').selectOption({ index: 0 });
      await form.locator('input[name="__rate"]').fill(rate);
      await form.locator('input[name="run_label"]').fill(`e2e ${RUN} at ${rate}`);
      await press(E, "Run scenario", form);
      await E.goto(`${BASE}/office/executive`);
    }
    const runs = await poll(async () => { await E.goto(`${BASE}/office/executive`); const t = await text(E); return t.includes(`e2e ${RUN} at 11.00`) && t.includes(`e2e ${RUN} at 13.50`); }, { tries: 10, every: 2000 });
    step("scenario: an Executive runs two pricing scenarios with inputs", !!runs);
    const form = formWith(E, "Compare");
    const opt = async (label) => (await form.locator('select[name="base_run_id"] option', { hasText: label }).first().getAttribute("value"));
    await form.locator('select[name="base_run_id"]').selectOption(await opt(`e2e ${RUN} at 11.00`));
    await form.locator('select[name="compared_run_id"]').selectOption(await opt(`e2e ${RUN} at 13.50`));
    await form.locator('select[name="comparison_metric"]').selectOption("trailing_30d_revenue_kes");
    await press(E, "Compare", form);
    await E.goto(`${BASE}/office/executive`);
    step("scenario: the comparison is shown with its difference", (await text(E)).includes(`e2e ${RUN} at 11.00 → e2e ${RUN} at 13.50`));
    await ctx.close();

    const { page: A, ctx: a2 } = await actor(b, "admin");
    await A.goto(`${BASE}/office/executive`);
    step("D26: an Administrator cannot reach the Executive Dashboard", !A.url().includes("/office/executive"), A.url());
    await a2.close();
    await revoke(F0, "Esther Executive Test", "EXECUTIVE");     // leave the role as j8 left it
    await f0.close();
  }

  // ================= 5. Office compliance forms
  {
    const { page: F, ctx } = await actor(b, "founder");
    await F.goto(`${BASE}/office/compliance`);
    let form = formWith(F, "Record cycle");
    await form.locator('input[name="cycle_start"]').fill("2026-09-15");
    await form.locator('input[name="cycle_end"]').fill("2026-10-14");
    await form.locator('input[name="publication_date"]').fill("2026-09-14");
    await form.locator('input[name="__petrol"]').fill("213.69");
    await form.locator('input[name="__diesel"]').fill("218.08");
    await form.locator('input[name="source_reference"]').fill("EPRA maximum retail prices, cycle 15 Sep - 14 Oct 2026");
    await press(F, "Record cycle", form);
    step("compliance: the Founder records the EPRA cycle with its source", await ok(form), await formError(form));
    await F.goto(`${BASE}/office/compliance`);
    step("compliance: the cycle in force is shown", /kisumu county · petrol super · 2026-09-15 – 2026-10-14 KES 213\.69/i.test(await text(F)), (await text(F)).match(/kisumu county · petrol super[^/]{0,60}/i)?.[0] ?? "not shown");
    form = formWith(F, "Record cycle");
    await form.locator('input[name="cycle_start"]').fill("2026-11-01");
    await form.locator('input[name="cycle_end"]').fill("2026-11-30");
    await form.locator('input[name="publication_date"]').fill("2026-10-14");
    await form.locator('input[name="__petrol"]').fill("214");
    await form.locator('input[name="source_reference"]').fill("wrong cycle");
    await press(F, "Record cycle", form);
    step("compliance: a cycle that is not 15th-14th is refused with a reason", (await formError(form)).length > 0, await formError(form));

    await F.goto(`${BASE}/office/compliance`);
    form = formWith(F, "Look up");
    await form.locator('input[name="identifier"]').fill(`JTDBR32E3${N}12`.slice(0, 17));
    await press(F, "Look up", form);
    await F.goto(`${BASE}/office/compliance`);
    step("compliance: an NTSA VIN lookup is listed and marked simulated", (await text(F)).includes(`JTDBR32E3${N}12`.slice(0, 17)) && /VIN · simulated/.test(await text(F)));
    form = formWith(F, "Look up");
    await form.locator('input[name="identifier"]').fill("JTDBR32E3O0512345");
    await press(F, "Look up", form);
    step("compliance: an invalid VIN is refused with a reason", /VIN is 17 characters/.test(await formError(form)), await formError(form));

    await F.goto(`${BASE}/office/compliance`);
    form = formWith(F, "Record invoice");
    await form.locator('input[name="supplier_pin"]').fill("P000111222A");
    await form.locator('input[name="supplier_name"]').fill("Kisumu Fuel Station");
    await form.locator('input[name="cu_invoice_number"]').fill(`CU00${N}${RUN}`);
    await form.locator('input[name="invoice_date"]').fill("2026-10-10");
    await form.locator('input[name="amount_kes:n"]').fill("4800");
    await press(F, "Record invoice", form);
    step("compliance: a supplier invoice is recorded", await ok(form), await formError(form));
    await form.locator('input[name="supplier_pin"]').fill("P000111222A");    // the same invoice again (the form resets after saving)
    await form.locator('input[name="supplier_name"]').fill("Kisumu Fuel Station");
    await form.locator('input[name="cu_invoice_number"]').fill(`CU00${N}${RUN}`);
    await form.locator('input[name="invoice_date"]').fill("2026-10-10");
    await form.locator('input[name="amount_kes:n"]').fill("4800");
    await press(F, "Record invoice", form);
    step("compliance: the same supplier invoice submitted twice is refused", /already recorded/.test(await formError(form)), await formError(form));
    await F.goto(`${BASE}/office/compliance`);
    step("compliance: the Founder is offered the payroll confirmation; the rates show as provisional",
      (await F.getByRole("button", { name: "Record professional confirmation" }).count()) > 0 && /awaiting professional confirmation/.test(await text(F)));
    await ctx.close();

    const { page: A, ctx: a2 } = await actor(b, "admin");
    await A.goto(`${BASE}/office/compliance`);
    step("compliance: an Administrator sees the screen but not the payroll confirmation",
      A.url().includes("/office/compliance") && (await A.getByRole("button", { name: "Record professional confirmation" }).count()) === 0);
    await a2.close();
    const { page: E, ctx: e2 } = await actor(b, "executive");
    await E.goto(`${BASE}/office/compliance`);
    step("compliance: an Executive cannot reach the compliance screen", !E.url().includes("/office/compliance"), E.url());
    await e2.close();
  }

  await b.close();
  writeResults("results-j17.json");
})();
