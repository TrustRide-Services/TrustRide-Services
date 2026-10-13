// Journey -- WP9 Founder decisions in the browser: the three-incorrect-attempt limit and block, next of kin
// (name, refusal without probing, decline), and the Office's next-of-kin follow-up on an open support case.
// Re-runnable: every person it registers is new.
const { BASE, browser, actor, step, press, formError, poll, writeResults } = require("./lib");

const N = String(Date.now() % 1000000).padStart(6, "0");
const RUN = Date.now().toString(36).slice(-4).toUpperCase();
const text = async (page) => (await page.locator("body").innerText()).replace(/\s+/g, " ");
const formWith = (page, button, scope) => (scope ?? page).locator("form", { has: page.getByRole("button", { name: button, exact: true }) }).first();

async function signUp(b, key, name, id, phone) {
  const a = await actor(b, key);
  const P = a.page;
  await P.goto(`${BASE}/register`);
  await P.fill('input[name="legalName"]', name);
  await P.fill('input[name="nationalId"]', id);
  await P.fill('input[name="phone"]', phone);
  await P.fill('input[name="email"]', `${key}@trustride.test`);
  await P.fill('input[name="password"]', "Trustride-e2e-2026");
  await P.check('input[name="consent"]');
  await P.locator('button[type="submit"]').click();
  await P.waitForURL(/\/verify/, { timeout: 30000 }).catch(() => {});
  return a;
}

