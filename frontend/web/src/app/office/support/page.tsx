import { redirect } from "next/navigation";
import { gateContext, officeAccess, officeSub, project } from "@/lib/trustride";
import CommandForm from "@/components/CommandForm";
import { Badge, Card, Empty, ErrorNote, Page, inputClass, when } from "@/components/ui";

type Case = { case_id: string; case_code: string; category: string; severity: string; subject: string; status: string; opened_at: string;
  sla_due_at: string | null; escalated_at: string | null; requester: string; assigned_to: string | null; order_code: string | null;
  messages: { author: string; body: string; internal: boolean; at: string }[] };

// Support queue (projection OFFICE_SUPPORT): most severe and soonest-due
// first. Internal notes never reach the customer.
export default async function OfficeSupport() {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  const admin = officeAccess(ctx).admin;
  const { data, error } = await project<{ cases: Case[] }>(officeSub(ctx), "OFFICE_SUPPORT");
  return (
    <Page title="Support" intro="Cases from customers, operators and actors.">
      <ErrorNote error={error} />
      {!data?.cases.length && <Empty>No cases.</Empty>}
      <div className="flex flex-col gap-3">
        {data?.cases.map((c) => {
          const open = !["RESOLVED", "CLOSED"].includes(c.status);
          return (
            <Card key={c.case_id} tone={c.escalated_at && open ? "danger" : undefined} className="flex flex-col gap-2">
              <div className="flex flex-wrap justify-between gap-2">
                <span className="text-sm text-text-primary font-semibold">{c.case_code} · {c.subject}</span>
                <span className="flex gap-2"><Badge status={c.severity} /><Badge status={c.status} /></span>
              </div>
              <p className="text-xs text-text-muted">{c.category.toLowerCase().replaceAll("_", " ")} · {c.requester}{c.order_code ? ` · order ${c.order_code}` : ""} · opened {when(c.opened_at)}
                {c.sla_due_at && open ? ` · due ${when(c.sla_due_at)}` : ""}{c.assigned_to ? ` · with ${c.assigned_to}` : " · unassigned"}</p>
              <div className="flex flex-col gap-1 border-l border-border pl-3">
                {c.messages.map((m, i) => (
                  <p key={i} className={`text-sm ${m.internal ? "text-gold-light italic" : "text-text-secondary"}`}>
                    <span className="text-text-muted text-xs">{m.author.toLowerCase()}{m.internal ? " (internal)" : ""} · {when(m.at)}</span><br />{m.body}</p>
                ))}
              </div>
              {admin && open && (
                <div className="flex flex-wrap gap-2 items-end">
                  {!c.assigned_to && <CommandForm sub="ADMIN_CONSOLE" command="ASSIGN_SUPPORT_CASE" fixed={{ case_id: c.case_id }} submit="Take this case" variant="ghost" inline />}
                  <CommandForm sub="ADMIN_CONSOLE" command="REPLY_SUPPORT_CASE" fixed={{ case_id: c.case_id }} submit="Send" inline>
                    <input name="body" required placeholder="Reply" className={`${inputClass} w-72`} />
                    <label className="text-xs text-text-secondary flex items-center gap-1"><input type="checkbox" name="internal:b" /> internal note</label>
                  </CommandForm>
                  <CommandForm sub="ADMIN_CONSOLE" command="RESOLVE_SUPPORT_CASE" fixed={{ case_id: c.case_id }} submit="Resolve" variant="ghost" inline>
                    <input name="resolution" required placeholder="Resolution (sent to the requester)" className={`${inputClass} w-72`} />
                  </CommandForm>
                </div>
              )}
            </Card>
          );
        })}
      </div>
    </Page>
  );
}
