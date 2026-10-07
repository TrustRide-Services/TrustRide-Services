import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { ACTING_COOKIE, SESSION_COOKIE, TOP_OF, subShellForPath } from "@/lib/shells";

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

  // Keep an Engine 11 shell session ready for the surface being visited, so
  // every projection and command on the page shares one session. The
  // database decides whether this person may open it; if not, no cookie is
  // set and the page shows why.
  // A link prefetch is not a visit: opening a session for it would record a
  // shell the person never entered (every Gate link would open one).
  const prefetch = request.headers.get("next-router-prefetch") === "1" || /prefetch/i.test(request.headers.get("purpose") ?? request.headers.get("sec-purpose") ?? "");
  const sub = userData.user && !prefetch ? subShellForPath(request.nextUrl.pathname) : null;
  if (userData.user && sub) {
    const acting = TOP_OF[sub] === "TRUSTRIDE_OFFICE" ? userData.user.id : (request.cookies.get(ACTING_COOKIE)?.value || userData.user.id);
    const cached = request.cookies.get(SESSION_COOKIE(sub))?.value;
    if (!cached || cached.split(":")[0] !== acting) {
      const { data: sessionId } = await supabase.rpc("fn_present_shell_session_open", {
        p_top_shell: TOP_OF[sub],
        p_sub_shell: sub,
        p_user_id: acting,
        p_channel_type: "WEB",
        p_access_id: accessCookie ?? request.cookies.get("trs_access_id")?.value ?? null,
      });
      if (sessionId) {
        const value = `${acting}:${sessionId}`;
        request.cookies.set(SESSION_COOKIE(sub), value);
        response.cookies.set(SESSION_COOKIE(sub), value, { httpOnly: true, sameSite: "lax", secure: true, path: "/", maxAge: 60 * 60 * 8 });
      }
    }
  }

  return response;
}
