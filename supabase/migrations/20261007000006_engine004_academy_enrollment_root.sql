-- ============================================================================
-- Engine 4 (Business): order root for TrustRide Academy enrollment (G6)
-- ============================================================================
-- EA-ACADEMY-TRAINING is an intake service (enrollment in TrustRide Academy
-- programmes), not a dispatch service. It gets its own governed request
-- root, decided by TrustRide Office on the same 2-3 working-day clock as
-- every other actor request. (EA-EMPLOYMENT-APPLICATION already has one:
-- it is an OFFICE_ACCESS_REQUEST for the Operator App.)
-- The value is added alone, before any function uses it.
ALTER TYPE trustride.business_order_root_enum ADD VALUE IF NOT EXISTS 'ACADEMY_ENROLLMENT_REQUEST';
