import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";

// Engine 11 v3.0.0 (TRS026-ENG011-PRESENT-003): exactly three main sovereign
// shells, each with its own sub-shells. The database enforces who may open
// which -- this file only names them.
export type TopShell = "TRUSTRIDE_OFFICE" | "TRUSTRIDE_BUSINESS" | "TRUSTRIDE_MARKETPLACE";
export type SubShell =
  | "OPERATOR_APP"
  | "ADMIN_CONSOLE"
  | "EXECUTIVE_DASHBOARD"
  | "CUSTOMER_APP"
  | "PARTNER_APP"
  | "GOVERNOR_APP"
  | "INTERMEDIARY_APP"
  | "MARKETPLACE_APP"
  | "VENDOR_APP";

export type Environment = "CUSTOMER" | "PARTNER" | "GOVERNOR" | "INTERMEDIARY" | "OPERATOR";

export const ACCESS_COOKIE = "trs_access_id";

// System Access is the first record of every visit (Sec.3.1). The id rides
// in a browser-session cookie so every shell session opened during the visit
// is linked back to the access event that began it.
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

export async function openShellSession(topShell: TopShell, subShell: SubShell): Promise<string> {
  const supabase = await createClient();
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData.user) throw userErr ?? new Error("Not signed in");

  const accessId = (await cookies()).get(ACCESS_COOKIE)?.value;
  const { data, error } = await supabase.rpc("fn_present_shell_session_open", {
    p_top_shell: topShell,
    p_sub_shell: subShell,
    p_user_id: userData.user.id,
    p_channel_type: "WEB",
    p_access_id: accessId ?? null,
  });
  if (error) throw error;
  return data as string;
}

// Every human action passes through Engine 11's command capture before any
// signal exists -- never a direct table write.
export async function captureCommand(topShell: TopShell, subShell: SubShell, commandType: string, payload: Record<string, unknown>) {
  const supabase = await createClient();
  const sessionId = await openShellSession(topShell, subShell);

  const { data: commandId, error } = await supabase.rpc("fn_present_capture_command", {
    p_shell_session_id: sessionId,
    p_command_type: commandType,
    p_command_payload: payload,
  });
  if (error) throw error;

  const { data: result, error: readErr } = await supabase
    .from("present_command_capture")
    .select("command_id, translation_status, translated_signal_id, rejection_reason")
    .eq("command_id", commandId)
    .single();
  if (readErr) throw readErr;
  return result as { command_id: string; translation_status: string; translated_signal_id: string | null; rejection_reason: string | null };
}

// Who is this person, as far as routing is concerned: identity status, every
// environment they hold (with its status), and any Office authority role.
export async function getActorContext() {
  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData.user) return null;

  const [{ data: profile }, { data: registrations }, founder, admin, executive] = await Promise.all([
    supabase.from("platform_users").select("user_id, display_name, status").eq("user_id", userData.user.id).maybeSingle(),
    supabase
      .from("business_actor_registration")
      .select("user_type_domain, registration_status, registered_at")
      .eq("user_id", userData.user.id)
      .order("registered_at", { ascending: false }),
    supabase.rpc("fn_am_i_role", { p_role_codes: ["FOUNDER"] }),
    supabase.rpc("fn_am_i_role", { p_role_codes: ["ADMINISTRATOR"] }),
    supabase.rpc("fn_am_i_role", { p_role_codes: ["EXECUTIVE"] }),
  ]);

  const envStatus = new Map<Environment, string>();
  for (const r of registrations ?? []) envStatus.set(r.user_type_domain as Environment, r.registration_status);

  const isFounder = founder.data === true;
  const office = {
    admin: isFounder || admin.data === true,
    executive: isFounder || executive.data === true,
    operator: isFounder || envStatus.get("OPERATOR") === "ACTIVE",
  };

  return {
    user: userData.user,
    profile,
    envStatus,
    isFounder,
    office,
    isStaff: office.admin || office.executive || office.operator,
  };
}

export type ActorContext = NonNullable<Awaited<ReturnType<typeof getActorContext>>>;
