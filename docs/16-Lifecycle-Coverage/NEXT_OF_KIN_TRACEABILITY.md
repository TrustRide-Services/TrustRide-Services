# Next of kin: Foundation traceability (WP9, item 2)

## Findings

**1. Foundation rule.** The Founder ruling of 2026-08-23 (Registration & Authentication Flow, Step 3.3 secondary
data) includes next of kin. The ruling's own text is not in the repository. It is recorded in the Foundation
migration `20260823000002_engine001_foundation.sql` (header item 9, and the Step 3.3 comments and code).
TBOC and FDN-001 do not use the phrase "next of kin".

**2. Authoritative model.** FDN-001 record 034, *Relationships & Networks*, defines "governed relationships between
Users (guardian↔student, household, EA↔client)". The table is `user_relationship`:
- `user_id` and `related_user_id` are both foreign keys to `platform_users`;
- the other columns are `relationship_type`, `guardian_authorization_ref`, `valid_from`, `valid_to`;
- constitutional basis: TBOC Art.11, 13.

**3. Schema before WP9.** The table, its foreign keys and a self/related-only read policy existed and matched
FDN-001. There were no functions, no screens and 0 rows, on staging and locally.

**4. Divergence.** Step 3.3 was implemented as a free-text `user_note` ("Next of kin: name (relationship),
contact: …"), not as a relationship. The original comment gives the reason: the related person "may not exist as
a platform_users row".
- WP8 (migration 056) closed that free-text path.
- Staging held 0 such notes, so no data was lost.

**5. Workflows needed.** The principal names a next of kin. The named person may decline. The Office may contact
the next of kin when the principal is unreachable during an open matter (support case or order in progress).

**6. Authority, privacy and audit.**
- Foundation's identity data is not blanket-readable (Foundation migration, correction 8).
- Being named grants nothing: no reads and no sessions.
- The Office reveal is role-checked, needs a reason and an open matter, and is audited. Audits never contain
  contact details.

**7. Foundation gap.** FDN-001 034 can represent a next of kin **only if the kin is a registered TrustRide
identity**. A next of kin outside TrustRide has no place in the model, which is the reason the original note was
used. Implemented: kin must be a verified identity. Founder decision needed for non-members (below).

## Traceability

| Rule | Table and fields | Constraints and permissions | Workflow | Operational use | Tests |
|---|---|---|---|---|---|
| Ruling 2026-08-23 Step 3.3; FDN-001 034 | `user_relationship` (`relationship_type = 'NEXT_OF_KIN'`, `user_id` = principal, `related_user_id` = kin, `valid_from`/`valid_to`) | FK to `platform_users` (existing); `user_relationship_not_self` CHECK; `user_relationship_one_active_next_of_kin` unique (one active); read policy self/related only (existing) | `fn_next_of_kin_nominate(phone, full_name)`: kin must be a verified (ACTIVE) person with that verified phone and name; same person again = no change; a different person closes the previous one | — | Suite 42; j18 |
| Privacy (FDN-001 correction 8; DPA) | — | One refusal message for any mismatch (no phone probing); no contact data in audit | Kin is notified and can decline (`fn_next_of_kin_decline`); principal can remove (`fn_next_of_kin_end`); `fn_my_next_of_kin` shows the principal's nominee and who named the user | — | Suite 42 (probing, decline, end, notifications); j18 |
| No implied authority | — | Kin gets no reads of the principal's profile, contacts, orders or address; no session as the principal | — | — | Suite 42 ("named person cannot read / act") |
| Operational fallback | `audit_log` `NEXT_OF_KIN_CONTACT_REVEALED` (reason, reference; no phone) | `fn_office_next_of_kin_reveal` (Founder/Administrator only; reason of 10+ characters; an open support case of the principal or an order in progress) | Office support screen, "Next of kin" button per open case | Contact the kin when the principal is unreachable | Suite 42 (role, reason, matter, audit); j18 (Office sees name and verified phone) |
| Audit | `audit_log`: `NEXT_OF_KIN_NOMINATED` / `_ENDED` / `_DECLINED` / `_CONTACT_REVEALED` | Hash-chained (existing) | — | — | Suite 42 |

**Migrations:**
- `20261013000062_engine001_next_of_kin.sql`: Foundation functions and constraints.
- `20261013000063_engine011_support_requester_reference.sql`: the support screen gets the requester reference.

**Screens:**
- Profile → "Next of kin": name, remove; decline when named.
- Office → Support → "Next of kin" per open case.

## Decision needed: next of kin outside TrustRide

| Option | Effect | Trade-off |
|---|---|---|
| A (implemented) | The next of kin must hold a verified TrustRide identity | Fully within FDN-001. Some people's natural next of kin will not register. |
| B | A Foundation amendment adding a governed, consent-noticed record of a non-member's name and phone, attached to the principal (not a platform identity) | Covers everyone. TrustRide then holds third-party personal data without that person's account; needs a DPA notice and a retention rule. |

**Recommendation:** keep A as the rule, and decide B explicitly if operations show a need. B is a constitutional
data-model change and should not be introduced quietly.
