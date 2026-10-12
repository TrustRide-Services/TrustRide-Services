import { redirect } from "next/navigation";
import { gateContext, officeAccess, project } from "@/lib/trustride";
import CommandForm from "@/components/CommandForm";
import { Badge, Card, Empty, ErrorNote, Kes, Notice, Page, Section, inputClass, labelClass, when } from "@/components/ui";

type Service = {
  service_id: string; service_code: string; service_name: string; description: string; macro_domain: string; status: string;
  fulfilment: string | null; pillar: string | null; ea_skill_category: string | null; special_intent: boolean;
  coverage: string[]; pricing: { jurisdiction: string; asset_class: string; registry_code: string; current_rate_kes: number | null }[];
  open_orders: number; blockers: string[]; ready_to_activate: boolean; updated_at: string;
};
type Catalogue = { services: Service[]; macro_domains: string[]; pillars: string[]; ea_skill_categories: string[]; jurisdictions: string[] };

const words = (s: string | null) => (s ?? "").toLowerCase().replaceAll("_", " ");

// Service catalogue (projection OFFICE_CATALOGUE; Engine 3). Engine 5 owns the
// price of every dispatched service: a service goes live only where Engine 5
// already prices it, and nothing on this page changes a rate.
export default async function OfficeCatalogue() {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  if (!officeAccess(ctx).admin) redirect("/office");
  const { data: d, error } = await project<Catalogue>("ADMIN_CONSOLE", "OFFICE_CATALOGUE");
  if (!d) return <Page title="Service catalogue"><ErrorNote error={error} /></Page>;
  const domains = d.macro_domains.map((m) => ({ m, list: d.services.filter((s) => s.macro_domain === m) }))
    .concat([{ m: "MARKETPLACE", list: d.services.filter((s) => s.macro_domain === "MARKETPLACE") }]);
  return (
    <Page title="Service catalogue" intro="What TrustRide offers, where, and the Engine 5 price behind each dispatched service.">
      <Notice>Prices are set in Engine 5 (the cost registry), not here. A dispatched service can go live only in jurisdictions where Engine 5 already prices it.
        Suspending a service stops new orders; orders already placed continue.</Notice>

      <Section title="Add a dispatched service">
        <Card>
          <CommandForm sub="ADMIN_CONSOLE" command="REGISTER_SERVICE" fixed={{ fulfilment: "DISPATCH" }} submit="Register as draft" success="Registered as a draft — add its coverage, then activate.">
            <div className="grid sm:grid-cols-2 gap-2">
              <label className={labelClass}>Service code<input name="service_code" required placeholder="TRANSPORT-BODA-EXPRESS" className={inputClass} /></label>
              <label className={labelClass}>Name<input name="service_name" required placeholder="Express Ride (Boda Boda)" className={inputClass} /></label>
              <label className={labelClass}>Domain
                <select name="macro_domain" className={inputClass}>{d.macro_domains.map((m) => <option key={m} value={m}>{words(m)}</option>)}</select></label>
              <label className={labelClass}>Pillar (Executive Assistants only)
                <select name="pillar" className={inputClass} defaultValue=""><option value="">—</option>{d.pillars.map((p) => <option key={p} value={p}>{words(p)}</option>)}</select></label>
              <label className={labelClass}>Skill category (Executive Assistants only)
                <select name="ea_skill_category" className={inputClass} defaultValue=""><option value="">—</option>{d.ea_skill_categories.map((c) => <option key={c} value={c}>{words(c)}</option>)}</select></label>
              <label className={labelClass}>Eligibility summary<input name="eligibility_summary" className={inputClass} /></label>
            </div>
            <label className={labelClass}>Description<input name="description" required className={inputClass} /></label>
          </CommandForm>
          <p className="text-xs text-text-muted mt-2">Academy, employment and marketplace services are fixed special intents (TBOC Art.18) and are not added here.</p>
        </Card>
      </Section>

      {domains.map(({ m, list }) => (
        <Section key={m} title={words(m)}>
          {!list.length && <Empty>No services.</Empty>}
          <div className="flex flex-col gap-2">
            {list.map((s) => (
              <Card key={s.service_id} className="flex flex-col gap-2" tone={s.status === "SUSPENDED" ? "danger" : undefined}>
                <div className="flex flex-wrap justify-between gap-2">
                  <span className="text-sm text-text-primary font-semibold">{s.service_name} <code className="text-xs text-text-muted font-normal">{s.service_code}</code></span>
                  <span className="flex gap-2 items-center">{s.special_intent && <span className="text-xs text-text-muted">special intent</span>}<Badge status={s.status} /></span>
                </div>
                <p className="text-xs text-text-secondary">{s.description}</p>
                <p className="text-xs text-text-secondary">
                  {words(s.fulfilment)}{s.pillar ? ` · ${words(s.pillar)} · ${words(s.ea_skill_category)}` : ""} · coverage {s.coverage.length ? s.coverage.map(words).join(", ") : "none"} · {s.open_orders} open order{s.open_orders === 1 ? "" : "s"} · updated {when(s.updated_at)}
                </p>
                {s.fulfilment === "DISPATCH" && (
                  <p className="text-xs text-text-secondary">Engine 5 pricing: {s.pricing.length
                    ? s.pricing.map((p, i) => <span key={i}>{i ? " · " : ""}{words(p.jurisdiction)} {words(p.asset_class)} {p.current_rate_kes != null ? <><Kes value={p.current_rate_kes} />/km</> : "(EA statutory rating)"}</span>)
                    : <span className="text-danger">none</span>}</p>
                )}
                {s.status !== "ACTIVE" && s.status !== "RETIRED" && s.blockers.length > 0 && (
                  <ul className="text-xs text-danger">{s.blockers.map((b) => <li key={b}>{b}</li>)}</ul>
                )}
                {!s.special_intent && s.status !== "RETIRED" && (
                  <div className="flex flex-wrap gap-2 items-end">
                    <CommandForm sub="ADMIN_CONSOLE" command="ADD_SERVICE_COVERAGE" fixed={{ service_id: s.service_id }} submit="Add coverage" variant="ghost" inline success="Coverage added.">
                      <select name="jurisdiction" className={`${inputClass} w-44`}>{d.jurisdictions.filter((j) => !s.coverage.includes(j)).map((j) => <option key={j} value={j}>{words(j)}</option>)}</select>
                    </CommandForm>
                    {(s.status === "DRAFT" || s.status === "SUSPENDED") && (
                      <CommandForm sub="ADMIN_CONSOLE" command="ACTIVATE_SERVICE" fixed={{ service_id: s.service_id }} submit={s.status === "SUSPENDED" ? "Reinstate" : "Activate"} inline
                        success="Live — customers can order it." confirm="Make this service available to customers now?" />
                    )}
                    {s.status === "ACTIVE" && (
                      <CommandForm sub="ADMIN_CONSOLE" command="SUSPEND_SERVICE" fixed={{ service_id: s.service_id }} submit="Suspend" variant="danger" inline success="Suspended — new orders stop; placed orders continue."
                        confirm="Stop new orders for this service? Orders already placed continue.">
                        <input name="reason" required placeholder="Why" className={`${inputClass} w-44`} />
                      </CommandForm>
                    )}
                    {(s.status === "DRAFT" || s.status === "SUSPENDED") && (
                      <CommandForm sub="ADMIN_CONSOLE" command="RETIRE_SERVICE" fixed={{ service_id: s.service_id }} submit="Retire" variant="danger" inline success="Retired."
                        confirm="Retire this service permanently? It cannot be offered again.">
                        <input name="reason" required placeholder="Why" className={`${inputClass} w-40`} />
                      </CommandForm>
                    )}
                  </div>
                )}
              </Card>
            ))}
          </div>
        </Section>
      ))}
    </Page>
  );
}
