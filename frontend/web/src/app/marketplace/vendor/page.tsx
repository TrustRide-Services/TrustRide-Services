import { project } from "@/lib/trustride";
import CommandForm from "@/components/CommandForm";
import RequestPanel, { scopeField } from "@/components/RequestPanel";
import { Badge, Card, Empty, ErrorNote, Kes, Page, Section, inputClass, labelClass, when } from "@/components/ui";

type Vendor = {
  agreement: { commission_pct: string; since: string; status: string } | null;
  listings: { listing_id: string; title: string; category: string; price_kes: number; status: string; listed_at: string }[];
  sales: { order_id: string; order_code: string; status: string; title: string; buyer_first_name: string; price_kes: string; can_confirm_handover: boolean }[];
  payouts: { gross_kes: number; commission_kes: number; payout_kes: number; status: string; paid_at: string | null }[];
};

// Vendor_App (projection VENDOR_HOME): apply; once approved, list motorcycles
// and cars, hand them over when paid, and receive the sale price less
// TrustRide's 5% by M-Pesa.
export default async function VendorPage() {
  const { data, error } = await project<Vendor>("VENDOR_APP", "VENDOR_HOME");
  return (
    <Page title="Sell as a vendor" intro="TrustRide lists motorcycles and cars only. Commission is 5% of every completed sale, deducted from your payout.">
      <ErrorNote error={error} />
      {!data?.agreement ? (
        <RequestPanel sub="VENDOR_APP" root="VENDOR_LISTING_REQUEST" command="SUBMIT_VENDOR_LISTING" title="Vendor application"
          fields={<>
            {scopeField("line.description", "Your business", "e.g. Kondele Motors -- used motorcycles")}
            <label className={labelClass}>What you sell
              <select name="scope.vehicle_category" className={inputClass}><option value="MOTORCYCLE">Motorcycles</option><option value="CAR">Cars</option></select>
            </label>
          </>} />
      ) : (
        <>
          <Section title="List a vehicle">
            <Card>
              <CommandForm sub="VENDOR_APP" command="PUBLISH_OFFER" submit="Publish listing" success="Listed.">
                <div className="grid sm:grid-cols-3 gap-2">
                  <label className={labelClass}>Category<select name="vehicle_category" className={inputClass}><option value="MOTORCYCLE">Motorcycle</option><option value="CAR">Car</option></select></label>
                  <label className={labelClass}>Title<input name="title" required placeholder="Bajaj Boxer 150, 2022" className={inputClass} /></label>
                  <label className={labelClass}>Price (KES)<input name="price_kes:n" type="number" min={1} required className={inputClass} /></label>
                </div>
                <label className={labelClass}>Description<textarea name="description" rows={2} className={inputClass} /></label>
              </CommandForm>
            </Card>
          </Section>
          <Section title={`My listings · ${data.listings.length}`}>
            {!data.listings.length && <Empty>No listings yet.</Empty>}
            {data.listings.map((l) => (
              <Card key={l.listing_id} className="flex flex-wrap justify-between items-center gap-2">
                <span className="text-sm text-text-primary">{l.title} · <Kes value={l.price_kes} /></span>
                <span className="flex items-center gap-2">
                  <Badge status={l.status} />
                  {l.status === "LISTED" && <CommandForm sub="VENDOR_APP" command="DELIST_OFFER" fixed={{ listing_id: l.listing_id }} submit="Withdraw" variant="ghost" />}
                </span>
              </Card>
            ))}
          </Section>
          <Section title="Sales">
            {!data.sales.length && <Empty>No sales yet.</Empty>}
            {data.sales.map((s) => (
              <Card key={s.order_id} className="flex flex-wrap justify-between items-center gap-2">
                <span className="text-sm text-text-primary">{s.order_code} · {s.title} · buyer {s.buyer_first_name} · <Kes value={s.price_kes} /></span>
                <span className="flex items-center gap-2">
                  <Badge status={s.status} />
                  {s.can_confirm_handover && (
                    <CommandForm sub="VENDOR_APP" command="CONFIRM_HANDOVER" fixed={{ order_id: s.order_id }} submit="Confirm handover" success="Handover recorded — your payout is on its way.">
                      <input name="notes" placeholder="Logbook transferred, keys handed" className={inputClass} />
                    </CommandForm>
                  )}
                </span>
              </Card>
            ))}
          </Section>
          <Section title="Payouts">
            {!data.payouts.length && <Empty>No payouts yet.</Empty>}
            {data.payouts.map((p, i) => (
              <Card key={i} className="flex justify-between text-sm">
                <span>Sale <Kes value={p.gross_kes} /> − commission <Kes value={p.commission_kes} /> = <span className="text-text-primary font-semibold"><Kes value={p.payout_kes} /></span></span>
                <span className="flex gap-2 items-center"><Badge status={p.status} />{p.paid_at && <span className="text-text-muted text-xs">{when(p.paid_at)}</span>}</span>
              </Card>
            ))}
          </Section>
        </>
      )}
    </Page>
  );
}
