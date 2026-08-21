# TRS026-OSMRDP-001 — Operational Security, Matching & Real-Time Dispatch Protocol (OS-MRDP)

## Adoption Status

**ADOPTED AS LAW — 2026-08-20**, by explicit Founder ruling on `FOUNDATION CORPUS AUDIT.docx`:
*"IMPLEMENT THIS AS ADOPTED AND LAW, PLACE IT AT ITS RIGHT PLACE."* Filed here per
`11-Operations-Manual`'s scope (this is a live, ongoing operational protocol — matching,
dispatch, vetting cycles, shift limits — not a one-time architectural decision).

**Flagged contradiction, resolved per the more recent and more specific ruling (documentation
hierarchy rule 2, `CLAUDE.md`):** §4.1 and §6 of the source document below reference a
*"dedicated, secure Investor Portal"* and an *"External Operator & Investor Transparency
Portal"*. This directly contradicts the Founder's later, explicit ruling in the same
Foundation Corpus Audit session: *"DELETE/FORGET DISCARD FROM EVERY MEMORY — WE ONLY HAVE 5
USER FACING APP AND ARE ALL DEFINED, A PARTNER IS A USER TYPE, SO THEY USE USER APP, OR USER
HUB."* That ruling is later, more specific to the surface-count question, and directly on
point — it governs. **No Investor Portal, and no sixth shell/surface of any kind, may be
built.** Financiers, Institutional Investors, and Fleet/Asset Owners are the `PARTNER` User
Type and access every capability named in §4.1/§6 (live telematics, earnings tracking,
aggregated performance metrics, financial dashboards) through the existing User Hub, exactly
as the Partner resource-contribution flow already does
(`fn_my_partner_resources`/`fn_my_partner_revenue_splits`, `20260820140000_partner_resource_
revenue_split.sql`). The source text is preserved verbatim below for traceability, not edited,
per the same "governed reversal, never deletion" discipline used throughout this platform's
own financial records (TBOC Article 42.4).

Everything else in this record — the matching algorithm, dispatch cascade, schedule
governance, telemetry/privacy safeguards, and vetting cycle — is adopted as-is and is a real
build gap against Orchestration (Engine 7) and Coordination (Engine 8), tracked below.

Original document reference retained below verbatim for traceability.

---

Company Name: TRUSTRIDE SERVICES
Registration Jurisdiction: Kisumu County, Republic of Kenya
Postal Address: P.O. Box 449-40100, Kisumu
Official Email: trustride.ke@gmail.com
Document Ref: OS-MRDP/TRS/KSM/2026/01
Scope: Internal Operators (Executive, Administrative, Academy, Field Operations) & External Operators (Field Specialists, Drivers, Riders, Merchants, Investors, Financiers)

## 1. Universal Scope & Operational Principle

The real-time matching, scheduling, verification, and tracking protocols built into the
TrustRide Platform apply uniformly across all Internal Operators (from C-Suite Executives
down to Field Operations Staff) and External Operators (Caregivers, Chefs, Babysitters,
Cleaners, Personal Drivers, Delivery Riders, Merchants, Financiers, and Institutional
Investors).

> As above: every operator/actor class named here is a `PARTNER`, `OPERATOR`, or internal
> staff **User Type** in the adopted Foundation model — never a separate app or portal.

## 2. Real-Time Matching & Algorithmic Dispatch Engine

The TrustRide Engine utilizes multi-factor matching logic to pair service requests with
qualified operators, optimizing for safety, skill accreditation, geographic proximity, and
schedule availability.

```
+-----------------------------------------------------------------------------------+
|                      MULTI-FACTOR MATCHING WORKFLOW                               |
+-----------------------------------------------------------------------------------+
| 1. REQUEST INITIATION | Client selects service, location, time, and preferences   |
| 2. GEO-FENCE FILTER   | Engine identifies active operators within optimal radius  |
| 3. VETTING & ACCRED.  | System verifies DCI Clearance, Academy Certs & Medicals   |
| 4. ALGORITHMIC SCORE  | Distance (40%) + Rating (30%) + Acceptance Rate (30%)     |
| 5. DISPATCH OFFER     | Cascading offer sent to top-ranked operator (30s window)  |
| 6. TASK ENGAGEMENT    | Real-time session initialized upon acceptance             |
+-----------------------------------------------------------------------------------+
```

