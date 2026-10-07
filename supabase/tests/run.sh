#!/bin/bash
# TrustRide rollback-only test runner.
#   ./run.sh local  [suite.sql ...]   -> local mirror container (trs_local17)
#   ./run.sh linked [suite.sql ...]   -> the linked Supabase project (staging)
# Each suite runs in its own transaction and ends in a forced rollback that
# carries its results; nothing persists. Exit code = number of failed checks.
cd "$(dirname "$0")"
TARGET=${1:-local}; shift
SUITES=${@:-$(ls [0-9]*.sql)}
FAILED=0
for s in $SUITES; do
  name=$(basename "$s" .sql)
  tmp=$(mktemp --suffix=.sql)
  {
    echo "SELECT set_config('trs.suite', '$name', false);"
    cat _helpers.sql
    cat "$s"
    cat <<'TAIL'
DO $tail$
DECLARE s TEXT;
BEGIN
  PERFORM pg_temp.t_admin();
  SELECT string_agg(CASE WHEN ok THEN 'PASS ' ELSE 'FAIL ' END || name || coalesce(' -- ' || detail, ''), E'\n' ORDER BY seq) INTO s FROM t_result;
  RAISE EXCEPTION 'TRS-TEST-RESULTS%', E'\n' || coalesce(s, 'NO CHECKS RECORDED');
END
$tail$;
TAIL
  } > "$tmp"
  if [ "$TARGET" = "local" ]; then
    out=$(MSYS_NO_PATHCONV=1 docker exec -i "${TRS_LOCAL_CONTAINER:-trs_local17}" psql -U supabase_admin -d postgres -X -q -1 < "$tmp" 2>&1)
  else
    out=$(cd ../.. && supabase db query --linked -f "$tmp" 2>&1)
  fi
  rm -f "$tmp"
  # The linked CLI returns the exception text JSON-escaped (literal \\n); decode first.
  res=$(echo "$out" | perl -pe 's/\\\\n/\n/g; s/\\n/\n/g' | sed -n '/TRS-TEST-RESULTS/,$p' | grep -E '^(PASS|FAIL|NO CHECKS)')
  if [ -z "$res" ]; then echo "== $name: SUITE ERROR"; echo "$out" | grep -v NOTICE | tail -15; FAILED=$((FAILED+1)); continue; fi
  p=$(echo "$res" | grep -c '^PASS'); f=$(echo "$res" | grep -c '^FAIL')
  echo "== $name: $p passed, $f failed"
  echo "$res" | grep '^FAIL'
  FAILED=$((FAILED+f))
done
exit $FAILED
