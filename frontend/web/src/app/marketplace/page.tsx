import Link from "next/link";
import { project } from "@/lib/trustride";
import CommandForm from "@/components/CommandForm";
import { Card, Empty, ErrorNote, Kes, Notice, Page, inputClass, labelClass, when } from "@/components/ui";

type Listing = { listing_id: string; title: string; description: string; category: string; price_kes: number; type: string;
  listed_at: string; seller: string; mine: boolean; stk_payable: boolean };

// Vehicles for sale (projection MARKETPLACE_LISTINGS). Reserving holds the
// vehicle while TrustRide Office confirms availability and viewing; payment
// is requested once confirmed.
export default async function MarketplacePage({ searchParams }: { searchParams: Promise<{ category?: string }> }) {
  const { category } = await searchParams;
  const { data, error } = await project<{ listings: Listing[]; phone_verified: boolean }>("MARKETPLACE_APP", "MARKETPLACE_LISTINGS",
    category ? { category } : {});
  return (
    <Page title="Vehicles for sale" intro="Second-hand, improved motorcycles and cars from TrustRide and approved vendors.">
      <ErrorNote error={error} />
      <div className="flex gap-2">
        {[["", "All"], ["MOTORCYCLE", "Motorcycles"], ["CAR", "Cars"]].map(([c, l]) => (
          <Link key={l} href={c ? `/marketplace?category=${c}` : "/marketplace"}
            className={`rounded-full border px-4 py-1.5 text-sm ${(category ?? "") === c ? "border-gold-dim bg-gold/10 text-text-primary" : "border-border text-text-secondary"}`}>{l}</Link>
        ))}
      </div>
      {data && !data.phone_verified && <Notice>Verify your phone number in Profile before reserving — TrustRide contacts you and requests payment on it.</Notice>}
      {data?.listings.length === 0 && <Empty>No vehicles listed right now.</Empty>}
      <div className="grid sm:grid-cols-2 gap-3">
        {data?.listings.map((l) => (
          <Card key={l.listing_id} className="flex flex-col gap-2">
            <div className="flex justify-between gap-2">
              <p className="text-text-primary font-semibold">{l.title}</p>
              <span className="text-gold-light font-semibold"><Kes value={l.price_kes} /></span>
            </div>
            <p className="text-text-secondary text-sm">{l.description}</p>
            <p className="text-text-muted text-xs">{l.category.toLowerCase()} · sold by {l.seller} · listed {when(l.listed_at)}
              {!l.stk_payable && " · paid by bank transfer"}</p>
            {l.mine ? <p className="text-xs text-text-muted">Your listing</p> : (
              <CommandForm sub="MARKETPLACE_APP" command="RESERVE_VEHICLE" fixed={{ listing_id: l.listing_id }} submit="Reserve"
                redirectTo="/marketplace/purchases/{signal}">
                <label className={labelClass}>Message to TrustRide (optional)<input name="notes" placeholder="When can I view it?" className={inputClass} /></label>
              </CommandForm>
            )}
          </Card>
        ))}
      </div>
    </Page>
  );
}
