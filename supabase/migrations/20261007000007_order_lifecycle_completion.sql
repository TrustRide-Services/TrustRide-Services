-- ============================================================================
-- Order lifecycle completion -- Engines 2, 3, 4, 5, 11
-- Implementation Completion Stages 7-9: G4 (unavailable resource), G5 (EA
-- hand-off), G6 (eligibility & routing), G7 (multi-line), G8/D2 (estimate ->
-- acceptance -> dispatch), G11 (scheduled orders), G12 (progress
-- notifications), G14 (platform-computed distance), D1 (Sunday closed),
-- Sec.16 (explicit order states), Sec.22 (no orphaned reservations).
-- ============================================================================
-- The engine wiring is unchanged in shape -- Business still asks Services,
-- Resources still matches, Cost still prices, Integration still collects.
-- What changes is that every hand-off now carries the information the next
-- engine needs, and every "no" now travels back and lands in an explicit
-- state the customer is told about:
--
--   RAISE_INTENT -> PLACED -> (Services) -> VALIDATED / SCHEDULED / DECLINED
--   -> (Resources) RESERVED or RESOURCE_UNAVAILABLE -> WAITING (retry each
--   minute; EXPIRED after the wait limit) -> RESOURCE_ASSIGNED: one job per
--   order line -> (Cost) FARE_QUOTED: one estimate, the sum of its lines ->
--   QUOTED -> customer ACCEPT_QUOTATION -> UNIT_PRICE_LOCKED -> operator
--   ACKNOWLEDGED -> DISPATCHED -> EN_ROUTE -> ARRIVED -> EXECUTING -> (each
--   stop) COMPLETED -> last stop: payment requested -> VERIFIED -> unit
--   released. Unaccepted estimates EXPIRE; customers CANCEL; Office
--   INTERVENEs (cancel / reassign / fail); a failed price FAILS the order and
--   releases the worker. Nothing waits silently.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Configuration (Founder-adjustable, effective-dated)
-- ---------------------------------------------------------------------------
-- (the third column of each row is its meaning; platform_configuration
-- stores only key and value)
INSERT INTO trustride.platform_configuration (config_key, config_value, environment, effective_from, changed_by)
SELECT v.k, v.v, 'ALL', now(), '00000000-0000-0000-0000-000000000000' FROM (VALUES
  ('QUOTE_ACCEPTANCE_WINDOW_MIN', '10', 'Minutes a customer has to accept a fare estimate before it expires and the matched worker is released.'),
  ('ORDER_WAIT_MAX_MIN', '30', 'Minutes an immediate order may wait for a free resource within working hours before it is closed (customer not charged).'),
  ('ORDER_RETRY_INTERVAL_SEC', '60', 'Seconds between matching attempts for a waiting order.'),
  ('SCHEDULED_DISPATCH_LEAD_MIN', '30', 'Minutes before a scheduled start that matching begins.'),
  ('SCHEDULE_MAX_DAYS_AHEAD', '14', 'How far ahead a customer may schedule a service.'),
  ('OPERATOR_ACK_TIMEOUT_MIN', '3', 'Minutes an operator has to acknowledge a confirmed job before it is offered to another operator.'),
  ('JOB_AUTO_VERIFY_MIN', '10', 'Minutes after a stop is completed before the platform verifies it automatically (so a worker is never left reserved).'),
  ('ORDER_MAX_LINES', '5', 'Maximum stops (order lines) per order.'),
  ('EA_DAY_SHIFT_WINDOW', '06:00-19:00', 'Local hours priced at the Executive Assistant DAY rate; other working hours are NIGHT.')
) AS v(k, v, d)
WHERE NOT EXISTS (SELECT 1 FROM trustride.platform_configuration c WHERE c.config_key = v.k);

-- D1 (Founder, Sunday is off duty): the EA Sunday/holiday multiplier can
-- never apply -- no Sunday or public-holiday service exists -- so it is
-- retired rather than left as a contradictory rule.
UPDATE trustride.cost_ea_shift_multiplier SET active = FALSE WHERE shift_type = 'SUNDAY_HOLIDAY' AND active;

-- ---------------------------------------------------------------------------
-- 2. Services: what each service needs to be fulfilled (G6, G15)
-- ---------------------------------------------------------------------------
-- requirements.fulfilment says HOW a service is fulfilled:
--   DISPATCH    -- matched to a worker/vehicle and priced (16 services)
--   INTAKE      -- a governed request decided by TrustRide Office
--   MARKETPLACE -- the Marketplace listing/inventory/purchase flow
UPDATE trustride.service_catalogue sc SET requirements = sc.requirements || r.req::jsonb, updated_at = now()
FROM (VALUES
  ('TRANSPORT-BODA-STANDARD', '{"fulfilment":"DISPATCH","trip":true}'),
  ('TRANSPORT-TUKTUK-STANDARD', '{"fulfilment":"DISPATCH","trip":true}'),
  ('TRANSPORT-SEDAN-STANDARD', '{"fulfilment":"DISPATCH","trip":true}'),
  ('COURIER-DOCUMENT', '{"fulfilment":"DISPATCH","trip":true}'),
  ('COURIER-PARCEL', '{"fulfilment":"DISPATCH","trip":true}'),
  ('DELIVERY-GOODS-TOWN', '{"fulfilment":"DISPATCH","trip":true}'),
  ('DELIVERY-CARGO-BULK', '{"fulfilment":"DISPATCH","trip":true}'),
  ('EA-ERRANDS-GENERAL', '{"fulfilment":"DISPATCH","ea_skill_category":"PERSONAL_SHOPPER_ERRAND","pillar":"ERRANDS"}'),
  ('EA-ERRANDS-SCHOOL_VISITATION', '{"fulfilment":"DISPATCH","ea_skill_category":"CORPORATE_REPRESENTATIVE","pillar":"ERRANDS"}'),
  ('EA-SHOPPING-GENERAL', '{"fulfilment":"DISPATCH","ea_skill_category":"PERSONAL_SHOPPER_ERRAND","pillar":"SHOPPING"}'),
  ('EA-SHOPPING-REPRESENTATION_DELIVERY', '{"fulfilment":"DISPATCH","ea_skill_category":"CORPORATE_REPRESENTATIVE","pillar":"SHOPPING"}'),
  ('EA-DRIVING-GENERAL', '{"fulfilment":"DISPATCH","ea_skill_category":"PROFESSIONAL_CHAUFFEUR","pillar":"DRIVING"}'),
  ('EA-DRIVING-STUDENT_PICKUP', '{"fulfilment":"DISPATCH","ea_skill_category":"PROFESSIONAL_CHAUFFEUR","pillar":"DRIVING"}'),
  ('EA-CAREGIVING-GENERAL', '{"fulfilment":"DISPATCH","ea_skill_category":"PATIENT_ELDER_CAREGIVER","pillar":"CAREGIVING"}'),
  ('EA-CLEANING-GENERAL', '{"fulfilment":"DISPATCH","ea_skill_category":"HOUSE_MANAGER_DOMESTIC","pillar":"CLEANING"}'),
  ('EA-CHEF-GENERAL', '{"fulfilment":"DISPATCH","ea_skill_category":"CERTIFIED_CHEF","pillar":"CHEF"}'),
  ('EA-ACADEMY-TRAINING', '{"fulfilment":"INTAKE","intake_root":"ACADEMY_ENROLLMENT_REQUEST","eligible_user_types":["CUSTOMER"],"requires_verified_identity":true,"command":"ENROLL_ACADEMY"}'),
  ('EA-EMPLOYMENT-APPLICATION', '{"fulfilment":"INTAKE","intake_root":"OFFICE_ACCESS_REQUEST","office_surface":"OPERATOR_APP","eligible_user_types":["CUSTOMER"],"requires_verified_identity":true,"command":"APPLY_EMPLOYMENT"}'),
  ('MARKETPLACE-ITEM-SALE', '{"fulfilment":"MARKETPLACE","actor":"BUYER","command":"PURCHASE_LISTING"}'),
  ('MARKETPLACE-ITEM-LISTING', '{"fulfilment":"MARKETPLACE","actor":"VENDOR_OR_OFFICE","command":"PUBLISH_OFFER"}'),
  ('MARKETPLACE-VENDOR-ONBOARDING', '{"fulfilment":"MARKETPLACE","actor":"VENDOR","command":"SUBMIT_VENDOR_LISTING"}'),
  ('MARKETPLACE-RESOURCE-CONTRIBUTION', '{"fulfilment":"MARKETPLACE","actor":"PARTNER","command":"SUBMIT_CONTRIBUTION"}'),
  ('MARKETPLACE-ITEM-ACQUISITION', '{"fulfilment":"MARKETPLACE","actor":"OFFICE","command":"ACQUIRE_INVENTORY"}'),
  ('MARKETPLACE-ITEM-REFURBISHMENT', '{"fulfilment":"MARKETPLACE","actor":"OFFICE","command":"ADVANCE_INVENTORY"}')
) AS r(code, req)
WHERE sc.service_code = r.code;

-- Safeguarding (G15): the credentials each Executive Assistant service
-- requires; ENHANCED-tier services (children, the elderly, the vulnerable)
-- additionally require enhanced vetting clearance. Each previous rule is
-- retired (never deleted) and replaced.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('EA-ERRANDS-GENERAL', 'STANDARD', '["SKILL_ERRANDS"]'),
    ('EA-ERRANDS-SCHOOL_VISITATION', 'ENHANCED', '["SKILL_ERRANDS","CHILD_SAFEGUARDING_CERT"]'),
    ('EA-SHOPPING-GENERAL', 'STANDARD', '["SKILL_SHOPPING"]'),
    ('EA-SHOPPING-REPRESENTATION_DELIVERY', 'STANDARD', '["SKILL_SHOPPING"]'),
    ('EA-DRIVING-GENERAL', 'STANDARD', '["SKILL_DRIVING"]'),
    ('EA-DRIVING-STUDENT_PICKUP', 'ENHANCED', '["SKILL_DRIVING","CHILD_SAFEGUARDING_CERT"]'),
    ('EA-CAREGIVING-GENERAL', 'ENHANCED', '["SKILL_CAREGIVING","FIRST_AID_CERT"]'),
    ('EA-CLEANING-GENERAL', 'STANDARD', '["SKILL_CLEANING"]'),
    ('EA-CHEF-GENERAL', 'STANDARD', '["SKILL_CHEF"]')
  ) AS x(code, tier, certs) LOOP
    UPDATE trustride.service_eligibility_rule er SET active = FALSE
    FROM trustride.service_catalogue sc WHERE sc.service_id = er.service_id AND sc.service_code = r.code AND er.active;
    PERFORM trustride.fn_service_eligibility_rule_add(sc.service_id, 'EXECUTIVE_ASSISTANT_HUMAN', r.tier, r.certs::jsonb)
    FROM trustride.service_catalogue sc WHERE sc.service_code = r.code;
  END LOOP;
END;
$$;

-- SERVICE_RESOLVED now carries the service's own requirements, so Business
-- never has to look them up across an engine boundary.
DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_service_lookup_requested_accept(uuid)'::regprocedure) INTO v_def;
  IF position('''requirements''' IN v_def) = 0 THEN
    v_def := replace(v_def, E'''coverage_confirmed'', v_resolved.coverage_confirmed,',
      E'''coverage_confirmed'', v_resolved.coverage_confirmed, ''service_code'', v_service_code,\n'
      || E'      ''requirements'', (SELECT requirements FROM trustride.service_catalogue WHERE service_id = v_resolved.service_id),');
    IF position('''requirements''' IN v_def) = 0 THEN RAISE EXCEPTION 'service lookup patch did not apply'; END IF;
    EXECUTE v_def;
  END IF;
END;
$patch$;