(async () => {
  const b = await browser();

  // ================= 1. three incorrect submissions, then the block
  {
    const a = await signUp(b, `limit-${N}`, "Limit Journey Person", `00${N}1`, `0796${N}`);
    const P = a.page;
    for (const [attempt, nextId] of [[1, `00${N}2`], [2, `00${N}3`]]) {
      const shown = await poll(async () => { await P.goto(`${BASE}/verify`); return /attempts remaining/.test(await text(P)); }, { tries: 30, every: 3000 });
      step(`limit: after incorrect submission ${attempt} the person sees ${3 - attempt} of 3 attempts remaining`,
        !!shown && (await text(P)).includes(`${3 - attempt} of 3 attempts remaining`), (await text(P)).match(/\d of 3 attempts remaining/)?.[0] ?? "not shown");
      const form = formWith(P, "Correct and check again");
      await form.locator('input[name="national_id"]').fill(nextId);
      await press(P, "Correct and check again", form);
    }
    const blocked = await poll(async () => { await P.goto(`${BASE}/verify`); return /Identity verification is blocked/.test(await text(P)); }, { tries: 30, every: 3000 });
    step("limit: after the third incorrect submission verification is blocked", !!blocked);
    step("limit: no retry form is offered once blocked", (await P.getByRole("button", { name: "Correct and check again" }).count()) === 0);
    await P.goto(`${BASE}/dashboard`);
    step("gate: the blocked (unverified) person cannot reach the Customer dashboard", !P.url().includes("/dashboard"), P.url());
    await a.ctx.close();
  }

  // ================= 2. next of kin
  // The kin: a new, verified person with a Customer profile.
  const kinName = `Kin Journey ${RUN}`;
  const kinPhone = `0795${N}`;
  const k = await signUp(b, `kin-${N}`, kinName, `3${N}5`, kinPhone);
  const K = k.page;
  const ok = await poll(async () => { await K.goto(`${BASE}/verify`); return /Welcome to TrustRide/.test(await text(K)); }, { tries: 40, every: 3000 });
  const code = await poll(async () => {
    await K.goto(`${BASE}/verify`);
    const t = await K.locator("text=Staging — messages").locator("..").textContent().catch(() => "");
    return /\b(\d{6})\b/.exec(t ?? "")?.[1];
  }, { tries: 20, every: 3000 });
  if (code) { await K.fill('input[name="code"]', code); await press(K, "Verify"); }
  await K.goto(`${BASE}/verify`);
  await press(K, "Continue as Customer");
  step("kin: the named person is a verified TrustRide identity with a verified phone", !!ok && !!code);

  const { page: C, ctx: cctx } = await actor(b, "customer");
  await cctx.clearCookies({ name: "trs_acting" });
  await cctx.clearCookies({ name: /^trs_s_/ });
  await C.goto(`${BASE}/dashboard/profile`);
  let form = formWith(C, "Name next of kin");
  if (!(await form.count())) form = formWith(C, "Name someone else");
  const nameBtn = (await C.getByRole("button", { name: "Name next of kin", exact: true }).count()) ? "Name next of kin" : "Name someone else";
  await form.locator('input[name="full_name"]').fill("Somebody Else");
  await form.locator('input[name="phone"]').fill(kinPhone);
  await press(C, nameBtn, form);
  step("kin: a wrong name for a real phone is refused without saying whether the phone is registered",
    /No verified TrustRide identity matches that phone number and full name/.test(await formError(form)), await formError(form));
  await form.locator('input[name="full_name"]').fill(kinName);
  await form.locator('input[name="phone"]').fill(kinPhone);
  await press(C, nameBtn, form);
  await C.goto(`${BASE}/dashboard/profile`);
  const kinSection = (await text(C)).match(/Next of kin The person[^]{0,260}/i)?.[0] ?? "no section";
  step("kin: the customer names their next of kin and sees it on their profile", kinSection.includes(kinName), kinSection);

  await K.goto(`${BASE}/dashboard/profile`);
  step("kin: the named person sees who named them, with a way to decline", /You are named as next of kin by: Akinyi Customer Test/.test(await text(K))
    && (await K.getByRole("button", { name: "Decline", exact: true }).count()) > 0);
  await K.goto(`${BASE}/dashboard/notifications`);
  step("kin: the named person was notified", /You were named as next of kin/.test(await text(K)));

  // ================= 3. Office follow-up on an open support case
  await C.goto(`${BASE}/dashboard/support`);
  form = formWith(C, "Send to TrustRide");
  await form.locator('select[name="category"]').selectOption("ACCOUNT");
  await form.locator('input[name="subject"]').fill(`Unreachable test ${RUN}`);
  await form.locator('textarea[name="body"]').fill("Please call me back.");
  await press(C, "Send to TrustRide", form);
  const { page: A, ctx: actx } = await actor(b, "admin");
  await A.goto(`${BASE}/office/support`);
  const card = A.locator(".trs-card", { hasText: `Unreachable test ${RUN}` }).first();
  form = formWith(A, "Next of kin", card);
  await form.locator('input[name="reason"]').fill("short");
  await press(A, "Next of kin", form);
  const tooShort = (await formError(form)) || "";
  step("kin: the Office must give a real reason (browser or database refuses a short one)", tooShort.length > 0 || !(await form.locator(".text-success").count()), tooShort);
  await A.goto(`${BASE}/office/support`);
  form = formWith(A, "Next of kin", A.locator(".trs-card", { hasText: `Unreachable test ${RUN}` }).first());
  await form.locator('input[name="reason"]').fill("Customer unreachable for two hours about this case");
  await press(A, "Next of kin", form);
  const shown = (await form.locator(".text-success").allTextContents()).join(" ");
  step("kin: the Office sees the next of kin's name and verified phone for the open case", shown.includes(kinName) && shown.includes(`+254${kinPhone.slice(1)}`), shown);
  await actx.close();

  // ================= 4. the named person declines
  await K.goto(`${BASE}/dashboard/profile`);
  await press(K, "Decline", formWith(K, "Decline"));
  await C.goto(`${BASE}/dashboard/profile`);
  step("kin: after the decline the customer's profile shows no next of kin", /No next of kin named yet/.test(await text(C)));
  await C.goto(`${BASE}/dashboard/notifications`);
  step("kin: the customer is told their next of kin declined", /Your next of kin declined/.test(await text(C)));
  await cctx.close();
  await k.ctx.close();

  await b.close();
  writeResults("results-j18.json");
})();
