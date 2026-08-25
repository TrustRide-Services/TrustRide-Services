-- ============================================================================
-- TRUSTRIDE SERVICES PLATFORM
-- ============================================================================
-- ENGINE CODE          : TRS026_ENG002_RESC (extension)
-- MIGRATION DATA
-- FILE NAME            : 20260824000004_engine002_resource_assignment_confirmed.sql
-- STATUS               : COMPLETE -- additive, no destructive changes.
-- CREATED AT           : 2026-08-24
-- ============================================================================
--
-- Companion to Engine 4's hardening pass (20260823000008, Correction 9):
-- Business's fn_business_resource_reserved_accept now emits a new signal,
-- RESOURCE_ASSIGNMENT_CONFIRMED, completing Article 20.2's second step ("the
-- reservation converts to a firm assignment once the requester accepts").
-- This file adds the Resources-domain receiver for that signal -- the
-- established pattern for one already-live engine's file adding a new
-- accept-handler for another engine's new signal (same pattern as Cost's own
-- extensions to fn_resource_assign).
--
-- Also hardens fn_resource_assignment_requested_accept (CREATE OR REPLACE,
-- same signature, safe) to thread order_line_id through to fn_resource_
-- reserve -- it was reading the payload before order_line_id existed on
-- that signal; now it does, so it should be carried through, matching the
-- Resources MNY-15 elevation's own Order-Line-bound design.
--
-- ============================================================================

CREATE OR REPLACE FUNCTION trustride.fn_resource_assignment_requested_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public, pg_temp
AS $$
DECLARE
  v_payload      JSONB;
  v_order_id     UUID;
  v_order_line_id UUID;
  v_capacity_class trustride.resource_capacity_class_enum;
  v_pickup_lat   NUMERIC;
  v_pickup_lon   NUMERIC;
  v_correlation_id UUID;
  v_best UUID;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_correlation_id FROM trustride.resource_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_resource_assignment_requested_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  v_order_id := (v_payload->>'order_id')::UUID;
  v_order_line_id := (v_payload->>'order_line_id')::UUID;
  v_capacity_class := (v_payload->>'required_capacity_class')::trustride.resource_capacity_class_enum;
  v_pickup_lat := (v_payload->'pickup_location'->>'latitude')::NUMERIC;
  v_pickup_lon := (v_payload->'pickup_location'->>'longitude')::NUMERIC;

  SELECT workforce_unit_id INTO v_best FROM trustride.fn_resource_discover(v_capacity_class, v_pickup_lat, v_pickup_lon) LIMIT 1;

  IF v_best IS NULL THEN
    UPDATE trustride.resource_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'RESOURCE_NOT_AVAILABLE', accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END IF;

  PERFORM trustride.fn_resource_reserve(v_best, v_order_id, v_correlation_id, '00000000-0000-0000-0000-000000000000'::uuid, v_order_line_id);

  UPDATE trustride.resource_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('workforce_unit_id', v_best) WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_assignment_requested_accept(UUID) IS
  '[Trace: §5.1 ASSIGNMENT_REQUESTED] Discovers the nearest AVAILABLE unit and reserves it automatically; rejects at the inbox if none exists, never silently. Hardening (2026-08-24): threads order_line_id through to fn_resource_reserve.';

CREATE OR REPLACE FUNCTION trustride.fn_resource_assignment_confirmed_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_correlation_id UUID;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_correlation_id FROM trustride.resource_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_resource_assignment_confirmed_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  PERFORM trustride.fn_resource_assign(
    (v_payload->>'workforce_unit_id')::uuid, (v_payload->>'order_id')::uuid, v_correlation_id, '00000000-0000-0000-0000-000000000000'::uuid,
    v_payload->>'origin_zone_code', v_payload->>'destination_zone_code',
    (v_payload->>'distance_km')::numeric, (v_payload->>'duration_min')::numeric,
    (v_payload->>'requester_user_id')::uuid, v_payload->>'jurisdiction', v_payload->>'engine_capacity',
    (v_payload->>'order_line_id')::uuid
  );

  UPDATE trustride.resource_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_assignment_confirmed_accept(UUID) IS
  '[Trace: Article 20.2, new signal per Engine 4''s Correction 9] Receives Business''s auto-confirmed RESOURCE_ASSIGNMENT_CONFIRMED and calls fn_resource_assign -- the real, complete conversion of a RESERVED unit into a firm ASSIGNED one, carrying trip context all the way to Cost''s own fare calculation.';

CREATE OR REPLACE FUNCTION trustride.fn_resource_inbox_process(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_signal_type TEXT;
  v_result TEXT;
BEGIN
  SELECT signal_type INTO v_signal_type FROM trustride.resource_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_signal_type IS NULL THEN
    RAISE EXCEPTION 'fn_resource_inbox_process: no RECEIVED signal %', p_signal_id;
  END IF;

  CASE v_signal_type
    WHEN 'ASSIGNMENT_REQUESTED' THEN v_result := trustride.fn_resource_assignment_requested_accept(p_signal_id);
    WHEN 'RESOURCE_ASSIGNMENT_CONFIRMED' THEN v_result := trustride.fn_resource_assignment_confirmed_accept(p_signal_id);
    WHEN 'JOB_COMPLETED' THEN v_result := trustride.fn_resource_job_completed_accept(p_signal_id);
    WHEN 'FLEET_VERIFICATION_UPDATED' THEN v_result := trustride.fn_resource_fleet_verification_updated_accept(p_signal_id);
    WHEN 'MARKETPLACE_LISTING_SOLD' THEN v_result := trustride.fn_resource_marketplace_listing_sold_accept(p_signal_id);
    ELSE
      UPDATE trustride.resource_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'UNREGISTERED_SIGNAL_TYPE:' || v_signal_type WHERE signal_id = p_signal_id;
      v_result := 'REJECTED';
  END CASE;

  RETURN v_result;
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_inbox_process(UUID) IS
  'Dispatches a RECEIVED resource_event_inbox row to the matching accept-handler by signal_type. Extended (2026-08-24) with RESOURCE_ASSIGNMENT_CONFIRMED.';

GRANT EXECUTE ON FUNCTION trustride.fn_resource_assignment_confirmed_accept(UUID) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_inbox_process(UUID) TO trs026_eng002_resc_service, trs026_eng007_orch_service;
