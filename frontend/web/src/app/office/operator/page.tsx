import Link from "next/link";
import { project } from "@/lib/trustride";
import CommandForm from "@/components/CommandForm";
import AutoRefresh from "@/components/AutoRefresh";
import { Badge, Card, Empty, ErrorNote, KV, Kes, Notice, Page, Section, when } from "@/components/ui";

type Job = { order_id: string; order_code: string; service_name: string; order_status: string; fare_confirmed: boolean; fare_kes: number | null;
  customer_first_name: string; current_status: string | null; requested_start_at: string | null; dispatch_mode: string;
  stops: { seq: number; from: string; to: string; status: string }[] };
type Home = {
  display_name: string; onboarding_pending: boolean;
  unit: { class: string; class_code: string; base: string; availability: string;
    vehicle: { label: string; plate: string; lifecycle: string; inspection: string; insurance: string; tracker: string | null } | null;
    capabilities: { type: string; expires_at: string | null }[] } | null;
  rating: { avg: number | null; count: number };
  active_jobs: Job[];
  recent_jobs: { order_code: string; completed_at: string; service: string }[];
};

// Operator App (projection OPERATOR_HOME) -- G3: go on and off duty, see
// your unit and vehicle, receive and work your jobs.
export default async function OperatorHome() {
  const { data, error } = await project<Home>("OPERATOR_APP", "OPERATOR_HOME");
  if (!data) return <Page title="Operator App"><ErrorNote error={error} /></Page>;
  const u = data.unit;
  const onDuty = u && ["AVAILABLE", "RESERVED", "ASSIGNED"].includes(u.availability);
  return (
    <Page title="Operator App" intro={`${data.display_name}${data.rating.count ? ` · ${data.rating.avg} ★ from ${data.rating.count} reviews` : ""}`}>
      <AutoRefresh seconds={10} />
      {data.onboarding_pending && <Notice>You are an approved TrustRide operator. TrustRide Office will form your working unit (class, base and vehicle) — you will be notified, then you can start your shift here.</Notice>}
      {u && (
        <Card tone={onDuty ? "gold" : undefined} className="flex flex-wrap justify-between items-center gap-4">
          <KV items={[["Unit", `${u.class} · ${u.base}`], ["State", <Badge key="a" status={u.availability} />],
            ...(u.vehicle ? [["Vehicle", `${u.vehicle.label} · ${u.vehicle.plate} · tracker ${u.vehicle.tracker?.toLowerCase().replace("_", " ") ?? "not fitted"}`] as [string, React.ReactNode]] : []),
            ["Credentials", u.capabilities.map((c) => c.type.toLowerCase().replaceAll("_", " ")).join(", ") || "—"]]} />
          {u.availability === "OFFLINE" && <CommandForm sub="OPERATOR_APP" command="SET_DUTY" fixed={{ on_duty: true }} submit="Start shift" success="You are on duty." />}
          {u.availability === "AVAILABLE" && <CommandForm sub="OPERATOR_APP" command="SET_DUTY" fixed={{ on_duty: false }} submit="End shift" variant="ghost" success="Shift ended." />}
          {u.availability === "MAINTENANCE" && <p className="text-sm text-gold-light">In maintenance — TrustRide Office returns you to service.</p>}
        </Card>
      )}
      <Section title={`My jobs · ${data.active_jobs.length}`}>
        {!data.active_jobs.length && <Empty>{onDuty ? "Waiting for a job. New jobs also arrive by SMS." : "Start your shift to receive jobs."}</Empty>}
        {data.active_jobs.map((j) => (
          <Link key={j.order_id} href={`/office/operator/${j.order_id}`}>
            <Card tone={j.current_status === "CREATED" && j.fare_confirmed ? "gold" : undefined} className="hover:border-gold-dim transition-colors">
              <div className="flex justify-between gap-2">
                <p className="text-text-primary font-semibold">{j.service_name} · {j.order_code}</p>
                <Badge status={j.current_status ?? j.order_status} />
              </div>
              <p className="text-text-secondary text-sm">{j.stops.map((s) => `${s.from} → ${s.to}`).join(" · ")}</p>
              <p className="text-text-muted text-xs">Customer {j.customer_first_name}{j.fare_kes ? <> · <Kes value={j.fare_kes} /></> : ""}
                {!j.fare_confirmed && " · waiting for the customer to confirm the fare"}{j.dispatch_mode === "SCHEDULED" && ` · starts ${when(j.requested_start_at)}`}</p>
            </Card>
          </Link>
        ))}
      </Section>
      <Section title="Recent jobs">
        {!data.recent_jobs.length && <Empty>None yet.</Empty>}
        {data.recent_jobs.map((r) => <p key={r.order_code} className="text-sm text-text-secondary">{r.order_code} · {r.service} · {when(r.completed_at)}</p>)}
      </Section>
    </Page>
  );
}
