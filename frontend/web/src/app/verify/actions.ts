"use server";

import { cookies } from "next/headers";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { ACCESS_COOKIE, type Environment } from "@/lib/trustride";

// Post-authorization routing (TRS026-ENG011-PRESENT-003 Sec.4, Sec.6).
// Customer activates immediately; Partner, Governor and Intermediary register
// PENDING and go straight to the surface where they submit their request --
// the database decides status, this only records the choice and routes.
const DESTINATION: Record<Exclude<Environment, "OPERATOR">, string> = {
  CUSTOMER: "/dashboard",
  PARTNER: "/dashboard/partner",
  GOVERNOR: "/dashboard/governor",
  INTERMEDIARY: "/dashboard/intermediary",
};

export async function chooseEnvironment(env: Exclude<Environment, "OPERATOR">, destination?: string) {
  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) redirect("/login");

  const { error } = await supabase.rpc("fn_business_actor_register", {
    p_user_id: userData.user.id,
    p_user_type_domain: env,
  });
  if (error) redirect(`/verify?error=${encodeURIComponent(error.message)}`);

  revalidatePath("/verify");
  redirect(destination ?? DESTINATION[env]);
}

export async function enterMarketplaceAsBuyer() {
  await chooseEnvironment("CUSTOMER", "/marketplace");
}

export async function requestOfficeAccess(formData: FormData) {
  const surface = String(formData.get("surface") ?? "");
  const justification = String(formData.get("justification") ?? "").trim();
  const supabase = await createClient();
  const accessId = (await cookies()).get(ACCESS_COOKIE)?.value ?? null;

  const { error } = await supabase.rpc("fn_present_office_access_request", {
    p_office_surface: surface,
    p_justification: justification,
    p_access_id: accessId,
  });
  if (error) redirect(`/verify?error=${encodeURIComponent(error.message)}`);

  revalidatePath("/verify");
  redirect("/verify?notice=office-requested");
}

// The one-time genesis path (fn_founder_bootstrap): offered only while no
// Founder exists, and only to a verified identity.
export async function claimFounder() {
  const supabase = await createClient();
  const { error } = await supabase.rpc("fn_founder_bootstrap");
  if (error) redirect(`/verify?error=${encodeURIComponent(error.message)}`);
  revalidatePath("/verify");
  redirect("/office");
}

export async function refreshVerification() {
  revalidatePath("/verify");
}
