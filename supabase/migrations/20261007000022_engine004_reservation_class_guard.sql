-- ============================================================================
-- Engine 4: a reserved resource must be of the class the order requires
-- ============================================================================
--   Found by the integrated Company -> Boda proof (Test D): Engine 2 chooses
--   only eligible units, but Business accepted ANY reservation it received.
--   A Sedan reserved against a Boda order was confirmed for assignment and
--   held ASSIGNED; only the absence of a Boda rate on a Sedan stopped a Sedan
--   being quoted and dispatched to the customer.
--
--   Business owns the order, so Business now refuses a reservation whose
--   capacity_class differs from the order's required class: the unit is
--   released straight back (ASSIGNMENT_RELEASED), the order returns to
--   WAITING for the next retry, and TrustRide Office is alerted. Nothing
--   else in the handler changes.
-- ============================================================================

DO $mig$
DECLARE
  v_def TEXT;
  v_anchor TEXT := '  UPDATE trustride.business_order SET reserved_workforce_unit_id = v_unit, waiting_since = NULL, updated_at = now() WHERE order_id = v_o.order_id;';
  v_guard TEXT := $g$  -- The reserved unit must be of the class this order requires (Test D).
  IF v_o.fulfilment_requirements->>'required_capacity_class_code' IS NOT NULL
     AND (v_payload->>'capacity_class') IS DISTINCT FROM (v_o.fulfilment_requirements->>'required_capacity_class_code') THEN
    UPDATE trustride.business_order SET reserved_workforce_unit_id = v_unit WHERE order_id = v_o.order_id;
    PERFORM trustride.fn_business_release_assignment(v_o.order_id,
      'CAPACITY_CLASS_MISMATCH: reserved ' || coalesce(v_payload->>'capacity_class', '?') || ', order requires ' || (v_o.fulfilment_requirements->>'required_capacity_class_code'));
    UPDATE trustride.business_order SET status = 'WAITING', order_stage = 'RESOURCE_AVAILABILITY', waiting_since = coalesce(waiting_since, now()),
      status_reason = 'No ' || (v_o.fulfilment_requirements->>'required_capacity_class_code') || ' free yet', updated_at = now()
    WHERE order_id = v_o.order_id;
    PERFORM trustride.fn_present_notify_office('Wrong resource class refused on ' || v_o.order_code,
      'A ' || coalesce(v_payload->>'capacity_class', '?') || ' unit was reserved for an order that requires ' || (v_o.fulfilment_requirements->>'required_capacity_class_code')
        || '. It was released and the order is waiting for an eligible resource.', 'PLATFORM_EXCEPTION', v_o.order_id);
    UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(),
      payload_out = jsonb_build_object('rejected', 'CAPACITY_CLASS_MISMATCH', 'reserved_class', v_payload->>'capacity_class',
        'required_class', v_o.fulfilment_requirements->>'required_capacity_class_code', 'released_unit', v_unit)
    WHERE signal_id = p_signal_id;
    RETURN 'ACCEPTED';
  END IF;

$g$;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_business_resource_reserved_accept(uuid)'::regprocedure) INTO v_def;
  IF position(v_anchor IN v_def) = 0 THEN
    RAISE EXCEPTION 'reservation class guard: anchor not found in fn_business_resource_reserved_accept';
  END IF;
  IF position('CAPACITY_CLASS_MISMATCH' IN v_def) > 0 THEN
    RETURN; -- already guarded
  END IF;
  EXECUTE replace(v_def, v_anchor, v_guard || v_anchor);
END;
$mig$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;

SELECT trustride.fn_platform_conformance_assert();
