import { project } from "@/lib/trustride";
import CommandForm from "@/components/CommandForm";
import RequestPanel, { scopeField } from "@/components/RequestPanel";
import ContributionForm from "./ContributionForm";
import { Badge, Card, Empty, ErrorNote, Page, Section, inputClass, labelClass } from "@/components/ui";

type Home = { registration: string | null;
  agreements: { category: string; type: string; start_date: string; status: string; commission_pct: string | null }[];
  vehicles: { plate: string; label: string; object_status: string; class: string | null; fleet_status: string | null; in_service: boolean; jobs_completed: number }[];
  bases: { estate_id: string; name: string }[] };

// Partner_App (projection PARTNER_HOME): request a partnership; once approved,
// contribute vehicles that enter TrustRide's fleet register in your
// ownership, are NTSA-verified, and are assigned to TrustRide operators.
export default async function PartnerPage() {
  const { data, error } = await project<Home>("PARTNER_APP", "PARTNER_HOME");
  const approved = data?.registration === "ACTIVE";
  return (
    <Page title="Partner" intro="Contribute vehicles, finance or collaboration. Contributed vehicles stay yours and work under TrustRide operators.">
      <ErrorNote error={error} />
      <RequestPanel sub="PARTNER_APP" root="RESOURCE_PARTNERSHIP_REQUEST" command="SUBMIT_PARTNERSHIP_REQUEST" title="Partnership request"
        fields={<>
          {scopeField("line.description", "What do you propose?", "e.g. 5 motorcycles for Kisumu CBD")}
          <label className={labelClass}>Partnership type
            <select name="scope.partner_category" className={inputClass}>
              <option value="FLEET_CONTRIBUTOR">Fleet contributor</option><option value="FINANCIER">Financier</option>
              <option value="STRATEGIC_COLLABORATOR">Strategic collaborator</option><option value="AMBASSADOR">Ambassador</option>
            </select>
          </label>
        </>} />
      {approved && (
        <>
          <Section title="Agreements">
            {data?.agreements.map((a, i) => (
              <Card key={i} className="flex justify-between text-sm"><span className="text-text-primary">{a.category.toLowerCase().replace("_", " ")} · since {a.start_date}</span><Badge status={a.status} /></Card>
            ))}
          </Section>
          <Section title="Contribute vehicles">
            <Card><ContributionForm bases={data?.bases ?? []} /></Card>
          </Section>
        </>
      )}
      <Section title={`My vehicles · ${data?.vehicles.length ?? 0}`}>
        {!data?.vehicles.length && <Empty>No contributed vehicles yet.</Empty>}
        {data?.vehicles.map((v) => (
          <Card key={v.plate} className="flex flex-wrap justify-between gap-2 text-sm">
            <span className="text-text-primary font-semibold">{v.label} · {v.plate}</span>
            <span className="flex gap-2 items-center text-text-muted">
              {v.class ?? "awaiting Office review"} · jobs {v.jobs_completed} {v.in_service && <Badge status="ACTIVE" text="In service" />}
              <Badge status={v.fleet_status ?? v.object_status} />
            </span>
          </Card>
        ))}
      </Section>
      <Section title="Tell TrustRide Office something">
        <Card>
          <CommandForm sub="PARTNER_APP" command="OPEN_SUPPORT_CASE" submit="Send" success="Sent.">
            <input type="hidden" name="category" value="OTHER" />
            <label className={labelClass}>Subject<input name="subject" required className={inputClass} /></label>
            <label className={labelClass}>Message<textarea name="body" required rows={2} className={inputClass} /></label>
          </CommandForm>
        </Card>
      </Section>
    </Page>
  );
}
