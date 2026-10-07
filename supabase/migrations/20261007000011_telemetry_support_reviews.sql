-- ============================================================================
-- Telemetry (Protrack), support cases and reviews -- Engines 2, 4, 6, 11
-- Implementation Completion Stage 13 (Sec.9 Protrack), Stage 15 (G18),
-- G13 (location comes from the vehicle, never the customer).
-- ============================================================================
-- TELEMETRY BOUNDARY
--   Protrack (an EXTERNAL_SYSTEM registrant with a TELEMETRY_INGEST
--   credential) -> integration gateway -> fn_integration_telemetry_ingest
--   (Engine 6: authenticate, validate, normalise; Protrack field names never
--   leave Engine 6) -> TELEMETRY_BATCH_NORMALIZED -> Resources (device ->
--   vehicle via resource_telemetry_binding; location history; device
--   health; out-of-area safety check) -> RESOURCE_LOCATION_UPDATED (only for
--   a vehicle on an active job) -> Business tracking session.
--   Tracking is active-session only (TBOC Article 21): a vehicle's location
--   reaches a customer only between dispatch and completion of their job.
-- SUPPORT
--   Anyone with a TrustRide identity opens a case (optionally about an
--   order); an operator REPORT_PROBLEM opens one about their job; Office
--   assigns, replies, resolves; SLA by severity, escalation, reopen window.
-- REVIEWS
--   One review per finished order by its customer, rating the operator (or
--   the Marketplace seller); ratings roll up into the operator's record.
-- ============================================================================

INSERT INTO trustride.platform_configuration (config_key, config_value, environment, effective_from, changed_by)
SELECT v.k, v.v, 'ALL', now(), '00000000-0000-0000-0000-000000000000' FROM (VALUES
  ('TELEMETRY_STALE_AFTER_MIN', '10'),          -- an on-duty vehicle silent longer than this is flagged
  ('TELEMETRY_MAX_POINT_AGE_HOURS', '24'),      -- older points are kept as history, never treated as live
  ('TELEMETRY_SERVICE_AREA_BUFFER_KM', '15'),   -- distance beyond the operating zones that triggers a safety alert
  ('SUPPORT_SLA_CRITICAL_MIN', '30'),
  ('SUPPORT_SLA_HIGH_HOURS', '4'),
  ('SUPPORT_SLA_NORMAL_HOURS', '24'),
  ('SUPPORT_REOPEN_DAYS', '7')
) AS v(k, v)
WHERE NOT EXISTS (SELECT 1 FROM trustride.platform_configuration c WHERE c.config_key = v.k);

-- ---------------------------------------------------------------------------
-- 1. Engine 6: telemetry ingestion and normalisation
-- ---------------------------------------------------------------------------
CREATE TABLE trustride.integration_telemetry_ingest_log (
  ingest_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  system_user_id   UUID,
  provider_code    TEXT NOT NULL,
  received_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  record_count     INTEGER NOT NULL,
  accepted_count   INTEGER NOT NULL,
  rejected_count   INTEGER NOT NULL,
  rejections       JSONB NOT NULL DEFAULT '[]'::jsonb,
  outcome          TEXT NOT NULL CHECK (outcome IN ('ACCEPTED', 'PARTIAL', 'REJECTED', 'UNAUTHENTICATED'))
);
CREATE INDEX idx_integration_telemetry_ingest_log_at ON trustride.integration_telemetry_ingest_log (received_at DESC);
ALTER TABLE trustride.integration_telemetry_ingest_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY integration_telemetry_ingest_log_service_write ON trustride.integration_telemetry_ingest_log FOR ALL TO trs026_eng006_intg_service USING (true) WITH CHECK (true);
CREATE POLICY integration_telemetry_ingest_log_office_read ON trustride.integration_telemetry_ingest_log FOR SELECT TO trustride_authenticated
  USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));
GRANT SELECT ON trustride.integration_telemetry_ingest_log TO trustride_authenticated;

