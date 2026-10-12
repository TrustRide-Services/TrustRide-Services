// Verifier: compares the database's audit chains with the seals retained in the
// object store. For each chain it recomputes every hash from the rows itself
// (sha256(prev | canonical row text)) from the chain's rebase point up to the
// newest externally sealed head, and checks that
//   * every link holds and every recomputed hash equals the stored hash,
//   * at every externally sealed position the hash equals the sealed head_hash,
//   * each seal's own hash equals the in-database seal row.
// A database rewrite after a seal was retained -- even one that recomputes all
// hashes and in-database seals consistently -- changes the hash at a sealed
// position and is reported as VERIFY_MISMATCH (Office alerted, exit code 1).
import { ListObjectsV2Command, GetObjectCommand } from "@aws-sdk/client-s3";
import { cfg, s3, rpc, sha256hex } from "./lib.mjs";

async function sealObjects(c, client) {
  const out = [];
  let token;
  do {
    const page = await client.send(new ListObjectsV2Command({ Bucket: c.bucket, Prefix: `${c.prefix}/${c.environment}/`, ContinuationToken: token }));
    for (const o of page.Contents ?? []) {
      const obj = await client.send(new GetObjectCommand({ Bucket: c.bucket, Key: o.Key, ChecksumMode: "ENABLED" }));
      const text = await obj.Body.transformToString("utf-8");
      const rec = JSON.parse(text);
      if (obj.Metadata?.["payload-sha256"] && obj.Metadata["payload-sha256"] !== sha256hex(text)) {
        throw new Error(`object ${o.Key} does not match its recorded payload hash`);
      }
      out.push({ key: o.Key, rec });
    }
    token = page.IsTruncated ? page.NextContinuationToken : undefined;
  } while (token);
  return out;
}

async function rows(c, chain, from, to) {
  const all = [];
  for (let a = from; a <= to; a += 5000) {
    all.push(...await rpc(c, "fn_platform_audit_chain_rows", { p_chain: chain, p_from: a, p_to: Math.min(a + 4999, to) }));
  }
  return all;
}

export async function verify(c = cfg()) {
  const client = s3(c);
  const objects = await sealObjects(c, client);
  const byChain = new Map();
  for (const o of objects) {
    if (o.rec.schema !== "trustride.audit-seal/v1" || o.rec.environment !== c.environment) continue;
    if (!byChain.has(o.rec.chain_table)) byChain.set(o.rec.chain_table, []);
    byChain.get(o.rec.chain_table).push(o);
  }
  const results = [];
  for (const [chain, seals] of byChain) {
    seals.sort((a, b) => a.rec.head_seq - b.rec.head_seq);
    const rebase = seals[0].rec.rebase_seq;
    const top = seals[seals.length - 1].rec.head_seq;
    const sealedAt = new Map(seals.map((s) => [s.rec.head_seq, s]));
    const problems = [];
    // Start from the legacy head (rebase point); rows after it carry the platform hash.
    let prev = null;
    if (rebase > 0) {
      const base = await rows(c, chain, rebase, rebase);
      prev = base[0]?.immutable_hash ?? null;
      if (!base.length) problems.push(`rebase row ${rebase} missing`);
      const s0 = sealedAt.get(rebase);
      if (s0 && s0.rec.head_hash !== prev) problems.push(`sealed head ${rebase} differs (no rows after rebase)`);
    }
    if (top > rebase) {
      let expectSeq = rebase + 1;
      for (const r of await rows(c, chain, rebase + 1, top)) {
        if (Number(r.chain_seq) !== expectSeq) { problems.push(`row ${expectSeq} missing`); break; }
        if ((r.prev_hash ?? null) !== prev) { problems.push(`link broken at ${expectSeq}`); break; }
        const h = sha256hex(`${prev ?? ""}|${r.canonical}`);
        if (h !== r.immutable_hash) { problems.push(`content altered at ${expectSeq}`); break; }
        const s = sealedAt.get(expectSeq);
        if (s && s.rec.head_hash !== h) { problems.push(`hash at sealed position ${expectSeq} differs from the external seal ${s.key}`); break; }
        prev = h; expectSeq++;
      }
      if (!problems.length && expectSeq <= top) problems.push(`rows ${expectSeq}..${top} missing`);
    }
    // Each seal row itself, against the seal chain in the database.
    for (const s of seals) {
      const sr = await rows(c, "platform_audit_chain_seal", s.rec.seal_chain_seq, s.rec.seal_chain_seq);
      if (!sr.length || sr[0].immutable_hash !== s.rec.seal_hash) problems.push(`in-database seal ${s.rec.seal_chain_seq} differs from ${s.key}`);
    }
    const latest = seals[seals.length - 1].rec;
    const ok = problems.length === 0;
    await rpc(c, "fn_platform_audit_seal_event_record", {
      p_event_type: ok ? "VERIFY_PASSED" : "VERIFY_MISMATCH", p_seal_id: latest.seal_id, p_destination: c.destination,
      p_detail: { chain, seals_checked: seals.length, head_seq: top, message: ok ? `verified to ${top}` : problems.join("; ") },
    });
    results.push({ chain, seals: seals.length, head_seq: top, ok, problems });
  }
  const failed = results.filter((r) => !r.ok).length;
  console.log(JSON.stringify({ chains: results.length, failed, results }));
  return { chains: results.length, failed, results };
}

if (process.argv[1]?.endsWith("verify.mjs")) {
  verify().then((r) => process.exit(r.failed ? 1 : 0), async (e) => {
    console.error(e.message);
    try { await rpc(cfg(), "fn_platform_audit_seal_event_record", { p_event_type: "VERIFY_ERROR", p_seal_id: null, p_destination: cfg().destination, p_detail: { message: String(e.message).slice(0, 300) } }); } catch {}
    process.exit(2);
  });
}
