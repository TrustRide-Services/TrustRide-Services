-- ============================================================================
-- TRS026 Construction Directive WP7 (section 2.4) -- eTIMS vocabulary: a
-- supplier invoice TrustRide receives is RECEIVED (it is not submitted by
-- TrustRide). Its own migration so the value is committed before 052 uses it.
-- ============================================================================

ALTER TYPE trustride.integration_etims_invoice_status_enum ADD VALUE IF NOT EXISTS 'RECEIVED';

SELECT trustride.fn_platform_conformance_assert();
