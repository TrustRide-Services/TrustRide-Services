import Image from "next/image";
import Link from "next/link";
import { redirect } from "next/navigation";
import { envStatus, gateContext, officeAccess, type Environment } from "@/lib/trustride";
import { chooseEnvironment, claimFounder, enterMarketplaceAsBuyer, refreshVerification, requestOfficeAccess } from "./actions";
import { addContactAction, resendCodeAction, signOutAction, verifyContactAction } from "@/app/actions";
import ActionForm from "@/components/ActionForm";
import { inputClass, when } from "@/components/ui";

// THE SOVEREIGN GATE (TRS026-ENG011-PRESENT-003 Sec.3)
// System Access -> Registration -> Authentication (Engine 6) -> Authorization
// -> Profile, then routing into exactly one of the three main shells. This
// page waits on Engine 6's identity result, asks for the one authoritative
// phone (M-Pesa and SMS, D3), and then lays out TrustRide Business,
// TrustRide Marketplace and TrustRide Office with a real way in for every
// actor. Everything shown comes from the gate context (Foundation only).
//
// RENDERING STRATEGY: fully dynamic -- this visitor's own identity.

const BUSINESS: { env: Exclude<Environment, "OPERATOR">; label: string; intent: string; flow: string; href: string }[] = [
  { env: "CUSTOMER", label: "Customer", intent: "Transport, delivery, courier and executive assistant services", flow: "Opens immediately", href: "/dashboard" },
  { env: "PARTNER", label: "Partner", intent: "Contribute vehicles, finance or business collaboration", flow: "Partnership request · decided within 2–3 working days", href: "/dashboard/partner" },
  { env: "GOVERNOR", label: "Governor", intent: "Regulators and authorities requesting oversight or statutory information", flow: "Regulatory access request · 2–3 working days", href: "/dashboard/governor" },
  { env: "INTERMEDIARY", label: "Intermediary", intent: "Facilitate transactions, suppliers and distribution; refer customers", flow: "Facilitation request · 2–3 working days", href: "/dashboard/intermediary" },
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
      active ? "border-success/40 text-success bg-success/10" : status === "REJECTED" ? "border-danger/40 text-danger" : "border-gold-dim/50 text-gold-light bg-gold/10"}`}>
      {active ? "Active" : status === "REJECTED" ? "Declined" : "Awaiting approval"}
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
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  if (!ctx.registered) redirect("/register");

  const outcome = ctx.verification?.outcome ?? "PENDING";
  const isVerified = ctx.identity_status === "ACTIVE";
  const isRejected = !isVerified && (outcome === "FAILED" || outcome === "REJECTED");
  const office = officeAccess(ctx);
  const isStaff = office.admin || office.executive || office.operator;
  const phone = ctx.phone_contact;
  const officePending = ctx.office_request && ["SUBMITTED", "UNDER_REVIEW"].includes(ctx.office_request.response ?? "SUBMITTED")
    && !["DECLINED", "CANCELLED", "CLOSED"].includes(ctx.office_request.status);

  return (
    <main className="flex flex-1 flex-col items-center justify-center px-4 sm:px-6 py-16 text-center relative">
      <form action={signOutAction} className="absolute top-6 right-6">
        <button type="submit" className="text-sm text-text-muted hover:text-danger transition-colors">Sign out</button>
      </form>

      <div className={`trs-card px-5 py-11 sm:px-11 flex flex-col items-center ${isVerified ? "max-w-4xl w-full" : "max-w-md w-full"}`}>
        <div className="relative mb-6">
          <div className="absolute inset-0 rounded-full bg-gold/15 blur-xl" />
          <Image src="/trustride-logo.png" alt="TrustRide" width={80} height={80} className="relative" />
        </div>
        {gateError && <p className="text-danger text-sm mb-4 max-w-md">{gateError}</p>}
        {notice === "office-requested" && <p className="text-success text-sm mb-4 max-w-md">Office access requested — TrustRide Office decides within 2–3 working days.</p>}

        {isRejected ? (
          <>
            <p className="text-[11px] font-semibold uppercase tracking-[0.28em] text-danger mb-3">Authentication not confirmed</p>
            <h1 className="font-display text-xl font-semibold text-text-primary mb-3 text-balance">We couldn&apos;t verify this identity</h1>
            {ctx.verification_failed_reasons?.length ? (
              <ul className="text-sm text-text-secondary mb-3">{ctx.verification_failed_reasons.map((r) => <li key={r}>{r.toLowerCase().replaceAll("_", " ")}</li>)}</ul>
            ) : null}
            <p className="text-sm text-text-secondary max-w-md leading-relaxed">
              The details you submitted didn&apos;t clear the official identity check — often a typo in the ID number or name.
              Contact TrustRide support: trustride.ke@gmail.com · 0756 984 386.
            </p>
          </>
        ) : !isVerified ? (
          <>
            <p className="text-[11px] font-semibold uppercase tracking-[0.28em] text-gold-dim mb-3">Authentication</p>
            <h1 className="font-display text-xl font-semibold text-text-primary mb-3 text-balance">Verifying your identity</h1>
            <p className="text-sm text-text-secondary max-w-md leading-relaxed mb-7">
              TrustRide checks every new identity through official verification before any shell opens. This usually resolves within moments.
            </p>
            <form action={refreshVerification}><button type="submit" className="trs-btn-primary rounded-xl px-7 py-3.5 font-semibold">Check again</button></form>
          </>
        ) : (
          <>
            <p className="text-[11px] font-semibold uppercase tracking-[0.28em] text-gold-dim mb-3">Access · Registration · Authentication · Authorization</p>
            <h1 className="font-display text-2xl font-semibold text-text-primary mb-1.5 text-balance">Welcome to TrustRide{ctx.display_name ? `, ${ctx.display_name.split(" ")[0]}` : ""}.</h1>
            <p className="text-sm text-gold-light italic mb-9">More than a ride — we save you time.</p>

            <div className="w-full text-left flex flex-col gap-9">
              {/* Phone: the one authoritative number for M-Pesa and SMS (D3) */}
              {!ctx.phone_verified && (
                <section>
                  <ShellHeading name="Your phone" kind="M-Pesa payments and SMS updates" />
                  <div className="trs-card p-4 flex flex-col gap-3">
                    {!phone ? (
                      <ActionForm action={addContactAction} submit="Send code" inline>
                        <input type="hidden" name="type" value="PHONE" />
                        <label className="flex flex-col gap-1 text-xs text-text-secondary flex-1 min-w-48">Phone number (Safaricom M-Pesa)
                          <input name="value" required inputMode="tel" placeholder="0712 345 678" className={inputClass} /></label>
                      </ActionForm>
                    ) : (
                      <>
                        <p className="text-sm text-text-secondary">We sent a 6-digit code to <span className="text-text-primary font-semibold">{phone.value}</span>.</p>
                        <div className="flex flex-wrap gap-2 items-end">
                          <ActionForm action={verifyContactAction} submit="Verify" inline>
                            <input type="hidden" name="contact_id" value={phone.contact_id} />
                            <input name="code" required inputMode="numeric" maxLength={6} placeholder="6-digit code" className={`${inputClass} w-36`} />
                          </ActionForm>
                          <ActionForm action={resendCodeAction} submit="New code" variant="ghost" inline><input type="hidden" name="contact_id" value={phone.contact_id} /></ActionForm>
                        </div>
                      </>
                    )}
                    <p className="text-xs text-text-muted">Services are paid by M-Pesa to this number after completion; it must be verified before you book.</p>
                    {ctx.simulated_messages.length > 0 && (
                      <div className="rounded-lg border border-gold-dim/40 bg-gold/5 p-3 text-xs text-text-secondary">
                        <span className="block uppercase tracking-wide text-gold-dim mb-1">Staging — messages a real phone would have received</span>
                        {ctx.simulated_messages.map((m, i) => <span key={i} className="block">{when(m.at)} · {m.body}</span>)}
                      </div>
                    )}
                  </div>
                </section>
              )}

              <section>
                <ShellHeading name="TrustRide Business" kind="external" />
                <div className="grid sm:grid-cols-2 gap-3.5">
                  {BUSINESS.map((b) => {
                    const status = envStatus(ctx, b.env);
                    return (
                      <div key={b.env} className="trs-card p-4 flex flex-col">
                        <div className="flex items-center justify-between gap-2 mb-1">
                          <span className="text-text-primary font-semibold text-sm">{b.label}</span><StatusChip status={status} />
                        </div>
                        <p className="text-text-muted text-xs leading-snug mb-1">{b.intent}</p>
                        <p className="text-text-secondary text-[11px] mb-3">{b.flow}</p>
                        {status ? (
                          <Link href={b.href} className="trs-btn-ghost mt-auto rounded-lg py-2 text-center text-sm font-semibold">Enter</Link>
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
                {ctx.represented_entities.length > 0 && (
                  <p className="text-xs text-text-muted mt-3">You also represent {ctx.represented_entities.map((e) => e.legal_name).join(", ")} — switch to it with “Act as” inside the shell.</p>
                )}
              </section>

              <section>
                <ShellHeading name="TrustRide Marketplace" kind="external · motorcycles and cars" />
                <div className="grid sm:grid-cols-2 gap-3.5">
                  <div className="trs-card p-4 flex flex-col">
                    <span className="text-text-primary font-semibold text-sm mb-1">Buy a vehicle</span>
                    <p className="text-text-muted text-xs leading-snug mb-3">Inspected, improved motorcycles and cars from TrustRide and approved vendors.</p>
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

              <section>
                <ShellHeading name="TrustRide Office" kind="internal · TrustRide staff only" />
                {isStaff ? (
                  <div className="trs-card p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                    <p className="text-text-secondary text-sm">You hold TrustRide Office access{office.founder ? " as Founder" : ""}.</p>
                    <Link href={office.admin || office.executive ? "/office" : "/office/operator"} className="trs-btn-primary rounded-lg px-5 py-2 text-sm font-semibold shrink-0 text-center">Enter TrustRide Office</Link>
                  </div>
                ) : !ctx.founder_exists ? (
                  <div className="trs-card p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                    <p className="text-text-secondary text-sm">No Founder has been established yet. The first verified identity may claim Founder authority — once, ever. Only do this if you are the Founder of TrustRide Services.</p>
                    <form action={claimFounder}><button type="submit" className="trs-btn-primary rounded-lg px-5 py-2 text-sm font-semibold shrink-0">Claim Founder authority</button></form>
                  </div>
                ) : officePending ? (
                  <div className="trs-card p-4">
                    <p className="text-text-secondary text-sm">Office access request <span className="text-text-primary font-semibold">{ctx.office_request!.order_code}</span> is with TrustRide Office — decision within 2–3 working days.</p>
                  </div>
                ) : (
                  <form action={requestOfficeAccess} className="trs-card p-4 grid sm:grid-cols-[180px_1fr_auto] gap-3 items-end">
                    {ctx.office_request?.response === "DECLINED" && <p className="sm:col-span-3 text-xs text-danger">Your last request ({ctx.office_request.order_code}) was declined.</p>}
                    <label className="text-xs text-text-secondary">Surface
                      <select name="surface" className="trs-input mt-1 w-full rounded-lg px-3 py-2 text-sm text-text-primary">
                        {OFFICE_SURFACES.map((s) => <option key={s.code} value={s.code}>{s.label}</option>)}
                      </select>
                    </label>
                    <label className="text-xs text-text-secondary">Your TrustRide role or staff reference
                      <input name="justification" required placeholder="e.g. Rider applicant, Operations administrator" className="trs-input mt-1 w-full rounded-lg px-3 py-2 text-sm text-text-primary placeholder:text-text-muted" />
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
