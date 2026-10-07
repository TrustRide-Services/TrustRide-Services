import { project } from "@/lib/trustride";
import type { SubShell } from "@/lib/shells";
import CommandForm from "@/components/CommandForm";
import AutoRefresh from "@/components/AutoRefresh";
import { Badge, Card, Empty, ErrorNote, KV, Kes, Notice, Page, Section, inputClass, labelClass, when } from "@/components/ui";

type Detail = {
  order_id: string; order_code: string; root: string; service_name: string; status: string; stage: string; status_reason: string | null;
  placed_at: string; dispatch_mode: string; requested_start_at: string | null; title: string;
  quote: { quote_id: string; total_kes: number; state: string; expires_at: string } | null;
  payment: { status: string; amount_kes: number; rail: string; receipt_code: string | null } | null;
  actions: Record<string, boolean>;
  lines: { seq: number; description: string; from: string; to: string; distance_km: string | null; billed_hours: string | null; price_kes: string | null; fare_kes: number | null; job_status: string | null }[];
  operator: { first_name: string; resource_type: string; vehicle: string | null; rating: number | null; rating_count: number } | null;
  tracking: { active: boolean; status: string; resource_type: string; resource_id: string | null; eta: string | null; lat: number | null; lon: number | null; updated_at: string } | null;
  payments: { status: string; amount_kes: number; adapter: string; failure_reason: string | null; receipt: string | null; at: string }[] | null;
  review: { rating: number; comment: string | null } | null;
  timeline: { title: string; body: string; at: string }[] | null;
  request: { status: string; notes: string | null; deadline: string } | null;
};

const LIVE = ["PLACED", "VALIDATED", "WAITING", "SCHEDULED", "QUOTED", "JOB_CREATED", "DISPATCHED", "EXECUTING", "COMPLETED", "AWAITING_PAYMENT"];

