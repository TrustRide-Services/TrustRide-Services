import { project } from "@/lib/trustride";
import type { SubShell } from "@/lib/shells";
import CommandForm from "@/components/CommandForm";
import { Badge, Card, Empty, ErrorNote, Page, Section, inputClass, labelClass, when } from "@/components/ui";

type Case = { case_id: string; case_code: string; category: string; severity: string; subject: string; status: string; opened_at: string;
  resolution: string | null; order_code: string | null; messages: { author: string; body: string; at: string }[] };

// Support (projection MY_SUPPORT): open a case, follow the conversation,
// close it when satisfied or reopen it within the window.
export default async function SupportCenter({ sub }: { sub: SubShell }) {
  const { data, error } = await project<{ cases: Case[] }>(sub, "MY_SUPPORT");
  return (
    <Page title="Support" intro="Safety concerns reach TrustRide Office within minutes; everything else within hours.">
      <ErrorNote error={error} />
      <Section title="Open a case">
        <Card>
          <CommandForm sub={sub} command="OPEN_SUPPORT_CASE" submit="Send to TrustRide" success="Case opened.">
            <label className={labelClass}>Topic
              <select name="category" className={inputClass}>
                <option value="OTHER">General question</option><option value="ACCOUNT">My account</option><option value="PAYMENT">Payment</option>
                <option value="SAFETY">Safety concern</option><option value="MARKETPLACE">Marketplace</option>
              </select>
            </label>
            <label className={labelClass}>Subject<input name="subject" required className={inputClass} /></label>
            <label className={labelClass}>Details<textarea name="body" required rows={3} className={inputClass} /></label>
          </CommandForm>
        </Card>
      </Section>
      <Section title={`My cases · ${data?.cases.length ?? 0}`}>
        {data?.cases.length === 0 && <Empty>No cases.</Empty>}
        {data?.cases.map((c) => (
          <Card key={c.case_id} tone={c.severity === "CRITICAL" ? "danger" : undefined} className="flex flex-col gap-3">
            <div className="flex flex-wrap justify-between gap-2">
              <div>
                <p className="text-text-primary font-semibold text-sm">{c.subject}</p>
                <p className="text-text-muted text-xs">{c.case_code} · {c.category.toLowerCase().replace("_", " ")}{c.order_code ? ` · ${c.order_code}` : ""} · {when(c.opened_at)}</p>
              </div>
              <Badge status={c.status} />
            </div>
            <ol className="flex flex-col gap-1.5">
              {c.messages.map((m, i) => (
                <li key={i} className={`text-sm rounded-lg px-3 py-2 ${m.author === "OFFICE" ? "bg-gold/10 border border-gold-dim/40" : "bg-surface"}`}>
                  <span className="text-[11px] text-text-muted">{m.author === "OFFICE" ? "TrustRide" : m.author === "SYSTEM" ? "System" : "You"} · {when(m.at)}</span>
                  <p className="text-text-primary">{m.body}</p>
                </li>
              ))}
            </ol>
            {c.status !== "CLOSED" && (
              <div className="flex flex-wrap gap-2 items-end">
                <CommandForm sub={sub} command="REPLY_SUPPORT_CASE" fixed={{ case_id: c.case_id }} submit="Reply" inline className="flex-1">
                  <input name="body" required placeholder="Write a reply" className={`${inputClass} flex-1 min-w-56`} />
                </CommandForm>
                {c.status === "RESOLVED" && (
                  <>
                    <CommandForm sub={sub} command="CLOSE_SUPPORT_CASE" fixed={{ case_id: c.case_id, action: "CLOSE" }} submit="Close — resolved" variant="ghost" />
                    <CommandForm sub={sub} command="CLOSE_SUPPORT_CASE" fixed={{ case_id: c.case_id, action: "REOPEN" }} submit="Reopen" variant="ghost" />
                  </>
                )}
              </div>
            )}
          </Card>
        ))}
      </Section>
    </Page>
  );
}
