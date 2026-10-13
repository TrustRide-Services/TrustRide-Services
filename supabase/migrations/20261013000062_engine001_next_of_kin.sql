-- ============================================================================
-- Founder direction (WP9 item 2): next of kin, on the Foundation model.
--
-- Traceability:
--   Founder ruling 2026-08-23 (Registration & Authentication Flow, Step 3.3,
--   recorded in 20260823000002_engine001_foundation.sql) -- next of kin is part of
--   the person's registration data;
--   FDN-001 record 034 "Relationships & Networks" -- governed relationships between
--   Users, table user_relationship (user_id, related_user_id -> platform_users,
--   relationship_type, valid_from, valid_to); TBOC Art.11, 13.
-- The table, its foreign keys and its self/related-only read policy existed;
-- nothing used them (0 rows, no function, no screen). Step 3.3 had instead been
-- written into a free-text note (closed in 056). Implemented now on the
-- Foundation model:
--   * next of kin = a NEXT_OF_KIN user_relationship to a verified (ACTIVE)
--     TrustRide person identity, never oneself; one active at a time; a change
--     closes the previous one (valid_to), keeping history;
--   * the principal names the person by their verified phone AND full name; any
--     mismatch gets one message, so phone numbers cannot be probed;
--   * the named person is told and may decline; being named grants no access to
--     the principal's data, account or instructions (no session, no reads);
--   * operational use: when the principal is unreachable, TrustRide Office
--     (Founder or Administrator) may reveal the kin's name and verified phone,
--     only with a stated reason and for an open support case or an order in
--     progress of that principal;
--   * every nomination, replacement, removal, decline and reveal is audited with
--     identities and references only -- never contact details.
-- Gap reported to the Founder: FDN-001 034 represents only relationships between
-- registered identities. A next of kin who is not a TrustRide identity has no
-- place in the Foundation model; that needs a Founder ruling, not a workaround.
-- ============================================================================

ALTER TABLE trustride.user_relationship ADD CONSTRAINT user_relationship_not_self CHECK (user_id <> related_user_id);
CREATE UNIQUE INDEX user_relationship_one_active_next_of_kin ON trustride.user_relationship (user_id)
  WHERE relationship_type = 'NEXT_OF_KIN' AND valid_to IS NULL;

