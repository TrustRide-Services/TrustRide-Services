// Partner (fleet contribution), Intermediary (referral) and unauthorized
// journeys: other people's orders/jobs by URL, Office pages, raw API reads.
const fs = require("fs");
const path = require("path");
const { createClient } = require(path.join("C:/Users/ALBERT/TrustRide-Services/frontend/web/node_modules/@supabase/supabase-js"));
const { BASE, browser, actor, step, press, formError, poll, writeResults } = require("./lib");
const text = async (page) => (await page.locator("body").innerText()).replace(/\s+/g, " ");
const env = Object.fromEntries(fs.readFileSync(path.join(__dirname, "local.env"), "utf8").trim().split(/\r?\n/).map((l) => {
  const i = l.indexOf("="); return [l.slice(0, i), l.slice(i + 1).replace(/^"|"$/g, "")];
}));

async function apply(page, who, label, fields) {
  await page.goto(`${BASE}/verify`);
  const btn = page.getByRole("button", { name: `Apply as ${label}` });
  if (await btn.count()) { await btn.click(); await page.waitForLoadState("networkidle"); }
  await page.goto(`${BASE}/dashboard/${label.toLowerCase()}`);
  if (await page.locator('input[name="line.description"]').count()) {
    for (const [k, v] of Object.entries(fields)) {
      const el = page.locator(`[name="${k}"]`);
      if ((await el.evaluate((e) => e.tagName)) === "SELECT") await el.selectOption(v); else await el.fill(v);
    }
    await press(page, "Submit to TrustRide Office");
  }
  await page.goto(`${BASE}/dashboard/${label.toLowerCase()}`);
  step(`${who}: ${label} request submitted`, /is with TrustRide Office/.test(await text(page)), (await text(page)).slice(0, 200));
}
async function approve(F, name, notes) {
  await F.goto(`${BASE}/office/requests`);
  const c = F.locator(".trs-card", { hasText: name }).filter({ has: F.getByRole("button", { name: "Approve" }) }).first();
  if (!(await c.count())) return false;
  await c.locator('input[name="notes"]').first().fill(notes);
  await press(F, "Approve", c);
  return true;
}

