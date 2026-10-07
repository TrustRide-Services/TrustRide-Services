import { redirect } from "next/navigation";
import NotificationList from "@/components/NotificationList";
import { businessSub, gateContext } from "@/lib/trustride";

export default async function BusinessNotifications() {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  return <NotificationList sub={businessSub(ctx)} />;
}
