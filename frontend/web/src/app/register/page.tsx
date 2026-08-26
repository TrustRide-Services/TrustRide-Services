import Image from "next/image";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import RegisterForm from "./RegisterForm";

// RENDERING STRATEGY: fully dynamic. This page's only job is a gate
// (signed in? already registered?) followed by a form scoped to this one
// signed-in user -- nothing on it is shared across visitors, so there's no
// static shell worth extracting.
export default async function RegisterPage() {
  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) redirect("/login");

  const { data: profile } = await supabase.from("platform_users").select("user_id").maybeSingle();
  if (profile) redirect("/verify");

  return (
    <main className="flex flex-1 flex-col items-center justify-center bg-bg-deepest px-6 py-16">
      <Image src="/trustride-logo.png" alt="TrustRide" width={64} height={64} className="mb-4" />
      <RegisterForm email={userData.user.email} />
    </main>
  );
}
