// Node test for the MetaMap adapter (no network): node --test supabase/functions/integration-gateway/metamap.test.ts
import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { metamapVerify, resetTokenCache, METAMAP_PRODUCTION_BASE, type IdentityJob } from "./metamap.ts";

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

const secrets: Record<string, string> = {
  METAMAP_CLIENT_ID: "cid", METAMAP_CLIENT_SECRET: "csecret",
  METAMAP_WEBHOOK_URL: "https://example.supabase.co/functions/v1/metamap-webhook", METAMAP_WEBHOOK_TOKEN: "tok en",
};
const env = (n: string) => secrets[n];
const tokenOk = { status: 200, body: { access_token: "jwt-1", expiresIn: 3600 } };

const person: IdentityJob = { request_id: "11111111-1111-1111-1111-111111111111", operation: "IDENTITY_VERIFY", adapter_type: "PRODUCTION",
  payload: { document_number: "12345678", first_name: "Wanjiku", last_name: "Otieno" } };
const entity: IdentityJob = { request_id: "22222222-2222-2222-2222-222222222222", operation: "ENTITY_VERIFY", adapter_type: "PRODUCTION",
  payload: { registration_number: "PVT-ABC1234", legal_name: "Mwangaza Logistics Limited" } };

beforeEach(() => resetTokenCache());

test("IPRS: OAuth client credentials, then the documented request; a found record is a definitive answer", async () => {
  const found = { data: { documentNumber: "12345678", fullName: "Wanjiku Achieng Otieno" }, error: null };
  const m = mock([tokenOk, { status: 200, body: found }]);
  const out = await metamapVerify(person, { fetch: m.fetch, env });
  assert.equal(m.calls[0].url, `${METAMAP_PRODUCTION_BASE}/oauth/`);
  assert.equal((m.calls[0].init.headers as Record<string, string>).Authorization, `Basic ${btoa("cid:csecret")}`);
  assert.equal(m.calls[0].init.body, "grant_type=client_credentials");
  assert.equal(m.calls[1].url, `${METAMAP_PRODUCTION_BASE}/govchecks/v1/ke/iprs`);
  assert.equal((m.calls[1].init.headers as Record<string, string>).Authorization, "Bearer jwt-1");
  const sent = JSON.parse(String(m.calls[1].init.body));
  assert.deepEqual({ ...sent, callbackUrl: undefined }, { documentNumber: "12345678", firstName: "Wanjiku", lastName: "Otieno", callbackUrl: undefined });
  assert.equal(sent.callbackUrl, `${secrets.METAMAP_WEBHOOK_URL}?request_id=${person.request_id}&token=tok%20en`);
  assert.deepEqual(out, { kind: "done", success: true, providerReference: null, response: found, error: null });
});

test("the token is reused until it nears expiry", async () => {
  const m = mock([tokenOk, { status: 200, body: { data: { fullName: "A" } } }, { status: 200, body: { data: { fullName: "B" } } }]);
  let now = 1_000_000;
  await metamapVerify(person, { fetch: m.fetch, env, now: () => now });
  now += 30 * 60 * 1000;
  await metamapVerify(person, { fetch: m.fetch, env, now: () => now });
  assert.equal(m.calls.filter((c) => c.url.endsWith("/oauth/")).length, 1);
});

test("BRS: registrationNumber and callbackURL as documented; the answer is passed on unchanged for Engine 6 to minimise", async () => {
  const brs = { status: 200, id: "kenyan-brs-validation", error: null,
    data: { companyName: "Mwangaza Logistics Limited", registrationStatus: "Registered", kraPIN: "P051234567Z", shareHolders: [{ idNumber: "30000001" }] } };
  const m = mock([tokenOk, { status: 200, body: brs }]);
  const out = await metamapVerify(entity, { fetch: m.fetch, env });
  assert.equal(m.calls[1].url, `${METAMAP_PRODUCTION_BASE}/govchecks/v1/ke/brs`);
  const sent = JSON.parse(String(m.calls[1].init.body));
  assert.equal(sent.registrationNumber, "PVT-ABC1234");
  assert.ok(sent.callbackURL.includes("request_id=" + entity.request_id));
  assert.equal(out.success, true);
  assert.deepEqual(out.response, brs);
});

