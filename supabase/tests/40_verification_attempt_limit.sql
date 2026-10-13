-- Suite 40 -- three incorrect identity submissions per registration identity (Founder direction, WP9 item 1).
-- A submission counts when the identity check gives a definitive answer that the submitted data is incorrect
-- (ID invalid, not found, holder deceased, names not matching, ID held by another identity). Provider
-- outages, malformed answers and answers TrustRide's own rule cannot use (record found, status unknown) do not
-- count. After the third, every further attempt is refused in the database. Counting is recorded and audited
-- without the ID number or names.
DO $$
DECLARE
  a UUID; c UUID; r JSONB; v TEXT; n INT; ok BOOLEAN; req RECORD; vid UUID;
  ready BOOLEAN := to_regprocedure('trustride.fn_registration_incorrect_attempts(uuid)') IS NOT NULL;
BEGIN
  IF NOT ready THEN
    PERFORM pg_temp.t_check('verification attempt limit exists', false, 'fn_registration_incorrect_attempts absent');
  ELSE
  a := gen_random_uuid();
  INSERT INTO auth.users (id, email, aud, role) VALUES (a, 'limit-a-' || substr(a::text, 1, 8) || '@test.trustride.ke', 'authenticated', 'authenticated');
  PERFORM pg_temp.t_as(a);
  PERFORM trustride.fn_registration_capture_primary('Limit Test Person', '00440001', TRUE);       -- 1st: simulator INVALID
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('limit: the first incorrect submission is counted (1 of 3)', trustride.fn_registration_incorrect_attempts(a) = 1,
    trustride.fn_registration_incorrect_attempts(a)::text);
  PERFORM pg_temp.t_as(a);
  r := trustride.fn_my_registration_retry_options();
  PERFORM pg_temp.t_check('limit: the person sees how many attempts remain',
    (r->>'incorrect_attempts')::int = 1 AND (r->>'attempts_remaining')::int = 2 AND NOT (r->>'locked')::boolean AND (r->>'retryable')::boolean, r::text);
  PERFORM trustride.fn_registration_retry_primary('Limit Test Person', '00440002');               -- 2nd: INVALID
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('limit: the second incorrect submission is counted (2 of 3)', trustride.fn_registration_incorrect_attempts(a) = 2);

  -- ============ an outage between attempts does not count
  UPDATE trustride.integration_adapter_registry SET active = FALSE WHERE port_code = 'IDENTITY_AUTHORITY' AND active;
  INSERT INTO trustride.integration_adapter_registry (port_code, adapter_type, active, notes) VALUES ('IDENTITY_AUTHORITY', 'PRODUCTION', TRUE, 'suite 40');
  PERFORM pg_temp.t_as(a);
  vid := trustride.fn_registration_retry_primary('Limit Test Person', '31440003');
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(4);
  SELECT * INTO req FROM trustride.integration_outbound_request WHERE port_code = 'IDENTITY_AUTHORITY' AND ref_id = vid;
  UPDATE trustride.integration_outbound_request SET attempts = max_attempts WHERE request_id = req.request_id;
  PERFORM trustride.fn_integration_outbound_result(req.request_id, FALSE, NULL, NULL, 'TimeoutError');
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('limit: a provider outage is recorded as inconclusive and not counted (still 2 of 3)',
    trustride.fn_registration_incorrect_attempts(a) = 2
    AND (SELECT failure_category FROM trustride.verification_record WHERE verification_id = vid) = 'INCONCLUSIVE');
  -- a malformed provider answer is inconclusive too
  PERFORM pg_temp.t_as(a);
  vid := trustride.fn_registration_retry_primary();                                               -- same details allowed after an outage
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(4);
  SELECT * INTO req FROM trustride.integration_outbound_request WHERE port_code = 'IDENTITY_AUTHORITY' AND ref_id = vid;
  PERFORM trustride.fn_integration_outbound_result(req.request_id, TRUE, 'mm-x', '{"unexpected":"shape"}', NULL);
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('limit: a malformed provider answer is inconclusive and not counted',
    trustride.fn_registration_incorrect_attempts(a) = 2 AND (SELECT failure_category FROM trustride.verification_record WHERE verification_id = vid) = 'INCONCLUSIVE');
  UPDATE trustride.integration_adapter_registry SET active = FALSE WHERE port_code = 'IDENTITY_AUTHORITY' AND active;
  INSERT INTO trustride.integration_adapter_registry (port_code, adapter_type, active, notes) VALUES ('IDENTITY_AUTHORITY', 'SIMULATOR', TRUE, 'suite 40');

  -- ============ the third incorrect submission blocks
  PERFORM pg_temp.t_as(a);
  PERFORM trustride.fn_registration_retry_primary('Limit Test Person', '99440004');               -- 3rd: simulator DECEASED
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('limit: the third incorrect submission is counted (3 of 3)', trustride.fn_registration_incorrect_attempts(a) = 3);
  PERFORM pg_temp.t_check('limit: reaching the limit is audited once',
    (SELECT count(*) FROM trustride.audit_log WHERE entity_id = a AND action = 'REGISTRATION_VERIFICATION_LIMIT_REACHED') = 1);
  PERFORM pg_temp.t_as(a);
  r := trustride.fn_my_registration_retry_options();
  PERFORM pg_temp.t_check('limit: the person is told verification is blocked; nothing is retryable',
    (r->>'locked')::boolean AND NOT (r->>'retryable')::boolean AND (r->>'attempts_remaining')::int = 0, r::text);
  BEGIN PERFORM trustride.fn_registration_retry_primary('Limit Test Person', '31440005'); ok := false; v := 'accepted';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%three%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('limit: a fourth attempt is refused', ok, left(v, 160));
  BEGIN PERFORM trustride.fn_registration_retry_primary(); ok := false; v := 'accepted';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%three%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('limit: a fourth attempt with no details is refused the same way', ok, left(v, 160));
  BEGIN PERFORM trustride.fn_registration_capture_primary('Limit Test Person', '31440006', TRUE); ok := false; v := 'accepted';
  EXCEPTION WHEN OTHERS THEN ok := true; v := SQLERRM; END;
  PERFORM pg_temp.t_check('limit: registering again from the same account is refused', ok, left(v, 160));
  BEGIN PERFORM trustride.fn_business_actor_register(a, 'CUSTOMER'); ok := false; v := 'accepted';
  EXCEPTION WHEN OTHERS THEN ok := true; v := SQLERRM; END;
  PERFORM pg_temp.t_check('limit: the blocked identity cannot open a Customer environment directly', ok, left(v, 160));
  PERFORM pg_temp.t_admin();
  SELECT count(*) INTO n FROM trustride.verification_record WHERE subject_user_id = a AND outcome = 'PENDING';
  PERFORM pg_temp.t_check('limit: no verification was opened by the refused attempts', n = 0, n::text);

  -- ============ the record and the audit protect identity data
  PERFORM pg_temp.t_check('limit: each counted attempt records its category and reason class',
    (SELECT count(*) FROM trustride.verification_record WHERE subject_user_id = a AND failure_category = 'INCORRECT_DATA' AND failure_reason_class IS NOT NULL) = 3);
  PERFORM pg_temp.t_check('limit: the counting audit entries carry no ID number or legal name',
    NOT EXISTS (SELECT 1 FROM trustride.audit_log WHERE entity_id = a AND action IN ('REGISTRATION_VERIFICATION_ATTEMPT_COUNTED', 'REGISTRATION_VERIFICATION_LIMIT_REACHED')
                AND (after_snapshot::text ~ '0044000[0-9]|9944000[0-9]|3144000[0-9]' OR after_snapshot::text ILIKE '%Limit Test Person%'))
    AND (SELECT count(*) FROM trustride.audit_log WHERE entity_id = a AND action = 'REGISTRATION_VERIFICATION_ATTEMPT_COUNTED') = 3);
  PERFORM pg_temp.t_check('limit: the failed-verification audit no longer copies the provider''s personal fields',
    NOT EXISTS (SELECT 1 FROM trustride.audit_log WHERE entity_id = a AND action = 'REGISTRATION_PRIMARY_FAILED'
                AND (after_snapshot->'raw_response' ?| ARRAY['documentNumber', 'fullName', 'dateOfBirth', 'returned_legal_name'] OR after_snapshot::text ILIKE '%Limit Test Person%')));

  -- ============ direct paths
  PERFORM pg_temp.t_check('limit: signed-in users cannot write verification records or change the count directly',
    NOT has_table_privilege('authenticated', 'trustride.verification_record', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'trustride.verification_record', 'UPDATE')
    AND NOT has_function_privilege('authenticated', 'trustride.fn_verification_completed_accept(uuid,text,text,text,jsonb)', 'EXECUTE'));

  -- ============ concurrency: one attempt at a time, counted under the identity's row lock
  c := gen_random_uuid();
  INSERT INTO auth.users (id, email, aud, role) VALUES (c, 'limit-c-' || substr(c::text, 1, 8) || '@test.trustride.ke', 'authenticated', 'authenticated');
  PERFORM pg_temp.t_as(c);
  PERFORM trustride.fn_registration_capture_primary('Concurrent Limit Person', '00440011', TRUE);
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_as(c);
  PERFORM trustride.fn_registration_retry_primary('Concurrent Limit Person', '00440012');
  BEGIN PERFORM trustride.fn_registration_retry_primary('Concurrent Limit Person', '00440013'); ok := false; v := 'second accepted';
  EXCEPTION WHEN OTHERS THEN ok := true; v := SQLERRM; END;
  PERFORM pg_temp.t_check('limit: a second attempt while one is in flight is refused (no extra attempt)', ok, left(v, 160));
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('limit: only the attempts that ran are counted', trustride.fn_registration_incorrect_attempts(c) = 2);
  END IF;
END
$$;
