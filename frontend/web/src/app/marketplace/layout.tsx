import Link from "next/link";
import { redirect } from "next/navigation";
import { getActorContext } from "@/lib/trustride";
import { signOutAction } from "@/app/dashboard/actions";

// TRUSTRIDE MARKETPLACE -- external sovereign shell (TRS026-ENG011-PRESENT-003
// Sec.7.3): Marketplace_App (TrustRide's own second-hand, improved motorcycles
// and cars) and Vendor_App (approved motorcycle and car sellers). Open to any
// verified external identity that has passed the Sovereign Gate.
//
// RENDERING STRATEGY: fully dynamic -- gated on this visitor's identity.
const pill = "rounded-full border border-border bg-surface px-4 py-2 text-sm font-medium text-text-secondary hover:text-text-primary hover:border-gold-dim transition-colors";

export default async function MarketplaceLayout({ children }: { children: React.ReactNode }) {
  const ctx = await getActorContext();
  if (!ctx) redirect("/login");
  if (!ctx.profile) redirect("/register");
  if (ctx.profile.status !== "ACTIVE") redirect("/verify");

  return (
    <div className="flex flex-col flex-1">
      <header className="sticky top-0 z-10 flex items-center gap-3 px-5 py-3.5 border-b border-border bg-bg-deepest/85 backdrop-blur">
        <span className="font-display text-lg font-semibold text-text-primary flex-1">
          TrustRide <span className="text-gold-light">Marketplace</span>
        </span>
        <Link href="/verify" className="text-xs text-text-muted hover:text-text-primary transition-colors">Switch shell</Link>
        <form action={signOutAction}>
          <button type="submit" className="text-danger text-sm font-medium hover:text-danger/80 transition-colors ml-2">Sign out</button>
        </form>
      </header>
      <nav className="flex flex-wrap gap-2 px-5 pt-4">
        <Link href="/marketplace" className={pill}>Buy a vehicle</Link>
        <Link href="/marketplace/vendor" className={pill}>Sell as a vendor</Link>
      </nav>
      <div className="flex-1 mt-3 p-5">{children}</div>
    </div>
  );
}
