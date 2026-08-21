# ADR 0001 — Constitutional Corpus Population

## Title

Population of the twelve-document hierarchy from the finalized TrustRide constitutional corpus

## Status

Accepted — 2026-08-16

## Context

`TrustRide Services Platform/docs/` was scaffolded per `PROJECT_REPOSITORY_STANDARD.md` with
twelve numbered placeholder folders, each holding only a `README.md` describing what it would
eventually contain. Separately, across an extended Claude Code / Cowork engagement, the
Founder directed the complete authoring, remediation, and final validation of TrustRide's
constitutional documentation: the four-sovereign framework (TBOC, SAPC, TEES, TISC) and the
eleven-engine registry (FDN-001 Foundation plus Engines 2–11), totalling 236 database tables,
each independently DDL-complete, RLS-secured, and cross-validated. This work was produced and
stored outside this repository (`C:\Users\ALBERT\Desktop\TrustRide_Devp_Final\`) during that
engagement, then mechanically re-validated in full (zero structural defects found — FK
ordering, CHECK-subquery ban, cross-engine foreign-key ban, Money Law, RLS coverage) and
closed out as a Final Report and a Coding & Deployment Plan.

The Founder's explicit ruling (2026-08-16): all prior/placeholder documentation in this
repository's TrustRide folders is null and void; the finalized, adopted corpus is the sole
authority going forward, and every `docs/` folder should be populated from it now.

## Decision

Populate all twelve `docs/` folders from the finalized corpus, replacing every placeholder
`README.md` with real content:

- `01-Constitution` ← TBOC (copied verbatim, frozen)
- `02-Software-Architecture-Definition-Document` ← SAPC (this folder's literal name
  coincidentally matches an earlier, informal reference PDF the Founder had authored before
  this engagement; that PDF was explicitly ruled background inspiration only and is not
  filed here — SAPC is the actual adopted architecture-definition instrument)
- `03-Core-Domain-Model` ← FDN-001 (Engine 001, Foundation — the platform's core bounded
  context in DDD terms)
- `04-Platform-Engine-Registry` ← Engines 002–010, each its own subfolder
- `05-Database-Architecture` ← TEES
- `06-Backend-Architecture` ← TISC
- `07-Presentation-Architecture` ← Engine 011, Presentation (kept separate from `04` to avoid
  duplicating a full engine spec across two folders)
- `08-API-Specifications` ← new compiled index across all eleven engines' own API contracts
- `09-Testing-Constitution` ← the Final Report (validation evidence), paired with the testing
  standard already recorded in `05` (TEES Part V)
- `10-Deployment-Architecture` ← the Build Plan, corrected during this population pass to
  reference this repository's actual, already-provisioned infrastructure rather than a
  greenfield proposal (see Consequences)
- `11-Operations-Manual` ← new synthesis from `06` and `10`
- `12-Developer-Documentation` ← new synthesis: the five working rules that produced zero
  structural defects, restated as forward-looking developer guidance

## Alternatives Considered

1. **Leave the corpus at its Desktop location and link to it.** Rejected — this repository is
   the institutional record; an external, un-versioned Desktop folder is not durable and
   contradicts CLAUDE.md rule 6 ("this workspace is Git-tracked... treat commits as part of
   the institutional record").
2. **Treat `02-Software-Architecture-Definition-Document` as reserved for the Founder's
   original informal PDF.** Rejected per the Founder's explicit ruling that all prior
   TrustRide documentation in this repository is superseded; SADD was knowledge-only
   background, never intended for this slot.
3. **Duplicate Engine 011's full spec into both `04` and `07`.** Rejected — creates a
   contradiction risk the Project Repository Standard explicitly warns against; `04`'s own
   README indexes Engine 011 with a pointer instead.

## Consequences

- The Build Plan (`10-Deployment-Architecture/`) was corrected during this population pass:
  originally proposed three Supabase environments and a fresh `trustride-platform/` monorepo;
  corrected to two environments (`trustride-dev`, `trustride-production` — matching the
  Supabase free-tier project limit and the projects already provisioned) and this repository's
  own existing `PROJECT_REPOSITORY_STANDARD.md` structure rather than a new one.
- `tech-stack/*.md` files populated from the Build Plan's Part I technology-stack table in the
  same pass (see CHANGELOG).
- Future schema or architecture changes must be proposed as an amendment to the relevant
  document within this hierarchy first (per the documentation-hierarchy rule that no lower
  document may introduce a concept contradicting a higher one), then implemented in code —
  never the reverse.
- This ADR itself is the durable record of the mapping decision, per CLAUDE.md rule 3.

## Related Decisions

- `01-ARCHITECTURE/adrs/0001-project-repository-standard.md` and `0002-final-workspace-restructure.md`
  (the standard this population conforms to)
- `01-ARCHITECTURE/adrs/0005-business-platform-separation.md` (why this content lives here and
  not in `trustride-services-business/`)
