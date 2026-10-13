-- ============================================================================
-- Founder direction (WP9 item 1): at most three incorrect identity
-- submissions per registration identity (Foundation, Engine 1).
--
-- Each failed identity check is classified on the verification record:
--   INCORRECT_DATA        the check established the submitted data is wrong --
--                         ID invalid / not found / holder deceased, names not
--                         matching the register, or the ID is held by another
--                         TrustRide identity.                          COUNTED
--   INCONCLUSIVE          provider outage, timeout, unreadable answer -- the
--                         data was never established wrong.         NOT counted
--   NOT_ACCEPTED_BY_RULE  the record was found but TrustRide's own rule cannot
--                         accept it (status unknown, no KRA PIN returned).
--                                                                   NOT counted
--   LEGACY_UNCLASSIFIED   failures recorded before this migration whose answer
--                         was not kept.                             NOT counted
-- On the third INCORRECT_DATA result every further attempt is refused in the
-- database (the retry is the only re-verification entry point; capture refuses
-- an existing registration). Counting and the block are audited with the
-- verification reference and reason class only -- no ID number, no name.
-- The Foundation audit of a verification no longer copies the provider's
-- personal fields (ID number, names, date of birth); Engine 6 keeps the
-- provider answer in its access-controlled log.
--
-- NOT DEFINED (reported for Founder decision, deliberately not invented): how
-- long the block lasts, what resets it, and who may lift it after review. The
-- block therefore stays until that decision is made.
-- ============================================================================

INSERT INTO trustride.platform_configuration (config_key, config_value, environment, effective_from, changed_by)
VALUES ('REGISTRATION_INCORRECT_ATTEMPT_LIMIT', '3', 'ALL', now(), '00000000-0000-0000-0000-000000000000');

ALTER TABLE trustride.verification_record
  ADD COLUMN failure_category TEXT CHECK (failure_category IN ('INCORRECT_DATA', 'INCONCLUSIVE', 'NOT_ACCEPTED_BY_RULE', 'LEGACY_UNCLASSIFIED')),
  ADD COLUMN failure_reason_class TEXT;

