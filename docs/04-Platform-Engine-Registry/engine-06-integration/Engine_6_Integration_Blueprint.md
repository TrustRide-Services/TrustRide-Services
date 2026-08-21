# TRUSTRIDE SERVICES

# ENGINE 6 — INTEGRATION ENGINE
## Complete Architectural, Data, API, and Signal Specification

**[Parent Authority: TBOC v2.0.0 Genesis Edition · Architecture Blueprint v1.1.0]**

*More than a Ride — We Save You Time.*

## Document Control

| Document Control Field | Entry |
| --- | --- |
| Document Title | Engine 6 — Integration Engine: Complete Specification |
| Document Identifier | TRS026-ENG006-INTG-001 |
| Version | 1.0.0 |
| Status | **ADOPTED** (2026-08-16, per Founder directive — build order FDN → Resources → Services → Business → Cost → Integration) |
| Classification | Institutional Blueprint — Confidential |
| Schema | `trustride` (single canonical PostgreSQL schema; this engine's tables are prefixed `integration_`) |
| Platform Code | TRS026 |
| Engine Code | `TRS026_ENG006_INTG` |
| Engine No. | `ENGINE_006` |
| Installation Order | 006 |
| Parent Authority | TBOC v2.0.0 Genesis Edition — Article 8 (Zero-Pollution Rule), Article 42.5 (electronic tax invoice law), Article 43 (Settlement Stages & Approved Payment Rails), Article 44 (Ledger Splits & Revenue Architecture), Article 48 (Workforce Financial Stewardship — statutory remittances), Article 49 (Financial Controls, Reporting & Audit), Article 52 (Vetting, Training & Continuous Verification), Article 54 (SOS & Emergency Escalation), Article 57 (The Four-Sovereign Framework — TISC scope), Article 60 (Lineage into TISC), Article 61 (The Inheritance Rules — traceability) |
| Architecture Lineage | Positioned as Engine 6 in the eleven-engine Constitutional Engine Registry (Annex C, FDN-001 v3.0.0); Layer 2 Business Runtime of the Backend/Frontend/Event-Signal Architecture Blueprint v1.1.0 |

## Document Purpose & Constitutional Basis

This instrument specifies **Engine 6 — the Integration Engine**, TrustRide's sole boundary with the outside world. It answers one constitutional question for the rest of the platform — **has the external system confirmed it, and what did it say?**

TBOC does not permit a technical document to invent business concepts (Article 8, the Zero-Pollution Rule). Every mechanical rule in this document therefore traces to a standing TBOC provision:

| This engine's function | TBOC basis |
| --- | --- |
| Executing the named payment rails — M-Pesa C2B STK Push (primary), Flutterwave (secondary) — as constitutional business law; their integration mechanics, credentials, and infrastructure governed downstream under TISC | Article 43 — Settlement Stages & Approved Payment Rails |
| Producing the lawful electronic tax invoice on every chargeable service | Article 42.5 |
| Ledger splits reaching statutory allocations that require external remittance | Article 44 — Ledger Splits & Revenue Architecture |
| Calculating, deducting, and remitting PAYE, NSSF, SHIF, Housing Levy, NITA, and withholding on statutory timelines | Article 48 — Workforce Financial Stewardship |
| Financial records audit-ready and institutional evidence | Article 49 — Financial Controls, Reporting & Audit |
| National identity verification, certificate of good conduct, guarantors, medical clearance, and statutory registrations as external checks | Article 52 — Vetting, Training & Continuous Verification |
| Escalation to public emergency response channels | Article 54 — SOS & Emergency Escalation |
| Live tracking and telemetry ingestion, payment and financial gateways, messaging (SMS, push, WhatsApp), tax integration, identity-access and security infrastructure — the TISC scope this engine executes | Article 57 — The Four-Sovereign Framework |
| TISC governs the settlement sequence, telemetry ingestion, and tax integration in infrastructure language, inheriting from this Constitution | Article 60 — Lineage into TISC |
| Every provision must name its parent article; work that cannot is not TrustRide work | Article 61 — The Inheritance Rules |
| No engine reads or writes another engine's tables; cross-engine truth moves only as a signal | Article 33 |

Foundation (Engine 1) holds the vetting *record* (`verification_record`) and forbids secrets anywhere in its own layer (FDN-001 Part V Law 12, Annex B). This engine is where that boundary is drawn: it is the **only** engine permitted to hold credential references, call an external system, and receive a webhook from one. No other engine of the eleven ever touches the outside world directly.

---

# SECTION 1 — ARCHITECTURAL ROLE & BOUNDARIES

## 1.1 Mission

Engine 6 is the platform's single, deterministic boundary with every system TrustRide does not own — payment rails, verification providers, the tax authority, the fuel-price regulator, and messaging gateways. No external call originates anywhere else on the platform; no external response is trusted anywhere else on the platform.

## 1.2 Operational Duties

1. **External system custody.** Maintain `integration_external_system_registry` — the constitutional inventory of every outside system TrustRide is integrated with, each classified, each governed.
2. **Credential custody.** Maintain `integration_credential_reference` — pointers into an external secrets vault, never the raw secret itself; this is the only table on the platform permitted to exist at all (FDN-001 Annex B, Secrets Law).
3. **Payment execution.** Execute the M-Pesa C2B STK Push and Flutterwave calls named as business law by TBOC Article 43, recording every attempt in `integration_payment_gateway_transaction`; Engine 6 never decides *whether* to charge, only executes the charge Cost (Engine 5) has already locked.
4. **Webhook reception.** Receive every inbound callback from an external system into `integration_webhook_inbound_log` before any downstream effect is applied — no external payload mutates platform state directly.
5. **Verification execution.** Execute National ID, Good Conduct, Guarantor, Medical, NTSA (licence, vehicle, inspection, insurance), and vendor KYC checks per Article 52, recording every request and outcome in `integration_verification_request`.
6. **Tax invoice submission.** Submit the lawful electronic tax invoice for every settled Order per Article 42.5, recording every submission in `integration_tax_invoice_submission`.
7. **Statutory remittance.** Submit PAYE, NSSF, SHIF, Housing Levy, NITA, and withholding remittances on statutory timelines per Article 48, recording every submission in `integration_statutory_remittance`.
8. **Messaging dispatch.** Execute SMS, push, and WhatsApp dispatch against Foundation's governed `notification_template` vocabulary, recording every send in `integration_message_dispatch_log`.
9. **Regulatory ingestion.** Ingest the monthly EPRA fuel-price gazette into `integration_epra_ingestion_log`, then hand the parsed rows to Cost (Engine 5) by signal.
10. **Resilience governance.** Maintain `integration_circuit_breaker_status` and `integration_retry_policy` so a failing external system degrades the platform gracefully rather than silently or catastrophically.

## 1.3 Interfaces with the Other Ten Engines

Per Plate I of the Backend Architecture and the Event/Signal Architecture, Engine 6 **never** calls another engine directly, and no other engine ever calls an external system directly. Every interface below is a signal, carried through Engines 7/8 (Workflow Orchestration & Coordination) — the Sovereign Processing Unit.

| Engine | Direction | What crosses the boundary |
| --- | --- | --- |
| **Engine 1 — Foundation** | Inbound (via signal) | `VERIFICATION_REQUESTED` at registration/onboarding, carrying the subject and verification type; Engine 6 never reads or writes `verification_record` directly — Foundation's own accept-handler writes it on `VERIFICATION_COMPLETED` |
| **Engine 2 — Resources** | Outbound (via signal) | `FLEET_VERIFICATION_UPDATED` — NTSA registration, inspection, and insurance results, ingested autonomously on a governed re-verification schedule (Article 52.3) |
| **Engine 3 — Services** | Outbound (via signal) | `VENDOR_VERIFICATION_UPDATED` — marketplace vendor KYC and commercial-agreement verification results |
| **Engine 4 — Business** | Outbound (via signal) | `PAYMENT_SETTLED` — the settlement outcome of the M-Pesa/Flutterwave call, carrying the settlement reference and (once submitted) the eTIMS tax invoice reference |
| **Engine 5 — Cost** | Bidirectional | Inbound: `PAYMENT_STK_TRIGGERED`, the finalized fare handed to Integration for the actual rail call. Outbound: `EPRA_FUEL_INDEX_UPDATED`, the parsed monthly fuel-price gazette |
| **Engines 7/8 — Workflow Orchestration & Coordination** | Structural | The exclusive transport for every signal in and out of Engine 6's outbox/inbox |
| **Engine 9 — AI/ML Advisory** | Outbound (read-only) | Advisory reads `integration_circuit_breaker_status` and historical `integration_payment_gateway_transaction` outcomes as lawful projections for external-reliability and payment-success-rate recommendations; it never writes back |
| **Any engine** | Inbound (via signal) | `NOTIFICATION_DISPATCH_REQUESTED` (a governed template code, recipient, and channel) and `EMERGENCY_ESCALATION_REQUESTED` (Article 54) may be raised by any engine that has a lawful reason; Engine 6 is the only executor of either |

## 1.4 Boundaries — What Engine 6 Never Does

1. **Never decides a fare, a rate, or a commission.** Engine 6 executes the payment Cost has already locked; it never computes or alters an amount.
2. **Never holds a business record of its own domain.** No Order, no Job, no Service, no Resource — Engine 6 holds only the record of the *call* it made and what came back.
3. **Never stores a raw secret.** `integration_credential_reference` holds a vault pointer only; the platform database never contains a usable credential in plaintext (FDN-001 Part V Law 12).
4. **Never applies an external payload to platform state directly.** Every webhook lands in `integration_webhook_inbound_log` first; state mutation happens only through Engine 6's own accept-handler emitting a governed outbound signal, received and accepted by the owning engine's own inbox.
5. **Never calls an external system outside a governed `integration_external_system_registry` entry.** An integration with no registry row does not exist in TrustRide (Article 8.4 — No undocumented capability).
6. **Never retries indefinitely.** Every call type carries a governed `integration_retry_policy`; exhaustion opens the circuit breaker and surfaces to Coordination (Engine 8) for operator review, never a silent infinite loop.

---

# SECTION 2 — PRODUCTION SQL DDL SCHEMA (PostgreSQL / Supabase-Ready)

## 2.0 Extensions & Enums (prerequisite)

```sql
-- Extensions (idempotent; already present platform-wide per Engine 001 Phase 0)
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- [Trace: TBOC-v2.0.0 | Article 57 | The Four-Sovereign Framework — TISC scope]
CREATE TYPE integration_system_category_enum AS ENUM (
  'PAYMENT_RAIL', 'VERIFICATION_PROVIDER', 'TAX_AUTHORITY', 'REGULATORY_FEED',
  'MESSAGING_GATEWAY', 'EMERGENCY_SERVICE'
);

CREATE TYPE integration_system_status_enum AS ENUM (
  'ACTIVE', 'SUSPENDED', 'DEPRECATED'
);

-- [Trace: TBOC-v2.0.0 | Article 43 | Settlement Stages & Approved Payment Rails]
CREATE TYPE integration_payment_rail_enum AS ENUM (
  'MPESA_C2B_STK', 'FLUTTERWAVE'
);

CREATE TYPE integration_txn_status_enum AS ENUM (
  'INITIATED', 'PENDING_CALLBACK', 'SETTLED', 'FAILED', 'TIMEOUT', 'REVERSED'
);

CREATE TYPE integration_breaker_state_enum AS ENUM (
  'CLOSED', 'OPEN', 'HALF_OPEN'
);

-- [Trace: TBOC-v2.0.0 | Article 52 | Vetting, Training & Continuous Verification]
CREATE TYPE integration_verification_subject_enum AS ENUM (
  'PERSON', 'FLEET_ASSET', 'VENDOR_ENTITY'
);

CREATE TYPE integration_verification_type_enum AS ENUM (
  'NATIONAL_ID', 'GOOD_CONDUCT', 'GUARANTOR', 'MEDICAL',
  'NTSA_LICENCE', 'NTSA_VEHICLE', 'NTSA_INSPECTION', 'NTSA_INSURANCE',
  'VENDOR_KYC', 'VENDOR_COMMERCIAL_AGREEMENT'
);

CREATE TYPE integration_verification_outcome_enum AS ENUM (
  'PENDING', 'VERIFIED', 'FAILED', 'EXPIRED'
);

CREATE TYPE integration_submission_status_enum AS ENUM (
  'PENDING', 'SUBMITTED', 'ACCEPTED', 'REJECTED'
);

-- [Trace: TBOC-v2.0.0 | Article 48 | Workforce Financial Stewardship]
CREATE TYPE integration_remittance_type_enum AS ENUM (
  'PAYE', 'NSSF', 'SHIF', 'HOUSING_LEVY', 'NITA', 'WITHHOLDING_TAX'
);

-- [Trace: TBOC-v2.0.0 | Article 57 | Messaging (SMS, push, WhatsApp)]
CREATE TYPE integration_message_channel_enum AS ENUM (
  'SMS', 'PUSH', 'WHATSAPP', 'EMAIL'
);

CREATE TYPE integration_dispatch_status_enum AS ENUM (
  'QUEUED', 'SENT', 'DELIVERED', 'FAILED'
);
```

## 2.1 `integration_external_system_registry` — The Governed External Inventory

```sql
-- [Trace: TBOC-v2.0.0 | Article 8.4, Article 57 | No undocumented capability]
CREATE TABLE integration_external_system_registry (
  system_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  system_code          TEXT NOT NULL UNIQUE,
  system_name          TEXT NOT NULL,
  system_category      integration_system_category_enum NOT NULL,
  base_endpoint_uri     TEXT,
  status                  integration_system_status_enum NOT NULL DEFAULT 'ACTIVE',
  onboarded_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE integration_external_system_registry IS
  '[Trace: TBOC-v2.0.0 | Article 8.4] An integration with no registry row does not exist in TrustRide. The single lawful inventory of every outside system this platform touches.';

-- Row Level Security (TBOC Zero-Trust law; FDN-001 Annex B, Part III Phase 8) — governed reference data, platform-readable, engine-service writable
ALTER TABLE integration_external_system_registry ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_external_system_registry_platform_read ON integration_external_system_registry
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY integration_external_system_registry_service_write ON integration_external_system_registry
  FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);

INSERT INTO integration_external_system_registry (system_code, system_name, system_category) VALUES
  ('MPESA_C2B_STK',        'M-Pesa C2B STK Push',                 'PAYMENT_RAIL'),
  ('FLUTTERWAVE',          'Flutterwave',                          'PAYMENT_RAIL'),
  ('NTSA_VERIFICATION',    'NTSA Vehicle & Licence Verification',  'VERIFICATION_PROVIDER'),
  ('VENDOR_KYC_PROVIDER',  'Vendor KYC & Commercial Verification', 'VERIFICATION_PROVIDER'),
  ('ETIMS_KRA',            'KRA eTIMS Electronic Tax Invoicing',   'TAX_AUTHORITY'),
  ('STATUTORY_REMITTANCE', 'Statutory Remittance Gateway (PAYE/NSSF/SHIF/Housing Levy/NITA)', 'TAX_AUTHORITY'),
  ('EPRA_FUEL_INDEX',      'EPRA Monthly Fuel Price Gazette',      'REGULATORY_FEED'),
  ('SMS_GATEWAY',          'SMS Gateway',                          'MESSAGING_GATEWAY'),
  ('WHATSAPP_GATEWAY',     'WhatsApp Business Gateway',            'MESSAGING_GATEWAY'),
  ('PUSH_GATEWAY',         'Push Notification Gateway',            'MESSAGING_GATEWAY'),
  ('EMERGENCY_DISPATCH',   'Public Emergency Response Channel',    'EMERGENCY_SERVICE');
```

## 2.2 `integration_credential_reference` — Vault Pointers Only

```sql
-- [Trace: TBOC-v2.0.0 | FDN-001 Part V Law 12, Annex B | Secrets exist only within Engine 006's boundary]
CREATE TABLE integration_credential_reference (
  credential_ref_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  system_id             UUID NOT NULL REFERENCES integration_external_system_registry (system_id),
  credential_purpose     TEXT NOT NULL,             -- e.g. 'API_KEY', 'OAUTH_CLIENT', 'WEBHOOK_SECRET'
  vault_reference           TEXT NOT NULL,           -- pointer into the external secrets vault; never the raw secret
  rotation_policy_days         SMALLINT NOT NULL DEFAULT 90,
  last_rotated_at                 TIMESTAMPTZ,
  expires_at                         TIMESTAMPTZ,
  status                                TEXT NOT NULL DEFAULT 'ACTIVE'
                                          CHECK (status IN ('ACTIVE', 'ROTATING', 'EXPIRED', 'REVOKED')),
  created_at                              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_integration_credential_system ON integration_credential_reference (system_id) WHERE status = 'ACTIVE';

COMMENT ON TABLE integration_credential_reference IS
  '[Trace: TBOC-v2.0.0 | FDN-001 Annex B Secrets Law] Holds a vault pointer only. This table, and this engine, is the sole lawful place on the platform where even a credential reference may live.';

-- Row Level Security — no platform_read policy at all: even a vault reference is engine-service-only, never broadly readable
ALTER TABLE integration_credential_reference ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_credential_reference_service_only ON integration_credential_reference
  FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);
```

## 2.3 `integration_circuit_breaker_status` — Resilience Governance

```sql
-- [Trace: TBOC-v2.0.0 | Article 56 | Business Continuity — payment-rail failure and physical disruption]
CREATE TABLE integration_circuit_breaker_status (
  breaker_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  system_id             UUID NOT NULL UNIQUE REFERENCES integration_external_system_registry (system_id),
  breaker_state          integration_breaker_state_enum NOT NULL DEFAULT 'CLOSED',
  failure_count             INTEGER NOT NULL DEFAULT 0 CHECK (failure_count >= 0),
  last_failure_at              TIMESTAMPTZ,
  opened_at                       TIMESTAMPTZ,
  next_retry_at                      TIMESTAMPTZ,
  updated_at                            TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE integration_circuit_breaker_status IS
  '[Trace: TBOC-v2.0.0 | Article 56] A failing external system degrades gracefully; the breaker opens rather than the platform retrying indefinitely or masking the failure.';

ALTER TABLE integration_circuit_breaker_status ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_circuit_breaker_status_platform_read ON integration_circuit_breaker_status
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY integration_circuit_breaker_status_service_write ON integration_circuit_breaker_status
  FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);
```

## 2.4 `integration_retry_policy` — Governed Retry & Backoff

```sql
-- [Trace: TBOC-v2.0.0 | Article 56 | Business Continuity]
CREATE TABLE integration_retry_policy (
  retry_policy_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  system_id             UUID NOT NULL REFERENCES integration_external_system_registry (system_id),
  call_type             TEXT NOT NULL,
  max_attempts           SMALLINT NOT NULL DEFAULT 3 CHECK (max_attempts > 0),
  backoff_seconds_base      SMALLINT NOT NULL DEFAULT 2 CHECK (backoff_seconds_base > 0),
  backoff_multiplier           NUMERIC(4,2) NOT NULL DEFAULT 2.00 CHECK (backoff_multiplier >= 1.00),
  timeout_ms                      INTEGER NOT NULL DEFAULT 15000 CHECK (timeout_ms > 0),
  active                             BOOLEAN NOT NULL DEFAULT TRUE,
  created_at                            TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (system_id, call_type)
);

COMMENT ON TABLE integration_retry_policy IS
  '[Trace: TBOC-v2.0.0 | Article 56] Every call type carries a governed retry policy; exhaustion opens the circuit breaker, never a silent infinite loop.';

ALTER TABLE integration_retry_policy ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_retry_policy_platform_read ON integration_retry_policy
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY integration_retry_policy_service_write ON integration_retry_policy
  FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);
```

## 2.5 `integration_payment_gateway_transaction` — Payment Rail Execution Ledger

```sql
-- [Trace: TBOC-v2.0.0 | Article 43 | Settlement Stages & Approved Payment Rails]
CREATE TABLE integration_payment_gateway_transaction (
  gateway_txn_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  system_id             UUID NOT NULL REFERENCES integration_external_system_registry (system_id),
  quote_id              UUID,                        -- by value reference to Engine 5's cost_unit_price_quotes.quote_id
  order_id              UUID,                        -- by value reference to Engine 4's business_order.order_id
  requester_user_id     UUID NOT NULL,               -- reference only; identity lives in Foundation
  payment_rail          integration_payment_rail_enum NOT NULL,
  amount_kes            NUMERIC(18,2) NOT NULL CHECK (amount_kes >= 0),
  currency               CHAR(3) NOT NULL DEFAULT 'KES',
  external_reference        TEXT,                    -- the rail's own transaction reference, once available
  request_payload              JSONB NOT NULL,
  response_payload                JSONB,
  txn_status                        integration_txn_status_enum NOT NULL DEFAULT 'INITIATED',
  correlation_id                       UUID NOT NULL,
  initiated_at                            TIMESTAMPTZ NOT NULL DEFAULT now(),
  settled_at                                 TIMESTAMPTZ,
  created_at                                    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_integration_gateway_txn_status ON integration_payment_gateway_transaction (txn_status);
CREATE INDEX idx_integration_gateway_txn_order ON integration_payment_gateway_transaction (order_id);
CREATE INDEX idx_integration_gateway_txn_correlation ON integration_payment_gateway_transaction (correlation_id);

COMMENT ON TABLE integration_payment_gateway_transaction IS
  '[Trace: TBOC-v2.0.0 | Article 43] Engine 6 never decides whether to charge; it executes the charge Cost has already locked, and records every attempt.';

-- Row Level Security — requester sees only their own transactions; the engine service role has full access
ALTER TABLE integration_payment_gateway_transaction ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_payment_gateway_transaction_requester_read ON integration_payment_gateway_transaction
  FOR SELECT TO trustride_authenticated
  USING (requester_user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY integration_payment_gateway_transaction_service_write ON integration_payment_gateway_transaction
  FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);
```

## 2.6 `integration_webhook_inbound_log` — Every Inbound Callback, Before Any Effect

```sql
-- [Trace: TBOC-v2.0.0 | Article 49 | Financial Controls — evidence discipline]
CREATE TABLE integration_webhook_inbound_log (
  webhook_id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  system_id                     UUID NOT NULL REFERENCES integration_external_system_registry (system_id),
  webhook_type                  TEXT NOT NULL,        -- e.g. 'MPESA_STK_CALLBACK', 'NTSA_VERIFICATION_CALLBACK'
  correlated_gateway_txn_id     UUID REFERENCES integration_payment_gateway_transaction (gateway_txn_id),
  raw_payload                   JSONB NOT NULL,
  signature_verified            BOOLEAN NOT NULL DEFAULT FALSE,
  processing_status             TEXT NOT NULL DEFAULT 'RECEIVED'
                                   CHECK (processing_status IN ('RECEIVED', 'PROCESSED', 'REJECTED', 'DUPLICATE')),
  received_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at                  TIMESTAMPTZ
);

CREATE INDEX idx_integration_webhook_status ON integration_webhook_inbound_log (processing_status);
CREATE INDEX idx_integration_webhook_gateway_txn ON integration_webhook_inbound_log (correlated_gateway_txn_id) WHERE correlated_gateway_txn_id IS NOT NULL;

COMMENT ON TABLE integration_webhook_inbound_log IS
  '[Trace: TBOC-v2.0.0 | Article 49] No external payload mutates platform state directly; it lands here first, unsigned payloads are flagged, and only a processed, verified row may trigger a downstream signal.';

ALTER TABLE integration_webhook_inbound_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_webhook_inbound_log_service_only ON integration_webhook_inbound_log
  FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);
```

## 2.7 `integration_verification_request` — External Vetting Execution

```sql
-- [Trace: TBOC-v2.0.0 | Article 52 | Vetting, Training & Continuous Verification]
CREATE TABLE integration_verification_request (
  verification_request_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  system_id                 UUID NOT NULL REFERENCES integration_external_system_registry (system_id),
  subject_type               integration_verification_subject_enum NOT NULL,
  subject_ref_id              UUID NOT NULL,          -- polymorphic, by value: person_user_id / fleet_resource_id / vendor entity_id
  verification_type              integration_verification_type_enum NOT NULL,
  request_payload                   JSONB NOT NULL,
  response_payload                     JSONB,
  outcome                                 integration_verification_outcome_enum NOT NULL DEFAULT 'PENDING',
  correlation_id                            UUID NOT NULL,
  requested_at                                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at                                    TIMESTAMPTZ,
  created_at                                         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_integration_verification_subject ON integration_verification_request (subject_type, subject_ref_id);
CREATE INDEX idx_integration_verification_outcome ON integration_verification_request (outcome);

COMMENT ON TABLE integration_verification_request IS
  '[Trace: TBOC-v2.0.0 | Article 52] Every National ID, Good Conduct, Guarantor, Medical, NTSA, and vendor KYC check executed by this platform is recorded here; Foundation''s verification_record is written only by Foundation''s own accept-handler on VERIFICATION_COMPLETED.';

ALTER TABLE integration_verification_request ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_verification_request_service_only ON integration_verification_request
  FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);
```

## 2.8 `integration_tax_invoice_submission` — eTIMS Electronic Tax Invoicing

```sql
-- [Trace: TBOC-v2.0.0 | Article 42.5 | Every chargeable service produces a lawful electronic tax invoice]
CREATE TABLE integration_tax_invoice_submission (
  invoice_submission_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id                  UUID NOT NULL,           -- by value reference to Engine 4's business_order.order_id
  receipt_code              TEXT NOT NULL,           -- by value, matches Engine 4's business_settlement.receipt_code
  taxable_amount_kes        NUMERIC(18,2) NOT NULL CHECK (taxable_amount_kes >= 0),
  tax_amount_kes            NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (tax_amount_kes >= 0),
  currency                  CHAR(3) NOT NULL DEFAULT 'KES',
  etims_invoice_reference   TEXT,                    -- KRA-issued invoice reference, once submitted
  submission_status         integration_submission_status_enum NOT NULL DEFAULT 'PENDING',
  submitted_at               TIMESTAMPTZ,
  created_at                    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_integration_tax_invoice_order ON integration_tax_invoice_submission (order_id);
CREATE UNIQUE INDEX uq_integration_tax_invoice_receipt ON integration_tax_invoice_submission (receipt_code);

COMMENT ON TABLE integration_tax_invoice_submission IS
  '[Trace: TBOC-v2.0.0 | Article 42.5] Submitted automatically as part of the same settlement-completion flow that produces PAYMENT_SETTLED; Business receives the etims_invoice_reference on that signal, never by a separate request.';

ALTER TABLE integration_tax_invoice_submission ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_tax_invoice_submission_service_only ON integration_tax_invoice_submission
  FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);
```

## 2.9 `integration_statutory_remittance` — PAYE, NSSF, SHIF, Housing Levy, NITA

```sql
-- [Trace: TBOC-v2.0.0 | Article 48 | Workforce Financial Stewardship]
CREATE TABLE integration_statutory_remittance (
  remittance_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  remittance_type        integration_remittance_type_enum NOT NULL,
  period_start            DATE NOT NULL,
  period_end               DATE NOT NULL,
  amount_kes                 NUMERIC(18,2) NOT NULL CHECK (amount_kes >= 0),
  currency                     CHAR(3) NOT NULL DEFAULT 'KES',
  authority_reference             TEXT,
  submission_status                  integration_submission_status_enum NOT NULL DEFAULT 'PENDING',
  submitted_at                          TIMESTAMPTZ,
  created_at                               TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_integration_remittance_period CHECK (period_end > period_start)
);

CREATE INDEX idx_integration_remittance_type_period ON integration_statutory_remittance (remittance_type, period_start DESC);

COMMENT ON TABLE integration_statutory_remittance IS
  '[Trace: TBOC-v2.0.0 | Article 48] Statutory obligations are calculated, deducted, and remitted on statutory timelines; compliance evidence is institutional record.';

-- Row Level Security — statutory financial records, Foundation Audit and engine-service roles only
ALTER TABLE integration_statutory_remittance ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_statutory_remittance_audit_read ON integration_statutory_remittance
  FOR SELECT TO trs_fdn_audit_service USING (true);
CREATE POLICY integration_statutory_remittance_service_write ON integration_statutory_remittance
  FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);
```

## 2.10 `integration_message_dispatch_log` — SMS, Push, WhatsApp Execution

```sql
-- [Trace: TBOC-v2.0.0 | Article 57 | Messaging (SMS, push, WhatsApp)]
CREATE TABLE integration_message_dispatch_log (
  dispatch_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  system_id              UUID NOT NULL REFERENCES integration_external_system_registry (system_id),
  template_code           TEXT NOT NULL,             -- by value; Foundation Substrate's notification_template.template_code
  channel                    integration_message_channel_enum NOT NULL,
  recipient_user_id             UUID NOT NULL,        -- reference only
  recipient_address                TEXT NOT NULL,     -- phone/token/email at time of send
  rendered_body                       TEXT,
  dispatch_status                        integration_dispatch_status_enum NOT NULL DEFAULT 'QUEUED',
  correlation_id                            UUID NOT NULL,
  dispatched_at                                TIMESTAMPTZ,
  created_at                                      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_integration_dispatch_status ON integration_message_dispatch_log (dispatch_status);
CREATE INDEX idx_integration_dispatch_recipient ON integration_message_dispatch_log (recipient_user_id);

COMMENT ON TABLE integration_message_dispatch_log IS
  '[Trace: TBOC-v2.0.0 | Article 57] Executes against Foundation''s governed notification_template vocabulary only; this engine never invents message content.';

ALTER TABLE integration_message_dispatch_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_message_dispatch_log_recipient_read ON integration_message_dispatch_log
  FOR SELECT TO trustride_authenticated
  USING (recipient_user_id = current_setting('app.current_user_id', true)::uuid);
CREATE POLICY integration_message_dispatch_log_service_write ON integration_message_dispatch_log
  FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);
```

## 2.11 `integration_epra_ingestion_log` — Monthly Fuel Price Gazette Ingestion

```sql
-- [Trace: TBOC-v2.0.0 | Article 45 (via Engine 5 dependency) | Regulatory ingestion]
CREATE TABLE integration_epra_ingestion_log (
  ingestion_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  system_id              UUID NOT NULL REFERENCES integration_external_system_registry (system_id),
  price_period            DATE NOT NULL,
  rows_ingested             INTEGER NOT NULL DEFAULT 0 CHECK (rows_ingested >= 0),
  source_reference             TEXT NOT NULL,
  ingestion_status                TEXT NOT NULL DEFAULT 'PENDING'
                                     CHECK (ingestion_status IN ('PENDING', 'COMPLETED', 'FAILED')),
  ingested_at                        TIMESTAMPTZ,
  created_at                            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX uq_integration_epra_period ON integration_epra_ingestion_log (price_period);

COMMENT ON TABLE integration_epra_ingestion_log IS
  '[Trace: TBOC-v2.0.0 | Article 45 via Engine 5] The gazette is ingested here, then handed to Cost (Engine 5) by EPRA_FUEL_INDEX_UPDATED — Engine 6 never computes a rate itself.';

ALTER TABLE integration_epra_ingestion_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_epra_ingestion_log_platform_read ON integration_epra_ingestion_log
  FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY integration_epra_ingestion_log_service_write ON integration_epra_ingestion_log
  FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);
```

## 2.12 Engine Event Substrate (Constitutional Mandatory Tables)

Per Plate I (Station Law) and CC-03 of the platform Conformance Certificate, every engine — Engine 6 included — carries exactly one outbox and one inbox, in the standard signal envelope shape (FDN-001 §11.2).

```sql
-- [Trace: TBOC-v2.0.0 | Article 59-60 — mandatory per-engine ledger tables]
CREATE TABLE integration_event_outbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG006_INTG',
  receiving_engine       TEXT NOT NULL,
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  signal_status               TEXT NOT NULL DEFAULT 'PENDING'
                                CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason              TEXT,
  idempotency_key                 TEXT NOT NULL UNIQUE,
  attempt_count                     INTEGER NOT NULL DEFAULT 0,
  emitted_at                         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_integration_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_integration_outbox_status ON integration_event_outbox (signal_status);
CREATE INDEX idx_integration_outbox_correlation ON integration_event_outbox (correlation_id);

ALTER TABLE integration_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_event_outbox_service_only ON integration_event_outbox
  FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);

-- [Trace: TBOC-v2.0.0 | Article 59-60 — mandatory per-engine ledger tables]
CREATE TABLE integration_event_inbox (
  signal_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id      UUID NOT NULL,
  causation_id         UUID,
  emitting_engine       TEXT NOT NULL,
  receiving_engine       TEXT NOT NULL DEFAULT 'TRS026_ENG006_INTG',
  signal_type              TEXT NOT NULL,
  payload_in                JSONB NOT NULL,
  payload_out                JSONB,
  signal_status                TEXT NOT NULL DEFAULT 'RECEIVED'
                                 CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason               TEXT,
  idempotency_key                  TEXT NOT NULL UNIQUE,
  received_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at                          TIMESTAMPTZ,
  CONSTRAINT chk_integration_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);
CREATE INDEX idx_integration_inbox_status ON integration_event_inbox (signal_status);
CREATE INDEX idx_integration_inbox_correlation ON integration_event_inbox (correlation_id);

ALTER TABLE integration_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_event_inbox_service_only ON integration_event_inbox
  FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);
```

---

# SECTION 3 — SYSTEM API CONTRACTS & WORKFLOW ORCHESTRATION

These endpoints are Engine 6's own external-facing surface — the one place on the platform where an HTTP call originates from, or is received from, outside TrustRide. Every internal effect still enters and leaves through Engine 6's own signal envelope (§5).

## 3.1 `POST /api/v1/integration/payments/stk-push`

**Request** (internal call, triggered by receiving `PAYMENT_STK_TRIGGERED`)

```json
{
  "correlation_id": "8f14e45f-ceea-4c9c-9c60-1a2f3e4d5b6c",
  "quote_id": "b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e",
  "requester_user_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "amount_kes": 181.09,
  "payment_rail": "MPESA_C2B_STK"
}
```

**Response — `202 Accepted`**

```json
{
  "correlation_id": "8f14e45f-ceea-4c9c-9c60-1a2f3e4d5b6c",
  "gateway_txn_id": "c3d4e5f6-a7b8-4c9d-0e1f-2a3b4c5d6e7f",
  "txn_status": "PENDING_CALLBACK"
}
```

## 3.2 `POST /api/v1/integration/webhooks/mpesa/callback`

**Request** (external-facing; signed by M-Pesa)

```json
{
  "MerchantRequestID": "29115-34620561-1",
  "CheckoutRequestID": "ws_CO_16082026090001234",
  "ResultCode": 0,
  "ResultDesc": "The service request is processed successfully.",
  "MpesaReceiptNumber": "TIJ7K8L9M0"
}
```

**Response — `200 OK`** (acknowledged to M-Pesa; downstream effect happens asynchronously via signal)

```json
{ "ResultCode": 0, "ResultDesc": "Accepted" }
```

## 3.3 `GET /api/v1/integration/verification/{verification_request_id}/status`

**Request** (path parameter `verification_request_id`)

**Response — `200 OK`**

```json
{
  "verification_request_id": "d5e6f7a8-b9c0-4d1e-8f2a-3b4c5d6e7f8a",
  "subject_type": "PERSON",
  "verification_type": "GOOD_CONDUCT",
  "outcome": "VERIFIED",
  "completed_at": "2026-08-16T09:40:00Z"
}
```

---

# SECTION 4 — EVENT-DRIVEN SIGNAL & INTEGRATION MATRIX

Every signal below travels the constitutional shape (Plate I): `integration_event_outbox` → Engines 7/8 (Orchestration + Coordination) → target engine's inbox, or the reverse into `integration_event_inbox`. Engine 6 never emits to, or receives directly from, another engine's outbox/inbox — and no other engine ever calls an external system directly.

## 4.1 Inbound Signals — Listened To

| Signal | Emitting engine | Payload (key fields) | Effect inside Engine 6 |
| --- | --- | --- | --- |
| `PAYMENT_STK_TRIGGERED` | Engine 5 (Cost), via Engines 7/8 | `quote_id`, `computed_total_fare_kes`, `currency`, `requester_user_id`, `payment_rail` | Writes an `integration_payment_gateway_transaction` row and executes the M-Pesa/Flutterwave call |
| `VERIFICATION_REQUESTED` | Engine 1 (Foundation), via Engines 7/8 | `subject_type`, `subject_ref_id`, `verification_type` | Writes an `integration_verification_request` row and executes the external check |
| `NOTIFICATION_DISPATCH_REQUESTED` | Any engine, via Engines 7/8 | `template_code`, `channel`, `recipient_user_id` | Writes an `integration_message_dispatch_log` row and executes the SMS/push/WhatsApp send |
| `EMERGENCY_ESCALATION_REQUESTED` | Any engine, via Engines 7/8 | `subject_user_id`, `session_context`, `location` | Escalates to the public emergency response channel per Article 54; every SOS event recorded end-to-end |

## 4.2 Outbound Signals — Emitted

| Signal | Receiving engine | Payload (key fields) | Triggering condition |
| --- | --- | --- | --- |
| `PAYMENT_SETTLED` | Engine 4 (Business), via Engines 7/8 | `order_id`, `settlement_reference`, `settled_at`, `etims_invoice_reference` | Fired when `integration_payment_gateway_transaction.txn_status` reaches `SETTLED`; the eTIMS submission (§2.8) runs as part of the same completion flow, so the invoice reference is included, never requested separately |
| `FLEET_VERIFICATION_UPDATED` | Engine 2 (Resources), via Engines 7/8 | `fleet_resource_id`, `inspection_status`, `insurance_status`, `verified_at` | Fired on a governed re-verification schedule (Article 52.3) or on completion of an NTSA check |
| `VENDOR_VERIFICATION_UPDATED` | Engine 3 (Services), via Engines 7/8 | `vendor_user_id`, `verification_status`, `verified_at` | Fired on completion of a vendor KYC or commercial-agreement check |
| `VERIFICATION_COMPLETED` | Engine 1 (Foundation), via Engines 7/8 | `subject_user_id`, `verification_type`, `outcome`, `verified_at` | Fired in answer to `VERIFICATION_REQUESTED`; Foundation's own accept-handler writes `verification_record` |
| `EPRA_FUEL_INDEX_UPDATED` | Engine 5 (Cost), via Engines 7/8 | `price_period`, `fuel_type`, `jurisdiction`, `pump_price_kes`, `source_reference` | Fired on completion of the monthly EPRA gazette ingestion (§2.11) |
| `NOTIFICATION_DISPATCH_COMPLETED` | Originating engine, via Engines 7/8 | `dispatch_id`, `dispatch_status`, `correlation_id` | Fired when a queued dispatch reaches `SENT`, `DELIVERED`, or `FAILED` |
| `EMERGENCY_ESCALATION_ACKNOWLEDGED` | Originating engine, via Engines 7/8 | `subject_user_id`, `acknowledged_at`, `response_reference` | Fired the instant the public emergency response channel acknowledges the escalation |

## 4.3 The Signal Envelope (as applied to Engine 6)

Identical to the platform-wide envelope (Plate I, §11.2 of the Foundation instrument): `signal_id`, `correlation_id`, `causation_id`, `emitting_engine` = `TRS026_ENG006_INTG`, `receiving_engine`, `signal_type`, `payload_in`, `payload_out`, `signal_status`, `rejection_reason`, `idempotency_key`, `attempt_count`, `emitted_at`, `received_at`, `accepted_at`. No field is added, renamed, or omitted — an engine that invents its own envelope shape is non-conformant.

---

# ANNEX — CONFORMANCE SELF-CERTIFICATION AGAINST THE THREE PLATES

Filed in the same discipline as the Foundation instrument's Part XI and the Engine 2/Engine 3/Engine 4/Engine 5 Annexes, so that Engine 6 can be certified on the same footing as its sibling engines.

| Check | Requirement | Result | Evidence |
| --- | --- | --- | --- |
| CC-02 | Every table assigned to exactly one of the five stations | **PASS** | §2.1–2.12: domain tables = Domain State; `integration_event_outbox` = Emission Ledger; `integration_event_inbox` = Reception Ledger; mutation only via the engine's own accept-handler |
| CC-03 | Engine carries the four ledger tables with the standard envelope | **PASS** | §2.12, §4.3 |
| CC-04 | Every cross-engine interaction is a signal; no foreign table access | **PASS** | §1.3, §4 — every interface listed is a named signal; `quote_id`, `order_id`, `subject_ref_id`, and `recipient_user_id` are by value, never a foreign key into another engine's schema |
| CC-06 | Idempotency, retry, dead-letter declared | **PASS** | `idempotency_key` UNIQUE on both ledger tables (§2.12); `integration_retry_policy` and `integration_circuit_breaker_status` govern external-call retry and exhaustion (§2.3, §2.4) |
| CC-07 | Engine declares its layer, holds nothing belonging to another layer | **PASS** | §1 — Layer 2, Business Runtime; holds no identity, order, catalogue, resource-availability, or pricing-computation state — only the record of the external call |
| CC-09 | Advisory outputs, if any, are records only | **N/A** | Engine 6 is not an advisory engine; it is a Layer 2 runtime engine |
| CC-12 | Every provision carries a trace tag | **PASS** | Every DDL block and table comment carries a `[Trace: TBOC-v2.0.0 | Article ...]` tag |
| Money Law | Every KES-denominated column is `NUMERIC(18,2)` | **PASS** | `amount_kes` (§2.5), `taxable_amount_kes`/`tax_amount_kes` (§2.8), `amount_kes` (§2.9) |
| RLS Law | Row-Level Security enabled on every table | **PASS** | All thirteen tables (§2.1–2.12 — §2.12 carries two: `integration_event_outbox` and `integration_event_inbox`) carry `ENABLE ROW LEVEL SECURITY` with an explicit policy |
| Secrets Law | No raw secret in the platform database | **PASS** | `integration_credential_reference` (§2.2) holds a `vault_reference` pointer only, service-role-only, no `platform_read` policy |

---

**END OF SPECIFICATION**

*Engine 6 is TrustRide's only door to the outside world. Every payment, every verification, every tax invoice, every remittance, every message — one boundary, one governed inventory, one truth about what the outside world actually said.*
