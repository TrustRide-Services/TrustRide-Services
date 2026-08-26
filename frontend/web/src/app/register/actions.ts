"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

// Article 20.1's Registration + the opening half of Identity Verification,
// captured in one real server-side call: fn_registration_capture_primary
// creates platform_users, person_profile, and a real PENDING
// verification_record, then hands off to Integration (Article 33 --
// Foundation never calls the government identity authority itself).
export async function submitRegistration(_prevState: unknown, formData: FormData) {
  const legalName = String(formData.get("legalName") ?? "").trim();
  const nationalId = String(formData.get("nationalId") ?? "").trim();
  const consent = formData.get("consent") === "on";

  if (!legalName) return { error: "Enter your full legal name, as on your ID." };
  if (!nationalId) return { error: "TrustRide verifies every identity -- enter your national ID number." };
  if (!consent) return { error: "TrustRide needs your consent under the Data Protection Act to proceed." };

  const supabase = await createClient();
  const { error } = await supabase.rpc("fn_registration_capture_primary", {
    p_full_legal_name: legalName,
    p_national_id: nationalId,
    p_consent_given: true,
  });
  if (error) return { error: error.message };

  redirect("/verify");
}
