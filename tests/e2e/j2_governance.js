// Journeys H (governance) and D (admin) up to an allocatable resource pool:
// Founder claim -> actors apply on their surfaces -> Office approves ->
// capabilities activate -> Office registers base/vehicle (NTSA) and forms
// working units -> operators go on duty.
const { BASE, browser, actor, step, shot, press, formError, poll, writeResults } = require("./lib");

(async () => {
  const b = await browser();
  const founder = await actor(b, "founder");
  const F = founder.page;

  // --- Founder claim (one-time genesis)
  await F.goto(`${BASE}/verify`);
  if (await F.getByRole("button", { name: "Claim Founder authority" }).count()) {
    await F.getByRole("button", { name: "Claim Founder authority" }).click();
    await F.waitForURL(/\/office/, { timeout: 30000 }).catch(() => {});
  }
  await F.goto(`${BASE}/office`);
  step("Founder: claimed and lands in the Admin Console", (await F.getByRole("heading", { name: "Admin Console" }).count()) > 0, F.url());

  // --- Second visitor cannot claim Founder
  const cust = await actor(b, "customer");
  await cust.page.goto(`${BASE}/verify`);
  step("Customer: Founder claim no longer offered", (await cust.page.getByRole("button", { name: "Claim Founder authority" }).count()) === 0);
  // Unauthorized: customer cannot open the Office
  await cust.page.goto(`${BASE}/office/resources`);
  step("Customer: TrustRide Office refused (routed back to the Gate)", cust.page.url().includes("/verify"), cust.page.url());
  // Customer environment
  await cust.page.goto(`${BASE}/verify`);
  if (await cust.page.getByRole("button", { name: "Continue as Customer" }).count()) await cust.page.getByRole("button", { name: "Continue as Customer" }).click();
  await cust.page.waitForURL(/\/dashboard/).catch(() => {});
  step("Customer: environment active, Customer App opens", cust.page.url().endsWith("/dashboard"), cust.page.url());
  await cust.save();

  // --- Operator and EA worker request Office access (Operator App)
  for (const who of ["operator", "eaworker"]) {
    const a = await actor(b, who);
    await a.page.goto(`${BASE}/verify`);
    if (await a.page.locator('select[name="surface"]').count()) {
      await a.page.selectOption('select[name="surface"]', "OPERATOR_APP");
      await a.page.fill('input[name="justification"]', who === "operator" ? "Boda rider applicant, licence B-12345" : "Executive assistant applicant");
      await a.page.getByRole("button", { name: "Request Office access" }).click();
      await a.page.waitForLoadState("networkidle");
    }
    await a.page.goto(`${BASE}/verify`);
    step(`${who}: Office access request submitted and shown as pending`, (await a.page.getByText("is with TrustRide Office").count()) > 0);
    await a.page.goto(`${BASE}/office/operator`);
    step(`${who}: Operator App refused before approval`, a.page.url().includes("/verify"), a.page.url());
    await a.save(); await a.ctx.close();
  }

  // --- Governor applies
  const gov = await actor(b, "governor");
  await gov.page.goto(`${BASE}/verify`);
  if (await gov.page.getByRole("button", { name: "Apply as Governor" }).count()) await gov.page.getByRole("button", { name: "Apply as Governor" }).click();
  await gov.page.waitForURL(/\/dashboard\/governor/).catch(() => {});
  await gov.page.goto(`${BASE}/dashboard/governor`);
  if (await gov.page.locator('input[name="line.description"]').count()) {
    await gov.page.fill('input[name="line.description"]', "Kisumu County Revenue Board -- levy oversight");
    await gov.page.fill('input[name="scope.authority"]', "Kisumu County Revenue Board");
    await gov.page.fill('input[name="scope.oversight_scope"]', "Trip volumes and revenue for levy assessment");
    await press(gov.page, "Submit to TrustRide Office");
  }
  await gov.page.goto(`${BASE}/dashboard/governor`);
  step("Governor: regulatory access request submitted", (await gov.page.getByText("is with TrustRide Office").count()) > 0, await formError(gov.page));
  await gov.save();

  // --- Vendor applies
  const ven = await actor(b, "vendor");
  await ven.page.goto(`${BASE}/marketplace/vendor`);
  if (await ven.page.locator('input[name="line.description"]').count()) {
    await ven.page.fill('input[name="line.description"]', "Kondele Motors -- used motorcycles");
    await press(ven.page, "Submit to TrustRide Office");
  }
  await ven.page.goto(`${BASE}/marketplace/vendor`);
  step("Vendor: vendor application submitted", (await ven.page.getByText("is with TrustRide Office").count()) > 0, ven.page.url() + " " + await formError(ven.page));
  if (!(await ven.page.getByText("is with TrustRide Office").count())) await shot(ven.page, "vendor-apply");
  await ven.save();

  // --- Founder decides every request
  await F.goto(`${BASE}/office/requests`);
  const names = ["Otieno Rider Test", "Achieng Assistant Test", "Kisumu County Revenue Test", "Wanjiru Vendor Test"];
  for (const n of names) {
    const card = F.locator(".trs-card", { hasText: n }).filter({ has: F.getByRole("button", { name: "Approve" }) }).first();
    if (!(await card.count())) { step(`Office: request from ${n} visible in the queue`, false); continue; }
    await card.locator('input[name="notes"]').first().fill("Approved in UI journey");
    await press(F, "Approve", card);
    const err = await formError(card).catch(() => "");
    await F.goto(`${BASE}/office/requests`);
    const stillOpen = await F.locator(".trs-card", { hasText: n }).filter({ has: F.getByRole("button", { name: "Approve" }) }).count();
    step(`Office: approved request from ${n}`, stillOpen === 0, err);
  }

  // Approved capabilities reach the actors' surfaces
  await gov.page.goto(`${BASE}/dashboard/governor`);
  step("Governor: approved, sees no data until a scope is granted (D4)", (await gov.page.getByText("Granted data").count()) === 0 && !(await gov.page.getByText("is with TrustRide Office").count()));
  await ven.page.goto(`${BASE}/marketplace/vendor`);
  step("Vendor: approved, listing form unlocked", (await ven.page.getByRole("button", { name: "Publish listing" }).count()) > 0);

  // --- Office: base, vehicle, NTSA, units
  await F.goto(`${BASE}/office/resources`);
  if (!(await F.getByText("Kisumu CBD Hub").count())) {
    const form = F.locator("form", { has: F.getByRole("button", { name: "Add base" }) });
    await form.locator('input[name="estate_code"]').fill("KSM-HUB-01");
    await form.locator('input[name="estate_name"]').fill("Kisumu CBD Hub");
    await form.locator('select[name="estate_type"]').selectOption("OPERATING_HUB");
    await form.locator('input[name="lat:n"]').fill("-0.0917");
    await form.locator('input[name="lon:n"]').fill("34.7680");
    await press(F, "Add base", form);
    step("Office: base registered", (await F.getByText("Kisumu CBD Hub").count()) > 0, await formError(form));
  }
  if (!(await F.getByText("KMFA123B").count())) {
    const form = F.locator("form", { has: F.getByRole("button", { name: "Register", exact: true }) });
    await form.locator('select[name="object_type"]').selectOption("MOTORCYCLE");
    await form.locator('input[name="plate_number"]').fill("KMFA123B");
    await form.locator('input[name="make"]').fill("Bajaj");
    await form.locator('input[name="model"]').fill("Boxer 150");
    await form.locator('input[name="year:n"]').fill("2024");
    await press(F, "Register", form);
    await F.goto(`${BASE}/office/resources`);
    step("Office: motorcycle registered", (await F.getByText("KMFA123B").count()) > 0, await formError(form));
  }
  // Tracker device
  if (!(await F.getByRole("option", { name: /PT-0001/ }).count()) && !(await F.getByText("tracker PT").count())) {
    const form = F.locator("form", { has: F.getByRole("button", { name: "Register", exact: true }) });
    await form.locator('select[name="object_type"]').selectOption("TRACKING_DEVICE");
    await form.locator('input[name="make"]').fill("Protrack");
    await form.locator('input[name="model"]').fill("GT06");
    await form.locator('input[name="serial_number"]').fill("PT-0001");
    await press(F, "Register", form);
  }
  await F.goto(`${BASE}/office/resources`);
  let vcard = F.locator(".trs-card", { hasText: "custodian" }).filter({ hasText: "KMFA123B" }).first();
  if (await vcard.getByRole("button", { name: "Add to fleet (NTSA check)" }).count()) {
    await press(F, "Add to fleet (NTSA check)", vcard);
  }
  const verified = await poll(async () => {
    await F.goto(`${BASE}/office/resources`);
    return /VERIFIED/i.test(await F.locator(".trs-card", { hasText: "custodian" }).filter({ hasText: "KMFA123B" }).first().innerText());
  }, { tries: 30, every: 3000 });
  step("Office: vehicle NTSA-verified through Engine 6", !!verified);
  vcard = F.locator(".trs-card", { hasText: "custodian" }).filter({ hasText: "KMFA123B" }).first();
  if (await vcard.getByRole("button", { name: "Fit tracker" }).count()) await press(F, "Fit tracker", vcard);
  await F.goto(`${BASE}/office/resources`);
  step("Office: Protrack tracker fitted to the vehicle", (await F.locator(".trs-card", { hasText: "custodian" }).filter({ hasText: "KMFA123B" }).first().textContent()).includes("tracker PT-0001"));

  // Onboard the rider with the motorcycle; the EA without a vehicle.
  for (const [n, cls, withVehicle] of [["Otieno Rider Test", "BODA_BODA", true], ["Achieng Assistant Test", "EXECUTIVE_ASSISTANT_HUMAN", false]]) {
    await F.goto(`${BASE}/office/resources`);
    const form = F.locator("form", { has: F.getByRole("button", { name: "Form working unit" }) });
    if (!(await form.count())) { step(`Office: onboarding form offers ${n}`, false, "no operator awaiting a unit"); continue; }
    const opt = form.locator('select[name="operator_user_id"] option', { hasText: n });
    if (!(await opt.count())) { step(`Office: ${n} awaiting a unit`, false); continue; }
    await form.locator('select[name="operator_user_id"]').selectOption({ label: n });
    await form.locator('select[name="capacity_class"]').selectOption(cls);
    if (withVehicle) await form.locator('select[name="fleet_resource_id"]').selectOption({ index: 1 });
    else await form.locator('select[name="fleet_resource_id"]').selectOption("");
    await press(F, "Form working unit", form);
    const err = await formError(form);
    await F.goto(`${BASE}/office/resources`);
    step(`Office: working unit formed for ${n} (${cls})`, (await F.locator(".trs-card", { hasText: n }).count()) > 0, err);
  }
  // EA credentials: vetting + skill
  await F.goto(`${BASE}/office/resources`);
  const ea = F.locator(".trs-card", { hasText: "Achieng Assistant Test" }).first();
  for (const cap of ["ENHANCED_VETTING_CLEARANCE", "SKILL_ERRANDS", "SKILL_SHOPPING"]) {
    if (!(await ea.count())) break;
    const form = ea.locator("form", { has: F.getByRole("button", { name: "Record credential" }) });
    if (!(await form.locator(`select[name="capability_type"] option[value="${cap}"]`).count())) { step(`Office: capability ${cap} offered`, false); continue; }
    await form.locator('select[name="capability_type"]').selectOption(cap);
    await form.locator('input[name="credential_ref"]').fill(`CERT-${cap.slice(0, 6)}`);
    await form.locator('input[name="expires_at"]').fill("2027-10-01");
    await press(F, "Record credential", form);
    step(`Office: EA credential ${cap} recorded`, !(await formError(form)), await formError(form));
  }

  // Operators go on duty from the Operator App
  for (const who of ["operator", "eaworker"]) {
    const a = await actor(b, who);
    await a.page.goto(`${BASE}/office/operator`);
    const on = a.page.getByRole("button", { name: /Start shift|Go on duty/i });
    if (await on.count()) await press(a.page, await on.first().textContent());
    await a.page.goto(`${BASE}/office/operator`);
    const body = await a.page.locator("body").innerText();
    step(`${who}: Operator App open, unit on duty`, /AVAILABLE|Available/.test(body), body.slice(0, 200));
    if (!/AVAILABLE|Available/.test(body)) await shot(a.page, `${who}-duty`);
    await a.save(); await a.ctx.close();
  }

  await founder.save();
  await b.close();
  writeResults("results.json");
})();
