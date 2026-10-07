-- ============================================================================
-- Platform: state vocabulary extensions for Implementation Completion
-- ============================================================================
-- New enum values must be committed before any function or row uses them,
-- so every value the completion stages need is added here, in one place,
-- each traced to the gap it closes. Nothing is renamed or removed.
-- ============================================================================

-- Engine 4 (Business) -- Order integrity (directive Sec.16): every order is
-- always in an explicit state; no silent dead ends.
ALTER TYPE trustride.business_order_status_enum ADD VALUE IF NOT EXISTS 'QUOTED';            -- G8: estimate shown, awaiting customer acceptance
ALTER TYPE trustride.business_order_status_enum ADD VALUE IF NOT EXISTS 'WAITING';           -- G4: no suitable resource yet; queued for retry
ALTER TYPE trustride.business_order_status_enum ADD VALUE IF NOT EXISTS 'SCHEDULED';         -- G11 / after-hours: held for a future dispatch window
ALTER TYPE trustride.business_order_status_enum ADD VALUE IF NOT EXISTS 'EXPIRED';           -- G8/G4: estimate not accepted in time, or waited past the limit
ALTER TYPE trustride.business_order_status_enum ADD VALUE IF NOT EXISTS 'FAILED';            -- G5: an unrecoverable engine failure, surfaced explicitly
ALTER TYPE trustride.business_order_status_enum ADD VALUE IF NOT EXISTS 'AWAITING_PAYMENT';  -- G6/G16: marketplace purchase reserved, payment requested

ALTER TYPE trustride.business_order_stage_enum ADD VALUE IF NOT EXISTS 'QUOTATION_ACCEPTANCE';
ALTER TYPE trustride.business_order_stage_enum ADD VALUE IF NOT EXISTS 'SCHEDULED_HOLD';
ALTER TYPE trustride.business_order_stage_enum ADD VALUE IF NOT EXISTS 'FULFILMENT';

-- G3 / directive Sec.13: the operator acknowledges (accepts) a job before
-- dispatching; a job can fail explicitly (operator-reported problem).
ALTER TYPE trustride.business_job_status_enum ADD VALUE IF NOT EXISTS 'ACKNOWLEDGED' AFTER 'CREATED';
ALTER TYPE trustride.business_job_status_enum ADD VALUE IF NOT EXISTS 'FAILED';

-- Engine 2 (Resources) -- G15 safeguarding: vetting clearance and the
-- Executive Assistant skills a worker is credentialled for.
ALTER TYPE trustride.resource_capability_type_enum ADD VALUE IF NOT EXISTS 'ENHANCED_VETTING_CLEARANCE';
ALTER TYPE trustride.resource_capability_type_enum ADD VALUE IF NOT EXISTS 'CHILD_SAFEGUARDING_CERT';
ALTER TYPE trustride.resource_capability_type_enum ADD VALUE IF NOT EXISTS 'SKILL_ERRANDS';
ALTER TYPE trustride.resource_capability_type_enum ADD VALUE IF NOT EXISTS 'SKILL_DRIVING';
ALTER TYPE trustride.resource_capability_type_enum ADD VALUE IF NOT EXISTS 'SKILL_CAREGIVING';
ALTER TYPE trustride.resource_capability_type_enum ADD VALUE IF NOT EXISTS 'SKILL_CLEANING';
ALTER TYPE trustride.resource_capability_type_enum ADD VALUE IF NOT EXISTS 'SKILL_CHEF';
ALTER TYPE trustride.resource_capability_type_enum ADD VALUE IF NOT EXISTS 'SKILL_SHOPPING';

-- Engine 6 (Integration) -- Stage 3 / Sec.7 notification channels, Sec.9
-- telemetry, and the explicit outcomes a delivery can have.
ALTER TYPE trustride.integration_notification_channel_enum ADD VALUE IF NOT EXISTS 'PUSH';
ALTER TYPE trustride.integration_notification_channel_enum ADD VALUE IF NOT EXISTS 'EMAIL';
ALTER TYPE trustride.integration_notification_status_enum ADD VALUE IF NOT EXISTS 'SUPPRESSED';   -- the person opted out / quiet hours
ALTER TYPE trustride.integration_notification_status_enum ADD VALUE IF NOT EXISTS 'UNREACHABLE';  -- no verified contact on that channel
ALTER TYPE trustride.integration_port_code_enum ADD VALUE IF NOT EXISTS 'PUSH_SERVICE';
ALTER TYPE trustride.integration_port_code_enum ADD VALUE IF NOT EXISTS 'EMAIL_SERVICE';
ALTER TYPE trustride.integration_port_code_enum ADD VALUE IF NOT EXISTS 'TELEMETRY_SERVICE';
ALTER TYPE trustride.integration_payment_txn_status_enum ADD VALUE IF NOT EXISTS 'TIMED_OUT';    -- G10: no callback within the window
