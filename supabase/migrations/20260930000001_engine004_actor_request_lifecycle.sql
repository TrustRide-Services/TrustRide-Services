-- ============================================================================
-- ENGINE 4 (BUSINESS) -- ACTOR REQUEST LIFECYCLE: NO WALLS
-- [Trace: TRS026-ENG011-PRESENT-003 Sec.4 (post-authorization flows),
--  Sec.4.5 (working-day SLA), Sec.6 (request handling: Business Engine +
--  Admin_Console), Sec.7 (external identities blocked from internal
--  operations); Founder direction 2026-10-01: "find a way they don't hit a wall"]
--
-- Walls found on the live platform before this migration, each closed here:
--   1. fn_business_actor_register was ungated: any signed-in caller could
--      register any environment -- including OPERATOR -- for any identity.
--      Now: self only; OPERATOR only through approved Office access; Customer
--      activates immediately (no waiting, Sec.4.1); Partner/Governor/
--      Intermediary register PENDING until their request is approved.
--   2. Requests could be decided only by the Business service role -- no
--      Admin could reach the queue, and a decision activated nothing.
--      Now: fn_business_actor_request_decide, gated to TrustRide Office
--      authority, activates exactly what was approved and notifies the actor.
--   3. The response window was 72 *calendar* hours and a missed window
--      auto-DECLINED the actor. Now: 2 working days target, 3 working days
--      deadline on TrustRide's own operating calendar (Mon-Fri 05:00-22:00,
--      Sat 06:00-23:00, Sunday off duty, public holidays excluded), the
--      clock starting at the next shift opening -- and a breach ESCALATES;
--      it never silently rejects anyone (Sec.4.5).
--   4. Nobody but the requester could read a request, so no review screen
--      could exist. Now: TrustRide Office authority can read the queue.
--   5. The vendor commission lived nowhere. Now: platform_configuration
--      MARKETPLACE_VENDOR_COMMISSION_PCT = 5, stamped into every approved
--      vendor agreement.
-- ============================================================================

-- ============================================================================
-- PHASE 1 -- FOUNDATION: ONE ROLE CHECK FOR TRUSTRIDE OFFICE AUTHORITY
-- ============================================================================
CREATE OR REPLACE FUNCTION trustride.fn_am_i_role(p_role_codes TEXT[])
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1 FROM trustride.role_assignment ra
    JOIN trustride.role_definition rd ON rd.role_id = ra.role_id
    WHERE ra.user_id = auth.uid() AND ra.status = 'ACTIVE'
      AND (ra.valid_to IS NULL OR ra.valid_to > now())
      AND rd.role_code = ANY (p_role_codes)
  );
$$;
COMMENT ON FUNCTION trustride.fn_am_i_role(TEXT[]) IS
  'Structural authority check by role_code set -- the Office surfaces need Founder/Administrator/Executive distinctions that fn_am_i_governor (any governance role) cannot express.';

-- Foundation's verification acceptance still granted the v1 shell name.
-- Rewritten in place from its live definition (one literal changed), and
-- existing grants moved to the shell that now exists.
DO $$
DECLARE v_def TEXT;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
  WHERE p.proname = 'fn_verification_completed_accept' AND p.pronamespace = 'trustride'::regnamespace;
  EXECUTE replace(v_def, '''USER_HUB''', '''TRUSTRIDE_BUSINESS''');
END;
$$;
UPDATE trustride.user_authorization SET shell_code = 'TRUSTRIDE_BUSINESS' WHERE shell_code = 'USER_HUB';

-- ============================================================================
-- PHASE 2 -- CONFIGURATION: MARKETPLACE VENDOR COMMISSION
-- ============================================================================
INSERT INTO trustride.platform_configuration (config_key, config_value, environment, effective_from, changed_by)
SELECT 'MARKETPLACE_VENDOR_COMMISSION_PCT', '5', 'ALL', now(), '00000000-0000-0000-0000-000000000000'
WHERE NOT EXISTS (SELECT 1 FROM trustride.platform_configuration WHERE config_key = 'MARKETPLACE_VENDOR_COMMISSION_PCT');

