-- ============================================================================
-- TRUSTRIDE SERVICES PLATFORM
-- ============================================================================
-- MIGRATION DATA
-- FILE NAME : 20260824000002_reconciliation_engines_1to5.sql
-- STATUS    : COMPLETE -- targeted, additive reconciliation fixes found by a
--             full Engines 1-5 compatibility audit, per Founder directive
--             2026-08-24: "do a comprehensive reconciliation, do a thorough
--             audit of engines 1-5 compatibility, complete work and
--             relationship, correct where you see gaps."
-- CREATED AT: 2026-08-24
-- ============================================================================
--
-- AUDIT METHOD: cross-checked, directly against the live trustride-stagging
-- database (never static file inspection alone) -- routing_rule vs
-- orch_destination_cache vs orch_outbox_registry vs every inbox processor's
-- CASE completeness vs engine_registry status vs every "mirrors by value"
-- vocabulary pair (Resources' resource_capacity_class_enum vs Cost's
-- cost_asset_class_enum, jurisdiction strings, engine_registry consistency),
-- plus a scan for any REJECTED/DEAD_LETTER signal sitting live and any
-- lingering current_setting('app.current_user_id') RLS bug.
--
-- FINDINGS:
--
--   1. REAL BUG, HIGH SEVERITY: cost_asset_class_enum does not actually
--      mirror resource_capacity_class_enum by value, despite resource_
--      capacity_class's own comment explicitly promising it does ("Engine
--      5's asset_class_enum/engine_capacity_enum mirror this registry by
--      value"). Resources has 7 capacity classes (BODA_BODA, TUKTUK, SEDAN,
--      PICKUP_TOWN, VAN_CARGO, TRUCK_LIGHT, EXECUTIVE_ASSISTANT_HUMAN);
--      Cost's asset_class_enum was rebuilt fresh during the 17-table Engine
--      005 rebuild and only carries 6, missing SEDAN entirely and using
--      EXECUTIVE_ASSISTANT (no _HUMAN suffix) instead of Resources' real
--      value. A live SEDAN or EXECUTIVE_ASSISTANT_HUMAN workforce unit
--      dispatched through the real signal pipeline would hit RESOURCE_
--      DISPATCH_INITIATED -> fn_cost_resource_dispatch_initiated_accept's
--      (v_payload->>'asset_class')::trustride.cost_asset_class_enum cast
--      and fail at runtime with an invalid-enum-literal error -- CREATE
--      FUNCTION never catches this (no static type-check of a text->enum
--      cast inside a plpgsql body), only a real dispatch would surface it,
--      exactly the class of bug this platform's own testing discipline
--      exists to catch before it reaches that point. Fixed below via ALTER
--      TYPE ADD VALUE / RENAME VALUE -- the safe, additive path; no existing
--      cost_rate/cost_registry/fare_calculation row currently references
--      the old EXECUTIVE_ASSISTANT label (only BODA_BODA has been seeded so
--      far), so the rename is lossless.
--   2. REAL BUG, MEDIUM SEVERITY: fn_orch_destination_cache_sync() only
--      INSERTs/UPSERTs cache rows from currently-active routing_rule rows;
--      it never deactivates a cache row whose routing_rule was since
--      deleted. Found directly: the Engine 4 (Business) rollback's own
--      reset command deleted orch_destination_cache rows WHERE destination_
--      engine_code = 'TRS026_ENG004_BUS' (matching what Business would have
--      RECEIVED), but three rows where Business was instead the SOURCE
--      engine (ASSIGNMENT_REQUESTED, JOB_COMPLETED, SERVICE_LOOKUP_REQUESTED
--      -> Resources/Services) survived, orphaned, with no matching routing_
--      rule row left to justify them. Currently inert (orch_outbox_registry
--      correctly has no TRS026_ENG004_BUS row, so fn_orch_dispatch_cycle's
--      own UNION ALL never looks at a business_event_outbox that doesn't
--      exist), but this is a real, generalizable correctness gap in Engine
--      7's own constitutional promise that its cache is a faithful mirror
--      of routing_rule -- the next engine reset would hit the identical
--      silent drift. Fixed below: the sync function now also marks any
--      cache row SUPERSEDED (the table's own existing status vocabulary --
--      ACTIVE/STALE/SUPERSEDED -- never hard-deleted, matching the
--      platform's own append-only-history convention) when its (source,
--      signal_type, destination) no longer has a matching active routing_
--      rule row.
--   3. CONFIRMED CLEAN (no fix needed, recorded for the audit trail):
--      routing_rule (4 live rows) matches orch_outbox_registry (4 active
--      engines: FDN/RESC/SERV/COST) exactly for every live-to-live signal
--      path; both fan-out branches of MARKETPLACE_LISTING_SOLD/RESOURCE_
--      MARKETPLACE_ITEM_READY are correctly wired both ways in fn_resource_
--      inbox_process/fn_service_inbox_process; every signal targeting a
--      not-yet-built engine (Business, Engine 6, Engine 9) correctly and
--      honestly surfaces as NO_RULE_MATCHED rather than erroring or being
--      silently dropped; engine_registry status (INSTALLED for 1/2/3/5/7/8,
--      REGISTERED for 4/6/9/10/11) exactly matches real deployed state;
--      zero REJECTED/DEAD_LETTER signals sitting unresolved in any live
--      inbox; the Article-2-RLS current_setting('app.current_user_id') bug
--      does not exist in any live engine (only as a documented comment in
--      Engine 4's own not-yet-live Correction 2).
--   4. NOTED, NOT FIXED HERE (pre-existing, already-documented gaps, out of
--      this reconciliation's scope since they are not compatibility BREAKS,
--      just incomplete coverage): no cost_rate/cost_registry exists yet for
--      any asset class other than BODA_BODA -- normal incremental rollout,
--      not a bug, and now safe to extend since the enum itself is correct;
--      resource_estate_register.jurisdiction is bare TEXT, not governed by
--      the same cost_jurisdiction_enum vocabulary Cost uses -- lower
--      severity since nothing currently casts it directly, flagged for a
--      future engine's own reconciliation pass rather than fixed here;
--      Resources still has no per-unit engine-capacity (CC_125 etc.) column
--      -- already a named, deferred gap from Engine 5's own build.
--
-- ============================================================================

-- --- Finding 1: cost_asset_class_enum <-> resource_capacity_class_enum ---
ALTER TYPE trustride.cost_asset_class_enum ADD VALUE IF NOT EXISTS 'SEDAN';
ALTER TYPE trustride.cost_asset_class_enum RENAME VALUE 'EXECUTIVE_ASSISTANT' TO 'EXECUTIVE_ASSISTANT_HUMAN';

-- --- Finding 2: fn_orch_destination_cache_sync must also prune orphans ---
-- (same signature as the live function -- CREATE OR REPLACE truly replaces,
-- no stale overload risk here since the parameter list is unchanged).
CREATE OR REPLACE FUNCTION trustride.fn_orch_destination_cache_sync()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_synced INTEGER;
  v_deactivated INTEGER;
BEGIN
  INSERT INTO trustride.orch_destination_cache
    (source_engine_code, signal_type, destination_engine_code, destination_inbox_table, default_partition_code, synced_from_routing_rule_ref, cache_status, last_synced_at)
  SELECT rr.source_engine, rr.event_type, rr.target_engine,
    CASE rr.target_engine
      WHEN 'TRS026_ENG001_FDN'  THEN 'platform_event_inbox'
      WHEN 'TRS026_ENG002_RESC' THEN 'resource_event_inbox'
      WHEN 'TRS026_ENG003_SERV' THEN 'service_event_inbox'
      WHEN 'TRS026_ENG004_BUS'  THEN 'business_event_inbox'
      WHEN 'TRS026_ENG005_COST' THEN 'cost_event_inbox'
      ELSE NULL
    END,
    rr.target_engine || ':DEFAULT',
    rr.route_id::text, 'ACTIVE', now()
  FROM trustride.routing_rule rr
  WHERE rr.active = TRUE
    AND CASE rr.target_engine
      WHEN 'TRS026_ENG001_FDN' THEN TRUE WHEN 'TRS026_ENG002_RESC' THEN TRUE WHEN 'TRS026_ENG003_SERV' THEN TRUE
      WHEN 'TRS026_ENG004_BUS' THEN TRUE WHEN 'TRS026_ENG005_COST' THEN TRUE ELSE FALSE
    END
  ON CONFLICT (source_engine_code, signal_type, destination_engine_code) DO UPDATE
    SET destination_inbox_table = EXCLUDED.destination_inbox_table,
        cache_status = 'ACTIVE', last_synced_at = now();

  GET DIAGNOSTICS v_synced = ROW_COUNT;

  -- Prune: any cache row whose (source, signal_type, destination) no longer
  -- has a matching ACTIVE routing_rule row is deactivated, never deleted --
  -- matching the platform's own append-only-history convention. This is
  -- what fn_orch_dispatch_cycle's own "WHERE cache_status = 'ACTIVE'" filter
  -- depends on to actually stop honoring a revoked route.
  UPDATE trustride.orch_destination_cache dc
  SET cache_status = 'SUPERSEDED', last_synced_at = now()
  WHERE dc.cache_status = 'ACTIVE'
    AND NOT EXISTS (
      SELECT 1 FROM trustride.routing_rule rr
      WHERE rr.active = TRUE
        AND rr.source_engine = dc.source_engine_code
        AND rr.event_type = dc.signal_type
        AND rr.target_engine = dc.destination_engine_code
    );
  GET DIAGNOSTICS v_deactivated = ROW_COUNT;

  RETURN v_synced + v_deactivated;
END;
$$;

-- Self-correct the three orphaned rows found live (ASSIGNMENT_REQUESTED,
-- JOB_COMPLETED, SERVICE_LOOKUP_REQUESTED, source=TRS026_ENG004_BUS) by
-- simply re-running the now-fixed sync.
SELECT trustride.fn_orch_destination_cache_sync();
