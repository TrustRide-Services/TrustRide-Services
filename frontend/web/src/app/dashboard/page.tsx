import { redirect } from "next/navigation";
import { getActorContext } from "@/lib/trustride";

// RENDERING STRATEGY: N/A -- routes to the first surface this person holds.
export default async function BusinessIndex() {
  const ctx = await getActorContext();
  if (ctx?.envStatus.get("CUSTOMER") === "ACTIVE") redirect("/dashboard/raise-intent");
  for (const env of ["PARTNER", "GOVERNOR", "INTERMEDIARY"] as const) {
    if (ctx?.envStatus.has(env)) redirect(`/dashboard/requests?as=${env}`);
  }
  redirect("/verify");
}
