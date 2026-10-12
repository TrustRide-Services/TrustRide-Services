// Africa's Talking SMS, WhatsApp Cloud API and Safaricom Daraja adapters (Engine 6).
// Moved out of index.ts unchanged in behaviour except for the hardening below, so
// they can be tested without a network (Construction Directive WP7, section 2.8):
//   * every provider call has a timeout (a hung provider never holds a request);
//   * configuration is checked before any call (fail closed, nothing half-sent);
//   * destinations and amounts are validated before money or messages move;
//   * a money request whose fate is unknown (the call to Safaricom failed after it
//     was sent: timeout, dropped connection) is reported as "unknown", never as a
//     failure: the request stays SENT, Safaricom's callback can still settle it,
//     and otherwise Engine 6's sweep closes it and asks the Office to verify on
//     the M-Pesa portal before any retry. Reporting it failed would lose a payout
//     Safaricom had accepted (its later result would be ignored as already final).

export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
export type Deps = { fetch: Fetch; env: (name: string) => string | undefined; now?: () => number; timeoutMs?: number };
export type Job = {
  request_id: string;
  operation: string;
  adapter_type: "SANDBOX" | "PRODUCTION" | "SIMULATOR";
  payload: Record<string, unknown>;
};
export type Outcome =
  | { kind: "done"; success: boolean; providerReference?: string | null; response?: unknown; error?: string | null }
  | { kind: "accepted"; providerReference: string; response?: unknown }
  | { kind: "unknown"; error: string };

// The money request has left TrustRide; if the call fails now, nobody knows whether Safaricom acted.
async function sentMoney(deps: Deps, url: string, init: RequestInit): Promise<Response | { kind: "unknown"; error: string }> {
  try {
    return await deps.fetch(url, { ...init, signal: signal(deps) });
  } catch (e) {
    return { kind: "unknown", error: `OUTCOME_UNKNOWN: ${(e as Error).name} after the request was sent to Safaricom` };
  }
}

const DEFAULT_TIMEOUT_MS = 20_000;
const signal = (deps: Deps) => AbortSignal.timeout(deps.timeoutMs ?? DEFAULT_TIMEOUT_MS);

function required(deps: Deps, name: string): string {
  const v = deps.env(name);
  if (!v) throw new Error(`${name} is not configured`);
  return v;
}

// Kenyan mobile numbers: +2547XXXXXXXX or +2541XXXXXXXX (E.164).
const KE_MOBILE_E164 = /^\+254[17]\d{8}$/;
// Daraja takes them without the plus.
const KE_MOBILE_DARAJA = /^254[17]\d{8}$/;

