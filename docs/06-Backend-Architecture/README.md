# 06. Backend Architecture

## Purpose

Defines the backend architecture for this project, per the Engineering Office
Project Repository Standard (`00-FOUNDATION/standards/PROJECT_REPOSITORY_STANDARD.md`).

## Scope

Services, APIs, authentication, authorization, event processing, integrations, background
jobs, validation, error handling.

## Contents

**`TRS026-TISC-001_Master_Instrument`** (md / docx / pdf) — the Technical Infrastructure &
Services Constitution (TISC), TrustRide's fourth and final sovereign instrument.

Covers exactly the external-facing backend surface: live tracking and telemetry ingestion
infrastructure, the settlement sequence and payment-rail infrastructure (M-Pesa C2B STK Push
primary, Flutterwave secondary, executed exclusively by Engine 6 Integration), Platform
Access capture infrastructure, messaging infrastructure (SMS/push/WhatsApp, plus the in-app
SOS/emergency escalation path), tax integration infrastructure (KRA eTIMS), and
identity-access/security infrastructure (external verification execution, secrets custody —
`integration_credential_reference` is the only table on the platform permitted to hold even a
vault *pointer*, and carries no public read policy).

For the internal event-processing/orchestration backend (the Sovereign Processing Unit —
routing, queueing, admission, consensus, recovery), see
`04-Platform-Engine-Registry/engine-07-orchestration/` and `engine-08-coordination/`. This
document covers the boundary with the outside world; those two cover the boundary between
engines.

## Dependencies

- `05-Database-Architecture/` — every infrastructure capability here writes only to tables
  already governed by the standard recorded there.

## Status

**Populated — ADOPTED, 2026-08-16.**
