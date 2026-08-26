import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOutAction } from "./actions";

const USER_TYPE_LABEL: Record<string, string> = {
  CUSTOMER: "Customer",
  PARTNER: "Partner",
  OPERATOR: "Operator",
};

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
  const isOperator = actor.user_type_domain === "OPERATOR";

  return (
    <div className="flex flex-col flex-1 bg-bg-deepest">
      <header className="flex items-center gap-3 px-4 py-4 border-b border-border">
        <span className="text-lg font-bold text-text-primary flex-1">TrustRide</span>
        <span className="rounded-full bg-surface-elevated px-2.5 py-1 text-[11px] font-bold uppercase tracking-wide text-gold-light">
          {userTypeLabel}
        </span>
        <span className="text-text-secondary">{profile.display_name}</span>
        <form action={signOutAction}>
          <button type="submit" className="text-danger">Sign out</button>
        </form>
      </header>

      <nav className="flex flex-wrap gap-2 px-3 pt-2.5">
        {!isOperator && (
          <Link href="/dashboard/orders" className="rounded-full bg-surface px-3.5 py-2 text-sm font-semibold text-text-secondary">
            My Orders
          </Link>
        )}
        {!isOperator && (
          <Link href="/dashboard/raise-intent" className="rounded-full bg-surface px-3.5 py-2 text-sm font-semibold text-text-secondary">
            Request Service
          </Link>
        )}
        <Link href="/dashboard/notifications" className="rounded-full bg-surface px-3.5 py-2 text-sm font-semibold text-text-secondary">
          Notifications
        </Link>
      </nav>

      <div className="flex-1 mt-2 p-4">{children}</div>
    </div>
  );
}
