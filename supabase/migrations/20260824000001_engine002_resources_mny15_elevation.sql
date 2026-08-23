-- ============================================================================
-- TRUSTRIDE SERVICES PLATFORM
-- ============================================================================
-- PLATFORM CODE        : TRS026
-- SCHEMA               : trustride
-- ENGINE NO            : ENGINE_002 (extension)
-- ENGINE CODE          : TRS026_ENG002_RESC
-- MIGRATION DATA
-- FILE NAME            : 20260824000001_engine002_resources_mny15_elevation.sql
-- STATUS               : COMPLETE -- additive extension, no destructive
--                        changes to any already-live Engine 2 object.
-- CREATED AT           : 2026-08-24
-- CREATED BY           : Onyango Albert Chitayi (Founder) + Engineering
-- ============================================================================
--
-- FOUNDER DIRECTIVE, 2026-08-23/24: "Fully push and implement MNY-15 into the
-- Resources domain... every other resource already established in TrustRide
-- must be designed and implemented with identical rigor, depth, precision,
-- and expression... Do not assume or invent what the resources are... All
-- the resources for TrustRide already established must be fully designed in
-- this manner."
--
-- SCOPE (per the Founder's own instruction, nothing invented beyond what
-- Engine 2 already established): resource_estate_register, resource_
-- capacity_class, resource_fleet_register, resource_equipment_register,
-- resource_workforce_unit, resource_workforce_capability, resource_
-- availability_ledger, resource_financial_asset, resource_maintenance_
-- record, resource_marketplace_inventory, resource_custody_log.
--
-- THE MNY-15 MAPPING (reviewed and confirmed with the Founder before this
-- file was written):
--
--   1. THE BOUNDARY STATEMENT (mirrors MNY-15 Section 3, "Money is not
--      Payment"): RESOURCE CUSTODY IS NOT RESOURCE ASSIGNMENT. Custody --
--      registration, ownership, physical possession, financial control --
--      is a standing institutional fact about a resource. Assignment --
--      which Order Line it currently serves -- is a temporal, revocable,
--      Order-Line-scoped operational fact layered on top of custody. A
--      resource's custody history persists across every assignment it ever
--      serves; no assignment ever overwrites or erases custody history, and
--      no custody change ever silently closes an open assignment.
--   2. ORDER-LINE BINDING (mirrors Sections 4-5, 11-12): every governed
--      resource event may now carry an explicit order_line_id, distinct
--      from the order_id it was already scoped to -- resource_availability_
--      ledger gains an order_line_id column, and fn_resource_reserve/fn_
--      resource_assign gain an optional p_order_line_id parameter (additive,
--      backward-compatible -- existing callers that only ever had order_id
--      keep working unchanged).
--   3. THE TRACEABLE, HASH-CHAINED EVENT (mirrors Section 6's exact field
--      list): resource_ledger_event is the new canonical constitutional
--      record -- event_id, resource_type, resource_ref_id, order_id, order_
--      line_id, event_type, before/after state, actor_id, session_id,
--      device_id, source, decision_timestamp, chain_seq, prev_hash,
--      immutable_hash -- built on the exact fn_audit_log_append pattern
--      already proven in Foundation (monotonic chain_seq identity column,
--      never a "pick the latest by timestamp" race).
--   4. EAGLE-EYE TRACEABILITY (mirrors Section 15's 15 financial questions,
--      adapted to physical/financial/human resources): v_resource_eagle_eye
--      answers, per resource: where is it, where did it come from, why does
--      it exist, what's it for, who controls it, who's entitled to use it,
--      its complete history, its current state, what evidence supports its
--      condition/compliance, its lifecycle position, has it retired, can it
--      reconcile.
--   5. SOVEREIGN INVARIANTS (mirrors Section 25's 25 numbered rules,
--      enforced as real constraints/triggers, not documentation):
--        - resource_ledger_event is append-only forever (REVOKE UPDATE,
--          DELETE FROM PUBLIC) -- no completed resource event is ever
--          altered or deleted from historical lineage.
--        - every governed state change to a resource (availability,
--          custody, lifecycle, balance) produces a resource_ledger_event
--          automatically, via AFTER-trigger mirrors on the existing tables
--          -- there is no code path that can change resource state without
--          also generating the traceable event, because the mirror fires
--          on the table itself, not on any particular caller.
--        - retirement does not delete: a BEFORE DELETE trigger blocks hard
--          deletion outright on every core resource register (fleet,
--          equipment, estate, financial asset, marketplace inventory,
--          workforce unit) -- the only lawful way to end a resource's
--          active life is lifecycle_state = 'RETIRED' (or unit_status =
--          'INACTIVE' for workforce units), never DELETE.
--        - the hash chain is monotonic and globally verifiable (chain_seq
--          identity column, matching Foundation's own audit_log fix for
--          the exact race this session already found and corrected once).
--   6. WHAT THIS FILE DELIBERATELY DOES NOT DO: it does not touch resource_
--      capacity_class or resource_workforce_capability (pure vocabulary/
--      credential tables with no independent operational state to trace),
--      it does not rename or drop any existing table/column/function (pure
--      additive extension -- Cost's resource_cost_factor.fleet_resource_id
--      and fn_resource_assign's existing callers are unaffected), and it
--      does not touch resource_maintenance_record's own cost_kes ledger
--      (already a complete, append-only record of its own narrow kind;
--      mirrored into resource_ledger_event as a LIFECYCLE_TRANSITIONED
--      event on the fleet resource it maintains, not duplicated as its own
--      table).
--
-- ============================================================================

-- ============================================================================
-- PHASE 2 -- ENUMS
-- ============================================================================
CREATE TYPE trustride.resource_event_type_enum AS ENUM (
  'AVAILABILITY_CHANGED', 'CUSTODY_TRANSFERRED', 'LIFECYCLE_TRANSITIONED',
  'BALANCE_ADJUSTED', 'RETIRED'
);
CREATE TYPE trustride.resource_event_source_enum AS ENUM (
  'SYSTEM', 'API', 'SIGNAL_INBOUND', 'ADMIN_ACTION'
);

-- ============================================================================
-- PHASE 3 -- THE CANONICAL CONSTITUTIONAL LEDGER
-- ============================================================================
CREATE TABLE trustride.resource_ledger_event (
  event_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_type      trustride.resource_custody_type_enum NOT NULL,
  resource_ref_id    UUID NOT NULL,
  order_id           UUID,
  order_line_id      UUID,
  event_type         trustride.resource_event_type_enum NOT NULL,
  before_state       JSONB,
  after_state        JSONB,
  actor_id           UUID,
  session_id         UUID,
  device_id          TEXT,
  source             trustride.resource_event_source_enum NOT NULL DEFAULT 'SYSTEM',
  decision_timestamp TIMESTAMPTZ NOT NULL DEFAULT now(),
  chain_seq          BIGINT GENERATED ALWAYS AS IDENTITY,
  prev_hash          CHAR(64),
  immutable_hash     CHAR(64) NOT NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.resource_ledger_event IS
  'The Resources-domain equivalent of MNY-15''s traceable, hash-chained ASSIGNMENT event (Section 6) -- the single canonical record every EAGLE-EYE question is answered from. Populated exclusively by fn_resource_ledger_event_append and its AFTER-trigger mirrors; never inserted into directly by a caller.';
REVOKE UPDATE, DELETE ON trustride.resource_ledger_event FROM PUBLIC;

-- ============================================================================
-- PHASE 3b -- ORDER-LINE BINDING (additive column on the existing ledger)
-- ============================================================================
ALTER TABLE trustride.resource_availability_ledger ADD COLUMN order_line_id UUID;
COMMENT ON COLUMN trustride.resource_availability_ledger.order_line_id IS
  'MNY-15 Section 5 binding, adapted: an assignment/reservation is scoped to the specific Order Line it serves, not merely the Order -- nullable because not every availability change (e.g., MAINTENANCE, OFFLINE) is Order-Line-scoped.';

-- ============================================================================
-- PHASE 4 -- THE ONE LAWFUL WAY TO APPEND TO THE CHAIN
-- ============================================================================
CREATE OR REPLACE FUNCTION trustride.fn_resource_ledger_event_append(
  p_resource_type trustride.resource_custody_type_enum, p_resource_ref_id UUID,
  p_event_type trustride.resource_event_type_enum, p_before_state JSONB, p_after_state JSONB,
  p_actor_id UUID, p_order_id UUID DEFAULT NULL, p_order_line_id UUID DEFAULT NULL,
  p_source trustride.resource_event_source_enum DEFAULT 'SYSTEM'
)
RETURNS UUID
-- `extensions` required for digest() -- matching Foundation's own
-- fn_audit_log_append fix, the same class of bug found and corrected once
-- already this session.
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp
AS $$
DECLARE
  v_prev_hash   CHAR(64);
  v_new_id      UUID := gen_random_uuid();
  v_new_hash    CHAR(64);
  v_canonical   TEXT;
  v_occurred_at TIMESTAMPTZ := now();
BEGIN
  SELECT immutable_hash INTO v_prev_hash
  FROM trustride.resource_ledger_event ORDER BY chain_seq DESC LIMIT 1;

  v_canonical := coalesce(v_prev_hash, '') || '|' || p_resource_type::text || '|' || p_resource_ref_id::text
    || '|' || p_event_type::text || '|' || coalesce(p_before_state::text, '') || '|' || coalesce(p_after_state::text, '')
    || '|' || coalesce(p_order_id::text, '') || '|' || coalesce(p_order_line_id::text, '') || '|' || v_occurred_at::text;
  v_new_hash := encode(digest(v_canonical, 'sha256'), 'hex');

  INSERT INTO trustride.resource_ledger_event
    (event_id, resource_type, resource_ref_id, order_id, order_line_id, event_type,
     before_state, after_state, actor_id, source, decision_timestamp, prev_hash, immutable_hash)
  VALUES
    (v_new_id, p_resource_type, p_resource_ref_id, p_order_id, p_order_line_id, p_event_type,
     p_before_state, p_after_state, p_actor_id, p_source, v_occurred_at, v_prev_hash, v_new_hash);

  RETURN v_new_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_ledger_event_append IS
  'The one lawful way to append to resource_ledger_event -- correct prev_hash/immutable_hash computation every time, mirroring fn_audit_log_append exactly.';

-- ============================================================================
-- PHASE 5 -- MIRRORING TRIGGERS (every governed state change traces itself,
-- automatically, regardless of which function or caller made the change)
-- ============================================================================

CREATE OR REPLACE FUNCTION trustride.trg_fn_resource_availability_mirror()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp AS $$
BEGIN
  PERFORM trustride.fn_resource_ledger_event_append(
    NEW.resource_type, NEW.resource_ref_id, 'AVAILABILITY_CHANGED', NULL, to_jsonb(NEW),
    NEW.changed_by, NEW.job_ref_id, NEW.order_line_id, 'SYSTEM'
  );
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_resource_availability_mirror
  AFTER INSERT ON trustride.resource_availability_ledger
  FOR EACH ROW EXECUTE FUNCTION trustride.trg_fn_resource_availability_mirror();

CREATE OR REPLACE FUNCTION trustride.trg_fn_resource_custody_mirror()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp AS $$
BEGIN
  PERFORM trustride.fn_resource_ledger_event_append(
    NEW.resource_type, NEW.resource_ref_id, 'CUSTODY_TRANSFERRED', NULL, to_jsonb(NEW),
    NEW.transferred_by, NULL, NULL, 'SYSTEM'
  );
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_resource_custody_mirror
  AFTER INSERT ON trustride.resource_custody_log
  FOR EACH ROW EXECUTE FUNCTION trustride.trg_fn_resource_custody_mirror();

CREATE OR REPLACE FUNCTION trustride.trg_fn_resource_fleet_lifecycle_mirror()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp AS $$
BEGIN
  IF NEW.lifecycle_state IS DISTINCT FROM OLD.lifecycle_state THEN
    PERFORM trustride.fn_resource_ledger_event_append(
      'FLEET', NEW.fleet_resource_id,
      CASE WHEN NEW.lifecycle_state = 'RETIRED' THEN 'RETIRED'::trustride.resource_event_type_enum ELSE 'LIFECYCLE_TRANSITIONED'::trustride.resource_event_type_enum END,
      to_jsonb(OLD), to_jsonb(NEW), NULL, NULL, NULL, 'SYSTEM'
    );
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_resource_fleet_lifecycle_mirror
  AFTER UPDATE OF lifecycle_state ON trustride.resource_fleet_register
  FOR EACH ROW EXECUTE FUNCTION trustride.trg_fn_resource_fleet_lifecycle_mirror();

CREATE OR REPLACE FUNCTION trustride.trg_fn_resource_equipment_lifecycle_mirror()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp AS $$
BEGIN
  IF NEW.lifecycle_state IS DISTINCT FROM OLD.lifecycle_state THEN
    PERFORM trustride.fn_resource_ledger_event_append(
      'EQUIPMENT', NEW.equipment_id,
      CASE WHEN NEW.lifecycle_state = 'RETIRED' THEN 'RETIRED'::trustride.resource_event_type_enum ELSE 'LIFECYCLE_TRANSITIONED'::trustride.resource_event_type_enum END,
      to_jsonb(OLD), to_jsonb(NEW), NULL, NULL, NULL, 'SYSTEM'
    );
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_resource_equipment_lifecycle_mirror
  AFTER UPDATE OF lifecycle_state ON trustride.resource_equipment_register
  FOR EACH ROW EXECUTE FUNCTION trustride.trg_fn_resource_equipment_lifecycle_mirror();

CREATE OR REPLACE FUNCTION trustride.trg_fn_resource_estate_lifecycle_mirror()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp AS $$
BEGIN
  IF NEW.lifecycle_state IS DISTINCT FROM OLD.lifecycle_state THEN
    PERFORM trustride.fn_resource_ledger_event_append(
      'ESTATE', NEW.estate_id,
      CASE WHEN NEW.lifecycle_state = 'RETIRED' THEN 'RETIRED'::trustride.resource_event_type_enum ELSE 'LIFECYCLE_TRANSITIONED'::trustride.resource_event_type_enum END,
      to_jsonb(OLD), to_jsonb(NEW), NULL, NULL, NULL, 'SYSTEM'
    );
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_resource_estate_lifecycle_mirror
  AFTER UPDATE OF lifecycle_state ON trustride.resource_estate_register
  FOR EACH ROW EXECUTE FUNCTION trustride.trg_fn_resource_estate_lifecycle_mirror();

CREATE OR REPLACE FUNCTION trustride.trg_fn_resource_financial_asset_mirror()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp AS $$
BEGIN
  IF NEW.current_balance_kes IS DISTINCT FROM OLD.current_balance_kes THEN
    PERFORM trustride.fn_resource_ledger_event_append(
      'FINANCIAL_ASSET', NEW.financial_asset_id, 'BALANCE_ADJUSTED',
      to_jsonb(OLD), to_jsonb(NEW), NULL, NULL, NULL, 'SYSTEM'
    );
  END IF;
  IF NEW.lifecycle_state IS DISTINCT FROM OLD.lifecycle_state THEN
    PERFORM trustride.fn_resource_ledger_event_append(
      'FINANCIAL_ASSET', NEW.financial_asset_id,
      CASE WHEN NEW.lifecycle_state = 'RETIRED' THEN 'RETIRED'::trustride.resource_event_type_enum ELSE 'LIFECYCLE_TRANSITIONED'::trustride.resource_event_type_enum END,
      to_jsonb(OLD), to_jsonb(NEW), NULL, NULL, NULL, 'SYSTEM'
    );
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_resource_financial_asset_mirror
  AFTER UPDATE OF current_balance_kes, lifecycle_state ON trustride.resource_financial_asset
  FOR EACH ROW EXECUTE FUNCTION trustride.trg_fn_resource_financial_asset_mirror();

CREATE OR REPLACE FUNCTION trustride.trg_fn_resource_marketplace_inventory_mirror()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp AS $$
BEGIN
  IF NEW.lifecycle_state IS DISTINCT FROM OLD.lifecycle_state THEN
    PERFORM trustride.fn_resource_ledger_event_append(
      'MARKETPLACE_INVENTORY', NEW.inventory_item_id,
      CASE WHEN NEW.lifecycle_state = 'RETIRED' THEN 'RETIRED'::trustride.resource_event_type_enum ELSE 'LIFECYCLE_TRANSITIONED'::trustride.resource_event_type_enum END,
      to_jsonb(OLD), to_jsonb(NEW), NULL, NULL, NULL, 'SYSTEM'
    );
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_resource_marketplace_inventory_mirror
  AFTER UPDATE OF lifecycle_state ON trustride.resource_marketplace_inventory
  FOR EACH ROW EXECUTE FUNCTION trustride.trg_fn_resource_marketplace_inventory_mirror();

CREATE OR REPLACE FUNCTION trustride.trg_fn_resource_workforce_unit_mirror()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, extensions, pg_temp AS $$
BEGIN
  IF NEW.unit_status IS DISTINCT FROM OLD.unit_status THEN
    PERFORM trustride.fn_resource_ledger_event_append(
      'WORKFORCE_UNIT', NEW.workforce_unit_id,
      CASE WHEN NEW.unit_status = 'INACTIVE' THEN 'RETIRED'::trustride.resource_event_type_enum ELSE 'LIFECYCLE_TRANSITIONED'::trustride.resource_event_type_enum END,
      to_jsonb(OLD), to_jsonb(NEW), NULL, NULL, NULL, 'SYSTEM'
    );
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_resource_workforce_unit_mirror
  AFTER UPDATE OF unit_status ON trustride.resource_workforce_unit
  FOR EACH ROW EXECUTE FUNCTION trustride.trg_fn_resource_workforce_unit_mirror();

-- ============================================================================
-- PHASE 6 -- RETIREMENT DOES NOT DELETE (Sovereign Invariant, enforced)
-- ============================================================================
CREATE OR REPLACE FUNCTION trustride.trg_fn_resource_block_hard_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp AS $$
BEGIN
  RAISE EXCEPTION 'Resource Constitution: % rows are never hard-deleted -- retire via lifecycle_state/unit_status = RETIRED/INACTIVE instead (attempted on %.%)',
    TG_TABLE_NAME, TG_TABLE_NAME, OLD;
END;
$$;

CREATE TRIGGER trg_block_delete_fleet BEFORE DELETE ON trustride.resource_fleet_register
  FOR EACH ROW EXECUTE FUNCTION trustride.trg_fn_resource_block_hard_delete();
CREATE TRIGGER trg_block_delete_equipment BEFORE DELETE ON trustride.resource_equipment_register
  FOR EACH ROW EXECUTE FUNCTION trustride.trg_fn_resource_block_hard_delete();
CREATE TRIGGER trg_block_delete_estate BEFORE DELETE ON trustride.resource_estate_register
  FOR EACH ROW EXECUTE FUNCTION trustride.trg_fn_resource_block_hard_delete();
CREATE TRIGGER trg_block_delete_financial_asset BEFORE DELETE ON trustride.resource_financial_asset
  FOR EACH ROW EXECUTE FUNCTION trustride.trg_fn_resource_block_hard_delete();
CREATE TRIGGER trg_block_delete_marketplace_inventory BEFORE DELETE ON trustride.resource_marketplace_inventory
  FOR EACH ROW EXECUTE FUNCTION trustride.trg_fn_resource_block_hard_delete();
CREATE TRIGGER trg_block_delete_workforce_unit BEFORE DELETE ON trustride.resource_workforce_unit
  FOR EACH ROW EXECUTE FUNCTION trustride.trg_fn_resource_block_hard_delete();

-- ============================================================================
-- PHASE 7 -- ORDER-LINE BINDING ON THE ASSIGNMENT FUNCTIONS (additive,
-- backward-compatible: existing callers that only pass p_order_id keep
-- working unchanged)
-- ============================================================================
DROP FUNCTION IF EXISTS trustride.fn_resource_reserve(UUID, UUID, UUID, UUID);

CREATE FUNCTION trustride.fn_resource_reserve(
  p_workforce_unit_id UUID, p_order_id UUID, p_correlation_id UUID, p_changed_by UUID,
  p_order_line_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_availability_id UUID;
  v_signal_id       UUID;
  v_capacity_class  trustride.resource_capacity_class_enum;
BEGIN
  SELECT cc.class_code INTO v_capacity_class
  FROM trustride.resource_workforce_unit wu JOIN trustride.resource_capacity_class cc ON cc.capacity_class_id = wu.capacity_class_id
  WHERE wu.workforce_unit_id = p_workforce_unit_id;

  UPDATE trustride.resource_availability_ledger SET effective_to = now()
  WHERE resource_type = 'WORKFORCE_UNIT' AND resource_ref_id = p_workforce_unit_id AND effective_to IS NULL AND availability_state = 'AVAILABLE';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_resource_reserve: workforce_unit % is not currently AVAILABLE', p_workforce_unit_id;
  END IF;

  INSERT INTO trustride.resource_availability_ledger (resource_type, resource_ref_id, availability_state, reason_code, job_ref_id, order_line_id, changed_by)
  VALUES ('WORKFORCE_UNIT', p_workforce_unit_id, 'RESERVED', 'ORDER_ASSIGNMENT_PENDING', p_order_id, p_order_line_id, p_changed_by)
  RETURNING availability_id INTO v_availability_id;

  INSERT INTO trustride.resource_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG004_BUS', 'RESOURCE_RESERVED',
    jsonb_build_object('order_id', p_order_id, 'order_line_id', p_order_line_id, 'workforce_unit_id', p_workforce_unit_id, 'capacity_class', v_capacity_class),
    'RESOURCE_RESERVED:' || p_order_id::text || ':' || p_workforce_unit_id::text)
  RETURNING signal_id INTO v_signal_id;

  RETURN v_availability_id;
END;
$$;

DROP FUNCTION IF EXISTS trustride.fn_resource_assign(UUID, UUID, UUID, UUID, TEXT, TEXT, NUMERIC, NUMERIC, UUID, TEXT, TEXT);

CREATE FUNCTION trustride.fn_resource_assign(
  p_workforce_unit_id UUID, p_order_id UUID, p_correlation_id UUID, p_changed_by UUID,
  p_origin_zone_code TEXT DEFAULT NULL, p_destination_zone_code TEXT DEFAULT NULL,
  p_distance_km NUMERIC DEFAULT NULL, p_duration_min NUMERIC DEFAULT NULL,
  p_requester_user_id UUID DEFAULT NULL, p_jurisdiction TEXT DEFAULT NULL, p_engine_capacity TEXT DEFAULT NULL,
  p_order_line_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_availability_id UUID;
  v_capacity_class  trustride.resource_capacity_class_enum;
  v_fleet_resource_id UUID;
  v_thing_id        UUID;
BEGIN
  SELECT cc.class_code, wu.fleet_resource_id INTO v_capacity_class, v_fleet_resource_id
  FROM trustride.resource_workforce_unit wu JOIN trustride.resource_capacity_class cc ON cc.capacity_class_id = wu.capacity_class_id
  WHERE wu.workforce_unit_id = p_workforce_unit_id;

  IF v_fleet_resource_id IS NOT NULL THEN
    SELECT thing_id INTO v_thing_id FROM trustride.resource_fleet_register WHERE fleet_resource_id = v_fleet_resource_id;
  END IF;

  UPDATE trustride.resource_availability_ledger SET effective_to = now()
  WHERE resource_type = 'WORKFORCE_UNIT' AND resource_ref_id = p_workforce_unit_id AND effective_to IS NULL AND availability_state = 'RESERVED';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_resource_assign: workforce_unit % is not currently RESERVED', p_workforce_unit_id;
  END IF;

  INSERT INTO trustride.resource_availability_ledger (resource_type, resource_ref_id, availability_state, reason_code, job_ref_id, order_line_id, changed_by)
  VALUES ('WORKFORCE_UNIT', p_workforce_unit_id, 'ASSIGNED', 'ORDER_ASSIGNMENT_CONFIRMED', p_order_id, p_order_line_id, p_changed_by)
  RETURNING availability_id INTO v_availability_id;

  INSERT INTO trustride.resource_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG004_BUS', 'RESOURCE_ASSIGNED',
    jsonb_build_object('order_id', p_order_id, 'order_line_id', p_order_line_id, 'workforce_unit_id', p_workforce_unit_id, 'capacity_class', v_capacity_class, 'engine_capacity', v_capacity_class, 'thing_id', v_thing_id),
    'RESOURCE_ASSIGNED:' || p_order_id::text || ':' || p_workforce_unit_id::text);

  INSERT INTO trustride.resource_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG005_COST', 'RESOURCE_DISPATCH_INITIATED',
    jsonb_build_object('asset_class', v_capacity_class, 'engine_capacity', p_engine_capacity, 'order_id', p_order_id, 'order_line_id', p_order_line_id, 'assignment_id', v_availability_id,
      'origin_zone_code', p_origin_zone_code, 'destination_zone_code', p_destination_zone_code, 'distance_km', p_distance_km,
      'duration_min', p_duration_min, 'requester_user_id', p_requester_user_id, 'jurisdiction', p_jurisdiction),
    'RESOURCE_DISPATCH_INITIATED:' || p_order_id::text || ':' || p_workforce_unit_id::text);

  RETURN v_availability_id;
END;
$$;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_assign(UUID, UUID, UUID, UUID, TEXT, TEXT, NUMERIC, NUMERIC, UUID, TEXT, TEXT, UUID) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_reserve(UUID, UUID, UUID, UUID, UUID) TO trs026_eng002_resc_service;

-- ============================================================================
-- PHASE 8 -- EAGLE-EYE TRACEABILITY VIEW
-- ============================================================================
CREATE VIEW trustride.v_resource_eagle_eye AS
SELECT
  e.resource_type,
  e.resource_ref_id,
  (SELECT min(created_at) FROM trustride.resource_ledger_event e2 WHERE e2.resource_type = e.resource_type AND e2.resource_ref_id = e.resource_ref_id) AS came_into_existence_at,
  (SELECT before_state FROM trustride.resource_ledger_event e2 WHERE e2.resource_type = e.resource_type AND e2.resource_ref_id = e.resource_ref_id ORDER BY chain_seq ASC LIMIT 1) AS origin_event,
  latest.after_state AS current_state,
  latest.event_type AS last_event_type,
  latest.order_id AS last_order_id,
  latest.order_line_id AS last_order_line_id,
  latest.decision_timestamp AS last_changed_at,
  (SELECT count(*) FROM trustride.resource_ledger_event e2 WHERE e2.resource_type = e.resource_type AND e2.resource_ref_id = e.resource_ref_id) AS complete_history_count,
  (latest.event_type = 'RETIRED') AS is_retired,
  latest.immutable_hash AS current_evidence_hash,
  latest.prev_hash AS previous_evidence_hash
FROM trustride.resource_ledger_event e
JOIN LATERAL (
  SELECT * FROM trustride.resource_ledger_event e3
  WHERE e3.resource_type = e.resource_type AND e3.resource_ref_id = e.resource_ref_id
  ORDER BY chain_seq DESC LIMIT 1
) latest ON true
GROUP BY e.resource_type, e.resource_ref_id, latest.after_state, latest.event_type, latest.order_id, latest.order_line_id, latest.decision_timestamp, latest.immutable_hash, latest.prev_hash;
COMMENT ON VIEW trustride.v_resource_eagle_eye IS
  'Resources-domain EAGLE-EYE (mirrors MNY-15 Section 15): for any resource, where is it (current_state), where did it come from (origin_event), why/what for (origin_event''s reason_code), who last changed it and when, its complete history count, whether it has retired, and its current/previous evidence hash for reconciliation.';

-- ============================================================================
-- PHASE 9 -- ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE trustride.resource_ledger_event ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_ledger_event_platform_read ON trustride.resource_ledger_event FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_ledger_event_service_write ON trustride.resource_ledger_event FOR INSERT TO trs026_eng002_resc_service WITH CHECK (true);

-- ============================================================================
-- PHASE 10 -- INDEXES
-- ============================================================================
CREATE INDEX idx_resource_ledger_event_resource ON trustride.resource_ledger_event (resource_type, resource_ref_id, chain_seq DESC);
CREATE INDEX idx_resource_ledger_event_order ON trustride.resource_ledger_event (order_id);
CREATE INDEX idx_resource_ledger_event_order_line ON trustride.resource_ledger_event (order_line_id);
CREATE INDEX idx_resource_availability_order_line ON trustride.resource_availability_ledger (order_line_id);

-- ============================================================================
-- PHASE 11 -- PRIVILEGE LOCKDOWN
-- ============================================================================
GRANT SELECT, INSERT ON trustride.resource_ledger_event TO trs026_eng002_resc_service;
GRANT SELECT ON trustride.v_resource_eagle_eye TO trustride_authenticated;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_ledger_event_append(trustride.resource_custody_type_enum, UUID, trustride.resource_event_type_enum, JSONB, JSONB, UUID, UUID, UUID, trustride.resource_event_source_enum) TO trs026_eng002_resc_service;

-- ============================================================================
-- PHASE 12 -- VALIDATION
-- ============================================================================
DO $$
DECLARE
  v_trigger_count INTEGER;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'trustride' AND table_name = 'resource_ledger_event') THEN
    RAISE EXCEPTION 'MNY-15 elevation validation failed: resource_ledger_event missing';
  END IF;

  SELECT count(*) INTO v_trigger_count
  FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'trustride' AND NOT t.tgisinternal
    AND t.tgname IN (
      'trg_resource_availability_mirror','trg_resource_custody_mirror','trg_resource_fleet_lifecycle_mirror',
      'trg_resource_equipment_lifecycle_mirror','trg_resource_estate_lifecycle_mirror','trg_resource_financial_asset_mirror',
      'trg_resource_marketplace_inventory_mirror','trg_resource_workforce_unit_mirror',
      'trg_block_delete_fleet','trg_block_delete_equipment','trg_block_delete_estate','trg_block_delete_financial_asset',
      'trg_block_delete_marketplace_inventory','trg_block_delete_workforce_unit'
    );
  IF v_trigger_count <> 14 THEN
    RAISE EXCEPTION 'MNY-15 elevation validation failed: expected 14 mirror/guard triggers, found %', v_trigger_count;
  END IF;

  RAISE NOTICE 'MNY-15 Resources elevation validation passed: resource_ledger_event live, 14/14 triggers installed.';
END
$$;

UPDATE trustride.engine_registry SET engine_version = '1.1.0' WHERE engine_code = 'TRS026_ENG002_RESC';
