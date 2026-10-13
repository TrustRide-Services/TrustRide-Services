-- Suite 41 -- automatic catalogue access after the authorization gate (Founder direction WP9 item 3; TBOC Art.20.1:
-- Platform Access -> Registration -> Identity Verification -> Authentication -> Authorization -> User Type Profile
-- Activated -> Service Catalogue Access). Registration or sign-in alone opens nothing transactional; a verified
-- person who activates their Customer profile reaches the catalogue at once, with no manual approval; catalogue
-- management stays with the Office; service prerequisites still apply.
DO $$
DECLARE
  pend UUID; failed UUID; ok_p UUID; admin UUID; r JSONB; v TEXT; ok BOOLEAN; n INT; reg UUID; reg2 UUID; s UUID;
BEGIN
  PERFORM pg_temp.t_open_all_hours();
  admin := pg_temp.t_person('Gate Admin', NULL);  PERFORM pg_temp.t_role(admin, 'ADMINISTRATOR');

  -- ============ registered and signed in, identity not yet verified
  pend := gen_random_uuid();
  INSERT INTO auth.users (id, email, aud, role) VALUES (pend, 'gate-p-' || substr(pend::text, 1, 8) || '@test.trustride.ke', 'authenticated', 'authenticated');
  PERFORM pg_temp.t_as(pend);
  PERFORM trustride.fn_registration_capture_primary('Gate Pending Person', '31550001', TRUE);   -- verification still pending (no cycle)
  BEGIN PERFORM trustride.fn_business_actor_register(pend, 'CUSTOMER'); ok := false; v := 'registered';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%verif%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('gate: an authenticated but unverified person cannot activate a Customer profile', ok, left(v, 160));
  PERFORM pg_temp.t_admin();
  INSERT INTO trustride.business_actor_registration (user_id, user_type_domain, registration_status) VALUES (pend, 'CUSTOMER', 'ACTIVE') ON CONFLICT DO NOTHING;  -- even if a profile row existed
  PERFORM pg_temp.t_as(pend);
  BEGIN s := trustride.fn_present_shell_session_open('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', pend, 'WEB'); ok := false; v := 'opened';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%verif%'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('gate: a profile without verification does not open the Customer shell (no bypass)', ok, left(v, 160));
  PERFORM pg_temp.t_admin();
  r := pg_temp.t_cmd(pend, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', '{"service_code":"TRANSPORT-BODA-STANDARD"}');
  PERFORM pg_temp.t_check('gate: the unverified person cannot place an order', coalesce(r->>'status', '') <> 'TRANSLATED', r::text);

  -- ============ verification failed
  failed := gen_random_uuid();
  INSERT INTO auth.users (id, email, aud, role) VALUES (failed, 'gate-f-' || substr(failed::text, 1, 8) || '@test.trustride.ke', 'authenticated', 'authenticated');
  PERFORM pg_temp.t_as(failed);
  PERFORM trustride.fn_registration_capture_primary('Gate Failed Person', '00550002', TRUE);
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_as(failed);
  BEGIN PERFORM trustride.fn_business_actor_register(failed, 'CUSTOMER'); ok := false; v := 'registered';
  EXCEPTION WHEN OTHERS THEN ok := true; v := SQLERRM; END;
  PERFORM pg_temp.t_check('gate: a person whose verification failed cannot activate a profile', ok, left(v, 160));
  PERFORM pg_temp.t_admin();

  -- ============ verified: the catalogue opens automatically on profile activation
  ok_p := gen_random_uuid();
  INSERT INTO auth.users (id, email, aud, role) VALUES (ok_p, 'gate-ok-' || substr(ok_p::text, 1, 8) || '@test.trustride.ke', 'authenticated', 'authenticated');
  PERFORM pg_temp.t_as(ok_p);
  PERFORM trustride.fn_registration_capture_primary('Gate Verified Person', '31550003', TRUE);
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('gate: the identity is verified', (SELECT status FROM trustride.platform_users WHERE user_id = ok_p) = 'ACTIVE');
  PERFORM pg_temp.t_as(ok_p);
  reg := trustride.fn_business_actor_register(ok_p, 'CUSTOMER');
  reg2 := trustride.fn_business_actor_register(ok_p, 'CUSTOMER');
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('gate: the Customer profile activates at once, with no manual approval',
    (SELECT registration_status FROM trustride.business_actor_registration WHERE actor_registration_id = reg) = 'ACTIVE');
  PERFORM pg_temp.t_check('gate: activating again creates nothing new (idempotent)', reg = reg2
    AND (SELECT count(*) FROM trustride.business_actor_registration WHERE user_id = ok_p AND user_type_domain = 'CUSTOMER') = 1);
  PERFORM pg_temp.t_as(ok_p);
  s := trustride.fn_present_shell_session_open('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', ok_p, 'WEB');
  r := trustride.fn_present_projection(s, 'SERVICE_CATALOGUE', '{}');
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('gate: the verified Customer sees the catalogue automatically',
    jsonb_array_length(r->'families') >= 1, left(r::text, 120));
  PERFORM pg_temp.t_check('gate: only live services are offered (suspended, draft and retired are not)',
    NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'families') f, jsonb_array_elements(f->'services') x
                JOIN trustride.service_catalogue sc ON sc.service_code = x->>'service_code' WHERE sc.status <> 'ACTIVE'));
  r := pg_temp.t_cmd(ok_p, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02"}}]'::jsonb));
  PERFORM pg_temp.t_check('gate: ordering still needs its own prerequisite -- a verified M-Pesa phone (D3)',
    r->>'status' = 'REJECTED' AND r->>'reason' ILIKE '%phone%', r::text);
  INSERT INTO trustride.user_contact (user_id, contact_type, contact_value, is_primary, is_verified, verified_at, status)
  VALUES (ok_p, 'PHONE', '+2547' || lpad((floor(random() * 100000000))::bigint::text, 8, '0'), TRUE, TRUE, now(), 'ACTIVE');
  r := pg_temp.t_cmd(ok_p, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02"}}]'::jsonb));
  PERFORM pg_temp.t_check('gate: the verified Customer with a verified phone places an order from the catalogue', r->>'status' = 'TRANSLATED', r::text);

  -- ============ prerequisites still apply; management stays with the Office
  r := pg_temp.t_cmd(ok_p, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', '{"service_code":"TRANSPORT-NO-SUCH-SERVICE"}');
  PERFORM pg_temp.t_check('gate: a service that is not live is refused', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(ok_p, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'SUSPEND_SERVICE',
    jsonb_build_object('service_id', (SELECT service_id FROM trustride.service_catalogue WHERE service_code = 'TRANSPORT-BODA-STANDARD'), 'reason', 'x'));
  PERFORM pg_temp.t_check('gate: an authorized Customer gains no catalogue-management power', coalesce(r->>'status', '') <> 'TRANSLATED', r::text);
  r := pg_temp.t_cmd(ok_p, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'REGISTER_SERVICE', '{"service_code":"TRANSPORT-BODA-X","service_name":"X","macro_domain":"TRANSPORT","description":"x","fulfilment":"DISPATCH"}');
  PERFORM pg_temp.t_check('gate: catalogue management is not available on the Customer surface', coalesce(r->>'status', '') <> 'TRANSLATED', r::text);
  PERFORM pg_temp.t_as(ok_p);
  PERFORM pg_temp.t_check('gate: the Customer cannot read another person''s profile or orders',
    pg_temp.t_visible('person_profile', format('user_id <> %L', ok_p)) = 0 AND pg_temp.t_visible('business_order', format('requester_user_id <> %L', ok_p)) = 0);
  PERFORM pg_temp.t_admin();

  -- ============ Office staff still pass (they are verified identities with roles)
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'VIEW_REGISTER', '{}');
  PERFORM pg_temp.t_check('gate: verified Office staff are unaffected', coalesce(r->>'status', '') <> 'SESSION_REFUSED', r::text);
END
$$;
