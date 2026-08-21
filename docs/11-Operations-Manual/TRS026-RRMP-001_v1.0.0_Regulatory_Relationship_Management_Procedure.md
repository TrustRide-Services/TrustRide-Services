# TRS026-RRMP-001 — Regulatory Relationship Management Procedure (RRMP)

## Adoption Status

**ADOPTED AS LAW — 2026-08-20**, by explicit Founder ruling on `FOUNDATION CORPUS AUDIT.docx`:
*"IMPLEMENT AS ADOPTED AND LAW, PLACE TO ITS RIGHTFUL CONSTITUTION HIERARCHY OR PLACE."* Filed
here per `11-Operations-Manual`'s scope — this is a live, recurring operational procedure
(regulator contact intake, SLA-bound engagement, Founder escalation), not a one-time
architectural or constitutional decision. No contradiction against any other adopted record
was found in this document.

Original document reference retained below verbatim for traceability.

---

Document Reference: RRMP/TRS/KSM/2026/01
Entity: TRUSTRIDE SERVICES
Operating Jurisdiction: Kisumu County & National Level, Republic of Kenya
Primary Governance Officer: Head of Legal Affairs & Regulatory Compliance
Scope: Universal (All Statutory, County, Financial, Tax, Data Protection, Transport, and Sector-Specific Regulators)

## 1. Purpose & Strategic Intent

The Regulatory Relationship Management Procedure (RRMP) establishes a formal, closed-loop
framework for managing all interactions, audits, filings, inquiries, and dispute resolution
processes between TRUSTRIDE SERVICES and key regulatory authorities.

The procedure mandates that no regulatory matter is updated silently. Any resolution,
modification, or ruling that alters operational, technical, or financial assumptions must be
flagged for systematic review and escalated to the Founders' Office whenever key decision
thresholds are triggered.

