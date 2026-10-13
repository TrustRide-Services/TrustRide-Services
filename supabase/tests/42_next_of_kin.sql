-- Suite 42 -- next of kin on the Foundation relationship model (FDN-001 record 034, user_relationship;
-- Founder ruling 2026-08-23 Step 3.3; Founder direction WP9 item 2). The next of kin is a registered, verified
-- TrustRide identity related to the principal by a governed NEXT_OF_KIN relationship -- never a free-text note.
-- Being named grants the kin no access to the principal's data or account. The Office may reveal the kin's
-- name and verified phone only to follow up on an open matter of an unreachable principal, with a reason;
-- every nomination, change, decline and reveal is audited without contact details.
DO $$
DECLARE
  p UUID; k UUID; k2 UUID; other UUID; admin UUID; exec_ UUID; rel UUID; rel2 UUID; r JSONB; v TEXT; ok BOOLEAN; n INT;
  kphone TEXT := '+2547' || lpad((floor(random() * 100000000))::bigint::text, 8, '0');
  k2phone TEXT := '+2547' || lpad((floor(random() * 100000000))::bigint::text, 8, '0');
  cs UUID;
  ready BOOLEAN := to_regprocedure('trustride.fn_next_of_kin_nominate(text,text)') IS NOT NULL;
