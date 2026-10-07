import { gateContext, project } from "@/lib/trustride";
import type { SubShell } from "@/lib/shells";
import ActionForm from "@/components/ActionForm";
import CommandForm from "@/components/CommandForm";
import {
  addContactAction, declareKraAction, registerEntityAction, removeContactAction, resendCodeAction, setPreferenceAction,
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

// Profile (projection MY_PROFILE): Foundation's one authoritative contact
// register (D3) -- the verified phone pays by M-Pesa and receives SMS.
export default async function ProfileCenter({ sub, referralSub }: { sub: SubShell; referralSub?: SubShell }) {
  const [{ data: p, error }, ctx] = await Promise.all([project<Profile>(sub, "MY_PROFILE"), gateContext()]);
  if (!p) return <Page title="Profile"><ErrorNote error={error} /></Page>;
  const pref = (c: string) => p.preferences.find((x) => x.channel === c);
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
