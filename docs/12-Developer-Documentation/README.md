# 12. Developer Documentation

## Purpose

Defines the developer documentation for this project, per the Engineering Office
Project Repository Standard (`00-FOUNDATION/standards/PROJECT_REPOSITORY_STANDARD.md`). Per
Part V of that standard, this extends the workspace-level standards in
`00-FOUNDATION/standards/` (coding, database, API, architecture, DDD, security) with
project-specific detail — it does not restate them.

## Scope

Development standards, coding standards, project structure, setup guides, contribution
guide, local development, FAQ.

## Contents

### The five rules every engineer working on this codebase must internalize

Drawn from `05-Database-Architecture/` (TEES) and `09-Testing-Constitution/` (the Final
Report's validation methodology) — the discipline that produced zero structural defects
across 236 tables, restated as working rules rather than retrospective findings:

1. **No `CHECK` constraint may contain a subquery.** PostgreSQL forbids it. Use a
   `CREATE CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY DEFERRED` instead — see any engine's
   own DDL for a worked example (e.g. `resource_workforce_unit`'s fleet-requirement check,
   `04-Platform-Engine-Registry/engine-02-resources/`).
2. **No foreign key ever crosses an engine boundary.** A reference to another engine's row is
   always a plain `UUID` column, by value, never `REFERENCES`.
3. **Every `NUMERIC` column matching `*_kes*` is `NUMERIC(18,2)`.** No exception.
4. **Row-Level Security is enabled on every table, no exception**, with an explicit policy —
   `platform_read` for governed reference data, `self_read`/`requester_read` scoped by
   `current_setting('app.current_user_id', true)::uuid` for personal/financial data.
5. **Every schema change is proposed as a specification amendment first**, then implemented —
   never the reverse. The specification in `01` through `10` is ground truth; code conforms
   to it, not the other way around.

### Local development setup

See `10-Deployment-Architecture/` Part III for the full step-by-step: `supabase start` for
the local stack (already configured at this project's own `supabase/`), the two-project
promotion path (`trustride-dev` → `trustride-production`), and the secrets discipline (never
a raw credential in a tracked file).

### Project structure

See `10-Deployment-Architecture/` Part II — this project's `database/`, `backend/`,
`frontend/`, `shared/`, `infrastructure/`, `tech-stack/`, `ai/` folders, per
`00-FOUNDATION/standards/PROJECT_REPOSITORY_STANDARD.md`.

### FAQ

**"Why does an engine's table reference another engine's ID without a foreign key?"** —
constitutional law (TBOC Article 33): no engine reads or writes another engine's tables.
Referential integrity for cross-engine references is enforced by the signal-and-accept
pattern, not by the database's own FK mechanism.

**"Where do I find the exact DDL for table X?"** — `04-Platform-Engine-Registry/` (or
`03-Core-Domain-Model/` for Foundation, `07-Presentation-Architecture/` for Presentation),
Section 2 of that engine's own specification.

## Dependencies

- `11-Operations-Manual/` — the full documentation hierarchy closes here; every downstream
  concern (running the platform day to day) is covered there.

## Status

**Populated — 2026-08-16.**
