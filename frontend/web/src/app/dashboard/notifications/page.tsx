import { createClient } from "@/lib/supabase/server";

type Notification = {
  notification_id: string;
  title: string;
  body: string;
  read_status: string;
  delivered_at: string;
};

export default async function NotificationsPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("present_notification_inbox")
    .select("notification_id, title, body, read_status, delivered_at")
    .order("delivered_at", { ascending: false });

  const items = (data as Notification[]) ?? [];

  return (
    <div className="max-w-2xl mx-auto">
      <h1 className="text-lg font-bold text-text-primary mb-4">Notifications</h1>
      {error && <p className="rounded-lg bg-danger-bg text-danger text-sm p-2.5 mb-3">{error.message}</p>}
      {items.length === 0 && !error && <p className="text-text-muted text-center mt-10">No notifications yet.</p>}
      <div className="flex flex-col gap-2.5">
        {items.map((n) => (
          <div
            key={n.notification_id}
            className={`rounded-xl border p-3.5 ${n.read_status === "UNREAD" ? "border-gold bg-surface" : "border-border bg-surface"}`}
          >
            <div className="flex justify-between items-center">
              <span className="font-bold text-text-primary">{n.title}</span>
              {n.read_status === "UNREAD" && <span className="w-2 h-2 rounded-full bg-gold" />}
            </div>
            <p className="text-text-secondary text-sm mt-1">{n.body}</p>
            <p className="text-text-muted text-xs mt-1.5">{new Date(n.delivered_at).toLocaleString()}</p>
          </div>
        ))}
      </div>
    </div>
  );
}