-- Accepts Protrack's push format (fields as Protrack names them: imei,
-- lat/lng, gpstime (unix seconds), speed (km/h), course (deg), acc (0/1 =
-- ignition)). Anything Protrack-specific is translated here and nowhere else.
CREATE OR REPLACE FUNCTION trustride.fn_integration_telemetry_ingest(p_key TEXT, p_records JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_system UUID;
  v_rec JSONB;
  v_points JSONB := '[]'::jsonb;
  v_rejections JSONB := '[]'::jsonb;
  v_lat NUMERIC; v_lon NUMERIC; v_at TIMESTAMPTZ;
  v_n INT := 0;
  v_ingest UUID;
  v_max_age INTERVAL := make_interval(hours => coalesce(nullif(trustride.fn_business_config('TELEMETRY_MAX_POINT_AGE_HOURS'), '')::int, 24));
BEGIN
  v_system := trustride.fn_external_system_authenticate(p_key, 'TELEMETRY_INGEST');
  IF v_system IS NULL THEN
    INSERT INTO trustride.integration_telemetry_ingest_log (provider_code, record_count, accepted_count, rejected_count, outcome)
    VALUES ('PROTRACK', coalesce(jsonb_array_length(p_records), 0), 0, coalesce(jsonb_array_length(p_records), 0), 'UNAUTHENTICATED');
    RETURN jsonb_build_object('outcome', 'UNAUTHENTICATED');
  END IF;

  FOR v_rec IN SELECT * FROM jsonb_array_elements(coalesce(p_records, '[]'::jsonb)) LOOP
    v_n := v_n + 1;
    BEGIN
      v_lat := coalesce(v_rec->>'lat', v_rec->>'latitude')::numeric;
      v_lon := coalesce(v_rec->>'lng', v_rec->>'lon', v_rec->>'longitude')::numeric;
      v_at := CASE WHEN coalesce(v_rec->>'gpstime', '') ~ '^[0-9]+$' THEN to_timestamp((v_rec->>'gpstime')::bigint)
                   ELSE coalesce(v_rec->>'gpstime', v_rec->>'recorded_at')::timestamptz END;
      IF coalesce(v_rec->>'imei', v_rec->>'device_id', '') = '' THEN RAISE EXCEPTION 'missing device id'; END IF;
      IF v_lat IS NULL OR v_lon IS NULL OR v_lat NOT BETWEEN -90 AND 90 OR v_lon NOT BETWEEN -180 AND 180 OR (v_lat = 0 AND v_lon = 0) THEN
        RAISE EXCEPTION 'invalid coordinates';
      END IF;
      IF v_at IS NULL OR v_at > now() + interval '5 minutes' THEN RAISE EXCEPTION 'invalid or future timestamp'; END IF;
      v_points := v_points || jsonb_build_array(jsonb_build_object(
        'device_ref', coalesce(v_rec->>'imei', v_rec->>'device_id'), 'lat', v_lat, 'lon', v_lon, 'recorded_at', v_at,
        'speed_kmh', (v_rec->>'speed')::numeric, 'heading_deg', (v_rec->>'course')::numeric,
        'ignition_on', CASE WHEN v_rec->>'acc' IN ('1', 'true') THEN TRUE WHEN v_rec->>'acc' IN ('0', 'false') THEN FALSE END,
        'live', v_at > now() - v_max_age));
    EXCEPTION WHEN OTHERS THEN
      v_rejections := v_rejections || jsonb_build_array(jsonb_build_object('index', v_n - 1, 'reason', SQLERRM));
    END;
  END LOOP;

  INSERT INTO trustride.integration_telemetry_ingest_log (system_user_id, provider_code, record_count, accepted_count, rejected_count, rejections, outcome)
  VALUES (v_system, 'PROTRACK', v_n, jsonb_array_length(v_points), jsonb_array_length(v_rejections), v_rejections,
    CASE WHEN jsonb_array_length(v_rejections) = 0 THEN 'ACCEPTED' WHEN jsonb_array_length(v_points) = 0 THEN 'REJECTED' ELSE 'PARTIAL' END)
  RETURNING ingest_id INTO v_ingest;

  IF jsonb_array_length(v_points) > 0 THEN
    INSERT INTO trustride.integration_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (v_ingest, 'TRS026_ENG002_RESC', 'TELEMETRY_BATCH_NORMALIZED',
      jsonb_build_object('ingest_id', v_ingest, 'provider_code', 'PROTRACK', 'points', v_points),
      'TELEMETRY_BATCH_NORMALIZED:' || v_ingest::text);
  END IF;
  PERFORM trustride.fn_integration_circuit_check('TELEMETRY_SERVICE');
  PERFORM trustride.fn_integration_circuit_record_result('TELEMETRY_SERVICE', TRUE, 0);
  RETURN jsonb_build_object('outcome', 'ACCEPTED', 'ingest_id', v_ingest, 'accepted', jsonb_array_length(v_points), 'rejected', v_rejections);
END;
$$;

-- ---------------------------------------------------------------------------
-- 2. Engine 2: resource location and device health
-- ---------------------------------------------------------------------------
ALTER TABLE trustride.resource_telemetry_binding
  ADD COLUMN last_seen_at TIMESTAMPTZ,
  ADD COLUMN last_location GEOMETRY(Point, 4326),
  ADD COLUMN telemetry_status TEXT NOT NULL DEFAULT 'NEVER_SEEN' CHECK (telemetry_status IN ('NEVER_SEEN', 'LIVE', 'STALE')),
  ADD COLUMN stale_alerted_at TIMESTAMPTZ;

CREATE TABLE trustride.resource_location_event (
  location_event_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  fleet_resource_id  UUID REFERENCES trustride.resource_fleet_register (fleet_resource_id),
  binding_id         UUID REFERENCES trustride.resource_telemetry_binding (binding_id),
  provider_code      TEXT NOT NULL,
  device_ref         TEXT NOT NULL,
  location           GEOMETRY(Point, 4326) NOT NULL,
  recorded_at        TIMESTAMPTZ NOT NULL,
  received_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  speed_kmh          NUMERIC(6,1),
  heading_deg        NUMERIC(5,1),
  ignition_on        BOOLEAN,
  order_id           UUID,
  outside_service_area BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE INDEX idx_resource_location_event_fleet_time ON trustride.resource_location_event (fleet_resource_id, recorded_at DESC);
CREATE INDEX idx_resource_location_event_order ON trustride.resource_location_event (order_id, recorded_at DESC) WHERE order_id IS NOT NULL;
COMMENT ON TABLE trustride.resource_location_event IS
  '[Trace: TBOC Art.21; Implementation Completion Sec.9] TrustRide''s own location history for its resources, normalised from provider telemetry. Personal data (Data Protection Act 2019): retained per retention_policy TELEMETRY.';
ALTER TABLE trustride.resource_location_event ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_location_event_service_write ON trustride.resource_location_event FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);
CREATE POLICY resource_location_event_office_read ON trustride.resource_location_event FOR SELECT TO trustride_authenticated
  USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));
GRANT SELECT ON trustride.resource_location_event TO trustride_authenticated;

INSERT INTO trustride.retention_policy (record_class, retention_years, legal_basis, purge_action, status)
SELECT 'TELEMETRY', 1, 'Data Protection Act 2019 -- minimum necessary; trip evidence kept 1 year', 'ANONYMISE', 'ACTIVE'
WHERE NOT EXISTS (SELECT 1 FROM trustride.retention_policy WHERE record_class = 'TELEMETRY');

