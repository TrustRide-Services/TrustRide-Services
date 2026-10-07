-- ============================================================================
-- Engine 2 (Resources): the software to receive real resources
-- Implementation Completion -- Stage 4 (Resource Management), G2 (resource
-- pool), G15 (vetting/certification matching groundwork), Sec.8, Sec.28.
-- ============================================================================
-- Reused, not duplicated: resource_fleet_register, resource_workforce_unit,
-- resource_workforce_capability, resource_availability_ledger,
-- resource_custody_log, fn_resource_fleet_register, fn_resource_workforce_
-- unit_form, fn_resource_workforce_capability_register/_verify, Engine 6's
-- NTSA port, and Resources' long-dormant FLEET_VERIFICATION_UPDATED handler
-- (which now finally has an emitter).
--
-- The lifecycle a real resource follows (directive Sec.4 G2), in the
-- states this engine already defines:
--   object REGISTERED (Foundation)  -> fleet REGISTERED -> NTSA check ->
--   fleet VERIFIED / AVAILABLE -> bound to a working unit (fleet ASSIGNED) ->
--   unit OFFLINE (off duty) <-> AVAILABLE (on duty) -> RESERVED (allocated
--   to an order) -> ASSIGNED (job active) -> released -> AVAILABLE.
-- A motorcycle may sit at "registered, awaiting operator" or "verified,
-- awaiting tracking device" indefinitely -- that is a waiting state, not a
-- software gap.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Telemetry identity: which tracking device is fitted to which vehicle
-- ---------------------------------------------------------------------------
CREATE TABLE trustride.resource_telemetry_binding (
  binding_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  fleet_resource_id     UUID NOT NULL REFERENCES trustride.resource_fleet_register (fleet_resource_id),
  device_object_id      UUID NOT NULL,          -- Foundation object_registry.object_id (TRACKING_DEVICE), by value
  provider_code         TEXT NOT NULL DEFAULT 'PROTRACK',
  provider_device_ref   TEXT NOT NULL,          -- the provider's device identity (IMEI)
  bound_by              UUID NOT NULL,
  bound_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  unbound_at            TIMESTAMPTZ,
  status                TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'UNBOUND'))
);
CREATE UNIQUE INDEX resource_telemetry_binding_active_fleet_uq ON trustride.resource_telemetry_binding (fleet_resource_id) WHERE status = 'ACTIVE';
CREATE UNIQUE INDEX resource_telemetry_binding_active_device_uq ON trustride.resource_telemetry_binding (provider_code, provider_device_ref) WHERE status = 'ACTIVE';
COMMENT ON TABLE trustride.resource_telemetry_binding IS
  '[Trace: Implementation Completion Sec.8-9] TrustRide owns the association between a resource and the tracking device fitted to it; the provider (Protrack) only supplies the device identity and its telemetry.';
ALTER TABLE trustride.resource_telemetry_binding ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_telemetry_binding_service_write ON trustride.resource_telemetry_binding
  FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);
CREATE POLICY resource_telemetry_binding_office_read ON trustride.resource_telemetry_binding
  FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR', 'EXECUTIVE']));
GRANT SELECT ON trustride.resource_telemetry_binding TO trustride_authenticated;


-- ---------------------------------------------------------------------------
-- 2. Office gate and vocabulary helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_resource_office_gate()
RETURNS UUID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  IF NOT trustride.fn_am_i_role(ARRAY['FOUNDER', 'ADMINISTRATOR']) THEN
    RAISE EXCEPTION 'Resource management is a TrustRide Office function (Founder or Administrator)';
  END IF;
  RETURN auth.uid();
END;
$$;

-- Which vehicle object may serve which capacity class.
CREATE OR REPLACE FUNCTION trustride.fn_resource_object_fits_class(p_object_type TEXT, p_class trustride.resource_capacity_class_enum)
RETURNS BOOLEAN LANGUAGE sql IMMUTABLE AS $$
  SELECT (p_object_type, p_class::text) IN (('MOTORCYCLE', 'BODA_BODA'), ('TUKTUK', 'TUKTUK'), ('CAR', 'SEDAN'),
    ('PICKUP', 'PICKUP_TOWN'), ('VAN', 'VAN_CARGO'), ('TRUCK', 'TRUCK_LIGHT'));
$$;

CREATE OR REPLACE FUNCTION trustride.fn_resource_unit_availability(p_unit_id UUID)
RETURNS trustride.resource_availability_state_enum LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT availability_state FROM trustride.resource_availability_ledger
  WHERE resource_type = 'WORKFORCE_UNIT' AND resource_ref_id = p_unit_id AND effective_to IS NULL
  ORDER BY effective_from DESC LIMIT 1;
$$;

