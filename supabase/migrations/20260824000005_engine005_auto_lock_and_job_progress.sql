-- ============================================================================
-- TRUSTRIDE SERVICES PLATFORM
-- ============================================================================
-- ENGINE CODE          : TRS026_ENG005_COST (extension)
-- MIGRATION DATA
-- FILE NAME            : 20260824000005_engine005_auto_lock_and_job_progress.sql
-- STATUS               : COMPLETE -- additive, no destructive changes.
-- CREATED AT           : 2026-08-24
-- ============================================================================
--
-- Found while hardening Engine 4 end-to-end: fn_cost_quote_lock (FARE_
-- ESTIMATED -> FARE_LOCKED, emits UNIT_PRICE_LOCKED) has never had any
-- caller anywhere in the real pipeline. Business's own fn_business_unit_
-- price_locked_accept is fully built and correct, but nothing ever produced
-- the signal it waits for -- every real quote would sit at FARE_ESTIMATED
-- forever, business_order.quote_id would never be set, and no settlement
-- would ever open. The quote_state model's FARE_ESTIMATED step exists to
-- let a requester review and accept a fare before it locks -- that requires
-- a real UI decision point, which does not exist yet (Engine 11 is
-- unbuilt). Consistent with the exact same precedent already established
-- this session (Resources auto-picks the nearest resource, Business auto-
-- confirms the assignment) -- rather than leave the pipeline stalled on a
-- human interaction that has nowhere to happen yet, fn_cost_resource_
-- dispatch_initiated_accept now locks the quote immediately upon issuing
-- it. This is named explicitly as a stand-in: once Engine 11 exists, the
-- auto-lock call below is the one line to remove in favor of a real
-- requester-driven fn_cost_quote_lock call.
--
-- Also closes the natural pairing on Business's own side: fn_business_job_
-- progress_advance already walks the real Article 20.3 Dispatch sub-
-- sequence (CREATED -> DISPATCHED -> EN_ROUTE -> ARRIVED -> EXECUTING ->
-- COMPLETED -> VERIFIED) but never touched Cost's quote lifecycle at all --
-- SERVICE_IN_PROGRESS and FARE_FINALIZED are real, already-built quote
-- states with no caller. EXECUTING (the service is actually happening) now
-- calls fn_cost_quote_mark_in_progress; COMPLETED (the service is
-- physically done) now calls fn_cost_quote_finalize, which is what
-- triggers PAYMENT_STK_TRIGGERED -- payment is requested when the service
-- is actually finished, never before.
--
-- ============================================================================

CREATE OR REPLACE FUNCTION trustride.fn_cost_resource_dispatch_initiated_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public, extensions, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_correlation_id UUID;
  v_context RECORD;
  v_calculation_id UUID;
  v_quote_id UUID;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_correlation_id FROM trustride.cost_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_cost_resource_dispatch_initiated_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  SELECT * INTO v_context FROM trustride.cost_pending_service_context WHERE correlation_id = v_correlation_id;
  IF v_context IS NULL THEN
    UPDATE trustride.cost_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'NO_SERVICE_CONTEXT_CACHED', accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END IF;

  BEGIN
    v_calculation_id := trustride.fn_cost_fare_calculate(
      v_context.macro_domain, v_context.service_code,
      (v_payload->>'asset_class')::trustride.cost_asset_class_enum,
      coalesce((v_payload->>'engine_capacity')::trustride.cost_engine_capacity_enum, 'NOT_APPLICABLE'),
      coalesce((v_payload->>'jurisdiction')::trustride.cost_jurisdiction_enum, 'KISUMU_COUNTY'),
      v_payload->>'origin_zone_code', v_payload->>'destination_zone_code',
      coalesce((v_payload->>'distance_km')::numeric, 0), coalesce((v_payload->>'duration_min')::numeric, 0),
      coalesce((v_payload->>'requester_user_id')::uuid, '00000000-0000-0000-0000-000000000000'::uuid), 'CUSTOMER',
      v_correlation_id, (v_payload->>'order_id')::uuid, (v_payload->>'assignment_id')::uuid, NULL, 0, NULL
    );
    v_quote_id := trustride.fn_cost_fare_quote_issue(v_calculation_id);

    -- Hardening (2026-08-24): auto-lock, named explicitly as a stand-in for
    -- a real requester decision Engine 11 does not yet exist to capture.
    PERFORM trustride.fn_cost_quote_lock(v_quote_id, v_correlation_id);
  EXCEPTION WHEN OTHERS THEN
    UPDATE trustride.cost_event_inbox SET signal_status = 'REJECTED', rejection_reason = SQLERRM, accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END;

  DELETE FROM trustride.cost_pending_service_context WHERE correlation_id = v_correlation_id;

  UPDATE trustride.cost_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('calculation_id', v_calculation_id, 'quote_id', v_quote_id) WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_cost_resource_dispatch_initiated_accept(UUID) IS
  'The real trigger for fare calculation -- joins with the cached service context, produces a fare_quote, and auto-locks it (hardening 2026-08-24, stand-in for a real requester decision until Engine 11 exists).';

-- Business now calls these two directly (not via signal) from
-- fn_business_job_progress_advance -- its role needs EXECUTE.
GRANT EXECUTE ON FUNCTION trustride.fn_cost_quote_mark_in_progress(UUID) TO trs026_eng004_bus_service;
GRANT EXECUTE ON FUNCTION trustride.fn_cost_quote_finalize(UUID, UUID) TO trs026_eng004_bus_service;
