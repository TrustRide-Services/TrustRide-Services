// Proof setup, through the screens only: a Sedan operator with a car (the
// wrong-class resource for Test D) and a fresh Protrack telemetry key.
const fs = require("fs");
const path = require("path");
const { BASE, browser, actor, step, press, formError, poll, writeResults } = require("./lib");
const text = async (p) => (await p.locator("body").innerText()).replace(/\s+/g, " ");

(async () => {
  const b = await browser();
  const F = (await actor(b, "founder")).page;

  // Sedan driver registers, verifies, requests Office access
  const sd = await actor(b, "sedan"); const S = sd.page;
  await S.goto(`${BASE}/verify`);
  if (/Sign in|Log in/i.test(await text(S)) || S.url().includes("/login")) {
    await S.goto(`${BASE}/register`);
    await S.fill('input[name="legalName"]', "Samuel Sedan Test");
    await S.fill('input[name="nationalId"]', "31000009");
    await S.fill('input[name="phone"]', "0711000009");
    await S.fill('input[name="email"]', "sedan@trustride.test");
    await S.fill('input[name="password"]', "Trustride-e2e-2026");
    await S.check('input[name="consent"]');
    await S.locator('button[type="submit"]').click();
    await S.waitForURL(/\/verify/, { timeout: 30000 }).catch(() => {});
  }
  const ok = await poll(async () => { await S.goto(`${BASE}/verify`); return /Welcome to TrustRide/.test(await text(S)); }, { tries: 40, every: 3000 });
  step("Setup: sedan driver identity verified", !!ok);
  const code = await poll(async () => { await S.goto(`${BASE}/verify`); return /\b(\d{6})\b/.exec((await text(S)).split(/staging/i)[1] ?? "")?.[1]; }, { tries: 20, every: 3000 });
  if (code && await S.locator('input[name="code"]').count()) { await S.fill('input[name="code"]', code); await press(S, "Verify"); }
  await S.goto(`${BASE}/verify`);
  if (await S.locator('select[name="surface"]').count()) {
    await S.selectOption('select[name="surface"]', "OPERATOR_APP");
    await S.fill('input[name="justification"]', "Sedan driver applicant");
    await S.getByRole("button", { name: "Request Office access" }).click(); await S.waitForLoadState("networkidle");
  }
  await sd.save();

  // Office approves and onboards with a verified car
  await F.goto(`${BASE}/office/requests`);
  const r = F.locator(".trs-card", { hasText: "Samuel Sedan Test" }).filter({ has: F.getByRole("button", { name: "Approve" }) }).first();
  if (await r.count()) { await r.locator('input[name="notes"]').first().fill("Approved"); await press(F, "Approve", r); }
  await F.goto(`${BASE}/office/resources`);
  if (!/KDA101S/.test(await text(F))) {
    const form = F.locator("form", { has: F.getByRole("button", { name: "Register", exact: true }) });
    await form.locator('select[name="object_type"]').selectOption("CAR");
    await form.locator('input[name="plate_number"]').fill("KDA 101S");
    await form.locator('input[name="make"]').fill("Toyota");
    await form.locator('input[name="model"]').fill("Probox");
    await form.locator('input[name="year:n"]').fill("2021");
    await press(F, "Register", form);
  }
  await F.goto(`${BASE}/office/resources`);
  const car = F.locator(".trs-card", { hasText: "custodian" }).filter({ hasText: "KDA101S" }).first();
  if (await car.getByRole("button", { name: "Add to fleet (NTSA check)" }).count()) await press(F, "Add to fleet (NTSA check)", car);
  const ver = await poll(async () => { await F.goto(`${BASE}/office/resources`); return /VERIFIED/i.test(await F.locator(".trs-card", { hasText: "custodian" }).filter({ hasText: "KDA101S" }).first().innerText()); }, { tries: 30, every: 3000 });
  step("Setup: car KDA101S NTSA-verified", !!ver);
  const form = F.locator("form", { has: F.getByRole("button", { name: "Form working unit" }) });
  if (await form.locator('select[name="operator_user_id"] option', { hasText: "Samuel Sedan Test" }).count()) {
    await form.locator('select[name="operator_user_id"]').selectOption({ label: "Samuel Sedan Test" });
    await form.locator('select[name="capacity_class"]').selectOption("SEDAN");
    const opt = await form.locator('select[name="fleet_resource_id"] option', { hasText: "KDA101S" }).getAttribute("value");
    await form.locator('select[name="fleet_resource_id"]').selectOption(opt);
    await press(F, "Form working unit", form);
    step("Setup: Sedan unit formed", !(await formError(form)), await formError(form));
  }
  await S.goto(`${BASE}/office/operator`);
  if (await S.getByRole("button", { name: "Start shift" }).count()) await press(S, "Start shift");
  await S.goto(`${BASE}/office/operator`);
  step("Setup: Sedan unit on duty", /AVAILABLE/.test(await text(S)));
  await sd.save();

  // Fresh Protrack key (shown once) for the tracking stage
  await F.goto(`${BASE}/office/integrations`);
  const sys = F.locator(".trs-card", { hasText: "Protrack GPS" }).filter({ has: F.getByRole("button", { name: "Issue telemetry key" }) }).first();
  await press(F, "Issue telemetry key", sys);
  await F.locator("code.select-all").first().waitFor({ timeout: 15000 }).catch(() => {});
  const key = await F.locator("code.select-all").first().textContent().catch(() => null);
  step("Setup: Protrack key issued for the proof", !!key);
  if (key) fs.writeFileSync(path.join(__dirname, "protrack.key"), key.trim());
  await b.close(); writeResults("proof-setup.json");
})();
