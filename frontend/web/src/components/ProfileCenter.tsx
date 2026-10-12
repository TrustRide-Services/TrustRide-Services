import { gateContext, project } from "@/lib/trustride";
import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";
import { ACTING_COOKIE, TOP_OF, type SubShell } from "@/lib/shells";
import ActionForm from "@/components/ActionForm";
import CommandForm from "@/components/CommandForm";
import {
  addContactAction, declareKraAction, registerEntityAction, removeContactAction, resendCodeAction, secondaryProfileAction, setPreferenceAction,
  setPrimaryContactAction, verifyContactAction,
} from "@/app/actions";
import { Badge, Card, Empty, ErrorNote, KV, Notice, Page, Section, inputClass, labelClass, when } from "@/components/ui";

type Profile = {
  identity: { display_name: string; global_uid: string; status: string; primitive: string };
  contacts: { contact_id: string; type: string; value: string; is_primary: boolean; is_verified: boolean }[];
  preferences: { channel: string; allowed: boolean; from: string | null; to: string | null }[];
  kra_pin: { value: string; status: string } | null;
  referral_applied: boolean;
  simulated_messages: { channel: string; body: string; at: string }[];
};
type Secondary = {
  address: { address_line_1: string; town: string | null; county_code: string | null; ward: string | null; estate: string | null; since: string } | null;
  socioeconomic: { income_band: string | null; household_size: number | null; primary_language: string | null; recorded_at: string } | null;
  education: { education_level: string; institution: string | null; qualification: string | null; year_completed: number | null }[];
};

