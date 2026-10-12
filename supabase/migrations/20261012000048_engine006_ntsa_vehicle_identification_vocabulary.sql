-- ============================================================================
-- TRS026 Construction Directive WP7 (section 2.7) -- vocabulary for NTSA vehicle
-- identification by VIN or chassis number. Its own migration so the value is
-- committed before 049 uses it.
-- ============================================================================

ALTER TYPE trustride.integration_ntsa_check_type_enum ADD VALUE IF NOT EXISTS 'VEHICLE_IDENTIFICATION';

SELECT trustride.fn_platform_conformance_assert();
