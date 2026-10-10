-- ============================================================================
-- Platform -- every identity, contact, authority and decision write is audited
-- TRS026-ENG-REMEDIATION-001, finding D17
-- ============================================================================
-- Forensic audit 2026-10-08: contact removal, primary change and channel
-- preferences (including the phone M-Pesa debits), KRA PIN declaration,
-- system-credential revocation, entity membership, Office actor-request and
-- advisory decisions, and notification read-marking left no audit record,
-- so a change of the payment phone could not be traced to who and when.
--
-- Correction:
--   * fn_platform_audit_row_change, an AFTER trigger, appends one audit_log
--     row per insert, update or delete on the audited tables, naming the
--     signed-in caller (or SYSTEM) and carrying before/after snapshots.
--     Phones and identifiers are masked to their last three characters and
--     key hashes are dropped. Because it sits on the table, every writer --
--     today's functions and any future one -- is covered.
--   * fn_platform_audited_tables() is the register; conformance refuses a
--     registered table without the trigger.
--   * System credentials are audited on issue, revocation and change of
--     scope or expiry, not on each use (last_used_at).
--   * Read-marking is one audit row per call with the count marked.
-- Existing function-level audit entries (business actions such as
-- CONTACT_ADDED) are kept; the trigger adds the row-level record beside them.
-- ============================================================================

CREATE FUNCTION trustride.fn_platform_audited_tables()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT ARRAY['user_contact', 'user_contact_preference', 'user_identifier', 'entity_membership', 'entity_system_credential',
               'role_assignment', 'advisory_recommendation_outcome', 'business_actor_registration', 'business_partner_agreement']::TEXT[];
$function$;

-- TG_ARGV[0] = primary key column; further arguments: a column to mask, or
-- '-column' to leave out of the snapshot.
CREATE FUNCTION trustride.fn_platform_audit_row_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_old JSONB;
  v_new JSONB;
  v_id  UUID;
  k     TEXT;
  i     INTEGER;
BEGIN
  IF TG_OP <> 'INSERT' THEN v_old := to_jsonb(OLD); END IF;
  IF TG_OP <> 'DELETE' THEN v_new := to_jsonb(NEW); END IF;
  v_id := (coalesce(v_new, v_old) ->> TG_ARGV[0])::uuid;
  FOR i IN 1 .. TG_NARGS - 1 LOOP
    k := TG_ARGV[i];
    IF left(k, 1) = '-' THEN
      v_old := v_old - substr(k, 2);
      v_new := v_new - substr(k, 2);
    ELSE
      IF v_old ->> k IS NOT NULL THEN
        v_old := jsonb_set(v_old, ARRAY[k], to_jsonb(repeat('*', greatest(length(v_old ->> k) - 3, 0)) || right(v_old ->> k, 3)));
      END IF;
      IF v_new ->> k IS NOT NULL THEN
        v_new := jsonb_set(v_new, ARRAY[k], to_jsonb(repeat('*', greatest(length(v_new ->> k) - 3, 0)) || right(v_new ->> k, 3)));
      END IF;
    END IF;
  END LOOP;
  PERFORM trustride.fn_audit_log_append(TG_TABLE_NAME, v_id, TG_OP, auth.uid(),
    CASE WHEN auth.uid() IS NULL THEN 'SYSTEM' ELSE 'USER' END, NULL, NULL, v_old, v_new);
  RETURN NULL;
END;
$function$;

