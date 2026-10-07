import Link from "next/link";
import { redirect } from "next/navigation";
import { gateContext, officeAccess, project } from "@/lib/trustride";
import CommandForm from "@/components/CommandForm";
import { Badge, Card, Empty, ErrorNote, Kes, Page, Section, inputClass, when } from "@/components/ui";

type Kpis = { window_days: number; orders_placed: number; orders_completed: number; orders_cancelled: number; orders_expired_or_failed: number;
  completion_rate_pct: number | null; revenue_settled_kes: number; avg_fare_kes: number | null; by_family: Record<string, number> | null;
  units_on_duty_now: number; units_busy_now: number; marketplace_sales_kes: number; marketplace_commission_kes: number;
  rating_avg: number | null; support_open: number; support_sla_breached: number };
type Advisory = {
  recommendations: { recommendation_id: string; type: string; subject_engine: string; payload: Record<string, unknown>; confidence: number | null; generated_at: string; outcome: string | null }[];
  anomalies: { type: string; severity: string; source: string; description: string; detected_at: string }[];
};
type Scenarios = {
  scenarios: { code: string; name: string; type: string; description: string | null }[];
  runs: { run_id: string; scenario: string; label: string | null; status: string; failure_reason: string | null; completed_at: string | null;
    outcomes: Record<string, unknown>[] | null; insights: Record<string, unknown>[] | null }[];
};

// Executive Dashboard: KPIs (EXEC_KPIS), Advisory (EXEC_ADVISORY), scenario
// modelling (EXEC_SCENARIOS + RUN_SCENARIO). Figures are computed from the
// engines' own records for the chosen window -- none are typed in.
export default async function Executive({ searchParams }: { searchParams: Promise<{ days?: string }> }) {
  const days = Number((await searchParams).days ?? 30);
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  if (!officeAccess(ctx).executive) redirect("/office");
  const [k, a, s] = await Promise.all([
    project<Kpis>("EXECUTIVE_DASHBOARD", "EXEC_KPIS", { days }),
    project<Advisory>("EXECUTIVE_DASHBOARD", "EXEC_ADVISORY"),
    project<Scenarios>("EXECUTIVE_DASHBOARD", "EXEC_SCENARIOS"),
  ]);
  const t = (label: string, value: React.ReactNode) => <Card><p className="text-text-muted text-xs">{label}</p><p className="text-xl font-display text-text-primary tabular-nums">{value}</p></Card>;
  return (
    <Page title="Executive Dashboard" intro={`Last ${days} days`}
      actions={<div className="flex gap-2">{[7, 30, 90].map((d) => <Link key={d} href={`/office/executive?days=${d}`} className={`rounded-full border px-3 py-1 text-sm ${d === days ? "border-gold-dim bg-gold/10 text-text-primary" : "border-border text-text-secondary"}`}>{d} d</Link>)}</div>}>
      <ErrorNote error={k.error} />
      {k.data && (
        <>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            {t("Orders placed", k.data.orders_placed)}
            {t("Completed", `${k.data.orders_completed} (${k.data.completion_rate_pct ?? 0}%)`)}
            {t("Cancelled / expired / failed", `${k.data.orders_cancelled} / ${k.data.orders_expired_or_failed}`)}
            {t("Revenue settled", <Kes value={k.data.revenue_settled_kes} />)}
            {t("Average fare", k.data.avg_fare_kes != null ? <Kes value={k.data.avg_fare_kes} /> : "—")}
            {t("Units on duty / busy now", `${k.data.units_on_duty_now} / ${k.data.units_busy_now}`)}
            {t("Marketplace sales (commission)", <><Kes value={k.data.marketplace_sales_kes} /> <span className="text-sm text-text-muted">(<Kes value={k.data.marketplace_commission_kes} />)</span></>)}
            {t("Rating · support open · SLA breached", `${k.data.rating_avg ?? "—"} · ${k.data.support_open} · ${k.data.support_sla_breached}`)}
          </div>
          {k.data.by_family && <Card><p className="text-text-muted text-xs mb-1">Orders by service family</p>
            <p className="text-sm text-text-secondary">{Object.entries(k.data.by_family).map(([f, n]) => `${f.toLowerCase().replaceAll("_", " ")} ${n}`).join(" · ")}</p></Card>}
        </>
      )}

      <Section title="Advisory">
        <ErrorNote error={a.error} />
        {!a.data?.recommendations.length && !a.data?.anomalies.length && <Empty>No recommendations or anomalies.</Empty>}
        {a.data?.anomalies.map((x, i) => (
          <Card key={i} tone={["HIGH", "CRITICAL"].includes(x.severity) ? "danger" : undefined}>
            <p className="text-sm text-text-primary">{x.type.toLowerCase().replaceAll("_", " ")} <span className="text-text-muted text-xs">{x.source} · {when(x.detected_at)}</span></p>
            <p className="text-xs text-text-secondary">{x.description}</p>
          </Card>
        ))}
        {a.data?.recommendations.map((r) => (
          <Card key={r.recommendation_id}>
            <div className="flex justify-between gap-2"><span className="text-sm text-text-primary">{r.type.toLowerCase().replaceAll("_", " ")} <span className="text-text-muted text-xs">{r.subject_engine} · {when(r.generated_at)}{r.confidence != null ? ` · confidence ${r.confidence}` : ""}</span></span>
              {r.outcome && <Badge status={r.outcome} />}</div>
            <pre className="text-xs text-text-secondary whitespace-pre-wrap break-words">{JSON.stringify(r.payload, null, 1)}</pre>
          </Card>
        ))}
      </Section>

      <Section title="Scenario modelling">
        <ErrorNote error={s.error} />
        {s.data && (
          <Card>
            <CommandForm sub="EXECUTIVE_DASHBOARD" command="RUN_SCENARIO" submit="Run scenario" success="Run complete — see the result below." inline>
              <select name="scenario_code" className={`${inputClass} w-56`}>{s.data.scenarios.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select>
              <input name="run_label" placeholder="Label" className={`${inputClass} w-44`} />
            </CommandForm>
          </Card>
        )}
        {s.data?.runs.map((r) => (
          <Card key={r.run_id} tone={r.status === "FAILED" ? "danger" : undefined} className="flex flex-col gap-1">
            <div className="flex justify-between gap-2"><span className="text-sm text-text-primary">{r.scenario}{r.label ? ` · ${r.label}` : ""} <span className="text-text-muted text-xs">{when(r.completed_at)}</span></span><Badge status={r.status} /></div>
            {r.failure_reason && <p className="text-xs text-danger">{r.failure_reason}</p>}
            {(r.outcomes ?? []).map((o, i) => <pre key={`o${i}`} className="text-xs text-text-secondary whitespace-pre-wrap break-words">{JSON.stringify(o)}</pre>)}
            {(r.insights ?? []).map((o, i) => <pre key={`i${i}`} className="text-xs text-gold-light whitespace-pre-wrap break-words">{JSON.stringify(o)}</pre>)}
          </Card>
        ))}
      </Section>
    </Page>
  );
}
