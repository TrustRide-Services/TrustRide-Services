import Link from "next/link";
import { project } from "@/lib/trustride";
import CommandForm from "@/components/CommandForm";
import AutoRefresh from "@/components/AutoRefresh";
import LocationShare from "./LocationShare";
import { Badge, Card, ErrorNote, KV, Kes, Notice, Page, Section, inputClass, labelClass } from "@/components/ui";

type Job = { order_id: string; order_code: string; service_name: string; order_status: string; fare_confirmed: boolean; fare_kes: number | null;
  customer_first_name: string; current_job_id: string | null; current_status: string | null; can_decline: boolean;
  stops: { job_id: string; seq: number; status: string; from: string; to: string; distance_km: string | null; billed_hours: string | null; description: string }[] };

const NEXT: Record<string, string> = {
  CREATED: "Accept job", ACKNOWLEDGED: "Set off (dispatched)", DISPATCHED: "I'm on the way", EN_ROUTE: "I've arrived",
  ARRIVED: "Start service", EXECUTING: "Complete this stop", COMPLETED: "Verify and close",
};

// One job (projection OPERATOR_JOB): the operator moves it step by step --
// accepted, dispatched, en route, arrived, executing, completed, verified --
// shares location while travelling, and reports problems.
export default async function OperatorJob({ params }: { params: Promise<{ orderId: string }> }) {
  const { orderId } = await params;
  const { data: j, error } = await project<Job>("OPERATOR_APP", "OPERATOR_JOB", { order_id: orderId });
  if (!j) return <Page title="Job"><ErrorNote error={error} /><Link href="/office/operator" className="text-gold-light text-sm">Back</Link></Page>;
  const s = j.current_status;
  const travelling = s && ["DISPATCHED", "EN_ROUTE", "ARRIVED", "EXECUTING"].includes(s);
  return (
    <Page title={`${j.service_name} · ${j.order_code}`} intro={`Customer ${j.customer_first_name}`} actions={<Badge status={s ?? j.order_status} />}>
      <AutoRefresh seconds={10} />
      {!j.fare_confirmed && <Notice>The customer has not confirmed the fare yet. The job opens as soon as they do.</Notice>}
      <Card>
        <KV items={[["Fare", j.fare_kes ? <Kes key="f" value={j.fare_kes} /> : "awaiting confirmation"], ["Payment", "M-Pesa from the customer after completion"]]} />
      </Card>
      <Section title="Stops">
        {j.stops.map((st) => (
          <Card key={st.job_id} tone={st.job_id === j.current_job_id ? "gold" : undefined} className="flex flex-wrap justify-between gap-2">
            <div>
              <p className="text-text-primary text-sm font-semibold">{st.seq}. {st.from}{st.to !== st.from ? ` → ${st.to}` : ""}</p>
              <p className="text-text-muted text-xs">{st.description}{st.distance_km ? ` · ${Number(st.distance_km).toFixed(1)} km` : ""}{st.billed_hours ? ` · ${st.billed_hours} h` : ""}</p>
            </div>
            <Badge status={st.status} />
          </Card>
        ))}
      </Section>
      {j.current_job_id && s && NEXT[s] && j.fare_confirmed && (
        <CommandForm sub="OPERATOR_APP" command={s === "CREATED" ? "ACKNOWLEDGE_JOB" : "EMIT_PROGRESS_SIGNAL"} fixed={{ job_id: j.current_job_id }}
          submit={NEXT[s]} success="Updated — the customer has been told." />
      )}
      {!j.current_job_id && j.stops.filter((st) => st.status === "COMPLETED").map((st) => (
        <CommandForm key={st.job_id} sub="OPERATOR_APP" command="EMIT_PROGRESS_SIGNAL" fixed={{ job_id: st.job_id }}
          submit={`Verify and close stop ${st.seq}`} success="Closed — you are free for the next job." />
      ))}
      {travelling && j.current_job_id && <LocationShare jobId={j.current_job_id} />}
      <div className="grid md:grid-cols-2 gap-4">
        {j.can_decline && (
          <Section title="Can't take it?">
            <Card>
              <CommandForm sub="OPERATOR_APP" command="DECLINE_JOB" fixed={{ order_id: j.order_id }} submit="Decline job" variant="danger"
                confirm="Decline this job? It will be offered to another operator." redirectTo="/office/operator">
                <label className={labelClass}>Reason<input name="reason" required className={inputClass} /></label>
              </CommandForm>
            </Card>
          </Section>
        )}
        {j.current_job_id && (
          <Section title="Report a problem">
            <Card>
              <CommandForm sub="OPERATOR_APP" command="REPORT_PROBLEM" fixed={{ job_id: j.current_job_id }} submit="Report to TrustRide Office" success="Reported — Office will contact you.">
                <label className={labelClass}>Kind<select name="category" className={inputClass}><option value="OPERATOR_PROBLEM">Problem with the job</option><option value="SAFETY">Safety</option></select></label>
                <label className={labelClass}>What happened<input name="subject" required className={inputClass} /></label>
              </CommandForm>
            </Card>
          </Section>
        )}
      </div>
    </Page>
  );
}
