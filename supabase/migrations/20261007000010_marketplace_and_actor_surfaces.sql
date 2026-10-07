-- ============================================================================
-- Marketplace completion + post-approval actor capabilities + Office user
-- management -- Engines 2, 3, 4, 6, 11
-- Implementation Completion Stages 10-11: G6 (Marketplace never dispatches),
-- G16 (approval activates the approved capability), Sec.11, Sec.14, D4.
-- ============================================================================
-- MARKETPLACE (motorcycles and cars only -- Founder rule)
--   Own marketplace: ACQUIRE_INVENTORY -> ADVANCE_INVENTORY (inspected,
--   valued, refurbished, compliant) -> PUBLISH_OFFER -> listed.
--   Vendor: approved VENDOR agreement (5% commission) -> PUBLISH_OFFER ->
--   listed; DELIST_OFFER.
--   Buyer: RESERVE_VEHICLE(listing) -> listing RESERVED + purchase request ->
--   Office confirms -> AWAITING_PAYMENT (M-Pesa STK up to the limit, recorded
--   bank transfer above it) -> paid -> listing SOLD, inventory SOLD ->
--   CONFIRM_HANDOVER -> COMPLETED -> vendor payout (gross - 5%) via Daraja
--   B2C. Unpaid reservations EXPIRE and the vehicle returns to sale.
-- APPROVAL ACTIVATES THE CAPABILITY
--   Partner: contributed vehicles enter the fleet register (NTSA-verified)
--   in the partner's ownership.
--   Governor: an oversight engagement with NO data rights until TrustRide
--   Office grants named aggregate scopes (D4 -- the boundary is built; which
--   scopes a county authority receives is the Founder's decision).
--   Intermediary: a facilitation engagement and a referral code that
--   attributes the actors they bring.
-- ============================================================================

INSERT INTO trustride.platform_configuration (config_key, config_value, environment, effective_from, changed_by)
SELECT v.k, v.v, 'ALL', now(), '00000000-0000-0000-0000-000000000000' FROM (VALUES
  ('MARKETPLACE_PAYMENT_WINDOW_HOURS', '72')   -- a confirmed reservation must be paid within this window
) AS v(k, v)
WHERE NOT EXISTS (SELECT 1 FROM trustride.platform_configuration c WHERE c.config_key = v.k);

-- ---------------------------------------------------------------------------
-- 1. Engine 3: listings know what they sell and who holds them
-- ---------------------------------------------------------------------------
ALTER TABLE trustride.service_marketplace_listing
  ADD COLUMN vehicle_category TEXT CHECK (vehicle_category IN ('MOTORCYCLE', 'CAR')),
  ADD COLUMN object_id UUID,
  ADD COLUMN commission_pct NUMERIC(5,2),
  ADD COLUMN reserved_order_id UUID,
  ADD COLUMN reserved_until TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION trustride.fn_service_marketplace_offer_publish(p_listing_type trustride.service_listing_type_enum, p_vendor_user_id UUID,
  p_vehicle_category TEXT, p_title TEXT, p_description TEXT, p_price_kes NUMERIC, p_object_id UUID, p_inventory_item_id UUID, p_commission_pct NUMERIC)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_listing UUID;
BEGIN
  IF p_vehicle_category NOT IN ('MOTORCYCLE', 'CAR') THEN
    RAISE EXCEPTION 'TrustRide Marketplace lists motorcycles and cars only';
  END IF;
  IF coalesce(trim(p_title), '') = '' OR p_price_kes IS NULL OR p_price_kes <= 0 THEN
    RAISE EXCEPTION 'A listing needs a title and a price';
  END IF;
  v_listing := trustride.fn_service_marketplace_listing_create(
    (SELECT service_id FROM trustride.service_catalogue WHERE service_code = 'MARKETPLACE-ITEM-LISTING'),
    p_listing_type, trim(p_title), coalesce(p_description, ''), p_price_kes, p_vendor_user_id, p_inventory_item_id);
  UPDATE trustride.service_marketplace_listing SET vehicle_category = p_vehicle_category, object_id = p_object_id, commission_pct = p_commission_pct
  WHERE listing_id = v_listing;
  PERFORM trustride.fn_service_marketplace_listing_publish(v_listing);
  RETURN v_listing;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_service_marketplace_listing_reserve(p_listing_id UUID, p_order_id UUID, p_until TIMESTAMPTZ)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  UPDATE trustride.service_marketplace_listing SET listing_status = 'RESERVED', reserved_order_id = p_order_id, reserved_until = p_until
  WHERE listing_id = p_listing_id AND listing_status = 'LISTED';
  IF NOT FOUND THEN RAISE EXCEPTION 'This vehicle is no longer available'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_service_marketplace_listing_release(p_listing_id UUID, p_order_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  UPDATE trustride.service_marketplace_listing SET listing_status = 'LISTED', reserved_order_id = NULL, reserved_until = NULL
  WHERE listing_id = p_listing_id AND listing_status = 'RESERVED' AND reserved_order_id = p_order_id;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_service_marketplace_listing_extend(p_listing_id UUID, p_order_id UUID, p_until TIMESTAMPTZ)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = trustride, public AS $$
  UPDATE trustride.service_marketplace_listing SET reserved_until = p_until WHERE listing_id = p_listing_id AND reserved_order_id = p_order_id;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_service_marketplace_listing_delist(p_listing_id UUID, p_by UUID, p_office BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  UPDATE trustride.service_marketplace_listing SET listing_status = 'DELISTED', delisted_at = now()
  WHERE listing_id = p_listing_id AND listing_status IN ('DRAFT', 'LISTED') AND (p_office OR vendor_user_id = p_by);
  IF NOT FOUND THEN RAISE EXCEPTION 'Only a listed (not reserved or sold) offer of yours can be withdrawn'; END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Engine 2: own-marketplace inventory is a registered Object
-- ---------------------------------------------------------------------------
ALTER TABLE trustride.resource_marketplace_inventory ADD COLUMN object_id UUID;

CREATE OR REPLACE FUNCTION trustride.fn_resource_office_inventory_acquire(p_object_id UUID, p_acquisition_source TEXT, p_acquisition_cost_kes NUMERIC, p_custody_estate_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_by UUID := trustride.fn_resource_office_gate();
  v_obj RECORD;
  v_item UUID;
BEGIN
  SELECT object_id, object_type, plate_number INTO v_obj FROM trustride.object_registry WHERE object_id = p_object_id;
  IF v_obj.object_id IS NULL OR v_obj.object_type NOT IN ('MOTORCYCLE', 'CAR') THEN
    RAISE EXCEPTION 'Marketplace stock is a registered motorcycle or car';
  END IF;
  IF EXISTS (SELECT 1 FROM trustride.resource_marketplace_inventory WHERE object_id = p_object_id AND lifecycle_state NOT IN ('SOLD', 'AFTERCARE', 'RETIRED')) THEN
    RAISE EXCEPTION 'This vehicle is already in marketplace stock';
  END IF;
  v_item := trustride.fn_resource_marketplace_inventory_register(coalesce(v_obj.plate_number, 'MKT-' || substr(p_object_id::text, 1, 8)),
    v_obj.object_type, p_acquisition_source, p_acquisition_cost_kes, p_custody_estate_id);
  UPDATE trustride.resource_marketplace_inventory SET object_id = p_object_id WHERE inventory_item_id = v_item;
  PERFORM trustride.fn_resource_custody_transfer('MARKETPLACE_INVENTORY', v_item, v_by, p_custody_estate_id, v_by);
  RETURN v_item;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_resource_office_inventory_advance(p_item UUID, p_new_state trustride.resource_inventory_lifecycle_enum,
  p_valuation_kes NUMERIC, p_inspection_status TEXT, p_refurbishment_status TEXT, p_compliance_status TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_by UUID := trustride.fn_resource_office_gate();
BEGIN
  IF p_new_state IN ('LISTED', 'SOLD', 'AFTERCARE') THEN
    RAISE EXCEPTION 'Listing and sale happen through the Marketplace, not by hand';
  END IF;
  IF p_new_state = 'VALUED' AND (p_valuation_kes IS NULL OR p_valuation_kes <= 0) THEN RAISE EXCEPTION 'Enter the valuation'; END IF;
  PERFORM trustride.fn_resource_marketplace_inventory_advance(p_item, p_new_state, gen_random_uuid(), p_valuation_kes, p_inspection_status, p_refurbishment_status, p_compliance_status);
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Engine 4: vendor payouts and governor/intermediary capability records
-- ---------------------------------------------------------------------------
CREATE TABLE trustride.business_marketplace_payout (
  payout_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id         UUID NOT NULL UNIQUE REFERENCES trustride.business_order (order_id),
  vendor_user_id   UUID NOT NULL,
  gross_kes        NUMERIC(18,2) NOT NULL,
  commission_pct   NUMERIC(5,2) NOT NULL,
  commission_kes   NUMERIC(18,2) NOT NULL,
  payout_kes       NUMERIC(18,2) NOT NULL,
  status           TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'REQUESTED', 'PAID', 'FAILED')),
  provider_reference TEXT,
  failure_reason   TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  requested_at     TIMESTAMPTZ,
  paid_at          TIMESTAMPTZ,
  CONSTRAINT business_marketplace_payout_sum CHECK (commission_kes + payout_kes = gross_kes)
);
COMMENT ON TABLE trustride.business_marketplace_payout IS
  '[Trace: Founder ruling -- 5% on every vendor sale] What a vendor is owed for a completed Marketplace sale: gross less TrustRide''s commission.';
ALTER TABLE trustride.business_marketplace_payout ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_marketplace_payout_service_write ON trustride.business_marketplace_payout FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);
CREATE POLICY business_marketplace_payout_vendor_read ON trustride.business_marketplace_payout FOR SELECT TO trustride_authenticated USING (vendor_user_id = auth.uid());
CREATE POLICY business_marketplace_payout_office_read ON trustride.business_marketplace_payout FOR SELECT TO trustride_authenticated
  USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));
