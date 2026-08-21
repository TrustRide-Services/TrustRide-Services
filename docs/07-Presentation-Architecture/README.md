# 07. Presentation Architecture

## Purpose

Defines the presentation architecture for this project, per the Engineering Office
Project Repository Standard (`00-FOUNDATION/standards/PROJECT_REPOSITORY_STANDARD.md`).

## Scope

Web, mobile, desktop, dashboards, components, UX, accessibility, navigation.

## Contents

**`Engine_11_Presentation_Blueprint`** (md / docx / pdf) — Engine 011, Presentation: the only
engine of the eleven that a human ever touches directly, and this project's complete
presentation-layer specification.

Covers the five constitutional shells (User Hub, Operator App, Admin Console, Sovereign
Executive Console, Marketplace Hub) and their enforced permitted-verb registry
(`present_shell_capability_registry`, backed by a deferred constraint trigger — not a
client-side convention), the command-capture pipeline (every human action becomes a
`present_command_capture` row before it becomes a signal — the database proof of "commands
become signals"), the projection-render/cache pipeline (every screen traces to a registered,
non-authoritative `projection_registry` entry), the heartbeat-display pattern, in-app
notifications, and localization. 12 tables.

## Dependencies

- `04-Platform-Engine-Registry/` — Presentation converts intent into signals for every one
  of the ten domain/runtime engines and Foundation; it authors no business logic of its own.

## Status

**Populated — ADOPTED, 2026-08-16.**
