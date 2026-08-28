import Image from "next/image";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { chooseUserType, refreshVerification } from "./actions";
import { signOutAction } from "@/app/dashboard/actions";

// The four USER_HUB sub-shells (Engine 11 v2.0.0) -- Operator is deliberately
// absent: TRUSTRIDE_OPERATOR now lives under the internal TRS_OPERATOR_HUB
// (TrustRide's own workforce, per the Article 44 finding that operators are
// constitutionally employees, not external contractors), so becoming an
// Operator is no longer a public self-service choice here.
const USER_TYPES = [
  { code: "CUSTOMER", label: "Customer", intent: "Request transport, delivery, courier, or marketplace services" },
  { code: "PARTNER", label: "Partner", intent: "Contribute a resource, finance, or business collaboration" },
  { code: "GOVERNOR", label: "Governor", intent: "Hold delegated oversight authority: registers, exceptions, governance signals" },
  { code: "INTERMEDIARY", label: "Intermediary", intent: "Publish offers and settle lawful flows as a marketplace vendor" },
];

// TRS_OPERATOR_HUB's three sub-shells -- shown so the platform's real
// two-shell structure is visible here, but never self-service. TrustRide's
// own workforce is authorized internally, not through public sign-up (the
// Article 44 finding that operators are constitutionally employees, not
// external contractors, applies to all three).
const INTERNAL_SHELLS = [
  { code: "TRUSTRIDE_OPERATOR", label: "Operator", note: "Drive, ride, or execute TrustRide work" },
  { code: "TRUSTRIDE_ADMIN", label: "Admin", note: "Platform administration & governance signals" },
  { code: "TRUSTRIDE_EXECUTIVE_CONSOLE", label: "Executive Console", note: "Whole-estate oversight & scenario modelling" },
];

