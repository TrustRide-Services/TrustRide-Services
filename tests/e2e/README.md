# TrustRide browser journeys and integrated proof

Real-browser journeys (Playwright) that drive the real screens as each actor, against a
**full local Supabase stack** built from `supabase/migrations`. They complement the
rollback-only SQL suites in `supabase/tests`, which never reach COMMIT.

## Run
1. `supabase start -x studio,logflare,vector,imgproxy,storage-api,realtime,edge-runtime,postgres-meta,supavisor,mailpit`
   (from the repo root; default ports 54321/54322).
2. `supabase status -o env | grep -E "^(API_URL|ANON_KEY|SERVICE_ROLE_KEY|DB_URL)=" > tests/e2e/local.env` (never commit it).
3. Night runs only: open the working windows on the LOCAL database —
   `UPDATE trustride.platform_configuration SET config_value='00:00-23:59' WHERE config_key IN ('WORKING_WINDOW_WEEKDAY','WORKING_WINDOW_SATURDAY','WORKING_WINDOW_SUNDAY','EA_DAY_SHIFT_WINDOW');`
4. Build the frontend against the local stack (`NEXT_PUBLIC_SUPABASE_URL=$API_URL NEXT_PUBLIC_SUPABASE_ANON_KEY=$ANON_KEY npm run build` in `frontend/web`), then `npx next start -p 3000`.
5. `cd tests/e2e && npm install && npx playwright install chromium`.
6. In Git Bash set `MSYS_NO_PATHCONV=1`.

## Order
`j1_register` → `j2_governance` → `j3_transport` → `j4_rest` → `j5_followup` → `j6_entity` →
`j7_partner_intermediary_security` → `j8_staff_roles` → `j9_governor_revoke` →
`j10_company_ride_and_support` → `j11_company_pay` → `j12_company_support`.

Integrated proof (Founder's Final Integrated Proof Mandate): `p0_setup.js`, then `proof.js <run-name>`
(writes `proof-<run-name>.json`). Last result: 44/44 PASS on TRS026-ORDER-000000023.

## Reports
`report/build_completion.js <out-dir> <content.js>` writes md/html/docx; `pdf.js <html> <pdf> <png>` prints the PDF.
`report/proof_content.js` reads `proof-final.json`.
