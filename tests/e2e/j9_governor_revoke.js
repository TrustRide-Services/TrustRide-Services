// D4 boundary both ways: Office withdraws the Governor's scope -> nothing; grants again -> only that aggregate.
const { BASE, browser, actor, step, writeResults } = require("./lib");
const text = async (p) => (await p.locator("body").innerText()).replace(/\s+/g, " ");
async function toggle(F, label) {
  await F.goto(`${BASE}/office/users?q=Kisumu`);
  const btn = F.locator(".trs-card", { hasText: "Kisumu County Revenue Test" }).getByRole("button", { name: label });
  F.once("dialog", (d) => d.accept()); await btn.click(); await F.waitForLoadState("networkidle"); await F.waitForTimeout(1500);
}
(async () => {
  const b = await browser();
  const F = (await actor(b, "founder")).page; const G = (await actor(b, "governor")).page;
  await toggle(F, "✓ aggregate service volumes");
  await G.goto(`${BASE}/dashboard/governor`);
  step("D4: scope withdrawn -> Governor sees no data, only the 'no scopes granted' message", !/Granted data/i.test(await text(G)) && /No data scopes have been granted/.test(await text(G)), (await text(G)).slice(-300));
  await toggle(F, "aggregate service volumes");
  await G.goto(`${BASE}/dashboard/governor`);
  step("D4: scope granted again -> only completed services by family", /Granted data/i.test(await text(G)) && /Completed services by family/.test(await text(G)) && !/Settled revenue/.test(await text(G)));
  await b.close(); writeResults("results.json");
})();
