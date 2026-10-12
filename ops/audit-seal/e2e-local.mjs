// End-to-end proof of the external audit seal, LOCAL STACK ONLY.
// Uses an independent S3-compatible store (MinIO, own container, credentials
// generated for this run and never printed) with Object Lock, the local
// Supabase stack, the real publisher and verifier. Writes results to
// e2e-local-result.json. Never point this at staging or production: it
// simulates an owner-level rewrite of an audit chain (and restores it).
import { execSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { CreateBucketCommand, DeleteObjectCommand, PutObjectCommand, PutObjectRetentionCommand, ListObjectVersionsCommand } from "@aws-sdk/client-s3";
import { s3, sha256b64 } from "./lib.mjs";

const DB = process.env.TRS_DB_CONTAINER || "supabase_db_TrustRide-Services";
const STORE = "trs-audit-seal-store";
const IMAGE = "bitnamilegacy/minio@sha256:451fe6858cb770cc9d0e77ba811ce287420f781c7c1b806a386f6896471a349c";
const PORT = 9100;
const results = [];
const step = (name, ok, detail = "") => { results.push({ name, ok, detail }); console.log(`${ok ? "PASS" : "FAIL"}  ${name}${detail ? "  — " + detail : ""}`); };
const sh = (cmd, input) => execSync(cmd, { input, env: { ...process.env, MSYS_NO_PATHCONV: "1" }, stdio: ["pipe", "pipe", "pipe"] }).toString().trim();
const sql = (q) => sh(`docker exec -i ${DB} psql -U supabase_admin -d postgres -X -A -t -q -v ON_ERROR_STOP=1`, q);

const env = Object.fromEntries(readFileSync(new URL("../../tests/e2e/local.env", import.meta.url), "utf8").trim().split(/\r?\n/)
  .map((l) => { const i = l.indexOf("="); return [l.slice(0, i), l.slice(i + 1).replace(/^"|"$/g, "")]; }));
if (!/^http:\/\/(127\.0\.0\.1|localhost)/.test(env.API_URL)) throw new Error("e2e-local refuses to run against a non-local stack");

const user = "seal" + randomBytes(4).toString("hex"), pass = randomBytes(24).toString("base64url");
process.env.AWS_ACCESS_KEY_ID = user; process.env.AWS_SECRET_ACCESS_KEY = pass; process.env.AWS_REGION = "us-east-1";
const base = {
  supabaseUrl: env.API_URL, serviceKey: env.SERVICE_ROLE_KEY, environment: "local-e2e", destination: "S3_COMPATIBLE_TEST",
  bucket: "trustride-audit-seals-e2e", prefix: "trustride/audit-seals", lockMode: "COMPLIANCE", retainDays: 1,
  region: "us-east-1", endpoint: `http://127.0.0.1:${PORT}`,
};
const { publish } = await import("./publish.mjs");
const { verify } = await import("./verify.mjs");

try { sh(`docker rm -f ${STORE}`); } catch {}
sh(`docker run -d --name ${STORE} -p ${PORT}:9000 -e MINIO_ROOT_USER=${user} -e MINIO_ROOT_PASSWORD=${pass} ${IMAGE}`);
const client = s3(base);
for (let i = 0; ; i++) {
  try { await client.send(new CreateBucketCommand({ Bucket: base.bucket, ObjectLockEnabledForBucket: true })); break; }
  catch (e) { if (i > 40) throw e; await new Promise((r) => setTimeout(r, 1500)); }
}
step("independent store up (MinIO, own credentials), Object Lock bucket created", true, base.bucket);

try {
  // 1. A verified chain produces a seal; the publisher retains it externally.
  sql(`SELECT trustride.fn_model_decision_log_write(NULL, 'E2E_SEAL_' || g, 'external seal e2e') FROM generate_series(1,3) g; SELECT trustride.fn_platform_audit_chain_seal();`);
  const p1 = await publish(base);
  const receipts = Number(sql(`SELECT count(*) FROM trustride.platform_audit_seal_receipt WHERE destination = 'S3_COMPATIBLE_TEST'`));
  step("seals published under COMPLIANCE retention and receipted only after the store confirmed", p1.failed === 0 && p1.published > 0 && receipts >= p1.published, JSON.stringify(p1) + ` receipts=${receipts}`);

  // 2. The verifier agrees with the database.
  const v1 = await verify(base);
  step("verifier recomputes every chain and matches every external seal", v1.failed === 0 && v1.chains > 0, `${v1.chains} chains`);

  // 3. Retained evidence cannot be changed during retention.
  const versions = await client.send(new ListObjectVersionsCommand({ Bucket: base.bucket, Prefix: base.prefix }));
  const one = versions.Versions[0];
  let refusedDelete = false, refusedShorten = false, refusedOverwrite = false;
  try { await client.send(new DeleteObjectCommand({ Bucket: base.bucket, Key: one.Key, VersionId: one.VersionId })); } catch { refusedDelete = true; }
  try { await client.send(new PutObjectRetentionCommand({ Bucket: base.bucket, Key: one.Key, VersionId: one.VersionId, Retention: { Mode: "COMPLIANCE", RetainUntilDate: new Date(Date.now() + 60_000) } })); } catch { refusedShorten = true; }
  try { await client.send(new PutObjectCommand({ Bucket: base.bucket, Key: one.Key, Body: "{}", IfNoneMatch: "*", ChecksumSHA256: sha256b64("{}") })); } catch { refusedOverwrite = true; }
  step("a retained seal version cannot be deleted", refusedDelete);
  step("its retention cannot be shortened (COMPLIANCE)", refusedShorten);
  step("a seal object cannot be replaced (conditional write)", refusedOverwrite);

  // 4. A failed external write is reported, never recorded as success.
  sql(`SELECT trustride.fn_model_decision_log_write(NULL, 'E2E_SEAL_FAIL', 'external seal e2e'); SELECT trustride.fn_platform_audit_chain_seal();`);
  const before = Number(sql(`SELECT count(*) FROM trustride.platform_audit_seal_receipt`));
  const p2 = await publish({ ...base, bucket: "no-such-bucket-e2e" });
  const after = Number(sql(`SELECT count(*) FROM trustride.platform_audit_seal_receipt`));
  const failEvents = Number(sql(`SELECT count(*) FROM trustride.platform_audit_seal_event WHERE event_type = 'PUBLISH_FAILED' AND recorded_at > now() - interval '5 minutes'`));
  const alert = Number(sql(`SELECT count(*) FROM trustride.present_notification_inbox WHERE title ILIKE 'Audit seal: publish failed%' AND critical`));
  step("a failed write records no receipt, records the failure and alerts the Office", p2.failed > 0 && after === before && failEvents >= p2.failed && alert > 0,
    `failed=${p2.failed} receipts ${before}->${after} events=${failEvents} alerts=${alert}`);
  const p3 = await publish(base);
  step("the retry to the real store succeeds", p3.failed === 0 && p3.published > 0, JSON.stringify(p3));

  // 5. Owner-level rewrite after sealing: change a sealed row and recompute every hash,
  //    the head and the in-database seals so the database's own check stays clean.
  const k = Number(sql(`SELECT min(chain_seq) FROM trustride.model_decision_log WHERE event_type LIKE 'E2E_SEAL_%'`));
  sql(`DROP TABLE IF EXISTS public.trs_e2e_backup_rows, public.trs_e2e_backup_seals, public.trs_e2e_backup_heads;
       CREATE TABLE public.trs_e2e_backup_rows AS SELECT * FROM trustride.model_decision_log WHERE chain_seq >= ${k};
       CREATE TABLE public.trs_e2e_backup_seals AS SELECT * FROM trustride.platform_audit_chain_seal;
       CREATE TABLE public.trs_e2e_backup_heads AS SELECT * FROM trustride.platform_audit_chain;`);
  sql(`SET timezone = 'UTC';
DO $rw$
DECLARE r RECORD; prev CHAR(64); s RECORD; sprev CHAR(64); first_seal BIGINT;
BEGIN
  ALTER TABLE trustride.model_decision_log DISABLE TRIGGER USER;
  ALTER TABLE trustride.platform_audit_chain_seal DISABLE TRIGGER USER;
  UPDATE trustride.model_decision_log SET event_description = event_description || ' [REWRITTEN BY OWNER]' WHERE chain_seq = ${k};
  SELECT immutable_hash INTO prev FROM trustride.model_decision_log WHERE chain_seq = ${k} - 1;
  FOR r IN SELECT chain_seq FROM trustride.model_decision_log WHERE chain_seq >= ${k} ORDER BY chain_seq LOOP
    UPDATE trustride.model_decision_log t SET prev_hash = prev, immutable_hash = trustride.fn_platform_audit_chain_hash(prev, to_jsonb(t))
    WHERE t.chain_seq = r.chain_seq RETURNING t.immutable_hash INTO prev;
  END LOOP;
  UPDATE trustride.platform_audit_chain SET head_hash = prev WHERE chain_table = 'model_decision_log';
  UPDATE trustride.platform_audit_chain_seal x SET head_hash = (SELECT immutable_hash FROM trustride.model_decision_log WHERE chain_seq = x.head_seq)
  WHERE x.chain_table = 'model_decision_log' AND x.head_seq >= ${k};
  SELECT min(chain_seq) INTO first_seal FROM trustride.platform_audit_chain_seal WHERE chain_table = 'model_decision_log' AND head_seq >= ${k};
  SELECT immutable_hash INTO sprev FROM trustride.platform_audit_chain_seal WHERE chain_seq = first_seal - 1;
  FOR s IN SELECT chain_seq FROM trustride.platform_audit_chain_seal WHERE chain_seq >= first_seal ORDER BY chain_seq LOOP
    UPDATE trustride.platform_audit_chain_seal t SET prev_hash = sprev, immutable_hash = trustride.fn_platform_audit_chain_hash(sprev, to_jsonb(t))
    WHERE t.chain_seq = s.chain_seq RETURNING t.immutable_hash INTO sprev;
  END LOOP;
  UPDATE trustride.platform_audit_chain SET head_hash = sprev WHERE chain_table = 'platform_audit_chain_seal';
  ALTER TABLE trustride.model_decision_log ENABLE TRIGGER USER;
  ALTER TABLE trustride.platform_audit_chain_seal ENABLE TRIGGER USER;
END
$rw$;`);
  const internal = sql(`SELECT count(*) FILTER (WHERE first_break_seq IS NOT NULL) FROM trustride.fn_platform_audit_chain_verify(TRUE)`);
  step("simulation: after a consistent owner-level rewrite the database's own verification finds nothing", internal === "0", `${internal} broken chains in-database`);
  const v2 = await verify(base);
  const bad = v2.results.find((r) => r.chain === "model_decision_log");
  step("the external seal detects the rewrite (VERIFY_MISMATCH, Office alerted)", !!bad && !bad.ok
    && Number(sql(`SELECT count(*) FROM trustride.platform_audit_seal_event WHERE event_type = 'VERIFY_MISMATCH' AND recorded_at > now() - interval '5 minutes'`)) > 0,
    bad ? bad.problems.join("; ") : "chain not checked");

  // Restore the original rows, seals and heads exactly.
  sql(`DO $rs$ BEGIN
  ALTER TABLE trustride.model_decision_log DISABLE TRIGGER USER;
  ALTER TABLE trustride.platform_audit_chain_seal DISABLE TRIGGER USER;
  UPDATE trustride.model_decision_log t SET event_description = b.event_description, prev_hash = b.prev_hash, immutable_hash = b.immutable_hash
    FROM public.trs_e2e_backup_rows b WHERE b.chain_seq = t.chain_seq;
  UPDATE trustride.platform_audit_chain_seal t SET head_hash = b.head_hash, prev_hash = b.prev_hash, immutable_hash = b.immutable_hash
    FROM public.trs_e2e_backup_seals b WHERE b.seal_id = t.seal_id;
  UPDATE trustride.platform_audit_chain t SET head_hash = b.head_hash, head_seq = b.head_seq FROM public.trs_e2e_backup_heads b WHERE b.chain_table = t.chain_table;
  ALTER TABLE trustride.model_decision_log ENABLE TRIGGER USER;
  ALTER TABLE trustride.platform_audit_chain_seal ENABLE TRIGGER USER;
END $rs$;
DROP TABLE public.trs_e2e_backup_rows, public.trs_e2e_backup_seals, public.trs_e2e_backup_heads;`);
  const v3 = await verify(base);
  step("after restoring the original rows the external verification passes again", v3.failed === 0, `${v3.chains} chains`);
} finally {
  writeFileSync(new URL("./e2e-local-result.json", import.meta.url), JSON.stringify({ at: new Date().toISOString(), image: IMAGE, results }, null, 1));
  try { sh(`docker rm -f ${STORE}`); } catch {}
}
const failed = results.filter((r) => !r.ok).length;
console.log(`\n${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
