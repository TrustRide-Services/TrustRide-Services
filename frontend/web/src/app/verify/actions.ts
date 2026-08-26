"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

// The one real writer for "which of the constitutional User Type Domains
// this person is" -- fn_business_actor_register (Engine 4/Business), not
// Foundation's own unwritten user_type_binding table (a real, separate,
// previously-undiscovered platform gap, out of this increment's scope).
export async function chooseUserType(userType: string) {
  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) redirect("/login");

  const { error } = await supabase.rpc("fn_business_actor_register", {
    p_user_id: userData.user.id,
    p_user_type_domain: userType,
  });
  if (error) redirect(`/verify?error=${encodeURIComponent(error.message)}`);

  revalidatePath("/verify");
  redirect("/dashboard");
}

export async function refreshVerification() {
  revalidatePath("/verify");
}
