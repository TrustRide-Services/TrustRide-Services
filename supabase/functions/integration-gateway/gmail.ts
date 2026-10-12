// Google email adapter (Engine 6, EMAIL_SERVICE port, NOTIFY_EMAIL; Founder decision 2.8: Google email).
//
//   send  -> POST https://gmail.googleapis.com/gmail/v1/users/me/messages/send  {raw: base64url(RFC 5322 message)}
//   token -> POST https://oauth2.googleapis.com/token, scope https://www.googleapis.com/auth/gmail.send
//
// Two ways Google lets a server send as a mailbox; which applies depends on the account:
//   GMAIL_AUTH_MODE=SERVICE_ACCOUNT   Google Workspace mailbox, service account with domain-wide delegation:
//                                     GMAIL_SERVICE_ACCOUNT_JSON (client_email, private_key), GMAIL_SENDER
//   GMAIL_AUTH_MODE=REFRESH_TOKEN     any Google mailbox (including @gmail.com), OAuth client with offline consent:
//                                     GMAIL_CLIENT_ID, GMAIL_CLIENT_SECRET, GMAIL_REFRESH_TOKEN, GMAIL_SENDER
// Optional: GMAIL_SENDER_NAME (default TrustRide).
//
// Gmail has no sandbox. A SANDBOX adapter delivers every message to GMAIL_SANDBOX_RECIPIENT (a TrustRide
// test inbox) and refuses to run without it, so a sandbox can never mail a real person.
//
// Outcome contract with fn_integration_outbound_result: success only when Gmail returns a message id;
// every failure is reported as a failure (Engine 6 retries, then records it failed).

export type Fetch = (url: string, init?: RequestInit) => Promise<Response>;
export type Deps = { fetch: Fetch; env: (name: string) => string | undefined; now?: () => number; timeoutMs?: number };
export type EmailJob = {
  request_id: string;
  operation: "NOTIFY_EMAIL";
  adapter_type: "SANDBOX" | "PRODUCTION" | "SIMULATOR";
  payload: Record<string, unknown>;
};
export type Outcome = { kind: "done"; success: boolean; providerReference?: string | null; response?: unknown; error?: string | null };

export const GMAIL_SEND_URL = "https://gmail.googleapis.com/gmail/v1/users/me/messages/send";
export const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
export const GMAIL_SEND_SCOPE = "https://www.googleapis.com/auth/gmail.send";
const DEFAULT_TIMEOUT_MS = 20_000;

let token: { value: string; expiresAt: number; key: string } | null = null;
export function resetTokenCache(): void { token = null; }

function required(deps: Deps, name: string): string {
  const v = deps.env(name);
  if (!v) throw new Error(`${name} is not configured`);
  return v;
}

// ------------------------------------------------------------- encoding
function bytesToBase64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}
const utf8 = (s: string) => new TextEncoder().encode(s);
export const base64url = (bytes: Uint8Array) => bytesToBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

// RFC 2047 encoded-word for non-ASCII header text.
function headerText(s: string): string {
  return /^[\x20-\x7E]*$/.test(s) ? s : `=?UTF-8?B?${bytesToBase64(utf8(s))}?=`;
}

const EMAIL = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/;

export function buildMessage(from: string, fromName: string, to: string, subject: string, body: string, messageId: string): string {
  for (const [name, value] of [["recipient", to], ["sender", from], ["subject", subject], ["sender name", fromName]]) {
    if (/[\r\n]/.test(value)) throw new Error(`INVALID_REQUEST: the ${name} contains a line break`);   // header injection
  }
  if (!EMAIL.test(to)) throw new Error("INVALID_REQUEST: the recipient is not an email address");
  if (!EMAIL.test(from)) throw new Error("GMAIL_SENDER is not an email address");
  const encodedBody = bytesToBase64(utf8(body)).replace(/.{1,76}/g, "$&\r\n");
  return [
    `From: ${headerText(fromName)} <${from}>`,
    `To: <${to}>`,
    `Subject: ${headerText(subject)}`,
    `Message-ID: <${messageId}@trustride.ke>`,
    "MIME-Version: 1.0",
    "Content-Type: text/plain; charset=UTF-8",
    "Content-Transfer-Encoding: base64",
    "",
    encodedBody,
  ].join("\r\n");
}

// --------------------------------------------------------------- tokens
function pemToPkcs8(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)).buffer;
}

