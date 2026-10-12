# Operating-company integration inventory (Construction Directive §3)

As of 2026-10-12, after WP7. For each of the fifteen categories this asks three questions:

1. Does TrustRide already own the capability?
2. Is an external system justified?
3. Does an existing provider or adapter already meet the need?

Each justified integration then gets a register entry. Statuses use the nine-level scale in
[INTEGRATION_REGISTER.md](INTEGRATION_REGISTER.md), and the dispositions in Construction Directive §9.
Nothing here is a wish list: a category with no justified external system says so.

## Summary

| # | Category | Owned internally | External system justified now | Disposition |
|---|---|---|---|---|
| 1 | HR and payroll | Partly: Operators are employees (Engine 2 engagements, Engine 4 pay); statutory calculation built in WP7 (migration 053) | Not yet. Payroll runs, P10 and bank files come first; an external payroll bureau is a later choice | Awaiting Founder/professional decision (payroll model, Housing Levy treatment) |
| 2 | Accounting, bookkeeping, general ledger | Partly: settlements, payouts and commissions in TrustRide's ledgers (`business_settlement`, `business_marketplace_payout`, `resource_ledger_event`) | Yes, at production: an external accounting system is needed for statutory accounts | Awaiting Founder decision (accounting system) |
| 3 | Procurement and supplier management | Partly: supplier invoices recorded via eTIMS purchases (WP7) | No: volume does not justify a procurement system | Not applicable now |
| 4 | Inventory and parts | No parts inventory (`resource_marketplace_inventory` is marketplace capacity, not parts) | No: maintenance is done by outside garages | Not applicable now |
| 5 | Asset and maintenance management | Yes: `resource_fleet_register`, `resource_maintenance_record`, `resource_financial_asset`, inspection and insurance status (Engine 2) | No | Implemented internally |
| 6 | Document management and e-signing | Partly: agreements recorded (`business_partner_agreement`); no document store or signatures | Yes, before partner or employee contracts are signed digitally | Awaiting Founder decision (e-signature provider) |
| 7 | Customer relationship management | Yes: customer profiles, support cases and messages, reviews (Engine 4) | No | Implemented internally |
| 8 | Security monitoring and incidents | Yes: `security_event`, `system_incident`, conformance watch, audit chains; external seals built (WP2) | Yes: S3 Object Lock for seals (decision 2.9) | Blocked by external dependency (AWS account) |
| 9 | Backup and disaster recovery | Supabase platform backups only | Yes, at pre-production (decision 2.10) | Deferred by Founder; RPO/RTO and procedure in WP10 |
| 10 | Fleet, GPS, telemetry | Yes: telemetry binding, ingest, staleness (Engines 2 and 6) | Yes: Protrack (existing) | Level 2 (no telemetry simulator); blocked by external dependency (credentials, devices) |
| 11 | Mapping, routing, geocoding | Zones and estates internal; routing provider contract (WP6) | Yes: routing provider | Awaiting Founder decision (provider) |
| 12 | Regulatory and tax compliance | eTIMS capability (WP7), statutory calendar, EA statutory rating, NTSA boundary, EPRA recording | Yes: KRA eTIMS, NTSA | Awaiting legal determination (eTIMS); blocked by external dependency (NTSA) |
| 13 | Communications and notifications | Notification router, preferences, quiet hours (Engine 6) | Yes: Africa's Talking, WhatsApp, Google email | Level 6; blocked by external dependency (credentials) |
| 14 | Identity and entity verification | Foundation onboarding rules; identity live path (WP7) | Yes: MetaMap (decision 2.6) | Level 6; awaiting Founder decision (person onboarding rule) |
| 15 | Other: payments | Settlement and payouts internal | Yes: Safaricom Daraja | Level 6; blocked by external dependency (credentials) |

## Register of justified integrations

Each entry gives: the capability; the owning and consuming engines; the data owner; the provider; the
contract; the adapter and simulator; persistence and reconciliation; authorization, privacy and audit;
failure handling; tests; prerequisites; and the state and next action.

### Payments: Safaricom Daraja (category 15)
- **Capability:** customers pay by M-Pesa STK push; TrustRide pays partners and operators by B2C.
- **Owner:** Engine 6 boundary; Engine 4 owns settlement and payouts. Data owner: Engine 4.
- **Contract:**
  - STK_PUSH {msisdn, amount (whole KES), account_reference};
  - B2C_PAYOUT {msisdn, amount, remarks};
  - callbacks `stk`, `b2c-result`, `b2c-timeout`.
- **Adapter:** `providers.ts`. **Simulator:** STK simulator and simulator confirmation.
- **Persistence:** `integration_payment_gateway_transaction`, `integration_outbound_request`; M-Pesa receipt kept for reconciliation.
- **Security:**
  - callback URL token;
  - a settlement needs the receipt, the exact amount prompted and the prompted phone;
  - the Office verifies unknown outcomes.
- **Failure handling:**
  - money is never re-sent automatically;
  - an unknown outcome stays SENT for the callback or the sweep;
  - after 10 minutes (2 hours for an accepted B2C) it becomes a final failure plus an Office alert.