-- ---------------------------------------------------------------------------
-- 3. Cost: pricing rows aligned with what each service actually dispatches
-- ---------------------------------------------------------------------------
-- Courier services dispatch bodas and bulk cargo dispatches cargo vans
-- (Services' eligibility), but Cost only priced courier on a van, had no row
-- at all for COURIER-DOCUMENT, priced bulk cargo on a light truck, and had no
-- row for three EA services. Each missing row reuses the governed rate card
-- and model already approved for that asset class; nothing is invented.
INSERT INTO trustride.cost_registry (registry_code, macro_domain, service_code, asset_class, jurisdiction, cost_rate_id, cost_model_id, overhead_pct, minimum_margin_pct, statutory_fee_kes, status)
SELECT 'REG-' || n.service_code || '-' || n.asset_class || '-KISUMU', n.macro_domain, n.service_code, n.asset_class::trustride.cost_asset_class_enum, 'KISUMU_COUNTY',
  rate_src.cost_rate_id, rate_src.cost_model_id, dom_src.overhead_pct, dom_src.minimum_margin_pct, dom_src.statutory_fee_kes, 'ACTIVE'
FROM (VALUES
  ('COURIER', 'COURIER-PARCEL', 'BODA_BODA', 'TRANSPORT-BODA-STANDARD', 'COURIER-PARCEL'),
  ('COURIER', 'COURIER-DOCUMENT', 'BODA_BODA', 'TRANSPORT-BODA-STANDARD', 'COURIER-PARCEL'),
  ('DELIVERY', 'DELIVERY-CARGO-BULK', 'VAN_CARGO', 'COURIER-PARCEL', 'DELIVERY-CARGO-BULK'),
  ('EXECUTIVE_ASSISTANTS', 'EA-ERRANDS-GENERAL', 'EXECUTIVE_ASSISTANT_HUMAN', 'EA-SHOPPING-GENERAL', 'EA-SHOPPING-GENERAL'),
  ('EXECUTIVE_ASSISTANTS', 'EA-ERRANDS-SCHOOL_VISITATION', 'EXECUTIVE_ASSISTANT_HUMAN', 'EA-SHOPPING-GENERAL', 'EA-SHOPPING-GENERAL'),
  ('EXECUTIVE_ASSISTANTS', 'EA-DRIVING-STUDENT_PICKUP', 'EXECUTIVE_ASSISTANT_HUMAN', 'EA-DRIVING-GENERAL', 'EA-DRIVING-GENERAL')
) AS n(macro_domain, service_code, asset_class, rate_from_service, policy_from_service)
JOIN trustride.cost_registry rate_src ON rate_src.service_code = n.rate_from_service AND rate_src.jurisdiction = 'KISUMU_COUNTY' AND rate_src.status = 'ACTIVE'
  AND (n.asset_class = 'EXECUTIVE_ASSISTANT_HUMAN' OR rate_src.asset_class::text = n.asset_class)
JOIN trustride.cost_registry dom_src ON dom_src.service_code = n.policy_from_service AND dom_src.jurisdiction = 'KISUMU_COUNTY' AND dom_src.status = 'ACTIVE'
WHERE NOT EXISTS (SELECT 1 FROM trustride.cost_registry x WHERE x.service_code = n.service_code AND x.asset_class::text = n.asset_class
                  AND x.jurisdiction = 'KISUMU_COUNTY' AND x.status = 'ACTIVE');

-- Line-level pricing (G7): each order line is its own calculation; the
-- order's single estimate is their sum, line by line.
ALTER TABLE trustride.fare_calculation ADD COLUMN order_line_id UUID;
CREATE TABLE trustride.fare_quote_line (
  quote_line_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id         UUID NOT NULL REFERENCES trustride.fare_quote (quote_id),
  calculation_id   UUID NOT NULL REFERENCES trustride.fare_calculation (calculation_id),
  order_line_id    UUID,
  line_sequence    SMALLINT NOT NULL,
  line_fare_kes    NUMERIC(18,2) NOT NULL CHECK (line_fare_kes >= 0),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (quote_id, line_sequence)
);
COMMENT ON TABLE trustride.fare_quote_line IS
  '[Trace: Implementation Completion G7] A quote''s per-stop build-up. fare_quote.computed_total_fare_kes is always the sum of its lines.';
ALTER TABLE trustride.fare_quote_line ENABLE ROW LEVEL SECURITY;
CREATE POLICY fare_quote_line_service_write ON trustride.fare_quote_line FOR ALL TO trs026_eng005_cost_service USING (true) WITH CHECK (true);
CREATE POLICY fare_quote_line_requester_read ON trustride.fare_quote_line FOR SELECT TO trustride_authenticated USING (EXISTS (
  SELECT 1 FROM trustride.fare_calculation c WHERE c.calculation_id = fare_quote_line.calculation_id AND c.requester_user_id = auth.uid()));
CREATE POLICY fare_quote_line_office_read ON trustride.fare_quote_line FOR SELECT TO trustride_authenticated
  USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));
GRANT SELECT ON trustride.fare_quote_line TO trustride_authenticated;

-- ---------------------------------------------------------------------------
-- 4. Business: order and job shape
-- ---------------------------------------------------------------------------
ALTER TABLE trustride.business_order
  ADD COLUMN jurisdiction TEXT,
  ADD COLUMN dispatch_mode TEXT NOT NULL DEFAULT 'IMMEDIATE' CHECK (dispatch_mode IN ('IMMEDIATE', 'SCHEDULED')),
  ADD COLUMN requested_start_at TIMESTAMPTZ,
  ADD COLUMN fulfilment_requirements JSONB,
  ADD COLUMN waiting_since TIMESTAMPTZ,
  ADD COLUMN assignment_attempts INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN last_assignment_requested_at TIMESTAMPTZ,
  ADD COLUMN reserved_workforce_unit_id UUID,
  ADD COLUMN declined_unit_ids UUID[] NOT NULL DEFAULT ARRAY[]::UUID[],
  ADD COLUMN status_reason TEXT;

ALTER TABLE trustride.business_job
  ADD COLUMN order_line_id UUID REFERENCES trustride.business_order_line (order_line_id),
  ADD COLUMN line_sequence SMALLINT NOT NULL DEFAULT 1,
  ADD COLUMN acknowledged_at TIMESTAMPTZ,
  ADD COLUMN arrived_at TIMESTAMPTZ,
  ADD COLUMN cancelled_at TIMESTAMPTZ,
  ADD COLUMN status_reason TEXT;
CREATE INDEX idx_business_job_unit_open ON trustride.business_job (workforce_unit_id) WHERE status NOT IN ('VERIFIED', 'CANCELLED', 'FAILED');

-- Operators read the jobs assigned to their own working unit.
CREATE POLICY business_job_operator_read ON trustride.business_job FOR SELECT TO trustride_authenticated USING (EXISTS (
  SELECT 1 FROM trustride.resource_workforce_unit wu WHERE wu.workforce_unit_id = business_job.workforce_unit_id AND wu.operator_user_id = auth.uid()));

-- ---------------------------------------------------------------------------
-- 5. Business: helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_business_config_num(p_key TEXT, p_default NUMERIC)
RETURNS NUMERIC LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT coalesce(nullif(trustride.fn_business_config(p_key), '')::numeric, p_default);
$$;

-- One door for every customer/operator-facing progress event. Presentation
-- renders it (in-app + SMS/WhatsApp through Engine 6).
CREATE OR REPLACE FUNCTION trustride.fn_business_progress_emit(p_order_id UUID, p_event TEXT, p_extra JSONB DEFAULT '{}'::jsonb)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_o RECORD;
  v_operator UUID;
  v_unit UUID;
BEGIN
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = p_order_id;
  v_unit := coalesce((p_extra->>'workforce_unit_id')::uuid,
    (SELECT workforce_unit_id FROM trustride.business_job WHERE order_id = p_order_id AND workforce_unit_id IS NOT NULL ORDER BY created_at DESC LIMIT 1),
    v_o.reserved_workforce_unit_id);
  SELECT operator_user_id INTO v_operator FROM trustride.resource_workforce_unit WHERE workforce_unit_id = v_unit;
  INSERT INTO trustride.business_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v_o.correlation_id, 'TRS026_ENG011_PRESENT', 'ORDER_PROGRESS',
    jsonb_build_object('order_id', v_o.order_id, 'order_code', v_o.order_code, 'service_code', v_o.service_code,
      'requester_user_id', v_o.requester_user_id, 'operator_user_id', v_operator, 'workforce_unit_id', v_unit,
      'event', p_event, 'order_status', v_o.status, 'requested_start_at', v_o.requested_start_at) || coalesce(p_extra, '{}'::jsonb),
    'ORDER_PROGRESS:' || v_o.order_id::text || ':' || p_event || ':' || coalesce(p_extra->>'job_id', '') || ':' || extract(epoch FROM clock_timestamp())::text);
END;
$$;

-- Release whatever worker this order holds (reserved or assigned) and close
-- its open jobs. Used by cancellation, expiry, failure and reassignment.
CREATE OR REPLACE FUNCTION trustride.fn_business_release_assignment(p_order_id UUID, p_reason TEXT, p_close_jobs_as trustride.business_job_status_enum DEFAULT 'CANCELLED')
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_o RECORD;
  v_unit UUID;
BEGIN
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = p_order_id;
  v_unit := coalesce(
    (SELECT workforce_unit_id FROM trustride.business_job WHERE order_id = p_order_id AND status NOT IN ('VERIFIED', 'CANCELLED', 'FAILED') AND workforce_unit_id IS NOT NULL LIMIT 1),
    v_o.reserved_workforce_unit_id);
  UPDATE trustride.business_job SET status = p_close_jobs_as, cancelled_at = now(), status_reason = p_reason
  WHERE order_id = p_order_id AND status NOT IN ('COMPLETED', 'VERIFIED', 'CANCELLED', 'FAILED');
  UPDATE trustride.business_tracking_session SET ended_at = now(), tracking_status = 'ENDED', updated_at = now()
  WHERE job_id IN (SELECT job_id FROM trustride.business_job WHERE order_id = p_order_id) AND ended_at IS NULL;
  IF v_unit IS NOT NULL THEN
    INSERT INTO trustride.business_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (v_o.correlation_id, 'TRS026_ENG002_RESC', 'ASSIGNMENT_RELEASED',
      jsonb_build_object('order_id', p_order_id, 'workforce_unit_id', v_unit, 'reason', p_reason),
      'ASSIGNMENT_RELEASED:' || p_order_id::text || ':' || v_unit::text || ':' || extract(epoch FROM clock_timestamp())::text);
  END IF;
  UPDATE trustride.business_order SET reserved_workforce_unit_id = NULL, updated_at = now() WHERE order_id = p_order_id;
  RETURN v_unit;
END;
$$;

-- Close an order in a terminal state, release its resources, cancel its
-- unaccepted/unused price, and tell everyone concerned.
CREATE OR REPLACE FUNCTION trustride.fn_business_order_close(p_order_id UUID, p_status trustride.business_order_status_enum, p_reason TEXT, p_event TEXT, p_notify_office BOOLEAN DEFAULT FALSE)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_o RECORD;
BEGIN
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = p_order_id FOR UPDATE;
  IF v_o.status IN ('SETTLED', 'REVIEWED', 'CLOSED', 'CANCELLED', 'EXPIRED', 'FAILED', 'DECLINED') THEN
    RETURN;
  END IF;
  PERFORM trustride.fn_business_release_assignment(p_order_id, p_reason, CASE WHEN p_status = 'FAILED' THEN 'FAILED' ELSE 'CANCELLED' END::trustride.business_job_status_enum);
  IF v_o.quote_id IS NOT NULL THEN
    BEGIN
      PERFORM trustride.fn_cost_quote_cancel(v_o.quote_id);
    EXCEPTION WHEN OTHERS THEN NULL;  -- already expired/finalized: nothing to cancel
    END;
  END IF;
  UPDATE trustride.business_order SET status = p_status, status_reason = p_reason, closed_at = now(), updated_at = now() WHERE order_id = p_order_id;
  PERFORM trustride.fn_audit_log_append('business_order', p_order_id, 'ORDER_' || p_status::text, NULL, 'SYSTEM', NULL, NULL,
    jsonb_build_object('from', v_o.status), jsonb_build_object('reason', p_reason));
  PERFORM trustride.fn_business_progress_emit(p_order_id, p_event, jsonb_build_object('reason', p_reason, 'notify_office', p_notify_office,
    'workforce_unit_id', coalesce(v_o.reserved_workforce_unit_id,
      (SELECT workforce_unit_id FROM trustride.business_job WHERE order_id = p_order_id AND workforce_unit_id IS NOT NULL LIMIT 1))));
END;
$$;

