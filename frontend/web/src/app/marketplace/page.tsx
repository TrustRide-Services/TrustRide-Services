import { Suspense } from "react";
import RequestHistory from "@/components/RequestHistory";
import { ReserveVehicleForm } from "./MarketplaceForms";

// Marketplace_App -- TrustRide's own second-hand, improved motorcycles and
// cars. A reservation enters the governed queue for confirmation.
// RENDERING STRATEGY: hybrid -- static heading and form, streamed history.
export default function MarketplacePage() {
  return (
    <div className="max-w-2xl mx-auto flex flex-col gap-6">
      <div>
        <h1 className="font-display text-xl font-semibold text-text-primary">Buy a vehicle</h1>
        <p className="text-text-secondary text-sm mt-1">
          Second-hand, improved motorcycles and cars — inspected, with condition reports and ownership-transfer support.
        </p>
      </div>
      <ReserveVehicleForm />
      <section>
        <h2 className="text-[11px] font-semibold uppercase tracking-[0.2em] text-gold-dim mb-3">Your reservations</h2>
        <Suspense fallback={<p className="text-text-muted text-sm">Loading…</p>}>
          <RequestHistory root="MARKETPLACE_PURCHASE_ORDER" empty="No reservations yet." />
        </Suspense>
      </section>
    </div>
  );
}
