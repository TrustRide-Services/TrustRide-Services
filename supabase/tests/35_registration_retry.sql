-- Suite 35 -- safe registration retry and one identity per national ID (Construction Directive 2.11, WP8).
-- Retryable states: the identity is VERIFICATION_FAILED and no verification is pending. After a definitive
-- answer (invalid, deceased, not found, names not matching) the same details are never replayed -- the person
-- corrects them; after PROVIDER_UNAVAILABLE the same details may be sent again. A national ID held by another
-- verified identity can be neither captured nor retried, and a verification that would create a second holder
-- fails instead of erroring. Every retry is audited with the ID masked.
DO $$
DECLARE
  a UUID; b UUID; c UUID; d UUID; v TEXT; n INT; ok BOOLEAN; r JSONB; req RECORD; vid UUID;
  ready BOOLEAN := to_regprocedure('trustride.fn_my_registration_retry_options()') IS NOT NULL;
BEGIN
  -- ============ the duplicate-identity backstop (checked whatever the build)
  PERFORM pg_temp.t_check('identity: a national ID can be held by only one verified identity (unique backstop)',
    EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'trustride' AND tablename = 'user_identifier' AND indexdef ILIKE '%UNIQUE%identifier_value%NATIONAL_ID%'));
  IF NOT ready THEN
    PERFORM pg_temp.t_check('registration retry options exist', false, 'fn_my_registration_retry_options absent');
  ELSE
  -- ============ a definitive failure: the same details are not replayed
  a := gen_random_uuid();
  INSERT INTO auth.users (id, email, aud, role) VALUES (a, 'retry-a-' || substr(a::text, 1, 8) || '@test.trustride.ke', 'authenticated', 'authenticated');
  PERFORM pg_temp.t_as(a);
  PERFORM trustride.fn_registration_capture_primary('Akinyi Retry Tester', '00718273', TRUE);   -- simulator: 00 prefix is INVALID
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('retry: the simulator''s invalid ID ends VERIFICATION_FAILED',
    (SELECT status FROM trustride.platform_users WHERE user_id = a) = 'VERIFICATION_FAILED');
  PERFORM pg_temp.t_as(a);
  r := trustride.fn_my_registration_retry_options();
  PERFORM pg_temp.t_check('retry: the person sees why it failed and that the details must be corrected',
    (r->>'retryable')::boolean AND NOT (r->>'same_details_allowed')::boolean AND r->>'last_result' = 'INVALID'
    AND r->>'national_id_masked' = '****8273' AND r->>'legal_name' = 'Akinyi Retry Tester', r::text);
  BEGIN PERFORM trustride.fn_registration_retry_primary(); ok := false; v := 'replayed';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%correct%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('retry: replaying the same details after a definitive answer is refused', ok, left(v, 160));
  BEGIN PERFORM trustride.fn_registration_retry_primary('Akinyi Retry Tester', ' 00718273 '); ok := false; v := 'replayed';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%correct%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('retry: the same details re-typed (spacing) are still the same details', ok, left(v, 160));
  vid := trustride.fn_registration_retry_primary('Akinyi Retry Tester', '31718273');
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('retry: corrected details start one new verification and the person is pending again',
    (SELECT outcome FROM trustride.verification_record WHERE verification_id = vid) = 'PENDING'
    AND (SELECT status FROM trustride.platform_users WHERE user_id = a) = 'PENDING_VERIFICATION'
    AND (SELECT national_id_ref FROM trustride.person_profile WHERE user_id = a) = '31718273');
  PERFORM pg_temp.t_check('retry: the superseded ID is kept as history, not deleted',
    EXISTS (SELECT 1 FROM trustride.user_identifier WHERE user_id = a AND identifier_type = 'NATIONAL_ID' AND identifier_value = '00718273' AND status = 'SUPERSEDED')
    AND EXISTS (SELECT 1 FROM trustride.user_identifier WHERE user_id = a AND identifier_type = 'NATIONAL_ID' AND identifier_value = '31718273' AND status = 'PENDING'));
  PERFORM pg_temp.t_check('retry: audited, with the ID masked and the change recorded',
    EXISTS (SELECT 1 FROM trustride.audit_log WHERE entity_id = a AND action = 'REGISTRATION_PRIMARY_RETRY'
            AND after_snapshot->>'national_id_changed' = 'true' AND after_snapshot::text NOT LIKE '%31718273%' AND after_snapshot::text LIKE '%8273%'));
  PERFORM pg_temp.t_as(a);
  BEGIN PERFORM trustride.fn_registration_retry_primary('Akinyi Retry Tester', '31718274'); ok := false; v := 'second retry';
  EXCEPTION WHEN OTHERS THEN ok := true; v := SQLERRM; END;
  PERFORM pg_temp.t_check('retry: a second retry while one is pending is refused (no duplicate verifications)', ok, left(v, 160));
  PERFORM pg_temp.t_check('retry: options say nothing is retryable while pending',
    NOT (trustride.fn_my_registration_retry_options()->>'retryable')::boolean);
  PERFORM pg_temp.t_admin();
  SELECT count(*) INTO n FROM trustride.verification_record WHERE subject_user_id = a AND outcome = 'PENDING';
  PERFORM pg_temp.t_check('retry: exactly one pending verification', n = 1, n::text);
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('retry: the corrected details verify and the identity becomes active',
    (SELECT status FROM trustride.platform_users WHERE user_id = a) = 'ACTIVE');
  PERFORM pg_temp.t_check('retry: verification activates only the corrected ID -- the superseded one stays superseded',
    (SELECT string_agg(identifier_value || '=' || status, ' ' ORDER BY identifier_value) FROM trustride.user_identifier
     WHERE user_id = a AND identifier_type = 'NATIONAL_ID') = '00718273=SUPERSEDED 31718273=ACTIVE');
  PERFORM pg_temp.t_as(a);
  BEGIN PERFORM trustride.fn_registration_retry_primary('X Y', '11111111'); ok := false; v := 'retried an active identity';
  EXCEPTION WHEN OTHERS THEN ok := true; v := SQLERRM; END;
  PERFORM pg_temp.t_check('retry: an active identity cannot retry (no re-verification bypass)', ok, left(v, 160));
  PERFORM pg_temp.t_admin();

  -- ============ one identity per national ID
  b := gen_random_uuid();
  INSERT INTO auth.users (id, email, aud, role) VALUES (b, 'retry-b-' || substr(b::text, 1, 8) || '@test.trustride.ke', 'authenticated', 'authenticated');
  PERFORM pg_temp.t_as(b);
  BEGIN PERFORM trustride.fn_registration_capture_primary('Someone Else', '31718273', TRUE); ok := false; v := 'captured';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%another%identity%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('identity: registering a national ID held by a verified identity is refused', ok, left(v, 160));
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('identity: the refused registration leaves no partial identity',
    NOT EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id = b));
  PERFORM pg_temp.t_as(b);
  PERFORM trustride.fn_registration_capture_primary('Brian Second Person', '99123456', TRUE);   -- simulator: 99 prefix is DECEASED
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_as(b);
  BEGIN PERFORM trustride.fn_registration_retry_primary('Brian Second Person', '31718273'); ok := false; v := 'took over';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%another%identity%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('identity: a retry cannot move onto a national ID another identity holds', ok, left(v, 160));
  PERFORM pg_temp.t_check('retry: a deceased-record answer is definitive too',
    trustride.fn_my_registration_retry_options()->>'last_result' = 'DECEASED'
    AND NOT (trustride.fn_my_registration_retry_options()->>'same_details_allowed')::boolean);
  PERFORM pg_temp.t_admin();

  -- a second holder appearing while a verification is in flight: the verification fails, it does not error
  c := gen_random_uuid();
  INSERT INTO auth.users (id, email, aud, role) VALUES (c, 'retry-c-' || substr(c::text, 1, 8) || '@test.trustride.ke', 'authenticated', 'authenticated');
  PERFORM pg_temp.t_as(c);
  PERFORM trustride.fn_registration_capture_primary('Cynthia Race Person', '41555666', TRUE);
  PERFORM pg_temp.t_admin();
  d := pg_temp.t_person('Race Holder', NULL);
  INSERT INTO trustride.user_identifier (user_id, identifier_type, identifier_value, status, verified_at) VALUES (d, 'NATIONAL_ID', '41555666', 'ACTIVE', now());
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('identity: a verification that would create a second holder fails with a reason (no error, no second holder)',
    (SELECT status FROM trustride.platform_users WHERE user_id = c) = 'VERIFICATION_FAILED'
    AND (SELECT count(*) FROM trustride.user_identifier WHERE identifier_type = 'NATIONAL_ID' AND identifier_value = '41555666' AND status = 'ACTIVE') = 1
    AND EXISTS (SELECT 1 FROM trustride.audit_log WHERE entity_id = c AND action = 'REGISTRATION_PRIMARY_FAILED' AND after_snapshot->'reasons' ? 'NATIONAL_ID_HELD_BY_ANOTHER_IDENTITY'));
  PERFORM pg_temp.t_as(c);
  PERFORM pg_temp.t_check('identity: the person is told the ID is already registered',
    trustride.fn_my_registration_retry_options()->'reasons' ? 'NATIONAL_ID_HELD_BY_ANOTHER_IDENTITY');
  PERFORM pg_temp.t_admin();

  -- ============ provider unavailable: the same details may be sent again
  UPDATE trustride.integration_adapter_registry SET active = FALSE WHERE port_code = 'IDENTITY_AUTHORITY' AND active;
  INSERT INTO trustride.integration_adapter_registry (port_code, adapter_type, active, notes) VALUES ('IDENTITY_AUTHORITY', 'PRODUCTION', TRUE, 'suite 35');
  d := gen_random_uuid();
  INSERT INTO auth.users (id, email, aud, role) VALUES (d, 'retry-d-' || substr(d::text, 1, 8) || '@test.trustride.ke', 'authenticated', 'authenticated');
  PERFORM pg_temp.t_as(d);
  PERFORM trustride.fn_registration_capture_primary('Dorcas Unavailable Case', '52525252', TRUE);
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(4);
  SELECT * INTO req FROM trustride.integration_outbound_request WHERE port_code = 'IDENTITY_AUTHORITY'
    AND ref_id = (SELECT verification_id FROM trustride.verification_record WHERE subject_user_id = d ORDER BY 1 LIMIT 1);
  UPDATE trustride.integration_outbound_request SET attempts = max_attempts WHERE request_id = req.request_id;
  PERFORM trustride.fn_integration_outbound_result(req.request_id, FALSE, NULL, NULL, 'TimeoutError');
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_as(d);
  r := trustride.fn_my_registration_retry_options();
  PERFORM pg_temp.t_check('retry: after PROVIDER_UNAVAILABLE the same details may be sent again',
    (r->>'retryable')::boolean AND (r->>'same_details_allowed')::boolean AND r->>'last_result' = 'PROVIDER_UNAVAILABLE', r::text);
  vid := trustride.fn_registration_retry_primary();
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(4);
  SELECT count(*) INTO n FROM trustride.integration_outbound_request WHERE port_code = 'IDENTITY_AUTHORITY' AND ref_id = vid;
  PERFORM pg_temp.t_check('retry: the retry goes to the provider through Engine 6 again (one new request)', n = 1, n::text);

  -- ============ access
  PERFORM pg_temp.t_check('retry: not callable without a signed-in person', pg_temp.t_fails('SELECT trustride.fn_registration_retry_primary()'));
  PERFORM pg_temp.t_check('retry: no anonymous access', NOT has_function_privilege('anon', 'trustride.fn_registration_retry_primary(text,text)', 'EXECUTE'));
  END IF;
END
$$;