- **Tests:** suites 05, 15, 31; `providers.test.ts`.
- **Prerequisites:** Daraja production app, shortcode, passkey, B2C initiator and credential.
- **State:** level 6. **Next:** credentials, then one sandbox STK and one B2C end to end (level 8).

### Messaging: Africa's Talking SMS, WhatsApp, Google email (category 13)
- **Capability:** verification codes, trip and payment notices, Office alerts.
- **Owner:** Engine 6 (notification router). Consumers: all engines through `NOTIFICATION_DISPATCH_REQUESTED`.
- **Contract:** NOTIFY_SMS / NOTIFY_WHATSAPP / NOTIFY_EMAIL {destination, subject, body, template_code}.
- **Adapters:** `providers.ts`, `gmail.ts`. **Simulator:** the outbound simulator.
- **Persistence:** `integration_notification_dispatch_log` (destination masked), with the provider's message ID.
- **Privacy:** recipients see only their own deliveries; secrets live only in Edge secrets.
- **Failure handling:** retried with backoff, then FAILED with the provider's reason; a duplicate result changes nothing.
- **Tests:** suites 02, 31, 34; `providers.test.ts`, `gmail.test.ts`.
- **Prerequisites:** AT account and sender ID; WhatsApp Business account and approved template; Google mailbox and credentials.
- **State:** level 6 each.

### Identity and entity verification: MetaMap (category 14)
- **Capability:** verify a person against IPRS and a business against BRS before onboarding.
- **Owner:** Engine 6; Foundation (Engine 1) decides onboarding. Data owner: Foundation.
- **Contract:**
  - IDENTITY_VERIFY {document_number, first_name, last_name};
  - ENTITY_VERIFY {registration_number, legal_name};
  - result `VERIFICATION_COMPLETED`.
- **Adapter:** `metamap.ts` plus the `metamap-webhook` callback. **Simulator:** the identity and entity simulators.
- **Persistence:** verification logs with provider and request; only the shareholder count is kept.
- **Security:** service-role callbacks; each answer applied once; late answers refused.
- **Failure handling:** notFound is definitive; systemError and timeouts are retried, then PROVIDER_UNAVAILABLE.
- **Tests:** suite 29; `metamap.test.ts`.
- **Prerequisites:**
  - the Founder decision on the person onboarding rule;
  - a MetaMap account;
  - ODPC registration;
  - MetaMap's confirmation of a sandbox host and callback format.
- **State:** level 6, with the switch locked.

### Fleet telemetry: Protrack (category 10)
- **Capability:** vehicle positions for dispatch and tracking.
- **Owner:** Engine 6 ingest; Engine 2 binding and staleness.
- **Contract:** push or poll into `fn_integration_telemetry_ingest`.
- **Adapter:** `protrack.ts`. **Simulator:** none.
- **Security:** hashed system key, failed attempts logged; poll fails closed.
- **Tests:** suite 07; `protrack.test.ts`.
- **Prerequisites:** Protrack account and devices; HTTPS confirmation.
- **State:** level 2. **Next:** a telemetry simulator (internal software work, WP9 coverage), then credentials.

### Regulatory: KRA eTIMS, NTSA, EPRA (category 12)

**eTIMS.** Sales, purchases and reconciliation, with treatment UNDETERMINED (suite 32).
- Prerequisites: `ETIMS_TAX_DETERMINATION`, then OSCU/VSCU onboarding and certification.
- Level 5.

**NTSA.** Plate verification and VIN/chassis identification (suites 03, 30).
- Prerequisite: an NTSA agreement or licensed gateway.
- Level 5.

**EPRA.** The Office records each published cycle with its provenance (suite 28).
- Prerequisite: the Engine 5 derivation decision before prices feed pricing.
- Level 5.

### Routing (category 11)
- **Contract:** ROUTE_MATRIX; `fn_integration_route_matrix_apply` (provider route matrix, 30-day freshness).
- **Built:** simulator with provenance (suite 28).
- **Prerequisite:** the Founder's choice of routing provider (recommendation in the WP6 ledger).
- **State:** level 1.

### Audit seals: Amazon S3 Object Lock (category 8)
- **Built:** publisher and verifier (`ops/audit-seal`), proven end to end against a local S3-compatible store, including detection of a rewritten chain (WP2).
- **Prerequisites:**
  - an AWS account administered separately from Supabase;
  - a bucket with Object Lock, COMPLIANCE mode (7 years proposed);
  - credentials.

### Accounting system (category 2): justified, not chosen
- **Need:** statutory accounts need an external general ledger (e.g. a Kenyan-supported cloud accounting package).
- **TrustRide side:** the settlement, payout and commission ledgers are the source.
- **Contract to define when chosen:** a daily journal export by account, with reconciliation against M-Pesa receipts.
- **Disposition:** awaiting Founder decision. Recommendation: choose the package together with the eTIMS determination, since eTIMS invoices and the ledger must reconcile.

### Document signing (category 6): justified, not chosen
- **Need:** partner and employee contracts signed digitally.
- **Disposition:** awaiting Founder decision.
- **Next step:** recommend a provider when contracts are drafted; no TrustRide-side work is useful before the contract templates exist.