// Profile (projection MY_PROFILE): Foundation's one authoritative contact
// register (D3) -- the verified phone pays by M-Pesa and receives SMS.
export default async function ProfileCenter({ sub, referralSub }: { sub: SubShell; referralSub?: SubShell }) {
  const [{ data: p, error }, ctx] = await Promise.all([project<Profile>(sub, "MY_PROFILE"), gateContext()]);
  if (!p) return <Page title="Profile"><ErrorNote error={error} /></Page>;
  const pref = (c: string) => p.preferences.find((x) => x.channel === c);
  // Acting for an organisation: its contacts are managed here by its
  // representative (the database checks the representation).
  const acting = TOP_OF[sub] === "TRUSTRIDE_OFFICE" ? "" : (await cookies()).get(ACTING_COOKIE)?.value ?? "";
  const owner = ctx?.represented_entities.some((e) => e.user_id === acting) ? acting : "";
  const ownerField = owner ? <input type="hidden" name="owner" value={owner} /> : null;
  // The secondary profile belongs to a person, on their own identity only.
  const second = !owner && p.identity.primitive === "PERSON"
    ? ((await (await createClient()).rpc("fn_my_secondary_profile")).data as Secondary | null) : null;
  return (
    <Page title="Profile" intro={`${p.identity.display_name} · ${p.identity.global_uid}`}>
      <Section title="Contact methods">
        <Card className="flex flex-col gap-3">
          {p.contacts.length === 0 && <Empty>No contact methods yet. Add your phone number — it is your M-Pesa payment number.</Empty>}
          {p.contacts.map((c) => (
            <div key={c.contact_id} className="flex flex-wrap items-center justify-between gap-2 border-b border-border pb-3 last:border-0 last:pb-0">
              <div className="text-sm">
                <span className="text-text-primary font-semibold">{c.value}</span>{" "}
                <span className="text-text-muted text-xs">{c.type.toLowerCase()}{c.is_primary ? " · primary" : ""}</span>{" "}
                <Badge status={c.is_verified ? "VERIFIED" : "PENDING"} text={c.is_verified ? "Verified" : "Not verified"} />
              </div>
              <div className="flex flex-wrap gap-2 items-end">
                {!c.is_verified && (
                  <>
                    <ActionForm action={verifyContactAction} submit="Verify" inline>
                      <input type="hidden" name="contact_id" value={c.contact_id} />
                      <input name="code" inputMode="numeric" maxLength={6} placeholder="6-digit code" className={`${inputClass} w-32`} />
                    </ActionForm>
                    <ActionForm action={resendCodeAction} submit="New code" variant="ghost" inline><input type="hidden" name="contact_id" value={c.contact_id} /></ActionForm>
                  </>
                )}
                {c.is_verified && !c.is_primary && (
                  <ActionForm action={setPrimaryContactAction} submit="Make primary" variant="ghost" inline><input type="hidden" name="contact_id" value={c.contact_id} /></ActionForm>
                )}
                <ActionForm action={removeContactAction} submit="Remove" variant="ghost" inline><input type="hidden" name="contact_id" value={c.contact_id} /></ActionForm>
              </div>
            </div>
          ))}
          <ActionForm action={addContactAction} submit="Add and send code" inline>
            {ownerField}
            <label className={labelClass}>Type
              <select name="type" className={inputClass}><option value="PHONE">Phone</option><option value="WHATSAPP">WhatsApp</option><option value="EMAIL">Email</option></select>
            </label>
            <label className={`${labelClass} flex-1 min-w-48`}>Number or address<input name="value" required placeholder="0712 345 678" className={inputClass} /></label>
          </ActionForm>
        </Card>
        {p.simulated_messages.length > 0 && (
          <Notice>
            <span className="block text-[11px] uppercase tracking-wide text-gold-dim mb-1">Staging — messages a real phone would have received</span>
            {p.simulated_messages.map((m, i) => <span key={i} className="block">{when(m.at)} · {m.channel}: {m.body}</span>)}
          </Notice>
        )}
      </Section>

      <Section title="How we reach you">
        <div className="grid sm:grid-cols-3 gap-3">
          {["SMS", "WHATSAPP", "EMAIL"].map((ch) => (
            <Card key={ch}>
              <ActionForm action={setPreferenceAction} submit="Save" variant="ghost">
                {ownerField}
                <input type="hidden" name="channel" value={ch} />
                <label className="flex items-center gap-2 text-sm text-text-primary">
                  <input type="checkbox" name="allowed" defaultChecked={pref(ch)?.allowed ?? true} /> {ch === "WHATSAPP" ? "WhatsApp" : ch === "SMS" ? "SMS" : "Email"}
                </label>
                <div className="grid grid-cols-2 gap-2">
                  <label className={labelClass}>Quiet from<input type="time" name="from" defaultValue={pref(ch)?.from ?? ""} className={inputClass} /></label>
                  <label className={labelClass}>until<input type="time" name="to" defaultValue={pref(ch)?.to ?? ""} className={inputClass} /></label>
                </div>
              </ActionForm>
            </Card>
          ))}
        </div>
        <p className="text-xs text-text-muted">Urgent messages (your fare to confirm, your driver has arrived, payment) are sent even in quiet hours.</p>
      </Section>

      {second && (
        <Section title="About you (optional)">
          <p className="text-xs text-text-muted -mt-1">Not needed to use TrustRide. Recorded on your own identity only; you can update it at any time.</p>
          <div className="grid md:grid-cols-3 gap-3">
            <Card>
              <p className="text-sm text-text-primary font-semibold mb-2">Home address</p>
              {second.address && <p className="text-xs text-text-secondary mb-2">{second.address.address_line_1}{second.address.town ? `, ${second.address.town}` : ""} · county {second.address.county_code} · since {when(second.address.since)}</p>}
              <ActionForm action={secondaryProfileAction} submit="Save address" variant="ghost">
                <input type="hidden" name="category" value="ADDRESS" />
                <label className={labelClass}>Plot, building or street<input name="address_line_1" required defaultValue={second.address?.address_line_1 ?? ""} className={inputClass} /></label>
                <div className="grid grid-cols-2 gap-2">
                  <label className={labelClass}>Town<input name="town" defaultValue={second.address?.town ?? ""} className={inputClass} /></label>
                  <label className={labelClass}>County code (01–47)<input name="county_code" required maxLength={2} inputMode="numeric" placeholder="42" defaultValue={second.address?.county_code ?? ""} className={inputClass} /></label>
                  <label className={labelClass}>Ward<input name="ward" defaultValue={second.address?.ward ?? ""} className={inputClass} /></label>
                  <label className={labelClass}>Estate<input name="estate" defaultValue={second.address?.estate ?? ""} className={inputClass} /></label>
                </div>
              </ActionForm>
            </Card>
            <Card>
              <p className="text-sm text-text-primary font-semibold mb-2">Education</p>
              {second.education.length === 0 ? <p className="text-xs text-text-muted mb-2">Nothing recorded.</p> : (
                <ul className="text-xs text-text-secondary mb-2 flex flex-col gap-0.5">
                  {second.education.map((e, i) => <li key={i}>{e.education_level}{e.qualification ? ` · ${e.qualification}` : ""}{e.institution ? ` · ${e.institution}` : ""}{e.year_completed ? ` (${e.year_completed})` : ""}</li>)}
                </ul>
              )}
              <ActionForm action={secondaryProfileAction} submit="Add qualification" variant="ghost">
                <input type="hidden" name="category" value="EDUCATION" />
                <label className={labelClass}>Level<input name="education_level" required placeholder="e.g. Diploma" className={inputClass} /></label>
                <label className={labelClass}>Qualification<input name="qualification" className={inputClass} /></label>
                <label className={labelClass}>Institution<input name="institution" className={inputClass} /></label>
                <label className={labelClass}>Year completed<input name="year_completed:n" type="number" min={1940} max={new Date().getFullYear()} className={inputClass} /></label>
              </ActionForm>
            </Card>
            <Card>
              <p className="text-sm text-text-primary font-semibold mb-2">Household</p>
              {second.socioeconomic && <p className="text-xs text-text-secondary mb-2">Household of {second.socioeconomic.household_size ?? "—"} · {second.socioeconomic.primary_language ?? "language not given"} · recorded {when(second.socioeconomic.recorded_at)}</p>}
              <ActionForm action={secondaryProfileAction} submit="Save household" variant="ghost">
                <input type="hidden" name="category" value="SOCIOECONOMIC" />
                <label className={labelClass}>Household size<input name="household_size:n" type="number" min={1} max={50} defaultValue={second.socioeconomic?.household_size ?? ""} className={inputClass} /></label>
                <label className={labelClass}>Main language<input name="primary_language" defaultValue={second.socioeconomic?.primary_language ?? ""} className={inputClass} /></label>
                <label className={labelClass}>Income band (optional)<input name="income_band" defaultValue={second.socioeconomic?.income_band ?? ""} className={inputClass} /></label>
                <label className="flex items-start gap-2 text-xs text-text-secondary"><input type="checkbox" name="consent:b" className="mt-0.5" />
                  I consent to TrustRide recording this socio-economic information about me (Data Protection Act 2019).</label>
              </ActionForm>
            </Card>
          </div>
        </Section>
      )}

      <div className="grid md:grid-cols-2 gap-4">
        <Section title="KRA PIN">
          <Card>
            {p.kra_pin ? <KV items={[["PIN", p.kra_pin.value], ["Status", p.kra_pin.status === "ACTIVE" ? "Verified" : "Declared"]]} /> : (
              <ActionForm action={declareKraAction} submit="Save PIN" inline>
                <input name="kra_pin" placeholder="A001234567X" className={`${inputClass} w-40`} />
              </ActionForm>
            )}
          </Card>
        </Section>
        {referralSub && (
          <Section title="Referral">
            <Card>
              {p.referral_applied ? <p className="text-sm text-text-secondary">A referral is recorded for you.</p> : (
                <CommandForm sub={referralSub} command="APPLY_REFERRAL_CODE" submit="Apply code" inline success="Thank you — referral recorded.">
                  <input name="referral_code" placeholder="TR-XXXXXX" className={`${inputClass} w-40`} />
                </CommandForm>
              )}
            </Card>
          </Section>
        )}
      </div>

      <Section title="Companies and organisations you represent">
        <Card className="flex flex-col gap-3">
          {ctx?.represented_entities.map((e) => (
            <p key={e.user_id} className="text-sm"><span className="text-text-primary font-semibold">{e.legal_name}</span>{" "}
              <span className="text-text-muted text-xs">{e.entity_type.toLowerCase().replace("_", " ")} · {e.membership_role.toLowerCase().replace("_", " ")}</span>{" "}
              <Badge status={e.status} /></p>
          ))}
          <p className="text-xs text-text-muted">Register a company, cooperative, NGO or government body you represent. It is verified with the Business Registration Service and KRA; once active, switch to it with &ldquo;Act as&rdquo; in the header.</p>
          <ActionForm action={registerEntityAction} submit="Register for verification">
            <div className="grid sm:grid-cols-2 gap-2">
              <label className={labelClass}>Legal name<input name="legal_name" required className={inputClass} /></label>
              <label className={labelClass}>Type
                <select name="entity_type" className={inputClass}>
                  {["COMPANY", "PARTNERSHIP", "SOLE_PROPRIETORSHIP", "COOPERATIVE", "NGO", "GOVERNMENT_BODY"].map((t) => <option key={t} value={t}>{t.toLowerCase().replace("_", " ")}</option>)}
                </select>
              </label>
              <label className={labelClass}>Registration number<input name="registration_number" required className={inputClass} /></label>
              <label className={labelClass}>KRA PIN<input name="kra_pin" placeholder="P051234567X" className={inputClass} /></label>
              <label className={labelClass}>County code (e.g. 42 for Kisumu)<input name="county_code" maxLength={2} className={inputClass} /></label>
            </div>
          </ActionForm>
        </Card>
      </Section>
    </Page>
  );
}
