"use server";

import { revalidatePath } from "next/cache";
import { captureCommand, type SubShell } from "@/lib/trustride";

export type RequestEnv = "PARTNER" | "GOVERNOR" | "INTERMEDIARY";

const ROUTE: Record<RequestEnv, { subShell: SubShell; command: string }> = {
  PARTNER: { subShell: "PARTNER_APP", command: "SUBMIT_PARTNERSHIP_REQUEST" },
  GOVERNOR: { subShell: "GOVERNOR_APP", command: "SUBMIT_REGULATORY_REQUEST" },
  INTERMEDIARY: { subShell: "INTERMEDIARY_APP", command: "SUBMIT_FACILITATION_REQUEST" },
};

// One request, one or more scope lines (TRS026-ENG011-PRESENT-003 Sec.4.2-4.4):
// each non-empty line of the scope box becomes its own scope line.
export async function submitActorRequest(env: RequestEnv, _prev: unknown, formData: FormData) {
  const scopeText = String(formData.get("scope") ?? "");
  const jurisdiction = String(formData.get("jurisdiction") ?? "KISUMU_COUNTY").trim() || "KISUMU_COUNTY";
  const detail: Record<string, string> = {};
  for (const key of ["partner_category", "authority_name", "facilitation_type"]) {
    const v = String(formData.get(key) ?? "").trim();
    if (v) detail[key] = v;
  }

  const lines = scopeText.split("\n").map((l) => l.trim()).filter(Boolean);
  if (lines.length === 0) return { error: "Describe at least one scope line." };
  if (env === "GOVERNOR" && !detail.authority_name) return { error: "Name the authority you represent." };

  const scope_lines = lines.map((line) => ({ line_description: line, quantity: 1, scope_detail: { ...detail, jurisdiction } }));

  try {
    const result = await captureCommand("TRUSTRIDE_BUSINESS", ROUTE[env].subShell, ROUTE[env].command, { scope_lines, jurisdiction });
    if (result.translation_status !== "TRANSLATED") return { error: result.rejection_reason ?? "Request could not be submitted" };
  } catch (err) {
    return { error: (err as Error).message };
  }

  revalidatePath("/dashboard/requests");
  return { error: null, submitted: true };
}
