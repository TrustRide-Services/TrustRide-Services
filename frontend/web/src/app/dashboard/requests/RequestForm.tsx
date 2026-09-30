"use client";

import { useActionState } from "react";
import { submitActorRequest, type RequestEnv } from "./actions";

const COPY: Record<RequestEnv, { title: string; scopeLabel: string; placeholder: string }> = {
  PARTNER: {
    title: "Resource Partnership Request",
    scopeLabel: "Partnership scope — one line per item you are offering",
    placeholder: "2 motorcycles (Honda CB125, 2023) for the Kisumu fleet\nWorking capital facility of KES 500,000",
  },
  GOVERNOR: {
    title: "Regulatory Access / Oversight Request",
    scopeLabel: "What you need — one line per oversight item or information request",
    placeholder: "Monthly trip and revenue summary for Kisumu County (county revenue assessment)\nOperator licensing register access",
  },
  INTERMEDIARY: {
    title: "Facilitation / Intermediation Request",
    scopeLabel: "Facilitation scope — one line per item",
    placeholder: "Supplier onboarding for spare parts distribution\nSettlement facilitation for partner payouts",
  },
};

const input = "trs-input w-full text-text-primary rounded-xl px-4 py-2.5 placeholder:text-text-muted";

export default function RequestForm({ env }: { env: RequestEnv }) {
  const [state, formAction, pending] = useActionState(submitActorRequest.bind(null, env), null);
  const copy = COPY[env];

  if (state?.submitted) {
    return (
      <div className="trs-card p-6">
        <p className="text-success font-semibold mb-1">Request submitted.</p>
        <p className="text-text-secondary text-sm">TrustRide Office decides within 2–3 working days. You will be notified here.</p>
      </div>
    );
  }

  return (
    <form action={formAction} className="trs-card p-6 flex flex-col gap-4">
      <h2 className="font-display text-lg font-semibold text-text-primary">{copy.title}</h2>
      {state?.error && <p className="rounded-lg bg-danger-bg text-danger text-sm p-2.5">{state.error}</p>}

      {env === "PARTNER" && (
        <label className="text-sm text-text-secondary">
          Partnership category
          <select name="partner_category" className={`${input} mt-1.5`}>
            <option value="FLEET_CONTRIBUTOR">Fleet contributor — vehicles and equipment</option>
            <option value="FINANCIER">Financier</option>
            <option value="AMBASSADOR">Ambassador</option>
            <option value="STRATEGIC_COLLABORATOR">Strategic collaborator</option>
          </select>
        </label>
      )}
      {env === "GOVERNOR" && (
        <label className="text-sm text-text-secondary">
          Authority you represent
          <input name="authority_name" placeholder="e.g. Kisumu County Revenue Authority" className={`${input} mt-1.5`} />
        </label>
      )}
      {env === "INTERMEDIARY" && (
        <label className="text-sm text-text-secondary">
          Facilitation type
          <select name="facilitation_type" className={`${input} mt-1.5`}>
            <option value="SUPPLIER_ONBOARDING">Supplier / distributor onboarding</option>
            <option value="TRANSACTION_FACILITATION">Transaction facilitation</option>
            <option value="SUPPLY_RECORDS">Supply records and inventory coordination</option>
            <option value="SETTLEMENT_FACILITATION">Settlement facilitation</option>
          </select>
        </label>
      )}
      <label className="text-sm text-text-secondary">
        Jurisdiction
        <input name="jurisdiction" defaultValue="KISUMU_COUNTY" className={`${input} mt-1.5`} />
      </label>
      <label className="text-sm text-text-secondary">
        {copy.scopeLabel}
        <textarea name="scope" rows={4} placeholder={copy.placeholder} className={`${input} mt-1.5`} />
      </label>

      <button type="submit" disabled={pending} className="trs-btn-primary rounded-xl py-3 font-semibold disabled:opacity-60">
        {pending ? "…" : "Submit request"}
      </button>
    </form>
  );
}
