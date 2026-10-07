"use client";

import { useActionState, useState } from "react";
import { runCommandAction, type ActionState } from "@/app/actions";

type Vehicle = { object_type: string; make: string; model: string; year: string; plate_number: string; capacity_class: string; inspection_status: string; insurance_status: string };
const CLASS_OF: Record<string, string> = { MOTORCYCLE: "BODA_BODA", TUKTUK: "TUKTUK", CAR: "SEDAN", PICKUP: "PICKUP_TOWN", VAN: "VAN_CARGO", TRUCK: "TRUCK_LIGHT" };
const blank = (): Vehicle => ({ object_type: "MOTORCYCLE", make: "", model: "", year: "", plate_number: "", capacity_class: "BODA_BODA", inspection_status: "PASSED", insurance_status: "ACTIVE" });

// Contribute one or more vehicles in a single request (SUBMIT_CONTRIBUTION).
export default function ContributionForm({ bases }: { bases: { estate_id: string; name: string }[] }) {
  const [vehicles, setVehicles] = useState<Vehicle[]>([blank()]);
  const [base, setBase] = useState(bases[0]?.estate_id ?? "");
  const [state, action, pending] = useActionState<ActionState, FormData>(runCommandAction, null);
  const set = (i: number, k: keyof Vehicle, v: string) =>
    setVehicles(vehicles.map((x, j) => (j === i ? { ...x, [k]: v, ...(k === "object_type" ? { capacity_class: CLASS_OF[v] } : {}) } : x)));
  const input = "trs-input rounded-lg px-3 py-2 text-sm text-text-primary";
  return (
    <form action={action} className="flex flex-col gap-3">
      <input type="hidden" name="__sub" value="PARTNER_APP" />
      <input type="hidden" name="__cmd" value="SUBMIT_CONTRIBUTION" />
      <input type="hidden" name="__success" value="Contribution submitted — TrustRide Office reviews and verifies each vehicle with NTSA." />
      <input type="hidden" name="__payload" value={JSON.stringify({ estate_id: base || undefined, vehicles: vehicles.map((v) => ({ ...v, year: v.year ? Number(v.year) : undefined })) })} />
      {vehicles.map((v, i) => (
        <div key={i} className="grid sm:grid-cols-6 gap-2">
          <select value={v.object_type} onChange={(e) => set(i, "object_type", e.target.value)} className={input}>
            {Object.keys(CLASS_OF).map((t) => <option key={t} value={t}>{t.toLowerCase()}</option>)}
          </select>
          <input placeholder="Make" value={v.make} onChange={(e) => set(i, "make", e.target.value)} className={input} />
          <input placeholder="Model" value={v.model} onChange={(e) => set(i, "model", e.target.value)} className={input} />
          <input placeholder="Year" value={v.year} onChange={(e) => set(i, "year", e.target.value)} className={input} />
          <input placeholder="Plate" required value={v.plate_number} onChange={(e) => set(i, "plate_number", e.target.value)} className={input} />
          <select value={`${v.inspection_status}/${v.insurance_status}`} onChange={(e) => { const [a, b] = e.target.value.split("/"); setVehicles(vehicles.map((x, j) => (j === i ? { ...x, inspection_status: a, insurance_status: b } : x))); }} className={input}>
            <option value="PASSED/ACTIVE">Inspected + insured</option><option value="PENDING/ACTIVE">Inspection pending</option><option value="PASSED/PENDING">Insurance pending</option>
          </select>
        </div>
      ))}
      <div className="flex flex-wrap gap-3 items-center">
        <button type="button" onClick={() => setVehicles([...vehicles, blank()])} className="text-sm text-gold-light">+ Another vehicle</button>
        {bases.length > 0 && (
          <label className="text-xs text-text-secondary flex items-center gap-2">Base
            <select value={base} onChange={(e) => setBase(e.target.value)} className={input}>{bases.map((b) => <option key={b.estate_id} value={b.estate_id}>{b.name}</option>)}</select>
          </label>
        )}
      </div>
      {state?.error && <p className="text-danger text-xs">{state.error}</p>}
      {state?.ok && <p className="text-success text-xs">{state.message}</p>}
      <button disabled={pending} className="trs-btn-primary self-start rounded-lg px-4 py-2 text-sm font-semibold disabled:opacity-60">{pending ? "…" : "Submit contribution"}</button>
    </form>
  );
}
