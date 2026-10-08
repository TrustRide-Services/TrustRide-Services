-- ============================================================================
-- Engine 4: a matched order no longer carries its "waiting" reason
-- ============================================================================
--   Found by the integrated Company -> Boda proof: after a waiting order was
--   matched, it kept status_reason "No BODA_BODA free yet" through quote,
--   dispatch and settlement, so the Office Orders screen described an
--   assigned order as having nobody free. Accepting a valid reservation now
--   clears the waiting reason together with waiting_since.
-- ============================================================================

DO $mig$
DECLARE
  v_def TEXT;
  v_old TEXT := '  UPDATE trustride.business_order SET reserved_workforce_unit_id = v_unit, waiting_since = NULL, updated_at = now() WHERE order_id = v_o.order_id;';
  v_new TEXT := '  UPDATE trustride.business_order SET reserved_workforce_unit_id = v_unit, waiting_since = NULL,
    status_reason = CASE WHEN v_o.status = ''WAITING'' THEN NULL ELSE status_reason END, updated_at = now() WHERE order_id = v_o.order_id;';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_business_resource_reserved_accept(uuid)'::regprocedure) INTO v_def;
  IF position(v_old IN v_def) = 0 THEN
    IF position('status_reason = CASE WHEN v_o.status = ''WAITING''' IN v_def) > 0 THEN RETURN; END IF;
    RAISE EXCEPTION 'waiting-reason fix: anchor not found in fn_business_resource_reserved_accept';
  END IF;
  EXECUTE replace(v_def, v_old, v_new);
END;
$mig$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;

SELECT trustride.fn_platform_conformance_assert();
