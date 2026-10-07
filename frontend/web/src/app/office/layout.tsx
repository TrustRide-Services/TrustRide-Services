import { redirect } from "next/navigation";
import ShellFrame from "@/components/ShellFrame";
import { gateContext, officeAccess } from "@/lib/trustride";

// TRUSTRIDE OFFICE -- internal staff only (Operator App, Admin Console,
// Executive Dashboard). The database opens each surface only for its role.
//
// RENDERING STRATEGY: fully dynamic -- role-gated live operations.
export default async function OfficeLayout({ children }: { children: React.ReactNode }) {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  if (!ctx.registered || ctx.identity_status !== "ACTIVE") redirect("/verify");
  const o = officeAccess(ctx);
  if (!o.admin && !o.executive && !o.operator) redirect("/verify");
  const nav = [
    ...(o.admin || o.executive ? [{ href: "/office", label: "Overview" }, { href: "/office/orders", label: "Orders" },
      { href: "/office/requests", label: "Requests" }, { href: "/office/resources", label: "Resources" }, { href: "/office/tracking", label: "Tracking" },
      { href: "/office/marketplace", label: "Marketplace" }, { href: "/office/support", label: "Support" }] : []),
    ...(o.admin ? [{ href: "/office/users", label: "Users & roles" }, { href: "/office/integrations", label: "Integrations" }] : []),
    ...(o.admin || o.executive ? [{ href: "/office/health", label: "Health" }] : []),
    ...(o.executive ? [{ href: "/office/executive", label: "Executive" }] : []),
    ...(o.operator ? [{ href: "/office/operator", label: "Operator App" }] : []),
    { href: "/office/notifications", label: "Notifications" },
  ];
  return <ShellFrame shell="TrustRide" accent="Office" nav={nav} ctx={ctx}>{children}</ShellFrame>;
}
