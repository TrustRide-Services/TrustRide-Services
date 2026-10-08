// j13: a verified identity that already holds Operator access, before any
// Founder exists, is still offered the one-time Founder claim (the live-site
// case: the Founder's own account had an active Operator environment).
// Self-contained on the LOCAL stack: the existing Founder assignment is set
// aside for the run and restored afterwards.
const { execSync } = require("child_process");
const { BASE, browser, step, writeResults } = require("./lib");

const DB = process.env.TRS_DB_CONTAINER || "supabase_db_TrustRide-Services";
const sql = (q) => execSync(`docker exec -i ${DB} psql -U postgres -d postgres -X -A -t -q`, { input: q, env: { ...process.env, MSYS_NO_PATHCONV: "1" } }).toString().trim();
const FOUNDER = "(SELECT role_id FROM trustride.role_definition WHERE role_code = 'FOUNDER')";
const OPERATOR_EMAIL = "operator@trustride.test";

(async () => {
  const held = sql(`UPDATE trustride.role_assignment SET status = 'E2E_SET_ASIDE' WHERE role_id = ${FOUNDER} AND status = 'ACTIVE' RETURNING assignment_id;`);
  const b = await browser();
  try {
    const ctx = await b.newContext();
    const page = await ctx.newPage();
    await page.goto(`${BASE}/login`);
    await page.fill('input[type="email"]', OPERATOR_EMAIL);
    await page.fill('input[type="password"]', "Trustride-e2e-2026");
    await page.click('button[type="submit"]');
    await page.waitForURL(/\/verify/, { timeout: 30000 });

    step("Operator: still holds TrustRide Office access", (await page.getByText("You hold TrustRide Office access").count()) > 0);
    const claim = page.getByRole("button", { name: "Claim Founder authority" });
    step("Operator, no Founder yet: Founder claim is offered", (await claim.count()) === 1);

    // A second tab holding the same Gate, to replay the claim afterwards.
    const stale = await ctx.newPage();
    await stale.goto(`${BASE}/verify`);

    if (await claim.count()) {
      await claim.click();
      await page.waitForURL(/\/office/, { timeout: 30000 }).catch(() => {});
      const holder = sql(`SELECT u.email FROM trustride.role_assignment ra JOIN auth.users u ON u.id = ra.user_id WHERE ra.role_id = ${FOUNDER} AND ra.status = 'ACTIVE';`);
      step("Claim: the operator now holds the single Founder assignment", holder === OPERATOR_EMAIL, holder);
      await page.goto(`${BASE}/verify`);
      step("Gate: shows Office access as Founder, claim no longer offered",
        (await page.getByText("You hold TrustRide Office access as Founder").count()) > 0 && (await claim.count()) === 0);

      // Repeat submission by the same person (double click / stale tab).
      await stale.getByRole("button", { name: "Claim Founder authority" }).click();
      await stale.waitForURL((u) => !u.pathname.endsWith("/verify") || u.search.includes("error"), { timeout: 30000 }).catch(() => {});
      step("Repeat claim by the Founder: lands in the Office, no database error shown",
        new URL(stale.url()).pathname.startsWith("/office") && !stale.url().includes("error"), stale.url());
    }
  } finally {
    await b.close();
    sql(`DELETE FROM trustride.role_assignment WHERE role_id = ${FOUNDER} AND status = 'ACTIVE' AND user_id = (SELECT id FROM auth.users WHERE email = '${OPERATOR_EMAIL}');`);
    if (held) sql(`UPDATE trustride.role_assignment SET status = 'ACTIVE' WHERE assignment_id IN ('${held.split(/\s+/).join("','")}');`);
    writeResults("results-j13.json");
  }
})();