GRANT SELECT ON trustride.business_marketplace_payout TO trustride_authenticated;

-- D4: the data a governor may see is granted scope by scope; none by default.
CREATE TABLE trustride.business_governor_data_grant (
  grant_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  governor_engagement_id UUID NOT NULL REFERENCES trustride.business_governor_engagement (governor_engagement_id),
  data_scope             TEXT NOT NULL CHECK (data_scope IN ('AGGREGATE_SERVICE_VOLUMES', 'AGGREGATE_REVENUE_AND_TAX', 'FLEET_COMPLIANCE_SUMMARY', 'SAFETY_INCIDENT_SUMMARY')),
  jurisdiction           TEXT NOT NULL,
  granted_by             UUID NOT NULL,
  granted_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at             TIMESTAMPTZ,
  revoked_by             UUID
);
CREATE UNIQUE INDEX business_governor_data_grant_active_uq ON trustride.business_governor_data_grant (governor_engagement_id, data_scope) WHERE revoked_at IS NULL;
COMMENT ON TABLE trustride.business_governor_data_grant IS
  '[Trace: Founder decision D4 pending] Every scope is aggregate-only (no personal data, Data Protection Act 2019) and granted explicitly by TrustRide Office per engagement. With no grant, a governor''s surface shows nothing.';
ALTER TABLE trustride.business_governor_data_grant ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_governor_data_grant_service_write ON trustride.business_governor_data_grant FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);
CREATE POLICY business_governor_data_grant_office_read ON trustride.business_governor_data_grant FOR SELECT TO trustride_authenticated
  USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));
GRANT SELECT ON trustride.business_governor_data_grant TO trustride_authenticated;

ALTER TABLE trustride.business_intermediary_engagement ADD COLUMN referral_code TEXT UNIQUE;
CREATE TABLE trustride.business_intermediary_referral (
  referral_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  intermediary_engagement_id UUID NOT NULL REFERENCES trustride.business_intermediary_engagement (intermediary_engagement_id),
  referred_user_id           UUID NOT NULL UNIQUE,   -- an actor is attributed to one intermediary, once
  referred_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE trustride.business_intermediary_referral ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_intermediary_referral_service_write ON trustride.business_intermediary_referral FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);
CREATE POLICY business_intermediary_referral_office_read ON trustride.business_intermediary_referral FOR SELECT TO trustride_authenticated
  USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));
GRANT SELECT ON trustride.business_intermediary_referral TO trustride_authenticated;

