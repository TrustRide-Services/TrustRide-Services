import { redirect } from "next/navigation";
import { gateContext, officeAccess, project } from "@/lib/trustride";
import CommandForm from "@/components/CommandForm";
import { Badge, Card, Empty, ErrorNote, Page, inputClass, when } from "@/components/ui";

type Users = {
  users: { user_id: string; name: string; uid: string; primitive: string; status: string; created_at: string; phone_verified: boolean;
    environments: { domain: string; status: string }[]; roles: string[]; governor_scopes: string[] | null }[];
  roles_available: string[];
  governor_scopes_available: string[];
};

// Users and roles (projection OFFICE_USERS, Admin Console only). Founder
// grants Executive and Administrator; Administrators grant operational roles
// below them. Governors see nothing until a scope is granted here (D4).
export default async function OfficeUsers({ searchParams }: { searchParams: Promise<{ q?: string }> }) {
  const { q = "" } = await searchParams;
  const ctx = await gateContext();
  if (!ctx) redirect("/login");
  if (!officeAccess(ctx).admin) redirect("/office");
  const { data, error } = await project<Users>("ADMIN_CONSOLE", "OFFICE_USERS", { q });
  return (
    <Page title="Users & roles" intro="Find a person or organisation; grant roles; suspend; set Governor data scopes.">
      <form className="flex gap-2"><input name="q" defaultValue={q} placeholder="Name or TrustRide ID" className={`${inputClass} max-w-sm`} />
        <button className="trs-btn-ghost rounded-lg px-4 py-2 text-sm font-semibold">Search</button></form>
      <ErrorNote error={error} />
      {!data?.users.length && <Empty>No one found.</Empty>}
      <div className="flex flex-col gap-2">
        {data?.users.map((u) => {
          const governor = u.environments.some((e) => e.domain === "GOVERNOR" && e.status === "ACTIVE");
          const self = u.user_id === ctx.user_id;
          return (
            <Card key={u.user_id} tone={u.status === "SUSPENDED" ? "danger" : undefined} className="flex flex-col gap-2">
              <div className="flex flex-wrap justify-between gap-2">
                <span className="text-sm text-text-primary font-semibold">{u.name} <span className="text-text-muted text-xs">{u.uid} · {u.primitive.toLowerCase()} · joined {when(u.created_at)}{u.phone_verified ? "" : " · phone not verified"}</span></span>
                <Badge status={u.status} />
              </div>
              <p className="text-xs text-text-secondary">
                {u.environments.map((e) => `${e.domain.toLowerCase()} (${e.status.toLowerCase()})`).join(" · ") || "no environment"}
                {u.roles.length ? ` · roles: ${u.roles.join(", ")}` : ""}</p>
              {!self && (
                <div className="flex flex-wrap gap-2 items-end">
                  {u.primitive === "PERSON" && (
                    <CommandForm sub="ADMIN_CONSOLE" command="GRANT_ROLE" fixed={{ user_id: u.user_id }} submit="Grant role" variant="ghost" inline>
                      <select name="role_code" className={`${inputClass} w-48`}>{data.roles_available.filter((r) => !u.roles.includes(r)).map((r) => <option key={r}>{r}</option>)}</select>
                    </CommandForm>
                  )}
                  {u.roles.filter((r) => r !== "FOUNDER").map((r) => (
                    <CommandForm key={r} sub="ADMIN_CONSOLE" command="REVOKE_ROLE" fixed={{ user_id: u.user_id, role_code: r }} submit={`Revoke ${r.toLowerCase()}`} variant="ghost" inline confirm={`Revoke ${r} from ${u.name}?`} />
                  ))}
                  {u.status === "SUSPENDED" ? (
                    <CommandForm sub="ADMIN_CONSOLE" command="REINSTATE_USER" fixed={{ user_id: u.user_id }} submit="Reinstate" inline>
                      <input name="reason" required placeholder="Reason" className={`${inputClass} w-44`} /></CommandForm>
                  ) : (
                    <CommandForm sub="ADMIN_CONSOLE" command="SUSPEND_USER" fixed={{ user_id: u.user_id }} submit="Suspend" variant="danger" inline confirm={`Suspend ${u.name}? They lose access to every surface.`}>
                      <input name="reason" required placeholder="Reason" className={`${inputClass} w-44`} /></CommandForm>
                  )}
                </div>
              )}
              {governor && (
                <div className="flex flex-wrap gap-2 items-center text-xs">
                  <span className="text-text-muted">Governor data:</span>
                  {data.governor_scopes_available.map((s) => {
                    const on = (u.governor_scopes ?? []).includes(s);
                    return (
                      <CommandForm key={s} sub="ADMIN_CONSOLE" command="SET_GOVERNOR_SCOPE" fixed={{ governor_user_id: u.user_id, data_scope: s, grant: !on }}
                        submit={`${on ? "✓ " : ""}${s.toLowerCase().replaceAll("_", " ")}`} variant={on ? "primary" : "ghost"} inline
                        confirm={on ? "Withdraw this data from the Governor?" : "Share this aggregate data with the Governor?"} />
                    );
                  })}
                </div>
              )}
            </Card>
          );
        })}
      </div>
    </Page>
  );
}
