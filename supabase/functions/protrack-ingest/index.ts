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

import { createClient } from "npm:@supabase/supabase-js@2";
import { crypto } from "jsr:@std/crypto@1";
import { encodeHex } from "jsr:@std/encoding@1/hex";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  db: { schema: "trustride" },
  auth: { persistSession: false },
});

async function md5(s: string): Promise<string> {
  return encodeHex(await crypto.subtle.digest("MD5", new TextEncoder().encode(s)));
}

// Protrack Open API record -> the canonical point shape Engine 6 accepts.
function toPoint(r: Record<string, unknown>) {
  return {
    imei: r.imei,
    lat: r.lat ?? r.latitude,
    lng: r.lng ?? r.lon ?? r.longitude,
    gpstime: r.gpstime ?? r.gps_time ?? r.recorded_at,
    speed: r.speed,
    course: r.course ?? r.direction,
    acc: r.acc ?? r.accstatus,
  };
}

async function ingest(key: string, records: Record<string, unknown>[]) {
  const { data, error } = await db.rpc("fn_integration_telemetry_ingest", { p_key: key, p_records: records.map(toPoint) });
  if (error) throw new Error(error.message);
  return data;
}

async function poll(): Promise<unknown> {
  const base = Deno.env.get("PROTRACK_API_BASE") ?? "http://api.protrack365.com";
  const time = Math.floor(Date.now() / 1000);
  const signature = await md5((await md5(Deno.env.get("PROTRACK_PASSWORD")!)) + time);
  const auth = await fetch(`${base}/api/authorization?time=${time}&account=${encodeURIComponent(Deno.env.get("PROTRACK_ACCOUNT")!)}&signature=${signature}`)
    .then((r) => r.json());
  if (auth.code !== 0) throw new Error(`Protrack authorization failed: ${auth.message ?? auth.code}`);
  const { data: devices, error } = await db.rpc("fn_resource_telemetry_bound_devices", { p_provider: "PROTRACK" });
  if (error) throw new Error(error.message);
  const imeis = (devices as { provider_device_ref: string }[]).map((d) => d.provider_device_ref);
  if (imeis.length === 0) return { polled: 0 };
  const results = [];
  for (let i = 0; i < imeis.length; i += 100) {  // the track endpoint takes batches of IMEIs
    const track = await fetch(`${base}/api/track?access_token=${auth.record.access_token}&imeis=${imeis.slice(i, i + 100).join(",")}`).then((r) => r.json());
    if (track.code !== 0) throw new Error(`Protrack track failed: ${track.message ?? track.code}`);
    results.push(await ingest(Deno.env.get("PROTRACK_SYSTEM_KEY")!, track.record ?? []));
  }
  return { polled: imeis.length, results };
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const body = await request.json().catch(() => null);
  try {
    if (body?.mode === "poll") {
      if (request.headers.get("x-trustride-gateway-secret") !== Deno.env.get("TRUSTRIDE_GATEWAY_SECRET")) return new Response("Forbidden", { status: 403 });
      return Response.json(await poll());
    }
    const key = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!key) return new Response("Unauthorized", { status: 401 });
    const records = Array.isArray(body) ? body : (body?.data ?? body?.record ?? []);
    const result = await ingest(key, records);
    if ((result as { outcome?: string })?.outcome === "UNAUTHENTICATED") return new Response("Unauthorized", { status: 401 });
    return Response.json(result);
  } catch (err) {
    console.error("telemetry", (err as Error).message);
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 502 });
  }
});
