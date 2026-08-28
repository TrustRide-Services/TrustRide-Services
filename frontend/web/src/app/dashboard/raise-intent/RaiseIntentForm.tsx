"use client";

import { useActionState, useState } from "react";
import { raiseIntentAction } from "../actions";

type CatalogueService = {
  service_id: string;
  service_code: string;
  macro_domain: string | null;
  bookable: boolean;
  label: string;
};

export default function RaiseIntentForm({ services, userTypeDomain }: { services: CatalogueService[]; userTypeDomain: string }) {
  const [state, formAction, pending] = useActionState(raiseIntentAction, null);
  const bookableDefault = services.find((s) => s.bookable) ?? services[0];
  const [selected, setSelected] = useState(bookableDefault?.service_code ?? "");
  const selectedService = services.find((s) => s.service_code === selected);

  if (services.length === 0) {
    return <p className="text-text-muted text-center mt-10">No active services are published yet. Check back soon.</p>;
  }

  return (
    <form action={formAction} className="trs-card max-w-xl p-6">
      {state?.error && <p className="rounded-lg bg-danger-bg text-danger text-sm p-2.5 mb-4">{state.error}</p>}

      <p className="text-text-secondary text-sm mb-2">Service</p>
      <div className="flex flex-wrap gap-2 mb-5">
        {services.map((s) => (
          <button
            key={s.service_id}
            type="button"
            disabled={!s.bookable}
            onClick={() => setSelected(s.service_code)}
            className={`rounded-xl px-4 py-2.5 text-sm font-semibold border transition-colors ${
              selected === s.service_code
                ? "border-gold-dim bg-gold/10 text-text-primary shadow-[0_0_0_1px_var(--gold-dim)]"
                : "border-border bg-surface text-text-secondary hover:border-border-strong"
            } ${!s.bookable ? "opacity-50" : ""}`}
          >
            {s.label}
            {!s.bookable && <span className="block text-[10px] text-text-muted">not yet bookable</span>}
          </button>
        ))}
      </div>

      <input type="hidden" name="serviceCode" value={selected} />
      <input type="hidden" name="macroDomain" value={selectedService?.macro_domain ?? ""} />
      <input type="hidden" name="userTypeDomain" value={userTypeDomain} />

      <label className="block text-text-secondary text-sm mb-1.5">From (zone code)</label>
      <input name="originZone" defaultValue="KSM-CBD-01" className="trs-input w-full text-text-primary rounded-xl px-4 py-2.5 mb-4" />

      <label className="block text-text-secondary text-sm mb-1.5">To (zone code)</label>
      <input name="destinationZone" defaultValue="KSM-CBD-01" className="trs-input w-full text-text-primary rounded-xl px-4 py-2.5 mb-4" />

      <div className="grid grid-cols-2 gap-4 mb-5">
        <div>
          <label className="block text-text-secondary text-sm mb-1.5">Distance (km)</label>
          <input name="distanceKm" defaultValue="4.0" className="trs-input w-full text-text-primary rounded-xl px-4 py-2.5" />
        </div>
        <div>
          <label className="block text-text-secondary text-sm mb-1.5">Duration (min)</label>
          <input name="durationMin" defaultValue="12.0" className="trs-input w-full text-text-primary rounded-xl px-4 py-2.5" />
        </div>
      </div>

      <button type="submit" disabled={pending} className="trs-btn-primary w-full font-semibold rounded-xl py-3.5 disabled:opacity-60">
        {pending ? "…" : "Request service"}
      </button>
    </form>
  );
}
