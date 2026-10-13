# Lifecycle coverage matrix (WP9)

As of 2026-10-13, staging (`fdkzewkogkujtwvonesn`), migrations through `20261013000065`. Each cell cites the
automated evidence behind it; nothing is marked covered because code exists.

**Classifications**

| Classification | Meaning |
|---|---|
| **Proven** | An automated test drives the stage and asserts its outcome (SQL suite on staging, or a browser journey). |
| **Proven by design refusal** | The stage is deliberately refused pending a decision, and the refusal is proven. |
| **Not applicable** | The stage does not exist for that service type. |
| **Gap** | Not proven; stated with the reason. |

The seven stages are the constitutional stages of TBOC Art.19:
1. Placement and Scope.
2. Assignment Validation and Job Creation.
3. Dispatch.
4. Execution and Completion.
5. Payment and Settlement.
6. Review, Rate and Support.
7. Resource Availability.

## 1. Service types × stages

Source: suite `44_lifecycle_coverage` (124/124 on staging). Every ACTIVE dispatched catalogue service is driven
with a resource of the class, certificates and vetting tier its eligibility rule requires.

| Service | Resource class | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| TRANSPORT-BODA-STANDARD | Boda boda | Proven | Proven | Proven | Proven | Proven | Proven | Proven |
| TRANSPORT-TUKTUK-STANDARD | Tuk-tuk | Proven | Proven | Proven | Proven | Proven | Proven | Proven |
| TRANSPORT-SEDAN-STANDARD | Sedan | Proven | Proven | Proven | Proven | Proven | Proven | Proven |
| COURIER-DOCUMENT | Boda boda | Proven | Proven | Proven | Proven | Proven | Proven | Proven |
| COURIER-PARCEL | Boda boda | Proven | Proven | Proven | Proven | Proven | Proven | Proven |
| DELIVERY-GOODS-TOWN | Pickup | Proven | Proven | Proven | Proven | Proven | Proven | Proven |
| DELIVERY-CARGO-BULK | Cargo van | Proven | Proven | Proven | Proven | Proven | Proven | Proven |
| EA-ERRANDS-GENERAL | Assistant (errands) | Proven | Proven | Proven | Proven | Proven | Proven | Proven |
| EA-SHOPPING-GENERAL | Assistant (shopping) | Proven | Proven | Proven | Proven | Proven | Proven | Proven |
| EA-CLEANING-GENERAL | Assistant (cleaning) | Proven | Proven | Proven | Proven | Proven | Proven | Proven |
| EA-CHEF-GENERAL | Assistant (chef) | Proven | Proven | Proven | Proven | Proven | Proven | Proven |
| EA-DRIVING-GENERAL | Assistant (driving) | Proven | Proven | Proven | Proven | Proven | Proven | Proven |
| EA-DRIVING-STUDENT_PICKUP | Assistant, ENHANCED vetting + child safeguarding | Proven | Proven | Proven | Proven | Proven | Proven | Proven |
| EA-CAREGIVING-GENERAL | Assistant, ENHANCED + caregiving + first aid | Proven | Proven by design refusal | — | — | — | — | — |
| EA-ERRANDS-SCHOOL_VISITATION | Assistant, ENHANCED + child safeguarding | Proven | Proven by design refusal | — | — | — | — | — |
| EA-SHOPPING-REPRESENTATION_DELIVERY | Assistant (corporate representative) | Proven | Proven by design refusal | — | — | — | — | — |

**How each stage is proven.**

| Stage | What the suite asserts |
|---|---|
| 1 | The order is placed with its order lines. |
| 2 | A qualified resource is reserved, a price is quoted, and accepting it creates the job. |
| 3 | The job is acknowledged and dispatched. |
| 4 | The job completes. |
| 5 | Settlement equals the accepted quote, and a receipt is issued. |
| 6 | A review and a support case are accepted on the order. |
| 7 | The resource is released and AVAILABLE. |

**Why three services stop at stage 2.** Their Executive Assistant skill (caregiver, corporate representative) is
mapped to a gazetted occupation only provisionally (`NEAREST_OCCUPATION_PENDING_FOUNDER`). The order is refused at
pricing rather than priced on an uncertain basis (WP3, suite 26). Their stages 3–7 run the same code as the
proven services, but are **unproven for these services** until the Founder decides the occupation mapping.

**Special intents** (not dispatched; their own fixed flows):