-- ---------------------------------------------------------------------------
-- 4. Engine 4: Marketplace purchase lifecycle
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_business_marketplace_reserve(p_buyer UUID, p_listing_id UUID, p_notes TEXT, p_correlation UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_l RECORD;
  v_order UUID;
BEGIN
  SELECT * INTO v_l FROM trustride.service_marketplace_listing WHERE listing_id = p_listing_id;
  IF v_l.listing_id IS NULL OR v_l.listing_status <> 'LISTED' THEN RAISE EXCEPTION 'This vehicle is no longer available'; END IF;
  IF v_l.vendor_user_id = p_buyer THEN RAISE EXCEPTION 'You cannot buy your own listing'; END IF;
  IF trustride.fn_user_payment_msisdn(p_buyer) IS NULL THEN
    RAISE EXCEPTION 'Add and verify your phone number first -- it is how TrustRide reaches you about this vehicle';
  END IF;
  v_order := trustride.fn_business_order_place(p_buyer, 'CUSTOMER', 'MARKETPLACE-ITEM-SALE', 'MARKETPLACE',
    jsonb_build_array(jsonb_build_object('line_description', v_l.title, 'quantity', 1, 'scope_detail', jsonb_build_object(
      'listing_id', v_l.listing_id, 'listing_type', v_l.listing_type, 'vehicle_category', v_l.vehicle_category,
      'price_kes', v_l.list_price_kes, 'vendor_user_id', v_l.vendor_user_id, 'commission_pct', v_l.commission_pct,
      'inventory_item_id', v_l.inventory_item_id, 'buyer_notes', p_notes))),
    'MARKETPLACE_PURCHASE_ORDER', 'KISUMU_COUNTY', p_correlation);
  -- Held while TrustRide Office confirms availability and viewing.
  PERFORM trustride.fn_service_marketplace_listing_reserve(p_listing_id, v_order,
    trustride.fn_business_working_deadline(now(), coalesce(trustride.fn_business_config('ACTOR_REQUEST_SLA_DEADLINE_WORKING_DAYS')::int, 3)));
  RETURN v_order;
END;
$$;

-- Office confirmed the reservation: payment is due.
CREATE OR REPLACE FUNCTION trustride.fn_business_marketplace_purchase_confirmed(p_order_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_o RECORD;
  v_scope JSONB;
  v_price NUMERIC;
  v_bank BOOLEAN;
  v_until TIMESTAMPTZ := now() + make_interval(hours => trustride.fn_business_config_num('MARKETPLACE_PAYMENT_WINDOW_HOURS', 72)::int);
BEGIN
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = p_order_id;
  SELECT scope_detail || jsonb_build_object('line_description', line_description) INTO v_scope FROM trustride.business_order_line WHERE order_id = p_order_id ORDER BY line_sequence LIMIT 1;
  v_price := (v_scope->>'price_kes')::numeric;
  v_bank := v_price > trustride.fn_business_config_num('PAYMENT_STK_MAX_KES', 250000);
  UPDATE trustride.business_order SET status = 'AWAITING_PAYMENT', order_stage = 'PAYMENT_SETTLEMENT', closed_at = NULL, updated_at = now() WHERE order_id = p_order_id;
  INSERT INTO trustride.business_settlement (order_id, computed_total_fare_kes, payment_rail)
  VALUES (p_order_id, v_price, (CASE WHEN v_bank THEN 'BANK_TRANSFER' ELSE 'MPESA_C2B_STK' END)::trustride.business_payment_rail_enum)
  ON CONFLICT (order_id) DO NOTHING;
  PERFORM trustride.fn_service_marketplace_listing_extend((v_scope->>'listing_id')::uuid, p_order_id, v_until);
  PERFORM trustride.fn_business_progress_emit(p_order_id, 'PURCHASE_CONFIRMED', jsonb_build_object('amount_kes', v_price, 'bank_transfer', v_bank,
    'pay_by', v_until, 'title', v_scope->>'line_description', 'notify_office', v_bank));
  IF NOT v_bank THEN
    PERFORM trustride.fn_business_payment_request(p_order_id);
  END IF;
END;
$$;

-- What a settlement sets in motion: for a Marketplace purchase, the sale.
CREATE OR REPLACE FUNCTION trustride.fn_business_settled_followup(p_order_id UUID, p_payload JSONB)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_o RECORD;
  v_scope JSONB;
BEGIN
  UPDATE trustride.business_settlement SET payment_rail = CASE WHEN p_payload->>'payment_rail' = 'BANK_TRANSFER' THEN 'BANK_TRANSFER' ELSE payment_rail END::trustride.business_payment_rail_enum
  WHERE order_id = p_order_id;
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = p_order_id;
  IF v_o.order_root_type = 'MARKETPLACE_PURCHASE_ORDER' THEN
    SELECT scope_detail || jsonb_build_object('line_description', line_description) INTO v_scope FROM trustride.business_order_line WHERE order_id = p_order_id ORDER BY line_sequence LIMIT 1;
    UPDATE trustride.business_order SET status = 'SETTLED', order_stage = 'FULFILMENT', updated_at = now() WHERE order_id = p_order_id;
    PERFORM trustride.fn_service_marketplace_listing_sell((v_scope->>'listing_id')::uuid, v_o.correlation_id);
    IF v_scope->>'vendor_user_id' IS NOT NULL THEN
      INSERT INTO trustride.business_marketplace_payout (order_id, vendor_user_id, gross_kes, commission_pct, commission_kes, payout_kes)
      SELECT p_order_id, (v_scope->>'vendor_user_id')::uuid, g, pct, round(g * pct / 100.0, 2), g - round(g * pct / 100.0, 2)
      FROM (SELECT (v_scope->>'price_kes')::numeric AS g, coalesce((v_scope->>'commission_pct')::numeric,
              trustride.fn_business_config_num('MARKETPLACE_VENDOR_COMMISSION_PCT', 5)) AS pct) x
      ON CONFLICT (order_id) DO NOTHING;
    END IF;
    PERFORM trustride.fn_business_progress_emit(p_order_id, 'PURCHASE_PAID', jsonb_build_object('title', v_scope->>'line_description',
      'vendor_user_id', v_scope->>'vendor_user_id'));
  END IF;
END;
$$;

-- The sale was recorded at settlement; this signal is now an
-- acknowledgement (it previously created an order with no requester).
CREATE OR REPLACE FUNCTION trustride.fn_business_marketplace_listing_sold_accept(p_signal_id uuid)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'no RECEIVED signal %', p_signal_id; END IF;
  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(),
    payload_out = jsonb_build_object('listing_id', v_payload->>'listing_id', 'recorded_at_settlement', true) WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

-- Handover: TrustRide Office (own stock) or the vendor (their listing).
CREATE OR REPLACE FUNCTION trustride.fn_business_marketplace_handover(p_order_id UUID, p_actor UUID, p_office BOOLEAN, p_notes TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_o RECORD;
  v_scope JSONB;
  v_p RECORD;
BEGIN
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = p_order_id FOR UPDATE;
  SELECT scope_detail || jsonb_build_object('line_description', line_description) INTO v_scope FROM trustride.business_order_line WHERE order_id = p_order_id ORDER BY line_sequence LIMIT 1;
  IF v_o.order_root_type <> 'MARKETPLACE_PURCHASE_ORDER' OR v_o.status <> 'SETTLED' THEN
    RAISE EXCEPTION 'Only a paid Marketplace purchase can be handed over';
  END IF;
  IF NOT p_office AND (v_scope->>'vendor_user_id') IS DISTINCT FROM p_actor::text THEN
    RAISE EXCEPTION 'Only the seller confirms handover';
  END IF;
  UPDATE trustride.business_order SET status = 'COMPLETED', order_stage = 'REVIEW_RATE_SUPPORT', status_reason = p_notes, updated_at = now() WHERE order_id = p_order_id;
  SELECT * INTO v_p FROM trustride.business_marketplace_payout WHERE order_id = p_order_id AND status IN ('PENDING', 'FAILED');
  IF v_p.payout_id IS NOT NULL THEN
    UPDATE trustride.business_marketplace_payout SET status = 'REQUESTED', requested_at = now() WHERE payout_id = v_p.payout_id;
    INSERT INTO trustride.business_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (v_o.correlation_id, 'TRS026_ENG006_INTG', 'VENDOR_PAYOUT_REQUESTED',
      jsonb_build_object('payout_id', v_p.payout_id, 'order_id', p_order_id, 'vendor_user_id', v_p.vendor_user_id, 'amount_kes', v_p.payout_kes,
        'remarks', 'TrustRide sale ' || v_o.order_code),
      'VENDOR_PAYOUT_REQUESTED:' || v_p.payout_id::text || ':' || extract(epoch FROM clock_timestamp())::text);
  END IF;
  PERFORM trustride.fn_business_progress_emit(p_order_id, 'HANDED_OVER', jsonb_build_object('title', v_scope->>'line_description'));
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_vendor_payout_result_accept(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_type TEXT;
BEGIN
  SELECT payload_in, signal_type INTO v_payload, v_type FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'no RECEIVED signal %', p_signal_id; END IF;
  UPDATE trustride.business_marketplace_payout
  SET status = CASE WHEN v_type = 'VENDOR_PAYOUT_COMPLETED' THEN 'PAID' ELSE 'FAILED' END,
      paid_at = CASE WHEN v_type = 'VENDOR_PAYOUT_COMPLETED' THEN now() END,
      provider_reference = v_payload->>'provider_reference', failure_reason = v_payload->>'reason'
  WHERE payout_id = (v_payload->>'payout_id')::uuid;
  IF v_type = 'VENDOR_PAYOUT_FAILED' THEN
    PERFORM trustride.fn_present_notify_office('Vendor payout failed', coalesce(v_payload->>'reason', 'unknown') || ' -- retry from the Admin Console',
      'PAYOUT_EXCEPTION', (v_payload->>'order_id')::uuid);
  END IF;
  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_vendor_payout_retry(p_payout_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_p RECORD;
BEGIN
  IF NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN RAISE EXCEPTION 'Payout retries are a TrustRide Office function'; END IF;
  SELECT * INTO v_p FROM trustride.business_marketplace_payout WHERE payout_id = p_payout_id AND status = 'FAILED';
  IF v_p.payout_id IS NULL THEN RAISE EXCEPTION 'Only a failed payout can be retried'; END IF;
  UPDATE trustride.business_marketplace_payout SET status = 'REQUESTED', requested_at = now(), failure_reason = NULL WHERE payout_id = p_payout_id;
  INSERT INTO trustride.business_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_payout_id, 'TRS026_ENG006_INTG', 'VENDOR_PAYOUT_REQUESTED',
    jsonb_build_object('payout_id', p_payout_id, 'order_id', v_p.order_id, 'vendor_user_id', v_p.vendor_user_id, 'amount_kes', v_p.payout_kes,
      'remarks', 'TrustRide sale payout'),
    'VENDOR_PAYOUT_REQUESTED:' || p_payout_id::text || ':' || extract(epoch FROM clock_timestamp())::text);
END;
$$;

-- Engine 6: Daraja B2C payout to the vendor's verified phone.
CREATE OR REPLACE FUNCTION trustride.fn_integration_vendor_payout_requested_accept(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
DECLARE
  v_payload JSONB;
  v_corr UUID;
  v_msisdn TEXT;
  v_mode trustride.integration_adapter_type_enum := trustride.fn_integration_adapter_mode('PAYMENT_GATEWAY');
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_corr FROM trustride.integration_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'no RECEIVED signal %', p_signal_id; END IF;
  v_msisdn := trustride.fn_user_payment_msisdn((v_payload->>'vendor_user_id')::uuid);
  IF v_msisdn IS NULL THEN
    INSERT INTO trustride.integration_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (v_corr, 'TRS026_ENG004_BUS', 'VENDOR_PAYOUT_FAILED', v_payload || jsonb_build_object('reason', 'VENDOR_HAS_NO_VERIFIED_PHONE'),
      'VENDOR_PAYOUT_FAILED:' || p_signal_id::text);
  ELSIF v_mode = 'SIMULATOR' THEN
    INSERT INTO trustride.integration_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (v_corr, 'TRS026_ENG004_BUS', 'VENDOR_PAYOUT_COMPLETED', v_payload || jsonb_build_object('provider_reference', 'SIM-B2C-' || encode(gen_random_bytes(4), 'hex')),
      'VENDOR_PAYOUT_COMPLETED:' || p_signal_id::text);
  ELSE
    PERFORM trustride.fn_integration_outbound_enqueue('PAYMENT_GATEWAY', 'B2C_PAYOUT',
      jsonb_build_object('payout_id', v_payload->>'payout_id', 'order_id', v_payload->>'order_id', 'vendor_user_id', v_payload->>'vendor_user_id',
        'msisdn', v_msisdn, 'amount', floor((v_payload->>'amount_kes')::numeric)::int, 'remarks', v_payload->>'remarks'),
      'VENDOR_PAYOUT', (v_payload->>'payout_id')::uuid, v_corr);
  END IF;
  UPDATE trustride.integration_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_integration_payout_outcome(p_request trustride.integration_outbound_request, p_final_success BOOLEAN, p_final_failure BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  IF p_final_success OR p_final_failure THEN
    INSERT INTO trustride.integration_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (p_request.correlation_id, 'TRS026_ENG004_BUS', CASE WHEN p_final_success THEN 'VENDOR_PAYOUT_COMPLETED' ELSE 'VENDOR_PAYOUT_FAILED' END,
      p_request.payload || jsonb_build_object('provider_reference', p_request.provider_reference, 'reason', p_request.last_error),
      'VENDOR_PAYOUT_RESULT:' || p_request.request_id::text);
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Engine 4: approval activates the approved capability
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_business_actor_request_decide(p_order_id uuid, p_decision trustride.business_partnership_response_status_enum, p_notes text DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_order RECORD;
  v_scope JSONB;
  v_actor_id UUID;
  v_activate trustride.business_user_type_domain_enum;
  v_line RECORD;
  v_estate UUID;
  v_fleet UUID;
BEGIN
  IF NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']) THEN
    RAISE EXCEPTION 'fn_business_actor_request_decide: only TrustRide Office authority may decide actor requests';
  END IF;
  SELECT * INTO v_order FROM trustride.business_order WHERE order_id = p_order_id;
  IF v_order.order_id IS NULL OR v_order.order_root_type = 'SERVICE_ORDER' THEN
    RAISE EXCEPTION 'fn_business_actor_request_decide: % is not an actor request', p_order_id;
  END IF;
  IF v_order.requester_user_id = v_caller AND NOT trustride.fn_am_i_role(ARRAY['FOUNDER']) THEN
    RAISE EXCEPTION 'fn_business_actor_request_decide: you cannot decide your own request';
  END IF;

  PERFORM trustride.fn_business_partnership_response_decide(p_order_id, p_decision, v_caller, p_notes);
  SELECT coalesce(scope_detail, '{}'::jsonb) INTO v_scope FROM trustride.business_order_line WHERE order_id = p_order_id ORDER BY line_sequence LIMIT 1;
  v_scope := coalesce(v_scope, '{}'::jsonb);

  IF p_decision = 'ACCEPTED' THEN
    v_activate := (CASE v_order.order_root_type
      WHEN 'RESOURCE_PARTNERSHIP_REQUEST' THEN 'PARTNER'
      WHEN 'VENDOR_LISTING_REQUEST' THEN 'PARTNER'
      WHEN 'REGULATORY_ACCESS_REQUEST' THEN 'GOVERNOR'
      WHEN 'FACILITATION_REQUEST' THEN 'INTERMEDIARY'
      WHEN 'OFFICE_ACCESS_REQUEST' THEN CASE WHEN v_scope->>'office_surface' = 'OPERATOR_APP' THEN 'OPERATOR' END
    END)::trustride.business_user_type_domain_enum;
    IF v_activate IS NOT NULL THEN
      INSERT INTO trustride.business_actor_registration (user_id, user_type_domain, registration_status, terms_summary)
      VALUES (v_order.requester_user_id, v_activate, 'ACTIVE', v_order.order_root_type::text || ' ' || v_order.order_code)
      ON CONFLICT (user_id, user_type_domain) DO UPDATE SET registration_status = 'ACTIVE'
      RETURNING actor_registration_id INTO v_actor_id;
    END IF;

    CASE v_order.order_root_type
      WHEN 'RESOURCE_PARTNERSHIP_REQUEST' THEN
        IF NOT EXISTS (SELECT 1 FROM trustride.business_partner_agreement WHERE actor_registration_id = v_actor_id AND status = 'ACTIVE'
                         AND partner_category <> 'VENDOR') THEN
          INSERT INTO trustride.business_partner_agreement (actor_registration_id, partner_category, agreement_type, agreement_terms, start_date)
          VALUES (v_actor_id, coalesce(nullif(v_scope->>'partner_category', ''), CASE WHEN v_scope ? 'contribution_object_id' THEN 'FLEET_CONTRIBUTOR' ELSE 'STRATEGIC_COLLABORATOR' END)::trustride.business_partner_category_enum,
            'RESOURCE_PARTNERSHIP', jsonb_build_object('request', v_order.order_code, 'scope', v_scope), current_date);
        END IF;
        -- Contributed vehicles enter the fleet register in the partner's ownership.
        FOR v_line IN SELECT scope_detail FROM trustride.business_order_line WHERE order_id = p_order_id AND scope_detail ? 'contribution_object_id' ORDER BY line_sequence LOOP
          v_estate := coalesce((v_line.scope_detail->>'estate_id')::uuid,
            (SELECT estate_id FROM trustride.resource_estate_register WHERE active AND estate_type = 'OPERATING_HUB' ORDER BY created_at LIMIT 1));
          IF v_estate IS NULL THEN
            RAISE EXCEPTION 'Register an operating hub before accepting vehicle contributions';
          END IF;
          v_fleet := trustride.fn_resource_office_fleet_register((v_line.scope_detail->>'contribution_object_id')::uuid,
            (v_line.scope_detail->>'capacity_class')::trustride.resource_capacity_class_enum, 'PARTNER_CONTRIBUTED', v_estate,
            coalesce(v_line.scope_detail->>'inspection_status', 'PENDING'), coalesce(v_line.scope_detail->>'insurance_status', 'PENDING'));
        END LOOP;
      WHEN 'VENDOR_LISTING_REQUEST' THEN
        IF NOT EXISTS (SELECT 1 FROM trustride.business_partner_agreement WHERE actor_registration_id = v_actor_id AND status = 'ACTIVE' AND partner_category = 'VENDOR') THEN
          INSERT INTO trustride.business_partner_agreement (actor_registration_id, partner_category, agreement_type, agreement_terms, start_date)
          VALUES (v_actor_id, 'VENDOR', 'MARKETPLACE_VENDOR_LISTING',
            jsonb_build_object('request', v_order.order_code,
              'commission_pct', trustride.fn_business_config_num('MARKETPLACE_VENDOR_COMMISSION_PCT', 5),
              'commission_basis', 'EVERY_COMPLETED_SALE', 'vehicle_category', v_scope->>'vehicle_category', 'scope', v_scope),
            current_date);
        END IF;
      WHEN 'REGULATORY_ACCESS_REQUEST' THEN
        IF NOT EXISTS (SELECT 1 FROM trustride.business_governor_engagement WHERE actor_registration_id = v_actor_id) THEN
          PERFORM trustride.fn_business_governor_engagement_open(v_actor_id, current_date, NULL,
            coalesce(v_scope->>'oversight_scope', v_scope->>'authority', 'Oversight -- data scopes granted by TrustRide Office'));
        ELSE
          UPDATE trustride.business_governor_engagement SET engagement_status = 'ACTIVE' WHERE actor_registration_id = v_actor_id;
        END IF;
      WHEN 'FACILITATION_REQUEST' THEN
        IF NOT EXISTS (SELECT 1 FROM trustride.business_intermediary_engagement WHERE actor_registration_id = v_actor_id) THEN
          PERFORM trustride.fn_business_intermediary_engagement_open(v_actor_id,
            CASE WHEN v_scope->>'intermediary_type' IN ('BROKER', 'AGENT', 'REFERRAL_PARTNER') THEN v_scope->>'intermediary_type' ELSE 'REFERRAL_PARTNER' END,
            current_date);
        END IF;
        UPDATE trustride.business_intermediary_engagement SET engagement_status = 'ACTIVE',
          referral_code = coalesce(referral_code, 'TR-' || upper(substr(encode(extensions.gen_random_bytes(4), 'hex'), 1, 6)))
        WHERE actor_registration_id = v_actor_id;
      WHEN 'OFFICE_ACCESS_REQUEST' THEN
        IF v_scope->>'office_surface' IN ('ADMIN_CONSOLE', 'EXECUTIVE_DASHBOARD') THEN
          PERFORM trustride.fn_role_assign(v_order.requester_user_id,
            CASE v_scope->>'office_surface' WHEN 'ADMIN_CONSOLE' THEN 'ADMINISTRATOR' ELSE 'EXECUTIVE' END);
        END IF;
      WHEN 'MARKETPLACE_PURCHASE_ORDER' THEN
        PERFORM trustride.fn_business_marketplace_purchase_confirmed(p_order_id);
      ELSE
        NULL;  -- ACADEMY_ENROLLMENT_REQUEST: the decision itself is the outcome (enrolled), notified below
    END CASE;
  ELSIF v_order.order_root_type = 'MARKETPLACE_PURCHASE_ORDER' THEN
    -- A declined reservation returns the vehicle to sale.
    PERFORM trustride.fn_service_marketplace_listing_release((v_scope->>'listing_id')::uuid, p_order_id);
  END IF;
  -- DECLINED leaves any pending environment PENDING: the actor may amend and
  -- re-submit (Sec.4.2-4.4). Nothing is closed off.

  INSERT INTO trustride.business_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v_order.correlation_id, 'TRS026_ENG011_PRESENT', 'ACTOR_REQUEST_DECIDED',
    jsonb_build_object('order_id', v_order.order_id, 'order_code', v_order.order_code, 'order_root_type', v_order.order_root_type,
                       'decision', p_decision, 'notes', p_notes, 'requester_user_id', v_order.requester_user_id),
    'ACTOR_REQUEST_DECIDED:' || v_order.order_id::text);
END;
$$;

-- Closing a Marketplace purchase (cancelled, expired, declined) returns the
-- vehicle to sale; everything else closes as before.
DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_business_order_close(uuid,trustride.business_order_status_enum,text,text,boolean)'::regprocedure) INTO v_def;
  IF position('fn_service_marketplace_listing_release' IN v_def) = 0 THEN
    v_def := replace(v_def, E'  UPDATE trustride.business_order SET status = p_status, status_reason = p_reason, closed_at = now(), updated_at = now() WHERE order_id = p_order_id;',
      E'  IF v_o.order_root_type = ''MARKETPLACE_PURCHASE_ORDER'' THEN\n'
      || E'    PERFORM trustride.fn_service_marketplace_listing_release((l.scope_detail->>''listing_id'')::uuid, p_order_id)\n'
      || E'    FROM trustride.business_order_line l WHERE l.order_id = p_order_id;\n'
      || E'    UPDATE trustride.business_partnership_response SET response_status = ''DECLINED'', responded_at = now(), response_notes = p_reason\n'
      || E'    WHERE order_id = p_order_id AND response_status IN (''SUBMITTED'', ''UNDER_REVIEW'');\n'
      || E'  END IF;\n'
      || E'  UPDATE trustride.business_order SET status = p_status, status_reason = p_reason, closed_at = now(), updated_at = now() WHERE order_id = p_order_id;');
    IF position('fn_service_marketplace_listing_release' IN v_def) = 0 THEN RAISE EXCEPTION 'order close patch did not apply'; END IF;
    EXECUTE v_def;
  END IF;
END;
$patch$;

-- Unpaid confirmed reservations expire; the vehicle returns to sale.
CREATE OR REPLACE FUNCTION trustride.fn_business_marketplace_sweep()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  r RECORD;
  n INTEGER := 0;
BEGIN
  FOR r IN SELECT o.order_id FROM trustride.business_order o
           JOIN trustride.business_order_line l ON l.order_id = o.order_id
           JOIN trustride.service_marketplace_listing ml ON ml.listing_id = (l.scope_detail->>'listing_id')::uuid
           WHERE o.order_root_type = 'MARKETPLACE_PURCHASE_ORDER' AND o.status = 'AWAITING_PAYMENT' AND ml.reserved_until < now() LOOP
    BEGIN
      PERFORM trustride.fn_business_order_close(r.order_id, 'EXPIRED', 'Payment was not received within the reservation window', 'EXPIRED', TRUE);
      n := n + 1;
    EXCEPTION WHEN OTHERS THEN
      PERFORM trustride.fn_present_notify_office('Marketplace sweep error', SQLERRM, 'PLATFORM_EXCEPTION', r.order_id);
    END;
  END LOOP;
  RETURN n;
END;
$$;
SELECT cron.schedule('trustride_marketplace_sweep', '*/5 * * * *', 'SELECT trustride.fn_business_marketplace_sweep();');

-- Intermediary referral attribution: any verified actor may name the
-- intermediary who brought them, once.
CREATE OR REPLACE FUNCTION trustride.fn_business_referral_apply(p_user UUID, p_code TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_e RECORD;
  v_id UUID;
BEGIN
  SELECT e.*, a.user_id AS intermediary_user_id INTO v_e FROM trustride.business_intermediary_engagement e
  JOIN trustride.business_actor_registration a ON a.actor_registration_id = e.actor_registration_id
  WHERE e.referral_code = upper(trim(p_code)) AND e.engagement_status = 'ACTIVE';
  IF v_e.intermediary_engagement_id IS NULL THEN RAISE EXCEPTION 'That referral code is not active'; END IF;
  IF v_e.intermediary_user_id = p_user THEN RAISE EXCEPTION 'You cannot refer yourself'; END IF;
  IF EXISTS (SELECT 1 FROM trustride.business_intermediary_referral WHERE referred_user_id = p_user) THEN
    RAISE EXCEPTION 'A referral is already recorded for you';
  END IF;
  INSERT INTO trustride.business_intermediary_referral (intermediary_engagement_id, referred_user_id) VALUES (v_e.intermediary_engagement_id, p_user)
  RETURNING referral_id INTO v_id;
  RETURN v_id;
END;
$$;

-- Governor data rights (Office).
CREATE OR REPLACE FUNCTION trustride.fn_business_governor_scope_set(p_governor_user_id UUID, p_scope TEXT, p_grant BOOLEAN, p_jurisdiction TEXT DEFAULT 'KISUMU_COUNTY')
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_e UUID;
BEGIN
  IF NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN RAISE EXCEPTION 'Governor data rights are granted by TrustRide Office'; END IF;
  SELECT g.governor_engagement_id INTO v_e FROM trustride.business_governor_engagement g
  JOIN trustride.business_actor_registration a ON a.actor_registration_id = g.actor_registration_id
  WHERE a.user_id = p_governor_user_id AND g.engagement_status = 'ACTIVE';
  IF v_e IS NULL THEN RAISE EXCEPTION 'No active governor engagement for this identity'; END IF;
  IF p_grant THEN
    INSERT INTO trustride.business_governor_data_grant (governor_engagement_id, data_scope, jurisdiction, granted_by)
    VALUES (v_e, p_scope, p_jurisdiction, auth.uid()) ON CONFLICT DO NOTHING;
  ELSE
    UPDATE trustride.business_governor_data_grant SET revoked_at = now(), revoked_by = auth.uid()
    WHERE governor_engagement_id = v_e AND data_scope = p_scope AND revoked_at IS NULL;
  END IF;
  PERFORM trustride.fn_audit_log_append('business_governor_data_grant', v_e, CASE WHEN p_grant THEN 'GOVERNOR_SCOPE_GRANTED' ELSE 'GOVERNOR_SCOPE_REVOKED' END,
    auth.uid(), 'USER', NULL, 'TRUSTRIDE_OFFICE', NULL, jsonb_build_object('scope', p_scope, 'jurisdiction', p_jurisdiction));
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Foundation: Office user management
-- ---------------------------------------------------------------------------
-- Role hierarchy: the Founder grants Office authority; Administrators grant
-- operational roles only. Nobody grants the Founder role.
CREATE OR REPLACE FUNCTION trustride.fn_role_grant_checked(p_user_id UUID, p_role_code TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  IF p_role_code = 'FOUNDER' THEN RAISE EXCEPTION 'The Founder role is never granted'; END IF;
  IF p_role_code IN ('ADMINISTRATOR', 'EXECUTIVE') AND NOT trustride.fn_am_i_role(ARRAY['FOUNDER']) THEN
    RAISE EXCEPTION 'Only the Founder grants Office authority roles';
  END IF;
  IF NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN RAISE EXCEPTION 'Role management is a TrustRide Office function'; END IF;
  IF NOT EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id = p_user_id AND status = 'ACTIVE' AND identity_primitive = 'PERSON') THEN
    RAISE EXCEPTION 'Roles are granted to verified people only';
  END IF;
  IF EXISTS (SELECT 1 FROM trustride.role_assignment ra JOIN trustride.role_definition rd ON rd.role_id = ra.role_id
             WHERE ra.user_id = p_user_id AND rd.role_code = p_role_code AND ra.status = 'ACTIVE' AND (ra.valid_to IS NULL OR ra.valid_to > now())) THEN
    RAISE EXCEPTION 'This person already holds %', p_role_code;
  END IF;
  RETURN trustride.fn_role_assign(p_user_id, p_role_code);
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_role_revoke(p_user_id UUID, p_role_code TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  IF p_role_code = 'FOUNDER' THEN RAISE EXCEPTION 'The Founder role is never revoked here'; END IF;
  IF p_role_code IN ('ADMINISTRATOR', 'EXECUTIVE') AND NOT trustride.fn_am_i_role(ARRAY['FOUNDER']) THEN
    RAISE EXCEPTION 'Only the Founder revokes Office authority roles';
  END IF;
  IF NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN RAISE EXCEPTION 'Role management is a TrustRide Office function'; END IF;
  UPDATE trustride.role_assignment ra SET status = 'REVOKED', valid_to = now()
  FROM trustride.role_definition rd WHERE rd.role_id = ra.role_id AND ra.user_id = p_user_id AND rd.role_code = p_role_code AND ra.status = 'ACTIVE';
  IF NOT FOUND THEN RAISE EXCEPTION 'This person does not hold %', p_role_code; END IF;
  PERFORM trustride.fn_audit_log_append('role_assignment', p_user_id, 'ROLE_REVOKED', auth.uid(), 'USER', NULL, 'TRUSTRIDE_OFFICE', NULL,
    jsonb_build_object('role_code', p_role_code));
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_user_suspend(p_user_id UUID, p_suspend BOOLEAN, p_reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  IF NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN RAISE EXCEPTION 'Suspension is a TrustRide Office function'; END IF;
  IF coalesce(trim(p_reason), '') = '' THEN RAISE EXCEPTION 'State the reason'; END IF;
  IF p_user_id = auth.uid() THEN RAISE EXCEPTION 'You cannot suspend yourself'; END IF;
  IF EXISTS (SELECT 1 FROM trustride.role_assignment ra JOIN trustride.role_definition rd ON rd.role_id = ra.role_id
             WHERE ra.user_id = p_user_id AND rd.role_code = 'FOUNDER' AND ra.status = 'ACTIVE') THEN
    RAISE EXCEPTION 'The Founder cannot be suspended';
  END IF;
  UPDATE trustride.platform_users SET status = CASE WHEN p_suspend THEN 'SUSPENDED' ELSE 'ACTIVE' END, updated_at = now()
  WHERE user_id = p_user_id AND status IN (CASE WHEN p_suspend THEN 'ACTIVE' ELSE 'SUSPENDED' END);
  IF NOT FOUND THEN RAISE EXCEPTION 'This identity is not %', CASE WHEN p_suspend THEN 'active' ELSE 'suspended' END; END IF;
  IF p_suspend THEN
    UPDATE trustride.present_shell_session SET session_status = 'ENDED', ended_at = now() WHERE user_id = p_user_id AND session_status = 'ACTIVE';
  END IF;
  PERFORM trustride.fn_audit_log_append('platform_users', p_user_id, CASE WHEN p_suspend THEN 'USER_SUSPENDED' ELSE 'USER_REINSTATED' END,
    auth.uid(), 'USER', NULL, 'TRUSTRIDE_OFFICE', NULL, jsonb_build_object('reason', p_reason));
END;
$$;

-- A suspended identity opens no shell.
DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_present_shell_session_open(trustride.present_top_shell_enum,trustride.present_sub_shell_enum,uuid,trustride.present_channel_type_enum,uuid,uuid,uuid)'::regprocedure) INTO v_def;
  IF position('SUSPENDED' IN v_def) = 0 THEN
    v_def := replace(v_def, E'  v_required_domain := (CASE p_sub_shell',
      E'  IF EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id IN (p_user_id, auth.uid()) AND status = ''SUSPENDED'') THEN\n'
      || E'    RAISE EXCEPTION ''This identity is suspended -- contact TrustRide Office'';\n'
      || E'  END IF;\n\n  v_required_domain := (CASE p_sub_shell');
    IF position('SUSPENDED' IN v_def) = 0 THEN RAISE EXCEPTION 'session open patch did not apply'; END IF;
    EXECUTE v_def;
  END IF;
END;
$patch$;

-- ---------------------------------------------------------------------------
-- 7. Inboxes and routes
-- ---------------------------------------------------------------------------
DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_business_inbox_process(uuid)'::regprocedure) INTO v_def;
  IF position('VENDOR_PAYOUT_COMPLETED' IN v_def) = 0 THEN
    v_def := replace(v_def, E'    ELSE\n      UPDATE trustride.business_event_inbox',
      E'    WHEN ''VENDOR_PAYOUT_COMPLETED'', ''VENDOR_PAYOUT_FAILED'' THEN v_result := trustride.fn_business_vendor_payout_result_accept(p_signal_id);\n    ELSE\n      UPDATE trustride.business_event_inbox');
    EXECUTE v_def;
  END IF;
  SELECT pg_get_functiondef('trustride.fn_integration_inbox_process(uuid)'::regprocedure) INTO v_def;
  IF position('VENDOR_PAYOUT_REQUESTED' IN v_def) = 0 THEN
    v_def := replace(v_def, E'    ELSE\n      UPDATE trustride.integration_event_inbox',
      E'    WHEN ''VENDOR_PAYOUT_REQUESTED'' THEN v_result := trustride.fn_integration_vendor_payout_requested_accept(p_signal_id);\n    ELSE\n      UPDATE trustride.integration_event_inbox');
    EXECUTE v_def;
  END IF;
END;
$patch$;

INSERT INTO trustride.routing_rule (event_type, source_engine, target_engine, route_priority)
SELECT v.e, v.s, v.t, 0
FROM (VALUES
  ('VENDOR_PAYOUT_REQUESTED', 'TRS026_ENG004_BUS', 'TRS026_ENG006_INTG'),
  ('VENDOR_PAYOUT_COMPLETED', 'TRS026_ENG006_INTG', 'TRS026_ENG004_BUS'),
  ('VENDOR_PAYOUT_FAILED', 'TRS026_ENG006_INTG', 'TRS026_ENG004_BUS')
) AS v(e, s, t)
WHERE NOT EXISTS (SELECT 1 FROM trustride.routing_rule r WHERE r.event_type = v.e AND r.source_engine = v.s AND r.target_engine = v.t);
SELECT trustride.fn_orch_destination_cache_sync();

-- ---------------------------------------------------------------------------
-- 8. Engine 11: verbs and messages
-- ---------------------------------------------------------------------------
DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  -- RESERVE_VEHICLE now reserves a specific listing.
  SELECT pg_get_functiondef('trustride.fn_present_capture_command(uuid,text,jsonb)'::regprocedure) INTO v_def;
  IF position('fn_business_marketplace_reserve' IN v_def) = 0 THEN
    v_def := regexp_replace(v_def,
      E'WHEN ''RESERVE_VEHICLE'' THEN\\s*?IF EXISTS .*?''MARKETPLACE_PURCHASE_ORDER''.*?v_command_id\\);',
      E'WHEN ''RESERVE_VEHICLE'' THEN\n        v_translated_signal_id := trustride.fn_business_marketplace_reserve(v_session.user_id, (p_command_payload->>''listing_id'')::uuid, p_command_payload->>''notes'', v_command_id);');
    IF position('fn_business_marketplace_reserve' IN v_def) = 0 THEN RAISE EXCEPTION 'reserve vehicle patch did not apply'; END IF;
    EXECUTE v_def;
  END IF;

  -- New progress messages.
  SELECT pg_get_functiondef('trustride.fn_present_order_progress_accept(uuid)'::regprocedure) INTO v_def;
  IF position('PURCHASE_CONFIRMED' IN v_def) = 0 THEN
    v_def := replace(v_def, E'    ELSE\n      v_c_title := NULL;',
      E'    WHEN ''PURCHASE_CONFIRMED'' THEN\n'
      || E'      v_c_title := ''Reservation confirmed'';\n'
      || E'      v_c_body := CASE WHEN coalesce((v_p->>''bank_transfer'')::boolean, false)\n'
      || E'        THEN format(''%s (%s) is held for you until %s. Pay KES %s by bank transfer -- TrustRide Office will send the account details.'', v_code, v_p->>''title'', to_char((v_p->>''pay_by'')::timestamptz AT TIME ZONE ''Africa/Nairobi'', ''Dy DD Mon HH24:MI''), v_p->>''amount_kes'')\n'
      || E'        ELSE format(''%s (%s) is held for you until %s. Approve the M-Pesa request for KES %s on your phone.'', v_code, v_p->>''title'', to_char((v_p->>''pay_by'')::timestamptz AT TIME ZONE ''Africa/Nairobi'', ''Dy DD Mon HH24:MI''), v_p->>''amount_kes'') END;\n'
      || E'      v_c_critical := TRUE;\n'
      || E'    WHEN ''PURCHASE_PAID'' THEN\n'
      || E'      v_c_title := ''Payment received'';\n'
      || E'      v_c_body := format(''%s is paid. The seller will arrange handover of %s.'', v_code, v_p->>''title'');\n'
      || E'      IF v_p->>''vendor_user_id'' IS NOT NULL THEN\n'
      || E'        INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, source_signal_correlation_id, category, critical)\n'
      || E'        VALUES ((v_p->>''vendor_user_id'')::uuid, ''TRUSTRIDE_MARKETPLACE'', ''VENDOR_APP'', ''Sold: '' || (v_p->>''title''), ''The buyer has paid. Arrange handover and confirm it in the Vendor App.'', v_corr, ''MARKETPLACE'', TRUE);\n'
      || E'      END IF;\n'
      || E'    WHEN ''HANDED_OVER'' THEN\n'
      || E'      v_c_title := ''Handover complete'';\n'
      || E'      v_c_body := format(''%s: %s is yours. Thank you for buying on TrustRide Marketplace.'', v_code, v_p->>''title'');\n'
      || E'    ELSE\n      v_c_title := NULL;');
    -- Marketplace buyers are addressed on the Marketplace surface.
    v_def := replace(v_def, E'VALUES ((v_p->>''requester_user_id'')::uuid, ''TRUSTRIDE_BUSINESS'', ''CUSTOMER_APP'', v_c_title, v_c_body, v_corr, ''ORDER'', v_c_critical);',
      E'VALUES ((v_p->>''requester_user_id'')::uuid,\n'
      || E'      (CASE WHEN v_p->>''service_code'' LIKE ''MARKETPLACE-%'' THEN ''TRUSTRIDE_MARKETPLACE'' ELSE ''TRUSTRIDE_BUSINESS'' END)::trustride.present_top_shell_enum,\n'
      || E'      (CASE WHEN v_p->>''service_code'' LIKE ''MARKETPLACE-%'' THEN ''MARKETPLACE_APP'' ELSE ''CUSTOMER_APP'' END)::trustride.present_sub_shell_enum,\n'
      || E'      v_c_title, v_c_body, v_corr, ''ORDER'', v_c_critical);');
    IF position('PURCHASE_CONFIRMED' IN v_def) = 0 OR position('MARKETPLACE_APP' IN v_def) = 0 THEN RAISE EXCEPTION 'order progress patch did not apply'; END IF;
    EXECUTE v_def;
  END IF;
END;
$patch$;

INSERT INTO trustride.present_shell_capability_registry (top_shell, sub_shell, command_type, permitted, requires_delegated_authority)
SELECT v.top::trustride.present_top_shell_enum, v.sub::trustride.present_sub_shell_enum, v.cmd, TRUE, FALSE
FROM (VALUES
  ('TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'CANCEL_ORDER'),
  ('TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'DELIST_OFFER'),
  ('TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'CONFIRM_HANDOVER'),
  ('TRUSTRIDE_BUSINESS', 'PARTNER_APP', 'SUBMIT_CONTRIBUTION'),
  ('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'APPLY_REFERRAL_CODE'),
  ('TRUSTRIDE_BUSINESS', 'PARTNER_APP', 'APPLY_REFERRAL_CODE'),
  ('TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'APPLY_REFERRAL_CODE'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ACQUIRE_INVENTORY'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ADVANCE_INVENTORY'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'PUBLISH_OFFER'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'DELIST_OFFER'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'CONFIRM_HANDOVER'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RETRY_VENDOR_PAYOUT'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'SET_GOVERNOR_SCOPE'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'GRANT_ROLE'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REVOKE_ROLE'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'SUSPEND_USER'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REINSTATE_USER'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_EXTERNAL_SYSTEM'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REVOKE_SYSTEM_CREDENTIAL'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'SET_ADAPTER')
) AS v(top, sub, cmd)
WHERE NOT EXISTS (SELECT 1 FROM trustride.present_shell_capability_registry r WHERE r.sub_shell = v.sub::trustride.present_sub_shell_enum AND r.command_type = v.cmd);

-- Vendor / Office: publish an offer.
CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_publish_offer(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_s RECORD;
  v_pct NUMERIC;
  v_item RECORD;
  v_listing UUID;
BEGIN
  SELECT * INTO v_s FROM trustride.present_shell_session WHERE session_id = p_session;
  IF v_s.sub_shell = 'VENDOR_APP' THEN
    SELECT (pa.agreement_terms->>'commission_pct')::numeric INTO v_pct
    FROM trustride.business_partner_agreement pa JOIN trustride.business_actor_registration a ON a.actor_registration_id = pa.actor_registration_id
    WHERE a.user_id = v_s.user_id AND a.registration_status = 'ACTIVE' AND pa.partner_category = 'VENDOR' AND pa.status = 'ACTIVE'
    ORDER BY pa.created_at DESC LIMIT 1;
    IF v_pct IS NULL THEN RAISE EXCEPTION 'Your vendor application must be approved before you can list'; END IF;
    IF p_payload->>'object_id' IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM trustride.object_registry WHERE object_id = (p_payload->>'object_id')::uuid AND custody_user_id = v_s.user_id) THEN
      RAISE EXCEPTION 'You can only list a vehicle registered in your custody';
    END IF;
    RETURN trustride.fn_service_marketplace_offer_publish('VENDOR_FACILITATED', v_s.user_id, p_payload->>'vehicle_category', p_payload->>'title',
      p_payload->>'description', (p_payload->>'price_kes')::numeric, (p_payload->>'object_id')::uuid, NULL, v_pct);
  END IF;
  -- TrustRide Office: own-marketplace stock that has passed compliance.
  SELECT * INTO v_item FROM trustride.resource_marketplace_inventory WHERE inventory_item_id = (p_payload->>'inventory_item_id')::uuid;
  IF v_item.inventory_item_id IS NULL OR v_item.lifecycle_state <> 'COMPLIANT' THEN
    RAISE EXCEPTION 'Only stock that has passed inspection, valuation, refurbishment and compliance can be listed';
  END IF;
  v_listing := trustride.fn_service_marketplace_offer_publish('OWN_MARKETPLACE', NULL, v_item.category, p_payload->>'title',
    p_payload->>'description', coalesce((p_payload->>'price_kes')::numeric, v_item.valuation_kes), v_item.object_id, v_item.inventory_item_id, NULL);
  PERFORM trustride.fn_resource_marketplace_inventory_advance(v_item.inventory_item_id, 'LISTED', p_command);
  RETURN v_listing;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_delist_offer(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_s RECORD;
BEGIN
  SELECT * INTO v_s FROM trustride.present_shell_session WHERE session_id = p_session;
  PERFORM trustride.fn_service_marketplace_listing_delist((p_payload->>'listing_id')::uuid, v_s.user_id, v_s.top_shell = 'TRUSTRIDE_OFFICE');
  RETURN (p_payload->>'listing_id')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_confirm_handover(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_s RECORD;
BEGIN
  SELECT * INTO v_s FROM trustride.present_shell_session WHERE session_id = p_session;
  PERFORM trustride.fn_business_marketplace_handover((p_payload->>'order_id')::uuid, v_s.user_id, v_s.top_shell = 'TRUSTRIDE_OFFICE', p_payload->>'notes');
  RETURN (p_payload->>'order_id')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_acquire_inventory(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_obj UUID := (p_payload->>'object_id')::uuid;
BEGIN
  IF v_obj IS NULL THEN
    v_obj := trustride.fn_registration_capture_object(p_payload->>'vehicle_category', p_payload->>'make', p_payload->>'model',
      (p_payload->>'year')::smallint, p_payload->>'plate_number', p_payload->>'serial_number', auth.uid());
  END IF;
  RETURN trustride.fn_resource_office_inventory_acquire(v_obj, coalesce(p_payload->>'acquisition_source', 'PURCHASE'),
    (p_payload->>'acquisition_cost_kes')::numeric, (p_payload->>'custody_estate_id')::uuid);
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_advance_inventory(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_resource_office_inventory_advance((p_payload->>'inventory_item_id')::uuid,
    (p_payload->>'new_state')::trustride.resource_inventory_lifecycle_enum, (p_payload->>'valuation_kes')::numeric,
    p_payload->>'inspection_status', p_payload->>'refurbishment_status', p_payload->>'compliance_status');
  RETURN (p_payload->>'inventory_item_id')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_retry_vendor_payout(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_business_vendor_payout_retry((p_payload->>'payout_id')::uuid);
  RETURN (p_payload->>'payout_id')::uuid;
END;
$$;

-- Partner: contribute vehicles (one order line per vehicle).
CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_submit_contribution(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_user UUID := (SELECT user_id FROM trustride.present_shell_session WHERE session_id = p_session);
  v_v JSONB;
  v_obj UUID;
  v_lines JSONB := '[]'::jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM trustride.business_actor_registration WHERE user_id = v_user AND user_type_domain = 'PARTNER' AND registration_status = 'ACTIVE') THEN
    RAISE EXCEPTION 'Contributions open once your partnership is approved';
  END IF;
  IF jsonb_array_length(coalesce(p_payload->'vehicles', '[]'::jsonb)) = 0 THEN RAISE EXCEPTION 'Add at least one vehicle'; END IF;
  FOR v_v IN SELECT * FROM jsonb_array_elements(p_payload->'vehicles') LOOP
    v_obj := coalesce((v_v->>'object_id')::uuid, trustride.fn_registration_capture_object(v_v->>'object_type', v_v->>'make', v_v->>'model',
      (v_v->>'year')::smallint, v_v->>'plate_number', NULL, v_user));
    v_lines := v_lines || jsonb_build_array(jsonb_build_object('line_description', 'Contributed ' || lower(v_v->>'object_type') || ' ' || coalesce(v_v->>'plate_number', ''),
      'quantity', 1, 'scope_detail', jsonb_build_object('contribution_object_id', v_obj, 'capacity_class', v_v->>'capacity_class',
        'estate_id', p_payload->>'estate_id', 'inspection_status', coalesce(v_v->>'inspection_status', 'PENDING'),
        'insurance_status', coalesce(v_v->>'insurance_status', 'PENDING'), 'partner_category', 'FLEET_CONTRIBUTOR')));
  END LOOP;
  RETURN trustride.fn_business_order_place(v_user, 'PARTNER', 'MARKETPLACE-RESOURCE-CONTRIBUTION', 'MARKETPLACE', v_lines,
    'RESOURCE_PARTNERSHIP_REQUEST', coalesce(p_payload->>'jurisdiction', 'KISUMU_COUNTY'), p_command);
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_apply_referral_code(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT trustride.fn_business_referral_apply((SELECT user_id FROM trustride.present_shell_session WHERE session_id = p_session), p_payload->>'referral_code');
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_set_governor_scope(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_business_governor_scope_set((p_payload->>'governor_user_id')::uuid, p_payload->>'data_scope',
    coalesce((p_payload->>'grant')::boolean, true), coalesce(p_payload->>'jurisdiction', 'KISUMU_COUNTY'));
  RETURN (p_payload->>'governor_user_id')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_grant_role(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT trustride.fn_role_grant_checked((p_payload->>'user_id')::uuid, p_payload->>'role_code');
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_revoke_role(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_role_revoke((p_payload->>'user_id')::uuid, p_payload->>'role_code');
  RETURN (p_payload->>'user_id')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_suspend_user(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_user_suspend((p_payload->>'user_id')::uuid, TRUE, p_payload->>'reason');
  RETURN (p_payload->>'user_id')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_reinstate_user(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_user_suspend((p_payload->>'user_id')::uuid, FALSE, p_payload->>'reason');
  RETURN (p_payload->>'user_id')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_register_external_system(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT trustride.fn_registration_capture_external_system(p_payload->>'system_name', p_payload->>'purpose', (p_payload->>'owner_entity_user_id')::uuid);
$$;

-- Issuing a system credential is deliberately NOT a captured command: a
-- secret must never be stored in a command record or a notification. The
-- Office screen calls fn_external_system_credential_issue directly (Office-
-- gated, audited) and shows the key exactly once.

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_revoke_system_credential(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_external_system_credential_revoke(p_payload->>'key_prefix');
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_set_adapter(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_integration_adapter_set((p_payload->>'port_code')::trustride.integration_port_code_enum,
    (p_payload->>'adapter_type')::trustride.integration_adapter_type_enum, p_payload->>'notes');
  RETURN NULL;
END;
$$;

-- A Marketplace buyer cancels from the Marketplace app.
-- (CANCEL_ORDER's handler already exists; the registry row above admits it
-- on MARKETPLACE_APP. Cancellation before payment returns the vehicle.)

-- ---------------------------------------------------------------------------
-- 9. Grants
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;

SELECT trustride.fn_platform_conformance_assert();
