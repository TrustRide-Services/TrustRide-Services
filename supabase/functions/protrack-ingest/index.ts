// Protrack telemetry intake (Engine 6 adapter boundary).
//
// PUSH mode -- Protrack (or any approved tracker) POSTs positions here with
//   Authorization: Bearer <TrustRide external-system key, scope TELEMETRY_INGEST>
//   body: an array of points, or {"data": [...]} / {"record": [...]}.
// POLL mode -- the database's telemetry poll job POSTs {"mode":"poll"} with the
//   gateway secret; this function asks the Protrack Open API for the latest
//   position of every device bound to a TrustRide vehicle.
//   Env: PROTRACK_API_BASE (default http://api.protrack365.com), PROTRACK_ACCOUNT,
//        PROTRACK_PASSWORD, PROTRACK_SYSTEM_KEY (the TrustRide key issued to Protrack),
//        TRUSTRIDE_GATEWAY_SECRET.
//
// Either way, points go to trustride.fn_integration_telemetry_ingest, which
// authenticates the system key and normalises; Protrack field names never
// travel past Engine 6. Deploy with --no-verify-jwt (the key is the auth).
// The logic lives in protrack.ts (tested under Node).

import { createClient } from "npm:@supabase/supabase-js@2";
import { crypto } from "jsr:@std/crypto@1";
import { encodeHex } from "jsr:@std/encoding@1/hex";
import { extractRecords, poll, toPoint, type Point } from "./protrack.ts";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  db: { schema: "trustride" },
  auth: { persistSession: false },
});

async function md5(s: string): Promise<string> {
  return encodeHex(await crypto.subtle.digest("MD5", new TextEncoder().encode(s)));
}

async function ingest(key: string, points: Point[]) {
  const { data, error } = await db.rpc("fn_integration_telemetry_ingest", { p_key: key, p_records: points });
  if (error) throw new Error(error.message);
  return data;
}

async function boundDevices(): Promise<string[]> {
  const { data, error } = await db.rpc("fn_resource_telemetry_bound_devices", { p_provider: "PROTRACK" });
  if (error) throw new Error(error.message);
  return (data as { provider_device_ref: string }[]).map((d) => d.provider_device_ref);
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const body = await request.json().catch(() => null);
  try {
    if (body?.mode === "poll") {
      const secret = Deno.env.get("TRUSTRIDE_GATEWAY_SECRET");
      if (!secret || request.headers.get("x-trustride-gateway-secret") !== secret) return new Response("Forbidden", { status: 403 });
      return Response.json(await poll({ fetch, env: (n) => Deno.env.get(n), md5, boundDevices, ingest }));
    }
    const key = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!key) return new Response("Unauthorized", { status: 401 });
    const records = extractRecords(body);
    if (!records) return new Response("Bad request: expected a list of points", { status: 400 });
    const result = await ingest(key, records.map(toPoint));
    if ((result as { outcome?: string })?.outcome === "UNAUTHENTICATED") return new Response("Unauthorized", { status: 401 });
    return Response.json(result);
  } catch (err) {
    console.error("telemetry", (err as Error).message);
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 502 });
  }
});
