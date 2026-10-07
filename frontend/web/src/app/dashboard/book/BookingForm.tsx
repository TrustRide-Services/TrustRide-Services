"use client";

import { useActionState, useMemo, useState } from "react";
import { runCommandAction, type ActionState } from "@/app/actions";

export type CatalogueService = { service_code: string; service_name: string; description: string; fulfilment: string; command: string | null;
  trip: boolean; needs_hours: boolean; vetting_tier: string | null };
export type Family = { domain: string; services: CatalogueService[] };
export type Zone = { zone_code: string; zone_name: string; jurisdiction: string };

const FAMILY_LABEL: Record<string, string> = {
  TRANSPORT: "Transport", DELIVERY: "Delivery", COURIER: "Courier", EXECUTIVE_ASSISTANTS: "Executive Assistants", MARKETPLACE: "Marketplace",
};

// Service-specific booking (G14): trips take stops by zone -- the platform
// computes distance and duration through its routing port; Executive
// Assistant services take a location and hours. Now, or scheduled within
// TrustRide's working hours (G11).
export default function BookingForm({ families, zones, maxStops, scheduleMaxDays, phoneVerified, openNow, nextOpen }: {
  families: Family[]; zones: Zone[]; maxStops: number; scheduleMaxDays: number; phoneVerified: boolean; openNow: boolean; nextOpen: string;
}) {
  const bookable = useMemo(() => families.filter((f) => f.domain !== "MARKETPLACE")
    .map((f) => ({ ...f, services: f.services.filter((s) => s.fulfilment === "DISPATCH") })).filter((f) => f.services.length), [families]);
  const [family, setFamily] = useState(bookable[0]?.domain ?? "");
  const services = bookable.find((f) => f.domain === family)?.services ?? [];
  const [code, setCode] = useState(services[0]?.service_code ?? "");
  const service = services.find((s) => s.service_code === code) ?? services[0];
  const first = zones[0]?.zone_code ?? "";
  const [stops, setStops] = useState<{ from: string; to: string }[]>([{ from: first, to: zones[1]?.zone_code ?? first }]);
  const [location, setLocation] = useState(first);
  const [hours, setHours] = useState(2);
  const [when, setWhen] = useState<"now" | "later">("now");
  const [at, setAt] = useState("");
  const [notes, setNotes] = useState("");
  const [state, action, pending] = useActionState<ActionState, FormData>(runCommandAction, null);

  // The booking window, fixed when the form opens, in the browser's local
  // time (datetime-local has no zone; toISOString would be UTC, 3 h off in Kenya).
  const [opened] = useState(() => Date.now());
  const min = localInput(opened + 20 * 60000);
  const max = localInput(opened + scheduleMaxDays * 86400000);
  const lines = service?.needs_hours
    ? [{ line_description: notes || service.service_name, scope_detail: { origin_zone_code: location, billed_hours: hours } }]
    : stops.map((s, i) => ({ line_description: stops.length > 1 ? `Stop ${i + 1}` : notes || service?.service_name, scope_detail: { origin_zone_code: s.from, destination_zone_code: s.to } }));
  const payload = {
    user_type_domain: "CUSTOMER", service_code: service?.service_code, order_lines: lines,
    ...(when === "later" && at ? { requested_start_at: new Date(at).toISOString() } : {}),
  };
  const zoneSelect = (value: string, onChange: (v: string) => void) => (
    <select value={value} onChange={(e) => onChange(e.target.value)} className="trs-input rounded-lg px-3 py-2 text-sm text-text-primary w-full">
      {zones.map((z) => <option key={z.zone_code} value={z.zone_code}>{z.zone_name}</option>)}
    </select>
  );

  if (!bookable.length) return <p className="text-text-muted text-sm">No services are open for booking.</p>;
  return (
    <form action={action} className="trs-card p-6 flex flex-col gap-5">
      <input type="hidden" name="__sub" value="CUSTOMER_APP" />
      <input type="hidden" name="__cmd" value="RAISE_INTENT" />
      <input type="hidden" name="__payload" value={JSON.stringify(payload)} />
      <input type="hidden" name="__redirect" value="/dashboard/orders/{signal}" />

      <div className="flex flex-wrap gap-2">
        {bookable.map((f) => (
          <button key={f.domain} type="button" onClick={() => { setFamily(f.domain); setCode(f.services[0].service_code); }}
            className={`rounded-full border px-4 py-1.5 text-sm ${family === f.domain ? "border-gold-dim bg-gold/10 text-text-primary" : "border-border text-text-secondary"}`}>
            {FAMILY_LABEL[f.domain] ?? f.domain}
          </button>
        ))}
      </div>

      <div className="grid sm:grid-cols-2 gap-2">
        {services.map((s) => (
          <button key={s.service_code} type="button" onClick={() => setCode(s.service_code)}
            className={`text-left rounded-xl border p-3 ${service?.service_code === s.service_code ? "border-gold-dim bg-gold/10" : "border-border hover:border-border-strong"}`}>
            <span className="block text-sm font-semibold text-text-primary">{s.service_name}</span>
            <span className="block text-xs text-text-muted">{s.description}</span>
            {s.vetting_tier === "ENHANCED" && <span className="block text-[11px] text-gold-light mt-1">Served only by enhanced-vetted assistants</span>}
          </button>
        ))}
      </div>

      {service?.needs_hours ? (
        <div className="grid sm:grid-cols-2 gap-3">
          <label className="text-xs text-text-secondary flex flex-col gap-1">Where{zoneSelect(location, setLocation)}</label>
          <label className="text-xs text-text-secondary flex flex-col gap-1">Hours
            <input type="number" min={1} max={12} value={hours} onChange={(e) => setHours(Number(e.target.value))} className="trs-input rounded-lg px-3 py-2 text-sm text-text-primary" />
          </label>
        </div>
      ) : (
        <div className="flex flex-col gap-2">
          {stops.map((s, i) => (
            <div key={i} className="grid sm:grid-cols-[1fr_1fr_auto] gap-2 items-end">
              <label className="text-xs text-text-secondary flex flex-col gap-1">{i === 0 ? "From" : `Stop ${i + 1} from`}
                {zoneSelect(s.from, (v) => setStops(stops.map((x, j) => (j === i ? { ...x, from: v } : x))))}</label>
              <label className="text-xs text-text-secondary flex flex-col gap-1">To
                {zoneSelect(s.to, (v) => setStops(stops.map((x, j) => (j === i ? { ...x, to: v } : x))))}</label>
              {stops.length > 1 ? (
                <button type="button" onClick={() => setStops(stops.filter((_, j) => j !== i))} className="text-xs text-danger px-2 py-2">Remove</button>
              ) : <span />}
            </div>
          ))}
          {stops.length < maxStops && (
            <button type="button" onClick={() => setStops([...stops, { from: stops[stops.length - 1].to, to: stops[stops.length - 1].to }])}
              className="self-start text-sm text-gold-light">+ Add a stop</button>
          )}
          <p className="text-xs text-text-muted">Distance and duration are calculated by TrustRide; each stop is priced and the fare is their sum.</p>
        </div>
      )}

      <label className="text-xs text-text-secondary flex flex-col gap-1">Notes for your {service?.needs_hours ? "assistant" : "driver"} (optional)
        <input value={notes} onChange={(e) => setNotes(e.target.value)} maxLength={140} className="trs-input rounded-lg px-3 py-2 text-sm text-text-primary" />
      </label>

      <div className="flex flex-wrap gap-4 items-end">
        <label className="text-sm text-text-secondary flex items-center gap-2"><input type="radio" checked={when === "now"} onChange={() => setWhen("now")} /> As soon as possible</label>
        <label className="text-sm text-text-secondary flex items-center gap-2"><input type="radio" checked={when === "later"} onChange={() => setWhen("later")} /> Schedule</label>
        {when === "later" && (
          <input type="datetime-local" min={min} max={max} value={at} onChange={(e) => setAt(e.target.value)} className="trs-input rounded-lg px-3 py-2 text-sm text-text-primary" />
        )}
      </div>
      {!openNow && when === "now" && (
        <p className="text-xs text-gold-light">TrustRide is closed right now (Mon–Fri 05:00–22:00, Sat 06:00–23:00, Sunday off duty). Your order will be served by the first shift: {new Date(nextOpen).toLocaleString("en-KE", { timeZone: "Africa/Nairobi" })}.</p>
      )}

      {!phoneVerified && <p className="text-xs text-danger">Verify your phone number in Profile first — it is your M-Pesa payment number.</p>}
      {state?.error && <p className="rounded-lg bg-danger-bg text-danger text-sm p-2.5">{state.error}</p>}
      <button type="submit" disabled={pending || !phoneVerified || (when === "later" && !at)} className="trs-btn-primary rounded-xl py-3.5 font-semibold disabled:opacity-60">
        {pending ? "Placing your order…" : "Request — we will show your fare before anyone is dispatched"}
      </button>
    </form>
  );
}

function localInput(ms: number) {
  const d = new Date(ms);
  return new Date(ms - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
}
