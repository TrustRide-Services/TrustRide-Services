import { project } from "@/lib/trustride";
import RequestPanel, { scopeField } from "@/components/RequestPanel";
import { Card, Empty, ErrorNote, KV, Page, Section, inputClass, labelClass, when } from "@/components/ui";

type Home = { engagement: { type: string; status: string; since: string; referral_code: string | null } | null;
  referrals: { first_name: string; referred_at: string; environments: string[] | null; orders_completed: number }[] };

// Intermediary_App (projection INTERMEDIARY_HOME): request a facilitation
// engagement; once approved, a referral code attributes the customers,
// vendors and partners you bring to TrustRide.
export default async function IntermediaryPage() {
  const { data, error } = await project<Home>("INTERMEDIARY_APP", "INTERMEDIARY_HOME");
  return (
    <Page title="Facilitation" intro="Bring customers, vendors and partners to TrustRide. Commission terms are set by TrustRide Office in your engagement.">
      <ErrorNote error={error} />
      <RequestPanel sub="INTERMEDIARY_APP" root="FACILITATION_REQUEST" command="SUBMIT_FACILITATION_REQUEST" title="Facilitation request"
        fields={<>
          {scopeField("line.description", "What you will facilitate", "e.g. referring boda owners in Kondele")}
          <label className={labelClass}>Role
            <select name="scope.intermediary_type" className={inputClass}>
              <option value="REFERRAL_PARTNER">Referral partner</option><option value="AGENT">Agent</option><option value="BROKER">Broker</option>
            </select>
          </label>
        </>} />
      {data?.engagement && (
        <Section title="Your engagement">
          <Card>
            <KV items={[["Type", data.engagement.type.toLowerCase().replace("_", " ")], ["Since", data.engagement.since],
              ["Referral code", <span key="c" className="font-display text-gold-light text-lg">{data.engagement.referral_code}</span>]]} />
            <p className="text-text-muted text-xs mt-2">People enter this code in their Profile once; it cannot be changed afterwards.</p>
          </Card>
        </Section>
      )}
      <Section title={`Referrals · ${data?.referrals.length ?? 0}`}>
        {!data?.referrals.length && <Empty>No referrals yet.</Empty>}
        {data?.referrals.map((r, i) => (
          <Card key={i} className="flex justify-between text-sm">
            <span className="text-text-primary">{r.first_name} · {(r.environments ?? []).join(", ").toLowerCase()}</span>
            <span className="text-text-muted">{r.orders_completed} completed orders · {when(r.referred_at)}</span>
          </Card>
        ))}
      </Section>
    </Page>
  );
}
