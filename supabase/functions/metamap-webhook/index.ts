// MetaMap GovChecks callback endpoint (Engine 6, IDENTITY_AUTHORITY port).
//
//   POST ?request_id=<outbound request>&token=<METAMAP_WEBHOOK_TOKEN>
//     -> trustride.fn_integration_metamap_webhook_ingest(request_id, body)
//
// MetaMap publishes no signature scheme for GovChecks callbacks, so the URL the
// gateway hands MetaMap carries a secret token (as the Daraja callbacks do).
// Deploy with --no-verify-jwt. The callback is logged (without shareholder
// identity numbers) and applied at most once; a callback for an unknown or
// already-final request changes nothing. Any 2xx tells MetaMap not to retry;
// a 500 asks it to retry.

import { createClient } from "npm:@supabase/supabase-js@2";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  db: { schema: "trustride" },
  auth: { persistSession: false },
});

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (request) => {
  const url = new URL(request.url);
  const expected = Deno.env.get("METAMAP_WEBHOOK_TOKEN");
  if (request.method !== "POST" || !expected || url.searchParams.get("token") !== expected) {
    return new Response("Forbidden", { status: 403 });
  }
  const requestId = url.searchParams.get("request_id") ?? "";
  if (!UUID.test(requestId)) return new Response("Bad request", { status: 400 });
  const body = await request.json().catch(() => null);
  if (!body || typeof body !== "object") return new Response("Bad request", { status: 400 });

  const { data, error } = await db.rpc("fn_integration_metamap_webhook_ingest", { p_request_id: requestId, p_body: body });
  if (error) { console.error("metamap callback", requestId, error.message); return new Response("Retry", { status: 500 }); }
  return new Response(JSON.stringify({ received: true, result: data }), { headers: { "Content-Type": "application/json" } });
});
