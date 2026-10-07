import Link from "next/link";
import { project } from "@/lib/trustride";
import type { SubShell } from "@/lib/shells";
import { Badge, Card, Empty, ErrorNote, Kes, Page, when } from "@/components/ui";

type Summary = { order_id: string; order_code: string; service_name: string; title: string; status: string; placed_at: string;
  quote: { total_kes: number } | null; payment: { amount_kes: number; receipt_code: string | null } | null; actions: Record<string, boolean> };

// My orders / my purchases (projection MY_ORDERS).
export default async function OrderList({ sub, scope, base, title }: { sub: SubShell; scope: "SERVICE" | "PURCHASE"; base: string; title: string }) {
  const { data, error } = await project<{ orders: Summary[] }>(sub, "MY_ORDERS", { scope });
  return (
    <Page title={title}>
      <ErrorNote error={error} />
      {data?.orders.length === 0 && <Empty>Nothing yet.</Empty>}
      <div className="flex flex-col gap-2">
        {data?.orders.map((o) => (
          <Link key={o.order_id} href={`${base}/${o.order_id}`}>
            <Card tone={o.actions.accept_quote || o.actions.retry_payment ? "gold" : undefined} className="flex flex-wrap justify-between items-center gap-3 hover:border-gold-dim transition-colors">
              <div>
                <p className="text-text-primary font-semibold text-sm">{scope === "PURCHASE" ? o.title : o.service_name}</p>
                <p className="text-text-muted text-xs">{o.order_code} · {when(o.placed_at)}</p>
              </div>
              <div className="flex items-center gap-3 text-sm">
                {(o.payment?.amount_kes ?? o.quote?.total_kes) != null && <Kes value={o.payment?.amount_kes ?? o.quote?.total_kes} />}
                {o.actions.accept_quote && <span className="text-gold-light text-xs">Confirm fare</span>}
                {o.actions.retry_payment && <span className="text-danger text-xs">Payment needed</span>}
                <Badge status={o.status} />
              </div>
            </Card>
          </Link>
        ))}
      </div>
    </Page>
  );
}