> This "no silent update" mandate is the same principle already binding on this codebase's
> own documentation hierarchy (`CLAUDE.md` rule 2: "flag any contradiction rather than
> silently resolving it") — RRMP is that principle applied to the regulatory domain
> specifically.

## 2. Governing Regulatory Regime & Authorities

This procedure covers primary statutory bodies, local county departments, and professional
advisory partners:

| Code | Authority |
|---|---|
| NTSA | National Transport and Safety Authority |
| ODPC | Office of the Data Protection Commissioner |
| KRA | Kenya Revenue Authority (eTIMS & Tax Compliance) |
| KISUMU FINANCE | Kisumu County Finance & Revenue Department (Trade Licensing) |
| IRA | Insurance Regulatory Authority (Fleet & Liability Compliance) |
| ADVISORY | External Legal Counsel, External Tax Auditors, Data Auditors |

## 3. Mandatory 6-Stage Closed-Loop Regulatory Workflow

Every regulatory touchpoint — whether a routine filing, audit inquiry, policy change, or
compliance notice — must traverse the following mandatory six-stage lifecycle:

| Stage | Name | SLA |
|---|---|---|
| 1 | Ingestion | Logged in Regulatory Contact Register (RCR) within 2 hours |
| 2 | Assignment | Formally assigned to Legal Affairs & designated Lead within 4 hours |
| 3 | Direct Engagement | Engagement via Named Official or Retained Professional, per statutory/emergency timeline |
| 4 | Outcome Log | Formal outcome & directives recorded in RCR within 12 hours of resolution |
| 5 | Assumption Shift Review | If resolved & assumptions shift → flagged for review (mandatory audit step) |
| 6 | Founder Escalation | Escalated to Founders' Office if decision triggers hit (immediate) |

### 3.1 Regulatory Contact Ingestion & Logging (SLA: within 2 hours of receipt)

All regulatory communications (letters, notices, portal alerts, physical inspections, or
summons) must be registered in the Regulatory Contact Register (RCR).

**Mandatory Fields:** Date/Time Received, Issuing Regulator (NTSA, ODPC, KRA, Kisumu Finance,
IRA, or Advisory), Issuing Official's Details, Channel, Subject Matter, Reference Number,
Statutory Deadline, and Initial Severity Rating (Low, Medium, High, Critical).

### 3.2 Assignment to Legal Affairs (SLA: within 4 hours of logging)

The Head of Legal Affairs assigns the logged item to a designated Compliance Officer or
retains external professional advisors (e.g., Senior Counsel, Tax Consultant, Certified Data
Auditor).

**Responsibility Mapping:** Single-point accountability assigned; formal response strategy
drafted; statutory deadline calendar updated.

### 3.3 Direct Engagement & Advisory Directives (SLA: per statutory or emergency timeline)

Direct contact is established with the named regulator officer or authority department.

**Protocol:** All verbal communications must be followed by written confirmation. Official
submissions must be reviewed and signed off by Legal Affairs prior to filing.

### 3.4 Outcome Recording & Final Resolution (SLA: within 12 hours of resolution)

Upon receiving a formal response, clearance, directive, or penalty from the regulator, the
full details are logged in the RCR.

**Documentation:** PDF attachments of official letters, receipts, certificates, or compliance
orders attached directly to the RCR entry.

### 3.5 Business Assumption Shift Review — Anti-Silent-Update Rule (mandatory audit step)

If the outcome changes any underlying business assumption (e.g., driver commission splits due
to tax rulings, routing parameters due to NTSA rules, data retention limits due to ODPC
orders, or county license fees), the system must flag the item for formal review.

**Strict Constraint:** Silent updates to code, financial models, or operational manuals are
explicitly prohibited. An Assumption Impact Assessment (AIA) must be conducted.

### 3.6 Founders' Office Notification & Decision Escalation (immediate trigger)

If the outcome triggers a Founder Decision Threshold, the Head of Legal Affairs must
immediately submit a Founders' Regulatory Decision Briefing (FRDB) to the Founders' Office.

## 4. Regulatory Contact Register (RCR) Data Scheme

The Regulatory Contact Register (RCR) serves as the single source of truth for compliance
tracking.

| Field Name | Type | Description / Constraint |
|---|---|---|
| RCR_ID | String (Unique) | Auto-generated ID (e.g., RCR-NTSA-2026-009) |
| REGULATOR_BODY | Enum | NTSA, ODPC, KRA, KISUMU_FINANCE, IRA, PROFESSIONAL_ADVISOR |
| NAMED_CONTACT | String | Name, Designation, and Contact Details of Issuing Official |
| DATE_RECEIVED | ISO Timestamp | Exact time notification was received |
| ASSIGNED_LEAD | String | Legal Affairs Lead or Assigned External Counsel |
| SEVERITY_LEVEL | Enum | LOW, MEDIUM, HIGH, CRITICAL |
| OUTCOME_STATUS | Enum | OPEN, IN_ENGAGEMENT, SOLVED, FLAGGED_FOR_REVIEW |
| ASSUMPTION_SHIFT | Boolean | TRUE if operational/financial parameters change; FALSE if routine |
| FOUNDER_NOTIFIED | Boolean | TRUE if escalated to Founders' Office; FALSE if standard operational |

## 5. Founders' Office Decision Escalation Matrix

Not all regulatory engagements require founder intervention. However, any outcome that
crosses defined risk, cost, or strategic thresholds mandates formal Founders' Office
escalation.

| Trigger | Threshold |
|---|---|
| Financial Impact | Penalty, tax adjustment, or fee > KES 500,000 |
| Licensing Risk | Suspension, revocation, or conditional threat to licenses |
| Business Model | Rulings forcing changes to commission rates or driver status |
| Data / Privacy | ODPC enforcement notices, audits, or breach investigations |
| Litigation | Formal court actions, injunctions, or statutory disputes |

### 5.1 Founder Escalation Protocol

When a Founder Decision Threshold is met:

1. Legal Affairs prepares a 1-page Founders' Regulatory Decision Briefing (FRDB) within 6
   hours.
2. The briefing details: Regulator Involved, Root Issue, Financial/Operational Exposure,
   Legal Options, Recommended Action, and Required Founder Approval.
3. The Founders' Office reviews and issues a formal written directive (Approved / Modified /
   Rejected) before any operational, code, or commercial changes are implemented.

## 6. Specific Regulator Interface Protocols

### 6.1 National Transport and Safety Authority (NTSA)

- **Scope:** Digital Hail & Fleet Licensing, Driver Badging, Vehicle Inspection Audits, Speed
  Telematics.
- **Lead Dept:** Legal Affairs + Transport Operations.
- **Review Trigger:** Changes to driver onboarding criteria, vehicle capacity rules, or
  digital taxi app licensing tariffs.

### 6.2 Office of the Data Protection Commissioner (ODPC)

- **Scope:** Data Controller/Processor Registration, Data Protection Impact Assessments
  (DPIA), Breach Notifications, Cross-Border Data Logs.
- **Lead Dept:** Legal Affairs + Data Protection Officer (DPO).
- **Review Trigger:** Enforcement notices, user consent framework directives, or
  modifications to geolocation telemetry retention periods.

### 6.3 Kenya Revenue Authority (KRA)

- **Scope:** eTIMS VSCU Integration, Corporate Tax, VAT, PAYE, Withholding Tax (WHT) on
  Marketplace/Fleet Contractors.
