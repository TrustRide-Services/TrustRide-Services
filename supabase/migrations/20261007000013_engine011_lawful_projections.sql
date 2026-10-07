-- ============================================================================
-- Engine 11: lawful projections for every screen (G20, Law C-III-3, Sec.23)
-- ============================================================================
--   Engine data -> registered projection -> presentation.
-- Every screen reads through fn_present_projection(session, code, params):
--   * the session must be ACTIVE and belong to the caller (or to the entity
--     the caller represents);
--   * the projection must be registered in Foundation's projection_registry
--     for the session's sub-shell -- an unregistered screen is non-conformant;
--   * the render is recorded in present_projection_render and cached in
--     present_projection_cache (offline-first display);
--   * the projection function decides, row by row, what this identity may
--     see. Tables are never read by screens directly.
-- The Gate context (who am I, which shells may I open) is read before any
-- shell exists, from Foundation alone (C-III-5): fn_present_gate_context.
-- ============================================================================

ALTER TABLE trustride.projection_registry
  ADD COLUMN sub_shells TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN description TEXT;

-- ---------------------------------------------------------------------------
-- 1. The dispatcher
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_present_projection(p_session UUID, p_code TEXT, p_params JSONB DEFAULT '{}'::jsonb)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_s RECORD;
  v_reg RECORD;
  v_out JSONB;
BEGIN
  SELECT * INTO v_s FROM trustride.present_shell_session WHERE session_id = p_session AND session_status = 'ACTIVE';
  IF v_s.session_id IS NULL OR (auth.uid() IS DISTINCT FROM v_s.user_id AND auth.uid() IS DISTINCT FROM v_s.acting_person_user_id) THEN
    RAISE EXCEPTION 'SESSION_INVALID: open your shell again';
  END IF;
  IF EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id IN (v_s.user_id, auth.uid()) AND status = 'SUSPENDED') THEN
    RAISE EXCEPTION 'This identity is suspended -- contact TrustRide Office';
  END IF;
  SELECT * INTO v_reg FROM trustride.projection_registry WHERE projection_code = p_code;
  IF v_reg.projection_id IS NULL THEN
    RAISE EXCEPTION '% is not a registered projection (FDN-001 Sec.11.4 C-III-3)', p_code;
  END IF;
  IF NOT (v_s.sub_shell::text = ANY (v_reg.sub_shells)) THEN
    RAISE EXCEPTION '% is not a lawful projection on %', p_code, v_s.sub_shell;
  END IF;
  EXECUTE format('SELECT trustride.%I($1, $2)', 'fn_present_proj_' || lower(p_code)) INTO v_out USING p_session, coalesce(p_params, '{}'::jsonb);
  v_out := coalesce(v_out, '{}'::jsonb);
  INSERT INTO trustride.present_projection_render (shell_session_id, projection_code) VALUES (p_session, p_code);
  INSERT INTO trustride.present_projection_cache (shell_session_id, projection_code, cached_payload, cache_status)
  VALUES (p_session, p_code, v_out, 'FRESH')
  ON CONFLICT (shell_session_id, projection_code) DO UPDATE SET cached_payload = EXCLUDED.cached_payload, cached_at = now(), cache_status = 'FRESH';
  RETURN v_out;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_session_user(p_session UUID)
RETURNS UUID LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT user_id FROM trustride.present_shell_session WHERE session_id = p_session;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_first_name(p_user UUID)
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT split_part(trim(display_name), ' ', 1) FROM trustride.platform_users WHERE user_id = p_user;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_zone_name(p_code TEXT)
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT coalesce((SELECT zone_name FROM trustride.cost_operational_zones WHERE zone_code = p_code), p_code);
$$;

-- What a customer may do with an order right now (one rule, used by every screen).
CREATE OR REPLACE FUNCTION trustride.fn_present_order_actions(p_order_id UUID)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object(
    'accept_quote', o.status = 'QUOTED',
    'decline_quote', o.status = 'QUOTED',
    'cancel', o.status IN ('PLACED', 'VALIDATED', 'WAITING', 'SCHEDULED', 'QUOTED', 'JOB_CREATED', 'DISPATCHED', 'AWAITING_PAYMENT')
      AND NOT EXISTS (SELECT 1 FROM trustride.business_job j WHERE j.order_id = o.order_id AND j.status IN ('ARRIVED', 'EXECUTING', 'COMPLETED', 'VERIFIED'))
      AND NOT (o.order_root_type = 'MARKETPLACE_PURCHASE_ORDER' AND o.status NOT IN ('PLACED', 'AWAITING_PAYMENT')),
    'retry_payment', EXISTS (SELECT 1 FROM trustride.business_settlement s WHERE s.order_id = o.order_id AND s.payment_status = 'FAILED' AND s.payment_rail = 'MPESA_C2B_STK'),
    'confirm_simulated_payment', EXISTS (SELECT 1 FROM trustride.integration_payment_gateway_transaction t WHERE t.order_id = o.order_id AND t.txn_status = 'PENDING_CALLBACK' AND t.adapter_type = 'SIMULATOR'),
    'review', o.status IN ('COMPLETED', 'SETTLED') AND NOT EXISTS (SELECT 1 FROM trustride.business_review r WHERE r.order_id = o.order_id AND r.reviewer_user_id = o.requester_user_id),
    'support', TRUE)
  FROM trustride.business_order o WHERE o.order_id = p_order_id;
$$;

-- ---------------------------------------------------------------------------
-- 2. Gate context (pre-shell, Foundation identity only)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_present_gate_context()
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT CASE WHEN auth.uid() IS NULL THEN NULL ELSE jsonb_build_object(
    'user_id', auth.uid(),
    'registered', pu.user_id IS NOT NULL,
    'display_name', pu.display_name,
    'identity_status', pu.status,
    'identity_primitive', pu.identity_primitive,
    'verification_failed_reasons', (SELECT al.after_snapshot->'reasons' FROM trustride.audit_log al
       WHERE al.entity_id = auth.uid() AND al.action = 'REGISTRATION_PRIMARY_FAILED' ORDER BY al.occurred_at DESC LIMIT 1),
    'phone_verified', EXISTS (SELECT 1 FROM trustride.user_contact c WHERE c.user_id = auth.uid() AND c.contact_type = 'PHONE' AND c.is_verified AND c.status = 'ACTIVE'),
    'environments', coalesce((SELECT jsonb_agg(jsonb_build_object('domain', a.user_type_domain, 'status', a.registration_status) ORDER BY a.registered_at)
       FROM trustride.business_actor_registration a WHERE a.user_id = auth.uid()), '[]'::jsonb),
    'roles', coalesce((SELECT jsonb_agg(DISTINCT rd.role_code) FROM trustride.role_assignment ra JOIN trustride.role_definition rd ON rd.role_id = ra.role_id
       WHERE ra.user_id = auth.uid() AND ra.status = 'ACTIVE' AND (ra.valid_to IS NULL OR ra.valid_to > now())), '[]'::jsonb),
    'founder_exists', EXISTS (SELECT 1 FROM trustride.role_assignment ra JOIN trustride.role_definition rd ON rd.role_id = ra.role_id
       WHERE rd.role_code = 'FOUNDER' AND ra.status = 'ACTIVE'),
    'has_working_unit', EXISTS (SELECT 1 FROM trustride.resource_workforce_unit wu WHERE wu.operator_user_id = auth.uid() AND wu.unit_status = 'ACTIVE'),
    'represented_entities', coalesce((SELECT jsonb_agg(jsonb_build_object('user_id', e.user_id, 'legal_name', e.legal_name, 'entity_type', e.entity_type,
         'status', ep.status, 'membership_role', m.membership_role,
         'environments', coalesce((SELECT jsonb_agg(jsonb_build_object('domain', a.user_type_domain, 'status', a.registration_status))
            FROM trustride.business_actor_registration a WHERE a.user_id = e.user_id), '[]'::jsonb)))
       FROM trustride.entity_membership m JOIN trustride.entity_profile e ON e.entity_id = m.entity_id
       JOIN trustride.platform_users ep ON ep.user_id = e.user_id
       WHERE m.person_user_id = auth.uid() AND (m.valid_to IS NULL OR m.valid_to >= current_date) AND e.entity_type <> 'EXTERNAL_SYSTEM'), '[]'::jsonb))
  END
  FROM (SELECT 1) one LEFT JOIN trustride.platform_users pu ON pu.user_id = auth.uid();
$$;

