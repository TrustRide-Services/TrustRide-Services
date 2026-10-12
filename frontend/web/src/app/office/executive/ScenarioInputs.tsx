"use client";

import { useState } from "react";
import { inputClass, labelClass } from "@/components/ui";

export type PricingRow = { macro_domain: string; service_code: string; asset_class: string; jurisdiction: string; current_rate_kes: number };

const rowLabel = (r: PricingRow) => `${r.service_code} · ${r.asset_class.toLowerCase().replaceAll("_", " ")} · ${r.jurisdiction.toLowerCase().replaceAll("_", " ")} (now ${r.current_rate_kes} KES/km)`;
const param = (name: string, value: unknown) => ({ parameter_name: name, parameter_value: value, parameter_source: "SIMULATION_PARAMETER" });

// Inputs of a scenario run, sent as the "parameters" list RUN_SCENARIO takes.
// Rows are Engine 5's active pricing rows; nothing here changes a rate.
export default function ScenarioInputs({ kind, rows }: { kind: "PRICING_CHANGE" | "COST_VS_CAPACITY"; rows: PricingRow[] }) {
  const [a, setA] = useState(0);
  const [b, setB] = useState(rows.length > 1 ? 1 : 0);
  const [rate, setRate] = useState("");
  const ra = rows[a];
  const rb = rows[b];
  const parameters = !ra ? [] : kind === "PRICING_CHANGE"
    ? [param("macro_domain", ra.macro_domain), param("service_code", ra.service_code), param("asset_class", ra.asset_class),
       param("jurisdiction", ra.jurisdiction), ...(rate ? [param("direct_per_km_rate_kes", Number(rate))] : [])]
    : [param("macro_domain", ra.macro_domain), param("jurisdiction", ra.jurisdiction), param("service_code_a", ra.service_code),
       param("asset_class_a", ra.asset_class), param("service_code_b", rb?.service_code), param("asset_class_b", rb?.asset_class)];
  const select = (value: number, set: (n: number) => void, name: string, filter?: (r: PricingRow) => boolean) => (
    <select name={name} value={value} onChange={(e) => set(Number(e.target.value))} className={inputClass}>
      {rows.map((r, i) => (!filter || filter(r) ? <option key={i} value={i}>{rowLabel(r)}</option> : null))}
    </select>
  );
  return (
    <div className="grid sm:grid-cols-2 gap-2 w-full">
      <label className={labelClass}>{kind === "PRICING_CHANGE" ? "Service and vehicle class" : "First class"}{select(a, setA, "__row_a")}</label>
      {kind === "PRICING_CHANGE" ? (
        <label className={labelClass}>Proposed rate (KES per km)
          <input name="__rate" type="number" step="0.01" min="0.01" required value={rate} onChange={(e) => setRate(e.target.value)} className={inputClass} /></label>
      ) : (
        <label className={labelClass}>Second class (same domain and area){select(b, setB, "__row_b", (r) => r.macro_domain === ra?.macro_domain && r.jurisdiction === ra?.jurisdiction)}</label>
      )}
      <input type="hidden" name="parameters:j" value={JSON.stringify(parameters)} />
    </div>
  );
}
