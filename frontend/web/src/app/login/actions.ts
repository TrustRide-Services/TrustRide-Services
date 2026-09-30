"use server";

import { bindSystemAccess, recordSystemAccess } from "@/lib/trustride";

// Sovereign Gate step 1 for a returning User: System Access is recorded
// before authentication, then bound to the identity once it succeeds.
export async function beginLoginAccess() {
  return recordSystemAccess("AUTHENTICATE");
}

export async function completeLoginAccess(accessId: string) {
  await bindSystemAccess(accessId, "AUTHENTICATED");
}
