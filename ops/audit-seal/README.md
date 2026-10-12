# External audit seals (S3 Object Lock)

TrustRide seals the verified head of every audit chain daily inside the database
(`trustride_audit_chain_seal`, 00:15 UTC; migration 029). The database owner can
rewrite a chain together with its in-database seals, so each seal is also kept
**outside** the database, in an object store whose retention nobody can shorten:
Amazon S3 with Object Lock in COMPLIANCE mode (Founder-approved, Construction
Directive §2.9).

```
Supabase (TrustRide)                         Separate administrative domain (AWS)
  platform_audit_chain_seal ──export──▶ publish.mjs ──PutObject + Object Lock──▶ S3 bucket
  platform_audit_seal_receipt ◀─receipt── (only after HEAD + GetObjectRetention confirm)
  platform_audit_seal_event   ◀─results── verify.mjs ◀──GetObject── S3 bucket
  fn_platform_audit_seal_watch (hourly): missing receipt / overdue verification → Office alert
```

## Why the publisher runs outside Supabase

Supabase Edge Function secrets are administered by the same project owner the seal
guards against. The AWS credentials therefore live only in the AWS account (Lambda or
EventBridge Scheduler, or a GitHub Actions job whose secrets Supabase administrators
cannot read). The database holds no credential that can write, delete or shorten
anything in the bucket.

## Files

| File | Purpose |
|---|---|
| `lib.mjs` | Configuration from the environment, S3 client, PostgREST RPC, hashing |
| `publish.mjs` | Exports pending seals; writes each with `IfNoneMatch: *`, SHA-256 checksum and COMPLIANCE retention; confirms with HEAD and GetObjectRetention; only then calls `fn_platform_audit_seal_receipt_record`. On failure it calls `fn_platform_audit_seal_event_record('PUBLISH_FAILED')`, which raises a critical Office alert, and exits 1 |
| `verify.mjs` | Recomputes every chain from its rows (`fn_platform_audit_chain_rows`: `sha256(prev ‖ '\|' ‖ canonical)`) up to the newest external seal; checks every sealed position and every in-database seal row against the bucket; records `VERIFY_PASSED` or `VERIFY_MISMATCH` (critical Office alert); exits 1 on a mismatch |
| `e2e-local.mjs` | Local proof against an independent S3-compatible store (MinIO with Object Lock, own container and credentials). Refuses to run against a non-local stack |

## Environment

| Variable | Meaning |
|---|---|
| `TRS_SUPABASE_URL`, `TRS_SERVICE_ROLE_KEY` | TrustRide project URL and service-role key (stored in the AWS domain) |
| `TRS_SEAL_ENVIRONMENT` | `staging` or `production`; part of every record and object key |
| `TRS_SEAL_DESTINATION` | `AWS_S3_OBJECT_LOCK` (default), or `S3_COMPATIBLE_TEST` for local proofs |
| `TRS_SEAL_BUCKET`, `TRS_SEAL_PREFIX` | Bucket and key prefix (default `trustride/audit-seals`) |
| `TRS_SEAL_LOCK_MODE`, `TRS_SEAL_RETAIN_DAYS` | `COMPLIANCE` and `2555` (7 years) — **proposal, awaiting Founder approval** |
| `AWS_REGION` and the AWS credential chain | Normal AWS SDK resolution (prefer an IAM role, not keys) |

Object key: `<prefix>/<environment>/<chain_table>/<seal_chain_seq, 12 digits>-<seal_id>.json`.
Record schema `trustride.audit-seal/v1`: seal id and position, sealed time, chain, head
sequence and hash, rows verified, verified flag, break position and kind, rebase point,
legacy row count, and the seal row's own previous and current hash (prior-seal linkage).

## Activation (not yet done — needs an AWS account)

1. **AWS account.** Use an account owned by TrustRide, separate from anyone who
   administers Supabase. Enable MFA on the root user.
2. **Bucket.** Create the bucket in `eu-central-1` (next to staging) with **Object Lock
   enabled at creation**. That also turns on versioning. Block all public access and
   use default encryption (SSE-S3 or SSE-KMS). Optionally set a default retention of
   COMPLIANCE for 2,555 days, matching the publisher.
3. **IAM role for the publisher and verifier**, with least privilege:
   ```json
   { "Version": "2012-10-17", "Statement": [
     { "Effect": "Allow", "Action": ["s3:PutObject", "s3:PutObjectRetention", "s3:GetObject", "s3:GetObjectVersion",
                                      "s3:GetObjectRetention", "s3:ListBucket", "s3:ListBucketVersions"],
       "Resource": ["arn:aws:s3:::<bucket>", "arn:aws:s3:::<bucket>/trustride/audit-seals/*"] },
     { "Effect": "Deny", "Action": ["s3:DeleteObject", "s3:DeleteObjectVersion", "s3:BypassGovernanceRetention",
                                     "s3:PutBucketObjectLockConfiguration", "s3:PutLifecycleConfiguration"],
       "Resource": ["arn:aws:s3:::<bucket>", "arn:aws:s3:::<bucket>/*"] } ] }
   ```
4. **Schedule.** Run `publish.mjs` daily at 00:45 UTC, after the 00:15 seal, and
   `verify.mjs` daily at 01:15 UTC. Use EventBridge Scheduler with Lambda, or GitHub
   Actions with OIDC into the role. Alert on any non-zero exit.
5. **Prove it.** Run publish and verify once against the real bucket. Confirm a
   `VERIFY_PASSED` event and a receipt with `destination = AWS_S3_OBJECT_LOCK`.
6. **Activate the watchdog** only after step 5 succeeds, by inserting a new
   `platform_configuration` row
   `AUDIT_SEAL_EXTERNAL_DESTINATION = AWS_S3_OBJECT_LOCK`. Until then the watchdog
   stays silent and claims nothing.

## Proven so far (local, 2026-10-12)

`e2e-local.mjs` against MinIO 2025-05-24 (Object Lock, COMPLIANCE) passed 11 of 11:

- seals were published and receipted only after the store confirmed retention;
- the verifier matched all 8 chains;
- deleting, shortening retention on, or replacing a retained seal was refused;
- a failed write was reported and alerted, never receipted, and its retry succeeded;
- a consistent owner-level rewrite went unnoticed by the in-database check but was detected by the external seal;
- after the rewrite was restored, verification passed again.

The AWS destination itself is **not activated**: no AWS account or credentials exist yet.

## Limits

- If **both** the Supabase domain and the AWS domain are compromised, an attacker can rewrite
  the database and, once retention allows, the evidence. COMPLIANCE retention cannot be
  shortened, even by the AWS root user.
- The publisher holds a service-role key. Hardening item: replace it with a dedicated database
  role that may execute only the four seal functions.
- The verifier reads canonical row text through the database API. A compromised database that
  answers the API with the original content while serving altered data elsewhere is outside
  what this check can see. Mitigation: run the verifier against a read replica or a restored
  backup as well.
- A rewrite is detectable only for rows covered by a retained seal, which means anything older
  than the last successful daily publication.
