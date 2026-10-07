import { redirect } from "next/navigation";
import { gateContext, officeSub, project } from "@/lib/trustride";
import AutoRefresh from "@/components/AutoRefresh";
import { Badge, Card, Empty, ErrorNote, Page, Section, when } from "@/components/ui";

type Tracking = {
  vehicles: { plate: string; device: string; status: string; last_seen_at: string | null; lat: number | null; lon: number | null; unit_availability: string | null; on_order: string | null }[];
  active_jobs: { order_code: string; status: string; lat: number | null; lon: number | null; updated_at: string }[];
};

const map = (lat: number | null, lon: number | null) =>
  lat != null && lon != null ? <a className="text-gold-light text-xs underline" target="_blank" rel="noreferrer" href={`https://www.google.com/maps?q=${lat},${lon}`}>map</a> : null;

// Administrative tracking (projection OFFICE_TRACKING): every Protrack-fitted
// vehicle and every live job position. Customers see only their own trip,
// only while it is active.
export default async function OfficeTracking() {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  const { data, error } = await project<Tracking>(officeSub(ctx), "OFFICE_TRACKING");
  return (
    <Page title="Tracking" intro="Protrack devices and live job positions.">
      <AutoRefresh seconds={15} />
      <ErrorNote error={error} />
      <Section title={`Live jobs · ${data?.active_jobs.length ?? 0}`}>
        {!data?.active_jobs.length && <Empty>No trip is being tracked right now.</Empty>}
        {data?.active_jobs.map((j, i) => (
          <Card key={i} className="flex flex-wrap justify-between gap-2 items-center">
            <span className="text-sm text-text-primary">{j.order_code}</span>
            <span className="flex gap-3 items-center"><Badge status={j.status} /><span className="text-xs text-text-muted">{when(j.updated_at)}</span>{map(j.lat, j.lon)}</span>
          </Card>
        ))}
      </Section>
      <Section title={`Fitted vehicles · ${data?.vehicles.length ?? 0}`}>
        {!data?.vehicles.length && <Empty>No tracker is fitted. Fit one from Resources.</Empty>}
        {data?.vehicles.map((v) => (
          <Card key={v.device} tone={v.status === "STALE" ? "danger" : undefined} className="flex flex-wrap justify-between gap-2 items-center">
            <span className="text-sm text-text-primary">{v.plate} <span className="text-text-muted text-xs">device {v.device}{v.on_order ? ` · on ${v.on_order}` : ""}</span></span>
            <span className="flex gap-3 items-center">
              <Badge status={v.status} />{v.unit_availability && <Badge status={v.unit_availability} />}
              <span className="text-xs text-text-muted">last seen {when(v.last_seen_at)}</span>{map(v.lat, v.lon)}
            </span>
          </Card>
        ))}
      </Section>
    </Page>
  );
}
