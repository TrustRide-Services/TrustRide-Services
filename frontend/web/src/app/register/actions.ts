"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { bindSystemAccess, recordSystemAccess } from "@/lib/trustride";

// The one shell a brand-new visitor sees: account credentials and identity
// details captured together, submitted once. auth.signUp() and
// fn_registration_capture_primary run back-to-back against the same
// server-side client within this single action, so the freshly-created
// session is already live for the RPC call -- no separate "now log in"
// step in between for the common case (email confirmation off). Where
// confirmation is required, there's no session yet to register against;
// the person is told to confirm and returns through /register once
// signed in, which then falls through to the shorter finish-registration
// form below.
export async function signUpAndRegister(_prevState: unknown, formData: FormData) {
  const legalName = String(formData.get("legalName") ?? "").trim();
  const nationalId = String(formData.get("nationalId") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const consent = formData.get("consent") === "on";
  const phone = String(formData.get("phone") ?? "").trim();

  if (!legalName) return { error: "Enter your full legal name, as on your ID." };
  if (!nationalId) return { error: "TrustRide verifies every identity -- enter your national ID number." };
  if (!email || !password) return { error: "Enter an email and password." };
  if (!consent) return { error: "TrustRide needs your consent under the Data Protection Act to proceed." };

  // Sovereign Gate step 1: System Access is recorded before anything else --
  // before the account even exists (TRS026-ENG011-PRESENT-003 Sec.3.1).
  const accessId = await recordSystemAccess("REGISTER");

  const supabase = await createClient();
  const { data, error: signUpError } = await supabase.auth.signUp({ email, password });
  if (signUpError) return { error: signUpError.message };

  if (!data.session) {
    return {
      error: null,
      notice: "Account created. Check your email to confirm it, then log in to finish registration.",
    };
  }

  const { error: regError } = await supabase.rpc("fn_registration_capture_primary", {
    p_full_legal_name: legalName,
    p_national_id: nationalId,
    p_consent_given: true,
  });
  if (regError) return { error: regError.message };
  await capturePhone(supabase, phone);

  await bindSystemAccess(accessId, "REGISTRATION");
  redirect("/verify");
}

// Article 20.1's Registration + the opening half of Identity Verification,
// captured in one real server-side call: fn_registration_capture_primary
// creates platform_users, person_profile, and a real PENDING
// verification_record, then hands off to Integration (Article 33 --
// Foundation never calls the government identity authority itself).
// Reached only when a session already exists without a profile yet (e.g.
// returning after confirming an email) -- the credentials step is done,
// so only name/ID/consent are asked here.
export async function submitRegistration(_prevState: unknown, formData: FormData) {
  const legalName = String(formData.get("legalName") ?? "").trim();
  const nationalId = String(formData.get("nationalId") ?? "").trim();
  const consent = formData.get("consent") === "on";
  const phone = String(formData.get("phone") ?? "").trim();

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
  await capturePhone(supabase, phone);

  redirect("/verify");
}

// The phone (M-Pesa and SMS, D3) is captured with the identity and a code
// sent at once. Best effort: a number Foundation refuses is asked for again
// at the Gate, with the reason, rather than failing the registration.
async function capturePhone(supabase: Awaited<ReturnType<typeof createClient>>, phone: string) {
  if (!phone) return;
  await supabase.rpc("fn_user_contact_add", { p_contact_type: "PHONE", p_contact_value: phone });
}
