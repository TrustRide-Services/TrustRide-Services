# 04. Platform Engine Registry

## Purpose

Defines the platform engine registry for this project, per the Engineering Office
Project Repository Standard (`00-FOUNDATION/standards/PROJECT_REPOSITORY_STANDARD.md`).

## Scope

The registry of platform engines and their operating contract.

## Contents

The complete eleven-engine Constitutional Engine Registry. Engine 001 (Foundation) lives in
`03-Core-Domain-Model/` and Engine 011 (Presentation) lives in `07-Presentation-Architecture/`
— both are full members of this registry but are filed under their own more specific
documentation-hierarchy slot per the Project Repository Standard. This folder holds the ten
domain/runtime engines in between, each a subfolder with its complete specification
(md/docx/pdf): mission, architectural role and boundaries, production SQL DDL, API contracts,
event-signal matrix, and Conformance Self-Certification.

| # | Engine | Folder | Tables | Version |
| --- | --- | --- | --- | --- |
| 001 | Foundation | `03-Core-Domain-Model/` | 92 | 3.0.0 |
| 002 | Resources | `engine-02-resources/` | 11 | 1.0.1 |
| 003 | Services | `engine-03-services/` | 10 | 1.0.1 |
| 004 | Business | `engine-04-business/` | 12 | 1.0.1 |
| 005 | Cost | `engine-05-cost/` | 12 | 1.1.1 |
| 006 | Integration | `engine-06-integration/` | 13 | 1.0.0 |
| 007 | Workflow Orchestration | `engine-07-orchestration/` | 21 | 1.0.0 |
| 008 | Workflow Coordination | `engine-08-coordination/` | 27 | 1.0.0 |
| 009 | AI/ML Advisory | `engine-09-advisory/` | 13 | 1.0.0 |
| 010 | Scenario Modelling | `engine-10-modelling/` | 13 | 1.0.0 |
| 011 | Presentation | `07-Presentation-Architecture/` | 12 | 1.0.0 |
| **TOTAL** | | | **236** | |

Every engine's own document carries the "Platform engines, responsibilities, dependencies,
interfaces, ownership, lifecycle" content this folder's Expected Contents names — Section 1
(Architectural Role & Boundaries) states responsibilities/dependencies/interfaces, Section 2
(DDL) states ownership, and each Annex Conformance Certificate states lifecycle readiness.
No table on the platform belongs to more than one engine; no cross-engine foreign key exists
anywhere in the corpus (verified — see `09-Testing-Constitution/`).

## Dependencies

- `03-Core-Domain-Model/` (Engine 001, Foundation) — per the mandated documentation
  hierarchy, this document must not introduce governance or business concepts that
  contradict its upstream document.

## Status

**Populated — all ten engines ADOPTED, 2026-08-16.**
