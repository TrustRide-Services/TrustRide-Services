# TRS026-VTDR-001 — Vendor Technology Decision Record (VTDR)

## Adoption Status

**ADOPTED AS LAW — 2026-08-20**, by explicit Founder ruling on `FOUNDATION CORPUS AUDIT.docx`:
*"ADOPT THIS AS LAW, PLACE IT IN ITS REQUIRED SPOT."* The Founder's own instruction specified
this is the `-2.0.0-HARDENED` revision of the source document (`TRUSTRIDE SERVICES PLATFORM —
VENDOR TECHNOLOGY DECISION RECORD (VTDR) - 2.0.0.docx`), superseding an earlier, unhardened
`VTDR.docx` draft in the same source folder. Filed here per `10-Deployment-Architecture`'s scope
(infrastructure, vendor selection, environments) alongside the Build Plan it extends.

This is the vendor/technology baseline for every integration this platform builds against.
Where a currently-implemented integration diverges from this record (e.g. Engine 6's Daraja
integration currently implements collection/STK Push only, not yet the full B2C/B2B surface
named below), that is a build-sequencing gap against adopted law, not a contradiction of it —
track such gaps in `11-Operations-Manual/` and close them against this record, never by quietly
building to a different vendor choice.

Original document reference retained below verbatim for traceability.

---

Document Reference: VTDR/TRS/KSM/2026/02-HARDENED
Entity: TRUSTRIDE SERVICES
Operating Jurisdiction: Kisumu County, Republic of Kenya (Headquarters & Western Kenya Operations Hub)
System Scope: TrustRide Platform (Digital Twin Architecture covering On-Demand Domestic Services, Executive Mobility, Courier & Last-Mile Logistics, E-Commerce Marketplace, and TRUSTRIDE Academy Digital Portal)
Primary Authors: Lead Systems Architect, Chief Information Security Officer (CISO), & Head of Regulatory Compliance
Regulatory Framework: Kenya Data Protection Act (DPA) 2019 / ODPC Directives, Central Bank of Kenya (CBK) National Payments System (NPS) Act, Communications Authority of Kenya (CAK) Regulations, and KRA eTIMS VSCU Architecture

## 1. Architectural Scope & System Topology

The TrustRide Platform functions as the complete digital twin of TRUSTRIDE SERVICES' physical
operations in Kisumu and the broader Western Kenya region. The system services four distinct
operator classes:

- **Internal Staff (Top to Bottom):** C-Suite Executives, Regional Operations Leads, Field
  Station Managers, Customer Support Agents, and TRUSTRIDE Academy Safety Trainers.
- **Field Service Specialists:** Vetted Caregivers, Babysitters, Cleaners, and Chefs.
- **Transport & Logistics Operators:** Chauffeurs, Executive Drivers, Delivery Riders, and
  Third-Party Fleet Owners.
- **External Stakeholders & Financiers:** Marketplace Merchants, Institutional Investors,
  Asset Financiers, and Statutory Auditors.

> **Note on operator-class language:** the source document's four-class split predates the
> Founder's later, binding workforce-classification ruling (see `WORKFORCE CLASSIFICATION
> DECISION FRAMEWORK & GOVERNANCE PROCEDURE`, and the Foundation Corpus Audit annotation
> *"THIS SPLIT THING REMOVE IT ENTIRELY"*). The vendor/technology decisions below stand as
> adopted law regardless of that terminology; the operator/User-Type model of record is the
> one in `01-Constitution` and Engine 001 Foundation, not the four-class list above.

```
+---------------------------------------------------------------------------------------------------+
|                                  TRUSTRIDE DIGITAL TWIN ENTERPRISE BUS                             |
+---------------------------------------------------------------------------------------------------+
|  CLIENT & OPERATOR APPS  | Flutter Cross-Platform Mobile Apps (TLS 1.3 Pinning / Biometric Auth)   |
|  API GATEWAY / MESH      | Kong Enterprise Gateway (OAuth2 + Mutual TLS + Rate Limiting)           |
+--------------------------+------------------------------------------------------------------------+
|                                  MICROSERVICES & CORE ENGINES                                      |
|  [ Matching & Dispatch ] [ Telematics & Geofencing ] [ Ledger & Escrow ] [ Vetting & Biometrics ]  |
+--------------------------+------------------------------------------------------------------------+
|                                    THIRD-PARTY HARDENED APIS                                       |
|  PAYMENTS        | M-Pesa Daraja 2.0 (Direct C2B/B2C/B2B) + Flutterwave v3 (PCI-DSS)               |
|  LOCATION & MAPS | Google Maps Platform + ODPC Geospatial Anonymization Engine                     |
|  MESSAGING       | Africa's Talking (Primary Local/USSD) + Twilio (Voice Masking/WhatsApp)         |
|  TAX & LEGAL     | KRA eTIMS VSCU API Engine + ODPC Audit & Tokenization Engine                    |
+---------------------------------------------------------------------------------------------------+
```

## 2. Pillar 1: Enterprise Payment Gateway Hardening

### 2.1 Decision Matrix: Direct M-Pesa Daraja 2.0 + Flutterwave Enterprise Hybrid

The local payment domain in Kenya requires zero-latency processing for mobile money alongside
enterprise-grade split settlement mechanics for multi-party marketplace distributions.

```
                                    +-----------------------------------+
                                    |     TRUSTRIDE PAYMENT ROUTER      |
                                    +-----------------+-----------------+
                                                      |
                   +----------------------------------+----------------------------------+
                   |                                                                     |
