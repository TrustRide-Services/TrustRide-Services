import { redirect } from "next/navigation";
import { gateContext, officeSub, project } from "@/lib/trustride";
import AutoRefresh from "@/components/AutoRefresh";
import { Badge, Card, Empty, ErrorNote, Page, Section, when } from "@/components/ui";

type Health = {
  health: { status: string; as_of: string | null; detail: { reasons?: string[] } };
  jobs: { jobname: string; schedule: string; active: boolean; last_run_at: string | null; last_status: string | null; last_message: string | null; failures_24h: number; runs_24h: number }[] | null;
  dead_letters: { source: string; target: string; reason: string; at: string; resolution: string | null }[];
  conformance: { check_code: string; object_name: string; detail: string }[];
  engines: { engine: string; score: number; status: string; at: string }[];
};

// Platform health (projection OFFICE_HEALTH): measured, not assumed --
// background jobs from pg_cron's own run log, handler failures from the
// dead-letter queue, and the permission conformance check.
export default async function OfficeHealth() {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  const { data: h, error } = await project<Health>(officeSub(ctx), "OFFICE_HEALTH");
  if (!h) return <Page title="Health"><ErrorNote error={error} /></Page>;
  return (
    <Page title="Platform health" intro={`As of ${when(h.health.as_of)}`} actions={<Badge status={h.health.status} />}>
      <AutoRefresh seconds={60} />
      {h.health.detail?.reasons?.length ? <Card tone="danger">{h.health.detail.reasons.map((r) => <p key={r} className="text-sm text-danger">{r.toLowerCase().replaceAll("_", " ")}</p>)}</Card> : null}
      <Section title="Permission conformance">
        {!h.conformance.length ? <Card><p className="text-sm text-success">No violations: every table has row security, every policy a grant, nothing open to the public.</p></Card> :
          h.conformance.map((v, i) => <Card key={i} tone="danger"><p className="text-sm">{v.check_code} · {v.object_name}</p><p className="text-xs text-text-muted">{v.detail}</p></Card>)}
      </Section>
      <Section title="Background jobs">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead><tr className="text-left text-text-muted text-xs"><th className="py-1 pr-3">Job</th><th className="pr-3">Every</th><th className="pr-3">Last run</th><th className="pr-3">Result</th><th className="pr-3 text-right">Runs 24 h</th><th className="text-right">Failed</th></tr></thead>
            <tbody>
              {(h.jobs ?? []).map((j) => (
                <tr key={j.jobname} className={`border-t border-border ${j.failures_24h > 0 || !j.active ? "text-danger" : "text-text-secondary"}`}>
                  <td className="py-1.5 pr-3 text-text-primary">{j.jobname}</td><td className="pr-3">{j.schedule}</td><td className="pr-3">{when(j.last_run_at)}</td>
                  <td className="pr-3" title={j.last_message ?? ""}>{j.active ? (j.last_status ?? "not yet run") : "paused"}</td>
                  <td className="pr-3 text-right tabular-nums">{j.runs_24h}</td><td className="text-right tabular-nums">{j.failures_24h}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Section>
      <Section title="Dead letters (handler failures)">
        {!h.dead_letters.length && <Empty>None — every signal was handled.</Empty>}
        {h.dead_letters.map((d, i) => (
          <Card key={i} tone={d.resolution ? undefined : "danger"}>
            <p className="text-sm text-text-primary">{d.source} → {d.target} <span className="text-text-muted text-xs">{when(d.at)}{d.resolution ? ` · ${d.resolution}` : " · unresolved"}</span></p>
            <p className="text-xs text-text-secondary break-words">{d.reason}</p>
          </Card>
        ))}
      </Section>
      <Section title="Engines">
        {!h.engines.length && <Empty>No engine measurements yet.</Empty>}
        <div className="grid sm:grid-cols-3 gap-2">
          {h.engines.map((e) => <Card key={e.engine} className="flex justify-between items-center"><span className="text-sm text-text-primary">{e.engine}</span><span className="flex gap-2 items-center text-xs"><Badge status={e.status} />{e.score}</span></Card>)}
        </div>
      </Section>
    </Page>
  );
}
