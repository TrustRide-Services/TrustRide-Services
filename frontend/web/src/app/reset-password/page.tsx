"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Image from "next/image";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";

// RENDERING STRATEGY: fully static client page. Reached only from a password
// reset email, through /auth/callback, which has already signed the person
// in; this page sets the new password on that session.
export default function ResetPasswordPage() {
  const router = useRouter();
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    if (!password) return setError("Enter a new password.");
    if (password !== confirm) return setError("The two passwords do not match.");
    setBusy(true);
    const { error } = await createClient().auth.updateUser({ password });
    setBusy(false);
    if (error) {
      return setError(/session/i.test(error.message)
        ? "This reset link has expired. Request a new one from the login page."
        : error.message);
    }
    router.push("/verify");
    router.refresh();
  };

  return (
    <main className="flex flex-1 flex-col items-center justify-center px-6 py-16 relative">
      <Link href="/login" className="absolute top-6 left-6 text-sm text-text-secondary hover:text-text-primary transition-colors">
        ← Back
      </Link>
      <form onSubmit={submit} className="trs-card w-full max-w-md px-8 py-10">
        <div className="relative mx-auto mb-5 w-fit">
          <div className="absolute inset-0 rounded-full bg-gold/15 blur-xl" />
          <Image src="/trustride-logo.png" alt="TrustRide" width={68} height={68} className="relative" />
        </div>
        <h1 className="font-display text-xl font-semibold text-text-primary text-center mb-6 text-balance">Choose a new password</h1>

        {error && <p className="text-danger text-center text-sm mb-4">{error}</p>}

        <input
          type="password"
          name="password"
          placeholder="New password"
          autoComplete="new-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          className="trs-input w-full text-text-primary rounded-xl px-4 py-3 mb-3 placeholder:text-text-muted"
        />
        <input
          type="password"
          name="confirm"
          placeholder="Repeat new password"
          autoComplete="new-password"
          value={confirm}
          onChange={(e) => setConfirm(e.target.value)}
          className="trs-input w-full text-text-primary rounded-xl px-4 py-3 mb-3 placeholder:text-text-muted"
        />

        <button
          type="submit"
          disabled={busy}
          className="trs-btn-primary w-full font-semibold rounded-xl py-3.5 mt-2 disabled:opacity-60"
        >
          {busy ? "…" : "Save new password"}
        </button>
      </form>
    </main>
  );
}
