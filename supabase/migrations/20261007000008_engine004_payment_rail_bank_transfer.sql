-- ============================================================================
-- Engine 4 (Business): BANK_TRANSFER payment rail
-- ============================================================================
-- A Marketplace vehicle can cost more than the M-Pesa STK per-transaction
-- limit; such purchases are paid by bank transfer, recorded by TrustRide
-- Office against the bank reference. The value is added alone, before use.
ALTER TYPE trustride.business_payment_rail_enum ADD VALUE IF NOT EXISTS 'BANK_TRANSFER';
