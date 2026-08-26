import { createClient } from "@/lib/supabase/server";

// Opens (or reuses, within a single request) a real present_shell_session
// and returns its session_id -- every command capture needs one. A fresh
// session per server request is intentional: this is a genuinely
// server-rendered app, not a long-lived client session object.
export async function getShellSession(shellCode: string): Promise<string> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("fn_present_shell_session_open", {
    p_shell_code: shellCode,
    p_channel_type: "WEB",
  });
  if (error) throw error;
  return data as string;
}

// Captures a human command through the real fn_present_capture_command
// pipeline and returns the full capture row so callers can check
// translation_status/rejection_reason -- never a raw table write.
export async function captureCommand(shellCode: string, commandType: string, payload: Record<string, unknown>) {
  const supabase = await createClient();
  const sessionId = await getShellSession(shellCode);

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
