"use client";

import { useActionState } from "react";
import { signUpAndRegister } from "./actions";

export default function SignUpForm() {
  const [state, formAction, pending] = useActionState(signUpAndRegister, null);

  if (state?.notice) {
    return (
      <div className="w-full max-w-md rounded-2xl border border-border bg-surface p-7 text-center">
        <h1 className="text-xl font-bold text-text-primary mb-3">Almost there</h1>
        <p className="text-sm text-text-secondary leading-relaxed">{state.notice}</p>
      </div>
    );
  }

  return (
    <form action={formAction} className="w-full max-w-md rounded-2xl border border-border bg-surface p-7">
      <h1 className="text-xl font-bold text-text-primary text-center mb-2">Create your account</h1>
      <p className="text-sm text-text-secondary text-center mb-6 leading-relaxed">
        TrustRide verifies every identity before opening full access -- tell us who you are and set your login in
        one step.
      </p>

      {state?.error && <p className="text-danger text-sm text-center mb-4">{state.error}</p>}

      <input
        name="legalName"
        placeholder="Full legal name, as on your ID"
        className="w-full bg-bg text-text-primary rounded-lg px-3.5 py-3 mb-3 border border-border placeholder:text-text-muted"
      />
      <input
        name="nationalId"
        placeholder="National ID number"
        className="w-full bg-bg text-text-primary rounded-lg px-3.5 py-3 mb-3 border border-border placeholder:text-text-muted"
      />
      <input
        type="email"
        name="email"
        autoCapitalize="off"
        placeholder="Email"
        className="w-full bg-bg text-text-primary rounded-lg px-3.5 py-3 mb-3 border border-border placeholder:text-text-muted"
      />
      <input
        type="password"
        name="password"
        placeholder="Password"
        className="w-full bg-bg text-text-primary rounded-lg px-3.5 py-3 mb-3 border border-border placeholder:text-text-muted"
      />
      <label className="flex items-center gap-2.5 mb-5 text-xs text-text-secondary leading-snug">
        <input type="checkbox" name="consent" className="accent-gold" />
        I consent to TrustRide processing this data under the Data Protection Act.
      </label>

      <button type="submit" disabled={pending} className="w-full bg-gold text-on-gold font-bold rounded-lg py-3.5 disabled:opacity-60">
        {pending ? "…" : "Sign Up"}
      </button>
    </form>
  );
}