CREATE FUNCTION trustride.fn_next_of_kin_notify(p_user uuid, p_title text, p_body text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
  INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, category, external_channels)
  VALUES (p_user, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', p_title, p_body, 'GENERAL', ARRAY[]::text[]);
$function$;

CREATE FUNCTION trustride.fn_next_of_kin_nominate(p_phone text, p_full_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_phone TEXT := trustride.fn_contact_normalize('PHONE', p_phone);
  v_kin UUID;
  v_existing RECORD;
  v_rel UUID;
  v_name TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'fn_next_of_kin_nominate: no authenticated session'; END IF;
  IF NOT EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id = v_uid AND identity_primitive = 'PERSON' AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'Verify your identity before naming a next of kin';
  END IF;
  SELECT c.user_id INTO v_kin FROM trustride.user_contact c JOIN trustride.platform_users u ON u.user_id = c.user_id
  WHERE c.contact_type = 'PHONE' AND c.is_verified AND c.status = 'ACTIVE' AND c.contact_value = v_phone
    AND u.identity_primitive = 'PERSON' AND u.status = 'ACTIVE'
    AND lower(regexp_replace(trim(u.display_name), '\s+', ' ', 'g')) = lower(regexp_replace(trim(coalesce(p_full_name, '')), '\s+', ' ', 'g'))
  LIMIT 1;
  IF v_kin IS NULL THEN
    RAISE EXCEPTION 'No verified TrustRide identity matches that phone number and full name. Your next of kin must hold a verified TrustRide identity.';
  END IF;
  IF v_kin = v_uid THEN RAISE EXCEPTION 'You cannot name yourself as your next of kin'; END IF;

  SELECT * INTO v_existing FROM trustride.user_relationship
  WHERE user_id = v_uid AND relationship_type = 'NEXT_OF_KIN' AND valid_to IS NULL FOR UPDATE;
  IF v_existing.relationship_id IS NOT NULL AND v_existing.related_user_id = v_kin THEN
    RETURN v_existing.relationship_id;   -- the same person again: nothing changes
  END IF;
  IF v_existing.relationship_id IS NOT NULL THEN
    UPDATE trustride.user_relationship SET valid_to = CURRENT_DATE WHERE relationship_id = v_existing.relationship_id;
    PERFORM trustride.fn_audit_log_append('user_relationship', v_existing.relationship_id, 'NEXT_OF_KIN_ENDED', v_uid, 'USER', NULL, NULL, NULL,
      jsonb_build_object('principal', v_uid, 'next_of_kin', v_existing.related_user_id, 'reason', 'REPLACED'));
  END IF;
  INSERT INTO trustride.user_relationship (user_id, related_user_id, relationship_type) VALUES (v_uid, v_kin, 'NEXT_OF_KIN')
  RETURNING relationship_id INTO v_rel;
  PERFORM trustride.fn_audit_log_append('user_relationship', v_rel, 'NEXT_OF_KIN_NOMINATED', v_uid, 'USER', NULL, NULL, NULL,
    jsonb_build_object('principal', v_uid, 'next_of_kin', v_kin, 'replaced', v_existing.relationship_id));
  SELECT display_name INTO v_name FROM trustride.platform_users WHERE user_id = v_uid;
  PERFORM trustride.fn_next_of_kin_notify(v_kin, 'You were named as next of kin',
    v_name || ' has named you as their next of kin on TrustRide. TrustRide may contact you if they cannot be reached. This gives you no access to their account. If you do not agree, decline it in your profile.');
  RETURN v_rel;
END;
$function$;

CREATE FUNCTION trustride.fn_next_of_kin_end()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_rel RECORD;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'fn_next_of_kin_end: no authenticated session'; END IF;
  SELECT * INTO v_rel FROM trustride.user_relationship WHERE user_id = v_uid AND relationship_type = 'NEXT_OF_KIN' AND valid_to IS NULL FOR UPDATE;
  IF v_rel.relationship_id IS NULL THEN RETURN; END IF;
  UPDATE trustride.user_relationship SET valid_to = CURRENT_DATE WHERE relationship_id = v_rel.relationship_id;
  PERFORM trustride.fn_audit_log_append('user_relationship', v_rel.relationship_id, 'NEXT_OF_KIN_ENDED', v_uid, 'USER', NULL, NULL, NULL,
    jsonb_build_object('principal', v_uid, 'next_of_kin', v_rel.related_user_id, 'reason', 'REMOVED_BY_PRINCIPAL'));
END;
$function$;

CREATE FUNCTION trustride.fn_next_of_kin_decline(p_relationship_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_rel RECORD;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'fn_next_of_kin_decline: no authenticated session'; END IF;
  SELECT * INTO v_rel FROM trustride.user_relationship WHERE relationship_id = p_relationship_id AND relationship_type = 'NEXT_OF_KIN' FOR UPDATE;
  IF v_rel.relationship_id IS NULL OR v_rel.related_user_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'Only the person named as next of kin can decline it';
  END IF;
  IF v_rel.valid_to IS NOT NULL THEN RETURN; END IF;
  UPDATE trustride.user_relationship SET valid_to = CURRENT_DATE WHERE relationship_id = p_relationship_id;
  PERFORM trustride.fn_audit_log_append('user_relationship', p_relationship_id, 'NEXT_OF_KIN_DECLINED', v_uid, 'USER', NULL, NULL, NULL,
    jsonb_build_object('principal', v_rel.user_id, 'next_of_kin', v_uid));
  PERFORM trustride.fn_next_of_kin_notify(v_rel.user_id, 'Your next of kin declined',
    'The person you named as next of kin has declined. Please name someone else in your profile.');
END;
$function$;

CREATE FUNCTION trustride.fn_my_next_of_kin()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'nominated', (SELECT jsonb_build_object('relationship_id', r.relationship_id, 'display_name', u.display_name, 'since', r.valid_from)
                  FROM trustride.user_relationship r JOIN trustride.platform_users u ON u.user_id = r.related_user_id
                  WHERE r.user_id = auth.uid() AND r.relationship_type = 'NEXT_OF_KIN' AND r.valid_to IS NULL LIMIT 1),
    'named_by', coalesce((SELECT jsonb_agg(jsonb_build_object('relationship_id', r.relationship_id, 'display_name', u.display_name, 'since', r.valid_from)
                            ORDER BY r.valid_from)
                          FROM trustride.user_relationship r JOIN trustride.platform_users u ON u.user_id = r.user_id
                          WHERE r.related_user_id = auth.uid() AND r.relationship_type = 'NEXT_OF_KIN' AND r.valid_to IS NULL), '[]'::jsonb))
  WHERE auth.uid() IS NOT NULL;
$function$;

-- Office follow-up when the principal cannot be reached: an open support case about them, or one of their orders in progress.
CREATE FUNCTION trustride.fn_office_next_of_kin_reveal(p_user_id uuid, p_reason text, p_reference text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_by UUID := auth.uid();
  v_ref UUID;
  v_kin RECORD;
BEGIN
  IF v_by IS NULL OR NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN
    RAISE EXCEPTION 'Only TrustRide Office (Founder or Administrator) may reveal next-of-kin details';
  END IF;
  IF length(trim(coalesce(p_reason, ''))) < 10 THEN RAISE EXCEPTION 'State why the person cannot be reached'; END IF;
  BEGIN v_ref := p_reference::uuid; EXCEPTION WHEN OTHERS THEN v_ref := NULL; END;
  IF v_ref IS NULL OR NOT (
       EXISTS (SELECT 1 FROM trustride.business_support_case sc WHERE sc.case_id = v_ref AND sc.status NOT IN ('RESOLVED', 'CLOSED')
               AND (sc.opened_by_user_id = p_user_id OR sc.order_id IN (SELECT o.order_id FROM trustride.business_order o WHERE o.requester_user_id = p_user_id)))
       OR EXISTS (SELECT 1 FROM trustride.business_order o WHERE o.order_id = v_ref AND o.requester_user_id = p_user_id
                  AND o.status NOT IN ('SETTLED', 'REVIEWED', 'CLOSED', 'CANCELLED', 'EXPIRED', 'FAILED', 'DECLINED'))) THEN
    RAISE EXCEPTION 'Next-of-kin details are revealed only for an open support case or an order in progress of this person';
  END IF;
  SELECT u.display_name, c.contact_value AS phone INTO v_kin
  FROM trustride.user_relationship r JOIN trustride.platform_users u ON u.user_id = r.related_user_id AND u.status = 'ACTIVE'
  LEFT JOIN LATERAL (SELECT contact_value FROM trustride.user_contact WHERE user_id = r.related_user_id AND contact_type = 'PHONE'
                     AND is_verified AND status = 'ACTIVE' ORDER BY is_primary DESC LIMIT 1) c ON true
  WHERE r.user_id = p_user_id AND r.relationship_type = 'NEXT_OF_KIN' AND r.valid_to IS NULL LIMIT 1;
  PERFORM trustride.fn_audit_log_append('platform_users', p_user_id, 'NEXT_OF_KIN_CONTACT_REVEALED', v_by, 'USER', NULL, 'TRUSTRIDE_OFFICE', NULL,
    jsonb_build_object('reason', trim(p_reason), 'reference', v_ref, 'next_of_kin_found', v_kin.display_name IS NOT NULL));
  IF v_kin.display_name IS NULL THEN RETURN jsonb_build_object('none', true); END IF;
  RETURN jsonb_build_object('none', false, 'display_name', v_kin.display_name, 'phone', v_kin.phone);
END;
$function$;

CREATE OR REPLACE FUNCTION trustride.fn_platform_authenticated_function_allowlist()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT ARRAY[
    -- Engine 11 gateway, Sovereign Gate and session (each checks the caller's own identity)
    'fn_present_command_execute', 'fn_present_projection', 'fn_present_shell_session_open', 'fn_present_shell_session_end',
    'fn_present_heartbeat_sync', 'fn_present_notifications_mark_read', 'fn_present_office_access_request',
    'fn_present_gate_context', 'fn_present_gate_context_v2', 'fn_present_system_access_record', 'fn_present_system_access_bind',
    -- Foundation self-service (own identity or a represented organisation)
    'fn_user_register', 'fn_registration_capture_primary', 'fn_registration_retry_primary', 'fn_registration_capture_entity',
    'fn_registration_declare_kra_pin', 'fn_registration_capture_object', 'fn_registration_capture_external_system',
    'fn_secondary_profile_submit', 'fn_my_secondary_profile', 'fn_my_registration_status', 'fn_my_registration_retry_options',
    'fn_next_of_kin_nominate', 'fn_next_of_kin_end', 'fn_next_of_kin_decline', 'fn_my_next_of_kin',
    'fn_founder_exists', 'fn_founder_bootstrap',
    'fn_user_contact_add', 'fn_user_contact_add_for', 'fn_user_contact_remove', 'fn_user_contact_send_code',
    'fn_user_contact_set_primary', 'fn_user_contact_verify', 'fn_user_contact_preference_set', 'fn_user_contact_preference_set_for',
    'fn_entity_member_add', 'fn_business_actor_register', 'fn_resource_operator_duty_set',
    -- Role-checked Office actions
    'fn_role_assign', 'fn_business_actor_request_decide', 'fn_integration_adapter_set', 'fn_external_system_credential_issue',
    'fn_external_system_credential_revoke', 'fn_advisory_recommendation_decide', 'fn_office_next_of_kin_reveal',
    -- Policy helpers used by row-level security
    'fn_am_i_administrator', 'fn_am_i_governor', 'fn_am_i_role', 'fn_am_i_member_of_entity', 'fn_am_i_member_of_entity_user',
    'fn_am_i_representative_of', 'fn_contact_may_manage'
  ]::TEXT[];
$function$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_next_of_kin_nominate(text, text) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_next_of_kin_end() TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_next_of_kin_decline(uuid) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_my_next_of_kin() TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_office_next_of_kin_reveal(uuid, text, text) TO trustride_authenticated;
SELECT trustride.fn_platform_conformance_assert();
