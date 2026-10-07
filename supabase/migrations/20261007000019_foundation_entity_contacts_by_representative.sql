-- ============================================================================
-- Foundation: a representative manages the contacts of the organisation
-- they represent (D3, G3)
-- ============================================================================
--   Every identity has one authoritative verified phone -- the M-Pesa payer
--   and SMS address -- including a company or county authority. Contacts
--   could only be managed for the caller's own identity, so an organisation
--   acting through its representative could never hold a verified phone and
--   therefore could never book or pay (found in the browser journeys). A
--   verified representative (fn_am_i_representative_of) may now add, verify,
--   choose and remove the organisation's contacts and set its preferences.
--   The code still goes to the organisation's own number; the audit trail
--   records the person who acted.
-- ============================================================================

CREATE OR REPLACE FUNCTION trustride.fn_contact_may_manage(p_owner UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT auth.uid() IS NOT NULL AND (p_owner = auth.uid() OR trustride.fn_am_i_representative_of(p_owner));
$$;

-- Add a contact to an identity the caller may manage, and send its code.
CREATE OR REPLACE FUNCTION trustride.fn_user_contact_add_for(p_owner UUID, p_contact_type TEXT, p_contact_value TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
DECLARE
  v_value TEXT;
  v_contact_id UUID;
  v_auth_email TEXT;
BEGIN
  IF p_owner IS NULL OR NOT EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id = p_owner) THEN
    RAISE EXCEPTION 'fn_user_contact_add: register your identity first';
  END IF;
  IF NOT trustride.fn_contact_may_manage(p_owner) THEN
    RAISE EXCEPTION 'fn_user_contact_add: you can only manage contacts of your own identity or an organisation you represent';
  END IF;
  v_value := trustride.fn_contact_normalize(p_contact_type, p_contact_value);
  IF EXISTS (SELECT 1 FROM trustride.user_contact WHERE contact_type = p_contact_type AND contact_value = v_value
             AND is_verified AND status = 'ACTIVE' AND user_id <> p_owner) THEN
    RAISE EXCEPTION 'This % is already verified on another TrustRide identity', lower(p_contact_type);
  END IF;

  SELECT contact_id INTO v_contact_id FROM trustride.user_contact
  WHERE user_id = p_owner AND contact_type = p_contact_type AND contact_value = v_value AND status = 'ACTIVE';
  IF v_contact_id IS NULL THEN
    INSERT INTO trustride.user_contact (user_id, contact_type, contact_value, is_primary, is_verified, status)
    VALUES (p_owner, p_contact_type, v_value,
      NOT EXISTS (SELECT 1 FROM trustride.user_contact WHERE user_id = p_owner AND contact_type = p_contact_type AND is_primary AND status = 'ACTIVE'),
      FALSE, 'ACTIVE')
    RETURNING contact_id INTO v_contact_id;
  END IF;

  -- Only the person's own sign-in email is already proven by Supabase Auth.
  SELECT lower(email) INTO v_auth_email FROM auth.users WHERE id = p_owner AND email_confirmed_at IS NOT NULL;
  IF p_contact_type = 'EMAIL' AND p_owner = auth.uid() AND v_value = v_auth_email THEN
    UPDATE trustride.user_contact SET is_verified = TRUE, verified_at = now() WHERE contact_id = v_contact_id;
  ELSIF NOT (SELECT is_verified FROM trustride.user_contact WHERE contact_id = v_contact_id) THEN
    PERFORM trustride.fn_user_contact_send_code(v_contact_id);
  END IF;

  PERFORM trustride.fn_audit_log_append('user_contact', v_contact_id, 'CONTACT_ADDED', auth.uid(), 'USER', NULL, NULL, NULL,
    jsonb_build_object('contact_type', p_contact_type, 'owner', p_owner));
  RETURN v_contact_id;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_user_contact_add(p_contact_type TEXT, p_contact_value TEXT)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT trustride.fn_user_contact_add_for(auth.uid(), p_contact_type, p_contact_value);
$$;

CREATE OR REPLACE FUNCTION trustride.fn_user_contact_send_code(p_contact_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
DECLARE
  v_contact RECORD;
  v_code TEXT;
  v_id UUID;
  v_recent INT;
BEGIN
  SELECT * INTO v_contact FROM trustride.user_contact WHERE contact_id = p_contact_id AND status = 'ACTIVE';
  IF v_contact.contact_id IS NULL OR (auth.uid() IS NOT NULL AND NOT trustride.fn_contact_may_manage(v_contact.user_id)) THEN
    RAISE EXCEPTION 'fn_user_contact_send_code: no such contact on your identity';
  END IF;
  IF v_contact.is_verified THEN
    RAISE EXCEPTION 'This contact is already verified';
  END IF;
  SELECT count(*) INTO v_recent FROM trustride.user_contact_verification
  WHERE contact_id = p_contact_id AND created_at > now() - interval '1 hour';
  IF v_recent >= 5 THEN
    RAISE EXCEPTION 'Too many codes requested for this contact -- try again in an hour';
  END IF;

  v_code := lpad(((('x' || encode(gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
  INSERT INTO trustride.user_contact_verification (contact_id, code_hash, expires_at)
  VALUES (p_contact_id, encode(digest(p_contact_id::text || ':' || v_code, 'sha256'), 'hex'), now() + interval '10 minutes')
  RETURNING contact_verification_id INTO v_id;

  -- Foundation never reaches an SMS/WhatsApp/email provider itself
  -- (Article 33): Engine 6 delivers.
  INSERT INTO trustride.platform_event_outbox (correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v_id, 'TRS026_ENG001_FDN', 'TRS026_ENG006_INTG', 'CONTACT_VERIFICATION_REQUESTED',
    jsonb_build_object('contact_id', p_contact_id, 'recipient_user_id', v_contact.user_id,
      'channel', CASE v_contact.contact_type WHEN 'PHONE' THEN 'SMS' ELSE v_contact.contact_type END,
      'destination', v_contact.contact_value, 'template_code', 'CONTACT_VERIFICATION_CODE',
      'params', jsonb_build_object('code', v_code, 'expires_minutes', 10)),
    'CONTACT_VERIFICATION_REQUESTED:' || v_id::text);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_user_contact_verify(p_contact_id UUID, p_code TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
DECLARE
  v_contact RECORD;
  v_ver RECORD;
BEGIN
  SELECT * INTO v_contact FROM trustride.user_contact WHERE contact_id = p_contact_id AND status = 'ACTIVE';
  IF v_contact.contact_id IS NULL OR NOT trustride.fn_contact_may_manage(v_contact.user_id) THEN
    RAISE EXCEPTION 'fn_user_contact_verify: no such contact on your identity';
  END IF;
  IF v_contact.is_verified THEN
    RETURN TRUE;
  END IF;
  SELECT * INTO v_ver FROM trustride.user_contact_verification
  WHERE contact_id = p_contact_id AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1;
  IF v_ver.contact_verification_id IS NULL OR v_ver.expires_at < now() THEN
    RAISE EXCEPTION 'This code has expired -- request a new one';
  END IF;
  IF v_ver.attempts >= 5 THEN
    RAISE EXCEPTION 'Too many wrong attempts -- request a new code';
  END IF;
  IF encode(digest(p_contact_id::text || ':' || trim(coalesce(p_code, '')), 'sha256'), 'hex') <> v_ver.code_hash THEN
    UPDATE trustride.user_contact_verification SET attempts = attempts + 1 WHERE contact_verification_id = v_ver.contact_verification_id;
    RETURN FALSE;
  END IF;
  IF EXISTS (SELECT 1 FROM trustride.user_contact WHERE contact_type = v_contact.contact_type AND contact_value = v_contact.contact_value
             AND is_verified AND status = 'ACTIVE' AND user_id <> v_contact.user_id) THEN
    RAISE EXCEPTION 'This % was verified on another TrustRide identity in the meantime', lower(v_contact.contact_type);
  END IF;

  UPDATE trustride.user_contact_verification SET consumed_at = now() WHERE contact_verification_id = v_ver.contact_verification_id;
  UPDATE trustride.user_contact SET is_verified = TRUE, verified_at = now() WHERE contact_id = p_contact_id;
  PERFORM trustride.fn_audit_log_append('user_contact', p_contact_id, 'CONTACT_VERIFIED', auth.uid(), 'USER', NULL, NULL, NULL,
    jsonb_build_object('contact_type', v_contact.contact_type, 'owner', v_contact.user_id));
  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_user_contact_set_primary(p_contact_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_contact RECORD;
BEGIN
  SELECT * INTO v_contact FROM trustride.user_contact WHERE contact_id = p_contact_id AND status = 'ACTIVE';
  IF v_contact.contact_id IS NULL OR NOT v_contact.is_verified OR NOT trustride.fn_contact_may_manage(v_contact.user_id) THEN
    RAISE EXCEPTION 'Only a verified contact on your identity can be made primary';
  END IF;
  UPDATE trustride.user_contact SET is_primary = FALSE WHERE user_id = v_contact.user_id AND contact_type = v_contact.contact_type AND is_primary;
  UPDATE trustride.user_contact SET is_primary = TRUE WHERE contact_id = p_contact_id;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_user_contact_remove(p_contact_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_contact RECORD;
BEGIN
  SELECT * INTO v_contact FROM trustride.user_contact WHERE contact_id = p_contact_id AND status = 'ACTIVE';
  IF v_contact.contact_id IS NULL OR NOT trustride.fn_contact_may_manage(v_contact.user_id) THEN
    RAISE EXCEPTION 'No such contact on your identity';
  END IF;
  -- The last verified phone is the M-Pesa payer and SMS channel; it is
  -- replaced, never simply removed.
  IF v_contact.contact_type = 'PHONE' AND v_contact.is_verified AND NOT EXISTS (
       SELECT 1 FROM trustride.user_contact WHERE user_id = v_contact.user_id AND contact_type = 'PHONE'
         AND status = 'ACTIVE' AND is_verified AND contact_id <> p_contact_id) THEN
    RAISE EXCEPTION 'This is the only verified phone -- add and verify another number first';
  END IF;
  UPDATE trustride.user_contact SET status = 'REMOVED', is_primary = FALSE WHERE contact_id = p_contact_id;
  IF v_contact.is_primary THEN
    UPDATE trustride.user_contact SET is_primary = TRUE
    WHERE contact_id = (SELECT contact_id FROM trustride.user_contact
                        WHERE user_id = v_contact.user_id AND contact_type = v_contact.contact_type AND status = 'ACTIVE' AND is_verified
                        ORDER BY verified_at DESC LIMIT 1);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_user_contact_preference_set_for(p_owner UUID, p_channel TEXT, p_allowed BOOLEAN,
  p_allowed_from TIME DEFAULT NULL, p_allowed_to TIME DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  IF NOT trustride.fn_contact_may_manage(p_owner) THEN
    RAISE EXCEPTION 'You can only set preferences for your own identity or an organisation you represent';
  END IF;
  INSERT INTO trustride.user_contact_preference (user_id, channel, allowed, allowed_from, allowed_to)
  VALUES (p_owner, p_channel, p_allowed, p_allowed_from, p_allowed_to)
  ON CONFLICT (user_id, channel) DO UPDATE SET allowed = EXCLUDED.allowed, allowed_from = EXCLUDED.allowed_from, allowed_to = EXCLUDED.allowed_to;
END;
$$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_contact_may_manage(UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_user_contact_add_for(UUID, TEXT, TEXT) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_user_contact_add(TEXT, TEXT) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_user_contact_preference_set_for(UUID, TEXT, BOOLEAN, TIME, TIME) TO trustride_authenticated;

SELECT trustride.fn_platform_conformance_assert();
