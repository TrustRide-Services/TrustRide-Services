"use client";

import { useState, Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Image from "next/image";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";

// RENDERING STRATEGY: fully static. Pure client component -- no server
// data, no cookies, identical HTML shipped to every visitor; Supabase auth
// calls happen entirely in the browser after hydration. Sign-up is
// deliberately NOT handled here -- it lives at /register, the one real
// combined shell (name, ID, email, password) that also captures identity
// details for verification. This page only ever authenticates an existing
// account or resets its password.
type Mode = "SIGN_IN" | "FORGOT_PASSWORD";

function LoginForm() {
  const router = useRouter();
  const params = useSearchParams();
  const initialMode: Mode = params.get("mode") === "forgot" ? "FORGOT_PASSWORD" : "SIGN_IN";
  const [mode, setMode] = useState<Mode>(initialMode);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    const supabase = createClient();
    setError(null);
    setNotice(null);

    if (mode === "FORGOT_PASSWORD") {
      if (!email) return setError("Enter the email on your account.");
      setBusy(true);
      const { error } = await supabase.auth.resetPasswordForEmail(email);
      setBusy(false);
      if (error) return setError(error.message);
      setNotice("If that email has an account, a reset link is on its way.");
      return;
    }

    if (!email || !password) return setError("Enter both email and password.");
    setBusy(true);
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    setBusy(false);
    if (error) return setError(error.message);
    router.push("/dashboard");
    router.refresh();
  };

  const heading = mode === "SIGN_IN" ? "Log in" : "Reset your password";
  const buttonLabel = mode === "SIGN_IN" ? "Log In" : "Send reset link";

  return (
    <main className="flex flex-1 flex-col items-center justify-center px-6 py-16 relative">
      <Link href="/" className="absolute top-6 left-6 text-sm text-text-secondary hover:text-text-primary transition-colors">
        ← Back
      </Link>
      <form onSubmit={submit} className="trs-card w-full max-w-md px-8 py-10">
        <div className="relative mx-auto mb-5 w-fit">
          <div className="absolute inset-0 rounded-full bg-gold/15 blur-xl" />
          <Image src="/trustride-logo.png" alt="TrustRide" width={68} height={68} className="relative" />
        </div>
        <h1 className="font-display text-xl font-semibold text-text-primary text-center mb-6 text-balance">{heading}</h1>

        {notice && <p className="text-success text-center text-sm mb-4">{notice}</p>}
        {error && <p className="text-danger text-center text-sm mb-4">{error}</p>}

        <input
          type="email"
          placeholder="Email"
          autoCapitalize="off"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="trs-input w-full text-text-primary rounded-xl px-4 py-3 mb-3 placeholder:text-text-muted"
        />
        {mode !== "FORGOT_PASSWORD" && (
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="trs-input w-full text-text-primary rounded-xl px-4 py-3 mb-3 placeholder:text-text-muted"
          />
        )}

        <button
          type="submit"
          disabled={busy}
          className="trs-btn-primary w-full font-semibold rounded-xl py-3.5 mt-2 mb-5 disabled:opacity-60"
        >
          {busy ? "…" : buttonLabel}
        </button>

        {mode === "SIGN_IN" && (
          <div className="flex flex-col items-center gap-2">
            <Link href="/register" className="text-gold-light font-semibold text-sm hover:text-gold transition-colors">
              Need an account? Sign up
            </Link>
            <button type="button" onClick={() => setMode("FORGOT_PASSWORD")} className="text-text-muted text-sm hover:text-text-secondary transition-colors">
              Forgot password?
            </button>
          </div>
        )}
        {mode === "FORGOT_PASSWORD" && (
          <button type="button" onClick={() => setMode("SIGN_IN")} className="w-full text-gold-light font-semibold text-sm hover:text-gold transition-colors">
            Back to log in
          </button>
        )}
      </form>
    </main>
  );
}

export default function LoginPage() {
  return (
    <Suspense>
      <LoginForm />
    </Suspense>
  );
}
