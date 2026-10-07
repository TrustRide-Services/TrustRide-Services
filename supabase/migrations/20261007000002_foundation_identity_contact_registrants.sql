-- ============================================================================
-- Foundation (Engine 1): identity, contact methods and registrant classes
-- Implementation Completion -- Stage 1 (Identity + Registration), Stage 3
-- (Contact), G10/D3 (the one authoritative phone number), G17 (registrant
-- classes B-D, KRA PIN).
-- ============================================================================
-- What already existed and is reused, not duplicated:
--   * user_contact / user_contact_preference -- Foundation's own contact
--     tables (empty, never written). They become THE authoritative contact
--     register (Founder decision D3): a phone number lives here once, is
--     verified here once, and every other engine asks Foundation for it
--     through fn_user_contact_resolve / fn_user_payment_msisdn -- no engine
--     keeps its own copy.
--   * entity_profile / entity_registration / entity_membership -- legal
--     entities (registrant class LEGAL_ENTITY), with KRA PIN.
--   * object_registry / object_registration -- Objects (vehicles, devices,
--     equipment), each with its own identity row (identity_primitive OBJECT).
--   * verification_record + the VERIFICATION_REQUESTED / _COMPLETED signal
--     pair with Engine 6 -- extended to entity verification, never bypassed.
-- New, because nothing equivalent existed:
--   * user_contact_verification -- one-time codes (hashed) proving a contact.
--   * entity_system_credential -- hashed API credentials for EXTERNAL_SYSTEM
--     registrants (e.g. the Protrack telemetry feed).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Contact register hardening
-- ---------------------------------------------------------------------------
ALTER TABLE trustride.user_contact
  ADD CONSTRAINT user_contact_type_check CHECK (contact_type IN ('PHONE', 'EMAIL', 'WHATSAPP')),
  ADD CONSTRAINT user_contact_status_check CHECK (status IN ('ACTIVE', 'REMOVED'));
-- A verified contact belongs to exactly one identity (the M-Pesa payer, the
-- SMS recipient). One primary per type per identity.
CREATE UNIQUE INDEX user_contact_verified_owner_uq ON trustride.user_contact (contact_type, contact_value)
  WHERE is_verified AND status = 'ACTIVE';
CREATE UNIQUE INDEX user_contact_primary_uq ON trustride.user_contact (user_id, contact_type)
  WHERE is_primary AND status = 'ACTIVE';
CREATE UNIQUE INDEX user_contact_active_value_uq ON trustride.user_contact (user_id, contact_type, contact_value)
  WHERE status = 'ACTIVE';

CREATE UNIQUE INDEX user_contact_preference_channel_uq ON trustride.user_contact_preference (user_id, channel);

CREATE TABLE trustride.user_contact_verification (
  contact_verification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id     UUID NOT NULL REFERENCES trustride.user_contact (contact_id),
  code_hash      CHAR(64) NOT NULL,
  expires_at     TIMESTAMPTZ NOT NULL,
  attempts       SMALLINT NOT NULL DEFAULT 0,
  consumed_at    TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_user_contact_verification_contact ON trustride.user_contact_verification (contact_id, created_at DESC);
COMMENT ON TABLE trustride.user_contact_verification IS
  '[Trace: Implementation Completion D3] One-time codes proving control of a contact method. Only the SHA-256 of contact_id||code is stored; nobody reads this table but Foundation''s own functions.';
ALTER TABLE trustride.user_contact_verification ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_contact_verification_service_write ON trustride.user_contact_verification
  FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);

-- ---------------------------------------------------------------------------
-- 2. Verification types and registrant-class vocabulary
-- ---------------------------------------------------------------------------
ALTER TABLE trustride.verification_record DROP CONSTRAINT verification_record_verification_type_check;
ALTER TABLE trustride.verification_record ADD CONSTRAINT verification_record_verification_type_check
  CHECK (verification_type IN ('NATIONAL_ID', 'GOOD_CONDUCT', 'GUARANTOR', 'MEDICAL', 'NTSA_LICENCE', 'NTSA_VEHICLE',
                               'ENTITY_REGISTRATION'));

ALTER TABLE trustride.entity_profile ADD CONSTRAINT entity_profile_entity_type_check
  CHECK (entity_type IN ('COMPANY', 'PARTNERSHIP', 'SOLE_PROPRIETORSHIP', 'COOPERATIVE', 'NGO', 'GOVERNMENT_BODY', 'EXTERNAL_SYSTEM'));
ALTER TABLE trustride.entity_membership ADD CONSTRAINT entity_membership_role_check
  CHECK (membership_role IN ('AUTHORIZED_REPRESENTATIVE', 'DIRECTOR', 'STAFF', 'SYSTEM_OWNER'));

ALTER TABLE trustride.object_registry ADD CONSTRAINT object_registry_object_type_check
  CHECK (object_type IN ('MOTORCYCLE', 'CAR', 'TUKTUK', 'PICKUP', 'VAN', 'TRUCK', 'TRACKING_DEVICE', 'PHONE', 'LAPTOP', 'EQUIPMENT', 'OTHER'));

-- Who opened a session on behalf of an entity (a representative acting for
-- a company, a county authority, a fleet partner).
ALTER TABLE trustride.present_shell_session ADD COLUMN acting_person_user_id UUID REFERENCES trustride.platform_users (user_id);

-- ---------------------------------------------------------------------------
-- 3. External-system credentials (registrant class EXTERNAL_SYSTEM)
-- ---------------------------------------------------------------------------
CREATE TABLE trustride.entity_system_credential (
  credential_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  system_user_id   UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  key_prefix       TEXT NOT NULL UNIQUE,
  key_hash         CHAR(64) NOT NULL,
  scopes           TEXT[] NOT NULL,
  status           TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'REVOKED')),
  issued_by        UUID NOT NULL REFERENCES trustride.platform_users (user_id),
  issued_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at       TIMESTAMPTZ,
  last_used_at     TIMESTAMPTZ,
  revoked_at       TIMESTAMPTZ,
  CONSTRAINT entity_system_credential_scopes_check CHECK (scopes <@ ARRAY['TELEMETRY_INGEST', 'PAYMENT_CALLBACK', 'STATUS_READ']::TEXT[])
);
COMMENT ON TABLE trustride.entity_system_credential IS
  '[Trace: Engine 11 v3.0.0 registrant class EXTERNAL_SYSTEM] API credentials issued by TrustRide Office to an external system (an Actor, not a person). The key is shown once at issue; only its SHA-256 is kept.';
