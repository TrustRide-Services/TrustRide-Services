// Operation -> adapter routing for the integration gateway (no Deno globals, so it is testable under Node).
import { b2cPayout, sendSms, sendWhatsapp, stkPush, type Deps, type Job, type Outcome } from "./providers.ts";
import { metamapVerify } from "./metamap.ts";
import { sendEmail } from "./gmail.ts";

export type { Deps, Job, Outcome };

export async function handle(req: Job, d: Deps): Promise<Outcome> {
  switch (req.operation) {
    case "NOTIFY_SMS": return sendSms(req, d);
    case "NOTIFY_WHATSAPP": return sendWhatsapp(req, d);
    case "STK_PUSH": return stkPush(req, d);
    case "B2C_PAYOUT": return b2cPayout(req, d);
    case "NOTIFY_EMAIL": return sendEmail({ ...req, operation: "NOTIFY_EMAIL" }, d);
    case "NOTIFY_PUSH":
      return { kind: "done", success: false, error: "PUSH_NOT_AVAILABLE (no device tokens are registered on the web surfaces)" };
    case "IDENTITY_VERIFY":
    case "ENTITY_VERIFY":
      return metamapVerify({ ...req, operation: req.operation }, d);
    default:
      return { kind: "done", success: false, error: `OPERATION_NOT_SUPPORTED: ${req.operation}` };
  }
}
