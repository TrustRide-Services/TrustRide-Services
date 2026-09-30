-- ============================================================================
-- ENGINE 4 (BUSINESS) -- ONE ORDER ROOT PER ACTOR PATH
-- [Trace: Founder direction 2026-10-01; TRS026-ENG011-PRESENT-003 Sec.4, Sec.7]
--
-- business_order_root_enum held two roots (SERVICE_ORDER for Customers,
-- RESOURCE_PARTNERSHIP_REQUEST for Partners). Every other actor path had no
-- lawful way into the Business engine at all. One root per path now, so no
-- authorized actor reaches a surface with nothing to submit:
--
--   SERVICE_ORDER                Customer -- the five services, immediate or scheduled
--   RESOURCE_PARTNERSHIP_REQUEST Partner -- contribute a resource / finance / collaboration
--   REGULATORY_ACCESS_REQUEST    Governor -- e.g. a county revenue authority requesting
--                                oversight access or statutory information for a
--                                jurisdiction and scope
--   FACILITATION_REQUEST         Intermediary -- facilitation / intermediation scope
--   VENDOR_LISTING_REQUEST       Vendor -- a motorcycle or car seller applying to list on
--                                the TrustRide Marketplace (commission per sale)
--   MARKETPLACE_PURCHASE_ORDER   Buyer -- reserving a second-hand motorcycle or car from
--                                the TrustRide Marketplace
--   OFFICE_ACCESS_REQUEST        TrustRide staff -- Operator, Admin or Executive requesting
--                                entry to TrustRide Office
--
-- Enum values only, in their own migration: a new enum value cannot be used
-- in the same transaction that adds it.
-- ============================================================================
ALTER TYPE trustride.business_order_root_enum ADD VALUE IF NOT EXISTS 'REGULATORY_ACCESS_REQUEST';
ALTER TYPE trustride.business_order_root_enum ADD VALUE IF NOT EXISTS 'FACILITATION_REQUEST';
ALTER TYPE trustride.business_order_root_enum ADD VALUE IF NOT EXISTS 'VENDOR_LISTING_REQUEST';
ALTER TYPE trustride.business_order_root_enum ADD VALUE IF NOT EXISTS 'MARKETPLACE_PURCHASE_ORDER';
ALTER TYPE trustride.business_order_root_enum ADD VALUE IF NOT EXISTS 'OFFICE_ACCESS_REQUEST';
