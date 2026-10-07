import { redirect } from "next/navigation";
import { gateContext, officeAccess, officeSub, project } from "@/lib/trustride";
import CommandForm from "@/components/CommandForm";
import { Badge, Card, Empty, ErrorNote, Page, Section, inputClass, labelClass, when } from "@/components/ui";

type Res = {
  estates: { estate_id: string; code: string; name: string; type: string; jurisdiction: string }[];
  vehicles: { object_id: string; type: string; label: string; plate: string; status: string; custodian: string | null;
    fleet: { fleet_resource_id: string; class: string; lifecycle: string; ownership: string; inspection: string; insurance: string; bound_unit: string | null;
      tracker: { device: string; status: string; last_seen_at: string | null } | null } | null }[];
  devices: { object_id: string; serial: string; model: string; bound: boolean }[];
  units: { workforce_unit_id: string; operator: string; class: string; base: string; availability: string; plate: string | null;
    capabilities: { capability_id: string; type: string; ref: string; expires_at: string | null }[] }[];
  operators_awaiting_unit: { user_id: string; name: string }[];
  classes: { code: string; label: string; requires_fleet: boolean }[];
  capability_types: string[];
};

const OBJ_CLASS: Record<string, string> = { MOTORCYCLE: "BODA_BODA", TUKTUK: "TUKTUK", CAR: "SEDAN", PICKUP: "PICKUP_TOWN", VAN: "VAN_CARGO", TRUCK: "TRUCK_LIGHT" };

