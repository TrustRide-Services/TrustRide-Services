"use server";

import { createClient } from "@/lib/supabase/server";
import { humanize } from "@/lib/trustride";
import { refresh } from "next/cache";

export type IssueState = { key?: string; error?: string } | null;

// Issuing a system credential is deliberately not a captured command: the
// secret must never be stored in a command record. Foundation checks the
// caller is Founder/Administrator, stores only a hash, and audits the issue;
// the key is returned here once and shown once.
export async function issueCredentialAction(_p: IssueState, fd: FormData): Promise<IssueState> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("fn_external_system_credential_issue", {
    p_system_user_id: String(fd.get("system_user_id")),
    p_scopes: fd.getAll("scopes").map(String),
    p_valid_days: Number(fd.get("valid_days") ?? 365),
  });
  if (error) return { error: humanize(error.message) };
  refresh();
  return { key: String(data) };
}
