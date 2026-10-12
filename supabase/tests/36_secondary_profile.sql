-- Suite 36 -- secondary profile (Construction Directive 2.11, WP8): the address, socio-economic and education
-- profile of FDN-001 (records 027, 030, 031) on one's own identity only. The socio-economic profile is
-- consent-governed; inputs are validated; repeating a submission records nothing new; relationships are only
-- those of the approved model (between registered identities), so free-text next-of-kin notes are refused.
DO $$
DECLARE
  p UUID; q UUID; r JSONB; v TEXT; n INT; ok BOOLEAN;
  ready BOOLEAN := to_regprocedure('trustride.fn_my_secondary_profile()') IS NOT NULL;
BEGIN
  IF NOT ready THEN
    PERFORM pg_temp.t_check('secondary profile read exists', false, 'fn_my_secondary_profile absent');
  ELSE
  p := pg_temp.t_person('Second Person', 'CUSTOMER');
  q := pg_temp.t_person('Other Person', 'CUSTOMER');

  -- ============ address
  PERFORM pg_temp.t_as(p);
  r := trustride.fn_secondary_profile_submit('ADDRESS', '{"address_line_1":"Plot 12, Milimani Road","town":"Kisumu","county_code":"42","ward":"Milimani","estate":"Milimani"}');
  PERFORM pg_temp.t_check('profile: an address is recorded on one''s own identity', (r->>'accepted')::boolean
    AND (trustride.fn_my_secondary_profile()->'address'->>'county_code') = '42', r::text);
  r := trustride.fn_secondary_profile_submit('ADDRESS', '{"address_line_1":"Plot 12, Milimani Road","town":"Kisumu","county_code":"42","ward":"Milimani","estate":"Milimani"}');
  PERFORM pg_temp.t_admin();
  SELECT count(*) INTO n FROM trustride.user_address WHERE user_id = p;
  PERFORM pg_temp.t_check('profile: submitting the same address again records nothing new', n = 1 AND (r->>'unchanged')::boolean, n::text || ' ' || r::text);
  PERFORM pg_temp.t_as(p);
  r := trustride.fn_secondary_profile_submit('ADDRESS', '{"address_line_1":"House 4, Kenyatta Avenue","town":"Nakuru","county_code":"32"}');
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('profile: a move keeps the old address as history and flags the county change for reconciliation',
    (SELECT count(*) FROM trustride.user_address WHERE user_id = p AND valid_to IS NOT NULL) = 1
    AND (SELECT county_code FROM trustride.user_address WHERE user_id = p AND is_primary AND valid_to IS NULL) = '32'
    AND (r->>'reconciliation_flagged')::boolean
    AND EXISTS (SELECT 1 FROM trustride.audit_log WHERE entity_id = p AND action = 'SECONDARY_DATA_RECONCILIATION_NOTE'), r::text);
  PERFORM pg_temp.t_as(p);
  FOR v IN SELECT unnest(ARRAY[
      '{"address_line_1":"","town":"Kisumu","county_code":"42"}',
      '{"address_line_1":"Plot 1","county_code":"48"}',
      '{"address_line_1":"Plot 1","county_code":"00"}',
      '{"address_line_1":"Plot 1","county_code":"Kisumu"}']) LOOP
    BEGIN PERFORM trustride.fn_secondary_profile_submit('ADDRESS', v::jsonb); ok := false;
    EXCEPTION WHEN OTHERS THEN ok := true; END;
    PERFORM pg_temp.t_check('profile: an invalid address is refused ' || v, ok);
  END LOOP;

  -- ============ socio-economic (consent-governed)
  BEGIN PERFORM trustride.fn_secondary_profile_submit('SOCIOECONOMIC', '{"household_size":4,"primary_language":"Dholuo"}'); ok := false; v := 'accepted';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%consent%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('profile: socio-economic data is refused without explicit consent', ok, left(v, 160));
  r := trustride.fn_secondary_profile_submit('SOCIOECONOMIC', '{"household_size":4,"primary_language":"Dholuo","income_band":"Prefer not to say","consent":true}');
  PERFORM pg_temp.t_check('profile: with consent the socio-economic profile is recorded as self-reported',
    (trustride.fn_my_secondary_profile()->'socioeconomic'->>'household_size')::int = 4
    AND trustride.fn_my_secondary_profile()->'socioeconomic'->>'data_source' = 'SELF_REPORTED', r::text);
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('profile: the consent is evidenced in the audit record',
    EXISTS (SELECT 1 FROM trustride.audit_log WHERE entity_id = p AND action = 'SECONDARY_DATA_SUBMITTED'
            AND after_snapshot->>'field_category' = 'SOCIOECONOMIC' AND (after_snapshot->>'consent_given')::boolean));
  PERFORM pg_temp.t_check('profile: personal values are not copied into the audit trail',
    NOT EXISTS (SELECT 1 FROM trustride.audit_log WHERE entity_id = p AND after_snapshot::text ILIKE '%Dholuo%'));
  PERFORM pg_temp.t_as(p);
  PERFORM pg_temp.t_check('profile: an impossible household size is refused',
    pg_temp.t_fails('SELECT trustride.fn_secondary_profile_submit(''SOCIOECONOMIC'', ''{"household_size":0,"consent":true}'')'));

  -- ============ education
  r := trustride.fn_secondary_profile_submit('EDUCATION', '{"education_level":"Diploma","institution":"Kisumu National Polytechnic","qualification":"Automotive Engineering","year_completed":2019}');
  r := trustride.fn_secondary_profile_submit('EDUCATION', '{"education_level":"Diploma","institution":"Kisumu National Polytechnic","qualification":"Automotive Engineering","year_completed":2019}');
  PERFORM pg_temp.t_check('profile: the same qualification submitted twice is recorded once',
    jsonb_array_length(trustride.fn_my_secondary_profile()->'education') = 1 AND (r->>'unchanged')::boolean, r::text);
  PERFORM pg_temp.t_check('profile: a completion year in the future is refused',
    pg_temp.t_fails(format('SELECT trustride.fn_secondary_profile_submit(''EDUCATION'', ''{"education_level":"Degree","year_completed":%s}'')', extract(year FROM now())::int + 1)));
  PERFORM pg_temp.t_check('profile: an education entry needs its level',
    pg_temp.t_fails('SELECT trustride.fn_secondary_profile_submit(''EDUCATION'', ''{"institution":"X"}'')'));

  -- ============ relationships: only the approved model
  BEGIN PERFORM trustride.fn_secondary_profile_submit('RELATIONSHIP', '{"name":"Jane","relationship_type":"Sister","contact":"0712000000"}'); ok := false; v := 'recorded';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%registered%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('profile: free-text next-of-kin details of a non-member are refused (not in the approved relationship model)', ok, left(v, 160));
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('profile: no next-of-kin note was written', NOT EXISTS (SELECT 1 FROM trustride.user_note WHERE user_id = p AND note_text LIKE 'Next of kin%'));
  PERFORM pg_temp.t_as(p);
  PERFORM pg_temp.t_check('profile: an unknown category is refused', pg_temp.t_fails('SELECT trustride.fn_secondary_profile_submit(''SALARY'', ''{}'')'));

  -- ============ ownership
  PERFORM pg_temp.t_as(q);
  r := trustride.fn_my_secondary_profile();
  PERFORM pg_temp.t_check('profile: another person sees only their own (empty) profile',
    r->'address' = 'null'::jsonb AND jsonb_array_length(r->'education') = 0 AND r->'socioeconomic' = 'null'::jsonb, r::text);
  PERFORM pg_temp.t_check('profile: another person cannot read the tables directly',
    pg_temp.t_visible('user_address', format('user_id = %L', p)) = 0 AND pg_temp.t_visible('user_socioeconomic_profile', format('user_id = %L', p)) = 0);
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('profile: not callable without a signed-in person', pg_temp.t_fails('SELECT trustride.fn_secondary_profile_submit(''EDUCATION'', ''{"education_level":"X"}'')'));
  PERFORM pg_temp.t_check('profile: the read is not available to anonymous visitors', NOT has_function_privilege('anon', 'trustride.fn_my_secondary_profile()', 'EXECUTE'));
  END IF;
END
$$;