test("notFound is a definitive answer (not retried)", async () => {
  const nf = { data: null, error: { type: "govCheckError", code: "kenyanIprs.notFound", message: "No results" } };
  const out = await metamapVerify(person, { fetch: mock([tokenOk, { status: 200, body: nf }]).fetch, env });
  assert.equal(out.success, true);
  assert.deepEqual(out.response, nf);
});

test("systemError / serviceUnavailable is retried", async () => {
  const su = { data: null, error: { type: "systemError", code: "kenyanIprs.serviceUnavailable" } };
  const out = await metamapVerify(person, { fetch: mock([tokenOk, { status: 200, body: su }]).fetch, env });
  assert.equal(out.success, false);
  assert.match(String(out.error), /^METAMAP_UNAVAILABLE: kenyanIprs.serviceUnavailable/);
});

test("HTTP 5xx is retried", async () => {
  const out = await metamapVerify(person, { fetch: mock([tokenOk, { status: 502, body: {} }]).fetch, env });
  assert.equal(out.success, false);
});

test("a timeout or network failure is retried, never treated as an answer", async () => {
  const timeout = Object.assign(new Error("The operation was aborted due to timeout"), { name: "TimeoutError" });
  const out = await metamapVerify(person, { fetch: mock([tokenOk, timeout]).fetch, env });
  assert.deepEqual(out, { kind: "done", success: false, error: "METAMAP_UNREACHABLE: TimeoutError" });
});

test("a rejected token is dropped so the next attempt authenticates again", async () => {
  const m = mock([tokenOk, { status: 401, body: {} }, { status: 200, body: { access_token: "jwt-2" } }, { status: 200, body: { data: { fullName: "A" } } }]);
  const first = await metamapVerify(person, { fetch: m.fetch, env });
  assert.equal(first.success, false);
  assert.match(String(first.error), /METAMAP_AUTH_REJECTED/);
  const second = await metamapVerify(person, { fetch: m.fetch, env });
  assert.equal(second.success, true);
  assert.equal((m.calls[3].init.headers as Record<string, string>).Authorization, "Bearer jwt-2");
});

test("OAuth failure is reported as an authentication failure (retried), never as an answer", async () => {
  const out = await metamapVerify(person, { fetch: mock([{ status: 401, body: { message: "bad" } }]).fetch, env });
  assert.deepEqual(out, { kind: "done", success: false, error: "METAMAP_AUTH_FAILED: HTTP 401" });
});

test("missing credentials fail before any call", async () => {
  const m = mock([]);
  const out = await metamapVerify(person, { fetch: m.fetch, env: () => undefined });
  assert.equal(out.success, false);
  assert.match(String(out.error), /METAMAP_CLIENT_ID is not configured/);
  assert.equal(m.calls.length, 0);
});

test("SANDBOX refuses without a MetaMap-supplied sandbox host (none is documented)", async () => {
  await assert.rejects(metamapVerify({ ...person, adapter_type: "SANDBOX" }, { fetch: mock([]).fetch, env }), /METAMAP_SANDBOX_NOT_AVAILABLE/);
});

test("an incomplete request is refused before any call", async () => {
  const m = mock([]);
  await assert.rejects(metamapVerify({ ...person, payload: { document_number: "12345678" } }, { fetch: m.fetch, env }), /INVALID_REQUEST/);
  assert.equal(m.calls.length, 0);
});

test("no callback is sent unless both the webhook URL and token are configured", async () => {
  const m = mock([tokenOk, { status: 200, body: { data: { fullName: "A" } } }]);
  await metamapVerify(person, { fetch: m.fetch, env: (n) => (n === "METAMAP_WEBHOOK_TOKEN" ? undefined : secrets[n]) });
  assert.equal(JSON.parse(String(m.calls[1].init.body)).callbackUrl, undefined);
});
