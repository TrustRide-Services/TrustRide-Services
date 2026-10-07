import { redirect } from "next/navigation";
import { gateContext, officeAccess, officeSub, project } from "@/lib/trustride";
import CommandForm from "@/components/CommandForm";
import { Badge, Card, Empty, ErrorNote, Kes, Page, Section, inputClass, labelClass, when } from "@/components/ui";

type Mkt = {
  inventory: { inventory_item_id: string; item_code: string; category: string; state: string; acquisition_cost_kes: number | null; valuation_kes: number | null;
    inspection: string | null; refurbishment: string | null; compliance: string | null }[];
  listings: { listing_id: string; title: string; type: string; category: string; price_kes: number; status: string; vendor: string | null; reserved_until: string | null }[];
  purchases: { order_id: string; order_code: string; status: string; title: string | null; placed_at: string; buyer: string;
    payment: { status: string; amount_kes: number; rail: string } | null }[];
  payouts: { payout_id: string; vendor: string; gross_kes: number; commission_kes: number; payout_kes: number; status: string; failure_reason: string | null }[];
  estates: { estate_id: string; name: string }[];
};

// The stock pipeline: acquired -> inspected -> valued -> refurbished ->
// compliant -> listed -> sold -> aftercare. Office records the first five; listing,
// sale and aftercare follow from the Marketplace itself.
const NEXT_STATE: Record<string, string> = { ACQUIRED: "INSPECTED", INSPECTED: "VALUED", VALUED: "REFURBISHED", REFURBISHED: "COMPLIANT" };

