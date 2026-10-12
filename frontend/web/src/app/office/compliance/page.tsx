import { redirect } from "next/navigation";
import { gateContext, officeAccess, project } from "@/lib/trustride";
import CommandForm from "@/components/CommandForm";
import EpraPrices from "./EpraPrices";
import { Badge, Card, Empty, ErrorNote, Kes, Notice, Page, Section, inputClass, labelClass, when } from "@/components/ui";

type Compliance = {
  founder: boolean;
  epra: { applied_to_pricing: boolean; watch_jurisdictions: string | null;
    current: { jurisdiction: string; fuel_type: string; pump_price_kes: number; cycle_start: string; cycle_end: string; source_reference: string; status: string }[];
    recent: { jurisdiction: string; fuel_type: string; pump_price_kes: number; cycle_start: string; cycle_end: string; source_reference: string; status: string; recorded_at: string }[] };
  ntsa_lookups: { reference_number: string; identifier_type: string; outcome: string; simulated: boolean; at: string }[];
  purchases: { supplier_pin: string; supplier_name: string; cu_invoice_number: string; invoice_date: string; amount_kes: number; description: string | null; status: string; recorded_at: string }[];
  etims: { determination: string | null; reconciliation_30d: Record<string, number> };
  payroll_sets: { set_id: string; label: string; effective_from: string; effective_to: string | null; status: string; ahl_deductible_confirmed: boolean | null;
    confirmation_reference: string | null; confirmed_at: string | null;
    items: { item_code: string; kind: string; seq: number; upper_kes: number | null; rate: number | null; employer_rate: number | null; fixed_kes: number | null;
      minimum_kes: number | null; deductible_before_paye: string | null; source: string }[] }[];
  dependencies: { port: string; status_level: number; readiness: string; blocking_dependency: string }[];
};

const words = (s: string | null | undefined) => (s ?? "").toLowerCase().replaceAll("_", " ");
const pct = (r: number | null) => (r == null ? "" : `${+(r * 100).toFixed(3)}%`);

