import { Suspense } from "react";
import RequestHistory from "@/components/RequestHistory";
import { VendorListingForm } from "../MarketplaceForms";

// Vendor_App -- motorcycle and car sellers apply to list on TrustRide.
// Listings must strictly align with TrustRide's market offering; 5%
// commission on every completed sale, recorded in the vendor agreement.
// RENDERING STRATEGY: hybrid -- static heading and form, streamed history.
export default function VendorPage() {
  return (
    <div className="max-w-2xl mx-auto flex flex-col gap-6">
      <div>
        <h1 className="font-display text-xl font-semibold text-text-primary">Sell as a vendor</h1>
        <p className="text-text-secondary text-sm mt-1">
          List motorcycles or cars on TrustRide Marketplace. TrustRide charges 5% on every completed sale. Applications are
          decided within 2–3 working days.
        </p>
      </div>
      <VendorListingForm />
      <section>
        <h2 className="text-[11px] font-semibold uppercase tracking-[0.2em] text-gold-dim mb-3">Your applications</h2>
        <Suspense fallback={<p className="text-text-muted text-sm">Loading…</p>}>
          <RequestHistory root="VENDOR_LISTING_REQUEST" empty="No applications yet." />
        </Suspense>
      </section>
    </div>
  );
}