// ------------------------------------------------------------------ SMS
export async function sendSms(req: Job, deps: Deps): Promise<Outcome> {
  const to = String(req.payload.destination ?? "");
  if (!KE_MOBILE_E164.test(to)) return { kind: "done", success: false, error: "INVALID_REQUEST: destination is not a Kenyan mobile number in E.164" };
  const host = req.adapter_type === "PRODUCTION" ? "https://api.africastalking.com" : "https://api.sandbox.africastalking.com";
  const form = new URLSearchParams({ username: required(deps, "AT_USERNAME"), to, message: String(req.payload.body ?? "") });
  const apiKey = required(deps, "AT_API_KEY");
  const sender = deps.env("AT_SENDER_ID");
  if (sender) form.set("from", sender);
  const res = await deps.fetch(`${host}/version1/messaging`, {
    method: "POST",
    headers: { apiKey, Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" },
    body: form,
    signal: signal(deps),
  });
  const json = await res.json().catch(() => ({}));
  const recipient = json?.SMSMessageData?.Recipients?.[0];
  const ok = res.ok && recipient && ["Success", "Sent", "Queued"].includes(recipient.status);
  return { kind: "done", success: !!ok, providerReference: recipient?.messageId ?? null, response: json,
    error: ok ? null : recipient?.status ?? json?.SMSMessageData?.Message ?? `HTTP ${res.status}` };
}

// ------------------------------------------------------------- WhatsApp
export async function sendWhatsapp(req: Job, deps: Deps): Promise<Outcome> {
  const destination = String(req.payload.destination ?? "");
  if (!KE_MOBILE_E164.test(destination)) return { kind: "done", success: false, error: "INVALID_REQUEST: destination is not a Kenyan mobile number in E.164" };
  const to = destination.replace(/^\+/, "");
  const phoneNumberId = required(deps, "WHATSAPP_PHONE_NUMBER_ID");
  const bearer = required(deps, "WHATSAPP_TOKEN");
  const template = deps.env("WHATSAPP_TEMPLATE_NAME");
  const body = template
    ? { messaging_product: "whatsapp", to, type: "template", template: { name: template, language: { code: deps.env("WHATSAPP_TEMPLATE_LANG") ?? "en" },
        components: [{ type: "body", parameters: [{ type: "text", text: String(req.payload.subject ?? "TrustRide") }, { type: "text", text: String(req.payload.body) }] }] } }
    : { messaging_product: "whatsapp", to, type: "text", text: { body: String(req.payload.body) } };
  const res = await deps.fetch(`https://graph.facebook.com/v20.0/${phoneNumberId}/messages`, {
    method: "POST",
    headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: signal(deps),
  });
  const json = await res.json().catch(() => ({}));
  return { kind: "done", success: res.ok, providerReference: json?.messages?.[0]?.id ?? null, response: json,
    error: res.ok ? null : json?.error?.message ?? `HTTP ${res.status}` };
}

// ---------------------------------------------------------------- Daraja
export function darajaHost(adapter: string) {
  return adapter === "PRODUCTION" ? "https://api.safaricom.co.ke" : "https://sandbox.safaricom.co.ke";
}

async function darajaToken(adapter: string, deps: Deps): Promise<string> {
  const basic = btoa(`${required(deps, "MPESA_CONSUMER_KEY")}:${required(deps, "MPESA_CONSUMER_SECRET")}`);
  const res = await deps.fetch(`${darajaHost(adapter)}/oauth/v1/generate?grant_type=client_credentials`, { headers: { Authorization: `Basic ${basic}` }, signal: signal(deps) });
  const json = await res.json().catch(() => ({}));
  if (!res.ok || !json.access_token) throw new Error(`Daraja OAuth failed: HTTP ${res.status}`);
  return json.access_token;
}

export function nairobiTimestamp(nowMs: number): string {
  // Daraja expects YYYYMMDDHHmmss in East Africa Time (UTC+3).
  const t = new Date(nowMs + 3 * 3600 * 1000);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${t.getUTCFullYear()}${p(t.getUTCMonth() + 1)}${p(t.getUTCDate())}${p(t.getUTCHours())}${p(t.getUTCMinutes())}${p(t.getUTCSeconds())}`;
}

function moneyCheck(req: Job): string | null {
  const amount = req.payload.amount;   // Engine 6 sends a JSON number; anything else is malformed
  if (typeof amount !== "number" || !Number.isInteger(amount) || amount < 1) return "INVALID_REQUEST: Daraja amounts are whole shillings of at least 1";
  if (!KE_MOBILE_DARAJA.test(String(req.payload.msisdn ?? ""))) return "INVALID_REQUEST: msisdn is not a Kenyan mobile number (2547XXXXXXXX / 2541XXXXXXXX)";
  return null;
}

export async function stkPush(req: Job, deps: Deps): Promise<Outcome> {
  const invalid = moneyCheck(req);
  if (invalid) return { kind: "done", success: false, error: invalid };
  const shortcode = required(deps, "MPESA_SHORTCODE");
  const passkey = required(deps, "MPESA_PASSKEY");
  const type = deps.env("MPESA_TRANSACTION_TYPE") ?? "CustomerPayBillOnline";
  const partyB = type === "CustomerBuyGoodsOnline" ? required(deps, "MPESA_PARTY_B") : shortcode;
  const callback = `${required(deps, "MPESA_CALLBACK_BASE_URL")}?kind=stk&token=${encodeURIComponent(required(deps, "MPESA_CALLBACK_TOKEN"))}`;
  const token = await darajaToken(req.adapter_type, deps);
  const timestamp = nairobiTimestamp((deps.now ?? Date.now)());
  const msisdn = String(req.payload.msisdn);
  const body = {
    BusinessShortCode: shortcode,
    Password: btoa(`${shortcode}${passkey}${timestamp}`),
    Timestamp: timestamp,
    TransactionType: type,
    Amount: Number(req.payload.amount),
    PartyA: msisdn,
    PartyB: partyB,
    PhoneNumber: msisdn,
    CallBackURL: callback,
    AccountReference: String(req.payload.account_reference ?? "TrustRide").slice(0, 12),
    TransactionDesc: "TrustRide",
  };
  const res = await sentMoney(deps, `${darajaHost(req.adapter_type)}/mpesa/stkpush/v1/processrequest`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!(res instanceof Response)) return res;
  const json = await res.json().catch(() => ({}));
  const ok = res.ok && String(json.ResponseCode) === "0" && json.CheckoutRequestID;
  // Success here means "the customer's phone is prompting"; the payment
  // itself is decided by Safaricom's callback.
  return { kind: "done", success: !!ok, providerReference: json.CheckoutRequestID ?? null, response: json,
    error: ok ? null : json.errorMessage ?? json.ResponseDescription ?? `HTTP ${res.status}` };
}

export async function b2cPayout(req: Job, deps: Deps): Promise<Outcome> {
  const invalid = moneyCheck(req);
  if (invalid) return { kind: "done", success: false, error: invalid };
  const base = required(deps, "MPESA_CALLBACK_BASE_URL");
  const cbToken = encodeURIComponent(required(deps, "MPESA_CALLBACK_TOKEN"));
  const body = {
    OriginatorConversationID: req.request_id,
    InitiatorName: required(deps, "MPESA_B2C_INITIATOR_NAME"),
    SecurityCredential: required(deps, "MPESA_B2C_SECURITY_CREDENTIAL"),
    CommandID: "BusinessPayment",
    Amount: Number(req.payload.amount),
    PartyA: required(deps, "MPESA_B2C_SHORTCODE"),
    PartyB: String(req.payload.msisdn),
    Remarks: String(req.payload.remarks ?? "TrustRide payout").slice(0, 100),
    QueueTimeOutURL: `${base}?kind=b2c-timeout&token=${cbToken}`,
    ResultURL: `${base}?kind=b2c-result&token=${cbToken}`,
    Occasion: "TrustRide",
  };
  const token = await darajaToken(req.adapter_type, deps);
  const res = await sentMoney(deps, `${darajaHost(req.adapter_type)}/mpesa/b2c/v3/paymentrequest`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!(res instanceof Response)) return res;
  const json = await res.json().catch(() => ({}));
  if (res.ok && String(json.ResponseCode) === "0") {
    // Accepted: the money moves when Safaricom posts the result.
    return { kind: "accepted", providerReference: json.ConversationID ?? req.request_id, response: json };
  }
  return { kind: "done", success: false, response: json, error: json.errorMessage ?? json.ResponseDescription ?? `HTTP ${res.status}` };
}
