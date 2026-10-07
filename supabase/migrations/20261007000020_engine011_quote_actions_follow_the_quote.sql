-- ============================================================================
-- Engine 11: the fare buttons follow the quote itself
-- ============================================================================
--   Accepting a fare locks the quote at once (Cost), but the order leaves
--   QUOTED only when the dispatch cycle carries FARE_ACCEPTED to Business --
--   up to one cycle later. In that window the order screen still offered
--   "Accept fare" / "Decline" for a fare already accepted (found in the
--   browser journeys). The buttons now appear only while the quote is an
--   open estimate.
-- ============================================================================

CREATE OR REPLACE FUNCTION trustride.fn_present_order_actions(p_order_id UUID)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object(
    'accept_quote', o.status = 'QUOTED' AND q.quote_state = 'FARE_ESTIMATED',
    'decline_quote', o.status = 'QUOTED' AND q.quote_state = 'FARE_ESTIMATED',
    'cancel', o.status IN ('PLACED', 'VALIDATED', 'WAITING', 'SCHEDULED', 'QUOTED', 'JOB_CREATED', 'DISPATCHED', 'AWAITING_PAYMENT')
      AND NOT EXISTS (SELECT 1 FROM trustride.business_job j WHERE j.order_id = o.order_id AND j.status IN ('ARRIVED', 'EXECUTING', 'COMPLETED', 'VERIFIED'))
      AND NOT (o.order_root_type = 'MARKETPLACE_PURCHASE_ORDER' AND o.status NOT IN ('PLACED', 'AWAITING_PAYMENT')),
    'retry_payment', EXISTS (SELECT 1 FROM trustride.business_settlement s WHERE s.order_id = o.order_id AND s.payment_status = 'FAILED' AND s.payment_rail = 'MPESA_C2B_STK'),
    'confirm_simulated_payment', EXISTS (SELECT 1 FROM trustride.integration_payment_gateway_transaction t WHERE t.order_id = o.order_id AND t.txn_status = 'PENDING_CALLBACK' AND t.adapter_type = 'SIMULATOR'),
    'review', o.status IN ('COMPLETED', 'SETTLED') AND NOT EXISTS (SELECT 1 FROM trustride.business_review r WHERE r.order_id = o.order_id AND r.reviewer_user_id = o.requester_user_id),
    'support', TRUE)
  FROM trustride.business_order o LEFT JOIN trustride.fare_quote q ON q.quote_id = o.quote_id
  WHERE o.order_id = p_order_id;
$$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;

SELECT trustride.fn_platform_conformance_assert();
