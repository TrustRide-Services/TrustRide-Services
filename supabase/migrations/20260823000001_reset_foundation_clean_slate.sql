-- ============================================================================
-- TRUSTRIDE SERVICES PLATFORM
-- ============================================================================
-- RESET NOTE: Founder ruling 2026-08-23 -- Engine 001 Foundation must ship
-- as ONE truly single migration file covering all five sub-engines
-- (Substrate, Core, Identity, Governance, Audit), not five separate pushes.
-- The prior Substrate-only push (20260821000001) is reset to empty here so
-- the complete file (20260823000002_engine001_foundation.sql) can be
-- applied to a genuinely clean database. No production project was ever
-- touched by the Substrate-only version; this reset is staging-only.
-- ============================================================================

DROP SCHEMA IF EXISTS trustride CASCADE;
DROP ROLE IF EXISTS trs026_eng001_fdn_service;
DROP ROLE IF EXISTS trustride_authenticated;

-- Clear the CLI's own migration-history tracking for the superseded file so
-- `supabase migration list` no longer reports it as applied.
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20260821000001';
