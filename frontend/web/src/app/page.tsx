import Image from "next/image";
import Link from "next/link";

// RENDERING STRATEGY: fully static. The already-signed-in redirect lives in
// middleware.ts instead of a cookies()/auth.getUser() call in this
// component, specifically so this page has zero per-request server work
// and can be served from the CDN edge -- the marketing pitch is identical
// for every anonymous visitor. See middleware.ts for the dynamic half of
// this route.
//
// Structure is Founder law (locked to the reference layout given
// 2026-08-28): topbar with the two real entry points, hero with the brand
// promise and both CTAs, a value strip, and an address footer -- plus the
// brand mark visible twice: a corner mark in the topbar and a large,
// near-invisible watermark behind the whole page.
export default function Home() {
  return (
    <>
      <div className="trs-watermark" aria-hidden />

      <header className="relative z-10 flex items-center justify-between gap-4 px-6 sm:px-8 py-4 border-b border-border bg-bg">
        <div className="flex items-center gap-2.5">
          <Image src="/trustride-logo.png" alt="TrustRide" width={34} height={34} priority />
          <span className="font-display font-semibold text-sm tracking-wide text-text-primary">TrustRide Services</span>
        </div>
        <nav className="flex items-center gap-6">
          <Link href="/login" className="text-[13px] text-text-secondary hover:text-gold-light transition-colors tracking-wide">
            External User Access
          </Link>
          <Link href="/login" className="text-[13px] text-text-secondary hover:text-gold-light transition-colors tracking-wide">
            Staff Access
          </Link>
        </nav>
      </header>

      <main className="relative z-[5] flex-1 flex flex-col items-center justify-center text-center px-6 py-16 max-w-2xl mx-auto">
        <div className="relative mb-8">
          <div className="absolute inset-0 rounded-full bg-gold/15 blur-2xl" />
          <Image src="/trustride-logo.png" alt="TrustRide Services" width={148} height={148} priority className="relative drop-shadow-[0_0_18px_rgba(242,178,85,0.22)]" />
        </div>

        <h1 className="font-display text-[1.9rem] sm:text-[2.2rem] font-bold leading-tight tracking-tight text-text-primary text-balance mb-4">
          More than a Ride — We Save You Time.
        </h1>

        <p className="text-[1.02rem] leading-relaxed text-text-secondary max-w-lg mb-9">
          TrustRide organises transport, courier, delivery, executive assistance and marketplace services into one
          trusted platform. Built in Kisumu. Serving people and businesses across Kenya.
        </p>

        <div className="flex gap-4 flex-wrap justify-center mb-9">
          <Link href="/register" className="trs-btn-primary min-w-[150px] px-9 py-3.5 rounded-md font-bold tracking-wide">
            Sign Up
          </Link>
          <Link href="/login" className="trs-btn-ghost min-w-[150px] px-9 py-3.5 rounded-md font-semibold tracking-wide">
            Login
          </Link>
        </div>

        <p className="text-[13px] leading-relaxed text-text-muted max-w-md">
          TrustRide protects every user&apos;s data. Registration authenticates identity through official
          verification (IPRS via secure partners such as MetaMap) so that only genuine users are allowed on the
          platform. Your safety and data privacy are constitutional priorities.
        </p>
      </main>

      <div className="relative z-[5] flex justify-center gap-8 flex-wrap px-6 py-6 border-t border-border bg-bg text-[13px] text-text-secondary">
        <span className="flex items-center gap-2"><span className="w-1.5 h-1.5 rounded-full bg-gold shrink-0" /> One trusted platform</span>
        <span className="flex items-center gap-2"><span className="w-1.5 h-1.5 rounded-full bg-gold shrink-0" /> Employed operators</span>
        <span className="flex items-center gap-2"><span className="w-1.5 h-1.5 rounded-full bg-gold shrink-0" /> Live tracking &amp; accountability</span>
      </div>

      <footer className="relative z-[5] text-center px-6 py-6 border-t border-border text-[12px] leading-relaxed text-text-muted">
        <strong className="text-text-secondary font-semibold">Kisumu County, Republic of Kenya</strong>
        <br />
        TrustRide Services · Founded by Onyango Albert Chitayi
        <br />
        Email: <a href="mailto:trustride.ke@gmail.com" className="text-text-secondary hover:text-gold-light transition-colors">trustride.ke@gmail.com</a>
        {" · "}
        Tel: <a href="tel:+254756984386" className="text-text-secondary hover:text-gold-light transition-colors">0756 984 386</a>
        {" / "}
        <a href="tel:+254714698020" className="text-text-secondary hover:text-gold-light transition-colors">0714 698 020</a>
        <br />
        © 2026 · Platform Code TRS026
      </footer>
    </>
  );
}
