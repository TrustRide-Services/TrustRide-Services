import { redirect } from "next/navigation";
import { gateContext, officeAccess, project } from "@/lib/trustride";
import CommandForm from "@/components/CommandForm";
import IssueCredential from "./IssueCredential";
import { Badge, Card, Empty, ErrorNote, Notice, Page, Section, inputClass, when } from "@/components/ui";

type Integrations = {
  gateway_configured: boolean;
  ports: { port: string; vendor: string | null; adapter: string | null; circuit: string | null }[];
  outbound: Record<string, number> | null;
  recent_failures: { operation: string; status: string; error: string | null; at: string }[];
  systems: { user_id: string; name: string; status: string;
    credentials: { prefix: string; scopes: string[]; status: string; last_used_at: string | null; expires_at: string | null }[] }[];
  telemetry: { batches_24h: number; points_24h: number; rejected_24h: number };
};

// Integrations (projection OFFICE_INTEGRATIONS): which provider each port
// talks to (simulator, sandbox, production), what is failing, and the
// external systems allowed to send TrustRide data (Protrack).
export default async function OfficeIntegrations() {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  if (!officeAccess(ctx).admin) redirect("/office");
  const { data: d, error } = await project<Integrations>("ADMIN_CONSOLE", "OFFICE_INTEGRATIONS");
  if (!d) return <Page title="Integrations"><ErrorNote error={error} /></Page>;
  return (
    <Page title="Integrations" intro="Providers behind each port, outbound traffic, and external systems.">
      {!d.gateway_configured && <Notice>The integration gateway is not configured in this environment. Messages and payments wait as “waiting configuration” until it is.</Notice>}
      <div className="grid sm:grid-cols-4 gap-3">
        {Object.entries(d.outbound ?? {}).map(([k, v]) => (
          <Card key={k}><p className="text-text-muted text-xs">{k.toLowerCase().replaceAll("_", " ")} (24 h)</p><p className="text-2xl font-display text-text-primary">{v}</p></Card>
        ))}
        <Card><p className="text-text-muted text-xs">Telemetry (24 h)</p><p className="text-sm text-text-primary">{d.telemetry.batches_24h} batches · {d.telemetry.points_24h} points · {d.telemetry.rejected_24h} rejected</p></Card>
      </div>

      <Section title="Ports">
        <div className="flex flex-col gap-2">
          {d.ports.map((p) => (
            <Card key={p.port} className="flex flex-wrap justify-between gap-2 items-center">
              <span className="text-sm text-text-primary">{p.port.toLowerCase().replaceAll("_", " ")} <span className="text-text-muted text-xs">{p.vendor ?? ""}</span></span>
              <span className="flex flex-wrap gap-2 items-center">
                <Badge status={p.adapter ?? "NONE"} />{p.circuit && p.circuit !== "CLOSED" && <Badge status={p.circuit} />}
                <CommandForm sub="ADMIN_CONSOLE" command="SET_ADAPTER" fixed={{ port_code: p.port }} submit="Switch" variant="ghost" inline
                  confirm="Switch this port's provider mode? Production sends real messages and moves real money.">
                  <select name="adapter_type" defaultValue={p.adapter ?? "SIMULATOR"} className={`${inputClass} w-36`}>
                    <option>SIMULATOR</option><option>SANDBOX</option><option>PRODUCTION</option></select>
                  <input name="notes" required placeholder="Why" className={`${inputClass} w-36`} />
                </CommandForm>
              </span>
            </Card>
          ))}
        </div>
      </Section>

      <Section title="Recent failures">
        {!d.recent_failures.length && <Empty>None.</Empty>}
        {d.recent_failures.map((f, i) => (
          <p key={i} className="text-sm border-b border-border py-1.5 flex flex-wrap justify-between gap-2">
            <span className="text-text-primary">{f.operation} <span className="text-text-muted text-xs">{f.error}</span></span>
            <span className="flex gap-2 items-center"><Badge status={f.status} /><span className="text-xs text-text-muted">{when(f.at)}</span></span>
          </p>
        ))}
      </Section>

      <Section title="External systems">
        <Card>
          <CommandForm sub="ADMIN_CONSOLE" command="REGISTER_EXTERNAL_SYSTEM" submit="Register system" success="Registered — now issue it a key." inline>
            <input name="system_name" required placeholder="System name (e.g. Protrack)" className={`${inputClass} w-56`} />
            <input name="purpose" required placeholder="Purpose" className={`${inputClass} w-64`} />
          </CommandForm>
        </Card>
        {d.systems.map((s) => (
          <Card key={s.user_id} className="flex flex-col gap-2">
            <div className="flex justify-between gap-2"><span className="text-sm text-text-primary font-semibold">{s.name}</span><Badge status={s.status} /></div>
            {s.credentials.map((k) => (
              <div key={k.prefix} className="flex flex-wrap justify-between gap-2 items-center text-xs text-text-secondary">
                <span><code>{k.prefix}…</code> · {k.scopes.join(", ")} · last used {when(k.last_used_at)} · expires {when(k.expires_at)}</span>
                <span className="flex gap-2 items-center"><Badge status={k.status} />
                  {k.status === "ACTIVE" && <CommandForm sub="ADMIN_CONSOLE" command="REVOKE_SYSTEM_CREDENTIAL" fixed={{ key_prefix: k.prefix }} submit="Revoke" variant="danger" inline confirm="Revoke this key? The system stops being able to send data immediately." />}</span>
              </div>
            ))}
            {s.status === "ACTIVE" && <IssueCredential systemUserId={s.user_id} />}
          </Card>
        ))}
      </Section>
    </Page>
  );
}
