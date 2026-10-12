// Hardening tests (no network) for Africa's Talking, WhatsApp, Daraja and the router:
//   node --test supabase/functions/integration-gateway/providers.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { sendSms, sendWhatsapp, stkPush, b2cPayout, nairobiTimestamp, type Job } from "./providers.ts";
import { handle } from "./router.ts";

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
const timeout = () => Object.assign(new Error("The operation was aborted due to timeout"), { name: "TimeoutError" });

const secrets: Record<string, string> = {
  AT_USERNAME: "trustride", AT_API_KEY: "atkey", AT_SENDER_ID: "TRUSTRIDE",
  WHATSAPP_TOKEN: "watoken", WHATSAPP_PHONE_NUMBER_ID: "1098",
  MPESA_CONSUMER_KEY: "ck", MPESA_CONSUMER_SECRET: "cs", MPESA_SHORTCODE: "174379", MPESA_PASSKEY: "pk",
  MPESA_CALLBACK_BASE_URL: "https://x.supabase.co/functions/v1/mpesa-callback", MPESA_CALLBACK_TOKEN: "cb tok",
  MPESA_B2C_SHORTCODE: "600000", MPESA_B2C_INITIATOR_NAME: "api", MPESA_B2C_SECURITY_CREDENTIAL: "cred",
};
const env = (n: string) => secrets[n];
const without = (name: string) => (n: string) => (n === name ? undefined : secrets[n]);
const job = (operation: string, payload: Record<string, unknown>, adapter: Job["adapter_type"] = "SANDBOX"): Job =>
  ({ request_id: "44444444-4444-4444-4444-444444444444", operation, adapter_type: adapter, payload });
const sms = job("NOTIFY_SMS", { destination: "+254712345678", body: "Your boda is on the way." });
const stk = job("STK_PUSH", { msisdn: "254712345678", amount: 651, account_reference: "ORDER-22" });
const b2c = job("B2C_PAYOUT", { msisdn: "254712345678", amount: 500, remarks: "Weekly earnings" });
const darajaToken = { status: 200, body: { access_token: "dt", expires_in: "3599" } };

// ---------------------------------------------------------------- SMS
test("SMS: sandbox host, apiKey header, sender ID; Success is delivered", async () => {
  const m = mock([{ status: 201, body: { SMSMessageData: { Recipients: [{ status: "Success", messageId: "ATX-1" }] } } }]);
  const out = await sendSms(sms, { fetch: m.fetch, env });
  assert.equal(m.calls[0].url, "https://api.sandbox.africastalking.com/version1/messaging");
  assert.equal((m.calls[0].init.headers as Record<string, string>).apiKey, "atkey");
  const form = m.calls[0].init.body as URLSearchParams;
  assert.equal(form.get("to"), "+254712345678");
  assert.equal(form.get("from"), "TRUSTRIDE");
  assert.ok(m.calls[0].init.signal, "the call has a timeout");
  assert.equal(out.kind === "done" && out.success, true);
});
test("SMS: production uses the live host", async () => {
  const m = mock([{ status: 201, body: { SMSMessageData: { Recipients: [{ status: "Success", messageId: "ATX-2" }] } } }]);
  await sendSms({ ...sms, adapter_type: "PRODUCTION" }, { fetch: m.fetch, env });
  assert.equal(m.calls[0].url, "https://api.africastalking.com/version1/messaging");
});
test("SMS: a rejected recipient (e.g. InsufficientBalance) is a failure with the provider's reason", async () => {
  const out = await sendSms(sms, { fetch: mock([{ status: 201, body: { SMSMessageData: { Recipients: [{ status: "InsufficientBalance" }] } } }]).fetch, env });
  assert.deepEqual([out.kind === "done" && out.success, out.kind === "done" && out.error], [false, "InsufficientBalance"]);
});
test("SMS: a non-Kenyan or malformed number is refused before any call", async () => {
  for (const destination of ["0712345678", "+255712345678", "+25471234567", "+254712345678\n"]) {
    const m = mock([]);
    const out = await sendSms({ ...sms, payload: { ...sms.payload, destination } }, { fetch: m.fetch, env });
    assert.match(String(out.kind === "done" && out.error), /^INVALID_REQUEST/);
    assert.equal(m.calls.length, 0);
  }
});
test("SMS: missing credentials fail closed before any call", async () => {
  const m = mock([]);
  await assert.rejects(sendSms(sms, { fetch: m.fetch, env: without("AT_API_KEY") }), /AT_API_KEY is not configured/);
  assert.equal(m.calls.length, 0);
});

