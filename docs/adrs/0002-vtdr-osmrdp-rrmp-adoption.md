# ADR 0002 — VTDR, OS-MRDP & RRMP Adoption

## Title

Adoption of the Vendor Technology Decision Record, Operational Security/Matching/Dispatch
Protocol, and Regulatory Relationship Management Procedure as binding law

## Status

Accepted — 2026-08-20

## Context

During the Foundation Corpus Audit engagement, the Founder annotated the delivered artifact
(`FOUNDATION CORPUS AUDIT.docx`) directly, in ALL CAPS, at four separate points, ruling on four
previously-unfiled governance documents that had existed only at
`C:\Users\ALBERT\Desktop\TrustRide_Devp_Final\claude_workspace\deliverables\` and never entered
this repository:

- **VTDR** (Vendor Technology Decision Record) — *"ADOPT THIS AS LAW, PLACE IT IN ITS
  REQUIRED SPOT."* The Founder specified the `-2.0.0-HARDENED` revision specifically (two VTDR
  drafts existed in the source folder — an earlier `VTDR.docx` and the hardened `VTDR -
  2.0.0.docx`).
- **OS-MRDP** (Operational Security, Matching & Real-Time Dispatch Protocol) — *"IMPLEMENT
  THIS AS ADOPTED AND LAW, PLACE IT AT ITS RIGHT PLACE."*
- **RRMP** (Regulatory Relationship Management Procedure) — *"IMPLEMENT AS ADOPTED AND LAW,
  PLACE TO ITS RIGHTFUL CONSTITUTION HIERARCHY OR PLACE."*
- A fourth ruling in the same document, on the **Workforce Classification Decision
  Framework**, rejected that document's Class-C independent-contractor split outright
  (*"THIS SPLIT THING REMOVE IT ENTIRELY"*) while authorizing a new Partner resource-
  contribution model in its place — already designed and implemented in code this session
  (`20260820140000_partner_resource_revenue_split.sql`, 7/7 pgTAP). That ruling is not itself
  filed as an adopted document here, since the source Workforce Classification memo was
  substantially rejected rather than adopted; the ruling's *law* is recorded in this platform's
  standing memory and in the revenue-split migration's own commit message, not as a filed
  corpus document.

None of VTDR, OS-MRDP, or RRMP conflicted with the "do not fabricate project content" rule
(`CLAUDE.md` rule 1) — they were supplied directly by the Founder, not invented.

## Decision

File all three documents into `docs/`, full text preserved, each with an "Adoption Status"
preamble recording the ruling and its date:

- **VTDR** → `10-Deployment-Architecture/TRS026-VTDR-001_v2.0.0_Vendor_Technology_Decision_
  Record.md`. Vendor/infrastructure selection is this folder's stated scope; it sits alongside
  the Build Plan it extends and is reconciled the same way ADR 0001 already reconciled the
  Build Plan against this repository's real Supabase infrastructure (§6 of the filed document
  flags the one point of divergence — AWS vs. the actual provisioned Supabase environments —
  rather than silently rewriting the source record).
- **OS-MRDP** → `11-Operations-Manual/TRS026-OSMRDP-001_v1.0.0_Operational_Security_Matching_
  Dispatch_Protocol.md`. This is a live, recurring operational protocol (matching, dispatch,
  shift limits, vetting cycles) — `11-Operations-Manual`'s stated scope, not a one-time
  architecture decision.
- **RRMP** → `11-Operations-Manual/TRS026-RRMP-001_v1.0.0_Regulatory_Relationship_Management_
  Procedure.md`. Same reasoning — a recurring procedure (regulator intake, SLA-bound
  engagement, Founder escalation), not a constitutional article.

**Flagged contradiction, not silently resolved (`CLAUDE.md` rule 2):** OS-MRDP §4.1 and §6
reference a *"dedicated, secure Investor Portal"* / *"External Operator & Investor
Transparency Portal."* This directly contradicts the Founder's separate, later, more specific
ruling in the same audit session: *"DELETE/FORGET DISCARD FROM EVERY MEMORY — WE ONLY HAVE 5
USER FACING APP AND ARE ALL DEFINED, A PARTNER IS A USER TYPE, SO THEY USE USER APP, OR USER
HUB."* Resolution: the later, more specific ruling governs. No Investor Portal or sixth
surface is authorized; every capability OS-MRDP describes for Financiers/Investors/Fleet
Owners is delivered through the User Hub under the `PARTNER` User Type. The filed OS-MRDP
document marks the two affected passages with strikethrough plus a corrective note rather than
deleting or rewriting the source text, consistent with how this platform's own financial
records handle corrections (TBOC Article 42.4 — governed reversal, never deletion).

Both OS-MRDP and RRMP are marked, in an "Implementation Status" section, as **not yet
implemented in code** — filing them as adopted law does not retroactively claim they were
built. Real, named build gaps are listed in each document (matching score, dispatch-offer
window, shift-hour cap enforcement, geofence masking, and continuous-verification cycle for
OS-MRDP; the entire Regulatory Contact Register and Founder-escalation workflow for RRMP) so
future work has a concrete, honest starting point rather than a vague "implement this" without
a scoped increment.

## Alternatives Considered

1. **Silently drop the Investor Portal language when transcribing OS-MRDP.** Rejected — this
   is exactly the "silent update" pattern RRMP itself (§3.5, the Anti-Silent-Update Rule) and
   `CLAUDE.md` rule 2 both prohibit. The contradiction is real and must be visible in the
   record, not smoothed over.
2. **File VTDR under `docs/adrs/` as a single decision record instead of the full document
   under `10-Deployment-Architecture/`.** Rejected — VTDR is a substantial, standalone
   technical specification (vendor matrix, endpoint list, security specifications), not a
   short decision narrative; ADR 0001 already established the pattern of filing full corpus
   documents in their numbered folder and recording only the *filing decision* as an ADR. This
   ADR follows that precedent rather than inventing a new one.
3. **Treat RRMP as constitutional (`01-Constitution/`) rather than operational.** Considered,
   since the Founder's own annotation says "place to its rightful constitution hierarchy" —
   read literally this could mean `01-Constitution/`. Rejected in favor of
   `11-Operations-Manual/` because RRMP's content is procedural and SLA-bound (a runbook for
   handling regulator contact), not a constitutional article defining rights, roles, or
   structure the way TBOC does; the Founder's phrasing is read as "the correct place within
   the constitution/documentation hierarchy," not as a literal folder instruction, matching how
   the Founder's other two rulings ("PLACE IT IN ITS REQUIRED SPOT" / "PLACE IT AT ITS RIGHT
   PLACE") were treated as delegating the specific folder choice to engineering judgement.
4. **Also file the Workforce Classification Decision Framework as an adopted document.**
   Rejected — that document's central proposal (Class-C independent contractors) was
   explicitly and completely rejected by the Founder, not adopted; filing it as "adopted law"
   would misrepresent the ruling. The part that *was* adopted (the 70/30 Partner
   resource-contribution model) already exists as real, tested code and is documented via its
   own migration and commit, which is the more accurate record for something that is a database
   mechanism, not a governance procedure.

## Consequences

- `10-Deployment-Architecture/` and `11-Operations-Manual/` READMEs are updated in this same
  change to index the three new documents, matching how `01-Constitution/README.md` already
  indexes TBOC.
- OS-MRDP's and RRMP's "Implementation Status" sections are now the authoritative gap list for
  future Orchestration/Coordination (matching/dispatch) and a new regulatory-contact bounded
  context (RCR) respectively — future work should update those sections as increments close,
  the same way `11-Operations-Manual/README.md`'s own Status line is kept current.
- The Investor Portal contradiction resolution recorded here is now the standing answer any
  future session should give if this question resurfaces — no need to re-litigate it.

## Related Decisions

- `docs/adrs/0001-constitutional-corpus-population.md` — establishes the "file full document
  in its numbered folder, record the filing decision as an ADR" pattern this ADR follows.
- `20260820130000_real_foundation_registration_flow.sql`,
  `20260820140000_partner_resource_revenue_split.sql` — the Partner User Type model that makes
  the Investor Portal resolution concrete (Financiers/Investors already have a real, working
  User Hub pathway, not just a policy statement).
