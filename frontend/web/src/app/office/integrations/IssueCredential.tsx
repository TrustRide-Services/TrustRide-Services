"use client";

import { useActionState } from "react";
import { issueCredentialAction, type IssueState } from "./actions";
import { inputClass } from "@/components/ui";

export default function IssueCredential({ systemUserId }: { systemUserId: string }) {
  const [state, action, pending] = useActionState<IssueState, FormData>(issueCredentialAction, null);
  if (state?.key) {
    return (
      <div className="rounded-lg border border-gold-dim bg-gold/10 p-3 text-sm flex flex-col gap-1">
        <p className="text-text-primary font-semibold">Copy this key now — it will not be shown again.</p>
        <code className="break-all text-gold-light select-all">{state.key}</code>
        <p className="text-text-muted text-xs">Give it to the system as <code>Authorization: Bearer &lt;key&gt;</code>.</p>
      </div>
    );
  }
  return (
    <form action={action} className="flex flex-wrap items-end gap-2">
      <input type="hidden" name="system_user_id" value={systemUserId} />
      <input type="hidden" name="scopes" value="TELEMETRY_INGEST" />
      <select name="valid_days" className={`${inputClass} w-32`}><option value="90">90 days</option><option value="365">1 year</option></select>
      <button disabled={pending} className="trs-btn-primary rounded-lg px-4 py-2 text-sm font-semibold disabled:opacity-60">{pending ? "…" : "Issue telemetry key"}</button>
      {state?.error && <p className="text-danger text-xs">{state.error}</p>}
    </form>
  );
}
