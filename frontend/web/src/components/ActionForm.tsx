"use client";

import { useActionState } from "react";
import type { ActionState } from "@/app/actions";

// A form bound to one identity/contact server action (Foundation functions
// that are not shell commands: contacts, preferences, KRA PIN, entities).
export default function ActionForm({
  action, children, submit, className = "", inline = false, variant = "primary",
}: {
  action: (prev: ActionState, fd: FormData) => Promise<ActionState>;
  children?: React.ReactNode;
  submit: string;
  className?: string;
  inline?: boolean;
  variant?: "primary" | "ghost";
}) {
  const [state, run, pending] = useActionState<ActionState, FormData>(action, null);
  return (
    <form action={run} className={`${inline ? "flex flex-wrap items-end gap-2" : "flex flex-col gap-2.5"} ${className}`}>
      {children}
      <div className="flex flex-col gap-1.5">
        <button type="submit" disabled={pending} className={`${variant === "primary" ? "trs-btn-primary" : "trs-btn-ghost"} rounded-lg px-4 py-2 text-sm font-semibold disabled:opacity-60`}>
          {pending ? "…" : submit}
        </button>
        {state?.error && <p className="text-danger text-xs max-w-md">{state.error}</p>}
        {state?.ok && state.message && <p className="text-success text-xs">{state.message}</p>}
      </div>
    </form>
  );
}