CREATE OR REPLACE FUNCTION trustride.fn_resource_telemetry_batch_accept(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
DECLARE
  v_payload JSONB;
  v_corr UUID;
  v_pt JSONB;
  v_b RECORD;
  v_unit RECORD;
  v_order UUID;
  v_geom GEOMETRY;
  v_outside BOOLEAN;
  v_buffer NUMERIC := coalesce(nullif(trustride.fn_business_config('TELEMETRY_SERVICE_AREA_BUFFER_KM'), '')::numeric, 15) * 1000;
  v_latest JSONB := '{}'::jsonb;   -- order_id -> newest live point
  v_unknown INT := 0;
  k TEXT;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_corr FROM trustride.resource_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'no RECEIVED signal %', p_signal_id; END IF;

  FOR v_pt IN SELECT * FROM jsonb_array_elements(v_payload->'points') ORDER BY (value->>'recorded_at')::timestamptz LOOP
    SELECT * INTO v_b FROM trustride.resource_telemetry_binding
    WHERE provider_code = coalesce(v_payload->>'provider_code', 'PROTRACK') AND provider_device_ref = v_pt->>'device_ref' AND status = 'ACTIVE';
    IF v_b.binding_id IS NULL THEN
      v_unknown := v_unknown + 1;   -- a device not (yet) fitted to a registered vehicle: kept in Engine 6's log only
      CONTINUE;
    END IF;
    v_geom := ST_SetSRID(ST_MakePoint((v_pt->>'lon')::numeric, (v_pt->>'lat')::numeric), 4326);
    -- On a job? (the vehicle's working unit is ASSIGNED to an order)
    SELECT wu.workforce_unit_id, al.job_ref_id INTO v_unit
    FROM trustride.resource_workforce_unit wu
    JOIN trustride.resource_availability_ledger al ON al.resource_type = 'WORKFORCE_UNIT' AND al.resource_ref_id = wu.workforce_unit_id AND al.effective_to IS NULL
    WHERE wu.fleet_resource_id = v_b.fleet_resource_id AND wu.unit_status = 'ACTIVE' AND al.availability_state = 'ASSIGNED';
    v_order := v_unit.job_ref_id;
    v_outside := NOT EXISTS (SELECT 1 FROM trustride.cost_operational_zones z WHERE z.active AND ST_DWithin(z.boundary::geography, v_geom::geography, v_buffer));
    INSERT INTO trustride.resource_location_event (fleet_resource_id, binding_id, provider_code, device_ref, location, recorded_at, speed_kmh, heading_deg, ignition_on, order_id, outside_service_area)
    VALUES (v_b.fleet_resource_id, v_b.binding_id, v_b.provider_code, v_b.provider_device_ref, v_geom, (v_pt->>'recorded_at')::timestamptz,
      (v_pt->>'speed_kmh')::numeric, (v_pt->>'heading_deg')::numeric, (v_pt->>'ignition_on')::boolean, v_order, v_outside);
    IF coalesce((v_pt->>'live')::boolean, true) AND (v_b.last_seen_at IS NULL OR (v_pt->>'recorded_at')::timestamptz > v_b.last_seen_at) THEN
      UPDATE trustride.resource_telemetry_binding SET last_seen_at = (v_pt->>'recorded_at')::timestamptz, last_location = v_geom,
        telemetry_status = 'LIVE', stale_alerted_at = NULL WHERE binding_id = v_b.binding_id;
      IF v_order IS NOT NULL THEN
        v_latest := v_latest || jsonb_build_object(v_order::text, v_pt || jsonb_build_object('fleet_resource_id', v_b.fleet_resource_id, 'outside_service_area', v_outside));
      END IF;
    END IF;
  END LOOP;

  -- One location update per order per batch reaches Business.
  FOR k IN SELECT jsonb_object_keys(v_latest) LOOP
    INSERT INTO trustride.resource_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (v_corr, 'TRS026_ENG004_BUS', 'RESOURCE_LOCATION_UPDATED', jsonb_build_object('order_id', k) || (v_latest->k),
      'RESOURCE_LOCATION_UPDATED:' || k || ':' || p_signal_id::text);
  END LOOP;

  UPDATE trustride.resource_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(),
    payload_out = jsonb_build_object('unbound_devices', v_unknown, 'orders_updated', (SELECT count(*) FROM jsonb_object_keys(v_latest))) WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

-- Device health: an on-duty vehicle whose tracker has gone quiet.
CREATE OR REPLACE FUNCTION trustride.fn_resource_telemetry_health_sweep()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  r RECORD;
  n INTEGER := 0;
BEGIN
  FOR r IN
    UPDATE trustride.resource_telemetry_binding b SET telemetry_status = 'STALE'
    WHERE b.status = 'ACTIVE' AND b.telemetry_status = 'LIVE'
      AND b.last_seen_at < now() - make_interval(mins => coalesce(nullif(trustride.fn_business_config('TELEMETRY_STALE_AFTER_MIN'), '')::int, 10))
    RETURNING b.binding_id, b.fleet_resource_id, b.provider_device_ref
  LOOP
    IF EXISTS (SELECT 1 FROM trustride.resource_workforce_unit wu WHERE wu.fleet_resource_id = r.fleet_resource_id AND wu.unit_status = 'ACTIVE'
               AND trustride.fn_resource_unit_availability(wu.workforce_unit_id) IN ('AVAILABLE', 'RESERVED', 'ASSIGNED')) THEN
      PERFORM trustride.fn_present_notify_office('Tracker silent: ' || r.provider_device_ref,
        'An on-duty vehicle has stopped reporting its position. Check the device or contact the operator.', 'TELEMETRY_EXCEPTION', r.binding_id);
      UPDATE trustride.resource_telemetry_binding SET stale_alerted_at = now() WHERE binding_id = r.binding_id;
    END IF;
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Engine 4: location reaches the active tracking session only
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_business_resource_location_updated_accept(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
DECLARE
  v_payload JSONB;
  v_job UUID;
  v_o RECORD;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.business_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'no RECEIVED signal %', p_signal_id; END IF;
  SELECT j.job_id INTO v_job FROM trustride.business_job j JOIN trustride.business_tracking_session t ON t.job_id = j.job_id AND t.ended_at IS NULL
  WHERE j.order_id = (v_payload->>'order_id')::uuid ORDER BY j.line_sequence LIMIT 1;
  IF v_job IS NOT NULL THEN
    UPDATE trustride.business_tracking_session
    SET exact_location = ST_SetSRID(ST_MakePoint((v_payload->>'lon')::numeric, (v_payload->>'lat')::numeric), 4326), updated_at = now()
    WHERE job_id = v_job AND ended_at IS NULL;
  END IF;
  IF coalesce((v_payload->>'outside_service_area')::boolean, false) THEN
    SELECT * INTO v_o FROM trustride.business_order WHERE order_id = (v_payload->>'order_id')::uuid;
    IF NOT EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE source_signal_correlation_id = v_o.order_id AND category = 'SAFETY'
                   AND delivered_at > now() - interval '30 minutes') THEN
      PERFORM trustride.fn_present_notify_office('Vehicle outside service area: ' || v_o.order_code,
        'A vehicle on an active job is beyond the operating zones. Contact the operator now.', 'SAFETY', v_o.order_id, ARRAY['FOUNDER', 'ADMINISTRATOR', 'SAFEGUARDING_OFFICER'], TRUE);
    END IF;
  END IF;
  UPDATE trustride.business_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(),
    payload_out = jsonb_build_object('tracking_updated', v_job IS NOT NULL) WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Engine 4: support cases
-- ---------------------------------------------------------------------------
INSERT INTO trustride.sequence_generator (sequence_code, prefix, current_value, padding, reset_policy)
SELECT 'TRS026-CASE', 'TRS026-CASE', 0, 9, 'NEVER' WHERE NOT EXISTS (SELECT 1 FROM trustride.sequence_generator WHERE sequence_code = 'TRS026-CASE');

CREATE TABLE trustride.business_support_case (
  case_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_code        TEXT NOT NULL UNIQUE,
  opened_by_user_id UUID NOT NULL,
  opened_via_shell trustride.present_sub_shell_enum,
  order_id         UUID REFERENCES trustride.business_order (order_id),
  job_id           UUID REFERENCES trustride.business_job (job_id),
  category         TEXT NOT NULL CHECK (category IN ('ORDER_ISSUE', 'PAYMENT', 'SAFETY', 'LOST_ITEM', 'OPERATOR_PROBLEM', 'ACCOUNT', 'MARKETPLACE', 'OTHER')),
  severity         TEXT NOT NULL CHECK (severity IN ('NORMAL', 'HIGH', 'CRITICAL')),
  subject          TEXT NOT NULL,
  status           TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'ASSIGNED', 'AWAITING_REQUESTER', 'RESOLVED', 'CLOSED')),
  assigned_to      UUID,
  sla_due_at       TIMESTAMPTZ NOT NULL,
  escalated_at     TIMESTAMPTZ,
  resolution       TEXT,
  opened_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at      TIMESTAMPTZ,
  closed_at        TIMESTAMPTZ
);
CREATE INDEX idx_business_support_case_open ON trustride.business_support_case (status, sla_due_at) WHERE status NOT IN ('RESOLVED', 'CLOSED');
CREATE TABLE trustride.business_support_message (
  message_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id        UUID NOT NULL REFERENCES trustride.business_support_case (case_id),
  author_user_id UUID,
  author_role    TEXT NOT NULL CHECK (author_role IN ('REQUESTER', 'OFFICE', 'SYSTEM')),
  body           TEXT NOT NULL,
  internal_note  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.business_support_case IS '[Trace: TBOC Order Stage REVIEW_RATE_SUPPORT; Implementation Completion G18] Customer and operator support cases with severity SLAs.';
ALTER TABLE trustride.business_support_case ENABLE ROW LEVEL SECURITY;
ALTER TABLE trustride.business_support_message ENABLE ROW LEVEL SECURITY;
CREATE POLICY business_support_case_service_write ON trustride.business_support_case FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);
CREATE POLICY business_support_message_service_write ON trustride.business_support_message FOR ALL TO trs026_eng004_bus_service USING (true) WITH CHECK (true);
CREATE POLICY business_support_case_requester_read ON trustride.business_support_case FOR SELECT TO trustride_authenticated USING (opened_by_user_id = auth.uid());
CREATE POLICY business_support_case_office_read ON trustride.business_support_case FOR SELECT TO trustride_authenticated
  USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE', 'SAFEGUARDING_OFFICER']));
