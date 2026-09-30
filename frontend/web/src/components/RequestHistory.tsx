import { createClient } from "@/lib/supabase/server";

const nairobi = (iso: string | null) =>
  iso ? new Date(iso).toLocaleString("en-KE", { timeZone: "Africa/Nairobi", weekday: "short", day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" }) : "—";

const STATUS_TONE: Record<string, string> = {
  ACCEPTED: "border-success/40 text-success bg-success/10",
  DECLINED: "border-danger/40 text-danger bg-danger-bg",
};
const PENDING_TONE = "border-gold-dim/50 text-gold-light bg-gold/10";

// Every actor request -- partnership, regulatory, facilitation, vendor
// listing, vehicle reservation -- lands in Engine 4's governed response queue.
// This shows the requester their own, straight from those tables (RLS: own
// rows only): decision status, the 2-working-day target, the 3-working-day
// deadline, and whether it has been escalated.
export default async function RequestHistory({ root, empty }: { root: string; empty: string }) {
  const supabase = await createClient();
  const { data: orders } = await supabase
    .from("business_order")
    .select("order_id, order_code, placed_at, business_order_line(line_description)")
    .eq("order_root_type", root)
    .order("placed_at", { ascending: false });

  const ids = (orders ?? []).map((o) => o.order_id);
  const { data: responses } = ids.length
    ? await supabase
        .from("business_partnership_response")
        .select("order_id, response_status, decision_target_at, response_due_at, escalated_at, response_notes")
        .in("order_id", ids)
    : { data: [] };
  const byOrder = new Map((responses ?? []).map((r) => [r.order_id, r]));

  if (!orders || orders.length === 0) return <p className="text-text-muted text-sm">{empty}</p>;

  return (
    <div className="flex flex-col gap-3">
      {orders.map((o) => {
        const r = byOrder.get(o.order_id);
        const status = r?.response_status ?? "SUBMITTED";
        const open = status === "SUBMITTED" || status === "UNDER_REVIEW";
        const lines = (o.business_order_line as { line_description: string }[] | null) ?? [];
        return (
          <div key={o.order_id} className="trs-card p-4">
            <div className="flex justify-between items-start gap-3">
              <span className="font-display font-semibold text-text-primary">{o.order_code}</span>
              <span className={`shrink-0 rounded-full border px-2.5 py-0.5 text-[11px] font-semibold uppercase tracking-wide ${STATUS_TONE[status] ?? PENDING_TONE}`}>
                {status === "ACCEPTED" ? "Approved" : status === "DECLINED" ? "Not approved" : r?.escalated_at ? "Escalated" : "In review"}
              </span>
            </div>
            <ul className="text-text-secondary text-sm mt-2 list-disc pl-5">
              {lines.map((l, i) => <li key={i}>{l.line_description}</li>)}
            </ul>
            {open && (
              <p className="text-text-muted text-xs mt-2.5">
                Decision target {nairobi(r?.decision_target_at ?? null)} · deadline {nairobi(r?.response_due_at ?? null)}
                {r?.escalated_at ? " · escalated within TrustRide Office" : ""}
              </p>
            )}
            {r?.response_notes && <p className="text-text-secondary text-xs mt-2">{r.response_notes}</p>}
          </div>
        );
      })}
    </div>
  );
}
