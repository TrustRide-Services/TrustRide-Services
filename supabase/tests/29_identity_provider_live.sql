-- Suite 29 -- live identity and entity verification through a provider (Construction Directive WP7, section 2.6).
-- With the identity port set live (registry edited around the switch, as activation would), a
-- verification becomes an outbound provider request and stays PENDING until the provider answers;
-- the answer is mapped factually (a found IPRS record is RECORD_FOUND_STATUS_UNKNOWN, no KRA PIN is
-- invented) and Foundation's own onboarding rules decide; a not-found or unavailable provider ends the
-- verification explicitly; answers are applied once; shareholder identity numbers are not kept; only
-- service_role ingests callbacks.
DO $$
DECLARE
  p UUID; rep UUID; req RECORD; v TEXT; n INT; vid UUID; ent UUID; i INT;
  ready BOOLEAN := to_regprocedure('trustride.fn_integration_identity_request_live(uuid,jsonb,uuid)') IS NOT NULL;
BEGIN
  IF NOT ready THEN
    PERFORM pg_temp.t_check('live identity path exists', false, 'fn_integration_identity_request_live absent');
  ELSE
  UPDATE trustride.integration_adapter_registry SET active = FALSE WHERE port_code = 'IDENTITY_AUTHORITY' AND active;
  INSERT INTO trustride.integration_adapter_registry (port_code, adapter_type, active, notes) VALUES ('IDENTITY_AUTHORITY', 'PRODUCTION', TRUE, 'suite 29');

  -- ============ a person registers: the provider is asked; nothing is decided before it answers
  p := gen_random_uuid();
  INSERT INTO auth.users (id, email, aud, role) VALUES (p, 'idlive-' || substr(p::text, 1, 8) || '@test.trustride.ke', 'authenticated', 'authenticated');
  PERFORM pg_temp.t_as(p);
  PERFORM trustride.fn_registration_capture_primary('Wanjiku Achieng Otieno', '12345678', TRUE);
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(4);
  SELECT verification_id INTO vid FROM trustride.verification_record WHERE subject_user_id = p ORDER BY 1 DESC LIMIT 1;
  SELECT * INTO req FROM trustride.integration_outbound_request WHERE port_code = 'IDENTITY_AUTHORITY' AND ref_id = vid;
  PERFORM pg_temp.t_check('live: the verification becomes one IDENTITY_VERIFY request to the provider (names split for IPRS)',
    req.operation = 'IDENTITY_VERIFY' AND req.payload->>'document_number' = '12345678' AND req.payload->>'first_name' = 'Wanjiku' AND req.payload->>'last_name' = 'Otieno'
    AND req.payload->>'provider' = 'METAMAP', coalesce(req.payload::text, 'no request'));
  SELECT outcome::text INTO v FROM trustride.verification_record WHERE verification_id = vid;
  PERFORM pg_temp.t_check('live: before the provider answers the verification is PENDING (nothing simulated, nothing granted)',
    v = 'PENDING' AND (SELECT status FROM trustride.platform_users WHERE user_id = p) <> 'ACTIVE', v);

  -- ============ the provider finds the IPRS record
  PERFORM trustride.fn_integration_outbound_result(req.request_id, TRUE, 'mm-001',
    '{"data":{"documentNumber":"12345678","givenNames":"Wanjiku Achieng","lastName":"Otieno","fullName":"Wanjiku Achieng Otieno","gender":"F","dateOfBirth":"1990-01-01"},"error":null}', NULL);
  PERFORM pg_temp.t_cycle(4);
  SELECT returned_status::text || '|' || coalesce(returned_kra_pin, 'no-kra') || '|' || provider INTO v FROM trustride.integration_identity_verification_log WHERE verification_id = vid;
  PERFORM pg_temp.t_check('live: a found record is mapped factually (RECORD_FOUND_STATUS_UNKNOWN, no KRA PIN invented, provider METAMAP)',
    v = 'RECORD_FOUND_STATUS_UNKNOWN|no-kra|METAMAP', v);
  SELECT outcome::text INTO v FROM trustride.verification_record WHERE verification_id = vid;
  PERFORM pg_temp.t_check('live: Foundation''s onboarding rule decides -- without vital status and KRA PIN the person is not verified (gap escalated)',
    v = 'FAILED' AND (SELECT status FROM trustride.platform_users WHERE user_id = p) = 'VERIFICATION_FAILED', v);
  v := trustride.fn_integration_metamap_webhook_ingest(req.request_id, '{"data":{"fullName":"Wanjiku Achieng Otieno"}}');
  SELECT count(*) INTO n FROM trustride.integration_event_outbox WHERE idempotency_key = 'VERIFICATION_COMPLETED:' || vid::text;
  PERFORM pg_temp.t_check('live: a webhook after the answer changes nothing (applied once)', v = 'ALREADY_APPLIED' AND n = 1, v || ' ' || n);
  PERFORM pg_temp.t_check('live: a webhook for an unknown request is logged and refused', trustride.fn_integration_metamap_webhook_ingest(gen_random_uuid(), '{}') = 'UNKNOWN_REQUEST');

  -- ============ not found; provider unavailable after the governed retries
  FOR i IN 1..2 LOOP
    p := gen_random_uuid();
    INSERT INTO auth.users (id, email, aud, role) VALUES (p, 'idlive' || i || '-' || substr(p::text, 1, 8) || '@test.trustride.ke', 'authenticated', 'authenticated');
    PERFORM pg_temp.t_as(p);
    PERFORM trustride.fn_registration_capture_primary('Test Person Number' || i, (22222220 + i)::text, TRUE);
    PERFORM pg_temp.t_admin();
    PERFORM pg_temp.t_cycle(4);
    SELECT verification_id INTO vid FROM trustride.verification_record WHERE subject_user_id = p ORDER BY 1 DESC LIMIT 1;
    SELECT * INTO req FROM trustride.integration_outbound_request WHERE port_code = 'IDENTITY_AUTHORITY' AND ref_id = vid;
    IF i = 1 THEN
      PERFORM trustride.fn_integration_outbound_result(req.request_id, TRUE, 'mm-nf',
        '{"data":null,"error":{"type":"govCheckError","code":"kenyanIprs.notFound","message":"No results"}}', NULL);
    ELSE
      v := trustride.fn_integration_outbound_result(req.request_id, FALSE, NULL, NULL, 'TimeoutError: provider did not answer in 20 s');
      PERFORM pg_temp.t_check('live: a first provider failure is retried and decides nothing',
        v = 'FAILED_RETRYABLE' AND (SELECT outcome::text FROM trustride.verification_record WHERE verification_id = vid) = 'PENDING', v);
      -- the gateway claims (and counts) each attempt; every attempt has now been made
      UPDATE trustride.integration_outbound_request SET attempts = max_attempts WHERE request_id = req.request_id;
      PERFORM trustride.fn_integration_outbound_result(req.request_id, FALSE, NULL, NULL, 'TimeoutError: provider did not answer in 20 s');
    END IF;
    PERFORM pg_temp.t_cycle(4);
    SELECT returned_status::text INTO v FROM trustride.integration_identity_verification_log WHERE verification_id = vid;
    PERFORM pg_temp.t_check(CASE WHEN i = 1 THEN 'live: a number the register does not know ends NOT_FOUND, verification FAILED'
                                 ELSE 'live: a provider that never answers ends PROVIDER_UNAVAILABLE after the retries -- never left pending' END,
      v = CASE WHEN i = 1 THEN 'NOT_FOUND' ELSE 'PROVIDER_UNAVAILABLE' END
      AND (SELECT outcome::text FROM trustride.verification_record WHERE verification_id = vid) = 'FAILED', coalesce(v, 'no answer applied'));
  END LOOP;
  -- the provider answers after TrustRide gave up: recorded, but nothing is applied and nothing claims it was
  v := trustride.fn_integration_metamap_webhook_ingest(req.request_id, '{"data":{"fullName":"Test Person Number2"},"error":null}');
  PERFORM pg_temp.t_check('live: a late answer after the final failure is refused as ALREADY_FINAL (the verification stays FAILED)',
    v = 'ALREADY_FINAL' AND (SELECT outcome::text FROM trustride.verification_record WHERE verification_id = vid) = 'FAILED', v);

  -- ============ a business: BRS returns the company and its KRA PIN
  rep := gen_random_uuid();
  INSERT INTO auth.users (id, email, aud, role) VALUES (rep, 'idlive-rep-' || substr(rep::text, 1, 8) || '@test.trustride.ke', 'authenticated', 'authenticated');
  INSERT INTO trustride.platform_users (user_id, global_uid, identity_primitive, display_name, status) VALUES (rep, 'T-' || substr(rep::text, 1, 12), 'PERSON', 'Rep Person', 'ACTIVE');
  PERFORM pg_temp.t_as(rep);
  ent := trustride.fn_registration_capture_entity('Mwangaza Logistics Limited', 'COMPANY', 'PVT-ABC1234', 'P051234567Z');
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(4);
  SELECT verification_id INTO vid FROM trustride.verification_record WHERE subject_user_id = ent AND verification_type = 'ENTITY_REGISTRATION' ORDER BY 1 DESC LIMIT 1;
  SELECT * INTO req FROM trustride.integration_outbound_request WHERE port_code = 'IDENTITY_AUTHORITY' AND ref_id = vid;
  PERFORM pg_temp.t_check('live: the business becomes an ENTITY_VERIFY (BRS) request', req.operation = 'ENTITY_VERIFY' AND req.payload->>'registration_number' = 'PVT-ABC1234',
    coalesce(req.payload::text, 'no request'));
  PERFORM trustride.fn_integration_outbound_result(req.request_id, TRUE, 'mm-brs',
    '{"status":200,"id":"kenyan-brs-validation","error":null,"data":{"registrationNumber":"PVT-ABC1234","companyName":"Mwangaza Logistics Limited","companyType":"Private Company","registrationStatus":"Registered","kraPIN":"P051234567Z","shareHolders":[{"name":"A Shareholder","shares":100,"idType":"NATIONAL_ID","idNumber":"30000001"}]}}', NULL);
  PERFORM pg_temp.t_cycle(4);
  SELECT outcome::text INTO v FROM trustride.verification_record WHERE verification_id = vid;
  PERFORM pg_temp.t_check('live: a registered company whose name and KRA PIN match is verified by Foundation''s rule', v = 'VERIFIED', v);
  -- the same answer also arrives by webhook for a request TrustRide does not know: the callback log is kept, the shareholders are not
  PERFORM trustride.fn_integration_metamap_webhook_ingest(gen_random_uuid(),
    '{"data":{"companyName":"Other Co","shareHolders":[{"name":"B Shareholder","idType":"NATIONAL_ID","idNumber":"30000001"}]}}');
  SELECT string_agg(t, ' ') INTO v FROM (
    SELECT 'entity_log' t WHERE EXISTS (SELECT 1 FROM trustride.integration_entity_verification_log WHERE raw_response::text LIKE '%30000001%')
    UNION ALL SELECT 'outbound_request' WHERE EXISTS (SELECT 1 FROM trustride.integration_outbound_request WHERE port_code = 'IDENTITY_AUTHORITY' AND (response::text LIKE '%30000001%' OR payload::text LIKE '%30000001%'))
    UNION ALL SELECT 'webhook_log' WHERE EXISTS (SELECT 1 FROM trustride.integration_webhook_log WHERE port_code = 'IDENTITY_AUTHORITY' AND raw_payload::text LIKE '%30000001%')
    UNION ALL SELECT 'event_outbox' WHERE EXISTS (SELECT 1 FROM trustride.integration_event_outbox WHERE payload_in::text LIKE '%30000001%')) x;
  PERFORM pg_temp.t_check('live: shareholder identity numbers are kept nowhere (request, callback log, verification log, signals)', v IS NULL, coalesce(v, ''));
  SELECT (raw_response->'data'->>'shareholder_count')::int INTO n FROM trustride.integration_entity_verification_log WHERE verification_id = vid;
  PERFORM pg_temp.t_check('live: only the number of shareholders is recorded', n = 1, coalesce(n::text, 'none'));

  -- ============ the Office returns the port to the simulator while a live request is queued
  p := gen_random_uuid();
  INSERT INTO auth.users (id, email, aud, role) VALUES (p, 'idlive-sw-' || substr(p::text, 1, 8) || '@test.trustride.ke', 'authenticated', 'authenticated');
  PERFORM pg_temp.t_as(p);
  PERFORM trustride.fn_registration_capture_primary('Switch Back Person', '33333333', TRUE);
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(4);
  SELECT verification_id INTO vid FROM trustride.verification_record WHERE subject_user_id = p ORDER BY 1 DESC LIMIT 1;
  SELECT * INTO req FROM trustride.integration_outbound_request WHERE port_code = 'IDENTITY_AUTHORITY' AND ref_id = vid;
  UPDATE trustride.integration_adapter_registry SET active = FALSE WHERE port_code = 'IDENTITY_AUTHORITY' AND active;
  INSERT INTO trustride.integration_adapter_registry (port_code, adapter_type, active, notes) VALUES ('IDENTITY_AUTHORITY', 'SIMULATOR', TRUE, 'suite 29');
  PERFORM trustride.fn_integration_outbound_dispatch(req.request_id);
  PERFORM pg_temp.t_cycle(4);
  SELECT returned_status::text INTO v FROM trustride.integration_identity_verification_log WHERE verification_id = vid;
  PERFORM pg_temp.t_check('live: a queued live request answered by the simulator is never a verification (PROVIDER_UNAVAILABLE, FAILED)',
    v = 'PROVIDER_UNAVAILABLE' AND (SELECT outcome::text FROM trustride.verification_record WHERE verification_id = vid) = 'FAILED', coalesce(v, 'none'));

  PERFORM pg_temp.t_check('only service_role ingests provider callbacks',
    NOT has_function_privilege('authenticated', 'trustride.fn_integration_metamap_webhook_ingest(uuid,jsonb)', 'EXECUTE')
    AND NOT has_function_privilege('anon', 'trustride.fn_integration_metamap_webhook_ingest(uuid,jsonb)', 'EXECUTE')
    AND has_function_privilege('service_role', 'trustride.fn_integration_metamap_webhook_ingest(uuid,jsonb)', 'EXECUTE'));
  END IF;
END
$$;