+------------------v------------------+                               +------------------v------------------+
|   SAFARICOM DARAJA 2.0 (DIRECT)     |                               |      FLUTTERWAVE ENTERPRISE         |
+-------------------------------------+                               +-------------------------------------+
| - Lipa Na M-Pesa Online (STK Push)  |                               | - Card Processing (Visa/Mastercard) |
| - C2B Validation & Confirmation     |                               | - Automated Split-Escrow API        |
| - B2C Instant Driver/Rider Payouts  |                               | - Regional Mobile Money Fallback    |
| - B2B Supplier Settlement           |                               | - Multi-Currency Ledger             |
+-------------------------------------+                               +-------------------------------------+
```

### 2.2 Primary Mobile Money Engine: Safaricom M-Pesa Daraja 2.0 API (Direct Integration)

**Core Endpoints Implemented:**

- `POST /mpesa/stkpush/v1/processrequest` — Real-time Lipa Na M-Pesa Online prompt triggered
  upon service booking or retail checkout.
- `POST /mpesa/b2c/v1/paymentrequest` — Direct API disbursement from TrustRide Escrow to
  individual driver, rider, or domestic specialist wallets upon job validation.
- `POST /mpesa/b2b/v1/paymentrequest` — Automated platform fee sweep to merchant supplier
  accounts and corporate bank ledgers.

**Security & Failover Specifications:**

- **OAuth 2.0 Bearer Token Management:** Automated token rotation cached via Redis cluster
  (TTL set to 3,500s; renewal triggered at T-300s).
- **STK Password Generation:** Base64 SHA-256 hash using BusinessShortCode + Passkey +
  Timestamp (YYYYMMDDHHmmss in EAT timezone).
- **Callback Idempotency & Asynchronous Queuing:** All Daraja HTTP callbacks are immediately
  acknowledged with HTTP 200 OK and pushed to an Apache Kafka queue (`payment-callbacks-v1`)
  to prevent webhook loss or duplicate processing during peak traffic.
- **Circuit Breaker Pattern:** If Daraja API latency exceeds 3,500ms or failure rate exceeds
  5% over a 60-second window, the system automatically routes secondary payment requests
  through the Flutterwave M-Pesa proxy rail.

### 2.3 Secondary Gateway & Card Engine: Flutterwave v3 API

**Role:** Credit/Debit Card Processing (Visa, Mastercard, AMEX), Automated Multi-Party
Escrow, and Regional Card Settlement.

**Technical Integration:**

- **Split-Payment Payload Strategy:** Utilizes Flutterwave subaccounts structure. Upon
  customer payment, 85% is instantly routed to the merchant/driver sub-account, while 15%
  is retained in the TrustRide master revenue escrow.
- **Compliance Standard:** PCI-DSS Level 1 compliant tokenization; zero plain-text card data
  touches TrustRide servers.

## 3. Pillar 2: Maps, Geolocation, Routing & ODPC Compliance Hardening

### 3.1 Mapping Architecture: Google Maps Platform + ODPC Privacy Layer

For real-time dispatch, routing, and tracking across Kisumu County (covering high-density
urban estates like Milimani, Riat, Mamboleo, Nyalenda, and Polyview), precision geospatial
telematics must co-exist with statutory data protection mandates.

```
+---------------------------------------------------------------------------------------------------+
|                               GEOSPATIAL & PRIVACY ARCHITECTURE                                    |
+---------------------------------------------------------------------------------------------------+
| VEHICLE TELEMATICS / AGENT APP | MQTT Broker over TLS 1.3 (5-second location ping during active job)|
| ANONYMIZATION ENGINE           | Spatial Hashing Engine (Strips PII & truncates precision to ~100m) |
| GOOGLE MAPS PLATFORM APIS      | Directions, Distance Matrix, Places Autocomplete APIs               |
| AUDIT & STORAGE                | Transient Storage in Redis; 30-day anonymized purge in PostgreSQL   |
+---------------------------------------------------------------------------------------------------+
```

### 3.2 Implemented Google Maps APIs & Optimization Rules

- **Places API (Autocomplete & Geocoding):** Resolves informal local landmarks and address
  descriptors into spatial coordinates (lat/lng). Requests are cached at the edge for 24
  hours to reduce API call volume.
- **Distance Matrix API:** Computes precise travel time and distance for dynamic pricing
  matrices (base fare + per-KM fee + per-minute rate) for mobility and last-mile courier
  delivery.
- **Directions API & Mobile SDKs:** Implements real-time route optimization, turn-by-turn
  navigation, and dynamic re-routing based on traffic density.

### 3.3 Hardened Privacy & ODPC 2019 Compliance Layer

Pursuant to the Kenya Data Protection Act, 2019 and ODPC guidelines regarding real-time
tracking of personnel and private residential entries:

- **Dynamic Geofence Masking:** Exact residential coordinates of clients are obfuscated for
  service specialists until the job state transitions to `IN_TRANSIT` (within 500 meters of
  destination).
- **Telemetry Ephemerality:** Continuous GPS tracking is strictly constrained to active job
  states (`ACCEPTED`, `IN_TRANSIT`, `IN_PROGRESS`). Telemetry drops to zero ping frequency
  when an operator goes offline or completes a task.
- **Data Anonymization at Rest:** Historical spatial data is decoupled from User Identifiers
  (UUIDs) and encrypted using AES-256-GCM. Coordinates are retained solely for aggregated
  route optimization models.

> The 500-meter geofence-masking threshold and the active-job-state-only telemetry rule are
> reaffirmed, in near-identical language, as adopted law in `OS-MRDP` (§4) — the two records
> are consistent, not duplicative; OS-MRDP governs the live operational protocol, this record
> governs the vendor/technology choice that implements it.

## 4. Pillar 3: Hybrid Messaging & Communication Hardening

### 4.1 Hybrid Architecture: Africa's Talking + Twilio

```
                                    +-----------------------------------+
                                    |     SMART MESSAGING ROUTER        |
                                    +-----------------+-----------------+
                                                      |
                   +----------------------------------+----------------------------------+
                   |                                                                     |