CREATE POLICY business_support_message_requester_read ON trustride.business_support_message FOR SELECT TO trustride_authenticated
  USING (NOT internal_note AND EXISTS (SELECT 1 FROM trustride.business_support_case c WHERE c.case_id = business_support_message.case_id AND c.opened_by_user_id = auth.uid()));
CREATE POLICY business_support_message_office_read ON trustride.business_support_message FOR SELECT TO trustride_authenticated
  USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE', 'SAFEGUARDING_OFFICER']));
GRANT SELECT ON trustride.business_support_case, trustride.business_support_message TO trustride_authenticated;

CREATE OR REPLACE FUNCTION trustride.fn_business_support_case_open(p_user UUID, p_shell trustride.present_sub_shell_enum, p_category TEXT, p_subject TEXT,
  p_body TEXT, p_order_id UUID DEFAULT NULL, p_job_id UUID DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_case UUID;
  v_sev TEXT;
  v_code TEXT;
BEGIN
  IF coalesce(trim(p_subject), '') = '' OR coalesce(trim(p_body), '') = '' THEN RAISE EXCEPTION 'Say what happened'; END IF;
  IF p_order_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM trustride.business_order o WHERE o.order_id = p_order_id AND (o.requester_user_id = p_user OR EXISTS (
         SELECT 1 FROM trustride.business_job j JOIN trustride.resource_workforce_unit wu ON wu.workforce_unit_id = j.workforce_unit_id
         WHERE j.order_id = o.order_id AND wu.operator_user_id = p_user))) THEN
    RAISE EXCEPTION 'You can only raise a case about your own order or job';
  END IF;
  v_sev := CASE WHEN p_category = 'SAFETY' THEN 'CRITICAL' WHEN p_category IN ('PAYMENT', 'OPERATOR_PROBLEM', 'LOST_ITEM') THEN 'HIGH' ELSE 'NORMAL' END;
  v_code := trustride.fn_sequence_next('TRS026-CASE');
  INSERT INTO trustride.business_support_case (case_code, opened_by_user_id, opened_via_shell, order_id, job_id, category, severity, subject, sla_due_at)
  VALUES (v_code, p_user, p_shell, p_order_id, p_job_id, p_category, v_sev, trim(p_subject),
    now() + CASE v_sev
      WHEN 'CRITICAL' THEN make_interval(mins => trustride.fn_business_config_num('SUPPORT_SLA_CRITICAL_MIN', 30)::int)
      WHEN 'HIGH' THEN make_interval(hours => trustride.fn_business_config_num('SUPPORT_SLA_HIGH_HOURS', 4)::int)
      ELSE make_interval(hours => trustride.fn_business_config_num('SUPPORT_SLA_NORMAL_HOURS', 24)::int) END)
  RETURNING case_id INTO v_case;
  INSERT INTO trustride.business_support_message (case_id, author_user_id, author_role, body) VALUES (v_case, p_user, 'REQUESTER', trim(p_body));
  PERFORM trustride.fn_present_notify_office(CASE v_sev WHEN 'CRITICAL' THEN 'URGENT: ' ELSE '' END || 'Support case ' || v_code || ' (' || lower(replace(p_category, '_', ' ')) || ')',
    left(trim(p_subject), 200), 'SUPPORT', v_case,
    CASE WHEN p_category = 'SAFETY' THEN ARRAY['FOUNDER', 'ADMINISTRATOR', 'SAFEGUARDING_OFFICER'] ELSE ARRAY['FOUNDER', 'ADMINISTRATOR'] END,
    v_sev = 'CRITICAL');
  INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, source_signal_correlation_id, category, external_channels)
  SELECT p_user, CASE WHEN p_shell IN ('OPERATOR_APP', 'ADMIN_CONSOLE', 'EXECUTIVE_DASHBOARD') THEN 'TRUSTRIDE_OFFICE'::trustride.present_top_shell_enum
                      WHEN p_shell IN ('MARKETPLACE_APP', 'VENDOR_APP') THEN 'TRUSTRIDE_MARKETPLACE'::trustride.present_top_shell_enum
                      ELSE 'TRUSTRIDE_BUSINESS'::trustride.present_top_shell_enum END,
    coalesce(p_shell, 'CUSTOMER_APP'), 'Support case ' || v_code || ' opened',
    'We have your report and will respond ' || CASE v_sev WHEN 'CRITICAL' THEN 'within minutes.' WHEN 'HIGH' THEN 'within a few hours.' ELSE 'within a day.' END,
    v_case, 'SUPPORT', ARRAY[]::TEXT[];
  RETURN v_case;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_support_case_message(p_case UUID, p_user UUID, p_body TEXT, p_internal BOOLEAN DEFAULT FALSE)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_c RECORD;
  v_office BOOLEAN := trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'SAFEGUARDING_OFFICER']);
  v_id UUID;
