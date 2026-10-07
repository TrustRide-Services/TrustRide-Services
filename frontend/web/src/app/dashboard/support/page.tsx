import { redirect } from "next/navigation";
import SupportCenter from "@/components/SupportCenter";
import { businessSub, gateContext } from "@/lib/trustride";

export default async function BusinessSupport() {
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  return <SupportCenter sub={businessSub(ctx)} />;
}
