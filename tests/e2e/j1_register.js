// Journey H (governance) start + A's first steps for every person:
// register -> identity verified (IPRS simulator) -> phone verified -> Gate.
const { BASE, browser, actor, step, shot, press, poll, writeResults } = require("./lib");

const PEOPLE = {
  founder: { name: "Albert Founder Test", id: "31000001", phone: "0711000001" },
  operator: { name: "Otieno Rider Test", id: "31000002", phone: "0711000002" },
  customer: { name: "Akinyi Customer Test", id: "31000003", phone: "0711000003" },
  vendor: { name: "Wanjiru Vendor Test", id: "31000004", phone: "0711000004" },
  governor: { name: "Kisumu County Revenue Test", id: "31000005", phone: "0711000005" },
  eaworker: { name: "Achieng Assistant Test", id: "31000006", phone: "0711000006" },
};

async function register(b, key) {
  const p = PEOPLE[key];
  const a = await actor(b, key);
  const { page } = a;
  await page.goto(`${BASE}/register`);
  await page.fill('input[name="legalName"]', p.name);
  await page.fill('input[name="nationalId"]', p.id);
  await page.fill('input[name="phone"]', p.phone);
  await page.fill('input[name="email"]', `${key}@trustride.test`);
  await page.fill('input[name="password"]', "Trustride-e2e-2026");
  await page.check('input[name="consent"]');
  await page.locator('button[type="submit"]').click();
  await page.waitForURL(/\/verify/, { timeout: 30000 }).catch(() => {});
  step(`${key}: registered and routed to the Gate`, page.url().includes("/verify"), page.url());

  // Identity verification is asynchronous (Engine 6 IPRS simulator via the dispatch cycle).
  const verified = await poll(async () => {
    await page.goto(`${BASE}/verify`);
    return (await page.getByText("Welcome to TrustRide").count()) > 0;
  }, { tries: 40, every: 3000 });
  step(`${key}: identity verified by Engine 6`, !!verified);
  if (!verified) { await shot(page, `${key}-verify`); return a; }

  // Phone: captured at registration; a code was sent (simulator shows it at the Gate).
  const code = await poll(async () => {
    await page.goto(`${BASE}/verify`);
    const t = await page.locator("text=Staging — messages").locator("..").textContent().catch(() => "");
    const m = /\b(\d{6})\b/.exec(t ?? "");
    return m?.[1];
  }, { tries: 20, every: 3000 });
  step(`${key}: verification code delivered (simulated SMS)`, !!code);
  if (code) {
    await page.fill('input[name="code"]', code);
    await press(page, "Verify");
    await page.goto(`${BASE}/verify`);
    step(`${key}: phone verified`, (await page.getByText("Your phone").count()) === 0);
  }
  await a.save();
  return a;
}

(async () => {
  const b = await browser();
  const only = process.argv[2];
  for (const key of Object.keys(PEOPLE)) {
    if (only && key !== only) continue;
    const a = await register(b, key);
    await a.ctx.close();
  }
  // A registered identity that opens /register again is sent to the Gate (D18: read through the function layer).
  if (!only || only === "customer") {
    const c = await actor(b, "customer");
    await c.page.goto(`${BASE}/register`);
    await c.page.waitForURL(/\/verify/, { timeout: 15000 }).catch(() => {});
    step("customer: opening /register again goes to the Gate", c.page.url().includes("/verify"), c.page.url());
    await c.ctx.close();
  }
  await b.close();
  writeResults("results.json");
})();