// ------------------------------------------------------------ WhatsApp
test("WhatsApp: text message to the number without +, bearer token, timeout", async () => {
  const m = mock([{ status: 200, body: { messages: [{ id: "wamid.1" }] } }]);
  const out = await sendWhatsapp(job("NOTIFY_WHATSAPP", { destination: "+254712345678", body: "Hello" }), { fetch: m.fetch, env });
  assert.equal(m.calls[0].url, "https://graph.facebook.com/v20.0/1098/messages");
  assert.equal(JSON.parse(String(m.calls[0].init.body)).to, "254712345678");
  assert.equal((m.calls[0].init.headers as Record<string, string>).Authorization, "Bearer watoken");
  assert.ok(m.calls[0].init.signal);
  assert.deepEqual([out.kind === "done" && out.success, out.kind === "done" && out.providerReference], [true, "wamid.1"]);
});
test("WhatsApp: an approved template is used when configured", async () => {
  const m = mock([{ status: 200, body: { messages: [{ id: "wamid.2" }] } }]);
  await sendWhatsapp(job("NOTIFY_WHATSAPP", { destination: "+254712345678", subject: "Trip", body: "Hello" }),
    { fetch: m.fetch, env: (n) => ({ ...secrets, WHATSAPP_TEMPLATE_NAME: "trustride_notice" } as Record<string, string>)[n] });
  const sent = JSON.parse(String(m.calls[0].init.body));
  assert.equal(sent.type, "template");
  assert.equal(sent.template.name, "trustride_notice");
});
test("WhatsApp: Meta's error (e.g. outside the 24-hour window) is a failure with its message", async () => {
  const out = await sendWhatsapp(job("NOTIFY_WHATSAPP", { destination: "+254712345678", body: "x" }),
    { fetch: mock([{ status: 400, body: { error: { message: "Re-engagement message" } } }]).fetch, env });
  assert.deepEqual([out.kind === "done" && out.success, out.kind === "done" && out.error], [false, "Re-engagement message"]);
});

