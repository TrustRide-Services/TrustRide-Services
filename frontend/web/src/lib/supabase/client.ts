import { createBrowserClient } from "@supabase/ssr";

// Browser-side Supabase client -- used only inside Client Components for
// interactive forms (auth, command submission). Real, live queries; no
// static/cached data.
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { db: { schema: "trustride" } }
  );
}
