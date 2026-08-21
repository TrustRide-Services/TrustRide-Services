# 10. Deployment Architecture

## Purpose

Defines the deployment architecture for this project, per the Engineering Office
Project Repository Standard (`00-FOUNDATION/standards/PROJECT_REPOSITORY_STANDARD.md`).

## Scope

Infrastructure, environments, CI/CD, infrastructure as code, monitoring, logging, backup,
disaster recovery, release strategy.

## Contents

**`TRS026-BUILD-PLAN-001_Coding_to_Deployment`** (md / docx / pdf) — the step-by-step coding-
and-deployment plan, reconciled against this repository's actual, already-provisioned
infrastructure (not a greenfield proposal):

- **Environments:** two Supabase projects — `trustride-dev` and `trustride-production` (org
  `omnex-ke`, `eu-central-1`) — already provisioned; no separate staging project (Supabase
  free-tier project limit). `trustride-dev` carries both development and pre-production
  verification duty.
- **Repository structure:** this project's own `database/`, `backend/`, `frontend/`,
  `shared/`, `infrastructure/`, `tech-stack/`, `ai/` folders, per
  `00-FOUNDATION/standards/PROJECT_REPOSITORY_STANDARD.md` — not a new structure.
- **Migration order:** Foundation first (92 tables), then Resources → Services → Business →
  Cost → Integration → Orchestration → Coordination → Advisory → Modelling → Presentation.
- **Backend build sequence:** six phases, Foundation services first, the Sovereign Processing
  Unit (Orchestration + Coordination) as the highest-risk phase with a flagged temporary
  direct-call shim for earlier parallel development, Advisory/Modelling last (lowest risk,
  zero write access to any other engine).
- **CI/CD:** the structural test suite (`09-Testing-Constitution/`) as a hard gate on every
  PR; `trustride-dev` on merge to `main`; `trustride-production` on tagged release only, with
  manual Founder/Governor approval.
- **Rollout:** internal Kisumu pilot → closed pilot → soft launch → general availability →
  geographic expansion, each gated on the prior stage's real operational data.

**`TRS026-VTDR-001_v2.0.0_Vendor_Technology_Decision_Record`** (adopted 2026-08-20, ADR 0002)
— the vendor/technology baseline for every external integration: M-Pesa Daraja 2.0 +
Flutterwave (payments), Google Maps + ODPC geospatial anonymization (mapping/privacy),
Africa's Talking + Twilio (messaging/voice masking), KRA eTIMS VSCU (tax invoicing), plus the
zero-trust/DR/pen-testing infrastructure security baseline. Reconciled against this
repository's actual Supabase infrastructure at the one point of divergence (see the
document's own §6 note).

## Dependencies

- `09-Testing-Constitution/` — no migration or deployment proceeds without passing the
  structural suite and, ultimately, the full Conformance Certificate.

## Status

**Populated — PROPOSED, 2026-08-16, pending Founder phase-gate approval to begin Phase 1.**
VTDR adopted as law 2026-08-20 (ADR 0002).
