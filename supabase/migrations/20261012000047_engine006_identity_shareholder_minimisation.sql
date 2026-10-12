-- ============================================================================
-- TRS026 Construction Directive WP7 (section 2.6) -- Engine 6 identity answers
-- keep no shareholder identity numbers; a late answer is not reported applied.
--
-- Found by suite 29 after 046 reached staging:
--   * MetaMap's BRS answer nests shareholders (name, ID type and ID number) under
--     data.shareHolders. 046 removed them from the verification log only; the
--     outbound request kept the provider answer whole and the callback log
--     stripped a top-level key that BRS does not use. Shareholders are not the
--     subject of the verification, so TrustRide keeps only their number (Data
--     Protection Act 2019 s.25(c), data minimisation).
--   * A provider answer arriving after TrustRide gave up (request FAILED, the
--     verification completed PROVIDER_UNAVAILABLE) was answered APPLIED although
--     nothing was applied. It is now ALREADY_FINAL; the person retries.
-- ============================================================================

CREATE FUNCTION trustride.fn_integration_identity_minimise(p_body jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'trustride', 'public'
AS $function$
  SELECT CASE
    WHEN p_body IS NULL OR jsonb_typeof(p_body) <> 'object' THEN p_body
    WHEN jsonb_typeof(p_body->'data') = 'object' AND (p_body->'data'->'shareHolders') IS NOT NULL THEN
      jsonb_set(p_body - 'shareHolders', '{data}', ((p_body->'data') - 'shareHolders')
        || jsonb_build_object('shareholder_count', CASE WHEN jsonb_typeof(p_body->'data'->'shareHolders') = 'array'
                                                        THEN jsonb_array_length(p_body->'data'->'shareHolders') ELSE 0 END))
    ELSE p_body - 'shareHolders'
  END;
$function$;

-- The provider answer stored on the outbound request is minimised as soon as it is applied.
DO $patch$
DECLARE
  v_def TEXT;
  v_old TEXT := E'IF NOT (p_final_success OR p_final_failure) THEN RETURN ''PENDING''; END IF;';
BEGIN
  SELECT pg_get_functiondef('trustride.fn_integration_identity_apply_outcome(trustride.integration_outbound_request,boolean,boolean)'::regprocedure) INTO v_def;
  IF position(v_old IN v_def) = 0 THEN RAISE EXCEPTION 'identity outcome anchor not found'; END IF;
  EXECUTE replace(v_def, v_old, v_old
    || E'\n  UPDATE trustride.integration_outbound_request SET response = trustride.fn_integration_identity_minimise(response)\n'
    || E'  WHERE request_id = p_request.request_id AND response IS DISTINCT FROM trustride.fn_integration_identity_minimise(response);');
END;
$patch$;

CREATE OR REPLACE FUNCTION trustride.fn_integration_metamap_webhook_ingest(p_request_id uuid, p_body jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
DECLARE
  v_req trustride.integration_outbound_request;
  v_webhook UUID;
  v_result TEXT;
BEGIN
  INSERT INTO trustride.integration_webhook_log (port_code, provider_reference, signature_valid, raw_payload, processed)
  VALUES ('IDENTITY_AUTHORITY', p_request_id::text, TRUE, trustride.fn_integration_identity_minimise(p_body), FALSE) RETURNING webhook_id INTO v_webhook;
  SELECT * INTO v_req FROM trustride.integration_outbound_request WHERE request_id = p_request_id AND port_code = 'IDENTITY_AUTHORITY';
  v_result := CASE WHEN v_req.request_id IS NULL THEN 'UNKNOWN_REQUEST'
                   WHEN v_req.status = 'SUCCEEDED' THEN 'ALREADY_APPLIED'
                   WHEN v_req.status = 'FAILED' THEN 'ALREADY_FINAL'   -- TrustRide gave up; the verification completed PROVIDER_UNAVAILABLE
                   ELSE 'APPLIED' END;
  IF v_result = 'APPLIED' THEN
    PERFORM trustride.fn_integration_outbound_result(p_request_id, TRUE, coalesce(p_body->>'id', p_request_id::text), p_body, NULL);
  END IF;
  UPDATE trustride.integration_webhook_log SET processed = TRUE, processed_at = now() WHERE webhook_id = v_webhook;
  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_integration_metamap_webhook_ingest(uuid, jsonb) TO service_role;
SELECT trustride.fn_platform_conformance_assert();
