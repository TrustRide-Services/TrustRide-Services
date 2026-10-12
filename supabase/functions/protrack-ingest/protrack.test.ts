// Hardening tests (no network) for Protrack telemetry: node --test supabase/functions/protrack-ingest/protrack.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { extractRecords, poll, toPoint, PROTRACK_DEFAULT_BASE, type Point } from "./protrack.ts";

const md5 = async (s: string) => createHash("md5").update(s).digest("hex");
type Call = string;
function mock(responses: Array<{ status: number; body: unknown } | Error>) {
  const calls: Call[] = [];
  const fetch = async (url: string, init: RequestInit = {}) => {
    calls.push(url);
    assert.ok(init.signal, "every Protrack call has a timeout");
    const next = responses.shift();
    if (!next) throw new Error("unexpected call " + url);
    if (next instanceof Error) throw next;
    return new Response(JSON.stringify(next.body), { status: next.status });
  };
  return { fetch, calls };
}
const secrets: Record<string, string> = { PROTRACK_ACCOUNT: "trustride ke", PROTRACK_PASSWORD: "pw", PROTRACK_SYSTEM_KEY: "sys-key" };

test("push: the accepted body shapes, and nothing else", () => {
  const p = { imei: "860000000000001", lat: -0.1, lng: 34.7 };
  assert.deepEqual(extractRecords([p]), [p]);
  assert.deepEqual(extractRecords({ data: [p] }), [p]);
  assert.deepEqual(extractRecords({ record: [p] }), [p]);
  for (const bad of [null, "text", 42, {}, { data: "x" }, { data: { imei: 1 } }, [1, 2], [null], [[p]]]) assert.equal(extractRecords(bad), null, JSON.stringify(bad));
});

test("push: Protrack field names are normalised to the canonical point", () => {
  assert.deepEqual(toPoint({ imei: "1", latitude: -0.09, lon: 34.76, gps_time: 1791900000, speed: 30, direction: 90, accstatus: 1 }),
    { imei: "1", lat: -0.09, lng: 34.76, gpstime: 1791900000, speed: 30, course: 90, acc: 1 });
});

test("poll: signed authorization, batched track calls, points ingested with the TrustRide system key", async () => {
  const imeis = Array.from({ length: 150 }, (_, i) => String(860000000000000 + i));
  const m = mock([{ status: 200, body: { code: 0, record: { access_token: "at/1" } } },
                  { status: 200, body: { code: 0, record: [{ imei: imeis[0], lat: -0.1, lng: 34.7, gpstime: 1 }] } },
                  { status: 200, body: { code: 0, record: [] } }]);
  const ingested: Array<[string, Point[]]> = [];
  const now = 1_791_900_000_000;
  const out = await poll({ fetch: m.fetch, env: (n) => secrets[n], md5, now: () => now, boundDevices: async () => imeis,
    ingest: async (k, pts) => { ingested.push([k, pts]); return { accepted: pts.length }; } });
  const time = now / 1000;
  assert.equal(m.calls[0], `${PROTRACK_DEFAULT_BASE}/api/authorization?time=${time}&account=trustride%20ke&signature=${await md5((await md5("pw")) + time)}`);
  assert.ok(m.calls[1].startsWith(`${PROTRACK_DEFAULT_BASE}/api/track?access_token=at%2F1&imeis=`));
  assert.equal(m.calls[1].split("imeis=")[1].split(",").length, 100);
  assert.equal(m.calls[2].split("imeis=")[1].split(",").length, 50);
  assert.equal(ingested[0][0], "sys-key");
  assert.deepEqual(out, { polled: 150, results: [{ accepted: 1 }, { accepted: 0 }] });
});

test("poll: missing credentials fail closed -- no call to Protrack", async () => {
  for (const name of ["PROTRACK_ACCOUNT", "PROTRACK_PASSWORD", "PROTRACK_SYSTEM_KEY"]) {
    const m = mock([]);
    await assert.rejects(poll({ fetch: m.fetch, env: (n) => (n === name ? undefined : secrets[n]), md5, boundDevices: async () => ["1"], ingest: async () => null }),
      new RegExp(`${name} is not configured`));
    assert.equal(m.calls.length, 0);
  }
});

test("poll: no bound devices means no Protrack call", async () => {
  const m = mock([]);
  assert.deepEqual(await poll({ fetch: m.fetch, env: (n) => secrets[n], md5, boundDevices: async () => [], ingest: async () => null }), { polled: 0 });
  assert.equal(m.calls.length, 0);
});

test("poll: refused authorization or track call is an error, nothing ingested", async () => {
  let ingested = 0;
  const deps = (r: Array<{ status: number; body: unknown }>) => ({ fetch: mock(r).fetch, env: (n: string) => secrets[n], md5,
    boundDevices: async () => ["1"], ingest: async () => { ingested++; return null; } });
  await assert.rejects(poll(deps([{ status: 200, body: { code: 10002, message: "signature error" } }])), /authorization failed: signature error/);
  await assert.rejects(poll(deps([{ status: 200, body: { code: 0, record: { access_token: "t" } } }, { status: 200, body: { code: 10010, message: "token expired" } }])), /track failed: token expired/);
  await assert.rejects(poll(deps([{ status: 502, body: "x" }])), /authorization failed/);
  assert.equal(ingested, 0);
});

test("poll: a configured HTTPS base is used", async () => {
  const m = mock([{ status: 200, body: { code: 0, record: { access_token: "t" } } }, { status: 200, body: { code: 0, record: [] } }]);
  await poll({ fetch: m.fetch, env: (n) => ({ ...secrets, PROTRACK_API_BASE: "https://api.protrack365.com/" } as Record<string, string>)[n], md5,
    boundDevices: async () => ["1"], ingest: async () => null });
  assert.ok(m.calls.every((c) => c.startsWith("https://api.protrack365.com/api/")));
});
