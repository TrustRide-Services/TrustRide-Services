-- ============================================================================
-- PLATFORM: AUTOMATIC SIGNAL DISPATCH (pg_cron)
-- ============================================================================
-- Found while preparing the frontend/Vercel handoff: nothing anywhere in
-- this rebuild ever calls trustride.fn_orch_dispatch_cycle() automatically.
-- Every one of this session's tests (local and the live staging closure
-- test) drove the cascade by calling it explicitly in a loop -- correct for
-- proving the platform's own logic, but it means a real end user submitting
-- a command through a real frontend would see their order sit motionless
-- forever, since nothing would ever pick the resulting signal up.
--
-- Fix: enable pg_cron (available on this project, not previously installed
-- -- confirmed via pg_available_extensions) and schedule the dispatch cycle
-- on a short interval, the same operational pattern this platform's own
-- prior build (a separate, now-superseded codebase) already used successfully
-- ("pg_cron 10s cadence"). This is Orchestration's own stated purpose made
-- real, not a frontend concern -- Engine 11's schema is untouched.
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS pg_cron;

GRANT USAGE ON SCHEMA cron TO postgres;

SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'trustride_dispatch_cycle';

SELECT cron.schedule(
  'trustride_dispatch_cycle',
  '10 seconds',
  $$SELECT trustride.fn_orch_dispatch_cycle();$$
);

-- ============================================================================
-- VALIDATION
-- ============================================================================
DO $$
DECLARE
  v_job RECORD;
BEGIN
  SELECT * INTO v_job FROM cron.job WHERE jobname = 'trustride_dispatch_cycle';
  IF v_job IS NULL OR NOT v_job.active THEN
    RAISE EXCEPTION 'AUTOMATIC DISPATCH VALIDATION FAILED: trustride_dispatch_cycle job not found or not active';
  END IF;
  RAISE NOTICE 'AUTOMATIC DISPATCH VERIFIED: trustride_dispatch_cycle scheduled every % (jobid=%), active=%.', v_job.schedule, v_job.jobid, v_job.active;
END;
$$;
