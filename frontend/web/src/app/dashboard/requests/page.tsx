import { Suspense } from "react";
import { redirect } from "next/navigation";
import { getActorContext } from "@/lib/trustride";
import RequestHistory from "@/components/RequestHistory";
import RequestForm from "./RequestForm";
import type { RequestEnv } from "./actions";

// Partner_App / Governor_App / Intermediary_App (TRS026-ENG011-PRESENT-003
// Sec.4.2-4.4): after Profile, the actor submits their request and follows it
// through TrustRide Office's 2-3 working-day decision. Open while PENDING --
// awaiting approval is a status, never a locked door.
//
// RENDERING STRATEGY: hybrid -- static heading, per-user status and history
// streamed via Suspense.
const META: Record<RequestEnv, { title: string; root: string; activeNote: string }> = {
  PARTNER: { title: "Partner", root: "RESOURCE_PARTNERSHIP_REQUEST", activeNote: "Your partnership is active. Listings, pricing, orders, settlement and payouts arrive on this surface in the next increment." },
  GOVERNOR: { title: "Governor", root: "REGULATORY_ACCESS_REQUEST", activeNote: "Your regulatory access is active. Compliance registers, audit trail and statutory reporting arrive on this surface in the next increment." },
  INTERMEDIARY: { title: "Intermediary", root: "FACILITATION_REQUEST", activeNote: "Your facilitation access is active. Supplier onboarding, supply records and settlement facilitation arrive on this surface in the next increment." },
};

export default async function RequestsPage({ searchParams }: { searchParams: Promise<{ as?: string }> }) {
  const { as } = await searchParams;
  const env = (as ?? "") as RequestEnv;
  const ctx = await getActorContext();
  if (!ctx) redirect("/login");
  if (!META[env] || !ctx.envStatus.has(env)) redirect("/verify");

  const meta = META[env];
  const active = ctx.envStatus.get(env) === "ACTIVE";

  return (
    <div className="max-w-2xl mx-auto flex flex-col gap-6">
      <div>
        <h1 className="font-display text-xl font-semibold text-text-primary">{meta.title}</h1>
        <p className="text-text-secondary text-sm mt-1">
          {active ? meta.activeNote : "Awaiting approval. Submit your request below — TrustRide Office decides within 2–3 working days (Mon–Fri 05:00–22:00, Sat 06:00–23:00)."}
        </p>
      </div>
      <RequestForm env={env} />
      <section>
        <h2 className="text-[11px] font-semibold uppercase tracking-[0.2em] text-gold-dim mb-3">Your requests</h2>
        <Suspense fallback={<p className="text-text-muted text-sm">Loading…</p>}>
          <RequestHistory root={meta.root} empty="No requests yet." />
        </Suspense>
      </section>
    </div>
  );
}
