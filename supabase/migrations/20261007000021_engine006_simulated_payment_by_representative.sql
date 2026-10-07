-- ============================================================================
-- Engine 6 (staging simulator): an organisation's representative approves
-- the organisation's simulated M-Pesa prompt
-- ============================================================================
--   A company's order is paid from the company's own verified phone (D3,
--   migration 19). On staging the simulator stands in for that phone, and
--   the representative acting for the company is the one who approves it.
--   The simulator only accepted the person whose own identity owned the
--   payment, so a company order could never be paid on staging (found in
--   the browser journeys). Real M-Pesa prompts are unaffected: they are
--   confirmed on the phone itself, never through this function.
-- ============================================================================

CREATE OR REPLACE FUNCTION trustride.fn_integration_payment_simulator_confirm(p_gateway_txn_id UUID, p_success BOOLEAN DEFAULT TRUE)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_txn RECORD;
BEGIN
  SELECT * INTO v_txn FROM trustride.integration_payment_gateway_transaction WHERE gateway_txn_id = p_gateway_txn_id;
  IF v_txn.gateway_txn_id IS NULL OR NOT (v_txn.requester_user_id = auth.uid() OR trustride.fn_am_i_representative_of(v_txn.requester_user_id)) THEN
    RAISE EXCEPTION 'No such payment on your identity';
  END IF;
  IF v_txn.adapter_type <> 'SIMULATOR' THEN
    RAISE EXCEPTION 'This is a real M-Pesa request -- confirm it on your phone';
  END IF;
  PERFORM trustride.fn_integration_payment_callback_simulate(p_gateway_txn_id, CASE WHEN p_success THEN 'SETTLED' ELSE 'FAILED' END::trustride.integration_payment_txn_status_enum);
  RETURN CASE WHEN p_success THEN 'SETTLED' ELSE 'FAILED' END;
END;
$$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;

SELECT trustride.fn_platform_conformance_assert();