CREATE TRIGGER trg_user_contact_audit AFTER INSERT OR UPDATE OR DELETE ON trustride.user_contact
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_platform_audit_row_change('contact_id', 'contact_value');
CREATE TRIGGER trg_user_contact_preference_audit AFTER INSERT OR UPDATE OR DELETE ON trustride.user_contact_preference
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_platform_audit_row_change('preference_id');
CREATE TRIGGER trg_user_identifier_audit AFTER INSERT OR UPDATE OR DELETE ON trustride.user_identifier
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_platform_audit_row_change('identifier_id', 'identifier_value');
CREATE TRIGGER trg_entity_membership_audit AFTER INSERT OR UPDATE OR DELETE ON trustride.entity_membership
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_platform_audit_row_change('membership_id');
CREATE TRIGGER trg_entity_system_credential_audit AFTER INSERT OR DELETE ON trustride.entity_system_credential
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_platform_audit_row_change('credential_id', '-key_hash');
CREATE TRIGGER trg_entity_system_credential_change_audit AFTER UPDATE ON trustride.entity_system_credential
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status OR OLD.revoked_at IS DISTINCT FROM NEW.revoked_at
                     OR OLD.scopes IS DISTINCT FROM NEW.scopes OR OLD.expires_at IS DISTINCT FROM NEW.expires_at)
  EXECUTE FUNCTION trustride.fn_platform_audit_row_change('credential_id', '-key_hash');
CREATE TRIGGER trg_role_assignment_audit AFTER INSERT OR UPDATE OR DELETE ON trustride.role_assignment
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_platform_audit_row_change('assignment_id');
CREATE TRIGGER trg_advisory_recommendation_outcome_audit AFTER INSERT OR UPDATE OR DELETE ON trustride.advisory_recommendation_outcome
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_platform_audit_row_change('outcome_id');
CREATE TRIGGER trg_business_actor_registration_audit AFTER INSERT OR UPDATE OR DELETE ON trustride.business_actor_registration
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_platform_audit_row_change('actor_registration_id');
CREATE TRIGGER trg_business_partner_agreement_audit AFTER INSERT OR UPDATE OR DELETE ON trustride.business_partner_agreement
  FOR EACH ROW EXECUTE FUNCTION trustride.fn_platform_audit_row_change('partner_agreement_id');

-- Read-marking: one record per call.
DO $patch$
DECLARE
  v_def TEXT;
  v_old TEXT := E'  GET DIAGNOSTICS n = ROW_COUNT;\n  RETURN n;\n';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_present_notifications_mark_read(uuid)'::regprocedure) INTO v_def;
  IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'mark_read tail not found'; END IF;
  v_def := replace(v_def, v_old, E'  GET DIAGNOSTICS n = ROW_COUNT;\n'
    || E'  IF n > 0 THEN\n'
    || E'    PERFORM trustride.fn_audit_log_append(''present_notification_inbox'', p_session, ''NOTIFICATIONS_MARKED_READ'', auth.uid(), ''USER'', NULL, NULL, NULL,\n'
    || E'      jsonb_build_object(''marked_read'', n));\n'
    || E'  END IF;\n'
    || E'  RETURN n;\n');
  EXECUTE v_def;
END;
$patch$;

-- Systemic guard.
DO $patch$
DECLARE
  v_def TEXT;
  v_old TEXT := E'         AND EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = c.oid AND t.tgfoid = ''trustride.fn_platform_audit_chain_append_only''::regproc AND t.tgenabled = ''O''));\n$function$';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_platform_conformance_violations()'::regprocedure) INTO v_def;
  IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'conformance tail not found'; END IF;
  v_def := replace(v_def, v_old, E'         AND EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = c.oid AND t.tgfoid = ''trustride.fn_platform_audit_chain_append_only''::regproc AND t.tgenabled = ''O''))\n'
    || E'  UNION ALL\n'
    || E'  -- Every table on the audited register writes its changes to the audit log.\n'
    || E'  SELECT ''AUDITED_TABLE_WITHOUT_TRIGGER'', a.t, ''registered as audited but carries no enabled fn_platform_audit_row_change trigger''\n'
    || E'  FROM unnest(trustride.fn_platform_audited_tables()) a(t)\n'
    || E'  WHERE NOT EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid\n'
    || E'                    WHERE c.relnamespace = ''trustride''::regnamespace AND c.relname = a.t\n'
    || E'                      AND t.tgfoid = ''trustride.fn_platform_audit_row_change''::regproc AND t.tgenabled = ''O'');\n$function$');
  EXECUTE v_def;
END;
$patch$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
