import Image from "next/image";
import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getActorContext, type Environment } from "@/lib/trustride";
import { chooseEnvironment, claimFounder, enterMarketplaceAsBuyer, refreshVerification, requestOfficeAccess } from "./actions";
import { signOutAction } from "@/app/dashboard/actions";

// THE SOVEREIGN GATE (TRS026-ENG011-PRESENT-003 Sec.3, TRS026-FE-01 module G)
// System Access -> Registration -> Authentication (Engine 6) -> Authorization
// -> Profile, then routing into exactly one of the three main shells. This
// page is steps 4-5 and the routing: it waits on Engine 6's result, and once
// authorization is green it lays out TrustRide Office, TrustRide Business and
// TrustRide Marketplace with a real way in for every actor -- nobody arrives
// at a shell with nothing to do.
//
// RENDERING STRATEGY: fully dynamic -- entirely decided by this visitor's own
// verification, registrations and roles.

const BUSINESS: { env: Exclude<Environment, "OPERATOR">; label: string; intent: string; flow: string }[] = [
  { env: "CUSTOMER", label: "Customer", intent: "Transport, delivery, courier, executive assistant and marketplace services", flow: "Catalogue opens immediately" },
  { env: "PARTNER", label: "Partner", intent: "Contribute resources, finance or business collaboration", flow: "Resource Partnership Request · 2–3 working days" },
  { env: "GOVERNOR", label: "Governor", intent: "Regulators and authorities — e.g. county revenue — requesting oversight or statutory information", flow: "Regulatory Access Request · 2–3 working days" },
  { env: "INTERMEDIARY", label: "Intermediary", intent: "Facilitate transactions, suppliers and distribution", flow: "Facilitation Request · 2–3 working days" },
];

const OFFICE_SURFACES = [
  { code: "ADMIN_CONSOLE", label: "Admin Console" },
  { code: "OPERATOR_APP", label: "Operator App" },
  { code: "EXECUTIVE_DASHBOARD", label: "Executive Dashboard" },
];

function StatusChip({ status }: { status: string | undefined }) {
  if (!status) return null;
  const active = status === "ACTIVE";
  return (
    <span className={`rounded-full border px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide ${
      active ? "border-success/40 text-success bg-success/10" : "border-gold-dim/50 text-gold-light bg-gold/10"
    }`}>
      {active ? "Active" : "Awaiting approval"}
    </span>
  );
}

function ShellHeading({ name, kind }: { name: string; kind: string }) {
  return (
    <div className="flex items-baseline gap-2 mb-3">
      <span className="text-[11px] font-semibold uppercase tracking-[0.2em] text-gold-dim">{name}</span>
      <span className="text-[11px] text-text-muted">— {kind}</span>
    </div>
  );
}

