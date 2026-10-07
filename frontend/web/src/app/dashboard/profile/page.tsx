import { redirect } from "next/navigation";
import ProfileCenter from "@/components/ProfileCenter";
import { businessSub, gateContext } from "@/lib/trustride";

export default async function BusinessProfile() {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  const sub = businessSub(ctx);
  return <ProfileCenter sub={sub} referralSub={sub === "CUSTOMER_APP" || sub === "PARTNER_APP" ? sub : undefined} />;
}
