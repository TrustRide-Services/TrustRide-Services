import Link from "next/link";
import { redirect } from "next/navigation";
import { gateContext, officeAccess, officeSub, project } from "@/lib/trustride";
import CommandForm from "@/components/CommandForm";
import AutoRefresh from "@/components/AutoRefresh";
import { Badge, Card, Empty, ErrorNote, Kes, Page, inputClass, when } from "@/components/ui";

type Row = { order_id: string; order_code: string; root: string; service_name: string; status: string; status_reason: string | null; placed_at: string;
  customer: string; operator: string | null; waiting_since: string | null; attempts: number; quote: { total_kes: number } | null;
  payment: { status: string; amount_kes: number; rail: string } | null; actions: Record<string, boolean> };

// Live orders and exceptions (projection OFFICE_ORDERS), with intervention:
// cancel, reassign to another worker, or close as failed; record a bank
// transfer for purchases above the M-Pesa limit.
export default async function OfficeOrders({ searchParams }: { searchParams: Promise<{ filter?: string }> }) {
  const { filter = "LIVE" } = await searchParams;
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  const admin = officeAccess(ctx).admin;
  const { data, error } = await project<{ orders: Row[] }>(officeSub(ctx), "OFFICE_ORDERS", { filter });
  return (
    <Page title="Orders" intro="Exceptions first: orders waiting for a worker, failed or expired.">
      <AutoRefresh seconds={20} />
      <div className="flex gap-2">
        {["LIVE", "EXCEPTIONS", "ALL"].map((f) => (
          <Link key={f} href={`/office/orders?filter=${f}`} className={`rounded-full border px-4 py-1.5 text-sm ${filter === f ? "border-gold-dim bg-gold/10 text-text-primary" : "border-border text-text-secondary"}`}>
            {f.toLowerCase()}</Link>
        ))}
      </div>
      <ErrorNote error={error} />
      {!data?.orders.length && <Empty>No orders.</Empty>}
      <div className="flex flex-col gap-2">
        {data?.orders.map((o) => (
          <Card key={o.order_id} tone={["WAITING", "FAILED"].includes(o.status) ? "danger" : undefined} className="flex flex-col gap-2">
            <div className="flex flex-wrap justify-between gap-2">
              <span className="text-text-primary font-semibold text-sm">{o.order_code} · {o.service_name}</span>
              <Badge status={o.status} />
            </div>
            <p className="text-xs text-text-muted">{o.customer} · {when(o.placed_at)}{o.operator ? ` · operator ${o.operator}` : ""}
              {o.waiting_since ? ` · waiting since ${when(o.waiting_since)} (${o.attempts} attempts)` : ""}
              {o.quote ? <> · <Kes value={o.quote.total_kes} /></> : null}{o.payment ? ` · payment ${o.payment.status.toLowerCase().replace("_", " ")}` : ""}</p>
            {o.status_reason && <p className="text-xs text-text-secondary">{o.status_reason}</p>}
            {admin && !["SETTLED", "REVIEWED", "CLOSED", "CANCELLED", "EXPIRED", "FAILED", "DECLINED"].includes(o.status) && (
              <div className="flex flex-wrap gap-2 items-end">
                {o.root === "SERVICE_ORDER" && (
                  <CommandForm sub="ADMIN_CONSOLE" command="INTERVENE_ORDER" fixed={{ order_id: o.order_id, action: "REASSIGN" }} submit="Reassign" variant="ghost" inline>
                    <input name="reason" required placeholder="Why" className={`${inputClass} w-44`} /></CommandForm>
                )}
                {o.root === "SERVICE_ORDER" && (
                  <CommandForm sub="ADMIN_CONSOLE" command="INTERVENE_ORDER" fixed={{ order_id: o.order_id, action: "CANCEL" }} submit="Cancel" variant="danger" inline confirm="Cancel this order?">
                    <input name="reason" required placeholder="Why" className={`${inputClass} w-44`} /></CommandForm>
                )}
                {o.payment && o.payment.rail === "BANK_TRANSFER" && o.payment.status !== "RECEIPT_GENERATED" && (
                  <CommandForm sub="ADMIN_CONSOLE" command="RECORD_BANK_PAYMENT" fixed={{ order_id: o.order_id, amount_kes: o.payment.amount_kes }} submit="Record bank transfer" inline>
                    <input name="bank_reference" required placeholder="Bank reference" className={`${inputClass} w-44`} /></CommandForm>
                )}
              </div>
            )}
          </Card>
        ))}
      </div>
    </Page>
  );
}
