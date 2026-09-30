import Link from "next/link";
import { redirect } from "next/navigation";
import { getActorContext, type Environment } from "@/lib/trustride";
import { signOutAction } from "./actions";

// TRUSTRIDE BUSINESS -- the external sovereign shell (TRS026-ENG011-PRESENT-003
// Sec.7.2): Customer_App, Partner_App, Governor_App, Intermediary_App. The nav
// shows each surface the person holds -- Customers get the catalogue and their
// orders; Partners, Governors and Intermediaries get their request surface,
// open even while awaiting approval so they can submit and follow it.
//
// RENDERING STRATEGY: fully dynamic -- every link depends on this person's own
// registrations, and the same gate decides whether to redirect away.
const REQUEST_ENVS: { env: Environment; label: string }[] = [
  { env: "PARTNER", label: "Partnership" },
  { env: "GOVERNOR", label: "Regulatory access" },
  { env: "INTERMEDIARY", label: "Facilitation" },
];

const pill = "rounded-full border border-border bg-surface px-4 py-2 text-sm font-medium text-text-secondary hover:text-text-primary hover:border-gold-dim transition-colors";

export default async function BusinessLayout({ children }: { children: React.ReactNode }) {
  const ctx = await getActorContext();
  if (!ctx) redirect("/login");
  if (!ctx.profile) redirect("/register");

  const isCustomer = ctx.envStatus.get("CUSTOMER") === "ACTIVE";
  const requestEnvs = REQUEST_ENVS.filter((r) => ctx.envStatus.has(r.env));
  if (!isCustomer && requestEnvs.length === 0) redirect("/verify");

  const initial = (ctx.profile.display_name ?? "?").trim()[0]?.toUpperCase() ?? "?";

  return (
    <div className="flex flex-col flex-1">
      <header className="sticky top-0 z-10 flex items-center gap-3 px-5 py-3.5 border-b border-border bg-bg-deepest/85 backdrop-blur">
        <span className="font-display text-lg font-semibold text-text-primary flex-1">
          TrustRide <span className="text-gold-light">Business</span>
        </span>
        <Link href="/verify" className="text-xs text-text-muted hover:text-text-primary transition-colors">Switch shell</Link>
        <div className="flex items-center gap-2.5 pl-1">
          <span className="w-8 h-8 rounded-full bg-gradient-to-br from-gold-light to-gold-dim text-on-gold font-display font-semibold text-sm flex items-center justify-center">
            {initial}
          </span>
          <span className="text-text-secondary text-sm hidden sm:inline">{ctx.profile.display_name}</span>
        </div>
        <form action={signOutAction}>
          <button type="submit" className="text-danger text-sm font-medium hover:text-danger/80 transition-colors ml-1">Sign out</button>
        </form>
      </header>

      <nav className="flex flex-wrap gap-2 px-5 pt-4">
        {isCustomer && <Link href="/dashboard/raise-intent" className={pill}>Service Catalogue</Link>}
        {isCustomer && <Link href="/dashboard/orders" className={pill}>My Orders</Link>}
        {requestEnvs.map((r) => (
          <Link key={r.env} href={`/dashboard/requests?as=${r.env}`} className={pill}>{r.label}</Link>
        ))}
        <Link href="/dashboard/notifications" className={pill}>Notifications</Link>
      </nav>

      <div className="flex-1 mt-3 p-5">{children}</div>
    </div>
  );
}
