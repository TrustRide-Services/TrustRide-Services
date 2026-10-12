// TrustRide integration gateway (Engine 6 adapter boundary).
//
// The ONLY component that holds external-provider credentials. The database
// queues work in trustride.integration_outbound_request and posts it here
// (pg_net) with a shared secret; this function calls the provider and reports
// the outcome back through trustride.fn_integration_outbound_result (or
// fn_integration_gateway_ack for calls that finish later, e.g. Daraja B2C).
// A money request whose fate is unknown is not reported at all: it stays SENT
// for Safaricom's callback or Engine 6's verification sweep (see providers.ts).
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
//   METAMAP_CLIENT_ID, METAMAP_CLIENT_SECRET, METAMAP_WEBHOOK_URL, METAMAP_WEBHOOK_TOKEN   MetaMap GovChecks (see metamap.ts)
//   GMAIL_AUTH_MODE, GMAIL_SENDER and the credentials of that mode                      Google email (see gmail.ts)
// SANDBOX adapters use the providers' sandbox hosts; PRODUCTION the live hosts.

import { createClient } from "npm:@supabase/supabase-js@2";
import { handle, type Deps, type Job, type Outcome } from "./router.ts";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  db: { schema: "trustride" },
  auth: { persistSession: false },
});

const deps: Deps = { fetch, env: (n) => Deno.env.get(n) };

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const secret = Deno.env.get("TRUSTRIDE_GATEWAY_SECRET");
  if (!secret || request.headers.get("x-trustride-gateway-secret") !== secret) {
    return new Response("Forbidden", { status: 403 });
  }
  const job = (await request.json().catch(() => null)) as Job | null;
  if (!job?.request_id || !job.operation) return new Response("Bad request", { status: 400 });
  let outcome: Outcome;
  try {
    outcome = await handle(job, deps);
  } catch (err) {
    // Thrown before anything left TrustRide (configuration, validation, OAuth): a definite failure.
    outcome = { kind: "done", success: false, error: (err as Error).message };
  }
  if (outcome.kind === "unknown") {
    console.error("money outcome unknown; left SENT for the callback or the verification sweep", job.request_id, outcome.error);
    return new Response(JSON.stringify({ reported: false, outcome: "unknown" }), { status: 202, headers: { "Content-Type": "application/json" } });
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
