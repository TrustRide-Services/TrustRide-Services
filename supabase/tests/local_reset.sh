#!/bin/bash
# Rebuild the local mirror from nothing: a fresh Supabase Postgres 17
# container, the hosted-project auth shim, then the full migration chain.
# Usage: ./local_reset.sh   (stops at the first failing migration)
set -e
cd "$(dirname "$0")"
docker rm -f trs_local17 >/dev/null 2>&1 || true
MSYS_NO_PATHCONV=1 docker run -d --name trs_local17 -e POSTGRES_PASSWORD=postgres -p 55433:5432 \
  public.ecr.aws/supabase/postgres:17.6.1.155 postgres -c config_file=/etc/postgresql/postgresql.conf -c cron.database_name=postgres >/dev/null
for i in $(seq 1 60); do
  MSYS_NO_PATHCONV=1 docker exec trs_local17 psql -U supabase_admin -d postgres -tAc "select 1" >/dev/null 2>&1 && break; sleep 2
done
sleep 5
MSYS_NO_PATHCONV=1 docker exec -i trs_local17 psql -U supabase_admin -d postgres -q < local_mirror_setup.sql 2>/dev/null
for f in ../migrations/*.sql; do
  if ! out=$(MSYS_NO_PATHCONV=1 docker exec -i trs_local17 psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q -1 < "$f" 2>&1); then
    echo "FAILED: $(basename "$f")"; echo "$out" | grep -v NOTICE | tail -8; exit 1
  fi
done
echo "local mirror ready: $(ls ../migrations/*.sql | wc -l) migrations applied"
