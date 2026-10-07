// TrustRide integration gateway (Engine 6 adapter boundary).
//
// The ONLY component that holds external-provider credentials. The database
// queues work in trustride.integration_outbound_request and posts it here
// (pg_net) with a shared secret; this function calls the provider and reports
// the outcome back through trustride.fn_integration_outbound_result (or
// fn_integration_gateway_ack for calls that finish later, e.g. Daraja B2C).
//
// Provider credentials live in this function's environment (Supabase secrets),
// never in the database:
//   TRUSTRIDE_GATEWAY_SECRET            shared with Vault 'trustride_integration_gateway_secret'
//   AT_USERNAME, AT_API_KEY, AT_SENDER_ID              Africa's Talking SMS
//   WHATSAPP_TOKEN, WHATSAPP_PHONE_NUMBER_ID, WHATSAPP_TEMPLATE_NAME (optional), WHATSAPP_TEMPLATE_LANG (default en)
//   MPESA_CONSUMER_KEY, MPESA_CONSUMER_SECRET, MPESA_SHORTCODE, MPESA_PASSKEY,
//   MPESA_TRANSACTION_TYPE (CustomerPayBillOnline | CustomerBuyGoodsOnline), MPESA_PARTY_B (till for BuyGoods),
//   MPESA_CALLBACK_BASE_URL (the mpesa-callback function URL), MPESA_CALLBACK_TOKEN,
//   MPESA_B2C_SHORTCODE, MPESA_B2C_INITIATOR_NAME, MPESA_B2C_SECURITY_CREDENTIAL
// SANDBOX adapters use the providers' sandbox hosts; PRODUCTION the live hosts.

import { createClient } from "npm:@supabase/supabase-js@2";

type OutboundRequest = {
  request_id: string;
  port_code: string;
  operation: "NOTIFY_SMS" | "NOTIFY_WHATSAPP" | "NOTIFY_EMAIL" | "NOTIFY_PUSH" | "STK_PUSH" | "B2C_PAYOUT";
  adapter_type: "SANDBOX" | "PRODUCTION" | "SIMULATOR";
  payload: Record<string, unknown>;
  attempt: number;
};

type Outcome =
  | { kind: "done"; success: boolean; providerReference?: string | null; response?: unknown; error?: string | null }
  | { kind: "accepted"; providerReference: string; response?: unknown };

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  db: { schema: "trustride" },
  auth: { persistSession: false },
});

function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`${name} is not configured`);
  return v;
}

