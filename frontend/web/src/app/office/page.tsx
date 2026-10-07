import { redirect } from "next/navigation";
import { gateContext, officeAccess, officeSub, project } from "@/lib/trustride";
import AutoRefresh from "@/components/AutoRefresh";
import { Badge, Card, Empty, ErrorNote, Page, Section, when } from "@/components/ui";

type Overview = {
  health: { status: string; as_of: string | null; detail: { reasons?: string[] } };
  orders: Record<string, number> | null; waiting_orders: number; pending_requests: number; escalated_requests: number;
  units: Record<string, number> | null; open_cases: Record<string, number> | null; failed_payments: number; stale_trackers: number;
  alerts: { title: string; body: string; category: string; at: string; critical: boolean }[];
};

// TrustRide Office overview (projection OFFICE_OVERVIEW).
export default async function OfficeHome() {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  const o = officeAccess(ctx);
  if (!o.admin && !o.executive) redirect("/office/operator");
  const { data, error } = await project<Overview>(officeSub(ctx), "OFFICE_OVERVIEW");
  const tile = (label: string, value: number | string | undefined, warn = false) => (
    <Card tone={warn ? "gold" : undefined}><p className="text-text-muted text-xs">{label}</p><p className="text-2xl font-display text-text-primary">{value ?? 0}</p></Card>
  );
  return (
    <Page title={o.admin ? "Admin Console" : "Executive Dashboard"} intro="Live operations across every engine.">
      <AutoRefresh seconds={20} />
      <ErrorNote error={error} />
      {data && (
        <>
          <Card tone={data.health.status === "HEALTHY" ? undefined : "danger"} className="flex flex-wrap items-center gap-3">
            <Badge status={data.health.status} /> <span className="text-sm text-text-secondary">Platform health as of {when(data.health.as_of)}</span>
            {data.health.detail?.reasons?.map((r) => <span key={r} className="text-xs text-danger">{r.toLowerCase().replaceAll("_", " ")}</span>)}
          </Card>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            {tile("Orders waiting for a worker", data.waiting_orders, data.waiting_orders > 0)}
            {tile("Requests awaiting decision", data.pending_requests, data.escalated_requests > 0)}
            {tile("Failed payments", data.failed_payments, data.failed_payments > 0)}
            {tile("Silent trackers", data.stale_trackers, data.stale_trackers > 0)}
          </div>
          <div className="grid md:grid-cols-3 gap-3">
            <Card><p className="text-text-muted text-xs mb-2">Orders by status</p>
              {Object.entries(data.orders ?? {}).map(([k, v]) => <p key={k} className="text-sm flex justify-between"><Badge status={k} /> <span>{v}</span></p>)}</Card>
            <Card><p className="text-text-muted text-xs mb-2">Working units</p>
              {Object.entries(data.units ?? {}).map(([k, v]) => <p key={k} className="text-sm flex justify-between"><Badge status={k} /> <span>{v}</span></p>)}
              {!data.units && <Empty>No units formed yet.</Empty>}</Card>
            <Card><p className="text-text-muted text-xs mb-2">Open support cases</p>
              {Object.entries(data.open_cases ?? {}).map(([k, v]) => <p key={k} className="text-sm flex justify-between"><Badge status={k} /> <span>{v}</span></p>)}
              {!data.open_cases && <Empty>None.</Empty>}</Card>
          </div>
          <Section title="Alerts for you">
            {!data.alerts.length && <Empty>No alerts.</Empty>}
            {data.alerts.map((a, i) => (
              <Card key={i} tone={a.critical ? "danger" : undefined}>
                <div className="flex justify-between gap-2"><span className="text-text-primary text-sm font-semibold">{a.title}</span><span className="text-text-muted text-xs">{when(a.at)}</span></div>
                <p className="text-text-secondary text-sm">{a.body}</p>
              </Card>
            ))}
          </Section>
        </>
      )}
    </Page>
  );
}
