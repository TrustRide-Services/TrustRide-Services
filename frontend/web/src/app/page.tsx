import Image from "next/image";
import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

// The true first screen -- rendered fresh on the server for every visit
// (this whole app is dynamic, no static export). Already-signed-in
// visitors are sent straight to /dashboard rather than seeing the pitch
// again.
export default async function Home() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getUser();
  if (data.user) redirect("/dashboard");

  return (
    <main className="flex flex-1 flex-col items-center justify-center bg-bg-deepest px-6 py-16 relative">
      <div className="absolute top-0 left-0 right-0 h-[3px] bg-gold" />
      <div className="flex flex-col items-center max-w-md w-full">
        <Image src="/trustride-logo.png" alt="TrustRide" width={168} height={168} priority className="mb-7" />
        <h1 className="text-2xl font-bold text-text-primary text-center tracking-tight">Welcome to TrustRide Services.</h1>
        <p className="text-base font-semibold text-gold-light text-center mt-1.5 mb-9">How may I help you?</p>

        <div className="flex gap-3.5 w-full">
          <Link
            href="/login"
            className="flex-1 py-4 rounded-xl text-center font-bold text-gold border-[1.5px] border-gold tracking-wide"
          >
            Log In
          </Link>
          <Link
            href="/register"
            className="flex-1 py-4 rounded-xl text-center font-bold text-on-gold bg-gold tracking-wide"
          >
            Sign Up
          </Link>
        </div>

        <Link href="/login?mode=forgot" className="mt-5 text-sm text-text-secondary">
          Forgot password?
        </Link>
      </div>

      <p className="absolute bottom-7 text-xs italic text-text-muted tracking-wide">more than a ride — we save you time.</p>
    </main>
  );
}
