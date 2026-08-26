import { redirect } from "next/navigation";

// RENDERING STRATEGY: N/A -- pure redirect, no content of its own.
export default function DashboardIndex() {
  redirect("/dashboard/orders");
}
