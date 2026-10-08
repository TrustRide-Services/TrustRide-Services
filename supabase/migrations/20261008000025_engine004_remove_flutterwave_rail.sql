-- ============================================================================
-- Engine 4 (Business) -- Flutterwave removed from the payment-rail vocabulary
-- ============================================================================
-- Founder ruling 2026-10-08: Flutterwave is removed completely until the
-- system grows. Engine 6 already dropped it as the payment port's secondary
-- vendor (20260824000008); the last trace is the FLUTTERWAVE label of
-- business_payment_rail_enum, which no row uses. The type is rebuilt with
-- the two rails TrustRide actually takes: M-Pesa STK and bank transfer.
-- Nothing in Engine 5 is touched.
-- ============================================================================
DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM trustride.business_settlement WHERE payment_rail::text = 'FLUTTERWAVE')
     OR EXISTS (SELECT 1 FROM trustride.business_customer_profile WHERE preferred_payment_rail::text = 'FLUTTERWAVE') THEN
    RAISE EXCEPTION 'FLUTTERWAVE is still in use -- not removed';
  END IF;
END;
$guard$;

ALTER TYPE trustride.business_payment_rail_enum RENAME TO business_payment_rail_enum_retired;
CREATE TYPE trustride.business_payment_rail_enum AS ENUM ('MPESA_C2B_STK', 'BANK_TRANSFER');
ALTER TABLE trustride.business_settlement
  ALTER COLUMN payment_rail TYPE trustride.business_payment_rail_enum USING payment_rail::text::trustride.business_payment_rail_enum;
ALTER TABLE trustride.business_customer_profile
  ALTER COLUMN preferred_payment_rail TYPE trustride.business_payment_rail_enum USING preferred_payment_rail::text::trustride.business_payment_rail_enum;
DROP TYPE trustride.business_payment_rail_enum_retired;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
