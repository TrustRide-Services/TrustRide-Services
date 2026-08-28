"use client";

import { useActionState } from "react";
import { submitRegistration } from "./actions";

export default function RegisterForm({ email }: { email: string | undefined }) {
  const [state, formAction, pending] = useActionState(submitRegistration, null);

  return (
    <form action={formAction} className="trs-card w-full max-w-md px-8 py-10">
      <h1 className="font-display text-xl font-semibold text-text-primary text-center mb-2 text-balance">One more step</h1>
      <p className="text-sm text-text-secondary text-center mb-7 leading-relaxed">
        You&apos;re signed in as {email}. TrustRide verifies every identity before opening full access -- tell us your
        legal name and ID number to begin.
      </p>

      {state?.error && <p className="text-danger text-sm text-center mb-4">{state.error}</p>}

      <input
        name="legalName"
        placeholder="Full legal name, as on your ID"
        className="trs-input w-full text-text-primary rounded-xl px-4 py-3 mb-3 placeholder:text-text-muted"
      />
      <input
        name="nationalId"
        placeholder="National ID number"
        className="trs-input w-full text-text-primary rounded-xl px-4 py-3 mb-3 placeholder:text-text-muted"
      />
      <label className="flex items-center gap-2.5 mb-6 text-xs text-text-secondary leading-snug">
        <input type="checkbox" name="consent" className="accent-gold" />
        I consent to TrustRide processing this data under the Data Protection Act.
      </label>

      <button type="submit" disabled={pending} className="trs-btn-primary w-full font-semibold rounded-xl py-3.5 disabled:opacity-60">
        {pending ? "…" : "Continue"}
      </button>
    </form>
  );
}
