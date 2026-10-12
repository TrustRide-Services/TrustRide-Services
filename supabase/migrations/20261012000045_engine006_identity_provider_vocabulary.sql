-- ============================================================================
-- Engine 6 -- vocabulary for a live identity provider and new outbound operations
-- Construction Directive WP7 (sections 2.6, 2.7)
-- ============================================================================
-- Enum values must be committed before use, so they come in their own
-- migration. A live identity authority can answer three things the simulator
-- never needed:
--   RECORD_FOUND_STATUS_UNKNOWN -- the national-register record exists and its
--     names are returned, but no vital status is given (MetaMap's Kenya IPRS
--     check returns documentNumber, givenNames, lastName, fullName, gender,
--     dateOfBirth -- no alive/deceased status);
--   NOT_FOUND -- no record for that number;
--   PROVIDER_UNAVAILABLE -- the provider could not answer after the governed
--     retries.
-- Outbound operations added: IDENTITY_VERIFY and ENTITY_VERIFY (identity
-- authority, provider-neutral; first provider MetaMap) and VEHICLE_LOOKUP
-- (NTSA chassis / VIN boundary).
-- ============================================================================

ALTER TYPE trustride.integration_verification_outcome_enum ADD VALUE IF NOT EXISTS 'RECORD_FOUND_STATUS_UNKNOWN';
ALTER TYPE trustride.integration_verification_outcome_enum ADD VALUE IF NOT EXISTS 'NOT_FOUND';
ALTER TYPE trustride.integration_verification_outcome_enum ADD VALUE IF NOT EXISTS 'PROVIDER_UNAVAILABLE';

ALTER TABLE trustride.integration_outbound_request DROP CONSTRAINT integration_outbound_request_operation_check;
ALTER TABLE trustride.integration_outbound_request ADD CONSTRAINT integration_outbound_request_operation_check
  CHECK (operation IN ('NOTIFY_SMS', 'NOTIFY_WHATSAPP', 'NOTIFY_EMAIL', 'NOTIFY_PUSH', 'STK_PUSH', 'B2C_PAYOUT', 'ROUTE_MATRIX',
                       'IDENTITY_VERIFY', 'ENTITY_VERIFY', 'VEHICLE_LOOKUP'));

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
