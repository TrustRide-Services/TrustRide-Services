// Staff roles through the Users page: a real Executive and a real
// Administrator (not the Founder), role boundaries, suspension, revocation.
const { BASE, browser, actor, step, press, formError, poll, writeResults } = require("./lib");
const text = async (page) => (await page.locator("body").innerText()).replace(/\s+/g, " ");

async function register(b, key, name, id, phone) {
  const a = await actor(b, key);
  const { page } = a;
  await page.goto(`${BASE}/register`);
  await page.fill('input[name="legalName"]', name);
  await page.fill('input[name="nationalId"]', id);
  await page.fill('input[name="phone"]', phone);
  await page.fill('input[name="email"]', `${key}@trustride.test`);
  await page.fill('input[name="password"]', "Trustride-e2e-2026");
  await page.check('input[name="consent"]');
  await page.locator('button[type="submit"]').click();
  await page.waitForURL(/\/verify/, { timeout: 30000 }).catch(() => {});
  const ok = await poll(async () => { await page.goto(`${BASE}/verify`); return /Welcome to TrustRide/.test(await text(page)); }, { tries: 40, every: 3000 });
  step(`${key}: registered and identity verified`, !!ok);
  await a.save();
  return a;
}
async function grant(F, name, role) {
  await F.goto(`${BASE}/office/users?q=${encodeURIComponent(name.split(" ")[0])}`);
  const c = F.locator(".trs-card", { hasText: name }).first();
  const f = c.locator("form", { has: F.getByRole("button", { name: "Grant role" }) });
  await f.locator('select[name="role_code"]').selectOption(role);
  await press(F, "Grant role", f);
  return formError(f);
}

(async () => {
  const b = await browser();
  const F = (await actor(b, "founder")).page;
  const ex = await register(b, "executive", "Esther Executive Test", "31000007", "0711000007");
  const ad = await register(b, "admin", "Adam Administrator Test", "31000008", "0711000008");
  const X = ex.page, A = ad.page;

  step("Office: Founder grants EXECUTIVE", !(await grant(F, "Esther Executive Test", "EXECUTIVE")));
  step("Office: Founder grants ADMINISTRATOR", !(await grant(F, "Adam Administrator Test", "ADMINISTRATOR")));

  await X.goto(`${BASE}/office/executive`);
  step("Executive: Executive Dashboard opens with KPIs", /Orders placed/.test(await text(X)), (await text(X)).slice(0, 200));
  await X.goto(`${BASE}/office/users`);
  step("Executive: refused at Users & roles (Administrator only)", !/Grant role/.test(await text(X)), X.url());
  await X.goto(`${BASE}/office/requests`);
  step("Executive: sees the request queue but cannot decide", !(await X.getByRole("button", { name: "Approve" }).count()));

  await A.goto(`${BASE}/office/users`);
  step("Administrator: Users & roles opens", /Grant role/.test(await text(A)), (await text(A)).slice(0, 200));
  const f = A.locator(".trs-card", { hasText: "Esther Executive Test" }).locator("form", { has: A.getByRole("button", { name: "Grant role" }) });
  const offersFounder = await f.locator('select[name="role_code"] option[value="FOUNDER"]').count();
  step("Administrator: Founder role is never grantable", offersFounder === 0);
  const tryExec = await (async () => {
    await A.goto(`${BASE}/office/users?q=Akinyi`);
    const g = A.locator(".trs-card", { hasText: "Akinyi Customer Test" }).locator("form", { has: A.getByRole("button", { name: "Grant role" }) });
    await g.locator('select[name="role_code"]').selectOption("EXECUTIVE");
    await press(A, "Grant role", g);
    return formError(g);
  })();
  step("Administrator: cannot grant EXECUTIVE (Founder only)", !!tryExec, tryExec);
  await A.goto(`${BASE}/office/executive`);
  step("Administrator: Executive Dashboard refused", !/Orders placed/.test(await text(A)), A.url());

  // Suspension takes effect on the next request; reinstatement restores it.
  await F.goto(`${BASE}/office/users?q=Adam`);
  const sc = F.locator(".trs-card", { hasText: "Adam Administrator Test" }).first();
  const sf = sc.locator("form", { has: F.getByRole("button", { name: "Suspend" }) });
  await sf.locator('input[name="reason"]').fill("UI journey: suspension test");
  F.once("dialog", (d) => d.accept());
  await press(F, "Suspend", sf);
  await A.goto(`${BASE}/office/users`);
  step("Suspended administrator is refused everywhere", !/Grant role/.test(await text(A)), (await text(A)).slice(0, 200));
  await F.goto(`${BASE}/office/users?q=Adam`);
  const rf = F.locator(".trs-card", { hasText: "Adam Administrator Test" }).locator("form", { has: F.getByRole("button", { name: "Reinstate" }) });
  await rf.locator('input[name="reason"]').fill("Test complete");
  await press(F, "Reinstate", rf);
  await A.goto(`${BASE}/office/users`);
  step("Reinstated administrator has access again", /Grant role/.test(await text(A)));

  // Revoke the Executive role
  await F.goto(`${BASE}/office/users?q=Esther`);
  const rv = F.locator(".trs-card", { hasText: "Esther Executive Test" }).getByRole("button", { name: "Revoke executive" });
  if (await rv.count()) { F.once("dialog", (d) => d.accept()); await rv.click(); await F.waitForLoadState("networkidle"); await F.waitForTimeout(1500); }
  await X.goto(`${BASE}/office/executive`);
  step("Revoked executive loses the Executive Dashboard", !/Orders placed/.test(await text(X)), X.url());

  await b.close();
  writeResults("results.json");
})();
