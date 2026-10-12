# TrustRide Integration Register (Engine 6)

Status as of 2026-10-12, migration `20261012000054`. The authoritative copy is the database table
`trustride.integration_port_registry`, columns:

- `live_adapter`, `live_operations`, `consumers`, `readiness` and `blocking_dependency`;
- `status_checkpoints` and `status_level`, the nine-level status in Construction Directive §4.8.

This document mirrors that table and adds the endpoints and providers that are not ports.

- Suite `21_integration_boundary.sql` checks that the register is complete and that the switching rules hold.
- Suite `34_integration_register.sql` checks the nine-level status.

The operating-company inventory (Construction Directive §3) is in
[OPERATING_COMPANY_INTEGRATION_INVENTORY.md](OPERATING_COMPANY_INTEGRATION_INVENTORY.md).

## How a port goes live

Every port starts on its **simulator**. TrustRide Office switches a port with `SET_ADAPTER`
(`fn_integration_adapter_set`, Founder or Administrator, audited).

- **A port whose live adapter is built can be switched** to `SANDBOX` or `PRODUCTION`.
  - Its requests go through `integration_outbound_request` → pg_net → the `integration-gateway`
    Edge Function, which calls the provider.
  - If the gateway or its secrets are not configured, the request waits as `WAITING_CONFIGURATION`
    and the flow reports why. It never hangs and never succeeds silently.
- **A port whose live adapter is not built cannot be switched.** The switch refuses and names the
  dependency. If the registry is edited by hand around the switch, the port's function refuses with
  `PROVIDER_NOT_INTEGRATED`, or with a more specific refusal such as `ETIMS_TAX_DETERMINATION_PENDING`.
  It never passes a simulated answer off as a provider's.
- **A simulator never imitates a provider's artefact.** Simulated references are marked
  (`SIM-…`, `"simulated": true`).

## Nine-level status

The checkpoints are:

1. contract defined;
2. adapter implemented;
3. simulator implemented;
4. internal workflow and persistence tested;
5. security and audit tests passed;
6. live adapter implemented;
7. provider credentials and authorization available;
8. live end-to-end transaction tested;
9. operational monitoring and recovery proven.

A port's **level** is the highest checkpoint reached with no gap below it. The database computes it;
nobody types it. Checkpoints 7–9 cannot be recorded for a port whose live adapter is not built.
**No port is above level 6:** no provider credentials exist on staging, and no live transaction has been run.