- **Lead Dept:** Finance & Tax Advisory + Legal Affairs.
- **Review Trigger:** Tax assessment notices, eTIMS protocol updates, or changes to
  marketplace agent tax withholding rates.

### 6.4 Kisumu County Finance & Revenue Department

- **Scope:** Unified Single Business Permits (SBP), Outdoor Advertising/Branding Permits,
  Trade Licenses, Market Stalls.
- **Lead Dept:** Regional Operations Lead + Legal Affairs.
- **Review Trigger:** Local county finance bill amendments, fee increases, or localized
  operational restrictions within Kisumu County boundaries.

### 6.5 Insurance Regulatory Authority (IRA) & Underwriters

- **Scope:** Commercial PSV Insurance, Passenger Liability Cover, Goods in Transit (GIT)
  Insurance for Couriers, Domestic Specialist Liability Cover.
- **Lead Dept:** Legal Affairs + Risk Manager.
- **Review Trigger:** Policy exclusions, premium adjustments > 5%, or dispute over claim
  payouts impacting operational liability.

## 7. Audit & Compliance Sign-Off

This Regulatory Relationship Management Procedure (RRMP) is a binding operational standard
for all departments within TRUSTRIDE SERVICES.

Approved by (source document, unsigned):

- Head of Legal Affairs & Regulatory Compliance
- Chief Finance Officer
- Chief Executive Officer / Founders' Office

## Implementation Status (added at adoption, 2026-08-20; updated 2026-08-20)

**Stages 1, 2, 4, 5, and 6 CLOSED, 2026-08-20** (`20260820170000_regulatory_contact_register.sql`,
11/11 pgTAP, live on `trustride-dev` and `trustride-production`). Founder ruling on placement,
2026-08-20 (mid-build correction to this section's original engine-ownership question):
"RRMP must be in Administration, more Founder/CEO level" — resolved as an Admin Console
feature, gated by `fn_am_i_administrator()`, not a new bounded context.

Real correction made while building this: `regulatory_contact_register` was not a new table to
design — it already existed as part of the original, constitutionally-adopted Foundation
schema (`20260816120100_engine001_foundation.sql`, TBOC Article 12.5), alongside a companion
`assumption_impact_assessment` table, both seeded at Foundation's original population but never
touched by a single function before this migration. This section's original "no Business,
Foundation, or Integration table today models a regulatory contact" claim was wrong — filed
here as a correction rather than silently edited away, per this document's own Anti-Silent-
Update principle (§1, §3.5).

Column mapping from RRMP's own Sec 4 illustrative names to the real, adopted schema:
`REGULATOR_BODY` → `regulator_name` (plain text, not an enum), `NAMED_CONTACT` →
`contact_name`/`contact_channel`, `ASSIGNED_LEAD` → `assigned_to`, `SEVERITY_LEVEL` →
`severity`, `OUTCOME_STATUS` → `outcome` (free text; no status-progression enum column exists),
`ASSUMPTION_SHIFT` → `assumption_shift_flag`, `FOUNDER_NOTIFIED` → `founder_notified_flag`.
`REFERENCE_NUMBER` and `STATUTORY_DEADLINE` have no column in the adopted schema — a real,
named gap, not fabricated.

The Founders' Regulatory Decision Briefing (§5.1) is implemented via
`assumption_impact_assessment`, not a separate document type: its
`affected_area`/`impact_summary`/`options`/`recommendation`/`required_directive`/`approved_by`
columns map directly onto the FRDB's own described fields (Regulator Involved, Root Issue,
Financial/Operational Exposure, Legal Options, Recommended Action, Required Founder Approval).

**Deliberately still open:** automatic escalation triggered by the §5 thresholds (KES 500,000,
licensing risk, business-model change, data/privacy enforcement, litigation) — none are
structured, machine-checkable facts this schema can safely infer; escalation stays an explicit
human judgement call by whoever holds `fn_am_i_administrator()` authority. A governed,
quorum-based approval chain for the Founder's own directive (the way
`FINANCIAL_REMEDY_AUTHORIZATION` works) was also not built — RRMP describes the FRDB as a
memo/directive, not a structured vote, so a single narrow `approved_by` completion was judged
sufficient; formalizing it further is a real, separately-scoped future gap if the Founder wants
it.

## Related Decisions

- `docs/adrs/0002-vtdr-osmrdp-rrmp-adoption.md` — the adoption decision for this record.
- `20260820170000_regulatory_contact_register.sql` — the implementing migration.
- `frontend/console/src/screens/AdminConsoleScreen.tsx` (Regulatory tab) — the Admin Console UI.
