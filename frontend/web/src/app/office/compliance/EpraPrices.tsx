"use client";

import { useState } from "react";
import { inputClass, labelClass } from "@/components/ui";

// The two published pump prices of one jurisdiction, sent as the "prices"
// list the RECORD_EPRA_PRICE_CYCLE command takes. The visible fields are
// prefixed "__" so they are not sent on their own.
export default function EpraPrices({ jurisdictions }: { jurisdictions: string[] }) {
  const [j, setJ] = useState(jurisdictions[0] ?? "KISUMU_COUNTY");
  const [petrol, setPetrol] = useState("");
  const [diesel, setDiesel] = useState("");
  const prices = [
    ...(petrol ? [{ jurisdiction: j, fuel_type: "PETROL_SUPER", pump_price_kes: Number(petrol) }] : []),
    ...(diesel ? [{ jurisdiction: j, fuel_type: "DIESEL", pump_price_kes: Number(diesel) }] : []),
  ];
  return (
    <div className="grid sm:grid-cols-3 gap-2">
      <label className={labelClass}>Jurisdiction
        <select name="__jurisdiction" value={j} onChange={(e) => setJ(e.target.value)} className={inputClass}>
          {jurisdictions.map((x) => <option key={x} value={x}>{x.toLowerCase().replaceAll("_", " ")}</option>)}
        </select></label>
      <label className={labelClass}>Super petrol (KES/litre)<input name="__petrol" type="number" step="0.01" value={petrol} onChange={(e) => setPetrol(e.target.value)} className={inputClass} /></label>
      <label className={labelClass}>Diesel (KES/litre)<input name="__diesel" type="number" step="0.01" value={diesel} onChange={(e) => setDiesel(e.target.value)} className={inputClass} /></label>
      <input type="hidden" name="prices:j" value={JSON.stringify(prices)} />
    </div>
  );
}
