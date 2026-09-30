"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { captureCommand } from "@/lib/trustride";

// Admin_Console's decision (TRS026-ENG011-PRESENT-003 Sec.6: "Business Engine
// + Admin_Console"). Captured as a command in TrustRide Office; the Business
// engine activates what was approved and notifies the actor.
export async function reviewRequest(orderId: string, decision: "ACCEPTED" | "DECLINED", formData: FormData) {
  const notes = String(formData.get("notes") ?? "").trim() || null;
  if (decision === "DECLINED" && !notes) redirect(`/office?error=${encodeURIComponent("Give a reason when declining -- the actor sees it and may amend and re-submit.")}`);

  let failure: string | null = null;
  try {
    const result = await captureCommand("TRUSTRIDE_OFFICE", "ADMIN_CONSOLE", "REVIEW_ACTOR_REQUEST", { order_id: orderId, decision, notes });
    if (result.translation_status !== "TRANSLATED") failure = result.rejection_reason ?? "Decision could not be recorded";
  } catch (err) {
    failure = (err as Error).message;
  }
  if (failure) redirect(`/office?error=${encodeURIComponent(failure)}`);

  revalidatePath("/office");
  redirect("/office");
}