-- An estimate the customer has not accepted is withdrawn when the matched
-- worker changes; an accepted (locked) price is kept.
CREATE OR REPLACE FUNCTION trustride.fn_business_withdraw_unaccepted_quote(p_order_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_q UUID;
BEGIN
  SELECT q.quote_id INTO v_q FROM trustride.business_order o JOIN trustride.fare_quote q ON q.quote_id = o.quote_id
  WHERE o.order_id = p_order_id AND q.quote_state = 'FARE_ESTIMATED';
  IF v_q IS NOT NULL THEN
    PERFORM trustride.fn_cost_quote_cancel(v_q);
    UPDATE trustride.business_order SET quote_id = NULL WHERE order_id = p_order_id;
  END IF;
END;
$$;

-- Is this local time inside a working window (Founder calendar)?
CREATE OR REPLACE FUNCTION trustride.fn_business_is_working_time(p_at TIMESTAMPTZ)
RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_open TIMESTAMPTZ;
  v_close TIMESTAMPTZ;
BEGIN
  SELECT window_open, window_close INTO v_open, v_close FROM trustride.fn_business_working_window((p_at AT TIME ZONE 'Africa/Nairobi')::date);
  RETURN v_open IS NOT NULL AND p_at >= v_open AND p_at <= v_close;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Business: placing a service order (RAISE_INTENT)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_business_service_order_place(p_requester UUID, p_payload JSONB, p_correlation_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_service RECORD;
  v_req JSONB;
  v_lines JSONB := '[]'::jsonb;
  v_line JSONB;
  v_scope JSONB;
  v_route RECORD;
  v_jurisdiction TEXT := coalesce(nullif(p_payload->>'jurisdiction', ''), 'KISUMU_COUNTY');
  v_start TIMESTAMPTZ := (p_payload->>'requested_start_at')::timestamptz;
  v_mode TEXT := 'IMMEDIATE';
  v_effective_start TIMESTAMPTZ;
  v_shift TEXT;
  v_day_from TIME;
  v_day_to TIME;
  v_hours NUMERIC;
  v_order UUID;
  v_n INT;
BEGIN
  SELECT sc.service_id, sc.service_code, sc.service_name, sc.requirements, sm.domain_code::text AS macro_domain
  INTO v_service FROM trustride.service_catalogue sc JOIN trustride.service_macro_domain sm ON sm.macro_domain_id = sc.macro_domain_id
  WHERE sc.service_code = p_payload->>'service_code' AND sc.status = 'ACTIVE';
  IF v_service.service_id IS NULL THEN
    RAISE EXCEPTION 'That service is not available';
  END IF;
  v_req := coalesce(v_service.requirements, '{}'::jsonb);
  IF coalesce(v_req->>'fulfilment', 'DISPATCH') <> 'DISPATCH' THEN
    RAISE EXCEPTION '% is requested through %, not a service order', v_service.service_name, coalesce(v_req->>'command', 'its own screen');
  END IF;
  IF v_jurisdiction NOT IN (SELECT unnest(enum_range(NULL::trustride.cost_jurisdiction_enum))::text) THEN
    RAISE EXCEPTION 'TrustRide does not operate in % yet', v_jurisdiction;
  END IF;
  -- Payment is by M-Pesa from the customer's verified phone (D3): an order
  -- that could never be paid is refused up front, not discovered at the end.
  IF trustride.fn_user_payment_msisdn(p_requester) IS NULL THEN
    RAISE EXCEPTION 'Add and verify your phone number first -- it is the M-Pesa number your order is paid from';
  END IF;

  v_n := jsonb_array_length(coalesce(p_payload->'order_lines', '[]'::jsonb));
  IF v_n < 1 THEN RAISE EXCEPTION 'Add at least one stop'; END IF;
  IF v_n > trustride.fn_business_config_num('ORDER_MAX_LINES', 5) THEN
    RAISE EXCEPTION 'At most % stops per order', trustride.fn_business_config_num('ORDER_MAX_LINES', 5);
  END IF;

  -- When: immediate, scheduled, or held for the first shift.
  IF v_start IS NOT NULL THEN
    IF v_start < now() + interval '15 minutes' THEN
      RAISE EXCEPTION 'A scheduled time must be at least 15 minutes from now';
    END IF;
    IF v_start > now() + make_interval(days => trustride.fn_business_config_num('SCHEDULE_MAX_DAYS_AHEAD', 14)::int) THEN
      RAISE EXCEPTION 'You can schedule up to % days ahead', trustride.fn_business_config_num('SCHEDULE_MAX_DAYS_AHEAD', 14);
    END IF;
    IF NOT trustride.fn_business_is_working_time(v_start) THEN
      RAISE EXCEPTION 'TrustRide serves Mon-Fri 05:00-22:00 and Sat 06:00-23:00 (Sunday closed) -- choose a time within those hours';
    END IF;
    v_mode := 'SCHEDULED';
    v_effective_start := v_start;
  ELSE
    v_effective_start := trustride.fn_business_next_working_open(now());  -- = now() when open; else the first shift
  END IF;

  -- Executive Assistant shift (D1: Sunday/holiday never applies).
  IF v_service.macro_domain = 'EXECUTIVE_ASSISTANTS' THEN
    v_day_from := split_part(coalesce(trustride.fn_business_config('EA_DAY_SHIFT_WINDOW'), '06:00-19:00'), '-', 1)::time;
    v_day_to := split_part(coalesce(trustride.fn_business_config('EA_DAY_SHIFT_WINDOW'), '06:00-19:00'), '-', 2)::time;
    v_shift := CASE WHEN (v_effective_start AT TIME ZONE 'Africa/Nairobi')::time >= v_day_from
                     AND (v_effective_start AT TIME ZONE 'Africa/Nairobi')::time < v_day_to THEN 'DAY' ELSE 'NIGHT' END;
  END IF;

  -- Each stop: validated, and for trips the platform computes the distance
  -- and duration through Engine 6's routing port (G14) -- never typed in.
  FOR v_line IN SELECT * FROM jsonb_array_elements(p_payload->'order_lines') LOOP
    v_scope := coalesce(v_line->'scope_detail', '{}'::jsonb);
    IF v_scope->>'origin_zone_code' IS NULL OR NOT EXISTS (
         SELECT 1 FROM trustride.cost_operational_zones WHERE zone_code = v_scope->>'origin_zone_code' AND active) THEN
      RAISE EXCEPTION 'Choose where the service starts (a TrustRide service zone)';
    END IF;
    IF v_service.macro_domain = 'EXECUTIVE_ASSISTANTS' THEN
      v_hours := (v_scope->>'billed_hours')::numeric;
      IF v_hours IS NULL OR v_hours < 1 OR v_hours > 12 THEN
        RAISE EXCEPTION 'Say how many hours you need (1 to 12)';
      END IF;
      v_scope := v_scope || jsonb_build_object('destination_zone_code', v_scope->>'origin_zone_code', 'billed_hours', v_hours,
        'shift_type', v_shift, 'ea_skill_category', v_req->>'ea_skill_category', 'jurisdiction', v_jurisdiction);
    ELSE
      IF v_scope->>'destination_zone_code' IS NULL OR NOT EXISTS (
           SELECT 1 FROM trustride.cost_operational_zones WHERE zone_code = v_scope->>'destination_zone_code' AND active) THEN
        RAISE EXCEPTION 'Choose where the trip ends (a TrustRide service zone)';
      END IF;
      SELECT * INTO v_route FROM trustride.fn_integration_routing_compute(v_scope->>'origin_zone_code', v_scope->>'destination_zone_code', p_correlation_id);
      v_scope := v_scope || jsonb_build_object('distance_km', v_route.distance_km, 'duration_min', v_route.duration_min,
        'routing_request_id', v_route.routing_request_id, 'distance_source', 'ENGINE6_ROUTING', 'jurisdiction', v_jurisdiction);
    END IF;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'line_description', coalesce(nullif(v_line->>'line_description', ''), v_service.service_name),
      'quantity', coalesce((v_line->>'quantity')::numeric, 1), 'scope_detail', v_scope));
  END LOOP;

  v_order := trustride.fn_business_order_place(p_requester, coalesce(nullif(p_payload->>'user_type_domain', ''), 'CUSTOMER')::trustride.business_user_type_domain_enum,
    v_service.service_code, v_service.macro_domain, v_lines, 'SERVICE_ORDER', v_jurisdiction, p_correlation_id);
  UPDATE trustride.business_order
  SET jurisdiction = v_jurisdiction, dispatch_mode = v_mode, requested_start_at = v_effective_start, service_id = v_service.service_id
  WHERE order_id = v_order;
  RETURN v_order;
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. Business: SERVICE_RESOLVED -> hold, decline, fail, or request a worker
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_business_assignment_request(p_order_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
DECLARE
  v_o RECORD;
  v_line RECORD;
  v_lat NUMERIC;
  v_lon NUMERIC;
BEGIN
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = p_order_id FOR UPDATE;
  SELECT * INTO v_line FROM trustride.business_order_line WHERE order_id = p_order_id ORDER BY line_sequence LIMIT 1;
  SELECT ST_Y(ST_Centroid(boundary)), ST_X(ST_Centroid(boundary)) INTO v_lat, v_lon
  FROM trustride.cost_operational_zones WHERE zone_code = v_line.scope_detail->>'origin_zone_code' AND active;
  IF v_lat IS NULL THEN
    PERFORM trustride.fn_business_order_close(p_order_id, 'FAILED', 'Pickup zone ' || coalesce(v_line.scope_detail->>'origin_zone_code', '?') || ' is not an active service zone', 'FAILED', TRUE);
    RETURN;
  END IF;
  UPDATE trustride.business_order
  SET status = CASE WHEN status = 'WAITING' THEN status ELSE 'VALIDATED' END,
      order_stage = 'ASSIGNMENT_VALIDATION_JOB_CREATION',
      assignment_attempts = assignment_attempts + 1, last_assignment_requested_at = now(), updated_at = now()
  WHERE order_id = p_order_id;
  INSERT INTO trustride.business_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v_o.correlation_id, 'TRS026_ENG002_RESC', 'ASSIGNMENT_REQUESTED',
    jsonb_build_object('order_id', p_order_id, 'order_line_id', v_line.order_line_id, 'macro_domain', v_o.macro_domain,
      'required_capacity_class', v_o.fulfilment_requirements->>'required_capacity_class_code',
      'required_vetting_tier', coalesce(v_o.fulfilment_requirements->>'required_vetting_tier', 'STANDARD'),
      'required_certifications', coalesce(v_o.fulfilment_requirements->'required_certifications', '[]'::jsonb),
      'jurisdiction', v_o.jurisdiction, 'excluded_unit_ids', to_jsonb(v_o.declined_unit_ids),
      'pickup_location', jsonb_build_object('latitude', v_lat, 'longitude', v_lon), 'attempt', v_o.assignment_attempts + 1),
    'ASSIGNMENT_REQUESTED:' || p_order_id::text || ':' || (v_o.assignment_attempts + 1)::text);
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_service_resolved_accept(p_signal_id uuid)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_corr UUID;
  v_o RECORD;
  v_req JSONB;
  v_lead INTERVAL;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_corr FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'fn_business_service_resolved_accept: no RECEIVED signal %', p_signal_id; END IF;

  SELECT * INTO v_o FROM trustride.business_order WHERE correlation_id = v_corr AND order_root_type = 'SERVICE_ORDER' ORDER BY created_at DESC LIMIT 1;
  IF v_o.order_id IS NULL THEN
    UPDATE trustride.business_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'NO_SERVICE_ORDER_FOR_CORRELATION', accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END IF;
  IF v_o.status <> 'PLACED' THEN  -- cancelled meanwhile
    UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('ignored', 'ORDER_' || v_o.status) WHERE signal_id = p_signal_id;
    RETURN 'ACCEPTED';
  END IF;

  v_req := coalesce(v_payload->'requirements', '{}'::jsonb) || coalesce(v_payload->'eligibility', '{}'::jsonb);
  UPDATE trustride.business_order SET service_id = coalesce((v_payload->>'service_id')::uuid, service_id), fulfilment_requirements = v_req, updated_at = now()
  WHERE order_id = v_o.order_id;

  IF NOT coalesce((v_payload->>'coverage_confirmed')::boolean, false) THEN
    PERFORM trustride.fn_business_order_close(v_o.order_id, 'DECLINED', 'Not yet offered in ' || coalesce(v_o.jurisdiction, 'this area'), 'DECLINED');
  ELSIF coalesce(v_req->>'fulfilment', 'DISPATCH') <> 'DISPATCH' OR v_req->>'required_capacity_class_code' IS NULL THEN
    PERFORM trustride.fn_business_order_close(v_o.order_id, 'FAILED', 'This service is not dispatched; it has its own request path', 'FAILED', TRUE);
  ELSE
    v_lead := make_interval(mins => trustride.fn_business_config_num('SCHEDULED_DISPATCH_LEAD_MIN', 30)::int);
    IF v_o.requested_start_at IS NOT NULL AND v_o.requested_start_at - v_lead > now() THEN
      UPDATE trustride.business_order SET status = 'SCHEDULED', order_stage = 'SCHEDULED_HOLD', updated_at = now() WHERE order_id = v_o.order_id;
      PERFORM trustride.fn_business_progress_emit(v_o.order_id, 'SCHEDULED',
        jsonb_build_object('first_shift', v_o.dispatch_mode = 'IMMEDIATE'));
    ELSE
      PERFORM trustride.fn_business_assignment_request(v_o.order_id);
    END IF;
  END IF;

  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

-- ---------------------------------------------------------------------------
-- 8. Resources: eligible matching; "no" travels back (G4, G15)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_resource_assignment_requested_accept(p_signal_id uuid)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_corr UUID;
  v_class trustride.resource_capacity_class_enum;
  v_best UUID;
  v_excluded UUID[];
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_corr FROM trustride.resource_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'fn_resource_assignment_requested_accept: no RECEIVED signal %', p_signal_id; END IF;
  v_class := (v_payload->>'required_capacity_class')::trustride.resource_capacity_class_enum;
  v_excluded := ARRAY(SELECT jsonb_array_elements_text(coalesce(v_payload->'excluded_unit_ids', '[]'::jsonb))::uuid);

  SELECT d.workforce_unit_id INTO v_best
  FROM trustride.fn_resource_discover_eligible(v_class, (v_payload->'pickup_location'->>'latitude')::numeric, (v_payload->'pickup_location'->>'longitude')::numeric,
    v_payload->>'required_vetting_tier', v_payload->'required_certifications', v_payload->>'jurisdiction') d
  WHERE d.workforce_unit_id <> ALL (v_excluded)
  LIMIT 1;

  IF v_best IS NULL THEN
    INSERT INTO trustride.resource_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (v_corr, 'TRS026_ENG004_BUS', 'RESOURCE_UNAVAILABLE',
      jsonb_build_object('order_id', v_payload->>'order_id', 'required_capacity_class', v_class, 'attempt', v_payload->>'attempt',
        'units_on_duty', (SELECT count(*) FROM trustride.resource_workforce_unit wu JOIN trustride.resource_capacity_class cc ON cc.capacity_class_id = wu.capacity_class_id
                          WHERE cc.class_code = v_class AND wu.unit_status = 'ACTIVE'
                            AND trustride.fn_resource_unit_availability(wu.workforce_unit_id) IN ('AVAILABLE', 'RESERVED', 'ASSIGNED'))),
      'RESOURCE_UNAVAILABLE:' || (v_payload->>'order_id') || ':' || coalesce(v_payload->>'attempt', '1'));
    UPDATE trustride.resource_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('outcome', 'RESOURCE_UNAVAILABLE')
    WHERE signal_id = p_signal_id;
    RETURN 'ACCEPTED';
  END IF;

  PERFORM trustride.fn_resource_reserve(v_best, (v_payload->>'order_id')::uuid, v_corr, '00000000-0000-0000-0000-000000000000'::uuid, (v_payload->>'order_line_id')::uuid);
  UPDATE trustride.resource_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('workforce_unit_id', v_best)
  WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

