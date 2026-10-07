"use client";

import { useActionState } from "react";
import { runCommandAction, type ActionState } from "@/app/actions";
import type { SubShell } from "@/lib/shells";

// A form that issues one Engine 11 command. Children are the fields; fixed
// carries the structured parts of the payload. The result (or the reason it
// was refused) is shown in place.
export default function CommandForm({
  sub, command, fixed = {}, children, submit, success, redirectTo, variant = "primary", className = "", inline = false, confirm,
}: {
  sub: SubShell;
  command: string;
  fixed?: Record<string, unknown>;
  children?: React.ReactNode;
  submit: string;
  success?: string;
  redirectTo?: string;
  variant?: "primary" | "ghost" | "danger";
  className?: string;
  inline?: boolean;
  confirm?: string;
}) {
  const [state, action, pending] = useActionState<ActionState, FormData>(runCommandAction, null);
  const btn =
    variant === "primary" ? "trs-btn-primary" : variant === "danger" ? "rounded-lg border border-danger/50 text-danger hover:bg-danger/10" : "trs-btn-ghost";
  return (
    <form
      action={action}
      onSubmit={(e) => { if (confirm && !window.confirm(confirm)) e.preventDefault(); }}
      className={`${inline ? "flex flex-wrap items-end gap-2" : "flex flex-col gap-2.5"} ${className}`}
    >
      <input type="hidden" name="__sub" value={sub} />
      <input type="hidden" name="__cmd" value={command} />
      <input type="hidden" name="__payload" value={JSON.stringify(fixed)} />
      {success && <input type="hidden" name="__success" value={success} />}
      {redirectTo && <input type="hidden" name="__redirect" value={redirectTo} />}
      {children}
      <div className="flex flex-col gap-1.5">
        <button type="submit" disabled={pending} className={`${btn} rounded-lg px-4 py-2 text-sm font-semibold disabled:opacity-60`}>
          {pending ? "…" : submit}
        </button>
        {state?.error && <p className="text-danger text-xs max-w-md">{state.error}</p>}
        {state?.ok && state.message && <p className="text-success text-xs">{state.message}</p>}
      </div>
    </form>
  );
}