### 2.1 Domain-Specific Dispatch Rules

**Domestic & Care Services (Caregivers, Babysitters, Cleaners, Chefs):**

- Match Criteria: Specialized certification (TRUSTRIDE Academy accreditation), language
  preference, past performance ratings, and biometric verification.
- Lead Time: Supports both instant emergency dispatch and scheduled recurring bookings.

**Personal Drivers & Courier Riders:**

- Match Criteria: Real-time GPS proximity, NTSA license endorsement class, vehicle
  inspection status, and speed compliance history.

## 3. Schedule Governance & Capacity Management

To guarantee service reliability while maintaining statutory compliance with working hours
under the Employment Act (Cap 226) and NTSA Fatigue Guidelines, the platform automates
schedule enforcement:

**Shift Rostering & Capacity Limits:**

- Domestic Field Operators: Capped at a maximum of 8 operational hours per day to prevent
  exhaustion in intensive roles (e.g., elder care or deep cleaning).
- Drivers & Riders: Platform enforces a mandatory 30-minute rest lockout after 4 hours of
  continuous driving. Maximum daily drive limit is strictly capped at 8 hours.

**Calendar Synchronization & Availability Management:**

- Operators manage availability via the TrustRide Operator App.
- Unscheduled drop-outs or no-shows trigger automated reassignment algorithms to ensure
  unbroken client coverage.

## 4. Real-Time Telemetry, Tracking & Privacy Safeguards

The tracking engine balances operational transparency with privacy compliance under the Data
Protection Act (DPA), 2019.

```
+-----------------------------------------------------------------------------------+
|                       TRACKING & PRIVACY SAFEGUARD MATRIX                         |
+-----------------------------------------------------------------------------------+
| ACTIVE SESSION ONLY   | GPS/Biometric tracking initiates upon job start and ends  |
|                       | immediately upon completion.                              |
| ANONYMIZED PIPELINE   | Live coordinates streamed via WebSockets without PII      |
|                       | exposure to third-party endpoints.                        |
| EMERGENCY OVERRIDE    | In-app SOS button broadcasts live coordinates to          |
|                       | TRUSTRIDE Security Ops & Kisumu Police Central Command.   |
+-----------------------------------------------------------------------------------+
```

### 4.1 Tiered Operational Visibility

- **Clients:** View active ETA, live transit routes (drivers/riders), and check-in/check-out
  timestamps (domestic staff).
- **Internal Operations & Station Managers:** Access real-time operational dashboards
  tracking fleet density across Kisumu County, job fulfillment rates, and safety alerts.
- **Financiers & Investors:** Receive aggregated, anonymized performance metrics (e.g., total
  completed trips, platform fulfillment velocity, SLA adherence rates) ~~via a dedicated,
  secure Investor Portal~~ **via the User Hub, as the `PARTNER` User Type** — see Adoption
  Status above.

## 5. Dual-Layer Security Vetting & Continuous Verification

Before an operator (internal staff, field specialist, driver, or rider) is activated on the
platform dispatch bus, they must undergo two-factor verification:

```
+-----------------------------------------------------------------------------------+
|                         CONTINUOUS VERIFICATION CYCLE                             |
+-----------------------------------------------------------------------------------+
| LEVEL 1: ONBOARDING   | DCI Certificate of Good Conduct, Chief's Letter, Medical  |
| LEVEL 2: DAILY CHECKS | Biometric selfie verification before logging onto shift   |
| LEVEL 3: AUDITS       | Random supervisor spot-checks & client review monitoring  |
| LEVEL 4: RENEWALS     | Annual re-vetting of criminal records and driving badges  |
+-----------------------------------------------------------------------------------+
```

## 6. External Operator & Investor Transparency ~~Portal~~ Access (via User Hub)

External partners, fleet investors, and financial backers are integrated directly into the
digital twin ecosystem through structured data access layers — **all as the `PARTNER` User
Type, through the existing User Hub, never a separate portal** (see Adoption Status above):

**Fleet & Asset Owners:**

