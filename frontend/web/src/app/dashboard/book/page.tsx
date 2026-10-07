import Link from "next/link";
import { project } from "@/lib/trustride";
import { Card, ErrorNote, Page, Section, inputClass, labelClass } from "@/components/ui";
import CommandForm from "@/components/CommandForm";
import BookingForm, { type Family, type Zone } from "./BookingForm";

type Catalogue = { families: Family[]; zones: Zone[]; working_hours: Record<string, string>; open_now: boolean; next_open: string;
  max_stops: number; schedule_max_days: number; phone_verified: boolean };

// Service catalogue and booking (projection SERVICE_CATALOGUE). Every one of
// the 24 services has a real path: 16 are booked here, the two intake
// services have their own forms below, and the six Marketplace services live
// in TrustRide Marketplace.
export default async function BookPage() {
  const { data, error } = await project<Catalogue>("CUSTOMER_APP", "SERVICE_CATALOGUE");
  if (!data) return <Page title="Book a service"><ErrorNote error={error} /></Page>;
  const ea = data.families.find((f) => f.domain === "EXECUTIVE_ASSISTANTS")?.services ?? [];
  const academy = ea.find((s) => s.command === "ENROLL_ACADEMY");
  const careers = ea.find((s) => s.command === "APPLY_EMPLOYMENT");
  const marketplace = data.families.find((f) => f.domain === "MARKETPLACE")?.services ?? [];
  return (
    <Page title="Book a service" intro={`Open Mon–Fri ${data.working_hours.weekday}, Sat ${data.working_hours.saturday}; Sunday is off duty. You will see and accept your fare before anyone is dispatched.`}>
      <BookingForm families={data.families} zones={data.zones} maxStops={data.max_stops} scheduleMaxDays={data.schedule_max_days}
        phoneVerified={data.phone_verified} openNow={data.open_now} nextOpen={data.next_open} />

      <div className="grid md:grid-cols-2 gap-4">
        {academy && (
          <Section title="TrustRide Academy">
            <Card>
              <p className="text-sm text-text-secondary mb-3">{academy.description} TrustRide Office confirms your place within 2–3 working days.</p>
              <CommandForm sub="CUSTOMER_APP" command="ENROLL_ACADEMY" submit="Apply to enrol" success="Enrollment request sent to TrustRide Office.">
                <label className={labelClass}>Programme
                  <select name="programme" className={inputClass}>
                    {["Professional Chauffeur", "Personal Shopper & Errands", "House Manager", "Certified Chef", "Patient & Elder Care", "Corporate Representative", "Boda Safety & Customer Care"].map((p) => <option key={p}>{p}</option>)}
                  </select>
                </label>
                <label className={labelClass}>Preferred start<input type="date" name="preferred_start" className={inputClass} /></label>
                <label className={labelClass}>Why this programme? (optional)<input name="motivation" className={inputClass} /></label>
              </CommandForm>
            </Card>
          </Section>
        )}
        {careers && (
          <Section title="Work with TrustRide">
            <Card>
              <p className="text-sm text-text-secondary mb-3">TrustRide operators and executive assistants are employees. Apply here; TrustRide Office reviews, vets and onboards you.</p>
              <CommandForm sub="CUSTOMER_APP" command="APPLY_EMPLOYMENT" submit="Apply" success="Application sent to TrustRide Office.">
                <label className={labelClass}>Role
                  <select name="role_sought" className={inputClass}>
                    {["Boda rider", "Tuk-tuk driver", "Sedan driver", "Delivery driver (pickup/van)", "Executive assistant -- errands & shopping", "Executive assistant -- driving", "Executive assistant -- caregiving", "Executive assistant -- cleaning", "Executive assistant -- chef"].map((p) => <option key={p}>{p}</option>)}
                  </select>
                </label>
                <label className={labelClass}>Experience<input name="experience" placeholder="e.g. 3 years, PSV licence" className={inputClass} /></label>
              </CommandForm>
            </Card>
          </Section>
        )}
      </div>

      {marketplace.length > 0 && (
        <Section title="Marketplace services">
          <Card className="flex flex-wrap items-center justify-between gap-3">
            <p className="text-sm text-text-secondary">Buying a vehicle, selling as a vendor and contributing vehicles are handled in TrustRide Marketplace and the Partner surface — never through dispatch.</p>
            <Link href="/marketplace" className="trs-btn-ghost rounded-lg px-4 py-2 text-sm font-semibold">Open Marketplace</Link>
          </Card>
        </Section>
      )}
    </Page>
  );
}
