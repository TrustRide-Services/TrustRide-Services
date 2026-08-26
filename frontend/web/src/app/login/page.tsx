"use client";

import { useState, Suspense } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import Image from "next/image";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";

// RENDERING STRATEGY: fully static. Pure client component -- no server
// data, no cookies, identical HTML shipped to every visitor; Supabase auth
// calls happen entirely in the browser after hydration.
type Mode = "SIGN_IN" | "SIGN_UP" | "FORGOT_PASSWORD";

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
    if (mode === "SIGN_UP") {
      const { error } = await supabase.auth.signUp({ email, password });
      setBusy(false);
      if (error) return setError(error.message);
      setNotice("Account created. Check your email to confirm, then log in.");
      setMode("SIGN_IN");
      return;
    }
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    setBusy(false);
    if (error) return setError(error.message);
    router.push("/dashboard");
    router.refresh();
  };

  const heading = mode === "SIGN_IN" ? "Log in" : mode === "SIGN_UP" ? "Create your account" : "Reset your password";
  const buttonLabel = mode === "SIGN_IN" ? "Log In" : mode === "SIGN_UP" ? "Sign Up" : "Send reset link";

  return (
    <main className="flex flex-1 flex-col items-center justify-center bg-bg-deepest px-6 py-16">
      <Link href="/" className="absolute top-5 left-5 text-sm text-text-secondary">
        ← Back
      </Link>
      <form onSubmit={submit} className="w-full max-w-md rounded-2xl border border-border bg-surface p-7">
        <Image src="/trustride-logo.png" alt="TrustRide" width={72} height={72} className="mx-auto mb-3.5" />
        <h1 className="text-xl font-bold text-text-primary text-center mb-5">{heading}</h1>

        {notice && <p className="text-success text-center text-sm mb-4">{notice}</p>}
        {error && <p className="text-danger text-center text-sm mb-4">{error}</p>}

        <input
          type="email"
          placeholder="Email"
          autoCapitalize="off"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="w-full bg-bg text-text-primary rounded-lg px-3.5 py-3 mb-3 border border-border placeholder:text-text-muted"
        />
        {mode !== "FORGOT_PASSWORD" && (
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full bg-bg text-text-primary rounded-lg px-3.5 py-3 mb-3 border border-border placeholder:text-text-muted"
          />
        )}

        <button
          type="submit"
          disabled={busy}
          className="w-full bg-gold text-on-gold font-bold rounded-lg py-3.5 mt-2 mb-4.5 disabled:opacity-60"
        >
          {busy ? "…" : buttonLabel}
        </button>

        {mode === "SIGN_IN" && (
          <div className="flex flex-col items-center gap-2">
            <button type="button" onClick={() => setMode("SIGN_UP")} className="text-gold-light font-semibold text-sm">
              Need an account? Sign up
            </button>
            <button type="button" onClick={() => setMode("FORGOT_PASSWORD")} className="text-text-muted text-sm">
              Forgot password?
            </button>
          </div>
        )}
        {mode === "SIGN_UP" && (
          <button type="button" onClick={() => setMode("SIGN_IN")} className="w-full text-gold-light font-semibold text-sm">
            Already have an account? Log in
          </button>
        )}
        {mode === "FORGOT_PASSWORD" && (
          <button type="button" onClick={() => setMode("SIGN_IN")} className="w-full text-gold-light font-semibold text-sm">
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
