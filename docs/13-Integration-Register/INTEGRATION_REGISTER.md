# TrustRide Integration Register (Engine 6)

Status as of 2026-10-11, migration `20261011000035`. The authoritative copy is the database
table `trustride.integration_port_registry` (columns `live_adapter`, `live_operations`,
`consumers`, `readiness`, `blocking_dependency`); this document mirrors it and adds the
endpoints and providers that are not ports. Suite `supabase/tests/21_integration_boundary.sql`
checks the register is complete and that the boundary below holds.

## How a port goes live

Every port starts on its **simulator**. TrustRide Office switches a port with `SET_ADAPTER`
(`fn_integration_adapter_set`, Founder or Administrator, audited).

- A port whose live adapter is **built** can be switched to `SANDBOX` or `PRODUCTION`. Its
  requests then go through `integration_outbound_request` → pg_net → the `integration-gateway`
  Edge Function, which calls the provider. If the gateway or its secrets are not configured, the
  request waits as `WAITING_CONFIGURATION` and the flow reports why. It never hangs and never
  succeeds silently.
- A port whose live adapter is **not built** cannot be switched. The switch refuses and names
  the dependency. If the registry is edited by hand around the switch, the port's function
  refuses with `PROVIDER_NOT_INTEGRATED` instead of passing a simulated answer off as a
  provider's.

## Ports

| Port | Live adapter | Live operations | Used by | Readiness | What blocks going live |
|---|---|---|---|---|---|
| PAYMENT_GATEWAY (Safaricom Daraja 3.0) | Built | STK_PUSH, B2C_PAYOUT | Order payment (STK push; callback through `mpesa-callback`), vendor payouts (B2C) | Live-ready, pending credentials | Daraja production credentials (shortcode, passkey, consumer key and secret, B2C initiator and security credential), `MPESA_CALLBACK_TOKEN`, callback base URL; Safaricom go-live approval |
| SMS_SERVICE (Africa's Talking) | Built | NOTIFY_SMS | Contact verification codes, notifications, critical Office alerts | Live-ready, pending credentials | `AT_USERNAME`, `AT_API_KEY`, approved `AT_SENDER_ID` |
| WHATSAPP_SERVICE (Meta Cloud API) | Built | NOTIFY_WHATSAPP | Notifications on the WhatsApp channel | Live-ready, pending credentials | WhatsApp Business account, approved template, `WHATSAPP_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID` |
| TELEMETRY_SERVICE (Protrack) | Built | PROTRACK_POLL, PROTRACK_PUSH | Vehicle/device GPS tracking (`protrack-ingest`, polled every 30 s) | Live-ready, pending credentials | `PROTRACK_API_BASE`, `PROTRACK_ACCOUNT`, `PROTRACK_PASSWORD`, `PROTRACK_SYSTEM_KEY` |
| NOTIFICATION_ROUTER | Internal | — | Channel choice, preferences and quiet hours for every notification | Internal | — |
| IDENTITY_AUTHORITY (IPRS / BRS / KRA) | Not built | — | Registration: person identity and organisation (BRS registration, KRA PIN) verification | Simulator only, pending provider | Contract with a licensed IPRS/BRS data provider; registration with the Office of the Data Protection Commissioner; then the gateway adapter |
| NTSA_SERVICE | Not built | — | Fleet and vehicle verification | Simulator only, pending provider | NTSA API access agreement or a licensed gateway; then the adapter |
| ROUTING_SERVICE | Not built | — | Distance/duration at order placement (Engine 4) and dispatch costing (Engine 5) | Simulator only, pending provider | Provider choice (HERE, Google or self-hosted OSM) **and a Founder ruling**, because routing distance feeds Engine 5 pricing |
| MAP_SERVICE (Google Maps Platform) | Not built | — | Nothing wired (no screen uses address search or geocoding) | Not wired, pending decision | Product decision on address search; Maps API key |
| ETIMS_SERVICE (KRA eTIMS) | Not built | — | Nothing wired (no invoice is submitted on settlement) | Not wired, pending decision | **Legal and tax determination**: who issues the eTIMS invoice for a TrustRide fare (TrustRide on its commission, or on the full fare as agent); KRA eTIMS VSCU/OSCU onboarding |
| EPRA_SERVICE | Not built | — | Nothing wired (Engine 5's fuel index waits for a signal that nothing emits) | Not wired, pending decision | **Founder ruling**: Engine 5 pricing is not to change, so feeding EPRA prices into it is the Founder's call; an EPRA data source |
| USSD_SERVICE (Africa's Talking) | Not built | — | Nothing wired (no inbound USSD endpoint) | Not wired, pending decision | Product decision on a USSD channel; a USSD service code |
| VOICE_MASKING_SERVICE | Not built | — | Nothing wired | Not wired, pending decision | Product decision on masked calling; provider with Kenyan proxy numbers |
| EMAIL_SERVICE | Not built | — (the gateway answers `EMAIL_PROVIDER_NOT_SELECTED`) | Notifications on the email channel | Not wired, pending decision | Founder selects a transactional email provider |
| PUSH_SERVICE (FCM) | Not built | — (the gateway answers `PUSH_NOT_AVAILABLE`) | Notifications on the push channel | Not wired, pending decision | A native app, or web push with device-token registration |

## Inbound endpoints (Edge Functions)

| Endpoint | Caller | Authentication | Writes through |
|---|---|---|---|
| `integration-gateway` | pg_net, from `fn_integration_outbound_dispatch` | `x-trustride-gateway-secret` header (`TRUSTRIDE_GATEWAY_SECRET`) | `fn_integration_gateway_ack`, `fn_integration_outbound_result` |
| `mpesa-callback` (`?kind=stk`, `b2c-result`, `b2c-timeout`) | Safaricom | Secret token in the URL (`MPESA_CALLBACK_TOKEN`); a success settles only with a receipt, the exact amount prompted and the prompted phone (migration 028) | `fn_integration_mpesa_callback_ingest`, `fn_integration_outbound_result` |
| `protrack-ingest` | pg_cron poll; Protrack push | Hashed TrustRide external-system key (scope `TELEMETRY_INGEST`) | `fn_integration_telemetry_ingest` |

## Providers outside Engine 6

| Provider | Purpose | Status |
|---|---|---|
| Supabase Auth (email) | Sign-up confirmation and password-reset emails | Live on staging (Supabase's built-in sender; custom SMTP is a production decision) |
| Vercel | Hosts the web app (`frontend/web`) | Live: https://trustride-services.vercel.app, deploys from `main` |

## Not provisioned (D14)

No port, adapter or function exists for these. Each needs a Founder decision before any work:

- **Airtel Money.** The register states Safaricom Daraja is the sole payment gateway. A second
  payment rail is a business decision.
- **MetaMap, or another document-and-selfie KYC provider.** Identity is designed around IPRS
  through `IDENTITY_AUTHORITY`. A KYC provider would be an alternative vendor for that port.
- **Google services beyond Maps.** Google Maps Platform is the named vendor of `MAP_SERVICE`,
  which is not wired.

## Tax, accounting, HR and inventory systems

There is no integration with an accounting package, payroll/HR system or external inventory
system. Settlements, payouts and commissions live in TrustRide's own ledgers
(`business_settlement`, `business_marketplace_payout`, the cost and resource registers).
eTIMS is the only tax-authority integration planned, and it waits on the determination above.
