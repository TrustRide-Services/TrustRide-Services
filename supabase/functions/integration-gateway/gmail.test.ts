// Node test for the Google email adapter (no network): node --test supabase/functions/integration-gateway/gmail.test.ts
import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { sendEmail, resetTokenCache, buildMessage, GMAIL_SEND_URL, GOOGLE_TOKEN_URL, GMAIL_SEND_SCOPE, type EmailJob } from "./gmail.ts";

type Call = { url: string; init: RequestInit };
function mock(responses: Array<{ status: number; body: unknown } | Error>) {
  const calls: Call[] = [];
  const fetch = async (url: string, init: RequestInit = {}) => {
    calls.push({ url, init });
    const next = responses.shift();
    if (!next) throw new Error("unexpected call " + url);
    if (next instanceof Error) throw next;
    return new Response(JSON.stringify(next.body), { status: next.status, headers: { "Content-Type": "application/json" } });
  };
  return { fetch, calls };
}
const fromB64url = (s: string) => Buffer.from(s.replace(/-/g, "+").replace(/_/g, "/"), "base64");
const decodeRaw = (call: Call) => fromB64url(JSON.parse(String(call.init.body)).raw).toString("utf8");
const mimeBody = (raw: string) => Buffer.from(raw.split("\r\n\r\n")[1].replace(/\r\n/g, ""), "base64").toString("utf8");

const rt: Record<string, string> = { GMAIL_AUTH_MODE: "REFRESH_TOKEN", GMAIL_CLIENT_ID: "cid", GMAIL_CLIENT_SECRET: "cs", GMAIL_REFRESH_TOKEN: "rtok", GMAIL_SENDER: "trustride.ke@gmail.com" };
const job: EmailJob = { request_id: "33333333-3333-3333-3333-333333333333", operation: "NOTIFY_EMAIL", adapter_type: "PRODUCTION",
  payload: { destination: "wanjiku@example.co.ke", subject: "Your TrustRide booking", body: "Your driver is on the way. Asante sana — KES 650.40" } };
const tokenOk = { status: 200, body: { access_token: "ya29.a", expires_in: 3599 } };
const sent = { status: 200, body: { id: "18c0ffee", threadId: "18c0ffee", labelIds: ["SENT"] } };

beforeEach(() => resetTokenCache());

test("refresh-token mode: token exchange, then one Gmail send with a well-formed message", async () => {
  const m = mock([tokenOk, sent]);
  const out = await sendEmail(job, { fetch: m.fetch, env: (n) => rt[n] });
  assert.equal(m.calls[0].url, GOOGLE_TOKEN_URL);
  const form = new URLSearchParams(String(m.calls[0].init.body));
  assert.deepEqual(Object.fromEntries(form), { grant_type: "refresh_token", client_id: "cid", client_secret: "cs", refresh_token: "rtok" });
  assert.equal(m.calls[1].url, GMAIL_SEND_URL);
  assert.equal((m.calls[1].init.headers as Record<string, string>).Authorization, "Bearer ya29.a");
  const raw = decodeRaw(m.calls[1]);
  assert.match(raw, /^From: TrustRide <trustride\.ke@gmail\.com>\r\nTo: <wanjiku@example\.co\.ke>\r\nSubject: Your TrustRide booking\r\n/);
  assert.match(raw, /Content-Type: text\/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n/);
  assert.equal(mimeBody(raw), job.payload.body);
  assert.deepEqual(out, { kind: "done", success: true, providerReference: "18c0ffee", response: { id: "18c0ffee", threadId: "18c0ffee" }, error: null });
});

test("service-account mode: a signed RS256 assertion for the sender with the gmail.send scope", async () => {
  const kp = await webcrypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]);
  const pkcs8 = Buffer.from(await webcrypto.subtle.exportKey("pkcs8", kp.privateKey)).toString("base64");
  const pem = `-----BEGIN PRIVATE KEY-----\n${pkcs8.replace(/.{64}/g, "$&\n")}\n-----END PRIVATE KEY-----\n`;
  const env = (n: string) => ({ GMAIL_AUTH_MODE: "SERVICE_ACCOUNT", GMAIL_SENDER: "notices@trustride.ke",
    GMAIL_SERVICE_ACCOUNT_JSON: JSON.stringify({ client_email: "mailer@trustride.iam.gserviceaccount.com", private_key: pem }) } as Record<string, string>)[n];
  const m = mock([tokenOk, sent]);
  const now = Date.UTC(2026, 9, 12, 9, 0, 0);
  const out = await sendEmail(job, { fetch: m.fetch, env, now: () => now });
  assert.equal(out.success, true);
  const form = new URLSearchParams(String(m.calls[0].init.body));
  assert.equal(form.get("grant_type"), "urn:ietf:params:oauth:grant-type:jwt-bearer");
  const [h, c, s] = String(form.get("assertion")).split(".");
  assert.deepEqual(JSON.parse(fromB64url(h).toString()), { alg: "RS256", typ: "JWT" });
  assert.deepEqual(JSON.parse(fromB64url(c).toString()), { iss: "mailer@trustride.iam.gserviceaccount.com", sub: "notices@trustride.ke",
    scope: GMAIL_SEND_SCOPE, aud: GOOGLE_TOKEN_URL, iat: now / 1000, exp: now / 1000 + 3600 });
  assert.ok(await webcrypto.subtle.verify("RSASSA-PKCS1-v1_5", kp.publicKey, fromB64url(s), new TextEncoder().encode(`${h}.${c}`)), "signature verifies");
});

