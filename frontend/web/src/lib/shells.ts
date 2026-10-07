// Engine 11 v3.0.0: three main sovereign shells and their sub-shells, and
// which sub-shell each route belongs to. Shared by the middleware and the
// server code; holds no secrets and does no I/O.

export type TopShell = "TRUSTRIDE_OFFICE" | "TRUSTRIDE_BUSINESS" | "TRUSTRIDE_MARKETPLACE";
export type SubShell =
  | "OPERATOR_APP"
  | "ADMIN_CONSOLE"
  | "EXECUTIVE_DASHBOARD"
  | "CUSTOMER_APP"
  | "PARTNER_APP"
  | "GOVERNOR_APP"
  | "INTERMEDIARY_APP"
  | "MARKETPLACE_APP"
  | "VENDOR_APP";

export const TOP_OF: Record<SubShell, TopShell> = {
  OPERATOR_APP: "TRUSTRIDE_OFFICE",
  ADMIN_CONSOLE: "TRUSTRIDE_OFFICE",
  EXECUTIVE_DASHBOARD: "TRUSTRIDE_OFFICE",
  CUSTOMER_APP: "TRUSTRIDE_BUSINESS",
  PARTNER_APP: "TRUSTRIDE_BUSINESS",
  GOVERNOR_APP: "TRUSTRIDE_BUSINESS",
  INTERMEDIARY_APP: "TRUSTRIDE_BUSINESS",
  MARKETPLACE_APP: "TRUSTRIDE_MARKETPLACE",
  VENDOR_APP: "TRUSTRIDE_MARKETPLACE",
};

// Routes whose sub-shell is fixed by the path (the middleware keeps a shell
// session ready for them). Office pages shared by Administrators and
// Executives choose their sub-shell from the person's role instead.
export function subShellForPath(pathname: string): SubShell | null {
  if (pathname.startsWith("/dashboard/partner")) return "PARTNER_APP";
  if (pathname.startsWith("/dashboard/governor")) return "GOVERNOR_APP";
  if (pathname.startsWith("/dashboard/intermediary")) return "INTERMEDIARY_APP";
  if (pathname.startsWith("/dashboard")) return "CUSTOMER_APP";
  if (pathname.startsWith("/marketplace/vendor")) return "VENDOR_APP";
  if (pathname.startsWith("/marketplace")) return "MARKETPLACE_APP";
  if (pathname.startsWith("/office/operator")) return "OPERATOR_APP";
  if (pathname.startsWith("/office/executive")) return "EXECUTIVE_DASHBOARD";
  return null;
}

export const SESSION_COOKIE = (sub: SubShell) => `trs_s_${sub.toLowerCase()}`;
export const ACTING_COOKIE = "trs_acting";
export const ACCESS_COOKIE = "trs_access_id";
