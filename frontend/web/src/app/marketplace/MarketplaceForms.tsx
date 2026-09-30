"use client";

import { useActionState } from "react";
import { reserveVehicle, submitVendorListing } from "./actions";

const input = "trs-input w-full text-text-primary rounded-xl px-4 py-2.5 placeholder:text-text-muted";

function Submitted({ title, body }: { title: string; body: string }) {
  return (
    <div className="trs-card p-6">
      <p className="text-success font-semibold mb-1">{title}</p>
      <p className="text-text-secondary text-sm">{body}</p>
    </div>
  );
}

function CategorySelect() {
  return (
    <label className="text-sm text-text-secondary">
      Vehicle
      <select name="vehicle_category" className={`${input} mt-1.5`}>
        <option value="MOTORCYCLE">Motorcycle</option>
        <option value="CAR">Car</option>
      </select>
    </label>
  );
}

export function ReserveVehicleForm() {
  const [state, action, pending] = useActionState(reserveVehicle, null);
  if (state?.submitted) return <Submitted title="Reservation received." body="TrustRide confirms availability within 2–3 working days. You will be notified." />;
  return (
    <form action={action} className="trs-card p-6 flex flex-col gap-4">
      <h2 className="font-display text-lg font-semibold text-text-primary">Reserve a vehicle</h2>
      {state?.error && <p className="rounded-lg bg-danger-bg text-danger text-sm p-2.5">{state.error}</p>}
      <CategorySelect />
      <label className="text-sm text-text-secondary">
        Make and model
        <input name="make_model" placeholder="e.g. Honda CB125, Toyota Axio" className={`${input} mt-1.5`} />
      </label>
      <label className="text-sm text-text-secondary">
        Budget (KES, optional)
        <input name="budget_kes" inputMode="numeric" placeholder="e.g. 180000" className={`${input} mt-1.5`} />
      </label>
      <button type="submit" disabled={pending} className="trs-btn-primary rounded-xl py-3 font-semibold disabled:opacity-60">
        {pending ? "…" : "Reserve"}
      </button>
    </form>
  );
}

export function VendorListingForm() {
  const [state, action, pending] = useActionState(submitVendorListing, null);
  if (state?.submitted) return <Submitted title="Application submitted." body="TrustRide Office decides within 2–3 working days. Once approved you can list on the Marketplace." />;
  return (
    <form action={action} className="trs-card p-6 flex flex-col gap-4">
      <h2 className="font-display text-lg font-semibold text-text-primary">Vendor application</h2>
      {state?.error && <p className="rounded-lg bg-danger-bg text-danger text-sm p-2.5">{state.error}</p>}
      <CategorySelect />
      <label className="text-sm text-text-secondary">
        Business or trading name
        <input name="business_name" placeholder="e.g. Kondele Motorcycles Ltd" className={`${input} mt-1.5`} />
      </label>
      <label className="text-sm text-text-secondary">
        Stock you intend to list — one line per vehicle or batch
        <textarea name="stock" rows={4} placeholder={"5 x Honda CB125 (2021-2023), inspected\n2 x Bajaj Boxer 150"} className={`${input} mt-1.5`} />
      </label>
      <label className="flex items-start gap-2.5 text-xs text-text-secondary leading-snug">
        <input type="checkbox" name="commission" className="accent-gold mt-0.5" />
        I accept TrustRide&apos;s 5% commission on every completed sale made through the Marketplace, and that listings
        must strictly be motorcycles or cars.
      </label>
      <button type="submit" disabled={pending} className="trs-btn-primary rounded-xl py-3 font-semibold disabled:opacity-60">
        {pending ? "…" : "Submit application"}
      </button>
    </form>
  );
}