-- ---------------------------------------------------------------------------
-- 3. Shared projections (every surface)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_present_proj_notifications(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object('items', coalesce(jsonb_agg(x ORDER BY x->>'delivered_at' DESC), '[]'::jsonb),
    'unread', count(*) FILTER (WHERE x->>'read_status' = 'UNREAD'))
  FROM (SELECT jsonb_build_object('notification_id', n.notification_id, 'title', n.title, 'body', n.body, 'category', n.category,
          'sub_shell', n.sub_shell, 'read_status', n.read_status, 'delivered_at', n.delivered_at, 'critical', n.critical) x
        FROM trustride.present_notification_inbox n
        WHERE n.recipient_user_id = trustride.fn_present_session_user(p_session) AND n.category <> 'SECRET'
        ORDER BY n.delivered_at DESC LIMIT coalesce((p_params->>'limit')::int, 50)) q;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_my_profile(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  WITH u AS (SELECT trustride.fn_present_session_user(p_session) AS id)
  SELECT jsonb_build_object(
    'identity', (SELECT jsonb_build_object('display_name', pu.display_name, 'global_uid', pu.global_uid, 'status', pu.status, 'primitive', pu.identity_primitive)
                 FROM trustride.platform_users pu, u WHERE pu.user_id = u.id),
    'contacts', coalesce((SELECT jsonb_agg(jsonb_build_object('contact_id', c.contact_id, 'type', c.contact_type, 'value', c.contact_value,
                  'is_primary', c.is_primary, 'is_verified', c.is_verified) ORDER BY c.contact_type, c.is_primary DESC)
                FROM trustride.user_contact c, u WHERE c.user_id = u.id AND c.status = 'ACTIVE'), '[]'::jsonb),
    'preferences', coalesce((SELECT jsonb_agg(jsonb_build_object('channel', p.channel, 'allowed', p.allowed, 'from', p.allowed_from, 'to', p.allowed_to))
                FROM trustride.user_contact_preference p, u WHERE p.user_id = u.id), '[]'::jsonb),
    'kra_pin', (SELECT jsonb_build_object('value', i.identifier_value, 'status', i.status) FROM trustride.user_identifier i, u
                WHERE i.user_id = u.id AND i.identifier_type = 'KRA_PIN' AND i.status IN ('ACTIVE', 'DECLARED') ORDER BY (i.status = 'ACTIVE') DESC LIMIT 1),
    'referral_applied', EXISTS (SELECT 1 FROM trustride.business_intermediary_referral r, u WHERE r.referred_user_id = u.id),
    -- Staging only: SMS a real phone would have received (simulator adapter).
    'simulated_messages', coalesce((SELECT jsonb_agg(jsonb_build_object('channel', d.channel, 'body', d.payload->>'body', 'at', d.created_at) ORDER BY d.created_at DESC)
                FROM (SELECT * FROM trustride.integration_notification_dispatch_log d, u WHERE d.recipient_ref = u.id AND d.adapter_type = 'SIMULATOR'
                      AND d.status IN ('QUEUED', 'DISPATCHED') ORDER BY d.created_at DESC LIMIT 5) d), '[]'::jsonb));
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_my_support(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object('cases', coalesce(jsonb_agg(jsonb_build_object('case_id', c.case_id, 'case_code', c.case_code, 'category', c.category,
      'severity', c.severity, 'subject', c.subject, 'status', c.status, 'opened_at', c.opened_at, 'resolution', c.resolution,
      'order_code', (SELECT order_code FROM trustride.business_order o WHERE o.order_id = c.order_id),
      'messages', coalesce((SELECT jsonb_agg(jsonb_build_object('author', m.author_role, 'body', m.body, 'at', m.created_at) ORDER BY m.created_at)
                  FROM trustride.business_support_message m WHERE m.case_id = c.case_id AND NOT m.internal_note), '[]'::jsonb))
      ORDER BY c.opened_at DESC), '[]'::jsonb))
  FROM trustride.business_support_case c WHERE c.opened_by_user_id = trustride.fn_present_session_user(p_session);
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_request_history(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object('requests', coalesce(jsonb_agg(jsonb_build_object('order_id', o.order_id, 'order_code', o.order_code,
      'root', o.order_root_type, 'status', o.status, 'placed_at', o.placed_at,
      'lines', (SELECT jsonb_agg(l.line_description ORDER BY l.line_sequence) FROM trustride.business_order_line l WHERE l.order_id = o.order_id),
      'response', (SELECT jsonb_build_object('status', r.response_status, 'notes', r.response_notes, 'target', r.decision_target_at, 'deadline', r.response_due_at,
          'escalated_at', r.escalated_at, 'responded_at', r.responded_at) FROM trustride.business_partnership_response r WHERE r.order_id = o.order_id))
      ORDER BY o.placed_at DESC), '[]'::jsonb))
  FROM trustride.business_order o
  WHERE o.requester_user_id = trustride.fn_present_session_user(p_session) AND o.order_root_type <> 'SERVICE_ORDER'
    AND (p_params->>'root' IS NULL OR o.order_root_type::text = p_params->>'root');
$$;

-- ---------------------------------------------------------------------------
-- 4. Customer
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_present_proj_service_catalogue(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object(
    'families', (SELECT jsonb_agg(f ORDER BY f->>'sort') FROM (
      SELECT jsonb_build_object('domain', sm.domain_code, 'sort', CASE sm.domain_code WHEN 'TRANSPORT' THEN 1 WHEN 'DELIVERY' THEN 2 WHEN 'COURIER' THEN 3
          WHEN 'EXECUTIVE_ASSISTANTS' THEN 4 ELSE 5 END,
        'services', jsonb_agg(jsonb_build_object('service_code', sc.service_code, 'service_name', sc.service_name, 'description', sc.description,
          'fulfilment', coalesce(sc.requirements->>'fulfilment', 'DISPATCH'), 'command', sc.requirements->>'command',
          'trip', coalesce((sc.requirements->>'trip')::boolean, false), 'needs_hours', sm.domain_code = 'EXECUTIVE_ASSISTANTS' AND sc.requirements->>'fulfilment' = 'DISPATCH',
          'vetting_tier', (SELECT er.required_vetting_tier FROM trustride.service_eligibility_rule er WHERE er.service_id = sc.service_id AND er.active LIMIT 1))
          ORDER BY sc.service_name)) f
      FROM trustride.service_catalogue sc JOIN trustride.service_macro_domain sm ON sm.macro_domain_id = sc.macro_domain_id
      WHERE sc.status = 'ACTIVE' GROUP BY sm.domain_code) x),
    'zones', (SELECT jsonb_agg(jsonb_build_object('zone_code', z.zone_code, 'zone_name', z.zone_name, 'jurisdiction', z.jurisdiction) ORDER BY z.zone_name)
              FROM trustride.cost_operational_zones z WHERE z.active),
    'working_hours', jsonb_build_object('weekday', trustride.fn_business_config('WORKING_WINDOW_WEEKDAY'),
       'saturday', trustride.fn_business_config('WORKING_WINDOW_SATURDAY'), 'sunday', trustride.fn_business_config('WORKING_WINDOW_SUNDAY')),
    'open_now', trustride.fn_business_is_working_time(now()),
    'next_open', trustride.fn_business_next_working_open(now()),
    'max_stops', trustride.fn_business_config_num('ORDER_MAX_LINES', 5),
    'schedule_max_days', trustride.fn_business_config_num('SCHEDULE_MAX_DAYS_AHEAD', 14),
    'phone_verified', trustride.fn_user_payment_msisdn(trustride.fn_present_session_user(p_session)) IS NOT NULL);
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_order_summary(p_order_id UUID)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object('order_id', o.order_id, 'order_code', o.order_code, 'root', o.order_root_type, 'service_code', o.service_code,
    'service_name', coalesce((SELECT service_name FROM trustride.service_catalogue WHERE service_code = o.service_code), o.service_code),
    'status', o.status, 'stage', o.order_stage, 'status_reason', o.status_reason, 'placed_at', o.placed_at, 'updated_at', o.updated_at,
    'dispatch_mode', o.dispatch_mode, 'requested_start_at', o.requested_start_at,
    'stops', (SELECT count(*) FROM trustride.business_order_line l WHERE l.order_id = o.order_id),
    'title', (SELECT l.line_description FROM trustride.business_order_line l WHERE l.order_id = o.order_id ORDER BY l.line_sequence LIMIT 1),
    'quote', (SELECT jsonb_build_object('quote_id', q.quote_id, 'total_kes', q.computed_total_fare_kes, 'state', q.quote_state, 'expires_at', q.expires_at)
              FROM trustride.fare_quote q WHERE q.quote_id = o.quote_id),
    'payment', (SELECT jsonb_build_object('status', s.payment_status, 'amount_kes', s.computed_total_fare_kes, 'rail', s.payment_rail, 'receipt_code', s.receipt_code)
                FROM trustride.business_settlement s WHERE s.order_id = o.order_id),
    'actions', trustride.fn_present_order_actions(o.order_id))
  FROM trustride.business_order o WHERE o.order_id = p_order_id;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_customer_home(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  WITH u AS (SELECT trustride.fn_present_session_user(p_session) AS id)
  SELECT jsonb_build_object(
    'display_name', (SELECT display_name FROM trustride.platform_users, u WHERE user_id = u.id),
    'phone_verified', (SELECT trustride.fn_user_payment_msisdn(u.id) IS NOT NULL FROM u),
    'active_orders', coalesce((SELECT jsonb_agg(trustride.fn_present_order_summary(o.order_id) ORDER BY o.placed_at DESC)
       FROM trustride.business_order o, u WHERE o.requester_user_id = u.id AND o.order_root_type = 'SERVICE_ORDER'
       AND o.status NOT IN ('SETTLED', 'REVIEWED', 'CLOSED', 'CANCELLED', 'EXPIRED', 'FAILED', 'DECLINED')), '[]'::jsonb),
    'completed_count', (SELECT count(*) FROM trustride.business_order o, u WHERE o.requester_user_id = u.id AND o.status IN ('SETTLED', 'REVIEWED')),
    'unread', (SELECT count(*) FROM trustride.present_notification_inbox n, u WHERE n.recipient_user_id = u.id AND n.read_status = 'UNREAD'),
    'open_cases', (SELECT count(*) FROM trustride.business_support_case c, u WHERE c.opened_by_user_id = u.id AND c.status NOT IN ('RESOLVED', 'CLOSED')));
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_my_orders(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object('orders', coalesce(jsonb_agg(trustride.fn_present_order_summary(o.order_id) ORDER BY o.placed_at DESC), '[]'::jsonb))
  FROM (SELECT order_id, placed_at FROM trustride.business_order
        WHERE requester_user_id = trustride.fn_present_session_user(p_session)
          AND order_root_type = CASE WHEN coalesce(p_params->>'scope', 'SERVICE') = 'PURCHASE' THEN 'MARKETPLACE_PURCHASE_ORDER'::trustride.business_order_root_enum ELSE 'SERVICE_ORDER' END
        ORDER BY placed_at DESC LIMIT 100) o;
$$;

-- One order, as its customer may see it. Operator identity is revealed only
-- once the customer has accepted the fare; the vehicle's position only while
-- the tracking session is active (TBOC Article 21: resource type, resource
-- id, ETA, status, exact location -- nothing more, nothing after).
CREATE OR REPLACE FUNCTION trustride.fn_present_proj_order_detail(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
DECLARE
  v_user UUID := trustride.fn_present_session_user(p_session);
  v_o RECORD;
  v_unit UUID;
  v_reveal BOOLEAN;
BEGIN
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = (p_params->>'order_id')::uuid AND requester_user_id = v_user;
  IF v_o.order_id IS NULL THEN RAISE EXCEPTION 'No such order on your identity'; END IF;
  SELECT workforce_unit_id INTO v_unit FROM trustride.business_job WHERE order_id = v_o.order_id AND status NOT IN ('CANCELLED', 'FAILED') LIMIT 1;
  v_reveal := v_unit IS NOT NULL AND EXISTS (SELECT 1 FROM trustride.fare_quote q WHERE q.quote_id = v_o.quote_id AND q.quote_state NOT IN ('FARE_ESTIMATED', 'EXPIRED', 'CANCELLED'));
  RETURN trustride.fn_present_order_summary(v_o.order_id) || jsonb_build_object(
    'lines', (SELECT jsonb_agg(jsonb_build_object('seq', l.line_sequence, 'description', l.line_description,
        'from', trustride.fn_present_zone_name(l.scope_detail->>'origin_zone_code'), 'to', trustride.fn_present_zone_name(l.scope_detail->>'destination_zone_code'),
        'distance_km', l.scope_detail->>'distance_km', 'duration_min', l.scope_detail->>'duration_min', 'billed_hours', l.scope_detail->>'billed_hours',
        'listing_id', l.scope_detail->>'listing_id', 'price_kes', l.scope_detail->>'price_kes',
        'fare_kes', (SELECT ql.line_fare_kes FROM trustride.fare_quote_line ql WHERE ql.quote_id = v_o.quote_id AND ql.order_line_id = l.order_line_id),
        'job_status', (SELECT j.status FROM trustride.business_job j WHERE j.order_line_id = l.order_line_id AND j.status NOT IN ('CANCELLED', 'FAILED') LIMIT 1))
        ORDER BY l.line_sequence) FROM trustride.business_order_line l WHERE l.order_id = v_o.order_id),
    'operator', CASE WHEN v_reveal THEN (SELECT jsonb_build_object('first_name', trustride.fn_present_first_name(wu.operator_user_id),
        'resource_type', cc.class_label,
        'vehicle', (SELECT trim(concat_ws(' ', ob.make, ob.model, ob.plate_number)) FROM trustride.resource_fleet_register f JOIN trustride.object_registry ob ON ob.object_id = f.object_id
                    WHERE f.fleet_resource_id = wu.fleet_resource_id),
        'rating', (SELECT round(avg(r.rating), 1) FROM trustride.business_review r WHERE r.reviewee_user_id = wu.operator_user_id),
        'rating_count', (SELECT count(*) FROM trustride.business_review r WHERE r.reviewee_user_id = wu.operator_user_id))
      FROM trustride.resource_workforce_unit wu JOIN trustride.resource_capacity_class cc ON cc.capacity_class_id = wu.capacity_class_id
      WHERE wu.workforce_unit_id = v_unit) END,
    'tracking', (SELECT jsonb_build_object('active', TRUE, 'status', t.tracking_status, 'resource_type', t.resource_type,
        'resource_id', (SELECT ob.plate_number FROM trustride.resource_workforce_unit wu JOIN trustride.resource_fleet_register f ON f.fleet_resource_id = wu.fleet_resource_id
                        JOIN trustride.object_registry ob ON ob.object_id = f.object_id WHERE wu.workforce_unit_id = v_unit),
        'eta', t.eta, 'lat', ST_Y(t.exact_location), 'lon', ST_X(t.exact_location), 'updated_at', t.updated_at)
      FROM trustride.business_tracking_session t JOIN trustride.business_job j ON j.job_id = t.job_id
      WHERE j.order_id = v_o.order_id AND t.ended_at IS NULL ORDER BY j.line_sequence LIMIT 1),
    'quote_lines', (SELECT jsonb_agg(jsonb_build_object('seq', ql.line_sequence, 'fare_kes', ql.line_fare_kes) ORDER BY ql.line_sequence)
        FROM trustride.fare_quote_line ql WHERE ql.quote_id = v_o.quote_id),
    'payments', (SELECT jsonb_agg(jsonb_build_object('status', t.txn_status, 'amount_kes', t.amount_kes, 'adapter', t.adapter_type, 'rail', t.payment_rail,
        'failure_reason', t.failure_reason, 'receipt', t.mpesa_receipt_number, 'at', t.initiated_at) ORDER BY t.initiated_at DESC)
        FROM trustride.integration_payment_gateway_transaction t WHERE t.order_id = v_o.order_id),
    'review', (SELECT jsonb_build_object('rating', r.rating, 'comment', r.comment) FROM trustride.business_review r WHERE r.order_id = v_o.order_id AND r.reviewer_user_id = v_user),
    'timeline', (SELECT jsonb_agg(jsonb_build_object('title', n.title, 'body', n.body, 'at', n.delivered_at) ORDER BY n.delivered_at)
        FROM trustride.present_notification_inbox n WHERE n.recipient_user_id = v_user AND n.source_signal_correlation_id = v_o.correlation_id),
    'request', (SELECT jsonb_build_object('status', r.response_status, 'notes', r.response_notes, 'deadline', r.response_due_at)
        FROM trustride.business_partnership_response r WHERE r.order_id = v_o.order_id));
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Operator App
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_present_operator_job_card(p_order_id UUID)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object('order_id', o.order_id, 'order_code', o.order_code,
    'service_name', coalesce((SELECT service_name FROM trustride.service_catalogue WHERE service_code = o.service_code), o.service_code),
    'order_status', o.status, 'requested_start_at', o.requested_start_at, 'dispatch_mode', o.dispatch_mode,
    'fare_confirmed', EXISTS (SELECT 1 FROM trustride.business_settlement s WHERE s.order_id = o.order_id),
    'fare_kes', (SELECT computed_total_fare_kes FROM trustride.business_settlement s WHERE s.order_id = o.order_id),
    'customer_first_name', trustride.fn_present_first_name(o.requester_user_id),
    'stops', (SELECT jsonb_agg(jsonb_build_object('job_id', j.job_id, 'seq', j.line_sequence, 'status', j.status,
        'from', trustride.fn_present_zone_name(l.scope_detail->>'origin_zone_code'), 'to', trustride.fn_present_zone_name(l.scope_detail->>'destination_zone_code'),
        'distance_km', l.scope_detail->>'distance_km', 'billed_hours', l.scope_detail->>'billed_hours', 'description', l.line_description) ORDER BY j.line_sequence)
      FROM trustride.business_job j JOIN trustride.business_order_line l ON l.order_line_id = j.order_line_id
      WHERE j.order_id = o.order_id AND j.status NOT IN ('CANCELLED', 'FAILED')),
    'current_job_id', (SELECT j.job_id FROM trustride.business_job j WHERE j.order_id = o.order_id AND j.status NOT IN ('COMPLETED', 'VERIFIED', 'CANCELLED', 'FAILED')
                       ORDER BY j.line_sequence LIMIT 1),
    'current_status', (SELECT j.status FROM trustride.business_job j WHERE j.order_id = o.order_id AND j.status NOT IN ('COMPLETED', 'VERIFIED', 'CANCELLED', 'FAILED')
                       ORDER BY j.line_sequence LIMIT 1),
    'can_decline', EXISTS (SELECT 1 FROM trustride.business_job j WHERE j.order_id = o.order_id AND j.status IN ('CREATED', 'ACKNOWLEDGED')))
  FROM trustride.business_order o WHERE o.order_id = p_order_id;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_operator_home(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  WITH u AS (SELECT trustride.fn_present_session_user(p_session) AS id),
  unit AS (SELECT wu.* FROM trustride.resource_workforce_unit wu, u WHERE wu.operator_user_id = u.id AND wu.unit_status = 'ACTIVE' LIMIT 1)
  SELECT jsonb_build_object(
    'display_name', (SELECT display_name FROM trustride.platform_users, u WHERE user_id = u.id),
    'unit', (SELECT jsonb_build_object('workforce_unit_id', unit.workforce_unit_id, 'class', cc.class_label, 'class_code', cc.class_code,
        'base', er.estate_name, 'availability', trustride.fn_resource_unit_availability(unit.workforce_unit_id),
        'vehicle', (SELECT jsonb_build_object('label', trim(concat_ws(' ', ob.make, ob.model)), 'plate', ob.plate_number, 'lifecycle', f.lifecycle_state,
              'inspection', f.inspection_status, 'insurance', f.insurance_status,
              'tracker', (SELECT b.telemetry_status FROM trustride.resource_telemetry_binding b WHERE b.fleet_resource_id = f.fleet_resource_id AND b.status = 'ACTIVE'))
            FROM trustride.resource_fleet_register f JOIN trustride.object_registry ob ON ob.object_id = f.object_id WHERE f.fleet_resource_id = unit.fleet_resource_id),
        'capabilities', coalesce((SELECT jsonb_agg(jsonb_build_object('type', c.capability_type, 'expires_at', c.expires_at, 'verified', c.verified))
            FROM trustride.resource_workforce_capability c WHERE c.workforce_unit_id = unit.workforce_unit_id AND c.active), '[]'::jsonb))
      FROM unit JOIN trustride.resource_capacity_class cc ON cc.capacity_class_id = unit.capacity_class_id
      JOIN trustride.resource_estate_register er ON er.estate_id = unit.primary_estate_id),
    'onboarding_pending', NOT EXISTS (SELECT 1 FROM unit),
    'rating', (SELECT jsonb_build_object('avg', round(avg(r.rating), 1), 'count', count(*)) FROM trustride.business_review r, u WHERE r.reviewee_user_id = u.id),
    'active_jobs', coalesce((SELECT jsonb_agg(trustride.fn_present_operator_job_card(x.order_id)) FROM (
        SELECT DISTINCT j.order_id FROM trustride.business_job j, unit WHERE j.workforce_unit_id = unit.workforce_unit_id
        AND j.status NOT IN ('VERIFIED', 'CANCELLED', 'FAILED')) x), '[]'::jsonb),
    'recent_jobs', coalesce((SELECT jsonb_agg(jsonb_build_object('order_code', x.order_code, 'completed_at', x.completed_at, 'service', x.service_code) ORDER BY x.completed_at DESC)
        FROM (SELECT o.order_code, max(j.completed_at) AS completed_at, o.service_code FROM trustride.business_job j
              JOIN trustride.business_order o ON o.order_id = j.order_id
              JOIN trustride.resource_workforce_unit wu ON wu.workforce_unit_id = j.workforce_unit_id, u
              WHERE wu.operator_user_id = u.id AND j.status = 'VERIFIED' GROUP BY o.order_code, o.service_code ORDER BY 2 DESC LIMIT 10) x), '[]'::jsonb));
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_operator_job(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM trustride.business_job j JOIN trustride.resource_workforce_unit wu ON wu.workforce_unit_id = j.workforce_unit_id
                 WHERE j.order_id = (p_params->>'order_id')::uuid AND wu.operator_user_id = trustride.fn_present_session_user(p_session)) THEN
    RAISE EXCEPTION 'This job is not assigned to you';
  END IF;
  RETURN trustride.fn_present_operator_job_card((p_params->>'order_id')::uuid);
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. TrustRide Office (Admin Console / Executive Dashboard)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_present_proj_office_overview(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object(
    'health', trustride.fn_present_platform_health(),
    'orders', (SELECT jsonb_object_agg(status, n) FROM (SELECT status::text, count(*) n FROM trustride.business_order
               WHERE order_root_type = 'SERVICE_ORDER' AND status NOT IN ('SETTLED', 'REVIEWED', 'CLOSED') OR (closed_at > now() - interval '1 day') GROUP BY status) x),
    'waiting_orders', (SELECT count(*) FROM trustride.business_order WHERE status = 'WAITING'),
    'pending_requests', (SELECT count(*) FROM trustride.business_partnership_response WHERE response_status IN ('SUBMITTED', 'UNDER_REVIEW')),
    'escalated_requests', (SELECT count(*) FROM trustride.business_partnership_response WHERE response_status IN ('SUBMITTED', 'UNDER_REVIEW') AND escalated_at IS NOT NULL),
    'units', (SELECT jsonb_object_agg(st, n) FROM (SELECT trustride.fn_resource_unit_availability(workforce_unit_id)::text st, count(*) n
               FROM trustride.resource_workforce_unit WHERE unit_status = 'ACTIVE' GROUP BY 1) x),
    'open_cases', (SELECT jsonb_object_agg(severity, n) FROM (SELECT severity, count(*) n FROM trustride.business_support_case WHERE status NOT IN ('RESOLVED', 'CLOSED') GROUP BY 1) x),
    'failed_payments', (SELECT count(*) FROM trustride.business_settlement WHERE payment_status = 'FAILED'),
    'stale_trackers', (SELECT count(*) FROM trustride.resource_telemetry_binding WHERE status = 'ACTIVE' AND telemetry_status = 'STALE'),
    'alerts', coalesce((SELECT jsonb_agg(jsonb_build_object('title', n.title, 'body', n.body, 'category', n.category, 'at', n.delivered_at, 'critical', n.critical)
        ORDER BY n.delivered_at DESC) FROM (SELECT * FROM trustride.present_notification_inbox WHERE recipient_user_id = trustride.fn_present_session_user(p_session)
        AND top_shell = 'TRUSTRIDE_OFFICE' AND category <> 'SECRET' ORDER BY delivered_at DESC LIMIT 15) n), '[]'::jsonb));
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_office_requests(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object('requests', coalesce(jsonb_agg(jsonb_build_object('order_id', o.order_id, 'order_code', o.order_code, 'root', o.order_root_type,
      'requester', (SELECT display_name FROM trustride.platform_users WHERE user_id = o.requester_user_id), 'requester_user_id', o.requester_user_id,
      'placed_at', o.placed_at, 'status', o.status,
      'lines', (SELECT jsonb_agg(jsonb_build_object('description', l.line_description, 'scope', l.scope_detail) ORDER BY l.line_sequence) FROM trustride.business_order_line l WHERE l.order_id = o.order_id),
      'response', jsonb_build_object('status', r.response_status, 'target', r.decision_target_at, 'deadline', r.response_due_at, 'escalated_at', r.escalated_at,
         'notes', r.response_notes, 'responded_at', r.responded_at))
      ORDER BY (r.response_status IN ('SUBMITTED', 'UNDER_REVIEW')) DESC, r.escalated_at NULLS LAST, o.placed_at), '[]'::jsonb))
  FROM trustride.business_order o JOIN trustride.business_partnership_response r ON r.order_id = o.order_id
  WHERE r.response_status IN ('SUBMITTED', 'UNDER_REVIEW') OR r.responded_at > now() - interval '14 days';
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_office_orders(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object('orders', coalesce(jsonb_agg(trustride.fn_present_order_summary(x.order_id) || jsonb_build_object(
      'customer', (SELECT display_name FROM trustride.platform_users WHERE user_id = x.requester_user_id),
      'waiting_since', x.waiting_since, 'attempts', x.assignment_attempts,
      'operator', (SELECT p.display_name FROM trustride.business_job j JOIN trustride.resource_workforce_unit wu ON wu.workforce_unit_id = j.workforce_unit_id
                   JOIN trustride.platform_users p ON p.user_id = wu.operator_user_id WHERE j.order_id = x.order_id AND j.status NOT IN ('CANCELLED', 'FAILED') LIMIT 1))
      ORDER BY (x.status IN ('WAITING', 'FAILED')) DESC, x.placed_at DESC), '[]'::jsonb))
  FROM (SELECT * FROM trustride.business_order
        WHERE order_root_type IN ('SERVICE_ORDER', 'MARKETPLACE_PURCHASE_ORDER')
          AND (coalesce(p_params->>'filter', 'LIVE') = 'ALL'
               OR (p_params->>'filter' = 'EXCEPTIONS' AND status IN ('WAITING', 'FAILED', 'EXPIRED'))
               OR (coalesce(p_params->>'filter', 'LIVE') = 'LIVE' AND status NOT IN ('SETTLED', 'REVIEWED', 'CLOSED', 'CANCELLED', 'EXPIRED', 'FAILED', 'DECLINED')))
        ORDER BY placed_at DESC LIMIT 200) x;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_office_resources(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object(
    'estates', coalesce((SELECT jsonb_agg(jsonb_build_object('estate_id', estate_id, 'code', estate_code, 'name', estate_name, 'type', estate_type, 'jurisdiction', jurisdiction))
       FROM trustride.resource_estate_register WHERE active), '[]'::jsonb),
    'vehicles', coalesce((SELECT jsonb_agg(jsonb_build_object('object_id', ob.object_id, 'type', ob.object_type, 'label', trim(concat_ws(' ', ob.make, ob.model)),
         'plate', ob.plate_number, 'status', ob.status, 'custodian', (SELECT display_name FROM trustride.platform_users WHERE user_id = ob.custody_user_id),
         'fleet', (SELECT jsonb_build_object('fleet_resource_id', f.fleet_resource_id, 'class', cc.class_code, 'lifecycle', f.lifecycle_state,
              'ownership', f.ownership_type, 'inspection', f.inspection_status, 'insurance', f.insurance_status,
              'bound_unit', (SELECT wu.workforce_unit_id FROM trustride.resource_workforce_unit wu WHERE wu.fleet_resource_id = f.fleet_resource_id AND wu.unit_status = 'ACTIVE'),
              'tracker', (SELECT jsonb_build_object('device', b.provider_device_ref, 'status', b.telemetry_status, 'last_seen_at', b.last_seen_at)
                          FROM trustride.resource_telemetry_binding b WHERE b.fleet_resource_id = f.fleet_resource_id AND b.status = 'ACTIVE'))
            FROM trustride.resource_fleet_register f JOIN trustride.resource_capacity_class cc ON cc.capacity_class_id = f.capacity_class_id
            WHERE f.object_id = ob.object_id AND f.active))
         ORDER BY ob.created_at DESC)
       FROM trustride.object_registry ob WHERE ob.object_type IN ('MOTORCYCLE', 'CAR', 'TUKTUK', 'PICKUP', 'VAN', 'TRUCK') AND ob.status <> 'RETIRED'), '[]'::jsonb),
    'devices', coalesce((SELECT jsonb_agg(jsonb_build_object('object_id', ob.object_id, 'serial', ob.serial_number, 'model', trim(concat_ws(' ', ob.make, ob.model)),
         'bound', EXISTS (SELECT 1 FROM trustride.resource_telemetry_binding b WHERE b.device_object_id = ob.object_id AND b.status = 'ACTIVE')))
       FROM trustride.object_registry ob WHERE ob.object_type = 'TRACKING_DEVICE' AND ob.status <> 'RETIRED'), '[]'::jsonb),
    'units', coalesce((SELECT jsonb_agg(jsonb_build_object('workforce_unit_id', wu.workforce_unit_id,
         'operator', (SELECT display_name FROM trustride.platform_users WHERE user_id = wu.operator_user_id), 'operator_user_id', wu.operator_user_id,
         'class', cc.class_code, 'base', er.estate_name, 'availability', trustride.fn_resource_unit_availability(wu.workforce_unit_id),
         'plate', (SELECT ob.plate_number FROM trustride.resource_fleet_register f JOIN trustride.object_registry ob ON ob.object_id = f.object_id WHERE f.fleet_resource_id = wu.fleet_resource_id),
         'capabilities', coalesce((SELECT jsonb_agg(jsonb_build_object('capability_id', c.capability_id, 'type', c.capability_type, 'ref', c.credential_ref, 'expires_at', c.expires_at))
              FROM trustride.resource_workforce_capability c WHERE c.workforce_unit_id = wu.workforce_unit_id AND c.active), '[]'::jsonb))
         ORDER BY cc.class_code)
       FROM trustride.resource_workforce_unit wu JOIN trustride.resource_capacity_class cc ON cc.capacity_class_id = wu.capacity_class_id
       JOIN trustride.resource_estate_register er ON er.estate_id = wu.primary_estate_id WHERE wu.unit_status = 'ACTIVE'), '[]'::jsonb),
    'operators_awaiting_unit', coalesce((SELECT jsonb_agg(jsonb_build_object('user_id', a.user_id, 'name', p.display_name))
       FROM trustride.business_actor_registration a JOIN trustride.platform_users p ON p.user_id = a.user_id
       WHERE a.user_type_domain = 'OPERATOR' AND a.registration_status = 'ACTIVE'
         AND NOT EXISTS (SELECT 1 FROM trustride.resource_workforce_unit wu WHERE wu.operator_user_id = a.user_id AND wu.unit_status = 'ACTIVE')), '[]'::jsonb),
    'classes', (SELECT jsonb_agg(jsonb_build_object('code', class_code, 'label', class_label, 'requires_fleet', requires_fleet)) FROM trustride.resource_capacity_class WHERE active),
    'capability_types', (SELECT jsonb_agg(v) FROM unnest(enum_range(NULL::trustride.resource_capability_type_enum)) v));
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_office_tracking(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
  SELECT jsonb_build_object('vehicles', coalesce(jsonb_agg(jsonb_build_object('plate', ob.plate_number, 'device', b.provider_device_ref,
      'status', b.telemetry_status, 'last_seen_at', b.last_seen_at, 'lat', ST_Y(b.last_location), 'lon', ST_X(b.last_location),
      'unit_availability', (SELECT trustride.fn_resource_unit_availability(wu.workforce_unit_id) FROM trustride.resource_workforce_unit wu
                            WHERE wu.fleet_resource_id = b.fleet_resource_id AND wu.unit_status = 'ACTIVE'),
      'on_order', (SELECT o.order_code FROM trustride.resource_location_event le JOIN trustride.business_order o ON o.order_id = le.order_id
                   WHERE le.fleet_resource_id = b.fleet_resource_id AND le.recorded_at > now() - interval '15 minutes' ORDER BY le.recorded_at DESC LIMIT 1))
      ORDER BY b.telemetry_status, ob.plate_number), '[]'::jsonb),
    'active_jobs', coalesce((SELECT jsonb_agg(jsonb_build_object('order_code', o.order_code, 'status', t.tracking_status, 'lat', ST_Y(t.exact_location),
        'lon', ST_X(t.exact_location), 'updated_at', t.updated_at))
      FROM trustride.business_tracking_session t JOIN trustride.business_job j ON j.job_id = t.job_id JOIN trustride.business_order o ON o.order_id = j.order_id
      WHERE t.ended_at IS NULL), '[]'::jsonb))
  FROM trustride.resource_telemetry_binding b JOIN trustride.resource_fleet_register f ON f.fleet_resource_id = b.fleet_resource_id
  JOIN trustride.object_registry ob ON ob.object_id = f.object_id WHERE b.status = 'ACTIVE';
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_office_marketplace(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object(
    'inventory', coalesce((SELECT jsonb_agg(jsonb_build_object('inventory_item_id', i.inventory_item_id, 'item_code', i.item_code, 'category', i.category,
        'state', i.lifecycle_state, 'acquisition_cost_kes', i.acquisition_cost_kes, 'valuation_kes', i.valuation_kes,
        'inspection', i.inspection_status, 'refurbishment', i.refurbishment_status, 'compliance', i.compliance_status) ORDER BY i.created_at DESC)
      FROM trustride.resource_marketplace_inventory i WHERE i.lifecycle_state NOT IN ('RETIRED')), '[]'::jsonb),
    'listings', coalesce((SELECT jsonb_agg(jsonb_build_object('listing_id', l.listing_id, 'title', l.title, 'type', l.listing_type, 'category', l.vehicle_category,
        'price_kes', l.list_price_kes, 'status', l.listing_status, 'vendor', (SELECT display_name FROM trustride.platform_users WHERE user_id = l.vendor_user_id),
        'reserved_until', l.reserved_until) ORDER BY l.created_at DESC) FROM trustride.service_marketplace_listing l WHERE l.listing_status <> 'DELISTED'), '[]'::jsonb),
    'purchases', coalesce((SELECT jsonb_agg(trustride.fn_present_order_summary(o.order_id) || jsonb_build_object(
        'buyer', (SELECT display_name FROM trustride.platform_users WHERE user_id = o.requester_user_id)) ORDER BY o.placed_at DESC)
      FROM trustride.business_order o WHERE o.order_root_type = 'MARKETPLACE_PURCHASE_ORDER' AND o.status IN ('PLACED', 'AWAITING_PAYMENT', 'SETTLED', 'COMPLETED')), '[]'::jsonb),
    'payouts', coalesce((SELECT jsonb_agg(jsonb_build_object('payout_id', p.payout_id, 'vendor', (SELECT display_name FROM trustride.platform_users WHERE user_id = p.vendor_user_id),
        'gross_kes', p.gross_kes, 'commission_kes', p.commission_kes, 'payout_kes', p.payout_kes, 'status', p.status, 'failure_reason', p.failure_reason) ORDER BY p.created_at DESC)
      FROM trustride.business_marketplace_payout p), '[]'::jsonb),
    'estates', coalesce((SELECT jsonb_agg(jsonb_build_object('estate_id', estate_id, 'name', estate_name)) FROM trustride.resource_estate_register WHERE active), '[]'::jsonb));
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_office_support(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object('cases', coalesce(jsonb_agg(jsonb_build_object('case_id', c.case_id, 'case_code', c.case_code, 'category', c.category,
      'severity', c.severity, 'subject', c.subject, 'status', c.status, 'opened_at', c.opened_at, 'sla_due_at', c.sla_due_at, 'escalated_at', c.escalated_at,
      'requester', (SELECT display_name FROM trustride.platform_users WHERE user_id = c.opened_by_user_id),
      'assigned_to', (SELECT display_name FROM trustride.platform_users WHERE user_id = c.assigned_to),
      'order_code', (SELECT order_code FROM trustride.business_order WHERE order_id = c.order_id), 'order_id', c.order_id,
      'messages', coalesce((SELECT jsonb_agg(jsonb_build_object('author', m.author_role, 'body', m.body, 'internal', m.internal_note, 'at', m.created_at) ORDER BY m.created_at)
                  FROM trustride.business_support_message m WHERE m.case_id = c.case_id), '[]'::jsonb))
      ORDER BY (c.status IN ('RESOLVED', 'CLOSED')), CASE c.severity WHEN 'CRITICAL' THEN 0 WHEN 'HIGH' THEN 1 ELSE 2 END, c.sla_due_at), '[]'::jsonb))
  FROM trustride.business_support_case c WHERE c.status NOT IN ('CLOSED') OR c.closed_at > now() - interval '7 days';
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_office_users(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object('users', coalesce(jsonb_agg(jsonb_build_object('user_id', pu.user_id, 'name', pu.display_name, 'uid', pu.global_uid,
      'primitive', pu.identity_primitive, 'status', pu.status, 'created_at', pu.created_at,
      'environments', coalesce((SELECT jsonb_agg(jsonb_build_object('domain', a.user_type_domain, 'status', a.registration_status)) FROM trustride.business_actor_registration a WHERE a.user_id = pu.user_id), '[]'::jsonb),
      'roles', coalesce((SELECT jsonb_agg(rd.role_code) FROM trustride.role_assignment ra JOIN trustride.role_definition rd ON rd.role_id = ra.role_id
                WHERE ra.user_id = pu.user_id AND ra.status = 'ACTIVE' AND (ra.valid_to IS NULL OR ra.valid_to > now())), '[]'::jsonb),
      'phone_verified', EXISTS (SELECT 1 FROM trustride.user_contact c WHERE c.user_id = pu.user_id AND c.contact_type = 'PHONE' AND c.is_verified AND c.status = 'ACTIVE'),
      'governor_scopes', (SELECT jsonb_agg(gr.data_scope) FROM trustride.business_governor_data_grant gr JOIN trustride.business_governor_engagement g ON g.governor_engagement_id = gr.governor_engagement_id
                JOIN trustride.business_actor_registration a ON a.actor_registration_id = g.actor_registration_id WHERE a.user_id = pu.user_id AND gr.revoked_at IS NULL))
      ORDER BY pu.created_at DESC), '[]'::jsonb),
    'roles_available', (SELECT jsonb_agg(role_code) FROM trustride.role_definition WHERE role_code <> 'FOUNDER'),
    'governor_scopes_available', '["AGGREGATE_SERVICE_VOLUMES","AGGREGATE_REVENUE_AND_TAX","FLEET_COMPLIANCE_SUMMARY","SAFETY_INCIDENT_SUMMARY"]'::jsonb)
  FROM (SELECT * FROM trustride.platform_users
        WHERE identity_primitive IN ('PERSON', 'ENTITY')
          AND (coalesce(p_params->>'q', '') = '' OR display_name ILIKE '%' || (p_params->>'q') || '%' OR global_uid ILIKE '%' || (p_params->>'q') || '%')
        ORDER BY created_at DESC LIMIT 100) pu;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_office_integrations(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object(
    'gateway_configured', trustride.fn_integration_gateway_configured(),
    'ports', (SELECT jsonb_agg(jsonb_build_object('port', p.port_code, 'vendor', p.primary_vendor, 'adapter', trustride.fn_integration_adapter_mode(p.port_code),
         'circuit', (SELECT state FROM trustride.integration_circuit_breaker_state c WHERE c.port_code = p.port_code)) ORDER BY p.port_code)
       FROM trustride.integration_port_registry p WHERE p.active),
    'outbound', (SELECT jsonb_object_agg(status, n) FROM (SELECT status, count(*) n FROM trustride.integration_outbound_request WHERE created_at > now() - interval '1 day' GROUP BY status) x),
    'recent_failures', coalesce((SELECT jsonb_agg(jsonb_build_object('operation', operation, 'status', status, 'error', last_error, 'at', created_at) ORDER BY created_at DESC)
       FROM (SELECT * FROM trustride.integration_outbound_request WHERE status IN ('FAILED', 'FAILED_RETRYABLE', 'WAITING_CONFIGURATION') ORDER BY created_at DESC LIMIT 20) f), '[]'::jsonb),
    'systems', coalesce((SELECT jsonb_agg(jsonb_build_object('user_id', e.user_id, 'name', e.legal_name, 'status', pu.status,
         'credentials', coalesce((SELECT jsonb_agg(jsonb_build_object('prefix', k.key_prefix, 'scopes', k.scopes, 'status', k.status, 'last_used_at', k.last_used_at, 'expires_at', k.expires_at))
              FROM trustride.entity_system_credential k WHERE k.system_user_id = e.user_id), '[]'::jsonb)))
       FROM trustride.entity_profile e JOIN trustride.platform_users pu ON pu.user_id = e.user_id WHERE e.entity_type = 'EXTERNAL_SYSTEM'), '[]'::jsonb),
    'telemetry', (SELECT jsonb_build_object('batches_24h', count(*), 'points_24h', coalesce(sum(accepted_count), 0), 'rejected_24h', coalesce(sum(rejected_count), 0))
       FROM trustride.integration_telemetry_ingest_log WHERE received_at > now() - interval '1 day'));
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_office_health(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object(
    'health', trustride.fn_present_platform_health(),
    'jobs', (SELECT jsonb_agg(to_jsonb(j)) FROM trustride.fn_platform_job_health() j),
    'dead_letters', coalesce((SELECT jsonb_agg(jsonb_build_object('source', d.source_engine, 'target', d.target_engine, 'reason', d.failure_reason, 'at', d.created_at, 'resolution', d.resolution)
        ORDER BY d.created_at DESC) FROM (SELECT * FROM trustride.dead_letter_review ORDER BY created_at DESC LIMIT 25) d), '[]'::jsonb),
    'conformance', coalesce((SELECT jsonb_agg(to_jsonb(v)) FROM trustride.fn_platform_conformance_violations() v), '[]'::jsonb),
    'engines', coalesce((SELECT jsonb_agg(jsonb_build_object('engine', h.engine_code, 'score', h.health_score, 'status', h.health_status, 'at', h.measured_at))
        FROM (SELECT DISTINCT ON (engine_code) * FROM trustride.coord_coordination_health ORDER BY engine_code, measured_at DESC) h), '[]'::jsonb));
$$;

-- ---------------------------------------------------------------------------
-- 7. Executive Dashboard (G19)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_present_proj_exec_kpis(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  WITH w AS (SELECT now() - make_interval(days => coalesce((p_params->>'days')::int, 30)) AS since),
  o AS (SELECT bo.* FROM trustride.business_order bo, w WHERE bo.order_root_type = 'SERVICE_ORDER' AND bo.placed_at > w.since)
  SELECT jsonb_build_object(
    'window_days', coalesce((p_params->>'days')::int, 30),
    'orders_placed', (SELECT count(*) FROM o),
    'orders_completed', (SELECT count(*) FROM o WHERE status IN ('COMPLETED', 'SETTLED', 'REVIEWED', 'CLOSED')),
    'orders_cancelled', (SELECT count(*) FROM o WHERE status = 'CANCELLED'),
    'orders_expired_or_failed', (SELECT count(*) FROM o WHERE status IN ('EXPIRED', 'FAILED')),
    'completion_rate_pct', (SELECT round(100.0 * count(*) FILTER (WHERE status IN ('COMPLETED', 'SETTLED', 'REVIEWED', 'CLOSED')) / nullif(count(*), 0), 1) FROM o),
    'revenue_settled_kes', (SELECT coalesce(sum(s.computed_total_fare_kes), 0) FROM trustride.business_settlement s JOIN o ON o.order_id = s.order_id WHERE s.payment_status = 'RECEIPT_GENERATED'),
    'avg_fare_kes', (SELECT round(avg(s.computed_total_fare_kes), 2) FROM trustride.business_settlement s JOIN o ON o.order_id = s.order_id WHERE s.payment_status = 'RECEIPT_GENERATED'),
    'by_family', (SELECT jsonb_object_agg(macro_domain, n) FROM (SELECT macro_domain, count(*) n FROM o GROUP BY 1) x),
    'units_on_duty_now', (SELECT count(*) FROM trustride.resource_workforce_unit WHERE unit_status = 'ACTIVE' AND trustride.fn_resource_unit_availability(workforce_unit_id) IN ('AVAILABLE', 'RESERVED', 'ASSIGNED')),
    'units_busy_now', (SELECT count(*) FROM trustride.resource_workforce_unit WHERE unit_status = 'ACTIVE' AND trustride.fn_resource_unit_availability(workforce_unit_id) IN ('RESERVED', 'ASSIGNED')),
    'marketplace_sales_kes', (SELECT coalesce(sum(s.computed_total_fare_kes), 0) FROM trustride.business_settlement s JOIN trustride.business_order bo ON bo.order_id = s.order_id, w
                              WHERE bo.order_root_type = 'MARKETPLACE_PURCHASE_ORDER' AND s.payment_status = 'RECEIPT_GENERATED' AND bo.placed_at > w.since),
    'marketplace_commission_kes', (SELECT coalesce(sum(p.commission_kes), 0) FROM trustride.business_marketplace_payout p, w WHERE p.created_at > w.since),
    'rating_avg', (SELECT round(avg(r.rating), 2) FROM trustride.business_review r, w WHERE r.created_at > w.since),
    'support_open', (SELECT count(*) FROM trustride.business_support_case WHERE status NOT IN ('RESOLVED', 'CLOSED')),
    'support_sla_breached', (SELECT count(*) FROM trustride.business_support_case c, w WHERE c.escalated_at > w.since),
    'health', trustride.fn_present_platform_health());
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_exec_advisory(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object(
    'recommendations', coalesce((SELECT jsonb_agg(jsonb_build_object('recommendation_id', r.recommendation_id, 'type', r.recommendation_type,
        'subject_engine', r.subject_engine_code, 'payload', r.recommendation_payload, 'confidence', r.confidence_score, 'generated_at', r.generated_at,
        'expires_at', r.expires_at, 'outcome', (SELECT o.outcome FROM trustride.advisory_recommendation_outcome o WHERE o.recommendation_id = r.recommendation_id
            ORDER BY o.decided_at DESC LIMIT 1)) ORDER BY r.generated_at DESC)
      FROM (SELECT * FROM trustride.advisory_recommendation ORDER BY generated_at DESC LIMIT 50) r), '[]'::jsonb),
    'anomalies', coalesce((SELECT jsonb_agg(jsonb_build_object('type', a.anomaly_type, 'severity', a.severity, 'source', a.source_engine_code,
        'description', a.description, 'detected_at', a.detected_at) ORDER BY a.detected_at DESC)
      FROM (SELECT * FROM trustride.advisory_anomaly_detection ORDER BY detected_at DESC LIMIT 50) a), '[]'::jsonb));
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_exec_scenarios(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object(
    'scenarios', coalesce((SELECT jsonb_agg(jsonb_build_object('code', s.scenario_code, 'name', s.scenario_name, 'type', s.scenario_type,
        'description', s.description, 'input_schema', s.input_schema) ORDER BY s.scenario_name)
      FROM trustride.model_scenario_registry s WHERE s.active), '[]'::jsonb),
    'runs', coalesce((SELECT jsonb_agg(jsonb_build_object('run_id', r.run_id, 'scenario', s.scenario_code, 'label', r.run_label, 'status', r.run_status,
        'failure_reason', r.failure_reason, 'started_at', r.started_at, 'completed_at', r.completed_at,
        'outcomes', (SELECT jsonb_agg(to_jsonb(po) - 'run_id') FROM trustride.model_projected_outcome po WHERE po.run_id = r.run_id),
        'insights', (SELECT jsonb_agg(to_jsonb(ai) - 'run_id') FROM trustride.model_actionable_insight ai WHERE ai.run_id = r.run_id))
        ORDER BY r.created_at DESC)
      FROM (SELECT * FROM trustride.model_scenario_run ORDER BY created_at DESC LIMIT 20) r JOIN trustride.model_scenario_registry s ON s.scenario_registry_id = r.scenario_registry_id), '[]'::jsonb));
$$;

-- ---------------------------------------------------------------------------
-- 8. Partner, Governor, Intermediary
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_present_proj_partner_home(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  WITH u AS (SELECT trustride.fn_present_session_user(p_session) AS id)
  SELECT jsonb_build_object(
    'registration', (SELECT a.registration_status FROM trustride.business_actor_registration a, u WHERE a.user_id = u.id AND a.user_type_domain = 'PARTNER'),
    'agreements', coalesce((SELECT jsonb_agg(jsonb_build_object('category', pa.partner_category, 'type', pa.agreement_type, 'start_date', pa.start_date,
         'status', pa.status, 'commission_pct', pa.agreement_terms->>'commission_pct'))
       FROM trustride.business_partner_agreement pa JOIN trustride.business_actor_registration a ON a.actor_registration_id = pa.actor_registration_id, u
       WHERE a.user_id = u.id), '[]'::jsonb),
    'vehicles', coalesce((SELECT jsonb_agg(jsonb_build_object('plate', ob.plate_number, 'label', trim(concat_ws(' ', ob.make, ob.model)), 'object_status', ob.status,
         'class', (SELECT cc.class_code FROM trustride.resource_fleet_register f JOIN trustride.resource_capacity_class cc ON cc.capacity_class_id = f.capacity_class_id WHERE f.object_id = ob.object_id AND f.active),
         'fleet_status', (SELECT f.lifecycle_state FROM trustride.resource_fleet_register f WHERE f.object_id = ob.object_id AND f.active),
         'in_service', EXISTS (SELECT 1 FROM trustride.resource_fleet_register f JOIN trustride.resource_workforce_unit wu ON wu.fleet_resource_id = f.fleet_resource_id
                               WHERE f.object_id = ob.object_id AND wu.unit_status = 'ACTIVE'),
         'jobs_completed', (SELECT count(DISTINCT j.order_id) FROM trustride.resource_fleet_register f JOIN trustride.resource_workforce_unit wu ON wu.fleet_resource_id = f.fleet_resource_id
                            JOIN trustride.business_job j ON j.workforce_unit_id = wu.workforce_unit_id WHERE f.object_id = ob.object_id AND j.status = 'VERIFIED'))
         ORDER BY ob.created_at DESC)
       FROM trustride.object_registry ob, u WHERE ob.custody_user_id = u.id AND ob.object_type IN ('MOTORCYCLE', 'CAR', 'TUKTUK', 'PICKUP', 'VAN', 'TRUCK')), '[]'::jsonb),
    'bases', coalesce((SELECT jsonb_agg(jsonb_build_object('estate_id', estate_id, 'name', estate_name)) FROM trustride.resource_estate_register WHERE active AND estate_type = 'OPERATING_HUB'), '[]'::jsonb));
$$;

-- D4: a governor sees only the aggregate scopes TrustRide Office granted,
-- for the granted jurisdiction; nothing personal; nothing without a grant.
CREATE OR REPLACE FUNCTION trustride.fn_present_proj_governor_oversight(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_user UUID := trustride.fn_present_session_user(p_session);
  v_eng RECORD;
  v_out JSONB := '{}'::jsonb;
  g RECORD;
BEGIN
  SELECT ge.* INTO v_eng FROM trustride.business_governor_engagement ge JOIN trustride.business_actor_registration a ON a.actor_registration_id = ge.actor_registration_id
  WHERE a.user_id = v_user;
  IF v_eng.governor_engagement_id IS NULL OR v_eng.engagement_status <> 'ACTIVE' THEN
    RETURN jsonb_build_object('engagement', NULL, 'scopes', '[]'::jsonb, 'message', 'Your oversight engagement opens once TrustRide Office approves your regulatory access request.');
  END IF;
  FOR g IN SELECT * FROM trustride.business_governor_data_grant WHERE governor_engagement_id = v_eng.governor_engagement_id AND revoked_at IS NULL LOOP
    v_out := v_out || jsonb_build_object(g.data_scope, CASE g.data_scope
      WHEN 'AGGREGATE_SERVICE_VOLUMES' THEN (SELECT jsonb_build_object('last_30_days', jsonb_object_agg(macro_domain, n)) FROM (
          SELECT macro_domain, count(*) n FROM trustride.business_order WHERE order_root_type = 'SERVICE_ORDER' AND jurisdiction = g.jurisdiction
          AND status IN ('COMPLETED', 'SETTLED', 'REVIEWED', 'CLOSED') AND placed_at > now() - interval '30 days' GROUP BY 1) x)
      WHEN 'AGGREGATE_REVENUE_AND_TAX' THEN (SELECT jsonb_build_object('last_30_days_settled_kes', coalesce(sum(s.computed_total_fare_kes), 0), 'transactions', count(*))
          FROM trustride.business_settlement s JOIN trustride.business_order o ON o.order_id = s.order_id
          WHERE o.jurisdiction = g.jurisdiction AND s.payment_status = 'RECEIPT_GENERATED' AND s.settled_at > now() - interval '30 days')
      WHEN 'FLEET_COMPLIANCE_SUMMARY' THEN (SELECT jsonb_object_agg(cls || ':' || lc, n) FROM (
          SELECT cc.class_code::text cls, f.lifecycle_state::text lc, count(*) n FROM trustride.resource_fleet_register f
          JOIN trustride.resource_capacity_class cc ON cc.capacity_class_id = f.capacity_class_id
          JOIN trustride.resource_estate_register er ON er.estate_id = f.home_estate_id WHERE f.active AND er.jurisdiction = g.jurisdiction GROUP BY 1, 2) x)
      WHEN 'SAFETY_INCIDENT_SUMMARY' THEN (SELECT jsonb_build_object('last_90_days', jsonb_object_agg(status, n)) FROM (
          SELECT status, count(*) n FROM trustride.business_support_case WHERE category = 'SAFETY' AND opened_at > now() - interval '90 days' GROUP BY 1) x)
    END || jsonb_build_object('jurisdiction', g.jurisdiction, 'granted_at', g.granted_at));
  END LOOP;
  RETURN jsonb_build_object('engagement', jsonb_build_object('status', v_eng.engagement_status, 'scope', v_eng.oversight_scope, 'since', v_eng.engagement_start),
    'scopes', v_out,
    'message', CASE WHEN v_out = '{}'::jsonb THEN 'No data scopes have been granted yet. TrustRide Office grants each aggregate scope explicitly.' END);
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_intermediary_home(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  WITH e AS (SELECT ie.* FROM trustride.business_intermediary_engagement ie JOIN trustride.business_actor_registration a ON a.actor_registration_id = ie.actor_registration_id
             WHERE a.user_id = trustride.fn_present_session_user(p_session))
  SELECT jsonb_build_object(
    'engagement', (SELECT jsonb_build_object('type', intermediary_type, 'status', engagement_status, 'since', engagement_start, 'referral_code', referral_code) FROM e),
    'referrals', coalesce((SELECT jsonb_agg(jsonb_build_object('first_name', trustride.fn_present_first_name(r.referred_user_id), 'referred_at', r.referred_at,
         'environments', (SELECT jsonb_agg(a.user_type_domain) FROM trustride.business_actor_registration a WHERE a.user_id = r.referred_user_id AND a.registration_status = 'ACTIVE'),
         'orders_completed', (SELECT count(*) FROM trustride.business_order o WHERE o.requester_user_id = r.referred_user_id AND o.status IN ('SETTLED', 'REVIEWED')))
         ORDER BY r.referred_at DESC)
       FROM trustride.business_intermediary_referral r, e WHERE r.intermediary_engagement_id = e.intermediary_engagement_id), '[]'::jsonb));
$$;

-- ---------------------------------------------------------------------------
-- 9. Marketplace
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_present_proj_marketplace_listings(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT jsonb_build_object('listings', coalesce(jsonb_agg(jsonb_build_object('listing_id', l.listing_id, 'title', l.title, 'description', l.description,
      'category', l.vehicle_category, 'price_kes', l.list_price_kes, 'type', l.listing_type, 'listed_at', l.listed_at,
      'seller', CASE WHEN l.listing_type = 'OWN_MARKETPLACE' THEN 'TrustRide' ELSE trustride.fn_present_first_name(l.vendor_user_id) END,
      'mine', l.vendor_user_id = trustride.fn_present_session_user(p_session),
      'stk_payable', l.list_price_kes <= trustride.fn_business_config_num('PAYMENT_STK_MAX_KES', 250000)) ORDER BY l.listed_at DESC), '[]'::jsonb),
    'phone_verified', trustride.fn_user_payment_msisdn(trustride.fn_present_session_user(p_session)) IS NOT NULL)
  FROM trustride.service_marketplace_listing l
  WHERE l.listing_status = 'LISTED' AND (p_params->>'category' IS NULL OR l.vehicle_category = p_params->>'category');
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_proj_vendor_home(p_session UUID, p_params JSONB)
RETURNS JSONB LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  WITH u AS (SELECT trustride.fn_present_session_user(p_session) AS id)
  SELECT jsonb_build_object(
    'agreement', (SELECT jsonb_build_object('commission_pct', pa.agreement_terms->>'commission_pct', 'since', pa.start_date, 'status', pa.status)
       FROM trustride.business_partner_agreement pa JOIN trustride.business_actor_registration a ON a.actor_registration_id = pa.actor_registration_id, u
       WHERE a.user_id = u.id AND pa.partner_category = 'VENDOR' AND pa.status = 'ACTIVE' ORDER BY pa.created_at DESC LIMIT 1),
    'listings', coalesce((SELECT jsonb_agg(jsonb_build_object('listing_id', l.listing_id, 'title', l.title, 'category', l.vehicle_category, 'price_kes', l.list_price_kes,
         'status', l.listing_status, 'listed_at', l.listed_at) ORDER BY l.created_at DESC)
       FROM trustride.service_marketplace_listing l, u WHERE l.vendor_user_id = u.id), '[]'::jsonb),
    'sales', coalesce((SELECT jsonb_agg(jsonb_build_object('order_id', o.order_id, 'order_code', o.order_code, 'status', o.status, 'title', l.line_description,
         'buyer_first_name', trustride.fn_present_first_name(o.requester_user_id), 'price_kes', l.scope_detail->>'price_kes',
         'can_confirm_handover', o.status = 'SETTLED') ORDER BY o.placed_at DESC)
       FROM trustride.business_order o JOIN trustride.business_order_line l ON l.order_id = o.order_id, u
       WHERE o.order_root_type = 'MARKETPLACE_PURCHASE_ORDER' AND l.scope_detail->>'vendor_user_id' = u.id::text), '[]'::jsonb),
    'payouts', coalesce((SELECT jsonb_agg(jsonb_build_object('gross_kes', p.gross_kes, 'commission_kes', p.commission_kes, 'payout_kes', p.payout_kes,
         'status', p.status, 'paid_at', p.paid_at) ORDER BY p.created_at DESC) FROM trustride.business_marketplace_payout p, u WHERE p.vendor_user_id = u.id), '[]'::jsonb));
$$;

-- ---------------------------------------------------------------------------
-- 10. Registration of every projection (C-III-3)
-- ---------------------------------------------------------------------------
INSERT INTO trustride.projection_registry (projection_code, shell, source_tables, refresh_mode, sub_shells, description)
SELECT v.code, v.shell, v.src::jsonb, 'LIVE', v.subs, v.descr
FROM (VALUES
  ('NOTIFICATIONS', 'TRUSTRIDE_BUSINESS', '["present_notification_inbox"]', ARRAY['CUSTOMER_APP','PARTNER_APP','GOVERNOR_APP','INTERMEDIARY_APP','MARKETPLACE_APP','VENDOR_APP','OPERATOR_APP','ADMIN_CONSOLE','EXECUTIVE_DASHBOARD'], 'Inbox'),
  ('MY_PROFILE', 'TRUSTRIDE_BUSINESS', '["platform_users","user_contact","user_contact_preference","user_identifier","integration_notification_dispatch_log"]', ARRAY['CUSTOMER_APP','PARTNER_APP','GOVERNOR_APP','INTERMEDIARY_APP','MARKETPLACE_APP','VENDOR_APP','OPERATOR_APP','ADMIN_CONSOLE','EXECUTIVE_DASHBOARD'], 'Profile, contacts, preferences'),
  ('MY_SUPPORT', 'TRUSTRIDE_BUSINESS', '["business_support_case","business_support_message"]', ARRAY['CUSTOMER_APP','PARTNER_APP','GOVERNOR_APP','INTERMEDIARY_APP','MARKETPLACE_APP','VENDOR_APP','OPERATOR_APP'], 'My support cases'),
  ('REQUEST_HISTORY', 'TRUSTRIDE_BUSINESS', '["business_order","business_order_line","business_partnership_response"]', ARRAY['CUSTOMER_APP','PARTNER_APP','GOVERNOR_APP','INTERMEDIARY_APP','MARKETPLACE_APP','VENDOR_APP','OPERATOR_APP'], 'My governed requests'),
  ('SERVICE_CATALOGUE', 'TRUSTRIDE_BUSINESS', '["service_catalogue","service_macro_domain","service_eligibility_rule","cost_operational_zones"]', ARRAY['CUSTOMER_APP'], 'Catalogue and booking context'),
  ('CUSTOMER_HOME', 'TRUSTRIDE_BUSINESS', '["business_order","business_settlement","fare_quote"]', ARRAY['CUSTOMER_APP'], 'Customer home'),
  ('MY_ORDERS', 'TRUSTRIDE_BUSINESS', '["business_order","fare_quote","business_settlement"]', ARRAY['CUSTOMER_APP','MARKETPLACE_APP'], 'My orders / purchases'),
  ('ORDER_DETAIL', 'TRUSTRIDE_BUSINESS', '["business_order","business_order_line","business_job","fare_quote","fare_quote_line","business_tracking_session","integration_payment_gateway_transaction","business_review"]', ARRAY['CUSTOMER_APP','MARKETPLACE_APP'], 'One order, tracking, payment'),
  ('OPERATOR_HOME', 'TRUSTRIDE_OFFICE', '["resource_workforce_unit","resource_fleet_register","business_job","business_review"]', ARRAY['OPERATOR_APP'], 'Operator App home'),
  ('OPERATOR_JOB', 'TRUSTRIDE_OFFICE', '["business_job","business_order","business_order_line","business_settlement"]', ARRAY['OPERATOR_APP'], 'One job'),
  ('OFFICE_OVERVIEW', 'TRUSTRIDE_OFFICE', '["orch_capacity_snapshot","business_order","resource_workforce_unit","business_support_case"]', ARRAY['ADMIN_CONSOLE','EXECUTIVE_DASHBOARD'], 'Office overview'),
  ('OFFICE_REQUESTS', 'TRUSTRIDE_OFFICE', '["business_order","business_partnership_response"]', ARRAY['ADMIN_CONSOLE','EXECUTIVE_DASHBOARD'], 'Actor request queue'),
  ('OFFICE_ORDERS', 'TRUSTRIDE_OFFICE', '["business_order","business_job"]', ARRAY['ADMIN_CONSOLE','EXECUTIVE_DASHBOARD'], 'Live orders and exceptions'),
  ('OFFICE_RESOURCES', 'TRUSTRIDE_OFFICE', '["resource_estate_register","object_registry","resource_fleet_register","resource_workforce_unit","resource_workforce_capability"]', ARRAY['ADMIN_CONSOLE','EXECUTIVE_DASHBOARD'], 'Resources'),
  ('OFFICE_TRACKING', 'TRUSTRIDE_OFFICE', '["resource_telemetry_binding","resource_location_event","business_tracking_session"]', ARRAY['ADMIN_CONSOLE','EXECUTIVE_DASHBOARD'], 'Administrative tracking'),
  ('OFFICE_MARKETPLACE', 'TRUSTRIDE_OFFICE', '["resource_marketplace_inventory","service_marketplace_listing","business_marketplace_payout"]', ARRAY['ADMIN_CONSOLE','EXECUTIVE_DASHBOARD'], 'Marketplace operations'),
  ('OFFICE_SUPPORT', 'TRUSTRIDE_OFFICE', '["business_support_case","business_support_message"]', ARRAY['ADMIN_CONSOLE','EXECUTIVE_DASHBOARD'], 'Support queue'),
  ('OFFICE_USERS', 'TRUSTRIDE_OFFICE', '["platform_users","business_actor_registration","role_assignment","business_governor_data_grant"]', ARRAY['ADMIN_CONSOLE'], 'Users and roles'),
  ('OFFICE_INTEGRATIONS', 'TRUSTRIDE_OFFICE', '["integration_port_registry","integration_adapter_registry","integration_outbound_request","entity_system_credential","integration_telemetry_ingest_log"]', ARRAY['ADMIN_CONSOLE'], 'Integrations'),
  ('OFFICE_HEALTH', 'TRUSTRIDE_OFFICE', '["orch_capacity_snapshot","dead_letter_review","coord_coordination_health"]', ARRAY['ADMIN_CONSOLE','EXECUTIVE_DASHBOARD'], 'Platform health'),
  ('EXEC_KPIS', 'TRUSTRIDE_OFFICE', '["business_order","business_settlement","business_marketplace_payout","business_review","business_support_case"]', ARRAY['EXECUTIVE_DASHBOARD','ADMIN_CONSOLE'], 'KPIs'),
  ('EXEC_ADVISORY', 'TRUSTRIDE_OFFICE', '["advisory_recommendation","advisory_anomaly_detection","advisory_recommendation_outcome"]', ARRAY['EXECUTIVE_DASHBOARD','ADMIN_CONSOLE'], 'Advisory feed'),
  ('EXEC_SCENARIOS', 'TRUSTRIDE_OFFICE', '["model_scenario_registry","model_scenario_run","model_projected_outcome","model_actionable_insight"]', ARRAY['EXECUTIVE_DASHBOARD'], 'Scenario modelling'),
  ('PARTNER_HOME', 'TRUSTRIDE_BUSINESS', '["business_partner_agreement","object_registry","resource_fleet_register"]', ARRAY['PARTNER_APP'], 'Partner home'),
  ('GOVERNOR_OVERSIGHT', 'TRUSTRIDE_BUSINESS', '["business_governor_engagement","business_governor_data_grant"]', ARRAY['GOVERNOR_APP'], 'Granted oversight data (aggregate only)'),
  ('INTERMEDIARY_HOME', 'TRUSTRIDE_BUSINESS', '["business_intermediary_engagement","business_intermediary_referral"]', ARRAY['INTERMEDIARY_APP'], 'Referrals'),
  ('MARKETPLACE_LISTINGS', 'TRUSTRIDE_MARKETPLACE', '["service_marketplace_listing"]', ARRAY['MARKETPLACE_APP','VENDOR_APP'], 'Vehicles for sale'),
  ('VENDOR_HOME', 'TRUSTRIDE_MARKETPLACE', '["business_partner_agreement","service_marketplace_listing","business_order","business_marketplace_payout"]', ARRAY['VENDOR_APP'], 'Vendor home')
) AS v(code, shell, src, subs, descr)
WHERE NOT EXISTS (SELECT 1 FROM trustride.projection_registry r WHERE r.projection_code = v.code);

-- The existing card projection keeps working; make its sub-shells explicit.
UPDATE trustride.projection_registry SET sub_shells = ARRAY['CUSTOMER_APP'] WHERE projection_code = 'USER_ORDER_STATUS_CARD' AND sub_shells = ARRAY[]::TEXT[];

-- Office-only projections must also be gated by role (a session alone is
-- not enough once an Office sub-shell is open, the role decided the session).
-- That is already the case: Office sub-shell sessions open only for the
-- matching role (fn_present_shell_session_open).

-- ---------------------------------------------------------------------------
-- 11. Notification read receipts (the inbox is otherwise read-only)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_present_notifications_mark_read(p_session UUID)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  n INTEGER;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM trustride.present_shell_session WHERE session_id = p_session AND session_status = 'ACTIVE'
                 AND (user_id = auth.uid() OR acting_person_user_id = auth.uid())) THEN
    RAISE EXCEPTION 'SESSION_INVALID';
  END IF;
  UPDATE trustride.present_notification_inbox SET read_status = 'READ', read_at = now()
  WHERE recipient_user_id = trustride.fn_present_session_user(p_session) AND read_status = 'UNREAD';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$$;

-- ---------------------------------------------------------------------------
-- 11b. Customers learn their operator's first name only (never the full
--      legal name), in notifications as on screen.
-- ---------------------------------------------------------------------------
DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_present_order_progress_accept(uuid)'::regprocedure) INTO v_def;
  IF position('fn_present_first_name' IN v_def) = 0 THEN
    v_def := replace(v_def, E'SELECT display_name INTO v_op_name FROM trustride.platform_users WHERE user_id = (v_p->>''operator_user_id'')::uuid;',
      E'v_op_name := trustride.fn_present_first_name((v_p->>''operator_user_id'')::uuid);');
    IF position('fn_present_first_name' IN v_def) = 0 THEN RAISE EXCEPTION 'operator name patch did not apply'; END IF;
    EXECUTE v_def;
  END IF;
END;
$patch$;

-- ---------------------------------------------------------------------------
-- 12. Grants
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_present_projection(UUID, TEXT, JSONB) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_gate_context() TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_notifications_mark_read(UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_present_shell_session_end(UUID) TO trustride_authenticated;

SELECT trustride.fn_platform_conformance_assert();
