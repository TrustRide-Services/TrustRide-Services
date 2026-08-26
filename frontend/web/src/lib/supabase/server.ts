import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

// Server-side Supabase client for Server Components, Server Actions, and
// Route Handlers -- reads/writes the real session cookie so every request
// is genuinely re-authenticated and re-rendered per request, never a
// frozen client bundle. Scoped to the trustride schema, same as the RPC
// surface every engine this session was built against.
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      db: { schema: "trustride" },
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) => cookieStore.set(name, value, options));
          } catch {
            // Called from a Server Component that can't set cookies -- the
            // middleware below refreshes the session on every request, so
            // this is safe to ignore here.
          }
        },
      },
    }
  );
}
