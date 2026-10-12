// MetaMap GovChecks adapter (Engine 6, IDENTITY_AUTHORITY port; Founder decision 2.6).
//
//   IDENTITY_VERIFY -> POST /govchecks/v1/ke/iprs  {documentNumber, firstName, lastName, callbackUrl?}
//   ENTITY_VERIFY   -> POST /govchecks/v1/ke/brs   {registrationNumber, callbackURL?}
//   OAuth           -> POST /oauth/ (Basic client_id:client_secret, grant_type=client_credentials; token ~1 h)
//
// The adapter only transports. It reports MetaMap's answer unchanged; Engine 6 in
// the database maps it (found / notFound / unavailable), keeps no shareholder
// identity numbers and lets Foundation's onboarding rules decide.
//
// Outcome contract with fn_integration_outbound_result:
//   success = true   a definitive answer: a record, or a govCheckError such as
//                    kenyanIprs.notFound / kenyanBrs.notFound;
//   success = false  retry later: timeout, network failure, HTTP 5xx, OAuth
//                    rejection, or MetaMap's systemError (e.g. *.serviceUnavailable).
//
// Secrets (Supabase Edge secrets, never the database):
//   METAMAP_CLIENT_ID, METAMAP_CLIENT_SECRET
//   METAMAP_WEBHOOK_URL (the metamap-webhook function URL), METAMAP_WEBHOOK_TOKEN (optional pair)
//   METAMAP_SANDBOX_API_BASE -- MetaMap documents no separate sandbox host, so a
//     SANDBOX adapter refuses to run unless MetaMap supplies one in writing.
//
// Written against MetaMap's published GovChecks documentation (Kenya IPRS and BRS).
// Not yet exercised against MetaMap: no account or credentials exist.

export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;

export type Deps = {
  fetch: Fetch;
  env: (name: string) => string | undefined;
  now?: () => number;
  timeoutMs?: number;
};

export type IdentityJob = {
  request_id: string;
  operation: "IDENTITY_VERIFY" | "ENTITY_VERIFY";
  adapter_type: "SANDBOX" | "PRODUCTION" | "SIMULATOR";
  payload: Record<string, unknown>;
};

export type Outcome = { kind: "done"; success: boolean; providerReference?: string | null; response?: unknown; error?: string | null };

export const METAMAP_PRODUCTION_BASE = "https://api.prod.metamap.com";
const DEFAULT_TIMEOUT_MS = 20_000;

let token: { value: string; expiresAt: number; base: string } | null = null;
export function resetTokenCache(): void { token = null; }

function required(deps: Deps, name: string): string {
  const v = deps.env(name);
  if (!v) throw new Error(`${name} is not configured`);
  return v;
}

export function metamapBase(job: IdentityJob, deps: Deps): string {
  if (job.adapter_type === "PRODUCTION") return METAMAP_PRODUCTION_BASE;
  if (job.adapter_type === "SANDBOX") {
    const sandbox = deps.env("METAMAP_SANDBOX_API_BASE");
    if (!sandbox) throw new Error("METAMAP_SANDBOX_NOT_AVAILABLE: MetaMap documents no sandbox host; set METAMAP_SANDBOX_API_BASE only from MetaMap's written instructions");
    return sandbox.replace(/\/+$/, "");
  }
  throw new Error("SIMULATOR jobs never reach the gateway");
}

async function accessToken(base: string, deps: Deps): Promise<string> {
  const now = (deps.now ?? Date.now)();
  if (token && token.base === base && token.expiresAt > now) return token.value;
  const basic = btoa(`${required(deps, "METAMAP_CLIENT_ID")}:${required(deps, "METAMAP_CLIENT_SECRET")}`);
  const res = await deps.fetch(`${base}/oauth/`, {
    method: "POST",
    headers: { Authorization: `Basic ${basic}`, "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" },
    body: "grant_type=client_credentials",
    signal: AbortSignal.timeout(deps.timeoutMs ?? DEFAULT_TIMEOUT_MS),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok || typeof json?.access_token !== "string") throw new Error(`METAMAP_AUTH_FAILED: HTTP ${res.status}`);
  const lifetimeSec = Number(json.expiresIn ?? json.expires_in ?? 3600);
  // Renew a minute early so a token never expires in flight.
  token = { value: json.access_token, base, expiresAt: now + Math.max(lifetimeSec - 60, 0) * 1000 };
  return token.value;
}

function callbackUrl(job: IdentityJob, deps: Deps): string | undefined {
  const url = deps.env("METAMAP_WEBHOOK_URL");
  const secret = deps.env("METAMAP_WEBHOOK_TOKEN");
  if (!url || !secret) return undefined;
  return `${url}?request_id=${encodeURIComponent(job.request_id)}&token=${encodeURIComponent(secret)}`;
}

export function requestBody(job: IdentityJob, deps: Deps): { path: string; body: Record<string, string> } {
  const p = job.payload;
  const cb = callbackUrl(job, deps);
  if (job.operation === "IDENTITY_VERIFY") {
    const documentNumber = String(p.document_number ?? "").trim();
    const firstName = String(p.first_name ?? "").trim();
    const lastName = String(p.last_name ?? "").trim();
    if (!documentNumber || !firstName || !lastName) throw new Error("INVALID_REQUEST: document_number, first_name and last_name are required");
    return { path: "/govchecks/v1/ke/iprs", body: { documentNumber, firstName, lastName, ...(cb ? { callbackUrl: cb } : {}) } };
  }
  const registrationNumber = String(p.registration_number ?? "").trim();
  if (!registrationNumber) throw new Error("INVALID_REQUEST: registration_number is required");
  return { path: "/govchecks/v1/ke/brs", body: { registrationNumber, ...(cb ? { callbackURL: cb } : {}) } };
}

export function classify(status: number, json: any): Outcome {
  const err = json?.error;
  const code = typeof err?.code === "string" ? err.code : "";
  if (status === 401 || status === 403) {
    resetTokenCache();
    return { kind: "done", success: false, response: json, error: `METAMAP_AUTH_REJECTED: HTTP ${status}` };
  }
  if (err?.type === "systemError" || /serviceUnavailable$/.test(code) || status >= 500) {
    return { kind: "done", success: false, response: json, error: `METAMAP_UNAVAILABLE: ${code || `HTTP ${status}`}` };
  }
  if (err && /\.notFound$/.test(code)) {
    return { kind: "done", success: true, providerReference: null, response: json, error: null };
  }
  if (status >= 200 && status < 300 && json?.data && typeof json.data === "object") {
    return { kind: "done", success: true, providerReference: null, response: json, error: null };
  }
  if (err?.type === "govCheckError") {
    // A definitive refusal other than not-found (e.g. invalid input): answered, not retried.
    return { kind: "done", success: true, providerReference: null, response: json, error: null };
  }
  return { kind: "done", success: false, response: json, error: `METAMAP_UNEXPECTED_ANSWER: HTTP ${status}` };
}

export async function metamapVerify(job: IdentityJob, deps: Deps): Promise<Outcome> {
  const base = metamapBase(job, deps);
  const { path, body } = requestBody(job, deps);
  let res: Response;
  try {
    const bearer = await accessToken(base, deps);
    res = await deps.fetch(`${base}${path}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(deps.timeoutMs ?? DEFAULT_TIMEOUT_MS),
    });
  } catch (e) {
    const err = e as Error;
    return { kind: "done", success: false, error: err.message.startsWith("METAMAP_") ? err.message : `METAMAP_UNREACHABLE: ${err.name}` };
  }
  const json = await res.json().catch(() => null);
  return classify(res.status, json);
}
