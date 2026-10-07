"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { refresh } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { command, humanize } from "@/lib/trustride";
import { ACTING_COOKIE, SESSION_COOKIE, type SubShell } from "@/lib/shells";

export type ActionState = { ok?: boolean; error?: string | null; message?: string | null; signal?: string | null } | null;

// The one generic way a screen issues an Engine 11 command. Form fields
// become the command payload: "name" is text, "name:n" a number, "name:b" a
// checkbox, "name:j" JSON; "__payload" (JSON) supplies structured parts.
// The database decides whether this person may issue it on this surface.
export async function runCommandAction(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const sub = String(formData.get("__sub") ?? "") as SubShell;
  const cmd = String(formData.get("__cmd") ?? "");
  let payload: Record<string, unknown> = {};
  try {
    payload = JSON.parse(String(formData.get("__payload") ?? "{}"));
  } catch {
    return { error: "The form could not be read." };
  }
  // "line.description" and "scope.<key>" build a one-line request:
  // { scope_lines: [{ line_description, scope_detail: { ... } }] }.
  const scope: Record<string, unknown> = {};
  let lineDescription: string | null = null;
  for (const [key, raw] of formData.entries()) {
    if (key.startsWith("__") || key.startsWith("$ACTION")) continue;
    const [name, type] = key.split(":");
    const value = String(raw);
    let v: unknown;
    if (type === "b") v = value === "on" || value === "true";
    else if (value === "") continue;
    else if (type === "n") v = Number(value);
    else if (type === "j") v = JSON.parse(value);
    else v = value;
    if (name === "line.description") lineDescription = String(v);
    else if (name.startsWith("scope.")) scope[name.slice(6)] = v;
    else payload[name] = v;
  }
  if (lineDescription !== null || Object.keys(scope).length) {
    payload.scope_lines = [{ line_description: lineDescription ?? "Request", scope_detail: scope }];
  }
  const result = await command(sub, cmd, payload);
  if (!result.ok) return { error: result.error };
  refresh();
  const success = String(formData.get("__success") ?? "") || "Done.";
  const go = String(formData.get("__redirect") ?? "");
  if (go) redirect(go.replace("{signal}", result.signal ?? ""));
  return { ok: true, message: success, signal: result.signal };
}

export async function signOutAction() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  const jar = await cookies();
  for (const c of jar.getAll()) if (c.name.startsWith("trs_")) jar.delete(c.name);
  redirect("/");
}

// Act for an entity you represent on Business and Marketplace surfaces (or
// for yourself again). Sessions are re-opened under the new identity; the
// database refuses an identity you do not represent.
export async function setActingIdentityAction(formData: FormData) {
  const id = String(formData.get("acting") ?? "");
  const jar = await cookies();
  if (id) jar.set(ACTING_COOKIE, id, { httpOnly: true, sameSite: "lax", secure: true, path: "/" });
  else jar.delete(ACTING_COOKIE);
  for (const c of jar.getAll()) if (c.name.startsWith("trs_s_")) jar.delete(c.name);
  redirect(String(formData.get("next") ?? "/dashboard"));
}

// --------------------------------------------- identity & contact (Foundation)
async function rpc(fn: string, args: Record<string, unknown>): Promise<ActionState> {
  const supabase = await createClient();
  const { error } = await supabase.rpc(fn, args);
  if (error) return { error: humanize(error.message) };
  refresh();
  return { ok: true, message: "Saved." };
}

// "owner" is present only when acting for an organisation (Profile); the
// Gate and a person's own Profile always manage their own contacts.
export async function addContactAction(_p: ActionState, fd: FormData): Promise<ActionState> {
  const owner = String(fd.get("owner") ?? "");
  const args = { p_contact_type: String(fd.get("type")), p_contact_value: String(fd.get("value") ?? "") };
  const r = owner ? await rpc("fn_user_contact_add_for", { p_owner: owner, ...args }) : await rpc("fn_user_contact_add", args);
  return r?.ok ? { ok: true, message: "We sent a code to verify it." } : r;
}
export async function verifyContactAction(_p: ActionState, fd: FormData): Promise<ActionState> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("fn_user_contact_verify", { p_contact_id: String(fd.get("contact_id")), p_code: String(fd.get("code") ?? "") });
  if (error) return { error: humanize(error.message) };
  if (data !== true) return { error: "That code is not right. Check the message and try again." };
  refresh();
  return { ok: true, message: "Verified." };
}
export async function resendCodeAction(_p: ActionState, fd: FormData): Promise<ActionState> {
  const r = await rpc("fn_user_contact_send_code", { p_contact_id: String(fd.get("contact_id")) });
  return r?.ok ? { ok: true, message: "A new code is on its way." } : r;
}
export async function setPrimaryContactAction(_p: ActionState, fd: FormData) {
  return rpc("fn_user_contact_set_primary", { p_contact_id: String(fd.get("contact_id")) });
}
export async function removeContactAction(_p: ActionState, fd: FormData) {
  return rpc("fn_user_contact_remove", { p_contact_id: String(fd.get("contact_id")) });
}
export async function setPreferenceAction(_p: ActionState, fd: FormData) {
  const owner = String(fd.get("owner") ?? "");
  const args = {
    p_channel: String(fd.get("channel")), p_allowed: fd.get("allowed") === "on",
    p_allowed_from: String(fd.get("from") ?? "") || null, p_allowed_to: String(fd.get("to") ?? "") || null,
  };
  return owner ? rpc("fn_user_contact_preference_set_for", { p_owner: owner, ...args }) : rpc("fn_user_contact_preference_set", args);
}
export async function declareKraAction(_p: ActionState, fd: FormData) {
  return rpc("fn_registration_declare_kra_pin", { p_kra_pin: String(fd.get("kra_pin") ?? "") });
}
export async function registerEntityAction(_p: ActionState, fd: FormData): Promise<ActionState> {
  const r = await rpc("fn_registration_capture_entity", {
    p_legal_name: String(fd.get("legal_name") ?? ""), p_entity_type: String(fd.get("entity_type") ?? ""),
    p_registration_number: String(fd.get("registration_number") ?? ""), p_kra_pin: String(fd.get("kra_pin") ?? "") || null,
    p_county_code: String(fd.get("county_code") ?? "") || null,
  });
  return r?.ok ? { ok: true, message: "Submitted for verification with the Business Registration Service and KRA." } : r;
}
export async function markNotificationsReadAction(fd: FormData) {
  const sub = String(fd.get("sub")) as SubShell;
  const sid = (await cookies()).get(SESSION_COOKIE(sub))?.value?.split(":")[1];
  if (sid) {
    const supabase = await createClient();
    await supabase.rpc("fn_present_notifications_mark_read", { p_session: sid });
  }
  refresh();
}
