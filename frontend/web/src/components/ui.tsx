import Link from "next/link";

// Small, shared presentation pieces. No data access here.

export function Page({ title, intro, children, actions }: { title: string; intro?: React.ReactNode; children: React.ReactNode; actions?: React.ReactNode }) {
  return (
    <div className="max-w-5xl mx-auto flex flex-col gap-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="font-display text-xl font-semibold text-text-primary">{title}</h1>
          {intro && <p className="text-text-secondary text-sm mt-1 max-w-3xl">{intro}</p>}
        </div>
        {actions}
      </div>
      {children}
    </div>
  );
}

export function Section({ title, children, aside }: { title: string; children: React.ReactNode; aside?: React.ReactNode }) {
  return (
    <section className="flex flex-col gap-3">
      <div className="flex items-baseline justify-between gap-2">
        <h2 className="text-[11px] font-semibold uppercase tracking-[0.2em] text-gold-dim">{title}</h2>
        {aside}
      </div>
      {children}
    </section>
  );
}

export function Card({ children, className = "", tone }: { children: React.ReactNode; className?: string; tone?: "danger" | "gold" }) {
  const border = tone === "danger" ? "border-danger/50" : tone === "gold" ? "border-gold-dim/60" : "";
  return <div className={`trs-card p-4 ${border} ${className}`}>{children}</div>;
}

const TONE: Record<string, string> = {
  good: "border-success/40 text-success bg-success/10",
  warn: "border-gold-dim/50 text-gold-light bg-gold/10",
  bad: "border-danger/40 text-danger bg-danger/10",
  neutral: "border-border text-text-secondary bg-surface",
};

const STATUS_TONE: Record<string, keyof typeof TONE> = {
  ACTIVE: "good", AVAILABLE: "good", SETTLED: "good", REVIEWED: "good", COMPLETED: "good", VERIFIED: "good", RECEIPT_GENERATED: "good",
  ACCEPTED: "good", PAID: "good", LIVE: "good", HEALTHY: "good", RESOLVED: "good", SUCCEEDED: "good", LISTED: "good", DELIVERED: "good", DISPATCHED: "good",
  PLACED: "warn", VALIDATED: "warn", WAITING: "warn", SCHEDULED: "warn", QUOTED: "warn", JOB_CREATED: "warn", EN_ROUTE: "warn", ARRIVED: "warn",
  EXECUTING: "warn", PENDING: "warn", SUBMITTED: "warn", UNDER_REVIEW: "warn", AWAITING_PAYMENT: "warn", RESERVED: "warn", INITIATED: "warn",
  PENDING_CALLBACK: "warn", OPEN: "warn", ASSIGNED: "warn", AWAITING_REQUESTER: "warn", DEGRADED: "warn", STALE: "warn", OFFLINE: "neutral",
  ACKNOWLEDGED: "warn", CREATED: "warn", REQUESTED: "warn", PENDING_VERIFICATION: "warn", MAINTENANCE: "warn", NEVER_SEEN: "neutral",
  CANCELLED: "neutral", EXPIRED: "neutral", CLOSED: "neutral", DECLINED: "bad", FAILED: "bad", SUSPENDED: "bad", VERIFICATION_FAILED: "bad",
  TIMED_OUT: "bad", CRITICAL: "bad", HIGH: "warn", NORMAL: "neutral", DELISTED: "neutral", SOLD: "good", REGISTERED: "warn", RETIRED: "neutral",
};

const STATUS_LABEL: Record<string, string> = {
  PLACED: "Placed", VALIDATED: "Matching", WAITING: "Waiting for a worker", SCHEDULED: "Scheduled", QUOTED: "Confirm fare", JOB_CREATED: "Confirmed",
  DISPATCHED: "On the way", EXECUTING: "In progress", COMPLETED: "Completed", SETTLED: "Paid", REVIEWED: "Reviewed", CLOSED: "Closed",
  CANCELLED: "Cancelled", EXPIRED: "Expired", FAILED: "Failed", DECLINED: "Declined", AWAITING_PAYMENT: "Awaiting payment",
  RECEIPT_GENERATED: "Paid", PENDING_CALLBACK: "Waiting for M-Pesa", INITIATED: "Requested", EN_ROUTE: "En route", ARRIVED: "Arrived",
  ACKNOWLEDGED: "Accepted", CREATED: "New", VERIFIED: "Verified", PENDING_VERIFICATION: "Verifying", AWAITING_REQUESTER: "Awaiting you",
};

export function label(status: string | null | undefined) {
  if (!status) return "—";
  return STATUS_LABEL[status] ?? status.charAt(0) + status.slice(1).toLowerCase().replace(/_/g, " ");
}

export function Badge({ status, text }: { status: string | null | undefined; text?: string }) {
  if (!status) return null;
  return (
    <span className={`inline-block rounded-full border px-2.5 py-0.5 text-[11px] font-semibold uppercase tracking-wide ${TONE[STATUS_TONE[status] ?? "neutral"]}`}>
      {text ?? label(status)}
    </span>
  );
}

export function Kes({ value }: { value: number | string | null | undefined }) {
  if (value === null || value === undefined || value === "") return <span>—</span>;
  return <span>KES {Number(value).toLocaleString("en-KE", { maximumFractionDigits: 2 })}</span>;
}

export function when(iso: string | null | undefined) {
  if (!iso) return "—";
  return new Date(iso).toLocaleString("en-KE", { timeZone: "Africa/Nairobi", weekday: "short", day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" });
}

export function Empty({ children }: { children: React.ReactNode }) {
  return <p className="text-text-muted text-sm">{children}</p>;
}

export function ErrorNote({ error }: { error: string | null | undefined }) {
  if (!error) return null;
  return <p className="rounded-lg bg-danger-bg text-danger text-sm p-2.5">{error}</p>;
}

export function Notice({ children }: { children: React.ReactNode }) {
  return <p className="rounded-lg border border-gold-dim/40 bg-gold/5 text-text-secondary text-sm p-3">{children}</p>;
}

export function KV({ items }: { items: [string, React.ReactNode][] }) {
  return (
    <dl className="grid grid-cols-[max-content_1fr] gap-x-4 gap-y-1 text-sm">
      {items.map(([k, v]) => (
        <div key={k} className="contents">
          <dt className="text-text-muted">{k}</dt>
          <dd className="text-text-primary">{v}</dd>
        </div>
      ))}
    </dl>
  );
}

export function NavPill({ href, children, active }: { href: string; children: React.ReactNode; active?: boolean }) {
  return (
    <Link href={href} className={`rounded-full border px-4 py-2 text-sm font-medium transition-colors ${
      active ? "border-gold-dim bg-gold/10 text-text-primary" : "border-border bg-surface text-text-secondary hover:text-text-primary hover:border-gold-dim"
    }`}>
      {children}
    </Link>
  );
}

export const inputClass = "trs-input w-full rounded-lg px-3 py-2 text-sm text-text-primary placeholder:text-text-muted";
export const labelClass = "flex flex-col gap-1 text-xs text-text-secondary";