-- Business released this order's worker: back to the pool (still on duty).
CREATE OR REPLACE FUNCTION trustride.fn_resource_assignment_released_accept(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_unit UUID;
  v_state trustride.resource_availability_state_enum;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.resource_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'no RECEIVED signal %', p_signal_id; END IF;
  v_unit := (v_payload->>'workforce_unit_id')::uuid;
  v_state := trustride.fn_resource_unit_availability(v_unit);
  IF v_state IN ('RESERVED', 'ASSIGNED') AND EXISTS (
       SELECT 1 FROM trustride.resource_availability_ledger WHERE resource_type = 'WORKFORCE_UNIT' AND resource_ref_id = v_unit
         AND effective_to IS NULL AND job_ref_id = (v_payload->>'order_id')::uuid) THEN
    PERFORM trustride.fn_resource_availability_move('WORKFORCE_UNIT', v_unit, 'AVAILABLE', 'RELEASED: ' || coalesce(v_payload->>'reason', ''), NULL);
  END IF;
  UPDATE trustride.resource_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('previous_state', v_state)
  WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

-- Assignment confirmation now carries the whole order context into the
-- dispatch signal Cost prices from (G5, G7).
CREATE OR REPLACE FUNCTION trustride.fn_resource_assignment_confirmed_accept(p_signal_id uuid)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_corr UUID;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_corr FROM trustride.resource_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'fn_resource_assignment_confirmed_accept: no RECEIVED signal %', p_signal_id; END IF;
  IF trustride.fn_resource_unit_availability((v_payload->>'workforce_unit_id')::uuid) <> 'RESERVED' THEN
    UPDATE trustride.resource_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'UNIT_NO_LONGER_RESERVED', accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END IF;
  PERFORM trustride.fn_resource_assign(
    (v_payload->>'workforce_unit_id')::uuid, (v_payload->>'order_id')::uuid, v_corr, '00000000-0000-0000-0000-000000000000'::uuid,
    v_payload->>'origin_zone_code', v_payload->>'destination_zone_code',
    (v_payload->>'distance_km')::numeric, (v_payload->>'duration_min')::numeric,
    (v_payload->>'requester_user_id')::uuid, v_payload->>'jurisdiction', v_payload->>'engine_capacity',
    (v_payload->>'order_line_id')::uuid,
    jsonb_strip_nulls(jsonb_build_object('lines', v_payload->'lines', 'ea_skill_category', v_payload->>'ea_skill_category',
      'billed_hours', v_payload->>'billed_hours', 'shift_type', v_payload->>'shift_type', 'queue_wait_min', v_payload->>'queue_wait_min',
      'transit_delivery_fee_kes', v_payload->>'transit_delivery_fee_kes', 'existing_quote_id', v_payload->>'existing_quote_id',
      'service_code', v_payload->>'service_code'))
  );
  UPDATE trustride.resource_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

-- ---------------------------------------------------------------------------
-- 9. Business: unavailable -> WAITING; reserved -> confirm with full context
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_business_resource_unavailable_accept(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_o RECORD;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'no RECEIVED signal %', p_signal_id; END IF;
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = (v_payload->>'order_id')::uuid FOR UPDATE;
  IF v_o.status IN ('VALIDATED', 'WAITING') THEN
    UPDATE trustride.business_order SET status = 'WAITING', order_stage = 'RESOURCE_AVAILABILITY',
      waiting_since = coalesce(waiting_since, now()), status_reason = 'No ' || coalesce(v_payload->>'required_capacity_class', 'resource') || ' free yet', updated_at = now()
    WHERE order_id = v_o.order_id;
    IF v_o.status <> 'WAITING' THEN  -- tell the customer once, not every retry
      PERFORM trustride.fn_business_progress_emit(v_o.order_id, 'WAITING', jsonb_build_object('required_capacity_class', v_payload->>'required_capacity_class',
        'max_wait_min', trustride.fn_business_config_num('ORDER_WAIT_MAX_MIN', 30)));
    END IF;
  END IF;
  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_resource_reserved_accept(p_signal_id uuid)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_corr UUID;
  v_o RECORD;
  v_unit UUID;
  v_first RECORD;
  v_lines JSONB;
  v_bad INT;
  v_existing_quote UUID;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_corr FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'fn_business_resource_reserved_accept: no RECEIVED signal %', p_signal_id; END IF;
  v_unit := (v_payload->>'workforce_unit_id')::uuid;
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = (v_payload->>'order_id')::uuid FOR UPDATE;

  -- The order moved on while the worker was being reserved (cancelled,
  -- expired): hand the worker straight back.
  IF v_o.status NOT IN ('VALIDATED', 'WAITING') THEN
    UPDATE trustride.business_order SET reserved_workforce_unit_id = v_unit WHERE order_id = v_o.order_id;
    PERFORM trustride.fn_business_release_assignment(v_o.order_id, 'ORDER_' || v_o.status::text);
    UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('released', true) WHERE signal_id = p_signal_id;
    RETURN 'ACCEPTED';
  END IF;

  UPDATE trustride.business_order SET reserved_workforce_unit_id = v_unit, waiting_since = NULL, updated_at = now() WHERE order_id = v_o.order_id;

  SELECT count(*) INTO v_bad FROM trustride.business_order_line l
  WHERE l.order_id = v_o.order_id AND (l.scope_detail->>'origin_zone_code' IS NULL OR l.scope_detail->>'destination_zone_code' IS NULL
    OR (v_o.macro_domain <> 'EXECUTIVE_ASSISTANTS' AND (l.scope_detail->>'distance_km' IS NULL OR l.scope_detail->>'duration_min' IS NULL))
    OR (v_o.macro_domain = 'EXECUTIVE_ASSISTANTS' AND l.scope_detail->>'billed_hours' IS NULL));
  IF v_bad > 0 THEN
    -- Never leave the worker reserved behind a broken order (G5).
    PERFORM trustride.fn_business_order_close(v_o.order_id, 'FAILED', 'Order scope incomplete -- a stop is missing its zones, distance or hours', 'FAILED', TRUE);
    UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('failed', 'ORDER_LINE_MISSING_SCOPE') WHERE signal_id = p_signal_id;
    RETURN 'ACCEPTED';
  END IF;

  SELECT * INTO v_first FROM trustride.business_order_line WHERE order_id = v_o.order_id ORDER BY line_sequence LIMIT 1;
  SELECT jsonb_agg(jsonb_build_object('order_line_id', l.order_line_id, 'line_sequence', l.line_sequence,
           'origin_zone_code', l.scope_detail->>'origin_zone_code', 'destination_zone_code', l.scope_detail->>'destination_zone_code',
           'distance_km', l.scope_detail->>'distance_km', 'duration_min', l.scope_detail->>'duration_min',
           'engine_capacity', l.scope_detail->>'engine_capacity', 'billed_hours', l.scope_detail->>'billed_hours',
           'shift_type', l.scope_detail->>'shift_type') ORDER BY l.line_sequence)
  INTO v_lines FROM trustride.business_order_line l WHERE l.order_id = v_o.order_id;

  -- A reassignment after the customer already accepted keeps that price.
  SELECT q.quote_id INTO v_existing_quote FROM trustride.fare_quote q WHERE q.quote_id = v_o.quote_id AND q.quote_state = 'FARE_LOCKED';

  INSERT INTO trustride.business_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v_corr, 'TRS026_ENG002_RESC', 'RESOURCE_ASSIGNMENT_CONFIRMED',
    jsonb_strip_nulls(jsonb_build_object(
      'order_id', v_o.order_id, 'order_line_id', v_first.order_line_id, 'workforce_unit_id', v_unit, 'service_code', v_o.service_code,
      'origin_zone_code', v_first.scope_detail->>'origin_zone_code', 'destination_zone_code', v_first.scope_detail->>'destination_zone_code',
      'distance_km', v_first.scope_detail->>'distance_km', 'duration_min', v_first.scope_detail->>'duration_min',
      'requester_user_id', v_o.requester_user_id, 'jurisdiction', v_o.jurisdiction,
      'engine_capacity', coalesce(v_first.scope_detail->>'engine_capacity', CASE WHEN v_payload->>'capacity_class' = 'BODA_BODA' THEN 'CC_125' ELSE 'NOT_APPLICABLE' END),
      'lines', v_lines,
      'ea_skill_category', v_o.fulfilment_requirements->>'ea_skill_category', 'billed_hours', v_first.scope_detail->>'billed_hours',
      'shift_type', v_first.scope_detail->>'shift_type', 'queue_wait_min', 0, 'transit_delivery_fee_kes', 0,
      'existing_quote_id', v_existing_quote)),
    'RESOURCE_ASSIGNMENT_CONFIRMED:' || v_o.order_id::text || ':' || v_unit::text || ':' || v_o.assignment_attempts::text);

  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

-- RESOURCE_ASSIGNED: one job per order line, same working unit, in order.
CREATE OR REPLACE FUNCTION trustride.fn_business_resource_assigned_accept(p_signal_id uuid)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_o RECORD;
  v_unit UUID;
  v_n INT;
  v_locked BOOLEAN;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'fn_business_resource_assigned_accept: no RECEIVED signal %', p_signal_id; END IF;
  v_unit := (v_payload->>'workforce_unit_id')::uuid;
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = (v_payload->>'order_id')::uuid FOR UPDATE;
  IF v_o.status NOT IN ('VALIDATED', 'WAITING') THEN
    PERFORM trustride.fn_business_release_assignment(v_o.order_id, 'ORDER_' || v_o.status::text);
    UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('released', true) WHERE signal_id = p_signal_id;
    RETURN 'ACCEPTED';
  END IF;

  INSERT INTO trustride.business_job (order_id, order_line_id, line_sequence, job_type, scheduled_window_start, scheduled_window_end, workforce_unit_id)
  SELECT v_o.order_id, l.order_line_id, l.line_sequence,
    CASE WHEN v_o.dispatch_mode = 'SCHEDULED' THEN 'SCHEDULED' ELSE 'IMMEDIATE' END::trustride.business_job_type_enum,
    CASE WHEN v_o.dispatch_mode = 'SCHEDULED' THEN v_o.requested_start_at END,
    CASE WHEN v_o.dispatch_mode = 'SCHEDULED' THEN v_o.requested_start_at + interval '2 hours' END,
    v_unit
  FROM trustride.business_order_line l WHERE l.order_id = v_o.order_id ORDER BY l.line_sequence;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  v_locked := EXISTS (SELECT 1 FROM trustride.fare_quote WHERE quote_id = v_o.quote_id AND quote_state = 'FARE_LOCKED');
  UPDATE trustride.business_order SET status = 'JOB_CREATED',
    order_stage = (CASE WHEN v_locked THEN 'DISPATCH' ELSE 'QUOTATION_ACCEPTANCE' END)::trustride.business_order_stage_enum,
    reserved_workforce_unit_id = v_unit, updated_at = now()
  WHERE order_id = v_o.order_id;
  IF v_locked THEN
    -- Reassigned after the customer accepted: the new operator is told now.
    PERFORM trustride.fn_business_progress_emit(v_o.order_id, 'FARE_ACCEPTED', jsonb_build_object('workforce_unit_id', v_unit, 'reassigned', true));
  END IF;

  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('jobs_created', v_n) WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

-- ---------------------------------------------------------------------------
-- 10. Cost: price every line; issue an estimate; never auto-lock (D2)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_cost_resource_dispatch_initiated_accept(p_signal_id uuid)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_corr UUID;
  v_context RECORD;
  v_asset trustride.cost_asset_class_enum;
  v_jur trustride.cost_jurisdiction_enum;
  v_lines JSONB;
  v_line JSONB;
  v_routing RECORD;
  v_calc UUID;
  v_first_calc UUID;
  v_calcs UUID[] := ARRAY[]::UUID[];
  v_line_ids UUID[] := ARRAY[]::UUID[];
  v_seqs SMALLINT[] := ARRAY[]::SMALLINT[];
  v_total NUMERIC(18,2) := 0;
  v_quote UUID;
  v_quote_code TEXT;
  v_prev_hash CHAR(64);
  v_hash CHAR(64);
  v_expires TIMESTAMPTZ;
  v_service_code TEXT;
  i INT;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_corr FROM trustride.cost_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'fn_cost_resource_dispatch_initiated_accept: no RECEIVED signal %', p_signal_id; END IF;

  -- A reassignment after the customer accepted keeps the accepted price.
  IF v_payload->>'existing_quote_id' IS NOT NULL THEN
    UPDATE trustride.cost_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(),
      payload_out = jsonb_build_object('reused_quote_id', v_payload->>'existing_quote_id') WHERE signal_id = p_signal_id;
    RETURN 'ACCEPTED';
  END IF;

  SELECT * INTO v_context FROM trustride.cost_pending_service_context WHERE correlation_id = v_corr;
  v_service_code := coalesce(v_context.service_code, v_payload->>'service_code');
  IF v_service_code IS NULL THEN
    UPDATE trustride.cost_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'NO_SERVICE_CONTEXT_CACHED', accepted_at = now() WHERE signal_id = p_signal_id;
    INSERT INTO trustride.cost_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (v_corr, 'TRS026_ENG004_BUS', 'FARE_CALCULATION_FAILED',
      jsonb_build_object('order_id', v_payload->>'order_id', 'reason', 'No service context for pricing'), 'FARE_CALCULATION_FAILED:' || p_signal_id::text);
    RETURN 'REJECTED';
  END IF;

  v_asset := (v_payload->>'asset_class')::trustride.cost_asset_class_enum;
  v_jur := coalesce(nullif(v_payload->>'jurisdiction', ''), 'KISUMU_COUNTY')::trustride.cost_jurisdiction_enum;
  v_lines := coalesce(v_payload->'lines', jsonb_build_array(jsonb_build_object('order_line_id', v_payload->>'order_line_id', 'line_sequence', 1,
    'origin_zone_code', v_payload->>'origin_zone_code', 'destination_zone_code', v_payload->>'destination_zone_code',
    'distance_km', v_payload->>'distance_km', 'duration_min', v_payload->>'duration_min', 'engine_capacity', v_payload->>'engine_capacity',
    'billed_hours', v_payload->>'billed_hours', 'shift_type', v_payload->>'shift_type')));

  BEGIN
    FOR v_line IN SELECT * FROM jsonb_array_elements(v_lines) LOOP
      IF v_asset = 'EXECUTIVE_ASSISTANT_HUMAN' THEN
        v_calc := trustride.fn_cost_ea_labor_calculate(
          (v_payload->>'ea_skill_category')::trustride.ea_skill_category_enum, v_jur,
          coalesce(v_line->>'origin_zone_code', v_payload->>'origin_zone_code'),
          coalesce((v_line->>'billed_hours')::numeric, (v_payload->>'billed_hours')::numeric),
          coalesce(v_line->>'shift_type', v_payload->>'shift_type')::trustride.cost_shift_type_enum,
          coalesce((v_payload->>'queue_wait_min')::numeric, 0), coalesce((v_payload->>'transit_delivery_fee_kes')::numeric, 0),
          (v_payload->>'requester_user_id')::uuid, v_corr, (v_payload->>'order_id')::uuid, (v_payload->>'assignment_id')::uuid, v_service_code);
      ELSE
        BEGIN
          SELECT * INTO v_routing FROM trustride.fn_integration_routing_compute(v_line->>'origin_zone_code', v_line->>'destination_zone_code', v_corr);
        EXCEPTION WHEN OTHERS THEN
          v_routing := NULL;
        END;
        v_calc := trustride.fn_cost_fare_calculate(
          coalesce(v_context.macro_domain, v_payload->>'macro_domain'), v_service_code, v_asset,
          coalesce(nullif(v_line->>'engine_capacity', '')::trustride.cost_engine_capacity_enum, CASE WHEN v_asset = 'BODA_BODA' THEN 'CC_125'::trustride.cost_engine_capacity_enum ELSE 'NOT_APPLICABLE' END),
          v_jur, v_line->>'origin_zone_code', v_line->>'destination_zone_code',
          coalesce(v_routing.distance_km, (v_line->>'distance_km')::numeric, 0),
          coalesce(v_routing.duration_min, (v_line->>'duration_min')::numeric, 0),
          (v_payload->>'requester_user_id')::uuid, 'CUSTOMER', v_corr, (v_payload->>'order_id')::uuid, (v_payload->>'assignment_id')::uuid,
          NULL, 0, NULL, v_routing.terrain_multiplier);
      END IF;
      UPDATE trustride.fare_calculation SET order_line_id = (v_line->>'order_line_id')::uuid WHERE calculation_id = v_calc;
      v_calcs := v_calcs || v_calc;
      v_line_ids := v_line_ids || (v_line->>'order_line_id')::uuid;
      v_seqs := v_seqs || coalesce((v_line->>'line_sequence')::smallint, (array_length(v_calcs, 1))::smallint);
      v_total := v_total + (SELECT computed_total_fare_kes FROM trustride.fare_calculation WHERE calculation_id = v_calc);
    END LOOP;

    -- One estimate for the order: the sum of its lines.
    v_first_calc := v_calcs[1];
    v_quote_code := trustride.fn_sequence_next('TRS026-QUOTE');
    v_expires := now() + make_interval(mins => coalesce(nullif(trustride.fn_business_config('QUOTE_ACCEPTANCE_WINDOW_MIN'), '')::int, 10));
    SELECT quote_hash INTO v_prev_hash FROM trustride.fare_quote ORDER BY created_at DESC LIMIT 1;
    v_hash := encode(extensions.digest(coalesce(v_prev_hash, '') || v_quote_code || v_total::text || now()::text, 'sha256'), 'hex');
    INSERT INTO trustride.fare_quote (calculation_id, quote_code, computed_total_fare_kes, currency, quote_hash, prev_quote_hash, expires_at, correlation_id)
    VALUES (v_first_calc, v_quote_code, v_total, 'KES', v_hash, v_prev_hash, v_expires, v_corr)
    RETURNING quote_id INTO v_quote;
    FOR i IN 1..array_length(v_calcs, 1) LOOP
      INSERT INTO trustride.fare_quote_line (quote_id, calculation_id, order_line_id, line_sequence, line_fare_kes)
      VALUES (v_quote, v_calcs[i], v_line_ids[i], v_seqs[i], (SELECT computed_total_fare_kes FROM trustride.fare_calculation WHERE calculation_id = v_calcs[i]));
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    UPDATE trustride.cost_event_inbox SET signal_status = 'REJECTED', rejection_reason = SQLERRM, accepted_at = now() WHERE signal_id = p_signal_id;
    -- The "no" travels back: Business releases the worker and tells the customer (G5).
    INSERT INTO trustride.cost_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (v_corr, 'TRS026_ENG004_BUS', 'FARE_CALCULATION_FAILED',
      jsonb_build_object('order_id', v_payload->>'order_id', 'reason', SQLERRM), 'FARE_CALCULATION_FAILED:' || p_signal_id::text);
    RETURN 'REJECTED';
  END;

  DELETE FROM trustride.cost_pending_service_context WHERE correlation_id = v_corr;
  INSERT INTO trustride.cost_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v_corr, 'TRS026_ENG004_BUS', 'FARE_QUOTED',
    jsonb_build_object('order_id', v_payload->>'order_id', 'quote_id', v_quote, 'quote_code', v_quote_code, 'computed_total_fare_kes', v_total,
      'currency', 'KES', 'expires_at', v_expires, 'line_count', array_length(v_calcs, 1)),
    'FARE_QUOTED:' || v_quote::text);
  UPDATE trustride.cost_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(),
    payload_out = jsonb_build_object('quote_id', v_quote, 'calculations', to_jsonb(v_calcs)) WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

