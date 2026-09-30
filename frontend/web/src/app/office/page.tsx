import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getActorContext } from "@/lib/trustride";
import { reviewRequest } from "./actions";

// Admin_Console review queue (TRS026-ENG011-PRESENT-003 Sec.4, Sec.6): every
// actor request -- partnership, regulatory access, facilitation, vendor
// listing, vehicle reservation, Office access -- awaiting TrustRide Office,
// with its 2-working-day target, 3-working-day deadline and escalation.
// Executives see the same queue read-only; Operators see their surface.
//
// RENDERING STRATEGY: fully dynamic -- live queue, Office-authority gated.
const ROOT_LABEL: Record<string, string> = {
  RESOURCE_PARTNERSHIP_REQUEST: "Partnership",
  REGULATORY_ACCESS_REQUEST: "Regulatory access",
  FACILITATION_REQUEST: "Facilitation",
  VENDOR_LISTING_REQUEST: "Vendor listing",
  MARKETPLACE_PURCHASE_ORDER: "Vehicle reservation",
  OFFICE_ACCESS_REQUEST: "Office access",
};

const nairobi = (iso: string | null) =>
  iso ? new Date(iso).toLocaleString("en-KE", { timeZone: "Africa/Nairobi", weekday: "short", day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" }) : "—";

type Row = {
  order_id: string;
  order_code: string;
  order_root_type: string;
  requester_user_id: string;
  placed_at: string;
  business_order_line: { line_description: string; scope_detail: Record<string, unknown> | null }[] | null;
};

export default async function OfficePage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error: officeError } = await searchParams;
  const ctx = await getActorContext();
  if (!ctx) redirect("/login");

  if (!ctx.office.admin && !ctx.office.executive) {
    return (
      <div className="max-w-2xl mx-auto trs-card p-6">
        <h1 className="font-display text-xl font-semibold text-text-primary mb-2">Operator App</h1>
        <p className="text-text-secondary text-sm">
          You are an approved TrustRide Operator. Assigned jobs, status updates, live location, proof of completion and
          earnings arrive on this surface in the next increment.
        </p>
      </div>
    );
  }

  const supabase = await createClient();
  const { data: orders } = await supabase
    .from("business_order")
    .select("order_id, order_code, order_root_type, requester_user_id, placed_at, business_order_line(line_description, scope_detail)")
    .neq("order_root_type", "SERVICE_ORDER")
    .order("placed_at", { ascending: true });
  const rows = (orders as Row[] | null) ?? [];

  const ids = rows.map((o) => o.order_id);
  const people = [...new Set(rows.map((o) => o.requester_user_id))];
  const [{ data: responses }, { data: users }] = await Promise.all([
    ids.length
      ? supabase.from("business_partnership_response").select("order_id, response_status, decision_target_at, response_due_at, escalated_at, response_notes, responded_at").in("order_id", ids)
      : Promise.resolve({ data: [] as never[] }),
    people.length
      ? supabase.from("platform_users").select("user_id, display_name").in("user_id", people)
      : Promise.resolve({ data: [] as never[] }),
  ]);
  const resp = new Map((responses ?? []).map((r) => [r.order_id, r]));
  const names = new Map((users ?? []).map((u) => [u.user_id, u.display_name]));

  const open = rows.filter((o) => ["SUBMITTED", "UNDER_REVIEW"].includes(resp.get(o.order_id)?.response_status ?? "SUBMITTED"));
  const decided = rows.filter((o) => !open.includes(o)).reverse().slice(0, 20);
  const canDecide = ctx.office.admin;

  return (
    <div className="max-w-4xl mx-auto flex flex-col gap-6">
      <div>
        <h1 className="font-display text-xl font-semibold text-text-primary">{canDecide ? "Admin Console" : "Executive Dashboard"}</h1>
        <p className="text-text-secondary text-sm mt-1">
          Actor requests awaiting TrustRide Office — decide within 2 working days, deadline 3 (Mon–Fri 05:00–22:00, Sat
          06:00–23:00; Sunday off duty). Past the deadline a request escalates; it is never declined by the clock.
        </p>
      </div>
      {officeError && <p className="rounded-lg bg-danger-bg text-danger text-sm p-2.5">{officeError}</p>}

      <section className="flex flex-col gap-3">
        <h2 className="text-[11px] font-semibold uppercase tracking-[0.2em] text-gold-dim">Awaiting decision · {open.length}</h2>
        {open.length === 0 && <p className="text-text-muted text-sm">Nothing waiting.</p>}
        {open.map((o) => {
          const r = resp.get(o.order_id);
          const overdue = r?.response_due_at && new Date(r.response_due_at) < new Date();
          return (
            <div key={o.order_id} className={`trs-card p-4 ${r?.escalated_at ? "border-danger/50" : ""}`}>
              <div className="flex flex-wrap justify-between items-start gap-2">
                <div>
                  <span className="font-display font-semibold text-text-primary">{o.order_code}</span>
                  <span className="ml-2 rounded-full border border-gold-dim/50 bg-gold/10 px-2.5 py-0.5 text-[11px] font-semibold uppercase tracking-wide text-gold-light">
                    {ROOT_LABEL[o.order_root_type] ?? o.order_root_type}
                  </span>
                  {r?.escalated_at && <span className="ml-2 text-[11px] font-semibold uppercase tracking-wide text-danger">Escalated</span>}
                </div>
                <span className="text-text-secondary text-sm">{names.get(o.requester_user_id) ?? "—"}</span>
              </div>
              <ul className="text-text-secondary text-sm mt-2 list-disc pl-5">
                {(o.business_order_line ?? []).map((l, i) => <li key={i}>{l.line_description}</li>)}
              </ul>
              <p className={`text-xs mt-2 ${overdue ? "text-danger" : "text-text-muted"}`}>
                Submitted {nairobi(o.placed_at)} · target {nairobi(r?.decision_target_at ?? null)} · deadline {nairobi(r?.response_due_at ?? null)}
              </p>
              {canDecide && (
                <form className="mt-3 flex flex-col sm:flex-row gap-2">
                  <input name="notes" placeholder="Notes to the actor (required to decline)"
                    className="trs-input flex-1 rounded-lg px-3 py-2 text-sm text-text-primary placeholder:text-text-muted" />
                  <button formAction={reviewRequest.bind(null, o.order_id, "ACCEPTED")} className="trs-btn-primary rounded-lg px-4 py-2 text-sm font-semibold">Approve</button>
                  <button formAction={reviewRequest.bind(null, o.order_id, "DECLINED")} className="trs-btn-ghost rounded-lg px-4 py-2 text-sm font-semibold">Decline</button>
                </form>
              )}
            </div>
          );
        })}
      </section>

      {decided.length > 0 && (
        <section className="flex flex-col gap-2">
          <h2 className="text-[11px] font-semibold uppercase tracking-[0.2em] text-gold-dim">Recently decided</h2>
          {decided.map((o) => {
            const r = resp.get(o.order_id);
            return (
              <div key={o.order_id} className="flex flex-wrap justify-between gap-2 text-sm border-b border-border py-2">
                <span className="text-text-primary">{o.order_code} · {ROOT_LABEL[o.order_root_type] ?? o.order_root_type} · {names.get(o.requester_user_id) ?? "—"}</span>
                <span className={r?.response_status === "ACCEPTED" ? "text-success" : "text-danger"}>
                  {r?.response_status === "ACCEPTED" ? "Approved" : "Declined"} {nairobi(r?.responded_at ?? null)}
                </span>
              </div>
            );
          })}
        </section>
      )}
    </div>
  );
}