+------------------v------------------+                               +------------------v------------------+
|        AFRICA'S TALKING API         |                               |          TWILIO ENTERPRISE          |
|     (Primary Local Infrastructure)  |                               |    (Voice Masking & Security)       |
+-------------------------------------+                               +-------------------------------------+
| - Bulk Transactional SMS            |                               | - Encrypted Voice Number Masking    |
| - USSD Gateway (*384*...#)          |                               | - WhatsApp Business API Messaging   |
| - Safaricom/Airtel Sender ID        |                               | - International OTP Fallback        |
+-------------------------------------+                               +-------------------------------------+
```

### 4.2 Local Engine: Africa's Talking API

- **Transactional SMS:** High-throughput dispatch notifications, order confirmation codes,
  and dispatch updates routed via direct local telco links (Safaricom, Airtel Kenya).
- **USSD Engine (`*384*TRIDE#`):** Provides offline accessibility for non-smartphone users in
  peri-urban areas to request basic courier pickups, verify service agent identities, or
  execute balance inquiries.

### 4.3 Privacy & Security Engine: Twilio API

- **Encrypted Voice & Phone Masking (Proxy Webhook):** Connects clients and operators via
  temporary proxy phone numbers. Plaintext personal phone numbers are never exposed on either
  agent or client user interfaces.
- **WhatsApp Business Cloud API:** Automated transmission of rich media invoices, interactive
  booking confirmations, and customer support ticket tracking.

## 5. Pillar 4: Taxation & Regulatory Compliance Architecture (KRA eTIMS VSCU)

Pursuant to the Tax Procedures Act and Kenya Revenue Authority regulations:

```
+---------------------------------------------------------------------------------------------------+
|                                  KRA eTIMS VSCU INTEGRATION FLOW                                   |
+---------------------------------------------------------------------------------------------------+
| 1. JOB COMPLETION   | Customer settles invoice via M-Pesa / Card Gateway                           |
| 2. PAYLOAD GEN.     | Order service constructs compliant JSON payload (itemization, VAT status)    |
| 3. VSCU ENGAGEMENT  | Platform signs payload via Mutual TLS to KRA Virtual Sales Control Unit       |
| 4. QR CODE & CU     | KRA returns Control Unit Number (CU) and eTIMS Verification QR Code URL       |
| 5. RECEIPT DELIVERY | Customer receives digital eTIMS receipt via SMS/WhatsApp with QR Code link    |
+---------------------------------------------------------------------------------------------------+
```

**Integration Method:** Virtual Sales Control Unit (VSCU) system-to-system integration,
utilizing automated asynchronous microservices.

**Withholding Tax Automation:** Automatic calculation and tax remittance logging for
marketplace vendors and fleet operations, outputting monthly KRA compliance reports.

## 6. Complete Hardened Vendor Technology Matrix

| Operational Domain | Selected Primary Vendor | Secondary / Failover | Cryptographic / SLA Benchmark | Statutory & Compliance Standard |
|---|---|---|---|---|
| Mobile Payment Engine | Safaricom M-Pesa Daraja 2.0 | Flutterwave M-Pesa Proxy | OAuth2, AES-256 HMAC; < 2s STK response time | CBK National Payments System Act; KRA eTIMS |
| Card & Multi-Currency | Flutterwave v3 | Paystack Kenya | PCI-DSS Level 1; TLS 1.3 Pinning | Anti-Money Laundering (AML) Act; Proceeds of Crime Act |
| Geospatial & Mapping | Google Maps Platform | OpenStreetMap / Leaflet Engine | HMAC Signed API Requests; < 100ms response | Kenya Data Protection Act (2019) PII Anonymization |
| Local Messaging & USSD | Africa's Talking | Infobip Kenya | Mutual TLS; 99.9% Delivery Guarantee | Communications Authority of Kenya (CAK) Standards |
| Voice Privacy & WhatsApp | Twilio API | Meta WhatsApp Cloud API | End-to-End Encrypted Voice Proxies | ODPC Telematics & Data Privacy Rules |
| Tax Invoicing Infrastructure | KRA eTIMS VSCU API | Manual KRA Portal Gateway | SHA-256 Encrypted Invoicing Signatures | Tax Procedures Act (Cap 469B); eTIMS Regulations |
| Cloud Hosting & Infrastructure | AWS (eu-west-1 Region) | Local Cloud Cache (Nairobi/Kisumu Edge) | SOC 1/2/3, ISO 27001, AWS KMS Encryption | ODPC Cross-Border Data Transfer Framework |

> **Reconciliation note:** this platform's actual provisioned infrastructure is Supabase
> (`trustride-dev` / `trustride-production`, `eu-central-1`), per the Build Plan in this same
> folder — not the AWS `eu-west-1` row above. The Build Plan's environment decision governs
> hosting; this row is retained verbatim as the source record and superseded on that one point
> only, consistent with how ADR 0001 already reconciled the Build Plan against this
> repository's real infrastructure.

## 7. Hardened Infrastructure Security & Resiliency Audit

- **Zero-Trust Network Architecture (ZTNA):** All inter-service communications within the
  platform microservices cluster are secured using Mutual TLS (mTLS) with automated
  certificate rotation every 90 days via HashiCorp Vault.
- **Data-at-Rest & Data-in-Transit Encryption:** All database volumes (PostgreSQL, Redis, S3
  objects) are encrypted using AES-256-GCM. All HTTP traffic is restricted to TLS 1.3.
- **Disaster Recovery & Business Continuity (DR/BCP):**
  - Recovery Point Objective (RPO): < 5 seconds (Real-time DB replication).
  - Recovery Time Objective (RTO): < 60 seconds (Automated DNS failover to standby
    infrastructure).
- **Vulnerability Management & Penetration Testing:** Mandatory quarterly third-party
  penetration testing and daily automated static/dynamic code analysis (SAST/DAST)
  integrated into the CI/CD pipeline.

## 8. Executive Approval & Record Sign-Off

This Vendor Technology Decision Record (VTDR) constitutes the architectural mandate for the
engineering, security, and operations divisions of TRUSTRIDE SERVICES. Any modification to
this technology baseline requires formal review by the Architecture Review Board (ARB) and
executive re-certification.

Approved by (source document, unsigned):

- Chief Technology Officer / Lead Architect
- Chief Information Security Officer (CISO)
- Head of Legal & Regulatory Compliance
- Chief Executive Officer

## Related Decisions

- `docs/adrs/0002-vtdr-osmrdp-rrmp-adoption.md` — the adoption decision for this record.
- `10-Deployment-Architecture/TRS026-BUILD-PLAN-001_Coding_to_Deployment` — the environment
  and infrastructure record this document is reconciled against (§6 note).
- `11-Operations-Manual/TRS026-OSMRDP-001_v1.0.0_Operational_Security_Matching_Dispatch_Protocol.md`
  — the operational protocol implementing this record's geospatial/privacy vendor choices.
