"use server";

import { command } from "@/lib/trustride";

export async function reportLocationAction(jobId: string, lat: number, lon: number) {
  const r = await command("OPERATOR_APP", "TRACK_ELEMENT", { job_id: jobId, lat, lon });
  return { error: r.ok ? null : r.error };
}
