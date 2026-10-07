import { project } from "@/lib/trustride";
import type { SubShell } from "@/lib/shells";
import { markNotificationsReadAction } from "@/app/actions";
import { Card, Empty, ErrorNote, Page, when } from "@/components/ui";

type Item = { notification_id: string; title: string; body: string; category: string; read_status: string; delivered_at: string; critical: boolean };

// Inbox (projection NOTIFICATIONS). The same messages also reach the person
// by SMS/WhatsApp through Engine 6, per their preferences.
export default async function NotificationList({ sub }: { sub: SubShell }) {
  const { data, error } = await project<{ items: Item[]; unread: number }>(sub, "NOTIFICATIONS", { limit: 100 });
  return (
    <Page title="Notifications" intro={`${data?.unread ?? 0} unread`}
      actions={data && data.unread > 0 ? (
        <form action={markNotificationsReadAction}><input type="hidden" name="sub" value={sub} />
          <button className="trs-btn-ghost rounded-lg px-4 py-2 text-sm font-semibold">Mark all read</button></form>) : undefined}>
      <ErrorNote error={error} />
      {data?.items.length === 0 && <Empty>Nothing yet.</Empty>}
      <div className="flex flex-col gap-2">
        {data?.items.map((n) => (
          <Card key={n.notification_id} tone={n.critical && n.read_status === "UNREAD" ? "gold" : undefined}>
            <div className="flex justify-between gap-3">
              <p className={`text-sm font-semibold ${n.read_status === "UNREAD" ? "text-text-primary" : "text-text-secondary"}`}>{n.title}</p>
              <span className="text-text-muted text-xs shrink-0">{when(n.delivered_at)}</span>
            </div>
            <p className="text-text-secondary text-sm">{n.body}</p>
          </Card>
        ))}
      </div>
    </Page>
  );
}
