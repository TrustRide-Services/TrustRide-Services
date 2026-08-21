# 08. API Specifications

## Purpose

Defines the API specifications for this project, per the Engineering Office
Project Repository Standard (`00-FOUNDATION/standards/PROJECT_REPOSITORY_STANDARD.md`).

## Scope

REST APIs, GraphQL APIs, event APIs, webhooks, contracts, authentication, versioning, error
codes.

## Contents

TrustRide exposes **REST only** — no GraphQL, per the platform's own signal-first design
(every mutation is a signal, not a generic query surface). Every engine's own specification
carries its full request/response JSON contracts in its own Section 3; this document is the
compiled index across all eleven, plus the platform-wide conventions every one of them shares.

### Platform-wide API conventions

- Every request that initiates a signal carries a client-generated `correlation_id` (UUID),
  echoed back in every response — the human-facing entry point into the same `correlation_id`
  that threads through the entire Signal Envelope (see `05-Database-Architecture/`).
- Versioning: `/api/v1/...` for every engine; a breaking change is a new version prefix,
  never an in-place contract change.
- Authentication: every request carries a Foundation-issued session token (`auth_session`);
  no engine issues its own credential.
- Error shape: `{ "correlation_id", "error_code", "error_message" }`, consistently, across
  every engine's `4xx` responses.

### Endpoint index by engine

| Engine | Endpoints |
| --- | --- |
| 002 Resources | `POST /resources/discover`, `POST /resources/reserve`, `GET /resources/fleet/{id}/compliance` |
| 003 Services | `GET /services/catalogue`, `POST /services/resolve`, `GET /services/marketplace/listings` |
| 004 Business | `POST /orders`, `POST /orders/{id}/accept`, `GET /orders/{id}/tracking`, `GET /orders/{id}/settlement` |
| 005 Cost | `POST /cost/unit-price/calculate`, `POST /cost/rate-cards/evaluate`, `GET /cost/ledger/reconcile` |
| 006 Integration | `POST /integration/payments/stk-push`, `POST /integration/webhooks/mpesa/callback`, `GET /integration/verification/{id}/status` |
| 007 Orchestration | `GET /orchestration/health`, `GET /orchestration/signals/{correlation_id}/trace` |
| 008 Coordination | `GET /coordination/consensus/{id}/status`, `GET /coordination/executions/{id}/certificate` |
| 009 AI/ML Advisory | `GET /advisory/recommendations`, `POST /advisory/recommendations/{id}/decision`, `GET /advisory/forecasts` |
| 010 Scenario Modelling | `POST /model/scenarios/{code}/run`, `GET /model/runs/{id}/results`, `GET /model/runs/compare` |
| 011 Presentation | `POST /present/commands`, `GET /present/projections/{code}`, `GET /present/heartbeat` |

Full request/response JSON examples for every endpoint above live in that engine's own
Section 3, under `04-Platform-Engine-Registry/` or `07-Presentation-Architecture/`.

### Webhooks (inbound, from external systems)

Exactly one inbound webhook surface exists on the platform: `POST
/integration/webhooks/mpesa/callback` (Engine 6). No other engine receives an external
webhook directly — this is the structural expression of TISC's "only Integration touches the
outside world" law.

## Dependencies

- `06-Backend-Architecture/` — every endpoint above is a thin HTTP surface over the signal
  emission this document's parent already governs; no endpoint performs a direct database
  write.

## Status

**Populated — ADOPTED, 2026-08-16.**
