# Frontend structure and rendering strategy

Implements **TRS026-FE-01 Frontend Architecture FINAL** and **TRS026-ENG011-PRESENT-003 FINAL** (Engine 11 v3.0.0).

## The Sovereign Gate

Every visitor passes the same sequence — no step skipped or reordered:

System Access → Registration → Authentication (Engine 6) → Authorization (Engine 1) → Profile → routed into one of the three main shells.

- **System Access** is the first record of every visit: at sign-up (`register/actions.ts`, before the account exists), at login (`login/actions.ts`), and once per browser session for a resumed visit (`lib/supabase/middleware.ts`). The id rides in the `trs_access_id` cookie and links every shell session opened during the visit.
- **`/verify`** is the Gate: it waits on Engine 6's result, then lays out the three shells with a real way in for every actor.

## The three main shells

| Shell | Route | Sub-shells | Who |
|---|---|---|---|
| TrustRide Business (external) | `/dashboard` | Customer_App, Partner_App, Governor_App, Intermediary_App | Customer: catalogue and orders immediately. Partner / Governor / Intermediary: submit a request, decided within 2–3 working days |
| TrustRide Marketplace (external) | `/marketplace` | Marketplace_App, Vendor_App | Buyers reserve motorcycles and cars; vendors apply to list (5% commission per sale) |
| TrustRide Office (internal) | `/office` | Admin_Console, Operator_App, Executive_Dashboard | TrustRide staff only — Admin decides every actor request |

The database, not this app, enforces who may open which shell (`fn_present_shell_session_open`). No actor lands on a surface with nothing lawful to do: pending Partners, Governors and Intermediaries can enter to submit and follow their request; staff request Office access at the Gate; the first verified identity may claim Founder authority once.

## Rendering strategy

Hybrid by default — static unless a route needs request-time identity.

| Route | Strategy | Why |
|---|---|---|
| `/` | Static | Identical for every anonymous visitor; the signed-in redirect lives in middleware |
| `/login` | Static (client) | No server data; auth runs in the browser, bracketed by System Access server actions |
| `/register`, `/verify` | Dynamic | Entirely decided by this visitor's own identity, verification and roles |
| `/dashboard`, `/marketplace`, `/office` layouts | Dynamic | Every link depends on the same gate that decides whether to redirect |
| `/dashboard/orders`, `/notifications`, `/raise-intent`, `/requests`, `/marketplace`, `/marketplace/vendor` | Hybrid | Static heading and form; per-user lists streamed via Suspense |
| `/office` | Dynamic | Internal, permission-gated live queue — correctness and freshness over static performance |
