import Image from "next/image";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import RegisterForm from "./RegisterForm";
import SignUpForm from "./SignUpForm";
import { signOutAction } from "@/app/dashboard/actions";

// RENDERING STRATEGY: fully dynamic. This is the one screen that must
// branch on whether a session already exists at all, so it's read straight
// from the request's cookies -- nothing on it is shared across visitors.
export default async function RegisterPage() {
  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();

  if (!userData.user) {
    return (
      <main className="flex flex-1 flex-col items-center justify-center px-6 py-16">
        <div className="relative mb-6">
          <div className="absolute inset-0 rounded-full bg-gold/15 blur-xl" />
          <Image src="/trustride-logo.png" alt="TrustRide" width={64} height={64} className="relative" />
        </div>
        <SignUpForm />
      </main>
    );
  }

  const { data: profile } = await supabase.from("platform_users").select("user_id").maybeSingle();
  if (profile) redirect("/verify");

  return (
    <main className="flex flex-1 flex-col items-center justify-center px-6 py-16 relative">
      <form action={signOutAction} className="absolute top-6 right-6">
        <button type="submit" className="text-sm text-text-muted hover:text-danger transition-colors">
          Sign out
        </button>
      </form>

      <div className="relative mb-6">
        <div className="absolute inset-0 rounded-full bg-gold/15 blur-xl" />
        <Image src="/trustride-logo.png" alt="TrustRide" width={64} height={64} className="relative" />
      </div>
      <RegisterForm email={userData.user.email} />
    </main>
  );
}