- Live telematics, earnings tracking, fuel efficiency metrics, and automated service
  maintenance alerts for owned vehicles leased or operated on the platform.

**Financiers & Institutional Investors:**

- Access to read-only financial dashboards displaying real-time platform GMV (Gross
  Merchandise Value), commission splits, tax remittance status, and operational unit
  economics.

**Marketplace Merchants:**

- Automated inventory synchronization, real-time dispatch assignment for sold goods, and
  automated daily payout settlements via M-Pesa B2C or bank transfer.

## 7. Dispatch & Safety Governance Sign-Off

This Operational Security, Matching & Real-Time Dispatch Protocol forms an integral
operational standard for TRUSTRIDE SERVICES.

Approved by (source document, unsigned):

- Chief Operations Officer
- Head of Safety & Security
- Chief Executive Officer

## Implementation Status (added at adoption, 2026-08-20)

Not yet implemented in code as of adoption. Real, tracked build gaps against this record:

- **§2 matching score (40% distance / 30% rating / 30% acceptance rate) — CLOSED, 2026-08-20**
  (`20260820160000_dispatch_matching_score_cascade.sql`, corrected same-day in
  `20260820161000`). Built in Resources (Engine 2, not Orchestration — `fn_resource_inbox_
  process`'s `ORDER_PLACED` branch is where candidate selection actually lived): distance
  uses the workforce unit's home estate against the order's origin zone (no live operator GPS
  exists anywhere in the schema yet — that upgrade is its own future increment, not faked
  here); rating computed live from `business_review`; acceptance rate tracked in a new
  `resource_operator_acceptance_stat` table. Capacity-class filtering (BODA_BODA vs. TUKTUK
  vs. …) is also new — the pre-existing selection had none. 13/13 pgTAP assertions
  (`backend/tests/sql/015_dispatch_matching_score.sql`), verified live on `trustride-dev` and
  `trustride-production`.
- **§2 30-second cascading dispatch-offer window — CLOSED, 2026-08-20** (same migration).
  `resource_dispatch_cascade`/`resource_dispatch_candidate` step through ranked candidates one
  at a time; decline or timeout (reaped every 10s via the existing `fn_orch_run_cycle` cron
  tick) advances to the next candidate; `ASSIGNMENT_CONFIRMED` is now emitted only on real
  operator acceptance (`fn_dispatch_offer_accept`), never synchronously. Operator-facing
  `ACCEPT_JOB_OFFER`/`DECLINE_JOB_OFFER` wired through Presentation on `OPERATOR_APP`;
  `OperatorScreen.tsx` shows a live incoming-offer banner with a countdown.
- **§3 8-hour daily cap / 30-minute rest after 4 hours** — no shift-hour tracking exists
  anywhere in the schema yet; this requires a new table (working-hours ledger per operator,
  keyed off `resource_workforce_unit`) before it can be enforced, not just a function.
- **§4 500-meter geofence masking** — no geofence-masking logic exists yet in any Cost/
  Resources function; real-time coordinate handling in the schema today is limited to what
  the Presentation layer's live-tracking screens already read directly from job state, with
  no anonymization/truncation step.
- **§5 continuous verification cycle** — Foundation already has the identity/vetting tables
  this could be built on (`03-Core-Domain-Model/`), but no scheduled re-vetting job or daily
  biometric-check gate exists yet.

None of the above may be silently approximated; each is a distinct, separately-scoped
increment against Orchestration/Coordination/Resources, to be planned and verified with the
same rigor as every other engine increment this session (propose → build → pgTAP-verify →
deploy `trustride-dev` → regress → commit).

## Related Decisions

- `docs/adrs/0002-vtdr-osmrdp-rrmp-adoption.md` — the adoption decision for this record,
  including the Investor Portal contradiction and its resolution.
- `10-Deployment-Architecture/TRS026-VTDR-001_v2.0.0_Vendor_Technology_Decision_Record.md`
  — §3.3's geofence/telemetry vendor choice, which this record's §4 governs operationally.
- `04-Platform-Engine-Registry/engine-07-orchestration/`, `engine-08-coordination/` — where
  the matching/dispatch build gaps above belong.