// Resources (projection OFFICE_RESOURCES) -- G2: everything needed to turn
// real people, vehicles and devices into a dispatchable pool, with no table
// edited by hand: bases, vehicles (NTSA-verified), onboarding approved
// operators into working units, credentials and vetting, Protrack devices,
// maintenance and retirement.
export default async function OfficeResources() {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  const admin = officeAccess(ctx).admin;
  const { data: r, error } = await project<Res>(officeSub(ctx), "OFFICE_RESOURCES");
  if (!r) return <Page title="Resources"><ErrorNote error={error} /></Page>;
  const verifiedFree = r.vehicles.filter((v) => v.fleet?.lifecycle === "VERIFIED" && !v.fleet.bound_unit);
  const estateOptions = r.estates.map((e) => <option key={e.estate_id} value={e.estate_id}>{e.name}</option>);
  return (
    <Page title="Resources" intro="Register what TrustRide owns or is given; verify it; form approved operators into working units.">
      {admin && (
        <div className="grid lg:grid-cols-2 gap-4">
          <Section title="1 · Onboard an approved operator">
            <Card>
              {!r.operators_awaiting_unit.length ? <Empty>No approved operator is waiting for a unit. Approve Office access (Operator App) requests first.</Empty> : (
                <CommandForm sub="ADMIN_CONSOLE" command="ONBOARD_OPERATOR" submit="Form working unit" success="Unit formed — the operator has been told to start their shift.">
                  <label className={labelClass}>Operator<select name="operator_user_id" className={inputClass}>{r.operators_awaiting_unit.map((o) => <option key={o.user_id} value={o.user_id}>{o.name}</option>)}</select></label>
                  <label className={labelClass}>Class<select name="capacity_class" className={inputClass}>{r.classes.map((c) => <option key={c.code} value={c.code}>{c.label}</option>)}</select></label>
                  <label className={labelClass}>Base<select name="estate_id" className={inputClass}>{estateOptions}</select></label>
                  <label className={labelClass}>Vehicle (not for Executive Assistants)
                    <select name="fleet_resource_id" className={inputClass}><option value="">— none —</option>
                      {verifiedFree.map((v) => <option key={v.fleet!.fleet_resource_id} value={v.fleet!.fleet_resource_id}>{v.label} · {v.plate} ({v.fleet!.class})</option>)}</select></label>
                </CommandForm>
              )}
            </Card>
          </Section>
          <Section title="2 · Register a vehicle or device">
            <Card>
              <CommandForm sub="ADMIN_CONSOLE" command="REGISTER_OBJECT" submit="Register" success="Registered.">
                <div className="grid grid-cols-2 gap-2">
                  <label className={labelClass}>Type<select name="object_type" className={inputClass}>
                    {["MOTORCYCLE", "TUKTUK", "CAR", "PICKUP", "VAN", "TRUCK", "TRACKING_DEVICE", "PHONE", "EQUIPMENT"].map((t) => <option key={t}>{t}</option>)}</select></label>
                  <label className={labelClass}>Plate (vehicles)<input name="plate_number" className={inputClass} /></label>
                  <label className={labelClass}>Make<input name="make" className={inputClass} /></label>
                  <label className={labelClass}>Model<input name="model" className={inputClass} /></label>
                  <label className={labelClass}>Year<input name="year:n" type="number" className={inputClass} /></label>
                  <label className={labelClass}>Serial / IMEI (devices)<input name="serial_number" className={inputClass} /></label>
                </div>
              </CommandForm>
            </Card>
          </Section>
          <Section title="3 · Add a base">
            <Card>
              <CommandForm sub="ADMIN_CONSOLE" command="REGISTER_ESTATE" submit="Add base" success="Base added.">
                <div className="grid grid-cols-2 gap-2">
                  <label className={labelClass}>Code<input name="estate_code" required className={inputClass} /></label>
                  <label className={labelClass}>Name<input name="estate_name" required className={inputClass} /></label>
                  <label className={labelClass}>Type<select name="estate_type" className={inputClass}>{["OPERATING_HUB", "HQ", "MAINTENANCE_YARD", "STORAGE_FACILITY"].map((t) => <option key={t}>{t}</option>)}</select></label>
                  <label className={labelClass}>Jurisdiction<input name="jurisdiction" defaultValue="KISUMU_COUNTY" className={inputClass} /></label>
                  <label className={labelClass}>Latitude<input name="lat:n" type="number" step="any" required className={inputClass} /></label>
                  <label className={labelClass}>Longitude<input name="lon:n" type="number" step="any" required className={inputClass} /></label>
                </div>
              </CommandForm>
            </Card>
          </Section>
          <Section title="Bases">
            <Card>{r.estates.map((e) => <p key={e.estate_id} className="text-sm text-text-secondary">{e.name} · {e.code} · {e.type.toLowerCase().replace("_", " ")} · {e.jurisdiction}</p>)}
              {!r.estates.length && <Empty>No bases yet — add one first.</Empty>}</Card>
          </Section>
        </div>
      )}

      <Section title={`Vehicles · ${r.vehicles.length}`}>
        {!r.vehicles.length && <Empty>No vehicles registered.</Empty>}
        {r.vehicles.map((v) => (
          <Card key={v.object_id} className="flex flex-col gap-2">
            <div className="flex flex-wrap justify-between gap-2">
              <span className="text-sm text-text-primary font-semibold">{v.label} · {v.plate} <span className="text-text-muted text-xs">custodian {v.custodian ?? "—"}</span></span>
              <span className="flex gap-2"><Badge status={v.status} />{v.fleet && <Badge status={v.fleet.lifecycle} />}</span>
            </div>
            {v.fleet && <p className="text-xs text-text-muted">{v.fleet.class} · {v.fleet.ownership.toLowerCase().replace("_", " ")} · inspection {v.fleet.inspection.toLowerCase()} · insurance {v.fleet.insurance.toLowerCase()}
              {v.fleet.bound_unit ? " · in a working unit" : ""}{v.fleet.tracker ? ` · tracker ${v.fleet.tracker.device} ${v.fleet.tracker.status.toLowerCase()} (${when(v.fleet.tracker.last_seen_at)})` : " · no tracker"}</p>}
            {admin && (
              <div className="flex flex-wrap gap-2 items-end">
                {!v.fleet && OBJ_CLASS[v.type] && (
                  <CommandForm sub="ADMIN_CONSOLE" command="REGISTER_FLEET" fixed={{ object_id: v.object_id, capacity_class: OBJ_CLASS[v.type] }} submit="Add to fleet (NTSA check)" inline>
                    <select name="home_estate_id" className={`${inputClass} w-40`}>{estateOptions}</select>
                    <select name="ownership_type" className={`${inputClass} w-40`}><option value="OWNED">Owned</option><option value="LEASED">Leased</option><option value="PARTNER_CONTRIBUTED">Partner contributed</option></select>
                    <select name="inspection_status" className={`${inputClass} w-36`}><option value="PASSED">Inspection passed</option><option value="PENDING">Inspection pending</option></select>
                    <select name="insurance_status" className={`${inputClass} w-36`}><option value="ACTIVE">Insured</option><option value="PENDING">Insurance pending</option></select>
                  </CommandForm>
                )}
                {v.fleet && v.fleet.lifecycle !== "VERIFIED" && (
                  <CommandForm sub="ADMIN_CONSOLE" command="REVERIFY_FLEET" fixed={{ fleet_resource_id: v.fleet.fleet_resource_id }} submit="Re-verify" variant="ghost" inline>
                    <select name="inspection_status" className={`${inputClass} w-36`}><option value="PASSED">Inspection passed</option><option value="PENDING">Pending</option><option value="FAILED">Failed</option></select>
                    <select name="insurance_status" className={`${inputClass} w-36`}><option value="ACTIVE">Insured</option><option value="PENDING">Pending</option><option value="EXPIRED">Expired</option></select>
                  </CommandForm>
                )}
                {v.fleet && !v.fleet.tracker && r.devices.some((d) => !d.bound) && (
                  <CommandForm sub="ADMIN_CONSOLE" command="BIND_TELEMETRY_DEVICE" fixed={{ fleet_resource_id: v.fleet.fleet_resource_id }} submit="Fit tracker" variant="ghost" inline>
                    <select name="device_object_id" className={`${inputClass} w-48`}>{r.devices.filter((d) => !d.bound).map((d) => <option key={d.object_id} value={d.object_id}>{d.model} · {d.serial}</option>)}</select>
                  </CommandForm>
                )}
                {v.fleet?.tracker && <CommandForm sub="ADMIN_CONSOLE" command="UNBIND_TELEMETRY_DEVICE" fixed={{ fleet_resource_id: v.fleet.fleet_resource_id }} submit="Remove tracker" variant="ghost" inline />}
              </div>
            )}
          </Card>
        ))}
      </Section>

      <Section title={`Working units · ${r.units.length}`}>
        {!r.units.length && <Empty>No working units yet.</Empty>}
        {r.units.map((u) => (
          <Card key={u.workforce_unit_id} className="flex flex-col gap-2">
            <div className="flex flex-wrap justify-between gap-2">
              <span className="text-sm text-text-primary font-semibold">{u.operator} · {u.class}{u.plate ? ` · ${u.plate}` : ""} · {u.base}</span>
              <Badge status={u.availability} />
            </div>
            <p className="text-xs text-text-muted">Credentials: {u.capabilities.map((c) => `${c.type.toLowerCase().replaceAll("_", " ")}${c.expires_at ? ` (to ${c.expires_at.slice(0, 10)})` : ""}`).join(", ") || "none recorded"}</p>
            {admin && (
              <div className="flex flex-wrap gap-2 items-end">
                <CommandForm sub="ADMIN_CONSOLE" command="RECORD_CAPABILITY" fixed={{ workforce_unit_id: u.workforce_unit_id }} submit="Record credential" variant="ghost" inline>
                  <select name="capability_type" className={`${inputClass} w-52`}>{r.capability_types.map((t) => <option key={t} value={t}>{t.toLowerCase().replaceAll("_", " ")}</option>)}</select>
                  <input name="credential_ref" required placeholder="Certificate no." className={`${inputClass} w-36`} />
                  <input name="expires_at" type="date" className={`${inputClass} w-36`} />
                </CommandForm>
                {u.capabilities.map((c) => (
                  <CommandForm key={c.capability_id} sub="ADMIN_CONSOLE" command="REVOKE_CAPABILITY" fixed={{ capability_id: c.capability_id, reason: "Revoked by Office" }}
                    submit={`Revoke ${c.type.toLowerCase().replaceAll("_", " ")}`} variant="ghost" inline confirm="Revoke this credential?" />
                ))}
                {!["RESERVED", "ASSIGNED"].includes(u.availability) && (
                  <>
                    <CommandForm sub="ADMIN_CONSOLE" command="SET_UNIT_STATE" fixed={{ workforce_unit_id: u.workforce_unit_id, state: u.availability === "MAINTENANCE" ? "AVAILABLE" : "MAINTENANCE" }}
                      submit={u.availability === "MAINTENANCE" ? "Return to service" : "Send to maintenance"} variant="ghost" inline>
                      <input name="reason" required placeholder="Reason" className={`${inputClass} w-36`} /></CommandForm>
                    <CommandForm sub="ADMIN_CONSOLE" command="DISSOLVE_UNIT" fixed={{ workforce_unit_id: u.workforce_unit_id }} submit="Dissolve" variant="danger" inline confirm="Dissolve this working unit?">
                      <input name="reason" required placeholder="Reason" className={`${inputClass} w-36`} /></CommandForm>
                  </>
                )}
              </div>
            )}
          </Card>
        ))}
      </Section>
    </Page>
  );
}
