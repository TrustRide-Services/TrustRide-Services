# 03. Core Domain Model (CDM)

## Purpose

Defines the CDM for this project, per the Engineering Office Project Repository Standard
(`00-FOUNDATION/standards/PROJECT_REPOSITORY_STANDARD.md`).

## Scope

Bounded contexts, aggregates, entities, value objects, commands, events, services,
repositories, business processes, relationships.

## Contents

**`TRS026-FDN-001_v3.0.0_ADOPTED`** (md / docx / pdf) — Engine 001, Foundation: the platform's
core bounded context and the substrate every other engine (its own bounded context) depends
on. 92 tables across five sub-engines.

Mapped to DDD terms: **aggregates/entities** = `TRS_FDN_CORE` (platform identity) and
`TRS_FDN_IDENTITY` (Person/Entity/Thing, User Type Domains); **value objects** =
`TRS_FDN_SUBSTRATE`'s governed vocabulary (semantic dictionary, domain reference, units of
measure); **commands/events** = the canonical Signal Envelope (Part IV, §11.2) — the one
shape every command and event on the platform carries; **repositories** = each table's own
RLS-governed access; **business processes** = `TRS_FDN_GOVERNANCE` (policy, approval chains,
rate registers) and `TRS_FDN_AUDIT` (the immutable evidence of every process). Includes the
full, migration-ready DDL compilation (Annex H, all 92 tables).

Every other engine (`04-Platform-Engine-Registry/`, `07-Presentation-Architecture/`) is its
own bounded context, referencing Foundation's identities **by value only** — never a foreign
key across a bounded-context boundary. This is the constitutional expression of DDD's own
"no aggregate reaches into another aggregate's internals" discipline (TBOC Article 33).

## Dependencies

- `02-Software-Architecture-Definition-Document/` — per the mandated documentation
  hierarchy, this document must not introduce architecture that contradicts SAPC.

## Status

**Populated — ADOPTED, 2026-08-16.** Migration-ready.
