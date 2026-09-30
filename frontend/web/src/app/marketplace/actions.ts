"use server";

import { revalidatePath } from "next/cache";
import { captureCommand } from "@/lib/trustride";

const CATEGORIES = new Set(["MOTORCYCLE", "CAR"]);

// Marketplace_App: reserve a second-hand, improved motorcycle or car.
export async function reserveVehicle(_prev: unknown, formData: FormData) {
  const category = String(formData.get("vehicle_category") ?? "");
  const makeModel = String(formData.get("make_model") ?? "").trim();
  const budget = String(formData.get("budget_kes") ?? "").trim();
  if (!CATEGORIES.has(category)) return { error: "TrustRide Marketplace sells motorcycles and cars only." };
  if (!makeModel) return { error: "Tell us the make and model you want." };

  try {
    const result = await captureCommand("TRUSTRIDE_MARKETPLACE", "MARKETPLACE_APP", "RESERVE_VEHICLE", {
      order_lines: [{
        line_description: `${category === "CAR" ? "Car" : "Motorcycle"}: ${makeModel}${budget ? ` (budget KES ${budget})` : ""}`,
        quantity: 1,
        scope_detail: { vehicle_category: category, make_model: makeModel, budget_kes: budget || null },
      }],
    });
    if (result.translation_status !== "TRANSLATED") return { error: result.rejection_reason ?? "Reservation could not be placed" };
  } catch (err) {
    return { error: (err as Error).message };
  }
  revalidatePath("/marketplace");
  return { error: null, submitted: true };
}

// Vendor_App: apply to list motorcycles or cars. Strictly TrustRide's
// offering; 5% commission on every completed sale, stamped into the vendor
// agreement on approval.
export async function submitVendorListing(_prev: unknown, formData: FormData) {
  const category = String(formData.get("vehicle_category") ?? "");
  const business = String(formData.get("business_name") ?? "").trim();
  const stock = String(formData.get("stock") ?? "").split("\n").map((l) => l.trim()).filter(Boolean);
  const accepted = formData.get("commission") === "on";
  if (!CATEGORIES.has(category)) return { error: "TrustRide Marketplace lists motorcycles and cars only." };
  if (!business) return { error: "Enter your business or trading name." };
  if (stock.length === 0) return { error: "Describe at least one vehicle or stock line." };
  if (!accepted) return { error: "Accept the 5% commission on every completed sale to apply." };

  try {
    const result = await captureCommand("TRUSTRIDE_MARKETPLACE", "VENDOR_APP", "SUBMIT_VENDOR_LISTING", {
      scope_lines: stock.map((line) => ({
        line_description: line,
        quantity: 1,
        scope_detail: { vehicle_category: category, business_name: business, commission_accepted: true },
      })),
    });
    if (result.translation_status !== "TRANSLATED") return { error: result.rejection_reason ?? "Application could not be submitted" };
  } catch (err) {
    return { error: (err as Error).message };
  }
  revalidatePath("/marketplace/vendor");
  return { error: null, submitted: true };
}
