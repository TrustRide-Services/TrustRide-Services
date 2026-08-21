## Document Control

| Document Control Field | Entry |
| --- | --- |
| Document Title | Technical Infrastructure & Services Constitution (TISC) |
| Document Identifier | TRS026-TISC-001 |
| Version | 1.0.0 |
| Edition | Genesis Edition |
| Status | ADOPTED — Sovereign Constitutional Instrument, Fourth of the Four-Sovereign Framework |
| Classification | Institutional Blueprint — Confidential |
| Constitutional Authority | Inherits from TBOC v2.0.0 Genesis Edition through SAPC, per TBOC Article 60 — Lineage into TISC |
| Framework Position | Fourth Sovereign — Technical Infrastructure & Services Constitution |
| Derives From | TRS026-TBOC-001 v2.0.0 Genesis Edition, Article 60; TRS026-SAPC-001 v1.0.0 |
| Governs | Live tracking and telemetry ingestion, payment and financial gateways, messaging (SMS, push, WhatsApp), tax integration, identity-access and security infrastructure |
| May Never Contain | Business rules; architecture contrary to SAPC |
| Jurisdiction | Republic of Kenya |
| Platform Code | TRS026 |
| Platform Name | TRUSTRIDE_SERVICES |
| Founder | Onyango Albert Chitayi, Founder & Chief Executive Officer |
| Date of Issue | 2026-08-16 |
| Compilation Note | Every infrastructure capability below is already built, table by table, primarily within Engine 6 (Integration) and cross-referenced across Foundation, Business, and Presentation; TISC formalizes it as one binding infrastructure constitution |

---

## Constitutional Authority & Position in the Four-Sovereign Framework

This instrument is the **fourth and final** of TrustRide Services' sovereign documents. Per TBOC Article 60 (Lineage into TISC), it inherits from TBOC through SAPC and must express, in infrastructure language, six mandates. Engine 6 (Integration) is TISC's primary technical home — "the only engine permitted to hold credential references, call an external system, and receive a webhook from one" — but TISC's scope is broader than any one engine: it is the infrastructure discipline that Foundation, Business, and Presentation also carry pieces of, gathered here into one constitutional statement.

---

# PART I — LIVE TRACKING INFRASTRUCTURE

*[Trace: TBOC Article 60.1; TBOC Article 21]*

The Live Tracking Information Contract names five data elements as constitutionally mandatory wherever live tracking is active: **Resource Type, Resource ID, ETA, Status, Exact Location.** TISC's infrastructure expression:

- **Governed vocabulary:** Foundation's `tracking_element_registry` (TRS_FDN_SUBSTRATE) constitutes exactly these five elements as mandatory rows — `mandatory BOOLEAN DEFAULT TRUE` — never an optional field.
- **Session anchor:** Foundation's `tracking_session` and Business's `business_tracking_session` both realize the active-session-only law: born at Job start, closed at Job completion, never a standing surveillance record.
- **Telemetry ingestion boundary:** live GPS/location ingestion executes exclusively through Engine 6 (Integration)'s external-system boundary; the substrate owns the vocabulary, the zones, and the session anchor — never the external call itself (FDN-001 Part X, corrected from a stray "SIIC" citation to the correct "TISC" reference during this platform's conformity audit).
- **Privacy safeguard:** tracking data is subject to the Data Protection Act 2019 retention discipline Foundation's `retention_policy` (TRS_FDN_AUDIT) governs; telemetry ingestion never exceeds the five-element contract into general surveillance.

# PART II — SETTLEMENT SEQUENCE & PAYMENT RAIL INFRASTRUCTURE

*[Trace: TBOC Article 60.2; TBOC Article 43]*

**Payment Initiated → Payment Authorized → Payment Settled → Ledger Posted → Receipt Generated.**

- **Approved rails:** M-Pesa customer-to-business payment prompting (C2B STK Push), primary; Flutterwave, secondary — named as TBOC business law, executed exclusively under TISC governance.
- **Execution infrastructure:** Engine 6's `integration_payment_gateway_transaction` is the sole execution ledger; `integration_webhook_inbound_log` receives every rail callback before any downstream effect is applied — no external payload mutates platform state directly.
- **Record of the sequence:** Business's `business_settlement` carries the settlement stages as they apply to a specific Order; Engine 6's `PAYMENT_SETTLED` signal, carrying the `etims_invoice_reference`, is the sole lawful bridge back from execution to record.
- **Constitutional boundary:** Engine 6 never decides *whether* to charge — Cost (Engine 5) locks the fare, Business requests the charge, Integration executes it. No other engine ever calls a payment rail directly (TISC Article 60.2, enforced structurally in Engine 6 §1.4).

# PART III — PLATFORM ACCESS CAPTURE INFRASTRUCTURE

