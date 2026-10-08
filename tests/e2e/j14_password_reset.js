// j14: "Forgot password" end to end -- request the link, open the real email
// (local mailpit), choose a new password, log in with it. LOCAL stack only;
// the test password is restored afterwards.
const { execSync } = require("child_process");
const { BASE, browser, step, writeResults } = require("./lib");

const DB = process.env.TRS_DB_CONTAINER || "supabase_db_TrustRide-Services";
const MAIL = process.env.TRS_MAILPIT || "http://127.0.0.1:54324";
const EMAIL = "customer@trustride.test";
const OLD = "Trustride-e2e-2026";
const NEW = "Trustride-reset-2026";
const sql = (q) => execSync(`docker exec -i ${DB} psql -U postgres -d postgres -X -A -t -q`, { input: q, env: { ...process.env, MSYS_NO_PATHCONV: "1" } }).toString().trim();

async function latestLink(since) {
  for (let i = 0; i < 20; i++) {
    const list = await (await fetch(`${MAIL}/api/v1/search?query=${encodeURIComponent(`to:"${EMAIL}"`)}`)).json();
    const m = (list.messages ?? []).find((x) => new Date(x.Created) > since);
    if (m) {
      const msg = await (await fetch(`${MAIL}/api/v1/message/${m.ID}`)).json();
      const link = /https?:\/\/[^\s"'<>]+\/auth\/v1\/verify\?[^\s"'<>]+/.exec(msg.HTML || msg.Text)?.[0];
      if (link) return link.replace(/&amp;/g, "&");
    }
    await new Promise((r) => setTimeout(r, 1500));
  }
  return null;
}

(async () => {
  const b = await browser();
  try {
    const page = await (await b.newContext()).newPage();
    page.setDefaultTimeout(20000);
    const since = new Date(Date.now() - 2000);
    await page.goto(`${BASE}/login?mode=forgot`);
    await page.fill('input[type="email"]', EMAIL);
    await page.click('button[type="submit"]');
    step("Forgot password: reset requested",
      await page.getByText("a reset link is on its way").waitFor({ timeout: 15000 }).then(() => true, () => false));

    const link = await latestLink(since);
    step("Reset email delivered with a link", !!link);
    if (!link) return;

    await page.goto(link);
    await page.waitForURL(/\/reset-password/, { timeout: 20000 }).catch(() => {});
    step("Email link signs the person in and opens the new-password page", page.url().includes("/reset-password"), page.url());
    if (!page.url().includes("/reset-password")) return;

    await page.fill('input[name="password"]', NEW);
    await page.fill('input[name="confirm"]', NEW);
    await page.click('button[type="submit"]');
    await page.waitForURL(/\/verify/, { timeout: 20000 }).catch(() => {});
    step("New password saved; routed to the Gate", page.url().includes("/verify"), page.url());

    const fresh = await (await b.newContext()).newPage();
    await fresh.goto(`${BASE}/login`);
    await fresh.fill('input[type="email"]', EMAIL);
    await fresh.fill('input[type="password"]', NEW);
    await fresh.click('button[type="submit"]');
    await fresh.waitForURL(/\/verify/, { timeout: 20000 }).catch(() => {});
    step("Log in with the new password", fresh.url().includes("/verify"), fresh.url());

    await page.goto(`${BASE}/auth/callback?code=not-a-real-code`);
    step("A used or bad link explains itself on the login page", page.url().includes("/login") && (await page.getByText("expired or was already used").count()) > 0, page.url());
  } finally {
    await b.close();
    sql(`UPDATE auth.users SET encrypted_password = extensions.crypt('${OLD}', extensions.gen_salt('bf')) WHERE email = '${EMAIL}';`);
    writeResults("results-j14.json");
  }
})();
