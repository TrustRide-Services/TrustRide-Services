import Link from "next/link";
import { cookies } from "next/headers";
import { signOutAction, setActingIdentityAction } from "@/app/actions";
import type { GateContext } from "@/lib/trustride";
import { ACTING_COOKIE } from "@/lib/shells";

// The frame every shell shares: which shell this is, its navigation, who is
// acting (a person, or an entity they represent), and the way out.
export default async function ShellFrame({
  shell, accent, nav, ctx, allowActing = false, children,
}: {
  shell: string;
  accent: string;
  nav: { href: string; label: string }[];
  ctx: GateContext;
  allowActing?: boolean;
  children: React.ReactNode;
}) {
  const acting = allowActing ? (await cookies()).get(ACTING_COOKIE)?.value ?? "" : "";
  const actingEntity = ctx.represented_entities.find((e) => e.user_id === acting);
  const name = actingEntity?.legal_name ?? ctx.display_name ?? "?";
  const initial = name.trim()[0]?.toUpperCase() ?? "?";
  const activeEntities = ctx.represented_entities.filter((e) => e.status === "ACTIVE");

  return (
    <div className="flex flex-col flex-1">
      <header className="sticky top-0 z-10 flex flex-wrap items-center gap-3 px-5 py-3.5 border-b border-border bg-bg-deepest/85 backdrop-blur">
        <span className="font-display text-lg font-semibold text-text-primary flex-1">
          {shell} <span className="text-gold-light">{accent}</span>
        </span>
        {allowActing && activeEntities.length > 0 && (
          <form action={setActingIdentityAction} className="flex items-center gap-2">
            <input type="hidden" name="next" value="/verify" />
            <select name="acting" defaultValue={acting} className="trs-input rounded-lg px-2 py-1 text-xs text-text-primary">
              <option value="">Myself</option>
              {activeEntities.map((e) => <option key={e.user_id} value={e.user_id}>{e.legal_name}</option>)}
            </select>
            <button className="text-xs text-text-muted hover:text-text-primary">Act as</button>
          </form>
        )}
        <Link href="/verify" className="text-xs text-text-muted hover:text-text-primary transition-colors">Switch shell</Link>
        <div className="flex items-center gap-2.5 pl-1">
          <span className="w-8 h-8 rounded-full bg-gradient-to-br from-gold-light to-gold-dim text-on-gold font-display font-semibold text-sm flex items-center justify-center">
            {initial}
          </span>
          <span className="text-text-secondary text-sm hidden sm:inline">{name}{actingEntity ? " (acting)" : ""}</span>
        </div>
        <form action={signOutAction}>
          <button type="submit" className="text-danger text-sm font-medium hover:text-danger/80 transition-colors ml-1">Sign out</button>
        </form>
      </header>
      <nav className="flex flex-wrap gap-2 px-5 pt-4">
        {nav.map((n) => (
          <Link key={n.href} href={n.href} className="rounded-full border border-border bg-surface px-4 py-2 text-sm font-medium text-text-secondary hover:text-text-primary hover:border-gold-dim transition-colors">
            {n.label}
          </Link>
        ))}
      </nav>
      <div className="flex-1 mt-3 p-5">{children}</div>
    </div>
  );
}