BEGIN
  SELECT * INTO v_c FROM trustride.business_support_case WHERE case_id = p_case FOR UPDATE;
  IF v_c.case_id IS NULL OR (NOT v_office AND v_c.opened_by_user_id <> p_user) THEN RAISE EXCEPTION 'No such case on your identity'; END IF;
  IF coalesce(trim(p_body), '') = '' THEN RAISE EXCEPTION 'Write a message'; END IF;
  IF v_c.status = 'CLOSED' THEN RAISE EXCEPTION 'This case is closed -- open a new one'; END IF;
  INSERT INTO trustride.business_support_message (case_id, author_user_id, author_role, body, internal_note)
  VALUES (p_case, p_user, CASE WHEN v_office AND v_c.opened_by_user_id <> p_user THEN 'OFFICE' ELSE 'REQUESTER' END, trim(p_body), p_internal AND v_office)
  RETURNING message_id INTO v_id;
  IF v_office AND v_c.opened_by_user_id <> p_user AND NOT p_internal THEN
    UPDATE trustride.business_support_case SET status = 'AWAITING_REQUESTER', assigned_to = coalesce(assigned_to, p_user) WHERE case_id = p_case;
    INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, source_signal_correlation_id, category)
    VALUES (v_c.opened_by_user_id,
      CASE WHEN v_c.opened_via_shell IN ('OPERATOR_APP', 'ADMIN_CONSOLE', 'EXECUTIVE_DASHBOARD') THEN 'TRUSTRIDE_OFFICE'::trustride.present_top_shell_enum
           WHEN v_c.opened_via_shell IN ('MARKETPLACE_APP', 'VENDOR_APP') THEN 'TRUSTRIDE_MARKETPLACE'::trustride.present_top_shell_enum
           ELSE 'TRUSTRIDE_BUSINESS'::trustride.present_top_shell_enum END,
      coalesce(v_c.opened_via_shell, 'CUSTOMER_APP'), 'Reply on ' || v_c.case_code, left(trim(p_body), 300), p_case, 'SUPPORT');
  ELSIF NOT v_office OR v_c.opened_by_user_id = p_user THEN
    UPDATE trustride.business_support_case SET status = CASE WHEN assigned_to IS NULL THEN 'OPEN' ELSE 'ASSIGNED' END WHERE case_id = p_case AND status IN ('AWAITING_REQUESTER', 'RESOLVED');
  END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_support_case_assign(p_case UUID, p_assignee UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  IF NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN RAISE EXCEPTION 'Assigning cases is a TrustRide Office function'; END IF;
  IF NOT EXISTS (SELECT 1 FROM trustride.fn_office_recipients(ARRAY['FOUNDER', 'ADMINISTRATOR', 'SAFEGUARDING_OFFICER']) r WHERE r = p_assignee) THEN
    RAISE EXCEPTION 'Cases are assigned to TrustRide Office staff';
  END IF;
  UPDATE trustride.business_support_case SET assigned_to = p_assignee, status = CASE WHEN status = 'OPEN' THEN 'ASSIGNED' ELSE status END
  WHERE case_id = p_case AND status NOT IN ('CLOSED');
  IF NOT FOUND THEN RAISE EXCEPTION 'No open case %', p_case; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_business_support_case_resolve(p_case UUID, p_resolution TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_c RECORD;
BEGIN
  IF NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'SAFEGUARDING_OFFICER']) THEN RAISE EXCEPTION 'Resolving cases is a TrustRide Office function'; END IF;
  IF coalesce(trim(p_resolution), '') = '' THEN RAISE EXCEPTION 'Record the resolution'; END IF;
  UPDATE trustride.business_support_case SET status = 'RESOLVED', resolution = trim(p_resolution), resolved_at = now()
  WHERE case_id = p_case AND status NOT IN ('RESOLVED', 'CLOSED') RETURNING * INTO v_c;
  IF v_c.case_id IS NULL THEN RAISE EXCEPTION 'No unresolved case %', p_case; END IF;
  INSERT INTO trustride.business_support_message (case_id, author_user_id, author_role, body) VALUES (p_case, auth.uid(), 'OFFICE', 'Resolved: ' || trim(p_resolution));
  INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, source_signal_correlation_id, category)
  VALUES (v_c.opened_by_user_id,
    CASE WHEN v_c.opened_via_shell IN ('OPERATOR_APP', 'ADMIN_CONSOLE', 'EXECUTIVE_DASHBOARD') THEN 'TRUSTRIDE_OFFICE'::trustride.present_top_shell_enum
         WHEN v_c.opened_via_shell IN ('MARKETPLACE_APP', 'VENDOR_APP') THEN 'TRUSTRIDE_MARKETPLACE'::trustride.present_top_shell_enum
         ELSE 'TRUSTRIDE_BUSINESS'::trustride.present_top_shell_enum END,
    coalesce(v_c.opened_via_shell, 'CUSTOMER_APP'), v_c.case_code || ' resolved', left(trim(p_resolution), 300), p_case, 'SUPPORT');
