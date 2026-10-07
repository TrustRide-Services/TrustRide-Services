// Safaricom Daraja result endpoints (Engine 6).
//
//   ?kind=stk          STK push callback  -> trustride.fn_integration_mpesa_callback_ingest
//   ?kind=b2c-result   B2C payout result  -> trustride.fn_integration_outbound_result (final)
//   ?kind=b2c-timeout  B2C queue timeout  -> trustride.fn_integration_outbound_result (failed)
//
// Safaricom calls these without our headers, so every URL carries a secret
// token (MPESA_CALLBACK_TOKEN). Deploy with --no-verify-jwt. Every call is
// answered {"ResultCode":0} once recorded, so Safaricom does not retry.

import { createClient } from "npm:@supabase/supabase-js@2";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  db: { schema: "trustride" },
  auth: { persistSession: false },
});

const accepted = () => new Response(JSON.stringify({ ResultCode: 0, ResultDesc: "Accepted" }), { headers: { "Content-Type": "application/json" } });

Deno.serve(async (request) => {
  const url = new URL(request.url);
  if (request.method !== "POST" || url.searchParams.get("token") !== Deno.env.get("MPESA_CALLBACK_TOKEN")) {
    return new Response("Forbidden", { status: 403 });
  }
  const body = await request.json().catch(() => null);
  if (!body) return new Response("Bad request", { status: 400 });
  const kind = url.searchParams.get("kind");

  if (kind === "stk") {
    const { error } = await db.rpc("fn_integration_mpesa_callback_ingest", { p_body: body });
    if (error) { console.error("stk callback", error.message); return new Response("Retry", { status: 500 }); }
    return accepted();
  }

  if (kind === "b2c-result" || kind === "b2c-timeout") {
    const result = body.Result ?? {};
    const requestId = result.OriginatorConversationID;
    const success = kind === "b2c-result" && Number(result.ResultCode) === 0;
    const { error } = await db.rpc("fn_integration_outbound_result", {
      p_request_id: requestId,
      p_success: success,
      p_provider_reference: result.TransactionID ?? result.ConversationID ?? null,
      p_response: body,
      p_error: success ? null : (kind === "b2c-timeout" ? "B2C_QUEUE_TIMEOUT" : `B2C_RESULT_${result.ResultCode}: ${result.ResultDesc ?? ""}`),
    });
    if (error) { console.error("b2c result", error.message); return new Response("Retry", { status: 500 }); }
    return accepted();
  }

  return new Response("Unknown callback kind", { status: 400 });
});