-- ============================================================================
-- PHASE 3 -- GATED ENVIRONMENT REGISTRATION (closes wall 1)
-- ============================================================================
CREATE OR REPLACE FUNCTION trustride.fn_business_actor_register(p_user_id UUID, p_user_type_domain trustride.business_user_type_domain_enum, p_terms_summary TEXT DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_actor_registration_id UUID;
  v_caller UUID := auth.uid();
  v_status TEXT := 'ACTIVE';
BEGIN
  -- A caller with no session is the platform itself (internal provisioning);
  -- a signed-in caller is a person acting on their own behalf.
  IF v_caller IS NOT NULL THEN
    IF p_user_id <> v_caller THEN
      RAISE EXCEPTION 'fn_business_actor_register: an environment can only be registered for your own identity';
    END IF;
    IF p_user_type_domain = 'OPERATOR' THEN
      RAISE EXCEPTION 'fn_business_actor_register: Operator is a TrustRide Office environment -- request Office access instead';
    END IF;
    -- Customer consumes immediately (Sec.4.1); every other external
    -- environment waits on an approved request (Sec.4.2-4.4).
    v_status := CASE WHEN p_user_type_domain = 'CUSTOMER' THEN 'ACTIVE' ELSE 'PENDING' END;
  END IF;

  INSERT INTO trustride.business_actor_registration (user_id, user_type_domain, terms_summary, registration_status)
  VALUES (p_user_id, p_user_type_domain, p_terms_summary, v_status)
  ON CONFLICT (user_id, user_type_domain) DO UPDATE
    SET terms_summary = coalesce(EXCLUDED.terms_summary, trustride.business_actor_registration.terms_summary)
  RETURNING actor_registration_id INTO v_actor_registration_id;

  PERFORM trustride.fn_audit_log_append('business_actor_registration', v_actor_registration_id, 'ACTOR_REGISTERED', p_user_id,
    'USER', NULL, NULL, NULL, jsonb_build_object('user_type_domain', p_user_type_domain, 'status', v_status));

  RETURN v_actor_registration_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_actor_register(UUID, trustride.business_user_type_domain_enum, TEXT) IS
  '[Trace: Article 12.9; TRS026-ENG011-PRESENT-003 Sec.4] Self only. Customer activates immediately; Partner/Governor/Intermediary register PENDING until approved; Operator only via approved Office access. Re-registering never raises a status.';

-- ============================================================================
-- PHASE 4 -- WORKING-DAY SLA (closes wall 3)
-- ============================================================================
-- TrustRide's operating calendar (Founder direction 2026-10-01), held as
-- configuration so it can change without a migration:
--   Monday-Friday 05:00-22:00, Saturday 06:00-23:00 (Africa/Nairobi)
--   Sunday is off duty -- record review, order planning, resource
--   maintenance and service day -- and never counts as a working day.
--   Foundation's calendar_reference PUBLIC_HOLIDAY dates do not count either.
INSERT INTO trustride.platform_configuration (config_key, config_value, environment, effective_from, changed_by)
SELECT v.k, v.v, 'ALL', now(), '00000000-0000-0000-0000-000000000000'
FROM (VALUES
  ('WORKING_WINDOW_WEEKDAY', '05:00-22:00'),
  ('WORKING_WINDOW_SATURDAY', '06:00-23:00'),
  ('WORKING_WINDOW_SUNDAY', 'OFF_DUTY'),
  ('ACTOR_REQUEST_SLA_TARGET_WORKING_DAYS', '2'),
  ('ACTOR_REQUEST_SLA_DEADLINE_WORKING_DAYS', '3')
) AS v(k, v)
WHERE NOT EXISTS (SELECT 1 FROM trustride.platform_configuration c WHERE c.config_key = v.k);

CREATE OR REPLACE FUNCTION trustride.fn_business_config(p_key TEXT)
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
  SELECT config_value FROM trustride.platform_configuration
  WHERE config_key = p_key AND effective_from <= now() AND (effective_to IS NULL OR effective_to > now())
  ORDER BY effective_from DESC LIMIT 1;
$$;

-- The working window for one local date, or NULLs if it is not a working day.
CREATE OR REPLACE FUNCTION trustride.fn_business_working_window(p_local_date DATE, OUT window_open TIMESTAMPTZ, OUT window_close TIMESTAMPTZ)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
DECLARE
  v_spec TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM trustride.calendar_reference WHERE calendar_date = p_local_date AND day_type = 'PUBLIC_HOLIDAY') THEN
    RETURN;
  END IF;
  v_spec := CASE extract(isodow FROM p_local_date)
    WHEN 7 THEN trustride.fn_business_config('WORKING_WINDOW_SUNDAY')
    WHEN 6 THEN trustride.fn_business_config('WORKING_WINDOW_SATURDAY')
    ELSE trustride.fn_business_config('WORKING_WINDOW_WEEKDAY')
  END;
  IF v_spec IS NULL OR v_spec !~ '^\d{2}:\d{2}-\d{2}:\d{2}$' THEN
    RETURN;  -- OFF_DUTY (or unset): not a working day
  END IF;
  window_open  := (p_local_date + split_part(v_spec, '-', 1)::time) AT TIME ZONE 'Africa/Nairobi';
  window_close := (p_local_date + split_part(v_spec, '-', 2)::time) AT TIME ZONE 'Africa/Nairobi';
