import Link from "next/link";
import { redirect } from "next/navigation";
import { getActorContext } from "@/lib/trustride";
import { signOutAction } from "@/app/dashboard/actions";

// TRUSTRIDE OFFICE -- the internal sovereign shell (TRS026-ENG011-PRESENT-003
// Sec.7.1): Admin_Console, Operator_App, Executive_Dashboard. TrustRide staff
// only; external identities never reach it (the database refuses to open an
// Office session for them regardless of this gate).
//
// RENDERING STRATEGY: fully dynamic -- every view is permission-gated and
// per-person; correctness and freshness over static performance.
export default async function OfficeLayout({ children }: { children: React.ReactNode }) {
  const ctx = await getActorContext();
  if (!ctx) redirect("/login");
  if (!ctx.isStaff) redirect("/verify");

  const surfaces = [
    ctx.office.admin && "Admin Console",
    ctx.office.executive && "Executive Dashboard",
    ctx.office.operator && "Operator App",
  ].filter(Boolean);

  return (
    <div className="flex flex-col flex-1">
      <header className="sticky top-0 z-10 flex items-center gap-3 px-5 py-3.5 border-b border-border bg-bg-deepest/85 backdrop-blur">
        <span className="font-display text-lg font-semibold text-text-primary flex-1">
          TrustRide <span className="text-gold-light">Office</span>
        </span>
        <span className="hidden sm:inline rounded-full border border-gold-dim/60 bg-gold/10 px-3 py-1 text-[10px] font-semibold uppercase tracking-[0.14em] text-gold-light">
          {ctx.isFounder ? "Founder" : surfaces.join(" · ")}
        </span>
        <Link href="/verify" className="text-xs text-text-muted hover:text-text-primary transition-colors">Switch shell</Link>
        <form action={signOutAction}>
          <button type="submit" className="text-danger text-sm font-medium hover:text-danger/80 transition-colors ml-2">Sign out</button>
        </form>
      </header>
      <div className="flex-1 p-5">{children}</div>
    </div>
  );
}