END;
$$;

-- The requester closes (satisfied) or reopens (within the window).
CREATE OR REPLACE FUNCTION trustride.fn_business_support_case_requester_action(p_case UUID, p_user UUID, p_action TEXT, p_body TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_c RECORD;
BEGIN
  SELECT * INTO v_c FROM trustride.business_support_case WHERE case_id = p_case AND opened_by_user_id = p_user FOR UPDATE;
  IF v_c.case_id IS NULL THEN RAISE EXCEPTION 'No such case on your identity'; END IF;
  IF upper(p_action) = 'CLOSE' THEN
    UPDATE trustride.business_support_case SET status = 'CLOSED', closed_at = now() WHERE case_id = p_case AND status <> 'CLOSED';
  ELSIF upper(p_action) = 'REOPEN' THEN
    IF v_c.status NOT IN ('RESOLVED', 'CLOSED') OR coalesce(v_c.resolved_at, v_c.closed_at) < now() - make_interval(days => trustride.fn_business_config_num('SUPPORT_REOPEN_DAYS', 7)::int) THEN
      RAISE EXCEPTION 'Only a recently resolved case can be reopened -- open a new one';
    END IF;
    UPDATE trustride.business_support_case SET status = CASE WHEN assigned_to IS NULL THEN 'OPEN' ELSE 'ASSIGNED' END, resolved_at = NULL, closed_at = NULL,
      sla_due_at = now() + make_interval(hours => trustride.fn_business_config_num('SUPPORT_SLA_HIGH_HOURS', 4)::int) WHERE case_id = p_case;
    INSERT INTO trustride.business_support_message (case_id, author_user_id, author_role, body) VALUES (p_case, p_user, 'REQUESTER', coalesce(nullif(trim(p_body), ''), 'Reopened'));
    PERFORM trustride.fn_present_notify_office('Case reopened: ' || v_c.case_code, coalesce(p_body, ''), 'SUPPORT', p_case);
  ELSE
    RAISE EXCEPTION 'Action is CLOSE or REOPEN';
  END IF;
END;
$$;

-- SLA: breaches escalate (never silently age); resolved cases auto-close.
CREATE OR REPLACE FUNCTION trustride.fn_business_support_sla_sweep()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  r RECORD;
  n INTEGER := 0;
BEGIN
  FOR r IN UPDATE trustride.business_support_case SET escalated_at = now()
           WHERE status IN ('OPEN', 'ASSIGNED') AND sla_due_at < now() AND escalated_at IS NULL RETURNING case_id, case_code, severity LOOP
    PERFORM trustride.fn_present_notify_office('Support SLA breached: ' || r.case_code, 'This ' || lower(r.severity) || ' case is past its response time.',
      'SUPPORT', r.case_id, ARRAY['FOUNDER', 'ADMINISTRATOR'], r.severity = 'CRITICAL');
    n := n + 1;
  END LOOP;
  UPDATE trustride.business_support_case SET status = 'CLOSED', closed_at = now()
  WHERE status = 'RESOLVED' AND resolved_at < now() - make_interval(days => trustride.fn_business_config_num('SUPPORT_REOPEN_DAYS', 7)::int);
  RETURN n;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Engine 4: reviews
-- ---------------------------------------------------------------------------
ALTER TABLE trustride.business_review ALTER COLUMN reviewee_user_id DROP NOT NULL;  -- NULL = TrustRide itself (own Marketplace stock)
CREATE UNIQUE INDEX business_review_one_per_order_uq ON trustride.business_review (order_id, reviewer_user_id);
CREATE POLICY business_review_office_read ON trustride.business_review FOR SELECT TO trustride_authenticated
  USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));

