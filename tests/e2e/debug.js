// Ad-hoc inspection: node debug.js <actor> <path> [buttonText] [field=value ...]
const { BASE, browser, actor, shot, press } = require("./lib");
(async () => {
  const [who, path, button, ...fields] = process.argv.slice(2);
  const b = await browser();
  const a = await actor(b, who);
  await a.page.goto(`${BASE}${path}`);
  if (button) {
    const form = a.page.locator("form", { has: a.page.getByRole("button", { name: button, exact: true }) }).first();
    for (const f of fields) {
      const [k, v] = f.split("=");
      const el = form.locator(`[name="${k}"]`);
      if ((await el.evaluate((e) => e.tagName)) === "SELECT") await el.selectOption(v); else await el.fill(v);
    }
    await press(a.page, button, form);
    console.log("FORM MESSAGES:", (await form.locator("p").allTextContents()).join(" | "));
  }
  console.log("URL:", a.page.url());
  console.log((await a.page.locator("body").innerText()).replace(/\s+/g, " ").slice(0, 1500));
  await shot(a.page, `debug-${who}`);
  await a.save();
  await b.close();
})();
