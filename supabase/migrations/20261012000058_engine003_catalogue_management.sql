-- ============================================================================
-- TRS026 Construction Directive 2.11 (WP8) -- catalogue management and its
-- cost-registry linkage (Engine 3, with Engine 11 commands; Engine 5 read only).
--
-- fn_service_catalogue_register / _activate and fn_service_coverage_zone_add had
-- no presentation path (D20); catalogue changes needed SQL. Rules, all taken from
-- the existing data and specifications:
--   * the Office registers DISPATCH services only. INTAKE and MARKETPLACE services
--     are TBOC Art.18 special intents with their own fixed commands; a new one is
--     a constitutional matter, not a catalogue edit;
--   * five macro domains only (Engine 3 boundary 5); an Executive Assistant service
--     names its pillar (Art.27) and a skill category Engine 5 rates
--     (cost_ea_trade_occupation, read only);
--   * activation (DRAFT or SUSPENDED -> ACTIVE) needs active coverage and, for every
--     covered jurisdiction, an ACTIVE Engine 5 cost_registry row for the service
--     code -- the price comes from Engine 5 or the service is not offered;
--   * suspension (ACTIVE -> SUSPENDED, reason required) stops new orders (Engine 3
--     resolves only ACTIVE services); orders already placed continue;
--   * retirement (DRAFT or SUSPENDED -> RETIRED, terminal) needs no open orders;
--   * every transition is audited with the person and broadcast as
--     SERVICE_CATALOGUE_UPDATED; repeating a transition changes nothing;
--   * Founder or Administrator, through the Admin Console only.
-- No governance approval chain is wired (approval_request has no workflow);
-- approved_request_id stays empty -- noted for the Founder.
-- ============================================================================

CREATE FUNCTION trustride.fn_service_catalogue_office_check()
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN
    RAISE EXCEPTION 'Only TrustRide Office (Founder or Administrator) manages the service catalogue';
  END IF;
END;
$function$;