ALTER TABLE trustride.entity_system_credential ENABLE ROW LEVEL SECURITY;
CREATE POLICY entity_system_credential_service_write ON trustride.entity_system_credential
  FOR ALL TO trs026_eng001_fdn_service USING (true) WITH CHECK (true);
CREATE POLICY entity_system_credential_office_read ON trustride.entity_system_credential
  FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));

-- Representatives read the entity they act for; Office reads all identities.
-- (Membership is resolved through a SECURITY DEFINER helper: entity_profile
-- and entity_membership policies reference each other, and a policy that
-- queried the other table directly would recurse.)
CREATE OR REPLACE FUNCTION trustride.fn_am_i_member_of_entity(p_entity_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT EXISTS (SELECT 1 FROM trustride.entity_membership m
                 WHERE m.entity_id = p_entity_id AND m.person_user_id = auth.uid() AND (m.valid_to IS NULL OR m.valid_to >= current_date));
$$;
CREATE OR REPLACE FUNCTION trustride.fn_am_i_member_of_entity_user(p_entity_user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT EXISTS (SELECT 1 FROM trustride.entity_profile e JOIN trustride.entity_membership m ON m.entity_id = e.entity_id
                 WHERE e.user_id = p_entity_user_id AND m.person_user_id = auth.uid() AND (m.valid_to IS NULL OR m.valid_to >= current_date));
$$;
CREATE POLICY platform_users_representative_read ON trustride.platform_users
  FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_member_of_entity_user(user_id));
CREATE POLICY entity_profile_representative_read ON trustride.entity_profile
  FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_member_of_entity(entity_id));
CREATE POLICY entity_profile_office_read ON trustride.entity_profile
  FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));
CREATE POLICY object_registry_office_read ON trustride.object_registry
  FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));
CREATE POLICY user_contact_office_read ON trustride.user_contact
  FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));
GRANT SELECT ON trustride.entity_system_credential TO trustride_authenticated;

-- ---------------------------------------------------------------------------
-- 4. Contact functions
-- ---------------------------------------------------------------------------
-- Normalise a contact value into its one canonical spelling. Kenyan mobile
-- numbers become E.164 (+2547XXXXXXXX / +2541XXXXXXXX).
CREATE OR REPLACE FUNCTION trustride.fn_contact_normalize(p_contact_type TEXT, p_value TEXT)
RETURNS TEXT LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  v TEXT := regexp_replace(coalesce(p_value, ''), '[\s\-\(\)\.]', '', 'g');
BEGIN
  IF p_contact_type IN ('PHONE', 'WHATSAPP') THEN
    IF v ~ '^0[17][0-9]{8}$' THEN v := '+254' || substr(v, 2);
    ELSIF v ~ '^254[17][0-9]{8}$' THEN v := '+' || v;
    ELSIF v ~ '^[17][0-9]{8}$' THEN v := '+254' || v;
    END IF;
    IF v !~ '^\+254[17][0-9]{8}$' THEN
      RAISE EXCEPTION 'Enter a Kenyan mobile number, e.g. 0712 345 678';
    END IF;
    RETURN v;
  ELSIF p_contact_type = 'EMAIL' THEN
    v := lower(trim(p_value));
    IF v !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
      RAISE EXCEPTION 'Enter a valid email address';
    END IF;
    RETURN v;
  END IF;
  RAISE EXCEPTION 'Unknown contact type %', p_contact_type;
END;
$$;