END;
$$;

-- The moment work can next happen: p_at itself if inside a working window,
-- otherwise the opening of the next shift. Anything arriving after hours is
-- taken up by the first shift.
CREATE OR REPLACE FUNCTION trustride.fn_business_next_working_open(p_at TIMESTAMPTZ)
RETURNS TIMESTAMPTZ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
DECLARE
  v_date DATE := (p_at AT TIME ZONE 'Africa/Nairobi')::date;
  v_open TIMESTAMPTZ;
  v_close TIMESTAMPTZ;
BEGIN
  FOR i IN 0..30 LOOP
    SELECT window_open, window_close INTO v_open, v_close FROM trustride.fn_business_working_window(v_date + i);
    IF v_open IS NOT NULL THEN
      IF p_at < v_open THEN RETURN v_open; END IF;
      IF p_at <= v_close THEN RETURN p_at; END IF;
    END IF;
  END LOOP;
  RAISE EXCEPTION 'fn_business_next_working_open: no working window within 30 days of %', p_at;
END;
$$;

-- Adds N working days: the clock starts at the next shift opening, then
-- lands at the same time of day N working days later, held inside that
-- day's working window.
CREATE OR REPLACE FUNCTION trustride.fn_business_working_deadline(p_from TIMESTAMPTZ, p_working_days INTEGER)
RETURNS TIMESTAMPTZ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
DECLARE
  v_start TIMESTAMPTZ := trustride.fn_business_next_working_open(p_from);
  v_time TIME := (v_start AT TIME ZONE 'Africa/Nairobi')::time;
  v_date DATE := (v_start AT TIME ZONE 'Africa/Nairobi')::date;
  v_counted INTEGER := 0;
  v_open TIMESTAMPTZ;
  v_close TIMESTAMPTZ;
  v_at TIMESTAMPTZ;
BEGIN
  WHILE v_counted < p_working_days LOOP
    v_date := v_date + 1;
    SELECT window_open, window_close INTO v_open, v_close FROM trustride.fn_business_working_window(v_date);
    IF v_open IS NOT NULL THEN
      v_counted := v_counted + 1;
    END IF;
  END LOOP;
  v_at := (v_date + v_time) AT TIME ZONE 'Africa/Nairobi';
  RETURN greatest(v_open, least(v_close, v_at));
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_working_deadline(TIMESTAMPTZ, INTEGER) IS
  '[Trace: Sec.4.5; Founder operating calendar] N working days from the next shift opening. Working days: Mon-Fri 05:00-22:00, Sat 06:00-23:00; Sunday off duty; public holidays excluded.';

ALTER TABLE trustride.business_partnership_response
  ADD COLUMN IF NOT EXISTS decision_target_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS escalated_at TIMESTAMPTZ;

-- Every request's clock is stamped here, whatever inserted it, and an actor
-- cannot stack a second open request of the same kind (a reservation is the
-- exception -- a buyer may reserve more than one vehicle).
CREATE OR REPLACE FUNCTION trustride.fn_business_partnership_response_stamp()
RETURNS trigger LANGUAGE plpgsql SET search_path = trustride, pg_temp AS $$
DECLARE
  v_new_order RECORD;
BEGIN
  NEW.decision_target_at := trustride.fn_business_working_deadline(now(),
    coalesce(trustride.fn_business_config('ACTOR_REQUEST_SLA_TARGET_WORKING_DAYS')::int, 2));
  NEW.response_due_at := trustride.fn_business_working_deadline(now(),
    coalesce(trustride.fn_business_config('ACTOR_REQUEST_SLA_DEADLINE_WORKING_DAYS')::int, 3));

  SELECT requester_user_id, order_root_type INTO v_new_order FROM trustride.business_order WHERE order_id = NEW.order_id;
  IF v_new_order.order_root_type <> 'MARKETPLACE_PURCHASE_ORDER' AND EXISTS (
      SELECT 1 FROM trustride.business_partnership_response r
      JOIN trustride.business_order o ON o.order_id = r.order_id
      WHERE o.requester_user_id = v_new_order.requester_user_id
        AND o.order_root_type = v_new_order.order_root_type
        AND r.response_status IN ('SUBMITTED', 'UNDER_REVIEW')) THEN
    RAISE EXCEPTION 'A request of this kind is already under review -- you will be notified of the decision';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_business_partnership_response_stamp ON trustride.business_partnership_response;
