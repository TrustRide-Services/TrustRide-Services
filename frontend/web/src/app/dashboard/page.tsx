import Link from "next/link";
import { redirect } from "next/navigation";
import { envStatus, gateContext, project } from "@/lib/trustride";
import { Badge, Card, Empty, ErrorNote, Kes, Notice, Page, Section, when } from "@/components/ui";
import AutoRefresh from "@/components/AutoRefresh";

type Summary = { order_id: string; order_code: string; service_name: string; status: string; title: string; updated_at: string;
  quote: { total_kes: number; state: string; expires_at: string } | null };
type Home = { display_name: string; phone_verified: boolean; active_orders: Summary[]; completed_count: number; unread: number; open_cases: number };

// Customer_App home (projection CUSTOMER_HOME).
export default async function BusinessHome() {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  if (!envStatus(ctx, "CUSTOMER")) {
    if (envStatus(ctx, "PARTNER")) redirect("/dashboard/partner");
    if (envStatus(ctx, "GOVERNOR")) redirect("/dashboard/governor");
    if (envStatus(ctx, "INTERMEDIARY")) redirect("/dashboard/intermediary");
  }
  const { data, error } = await project<Home>("CUSTOMER_APP", "CUSTOMER_HOME");
  return (
    <Page title={`Karibu, ${data?.display_name?.split(" ")[0] ?? ""}`} intro="Book transport, delivery, courier and executive-assistant services; follow every order to its receipt."
      actions={<Link href="/dashboard/book" className="trs-btn-primary rounded-xl px-5 py-2.5 text-sm font-semibold">Book a service</Link>}>
      <ErrorNote error={error} />
      {data && !data.phone_verified && (
        <Notice>
          Add and verify your phone number before booking — it is the M-Pesa number your orders are paid from and how we reach you.{" "}
          <Link href="/dashboard/profile" className="text-gold-light underline">Verify your phone</Link>
        </Notice>
      )}
      {data && data.active_orders.length > 0 && <AutoRefresh seconds={15} />}
      <Section title={`In progress · ${data?.active_orders.length ?? 0}`}>
        {data?.active_orders.length === 0 && <Empty>Nothing in progress. Completed orders: {data.completed_count}.</Empty>}
        <div className="grid sm:grid-cols-2 gap-3">
          {data?.active_orders.map((o) => (
            <Link key={o.order_id} href={`/dashboard/orders/${o.order_id}`}>
              <Card tone={o.status === "QUOTED" ? "gold" : undefined} className="hover:border-gold-dim transition-colors">
                <div className="flex justify-between items-start gap-2">
                  <div>
                    <p className="text-text-primary font-semibold">{o.service_name}</p>
                    <p className="text-text-muted text-xs">{o.order_code} · updated {when(o.updated_at)}</p>
                  </div>
                  <Badge status={o.status} />
                </div>
                {o.status === "QUOTED" && o.quote && (
                  <p className="text-sm text-gold-light mt-2">Fare <Kes value={o.quote.total_kes} /> — confirm before {when(o.quote.expires_at)}</p>
                )}
              </Card>
            </Link>
          ))}
        </div>
      </Section>
      <div className="grid sm:grid-cols-3 gap-3">
        <Card><p className="text-text-muted text-xs">Unread notifications</p><p className="text-2xl font-display text-text-primary">{data?.unread ?? 0}</p></Card>
        <Card><p className="text-text-muted text-xs">Open support cases</p><p className="text-2xl font-display text-text-primary">{data?.open_cases ?? 0}</p></Card>
        <Card><p className="text-text-muted text-xs">Completed orders</p><p className="text-2xl font-display text-text-primary">{data?.completed_count ?? 0}</p></Card>
      </div>
    </Page>
  );
}
