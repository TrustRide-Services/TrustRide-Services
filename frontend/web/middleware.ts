import { type NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

// RENDERING STRATEGY note (applies to the whole app): this file is the one
// place session/auth state is read on every request. Individual routes
// stay static or hybrid on their own terms (see the per-page comments);
// this middleware only ever does two things -- refresh the session cookie,
// and redirect an already-authenticated visitor away from the static "/"
// pitch. It never forces a route to render dynamically by itself.
export async function middleware(request: NextRequest) {
  return await updateSession(request);
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|trustride-logo.png|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"],
};