export default async function VerifyPage({ searchParams }: { searchParams: Promise<{ error?: string; notice?: string }> }) {
  const { error: gateError, notice } = await searchParams;
  const ctx = await getActorContext();
  if (!ctx) redirect("/login");
  if (!ctx.profile) redirect("/register");

  const supabase = await createClient();
  const [{ data: verification }, { data: founderExists }, { data: officeRequest }] = await Promise.all([
    supabase
      .from("verification_record")
      .select("outcome")
      .eq("verification_type", "NATIONAL_ID")
      .order("verified_at", { ascending: false, nullsFirst: false })
      .limit(1)
      .maybeSingle(),
    supabase.rpc("fn_founder_exists"),
    supabase
      .from("business_order")
      .select("order_code, status")
      .eq("order_root_type", "OFFICE_ACCESS_REQUEST")
      .order("placed_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
  ]);

  const outcome = verification?.outcome ?? "PENDING";
  const isVerified = outcome === "VERIFIED";
  const isRejected = outcome === "FAILED" || outcome === "REJECTED";

  return (
    <main className="flex flex-1 flex-col items-center justify-center px-6 py-16 text-center relative">
      <form action={signOutAction} className="absolute top-6 right-6">
        <button type="submit" className="text-sm text-text-muted hover:text-danger transition-colors">Sign out</button>
      </form>

      <div className={`trs-card px-8 py-11 sm:px-11 flex flex-col items-center ${isVerified ? "max-w-4xl w-full" : "max-w-md w-full"}`}>
        <div className="relative mb-6">
          <div className="absolute inset-0 rounded-full bg-gold/15 blur-xl" />
          <Image src="/trustride-logo.png" alt="TrustRide" width={80} height={80} className="relative" />
        </div>
        {gateError && <p className="text-danger text-sm mb-4 max-w-md">{gateError}</p>}
        {notice === "office-requested" && (
          <p className="text-success text-sm mb-4 max-w-md">Office access requested — TrustRide Office decides within 2–3 working days.</p>
        )}

        {isRejected ? (
          <>
            <p className="text-[11px] font-semibold uppercase tracking-[0.28em] text-danger mb-3">Authentication Not Confirmed</p>
            <h1 className="font-display text-xl font-semibold text-text-primary mb-3 text-balance">We couldn&apos;t verify this identity</h1>
            <p className="text-sm text-text-secondary max-w-md leading-relaxed">
              The details you submitted didn&apos;t clear the official identity check. This can happen with a typo in your ID
              number or name. Please contact TrustRide support — trustride.ke@gmail.com · 0756 984 386.
            </p>
          </>
        ) : !isVerified ? (
          <>
            <p className="text-[11px] font-semibold uppercase tracking-[0.28em] text-gold-dim mb-3">Authentication</p>
            <h1 className="font-display text-xl font-semibold text-text-primary mb-3 text-balance">Verifying your identity</h1>
            <p className="text-sm text-text-secondary max-w-md leading-relaxed mb-7">
              TrustRide checks every new identity through official verification before any shell opens. This usually
              resolves within moments.
            </p>
            <form action={refreshVerification}>
              <button type="submit" className="trs-btn-primary rounded-xl px-7 py-3.5 font-semibold">Check again</button>
            </form>
          </>
        ) : (
          <>
            <p className="text-[11px] font-semibold uppercase tracking-[0.28em] text-gold-dim mb-3">
              Access · Registration · Authentication · Authorization
            </p>
            <h1 className="font-display text-2xl font-semibold text-text-primary mb-1.5 text-balance">Welcome to TrustRide.</h1>
            <p className="text-sm text-gold-light italic mb-9">More than a ride — we save you time.</p>

            <div className="w-full text-left flex flex-col gap-9">
              {/* 2.0 TrustRide Business */}
              <section>
                <ShellHeading name="TrustRide Business" kind="external" />
                <div className="grid sm:grid-cols-2 gap-3.5">
                  {BUSINESS.map((b) => {
                    const status = ctx.envStatus.get(b.env);
                    return (
                      <div key={b.env} className="trs-card p-4 flex flex-col">
                        <div className="flex items-center justify-between gap-2 mb-1">
                          <span className="text-text-primary font-semibold text-sm">{b.label}</span>
                          <StatusChip status={status} />
                        </div>
                        <p className="text-text-muted text-xs leading-snug mb-1">{b.intent}</p>
                        <p className="text-text-secondary text-[11px] mb-3">{b.flow}</p>
                        {status ? (
                          <Link href={b.env === "CUSTOMER" ? "/dashboard" : `/dashboard/requests?as=${b.env}`} className="trs-btn-ghost mt-auto rounded-lg py-2 text-center text-sm font-semibold">
                            Enter
                          </Link>
                        ) : (
                          <form action={chooseEnvironment.bind(null, b.env, undefined)} className="mt-auto">
                            <button type="submit" className="trs-btn-primary w-full rounded-lg py-2 text-sm font-semibold">
                              {b.env === "CUSTOMER" ? "Continue as Customer" : `Apply as ${b.label}`}
                            </button>
                          </form>
                        )}
                      </div>
                    );
                  })}
                </div>
              </section>

              {/* 3.0 TrustRide Marketplace */}
              <section>
                <ShellHeading name="TrustRide Marketplace" kind="external · motorcycles and cars" />
                <div className="grid sm:grid-cols-2 gap-3.5">
                  <div className="trs-card p-4 flex flex-col">
                    <span className="text-text-primary font-semibold text-sm mb-1">Buy a vehicle</span>
                    <p className="text-text-muted text-xs leading-snug mb-3">Second-hand, improved motorcycles and cars from TrustRide and approved vendors.</p>
                    <form action={enterMarketplaceAsBuyer} className="mt-auto">
                      <button type="submit" className="trs-btn-primary w-full rounded-lg py-2 text-sm font-semibold">Enter Marketplace</button>
                    </form>
                  </div>
                  <div className="trs-card p-4 flex flex-col">
                    <span className="text-text-primary font-semibold text-sm mb-1">Sell as a vendor</span>
                    <p className="text-text-muted text-xs leading-snug mb-3">List motorcycles or cars on TrustRide. 5% commission on every completed sale. Approval within 2–3 working days.</p>
                    <Link href="/marketplace/vendor" className="trs-btn-ghost mt-auto rounded-lg py-2 text-center text-sm font-semibold">Vendor application</Link>
                  </div>
                </div>
              </section>

              {/* 1.0 TrustRide Office */}
              <section>
                <ShellHeading name="TrustRide Office" kind="internal · TrustRide staff only" />
                {ctx.isStaff ? (
                  <div className="trs-card p-4 flex items-center justify-between gap-4">
                    <p className="text-text-secondary text-sm">
                      You hold TrustRide Office access{ctx.isFounder ? " as Founder" : ""}.
                    </p>
                    <Link href="/office" className="trs-btn-primary rounded-lg px-5 py-2 text-sm font-semibold shrink-0">Enter TrustRide Office</Link>
                  </div>
                ) : founderExists === false ? (
                  <div className="trs-card p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                    <p className="text-text-secondary text-sm">
                      No Founder has been established yet. The first verified identity may claim Founder authority —
                      once, ever. Only do this if you are the Founder of TrustRide Services.
                    </p>
                    <form action={claimFounder}>
                      <button type="submit" className="trs-btn-primary rounded-lg px-5 py-2 text-sm font-semibold shrink-0">Claim Founder authority</button>
                    </form>
                  </div>
                ) : officeRequest && officeRequest.status === "PLACED" ? (
                  <div className="trs-card p-4">
                    <p className="text-text-secondary text-sm">
                      Office access request <span className="text-text-primary font-semibold">{officeRequest.order_code}</span> is with
                      TrustRide Office — decision within 2–3 working days.
                    </p>
                  </div>
                ) : (
                  <form action={requestOfficeAccess} className="trs-card p-4 grid sm:grid-cols-[180px_1fr_auto] gap-3 items-end">
                    <label className="text-xs text-text-secondary">
                      Surface
                      <select name="surface" className="trs-input mt-1 w-full rounded-lg px-3 py-2 text-sm text-text-primary">
                        {OFFICE_SURFACES.map((s) => <option key={s.code} value={s.code}>{s.label}</option>)}
                      </select>
                    </label>
                    <label className="text-xs text-text-secondary">
                      Your TrustRide role or staff reference
                      <input name="justification" required placeholder="e.g. Operations administrator, staff ref TRS-001"
                        className="trs-input mt-1 w-full rounded-lg px-3 py-2 text-sm text-text-primary placeholder:text-text-muted" />
                    </label>
                    <button type="submit" className="trs-btn-ghost rounded-lg px-4 py-2 text-sm font-semibold">Request Office access</button>
                  </form>
                )}
              </section>
            </div>
          </>
        )}
      </div>
    </main>
  );
}