(async () => {
  const b = await browser();
  const F = (await actor(b, "founder")).page;
  const op = await actor(b, "operator"); const O = op.page;
  const eaw = await actor(b, "eaworker"); const E = eaw.page;
  const cust = await actor(b, "customer"); const C = cust.page;
  const ven = await actor(b, "vendor"); const V = ven.page;

  // ================= Partner: a rider contributes their own motorcycle
  await apply(O, "Operator", "Partner", { "line.description": "My own motorcycle for TrustRide Kisumu", "scope.partner_category": "FLEET_CONTRIBUTOR" });
  step("Office: partnership request approved", await approve(F, "Otieno Rider Test", "Welcome as a fleet contributor"));
  await O.goto(`${BASE}/dashboard/partner`);
  step("Partner: approved; contribution form unlocked", (await O.getByRole("button", { name: "Submit contribution" }).count()) > 0, (await text(O)).slice(0, 200));
  if (await O.getByRole("button", { name: "Submit contribution" }).count()) {
    const form = O.locator("form", { has: O.getByRole("button", { name: "Submit contribution" }) });
    await form.locator("select").first().selectOption("MOTORCYCLE");
    await form.getByPlaceholder("Make").fill("TVS");
    await form.getByPlaceholder("Model").fill("HLX 125");
    await form.getByPlaceholder("Year").fill("2023");
    await form.getByPlaceholder("Plate").fill("KMFB456C");
    await form.getByRole("button", { name: "Submit contribution" }).click();
    await O.waitForTimeout(2500);
    step("Partner: vehicle contribution submitted", /Contribution submitted/.test(await text(O)), (await text(O)).slice(0, 300));
  }
  step("Office: contribution approved", await approve(F, "Otieno Rider Test", "Bring it for inspection Monday"));
  const contributed = await poll(async () => { await F.goto(`${BASE}/office/resources`); return /KMFB456C/.test(await text(F)) && /partner contributed/i.test(await text(F)); }, { tries: 20, every: 3000 });
  step("Partner: contributed vehicle registered in the fleet as partner-contributed (NTSA check started)", !!contributed, (await text(F)).match(/KMFB456C[^·]*·[^·]*·[^·]*/)?.[0] ?? "");

  // ================= Intermediary: referral code and a referral
  await apply(E, "EA worker", "Intermediary", { "line.description": "Referring boda owners in Kondele" });
  step("Office: facilitation request approved", await approve(F, "Achieng Assistant Test", "Approved"));
  await E.goto(`${BASE}/dashboard/intermediary`);
  const code = (await text(E)).match(/Referral code\s*([A-Z0-9-]{4,})/)?.[1];
  step("Intermediary: referral code issued", !!code, (await text(E)).slice(0, 300));
  if (code) {
    await C.goto(`${BASE}/dashboard/profile`);
    const rf = C.locator("form", { has: C.locator('input[name="referral_code"]') });
    if (await rf.count()) { await rf.locator('input[name="referral_code"]').fill(code); await press(C, "Apply code", rf); }
    await E.goto(`${BASE}/dashboard/intermediary`);
    step("Intermediary: referral recorded against their code", /Akinyi|Referrals · 1/i.test(await text(E)), (await text(E)).slice(0, 300));
  }

  // ================= Unauthorized journeys
  const someOrder = fs.readFileSync(path.join(__dirname, "order-url.txt"), "utf8").trim();
  await V.goto(someOrder);
  step("Security: another user's order URL shows nothing of it", /No such order on your identity|not|refused/i.test(await text(V)) && !/Otieno|KMFA123B/.test(await text(V)), (await text(V)).slice(0, 200));
  const jobId = someOrder.split("/").pop();
  await E.goto(`${BASE}/office/operator/${jobId}`);
  step("Security: an operator cannot open another operator's job", /not assigned to you/i.test(await text(E)), (await text(E)).slice(0, 200));
  for (const p of ["/office", "/office/users", "/office/integrations"]) {
    await C.goto(`${BASE}${p}`);
    step(`Security: customer refused at ${p}`, !C.url().includes("/office"), C.url());
  }
  await O.goto(`${BASE}/office/users`);
  step("Security: operator refused at the Admin Console", !/Users & roles/.test(await text(O)) || O.url().includes("/verify") || O.url().endsWith("/office/operator"), O.url());

  // Raw Data API as the customer
  const sb = createClient(env.API_URL, env.ANON_KEY, { db: { schema: "trustride" } });
  await sb.auth.signInWithPassword({ email: "customer@trustride.test", password: "Trustride-e2e-2026" });
  const me = (await sb.auth.getUser()).data.user.id;
  const orders = await sb.from("business_order").select("requester_user_id");
  step("Security (API): customer reads only their own orders", !orders.error ? orders.data.every((o) => o.requester_user_id === me) : true, orders.error?.message ?? `${orders.data.length} rows`);
  const users = await sb.from("platform_users").select("user_id, display_name");
  step("Security (API): customer reads only herself and the company she represents", (users.data ?? []).every((u) => u.user_id === me || u.display_name === "Akinyi Logistics Ltd"), JSON.stringify(users.data?.map((u) => u.display_name)));
  const ins = await sb.from("business_order").insert({ requester_user_id: me });
  step("Security (API): customer cannot write tables directly", !!ins.error, ins.error?.message);
  const s = await sb.rpc("fn_present_shell_session_open", { p_top_shell: "TRUSTRIDE_OFFICE", p_sub_shell: "ADMIN_CONSOLE", p_user_id: me, p_channel_type: "WEB", p_access_id: null });
  step("Security (API): customer cannot open the Admin Console", !!s.error, s.error?.message);
  const anon = createClient(env.API_URL, env.ANON_KEY, { db: { schema: "trustride" } });
  const a1 = await anon.from("business_order").select("order_id");
  step("Security (API): anonymous reads nothing", !!a1.error || a1.data.length === 0, a1.error?.message ?? `${a1.data.length} rows`);

  for (const a of [op, eaw, cust, ven]) await a.save();
  await b.close();
  writeResults("results.json");
})();