-- Expired estimates now travel back to Business.
CREATE OR REPLACE FUNCTION trustride.fn_cost_quote_expire_sweep()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  r RECORD;
  n INTEGER := 0;
BEGIN
  FOR r IN
    UPDATE trustride.fare_quote q SET quote_state = 'EXPIRED'
    WHERE q.quote_state = 'FARE_ESTIMATED' AND q.expires_at < now()
    RETURNING q.quote_id, q.correlation_id, (SELECT order_id FROM trustride.fare_calculation c WHERE c.calculation_id = q.calculation_id) AS order_id
  LOOP
    INSERT INTO trustride.cost_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (r.correlation_id, 'TRS026_ENG004_BUS', 'QUOTE_EXPIRED', jsonb_build_object('quote_id', r.quote_id, 'order_id', r.order_id),
      'QUOTE_EXPIRED:' || r.quote_id::text);
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;

-- ---------------------------------------------------------------------------
-- 11. Business: estimate shown, accepted, expired or failed
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_business_fare_quoted_accept(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_o RECORD;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'no RECEIVED signal %', p_signal_id; END IF;
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = (v_payload->>'order_id')::uuid FOR UPDATE;
  IF v_o.status <> 'JOB_CREATED' THEN
    BEGIN PERFORM trustride.fn_cost_quote_cancel((v_payload->>'quote_id')::uuid); EXCEPTION WHEN OTHERS THEN NULL; END;
  ELSE
    UPDATE trustride.business_order SET quote_id = (v_payload->>'quote_id')::uuid, status = 'QUOTED', order_stage = 'QUOTATION_ACCEPTANCE', updated_at = now()
    WHERE order_id = v_o.order_id;
    PERFORM trustride.fn_business_progress_emit(v_o.order_id, 'QUOTED', jsonb_build_object('quote_id', v_payload->>'quote_id',
      'computed_total_fare_kes', v_payload->>'computed_total_fare_kes', 'expires_at', v_payload->>'expires_at', 'line_count', v_payload->>'line_count'));
  END IF;
  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_fare_calculation_failed_accept(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'no RECEIVED signal %', p_signal_id; END IF;
  PERFORM trustride.fn_business_order_close((v_payload->>'order_id')::uuid, 'FAILED',
    'We could not price this order: ' || left(coalesce(v_payload->>'reason', 'unknown'), 200), 'FAILED', TRUE);
  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_quote_expired_accept(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_o RECORD;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'no RECEIVED signal %', p_signal_id; END IF;
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = (v_payload->>'order_id')::uuid;
  IF v_o.status = 'QUOTED' AND v_o.quote_id = (v_payload->>'quote_id')::uuid THEN
    PERFORM trustride.fn_business_order_close(v_o.order_id, 'EXPIRED', 'The fare was not confirmed in time', 'EXPIRED');
  END IF;
  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

-- UNIT_PRICE_LOCKED (the customer accepted): settlement opened, operator told.
CREATE OR REPLACE FUNCTION trustride.fn_business_unit_price_locked_accept(p_signal_id uuid)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_o RECORD;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'fn_business_unit_price_locked_accept: no RECEIVED signal %', p_signal_id; END IF;
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = (v_payload->>'order_id')::uuid FOR UPDATE;
  UPDATE trustride.business_order SET quote_id = (v_payload->>'quote_id')::uuid, updated_at = now(),
    status = CASE WHEN status = 'QUOTED' THEN 'JOB_CREATED' ELSE status END,
    order_stage = CASE WHEN status = 'QUOTED' THEN 'DISPATCH' ELSE order_stage END
  WHERE order_id = v_o.order_id;
  INSERT INTO trustride.business_settlement (order_id, computed_total_fare_kes, payment_rail)
  VALUES (v_o.order_id, (v_payload->>'computed_total_fare_kes')::numeric, 'MPESA_C2B_STK')
  ON CONFLICT (order_id) DO NOTHING;
  IF v_o.status = 'QUOTED' THEN
    PERFORM trustride.fn_business_progress_emit(v_o.order_id, 'FARE_ACCEPTED', jsonb_build_object('computed_total_fare_kes', v_payload->>'computed_total_fare_kes'));
  END IF;
  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

-- ---------------------------------------------------------------------------
-- 12. Customer and Office actions on an order
-- ---------------------------------------------------------------------------
-- Customers cancel free of charge until the worker has arrived; once the
-- worker is at the door or the service has started, the order can no longer
-- be cancelled by the customer (TrustRide Office can still intervene).
CREATE OR REPLACE FUNCTION trustride.fn_business_order_cancel(p_order_id uuid, p_requester_user_id uuid, p_reason text DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_o RECORD;
BEGIN
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = p_order_id AND requester_user_id = p_requester_user_id FOR UPDATE;
  IF v_o.order_id IS NULL OR v_o.status IN ('SETTLED', 'REVIEWED', 'CLOSED', 'CANCELLED', 'EXPIRED', 'FAILED', 'DECLINED', 'COMPLETED') THEN
    RAISE EXCEPTION 'fn_business_order_cancel: order % cannot be cancelled by % (not the owner, already closed, or does not exist)', p_order_id, p_requester_user_id;
  END IF;
  IF EXISTS (SELECT 1 FROM trustride.business_job WHERE order_id = p_order_id AND status IN ('ARRIVED', 'EXECUTING', 'COMPLETED', 'VERIFIED')) THEN
    RAISE EXCEPTION 'Your % has already arrived or started -- contact support to stop this order', CASE WHEN v_o.macro_domain = 'EXECUTIVE_ASSISTANTS' THEN 'assistant' ELSE 'driver' END;
  END IF;
  PERFORM trustride.fn_business_order_close(p_order_id, 'CANCELLED', coalesce(nullif(trim(p_reason), ''), 'Cancelled by customer'), 'CANCELLED');
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_order_office_intervene(p_order_id UUID, p_action TEXT, p_reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_o RECORD;
  v_unit UUID;
BEGIN
  IF NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN
    RAISE EXCEPTION 'Order intervention is a TrustRide Office function';
  END IF;
  IF coalesce(trim(p_reason), '') = '' THEN RAISE EXCEPTION 'State the reason for the intervention'; END IF;
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = p_order_id FOR UPDATE;
  IF v_o.order_id IS NULL OR v_o.order_root_type <> 'SERVICE_ORDER' THEN RAISE EXCEPTION 'No such service order'; END IF;
  IF v_o.status IN ('SETTLED', 'REVIEWED', 'CLOSED', 'CANCELLED', 'EXPIRED', 'FAILED', 'DECLINED') THEN
    RAISE EXCEPTION 'Order % is already closed (%)', v_o.order_code, v_o.status;
  END IF;
  PERFORM trustride.fn_audit_log_append('business_order', p_order_id, 'OFFICE_INTERVENTION_' || upper(p_action), auth.uid(), 'USER', NULL, 'TRUSTRIDE_OFFICE',
    jsonb_build_object('status', v_o.status), jsonb_build_object('reason', p_reason));
  CASE upper(p_action)
    WHEN 'CANCEL' THEN
      PERFORM trustride.fn_business_order_close(p_order_id, 'CANCELLED', 'Cancelled by TrustRide Office: ' || p_reason, 'CANCELLED');
    WHEN 'FAIL' THEN
      PERFORM trustride.fn_business_order_close(p_order_id, 'FAILED', 'Closed by TrustRide Office: ' || p_reason, 'FAILED');
    WHEN 'REASSIGN' THEN
      IF EXISTS (SELECT 1 FROM trustride.business_job WHERE order_id = p_order_id AND status IN ('EXECUTING', 'COMPLETED', 'VERIFIED')) THEN
        RAISE EXCEPTION 'The service has started -- it cannot be reassigned';
      END IF;
      v_unit := trustride.fn_business_release_assignment(p_order_id, 'Reassigned by TrustRide Office: ' || p_reason);
      PERFORM trustride.fn_business_withdraw_unaccepted_quote(p_order_id);
      UPDATE trustride.business_order SET status = 'VALIDATED', declined_unit_ids = CASE WHEN v_unit IS NULL THEN declined_unit_ids ELSE array_append(declined_unit_ids, v_unit) END,
        updated_at = now() WHERE order_id = p_order_id;
      PERFORM trustride.fn_business_progress_emit(p_order_id, 'REASSIGNING', jsonb_build_object('reason', p_reason, 'workforce_unit_id', v_unit));
      PERFORM trustride.fn_business_assignment_request(p_order_id);
    ELSE
      RAISE EXCEPTION 'Intervention is CANCEL, REASSIGN or FAIL';
  END CASE;
END;
$$;

-- ---------------------------------------------------------------------------
-- 13. Operator: acknowledge, decline, progress (G3)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_business_job_acknowledge(p_order_id UUID, p_operator_user_id UUID)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_o RECORD;
  n INTEGER;
BEGIN
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = p_order_id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM trustride.business_job j JOIN trustride.resource_workforce_unit wu ON wu.workforce_unit_id = j.workforce_unit_id
                 WHERE j.order_id = p_order_id AND wu.operator_user_id = p_operator_user_id AND j.status = 'CREATED') THEN
    RAISE EXCEPTION 'There is no job on this order waiting for you';
  END IF;
  IF v_o.status <> 'JOB_CREATED' OR NOT EXISTS (SELECT 1 FROM trustride.business_settlement WHERE order_id = p_order_id) THEN
    RAISE EXCEPTION 'The customer has not confirmed the fare yet -- the job opens once they do';
  END IF;
  UPDATE trustride.business_job SET status = 'ACKNOWLEDGED', acknowledged_at = now() WHERE order_id = p_order_id AND status = 'CREATED';
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM trustride.fn_business_progress_emit(p_order_id, 'ACKNOWLEDGED');
  RETURN n;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_job_decline(p_order_id UUID, p_operator_user_id UUID, p_reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_unit UUID;
BEGIN
  SELECT j.workforce_unit_id INTO v_unit FROM trustride.business_job j JOIN trustride.resource_workforce_unit wu ON wu.workforce_unit_id = j.workforce_unit_id
  WHERE j.order_id = p_order_id AND wu.operator_user_id = p_operator_user_id AND j.status IN ('CREATED', 'ACKNOWLEDGED') LIMIT 1;
  IF v_unit IS NULL THEN
    RAISE EXCEPTION 'You can only decline a job before you set off';
  END IF;
  PERFORM trustride.fn_business_release_assignment(p_order_id, 'Declined by operator: ' || coalesce(p_reason, 'no reason'));
  PERFORM trustride.fn_business_withdraw_unaccepted_quote(p_order_id);
  UPDATE trustride.business_order SET status = 'VALIDATED', declined_unit_ids = array_append(declined_unit_ids, v_unit), updated_at = now()
  WHERE order_id = p_order_id;
  PERFORM trustride.fn_business_progress_emit(p_order_id, 'REASSIGNING', jsonb_build_object('reason', 'The first operator could not take it', 'workforce_unit_id', v_unit));
  PERFORM trustride.fn_business_assignment_request(p_order_id);
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_job_progress_advance(p_job_id uuid, p_operator_user_id uuid, p_correlation_id uuid DEFAULT gen_random_uuid())
RETURNS trustride.business_job_status_enum LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_job RECORD;
  v_o RECORD;
  v_next trustride.business_job_status_enum;
  v_seq trustride.business_job_status_enum[] := ARRAY['CREATED','ACKNOWLEDGED','DISPATCHED','EN_ROUTE','ARRIVED','EXECUTING','COMPLETED','VERIFIED']::trustride.business_job_status_enum[];
  v_idx INTEGER;
  v_current_line SMALLINT;
  v_all_done BOOLEAN;
  v_all_verified BOOLEAN;
BEGIN
  SELECT j.*, wu.operator_user_id INTO v_job
  FROM trustride.business_job j LEFT JOIN trustride.resource_workforce_unit wu ON wu.workforce_unit_id = j.workforce_unit_id
  WHERE j.job_id = p_job_id;
  IF v_job.job_id IS NULL THEN RAISE EXCEPTION 'fn_business_job_progress_advance: unknown job_id %', p_job_id; END IF;
  IF v_job.operator_user_id IS DISTINCT FROM p_operator_user_id AND p_operator_user_id <> '00000000-0000-0000-0000-000000000000'::uuid THEN
    RAISE EXCEPTION 'fn_business_job_progress_advance: % is not the assigned operator for job %', p_operator_user_id, p_job_id;
  END IF;
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = v_job.order_id FOR UPDATE;
  IF v_o.status IN ('CANCELLED', 'EXPIRED', 'FAILED', 'DECLINED', 'CLOSED') THEN
    RAISE EXCEPTION 'This order is % -- stop work on it', lower(v_o.status::text);
  END IF;
  IF v_job.status = 'CREATED' THEN
    PERFORM trustride.fn_business_job_acknowledge(v_job.order_id, v_job.operator_user_id);
    RETURN 'ACKNOWLEDGED';
  END IF;

  v_idx := array_position(v_seq, v_job.status);
  IF v_idx IS NULL OR v_idx >= array_length(v_seq, 1) THEN
    RAISE EXCEPTION 'fn_business_job_progress_advance: job % cannot advance past %', p_job_id, v_job.status;
  END IF;
  v_next := v_seq[v_idx + 1];

  -- Stops are served in order: only the current stop moves past ACKNOWLEDGED.
  SELECT min(line_sequence) INTO v_current_line FROM trustride.business_job
  WHERE order_id = v_job.order_id AND status NOT IN ('COMPLETED', 'VERIFIED', 'CANCELLED', 'FAILED');
  IF v_next NOT IN ('VERIFIED') AND v_job.line_sequence > v_current_line THEN
    RAISE EXCEPTION 'Finish stop % first', v_current_line;
  END IF;

  UPDATE trustride.business_job SET status = v_next,
    dispatched_at = CASE WHEN v_next = 'DISPATCHED' THEN now() ELSE dispatched_at END,
    arrived_at = CASE WHEN v_next = 'ARRIVED' THEN now() ELSE arrived_at END,
    completed_at = CASE WHEN v_next = 'COMPLETED' THEN now() ELSE completed_at END,
    verified_at = CASE WHEN v_next = 'VERIFIED' THEN now() ELSE verified_at END
  WHERE job_id = p_job_id;

  IF v_next = 'DISPATCHED' THEN
    PERFORM trustride.fn_business_tracking_session_open(p_job_id);
    IF v_o.status <> 'DISPATCHED' AND v_o.status <> 'EXECUTING' THEN
      UPDATE trustride.business_order SET status = 'DISPATCHED', order_stage = 'DISPATCH', updated_at = now() WHERE order_id = v_o.order_id;
    END IF;
    PERFORM trustride.fn_business_progress_emit(v_o.order_id, 'DISPATCHED', jsonb_build_object('job_id', p_job_id, 'line_sequence', v_job.line_sequence));
  ELSIF v_next IN ('EN_ROUTE', 'ARRIVED') THEN
    UPDATE trustride.business_tracking_session SET tracking_status = v_next::text, updated_at = now() WHERE job_id = p_job_id AND ended_at IS NULL;
    PERFORM trustride.fn_business_progress_emit(v_o.order_id, v_next::text, jsonb_build_object('job_id', p_job_id, 'line_sequence', v_job.line_sequence));
  ELSIF v_next = 'EXECUTING' THEN
    IF v_o.status <> 'EXECUTING' THEN
      UPDATE trustride.business_order SET status = 'EXECUTING', order_stage = 'EXECUTION_COMPLETION', updated_at = now() WHERE order_id = v_o.order_id;
      PERFORM trustride.fn_cost_quote_mark_in_progress(v_o.quote_id) FROM trustride.fare_quote WHERE quote_id = v_o.quote_id AND quote_state = 'FARE_LOCKED';
    END IF;
    UPDATE trustride.business_tracking_session SET tracking_status = 'EXECUTING', updated_at = now() WHERE job_id = p_job_id AND ended_at IS NULL;
    PERFORM trustride.fn_business_progress_emit(v_o.order_id, 'EXECUTING', jsonb_build_object('job_id', p_job_id, 'line_sequence', v_job.line_sequence));
  ELSIF v_next = 'COMPLETED' THEN
    UPDATE trustride.business_tracking_session SET ended_at = now(), tracking_status = 'COMPLETED', updated_at = now() WHERE job_id = p_job_id AND ended_at IS NULL;
    v_all_done := NOT EXISTS (SELECT 1 FROM trustride.business_job WHERE order_id = v_o.order_id AND status NOT IN ('COMPLETED', 'VERIFIED', 'CANCELLED', 'FAILED'));
    IF v_all_done THEN
      UPDATE trustride.business_order SET status = 'COMPLETED', order_stage = 'PAYMENT_SETTLEMENT', updated_at = now() WHERE order_id = v_o.order_id;
      -- The service is physically finished: only now is payment requested.
      PERFORM trustride.fn_cost_quote_finalize(v_o.quote_id, p_correlation_id) FROM trustride.fare_quote WHERE quote_id = v_o.quote_id AND quote_state = 'SERVICE_IN_PROGRESS';
      PERFORM trustride.fn_business_progress_emit(v_o.order_id, 'COMPLETED', jsonb_build_object('job_id', p_job_id,
        'computed_total_fare_kes', (SELECT computed_total_fare_kes FROM trustride.business_settlement WHERE order_id = v_o.order_id)));
    ELSE
      PERFORM trustride.fn_business_progress_emit(v_o.order_id, 'STOP_COMPLETED', jsonb_build_object('job_id', p_job_id, 'line_sequence', v_job.line_sequence));
    END IF;
  ELSIF v_next = 'VERIFIED' THEN
    v_all_verified := NOT EXISTS (SELECT 1 FROM trustride.business_job WHERE order_id = v_o.order_id AND status NOT IN ('VERIFIED', 'CANCELLED', 'FAILED'));
    IF v_all_verified THEN
      -- Every stop done and verified: the working unit returns to the pool.
      INSERT INTO trustride.business_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
      VALUES (p_correlation_id, 'TRS026_ENG002_RESC', 'JOB_COMPLETED',
        jsonb_build_object('job_id', p_job_id, 'order_id', v_o.order_id, 'workforce_unit_id', v_job.workforce_unit_id, 'completed_at', now()),
        'JOB_COMPLETED:' || v_o.order_id::text);
      UPDATE trustride.business_order SET reserved_workforce_unit_id = NULL WHERE order_id = v_o.order_id;
    END IF;
  END IF;
  RETURN v_next;
END;
$$;

-- ---------------------------------------------------------------------------
-- 14. The dispatch sweep: waiting, scheduled, acknowledgement, auto-verify
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_business_dispatch_sweep()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  r RECORD;
  v_retry INTERVAL := make_interval(secs => trustride.fn_business_config_num('ORDER_RETRY_INTERVAL_SEC', 60)::int);
  v_max_wait INTERVAL := make_interval(mins => trustride.fn_business_config_num('ORDER_WAIT_MAX_MIN', 30)::int);
  v_lead INTERVAL := make_interval(mins => trustride.fn_business_config_num('SCHEDULED_DISPATCH_LEAD_MIN', 30)::int);
  v_ack INTERVAL := make_interval(mins => trustride.fn_business_config_num('OPERATOR_ACK_TIMEOUT_MIN', 3)::int);
  v_verify INTERVAL := make_interval(mins => trustride.fn_business_config_num('JOB_AUTO_VERIFY_MIN', 10)::int);
  v_retried INT := 0; v_expired INT := 0; v_held INT := 0; v_reassigned INT := 0; v_verified INT := 0; v_errors INT := 0;
  v_working BOOLEAN := trustride.fn_business_is_working_time(now());
BEGIN
  -- Each order is handled in its own sub-transaction: one bad order is
  -- reported to Office and never stops the sweep for everyone else.

  -- Waiting orders: retry, hold for the first shift, or close after the limit.
  FOR r IN SELECT * FROM trustride.business_order WHERE status = 'WAITING' ORDER BY waiting_since LOOP
    BEGIN
      IF NOT v_working THEN
        UPDATE trustride.business_order SET status = 'SCHEDULED', order_stage = 'SCHEDULED_HOLD', waiting_since = NULL,
          requested_start_at = trustride.fn_business_next_working_open(now()), updated_at = now() WHERE order_id = r.order_id;
        PERFORM trustride.fn_business_progress_emit(r.order_id, 'SCHEDULED', jsonb_build_object('first_shift', true));
        v_held := v_held + 1;
      ELSIF r.waiting_since < now() - v_max_wait THEN
        PERFORM trustride.fn_business_order_close(r.order_id, 'EXPIRED', 'No ' || lower(replace(coalesce(r.fulfilment_requirements->>'required_capacity_class_code', 'worker'), '_', ' ')) || ' became free within ' || trustride.fn_business_config_num('ORDER_WAIT_MAX_MIN', 30) || ' minutes', 'EXPIRED', TRUE);
        v_expired := v_expired + 1;
      ELSIF r.last_assignment_requested_at IS NULL OR r.last_assignment_requested_at < now() - v_retry THEN
        PERFORM trustride.fn_business_assignment_request(r.order_id);
        v_retried := v_retried + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
      PERFORM trustride.fn_present_notify_office('Dispatch sweep error on ' || r.order_code, SQLERRM, 'PLATFORM_EXCEPTION', r.order_id);
    END;
  END LOOP;

  -- Scheduled orders whose dispatch window has opened.
  FOR r IN SELECT * FROM trustride.business_order WHERE status = 'SCHEDULED' AND requested_start_at - v_lead <= now() LOOP
    BEGIN
      IF v_working OR trustride.fn_business_is_working_time(greatest(now(), r.requested_start_at)) THEN
        PERFORM trustride.fn_business_assignment_request(r.order_id);
        v_retried := v_retried + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
      PERFORM trustride.fn_present_notify_office('Dispatch sweep error on ' || r.order_code, SQLERRM, 'PLATFORM_EXCEPTION', r.order_id);
    END;
  END LOOP;

  -- Confirmed jobs the operator has not acknowledged: offer to someone else.
  FOR r IN
    SELECT o.order_id, o.order_code, min(wu.operator_user_id::text)::uuid AS operator_user_id
    FROM trustride.business_order o
    JOIN trustride.business_job j ON j.order_id = o.order_id AND j.status = 'CREATED'
    JOIN trustride.resource_workforce_unit wu ON wu.workforce_unit_id = j.workforce_unit_id
    JOIN trustride.fare_quote q ON q.quote_id = o.quote_id AND q.quote_state = 'FARE_LOCKED'
    WHERE o.status = 'JOB_CREATED' AND greatest(q.locked_at, j.created_at) < now() - v_ack
    GROUP BY o.order_id, o.order_code
  LOOP
    BEGIN
      PERFORM trustride.fn_business_job_decline(r.order_id, r.operator_user_id, 'Not acknowledged in time');
      v_reassigned := v_reassigned + 1;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
      PERFORM trustride.fn_present_notify_office('Dispatch sweep error on ' || r.order_code, SQLERRM, 'PLATFORM_EXCEPTION', r.order_id);
    END;
  END LOOP;

  -- Stops completed but never verified: verify, so the worker is released.
  FOR r IN SELECT job_id FROM trustride.business_job WHERE status = 'COMPLETED' AND completed_at < now() - v_verify LOOP
    BEGIN
      PERFORM trustride.fn_business_job_progress_advance(r.job_id, '00000000-0000-0000-0000-000000000000'::uuid);
      v_verified := v_verified + 1;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
      PERFORM trustride.fn_present_notify_office('Auto-verify error', SQLERRM, 'PLATFORM_EXCEPTION', r.job_id);
    END;
  END LOOP;

  RETURN jsonb_build_object('retried', v_retried, 'expired', v_expired, 'held_for_first_shift', v_held,
    'reassigned_unacknowledged', v_reassigned, 'auto_verified', v_verified, 'errors', v_errors);
END;
$$;

-- ---------------------------------------------------------------------------
-- 14b. No swallowed failures (Sec.22): a handler that throws no longer leaves
--      its signal silently RECEIVED -- it is dead-lettered with the error,
--      recorded for review, and TrustRide Office is told.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_orch_handler_failed(p_inbox_table TEXT, p_signal_id UUID, p_source TEXT, p_target TEXT, p_signal_type TEXT, p_error TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  EXECUTE format('UPDATE trustride.%I SET signal_status = ''DEAD_LETTER'', rejection_reason = $2, accepted_at = now() WHERE signal_id = $1 AND signal_status = ''RECEIVED''', p_inbox_table)
  USING p_signal_id, left('HANDLER_ERROR: ' || p_error, 500);
  INSERT INTO trustride.dead_letter_review (event_id, source_engine, target_engine, failure_reason)
  VALUES (p_signal_id, p_source, p_target, left(p_signal_type || ': ' || p_error, 1000));
  PERFORM trustride.fn_present_notify_office('Signal failed: ' || p_signal_type, left(p_error, 300), 'PLATFORM_EXCEPTION', p_signal_id,
    ARRAY['FOUNDER', 'ADMINISTRATOR'], FALSE);
EXCEPTION WHEN OTHERS THEN
  NULL;  -- recording a failure must never itself stop the dispatch cycle
END;
$$;

DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_orch_dispatch_cycle()'::regprocedure) INTO v_def;
  IF position('fn_orch_handler_failed' IN v_def) = 0 THEN
    v_def := replace(v_def, E'      EXCEPTION WHEN OTHERS THEN\n        NULL;\n      END;',
      E'      EXCEPTION WHEN OTHERS THEN\n        PERFORM trustride.fn_orch_handler_failed(v_cache.destination_inbox_table, v_row.signal_id, v_row.emitting_engine, v_cache.destination_engine_code, v_row.signal_type, SQLERRM);\n      END;');
    IF position('fn_orch_handler_failed' IN v_def) = 0 THEN RAISE EXCEPTION 'dispatch cycle patch did not apply'; END IF;
    EXECUTE v_def;
  END IF;
END;
$patch$;

-- ---------------------------------------------------------------------------
-- 15. Inboxes, routes, schedules
-- ---------------------------------------------------------------------------
DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_business_inbox_process(uuid)'::regprocedure) INTO v_def;
  IF position('RESOURCE_UNAVAILABLE' IN v_def) = 0 THEN
    v_def := replace(v_def, E'    ELSE\n      UPDATE trustride.business_event_inbox',
      E'    WHEN ''RESOURCE_UNAVAILABLE'' THEN v_result := trustride.fn_business_resource_unavailable_accept(p_signal_id);\n'
      || E'    WHEN ''FARE_QUOTED'' THEN v_result := trustride.fn_business_fare_quoted_accept(p_signal_id);\n'
      || E'    WHEN ''FARE_CALCULATION_FAILED'' THEN v_result := trustride.fn_business_fare_calculation_failed_accept(p_signal_id);\n'
      || E'    WHEN ''QUOTE_EXPIRED'' THEN v_result := trustride.fn_business_quote_expired_accept(p_signal_id);\n'
      || E'    ELSE\n      UPDATE trustride.business_event_inbox');
    IF position('RESOURCE_UNAVAILABLE' IN v_def) = 0 THEN RAISE EXCEPTION 'business inbox patch did not apply'; END IF;
    EXECUTE v_def;
  END IF;

  SELECT pg_get_functiondef('trustride.fn_resource_inbox_process(uuid)'::regprocedure) INTO v_def;
  IF position('ASSIGNMENT_RELEASED' IN v_def) = 0 THEN
    v_def := replace(v_def, E'    ELSE\n      UPDATE trustride.resource_event_inbox',
      E'    WHEN ''ASSIGNMENT_RELEASED'' THEN v_result := trustride.fn_resource_assignment_released_accept(p_signal_id);\n    ELSE\n      UPDATE trustride.resource_event_inbox');
    IF position('ASSIGNMENT_RELEASED' IN v_def) = 0 THEN RAISE EXCEPTION 'resource inbox patch did not apply'; END IF;
    EXECUTE v_def;
  END IF;
END;
$patch$;

INSERT INTO trustride.routing_rule (event_type, source_engine, target_engine, route_priority)
SELECT v.e, v.s, v.t, 0
FROM (VALUES
  ('RESOURCE_UNAVAILABLE', 'TRS026_ENG002_RESC', 'TRS026_ENG004_BUS'),
  ('ASSIGNMENT_RELEASED', 'TRS026_ENG004_BUS', 'TRS026_ENG002_RESC'),
  ('FARE_QUOTED', 'TRS026_ENG005_COST', 'TRS026_ENG004_BUS'),
  ('FARE_CALCULATION_FAILED', 'TRS026_ENG005_COST', 'TRS026_ENG004_BUS'),
  ('QUOTE_EXPIRED', 'TRS026_ENG005_COST', 'TRS026_ENG004_BUS'),
  ('ORDER_PROGRESS', 'TRS026_ENG004_BUS', 'TRS026_ENG011_PRESENT')
) AS v(e, s, t)
WHERE NOT EXISTS (SELECT 1 FROM trustride.routing_rule r WHERE r.event_type = v.e AND r.source_engine = v.s AND r.target_engine = v.t);
SELECT trustride.fn_orch_destination_cache_sync();

SELECT cron.schedule('trustride_business_dispatch_sweep', '* * * * *', 'SELECT trustride.fn_business_dispatch_sweep();');
SELECT cron.schedule('trustride_cost_quote_expire_sweep', '* * * * *', 'SELECT trustride.fn_cost_quote_expire_sweep();');

-- ---------------------------------------------------------------------------
-- 16. Engine 11: progress rendering and the customer/operator/Office verbs
-- ---------------------------------------------------------------------------
-- What each order event says, and to whom. Operators hear about their work;
-- customers about their order; Office about exceptions.
CREATE OR REPLACE FUNCTION trustride.fn_present_order_progress_accept(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_p JSONB;
  v_corr UUID;
  v_event TEXT;
  v_code TEXT;
  v_op_name TEXT;
  v_vehicle TEXT;
  v_who TEXT;
  v_when TEXT;
  v_c_title TEXT; v_c_body TEXT; v_c_critical BOOLEAN := FALSE;
  v_o_title TEXT; v_o_body TEXT; v_o_critical BOOLEAN := FALSE;
BEGIN
  SELECT payload_in, correlation_id INTO v_p, v_corr FROM trustride.present_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_p IS NULL THEN RAISE EXCEPTION 'no RECEIVED signal %', p_signal_id; END IF;
  v_event := v_p->>'event';
  v_code := v_p->>'order_code';
  SELECT display_name INTO v_op_name FROM trustride.platform_users WHERE user_id = (v_p->>'operator_user_id')::uuid;
  SELECT trim(concat_ws(' ', o.make, o.model, o.plate_number)) INTO v_vehicle
  FROM trustride.resource_workforce_unit wu JOIN trustride.resource_fleet_register f ON f.fleet_resource_id = wu.fleet_resource_id
  JOIN trustride.object_registry o ON o.object_id = f.object_id WHERE wu.workforce_unit_id = (v_p->>'workforce_unit_id')::uuid;
  v_who := coalesce(v_op_name, 'Your TrustRide operator') || coalesce(' (' || nullif(v_vehicle, '') || ')', '');
  v_when := to_char((v_p->>'requested_start_at')::timestamptz AT TIME ZONE 'Africa/Nairobi', 'Dy DD Mon HH24:MI');

  CASE v_event
    WHEN 'WAITING' THEN
      v_c_title := 'Finding you a ' || lower(replace(coalesce(v_p->>'required_capacity_class', 'worker'), '_', ' '));
      v_c_body := format('All are busy right now. We keep trying for up to %s minutes and will tell you the moment one is free. You can cancel at no charge.', v_p->>'max_wait_min');
    WHEN 'SCHEDULED' THEN
      v_c_title := 'Order scheduled';
      v_c_body := CASE WHEN coalesce((v_p->>'first_shift')::boolean, false)
        THEN format('%s is outside working hours. It will be served by the first shift: %s.', v_code, v_when)
        ELSE format('%s is booked for %s. We will confirm your fare before your worker sets off.', v_code, v_when) END;
    WHEN 'QUOTED' THEN
      v_c_title := 'Confirm your fare: KES ' || (v_p->>'computed_total_fare_kes');
      v_c_body := format('%s is ready -- %s is matched. Accept the fare in My Orders before %s or the booking lapses.', v_code, v_who,
        to_char((v_p->>'expires_at')::timestamptz AT TIME ZONE 'Africa/Nairobi', 'HH24:MI'));
      v_c_critical := TRUE;
    WHEN 'FARE_ACCEPTED' THEN
      v_c_title := 'Fare confirmed';
      v_c_body := format('%s confirmed. %s will acknowledge shortly.', v_code, v_who);
      v_o_title := 'New job ' || v_code;
      v_o_body := 'A customer confirmed a job for you. Open the Operator App and acknowledge it now.';
      v_o_critical := TRUE;
    WHEN 'ACKNOWLEDGED' THEN
      v_c_title := 'Your order is accepted';
      v_c_body := format('%s accepted %s.', v_who, v_code);
    WHEN 'DISPATCHED' THEN
      v_c_title := 'On the way';
      v_c_body := format('%s is setting off for %s.', v_who, v_code);
    WHEN 'EN_ROUTE' THEN
      v_c_title := 'On the way';
      v_c_body := format('%s is en route. Track it in My Orders.', v_who);
    WHEN 'ARRIVED' THEN
      v_c_title := 'Arrived';
      v_c_body := format('%s has arrived.', v_who);
      v_c_critical := TRUE;
    WHEN 'EXECUTING' THEN
      v_c_title := 'Service started';
      v_c_body := format('%s has started.', v_code);
    WHEN 'STOP_COMPLETED' THEN
      v_c_title := 'Stop ' || (v_p->>'line_sequence') || ' done';
      v_c_body := format('%s: stop %s completed; continuing to the next.', v_code, v_p->>'line_sequence');
    WHEN 'COMPLETED' THEN
      v_c_title := 'Service complete';
      v_c_body := format('%s is complete. An M-Pesa request for KES %s is being sent to your phone.', v_code, v_p->>'computed_total_fare_kes');
      v_c_critical := TRUE;
    WHEN 'REASSIGNING' THEN
      v_c_title := 'Finding another operator';
      v_c_body := format('%s: %s. We are matching you with someone else.', v_code, coalesce(v_p->>'reason', 'your operator could not continue'));
      v_o_title := 'Job ' || v_code || ' reassigned';
      v_o_body := 'This job has been passed to another operator.';
    WHEN 'CANCELLED' THEN
      v_c_title := 'Order cancelled';
      v_c_body := format('%s was cancelled (%s). You have not been charged.', v_code, v_p->>'reason');
      v_o_title := 'Job ' || v_code || ' cancelled';
      v_o_body := 'Stop: this job was cancelled.';
      v_o_critical := v_p->>'operator_user_id' IS NOT NULL;
    WHEN 'EXPIRED' THEN
      v_c_title := 'Order closed';
      v_c_body := format('%s closed: %s. You have not been charged.', v_code, v_p->>'reason');
      v_o_title := 'Job ' || v_code || ' closed';
      v_o_body := 'This job lapsed and is no longer yours.';
    WHEN 'FAILED' THEN
      v_c_title := 'We could not complete your order';
      v_c_body := format('%s: %s. You have not been charged; TrustRide Office has been alerted.', v_code, v_p->>'reason');
      v_o_title := 'Job ' || v_code || ' stopped';
      v_o_body := 'This job was stopped by the platform.';
    WHEN 'DECLINED' THEN
      v_c_title := 'Not available in your area yet';
      v_c_body := format('%s: %s.', v_code, v_p->>'reason');
    ELSE
      v_c_title := NULL;
  END CASE;

  IF v_c_title IS NOT NULL THEN
    INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, source_signal_correlation_id, category, critical)
    VALUES ((v_p->>'requester_user_id')::uuid, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', v_c_title, v_c_body, v_corr, 'ORDER', v_c_critical);
  END IF;
  IF v_o_title IS NOT NULL AND v_p->>'operator_user_id' IS NOT NULL THEN
    INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, source_signal_correlation_id, category, critical)
    VALUES ((v_p->>'operator_user_id')::uuid, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', v_o_title, v_o_body, v_corr, 'JOB', v_o_critical);
  END IF;
  IF coalesce((v_p->>'notify_office')::boolean, false) THEN
    PERFORM trustride.fn_present_notify_office('Order ' || v_code || ' ' || lower(v_event), coalesce(v_p->>'reason', v_event), 'ORDER_EXCEPTION', v_corr);
  END IF;
  UPDATE trustride.present_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  -- Presentation inbox: ORDER_PROGRESS; Academy enrollment notifications.
  SELECT pg_get_functiondef('trustride.fn_present_inbox_process(uuid)'::regprocedure) INTO v_def;
  IF position('ORDER_PROGRESS' IN v_def) = 0 THEN
    v_def := replace(v_def, E'    WHEN ''SERVICE_CATALOGUE_UPDATED'' THEN',
      E'    WHEN ''ORDER_PROGRESS'' THEN\n      RETURN trustride.fn_present_order_progress_accept(p_signal_id);\n\n    WHEN ''SERVICE_CATALOGUE_UPDATED'' THEN');
    v_def := replace(v_def, E'          WHEN ''OFFICE-ACCESS'' THEN',
      E'          WHEN ''EA-ACADEMY-TRAINING'' THEN ARRAY[''TRUSTRIDE_BUSINESS'', ''CUSTOMER_APP'', ''Academy enrollment received'', ''Enrollment %s is with TrustRide Office -- decision within 2-3 working days.'']\n          WHEN ''OFFICE-ACCESS'' THEN');
    v_def := replace(v_def, E'          WHEN ''MARKETPLACE_PURCHASE_ORDER'' THEN ARRAY[''TRUSTRIDE_MARKETPLACE'', ''MARKETPLACE_APP'']',
      E'          WHEN ''MARKETPLACE_PURCHASE_ORDER'' THEN ARRAY[''TRUSTRIDE_MARKETPLACE'', ''MARKETPLACE_APP'']\n          WHEN ''ACADEMY_ENROLLMENT_REQUEST'' THEN ARRAY[''TRUSTRIDE_BUSINESS'', ''CUSTOMER_APP'']');
    IF position('ORDER_PROGRESS' IN v_def) = 0 OR position('ACADEMY_ENROLLMENT_REQUEST' IN v_def) = 0 OR position('Academy enrollment received' IN v_def) = 0 THEN
      RAISE EXCEPTION 'presentation inbox patch did not apply';
    END IF;
    EXECUTE v_def;
  END IF;

  -- Capture: RAISE_INTENT goes through the completed order path;
  -- ACCEPT_QUOTATION and TRACK_ELEMENT gain their ownership checks.
  SELECT pg_get_functiondef('trustride.fn_present_capture_command(uuid,text,jsonb)'::regprocedure) INTO v_def;
  IF position('fn_business_service_order_place' IN v_def) = 0 THEN
    v_def := regexp_replace(v_def,
      -- (non-greedy first quantifier: in PostgreSQL the first quantifier sets
      -- the greediness of the whole pattern)
      E'WHEN ''RAISE_INTENT'' THEN\\s*?v_translated_signal_id := trustride\\.fn_business_order_place\\(.*?v_command_id\\);',
      E'WHEN ''RAISE_INTENT'' THEN\n        v_translated_signal_id := trustride.fn_business_service_order_place(v_session.user_id, p_command_payload, v_command_id);');
    v_def := replace(v_def, E'PERFORM trustride.fn_cost_quote_lock((p_command_payload->>''quote_id'')::uuid, v_command_id);',
      E'v_translated_signal_id := trustride.fn_present_cmd_accept_quotation(p_shell_session_id, p_command_payload, v_command_id);');
    v_def := regexp_replace(v_def,
      E'PERFORM trustride\\.fn_business_tracking_location_update\\(.*?\\(p_command_payload->>''eta''\\)::timestamptz\\);',
      E'v_translated_signal_id := trustride.fn_present_cmd_track_element(p_shell_session_id, p_command_payload, v_command_id);');
    IF position('fn_business_service_order_place' IN v_def) = 0 OR position('fn_present_cmd_accept_quotation' IN v_def) = 0
       OR position('fn_present_cmd_track_element' IN v_def) = 0 THEN
      RAISE EXCEPTION 'capture command patch did not apply';
    END IF;
    EXECUTE v_def;
  END IF;
END;
$patch$;

-- Only the customer whose order it is may accept its estimate.
CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_accept_quotation(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_user UUID := (SELECT user_id FROM trustride.present_shell_session WHERE session_id = p_session);
  v_o RECORD;
BEGIN
  SELECT * INTO v_o FROM trustride.business_order WHERE quote_id = (p_payload->>'quote_id')::uuid AND requester_user_id = v_user;
  IF v_o.order_id IS NULL THEN RAISE EXCEPTION 'This fare is not for one of your orders'; END IF;
  IF v_o.status <> 'QUOTED' THEN RAISE EXCEPTION 'This order is % -- there is no fare waiting for your confirmation', lower(v_o.status::text); END IF;
  PERFORM trustride.fn_cost_quote_lock(v_o.quote_id, p_command);
  RETURN v_o.order_id;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_decline_quotation(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_user UUID := (SELECT user_id FROM trustride.present_shell_session WHERE session_id = p_session);
  v_o RECORD;
BEGIN
  SELECT * INTO v_o FROM trustride.business_order WHERE quote_id = (p_payload->>'quote_id')::uuid AND requester_user_id = v_user;
  IF v_o.order_id IS NULL OR v_o.status <> 'QUOTED' THEN RAISE EXCEPTION 'There is no fare waiting for your confirmation'; END IF;
  PERFORM trustride.fn_business_order_cancel(v_o.order_id, v_user, 'Fare declined by customer');
  RETURN v_o.order_id;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_cancel_order(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_business_order_cancel((p_payload->>'order_id')::uuid,
    (SELECT user_id FROM trustride.present_shell_session WHERE session_id = p_session), p_payload->>'reason');
  RETURN (p_payload->>'order_id')::uuid;
END;
$$;

-- Location reports come from the operator (or, in the telemetry stage, the
-- vehicle's tracking device) -- never from the customer (G13).
CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_track_element(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_user UUID := (SELECT user_id FROM trustride.present_shell_session WHERE session_id = p_session);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM trustride.business_job j JOIN trustride.resource_workforce_unit wu ON wu.workforce_unit_id = j.workforce_unit_id
                 WHERE j.job_id = (p_payload->>'job_id')::uuid AND wu.operator_user_id = v_user) THEN
    RAISE EXCEPTION 'You can only report location for your own job';
  END IF;
  PERFORM trustride.fn_business_tracking_location_update((p_payload->>'job_id')::uuid, (p_payload->>'lat')::numeric,
    (p_payload->>'lon')::numeric, (p_payload->>'eta')::timestamptz);
  RETURN (p_payload->>'job_id')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_acknowledge_job(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_order UUID := coalesce((p_payload->>'order_id')::uuid, (SELECT order_id FROM trustride.business_job WHERE job_id = (p_payload->>'job_id')::uuid));
BEGIN
  PERFORM trustride.fn_business_job_acknowledge(v_order, (SELECT user_id FROM trustride.present_shell_session WHERE session_id = p_session));
  RETURN v_order;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_decline_job(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_order UUID := coalesce((p_payload->>'order_id')::uuid, (SELECT order_id FROM trustride.business_job WHERE job_id = (p_payload->>'job_id')::uuid));
BEGIN
  PERFORM trustride.fn_business_job_decline(v_order, (SELECT user_id FROM trustride.present_shell_session WHERE session_id = p_session), p_payload->>'reason');
  RETURN v_order;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_intervene_order(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_business_order_office_intervene((p_payload->>'order_id')::uuid, p_payload->>'action', p_payload->>'reason');
  RETURN (p_payload->>'order_id')::uuid;
END;
$$;

-- Intake services (G6): Academy enrollment and employment application.
CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_enroll_academy(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_user UUID := (SELECT user_id FROM trustride.present_shell_session WHERE session_id = p_session);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id = v_user AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'Verify your identity before enrolling';
  END IF;
  IF coalesce(trim(p_payload->>'programme'), '') = '' THEN RAISE EXCEPTION 'Choose a programme'; END IF;
  RETURN trustride.fn_business_order_place(v_user, 'CUSTOMER', 'EA-ACADEMY-TRAINING', 'EXECUTIVE_ASSISTANTS',
    jsonb_build_array(jsonb_build_object('line_description', 'TrustRide Academy: ' || (p_payload->>'programme'), 'quantity', 1,
      'scope_detail', jsonb_build_object('programme', p_payload->>'programme', 'preferred_start', p_payload->>'preferred_start',
        'motivation', p_payload->>'motivation'))),
    'ACADEMY_ENROLLMENT_REQUEST', coalesce(p_payload->>'jurisdiction', 'KISUMU_COUNTY'), p_command);
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_apply_employment(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_access UUID := (SELECT access_id FROM trustride.present_shell_session WHERE session_id = p_session);
BEGIN
  IF coalesce(trim(p_payload->>'role_sought'), '') = '' THEN RAISE EXCEPTION 'Say which role you are applying for'; END IF;
  RETURN trustride.fn_present_office_access_request('OPERATOR_APP',
    'Employment application -- ' || (p_payload->>'role_sought') || coalesce('. Experience: ' || nullif(p_payload->>'experience', ''), ''), v_access);
END;
$$;

UPDATE trustride.present_shell_capability_registry SET permitted = FALSE WHERE sub_shell = 'CUSTOMER_APP' AND command_type = 'TRACK_ELEMENT';
INSERT INTO trustride.present_shell_capability_registry (top_shell, sub_shell, command_type, permitted, requires_delegated_authority)
SELECT v.top::trustride.present_top_shell_enum, v.sub::trustride.present_sub_shell_enum, v.cmd, TRUE, FALSE
FROM (VALUES
  ('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'CANCEL_ORDER'), ('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'DECLINE_QUOTATION'),
  ('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'ENROLL_ACADEMY'), ('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'APPLY_EMPLOYMENT'),
  ('TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'ACKNOWLEDGE_JOB'), ('TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'DECLINE_JOB'),
  ('TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'TRACK_ELEMENT'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'INTERVENE_ORDER')
) AS v(top, sub, cmd)
WHERE NOT EXISTS (SELECT 1 FROM trustride.present_shell_capability_registry r WHERE r.sub_shell = v.sub::trustride.present_sub_shell_enum AND r.command_type = v.cmd);

-- ---------------------------------------------------------------------------
-- 17. Grants
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_user_payment_msisdn(UUID) TO trs026_eng004_bus_service;

SELECT trustride.fn_platform_conformance_assert();
