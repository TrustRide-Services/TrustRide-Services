import { Suspense } from "react";
import { createClient } from "@/lib/supabase/server";
import { acceptQuotationAction } from "../actions";

type MyOrder = {
  order_id: string;
  order_code: string;
  service_code: string;
  status: string;
  quote_id: string | null;
  placed_at: string;
};

async function AcceptQuotationButton({ quoteId }: { quoteId: string }) {
  async function action() {
    "use server";
    await acceptQuotationAction(quoteId);
  }
  return (
    <form action={action}>
      <button type="submit" className="trs-btn-primary rounded-lg text-sm font-semibold px-4 py-2 mt-3">
        Accept quotation
      </button>
    </form>
  );
}

const STATUS_TONE: Record<string, string> = {
  DELIVERED: "bg-success/15 text-success border-success/30",
  SETTLED: "bg-success/15 text-success border-success/30",
  CANCELLED: "bg-danger-bg text-danger border-danger/30",
  REJECTED: "bg-danger-bg text-danger border-danger/30",
};
const DEFAULT_TONE = "bg-gold/10 text-gold-light border-gold-dim/40";

async function OrdersList() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("business_order")
    .select("order_id, order_code, service_code, status, quote_id, placed_at")
    .order("placed_at", { ascending: false });

  const orders = (data as MyOrder[]) ?? [];

  return (
    <>
      {error && <p className="rounded-lg bg-danger-bg text-danger text-sm p-2.5 mb-3">{error.message}</p>}
      {orders.length === 0 && !error && (
        <p className="text-text-muted text-center mt-10">No orders yet -- place one from the Request Service tab.</p>
      )}
      <div className="flex flex-col gap-3">
        {orders.map((o) => (
          <div key={o.order_id} className="trs-card p-4">
            <div className="flex justify-between items-start gap-3">
              <span className="font-display font-semibold text-text-primary">{o.order_code}</span>
              <span className={`shrink-0 rounded-full border px-2.5 py-0.5 text-[11px] font-semibold uppercase tracking-wide ${STATUS_TONE[o.status] ?? DEFAULT_TONE}`}>
                {o.status}
              </span>
            </div>
            <p className="text-text-secondary text-xs mt-1.5">{o.service_code}</p>
            {o.quote_id && <AcceptQuotationButton quoteId={o.quote_id} />}
          </div>
        ))}
      </div>
    </>
  );
}

// RENDERING STRATEGY: hybrid. The heading is identical for every visitor and
// carries no data dependency, so it's a plain static shell; the order list
// is RLS-scoped to auth.uid() (genuinely per-user, uncacheable) and is
// isolated in its own Suspense boundary so the shell paints immediately
// while that query is still in flight.
export default function OrdersPage() {
  return (
    <div className="max-w-2xl mx-auto">
      <h1 className="font-display text-xl font-semibold text-text-primary mb-5">Your orders</h1>
      <Suspense fallback={<p className="text-text-muted text-center mt-10">Loading your orders…</p>}>
        <OrdersList />
      </Suspense>
    </div>
  );
}
