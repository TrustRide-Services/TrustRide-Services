import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { ACCESS_COOKIE, ACTING_COOKIE, SESSION_COOKIE, TOP_OF, type SubShell } from "@/lib/shells";

export type { SubShell, TopShell } from "@/lib/shells";
export { ACCESS_COOKIE } from "@/lib/shells";
export type Environment = "CUSTOMER" | "PARTNER" | "GOVERNOR" | "INTERMEDIARY" | "OPERATOR";

// Every screen reads through Engine 11's lawful projections and every action
// goes through its command capture. The database decides who may do what;
// this file only carries the call.

// ------------------------------------------------------------------ Gate
export type GateContext = {
  user_id: string;
  registered: boolean;
  display_name: string | null;
  identity_status: string | null;
  identity_primitive: string | null;
  verification_failed_reasons: string[] | null;
  phone_verified: boolean;
  environments: { domain: Environment; status: string }[];
  roles: string[];
  founder_exists: boolean;
  has_working_unit: boolean;
  represented_entities: { user_id: string; legal_name: string; entity_type: string; status: string; membership_role: string;
    environments: { domain: Environment; status: string }[] }[];
  verification: { outcome: string; type: string } | null;
  office_request: { order_code: string; status: string; surface: string; response: string | null } | null;
  phone_contact: { contact_id: string; value: string; is_verified: boolean } | null;
  simulated_messages: { channel: string; body: string; at: string }[];
};

export async function gateContext(): Promise<GateContext | null> {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return null;
  const { data, error } = await supabase.rpc("fn_present_gate_context_v2");
  if (error) throw new Error(humanize(error.message));
  return data as GateContext;
}

export function envStatus(ctx: GateContext, env: Environment): string | undefined {
  return ctx.environments.find((e) => e.domain === env)?.status;
}

export function officeAccess(ctx: GateContext) {
  const has = (r: string) => ctx.roles.includes(r);
  const founder = has("FOUNDER");
  return {
    founder,
    admin: founder || has("ADMINISTRATOR"),
    executive: founder || has("EXECUTIVE"),
    operator: envStatus(ctx, "OPERATOR") === "ACTIVE" || has("DISPATCHER"),
  };
}

// --------------------------------------------------------- System Access
export async function recordSystemAccess(intent: "REGISTER" | "AUTHENTICATE" | "RESUME_SESSION") {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("fn_present_system_access_record", {
    p_channel_type: "WEB",
    p_intent: intent,
    p_registrant_class: "NATURAL_PERSON",
  });
  if (error) throw error;
  return data as string;
}

export async function bindSystemAccess(accessId: string, step: "REGISTRATION" | "AUTHENTICATED" | "SESSION_RESUMED") {
  const supabase = await createClient();
  const { error } = await supabase.rpc("fn_present_system_access_bind", { p_access_id: accessId, p_gate_step: step });
  if (error) throw error;
  (await cookies()).set(ACCESS_COOKIE, accessId, { httpOnly: true, sameSite: "lax", secure: true, path: "/" });
}

// ------------------------------------------------------- Shell sessions
// Business and Marketplace surfaces may act for an entity the person
// represents (a company, a county authority); Office never does.
async function actingIdentity(sub: SubShell, selfId: string): Promise<string> {
  if (TOP_OF[sub] === "TRUSTRIDE_OFFICE") return selfId;
  return (await cookies()).get(ACTING_COOKIE)?.value || selfId;
}

async function openSession(sub: SubShell): Promise<{ id: string } | { error: string }> {
  const supabase = await createClient();
  const { data: auth } = await supabase.auth.getUser();
  if (!auth.user) return { error: "Sign in first." };
  const jar = await cookies();
  const acting = await actingIdentity(sub, auth.user.id);
  const { data, error } = await supabase.rpc("fn_present_shell_session_open", {
    p_top_shell: TOP_OF[sub],
    p_sub_shell: sub,
    p_user_id: acting,
    p_channel_type: "WEB",
    p_access_id: jar.get(ACCESS_COOKIE)?.value ?? null,
  });
  if (error) return { error: humanize(error.message) };
  try {
    // Only Server Actions may set cookies; during a render this throws and
    // the middleware keeps the cookie fresh instead.
    jar.set(SESSION_COOKIE(sub), `${acting}:${data}`, { httpOnly: true, sameSite: "lax", secure: true, path: "/", maxAge: 60 * 60 * 8 });
  } catch {}
  return { id: data as string };
}

