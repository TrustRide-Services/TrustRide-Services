"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { captureCommand } from "@/lib/trustride";

export async function signOutAction() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/");
}

export async function acceptQuotationAction(quoteId: string) {
  const result = await captureCommand("ACCEPT_QUOTATION", { quote_id: quoteId });
  if (result.translation_status !== "TRANSLATED") {
    return { error: result.rejection_reason ?? "Could not accept quotation" };
  }
  revalidatePath("/dashboard/orders");
  return { error: null };
}

const SERVICE_INTENT_FIELDS: Record<string, { asset_class: string; engine_capacity: string; jurisdiction: string; label: string }> = {
  "TRANSPORT-BODA-STANDARD": {
    asset_class: "BODA_BODA",
    engine_capacity: "CC_125",
    jurisdiction: "KISUMU_COUNTY",
    label: "Boda ride (Kisumu)",
  },
};

export async function raiseIntentAction(_prevState: unknown, formData: FormData) {
  const serviceCode = String(formData.get("serviceCode") ?? "");
  const macroDomain = String(formData.get("macroDomain") ?? "");
  const originZone = String(formData.get("originZone") ?? "").trim();
  const destinationZone = String(formData.get("destinationZone") ?? "").trim();
  const distance = parseFloat(String(formData.get("distanceKm") ?? ""));
  const duration = parseFloat(String(formData.get("durationMin") ?? ""));
  const userTypeDomain = String(formData.get("userTypeDomain") ?? "CUSTOMER");

  const fields = SERVICE_INTENT_FIELDS[serviceCode];
  if (!fields) return { error: "This service is listed but isn't wired for booking yet." };
  if (!macroDomain || !originZone || !destinationZone || Number.isNaN(distance) || Number.isNaN(duration)) {
    return { error: "Fill in origin, destination, distance, and duration." };
  }

  try {
    const result = await captureCommand("RAISE_INTENT", {
      user_type_domain: userTypeDomain,
      service_code: serviceCode,
      macro_domain: macroDomain,
      jurisdiction: fields.jurisdiction,
      order_lines: [
        {
          line_description: fields.label,
          quantity: 1,
          scope_detail: {
            origin_zone_code: originZone,
            destination_zone_code: destinationZone,
            asset_class: fields.asset_class,
            engine_capacity: fields.engine_capacity,
            jurisdiction: fields.jurisdiction,
            distance_km: distance,
            duration_min: duration,
          },
        },
      ],
    });
    if (result.translation_status !== "TRANSLATED") {
      return { error: result.rejection_reason ?? "Order could not be placed" };
    }
  } catch (err) {
    return { error: (err as Error).message };
  }

  revalidatePath("/dashboard/orders");
  redirect("/dashboard/orders");
}
