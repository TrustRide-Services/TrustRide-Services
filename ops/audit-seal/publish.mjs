// Publisher: copies every daily audit seal not yet retained at the destination
// into the object store under Object Lock, confirms the store retained it, and
// only then records a receipt in TrustRide. A failure is reported to TrustRide
// (which alerts the Office) and makes the process exit non-zero; it is never
// recorded as a success.
import { PutObjectCommand, HeadObjectCommand, GetObjectRetentionCommand } from "@aws-sdk/client-s3";
import { cfg, s3, rpc, sha256hex, sha256b64, objectKey } from "./lib.mjs";

export async function publish(c = cfg()) {
  const client = s3(c);
  const pending = await rpc(c, "fn_platform_audit_seal_export", { p_destination: c.destination, p_environment: c.environment, p_limit: 500 });
  let published = 0, failed = 0;
  for (const rec of pending) {
    const key = objectKey(c, rec);
    const retainUntil = new Date(Date.now() + c.retainDays * 86_400_000);
    try {
      if (sha256hex(rec.payload_text) !== rec.payload_sha256) throw new Error("exported payload hash does not match its text");
      const put = await client.send(new PutObjectCommand({
        Bucket: c.bucket, Key: key, Body: rec.payload_text, ContentType: "application/json",
        ChecksumSHA256: sha256b64(rec.payload_text),
        ObjectLockMode: c.lockMode, ObjectLockRetainUntilDate: retainUntil,
        IfNoneMatch: "*",                                  // never replace an existing seal object
        Metadata: { "seal-id": rec.seal_id, "payload-sha256": rec.payload_sha256 },
      }));
      // Confirm what the store actually holds before claiming retention.
      const head = await client.send(new HeadObjectCommand({ Bucket: c.bucket, Key: key, VersionId: put.VersionId }));
      const ret = await client.send(new GetObjectRetentionCommand({ Bucket: c.bucket, Key: key, VersionId: put.VersionId }));
      if (head.Metadata?.["payload-sha256"] !== rec.payload_sha256) throw new Error("stored object metadata does not match the seal");
      if (!ret.Retention || ret.Retention.Mode !== c.lockMode || new Date(ret.Retention.RetainUntilDate) <= new Date()) {
        throw new Error(`store did not confirm ${c.lockMode} retention`);
      }
      await rpc(c, "fn_platform_audit_seal_receipt_record", {
        p_seal_id: rec.seal_id, p_destination: c.destination, p_environment: c.environment, p_bucket: c.bucket, p_object_key: key,
        p_version_id: put.VersionId ?? null, p_etag: put.ETag ?? null, p_lock_mode: ret.Retention.Mode,
        p_retain_until: new Date(ret.Retention.RetainUntilDate).toISOString(), p_payload_sha256: rec.payload_sha256,
      });
      published++;
    } catch (err) {
      failed++;
      const message = `${err.name ?? "Error"}: ${String(err.message).slice(0, 300)}`;
      await rpc(c, "fn_platform_audit_seal_event_record", {
        p_event_type: "PUBLISH_FAILED", p_seal_id: rec.seal_id, p_destination: c.destination,
        p_detail: { message, object_key: key },
      }).catch((e) => console.error("could not report the failure to TrustRide:", e.message));
      console.error(`seal ${rec.seal_id} (${rec.chain_table}): ${message}`);
    }
  }
  console.log(JSON.stringify({ pending: pending.length, published, failed }));
  return { pending: pending.length, published, failed };
}

if (import.meta.url === `file://${process.argv[1].replace(/\\/g, "/")}` || process.argv[1]?.endsWith("publish.mjs")) {
  publish().then((r) => process.exit(r.failed ? 1 : 0), (e) => { console.error(e.message); process.exit(2); });
}
