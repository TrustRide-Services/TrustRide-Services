-- ============================================================================
-- TRS026 Construction Directive 2.11 (WP8) -- secondary profile (Foundation).
--
-- fn_secondary_profile_submit was already callable by any signed-in person with
-- no screen. Hardened before it gets one:
--   * categories are the FDN-001 Master User Profile records 027 (address), 030
--     (socio-economic) and 031 (education), on one's own identity only;
--   * the socio-economic profile is consent-governed (FDN-001 030, Art.13): it is
--     refused without explicit consent, and the consent is evidenced in the audit;
--   * RELATIONSHIP wrote a non-member's name and phone ("next of kin") into a free-
--     text note. FDN-001 034 defines relationships only between registered users
--     (guardian-student, household, EA-client), governed; the free-text path is not
--     in the approved model and is now refused (a Founder decision if wanted);
--   * validation: county codes 01-47 (Constitution of Kenya, First Schedule),
--     required fields, plausible household size and completion year, lengths;
--   * repeating a submission records nothing new; personal values are not copied
--     into the audit trail (category and consent only);
--   * fn_my_secondary_profile returns the caller's own current profile.
-- ============================================================================

CREATE OR REPLACE FUNCTION trustride.fn_secondary_profile_submit(p_field_category text, p_field_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_d JSONB := coalesce(p_field_data, '{}'::jsonb);
  v_cur RECORD;
  v_prior_county TEXT;
  v_reconcile BOOLEAN := FALSE;
  v_line TEXT; v_town TEXT; v_county TEXT; v_ward TEXT; v_estate TEXT;
  v_size INT; v_year INT; v_level TEXT; v_inst TEXT; v_qual TEXT; v_lang TEXT; v_income TEXT;
  v_consent BOOLEAN := FALSE;
  t TEXT;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'fn_secondary_profile_submit: no authenticated session'; END IF;
  IF NOT EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id = v_user_id AND identity_primitive = 'PERSON' AND status <> 'SUSPENDED') THEN
    RAISE EXCEPTION 'fn_secondary_profile_submit: complete your primary registration first';
  END IF;
  -- Text limits for every field.
  FOR t IN SELECT jsonb_object_keys(v_d) LOOP
    IF jsonb_typeof(v_d->t) = 'string' AND length(v_d->>t) > 200 THEN RAISE EXCEPTION '% is too long (200 characters at most)', t; END IF;
  END LOOP;

  CASE p_field_category
    WHEN 'ADDRESS' THEN
      v_line := nullif(trim(coalesce(v_d->>'address_line_1', '')), '');
      v_town := nullif(trim(coalesce(v_d->>'town', '')), '');
      v_county := nullif(lpad(trim(coalesce(v_d->>'county_code', '')), 2, '0'), '00');
      v_ward := nullif(trim(coalesce(v_d->>'ward', '')), '');
      v_estate := nullif(trim(coalesce(v_d->>'estate', '')), '');
      IF v_line IS NULL THEN RAISE EXCEPTION 'The address needs its first line (plot, building or street)'; END IF;
      IF v_county IS NULL OR v_county !~ '^(0[1-9]|[1-3][0-9]|4[0-7])$' THEN
        RAISE EXCEPTION 'County code must be 01-47 (Constitution of Kenya, First Schedule), e.g. 42 for Kisumu';
      END IF;
      SELECT * INTO v_cur FROM trustride.user_address WHERE user_id = v_user_id AND is_primary AND valid_to IS NULL;
      IF v_cur.address_id IS NOT NULL AND (v_cur.address_line_1, v_cur.town, v_cur.county_code, v_cur.ward, v_cur.estate)
           IS NOT DISTINCT FROM (v_line, v_town, v_county::bpchar, v_ward, v_estate) THEN
        RETURN jsonb_build_object('accepted', true, 'unchanged', true, 'reconciliation_flagged', false);
      END IF;
      v_prior_county := v_cur.county_code;
      v_reconcile := v_prior_county IS NOT NULL AND v_prior_county IS DISTINCT FROM v_county;
      UPDATE trustride.user_address SET valid_to = CURRENT_DATE, is_primary = FALSE WHERE user_id = v_user_id AND is_primary AND valid_to IS NULL;
      INSERT INTO trustride.user_address (user_id, address_type, address_line_1, town, county_code, ward, estate, is_primary)
      VALUES (v_user_id, 'PRIMARY', v_line, v_town, v_county, v_ward, v_estate, TRUE);

    WHEN 'SOCIOECONOMIC' THEN
      v_consent := coalesce((v_d->>'consent')::boolean, false);
      IF NOT v_consent THEN
        RAISE EXCEPTION 'The socio-economic profile is optional and recorded only with your explicit consent (Data Protection Act 2019 s.30)';
      END IF;
      v_size := (v_d->>'household_size')::int;
      IF v_size IS NOT NULL AND (v_size < 1 OR v_size > 50) THEN RAISE EXCEPTION 'Household size must be between 1 and 50'; END IF;
      v_income := nullif(trim(coalesce(v_d->>'income_band', '')), '');
      v_lang := nullif(trim(coalesce(v_d->>'primary_language', '')), '');
      IF v_size IS NULL AND v_income IS NULL AND v_lang IS NULL THEN RAISE EXCEPTION 'Nothing to record'; END IF;
      SELECT * INTO v_cur FROM trustride.user_socioeconomic_profile WHERE user_id = v_user_id ORDER BY last_assessed_at DESC NULLS LAST LIMIT 1;
      IF v_cur.profile_id IS NOT NULL AND (v_cur.income_band, v_cur.household_size, v_cur.primary_language) IS NOT DISTINCT FROM (v_income, v_size::smallint, v_lang) THEN
        RETURN jsonb_build_object('accepted', true, 'unchanged', true, 'reconciliation_flagged', false);
      END IF;
      INSERT INTO trustride.user_socioeconomic_profile (user_id, income_band, household_size, primary_language, data_source, last_assessed_at)
      VALUES (v_user_id, v_income, v_size, v_lang, 'SELF_REPORTED', now());

    WHEN 'EDUCATION' THEN
      v_level := nullif(trim(coalesce(v_d->>'education_level', '')), '');
      IF v_level IS NULL THEN RAISE EXCEPTION 'The education entry needs its level'; END IF;
      v_inst := nullif(trim(coalesce(v_d->>'institution', '')), '');
      v_qual := nullif(trim(coalesce(v_d->>'qualification', '')), '');
      v_year := (v_d->>'year_completed')::int;
      IF v_year IS NOT NULL AND (v_year < 1940 OR v_year > extract(year FROM now())::int) THEN
        RAISE EXCEPTION 'Completion year must be between 1940 and this year';
      END IF;
      IF EXISTS (SELECT 1 FROM trustride.user_education_profile WHERE user_id = v_user_id
                 AND (education_level, institution, qualification, year_completed) IS NOT DISTINCT FROM (v_level, v_inst, v_qual, v_year::smallint)) THEN
        RETURN jsonb_build_object('accepted', true, 'unchanged', true, 'reconciliation_flagged', false);
      END IF;
      INSERT INTO trustride.user_education_profile (user_id, education_level, institution, qualification, year_completed)
      VALUES (v_user_id, v_level, v_inst, v_qual, v_year);

    WHEN 'RELATIONSHIP' THEN
      RAISE EXCEPTION 'Relationships are recorded only between registered TrustRide identities (guardian-student, household, assistant-client) and are governed; details of people outside TrustRide are not recorded';
    ELSE
      RAISE EXCEPTION 'fn_secondary_profile_submit: unrecognized field_category %', p_field_category;
  END CASE;

  IF v_reconcile THEN
    PERFORM trustride.fn_audit_log_append('platform_users', v_user_id, 'SECONDARY_DATA_RECONCILIATION_NOTE', v_user_id,
      'USER', NULL, NULL, jsonb_build_object('field_category', p_field_category, 'prior_county_code', v_prior_county),
      jsonb_build_object('field_category', p_field_category, 'county_code', v_county));
  END IF;
  PERFORM trustride.fn_audit_log_append('platform_users', v_user_id, 'SECONDARY_DATA_SUBMITTED', v_user_id,
    'USER', NULL, NULL, NULL, jsonb_build_object('field_category', p_field_category, 'consent_given', CASE WHEN p_field_category = 'SOCIOECONOMIC' THEN v_consent END));

  RETURN jsonb_build_object('accepted', true, 'unchanged', false, 'reconciliation_flagged', v_reconcile);
