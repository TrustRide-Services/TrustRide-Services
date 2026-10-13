#!/bin/bash
# Two truly parallel registration retries for one identity (Founder direction WP9 item 1).
# LOCAL DATABASE ONLY: commits a throwaway identity in the local stack (never run against staging).
# Expectation: one retry opens a verification; the other waits on the identity's row lock and is refused
# ("already in progress"); exactly one verification is pending and no attempt is counted twice.
set -u
C=${TRS_LOCAL_CONTAINER:-supabase_db_TrustRide-Services}
PSQL() { MSYS_NO_PATHCONV=1 docker exec -i "$C" psql -U postgres -d postgres -X -q -v ON_ERROR_STOP=1 "$@"; }
U=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || python -c "import uuid;print(uuid.uuid4())")
N=$(( RANDOM % 9000 + 1000 ))
AS="SELECT set_config('request.jwt.claims', json_build_object('sub', '$U', 'role', 'authenticated')::text, true), set_config('request.jwt.claim.sub', '$U', true); SET LOCAL ROLE authenticated;"

# 1. a registration whose first check failed (simulator: 00 prefix is INVALID)
PSQL <<SQL >/dev/null
INSERT INTO auth.users (id, email, aud, role) VALUES ('$U', 'race-$N@test.trustride.ke', 'authenticated', 'authenticated');
BEGIN; $AS SELECT trustride.fn_registration_capture_primary('Race Test Person', '0077$N', TRUE); COMMIT;
DO \$\$ BEGIN FOR i IN 1..4 LOOP PERFORM trustride.fn_orch_dispatch_cycle(); END LOOP; END \$\$;
SQL
echo "status before: $(PSQL -Atc "SELECT status FROM trustride.platform_users WHERE user_id = '$U'")"

# 2. two retries at the same moment; the first holds its transaction open for 3 seconds
( PSQL -Atc "BEGIN; $AS SELECT 'A:' || trustride.fn_registration_retry_primary('Race Test Person', '0078$N'); SELECT pg_sleep(3); COMMIT;" 2>&1 | grep -E "A:|ERROR" | sed 's/^/  session A /' ) &
sleep 0.5
( PSQL -Atc "BEGIN; $AS SELECT 'B:' || trustride.fn_registration_retry_primary('Race Test Person', '0079$N'); COMMIT;" 2>&1 | grep -E "B:|ERROR" | sed 's/^/  session B /' ) &
wait

# 3. the outcome
PENDING=$(PSQL -Atc "SELECT count(*) FROM trustride.verification_record WHERE subject_user_id = '$U' AND outcome = 'PENDING'")
TOTAL=$(PSQL -Atc "SELECT count(*) FROM trustride.verification_record WHERE subject_user_id = '$U'")
echo "pending verifications: $PENDING (expected 1); verification records: $TOTAL (expected 2)"
PSQL -c "DO \$\$ BEGIN FOR i IN 1..4 LOOP PERFORM trustride.fn_orch_dispatch_cycle(); END LOOP; END \$\$;" >/dev/null
COUNTED=$(PSQL -Atc "SELECT trustride.fn_registration_incorrect_attempts('$U')")
echo "incorrect attempts counted: $COUNTED (expected 2)"
[ "$PENDING" = "1" ] && [ "$TOTAL" = "2" ] && [ "$COUNTED" = "2" ] && echo "RESULT: PASS" || { echo "RESULT: FAIL"; exit 1; }