export async function serviceAccountAssertion(clientEmail: string, privateKeyPem: string, subject: string, nowMs: number): Promise<string> {
  const iat = Math.floor(nowMs / 1000);
  const header = base64url(utf8(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = base64url(utf8(JSON.stringify({ iss: clientEmail, sub: subject, scope: GMAIL_SEND_SCOPE, aud: GOOGLE_TOKEN_URL, iat, exp: iat + 3600 })));
  const key = await crypto.subtle.importKey("pkcs8", pemToPkcs8(privateKeyPem), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, utf8(`${header}.${claims}`)));
  return `${header}.${claims}.${base64url(signature)}`;
}

async function accessToken(deps: Deps, sender: string): Promise<string> {
  const now = (deps.now ?? Date.now)();
  const mode = deps.env("GMAIL_AUTH_MODE");
  let form: URLSearchParams;
  if (mode === "SERVICE_ACCOUNT") {
    let sa: { client_email?: string; private_key?: string };
    try { sa = JSON.parse(required(deps, "GMAIL_SERVICE_ACCOUNT_JSON")); } catch (e) {
      throw new Error((e as Error).message.includes("not configured") ? (e as Error).message : "GMAIL_SERVICE_ACCOUNT_JSON is not valid JSON");
    }
    if (!sa.client_email || !sa.private_key) throw new Error("GMAIL_SERVICE_ACCOUNT_JSON lacks client_email or private_key");
    const key = `sa:${sa.client_email}:${sender}`;
    if (token && token.key === key && token.expiresAt > now) return token.value;
    form = new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: await serviceAccountAssertion(sa.client_email, sa.private_key, sender, now) });
    return exchange(deps, form, key, now);
  }
  if (mode === "REFRESH_TOKEN") {
    const clientId = required(deps, "GMAIL_CLIENT_ID");
    const key = `rt:${clientId}:${sender}`;
    if (token && token.key === key && token.expiresAt > now) return token.value;
    form = new URLSearchParams({ grant_type: "refresh_token", client_id: clientId,
      client_secret: required(deps, "GMAIL_CLIENT_SECRET"), refresh_token: required(deps, "GMAIL_REFRESH_TOKEN") });
    return exchange(deps, form, key, now);
  }
  throw new Error("GMAIL_AUTH_MODE is not configured (SERVICE_ACCOUNT or REFRESH_TOKEN)");
}

async function exchange(deps: Deps, form: URLSearchParams, key: string, now: number): Promise<string> {
  const res = await deps.fetch(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" },
    body: form.toString(),
    signal: AbortSignal.timeout(deps.timeoutMs ?? DEFAULT_TIMEOUT_MS),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok || typeof json?.access_token !== "string") {
    // e.g. invalid_grant: a revoked or expired refresh token, or delegation not granted
    throw new Error(`GMAIL_AUTH_FAILED: ${json?.error ?? `HTTP ${res.status}`}`);
  }
  token = { value: json.access_token, key, expiresAt: now + Math.max(Number(json.expires_in ?? 3600) - 60, 0) * 1000 };
  return token.value;
}

// ----------------------------------------------------------------- send
export async function sendEmail(job: EmailJob, deps: Deps): Promise<Outcome> {
  if (job.adapter_type === "SIMULATOR") throw new Error("SIMULATOR jobs never reach the gateway");
  try {
    const sender = required(deps, "GMAIL_SENDER");
    const to = job.adapter_type === "SANDBOX"
      ? (deps.env("GMAIL_SANDBOX_RECIPIENT") ?? (() => { throw new Error("GMAIL_SANDBOX_RECIPIENT is not configured (Gmail has no sandbox; a sandbox must never mail a real person)"); })())
      : String(job.payload.destination ?? "").trim();
    const raw = buildMessage(sender, deps.env("GMAIL_SENDER_NAME") ?? "TrustRide", to,
      String(job.payload.subject ?? "TrustRide"), String(job.payload.body ?? ""), job.request_id);
    const bearer = await accessToken(deps, sender);
    const res = await deps.fetch(GMAIL_SEND_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ raw: base64url(utf8(raw)) }),
      signal: AbortSignal.timeout(deps.timeoutMs ?? DEFAULT_TIMEOUT_MS),
    });
    const json = await res.json().catch(() => null);
    if (res.ok && typeof json?.id === "string") {
      return { kind: "done", success: true, providerReference: json.id, response: { id: json.id, threadId: json.threadId ?? null }, error: null };
    }
    if (res.status === 401) resetTokenCache();
    return { kind: "done", success: false, response: json, error: `GMAIL_SEND_FAILED: HTTP ${res.status}${json?.error?.status ? ` ${json.error.status}` : ""}` };
  } catch (e) {
    const err = e as Error;
    return { kind: "done", success: false, error: err.name === "TimeoutError" || err.name === "TypeError" ? `GMAIL_UNREACHABLE: ${err.name}` : err.message };
  }
}