// Article 20.1's Identity Verification + Authorization steps, made real:
// Engine 6's simulated identity adapter processes the real
// VERIFICATION_REQUESTED signal automatically (pg_cron dispatch, ~10s), so
// this page genuinely resolves on its own on a fresh server-rendered visit
// -- "Check again" (a plain form resubmit) exists for the person, not
// because anything requires manual polling.
// RENDERING STRATEGY: fully dynamic. Which of the three states below
// renders (pending / verified / rejected) is decided entirely by this
// user's own verification_record and business_actor_registration rows --
// there's no version of this page that's the same for two different
// visitors, so the whole thing is a Server Component read straight from
// the request's session, not a static shell candidate.
export default async function VerifyPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const { error: bindError } = await searchParams;
  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) redirect("/login");

  const { data: profile } = await supabase.from("platform_users").select("user_id").maybeSingle();
  if (!profile) redirect("/register");

  const { data: verification } = await supabase
    .from("verification_record")
    .select("outcome")
    .eq("verification_type", "NATIONAL_ID")
    .order("verified_at", { ascending: false, nullsFirst: false })
    .limit(1)
    .maybeSingle();

  const { data: actor } = await supabase
    .from("business_actor_registration")
    .select("user_type_domain")
    .eq("registration_status", "ACTIVE")
    .limit(1)
    .maybeSingle();

  if (actor?.user_type_domain) redirect("/dashboard");

  const outcome = verification?.outcome ?? "PENDING";
  const isVerified = outcome === "VERIFIED";
  const isRejected = outcome === "REJECTED";

  return (
    <main className="flex flex-1 flex-col items-center justify-center px-6 py-16 text-center relative">
      <form action={signOutAction} className="absolute top-6 right-6">
        <button type="submit" className="text-sm text-text-muted hover:text-danger transition-colors">
          Sign out
        </button>
      </form>

      <div className={`trs-card px-8 py-11 sm:px-11 flex flex-col items-center ${isVerified ? "max-w-3xl w-full" : "max-w-md w-full"}`}>
        <div className="relative mb-6">
          <div className="absolute inset-0 rounded-full bg-gold/15 blur-xl" />
          <Image src="/trustride-logo.png" alt="TrustRide" width={80} height={80} className="relative" />
        </div>
        {bindError && <p className="text-danger text-sm mb-4 max-w-md">{bindError}</p>}

        {isRejected ? (
          <>
            <p className="text-[11px] font-semibold uppercase tracking-[0.28em] text-danger mb-3">Verification Failed</p>
            <h1 className="font-display text-xl font-semibold text-text-primary mb-3 text-balance">We couldn&apos;t verify this identity</h1>
            <p className="text-sm text-text-secondary max-w-md leading-relaxed">
              The details you submitted didn&apos;t clear our identity check. This can happen with a typo in your ID
              number or name. Please contact TrustRide support to resolve this.
            </p>
          </>
        ) : isVerified ? (
          <>
            <p className="text-[11px] font-semibold uppercase tracking-[0.28em] text-gold-dim mb-3">Access · Registration · Authentication · Authorization</p>
            <h1 className="font-display text-2xl font-semibold text-text-primary mb-1.5 text-balance">Welcome to TrustRide.</h1>
            <p className="text-sm text-gold-light italic mb-8">More than a ride — we save you time.</p>

            <div className="w-full text-left">
              <div className="flex items-baseline gap-2 mb-3">
                <span className="text-[11px] font-semibold uppercase tracking-[0.2em] text-gold-dim">User Hub</span>
                <span className="text-[11px] text-text-muted">— external, self-service. Choose your shell.</span>
              </div>
              <div className="grid grid-cols-2 gap-3.5 w-full mb-9">
                {USER_TYPES.map((t) => (
                  <form key={t.code} action={chooseUserType.bind(null, t.code)} className="contents">
                    <button
                      type="submit"
                      className="trs-choice-card trs-card text-left p-4 flex flex-col items-start"
                    >
                      <span className="w-9 h-9 rounded-full bg-gradient-to-br from-gold-light to-gold-dim text-on-gold font-display font-semibold text-sm flex items-center justify-center mb-3">
                        {t.label[0]}
                      </span>
                      <span className="block text-text-primary font-semibold text-sm mb-1">{t.label}</span>
                      <span className="block text-text-muted text-xs leading-snug">{t.intent}</span>
                    </button>
                  </form>
                ))}
              </div>

              <div className="flex items-baseline gap-2 mb-3">
                <span className="text-[11px] font-semibold uppercase tracking-[0.2em] text-text-muted">TrustRide Operator Hub</span>
                <span className="text-[11px] text-text-muted">— internal, granted by TrustRide, not self-service.</span>
              </div>
              <div className="grid grid-cols-3 gap-3">
                {INTERNAL_SHELLS.map((s) => (
                  <div
                    key={s.code}
                    className="trs-card p-4 flex flex-col items-start opacity-55 cursor-not-allowed select-none"
                    title="Internal access only -- granted by TrustRide, not chosen here"
                  >
                    <span className="w-9 h-9 rounded-full border border-border-strong text-text-muted font-display font-semibold text-sm flex items-center justify-center mb-3">
                      {s.label[0]}
                    </span>
                    <span className="block text-text-secondary font-semibold text-sm mb-1">{s.label}</span>
                    <span className="block text-text-muted text-xs leading-snug">{s.note}</span>
                  </div>
                ))}
              </div>
            </div>
          </>
        ) : (
          <>
            <p className="text-[11px] font-semibold uppercase tracking-[0.28em] text-gold-dim mb-3">Verifying</p>
            <h1 className="font-display text-xl font-semibold text-text-primary mb-3 text-balance">Verifying your identity</h1>
            <p className="text-sm text-text-secondary max-w-md leading-relaxed mb-7">
              TrustRide checks every new identity before opening full access to the platform -- this protects you and
              everyone else who relies on TrustRide. This usually resolves within moments.
            </p>
            <form action={refreshVerification}>
              <button type="submit" className="trs-btn-primary rounded-xl px-7 py-3.5 font-semibold">
                Check again
              </button>
            </form>
          </>
        )}
      </div>
    </main>
  );
}