-- Move a ledger to a new state (closing the current row). Internal.
CREATE OR REPLACE FUNCTION trustride.fn_resource_availability_move(p_type trustride.resource_custody_type_enum, p_ref UUID,
  p_to trustride.resource_availability_state_enum, p_reason TEXT, p_by UUID, p_order_id UUID DEFAULT NULL, p_order_line_id UUID DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_id UUID;
BEGIN
  UPDATE trustride.resource_availability_ledger SET effective_to = now()
  WHERE resource_type = p_type AND resource_ref_id = p_ref AND effective_to IS NULL;
  INSERT INTO trustride.resource_availability_ledger (resource_type, resource_ref_id, availability_state, reason_code, job_ref_id, order_line_id, changed_by)
  VALUES (p_type, p_ref, p_to, p_reason, p_order_id, p_order_line_id, coalesce(p_by, '00000000-0000-0000-0000-000000000000'::uuid))
  RETURNING availability_id INTO v_id;
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. Bases (estates)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_resource_office_estate_register(p_estate_code TEXT, p_estate_type trustride.resource_estate_type_enum,
  p_estate_name TEXT, p_lat NUMERIC, p_lon NUMERIC, p_jurisdiction TEXT, p_capacity_description TEXT DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_by UUID := trustride.fn_resource_office_gate();
  v_id UUID;
BEGIN
  v_id := trustride.fn_resource_estate_register(upper(trim(p_estate_code)), p_estate_type, trim(p_estate_name), p_lat, p_lon, p_jurisdiction, v_by, p_capacity_description);
  UPDATE trustride.resource_estate_register SET lifecycle_state = 'VERIFIED', updated_at = now() WHERE estate_id = v_id;
  RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4. Vehicles: register into the fleet, then NTSA verification via Engine 6
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_resource_office_fleet_register(p_object_id UUID, p_capacity_class trustride.resource_capacity_class_enum,
  p_ownership_type trustride.resource_ownership_type_enum, p_home_estate_id UUID, p_inspection_status TEXT, p_insurance_status TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_by UUID := trustride.fn_resource_office_gate();
  v_obj RECORD;
  v_fleet UUID;
BEGIN
  SELECT object_id, object_type, plate_number, custody_user_id, status INTO v_obj FROM trustride.object_registry WHERE object_id = p_object_id;
  IF v_obj.object_id IS NULL THEN
    RAISE EXCEPTION 'Register the vehicle as an Object first';
  END IF;
  IF NOT trustride.fn_resource_object_fits_class(v_obj.object_type, p_capacity_class) THEN
    RAISE EXCEPTION 'A % cannot serve the % class', lower(v_obj.object_type), p_capacity_class;
  END IF;
  IF EXISTS (SELECT 1 FROM trustride.resource_fleet_register WHERE object_id = p_object_id AND active) THEN
    RAISE EXCEPTION 'This vehicle is already in the fleet register';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trustride.resource_estate_register WHERE estate_id = p_home_estate_id AND active) THEN
    RAISE EXCEPTION 'Choose an active base for the vehicle';
  END IF;
  IF p_inspection_status NOT IN ('PASSED', 'PENDING', 'FAILED') OR p_insurance_status NOT IN ('ACTIVE', 'PENDING', 'EXPIRED') THEN
    RAISE EXCEPTION 'Inspection is PASSED/PENDING/FAILED; insurance is ACTIVE/PENDING/EXPIRED';
  END IF;

  v_fleet := trustride.fn_resource_fleet_register(p_object_id, p_capacity_class, p_ownership_type, v_obj.plate_number, p_home_estate_id,
    coalesce(v_obj.custody_user_id, v_by));
  UPDATE trustride.resource_fleet_register SET inspection_status = p_inspection_status, insurance_status = p_insurance_status
  WHERE fleet_resource_id = v_fleet;

  -- Resources never calls NTSA itself (Article 33): Engine 6 does.
  INSERT INTO trustride.resource_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (gen_random_uuid(), 'TRS026_ENG006_INTG', 'FLEET_VERIFICATION_REQUESTED',
    jsonb_build_object('fleet_resource_id', v_fleet, 'object_id', p_object_id, 'plate_number', v_obj.plate_number,
      'inspection_status', p_inspection_status, 'insurance_status', p_insurance_status),
    'FLEET_VERIFICATION_REQUESTED:' || v_fleet::text || ':' || extract(epoch FROM now())::text);
  RETURN v_fleet;
END;
$$;

-- Re-run verification after documents change (new insurance, re-inspection).
CREATE OR REPLACE FUNCTION trustride.fn_resource_office_fleet_reverify(p_fleet_resource_id UUID, p_inspection_status TEXT, p_insurance_status TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_by UUID := trustride.fn_resource_office_gate();
  v_f RECORD;
BEGIN
  SELECT f.fleet_resource_id, f.object_id, f.registration_particulars INTO v_f FROM trustride.resource_fleet_register f WHERE f.fleet_resource_id = p_fleet_resource_id AND f.active;
  IF v_f.fleet_resource_id IS NULL THEN RAISE EXCEPTION 'No active fleet resource %', p_fleet_resource_id; END IF;
  UPDATE trustride.resource_fleet_register SET inspection_status = p_inspection_status, insurance_status = p_insurance_status, updated_at = now()
  WHERE fleet_resource_id = p_fleet_resource_id;
  INSERT INTO trustride.resource_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (gen_random_uuid(), 'TRS026_ENG006_INTG', 'FLEET_VERIFICATION_REQUESTED',
    jsonb_build_object('fleet_resource_id', p_fleet_resource_id, 'object_id', v_f.object_id, 'plate_number', v_f.registration_particulars,
      'inspection_status', p_inspection_status, 'insurance_status', p_insurance_status),
    'FLEET_VERIFICATION_REQUESTED:' || p_fleet_resource_id::text || ':' || extract(epoch FROM clock_timestamp())::text);
END;
$$;

-- Engine 6: NTSA vehicle-registration check, outcome to Resources (fleet
-- compliance) and Foundation (the Object's own verification).
CREATE OR REPLACE FUNCTION trustride.fn_integration_fleet_verification_requested_accept(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_corr UUID;
  v_log UUID;
  v_outcome TEXT;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_corr FROM trustride.integration_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'no RECEIVED signal %', p_signal_id; END IF;
  v_log := trustride.fn_integration_ntsa_verify('VEHICLE_REGISTRATION', v_payload->>'plate_number', v_corr);
  SELECT outcome::text INTO v_outcome FROM trustride.integration_ntsa_verification_log WHERE ntsa_verification_id = v_log;

  INSERT INTO trustride.integration_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v_corr, 'TRS026_ENG002_RESC', 'FLEET_VERIFICATION_UPDATED',
    jsonb_build_object('fleet_resource_id', v_payload->>'fleet_resource_id', 'ntsa_outcome', v_outcome,
      'inspection_status', CASE WHEN v_outcome = 'VALID' THEN v_payload->>'inspection_status' ELSE 'FAILED' END,
      'insurance_status', v_payload->>'insurance_status'),
    'FLEET_VERIFICATION_UPDATED:' || v_log::text);
  INSERT INTO trustride.integration_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v_corr, 'TRS026_ENG001_FDN', 'OBJECT_VERIFICATION_UPDATED',
    jsonb_build_object('object_id', v_payload->>'object_id', 'registration_type', 'NTSA_REG', 'ntsa_outcome', v_outcome),
    'OBJECT_VERIFICATION_UPDATED:' || v_log::text);
  UPDATE trustride.integration_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('ntsa_outcome', v_outcome)
  WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

-- Foundation: an Object's statutory registration outcome.
CREATE OR REPLACE FUNCTION trustride.fn_object_verification_updated_accept(p_signal_id UUID)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_obj RECORD;
  v_ok BOOLEAN;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.platform_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'no RECEIVED signal %', p_signal_id; END IF;
  SELECT object_id, user_id INTO v_obj FROM trustride.object_registry WHERE object_id = (v_payload->>'object_id')::uuid;
  v_ok := v_payload->>'ntsa_outcome' = 'VALID';
  UPDATE trustride.object_registration SET status = CASE WHEN v_ok THEN 'ACTIVE' ELSE 'REJECTED' END,
    verified_at = CASE WHEN v_ok THEN now() END
  WHERE object_id = v_obj.object_id AND registration_type = coalesce(v_payload->>'registration_type', 'NTSA_REG');
  UPDATE trustride.object_registry SET status = CASE WHEN v_ok THEN 'ACTIVE' ELSE 'VERIFICATION_FAILED' END, updated_at = now()
  WHERE object_id = v_obj.object_id;
  UPDATE trustride.platform_users SET status = CASE WHEN v_ok THEN 'ACTIVE' ELSE 'VERIFICATION_FAILED' END, updated_at = now()
  WHERE user_id = v_obj.user_id;
  UPDATE trustride.platform_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

-- Resources: the dormant handler expected inspection/insurance statuses;
-- it now also honours the NTSA outcome (a plate NTSA cannot find is never
-- compliant, whatever the documents say).
CREATE OR REPLACE FUNCTION trustride.fn_resource_fleet_verification_updated_accept(p_signal_id uuid)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_payload JSONB;
  v_fleet UUID;
  v_compliant BOOLEAN;
  v_bound BOOLEAN;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.resource_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN RAISE EXCEPTION 'fn_resource_fleet_verification_updated_accept: no RECEIVED signal %', p_signal_id; END IF;
  v_fleet := (v_payload->>'fleet_resource_id')::uuid;
  v_compliant := v_payload->>'inspection_status' = 'PASSED' AND v_payload->>'insurance_status' = 'ACTIVE'
    AND coalesce(v_payload->>'ntsa_outcome', 'VALID') = 'VALID';

  UPDATE trustride.resource_fleet_register
  SET inspection_status = v_payload->>'inspection_status', insurance_status = v_payload->>'insurance_status',
      lifecycle_state = (CASE WHEN v_compliant THEN 'VERIFIED' ELSE 'REGISTERED' END)::trustride.resource_lifecycle_state_enum, updated_at = now()
  WHERE fleet_resource_id = v_fleet;

  -- A vehicle already bound to a working unit stays ASSIGNED to it when it
  -- passes; when it fails it goes OFFLINE and its unit is taken off duty.
  v_bound := EXISTS (SELECT 1 FROM trustride.resource_workforce_unit WHERE fleet_resource_id = v_fleet AND unit_status = 'ACTIVE');
  PERFORM trustride.fn_resource_availability_move('FLEET', v_fleet,
    (CASE WHEN v_compliant AND v_bound THEN 'ASSIGNED' WHEN v_compliant THEN 'AVAILABLE' ELSE 'OFFLINE' END)::trustride.resource_availability_state_enum,
    CASE WHEN v_compliant THEN 'VERIFICATION_PASSED' ELSE 'VERIFICATION_FAILED_NON_COMPLIANT' END, NULL);
  IF NOT v_compliant AND v_bound THEN
    PERFORM trustride.fn_resource_availability_move('WORKFORCE_UNIT', wu.workforce_unit_id, 'OFFLINE', 'VEHICLE_NON_COMPLIANT', NULL)
    FROM trustride.resource_workforce_unit wu
    WHERE wu.fleet_resource_id = v_fleet AND wu.unit_status = 'ACTIVE'
      AND trustride.fn_resource_unit_availability(wu.workforce_unit_id) = 'AVAILABLE';
  END IF;
  UPDATE trustride.resource_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Working units: onboarding, duty, intervention, dissolution
-- ---------------------------------------------------------------------------
-- Form an approved operator into a working unit. Whether the operator is
-- approved is Business's knowledge; the Office command (Engine 11) checks it
-- before calling here. This function owns everything Resources must ensure.
CREATE OR REPLACE FUNCTION trustride.fn_resource_office_unit_form(p_operator_user_id UUID, p_capacity_class trustride.resource_capacity_class_enum,
  p_estate_id UUID, p_fleet_resource_id UUID DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_by UUID := trustride.fn_resource_office_gate();
  v_class RECORD;
  v_fleet RECORD;
  v_unit UUID;
BEGIN
  SELECT * INTO v_class FROM trustride.resource_capacity_class WHERE class_code = p_capacity_class AND active;
  IF v_class.capacity_class_id IS NULL THEN RAISE EXCEPTION 'Unknown capacity class %', p_capacity_class; END IF;
  IF NOT EXISTS (SELECT 1 FROM trustride.resource_estate_register WHERE estate_id = p_estate_id AND active) THEN
    RAISE EXCEPTION 'Choose an active base';
  END IF;
  IF EXISTS (SELECT 1 FROM trustride.resource_workforce_unit WHERE operator_user_id = p_operator_user_id AND unit_status = 'ACTIVE') THEN
    RAISE EXCEPTION 'This operator already has an active working unit -- dissolve it first';
  END IF;

  IF v_class.requires_fleet THEN
    IF p_fleet_resource_id IS NULL THEN
      RAISE EXCEPTION 'The % class needs a vehicle', p_capacity_class;
    END IF;
    SELECT f.*, cc.class_code INTO v_fleet FROM trustride.resource_fleet_register f
    JOIN trustride.resource_capacity_class cc ON cc.capacity_class_id = f.capacity_class_id
    WHERE f.fleet_resource_id = p_fleet_resource_id AND f.active;
    IF v_fleet.fleet_resource_id IS NULL THEN RAISE EXCEPTION 'Unknown vehicle'; END IF;
    IF v_fleet.class_code <> p_capacity_class THEN
      RAISE EXCEPTION 'This vehicle is registered for the % class', v_fleet.class_code;
    END IF;
    IF v_fleet.lifecycle_state <> 'VERIFIED' THEN
      RAISE EXCEPTION 'This vehicle has not passed verification yet (NTSA, inspection, insurance)';
    END IF;
    IF EXISTS (SELECT 1 FROM trustride.resource_workforce_unit WHERE fleet_resource_id = p_fleet_resource_id AND unit_status = 'ACTIVE') THEN
      RAISE EXCEPTION 'This vehicle is already bound to another working unit';
    END IF;
  ELSIF p_fleet_resource_id IS NOT NULL THEN
    RAISE EXCEPTION 'The % class does not take a vehicle', p_capacity_class;
  END IF;

  v_unit := trustride.fn_resource_workforce_unit_form(p_operator_user_id, p_capacity_class, p_estate_id, p_fleet_resource_id);
  -- A new unit starts OFF DUTY: only operators who start their shift are
  -- offered work.
  PERFORM trustride.fn_resource_availability_move('WORKFORCE_UNIT', v_unit, 'OFFLINE', 'ONBOARDED_OFF_DUTY', v_by);
  IF p_fleet_resource_id IS NOT NULL THEN
    PERFORM trustride.fn_resource_availability_move('FLEET', p_fleet_resource_id, 'ASSIGNED', 'BOUND_TO_WORKFORCE_UNIT', v_by);
    PERFORM trustride.fn_resource_custody_transfer('FLEET', p_fleet_resource_id, p_operator_user_id, p_estate_id, v_by);
  END IF;
  RETURN v_unit;
END;
$$;

-- An operator starts or ends their shift (their own unit only).
CREATE OR REPLACE FUNCTION trustride.fn_resource_operator_duty_set(p_on_duty BOOLEAN)
RETURNS trustride.resource_availability_state_enum LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_unit RECORD;
  v_state trustride.resource_availability_state_enum;
  v_fleet_state trustride.resource_availability_state_enum;
BEGIN
  SELECT * INTO v_unit FROM trustride.resource_workforce_unit WHERE operator_user_id = auth.uid() AND unit_status = 'ACTIVE';
  IF v_unit.workforce_unit_id IS NULL THEN
    RAISE EXCEPTION 'You are not formed into a working unit yet -- TrustRide Office completes your onboarding';
  END IF;
  v_state := trustride.fn_resource_unit_availability(v_unit.workforce_unit_id);
  IF p_on_duty THEN
    IF v_state = 'AVAILABLE' THEN RETURN v_state; END IF;
    IF v_state <> 'OFFLINE' THEN
      RAISE EXCEPTION 'Your unit is % -- it cannot go on duty now', lower(v_state::text);
    END IF;
    IF v_unit.fleet_resource_id IS NOT NULL THEN
      SELECT availability_state INTO v_fleet_state FROM trustride.resource_availability_ledger
      WHERE resource_type = 'FLEET' AND resource_ref_id = v_unit.fleet_resource_id AND effective_to IS NULL;
      IF v_fleet_state IS DISTINCT FROM 'ASSIGNED' OR NOT EXISTS (
           SELECT 1 FROM trustride.resource_fleet_register WHERE fleet_resource_id = v_unit.fleet_resource_id AND lifecycle_state = 'VERIFIED' AND active) THEN
        RAISE EXCEPTION 'Your vehicle is not cleared for duty (verification, maintenance or documents) -- contact TrustRide Office';
      END IF;
    END IF;
    PERFORM trustride.fn_resource_availability_move('WORKFORCE_UNIT', v_unit.workforce_unit_id, 'AVAILABLE', 'SHIFT_STARTED', auth.uid());
    RETURN 'AVAILABLE';
  ELSE
    IF v_state = 'OFFLINE' THEN RETURN v_state; END IF;
    IF v_state IN ('RESERVED', 'ASSIGNED') THEN
      RAISE EXCEPTION 'Finish your current job before ending your shift';
    END IF;
    PERFORM trustride.fn_resource_availability_move('WORKFORCE_UNIT', v_unit.workforce_unit_id, 'OFFLINE', 'SHIFT_ENDED', auth.uid());
    RETURN 'OFFLINE';
  END IF;
END;
$$;

-- Office intervention: take a unit off duty, send it (and its vehicle) to
-- maintenance, or return it to service. Never while it is on a job.
CREATE OR REPLACE FUNCTION trustride.fn_resource_office_unit_state_set(p_unit_id UUID, p_state trustride.resource_availability_state_enum, p_reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_by UUID := trustride.fn_resource_office_gate();
  v_unit RECORD;
  v_cur trustride.resource_availability_state_enum;
BEGIN
  SELECT * INTO v_unit FROM trustride.resource_workforce_unit WHERE workforce_unit_id = p_unit_id AND unit_status = 'ACTIVE';
  IF v_unit.workforce_unit_id IS NULL THEN RAISE EXCEPTION 'No active working unit %', p_unit_id; END IF;
  IF p_state NOT IN ('AVAILABLE', 'OFFLINE', 'MAINTENANCE') THEN
    RAISE EXCEPTION 'Office may set a unit AVAILABLE, OFFLINE or MAINTENANCE';
  END IF;
  IF coalesce(trim(p_reason), '') = '' THEN RAISE EXCEPTION 'State the reason'; END IF;
  v_cur := trustride.fn_resource_unit_availability(p_unit_id);
  IF v_cur IN ('RESERVED', 'ASSIGNED') THEN
    RAISE EXCEPTION 'This unit is on a job -- resolve or reassign the job first';
  END IF;
  PERFORM trustride.fn_resource_availability_move('WORKFORCE_UNIT', p_unit_id, p_state, 'OFFICE: ' || p_reason, v_by);
  IF v_unit.fleet_resource_id IS NOT NULL THEN
    PERFORM trustride.fn_resource_availability_move('FLEET', v_unit.fleet_resource_id,
      CASE WHEN p_state = 'MAINTENANCE' THEN 'MAINTENANCE' ELSE 'ASSIGNED' END::trustride.resource_availability_state_enum,
      'OFFICE: ' || p_reason, v_by);
  END IF;
  PERFORM trustride.fn_audit_log_append('resource_workforce_unit', p_unit_id, 'UNIT_STATE_SET_BY_OFFICE', v_by, 'USER', NULL, 'TRUSTRIDE_OFFICE',
    jsonb_build_object('from', v_cur), jsonb_build_object('to', p_state, 'reason', p_reason));
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_resource_office_unit_dissolve(p_unit_id UUID, p_reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_by UUID := trustride.fn_resource_office_gate();
  v_unit RECORD;
  v_owner UUID;
BEGIN
  SELECT * INTO v_unit FROM trustride.resource_workforce_unit WHERE workforce_unit_id = p_unit_id AND unit_status = 'ACTIVE';
  IF v_unit.workforce_unit_id IS NULL THEN RAISE EXCEPTION 'No active working unit %', p_unit_id; END IF;
  IF trustride.fn_resource_unit_availability(p_unit_id) IN ('RESERVED', 'ASSIGNED') THEN
    RAISE EXCEPTION 'This unit is on a job -- resolve the job first';
  END IF;
  UPDATE trustride.resource_workforce_unit SET unit_status = 'INACTIVE', dissolved_at = now() WHERE workforce_unit_id = p_unit_id;
  PERFORM trustride.fn_resource_availability_move('WORKFORCE_UNIT', p_unit_id, 'RETIRED', 'DISSOLVED: ' || coalesce(p_reason, ''), v_by);
  IF v_unit.fleet_resource_id IS NOT NULL THEN
    -- The vehicle returns to its owner's custody and to the pool.
    SELECT o.custody_user_id INTO v_owner FROM trustride.resource_fleet_register f JOIN trustride.object_registry o ON o.object_id = f.object_id
    WHERE f.fleet_resource_id = v_unit.fleet_resource_id;
    PERFORM trustride.fn_resource_custody_transfer('FLEET', v_unit.fleet_resource_id, coalesce(v_owner, v_by), NULL, v_by);
    PERFORM trustride.fn_resource_availability_move('FLEET', v_unit.fleet_resource_id, 'AVAILABLE', 'UNBOUND_FROM_UNIT', v_by);
  END IF;
END;
$$;

-- Office records a credential (good conduct, first aid, PSV licence,
-- enhanced vetting clearance, an EA skill) after checking the document.
CREATE OR REPLACE FUNCTION trustride.fn_resource_office_capability_record(p_unit_id UUID, p_capability_type trustride.resource_capability_type_enum,
  p_credential_ref TEXT, p_expires_at TIMESTAMPTZ DEFAULT NULL)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_by UUID := trustride.fn_resource_office_gate();
  v_id UUID;
BEGIN
  IF coalesce(trim(p_credential_ref), '') = '' THEN RAISE EXCEPTION 'Record the certificate or reference number'; END IF;
  UPDATE trustride.resource_workforce_capability SET active = FALSE
  WHERE workforce_unit_id = p_unit_id AND capability_type = p_capability_type AND active;
  v_id := trustride.fn_resource_workforce_capability_register(p_unit_id, p_capability_type, trim(p_credential_ref));
  PERFORM trustride.fn_resource_workforce_capability_verify(v_id, v_by, p_expires_at);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_resource_office_capability_revoke(p_capability_id UUID, p_reason TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_by UUID := trustride.fn_resource_office_gate();
BEGIN
  UPDATE trustride.resource_workforce_capability SET active = FALSE WHERE capability_id = p_capability_id AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'No active capability %', p_capability_id; END IF;
  PERFORM trustride.fn_audit_log_append('resource_workforce_capability', p_capability_id, 'CAPABILITY_REVOKED', v_by, 'USER', NULL, 'TRUSTRIDE_OFFICE', NULL,
    jsonb_build_object('reason', p_reason));
END;
$$;

-- ---------------------------------------------------------------------------
-- 6. Eligibility (G15): vetting tier and certifications, not just class
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_resource_unit_meets(p_unit_id UUID, p_vetting_tier TEXT, p_certifications JSONB)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = trustride, public AS $$
  WITH caps AS (
    SELECT capability_type::text AS t FROM trustride.resource_workforce_capability
    WHERE workforce_unit_id = p_unit_id AND active AND verified AND (expires_at IS NULL OR expires_at > now())
  )
  SELECT (coalesce(p_vetting_tier, 'STANDARD') <> 'ENHANCED' OR EXISTS (SELECT 1 FROM caps WHERE t = 'ENHANCED_VETTING_CLEARANCE'))
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements_text(coalesce(p_certifications, '[]'::jsonb)) req(t)
                     WHERE req.t NOT IN (SELECT t FROM caps));
$$;

CREATE OR REPLACE FUNCTION trustride.fn_resource_discover_eligible(p_required_capacity_class trustride.resource_capacity_class_enum,
  p_pickup_lat NUMERIC, p_pickup_lon NUMERIC, p_vetting_tier TEXT, p_certifications JSONB, p_jurisdiction TEXT)
RETURNS TABLE (workforce_unit_id UUID, fleet_resource_id UUID, capacity_class trustride.resource_capacity_class_enum, distance_km NUMERIC,
  availability_state trustride.resource_availability_state_enum)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = trustride, extensions, public AS $$
DECLARE
  v_pickup GEOMETRY := ST_SetSRID(ST_MakePoint(p_pickup_lon, p_pickup_lat), 4326);
BEGIN
  RETURN QUERY
  SELECT wu.workforce_unit_id, wu.fleet_resource_id, cc.class_code,
    round((ST_DistanceSphere(v_pickup, er.location) / 1000.0)::numeric, 2), al.availability_state
  FROM trustride.resource_workforce_unit wu
  JOIN trustride.resource_capacity_class cc ON cc.capacity_class_id = wu.capacity_class_id
  JOIN trustride.resource_estate_register er ON er.estate_id = wu.primary_estate_id
  JOIN trustride.resource_availability_ledger al ON al.resource_type = 'WORKFORCE_UNIT' AND al.resource_ref_id = wu.workforce_unit_id AND al.effective_to IS NULL
  LEFT JOIN trustride.resource_fleet_register f ON f.fleet_resource_id = wu.fleet_resource_id
  WHERE cc.class_code = p_required_capacity_class
    AND wu.unit_status = 'ACTIVE'
    AND al.availability_state = 'AVAILABLE'
    AND (p_jurisdiction IS NULL OR er.jurisdiction = p_jurisdiction)
    AND (NOT cc.requires_fleet OR (f.active AND f.lifecycle_state = 'VERIFIED'))
    AND trustride.fn_resource_unit_meets(wu.workforce_unit_id, p_vetting_tier, p_certifications)
  ORDER BY 4 ASC, al.effective_from ASC;  -- nearest first; longest-waiting breaks ties
END;
$$;

-- ---------------------------------------------------------------------------
-- 7. Telemetry device binding (Office)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_resource_office_telemetry_bind(p_fleet_resource_id UUID, p_device_object_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_by UUID := trustride.fn_resource_office_gate();
  v_dev RECORD;
  v_id UUID;
BEGIN
  SELECT object_id, object_type, serial_number, make, status INTO v_dev FROM trustride.object_registry WHERE object_id = p_device_object_id;
  IF v_dev.object_id IS NULL OR v_dev.object_type <> 'TRACKING_DEVICE' THEN
    RAISE EXCEPTION 'Register the tracking device as an Object (type TRACKING_DEVICE) first';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trustride.resource_fleet_register WHERE fleet_resource_id = p_fleet_resource_id AND active) THEN
    RAISE EXCEPTION 'Unknown vehicle';
  END IF;
  UPDATE trustride.resource_telemetry_binding SET status = 'UNBOUND', unbound_at = now()
  WHERE status = 'ACTIVE' AND (fleet_resource_id = p_fleet_resource_id OR provider_device_ref = v_dev.serial_number);
  INSERT INTO trustride.resource_telemetry_binding (fleet_resource_id, device_object_id, provider_code, provider_device_ref, bound_by)
  VALUES (p_fleet_resource_id, p_device_object_id, 'PROTRACK', v_dev.serial_number, v_by) RETURNING binding_id INTO v_id;
  PERFORM trustride.fn_resource_custody_transfer('DEVICE', p_device_object_id, v_by, NULL, v_by);
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_resource_office_telemetry_unbind(p_fleet_resource_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_by UUID := trustride.fn_resource_office_gate();
BEGIN
  UPDATE trustride.resource_telemetry_binding SET status = 'UNBOUND', unbound_at = now() WHERE fleet_resource_id = p_fleet_resource_id AND status = 'ACTIVE';
  IF NOT FOUND THEN RAISE EXCEPTION 'No tracking device is bound to this vehicle'; END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 8. Signals and routes
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trustride.fn_resource_inbox_process(p_signal_id uuid)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_signal_type TEXT;
  v_result TEXT;
BEGIN
  SELECT signal_type INTO v_signal_type FROM trustride.resource_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_signal_type IS NULL THEN
    RAISE EXCEPTION 'fn_resource_inbox_process: no RECEIVED signal %', p_signal_id;
  END IF;
  CASE v_signal_type
    WHEN 'ASSIGNMENT_REQUESTED' THEN v_result := trustride.fn_resource_assignment_requested_accept(p_signal_id);
    WHEN 'RESOURCE_ASSIGNMENT_CONFIRMED' THEN v_result := trustride.fn_resource_assignment_confirmed_accept(p_signal_id);
    WHEN 'JOB_COMPLETED' THEN v_result := trustride.fn_resource_job_completed_accept(p_signal_id);
    WHEN 'FLEET_VERIFICATION_UPDATED' THEN v_result := trustride.fn_resource_fleet_verification_updated_accept(p_signal_id);
    WHEN 'MARKETPLACE_LISTING_SOLD' THEN v_result := trustride.fn_resource_marketplace_listing_sold_accept(p_signal_id);
    ELSE
      UPDATE trustride.resource_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'UNREGISTERED_SIGNAL_TYPE:' || v_signal_type WHERE signal_id = p_signal_id;
      v_result := 'REJECTED';
  END CASE;
  RETURN v_result;
END;
$$;

DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  -- Engine 6 inbox: + FLEET_VERIFICATION_REQUESTED
  SELECT pg_get_functiondef('trustride.fn_integration_inbox_process(uuid)'::regprocedure) INTO v_def;
  IF position('FLEET_VERIFICATION_REQUESTED' IN v_def) = 0 THEN
    v_def := replace(v_def, E'    ELSE\n      UPDATE trustride.integration_event_inbox',
      E'    WHEN ''FLEET_VERIFICATION_REQUESTED'' THEN v_result := trustride.fn_integration_fleet_verification_requested_accept(p_signal_id);\n    ELSE\n      UPDATE trustride.integration_event_inbox');
    IF position('FLEET_VERIFICATION_REQUESTED' IN v_def) = 0 THEN RAISE EXCEPTION 'integration inbox patch did not apply'; END IF;
    EXECUTE v_def;
  END IF;
  -- Foundation inbox: + OBJECT_VERIFICATION_UPDATED
  SELECT pg_get_functiondef('trustride.fn_platform_inbox_process(uuid)'::regprocedure) INTO v_def;
  IF position('OBJECT_VERIFICATION_UPDATED' IN v_def) = 0 THEN
    v_def := replace(v_def, E'    ELSE\n      UPDATE trustride.platform_event_inbox',
      E'    WHEN ''OBJECT_VERIFICATION_UPDATED'' THEN\n      v_result := trustride.fn_object_verification_updated_accept(p_signal_id);\n    ELSE\n      UPDATE trustride.platform_event_inbox');
    IF position('OBJECT_VERIFICATION_UPDATED' IN v_def) = 0 THEN RAISE EXCEPTION 'platform inbox patch did not apply'; END IF;
    EXECUTE v_def;
  END IF;
END;
$patch$;

INSERT INTO trustride.routing_rule (event_type, source_engine, target_engine, route_priority)
SELECT v.e, v.s, v.t, 0
FROM (VALUES
  ('FLEET_VERIFICATION_REQUESTED', 'TRS026_ENG002_RESC', 'TRS026_ENG006_INTG'),
  ('FLEET_VERIFICATION_UPDATED', 'TRS026_ENG006_INTG', 'TRS026_ENG002_RESC'),
  ('OBJECT_VERIFICATION_UPDATED', 'TRS026_ENG006_INTG', 'TRS026_ENG001_FDN')
) AS v(e, s, t)
WHERE NOT EXISTS (SELECT 1 FROM trustride.routing_rule r WHERE r.event_type = v.e AND r.source_engine = v.s AND r.target_engine = v.t);
SELECT trustride.fn_orch_destination_cache_sync();

-- ---------------------------------------------------------------------------
-- 9. Engine 11: pluggable command handlers + the Office/Operator commands
-- ---------------------------------------------------------------------------
-- From here on, a verb's live handler is a function named
-- fn_present_cmd_<verb>(session_id, payload, command_id) RETURNS UUID.
-- fn_present_capture_command keeps every existing verb exactly as it was
-- and, for any other permitted verb, calls its handler when one exists --
-- so each completion stage adds verbs without rewriting the dispatcher.
DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_present_capture_command(uuid,text,jsonb)'::regprocedure) INTO v_def;
  IF position('fn_present_cmd_' IN v_def) = 0 THEN
    v_def := replace(v_def,
      E'      ELSE\n        NULL; -- registered verb, no live domain handler yet -- captured, never faked',
      E'      ELSE\n'
      || E'        IF to_regprocedure(''trustride.fn_present_cmd_'' || lower(p_command_type) || ''(uuid,jsonb,uuid)'') IS NOT NULL THEN\n'
      || E'          EXECUTE format(''SELECT trustride.%I($1, $2, $3)'', ''fn_present_cmd_'' || lower(p_command_type))\n'
      || E'            INTO v_translated_signal_id USING p_shell_session_id, p_command_payload, v_command_id;\n'
      || E'          v_translation_status := ''TRANSLATED'';\n'
      || E'        END IF; -- otherwise: registered verb, no live domain handler yet -- captured, never faked');
    IF position('fn_present_cmd_' IN v_def) = 0 THEN RAISE EXCEPTION 'capture command patch did not apply'; END IF;
    EXECUTE v_def;
  END IF;
END;
$patch$;

INSERT INTO trustride.present_shell_capability_registry (top_shell, sub_shell, command_type, permitted, requires_delegated_authority)
SELECT 'TRUSTRIDE_OFFICE', v.sub::trustride.present_sub_shell_enum, v.cmd, TRUE, FALSE
FROM (VALUES
  ('ADMIN_CONSOLE', 'REGISTER_ESTATE'), ('ADMIN_CONSOLE', 'REGISTER_OBJECT'), ('ADMIN_CONSOLE', 'REGISTER_FLEET'),
  ('ADMIN_CONSOLE', 'REVERIFY_FLEET'), ('ADMIN_CONSOLE', 'ONBOARD_OPERATOR'), ('ADMIN_CONSOLE', 'SET_UNIT_STATE'),
  ('ADMIN_CONSOLE', 'DISSOLVE_UNIT'), ('ADMIN_CONSOLE', 'RECORD_CAPABILITY'), ('ADMIN_CONSOLE', 'REVOKE_CAPABILITY'),
  ('ADMIN_CONSOLE', 'BIND_TELEMETRY_DEVICE'), ('ADMIN_CONSOLE', 'UNBIND_TELEMETRY_DEVICE'),
  ('OPERATOR_APP', 'SET_DUTY')
) AS v(sub, cmd)
WHERE NOT EXISTS (SELECT 1 FROM trustride.present_shell_capability_registry r WHERE r.sub_shell = v.sub::trustride.present_sub_shell_enum AND r.command_type = v.cmd);

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_register_estate(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT trustride.fn_resource_office_estate_register(p_payload->>'estate_code', (p_payload->>'estate_type')::trustride.resource_estate_type_enum,
    p_payload->>'estate_name', (p_payload->>'lat')::numeric, (p_payload->>'lon')::numeric, coalesce(p_payload->>'jurisdiction', 'KISUMU_COUNTY'),
    p_payload->>'capacity_description');
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_register_object(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT trustride.fn_registration_capture_object(p_payload->>'object_type', p_payload->>'make', p_payload->>'model',
    (p_payload->>'year')::smallint, p_payload->>'plate_number', p_payload->>'serial_number', (p_payload->>'custody_user_id')::uuid);
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_register_fleet(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT trustride.fn_resource_office_fleet_register((p_payload->>'object_id')::uuid, (p_payload->>'capacity_class')::trustride.resource_capacity_class_enum,
    coalesce(p_payload->>'ownership_type', 'OWNED')::trustride.resource_ownership_type_enum, (p_payload->>'home_estate_id')::uuid,
    coalesce(p_payload->>'inspection_status', 'PENDING'), coalesce(p_payload->>'insurance_status', 'PENDING'));
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_reverify_fleet(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_resource_office_fleet_reverify((p_payload->>'fleet_resource_id')::uuid, p_payload->>'inspection_status', p_payload->>'insurance_status');
  RETURN (p_payload->>'fleet_resource_id')::uuid;
END;
$$;

-- Onboarding spans two engines: Business knows the operator is approved and
-- holds their employment engagement (Article 44: operators are employees);
-- Resources forms the working unit.
CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_onboard_operator(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
DECLARE
  v_operator UUID := (p_payload->>'operator_user_id')::uuid;
  v_reg UUID;
  v_unit UUID;
BEGIN
  SELECT actor_registration_id INTO v_reg FROM trustride.business_actor_registration
  WHERE user_id = v_operator AND user_type_domain = 'OPERATOR' AND registration_status = 'ACTIVE';
  IF v_reg IS NULL THEN
    RAISE EXCEPTION 'This person is not an approved Operator -- approve their Office access request first';
  END IF;
  v_unit := trustride.fn_resource_office_unit_form(v_operator, (p_payload->>'capacity_class')::trustride.resource_capacity_class_enum,
    (p_payload->>'estate_id')::uuid, (p_payload->>'fleet_resource_id')::uuid);
  IF NOT EXISTS (SELECT 1 FROM trustride.business_operator_engagement WHERE actor_registration_id = v_reg AND engagement_status = 'ACTIVE') THEN
    PERFORM trustride.fn_business_operator_engagement_open(v_reg, coalesce(p_payload->>'employment_type', 'EMPLOYEE'), current_date);
  END IF;
  INSERT INTO trustride.present_notification_inbox (recipient_user_id, top_shell, sub_shell, title, body, source_signal_correlation_id, category)
  VALUES (v_operator, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'You are onboarded',
    'Your working unit is ready. Open the Operator App and start your shift to receive jobs.', p_command, 'OPERATOR');
  RETURN v_unit;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_set_unit_state(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_resource_office_unit_state_set((p_payload->>'workforce_unit_id')::uuid,
    (p_payload->>'state')::trustride.resource_availability_state_enum, p_payload->>'reason');
  RETURN (p_payload->>'workforce_unit_id')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_dissolve_unit(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_resource_office_unit_dissolve((p_payload->>'workforce_unit_id')::uuid, p_payload->>'reason');
  RETURN (p_payload->>'workforce_unit_id')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_record_capability(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT trustride.fn_resource_office_capability_record((p_payload->>'workforce_unit_id')::uuid,
    (p_payload->>'capability_type')::trustride.resource_capability_type_enum, p_payload->>'credential_ref', (p_payload->>'expires_at')::timestamptz);
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_revoke_capability(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_resource_office_capability_revoke((p_payload->>'capability_id')::uuid, p_payload->>'reason');
  RETURN (p_payload->>'capability_id')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_bind_telemetry_device(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE sql SECURITY DEFINER SET search_path = trustride, public AS $$
  SELECT trustride.fn_resource_office_telemetry_bind((p_payload->>'fleet_resource_id')::uuid, (p_payload->>'device_object_id')::uuid);
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_unbind_telemetry_device(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_resource_office_telemetry_unbind((p_payload->>'fleet_resource_id')::uuid);
  RETURN (p_payload->>'fleet_resource_id')::uuid;
END;
$$;

CREATE OR REPLACE FUNCTION trustride.fn_present_cmd_set_duty(p_session UUID, p_payload JSONB, p_command UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public AS $$
BEGIN
  PERFORM trustride.fn_resource_operator_duty_set(coalesce((p_payload->>'on_duty')::boolean, false));
  RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------------
-- 10. Grants
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_operator_duty_set(BOOLEAN) TO trustride_authenticated;

SELECT trustride.fn_platform_conformance_assert();