CREATE OR REPLACE FUNCTION trustride.fn_business_review_by_customer(p_order_id UUID, p_user UUID, p_rating SMALLINT, p_comment TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_o RECORD;
  v_reviewee UUID;
BEGIN
  SELECT * INTO v_o FROM trustride.business_order WHERE order_id = p_order_id AND requester_user_id = p_user;
  IF v_o.order_id IS NULL THEN RAISE EXCEPTION 'You can only review your own order'; END IF;
  IF v_o.status NOT IN ('COMPLETED', 'SETTLED') THEN RAISE EXCEPTION 'You can review an order once it is finished'; END IF;
  IF p_rating NOT BETWEEN 1 AND 5 THEN RAISE EXCEPTION 'Rate from 1 to 5 stars'; END IF;
  IF EXISTS (SELECT 1 FROM trustride.business_review WHERE order_id = p_order_id AND reviewer_user_id = p_user) THEN
    RAISE EXCEPTION 'You have already reviewed this order';
  END IF;
  IF v_o.order_root_type = 'MARKETPLACE_PURCHASE_ORDER' THEN
    SELECT (scope_detail->>'vendor_user_id')::uuid INTO v_reviewee FROM trustride.business_order_line WHERE order_id = p_order_id LIMIT 1;
  ELSE
    SELECT wu.operator_user_id INTO v_reviewee FROM trustride.business_job j JOIN trustride.resource_workforce_unit wu ON wu.workforce_unit_id = j.workforce_unit_id
    WHERE j.order_id = p_order_id AND j.status IN ('COMPLETED', 'VERIFIED') ORDER BY j.line_sequence LIMIT 1;
  END IF;
  RETURN trustride.fn_business_review_submit(p_order_id, p_user, v_reviewee, p_rating, nullif(trim(p_comment), ''));
END;
$$;

-- fn_business_review_submit inserted with reviewee NOT NULL assumptions;
-- it also lets SETTLED orders move to REVIEWED -- unchanged.

-- ---------------------------------------------------------------------------
-- 6. Inboxes, routes, schedules, Engine 11 verbs
-- ---------------------------------------------------------------------------
DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_resource_inbox_process(uuid)'::regprocedure) INTO v_def;
  IF position('TELEMETRY_BATCH_NORMALIZED' IN v_def) = 0 THEN
    v_def := replace(v_def, E'    ELSE\n      UPDATE trustride.resource_event_inbox',
      E'    WHEN ''TELEMETRY_BATCH_NORMALIZED'' THEN v_result := trustride.fn_resource_telemetry_batch_accept(p_signal_id);\n    ELSE\n      UPDATE trustride.resource_event_inbox');
    EXECUTE v_def;
  END IF;
  SELECT pg_get_functiondef('trustride.fn_business_inbox_process(uuid)'::regprocedure) INTO v_def;
  IF position('RESOURCE_LOCATION_UPDATED' IN v_def) = 0 THEN
    v_def := replace(v_def, E'    ELSE\n      UPDATE trustride.business_event_inbox',
      E'    WHEN ''RESOURCE_LOCATION_UPDATED'' THEN v_result := trustride.fn_business_resource_location_updated_accept(p_signal_id);\n    ELSE\n      UPDATE trustride.business_event_inbox');
    EXECUTE v_def;
  END IF;
END;
$patch$;

INSERT INTO trustride.routing_rule (event_type, source_engine, target_engine, route_priority)
SELECT v.e, v.s, v.t, 0
FROM (VALUES
  ('TELEMETRY_BATCH_NORMALIZED', 'TRS026_ENG006_INTG', 'TRS026_ENG002_RESC'),
  ('RESOURCE_LOCATION_UPDATED', 'TRS026_ENG002_RESC', 'TRS026_ENG004_BUS')
) AS v(e, s, t)
WHERE NOT EXISTS (SELECT 1 FROM trustride.routing_rule r WHERE r.event_type = v.e AND r.source_engine = v.s AND r.target_engine = v.t);
SELECT trustride.fn_orch_destination_cache_sync();

SELECT cron.schedule('trustride_telemetry_health_sweep', '*/2 * * * *', 'SELECT trustride.fn_resource_telemetry_health_sweep();');
SELECT cron.schedule('trustride_support_sla_sweep', '*/5 * * * *', 'SELECT trustride.fn_business_support_sla_sweep();');

INSERT INTO trustride.present_shell_capability_registry (top_shell, sub_shell, command_type, permitted, requires_delegated_authority)
SELECT v.top::trustride.present_top_shell_enum, v.sub::trustride.present_sub_shell_enum, v.cmd, TRUE, FALSE
FROM (VALUES
  ('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'OPEN_SUPPORT_CASE'), ('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'REPLY_SUPPORT_CASE'),
  ('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'CLOSE_SUPPORT_CASE'), ('TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'SUBMIT_REVIEW'),
  ('TRUSTRIDE_BUSINESS', 'PARTNER_APP', 'OPEN_SUPPORT_CASE'), ('TRUSTRIDE_BUSINESS', 'PARTNER_APP', 'REPLY_SUPPORT_CASE'),
  ('TRUSTRIDE_BUSINESS', 'GOVERNOR_APP', 'OPEN_SUPPORT_CASE'), ('TRUSTRIDE_BUSINESS', 'GOVERNOR_APP', 'REPLY_SUPPORT_CASE'),
  ('TRUSTRIDE_BUSINESS', 'INTERMEDIARY_APP', 'OPEN_SUPPORT_CASE'), ('TRUSTRIDE_BUSINESS', 'INTERMEDIARY_APP', 'REPLY_SUPPORT_CASE'),
  ('TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'OPEN_SUPPORT_CASE'), ('TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'REPLY_SUPPORT_CASE'),
  ('TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'SUBMIT_REVIEW'),
  ('TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'OPEN_SUPPORT_CASE'), ('TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'REPLY_SUPPORT_CASE'),
  ('TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'REPORT_PROBLEM'), ('TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'OPEN_SUPPORT_CASE'),
  ('TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'REPLY_SUPPORT_CASE'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ASSIGN_SUPPORT_CASE'), ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REPLY_SUPPORT_CASE'),
  ('TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RESOLVE_SUPPORT_CASE')
) AS v(top, sub, cmd)
WHERE NOT EXISTS (SELECT 1 FROM trustride.present_shell_capability_registry r WHERE r.sub_shell = v.sub::trustride.present_sub_shell_enum AND r.command_type = v.cmd);

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_open_support_case(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_s RECORD;
BEGIN
  SELECT * INTO v_s FROM trustride.present_shell_session WHERE session_id = p_session;
  RETURN trustride.fn_business_support_case_open(v_s.user_id, v_s.sub_shell, coalesce(p_payload->>'category', 'OTHER'), p_payload->>'subject', p_payload->>'body',
    (p_payload->>'order_id')::uuid, NULL);
END;
$$;

-- An operator's problem on a job: always tied to the job, always to Office.
CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_report_problem(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_s RECORD;
  v_j RECORD;
BEGIN
  SELECT * INTO v_s FROM trustride.present_shell_session WHERE session_id = p_session;
  SELECT j.* INTO v_j FROM trustride.business_job j JOIN trustride.resource_workforce_unit wu ON wu.workforce_unit_id = j.workforce_unit_id
  WHERE j.job_id = (p_payload->>'job_id')::uuid AND wu.operator_user_id = v_s.user_id;
  IF v_j.job_id IS NULL THEN RAISE EXCEPTION 'You can only report a problem on your own job'; END IF;
  RETURN trustride.fn_business_support_case_open(v_s.user_id, 'OPERATOR_APP',
    CASE WHEN p_payload->>'category' = 'SAFETY' THEN 'SAFETY' ELSE 'OPERATOR_PROBLEM' END,
    coalesce(nullif(p_payload->>'subject', ''), 'Problem on a job'), coalesce(p_payload->>'body', p_payload->>'subject'), v_j.order_id, v_j.job_id);
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_reply_support_case(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT trustride.fn_business_support_case_message((p_payload->>'case_id')::uuid,
    (SELECT user_id FROM trustride.present_shell_session WHERE session_id = p_session), p_payload->>'body', coalesce((p_payload->>'internal')::boolean, false));
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_close_support_case(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_business_support_case_requester_action((p_payload->>'case_id')::uuid,
    (SELECT user_id FROM trustride.present_shell_session WHERE session_id = p_session), coalesce(p_payload->>'action', 'CLOSE'), p_payload->>'body');
  RETURN (p_payload->>'case_id')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_assign_support_case(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_business_support_case_assign((p_payload->>'case_id')::uuid,
    coalesce((p_payload->>'assignee_user_id')::uuid, (SELECT user_id FROM trustride.present_shell_session WHERE session_id = p_session)));
  RETURN (p_payload->>'case_id')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_resolve_support_case(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_business_support_case_resolve((p_payload->>'case_id')::uuid, p_payload->>'resolution');
  RETURN (p_payload->>'case_id')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_submit_review(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT trustride.fn_business_review_by_customer((p_payload->>'order_id')::uuid,
    (SELECT user_id FROM trustride.present_shell_session WHERE session_id = p_session), (p_payload->>'rating')::smallint, p_payload->>'comment');
$$;

-- ---------------------------------------------------------------------------
-- 7. Grants
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_integration_telemetry_ingest(TEXT, JSONB) TO service_role;

SELECT trustride.fn_platform_conformance_assert();