// One order as its customer may see it (projection ORDER_DETAIL), with every
// action the order allows right now.
export default async function OrderDetail({ sub, orderId }: { sub: SubShell; orderId: string }) {
  const { data: o, error } = await project<Detail>(sub, "ORDER_DETAIL", { order_id: orderId });
  if (!o) return <Page title="Order"><ErrorNote error={error} /></Page>;
  const a = o.actions;
  return (
    <Page title={o.service_name} intro={<>{o.order_code} · placed {when(o.placed_at)}{o.dispatch_mode === "SCHEDULED" && <> · scheduled for {when(o.requested_start_at)}</>}</>}
      actions={<Badge status={o.status} />}>
      {LIVE.includes(o.status) && <AutoRefresh seconds={o.tracking ? 8 : 15} />}
      {o.status_reason && ["CANCELLED", "EXPIRED", "FAILED", "DECLINED", "WAITING"].includes(o.status) && <Notice>{o.status_reason}</Notice>}

      {a.accept_quote && o.quote && (
        <Card tone="gold">
          <p className="text-text-primary font-semibold">Your fare: <Kes value={o.quote.total_kes} /></p>
          <p className="text-text-secondary text-sm mb-3">Confirm before {when(o.quote.expires_at)}. Nobody is dispatched until you accept; you pay by M-Pesa after the service.</p>
          <div className="flex flex-wrap gap-2">
            <CommandForm sub={sub} command="ACCEPT_QUOTATION" fixed={{ quote_id: o.quote.quote_id }} submit="Accept fare" success="Fare confirmed — your operator is being told." />
            <CommandForm sub={sub} command="DECLINE_QUOTATION" fixed={{ quote_id: o.quote.quote_id }} submit="Decline" variant="ghost" confirm="Decline this fare and cancel the order?" />
          </div>
        </Card>
      )}

      {o.tracking && (
        <Section title="Live tracking">
          <Card>
            <KV items={[
              ["Status", <Badge key="s" status={o.tracking.status} />],
              ["Vehicle", `${o.tracking.resource_type}${o.tracking.resource_id ? " · " + o.tracking.resource_id : ""}`],
              ["ETA", o.tracking.eta ? when(o.tracking.eta) : "—"],
              ["Position", o.tracking.lat != null ? (
                <a key="p" className="text-gold-light underline" target="_blank" rel="noreferrer"
                  href={`https://www.google.com/maps/search/?api=1&query=${o.tracking.lat},${o.tracking.lon}`}>
                  {Number(o.tracking.lat).toFixed(5)}, {Number(o.tracking.lon).toFixed(5)}
                </a>) : "Waiting for the first position"],
              ["Updated", when(o.tracking.updated_at)],
            ]} />
          </Card>
        </Section>
      )}

      {o.operator && (
        <Section title="Your operator">
          <Card>
            <KV items={[
              ["Name", o.operator.first_name],
              ["Service", o.operator.resource_type],
              ...(o.operator.vehicle ? [["Vehicle", o.operator.vehicle] as [string, React.ReactNode]] : []),
              ["Rating", o.operator.rating ? `${o.operator.rating} ★ (${o.operator.rating_count})` : "New"],
            ]} />
          </Card>
        </Section>
      )}

      <Section title={o.root === "MARKETPLACE_PURCHASE_ORDER" ? "Vehicle" : `Stops · ${o.lines.length}`}>
        <div className="flex flex-col gap-2">
          {o.lines.map((l) => (
            <Card key={l.seq} className="flex flex-wrap justify-between gap-2">
              <div>
                <p className="text-text-primary text-sm font-semibold">{l.description}</p>
                {l.from && l.to && l.from !== l.to && <p className="text-text-muted text-xs">{l.from} → {l.to}{l.distance_km ? ` · ${Number(l.distance_km).toFixed(1)} km` : ""}</p>}
                {l.billed_hours && <p className="text-text-muted text-xs">{l.from} · {l.billed_hours} hours</p>}
              </div>
              <div className="text-right text-sm">
                {l.fare_kes != null && <p className="text-text-primary"><Kes value={l.fare_kes} /></p>}
                {l.price_kes && <p className="text-text-primary"><Kes value={l.price_kes} /></p>}
                {l.job_status && <Badge status={l.job_status} />}
              </div>
            </Card>
          ))}
        </div>
      </Section>

      {o.request && (
        <Notice>Reservation status: {o.request.status.toLowerCase().replace("_", " ")}{o.request.notes ? ` — ${o.request.notes}` : ""}. Decision deadline {when(o.request.deadline)}.</Notice>
      )}

      {(o.payment || (o.payments && o.payments.length > 0)) && (
        <Section title="Payment">
          <Card className="flex flex-col gap-3">
            {o.payment && (
              <KV items={[["Amount", <Kes key="k" value={o.payment.amount_kes} />], ["Status", <Badge key="b" status={o.payment.status} />],
                ["Method", o.payment.rail === "BANK_TRANSFER" ? "Bank transfer (TrustRide Office sends the details)" : "M-Pesa"],
                ...(o.payment.receipt_code ? [["Receipt", o.payment.receipt_code] as [string, React.ReactNode]] : [])]} />
            )}
            {o.payments?.map((p, i) => (
              <p key={i} className="text-xs text-text-muted">{when(p.at)} · <Kes value={p.amount_kes} /> · {p.status.toLowerCase().replace("_", " ")}
                {p.failure_reason ? ` (${p.failure_reason.toLowerCase().replaceAll("_", " ")})` : ""}{p.receipt ? ` · ${p.receipt}` : ""}</p>
            ))}
            <div className="flex flex-wrap gap-2">
              {a.confirm_simulated_payment && (
                <>
                  <CommandForm sub={sub} command="CONFIRM_SIMULATED_PAYMENT" fixed={{ order_id: o.order_id }} submit="Approve (staging M-Pesa simulator)" success="Payment confirmed." />
                  <CommandForm sub={sub} command="CONFIRM_SIMULATED_PAYMENT" fixed={{ order_id: o.order_id, success: false }} submit="Decline prompt" variant="ghost" />
                </>
              )}
              {a.retry_payment && <CommandForm sub={sub} command="RETRY_PAYMENT" fixed={{ order_id: o.order_id }} submit="Pay again with M-Pesa" success="A new M-Pesa prompt is on its way to your phone." />}
            </div>
          </Card>
        </Section>
      )}

      {(a.review || o.review) && (
        <Section title="Your review">
          {o.review ? <Card><p className="text-sm text-text-primary">{"★".repeat(o.review.rating)}{"☆".repeat(5 - o.review.rating)} {o.review.comment}</p></Card> : (
            <Card>
              <CommandForm sub={sub} command="SUBMIT_REVIEW" fixed={{ order_id: o.order_id }} submit="Submit review" success="Thank you." inline>
                <label className={labelClass}>Rating
                  <select name="rating:n" defaultValue="5" className={inputClass}>{[5, 4, 3, 2, 1].map((r) => <option key={r} value={r}>{r} ★</option>)}</select>
                </label>
                <label className={`${labelClass} flex-1 min-w-48`}>Comment<input name="comment" className={inputClass} /></label>
              </CommandForm>
            </Card>
          )}
        </Section>
      )}

      <div className="grid md:grid-cols-2 gap-4">
        {a.cancel && (
          <Section title="Cancel">
            <Card>
              <CommandForm sub={sub} command="CANCEL_ORDER" fixed={{ order_id: o.order_id }} submit="Cancel order" variant="danger" confirm="Cancel this order?" success="Cancelled.">
                <label className={labelClass}>Reason (optional)<input name="reason" className={inputClass} /></label>
              </CommandForm>
            </Card>
          </Section>
        )}
        <Section title="Need help?">
          <Card>
            <CommandForm sub={sub} command="OPEN_SUPPORT_CASE" fixed={{ order_id: o.order_id }} submit="Contact support" success="Support case opened — see Support.">
              <label className={labelClass}>Topic
                <select name="category" className={inputClass}>
                  <option value="ORDER_ISSUE">Problem with this order</option><option value="PAYMENT">Payment</option>
                  <option value="LOST_ITEM">Lost item</option><option value="SAFETY">Safety concern</option>
                  {o.root === "MARKETPLACE_PURCHASE_ORDER" && <option value="MARKETPLACE">Vehicle purchase</option>}
                </select>
              </label>
              <label className={labelClass}>Subject<input name="subject" required className={inputClass} /></label>
              <label className={labelClass}>What happened<textarea name="body" required rows={3} className={inputClass} /></label>
            </CommandForm>
          </Card>
        </Section>
      </div>

      <Section title="Timeline">
        {!o.timeline?.length && <Empty>No updates yet.</Empty>}
        <ol className="flex flex-col gap-2">
          {o.timeline?.map((t, i) => (
            <li key={i} className="text-sm border-l-2 border-gold-dim/50 pl-3">
              <span className="text-text-primary font-semibold">{t.title}</span> <span className="text-text-muted text-xs">{when(t.at)}</span>
              <p className="text-text-secondary">{t.body}</p>
            </li>
          ))}
        </ol>
      </Section>
    </Page>
  );
}
