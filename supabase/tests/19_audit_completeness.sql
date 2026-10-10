-- Suite 19 -- every identity, contact, authority and decision write is on the audit record
-- (TRS026-ENG-REMEDIATION-001: D17). Each write names who made it and when;
-- phones, identifiers and keys are never stored in clear in the audit log.
DO $$
DECLARE
  cust UUID; founder UUID; c2 UUID; sys UUID; v_key TEXT; sess UUID; n INT; v TEXT; t0 TIMESTAMPTZ := clock_timestamp();
  tbl TEXT;
BEGIN
  cust := pg_temp.t_customer('Audit Cust');
  founder := pg_temp.t_person('Audit Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');

  -- ============ the M-Pesa phone and every contact change
  PERFORM pg_temp.t_as(cust);
  c2 := trustride.fn_user_contact_add('PHONE', '0722 000 111');
  PERFORM trustride.fn_user_contact_preference_set('SMS', FALSE);
  PERFORM trustride.fn_user_contact_remove(c2);
  PERFORM trustride.fn_registration_declare_kra_pin('A009876543Z');
  PERFORM pg_temp.t_admin();
  FOREACH tbl IN ARRAY ARRAY['user_contact', 'user_contact_preference', 'user_identifier'] LOOP
    SELECT count(*) INTO n FROM trustride.audit_log WHERE entity_type = tbl AND actor_id = cust;
    PERFORM pg_temp.t_check('D17 a change to ' || tbl || ' is audited with the customer as actor', n > 0, n::text);
  END LOOP;
  SELECT count(*) INTO n FROM trustride.audit_log WHERE entity_type = 'user_contact' AND entity_id = c2 AND action = 'UPDATE' AND actor_id = cust;
  PERFORM pg_temp.t_check('D17 removing a phone is audited (who, which contact, when)', n > 0, n::text);

  -- ============ Office authority changes
  PERFORM pg_temp.t_as(founder);
  sys := trustride.fn_registration_capture_external_system('AuditTrack', 'GPS telemetry for audit');
  v_key := trustride.fn_external_system_credential_issue(sys, ARRAY['TELEMETRY_INGEST']);
  PERFORM trustride.fn_external_system_credential_revoke(split_part(v_key, '.', 1));
  PERFORM pg_temp.t_admin();
  SELECT count(*) INTO n FROM trustride.audit_log WHERE entity_type = 'entity_system_credential' AND action = 'UPDATE' AND actor_id = founder;
  PERFORM pg_temp.t_check('D17 revoking a system credential is audited with the Founder as actor', n > 0, n::text);
  PERFORM trustride.fn_external_system_authenticate(v_key, 'TELEMETRY_INGEST');
  SELECT count(*) INTO n FROM trustride.audit_log WHERE entity_type = 'entity_system_credential' AND occurred_at >= t0;
  PERFORM pg_temp.t_check('D17 credential use (last_used_at) does not flood the audit log', n <= 2, n::text);

  -- ============ notification read-marking
  INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, category)
  VALUES (cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'Audit', 'read me', 'GENERAL');
  PERFORM pg_temp.t_as(cust);
  sess := trustride.fn_present_shell_session_open('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', cust, 'WEB');
  PERFORM trustride.fn_present_notifications_mark_read(sess);
  PERFORM pg_temp.t_admin();
  SELECT count(*) INTO n FROM trustride.audit_log WHERE action = 'NOTIFICATIONS_MARKED_READ' AND actor_id = cust;
  PERFORM pg_temp.t_check('D17 marking notifications read is audited', n = 1, n::text);

  -- ============ privacy and the systemic guard
  SELECT count(*) INTO n FROM trustride.audit_log
  WHERE occurred_at >= t0 AND (coalesce(before_snapshot::text, '') || coalesce(after_snapshot::text, '')) ~ '(\+?2547[0-9]{8}|A009876543Z|key_hash)';
  PERFORM pg_temp.t_check('D17 no phone, KRA PIN or key hash in clear in the audit log', n = 0, n::text);
  SELECT count(*), string_agg(object_name, ' ') INTO n, v FROM trustride.fn_platform_conformance_violations() WHERE check_code = 'AUDITED_TABLE_WITHOUT_TRIGGER';
  PERFORM pg_temp.t_check('systemic: every table on the audited register carries the audit trigger (conformance)',
    pg_get_functiondef('trustride.fn_platform_conformance_violations()'::regprocedure) LIKE '%AUDITED_TABLE_WITHOUT_TRIGGER%' AND n = 0, coalesce(v, ''));
END
$$;
