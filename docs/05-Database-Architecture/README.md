# 05. Database Architecture

## Purpose

Defines the database architecture for this project, per the Engineering Office
Project Repository Standard (`00-FOUNDATION/standards/PROJECT_REPOSITORY_STANDARD.md`).

## Scope

Database design, schemas, tables, relationships, indexes, functions, procedures, policies,
storage, migration strategy.

## Contents

**`TRS026-TEES-001_Master_Instrument`** (md / docx / pdf) — the Technical & Engineering
Execution Standard (TEES), TrustRide's third sovereign instrument.

Covers exactly this folder's scope: the data-home register (which engine owns which business
register), the platform's governed state-machine catalogue (every `ENUM`-typed status column
across all 236 tables, with the Order lifecycle as the worked example), the fourteen-phase
engine installation lifecycle (extensions → schema → enums → tables → constraints →
relationships → functions → triggers → RLS → indexes → views → privilege lockdown →
validation → finalization), the nine binding column conventions (UUID identity, FK naming,
Money Law `NUMERIC(18,2)`, Time Law, immutability, traceability, RLS, secrets law), the
cross-engine reference discipline (by value only, zero foreign keys across engine
boundaries), and the deferred-constraint-trigger standard (PostgreSQL forbids a subquery
inside `CHECK`; every cross-row rule uses `CREATE CONSTRAINT TRIGGER ... DEFERRABLE INITIALLY
DEFERRED` instead).

For the actual migration-ready DDL itself (all 236 `CREATE TABLE` statements), see
`03-Core-Domain-Model/` (Foundation's 92) and each engine folder under
`04-Platform-Engine-Registry/` / `07-Presentation-Architecture/`. This document is the
*standard* those tables already conform to, not a duplicate of the DDL itself.

## Dependencies

- `04-Platform-Engine-Registry/` — this standard was derived from, and is proven against,
  the DDL already adopted in every engine's own specification.

## Status

**Populated — ADOPTED, 2026-08-16.** Every rule recorded here was already enforced,
table-by-table, before this document existed — it compiles proven discipline, not new
invention.
