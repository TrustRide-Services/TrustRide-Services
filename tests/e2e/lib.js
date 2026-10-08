// Shared helpers for the TrustRide UI journey run (local stack only).
const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");

const BASE = "http://localhost:3000";
const DIR = __dirname;
const results = [];

async function browser() {
  return chromium.launch({ headless: true });
}

async function actor(b, name) {
  const state = path.join(DIR, `state-${name}.json`);
  const ctx = await b.newContext(fs.existsSync(state) ? { storageState: state } : {});
  ctx.setDefaultTimeout(20000);
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log(`  [${name} pageerror] ${e.message}`));
  return { ctx, page, name, save: () => ctx.storageState({ path: state }) };
}

function step(label, ok, detail = "") {
  results.push({ label, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"}  ${label}${detail ? `  — ${detail}` : ""}`);
  return ok;
}

async function shot(page, name) {
  await page.screenshot({ path: path.join(DIR, `shot-${name}.png`), fullPage: true }).catch(() => {});
}

// Click a button by its visible text, optionally inside a container, and wait
// for the server action to settle (button returns from "…").
async function press(page, text, scope) {
  const root = scope ?? page;
  const btn = root.getByRole("button", { name: text, exact: true }).first();
  await page.waitForLoadState("networkidle").catch(() => {});
  await btn.click();
  await page.waitForTimeout(400);
  await page.waitForFunction(() => ![...document.querySelectorAll("button")].some((b) => b.textContent === "…"), null, { timeout: 30000 }).catch(() => {});
  await page.waitForLoadState("networkidle").catch(() => {});
}

// Text of any error the form under `scope` shows.
async function formError(scope) {
  const e = scope.locator(".text-danger");
  return (await e.count()) ? (await e.allTextContents()).join(" | ") : "";
}

async function poll(fn, { tries = 30, every = 2000 } = {}) {
  for (let i = 0; i < tries; i++) {
    const v = await fn();
    if (v) return v;
    await new Promise((r) => setTimeout(r, every));
  }
  return null;
}

function writeResults(file) {
  const out = path.join(DIR, file);
  const prev = fs.existsSync(out) ? JSON.parse(fs.readFileSync(out, "utf8")) : [];
  fs.writeFileSync(out, JSON.stringify(prev.concat(results), null, 1));
  const failed = results.filter((r) => !r.ok).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
}

module.exports = { BASE, browser, actor, step, shot, press, formError, poll, writeResults };
