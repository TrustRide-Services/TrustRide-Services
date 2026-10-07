import { redirect } from "next/navigation";
import ShellFrame from "@/components/ShellFrame";
import { gateContext } from "@/lib/trustride";

// TRUSTRIDE MARKETPLACE -- motorcycles and cars, from TrustRide's own stock
// and approved vendors (Marketplace_App, Vendor_App). Never dispatched.
//
// RENDERING STRATEGY: fully dynamic -- per-person surfaces.
export default async function MarketplaceLayout({ children }: { children: React.ReactNode }) {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  if (!ctx.registered) redirect("/register");
  if (ctx.identity_status !== "ACTIVE") redirect("/verify");
  const nav = [
    { href: "/marketplace", label: "Vehicles for sale" },
    { href: "/marketplace/purchases", label: "My purchases" },
    { href: "/marketplace/vendor", label: "Sell as a vendor" },
    { href: "/marketplace/support", label: "Support" },
    { href: "/marketplace/notifications", label: "Notifications" },
    { href: "/marketplace/profile", label: "Profile" },
  ];
  return <ShellFrame shell="TrustRide" accent="Marketplace" nav={nav} ctx={ctx} allowActing>{children}</ShellFrame>;
}