CREATE TRIGGER trg_business_partnership_response_stamp
  BEFORE INSERT ON trustride.business_partnership_response
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_business_partnership_response_stamp();

-- A breached window escalates to TrustRide Office; it never declines the
-- actor on the Office's behalf (Sec.4.5 "Escalation occurs on breach").
CREATE OR REPLACE FUNCTION trustride.fn_business_partnership_response_timeout_sweep()
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_row RECORD;
  v_swept INTEGER := 0;
BEGIN
  FOR v_row IN
    UPDATE trustride.business_partnership_response r
    SET response_status = 'UNDER_REVIEW', escalated_at = now(),
        response_notes = concat_ws(' ', r.response_notes, '[Escalated: 72 working-hour window elapsed without a decision]')
    WHERE r.response_status IN ('SUBMITTED', 'UNDER_REVIEW') AND r.response_due_at < now() AND r.escalated_at IS NULL
    RETURNING r.order_id
  LOOP
    v_swept := v_swept + 1;
    INSERT INTO trustride.business_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    SELECT o.correlation_id, 'TRS026_ENG011_PRESENT', 'ACTOR_REQUEST_ESCALATED',
      jsonb_build_object('order_id', o.order_id, 'order_code', o.order_code, 'order_root_type', o.order_root_type,
                         'requester_user_id', o.requester_user_id),
      'ACTOR_REQUEST_ESCALATED:' || o.order_id::text
    FROM trustride.business_order o WHERE o.order_id = v_row.order_id;
  END LOOP;
  RETURN v_swept;
END;
$$;
COMMENT ON FUNCTION trustride.fn_business_partnership_response_timeout_sweep() IS
  '[Trace: Sec.4.5] Supersedes Correction 4''s auto-decline: a request unanswered within 72 working hours is escalated to TrustRide Office and the actor is told -- never rejected by a timer.';

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname = 'trustride_actor_request_sla_sweep';
  PERFORM cron.schedule('trustride_actor_request_sla_sweep', '*/15 * * * *', 'SELECT trustride.fn_business_partnership_response_timeout_sweep();');
END;
$$;

-- ============================================================================
-- PHASE 5 -- THE DECISION THAT ACTIVATES (closes wall 2)
-- ============================================================================
CREATE OR REPLACE FUNCTION trustride.fn_business_actor_request_decide(
  p_order_id UUID, p_decision trustride.business_partnership_response_status_enum, p_notes TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_order RECORD;
  v_scope JSONB;
  v_actor_id UUID;
  v_activate trustride.business_user_type_domain_enum;
BEGIN
  IF NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']) THEN
    RAISE EXCEPTION 'fn_business_actor_request_decide: only TrustRide Office authority may decide actor requests';
  END IF;

  SELECT * INTO v_order FROM trustride.business_order WHERE order_id = p_order_id;
  IF v_order IS NULL OR v_order.order_root_type = 'SERVICE_ORDER' THEN
    RAISE EXCEPTION 'fn_business_actor_request_decide: % is not an actor request', p_order_id;
  END IF;
  -- Separation of duties: nobody approves their own request -- the Founder,
  -- who holds genesis authority over the whole platform, excepted.
  IF v_order.requester_user_id = v_caller AND NOT trustride.fn_am_i_role(ARRAY['FOUNDER']) THEN
    RAISE EXCEPTION 'fn_business_actor_request_decide: you cannot decide your own request';
  END IF;

  PERFORM trustride.fn_business_partnership_response_decide(p_order_id, p_decision, v_caller, p_notes);

  IF p_decision = 'ACCEPTED' THEN
    SELECT coalesce(scope_detail, '{}'::jsonb) INTO v_scope FROM trustride.business_order_line
    WHERE order_id = p_order_id ORDER BY line_sequence LIMIT 1;
    v_scope := coalesce(v_scope, '{}'::jsonb);

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

    IF v_order.order_root_type = 'RESOURCE_PARTNERSHIP_REQUEST' THEN
      INSERT INTO trustride.business_partner_agreement (actor_registration_id, partner_category, agreement_type, agreement_terms, start_date)
      VALUES (v_actor_id,
        coalesce(nullif(v_scope->>'partner_category', ''), 'STRATEGIC_COLLABORATOR')::trustride.business_partner_category_enum,
        'RESOURCE_PARTNERSHIP', jsonb_build_object('request', v_order.order_code, 'scope', v_scope), current_date);
    ELSIF v_order.order_root_type = 'VENDOR_LISTING_REQUEST' THEN
      INSERT INTO trustride.business_partner_agreement (actor_registration_id, partner_category, agreement_type, agreement_terms, start_date)
      VALUES (v_actor_id, 'VENDOR', 'MARKETPLACE_VENDOR_LISTING',
        jsonb_build_object('request', v_order.order_code,
          'commission_pct', (SELECT config_value::numeric FROM trustride.platform_configuration
                             WHERE config_key = 'MARKETPLACE_VENDOR_COMMISSION_PCT' ORDER BY effective_from DESC LIMIT 1),
          'commission_basis', 'EVERY_COMPLETED_SALE',
          'vehicle_category', v_scope->>'vehicle_category', 'scope', v_scope),
        current_date);
    ELSIF v_order.order_root_type = 'OFFICE_ACCESS_REQUEST' AND v_scope->>'office_surface' IN ('ADMIN_CONSOLE', 'EXECUTIVE_DASHBOARD') THEN
      PERFORM trustride.fn_role_assign(v_order.requester_user_id,
        CASE v_scope->>'office_surface' WHEN 'ADMIN_CONSOLE' THEN 'ADMINISTRATOR' ELSE 'EXECUTIVE' END);
    END IF;
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
COMMENT ON FUNCTION trustride.fn_business_actor_request_decide(UUID, trustride.business_partnership_response_status_enum, TEXT) IS
  '[Trace: Sec.6 "Business Engine + Admin_Console"] The Office decision on any actor request. ACCEPTED activates exactly what was requested -- environment, partner/vendor agreement (with the configured commission), or Office role. DECLINED leaves the actor free to amend and re-submit.';

-- ============================================================================
-- PHASE 6 -- THE OFFICE CAN SEE THE QUEUE (closes wall 4)
-- ============================================================================
CREATE POLICY business_order_office_read ON trustride.business_order FOR SELECT TO trustride_authenticated
  USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));
