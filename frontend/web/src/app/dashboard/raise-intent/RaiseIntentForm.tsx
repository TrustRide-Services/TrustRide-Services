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
    <form action={formAction} className="max-w-xl">
      <h1 className="text-lg font-bold text-text-primary mb-4">Request a service</h1>
      {state?.error && <p className="rounded-lg bg-danger-bg text-danger text-sm p-2.5 mb-3">{state.error}</p>}

      <p className="text-text-secondary text-sm mb-1.5">Service</p>
      <div className="flex flex-wrap gap-2 mb-4">
        {services.map((s) => (
          <button
            key={s.service_id}
            type="button"
            disabled={!s.bookable}
            onClick={() => setSelected(s.service_code)}
            className={`rounded-lg px-3.5 py-2.5 text-sm font-semibold border ${
              selected === s.service_code ? "border-gold bg-surface-elevated text-text-primary" : "border-border bg-surface text-text-secondary"
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
      <input name="originZone" defaultValue="KSM-CBD-01" className="w-full bg-surface text-text-primary rounded-lg px-3.5 py-2.5 mb-3.5 border border-border" />

      <label className="block text-text-secondary text-sm mb-1.5">To (zone code)</label>
      <input name="destinationZone" defaultValue="KSM-CBD-01" className="w-full bg-surface text-text-primary rounded-lg px-3.5 py-2.5 mb-3.5 border border-border" />

      <label className="block text-text-secondary text-sm mb-1.5">Distance (km)</label>
      <input name="distanceKm" defaultValue="4.0" className="w-full bg-surface text-text-primary rounded-lg px-3.5 py-2.5 mb-3.5 border border-border" />

      <label className="block text-text-secondary text-sm mb-1.5">Duration (min)</label>
      <input name="durationMin" defaultValue="12.0" className="w-full bg-surface text-text-primary rounded-lg px-3.5 py-2.5 mb-4 border border-border" />

      <button type="submit" disabled={pending} className="w-full bg-gold text-on-gold font-bold rounded-lg py-3.5 disabled:opacity-60">
        {pending ? "…" : "Request service"}
      </button>
    </form>
  );
}
