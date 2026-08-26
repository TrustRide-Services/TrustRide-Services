import { createClient } from "@/lib/supabase/server";
import RaiseIntentForm from "./RaiseIntentForm";

// Real service_code fields required by RAISE_INTENT beyond what
// service_catalogue itself carries (asset class, engine capacity,
// jurisdiction) -- these are rate-card-specific, not catalogue-wide. A
// service present in the real catalogue but missing here is shown, but
// disabled, with an honest reason -- never silently mis-quoted.
const BOOKABLE_CODES = new Set(["TRANSPORT-BODA-STANDARD"]);
const LABELS: Record<string, string> = { "TRANSPORT-BODA-STANDARD": "Boda ride (Kisumu)" };

export default async function RaiseIntentPage() {
  const supabase = await createClient();

  const { data } = await supabase
    .from("service_catalogue")
    .select("service_id, service_code, status, service_macro_domain(domain_code)")
    .eq("status", "ACTIVE");

  const { data: actor } = await supabase
    .from("business_actor_registration")
    .select("user_type_domain")
    .eq("registration_status", "ACTIVE")
    .limit(1)
    .maybeSingle();

  type Row = { service_id: string; service_code: string; service_macro_domain: { domain_code: string } | null };
  const services = ((data as unknown as Row[]) ?? []).map((s) => ({
    service_id: s.service_id,
    service_code: s.service_code,
    macro_domain: s.service_macro_domain?.domain_code ?? null,
    bookable: BOOKABLE_CODES.has(s.service_code),
    label: LABELS[s.service_code] ?? s.service_code,
  }));

  return <RaiseIntentForm services={services} userTypeDomain={actor?.user_type_domain ?? "CUSTOMER"} />;
}
