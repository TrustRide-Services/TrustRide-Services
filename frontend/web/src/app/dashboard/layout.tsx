import { redirect } from "next/navigation";
import ShellFrame from "@/components/ShellFrame";
import { envStatus, gateContext } from "@/lib/trustride";

// TRUSTRIDE BUSINESS -- the external sovereign shell (TRS026-ENG011-PRESENT-003
// Sec.7.2): Customer_App, Partner_App, Governor_App, Intermediary_App. Every
// page below reads through Engine 11's lawful projections.
//
// RENDERING STRATEGY: fully dynamic -- per-person surfaces.
export default async function BusinessLayout({ children }: { children: React.ReactNode }) {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  if (!ctx.registered) redirect("/register");
  if (ctx.identity_status !== "ACTIVE") redirect("/verify");

  const has = (env: "CUSTOMER" | "PARTNER" | "GOVERNOR" | "INTERMEDIARY") =>
    !!envStatus(ctx, env) || ctx.represented_entities.some((e) => e.environments.some((x) => x.domain === env));
  if (!has("CUSTOMER") && !has("PARTNER") && !has("GOVERNOR") && !has("INTERMEDIARY")) redirect("/verify");

  const nav = [
    ...(has("CUSTOMER") ? [{ href: "/dashboard", label: "Home" }, { href: "/dashboard/book", label: "Book a service" }, { href: "/dashboard/orders", label: "My orders" }] : []),
    ...(has("PARTNER") ? [{ href: "/dashboard/partner", label: "Partner" }] : []),
    ...(has("GOVERNOR") ? [{ href: "/dashboard/governor", label: "Oversight" }] : []),
    ...(has("INTERMEDIARY") ? [{ href: "/dashboard/intermediary", label: "Facilitation" }] : []),
    { href: "/dashboard/support", label: "Support" },
    { href: "/dashboard/notifications", label: "Notifications" },
    { href: "/dashboard/profile", label: "Profile" },
  ];

  return <ShellFrame shell="TrustRide" accent="Business" nav={nav} ctx={ctx} allowActing>{children}</ShellFrame>;
}
