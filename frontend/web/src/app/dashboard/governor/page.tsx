import { project } from "@/lib/trustride";
import RequestPanel, { scopeField } from "@/components/RequestPanel";
import { Card, ErrorNote, KV, Notice, Page, Section, when } from "@/components/ui";

type Oversight = { engagement: { status: string; scope: string; since: string } | null; scopes: Record<string, Record<string, unknown>>; message: string | null };

const SCOPE_LABEL: Record<string, string> = {
  AGGREGATE_SERVICE_VOLUMES: "Completed services by family (last 30 days)",
  AGGREGATE_REVENUE_AND_TAX: "Settled revenue (last 30 days)",
  FLEET_COMPLIANCE_SUMMARY: "Fleet by class and compliance state",
  SAFETY_INCIDENT_SUMMARY: "Safety cases by status (last 90 days)",
};

function flatten(v: unknown): [string, React.ReactNode][] {
  if (!v || typeof v !== "object") return [];
  return Object.entries(v as Record<string, unknown>).flatMap(([k, x]) =>
    x && typeof x === "object" ? flatten(x).map(([kk, vv]) => [`${k} · ${kk}`, vv] as [string, React.ReactNode]) : [[k.replaceAll("_", " "), String(x)]]);
}

// Governor_App (projection GOVERNOR_OVERSIGHT): request regulatory access;
// once approved, see exactly the aggregate scopes TrustRide Office granted --
// nothing personal, nothing without a grant (Founder decision D4).
export default async function GovernorPage() {
  const { data, error } = await project<Oversight>("GOVERNOR_APP", "GOVERNOR_OVERSIGHT");
  return (
    <Page title="Oversight" intro="For regulators and authorities — for example a county revenue board. Data is aggregate and granted scope by scope by TrustRide Office.">
      <ErrorNote error={error} />
      <RequestPanel sub="GOVERNOR_APP" root="REGULATORY_ACCESS_REQUEST" command="SUBMIT_REGULATORY_REQUEST" title="Regulatory access request"
        fields={<>
          {scopeField("line.description", "Authority and purpose", "e.g. Kisumu County Revenue Board -- levy oversight")}
          {scopeField("scope.authority", "Authority name")}
          {scopeField("scope.oversight_scope", "What you need to see", "e.g. trip volumes and revenue for levy assessment")}
        </>} />
      {data?.message && <Notice>{data.message}</Notice>}
      {data?.engagement && (
        <Section title="Granted data">
          {Object.entries(data.scopes).map(([scope, v]) => (
            <Card key={scope}>
              <p className="text-text-primary font-semibold text-sm mb-2">{SCOPE_LABEL[scope] ?? scope}</p>
              <KV items={flatten(v).filter(([k]) => !k.startsWith("granted at"))} />
              <p className="text-text-muted text-xs mt-2">Granted {when(String(v.granted_at ?? ""))}</p>
            </Card>
          ))}
        </Section>
      )}
    </Page>
  );
}