BEGIN
  IF NOT ready THEN
    PERFORM pg_temp.t_check('next-of-kin workflow exists', false, 'fn_next_of_kin_nominate absent');
  ELSE
  p := pg_temp.t_customer('Principal Person');
  k := pg_temp.t_person('Kin Person One', NULL);
  INSERT INTO trustride.user_contact (user_id, contact_type, contact_value, is_primary, is_verified, verified_at, status) VALUES (k, 'PHONE', kphone, TRUE, TRUE, now(), 'ACTIVE');
  k2 := pg_temp.t_person('Kin Person Two', NULL);
  INSERT INTO trustride.user_contact (user_id, contact_type, contact_value, is_primary, is_verified, verified_at, status) VALUES (k2, 'PHONE', k2phone, TRUE, TRUE, now(), 'ACTIVE');
  other := pg_temp.t_customer('Unrelated Person');
  admin := pg_temp.t_person('Kin Admin', NULL);  PERFORM pg_temp.t_role(admin, 'ADMINISTRATOR');
  exec_ := pg_temp.t_person('Kin Exec', NULL);  PERFORM pg_temp.t_role(exec_, 'EXECUTIVE');

  -- ============ nomination
  PERFORM pg_temp.t_as(p);
  rel := trustride.fn_next_of_kin_nominate('0' || substr(kphone, 5), 'kin person one');
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('kin: a verified identity is named next of kin by phone and full name (any phone format)',
    EXISTS (SELECT 1 FROM trustride.user_relationship WHERE relationship_id = rel AND user_id = p AND related_user_id = k
            AND relationship_type = 'NEXT_OF_KIN' AND valid_to IS NULL));
  PERFORM pg_temp.t_check('kin: the nomination is audited without the phone number',
    EXISTS (SELECT 1 FROM trustride.audit_log WHERE entity_id = rel AND action = 'NEXT_OF_KIN_NOMINATED' AND actor_id = p
            AND after_snapshot::text NOT LIKE '%' || substr(kphone, 5) || '%'));
  PERFORM pg_temp.t_check('kin: the named person is told, and how to decline',
    EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = k AND title ILIKE '%next of kin%'));
  PERFORM pg_temp.t_as(p);
  rel2 := trustride.fn_next_of_kin_nominate(kphone, 'Kin Person One');
  PERFORM pg_temp.t_check('kin: naming the same person again changes nothing', rel2 = rel);
  r := trustride.fn_my_next_of_kin();
  PERFORM pg_temp.t_check('kin: the principal sees whom they named', r->'nominated'->>'display_name' = 'Kin Person One', r::text);

  -- ============ invalid nominations (one message, so phone numbers cannot be probed)
  FOR v IN SELECT unnest(ARRAY[
      format('SELECT trustride.fn_next_of_kin_nominate(%L, %L)', kphone, 'Wrong Name'),
      'SELECT trustride.fn_next_of_kin_nominate(''+254700000001'', ''Nobody Here'')']) LOOP
    BEGIN EXECUTE v; ok := false;
    EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE 'No verified TrustRide identity matches%'; END;
    PERFORM pg_temp.t_check('kin: refused without revealing whether the phone is registered: ' || left(v, 70), ok);
  END LOOP;
  BEGIN PERFORM trustride.fn_next_of_kin_nominate('not a phone', 'Kin Person One'); ok := false; v := 'accepted';
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM !~* 'no verified TrustRide identity' AND SQLERRM ~* '(phone|mobile number)'; v := SQLERRM; END;
  PERFORM pg_temp.t_check('kin: a malformed phone number gets a format message (it reveals nothing about registration)', ok, left(v, 160));
  BEGIN PERFORM trustride.fn_next_of_kin_nominate((SELECT contact_value FROM trustride.user_contact WHERE user_id = p AND contact_type = 'PHONE' LIMIT 1), 'Principal Person'); ok := false;
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM pg_temp.t_check('kin: a person cannot name themselves', ok);
  PERFORM pg_temp.t_admin();
  UPDATE trustride.platform_users SET status = 'SUSPENDED' WHERE user_id = k2;
  PERFORM pg_temp.t_as(p);
  BEGIN PERFORM trustride.fn_next_of_kin_nominate(k2phone, 'Kin Person Two'); ok := false;
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM pg_temp.t_check('kin: a suspended identity cannot be named', ok);
  PERFORM pg_temp.t_admin();
  UPDATE trustride.platform_users SET status = 'ACTIVE' WHERE user_id = k2;
  PERFORM pg_temp.t_check('kin: a person cannot relate to themselves at all (database constraint)',
    pg_temp.t_fails(format('INSERT INTO trustride.user_relationship (user_id, related_user_id, relationship_type) VALUES (%L, %L, ''NEXT_OF_KIN'')', p, p)));

  -- ============ replacement keeps history; one active next of kin
  PERFORM pg_temp.t_as(p);
  rel2 := trustride.fn_next_of_kin_nominate(k2phone, 'Kin Person Two');
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('kin: naming someone else replaces the next of kin and keeps the old one as history',
    (SELECT valid_to FROM trustride.user_relationship WHERE relationship_id = rel) IS NOT NULL
    AND (SELECT count(*) FROM trustride.user_relationship WHERE user_id = p AND relationship_type = 'NEXT_OF_KIN' AND valid_to IS NULL) = 1);
  PERFORM pg_temp.t_check('kin: only one active next of kin (database constraint)',
    pg_temp.t_fails(format('INSERT INTO trustride.user_relationship (user_id, related_user_id, relationship_type) VALUES (%L, %L, ''NEXT_OF_KIN'')', p, k)));

  -- ============ the kin gains no access
  PERFORM pg_temp.t_as(k2);
  r := trustride.fn_my_next_of_kin();
  PERFORM pg_temp.t_check('kin: the named person sees who named them -- and nothing else',
    jsonb_array_length(r->'named_by') = 1 AND r->'named_by'->0->>'display_name' = 'Principal Person'
    AND NOT (r::text ILIKE '%phone%'), r::text);
  PERFORM pg_temp.t_check('kin: the named person cannot read the principal''s profile, contacts, orders or address',
    pg_temp.t_visible('person_profile', format('user_id = %L', p)) = 0 AND pg_temp.t_visible('user_contact', format('user_id = %L', p)) = 0
    AND pg_temp.t_visible('business_order', format('requester_user_id = %L', p)) = 0 AND pg_temp.t_visible('user_address', format('user_id = %L', p)) = 0);
  BEGIN PERFORM trustride.fn_present_shell_session_open('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', p, 'WEB'); ok := false;
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM pg_temp.t_check('kin: the named person cannot act for the principal (no session as them)', ok);
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_as(other);
  PERFORM pg_temp.t_check('kin: an unrelated person cannot see the relationship', pg_temp.t_visible('user_relationship', format('user_id = %L', p)) = 0);
  BEGIN PERFORM trustride.fn_next_of_kin_decline(rel2); ok := false;
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM pg_temp.t_check('kin: an unrelated person cannot decline someone else''s nomination', ok);
  PERFORM pg_temp.t_admin();

  -- ============ operational fallback: the Office reveals the kin for an open matter
  INSERT INTO trustride.business_support_case (case_code, opened_by_user_id, category, severity, subject, sla_due_at)
  VALUES ('SUP-KIN-' || substr(md5(random()::text), 1, 6), p, 'OPERATOR_PROBLEM', 'HIGH', 'Customer unreachable during an assistant engagement', now() + interval '4 hours')
  RETURNING case_id INTO cs;
  PERFORM pg_temp.t_as(admin);
  BEGIN r := trustride.fn_office_next_of_kin_reveal(p, 'short', cs::text); ok := false;
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM pg_temp.t_check('kin: the Office must state a real reason', ok);
  BEGIN r := trustride.fn_office_next_of_kin_reveal(p, 'Customer unreachable for two hours during an engagement', gen_random_uuid()::text); ok := false;
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM pg_temp.t_check('kin: the Office must refer to an open matter of this person', ok);
  r := trustride.fn_office_next_of_kin_reveal(p, 'Customer unreachable for two hours during an engagement', cs::text);
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('kin: for an open support case the Office sees the kin''s name and verified phone',
    r->>'display_name' = 'Kin Person Two' AND r->>'phone' = k2phone, r::text);
  PERFORM pg_temp.t_check('kin: the reveal is audited with reason and matter, not the phone',
    EXISTS (SELECT 1 FROM trustride.audit_log WHERE entity_id = p AND action = 'NEXT_OF_KIN_CONTACT_REVEALED' AND actor_id = admin
            AND after_snapshot->>'reference' = cs::text AND after_snapshot::text NOT LIKE '%' || substr(k2phone, 5) || '%'));
  PERFORM pg_temp.t_as(exec_);
  BEGIN r := trustride.fn_office_next_of_kin_reveal(p, 'Customer unreachable for two hours during an engagement', cs::text); ok := false;
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM pg_temp.t_check('kin: an Executive cannot reveal next-of-kin details', ok);
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_as(other);
  BEGIN r := trustride.fn_office_next_of_kin_reveal(p, 'Customer unreachable for two hours during an engagement', cs::text); ok := false;
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM pg_temp.t_check('kin: a customer cannot reveal next-of-kin details', ok);
  PERFORM pg_temp.t_admin();

  -- ============ decline and end
  PERFORM pg_temp.t_as(k2);
  PERFORM trustride.fn_next_of_kin_decline(rel2);
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('kin: the named person can decline; the principal is told; it is audited',
    (SELECT valid_to FROM trustride.user_relationship WHERE relationship_id = rel2) IS NOT NULL
    AND EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = p AND title ILIKE '%next of kin%declined%')
    AND EXISTS (SELECT 1 FROM trustride.audit_log WHERE entity_id = rel2 AND action = 'NEXT_OF_KIN_DECLINED' AND actor_id = k2));
  PERFORM pg_temp.t_as(admin);
  r := trustride.fn_office_next_of_kin_reveal(p, 'Customer unreachable for two hours during an engagement', cs::text);
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('kin: with no active next of kin the Office is told there is none', r->>'display_name' IS NULL AND (r->>'none')::boolean, r::text);
  PERFORM pg_temp.t_as(p);
  rel := trustride.fn_next_of_kin_nominate(kphone, 'Kin Person One');
  PERFORM trustride.fn_next_of_kin_end();
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('kin: the principal can remove their next of kin (audited)',
    NOT EXISTS (SELECT 1 FROM trustride.user_relationship WHERE user_id = p AND relationship_type = 'NEXT_OF_KIN' AND valid_to IS NULL)
    AND EXISTS (SELECT 1 FROM trustride.audit_log WHERE entity_id = rel AND action = 'NEXT_OF_KIN_ENDED' AND actor_id = p));

  -- ============ no free-text substitute; access
  PERFORM pg_temp.t_as(p);
  PERFORM pg_temp.t_check('kin: the free-text next-of-kin note path stays closed',
    pg_temp.t_fails('SELECT trustride.fn_secondary_profile_submit(''RELATIONSHIP'', ''{"name":"X","contact":"0712000000"}'')'));
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('kin: nobody unauthenticated can nominate', pg_temp.t_fails(format('SELECT trustride.fn_next_of_kin_nominate(%L, ''Kin Person One'')', kphone)));
  PERFORM pg_temp.t_check('kin: no anonymous access to the reveal', NOT has_function_privilege('anon', 'trustride.fn_office_next_of_kin_reveal(uuid,text,text)', 'EXECUTE'));
  END IF;
END
$$;