// ------------------------------------------------------------------ SMS
async function sendSms(req: OutboundRequest): Promise<Outcome> {
  const host = req.adapter_type === "PRODUCTION" ? "https://api.africastalking.com" : "https://api.sandbox.africastalking.com";
  const form = new URLSearchParams({
    username: env("AT_USERNAME"),
    to: String(req.payload.destination),
    message: String(req.payload.body),
  });
  const sender = Deno.env.get("AT_SENDER_ID");
  if (sender) form.set("from", sender);
  const res = await fetch(`${host}/version1/messaging`, {
    method: "POST",
    headers: { apiKey: env("AT_API_KEY"), Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" },
    body: form,
  });
  const json = await res.json().catch(() => ({}));
  const recipient = json?.SMSMessageData?.Recipients?.[0];
  const ok = res.ok && recipient && ["Success", "Sent", "Queued"].includes(recipient.status);
  return { kind: "done", success: !!ok, providerReference: recipient?.messageId ?? null, response: json,
    error: ok ? null : recipient?.status ?? json?.SMSMessageData?.Message ?? `HTTP ${res.status}` };
}

// ------------------------------------------------------------- WhatsApp
async function sendWhatsapp(req: OutboundRequest): Promise<Outcome> {
  const to = String(req.payload.destination).replace(/^\+/, "");
  const template = Deno.env.get("WHATSAPP_TEMPLATE_NAME");
  const body = template
    ? { messaging_product: "whatsapp", to, type: "template", template: { name: template, language: { code: Deno.env.get("WHATSAPP_TEMPLATE_LANG") ?? "en" },
        components: [{ type: "body", parameters: [{ type: "text", text: String(req.payload.subject ?? "TrustRide") }, { type: "text", text: String(req.payload.body) }] }] } }
    : { messaging_product: "whatsapp", to, type: "text", text: { body: String(req.payload.body) } };
  const res = await fetch(`https://graph.facebook.com/v20.0/${env("WHATSAPP_PHONE_NUMBER_ID")}/messages`, {
    method: "POST",
    headers: { Authorization: `Bearer ${env("WHATSAPP_TOKEN")}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const json = await res.json().catch(() => ({}));
  return { kind: "done", success: res.ok, providerReference: json?.messages?.[0]?.id ?? null, response: json,
    error: res.ok ? null : json?.error?.message ?? `HTTP ${res.status}` };
}

// ---------------------------------------------------------------- Daraja
function darajaHost(adapter: string) {
  return adapter === "PRODUCTION" ? "https://api.safaricom.co.ke" : "https://sandbox.safaricom.co.ke";
}

async function darajaToken(adapter: string): Promise<string> {
  const basic = btoa(`${env("MPESA_CONSUMER_KEY")}:${env("MPESA_CONSUMER_SECRET")}`);
  const res = await fetch(`${darajaHost(adapter)}/oauth/v1/generate?grant_type=client_credentials`, { headers: { Authorization: `Basic ${basic}` } });
  const json = await res.json().catch(() => ({}));
  if (!res.ok || !json.access_token) throw new Error(`Daraja OAuth failed: HTTP ${res.status}`);
  return json.access_token;
}

function nairobiTimestamp(): string {
  // Daraja expects YYYYMMDDHHmmss in East Africa Time (UTC+3).
  const t = new Date(Date.now() + 3 * 3600 * 1000);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${t.getUTCFullYear()}${p(t.getUTCMonth() + 1)}${p(t.getUTCDate())}${p(t.getUTCHours())}${p(t.getUTCMinutes())}${p(t.getUTCSeconds())}`;
}

async function stkPush(req: OutboundRequest): Promise<Outcome> {
  const token = await darajaToken(req.adapter_type);
  const shortcode = env("MPESA_SHORTCODE");
  const timestamp = nairobiTimestamp();
  const type = Deno.env.get("MPESA_TRANSACTION_TYPE") ?? "CustomerPayBillOnline";
  const msisdn = String(req.payload.msisdn);
  const body = {
    BusinessShortCode: shortcode,
    Password: btoa(`${shortcode}${env("MPESA_PASSKEY")}${timestamp}`),
    Timestamp: timestamp,
    TransactionType: type,
    Amount: Number(req.payload.amount),
    PartyA: msisdn,
    PartyB: type === "CustomerBuyGoodsOnline" ? env("MPESA_PARTY_B") : shortcode,
    PhoneNumber: msisdn,
    CallBackURL: `${env("MPESA_CALLBACK_BASE_URL")}?kind=stk&token=${encodeURIComponent(env("MPESA_CALLBACK_TOKEN"))}`,
    AccountReference: String(req.payload.account_reference ?? "TrustRide").slice(0, 12),
    TransactionDesc: "TrustRide",
  };
  const res = await fetch(`${darajaHost(req.adapter_type)}/mpesa/stkpush/v1/processrequest`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const json = await res.json().catch(() => ({}));
  const ok = res.ok && String(json.ResponseCode) === "0" && json.CheckoutRequestID;
  // Success here means "the customer's phone is prompting"; the payment
  // itself is decided by Safaricom's callback.
  return { kind: "done", success: !!ok, providerReference: json.CheckoutRequestID ?? null, response: json,
    error: ok ? null : json.errorMessage ?? json.ResponseDescription ?? `HTTP ${res.status}` };
}

async function b2cPayout(req: OutboundRequest): Promise<Outcome> {
  const token = await darajaToken(req.adapter_type);
  const base = env("MPESA_CALLBACK_BASE_URL");
  const cbToken = encodeURIComponent(env("MPESA_CALLBACK_TOKEN"));
  const body = {
    OriginatorConversationID: req.request_id,
    InitiatorName: env("MPESA_B2C_INITIATOR_NAME"),
    SecurityCredential: env("MPESA_B2C_SECURITY_CREDENTIAL"),
    CommandID: "BusinessPayment",
    Amount: Number(req.payload.amount),
    PartyA: env("MPESA_B2C_SHORTCODE"),
    PartyB: String(req.payload.msisdn),
    Remarks: String(req.payload.remarks ?? "TrustRide payout").slice(0, 100),
    QueueTimeOutURL: `${base}?kind=b2c-timeout&token=${cbToken}`,
    ResultURL: `${base}?kind=b2c-result&token=${cbToken}`,
    Occasion: "TrustRide",
  };
  const res = await fetch(`${darajaHost(req.adapter_type)}/mpesa/b2c/v3/paymentrequest`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const json = await res.json().catch(() => ({}));
  if (res.ok && String(json.ResponseCode) === "0") {
    // Accepted: the money moves when Safaricom posts the result.
    return { kind: "accepted", providerReference: json.ConversationID ?? req.request_id, response: json };
  }
  return { kind: "done", success: false, response: json, error: json.errorMessage ?? json.ResponseDescription ?? `HTTP ${res.status}` };
}

// ---------------------------------------------------------------- router
async function handle(req: OutboundRequest): Promise<Outcome> {
  switch (req.operation) {
    case "NOTIFY_SMS": return sendSms(req);
    case "NOTIFY_WHATSAPP": return sendWhatsapp(req);
    case "STK_PUSH": return stkPush(req);
    case "B2C_PAYOUT": return b2cPayout(req);
    case "NOTIFY_EMAIL":
      return { kind: "done", success: false, error: "EMAIL_PROVIDER_NOT_SELECTED (Founder decision pending)" };
    case "NOTIFY_PUSH":
      return { kind: "done", success: false, error: "PUSH_NOT_AVAILABLE (no device tokens are registered on the web surfaces)" };
  }
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
  if (request.headers.get("x-trustride-gateway-secret") !== Deno.env.get("TRUSTRIDE_GATEWAY_SECRET")) {
    return new Response("Forbidden", { status: 403 });
  }
  const job = (await request.json()) as OutboundRequest;
  let outcome: Outcome;
  try {
    outcome = await handle(job);
  } catch (err) {
    outcome = { kind: "done", success: false, error: (err as Error).message };
  }
  const { error } = outcome.kind === "accepted"
    ? await db.rpc("fn_integration_gateway_ack", { p_request_id: job.request_id, p_provider_reference: outcome.providerReference, p_response: outcome.response ?? null })
    : await db.rpc("fn_integration_outbound_result", {
        p_request_id: job.request_id, p_success: outcome.success, p_provider_reference: outcome.providerReference ?? null,
        p_response: outcome.response ?? null, p_error: outcome.error ?? null,
      });
  if (error) {
    console.error("reporting outcome failed", job.request_id, error.message);
    return new Response(JSON.stringify({ reported: false, error: error.message }), { status: 500 });
  }
  return new Response(JSON.stringify({ reported: true, outcome: outcome.kind }), { headers: { "Content-Type": "application/json" } });
});
