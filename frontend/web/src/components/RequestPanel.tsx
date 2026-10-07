import { project } from "@/lib/trustride";
import type { SubShell } from "@/lib/shells";
import CommandForm from "@/components/CommandForm";
import { Badge, Card, Empty, Section, inputClass, labelClass, when } from "@/components/ui";

type Req = { order_id: string; order_code: string; root: string; status: string; placed_at: string; lines: string[] | null;
  response: { status: string; notes: string | null; target: string; deadline: string; escalated_at: string | null; responded_at: string | null } | null };

// An actor's governed request: submit it (open even while pending), and
// follow it to TrustRide Office's decision (projection REQUEST_HISTORY).
export default async function RequestPanel({ sub, root, command, title, fields }: {
  sub: SubShell; root: string; command: string; title: string; fields: React.ReactNode;
}) {
  const { data } = await project<{ requests: Req[] }>(sub, "REQUEST_HISTORY", { root });
  const open = data?.requests.find((r) => r.response && ["SUBMITTED", "UNDER_REVIEW"].includes(r.response.status));
  return (
    <div className="grid md:grid-cols-2 gap-4">
      <Section title={title}>
        <Card>
          {open ? (
            <p className="text-sm text-text-secondary">Request <span className="text-text-primary font-semibold">{open.order_code}</span> is with TrustRide Office —
              decision by {when(open.response?.target)} (deadline {when(open.response?.deadline)}).{open.response?.escalated_at ? " It has been escalated." : ""}</p>
          ) : (
            <CommandForm sub={sub} command={command} submit="Submit to TrustRide Office" success="Submitted — decision within 2–3 working days.">{fields}</CommandForm>
          )}
        </Card>
      </Section>
      <Section title="My requests">
        {!data?.requests.length && <Empty>None yet.</Empty>}
        {data?.requests.map((r) => (
          <Card key={r.order_id}>
            <div className="flex justify-between gap-2">
              <span className="text-text-primary font-semibold text-sm">{r.order_code}</span>
              <Badge status={r.response?.status ?? r.status} />
            </div>
            <p className="text-text-muted text-xs">{(r.lines ?? []).join(" · ")} · {when(r.placed_at)}</p>
            {r.response?.notes && <p className="text-text-secondary text-sm mt-1">“{r.response.notes}”</p>}
          </Card>
        ))}
      </Section>
    </div>
  );
}

export const scopeField = (name: string, labelText: string, placeholder = "") => (
  <label className={labelClass}>{labelText}<input name={name} placeholder={placeholder} className={inputClass} /></label>
);