*[Trace: TBOC Article 60.3; TBOC Article 14]*

Platform Access is the first constitutional engagement event — never absorbed into registration or authentication. Foundation's `platform_access_event` (TRS_FDN_IDENTITY) captures channel (ANDROID/WEB/OTHER), access mode (VISITOR/RETURNING/AUTHENTICATED), intent signals, and fraud telemetry as institutional evidence, anchoring every subsequent interpretation of that engagement (the "anchor rule").

# PART IV — MESSAGING INFRASTRUCTURE

*[Trace: TBOC Article 60.4]*

- **Governed vocabulary:** Foundation's `notification_template` (TRS_FDN_SUBSTRATE) constitutes every message template, inheriting constitutional vocabulary only.
- **Execution:** Engine 6's `integration_message_dispatch_log` executes SMS, push, and WhatsApp sends against that vocabulary — this engine never invents message content.
- **In-app surface:** Engine 11's `present_notification_inbox` is the bell-icon feed a User Type sees, distinct from the external dispatch log.
- **Safety-critical messaging:** the in-app SOS capability (TBOC Article 54) is realized as `EMERGENCY_ESCALATION_REQUESTED`/`EMERGENCY_ESCALATION_ACKNOWLEDGED` (Engine 6 §4.1–4.2) — escalating to the public emergency response channel, every SOS event recorded end-to-end: trigger, response, resolution, aftercare.
- **Sender identity:** every dispatch carries an honest, branded sender identity — no message pretends to originate from anywhere but TrustRide Services.

# PART V — TAX INTEGRATION INFRASTRUCTURE

*[Trace: TBOC Article 60.5; TBOC Article 42.5]*

Every chargeable service produces a lawful electronic tax invoice as required by Kenyan law (KRA eTIMS). Engine 6's `integration_tax_invoice_submission` is the sole submission ledger, running as part of the same settlement-completion flow that produces `PAYMENT_SETTLED` — Business receives the `etims_invoice_reference` on that one signal, never through a separate request. Institutional invoice numbers (`TRS026-INV-...`) are issued exclusively by Foundation's `sequence_generator`, never invented locally by any engine.

# PART VI — IDENTITY-ACCESS & SECURITY INFRASTRUCTURE

*[Trace: TBOC Article 60.6]*

- **One identity, one account:** enforced at Foundation (`platform_users`, `auth_session`, `mfa_enrollment`) — no shell, and no downstream engine, ever creates a second identity root.
- **External verification execution:** Engine 6's `integration_verification_request` executes every National ID, Good Conduct, Guarantor, Medical, NTSA, and vendor KYC check; Foundation's `verification_record` is written only by Foundation's own accept-handler on `VERIFICATION_COMPLETED` — Engine 6 never writes it directly.
- **Secrets custody:** Engine 6's `integration_credential_reference` is the sole table on the platform permitted to hold even a *pointer* to a credential, and even that table carries no `platform_read` policy — the tightest RLS posture in the entire schema.
- **Shell isolation and role boundaries:** Engine 11's `present_shell_capability_registry`, enforced by a deferred constraint trigger, is the structural guarantee that access control is never merely a client-side convention.
- **Security events as institutional evidence:** Foundation's `security_event` (TRS_FDN_AUDIT) and `platform_security` (TRS_FDN_CORE) preserve every anomaly and policy as permanent, auditable record.

---

# ANNEX — TRACEABILITY MATRIX (TISC PART → TBOC PARENT)

| TISC Part | TBOC Parent Article |
| --- | --- |
| Part I (Live Tracking Infrastructure) | Article 60.1, Article 21 |
| Part II (Settlement & Payment Rail Infrastructure) | Article 60.2, Article 43 |
| Part III (Platform Access Capture) | Article 60.3, Article 14 |
| Part IV (Messaging Infrastructure) | Article 60.4, Article 54 |
| Part V (Tax Integration Infrastructure) | Article 60.5, Article 42.5 |
| Part VI (Identity-Access & Security Infrastructure) | Article 60.6 |

---

**END OF INSTRUMENT**

*TISC is the last mile between TrustRide's constitutional law and the outside world — one boundary, one governed inventory of every external touch, and nothing beyond what the Constitution above it already authorized.*

---

# THE FOUR-SOVEREIGN FRAMEWORK — COMPLETE

With this instrument, all four sovereign documents of TrustRide Services stand adopted: **TBOC** (supreme business law), **SAPC** (system architecture — eleven engines, 236 tables), **TEES** (technical execution standard), and **TISC** (infrastructure constitution). Every provision in every one of the four names its parent; no document invents what another already governs. TrustRide Services now has a complete, traceable, sovereign constitutional stack, ready for the next phase — engineering the platform into code.
