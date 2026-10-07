-- ============================================================================
-- Engine 11: the frontend contract -- commands return their outcome; the
-- Gate needs no table reads (G20).
-- ============================================================================

-- Capture a command and return its outcome in one call (the command record
-- itself stays the audit trail).
CREATE OR REPLACE FUNCTION trustride.fn_present_command_execute(p_session UUID, p_command_type TEXT, p_payload JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_s RECORD;
  v_cmd UUID;
  v_r RECORD;
BEGIN
  SELECT * INTO v_s FROM trustride.present_shell_session WHERE session_id = p_session AND session_status = 'ACTIVE';
  IF v_s.session_id IS NULL OR (auth.uid() IS DISTINCT FROM v_s.user_id AND auth.uid() IS DISTINCT FROM v_s.acting_person_user_id) THEN
    RAISE EXCEPTION 'SESSION_INVALID: open your shell again';
  END IF;
  IF EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id IN (v_s.user_id, auth.uid()) AND status = 'SUSPENDED') THEN
    RAISE EXCEPTION 'This identity is suspended -- contact TrustRide Office';
  END IF;
  v_cmd := trustride.fn_present_capture_command(p_session, p_command_type, coalesce(p_payload, '{}'::jsonb));
  SELECT translation_status, rejection_reason, translated_signal_id INTO v_r FROM trustride.present_command_capture WHERE command_id = v_cmd;
  RETURN jsonb_build_object('command_id', v_cmd, 'status', v_r.translation_status, 'reason', v_r.rejection_reason, 'signal', v_r.translated_signal_id);
END;
$$;

-- Gate context: + verification outcome and any pending Office access request.
CREATE OR REPLACE FUNCTION trustride.fn_present_gate_context_v2()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN NULL ELSE trustride.fn_present_gate_context() || jsonb_build_object(
    'verification', (SELECT jsonb_build_object('outcome', v.outcome, 'type', v.verification_type) FROM trustride.verification_record v
       WHERE v.subject_user_id = auth.uid() ORDER BY coalesce(v.verified_at, 'infinity'::timestamptz) DESC LIMIT 1),
    'office_request', (SELECT jsonb_build_object('order_code', o.order_code, 'status', o.status,
         'surface', (SELECT l.scope_detail->>'office_surface' FROM trustride.business_order_line l WHERE l.order_id = o.order_id LIMIT 1),
         'response', (SELECT r.response_status FROM trustride.business_partnership_response r WHERE r.order_id = o.order_id))
       FROM trustride.business_order o WHERE o.requester_user_id = auth.uid() AND o.order_root_type = 'OFFICE_ACCESS_REQUEST'
       ORDER BY o.placed_at DESC LIMIT 1)) END;
$$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_present_command_execute(UUID, TEXT, JSONB) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_gate_context_v2() TO trustride_authenticated;

SELECT trustride.fn_platform_conformance_assert();