CREATE FUNCTION trustride.fn_service_catalogue_broadcast(p_service_id uuid, p_status text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
  INSERT INTO trustride.service_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (gen_random_uuid(), 'TRS026_ENG011_PRESENT', 'SERVICE_CATALOGUE_UPDATED',
    jsonb_build_object('service_id', p_service_id, 'status', p_status, 'effective_from', now()),
    'SERVICE_CATALOGUE_UPDATED:' || p_service_id::text || ':' || p_status || ':' || clock_timestamp()::text);
$function$;

-- Open orders for a service: Engine 4 records Engine 3's service_id on each order (read only).
CREATE FUNCTION trustride.fn_service_open_orders(p_service_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
  SELECT count(*)::int FROM trustride.business_order
  WHERE service_id = p_service_id AND status NOT IN ('SETTLED', 'REVIEWED', 'CLOSED', 'CANCELLED', 'EXPIRED', 'FAILED', 'DECLINED');
$function$;

-- Why a service cannot be activated (empty = it can).
CREATE FUNCTION trustride.fn_service_catalogue_activation_blockers(p_service_id uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
  SELECT CASE WHEN sc.service_id IS NULL THEN ARRAY['Unknown service']
    ELSE array_remove(ARRAY[
      CASE WHEN sc.status NOT IN ('DRAFT', 'SUSPENDED', 'ACTIVE') THEN 'A ' || lower(sc.status::text) || ' service cannot be activated' END,
      CASE WHEN NOT EXISTS (SELECT 1 FROM trustride.service_coverage_zone cz WHERE cz.service_id = sc.service_id AND cz.active AND cz.effective_to IS NULL)
           THEN 'No coverage: add the jurisdictions where it is offered' END,
      CASE WHEN EXISTS (SELECT 1 FROM trustride.service_catalogue o WHERE o.service_code = sc.service_code AND o.status = 'ACTIVE' AND o.service_id <> sc.service_id)
           THEN 'Another active service uses this code' END]
      || coalesce((SELECT array_agg('No Engine 5 pricing (cost registry) for ' || cz.jurisdiction ORDER BY cz.jurisdiction)
                   FROM trustride.service_coverage_zone cz
                   WHERE cz.service_id = sc.service_id AND cz.active AND cz.effective_to IS NULL
                     AND sc.requirements->>'fulfilment' = 'DISPATCH'
                     AND NOT EXISTS (SELECT 1 FROM trustride.cost_registry reg WHERE reg.service_code = sc.service_code
                                     AND reg.jurisdiction::text = cz.jurisdiction AND reg.status = 'ACTIVE')), ARRAY[]::text[]), NULL) END
  FROM (SELECT NULL) d LEFT JOIN trustride.service_catalogue sc ON sc.service_id = p_service_id;
$function$;

CREATE FUNCTION trustride.fn_service_catalogue_office_register(p_service_code text, p_service_name text, p_macro_domain text, p_description text,
  p_fulfilment text, p_pillar text DEFAULT NULL, p_ea_skill_category text DEFAULT NULL, p_eligibility_summary text DEFAULT NULL)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_code TEXT := upper(trim(coalesce(p_service_code, '')));
  v_domain trustride.service_macro_domain_enum;
  v_req JSONB;
  v_id UUID;
BEGIN
  PERFORM trustride.fn_service_catalogue_office_check();
  IF v_code !~ '^[A-Z0-9]+(-[A-Z0-9_]+)+$' THEN
    RAISE EXCEPTION 'Service code must look like DOMAIN-LINE-VARIANT in capitals (e.g. TRANSPORT-BODA-EXPRESS)';
  END IF;
  IF coalesce(trim(p_service_name), '') = '' OR coalesce(trim(p_description), '') = '' THEN
    RAISE EXCEPTION 'A service needs its name and description';
  END IF;
  BEGIN v_domain := upper(trim(p_macro_domain))::trustride.service_macro_domain_enum;
  EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'Unknown macro domain % -- TrustRide offers five (TBOC Art.23)', coalesce(p_macro_domain, 'nothing'); END;
  IF coalesce(upper(p_fulfilment), '') <> 'DISPATCH' THEN
    RAISE EXCEPTION 'Only dispatched services are added from the Office; intake and marketplace services are the fixed special intents of TBOC Art.18';
  END IF;
  IF v_domain = 'MARKETPLACE' THEN RAISE EXCEPTION 'Marketplace services are special intents (TBOC Art.28), not dispatched services'; END IF;
  IF EXISTS (SELECT 1 FROM trustride.service_catalogue WHERE service_code = v_code) THEN
    RAISE EXCEPTION 'Service code % is already in the catalogue', v_code;
  END IF;
  IF v_domain = 'EXECUTIVE_ASSISTANTS' THEN
    BEGIN PERFORM upper(trim(p_pillar))::trustride.service_pillar_code_enum;
    EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'An Executive Assistant service names one of the six pillars (TBOC Art.27)'; END;
    IF NOT EXISTS (SELECT 1 FROM trustride.cost_ea_trade_occupation WHERE ea_skill_category = upper(trim(coalesce(p_ea_skill_category, '')))) THEN
      RAISE EXCEPTION 'Skill category % is not one Engine 5 rates under the Wages Order', coalesce(p_ea_skill_category, 'nothing');
    END IF;
    v_req := jsonb_build_object('pillar', upper(trim(p_pillar)), 'fulfilment', 'DISPATCH', 'ea_skill_category', upper(trim(p_ea_skill_category)));
  ELSE
    v_req := jsonb_build_object('trip', true, 'fulfilment', 'DISPATCH');
  END IF;
  v_id := trustride.fn_service_catalogue_register(v_code, trim(p_service_name), v_domain, trim(p_description), v_req, auth.uid());
  IF nullif(trim(coalesce(p_eligibility_summary, '')), '') IS NOT NULL THEN
    UPDATE trustride.service_catalogue SET eligibility_rules_summary = trim(p_eligibility_summary) WHERE service_id = v_id;
  END IF;
  PERFORM trustride.fn_service_catalogue_broadcast(v_id, 'DRAFT');
  RETURN v_id;
END;
$function$;

-- Registration is audited as a person's act (it was recorded with actor type USER and a NULL actor).
CREATE OR REPLACE FUNCTION trustride.fn_service_catalogue_register(p_service_code text, p_service_name text, p_macro_domain trustride.service_macro_domain_enum, p_description text, p_requirements jsonb DEFAULT '{}'::jsonb, p_registered_by uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_macro_domain_id UUID;
  v_service_id UUID;
BEGIN
  SELECT macro_domain_id INTO v_macro_domain_id FROM trustride.service_macro_domain WHERE domain_code = p_macro_domain AND active = TRUE;
  IF v_macro_domain_id IS NULL THEN
    RAISE EXCEPTION 'fn_service_catalogue_register: unknown or inactive macro_domain %', p_macro_domain;
  END IF;
  INSERT INTO trustride.service_catalogue (service_code, service_name, macro_domain_id, description, requirements, status)
  VALUES (p_service_code, p_service_name, v_macro_domain_id, p_description, p_requirements, 'DRAFT')
  RETURNING service_id INTO v_service_id;
  PERFORM trustride.fn_audit_log_append('service_catalogue', v_service_id, 'SERVICE_REGISTERED', p_registered_by,
    CASE WHEN p_registered_by IS NULL THEN 'SYSTEM' ELSE 'USER' END, NULL, 'TRUSTRIDE_OFFICE', NULL,
    jsonb_build_object('service_code', p_service_code, 'macro_domain', p_macro_domain, 'requirements', p_requirements));
  RETURN v_service_id;
END;
$function$;

CREATE OR REPLACE FUNCTION trustride.fn_service_coverage_zone_add(p_service_id uuid, p_jurisdiction text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_j TEXT := upper(trim(coalesce(p_jurisdiction, '')));
  v_status TEXT;
  v_coverage_id UUID;
BEGIN
  PERFORM trustride.fn_service_catalogue_office_check();
  SELECT status::text INTO v_status FROM trustride.service_catalogue WHERE service_id = p_service_id;
  IF v_status IS NULL THEN RAISE EXCEPTION 'Unknown service'; END IF;
  IF v_status = 'RETIRED' THEN RAISE EXCEPTION 'A retired service takes no new coverage'; END IF;
  IF NOT v_j = ANY (enum_range(NULL::trustride.cost_jurisdiction_enum)::text[]) THEN
    RAISE EXCEPTION 'Unknown jurisdiction % -- one of %', v_j, array_to_string(enum_range(NULL::trustride.cost_jurisdiction_enum)::text[], ', ');
  END IF;
  SELECT coverage_id INTO v_coverage_id FROM trustride.service_coverage_zone
  WHERE service_id = p_service_id AND jurisdiction = v_j AND active AND effective_to IS NULL;
  IF v_coverage_id IS NOT NULL THEN RETURN v_coverage_id; END IF;
  INSERT INTO trustride.service_coverage_zone (service_id, jurisdiction) VALUES (p_service_id, v_j) RETURNING coverage_id INTO v_coverage_id;
  PERFORM trustride.fn_audit_log_append('service_catalogue', p_service_id, 'SERVICE_COVERAGE_ADDED', auth.uid(),
    CASE WHEN auth.uid() IS NULL THEN 'SYSTEM' ELSE 'USER' END, NULL, 'TRUSTRIDE_OFFICE', NULL, jsonb_build_object('jurisdiction', v_j));
  RETURN v_coverage_id;
END;
$function$;

CREATE OR REPLACE FUNCTION trustride.fn_service_catalogue_activate(p_service_id uuid, p_activated_by uuid, p_approved_request_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_status TEXT;
  v_blockers TEXT[];
BEGIN
  PERFORM trustride.fn_service_catalogue_office_check();
  SELECT status::text INTO v_status FROM trustride.service_catalogue WHERE service_id = p_service_id FOR UPDATE;
  IF v_status = 'ACTIVE' THEN RETURN; END IF;   -- already live: nothing to do
  v_blockers := trustride.fn_service_catalogue_activation_blockers(p_service_id);
  IF cardinality(v_blockers) > 0 THEN RAISE EXCEPTION 'Cannot activate: %', array_to_string(v_blockers, '; '); END IF;
  UPDATE trustride.service_catalogue SET status = 'ACTIVE', approved_request_id = p_approved_request_id, effective_to = NULL, updated_at = now()
  WHERE service_id = p_service_id;
  PERFORM trustride.fn_audit_log_append('service_catalogue', p_service_id, 'SERVICE_ACTIVATED', p_activated_by,
    CASE WHEN p_activated_by IS NULL THEN 'SYSTEM' ELSE 'USER' END, NULL, 'TRUSTRIDE_OFFICE', jsonb_build_object('status', v_status),
    jsonb_build_object('status', 'ACTIVE', 'approved_request_id', p_approved_request_id));
  PERFORM trustride.fn_service_catalogue_broadcast(p_service_id, 'ACTIVE');
END;
$function$;

CREATE FUNCTION trustride.fn_service_catalogue_suspend(p_service_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_status TEXT;
BEGIN
  PERFORM trustride.fn_service_catalogue_office_check();
  IF coalesce(trim(p_reason), '') = '' THEN RAISE EXCEPTION 'State why the service is suspended'; END IF;
  SELECT status::text INTO v_status FROM trustride.service_catalogue WHERE service_id = p_service_id FOR UPDATE;
  IF v_status IS NULL THEN RAISE EXCEPTION 'Unknown service'; END IF;
  IF v_status = 'SUSPENDED' THEN RETURN; END IF;
  IF v_status <> 'ACTIVE' THEN RAISE EXCEPTION 'Only a live service can be suspended (this one is %)', lower(v_status); END IF;
  UPDATE trustride.service_catalogue SET status = 'SUSPENDED', updated_at = now() WHERE service_id = p_service_id;
  PERFORM trustride.fn_audit_log_append('service_catalogue', p_service_id, 'SERVICE_SUSPENDED', auth.uid(),
    CASE WHEN auth.uid() IS NULL THEN 'SYSTEM' ELSE 'USER' END, NULL, 'TRUSTRIDE_OFFICE', jsonb_build_object('status', v_status),
    jsonb_build_object('status', 'SUSPENDED', 'reason', trim(p_reason), 'open_orders_continuing', trustride.fn_service_open_orders(p_service_id)));
  PERFORM trustride.fn_service_catalogue_broadcast(p_service_id, 'SUSPENDED');
END;
$function$;

CREATE FUNCTION trustride.fn_service_catalogue_retire(p_service_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'trustride', 'pg_temp'
AS $function$
DECLARE
  v_status TEXT;
  v_open INT;
BEGIN
  PERFORM trustride.fn_service_catalogue_office_check();
  IF coalesce(trim(p_reason), '') = '' THEN RAISE EXCEPTION 'State why the service is retired'; END IF;
  SELECT status::text INTO v_status FROM trustride.service_catalogue WHERE service_id = p_service_id FOR UPDATE;
  IF v_status IS NULL THEN RAISE EXCEPTION 'Unknown service'; END IF;
  IF v_status = 'RETIRED' THEN RETURN; END IF;
  IF v_status = 'ACTIVE' THEN RAISE EXCEPTION 'Suspend the service first, then retire it once its open orders are finished'; END IF;
  v_open := trustride.fn_service_open_orders(p_service_id);
  IF v_open > 0 THEN RAISE EXCEPTION 'Cannot retire: % open order(s) still reference this service', v_open; END IF;
  UPDATE trustride.service_catalogue SET status = 'RETIRED', effective_to = greatest(now(), effective_from + interval '1 second'), updated_at = now()
  WHERE service_id = p_service_id;
  PERFORM trustride.fn_audit_log_append('service_catalogue', p_service_id, 'SERVICE_RETIRED', auth.uid(),
    CASE WHEN auth.uid() IS NULL THEN 'SYSTEM' ELSE 'USER' END, NULL, 'TRUSTRIDE_OFFICE', jsonb_build_object('status', v_status),
    jsonb_build_object('status', 'RETIRED', 'reason', trim(p_reason)));
  PERFORM trustride.fn_service_catalogue_broadcast(p_service_id, 'RETIRED');
END;
$function$;

-- ----------------------------------------------------------------- Engine 11 commands
CREATE FUNCTION trustride.fn_present_cmd_register_service(p_session uuid, p_payload jsonb, p_command uuid)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'trustride', 'public'
AS $function$
BEGIN
  RETURN trustride.fn_service_catalogue_office_register(p_payload->>'service_code', p_payload->>'service_name', p_payload->>'macro_domain',
    p_payload->>'description', p_payload->>'fulfilment', p_payload->>'pillar', p_payload->>'ea_skill_category', p_payload->>'eligibility_summary');
END;
$function$;
CREATE FUNCTION trustride.fn_present_cmd_add_service_coverage(p_session uuid, p_payload jsonb, p_command uuid)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'trustride', 'public'
AS $function$
BEGIN
  RETURN trustride.fn_service_coverage_zone_add((p_payload->>'service_id')::uuid, p_payload->>'jurisdiction');
END;
$function$;
CREATE FUNCTION trustride.fn_present_cmd_activate_service(p_session uuid, p_payload jsonb, p_command uuid)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'trustride', 'public'
AS $function$
BEGIN
  PERFORM trustride.fn_service_catalogue_activate((p_payload->>'service_id')::uuid, auth.uid(), NULL);
  RETURN (p_payload->>'service_id')::uuid;
END;
$function$;
CREATE FUNCTION trustride.fn_present_cmd_suspend_service(p_session uuid, p_payload jsonb, p_command uuid)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'trustride', 'public'
AS $function$
BEGIN
  PERFORM trustride.fn_service_catalogue_suspend((p_payload->>'service_id')::uuid, p_payload->>'reason');
  RETURN (p_payload->>'service_id')::uuid;
END;
$function$;
CREATE FUNCTION trustride.fn_present_cmd_retire_service(p_session uuid, p_payload jsonb, p_command uuid)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'trustride', 'public'
AS $function$
BEGIN
  PERFORM trustride.fn_service_catalogue_retire((p_payload->>'service_id')::uuid, p_payload->>'reason');
  RETURN (p_payload->>'service_id')::uuid;
END;
$function$;
INSERT INTO trustride.present_shell_capability_registry (top_shell, sub_shell, command_type, permitted, requires_delegated_authority)
SELECT 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', c, TRUE, FALSE
FROM unnest(ARRAY['REGISTER_SERVICE', 'ADD_SERVICE_COVERAGE', 'ACTIVATE_SERVICE', 'SUSPEND_SERVICE', 'RETIRE_SERVICE']) c;

-- ----------------------------------------------------------------- Office projection
CREATE FUNCTION trustride.fn_present_proj_office_catalogue(p_session uuid, p_params jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'trustride', 'public'
AS $function$
  SELECT jsonb_build_object(
    'services', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'service_id', sc.service_id, 'service_code', sc.service_code, 'service_name', sc.service_name, 'description', sc.description,
        'macro_domain', sm.domain_code, 'status', sc.status, 'fulfilment', sc.requirements->>'fulfilment', 'pillar', sc.requirements->>'pillar',
        'ea_skill_category', sc.requirements->>'ea_skill_category',
        'special_intent', EXISTS (SELECT 1 FROM trustride.service_special_intent si WHERE si.resolves_to_service_id = sc.service_id),
        'coverage', coalesce((SELECT jsonb_agg(cz.jurisdiction ORDER BY cz.jurisdiction) FROM trustride.service_coverage_zone cz
                              WHERE cz.service_id = sc.service_id AND cz.active AND cz.effective_to IS NULL), '[]'::jsonb),
        'pricing', coalesce((SELECT jsonb_agg(jsonb_build_object('jurisdiction', reg.jurisdiction, 'asset_class', reg.asset_class,
                                   'registry_code', reg.registry_code, 'current_rate_kes', rt.direct_per_km_rate_kes) ORDER BY reg.jurisdiction, reg.asset_class)
                             FROM trustride.cost_registry reg LEFT JOIN trustride.cost_rate rt ON rt.rate_id = reg.cost_rate_id
                             WHERE reg.service_code = sc.service_code AND reg.status = 'ACTIVE'), '[]'::jsonb),
        'open_orders', trustride.fn_service_open_orders(sc.service_id),
        'blockers', to_jsonb(trustride.fn_service_catalogue_activation_blockers(sc.service_id)),
        'ready_to_activate', sc.status IN ('DRAFT', 'SUSPENDED') AND cardinality(trustride.fn_service_catalogue_activation_blockers(sc.service_id)) = 0,
        'updated_at', sc.updated_at)
        ORDER BY sm.domain_code, sc.service_code)
      FROM trustride.service_catalogue sc JOIN trustride.service_macro_domain sm ON sm.macro_domain_id = sc.macro_domain_id), '[]'::jsonb),
    'macro_domains', to_jsonb(ARRAY['TRANSPORT', 'COURIER', 'DELIVERY', 'EXECUTIVE_ASSISTANTS']),
    'pillars', to_jsonb(enum_range(NULL::trustride.service_pillar_code_enum)::text[]),
    'ea_skill_categories', coalesce((SELECT jsonb_agg(DISTINCT ea_skill_category) FROM trustride.cost_ea_trade_occupation), '[]'::jsonb),
    'jurisdictions', to_jsonb(enum_range(NULL::trustride.cost_jurisdiction_enum)::text[]));
$function$;

INSERT INTO trustride.projection_registry (projection_code, shell, source_tables, refresh_mode, is_authoritative, sub_shells, description)
SELECT 'OFFICE_CATALOGUE', 'TRUSTRIDE_OFFICE',
  '["service_catalogue", "service_macro_domain", "service_coverage_zone", "service_special_intent", "cost_registry", "cost_rate", "cost_ea_trade_occupation", "business_order"]'::jsonb,
  refresh_mode, FALSE, ARRAY['ADMIN_CONSOLE'], 'Service catalogue with coverage, Engine 5 pricing linkage and activation readiness'
FROM trustride.projection_registry WHERE projection_code = 'OFFICE_INTEGRATIONS';

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