async function shellSession(sub: SubShell, fresh = false): Promise<{ id: string } | { error: string }> {
  if (!fresh) {
    const supabase = await createClient();
    const { data: auth } = await supabase.auth.getUser();
    if (!auth.user) return { error: "Sign in first." };
    const raw = (await cookies()).get(SESSION_COOKIE(sub))?.value;
    const acting = await actingIdentity(sub, auth.user.id);
    if (raw) {
      const [owner, id] = raw.split(":");
      if (owner === acting && id) return { id };
    }
  }
  return openSession(sub);
}

// ---------------------------------------------------------- Projections
export async function project<T = Record<string, unknown>>(sub: SubShell, code: string, params: Record<string, unknown> = {}):
  Promise<{ data: T; error: null } | { data: null; error: string }> {
  const supabase = await createClient();
  for (const fresh of [false, true]) {
    const s = await shellSession(sub, fresh);
    if ("error" in s) return { data: null, error: s.error };
    const { data, error } = await supabase.rpc("fn_present_projection", { p_session: s.id, p_code: code, p_params: params });
    if (!error) return { data: data as T, error: null };
    if (!fresh && error.message.includes("SESSION_INVALID")) continue;
    return { data: null, error: humanize(error.message) };
  }
  return { data: null, error: "Could not open your shell" };
}

// ------------------------------------------------------------- Commands
export type CommandResult = { ok: boolean; error: string | null; signal: string | null; commandId: string | null };

export async function command(sub: SubShell, commandType: string, payload: Record<string, unknown>): Promise<CommandResult> {
  const supabase = await createClient();
  for (const fresh of [false, true]) {
    const s = await shellSession(sub, fresh);
    if ("error" in s) return { ok: false, error: s.error, signal: null, commandId: null };
    const { data, error } = await supabase.rpc("fn_present_command_execute", { p_session: s.id, p_command_type: commandType, p_payload: payload });
    if (error) {
      if (!fresh && error.message.includes("SESSION_INVALID")) continue;
      return { ok: false, error: humanize(error.message), signal: null, commandId: null };
    }
    const r = data as { command_id: string; status: string; reason: string | null; signal: string | null };
    if (r.status === "TRANSLATED") return { ok: true, error: null, signal: r.signal, commandId: r.command_id };
    if (r.status === "CAPTURED") return { ok: false, error: "This action is recorded but has no live handler yet.", signal: null, commandId: r.command_id };
    return { ok: false, error: humanize(r.reason ?? "Rejected"), signal: null, commandId: r.command_id };
  }
  return { ok: false, error: "Could not open your shell", signal: null, commandId: null };
}

// Database messages are written for people already; strip the function
// prefixes and technical tails.
export function humanize(message: string): string {
  return message
    .replace(/^(ERROR:\s*)?/, "")
    .replace(/^(fn_[a-z0-9_]+|present_command_capture [0-9a-f-]+):\s*/i, "")
    .replace(/\s*\(FDN-001[^)]*\)/g, "")
    .replace(/^SESSION_INVALID:\s*/, "")
    .trim();
}

// The Business sub-shell a person's shared pages (profile, support, inbox)
// open on: Customer_App if they hold it, else the request surface they hold.
export function businessSub(ctx: GateContext): SubShell {
  if (envStatus(ctx, "CUSTOMER")) return "CUSTOMER_APP";
  if (envStatus(ctx, "PARTNER")) return "PARTNER_APP";
  if (envStatus(ctx, "GOVERNOR")) return "GOVERNOR_APP";
  if (envStatus(ctx, "INTERMEDIARY")) return "INTERMEDIARY_APP";
  return "CUSTOMER_APP";
}

// The Office sub-shell a shared Office page opens on: Admin Console for
// Administrators (and the Founder), Executive Dashboard for Executives.
export function officeSub(ctx: GateContext): SubShell {
  return officeAccess(ctx).admin ? "ADMIN_CONSOLE" : "EXECUTIVE_DASHBOARD";
}