// -------------------------------------------------------------- Daraja
test("STK: OAuth, then the documented request: password, EAT timestamp, callback with token", async () => {
  const m = mock([darajaToken, { status: 200, body: { ResponseCode: "0", CheckoutRequestID: "ws_CO_1", MerchantRequestID: "m1" } }]);
  const now = Date.UTC(2026, 9, 12, 21, 30, 5);   // 00:30:05 on 13 Oct in Nairobi
  const out = await stkPush(stk, { fetch: m.fetch, env, now: () => now });
  assert.equal(m.calls[0].url, "https://sandbox.safaricom.co.ke/oauth/v1/generate?grant_type=client_credentials");
  assert.equal(m.calls[1].url, "https://sandbox.safaricom.co.ke/mpesa/stkpush/v1/processrequest");
  const b = JSON.parse(String(m.calls[1].init.body));
  assert.equal(b.Timestamp, "20261013003005");
  assert.equal(b.Password, btoa("174379pk20261013003005"));
  assert.deepEqual([b.Amount, b.PartyA, b.PartyB, b.PhoneNumber, b.AccountReference], [651, "254712345678", "174379", "254712345678", "ORDER-22"]);
  assert.equal(b.CallBackURL, `${secrets.MPESA_CALLBACK_BASE_URL}?kind=stk&token=cb%20tok`);
  assert.deepEqual([out.kind === "done" && out.success, out.kind === "done" && out.providerReference], [true, "ws_CO_1"]);
});
test("STK: Buy Goods sends to the till, never the paybill", async () => {
  const m = mock([darajaToken, { status: 200, body: { ResponseCode: "0", CheckoutRequestID: "ws_CO_2" } }]);
  await stkPush(stk, { fetch: m.fetch, env: (n) => ({ ...secrets, MPESA_TRANSACTION_TYPE: "CustomerBuyGoodsOnline", MPESA_PARTY_B: "5550001" } as Record<string, string>)[n] });
  assert.equal(JSON.parse(String(m.calls[1].init.body)).PartyB, "5550001");
});
test("STK: Safaricom's refusal is a failure with its message", async () => {
  const out = await stkPush(stk, { fetch: mock([darajaToken, { status: 400, body: { errorMessage: "Invalid PhoneNumber" } }]).fetch, env });
  assert.deepEqual([out.kind === "done" && out.success, out.kind === "done" && out.error], [false, "Invalid PhoneNumber"]);
});
test("Daraja: fractional, zero or negative amounts and non-Kenyan numbers are refused before any call", async () => {
  for (const payload of [{ ...stk.payload, amount: 650.4 }, { ...stk.payload, amount: 0 }, { ...stk.payload, amount: -5 }, { ...stk.payload, amount: "651" },
                         { ...stk.payload, msisdn: "+254712345678" }, { ...stk.payload, msisdn: "255712345678" }]) {
    for (const fn of [stkPush, b2cPayout]) {
      const m = mock([]);
      const out = await fn({ ...stk, payload }, { fetch: m.fetch, env });
      assert.match(String(out.kind === "done" && out.error), /^INVALID_REQUEST/, JSON.stringify(payload));
      assert.equal(m.calls.length, 0);
    }
  }
});
test("Daraja: missing credentials fail closed before any call (nothing half-sent)", async () => {
  for (const name of ["MPESA_PASSKEY", "MPESA_CALLBACK_TOKEN", "MPESA_CONSUMER_SECRET"]) {
    const m = mock([]);
    await assert.rejects(stkPush(stk, { fetch: m.fetch, env: without(name) }), new RegExp(`${name} is not configured`));
    assert.equal(m.calls.length, 0);
  }
  const m = mock([]);
  await assert.rejects(b2cPayout(b2c, { fetch: m.fetch, env: without("MPESA_B2C_SECURITY_CREDENTIAL") }), /not configured/);
  assert.equal(m.calls.length, 0);
});
test("Daraja: an OAuth failure is a definite failure -- no money request was sent", async () => {
  const m = mock([{ status: 400, body: {} }]);
  await assert.rejects(stkPush(stk, { fetch: m.fetch, env }), /Daraja OAuth failed: HTTP 400/);
  assert.equal(m.calls.length, 1);
});
test("STK: a timeout after the request was sent is UNKNOWN, never a failure", async () => {
  const out = await stkPush(stk, { fetch: mock([darajaToken, timeout()]).fetch, env });
  assert.equal(out.kind, "unknown");
  assert.match(String(out.kind === "unknown" && out.error), /^OUTCOME_UNKNOWN: TimeoutError/);
});
test("B2C: accepted means the money moves on Safaricom's result (ack, not success)", async () => {
  const m = mock([darajaToken, { status: 200, body: { ResponseCode: "0", ConversationID: "AG_1", OriginatorConversationID: b2c.request_id } }]);
  const out = await b2cPayout(b2c, { fetch: m.fetch, env });
  const sent = JSON.parse(String(m.calls[1].init.body));
  assert.equal(sent.OriginatorConversationID, b2c.request_id);
  assert.equal(sent.ResultURL, `${secrets.MPESA_CALLBACK_BASE_URL}?kind=b2c-result&token=cb%20tok`);
  assert.equal(sent.QueueTimeOutURL, `${secrets.MPESA_CALLBACK_BASE_URL}?kind=b2c-timeout&token=cb%20tok`);
  assert.deepEqual(out, { kind: "accepted", providerReference: "AG_1", response: { ResponseCode: "0", ConversationID: "AG_1", OriginatorConversationID: b2c.request_id } });
});
test("B2C: a dropped connection after sending is UNKNOWN (a payout Safaricom accepted is never recorded failed)", async () => {
  const out = await b2cPayout(b2c, { fetch: mock([darajaToken, Object.assign(new Error("connection reset"), { name: "TypeError" })]).fetch, env });
  assert.equal(out.kind, "unknown");
});
test("nairobiTimestamp is East Africa Time", () => {
  assert.equal(nairobiTimestamp(Date.UTC(2026, 11, 31, 22, 0, 0)), "20270101010000");
});

// -------------------------------------------------------------- router
test("router: an operation the gateway does not know is refused explicitly", async () => {
  const out = await handle(job("FAX_SEND", {}), { fetch: mock([]).fetch, env });
  assert.deepEqual(out, { kind: "done", success: false, error: "OPERATION_NOT_SUPPORTED: FAX_SEND" });
});
test("router: push is refused with its reason; email and identity reach their adapters", async () => {
  const push = await handle(job("NOTIFY_PUSH", {}), { fetch: mock([]).fetch, env });
  assert.match(String(push.kind === "done" && push.error), /^PUSH_NOT_AVAILABLE/);
  const email = await handle(job("NOTIFY_EMAIL", { destination: "a@b.co.ke", subject: "s", body: "b" }), { fetch: mock([]).fetch, env });
  assert.match(String(email.kind === "done" && email.error), /GMAIL_SENDER is not configured/);
  await assert.rejects(handle(job("IDENTITY_VERIFY", { document_number: "1", first_name: "a", last_name: "b" }), { fetch: mock([]).fetch, env }), /METAMAP_SANDBOX_NOT_AVAILABLE/);
});