| Port (provider) | Level | Checkpoints met | Next checkpoint and what it needs |
|---|---|---|---|
| PAYMENT_GATEWAY (Safaricom Daraja) | 6 | 1–6 | 7: Daraja credentials as Edge secrets (shortcode, passkey, consumer key and secret, B2C initiator and credential) |
| SMS_SERVICE (Africa's Talking) | 6 | 1–6 | 7: `AT_USERNAME`, `AT_API_KEY`, approved sender ID |
| WHATSAPP_SERVICE (Meta Cloud API) | 6 | 1–6 | 7: WhatsApp Business account, approved template, token, phone-number ID |
| EMAIL_SERVICE (Google, Gmail API) | 6 | 1–6 | 7: Google mailbox; Workspace service account with delegation, or OAuth client and refresh token |
| IDENTITY_AUTHORITY (MetaMap GovChecks) | 6 | 1–6 | 7: MetaMap account. Switching live is also blocked by the Founder decision on person onboarding |
| NTSA_SERVICE | 5 | 1–5 | 6: NTSA access agreement or licensed gateway (NTSA publishes no API) |
| ETIMS_SERVICE (KRA eTIMS) | 5 | 1–5 | 6: legal and tax determination, then KRA OSCU/VSCU onboarding and certification |
| EPRA_SERVICE | 5 | 1–5 | 6: not an API (EPRA publishes none). Prices are recorded by the Office; applying them to pricing awaits the Engine 5 derivation decision |
| TELEMETRY_SERVICE (Protrack) | **2** | 1, 2, 4, 5, 6 | 3: no telemetry simulator. Tests push points through the production ingest. 7: Protrack credentials and devices |
| ROUTING_SERVICE | 1 | 1, 3, 4, 5 | 2: Founder chooses the routing provider; then the adapter |
| PUSH_SERVICE | 1 | 1, 3 | 2: a native app, or web push with device-token registration |
| MAP_SERVICE | 0 | 3 | 1: product decision on address search |
| VOICE_MASKING_SERVICE | 0 | 3 | 1: product decision on masked calling |
| USSD_SERVICE | 0 | 3 | 1: product decision on a USSD channel |
| NOTIFICATION_ROUTER | internal | — | — |

## Ports

| Port | Live adapter | Live operations | Used by | What blocks going live |
|---|---|---|---|---|
| PAYMENT_GATEWAY | Built (`providers.ts`) | STK_PUSH, B2C_PAYOUT | Order payment (callback through `mpesa-callback`); vendor payouts | Daraja production credentials and callback URLs |
| SMS_SERVICE | Built (`providers.ts`) | NOTIFY_SMS | Verification codes, notifications, critical Office alerts | Africa's Talking account and sender ID |
| WHATSAPP_SERVICE | Built (`providers.ts`) | NOTIFY_WHATSAPP | Notifications on the WhatsApp channel | Business account, approved template, token |
| EMAIL_SERVICE | Built (`gmail.ts`) | NOTIFY_EMAIL | Notifications on the email channel | Google mailbox and credentials (see below) |
| TELEMETRY_SERVICE | Built (`protrack.ts`) | Poll, push | Vehicle GPS (`protrack-ingest`) | Protrack account and devices. Its API base is plain HTTP until Protrack confirms HTTPS |
| IDENTITY_AUTHORITY | Code built (`metamap.ts`); switch locked | IDENTITY_VERIFY (ke/iprs), ENTITY_VERIFY (ke/brs) | Registration (person, organisation) | Founder decision: IPRS via MetaMap returns no vital status and no KRA PIN, which Foundation's rule requires. Then the MetaMap account and ODPC registration. Direct IPRS deferred |
| NTSA_SERVICE | Not built | — (plate check and VIN/chassis identification run on the simulator) | Fleet verification; Office `NTSA_VEHICLE_LOOKUP` | NTSA agreement or licensed gateway |
| ETIMS_SERVICE | Not built | — (sales, purchases and reconciliation run on the simulator) | Office `RECORD_PURCHASE_INVOICE`; reconciliation | `ETIMS_TAX_DETERMINATION`, then KRA onboarding |
| EPRA_SERVICE | Built (Office record) | RECORD_EPRA_PRICE_CYCLE | Recorded, not applied to pricing | Engine 5 derivation correction and fare-impact approval |
| ROUTING_SERVICE | Not built | — (provider route matrix contract exists) | Distance and duration for orders and costing | Provider choice |
| MAP_SERVICE, USSD_SERVICE, VOICE_MASKING_SERVICE, PUSH_SERVICE | Not built | — | Nothing wired | Product decisions |

### Google email: which mechanism

The adapter supports both mechanisms Google offers for server-side sending. Which one applies depends
on the mailbox, and that is an external prerequisite.

- **Google Workspace mailbox:** a service account with domain-wide delegation for the `gmail.send`
  scope (`GMAIL_AUTH_MODE=SERVICE_ACCOUNT`). Recommended for production: no user token to expire,
  and Workspace sending limits apply.
- **Consumer Gmail** (e.g. @gmail.com): an OAuth client and refresh token
  (`GMAIL_AUTH_MODE=REFRESH_TOKEN`). Limits: about 500 messages a day. The OAuth app must be
  published and verified, since `gmail.send` is a sensitive scope; otherwise refresh tokens expire
  after 7 days.

Gmail has no sandbox, so `SANDBOX` delivers only to `GMAIL_SANDBOX_RECIPIENT`.

## Inbound endpoints (Edge Functions)

| Endpoint | Caller | Authentication | Writes through |
|---|---|---|---|
| `integration-gateway` | pg_net, from `fn_integration_outbound_dispatch` | `x-trustride-gateway-secret` (`TRUSTRIDE_GATEWAY_SECRET`); refuses when unset | `fn_integration_gateway_ack`, `fn_integration_outbound_result` |
| `mpesa-callback` (`stk`, `b2c-result`, `b2c-timeout`) | Safaricom | Secret token in the URL (`MPESA_CALLBACK_TOKEN`) | `fn_integration_mpesa_callback_ingest`, `fn_integration_outbound_result` |
| `metamap-webhook` | MetaMap | Secret token in the URL (`METAMAP_WEBHOOK_TOKEN`); MetaMap publishes no GovChecks signature scheme | `fn_integration_metamap_webhook_ingest` |
| `protrack-ingest` | pg_cron poll; Protrack push | Gateway secret (poll); hashed external-system key, scope `TELEMETRY_INGEST` (push) | `fn_integration_telemetry_ingest` |

## Failure rules (gateway)

- **Timeouts.** Every provider call has a 20 s timeout.
- **Configuration.** It is checked before any call (fail closed). Destinations and amounts are
  validated before money or messages move.
- **Ambiguous money outcomes.** An M-Pesa request whose outcome is unknown after sending is not
  reported as failed. It stays SENT, Safaricom's result can still settle it, and otherwise Engine 6's
  sweep closes it and tells the Office to verify on the M-Pesa portal. Money is never re-sent
  automatically.
- **Retries.** Non-money failures are retried with backoff up to `max_attempts`, then recorded failed.

## Providers outside Engine 6

| Provider | Purpose | Status |
|---|---|---|
| Supabase Auth (email) | Sign-up confirmation and password-reset emails | Live on staging (Supabase's sender; custom SMTP, e.g. Google, is a production decision) |
| Vercel | Hosts the web app (`frontend/web`) | Live: https://trustride-services.vercel.app, deploys from `main` |
| Amazon S3 (Object Lock) | External daily audit seals (`ops/audit-seal`) | Built and proven against a local S3-compatible store; AWS account not activated |

## Decided out of scope

- **Airtel Money:** cancelled by the Founder (decision 2.8). Daraja is the payment gateway.
- **Direct IPRS:** deferred by the Founder (decision 2.6). The identity contract is provider-neutral,
  so it can be added as a second vendor of `IDENTITY_AUTHORITY`.
- **Google Maps or other Google products for routing:** not approved by the email decision.
