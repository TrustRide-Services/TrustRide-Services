-- ============================================================================
-- Engine 11: the Gate shows the person's own simulated messages (staging)
-- ============================================================================
--   While the SMS port runs on the SIMULATOR adapter no real SMS is sent, so
--   a person verifying their phone at the Gate (before any shell, hence
--   before MY_PROFILE) could never read their code. The gate context now
--   carries the caller's own last few simulator-delivered messages -- the
--   same rule MY_PROFILE uses. Under SANDBOX/PRODUCTION adapters there are
--   no simulator rows, so this is empty and codes arrive by real SMS only.
-- ============================================================================

CREATE OR REPLACE FUNCTION trustride.fn_present_gate_context_v2()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN NULL ELSE trustride.fn_present_gate_context() || jsonb_build_object(
    'verification', (SELECT jsonb_build_object('outcome', v.outcome, 'type', v.verification_type) FROM trustride.verification_record v
       WHERE v.subject_user_id = auth.uid() ORDER BY coalesce(v.verified_at, 'infinity'::timestamptz) DESC LIMIT 1),
    'office_request', (SELECT jsonb_build_object('order_code', o.order_code, 'status', o.status,
         'surface', (SELECT l.scope_detail->>'office_surface' FROM trustride.business_order_line l WHERE l.order_id = o.order_id LIMIT 1),
         'response', (SELECT r.response_status FROM trustride.business_partnership_response r WHERE r.order_id = o.order_id))
       FROM trustride.business_order o WHERE o.requester_user_id = auth.uid() AND o.order_root_type = 'OFFICE_ACCESS_REQUEST'
       ORDER BY o.placed_at DESC LIMIT 1),
    'phone_contact', (SELECT jsonb_build_object('contact_id', c.contact_id, 'value', c.contact_value, 'is_verified', c.is_verified)
       FROM trustride.user_contact c WHERE c.user_id = auth.uid() AND c.contact_type = 'PHONE' AND c.status = 'ACTIVE'
       ORDER BY c.is_verified DESC, c.is_primary DESC, c.created_at DESC LIMIT 1),
    'simulated_messages', coalesce((SELECT jsonb_agg(jsonb_build_object('channel', d.channel, 'body', d.payload->>'body', 'at', d.created_at) ORDER BY d.created_at DESC)
       FROM (SELECT * FROM trustride.integration_notification_dispatch_log d WHERE d.recipient_ref = auth.uid() AND d.adapter_type = 'SIMULATOR'
             AND d.status IN ('QUEUED', 'DISPATCHED') ORDER BY d.created_at DESC LIMIT 3) d), '[]'::jsonb)) END;
$$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_present_gate_context_v2() TO trustride_authenticated;

SELECT trustride.fn_platform_conformance_assert();
