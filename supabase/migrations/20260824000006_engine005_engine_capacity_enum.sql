-- ============================================================================
-- TRUSTRIDE SERVICES PLATFORM
-- ============================================================================
-- ENGINE CODE          : TRS026_ENG005_COST (extension)
-- MIGRATION DATA
-- FILE NAME            : 20260824000006_engine005_engine_capacity_enum.sql
-- STATUS               : COMPLETE -- additive, no destructive changes.
-- CREATED AT           : 2026-08-24
-- ============================================================================
--
-- Split into its own file, deliberately: PostgreSQL does not allow a newly
-- added enum value (ALTER TYPE ... ADD VALUE) to be referenced within the
-- SAME transaction that added it, and each migration file applies as one
-- transaction. CC_1500_SALOON and TON_7_0 are used by the very next
-- migration (the universal asset matrix hardening), so the addition must
-- commit first, in its own file.
-- ============================================================================

ALTER TYPE trustride.cost_engine_capacity_enum ADD VALUE IF NOT EXISTS 'CC_1500_SALOON';
ALTER TYPE trustride.cost_engine_capacity_enum ADD VALUE IF NOT EXISTS 'TON_7_0';
