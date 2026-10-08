import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

// Where Supabase Auth email links land (password reset today): the one-time
// code is exchanged for a session cookie, then the person continues to
// `next` -- a path on this site only, never an outside address.
export async function GET(request: NextRequest) {
  const url = request.nextUrl;
  const code = url.searchParams.get("code");
  const nextParam = url.searchParams.get("next") ?? "/verify";
  const next = nextParam.startsWith("/") && !nextParam.startsWith("//") ? nextParam : "/verify";

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) return NextResponse.redirect(new URL(next, url.origin));
  }
  const failed = new URL("/login", url.origin);
  failed.searchParams.set("error", "That link has expired or was already used. Request a new one.");
  return NextResponse.redirect(failed);
}