-- Issue a fresh one-time code for a contact and hand delivery to Engine 6.
CREATE OR REPLACE FUNCTION trustride.fn_user_contact_send_code(p_contact_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
DECLARE
  v_contact RECORD;
  v_code TEXT;
  v_id UUID;
  v_recent INT;
BEGIN
  SELECT * INTO v_contact FROM trustride.user_contact WHERE contact_id = p_contact_id AND status = 'ACTIVE';
  IF v_contact.contact_id IS NULL OR (auth.uid() IS NOT NULL AND v_contact.user_id <> auth.uid()) THEN
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

-- Add a contact method to the caller's own identity and send its code.
-- The sign-in email is already proven by Supabase Auth and is accepted as
-- verified without a second code.
CREATE OR REPLACE FUNCTION trustride.fn_user_contact_add(p_contact_type TEXT, p_contact_value TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
DECLARE
  v_user UUID := auth.uid();
  v_value TEXT;
  v_contact_id UUID;
  v_auth_email TEXT;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id = v_user) THEN
    RAISE EXCEPTION 'fn_user_contact_add: register your identity first';
  END IF;
  v_value := trustride.fn_contact_normalize(p_contact_type, p_contact_value);
  IF EXISTS (SELECT 1 FROM trustride.user_contact WHERE contact_type = p_contact_type AND contact_value = v_value
             AND is_verified AND status = 'ACTIVE' AND user_id <> v_user) THEN
    RAISE EXCEPTION 'This % is already verified on another TrustRide identity', lower(p_contact_type);
  END IF;

  SELECT contact_id INTO v_contact_id FROM trustride.user_contact
  WHERE user_id = v_user AND contact_type = p_contact_type AND contact_value = v_value AND status = 'ACTIVE';
  IF v_contact_id IS NULL THEN
    INSERT INTO trustride.user_contact (user_id, contact_type, contact_value, is_primary, is_verified, status)
    VALUES (v_user, p_contact_type, v_value,
      NOT EXISTS (SELECT 1 FROM trustride.user_contact WHERE user_id = v_user AND contact_type = p_contact_type AND is_primary AND status = 'ACTIVE'),
      FALSE, 'ACTIVE')
    RETURNING contact_id INTO v_contact_id;
  END IF;

  SELECT lower(email) INTO v_auth_email FROM auth.users WHERE id = v_user AND email_confirmed_at IS NOT NULL;
  IF p_contact_type = 'EMAIL' AND v_value = v_auth_email THEN
    UPDATE trustride.user_contact SET is_verified = TRUE, verified_at = now() WHERE contact_id = v_contact_id;
  ELSIF NOT (SELECT is_verified FROM trustride.user_contact WHERE contact_id = v_contact_id) THEN
    PERFORM trustride.fn_user_contact_send_code(v_contact_id);
  END IF;

  PERFORM trustride.fn_audit_log_append('user_contact', v_contact_id, 'CONTACT_ADDED', v_user, 'USER', NULL, NULL, NULL,
    jsonb_build_object('contact_type', p_contact_type));
  RETURN v_contact_id;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_user_contact_verify(p_contact_id UUID, p_code TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
DECLARE
  v_user UUID := auth.uid();
  v_contact RECORD;
  v_ver RECORD;
BEGIN
  SELECT * INTO v_contact FROM trustride.user_contact WHERE contact_id = p_contact_id AND status = 'ACTIVE';
  IF v_contact.contact_id IS NULL OR v_contact.user_id <> v_user THEN
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
             AND is_verified AND status = 'ACTIVE' AND user_id <> v_user) THEN
    RAISE EXCEPTION 'This % was verified on another TrustRide identity in the meantime', lower(v_contact.contact_type);
  END IF;

  UPDATE trustride.user_contact_verification SET consumed_at = now() WHERE contact_verification_id = v_ver.contact_verification_id;
  UPDATE trustride.user_contact SET is_verified = TRUE, verified_at = now() WHERE contact_id = p_contact_id;
  PERFORM trustride.fn_audit_log_append('user_contact', p_contact_id, 'CONTACT_VERIFIED', v_user, 'USER', NULL, NULL, NULL,
    jsonb_build_object('contact_type', v_contact.contact_type));
  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_user_contact_set_primary(p_contact_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_contact RECORD;
BEGIN
  SELECT * INTO v_contact FROM trustride.user_contact WHERE contact_id = p_contact_id AND status = 'ACTIVE' AND user_id = auth.uid();
  IF v_contact.contact_id IS NULL OR NOT v_contact.is_verified THEN
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
  SELECT * INTO v_contact FROM trustride.user_contact WHERE contact_id = p_contact_id AND status = 'ACTIVE' AND user_id = auth.uid();
  IF v_contact.contact_id IS NULL THEN
    RAISE EXCEPTION 'No such contact on your identity';
  END IF;
  -- The last verified phone is the M-Pesa payer and SMS channel; it is
  -- replaced, never simply removed.
  IF v_contact.contact_type = 'PHONE' AND v_contact.is_verified AND NOT EXISTS (
       SELECT 1 FROM trustride.user_contact WHERE user_id = v_contact.user_id AND contact_type = 'PHONE'
         AND status = 'ACTIVE' AND is_verified AND contact_id <> p_contact_id) THEN
    RAISE EXCEPTION 'This is your only verified phone -- add and verify another number first';
  END IF;
  UPDATE trustride.user_contact SET status = 'REMOVED', is_primary = FALSE WHERE contact_id = p_contact_id;
  -- Promote the next verified contact of the same type, if any.
  IF v_contact.is_primary THEN
    UPDATE trustride.user_contact SET is_primary = TRUE
    WHERE contact_id = (SELECT contact_id FROM trustride.user_contact
                        WHERE user_id = v_contact.user_id AND contact_type = v_contact.contact_type AND status = 'ACTIVE' AND is_verified
                        ORDER BY verified_at DESC LIMIT 1);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_user_contact_preference_set(p_channel TEXT, p_allowed BOOLEAN, p_allowed_from TIME DEFAULT NULL, p_allowed_to TIME DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in first'; END IF;
  INSERT INTO trustride.user_contact_preference (user_id, channel, allowed, allowed_from, allowed_to)
  VALUES (auth.uid(), p_channel, p_allowed, p_allowed_from, p_allowed_to)
  ON CONFLICT (user_id, channel) DO UPDATE SET allowed = EXCLUDED.allowed, allowed_from = EXCLUDED.allowed_from, allowed_to = EXCLUDED.allowed_to;
END;
$$;

-- The lawful interface other engines use to reach a person: Foundation
-- resolves the channel to the verified primary contact and honours the
-- person's preference. Returns no row when the person cannot be reached on
-- that channel (the caller records that explicitly; it never guesses).
CREATE OR REPLACE FUNCTION trustride.fn_user_contact_resolve(p_user_id UUID, p_channel TEXT)
RETURNS TABLE (destination TEXT, contact_type TEXT, channel_allowed BOOLEAN, quiet_now BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  WITH pref AS (
    SELECT allowed, allowed_from, allowed_to FROM trustride.user_contact_preference WHERE user_id = p_user_id AND channel = p_channel
  ), c AS (
    SELECT uc.contact_value, uc.contact_type
    FROM trustride.user_contact uc
    WHERE uc.user_id = p_user_id AND uc.status = 'ACTIVE' AND uc.is_verified
      AND uc.contact_type = ANY (CASE p_channel
        WHEN 'SMS' THEN ARRAY['PHONE']
        WHEN 'WHATSAPP' THEN ARRAY['WHATSAPP', 'PHONE']
        WHEN 'EMAIL' THEN ARRAY['EMAIL']
        ELSE ARRAY[]::TEXT[] END)
    ORDER BY (uc.contact_type = 'WHATSAPP') DESC, uc.is_primary DESC, uc.verified_at DESC
    LIMIT 1
  )
  SELECT c.contact_value, c.contact_type,
    coalesce((SELECT allowed FROM pref), TRUE),
    coalesce((SELECT CASE
      WHEN allowed_from IS NULL OR allowed_to IS NULL THEN FALSE
      WHEN allowed_from <= allowed_to THEN NOT ((now() AT TIME ZONE 'Africa/Nairobi')::time BETWEEN allowed_from AND allowed_to)
      ELSE NOT ((now() AT TIME ZONE 'Africa/Nairobi')::time >= allowed_from OR (now() AT TIME ZONE 'Africa/Nairobi')::time <= allowed_to) END
      FROM pref), FALSE)
  FROM c;
$$;

-- The M-Pesa payer number (Daraja wants 2547XXXXXXXX, no plus): the
-- verified primary phone, nothing else.
CREATE OR REPLACE FUNCTION trustride.fn_user_payment_msisdn(p_user_id UUID)
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT ltrim(contact_value, '+') FROM trustride.user_contact
  WHERE user_id = p_user_id AND contact_type = 'PHONE' AND status = 'ACTIVE' AND is_verified
  ORDER BY is_primary DESC, verified_at DESC LIMIT 1;
$$;

-- ---------------------------------------------------------------------------
-- 5. Acting for an entity
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_am_i_representative_of(p_entity_user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT EXISTS (
    SELECT 1 FROM trustride.entity_profile e JOIN trustride.entity_membership m ON m.entity_id = e.entity_id
    JOIN trustride.platform_users pu ON pu.user_id = e.user_id
    WHERE e.user_id = p_entity_user_id AND m.person_user_id = auth.uid()
      AND m.membership_role IN ('AUTHORIZED_REPRESENTATIVE', 'DIRECTOR')
      AND (m.valid_to IS NULL OR m.valid_to >= current_date)
      AND pu.status = 'ACTIVE');
$$;

-- ---------------------------------------------------------------------------
-- 6. Registrant class LEGAL_ENTITY
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_registration_capture_entity(
  p_legal_name TEXT, p_entity_type TEXT, p_registration_number TEXT, p_kra_pin TEXT, p_county_code TEXT DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_entity_user UUID := gen_random_uuid();
  v_entity_id UUID;
  v_verification_id UUID;
  v_pin TEXT := upper(trim(coalesce(p_kra_pin, '')));
BEGIN
  IF v_caller IS NULL OR NOT EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id = v_caller AND status = 'ACTIVE' AND identity_primitive = 'PERSON') THEN
    RAISE EXCEPTION 'A verified person registers an entity and becomes its authorized representative -- verify your own identity first';
  END IF;
  IF coalesce(trim(p_legal_name), '') = '' OR coalesce(trim(p_registration_number), '') = '' THEN
    RAISE EXCEPTION 'Legal name and registration number are required';
  END IF;
  IF p_entity_type = 'EXTERNAL_SYSTEM' THEN
    RAISE EXCEPTION 'External systems are registered by TrustRide Office';
  END IF;
  -- KRA PIN (Article 14 statutory identifiers): required for every
  -- commercial entity; optional for NGOs and government bodies.
  IF v_pin = '' AND p_entity_type NOT IN ('NGO', 'GOVERNMENT_BODY') THEN
    RAISE EXCEPTION 'A KRA PIN is required for a %', lower(replace(p_entity_type, '_', ' '));
  END IF;
  IF v_pin <> '' AND v_pin !~ '^[AP][0-9]{9}[A-Z]$' THEN
    RAISE EXCEPTION 'A KRA PIN looks like P051234567X';
  END IF;
  IF p_county_code IS NOT NULL AND p_county_code !~ '^(0[1-9]|[1-3][0-9]|4[0-7])$' THEN
    RAISE EXCEPTION 'County code is the two-digit Kenyan county number (Kisumu is 42)';
  END IF;
  IF EXISTS (SELECT 1 FROM trustride.entity_profile WHERE registration_number = trim(p_registration_number) AND status <> 'REJECTED') THEN
    RAISE EXCEPTION 'An entity with registration number % is already registered -- ask its representative to add you', trim(p_registration_number);
  END IF;

  INSERT INTO trustride.platform_users (user_id, global_uid, identity_primitive, display_name, status)
  VALUES (v_entity_user, 'TRS026-E-' || upper(substr(v_entity_user::text, 1, 8)), 'ENTITY', trim(p_legal_name), 'PENDING_VERIFICATION');
  INSERT INTO trustride.entity_profile (user_id, legal_name, entity_type, registration_number, kra_pin, county_code, status)
  VALUES (v_entity_user, trim(p_legal_name), p_entity_type, trim(p_registration_number), nullif(v_pin, ''), p_county_code, 'PENDING_VERIFICATION')
  RETURNING entity_id INTO v_entity_id;
  INSERT INTO trustride.entity_registration (entity_id, registration_type, registration_value, issuing_authority, status)
  VALUES (v_entity_id, 'BUSINESS_REGISTRATION', trim(p_registration_number), 'Business Registration Service', 'PENDING');
  IF v_pin <> '' THEN
    INSERT INTO trustride.entity_registration (entity_id, registration_type, registration_value, issuing_authority, status)
    VALUES (v_entity_id, 'KRA_PIN', v_pin, 'Kenya Revenue Authority', 'PENDING');
  END IF;
  INSERT INTO trustride.entity_membership (entity_id, person_user_id, membership_role, valid_from, granted_by)
  VALUES (v_entity_id, v_caller, 'AUTHORIZED_REPRESENTATIVE', current_date, v_caller);

  INSERT INTO trustride.verification_record (subject_user_id, verification_type, outcome)
  VALUES (v_entity_user, 'ENTITY_REGISTRATION', 'PENDING') RETURNING verification_id INTO v_verification_id;

  INSERT INTO trustride.platform_event_outbox (correlation_id, emitting_engine, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (gen_random_uuid(), 'TRS026_ENG001_FDN', 'TRS026_ENG006_INTG', 'VERIFICATION_REQUESTED',
    jsonb_build_object('verification_id', v_verification_id, 'subject_user_id', v_entity_user, 'verification_type', 'ENTITY_REGISTRATION',
      'full_legal_name', trim(p_legal_name), 'registration_number', trim(p_registration_number), 'kra_pin', nullif(v_pin, ''),
      'entity_type', p_entity_type),
    'VERIFICATION_REQUESTED:' || v_verification_id::text);

  PERFORM trustride.fn_audit_log_append('platform_users', v_entity_user, 'ENTITY_REGISTERED', v_caller, 'USER', NULL, NULL, NULL,
    jsonb_build_object('entity_type', p_entity_type, 'verification_id', v_verification_id));
  RETURN v_entity_user;
END;
$$;

-- A representative adds another person (who must already hold a verified
-- identity) to the entity.
CREATE OR REPLACE FUNCTION trustride.fn_entity_member_add(p_entity_user_id UUID, p_person_user_id UUID, p_membership_role TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_entity_id UUID;
  v_id UUID;
BEGIN
  IF NOT trustride.fn_am_i_representative_of(p_entity_user_id) THEN
    RAISE EXCEPTION 'Only an authorized representative of this entity may add members';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id = p_person_user_id AND identity_primitive = 'PERSON' AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'The person must hold a verified TrustRide identity';
  END IF;
  SELECT entity_id INTO v_entity_id FROM trustride.entity_profile WHERE user_id = p_entity_user_id;
  INSERT INTO trustride.entity_membership (entity_id, person_user_id, membership_role, valid_from, granted_by)
  VALUES (v_entity_id, p_person_user_id, p_membership_role, current_date, auth.uid()) RETURNING membership_id INTO v_id;
  RETURN v_id;
END;
$$;

-- Verification outcome for an entity (called from fn_verification_completed_accept).
CREATE OR REPLACE FUNCTION trustride.fn_entity_verification_completed(p_verification_id UUID, p_returned_legal_name TEXT, p_returned_status TEXT, p_returned_kra_pin TEXT, p_raw_response JSONB)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_entity_user UUID;
  v_profile RECORD;
  v_ok BOOLEAN;
BEGIN
  SELECT subject_user_id INTO v_entity_user FROM trustride.verification_record
  WHERE verification_id = p_verification_id AND outcome = 'PENDING' AND verification_type = 'ENTITY_REGISTRATION';
  IF v_entity_user IS NULL THEN
    RAISE EXCEPTION 'fn_entity_verification_completed: no PENDING entity verification %', p_verification_id;
  END IF;
  SELECT * INTO v_profile FROM trustride.entity_profile WHERE user_id = v_entity_user;
  v_ok := p_returned_status = 'VALID'
    AND lower(trim(coalesce(p_returned_legal_name, ''))) = lower(trim(v_profile.legal_name))
    AND (v_profile.kra_pin IS NULL OR v_profile.kra_pin = upper(coalesce(p_returned_kra_pin, '')));

  IF v_ok THEN
    UPDATE trustride.verification_record SET outcome = 'VERIFIED', verified_at = now() WHERE verification_id = p_verification_id;
    UPDATE trustride.entity_profile SET status = 'ACTIVE', updated_at = now() WHERE user_id = v_entity_user;
    UPDATE trustride.entity_registration SET status = 'ACTIVE', verified_at = now(), verification_ref = p_verification_id
    WHERE entity_id = v_profile.entity_id;
    UPDATE trustride.platform_users SET status = 'ACTIVE', updated_at = now() WHERE user_id = v_entity_user;
  ELSE
    UPDATE trustride.verification_record SET outcome = 'FAILED' WHERE verification_id = p_verification_id;
    UPDATE trustride.entity_profile SET status = 'VERIFICATION_FAILED', updated_at = now() WHERE user_id = v_entity_user;
    UPDATE trustride.platform_users SET status = 'VERIFICATION_FAILED', updated_at = now() WHERE user_id = v_entity_user;
  END IF;
  PERFORM trustride.fn_audit_log_append('platform_users', v_entity_user, CASE WHEN v_ok THEN 'ENTITY_VERIFIED' ELSE 'ENTITY_VERIFICATION_FAILED' END,
    v_entity_user, 'SYSTEM', NULL, NULL, NULL, jsonb_build_object('verification_id', p_verification_id, 'raw_response', p_raw_response));
  RETURN CASE WHEN v_ok THEN 'VERIFIED' ELSE 'FAILED' END;
END;
$$;

-- fn_verification_completed_accept: unchanged for people; entity
-- verifications route to their own branch, and an authority-returned KRA PIN
-- supersedes a declared one (patched in place -- the function keeps its
-- signature, defaults and grants).
DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_verification_completed_accept(uuid,text,text,text,jsonb)'::regprocedure) INTO v_def;
  IF position('fn_entity_verification_completed' IN v_def) = 0 THEN
    v_def := regexp_replace(v_def, E'
BEGIN
',
      E'
BEGIN
  IF EXISTS (SELECT 1 FROM trustride.verification_record WHERE verification_id = p_verification_id AND verification_type = ''ENTITY_REGISTRATION'') THEN
    RETURN trustride.fn_entity_verification_completed(p_verification_id, p_returned_legal_name, p_returned_status, p_returned_kra_pin, p_raw_response);
  END IF;
');
    v_def := replace(v_def,
      'INSERT INTO trustride.user_identifier (user_id, identifier_type, identifier_value, status, verified_at)',
      E'UPDATE trustride.user_identifier SET status = ''SUPERSEDED'' WHERE user_id = v_subject_user_id AND identifier_type = ''KRA_PIN'' AND status = ''DECLARED'';
    INSERT INTO trustride.user_identifier (user_id, identifier_type, identifier_value, status, verified_at)');
    IF position('fn_entity_verification_completed' IN v_def) = 0 OR position('SUPERSEDED' IN v_def) = 0 THEN
      RAISE EXCEPTION 'fn_verification_completed_accept patch did not apply';
    END IF;
    EXECUTE v_def;
  END IF;
END;
$patch$;

-- A person may declare their KRA PIN up front; the identity authority's
-- returned PIN remains the verified one.
CREATE OR REPLACE FUNCTION trustride.fn_registration_declare_kra_pin(p_kra_pin TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_pin TEXT := upper(trim(coalesce(p_kra_pin, '')));
BEGIN
  IF auth.uid() IS NULL OR NOT EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Register your identity first';
  END IF;
  IF v_pin !~ '^[AP][0-9]{9}[A-Z]$' THEN
    RAISE EXCEPTION 'A KRA PIN looks like A001234567X';
  END IF;
  IF EXISTS (SELECT 1 FROM trustride.user_identifier WHERE user_id = auth.uid() AND identifier_type = 'KRA_PIN' AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'Your KRA PIN is already verified';
  END IF;
  DELETE FROM trustride.user_identifier WHERE user_id = auth.uid() AND identifier_type = 'KRA_PIN' AND status = 'DECLARED';
  INSERT INTO trustride.user_identifier (user_id, identifier_type, identifier_value, status)
  VALUES (auth.uid(), 'KRA_PIN', v_pin, 'DECLARED');
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. Registrant class EXTERNAL_SYSTEM (Office-registered)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_registration_capture_external_system(p_system_name TEXT, p_purpose TEXT, p_owner_entity_user_id UUID DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_system_user UUID := gen_random_uuid();
  v_entity_id UUID;
  v_owner_entity UUID;
BEGIN
  IF NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN
    RAISE EXCEPTION 'External systems are registered by TrustRide Office (Founder or Administrator)';
  END IF;
  IF coalesce(trim(p_system_name), '') = '' OR coalesce(trim(p_purpose), '') = '' THEN
    RAISE EXCEPTION 'Name the system and state what it does';
  END IF;
  INSERT INTO trustride.platform_users (user_id, global_uid, identity_primitive, display_name, status)
  VALUES (v_system_user, 'TRS026-S-' || upper(substr(v_system_user::text, 1, 8)), 'ENTITY', trim(p_system_name), 'ACTIVE');
  INSERT INTO trustride.entity_profile (user_id, legal_name, entity_type, status)
  VALUES (v_system_user, trim(p_system_name), 'EXTERNAL_SYSTEM', 'ACTIVE') RETURNING entity_id INTO v_entity_id;
  INSERT INTO trustride.entity_registration (entity_id, registration_type, registration_value, issuing_authority, verified_at, status)
  VALUES (v_entity_id, 'SYSTEM_PURPOSE', trim(p_purpose), 'TrustRide Office', now(), 'ACTIVE');
  IF p_owner_entity_user_id IS NOT NULL THEN
    SELECT entity_id INTO v_owner_entity FROM trustride.entity_profile WHERE user_id = p_owner_entity_user_id;
    INSERT INTO trustride.entity_registration (entity_id, registration_type, registration_value, issuing_authority, verified_at, status)
    VALUES (v_entity_id, 'OWNER_ENTITY', p_owner_entity_user_id::text, 'TrustRide Office', now(), 'ACTIVE');
  END IF;
  PERFORM trustride.fn_audit_log_append('platform_users', v_system_user, 'EXTERNAL_SYSTEM_REGISTERED', auth.uid(), 'USER', NULL, 'TRUSTRIDE_OFFICE', NULL,
    jsonb_build_object('purpose', p_purpose));
  RETURN v_system_user;
END;
$$;

-- Issue a credential; the plaintext key is returned exactly once.
CREATE OR REPLACE FUNCTION trustride.fn_external_system_credential_issue(p_system_user_id UUID, p_scopes TEXT[], p_valid_days INTEGER DEFAULT 365)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
DECLARE
  v_prefix TEXT := 'trs_' || encode(gen_random_bytes(6), 'hex');
  v_secret TEXT := encode(gen_random_bytes(32), 'hex');
BEGIN
  IF NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN
    RAISE EXCEPTION 'Only TrustRide Office may issue system credentials';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trustride.entity_profile WHERE user_id = p_system_user_id AND entity_type = 'EXTERNAL_SYSTEM' AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'Not an active external system';
  END IF;
  INSERT INTO trustride.entity_system_credential (system_user_id, key_prefix, key_hash, scopes, issued_by, expires_at)
  VALUES (p_system_user_id, v_prefix, encode(digest(v_prefix || '.' || v_secret, 'sha256'), 'hex'), p_scopes, auth.uid(),
    now() + make_interval(days => p_valid_days));
  PERFORM trustride.fn_audit_log_append('entity_system_credential', p_system_user_id, 'SYSTEM_CREDENTIAL_ISSUED', auth.uid(), 'USER', NULL, 'TRUSTRIDE_OFFICE', NULL,
    jsonb_build_object('key_prefix', v_prefix, 'scopes', p_scopes));
  RETURN v_prefix || '.' || v_secret;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_external_system_credential_revoke(p_key_prefix TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  IF NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN
    RAISE EXCEPTION 'Only TrustRide Office may revoke system credentials';
  END IF;
  UPDATE trustride.entity_system_credential SET status = 'REVOKED', revoked_at = now() WHERE key_prefix = p_key_prefix AND status = 'ACTIVE';
  IF NOT FOUND THEN RAISE EXCEPTION 'No active credential %', p_key_prefix; END IF;
END;
$$;

-- Authenticate a presented key for a required scope. Called only by the
-- integration gateway (service role); returns the system identity or NULL.
CREATE OR REPLACE FUNCTION trustride.fn_external_system_authenticate(p_key TEXT, p_required_scope TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
DECLARE
  v_cred RECORD;
BEGIN
  SELECT * INTO v_cred FROM trustride.entity_system_credential
  WHERE key_prefix = split_part(p_key, '.', 1) AND status = 'ACTIVE' AND (expires_at IS NULL OR expires_at > now());
  IF v_cred.credential_id IS NULL OR v_cred.key_hash <> encode(digest(p_key, 'sha256'), 'hex') OR NOT (p_required_scope = ANY (v_cred.scopes)) THEN
    RETURN NULL;
  END IF;
  UPDATE trustride.entity_system_credential SET last_used_at = now() WHERE credential_id = v_cred.credential_id;
  RETURN v_cred.system_user_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 8. Registrant class OBJECT (vehicles, tracking devices, equipment)
-- ---------------------------------------------------------------------------
-- Office registers any Object; an ACTIVE Partner registers an Object in
-- their own custody (a contributed motorcycle or car). Vehicles start
-- PENDING_VERIFICATION until NTSA confirms; other objects are ACTIVE.
CREATE OR REPLACE FUNCTION trustride.fn_registration_capture_object(
  p_object_type TEXT, p_make TEXT, p_model TEXT, p_year SMALLINT, p_plate_number TEXT, p_serial_number TEXT,
  p_custody_user_id UUID DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_office BOOLEAN := trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']);
  v_custodian UUID := coalesce(p_custody_user_id, v_caller);
  v_object_user UUID := gen_random_uuid();
  v_object_id UUID;
  v_is_vehicle BOOLEAN := p_object_type IN ('MOTORCYCLE', 'CAR', 'TUKTUK', 'PICKUP', 'VAN', 'TRUCK');
  v_plate TEXT := nullif(upper(regexp_replace(coalesce(p_plate_number, ''), '\s', '', 'g')), '');
BEGIN
  IF v_caller IS NOT NULL AND NOT v_office THEN
    IF v_custodian <> v_caller AND NOT trustride.fn_am_i_representative_of(v_custodian) THEN
      RAISE EXCEPTION 'You may register objects only into your own custody';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM trustride.business_actor_registration WHERE user_id = v_custodian AND user_type_domain = 'PARTNER' AND registration_status = 'ACTIVE') THEN
      RAISE EXCEPTION 'Objects are contributed by approved Partners or registered by TrustRide Office';
    END IF;
  END IF;
  IF v_is_vehicle AND v_plate IS NULL THEN
    RAISE EXCEPTION 'A vehicle needs its registration plate';
  END IF;
  IF p_object_type = 'TRACKING_DEVICE' AND coalesce(trim(p_serial_number), '') = '' THEN
    RAISE EXCEPTION 'A tracking device needs its device ID (IMEI or serial)';
  END IF;
  IF v_plate IS NOT NULL AND EXISTS (SELECT 1 FROM trustride.object_registry WHERE plate_number = v_plate AND status <> 'RETIRED') THEN
    RAISE EXCEPTION 'A vehicle with plate % is already registered', v_plate;
  END IF;
  IF p_object_type = 'TRACKING_DEVICE' AND EXISTS (SELECT 1 FROM trustride.object_registry WHERE object_type = 'TRACKING_DEVICE' AND serial_number = trim(p_serial_number) AND status <> 'RETIRED') THEN
    RAISE EXCEPTION 'Tracking device % is already registered', trim(p_serial_number);
  END IF;

  INSERT INTO trustride.platform_users (user_id, global_uid, identity_primitive, display_name, status)
  VALUES (v_object_user, 'TRS026-O-' || upper(substr(v_object_user::text, 1, 8)), 'OBJECT',
    trim(concat_ws(' ', p_make, p_model, v_plate, CASE WHEN v_plate IS NULL THEN p_serial_number END)),
    CASE WHEN v_is_vehicle THEN 'PENDING_VERIFICATION' ELSE 'ACTIVE' END);
  INSERT INTO trustride.object_registry (user_id, object_type, make, model, year, plate_number, serial_number, custody_user_id, status)
  VALUES (v_object_user, p_object_type, p_make, p_model, p_year, v_plate, nullif(trim(p_serial_number), ''), v_custodian,
    CASE WHEN v_is_vehicle THEN 'PENDING_VERIFICATION' ELSE 'ACTIVE' END)
  RETURNING object_id INTO v_object_id;
  IF v_plate IS NOT NULL THEN
    INSERT INTO trustride.object_registration (object_id, registration_type, registration_value, issuing_authority, status)
    VALUES (v_object_id, 'NTSA_REG', v_plate, 'NTSA', 'PENDING');
  END IF;

  PERFORM trustride.fn_audit_log_append('object_registry', v_object_id, 'OBJECT_REGISTERED', v_caller, 'USER', NULL, NULL, NULL,
    jsonb_build_object('object_type', p_object_type, 'plate', v_plate, 'custodian', v_custodian));
  RETURN v_object_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 9. Sessions and environments for represented entities
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_business_actor_register(p_user_id uuid, p_user_type_domain trustride.business_user_type_domain_enum, p_terms_summary text DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_actor_registration_id UUID;
  v_caller UUID := auth.uid();
  v_status TEXT := 'ACTIVE';
BEGIN
  -- A caller with no session is the platform itself (internal provisioning);
  -- a signed-in caller acts for their own identity or for an entity they
  -- represent (a company, a county authority, a fleet partner).
  IF v_caller IS NOT NULL THEN
    IF p_user_id <> v_caller AND NOT trustride.fn_am_i_representative_of(p_user_id) THEN
      RAISE EXCEPTION 'fn_business_actor_register: an environment can only be registered for your own identity or an entity you represent';
    END IF;
    IF p_user_type_domain = 'OPERATOR' THEN
      RAISE EXCEPTION 'fn_business_actor_register: Operator is a TrustRide Office environment -- request Office access instead';
    END IF;
    v_status := CASE WHEN p_user_type_domain = 'CUSTOMER' THEN 'ACTIVE' ELSE 'PENDING' END;
  END IF;

  INSERT INTO trustride.business_actor_registration (user_id, user_type_domain, terms_summary, registration_status)
  VALUES (p_user_id, p_user_type_domain, p_terms_summary, v_status)
  ON CONFLICT (user_id, user_type_domain) DO UPDATE
    SET terms_summary = coalesce(EXCLUDED.terms_summary, trustride.business_actor_registration.terms_summary)
  RETURNING actor_registration_id INTO v_actor_registration_id;

  PERFORM trustride.fn_audit_log_append('business_actor_registration', v_actor_registration_id, 'ACTOR_REGISTERED', coalesce(v_caller, p_user_id),
    'USER', NULL, NULL, NULL, jsonb_build_object('user_type_domain', p_user_type_domain, 'status', v_status, 'for_identity', p_user_id));
  RETURN v_actor_registration_id;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_shell_session_open(p_top_shell trustride.present_top_shell_enum, p_sub_shell trustride.present_sub_shell_enum, p_user_id uuid, p_channel_type trustride.present_channel_type_enum, p_access_id uuid DEFAULT NULL, p_device_id uuid DEFAULT NULL, p_auth_session_ref uuid DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_session_id UUID;
  v_required_domain trustride.business_user_type_domain_enum;
  v_acting UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM trustride.shell_registry WHERE shell_code = p_top_shell::text AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'fn_present_shell_session_open: % is not a registered ACTIVE main shell', p_top_shell;
  END IF;

  -- A session opens for the caller's own identity, or -- on Business and
  -- Marketplace surfaces only -- for an entity the caller represents.
  IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid() THEN
    IF p_top_shell = 'TRUSTRIDE_OFFICE' OR NOT trustride.fn_am_i_representative_of(p_user_id) THEN
      RAISE EXCEPTION 'fn_present_shell_session_open: a session can only be opened for the caller''s own identity or an entity they represent';
    END IF;
    v_acting := auth.uid();
  END IF;

  v_required_domain := (CASE p_sub_shell
    WHEN 'CUSTOMER_APP' THEN 'CUSTOMER'
    WHEN 'PARTNER_APP' THEN 'PARTNER'
    WHEN 'GOVERNOR_APP' THEN 'GOVERNOR'
    WHEN 'INTERMEDIARY_APP' THEN 'INTERMEDIARY'
    WHEN 'OPERATOR_APP' THEN 'OPERATOR'
  END)::trustride.business_user_type_domain_enum;

  IF p_top_shell = 'TRUSTRIDE_OFFICE' THEN
    IF NOT (
      trustride.fn_am_i_role(ARRAY['FOUNDER'])
      OR (p_sub_shell = 'ADMIN_CONSOLE' AND trustride.fn_am_i_role(ARRAY['ADMINISTRATOR']))
      OR (p_sub_shell = 'EXECUTIVE_DASHBOARD' AND trustride.fn_am_i_role(ARRAY['EXECUTIVE']))
      OR (p_sub_shell = 'OPERATOR_APP' AND (trustride.fn_am_i_role(ARRAY['DISPATCHER']) OR EXISTS (
            SELECT 1 FROM trustride.business_actor_registration
            WHERE user_id = p_user_id AND user_type_domain = 'OPERATOR' AND registration_status = 'ACTIVE')))
    ) THEN
      RAISE EXCEPTION 'fn_present_shell_session_open: % is TrustRide Office -- internal staff only; request Office access at the Sovereign Gate', p_sub_shell;
    END IF;
  ELSIF v_required_domain IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM trustride.business_actor_registration
      WHERE user_id = p_user_id AND user_type_domain = v_required_domain AND registration_status IN ('ACTIVE', 'PENDING')) THEN
    RAISE EXCEPTION 'fn_present_shell_session_open: % opens only for an identity registered as %', p_sub_shell, v_required_domain;
  END IF;

  INSERT INTO trustride.present_shell_session (top_shell, sub_shell, user_id, access_id, device_id, channel_type, auth_session_ref, acting_person_user_id)
  VALUES (p_top_shell, p_sub_shell, p_user_id, p_access_id, p_device_id, p_channel_type, p_auth_session_ref, v_acting)
  RETURNING session_id INTO v_session_id;
  RETURN v_session_id;
END;
$$;

-- Representatives see the sessions they opened for an entity.
CREATE POLICY present_shell_session_acting_read ON trustride.present_shell_session
  FOR SELECT TO trustride_authenticated USING (acting_person_user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 10. Grants
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;

GRANT EXECUTE ON FUNCTION trustride.fn_user_contact_add(TEXT, TEXT) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_user_contact_send_code(UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_user_contact_verify(UUID, TEXT) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_user_contact_set_primary(UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_user_contact_remove(UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_user_contact_preference_set(TEXT, BOOLEAN, TIME, TIME) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_am_i_representative_of(UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_am_i_member_of_entity(UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_am_i_member_of_entity_user(UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_registration_capture_entity(TEXT, TEXT, TEXT, TEXT, TEXT) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_entity_member_add(UUID, UUID, TEXT) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_registration_declare_kra_pin(TEXT) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_registration_capture_external_system(TEXT, TEXT, UUID) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_external_system_credential_issue(UUID, TEXT[], INTEGER) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_external_system_credential_revoke(TEXT) TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_registration_capture_object(TEXT, TEXT, TEXT, SMALLINT, TEXT, TEXT, UUID) TO trustride_authenticated;
-- Lawful contact interface for the engines that deliver messages / payments.
GRANT EXECUTE ON FUNCTION trustride.fn_user_contact_resolve(UUID, TEXT) TO trs026_eng006_intg_service, trs026_eng011_present_service;
GRANT EXECUTE ON FUNCTION trustride.fn_user_payment_msisdn(UUID) TO trs026_eng006_intg_service;
-- The integration gateway (Supabase service role) authenticates external systems.
GRANT EXECUTE ON FUNCTION trustride.fn_external_system_authenticate(TEXT, TEXT) TO service_role;
GRANT USAGE ON SCHEMA trustride TO service_role;

SELECT trustride.fn_platform_conformance_assert();