// Marketplace operations (projection OFFICE_MARKETPLACE): TrustRide's own
// stock, vendor listings, purchases awaiting handover, vendor payouts.
export default async function OfficeMarketplace() {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  const admin = officeAccess(ctx).admin;
  const { data: m, error } = await project<Mkt>(officeSub(ctx), "OFFICE_MARKETPLACE");
  if (!m) return <Page title="Marketplace"><ErrorNote error={error} /></Page>;
  return (
    <Page title="Marketplace" intro="Own stock, vendor listings, purchases and payouts.">
      {admin && (
        <Section title="Acquire a vehicle into stock">
          <Card>
            <CommandForm sub="ADMIN_CONSOLE" command="ACQUIRE_INVENTORY" submit="Acquire" success="Added to stock — inspect it next.">
              <div className="grid sm:grid-cols-4 gap-2">
                <label className={labelClass}>Category<select name="vehicle_category" className={inputClass}>{["MOTORCYCLE", "TUKTUK", "CAR", "PICKUP", "VAN", "TRUCK"].map((t) => <option key={t}>{t}</option>)}</select></label>
                <label className={labelClass}>Make<input name="make" required className={inputClass} /></label>
                <label className={labelClass}>Model<input name="model" required className={inputClass} /></label>
                <label className={labelClass}>Year<input name="year:n" type="number" className={inputClass} /></label>
                <label className={labelClass}>Plate<input name="plate_number" required className={inputClass} /></label>
                <label className={labelClass}>Source<select name="acquisition_source" className={inputClass}><option>PURCHASE</option><option>TRADE_IN</option><option>AUCTION</option></select></label>
                <label className={labelClass}>Cost (KES)<input name="acquisition_cost_kes:n" type="number" required className={inputClass} /></label>
                <label className={labelClass}>Kept at<select name="custody_estate_id" className={inputClass}>{m.estates.map((e) => <option key={e.estate_id} value={e.estate_id}>{e.name}</option>)}</select></label>
              </div>
            </CommandForm>
          </Card>
        </Section>
      )}

      <Section title={`Own stock · ${m.inventory.length}`}>
        {!m.inventory.length && <Empty>No stock.</Empty>}
        {m.inventory.map((i) => (
          <Card key={i.inventory_item_id} className="flex flex-col gap-2">
            <div className="flex flex-wrap justify-between gap-2">
              <span className="text-sm text-text-primary font-semibold">{i.item_code} · {i.category.toLowerCase()}</span><Badge status={i.state} />
            </div>
            <p className="text-xs text-text-muted">Cost {i.acquisition_cost_kes != null ? <Kes value={i.acquisition_cost_kes} /> : "—"} · valuation {i.valuation_kes != null ? <Kes value={i.valuation_kes} /> : "—"}
              {" · "}inspection {i.inspection ?? "—"} · refurbishment {i.refurbishment ?? "—"} · compliance {i.compliance ?? "—"}</p>
            {admin && NEXT_STATE[i.state] && (
              <CommandForm sub="ADMIN_CONSOLE" command="ADVANCE_INVENTORY" fixed={{ inventory_item_id: i.inventory_item_id, new_state: NEXT_STATE[i.state] }}
                submit={`Mark ${NEXT_STATE[i.state].toLowerCase()}`} variant="ghost" inline>
                {NEXT_STATE[i.state] === "INSPECTED" && <input name="inspection_status" required placeholder="Inspection result" className={`${inputClass} w-44`} />}
                {NEXT_STATE[i.state] === "VALUED" && <input name="valuation_kes:n" type="number" required placeholder="Valuation (KES)" className={`${inputClass} w-44`} />}
                {NEXT_STATE[i.state] === "REFURBISHED" && <input name="refurbishment_status" required placeholder="Work done" className={`${inputClass} w-44`} />}
                {NEXT_STATE[i.state] === "COMPLIANT" && <input name="compliance_status" required placeholder="Compliance reference" className={`${inputClass} w-44`} />}
              </CommandForm>
            )}
            {admin && i.state === "COMPLIANT" && (
              <CommandForm sub="ADMIN_CONSOLE" command="PUBLISH_OFFER" fixed={{ inventory_item_id: i.inventory_item_id }} submit="List for sale" inline>
                <input name="title" required placeholder="Listing title" className={`${inputClass} w-56`} />
                <input name="price_kes:n" type="number" placeholder={`Price (default ${i.valuation_kes ?? ""})`} className={`${inputClass} w-40`} />
                <input name="description" placeholder="Description" className={`${inputClass} w-64`} />
              </CommandForm>
            )}
          </Card>
        ))}
      </Section>

      <Section title={`Listings · ${m.listings.length}`}>
        {!m.listings.length && <Empty>Nothing listed.</Empty>}
        {m.listings.map((l) => (
          <Card key={l.listing_id} className="flex flex-wrap justify-between gap-2 items-center">
            <span className="text-sm text-text-primary">{l.title} · <Kes value={l.price_kes} /> <span className="text-text-muted text-xs">{l.type === "OWN_MARKETPLACE" ? "TrustRide stock" : `vendor ${l.vendor}`}
              {l.reserved_until ? ` · reserved to ${when(l.reserved_until)}` : ""}</span></span>
            <span className="flex gap-2 items-center"><Badge status={l.status} />
              {admin && ["DRAFT", "LISTED"].includes(l.status) && <CommandForm sub="ADMIN_CONSOLE" command="DELIST_OFFER" fixed={{ listing_id: l.listing_id }} submit="Delist" variant="ghost" inline confirm="Delist this offer?" />}</span>
          </Card>
        ))}
      </Section>

      <Section title={`Purchases · ${m.purchases.length}`}>
        {!m.purchases.length && <Empty>No purchases.</Empty>}
        {m.purchases.map((p) => (
          <Card key={p.order_id} className="flex flex-col gap-2">
            <div className="flex flex-wrap justify-between gap-2">
              <span className="text-sm text-text-primary font-semibold">{p.order_code} · {p.title} · {p.buyer}</span><Badge status={p.status} />
            </div>
            <p className="text-xs text-text-muted">{when(p.placed_at)}{p.payment ? <> · <Kes value={p.payment.amount_kes} /> by {p.payment.rail.toLowerCase().replaceAll("_", " ")} · {p.payment.status.toLowerCase().replaceAll("_", " ")}</> : ""}</p>
            {admin && p.status === "SETTLED" && (
              <CommandForm sub="ADMIN_CONSOLE" command="CONFIRM_HANDOVER" fixed={{ order_id: p.order_id }} submit="Confirm handover" inline>
                <input name="notes" placeholder="Handover notes (logbook, keys)" className={`${inputClass} w-72`} />
              </CommandForm>
            )}
            {admin && p.payment?.rail === "BANK_TRANSFER" && p.payment.status !== "RECEIPT_GENERATED" && (
              <CommandForm sub="ADMIN_CONSOLE" command="RECORD_BANK_PAYMENT" fixed={{ order_id: p.order_id, amount_kes: p.payment.amount_kes }} submit="Record bank transfer" inline>
                <input name="bank_reference" required placeholder="Bank reference" className={`${inputClass} w-44`} />
              </CommandForm>
            )}
          </Card>
        ))}
      </Section>

      <Section title="Vendor payouts">
        {!m.payouts.length && <Empty>No payouts.</Empty>}
        {m.payouts.map((p) => (
          <Card key={p.payout_id} tone={p.status === "FAILED" ? "danger" : undefined} className="flex flex-wrap justify-between gap-2 items-center">
            <span className="text-sm text-text-primary">{p.vendor} · <Kes value={p.payout_kes} /> <span className="text-text-muted text-xs">(sale <Kes value={p.gross_kes} />, commission <Kes value={p.commission_kes} />){p.failure_reason ? ` · ${p.failure_reason}` : ""}</span></span>
            <span className="flex gap-2 items-center"><Badge status={p.status} />
              {admin && p.status === "FAILED" && <CommandForm sub="ADMIN_CONSOLE" command="RETRY_VENDOR_PAYOUT" fixed={{ payout_id: p.payout_id }} submit="Retry payout" inline confirm="Send this payout again? Check M-Pesa first that the earlier attempt did not go through." />}</span>
          </Card>
        ))}
      </Section>
    </Page>
  );
}
