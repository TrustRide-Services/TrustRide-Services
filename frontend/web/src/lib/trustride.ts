import { createClient } from "@/lib/supabase/server";

// USER_HUB's four sub-shells map directly onto Engine 4's own
// business_user_type_domain_enum (CUSTOMER, PARTNER, GOVERNOR, INTERMEDIARY --
// OPERATOR now resolves to the internal TRUSTRIDE_OPERATOR sub-shell instead,
// not something this User Hub app opens sessions into).
const SUB_SHELL_BY_USER_TYPE: Record<string, string> = {
  CUSTOMER: "CUSTOMER_APP",
  PARTNER: "PARTNER_APP",
  GOVERNOR: "GOVERNOR_APP",
  INTERMEDIARY: "INTERMEDIARY_APP",
};

// Opens (or reuses, within a single request) a real present_shell_session
// and returns its session_id -- every command capture needs one. A fresh
// session per server request is intentional: this is a genuinely
// server-rendered app, not a long-lived client session object. sub_shell is
// resolved from the caller's own active actor registration, never passed
// in by the page -- a page cannot open a session on a sub_shell its signed-in
// user doesn't actually belong to.
export async function getShellSession(): Promise<string> {
  const supabase = await createClient();
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData.user) throw userErr ?? new Error("getShellSession: no authenticated user");

  const { data: actor } = await supabase
    .from("business_actor_registration")
    .select("user_type_domain")
    .eq("registration_status", "ACTIVE")
    .order("registered_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  const subShell = SUB_SHELL_BY_USER_TYPE[actor?.user_type_domain ?? ""] ?? "CUSTOMER_APP";

  const { data, error } = await supabase.rpc("fn_present_shell_session_open", {
    p_top_shell: "USER_HUB",
    p_sub_shell: subShell,
    p_user_id: userData.user.id,
    p_channel_type: "WEB",
  });
  if (error) throw error;
  return data as string;
}

// Captures a human command through the real fn_present_capture_command
// pipeline and returns the full capture row so callers can check
// translation_status/rejection_reason -- never a raw table write.
export async function captureCommand(commandType: string, payload: Record<string, unknown>) {
  const supabase = await createClient();
  const sessionId = await getShellSession();

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
  return result;
}
