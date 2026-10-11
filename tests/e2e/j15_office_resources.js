// Journey -- TrustRide Office records equipment, a financial asset and vehicle
// maintenance through the Resources screen (TRS026-ENG-REMEDIATION-001 D20).
// Runs after j2 (vehicle KMFA123B in the rider's working unit) and leaves the
// unit back in service.
const { BASE, browser, actor, step, press, formError, writeResults } = require("./lib");

const RUN = Date.now().toString(36).slice(-4).toUpperCase();  // unique codes: the journey can be re-run
const text = async (page) => (await page.locator("body").innerText()).replace(/\s+/g, " ");

(async () => {
  const b = await browser();
  const F = (await actor(b, "founder")).page;

  // Equipment
  await F.goto(`${BASE}/office/resources`);
  let form = F.locator("form", { has: F.getByRole("button", { name: "Register equipment" }) });
  await form.locator('select[name="equipment_type"]').selectOption("SAFETY_GEAR");
  await form.locator('input[name="item_code"]').fill(`hel-${RUN}`);
  await form.locator('input[name="description"]').fill("Rider helmet, size L");
  await press(F, "Register equipment", form);
  let err = await formError(form);
  await F.goto(`${BASE}/office/resources`);
  step("Office: equipment registered and listed", (await text(F)).includes(`HEL-${RUN}`), err);

  // Financial asset
  form = F.locator("form", { has: F.getByRole("button", { name: "Register asset" }) });
  await form.locator('select[name="asset_type"]').selectOption("CASH_FLOAT");
  await form.locator('input[name="asset_code"]').fill(`float-${RUN}`);
  await form.locator('input[name="principal_amount_kes:n"]').fill("5000");
  await press(F, "Register asset", form);
  err = await formError(form);
  await F.goto(`${BASE}/office/resources`);
  step("Office: financial asset registered and listed", (await text(F)).includes(`FLOAT-${RUN} · cash float · KES 5,000 of 5,000`), err);

  // Vehicle maintenance
  let vcard = F.locator(".trs-card", { hasText: "custodian" }).filter({ hasText: "KMFA123B" }).first();
  form = vcard.locator("form", { has: F.getByRole("button", { name: "Open maintenance" }) });
  if (!(await form.count())) step("Office: maintenance offered on KMFA123B", false, "no Open maintenance form");
  else {
    await form.locator('select[name="maintenance_type"]').selectOption("ROUTINE_SERVICE");
    await form.locator('input[name="description"]').fill("5,000 km service");
    await form.locator('input[name="cost_kes:n"]').fill("2500");
    await press(F, "Open maintenance", form);
    err = await formError(form);
    await F.goto(`${BASE}/office/resources`);
    vcard = F.locator(".trs-card", { hasText: "custodian" }).filter({ hasText: "KMFA123B" }).first();
    step("Office: maintenance opened on KMFA123B", /in routine service since/.test(await vcard.innerText()), err);
    const unit = F.locator(".trs-card", { hasText: "KMFA123B" }).filter({ has: F.getByRole("button", { name: "Return to service" }) }).first();
    step("Office: the rider's working unit is off service while the vehicle is maintained", (await unit.count()) > 0);

    form = vcard.locator("form", { has: F.getByRole("button", { name: "Complete maintenance" }) });
    await form.locator('input[name="condition_after"]').fill("Good -- serviced");
    await press(F, "Complete maintenance", form);
    err = await formError(form);
    await F.goto(`${BASE}/office/resources`);
    vcard = F.locator(".trs-card", { hasText: "custodian" }).filter({ hasText: "KMFA123B" }).first();
    step("Office: maintenance completed", !/in routine service since/.test(await vcard.innerText())
      && (await vcard.getByRole("button", { name: "Open maintenance" }).count()) > 0, err);

    const back = F.locator(".trs-card", { hasText: "KMFA123B" }).filter({ has: F.getByRole("button", { name: "Return to service" }) }).first();
    if (await back.count()) {
      const f2 = back.locator("form", { has: F.getByRole("button", { name: "Return to service" }) });
      await f2.locator('input[name="reason"]').fill("Service completed");
      await press(F, "Return to service", f2);
      err = await formError(f2);
    }
    await F.goto(`${BASE}/office/resources`);
    step("Office: the working unit is back in service", (await F.locator(".trs-card", { hasText: "KMFA123B" })
      .filter({ has: F.getByRole("button", { name: "Return to service" }) }).count()) === 0, err);
  }

  await b.close();
  writeResults("results.json");
})();
