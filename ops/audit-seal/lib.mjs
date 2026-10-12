// Shared by the publisher and the verifier. Configuration comes only from the
// environment of the machine that runs them (an AWS Lambda / GitHub Actions job
// in a separate administrative domain from Supabase). Nothing here is logged
// that could carry a secret.
import { createHash } from "node:crypto";
import { S3Client } from "@aws-sdk/client-s3";

export function need(name) {
  const v = process.env[name];
  if (!v) throw new Error(`missing environment variable ${name}`);
  return v;
}

export const cfg = () => ({
  supabaseUrl: need("TRS_SUPABASE_URL"),
  serviceKey: need("TRS_SERVICE_ROLE_KEY"),
  environment: need("TRS_SEAL_ENVIRONMENT"),            // e.g. staging, production
  destination: process.env.TRS_SEAL_DESTINATION || "AWS_S3_OBJECT_LOCK", // or S3_COMPATIBLE_TEST
  bucket: need("TRS_SEAL_BUCKET"),
  prefix: process.env.TRS_SEAL_PREFIX || "trustride/audit-seals",
  lockMode: process.env.TRS_SEAL_LOCK_MODE || "COMPLIANCE",
  retainDays: Number(process.env.TRS_SEAL_RETAIN_DAYS || "2555"), // 7 years (proposal; Founder approves)
  region: process.env.AWS_REGION || "eu-central-1",
  endpoint: process.env.TRS_S3_ENDPOINT || undefined,             // set only for an S3-compatible test store
});

export function s3(c) {
  return new S3Client({ region: c.region, endpoint: c.endpoint, forcePathStyle: !!c.endpoint });
}

export const sha256hex = (s) => createHash("sha256").update(Buffer.from(s, "utf8")).digest("hex");
export const sha256b64 = (s) => createHash("sha256").update(Buffer.from(s, "utf8")).digest("base64");

// PostgREST RPC on the trustride schema with the service role.
export async function rpc(c, fn, args) {
  const res = await fetch(`${c.supabaseUrl}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { apikey: c.serviceKey, Authorization: `Bearer ${c.serviceKey}`, "Content-Type": "application/json", "Content-Profile": "trustride" },
    body: JSON.stringify(args),
    signal: AbortSignal.timeout(30_000),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${fn}: HTTP ${res.status} ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : null;
}

export const objectKey = (c, rec) =>
  `${c.prefix}/${c.environment}/${rec.chain_table}/${String(rec.seal_chain_seq).padStart(12, "0")}-${rec.seal_id}.json`;
