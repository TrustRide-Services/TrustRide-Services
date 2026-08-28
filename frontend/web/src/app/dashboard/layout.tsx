import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOutAction } from "./actions";

// The four USER_HUB sub-shells this app actually serves (Engine 11 v2.0.0).
// GOVERNOR_APP and INTERMEDIARY_APP have real capability-registry verbs
// (VIEW_REGISTER/RULE_ON_EXCEPTION/EMIT_GOVERNANCE_SIGNAL and
// PUBLISH_OFFER/RECEIVE_ORDER_SIGNAL/SETTLE_LAWFUL_FLOW) but no built screens
// yet -- those personas see Notifications only, honestly, rather than a
// Request Service tab that would just reject their command.
const USER_TYPE_LABEL: Record<string, string> = {
  CUSTOMER: "Customer",
  PARTNER: "Partner",
  GOVERNOR: "Governor",
  INTERMEDIARY: "Intermediary",
};
const RAISES_INTENT = new Set(["CUSTOMER", "PARTNER"]);

// RENDERING STRATEGY: fully dynamic, deliberately not split with Suspense.
// Every pixel this layout renders (nav visibility, user-type badge, display
// name) depends on the same auth+profile+actor gate that also decides
// whether to redirect away entirely -- there is no data-independent shell
// to paint before that gate resolves, so streaming it wouldn't shorten
// perceived load, only add complexity. Correctness of the gate (never
// flash protected chrome to an unverified user) outweighs the marginal
// perf a contrived split would buy here.
export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) redirect("/login");

  const { data: profile } = await supabase.from("platform_users").select("display_name").maybeSingle();
  if (!profile) redirect("/register");

  const { data: actor } = await supabase
    .from("business_actor_registration")
    .select("user_type_domain")
    .eq("registration_status", "ACTIVE")
    .limit(1)
    .maybeSingle();
  if (!actor?.user_type_domain) redirect("/verify");

  const userTypeLabel = USER_TYPE_LABEL[actor.user_type_domain] ?? actor.user_type_domain;
  const canRaiseIntent = RAISES_INTENT.has(actor.user_type_domain);

  const initial = (profile.display_name ?? "?").trim()[0]?.toUpperCase() ?? "?";

  return (
    <div className="flex flex-col flex-1">
      <header className="sticky top-0 z-10 flex items-center gap-3 px-5 py-3.5 border-b border-border bg-bg-deepest/85 backdrop-blur">
        <span className="font-display text-lg font-semibold text-text-primary flex-1">TrustRide</span>
        <span className="rounded-full border border-gold-dim/60 bg-gold/10 px-3 py-1 text-[10px] font-semibold uppercase tracking-[0.14em] text-gold-light">
          {userTypeLabel}
        </span>
        <div className="flex items-center gap-2.5 pl-1">
          <span className="w-8 h-8 rounded-full bg-gradient-to-br from-gold-light to-gold-dim text-on-gold font-display font-semibold text-sm flex items-center justify-center">
            {initial}
          </span>
          <span className="text-text-secondary text-sm hidden sm:inline">{profile.display_name}</span>
        </div>
        <form action={signOutAction}>
          <button type="submit" className="text-danger text-sm font-medium hover:text-danger/80 transition-colors ml-1">Sign out</button>
        </form>
      </header>

      <nav className="flex flex-wrap gap-2 px-5 pt-4">
        {canRaiseIntent && (
          <Link href="/dashboard/orders" className="rounded-full border border-border bg-surface px-4 py-2 text-sm font-medium text-text-secondary hover:text-text-primary hover:border-gold-dim transition-colors">
            My Orders
          </Link>
        )}
        {canRaiseIntent && (
          <Link href="/dashboard/raise-intent" className="rounded-full border border-border bg-surface px-4 py-2 text-sm font-medium text-text-secondary hover:text-text-primary hover:border-gold-dim transition-colors">
            Request Service
          </Link>
        )}
        <Link href="/dashboard/notifications" className="rounded-full border border-border bg-surface px-4 py-2 text-sm font-medium text-text-secondary hover:text-text-primary hover:border-gold-dim transition-colors">
          Notifications
        </Link>
      </nav>

      <div className="flex-1 mt-3 p-5">{children}</div>
    </div>
  );
}
