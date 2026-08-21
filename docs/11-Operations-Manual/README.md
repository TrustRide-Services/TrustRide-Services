# 11. Operations Manual

## Purpose

Defines the operations manual for this project, per the Engineering Office
Project Repository Standard (`00-FOUNDATION/standards/PROJECT_REPOSITORY_STANDARD.md`).

## Scope

Administration, monitoring, incident response, maintenance, troubleshooting, runbooks,
operational procedures.

## Contents

Drawn from `06-Backend-Architecture/` (TISC) and `10-Deployment-Architecture/` (Build Plan
Part IX), focused on what changes once the platform is live rather than being built.

### Observability

Orchestration's `orch_capacity_snapshot`/`orch_queue_metrics` and Coordination's
`coord_coordination_health`/`coord_runtime_alert` (see `04-Platform-Engine-Registry/engine-07-orchestration/`
and `engine-08-coordination/`) are the system of record for platform health — wiring these
already-specified tables to a live dashboard on the Admin Console is the whole of the
observability build, not a separate monitoring stack.

### Incident response

Foundation's `system_incident` and `security_event` (`03-Core-Domain-Model/`) are the system
of record for every incident. The Admin Console's "Operational Controls" surface
(`07-Presentation-Architecture/`) is where Governors act on them — re-assign, cancel, recover
— every action itself a governed signal, never a direct database write.

### SOS / emergency response

`EMERGENCY_ESCALATION_REQUESTED` / `ACKNOWLEDGED` (Engine 6, `06-Backend-Architecture/`) is
the live runbook: trigger → response → resolution → aftercare, recorded end-to-end per TBOC
Article 54. This is the one operational path that must be drilled and rehearsed before any
public launch stage in `10-Deployment-Architecture/`'s rollout table.

### Maintenance & continuous compliance

Re-run the structural test suite (`09-Testing-Constitution/`) on every schema change,
permanently — not a one-time audit. Any schema change discovered necessary in production is
proposed as a new versioned amendment to the relevant engine specification first (mirroring
FDN-001's own Amendment Register pattern), then implemented — never the reverse.

### Real-time matching & dispatch

**`TRS026-OSMRDP-001_v1.0.0_Operational_Security_Matching_Dispatch_Protocol`** (adopted
2026-08-20, ADR 0002) — the algorithmic matching score (40% distance / 30% rating / 30%
acceptance rate) and the 30-second cascading dispatch offer are **implemented and live**
(`20260820160000`/`161000`, 13/13 pgTAP, `trustride-dev` + `trustride-production`). Still
open: shift/rest limits (8-hour daily cap, 30-minute rest after 4 hours), 500m geofence
privacy masking, and the continuous identity-verification cycle — see the document's own
Implementation Status section for the exact, named build gaps.

### Regulatory relationship management

**`TRS026-RRMP-001_v1.0.0_Regulatory_Relationship_Management_Procedure`** (adopted 2026-08-20,
ADR 0002) — the 6-stage closed-loop workflow (ingestion → assignment → engagement → outcome →
assumption-shift review → Founder escalation) for every NTSA/ODPC/KRA/County-Finance/IRA
contact. **Stages 1/2/4/5/6 implemented and live** (`20260820170000`, 11/11 pgTAP,
`trustride-dev` + `trustride-production`), surfaced as a Regulatory tab in the Admin Console
per the Founder's "more Founder/CEO level" placement ruling — built against the real,
pre-existing `regulatory_contact_register`/`assumption_impact_assessment` tables (TBOC Article
12.5), not a new schema. Still open: automatic threshold-based escalation (deliberately not
built — see the document's own Implementation Status section).

## Dependencies

- `10-Deployment-Architecture/` — operations begin where deployment's rollout table ends.

## Status

**Populated — 2026-08-16, extended 2026-08-19, extended 2026-08-20 (OS-MRDP/RRMP adoption,
ADR 0002).** Operational until the platform reaches its first live pilot; will accumulate real
runbook detail as incidents and maintenance events actually occur. Practical, command-level
procedures (deployment, rollback, secret rotation, Daraja/callback failure, reconciliation,
dead-letter, database incident, emergency shutdown, production verification) now live in
`RUNBOOKS.md`, written against the system as it actually exists as part of Production Closure
— this file stays the design-level index.
