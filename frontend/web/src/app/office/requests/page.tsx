import { redirect } from "next/navigation";
import { gateContext, officeAccess, officeSub, project } from "@/lib/trustride";
import CommandForm from "@/components/CommandForm";
import { Badge, Card, Empty, ErrorNote, Page, Section, inputClass, when } from "@/components/ui";

type Req = { order_id: string; order_code: string; root: string; requester: string; placed_at: string; status: string;
  lines: { description: string; scope: Record<string, unknown> }[];
  response: { status: string; target: string; deadline: string; escalated_at: string | null; notes: string | null; responded_at: string | null } };

const ROOT: Record<string, string> = {
  RESOURCE_PARTNERSHIP_REQUEST: "Partnership / contribution", REGULATORY_ACCESS_REQUEST: "Regulatory access", FACILITATION_REQUEST: "Facilitation",
  VENDOR_LISTING_REQUEST: "Vendor", MARKETPLACE_PURCHASE_ORDER: "Vehicle reservation", OFFICE_ACCESS_REQUEST: "Office access / employment",
  ACADEMY_ENROLLMENT_REQUEST: "Academy enrolment",
};

// Actor requests (projection OFFICE_REQUESTS): decide within 2 working days,
// deadline 3; past it a request escalates, never auto-declines. Approval
// activates exactly what was requested.
export default async function OfficeRequests() {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  const canDecide = officeAccess(ctx).admin;
  const { data, error } = await project<{ requests: Req[] }>(officeSub(ctx), "OFFICE_REQUESTS");
  const open = data?.requests.filter((r) => ["SUBMITTED", "UNDER_REVIEW"].includes(r.response.status)) ?? [];
  const decided = data?.requests.filter((r) => !open.includes(r)) ?? [];
  return (
    <Page title="Actor requests" intro="Mon–Fri 05:00–22:00, Sat 06:00–23:00; Sunday off duty.">
      <ErrorNote error={error} />
      <Section title={`Awaiting decision · ${open.length}`}>
        {!open.length && <Empty>Nothing waiting.</Empty>}
        {open.map((r) => (
          <Card key={r.order_id} tone={r.response.escalated_at ? "danger" : undefined}>
            <div className="flex flex-wrap justify-between gap-2">
              <span className="text-text-primary font-semibold">{r.order_code} · {ROOT[r.root] ?? r.root}</span>
              <span className="text-text-secondary text-sm">{r.requester}</span>
            </div>
            <ul className="text-sm text-text-secondary list-disc pl-5 mt-1">
              {r.lines.map((l, i) => <li key={i}>{l.description}{Object.keys(l.scope ?? {}).length ? <span className="text-text-muted text-xs"> {JSON.stringify(l.scope)}</span> : null}</li>)}
            </ul>
            <p className={`text-xs mt-1 ${new Date(r.response.deadline) < new Date() ? "text-danger" : "text-text-muted"}`}>
              Submitted {when(r.placed_at)} · target {when(r.response.target)} · deadline {when(r.response.deadline)}{r.response.escalated_at ? " · ESCALATED" : ""}</p>
            {canDecide && (
              <div className="flex flex-wrap gap-2 mt-3 items-end">
                <CommandForm sub="ADMIN_CONSOLE" command="REVIEW_ACTOR_REQUEST" fixed={{ order_id: r.order_id, decision: "ACCEPTED" }} submit="Approve" inline>
                  <input name="notes" placeholder="Notes (optional)" className={`${inputClass} w-56`} />
                </CommandForm>
                <CommandForm sub="ADMIN_CONSOLE" command="REVIEW_ACTOR_REQUEST" fixed={{ order_id: r.order_id, decision: "DECLINED" }} submit="Decline" variant="ghost" inline>
                  <input name="notes" required placeholder="Reason (sent to the actor)" className={`${inputClass} w-56`} />
                </CommandForm>
              </div>
            )}
          </Card>
        ))}
      </Section>
      <Section title="Decided (last 14 days)">
        {decided.map((r) => (
          <p key={r.order_id} className="text-sm flex flex-wrap justify-between border-b border-border py-1.5">
            <span className="text-text-primary">{r.order_code} · {ROOT[r.root] ?? r.root} · {r.requester}</span>
            <span><Badge status={r.response.status} /> {when(r.response.responded_at)}</span>
          </p>
        ))}
      </Section>
    </Page>
  );
}