// Compliance (projection OFFICE_COMPLIANCE): EPRA price cycles, NTSA vehicle
// lookups, supplier invoices and payroll rates. Each form issues an existing
// command; what is simulated, pending a decision or not yet live is said so.
export default async function OfficeCompliance() {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  if (!officeAccess(ctx).admin) redirect("/office");
  const { data: d, error } = await project<Compliance>("ADMIN_CONSOLE", "OFFICE_COMPLIANCE");
  if (!d) return <Page title="Compliance"><ErrorNote error={error} /></Page>;
  const dep = (port: string) => d.dependencies.find((x) => x.port === port);
  const jurisdictions = (d.epra.watch_jurisdictions ?? "KISUMU_COUNTY").split(",").map((x) => x.trim());
  return (
    <Page title="Compliance" intro="Fuel prices, vehicle identification, supplier invoices and payroll rates.">
      <Section title="EPRA fuel prices">
        <Notice>{d.epra.applied_to_pricing ? "Recorded prices feed pricing." : "Recorded prices are kept with their source but do not change fares until the Founder approves the Engine 5 fuel-price correction."}</Notice>
        <div className="grid sm:grid-cols-2 gap-3">
          {d.epra.current.length === 0 && <Card tone="danger"><p className="text-sm text-danger">No EPRA cycle is recorded for today — record the prices EPRA published for this cycle (15th–14th).</p></Card>}
          {d.epra.current.map((c) => (
            <Card key={c.jurisdiction + c.fuel_type}>
              <p className="text-text-muted text-xs">{words(c.jurisdiction)} · {words(c.fuel_type)} · {c.cycle_start} – {c.cycle_end}</p>
              <p className="text-xl font-display text-text-primary"><Kes value={c.pump_price_kes} /> / litre</p>
              <p className="text-xs text-text-secondary">{c.source_reference}</p>
            </Card>
          ))}
        </div>
        <Card>
          <CommandForm sub="ADMIN_CONSOLE" command="RECORD_EPRA_PRICE_CYCLE" submit="Record cycle" success="Recorded with its source.">
            <div className="grid sm:grid-cols-3 gap-2">
              <label className={labelClass}>Cycle starts (15th)<input name="cycle_start" type="date" required className={inputClass} /></label>
              <label className={labelClass}>Cycle ends (14th)<input name="cycle_end" type="date" required className={inputClass} /></label>
              <label className={labelClass}>Published on<input name="publication_date" type="date" required className={inputClass} /></label>
            </div>
            <EpraPrices jurisdictions={jurisdictions} />
            <div className="grid sm:grid-cols-2 gap-2">
              <label className={labelClass}>Source (publication title)<input name="source_reference" required placeholder="EPRA maximum retail prices, cycle 15 Oct – 14 Nov 2026" className={inputClass} /></label>
              <label className={labelClass}>Source link<input name="source_url" type="url" placeholder="https://www.epra.go.ke/…" className={inputClass} /></label>
            </div>
          </CommandForm>
        </Card>
        {d.epra.recent.length > 0 && (
          <div className="flex flex-col">
            {d.epra.recent.map((r, i) => (
              <p key={i} className="text-xs border-b border-border py-1 flex flex-wrap justify-between gap-2 text-text-secondary">
                <span>{words(r.jurisdiction)} · {words(r.fuel_type)} · {r.cycle_start} – {r.cycle_end} · <Kes value={r.pump_price_kes} /> · {r.source_reference}</span>
                <span className="flex gap-2 items-center"><Badge status={r.status} />{when(r.recorded_at)}</span>
              </p>
            ))}
          </div>
        )}
      </Section>

      <Section title="NTSA vehicle identification">
        <Notice>Answers come from the simulator: NTSA publishes no lookup service, and TrustRide has no NTSA access agreement yet. {dep("NTSA_SERVICE")?.blocking_dependency}</Notice>
        <Card>
          <CommandForm sub="ADMIN_CONSOLE" command="NTSA_VEHICLE_LOOKUP" submit="Look up" success="Looked up — see the result below." inline>
            <select name="identifier_type" className={`${inputClass} w-32`}><option value="VIN">VIN</option><option value="CHASSIS">Chassis</option></select>
            <input name="identifier" required placeholder="17-character VIN or chassis number" className={`${inputClass} w-72`} />
          </CommandForm>
        </Card>
        {!d.ntsa_lookups.length && <Empty>No lookups yet.</Empty>}
        {d.ntsa_lookups.map((n, i) => (
          <p key={i} className="text-sm border-b border-border py-1.5 flex flex-wrap justify-between gap-2">
            <span className="text-text-primary"><code>{n.reference_number}</code> <span className="text-text-muted text-xs">{n.identifier_type}{n.simulated ? " · simulated" : ""}</span></span>
            <span className="flex gap-2 items-center"><Badge status={n.outcome} /><span className="text-xs text-text-muted">{when(n.at)}</span></span>
          </p>
        ))}
      </Section>

      <Section title="Supplier invoices (eTIMS purchases)">
        <Notice>Recorded as received from suppliers. Nothing is sent to KRA: eTIMS submission waits for the legal and tax determination ({words(d.etims.determination)}).</Notice>
        <Card>
          <CommandForm sub="ADMIN_CONSOLE" command="RECORD_PURCHASE_INVOICE" submit="Record invoice" success="Supplier invoice recorded.">
            <div className="grid sm:grid-cols-3 gap-2">
              <label className={labelClass}>Supplier KRA PIN<input name="supplier_pin" required placeholder="P051234567X" className={inputClass} /></label>
              <label className={labelClass}>Supplier name<input name="supplier_name" required className={inputClass} /></label>
              <label className={labelClass}>Control unit invoice number<input name="cu_invoice_number" required placeholder="As printed on the invoice" className={inputClass} /></label>
              <label className={labelClass}>Invoice date<input name="invoice_date" type="date" required className={inputClass} /></label>
              <label className={labelClass}>Amount (KES)<input name="amount_kes:n" type="number" step="0.01" min="0.01" required className={inputClass} /></label>
              <label className={labelClass}>What was bought<input name="description" className={inputClass} /></label>
            </div>
          </CommandForm>
        </Card>
        {Object.keys(d.etims.reconciliation_30d).length > 0 && (
          <p className="text-xs text-text-secondary">Last 30 days: {Object.entries(d.etims.reconciliation_30d).map(([k, v]) => `${words(k)} ${v}`).join(" · ")}</p>
        )}
        {!d.purchases.length && <Empty>No supplier invoices recorded.</Empty>}
        {d.purchases.map((p, i) => (
          <p key={i} className="text-sm border-b border-border py-1.5 flex flex-wrap justify-between gap-2">
            <span className="text-text-primary">{p.supplier_name} <span className="text-text-muted text-xs">{p.supplier_pin} · {p.cu_invoice_number} · {p.invoice_date}{p.description ? ` · ${p.description}` : ""}</span></span>
            <span className="flex gap-2 items-center"><Kes value={p.amount_kes} /><Badge status={p.status} /></span>
          </p>
        ))}
      </Section>

      <Section title="Payroll statutory rates">
        {d.payroll_sets.map((s) => (
          <Card key={s.set_id} className="flex flex-col gap-2" tone={s.status === "PROVISIONAL" ? "gold" : undefined}>
            <div className="flex flex-wrap justify-between gap-2">
              <span className="text-sm text-text-primary font-semibold">{s.label} <span className="text-text-muted text-xs font-normal">from {s.effective_from}{s.effective_to ? ` to ${s.effective_to}` : ""}</span></span>
              <Badge status={s.status} />
            </div>
            <ul className="text-xs text-text-secondary flex flex-col gap-0.5">
              {s.items.map((i) => (
                <li key={i.item_code + i.seq}>
                  <span className="text-text-primary">{i.item_code === "PAYE" ? `PAYE band ${i.seq}` : words(i.item_code)}</span>{" "}
                  {i.rate != null && pct(i.rate)}{i.employer_rate ? ` + employer ${pct(i.employer_rate)}` : ""}{i.upper_kes != null ? ` up to KES ${i.upper_kes.toLocaleString()}` : ""}
                  {i.fixed_kes != null ? ` KES ${i.fixed_kes.toLocaleString()} a month` : ""}{i.minimum_kes != null ? ` (minimum KES ${i.minimum_kes})` : ""}
                  {i.deductible_before_paye && ` · deductible before PAYE: ${i.deductible_before_paye === "UNCONFIRMED" ? "awaiting professional confirmation" : words(i.deductible_before_paye)}`}
                  <span className="text-text-muted"> — {i.source}</span>
                </li>
              ))}
            </ul>
            {s.status === "CONFIRMED" ? (
              <p className="text-xs text-success">Confirmed {when(s.confirmed_at)} · Housing Levy {s.ahl_deductible_confirmed ? "deductible" : "not deductible"} before PAYE · {s.confirmation_reference}</p>
            ) : d.founder ? (
              <CommandForm sub="ADMIN_CONSOLE" command="CONFIRM_PAYROLL_STATUTORY_SET" fixed={{ set_id: s.set_id }} submit="Record professional confirmation"
                success="Confirmed — payroll figures are now final." confirm="Record that a qualified professional has confirmed these rates? This cannot be undone.">
                <div className="grid sm:grid-cols-2 gap-2">
                  <label className={labelClass}>Housing Levy deductible before PAYE?
                    <select name="ahl_deductible:j" className={inputClass} required defaultValue=""><option value="" disabled>Choose</option><option value="true">Yes</option><option value="false">No</option></select></label>
                  <label className={labelClass}>Confirmation reference (opinion, letter or KRA ruling)<input name="confirmation_reference" required className={inputClass} /></label>
                </div>
              </CommandForm>
            ) : (
              <p className="text-xs text-text-muted">Provisional: payroll figures are not final until the Founder records a professional confirmation.</p>
            )}
          </Card>
        ))}
      </Section>
    </Page>
  );
}
