import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

// Refreshes the Supabase auth session on every single request -- this is
// what makes the app genuinely server-rendered per request rather than
// serving a stale session from a cached page. Runs in middleware.ts.
export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      db: { schema: "trustride" },
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
          supabaseResponse = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) => supabaseResponse.cookies.set(name, value, options));
        },
      },
    }
  );

  const { data: userData } = await supabase.auth.getUser();

  // System Access is the first record of every visit (TRS026-ENG011-PRESENT-003
  // Sec.3.1). Sign-up and login record their own; a signed-in visitor whose
  // session simply resumed is recorded here, once per browser session.
  let accessCookie: string | null = null;
  if (userData.user && !request.cookies.get("trs_access_id")) {
    const { data: accessId } = await supabase.rpc("fn_present_system_access_record", {
      p_channel_type: "WEB",
      p_intent: "RESUME_SESSION",
      p_registrant_class: "NATURAL_PERSON",
    });
    if (accessId) {
      await supabase.rpc("fn_present_system_access_bind", { p_access_id: accessId, p_gate_step: "SESSION_RESUMED" });
      accessCookie = accessId as string;
    }
  }

  // A signed-in visitor on the static "/" pitch goes to the Sovereign Gate,
  // which routes them into whichever of the three shells they hold.
  let response = supabaseResponse;
  if (userData.user && request.nextUrl.pathname === "/") {
    const url = request.nextUrl.clone();
    url.pathname = "/verify";
    response = NextResponse.redirect(url);
    supabaseResponse.cookies.getAll().forEach((c) => response.cookies.set(c));
  }
  if (accessCookie) {
    response.cookies.set("trs_access_id", accessCookie, { httpOnly: true, sameSite: "lax", secure: true, path: "/" });
  }

  return response;
}
