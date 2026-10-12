// Protrack telemetry logic (Engine 6), free of Deno globals so it can be tested under Node.
// Hardening (Construction Directive WP7, section 2.8):
//   * POLL fails closed: no Protrack call is made unless account, password and system key are configured;
//   * every Protrack call has a timeout;
//   * a PUSH body that is not a list of points is refused (400), never ingested half-read.
// Note: Protrack's published Open API base is plain http://api.protrack365.com, so the access
// token travels unencrypted in the query string. PROTRACK_API_BASE switches to HTTPS as soon as
// Protrack confirms it is served there (open item on the integration register).

export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
export type PollDeps = {
  fetch: Fetch;
  env: (name: string) => string | undefined;
  md5: (s: string) => Promise<string>;
  boundDevices: () => Promise<string[]>;
  ingest: (key: string, points: Point[]) => Promise<unknown>;
  now?: () => number;
  timeoutMs?: number;
};
export type Point = { imei: unknown; lat: unknown; lng: unknown; gpstime: unknown; speed: unknown; course: unknown; acc: unknown };

export const PROTRACK_DEFAULT_BASE = "http://api.protrack365.com";
const DEFAULT_TIMEOUT_MS = 20_000;

// Protrack Open API record -> the canonical point shape Engine 6 accepts.
export function toPoint(r: Record<string, unknown>): Point {
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

// A push body: an array of points, or {"data": [...]} / {"record": [...]}. Anything else is refused.
export function extractRecords(body: unknown): Record<string, unknown>[] | null {
  const list = Array.isArray(body) ? body : (body as { data?: unknown; record?: unknown } | null)?.data ?? (body as { record?: unknown } | null)?.record;
  if (!Array.isArray(list)) return null;
  if (!list.every((r) => r !== null && typeof r === "object" && !Array.isArray(r))) return null;
  return list as Record<string, unknown>[];
}

function required(deps: PollDeps, name: string): string {
  const v = deps.env(name);
  if (!v) throw new Error(`${name} is not configured`);
  return v;
}

async function getJson(deps: PollDeps, url: string): Promise<any> {
  const res = await deps.fetch(url, { signal: AbortSignal.timeout(deps.timeoutMs ?? DEFAULT_TIMEOUT_MS) });
  return res.json().catch(() => ({ code: `HTTP ${res.status}` }));
}

export async function poll(deps: PollDeps): Promise<{ polled: number; results?: unknown[] }> {
  const account = required(deps, "PROTRACK_ACCOUNT");
  const password = required(deps, "PROTRACK_PASSWORD");
  const systemKey = required(deps, "PROTRACK_SYSTEM_KEY");
  const base = (deps.env("PROTRACK_API_BASE") ?? PROTRACK_DEFAULT_BASE).replace(/\/+$/, "");
  const imeis = await deps.boundDevices();
  if (imeis.length === 0) return { polled: 0 };
  const time = Math.floor((deps.now ?? Date.now)() / 1000);
  const signature = await deps.md5((await deps.md5(password)) + time);
  const auth = await getJson(deps, `${base}/api/authorization?time=${time}&account=${encodeURIComponent(account)}&signature=${signature}`);
  if (auth?.code !== 0 || !auth?.record?.access_token) throw new Error(`Protrack authorization failed: ${auth?.message ?? auth?.code}`);
  const results = [];
  for (let i = 0; i < imeis.length; i += 100) {  // the track endpoint takes batches of IMEIs
    const batch = imeis.slice(i, i + 100).map(encodeURIComponent).join(",");
    const track = await getJson(deps, `${base}/api/track?access_token=${encodeURIComponent(auth.record.access_token)}&imeis=${batch}`);
    if (track?.code !== 0) throw new Error(`Protrack track failed: ${track?.message ?? track?.code}`);
    const records = Array.isArray(track.record) ? track.record : [];
    results.push(await deps.ingest(systemKey, records.map(toPoint)));
  }
  return { polled: imeis.length, results };
}