test("the token is reused until it nears expiry", async () => {
  const m = mock([tokenOk, sent, sent]);
  let now = 5_000_000;
  await sendEmail(job, { fetch: m.fetch, env: (n) => rt[n], now: () => now });
  now += 30 * 60 * 1000;
  await sendEmail(job, { fetch: m.fetch, env: (n) => rt[n], now: () => now });
  assert.equal(m.calls.filter((c) => c.url === GOOGLE_TOKEN_URL).length, 1);
});

test("non-ASCII subjects are RFC 2047 encoded", () => {
  const raw = buildMessage("a@trustride.ke", "TrustRide", "b@example.com", "Malipo — risiti", "x", "id1");
  assert.match(raw, /\r\nSubject: =\?UTF-8\?B\?[A-Za-z0-9+/=]+\?=\r\n/);
});

test("header injection and malformed recipients are refused before any call", async () => {
  for (const payload of [{ ...job.payload, destination: "a@b.com\r\nBcc: victim@example.com" }, { ...job.payload, subject: "Hi\nBcc: x@y.com" },
                         { ...job.payload, destination: "not-an-email" }, { ...job.payload, destination: "" }]) {
    const m = mock([]);
    const out = await sendEmail({ ...job, payload }, { fetch: m.fetch, env: (n) => rt[n] });
    assert.equal(out.success, false);
    assert.match(String(out.error), /^INVALID_REQUEST/);
    assert.equal(m.calls.length, 0);
  }
});

test("SANDBOX delivers only to the TrustRide test inbox, and refuses without one", async () => {
  const m = mock([tokenOk, sent]);
  await sendEmail({ ...job, adapter_type: "SANDBOX" }, { fetch: m.fetch, env: (n) => ({ ...rt, GMAIL_SANDBOX_RECIPIENT: "qa@trustride.ke" } as Record<string, string>)[n] });
  assert.match(decodeRaw(m.calls[1]), /\r\nTo: <qa@trustride\.ke>\r\n/);
  const none = mock([]);
  const out = await sendEmail({ ...job, adapter_type: "SANDBOX" }, { fetch: none.fetch, env: (n) => rt[n] });
  assert.equal(out.success, false);
  assert.match(String(out.error), /GMAIL_SANDBOX_RECIPIENT is not configured/);
  assert.equal(none.calls.length, 0);
});

test("a revoked refresh token is an authentication failure, not a send", async () => {
  const out = await sendEmail(job, { fetch: mock([{ status: 400, body: { error: "invalid_grant" } }]).fetch, env: (n) => rt[n] });
  assert.deepEqual(out, { kind: "done", success: false, error: "GMAIL_AUTH_FAILED: invalid_grant" });
});

test("Gmail refusals and rate limits are failures (retried by Engine 6); a 401 drops the token", async () => {
  const m = mock([tokenOk, { status: 429, body: { error: { code: 429, status: "RESOURCE_EXHAUSTED" } } }, { status: 401, body: {} }, tokenOk, sent]);
  const a = await sendEmail(job, { fetch: m.fetch, env: (n) => rt[n] });
  assert.equal(a.success, false);
  assert.equal(a.error, "GMAIL_SEND_FAILED: HTTP 429 RESOURCE_EXHAUSTED");
  const b = await sendEmail(job, { fetch: m.fetch, env: (n) => rt[n] });
  assert.equal(b.error, "GMAIL_SEND_FAILED: HTTP 401");
  const c = await sendEmail(job, { fetch: m.fetch, env: (n) => rt[n] });
  assert.equal(c.success, true);
  assert.equal(m.calls.filter((x) => x.url === GOOGLE_TOKEN_URL).length, 2);
});

test("a timeout is a failure, never a delivery", async () => {
  const timeout = Object.assign(new Error("aborted"), { name: "TimeoutError" });
  const out = await sendEmail(job, { fetch: mock([tokenOk, timeout]).fetch, env: (n) => rt[n] });
  assert.deepEqual(out, { kind: "done", success: false, error: "GMAIL_UNREACHABLE: TimeoutError" });
});

test("missing configuration fails before any call", async () => {
  const m = mock([]);
  const out = await sendEmail(job, { fetch: m.fetch, env: (n) => (n === "GMAIL_SENDER" ? "a@trustride.ke" : undefined) });
  assert.equal(out.success, false);
  assert.match(String(out.error), /GMAIL_AUTH_MODE is not configured/);
  assert.equal(m.calls.length, 0);
});