CREATE POLICY business_order_line_office_read ON trustride.business_order_line FOR SELECT TO trustride_authenticated
  USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));
CREATE POLICY business_partnership_response_office_read ON trustride.business_partnership_response FOR SELECT TO trustride_authenticated
  USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));
CREATE POLICY business_actor_registration_office_read ON trustride.business_actor_registration FOR SELECT TO trustride_authenticated
  USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));
CREATE POLICY platform_users_office_read ON trustride.platform_users FOR SELECT TO trustride_authenticated
  USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));
CREATE POLICY business_partner_agreement_office_read ON trustride.business_partner_agreement FOR SELECT TO trustride_authenticated
  USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));

-- ============================================================================
-- PHASE 7 -- ROUTING: decisions and escalations reach Engine 11
-- ============================================================================
INSERT INTO trustride.routing_rule (event_type, source_engine, target_engine, route_priority)
SELECT v.event_type, 'TRS026_ENG004_BUS', 'TRS026_ENG011_PRESENT', 0
FROM (VALUES ('ACTOR_REQUEST_DECIDED'), ('ACTOR_REQUEST_ESCALATED')) AS v(event_type)
WHERE NOT EXISTS (SELECT 1 FROM trustride.routing_rule r
                  WHERE r.event_type = v.event_type AND r.source_engine = 'TRS026_ENG004_BUS' AND r.target_engine = 'TRS026_ENG011_PRESENT');
SELECT trustride.fn_orch_destination_cache_sync();

-- ============================================================================
-- PHASE 8 -- GRANTS
-- ============================================================================
GRANT EXECUTE ON FUNCTION trustride.fn_am_i_role(TEXT[]) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_business_actor_request_decide(UUID, trustride.business_partnership_response_status_enum, TEXT) TO trustride_authenticated;
REVOKE EXECUTE ON FUNCTION trustride.fn_am_i_role(TEXT[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_business_actor_register(UUID, trustride.business_user_type_domain_enum, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_business_working_deadline(TIMESTAMPTZ, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_business_next_working_open(TIMESTAMPTZ) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_business_working_window(DATE) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_business_config(TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_business_partnership_response_stamp() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_business_partnership_response_timeout_sweep() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_business_actor_request_decide(UUID, trustride.business_partnership_response_status_enum, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trustride.fn_verification_completed_accept(UUID, TEXT, TEXT, TEXT, JSONB) FROM PUBLIC;
