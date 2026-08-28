import Image from "next/image";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { chooseUserType, refreshVerification } from "./actions";

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
    <main className="flex flex-1 flex-col items-center justify-center bg-bg-deepest px-7 py-16 text-center">
      <Image src="/trustride-logo.png" alt="TrustRide" width={96} height={96} className="mb-6" />
      {bindError && <p className="text-danger text-sm mb-4 max-w-md">{bindError}</p>}

      {isRejected ? (
        <>
          <h1 className="text-xl font-bold text-text-primary mb-3">We couldn&apos;t verify this identity</h1>
          <p className="text-sm text-text-secondary max-w-md leading-relaxed">
            The details you submitted didn&apos;t clear our identity check. This can happen with a typo in your ID
            number or name. Please contact TrustRide support to resolve this.
          </p>
        </>
      ) : isVerified ? (
        <>
          <h1 className="text-xl font-bold text-text-primary mb-3">Identity verified</h1>
          <p className="text-sm text-text-secondary mb-4">How will you engage with TrustRide?</p>
          <div className="flex flex-wrap gap-2.5 justify-center max-w-lg">
            {USER_TYPES.map((t) => (
              <form key={t.code} action={chooseUserType.bind(null, t.code)}>
                <button
                  type="submit"
                  className="w-[150px] rounded-xl border border-border bg-surface p-4 text-left hover:border-gold"
                >
                  <span className="block text-gold-light font-bold text-sm mb-1.5">{t.label}</span>
                  <span className="block text-text-muted text-xs leading-snug">{t.intent}</span>
                </button>
              </form>
            ))}
          </div>
        </>
      ) : (
        <>
          <h1 className="text-xl font-bold text-text-primary mb-3">Verifying your identity</h1>
          <p className="text-sm text-text-secondary max-w-md leading-relaxed mb-6">
            TrustRide checks every new identity before opening full access to the platform -- this protects you and
            everyone else who relies on TrustRide. This usually resolves within moments.
          </p>
          <form action={refreshVerification}>
            <button type="submit" className="rounded-lg bg-gold text-on-gold font-bold px-7 py-3.5">
              Check again
            </button>
          </form>
        </>
      )}
    </main>
  );
}