CREATE FUNCTION trustride.fn_registration_classify_failure(p_returned_status text, p_reasons text[])
 RETURNS TABLE(category text, reason_class text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
  SELECT CASE
           WHEN p_returned_status IS NULL OR p_returned_status = 'PROVIDER_UNAVAILABLE' THEN 'INCONCLUSIVE'
           WHEN p_returned_status IN ('INVALID', 'NOT_FOUND', 'DECEASED') THEN 'INCORRECT_DATA'
           WHEN 'NATIONAL_ID_HELD_BY_ANOTHER_IDENTITY' = ANY (p_reasons) THEN 'INCORRECT_DATA'
           WHEN 'REAL_LEGAL_NAMES_MISMATCH' = ANY (p_reasons) THEN 'INCORRECT_DATA'
           ELSE 'NOT_ACCEPTED_BY_RULE' END,
         CASE
           WHEN p_returned_status IS NULL OR p_returned_status = 'PROVIDER_UNAVAILABLE' THEN 'PROVIDER_UNAVAILABLE'
           WHEN p_returned_status IN ('INVALID', 'NOT_FOUND', 'DECEASED') THEN 'ID_' || p_returned_status
           WHEN 'NATIONAL_ID_HELD_BY_ANOTHER_IDENTITY' = ANY (p_reasons) THEN 'ID_HELD_BY_ANOTHER_IDENTITY'
           WHEN 'REAL_LEGAL_NAMES_MISMATCH' = ANY (p_reasons) THEN 'NAME_MISMATCH'
           ELSE coalesce(p_returned_status, 'UNKNOWN') END;
$function$;

-- Only non-personal provider fields are kept in Foundation's immutable audit.
CREATE FUNCTION trustride.fn_registration_minimise_raw(p_raw jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
  SELECT CASE WHEN p_raw IS NULL OR jsonb_typeof(p_raw) <> 'object' THEN NULL ELSE jsonb_strip_nulls(jsonb_build_object(
    'provider', p_raw->'provider', 'simulated', p_raw->'simulated', 'source', p_raw->'source', 'reason', p_raw->'reason',
    'adapter', p_raw->'adapter', 'operation', p_raw->'operation', 'error_code', p_raw->'error'->'code')) END;
$function$;

CREATE FUNCTION trustride.fn_registration_incorrect_attempts(p_user_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
  SELECT count(*)::int FROM trustride.verification_record
  WHERE subject_user_id = p_user_id AND verification_type = 'NATIONAL_ID' AND failure_category = 'INCORRECT_DATA';
$function$;

CREATE FUNCTION trustride.fn_registration_attempt_limit()
 RETURNS integer
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
  SELECT coalesce(nullif(trustride.fn_business_config('REGISTRATION_INCORRECT_ATTEMPT_LIMIT'), '')::int, 3);
$function$;

-- Verification completion: classify, count, block; minimise the audited provider answer.
DO $patch$
DECLARE
  v_def TEXT;
  a1 TEXT := E'    UPDATE trustride.verification_record SET outcome = ''FAILED'' WHERE verification_id = p_verification_id;';
  a2 TEXT := E'''raw_response'', p_raw_response)';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'trustride' AND p.proname = 'fn_verification_completed_accept';
  IF position(a1 IN v_def) = 0 OR position(a2 IN v_def) = 0 THEN RAISE EXCEPTION 'verification completion anchors not found'; END IF;
  v_def := replace(v_def, a1,
       E'    UPDATE trustride.verification_record SET outcome = ''FAILED'', failure_category = c.category, failure_reason_class = c.reason_class\n'
    || E'    FROM trustride.fn_registration_classify_failure(p_returned_status, v_reasons) c WHERE verification_id = p_verification_id;\n'
    || E'    IF (SELECT failure_category FROM trustride.verification_record WHERE verification_id = p_verification_id) = ''INCORRECT_DATA'' THEN\n'
    || E'      PERFORM trustride.fn_audit_log_append(''platform_users'', v_subject_user_id, ''REGISTRATION_VERIFICATION_ATTEMPT_COUNTED'', v_subject_user_id,\n'
    || E'        ''SYSTEM'', NULL, NULL, NULL, jsonb_build_object(''verification_id'', p_verification_id,\n'
    || E'          ''reason_class'', (SELECT failure_reason_class FROM trustride.verification_record WHERE verification_id = p_verification_id),\n'
    || E'          ''incorrect_attempts'', trustride.fn_registration_incorrect_attempts(v_subject_user_id), ''limit'', trustride.fn_registration_attempt_limit()));\n'
    || E'      IF trustride.fn_registration_incorrect_attempts(v_subject_user_id) = trustride.fn_registration_attempt_limit() THEN\n'
    || E'        PERFORM trustride.fn_audit_log_append(''platform_users'', v_subject_user_id, ''REGISTRATION_VERIFICATION_LIMIT_REACHED'', v_subject_user_id,\n'
    || E'          ''SYSTEM'', NULL, NULL, NULL, jsonb_build_object(''verification_id'', p_verification_id, ''limit'', trustride.fn_registration_attempt_limit()));\n'
    || E'      END IF;\n'
    || E'    END IF;');
  v_def := replace(v_def, a2, E'''raw_response'', trustride.fn_registration_minimise_raw(p_raw_response))');
  EXECUTE v_def;
END;
$patch$;

-- Earlier failures: classify from what Foundation recorded at the time; unknown answers are not counted.
UPDATE trustride.verification_record v SET
  failure_category = CASE WHEN a.after_snapshot ? 'returned_status' OR a.after_snapshot->'reasons' ? 'NATIONAL_ID_HELD_BY_ANOTHER_IDENTITY'
                          THEN c.category ELSE 'LEGACY_UNCLASSIFIED' END,
  failure_reason_class = c.reason_class
FROM (SELECT DISTINCT ON (al.after_snapshot->>'verification_id') al.after_snapshot
      FROM trustride.audit_log al WHERE al.action = 'REGISTRATION_PRIMARY_FAILED' ORDER BY al.after_snapshot->>'verification_id', al.chain_seq DESC) a,
     LATERAL trustride.fn_registration_classify_failure(a.after_snapshot->>'returned_status',
       ARRAY(SELECT jsonb_array_elements_text(coalesce(a.after_snapshot->'reasons', '[]'::jsonb)))) c
WHERE v.outcome = 'FAILED' AND v.verification_type = 'NATIONAL_ID' AND v.failure_category IS NULL
  AND a.after_snapshot->>'verification_id' = v.verification_id::text;
UPDATE trustride.verification_record SET failure_category = 'LEGACY_UNCLASSIFIED'
WHERE outcome = 'FAILED' AND verification_type = 'NATIONAL_ID' AND failure_category IS NULL;

-- The retry refuses once the limit is reached (checked under the identity's row lock).
DO $patch$
DECLARE
  v_def TEXT;
  a1 TEXT := E'  IF EXISTS (SELECT 1 FROM trustride.verification_record WHERE subject_user_id = v_uid AND outcome = ''PENDING'') THEN';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_registration_retry_primary(text,text)'::regprocedure) INTO v_def;
  IF position(a1 IN v_def) = 0 THEN RAISE EXCEPTION 'retry anchor not found'; END IF;
  EXECUTE replace(v_def, a1,
       E'  IF trustride.fn_registration_incorrect_attempts(v_uid) >= trustride.fn_registration_attempt_limit() THEN\n'
    || E'    RAISE EXCEPTION ''Identity verification is blocked: three submissions were found incorrect. Contact TrustRide support -- the review process is being defined.'';\n'
    || E'  END IF;\n'
    || a1);
END;
$patch$;

CREATE OR REPLACE FUNCTION trustride.fn_my_registration_retry_options()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_status TEXT;
  v_last RECORD;
  v_pending BOOLEAN;
  v_profile RECORD;
  v_count INT;
  v_limit INT := trustride.fn_registration_attempt_limit();
  v_locked BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RETURN NULL; END IF;
  SELECT status INTO v_status FROM trustride.platform_users WHERE user_id = v_uid;
  SELECT * INTO v_last FROM trustride.fn_registration_last_result(v_uid);
  SELECT legal_name, national_id_ref INTO v_profile FROM trustride.person_profile WHERE user_id = v_uid;
  v_pending := EXISTS (SELECT 1 FROM trustride.verification_record WHERE subject_user_id = v_uid AND outcome = 'PENDING');
  v_count := trustride.fn_registration_incorrect_attempts(v_uid);
  v_locked := v_count >= v_limit;
  RETURN jsonb_build_object(
    'status', v_status,
    'retryable', v_status = 'VERIFICATION_FAILED' AND NOT v_pending AND NOT v_locked,
    'same_details_allowed', v_status = 'VERIFICATION_FAILED' AND NOT v_pending AND NOT v_locked AND v_last.returned_status = 'PROVIDER_UNAVAILABLE',
    'last_result', v_last.returned_status,
    'reasons', coalesce(v_last.reasons, '[]'::jsonb),
    'incorrect_attempts', v_count,
    'attempts_remaining', greatest(v_limit - v_count, 0),
    'attempt_limit', v_limit,
    'locked', v_locked,
    'legal_name', v_profile.legal_name,
    'national_id_masked', CASE WHEN v_profile.national_id_ref IS NULL THEN NULL ELSE '****' || right(v_profile.national_id_ref, 4) END);
END;
$function$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
