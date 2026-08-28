import Image from "next/image";
import Link from "next/link";

// RENDERING STRATEGY: fully static. The already-signed-in redirect lives in
// middleware.ts instead of a cookies()/auth.getUser() call in this
// component, specifically so this page has zero per-request server work
// and can be served from the CDN edge -- the marketing pitch is identical
// for every anonymous visitor. See middleware.ts for the dynamic half of
// this route.
export default function Home() {
  return (
    <main className="flex flex-1 flex-col items-center justify-center px-6 py-16 relative overflow-hidden">
      <div className="absolute top-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-gold to-transparent" />

      <div className="trs-card flex flex-col items-center max-w-md w-full px-9 py-11">
        <div className="relative mb-6">
          <div className="absolute inset-0 rounded-full bg-gold/20 blur-2xl" />
          <Image src="/trustride-logo.png" alt="TrustRide" width={132} height={132} priority className="relative" />
        </div>

        <p className="text-[11px] font-semibold uppercase tracking-[0.28em] text-gold-dim mb-3">
          Constitutional Services Platform
        </p>
        <h1 className="font-display text-[1.75rem] leading-tight font-semibold text-text-primary text-center text-balance">
          Welcome to TrustRide.
        </h1>
        <p className="text-base text-gold-light text-center mt-2 mb-10">How may I help you?</p>

        <div className="flex gap-3.5 w-full">
          <Link
            href="/login"
            className="trs-btn-ghost flex-1 py-3.5 rounded-xl text-center font-semibold tracking-wide"
          >
            Log In
          </Link>
          <Link
            href="/register"
            className="trs-btn-primary flex-1 py-3.5 rounded-xl text-center font-semibold tracking-wide"
          >
            Sign Up
          </Link>
        </div>

        <Link href="/login?mode=forgot" className="mt-6 text-sm text-text-secondary hover:text-text-primary transition-colors">
          Forgot password?
        </Link>
      </div>

      <p className="absolute bottom-7 text-xs italic text-text-muted tracking-wide">more than a ride — we save you time.</p>
    </main>
  );
}
