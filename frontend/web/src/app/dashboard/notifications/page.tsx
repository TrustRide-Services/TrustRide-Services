import { Suspense } from "react";
import { createClient } from "@/lib/supabase/server";

type Notification = {
  notification_id: string;
  title: string;
  body: string;
  read_status: string;
  delivered_at: string;
};

async function NotificationsList() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("present_notification_inbox")
    .select("notification_id, title, body, read_status, delivered_at")
    .order("delivered_at", { ascending: false });

  const items = (data as Notification[]) ?? [];

  return (
    <>
      {error && <p className="rounded-lg bg-danger-bg text-danger text-sm p-2.5 mb-3">{error.message}</p>}
      {items.length === 0 && !error && <p className="text-text-muted text-center mt-10">No notifications yet.</p>}
      <div className="flex flex-col gap-3">
        {items.map((n) => (
          <div
            key={n.notification_id}
            className={`trs-card p-4 ${n.read_status === "UNREAD" ? "border-gold-dim/50" : ""}`}
          >
            <div className="flex justify-between items-center gap-3">
              <span className="font-display font-semibold text-text-primary">{n.title}</span>
              {n.read_status === "UNREAD" && <span className="shrink-0 w-2 h-2 rounded-full bg-gold shadow-[0_0_8px_var(--gold)]" />}
            </div>
            <p className="text-text-secondary text-sm mt-1.5">{n.body}</p>
            <p className="text-text-muted text-xs mt-2">{new Date(n.delivered_at).toLocaleString()}</p>
          </div>
        ))}
      </div>
    </>
  );
}

// RENDERING STRATEGY: hybrid, same shape as dashboard/orders -- static
// heading shell, Suspense-streamed per-user list. Real-time delivery (a
// live badge count, a toast on a fresh signal) belongs to a future
// client-side subscription layered on top of this shell, not a reason to
// make the whole page a client component today.
export default function NotificationsPage() {
  return (
    <div className="max-w-2xl mx-auto">
      <h1 className="font-display text-xl font-semibold text-text-primary mb-5">Notifications</h1>
      <Suspense fallback={<p className="text-text-muted text-center mt-10">Loading notifications…</p>}>
        <NotificationsList />
      </Suspense>
    </div>
  );
}
