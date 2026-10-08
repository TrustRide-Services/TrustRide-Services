# 10. Deployment Architecture

## Purpose

Defines the deployment architecture for TrustRide Services: where the code lives, which
environments exist, how changes move from a workstation to the live site, and the
vendor/technology baseline every external integration follows.

## Scope

Infrastructure, environments, CI/CD, monitoring, logging, backup, disaster recovery, release
strategy.

## Current setup (verified 2026-10-08)

| Concern | Where it lives |
| --- | --- |
| **Source code** | GitHub `TrustRide-Services/TrustRide-Services`, branch `main`; local working copy `C:\Users\ALBERT\TrustRide-Services` |
| **Database, Auth, Edge Functions** | Supabase project `trustride-stagging` (ref `fdkzewkogkujtwvonesn`, region `eu-central-1`), organisation "TRUSTRIDE SYSTEM" |
| **Web application** | Vercel team `trust-ride`, project `trustride-services` (Next.js, root `frontend/web`), live at https://trustride-services.vercel.app against `trustride-stagging` |
| **Production database** | Supabase project `trustride-production` — provisioned, **not yet wired or deployed to**; nothing is promoted there without explicit Founder authorization |
| **Local development** | Full Supabase stack via `supabase start` (ports 54321/54322), built from `supabase/migrations` |

**Repository structure (actual):**

```
TrustRide-Services/
├── docs/              # the governed document hierarchy (this folder is 10-Deployment-Architecture)
├── supabase/
│   ├── migrations/    # the eleven engines, in order, as timestamped migrations
│   ├── functions/     # Edge Functions: integration-gateway, mpesa-callback, protrack-ingest
│   ├── tests/         # rollback-only SQL suites (run.sh local | linked)
│   └── config.toml    # local stack config (never pushed with `supabase config push`)
├── frontend/web/      # the Next.js web application (Office / Business / Marketplace shells)
└── tests/e2e/         # Playwright browser journeys and the integrated proof
```

**How a change reaches the live site:**

1. Develop and prove locally (`supabase start`, `supabase/tests/run.sh local`, browser journeys in
   `tests/e2e`).
2. Database: `supabase db push --linked --yes` to `trustride-stagging`, then
   `supabase migration list --linked` and `supabase/tests/run.sh linked` (must be 0 failed).
3. Edge Functions: `supabase functions deploy <slug> --project-ref fdkzewkogkujtwvonesn --no-verify-jwt`
   (every function authenticates with its own secret or key, not a Supabase JWT).
4. Web: commit and push to `main`; Vercel's GitHub integration builds `frontend/web` and
   promotes it to production on https://trustride-services.vercel.app automatically.

## Contents

**`TRS026-BUILD-PLAN-001_Coding_to_Deployment`** — the coding-and-deployment plan: technology
stack, migration order, backend build sequence, testing strategy, CI/CD and rollout stages
(internal Kisumu pilot → closed pilot → soft launch → general availability → geographic
expansion, each gated on the prior stage's real operational data). Version 1.1.0 records the
environments and repository above.

**`TRS026-VTDR-001_v2.0.0_Vendor_Technology_Decision_Record`** (adopted 2026-08-20, ADR 0002)
— the vendor/technology baseline for every external integration: M-Pesa Daraja 2.0
(payments; Flutterwave removed by Founder ruling 2026-10-08 until the system grows), Google Maps + ODPC geospatial anonymization (mapping/privacy),
Africa's Talking + Twilio (messaging/voice masking), KRA eTIMS VSCU (tax invoicing), plus the
zero-trust/DR/pen-testing infrastructure security baseline.

Operational procedures (deploy, rollback, secrets, incidents, backup) are in
`docs/11-Operations-Manual/RUNBOOKS.md`.

## Dependencies

- `09-Testing-Constitution/` — no migration or deployment proceeds without passing the
  SQL suites and the affected browser journeys.

## Status

**Live on staging, 2026-10-08.** All eleven engines deployed to `trustride-stagging`
(migrations through `20261008000025`); 12 SQL suites / 452 checks passing; Founder's Final
Integrated Proof (Company → Boda) PROVEN 44/44. Every integration port runs in `SIMULATOR`
mode until provider credentials are supplied. VTDR adopted as law 2026-08-20 (ADR 0002).
