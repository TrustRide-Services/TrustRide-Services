import { redirect } from "next/navigation";
import NotificationList from "@/components/NotificationList";
import { gateContext, officeAccess, officeSub } from "@/lib/trustride";

export default async function OfficeNotifications() {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  const o = officeAccess(ctx);
  return <NotificationList sub={o.admin || o.executive ? officeSub(ctx) : "OPERATOR_APP"} />;
}