END;
$function$;

CREATE FUNCTION trustride.fn_my_secondary_profile()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'address', (SELECT jsonb_build_object('address_line_1', a.address_line_1, 'town', a.town, 'county_code', a.county_code, 'ward', a.ward,
                       'estate', a.estate, 'since', a.valid_from)
                FROM trustride.user_address a WHERE a.user_id = auth.uid() AND a.is_primary AND a.valid_to IS NULL LIMIT 1),
    'socioeconomic', (SELECT jsonb_build_object('income_band', s.income_band, 'household_size', s.household_size, 'primary_language', s.primary_language,
                             'data_source', s.data_source, 'recorded_at', s.last_assessed_at)
                      FROM trustride.user_socioeconomic_profile s WHERE s.user_id = auth.uid() ORDER BY s.last_assessed_at DESC NULLS LAST LIMIT 1),
    'education', coalesce((SELECT jsonb_agg(jsonb_build_object('education_level', e.education_level, 'institution', e.institution,
                                  'qualification', e.qualification, 'year_completed', e.year_completed) ORDER BY e.year_completed DESC NULLS LAST)
                           FROM trustride.user_education_profile e WHERE e.user_id = auth.uid()), '[]'::jsonb))
  WHERE auth.uid() IS NOT NULL;
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
    'fn_founder_exists', 'fn_founder_bootstrap',
    'fn_user_contact_add', 'fn_user_contact_add_for', 'fn_user_contact_remove', 'fn_user_contact_send_code',
    'fn_user_contact_set_primary', 'fn_user_contact_verify', 'fn_user_contact_preference_set', 'fn_user_contact_preference_set_for',
    'fn_entity_member_add', 'fn_business_actor_register', 'fn_resource_operator_duty_set',
    -- Role-checked Office actions
    'fn_role_assign', 'fn_business_actor_request_decide', 'fn_integration_adapter_set', 'fn_external_system_credential_issue',
    'fn_external_system_credential_revoke', 'fn_advisory_recommendation_decide',
    -- Policy helpers used by row-level security
    'fn_am_i_administrator', 'fn_am_i_governor', 'fn_am_i_role', 'fn_am_i_member_of_entity', 'fn_am_i_member_of_entity_user',
    'fn_am_i_representative_of', 'fn_contact_may_manage'
  ]::TEXT[];
$function$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_my_secondary_profile() TO trustride_authenticated;
SELECT trustride.fn_platform_conformance_assert();