| Intent | Evidence | Classification |
|---|---|---|
| Marketplace listing, reservation and purchase | Suites 04 and 06; j4 (Journey E: a purchase never enters driver dispatch) | Proven |
| Academy enrolment | Suite 04 (an Academy order is sent to its own intake; enrolment becomes a governed Office request) | Proven (intake stage only; no dispatch by design) |
| Employment application | Suite 04 (becomes an Operator access request); suite 03 (employment engagement opened) | Proven (intake stage only) |
| Vendor onboarding, resource contribution | Suites 06 and 09; j7 | Proven (request and decision) |

## 2. Actor types

| Actor (TBOC Art.12) | Evidence | Classification |
|---|---|---|
| Customer | Suites 04, 05, 44; j3, j4, j17, j18 | Proven |
| Customer acting for an organisation | Suite 02; j6, j10–j12 | Proven |
| Partner | Suites 06, 09; j7 | Proven |
| Operator (employee) | Suites 03, 04, 44 (progress through Operator App); j3, j8 | Proven |
| Intermediary | Suites 06, 09; j7 | Proven |
| Governor | Suites 06, 09, 10; j2, j9 (scope grant and revocation) | Proven |
| Office: Founder, Administrator, Executive | Suites 13, 37, 38, 39, 41; j8, j15, j17 | Proven |

## 3. Engines and cross-cutting guarantees

| Guarantee | Evidence | Classification |
|---|---|---|
| Engines 7/8 route and coordinate every cross-engine signal; fan-out/fan-in; consensus | Suites 27, 20, 08; WP4 interaction inventory | Proven |
| Engine 6 is the only external boundary; no simulated answer presented as live | Suites 21, 28–34, 43; Node adapter tests 50/50 | Proven |
| Authorization at the database (sessions, commands, direct calls) | Suites 01, 13, 14, 41 (verified-identity gate), 37 (D26) | Proven |
| Identity: one identity per national ID, safe retry, three-attempt limit | Suites 35, 40; parallel-retry race (two connections) | Proven |
| Resource lifecycle (reserve, assign, release, maintenance, telemetry) | Suites 03, 11, 23, 44, 07, 43 | Proven |
| Idempotency (duplicate signals, commands, callbacks, answers) | Suites 02, 05, 08, 20, 24, 27, 29, 31, 41, 43 | Proven |
| Retries and timeouts | Suites 02 (notification retry), 29 (identity), 31 (money: no automatic re-send), 27 (fan-in timeout), 43 (telemetry outage) | Proven |
| Terminal failure states (dead letter, expiry, cancellation, decline) | Suites 04, 06, 20, 27 | Proven |
| Audit (hash chains, completeness, seals) | Suites 16, 19, 25; WP2 external-seal end-to-end | Proven (S3 Object Lock not activated) |
| Financial consistency (prompt = quote = settlement; ceil rounding; callbacks) | Suites 05, 15, 26, 44 | Proven |
| Recovery from partial failure | Suites 31 (unknown M-Pesa outcome → Office verification), 27 (fan-in timeout → dead letter), 43 (telemetry outage → STALE → LIVE), 29 (provider outage → resend allowed) | Proven |

## 4. Integration workflows (Engine 6)

| Integration | Simulator path | Live path |
|---|---|---|
| Daraja (STK, B2C) | Proven (05, 15, 31) | Adapter proven against mocks; credentials absent (level 6) |
| Africa's Talking SMS, WhatsApp, Google email | Proven (02, 31, 34) | Adapters proven against mocks (level 6) |
| MetaMap identity / business | Proven (02, 29, 35, 40) | Adapter proven against mocks; switch locked pending the onboarding-rule decision (level 6) |
| Protrack telemetry | **Proven (43), new in WP9** | Adapter proven against mocks; credentials absent; HTTPS unconfirmed (level 6) |
| NTSA, eTIMS, EPRA | Proven (28, 30, 32) | No live path (NTSA access; tax determination; EPRA has no API) (level 5) |
| Routing | Proven (28) | Provider not chosen (level 1) |

## 5. Remaining gaps

1. Stages 3–7 for the caregiver and corporate-representative services await the Founder's occupation decision.
2. Executive scenarios PEAK_DEMAND, FLEET_EXPANSION and ZONE_IMPACT cannot run. See
   [ENGINE_10_SCENARIO_DATA_REQUIREMENTS.md](ENGINE_10_SCENARIO_DATA_REQUIREMENTS.md).
3. Live provider transactions: none anywhere (no credentials). This is a production gate.
4. Payment stage 5 is proven on the simulator and through Daraja callbacks; no real M-Pesa money has moved.
