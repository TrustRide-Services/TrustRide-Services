-- ============================================================================
-- TRUSTRIDE SERVICES PLATFORM
-- ============================================================================
-- PLATFORM ID          : b302bb5d-7d20-41e9-a074-a18d8ebd2aa5
-- PLATFORM CODE        : TRS026
-- PLATFORM NAME        : TRUSTRIDE_SERVICES
-- SCHEMA               : trustride
-- ENGINE NO            : ENGINE_002
-- ENGINE ID            : c1a2b3c4-0002-4eng-8002-002resources02
-- ENGINE CODE          : TRS026_ENG002_RESC
-- ENGINE DOMAIN        : Institutional Resources
-- ENGINE CLASS         : Resource Engine
-- ENGINE TYPE          : Resource Management
-- ENGINE NAME          : TrustRide Resources
-- ENGINE DESCRIPTION   : The platform's single, deterministic authority for
--                        registering, custodying, and gating the availability
--                        of every business resource TrustRide deploys to do
--                        its work -- fleet, equipment, physical estate,
--                        deployable workforce units, technology, financial
--                        floats, and Own Marketplace inventory while held
--                        for trade.
-- ENGINE FUNCTION      : Answers, before any other engine asks: what capacity
--                        exists right now, and is it lawful to dispatch.
-- PLATFORM VERSION     : 1.0.0
-- ENGINE VERSION       : 1.0.1
-- MIGRATION DATA
-- FILE NAME            : 20260823000003_engine002_resources.sql
-- INSTALLATION ORDER   : 002
-- STATUS               : COMPLETE -- one single migration file, 13 tables,
--                        applied on top of the already-live Foundation engine.
-- CREATED AT           : 2026-08-23
-- CREATED BY           : Onyango Albert Chitayi (Founder) + Engineering
-- ============================================================================
--
-- Source: TRS026-ENG002-RESC-001 v1.0.1 (ADOPTED 2026-08-16), Sections 2-5.
-- Corrections and Founder-directed amendments applied in this compilation:
--   1. Schema-qualified every table/type/function as `trustride.*` -- the
--      source document's own DDL omits the prefix, assuming a session
--      search_path of `trustride`; this file follows Foundation's own
--      explicit-qualification discipline instead, for an unambiguous file.
--   2. Custom role trs026_eng002_resc_service created immediately after
--      Phase 1 Schema (Foundation's own Correction 8 pattern) -- RLS
--      policies below require the role to exist before CREATE POLICY runs.
--   3. REAL BUG FOUND AND FIXED (2026-08-23, caught while tracing the
--      discovery workflow against the source document itself, before any
--      execution): resource_availability_ledger.resource_type and
--      resource_custody_log.resource_type are typed as
--      resource_custody_type_enum, but that enum (FLEET, EQUIPMENT, DEVICE,
--      ESTATE, MARKETPLACE_INVENTORY) never included WORKFORCE_UNIT -- the
--      one resource the entire engine exists to gate (Article 41; the
--      source document's own §4.1 discovery response keys availability
--      directly off workforce_unit_id). Fixed by adding WORKFORCE_UNIT to
--      the enum.
--   4. Founder ruling 2026-08-23 (Kisumu build plan, item 1): "a COMPLETE
--      TrustRide-defined Resources... MOTORCYCLES, PICKUPS AND VANS, SMALL
--      CARS, TRUSTRIDE WORKFORCE, TECHNOLOGY, MONEY AND FINANCES... DO NOT
--      QUANTIFY THE RESOURCES, LET THE RESOURCES TABLE BE OPEN... WE SHALL
--      HAVE PARTNERS WHOM WILL ALSO BRING RESOURCES." Against the source
--      document: motorcycles/pickups/vans were already covered
--      (BODA_BODA/PICKUP_TOWN/VAN_CARGO), partner-contributed resources
--      were already covered (ownership_type = PARTNER_CONTRIBUTED), and no
--      quantity/count column exists anywhere -- each physical unit is its
--      own row, exactly as directed. Genuinely missing, added here:
--        a. SEDAN capacity class -- small cars (resource_capacity_class_enum).
--        b. TECHNOLOGY_ASSET equipment type -- devices, hardware, software
--           licences as their own governed category, not folded into
--           OPERATIONAL_TOOL (resource_equipment_type_enum).
--        c. trustride.resource_workforce_capability -- Article 37 names
--           "capability" as its own resource kind; the source document's
--           workforce coverage stopped at the rider-to-fleet pairing with
--           no register of the licences/certifications (PSV, defensive
--           driving, first aid) that actually gate who may be assigned to
--           what. New table, new resource_capability_type_enum.
--        d. trustride.resource_financial_asset -- Article 37 names "asset"
--           broadly, but the source document's asset coverage was
--           vehicles/equipment/estate only; Money and Finances (cash
--           floats, fuel-advance funds, financing facilities) were entirely
--           absent as a registered, custodied, availability-gated resource.
--           New table, new resource_financial_asset_type_enum, and
--           FINANCIAL_ASSET added to resource_custody_type_enum so it gets
--           the same custody-accountability and availability-ledger
--           treatment as any physical resource (Article 37.4 applies
--           universally, not just to vehicles).
--   5. The source document compiles Section 2 (static DDL: tables, enums,
--      RLS, indexes) and separately narrates Section 4 (API contracts) and
--      Section 5 (signal matrix) in prose -- exactly the gap already found
--      and named in Foundation's own corpus read (a blueprint's prose
--      describing behaviour is not the same as that behaviour being
--      compiled). This file completes Phase 6/7 for real: fn_resource_
--      discover, fn_resource_reserve, fn_resource_assign, fn_resource_
--      custody_transfer, the four inbound signal accept-handlers, and the
--      full registration/lifecycle function set are all live PL/pgSQL
--      below, not prose.
--   6. Privilege lockdown uses explicit per-function GRANTs to
--      trs026_eng002_resc_service, never a schema-wide "ALL FUNCTIONS IN
--      SCHEMA trustride" blanket -- since every engine shares one schema,
--      a blanket grant issued from Engine 2's migration (running after
--      Foundation's 14 functions already exist) would retroactively sweep
--      up EXECUTE on Foundation's own privileged functions. This is a
--      precision correction over blindly repeating Foundation's own
--      same-file blanket shorthand, which was safe only because nothing
--      else existed yet when it ran.
--   7. Engine 2's lawful state-changing functions append to Foundation's
--      shared platform-wide audit hash chain via trustride.fn_audit_log_
--      append -- Article 49-51's evidence discipline is platform-wide, not
--      Foundation-private, and audit_log's entity_type/entity_id columns
--      are engine-agnostic by design. EXECUTE on that one Foundation
--      function (and fn_sequence_next, for future sequence use) is granted
--      to trs026_eng002_resc_service explicitly, by this file, rather than
--      assumed.
--
-- ============================================================================

-- ============================================================================
-- PHASE 0 -- EXTENSIONS (idempotent; already present platform-wide per Engine 001 Phase 0)
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;

-- ============================================================================
-- PHASE 1 -- SCHEMA + EARLY ROLE CREATION (Foundation's Correction 8 pattern:
-- RLS policies below need this role to physically exist before CREATE POLICY)
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng002_resc_service') THEN
    CREATE ROLE trs026_eng002_resc_service NOLOGIN;
  END IF;
END
$$;

-- ============================================================================
-- PHASE 2 -- ENUMS
-- ============================================================================

-- [Trace: TBOC-v2.0.0 | Article 39 | Fleet & Equipment Register]
CREATE TYPE trustride.resource_domain_enum AS ENUM (
  'TRANSPORT', 'COURIER', 'DELIVERY', 'EXECUTIVE_ASSISTANTS', 'MARKETPLACE'
);

-- Correction 4a: SEDAN added -- Founder directive, "small cars" as a named,
-- required capacity class alongside motorcycles/pickups/vans.
CREATE TYPE trustride.resource_capacity_class_enum AS ENUM (
  'BODA_BODA', 'TUKTUK', 'SEDAN', 'PICKUP_TOWN', 'VAN_CARGO', 'TRUCK_LIGHT', 'EXECUTIVE_ASSISTANT_HUMAN'
);

-- [Trace: TBOC-v2.0.0 | Article 41 | Resource Lifecycle & Availability -- the ten constitutional stages, verbatim]
CREATE TYPE trustride.resource_lifecycle_state_enum AS ENUM (
  'NEED_IDENTIFIED', 'ACQUIRED', 'REGISTERED', 'VERIFIED', 'ASSIGNED',
  'UTILIZED', 'MONITORED', 'MAINTAINED', 'EVALUATED', 'REASSIGNED', 'RETIRED'
);

-- [Trace: TBOC-v2.0.0 | Article 41 -- live dispatch-facing availability signal, narrower than the full lifecycle]
CREATE TYPE trustride.resource_availability_state_enum AS ENUM (
  'AVAILABLE', 'RESERVED', 'ASSIGNED', 'MAINTENANCE', 'OFFLINE', 'RETIRED'
);

CREATE TYPE trustride.resource_estate_type_enum AS ENUM (
  'HQ', 'OPERATING_HUB', 'MAINTENANCE_YARD', 'STORAGE_FACILITY'
);

CREATE TYPE trustride.resource_ownership_type_enum AS ENUM (
  'OWNED', 'LEASED', 'PARTNER_CONTRIBUTED'
);

-- Correction 4b: TECHNOLOGY_ASSET added -- Founder directive, "technology" as
-- its own governed equipment category, not folded into OPERATIONAL_TOOL.
CREATE TYPE trustride.resource_equipment_type_enum AS ENUM (
  'OPERATIONAL_TOOL', 'STATION_EQUIPMENT', 'UNIFORM', 'SAFETY_GEAR', 'TECHNOLOGY_ASSET'
);

-- [Trace: TBOC-v2.0.0 | Article 40 -- the exact Own Marketplace item lifecycle]
CREATE TYPE trustride.resource_inventory_lifecycle_enum AS ENUM (
  'ACQUIRED', 'INSPECTED', 'VALUED', 'REFURBISHED', 'COMPLIANT',
  'LISTED', 'SOLD', 'AFTERCARE', 'RETIRED'
);

-- Correction 3 (WORKFORCE_UNIT) + Correction 4d (FINANCIAL_ASSET).
CREATE TYPE trustride.resource_custody_type_enum AS ENUM (
  'FLEET', 'EQUIPMENT', 'DEVICE', 'ESTATE', 'MARKETPLACE_INVENTORY', 'WORKFORCE_UNIT', 'FINANCIAL_ASSET'
);

-- Correction 4c: new -- Article 37's "capability" resource kind, realized.
CREATE TYPE trustride.resource_capability_type_enum AS ENUM (
  'PSV_LICENSE', 'DEFENSIVE_DRIVING_CERT', 'FIRST_AID_CERT', 'GOOD_CONDUCT_CERT',
  'MECHANIC_CERTIFICATION', 'LANGUAGE_PROFICIENCY', 'CUSTOMER_CARE_TRAINING'
);

-- Correction 4d: new -- Founder directive, "Money and Finances" as a resource.
CREATE TYPE trustride.resource_financial_asset_type_enum AS ENUM (
  'CASH_FLOAT', 'FUEL_ADVANCE_FUND', 'WORKING_CAPITAL', 'FINANCING_FACILITY', 'PETTY_CASH'
);

-- ============================================================================
-- PHASE 3/4/5 -- TABLES, CONSTRAINTS, RELATIONSHIPS
-- ============================================================================

-- --- 2.1 resource_estate_register ---
CREATE TABLE trustride.resource_estate_register (
  estate_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  estate_code          TEXT NOT NULL UNIQUE,
  estate_type          trustride.resource_estate_type_enum NOT NULL,
  estate_name          TEXT NOT NULL,
  location             GEOMETRY(POINT, 4326) NOT NULL,
  jurisdiction         TEXT NOT NULL,
  custodian_user_id    UUID NOT NULL,
  capacity_description TEXT,
  compliance_status    TEXT NOT NULL DEFAULT 'PENDING_REVIEW'
                          CHECK (compliance_status IN ('COMPLIANT', 'PENDING_REVIEW', 'NON_COMPLIANT')),
  county_licence_ref   TEXT,
  lifecycle_state      trustride.resource_lifecycle_state_enum NOT NULL DEFAULT 'REGISTERED',
  active               BOOLEAN NOT NULL DEFAULT TRUE,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.resource_estate_register IS
  '[Trace: TBOC-v2.0.0 | Article 38] The constitutional register of TrustRide''s physical estate -- Kisumu HQ, operating hubs, maintenance yards, and storage facilities.';

-- --- 2.2 resource_capacity_class ---
CREATE TABLE trustride.resource_capacity_class (
  capacity_class_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_code         trustride.resource_capacity_class_enum NOT NULL UNIQUE,
  class_label        TEXT NOT NULL,
  domain_affinity    trustride.resource_domain_enum NOT NULL,
  requires_fleet     BOOLEAN NOT NULL DEFAULT TRUE,
  description        TEXT NOT NULL,
  active             BOOLEAN NOT NULL DEFAULT TRUE,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.resource_capacity_class IS
  '[Trace: TBOC-v2.0.0 | Article 39] The constitutional source of capacity-class vocabulary; Engine 5''s asset_class_enum/engine_capacity_enum mirror this registry by value.';

-- --- 2.3 resource_fleet_register ---
CREATE TABLE trustride.resource_fleet_register (
  fleet_resource_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  thing_id                 UUID NOT NULL UNIQUE,
  capacity_class_id        UUID NOT NULL REFERENCES trustride.resource_capacity_class (capacity_class_id),
  ownership_type           trustride.resource_ownership_type_enum NOT NULL,
  registration_particulars TEXT NOT NULL,
  inspection_status        TEXT NOT NULL DEFAULT 'PENDING'
                              CHECK (inspection_status IN ('PENDING', 'PASSED', 'FAILED', 'EXPIRED')),
  insurance_status         TEXT NOT NULL DEFAULT 'PENDING'
                              CHECK (insurance_status IN ('PENDING', 'ACTIVE', 'EXPIRED', 'LAPSED')),
  condition_record         TEXT,
  home_estate_id           UUID NOT NULL REFERENCES trustride.resource_estate_register (estate_id),
  custodian_user_id        UUID NOT NULL,
  lifecycle_state          trustride.resource_lifecycle_state_enum NOT NULL DEFAULT 'REGISTERED',
  active                   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.resource_fleet_register IS
  '[Trace: TBOC-v2.0.0 | Article 39.1] Fleet hardware. No fleet resource may be assigned to an Order without PASSED inspection and ACTIVE insurance (Article 41).';

-- --- 2.4 resource_equipment_register ---
CREATE TABLE trustride.resource_equipment_register (
  equipment_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  equipment_type    trustride.resource_equipment_type_enum NOT NULL,
  item_code         TEXT NOT NULL UNIQUE,
  description       TEXT NOT NULL,
  thing_id          UUID,
  issued_to_user_id UUID,
  issued_at         TIMESTAMPTZ,
  condition_state   TEXT NOT NULL DEFAULT 'NEW'
                       CHECK (condition_state IN ('NEW', 'SERVICEABLE', 'WORN', 'DAMAGED', 'DECOMMISSIONED')),
  returned_at       TIMESTAMPTZ,
  home_estate_id    UUID NOT NULL REFERENCES trustride.resource_estate_register (estate_id),
  lifecycle_state   trustride.resource_lifecycle_state_enum NOT NULL DEFAULT 'REGISTERED',
  active            BOOLEAN NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.resource_equipment_register IS
  '[Trace: TBOC-v2.0.0 | Article 39.2-39.5] Operational equipment, station equipment, uniforms, safety gear, and technology assets; issuance and return are always recorded.';

-- --- 2.5 resource_workforce_unit ---
CREATE TABLE trustride.resource_workforce_unit (
  workforce_unit_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  operator_user_id  UUID NOT NULL,
  fleet_resource_id UUID REFERENCES trustride.resource_fleet_register (fleet_resource_id),
  capacity_class_id UUID NOT NULL REFERENCES trustride.resource_capacity_class (capacity_class_id),
  primary_estate_id UUID NOT NULL REFERENCES trustride.resource_estate_register (estate_id),
  unit_status       TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (unit_status IN ('ACTIVE', 'INACTIVE')),
  formed_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  dissolved_at      TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.resource_workforce_unit IS
  '[Trace: TBOC-v2.0.0 | Article 37, 41] A rider without a motorcycle, or a motorcycle without a rider, is not a dispatchable resource -- this table is the pairing that makes one.';

-- --- Correction 4c: resource_workforce_capability ---
CREATE TABLE trustride.resource_workforce_capability (
  capability_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workforce_unit_id UUID NOT NULL REFERENCES trustride.resource_workforce_unit (workforce_unit_id),
  capability_type   trustride.resource_capability_type_enum NOT NULL,
  credential_ref    TEXT,
  verified          BOOLEAN NOT NULL DEFAULT FALSE,
  verified_at       TIMESTAMPTZ,
  expires_at        TIMESTAMPTZ,
  active            BOOLEAN NOT NULL DEFAULT TRUE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.resource_workforce_capability IS
  '[Trace: TBOC-v2.0.0 | Article 37 -- "capability" as a named resource kind] Licences, certifications, and skills held by a workforce unit that gate eligibility for specific assignments beyond raw capacity class.';

-- --- 2.6 resource_availability_ledger ---
CREATE TABLE trustride.resource_availability_ledger (
  availability_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_type      trustride.resource_custody_type_enum NOT NULL,
  resource_ref_id    UUID NOT NULL,
  availability_state trustride.resource_availability_state_enum NOT NULL,
  effective_from     TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to       TIMESTAMPTZ,
  reason_code        TEXT,
  job_ref_id         UUID,
  changed_by         UUID NOT NULL,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.resource_availability_ledger IS
  '[Trace: TBOC-v2.0.0 | Article 41] No unavailable, unverified, or non-compliant resource may be dispatched; availability is restored at the close of every Job.';

-- --- Correction 4d: resource_financial_asset ---
-- Registers the financial resource itself (a float/facility, and whether it
-- is currently drawable) -- deliberately NOT a transaction ledger. Actual
-- fund movement (disbursement, settlement) stays Business/Cost/Integration's
-- domain (Article 33); current_balance_kes is a live gauge, updated only via
-- inbound signal, exactly like condition_record on a physical asset.
CREATE TABLE trustride.resource_financial_asset (
  financial_asset_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_code           TEXT NOT NULL UNIQUE,
  asset_type           trustride.resource_financial_asset_type_enum NOT NULL,
  ownership_type       trustride.resource_ownership_type_enum NOT NULL,
  currency             CHAR(3) NOT NULL DEFAULT 'KES',
  principal_amount_kes NUMERIC(18,2) NOT NULL CHECK (principal_amount_kes >= 0),
  current_balance_kes  NUMERIC(18,2) NOT NULL CHECK (current_balance_kes >= 0),
  custodian_user_id    UUID NOT NULL,
  home_estate_id       UUID NOT NULL REFERENCES trustride.resource_estate_register (estate_id),
  compliance_status    TEXT NOT NULL DEFAULT 'PENDING_REVIEW'
                          CHECK (compliance_status IN ('COMPLIANT', 'PENDING_REVIEW', 'NON_COMPLIANT')),
  lifecycle_state      trustride.resource_lifecycle_state_enum NOT NULL DEFAULT 'REGISTERED',
  active               BOOLEAN NOT NULL DEFAULT TRUE,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.resource_financial_asset IS
  '[Trace: TBOC-v2.0.0 | Article 37 -- "asset" extended to financial resources, Founder directive 2026-08-23] Money and finances as a first-class, custodied, availability-gated resource -- cash floats, fuel-advance funds, working capital, financing facilities.';

-- --- 3.1 resource_maintenance_record ---
CREATE TABLE trustride.resource_maintenance_record (
  maintenance_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  fleet_resource_id      UUID NOT NULL REFERENCES trustride.resource_fleet_register (fleet_resource_id),
  maintenance_type       TEXT NOT NULL CHECK (maintenance_type IN
                            ('INSPECTION','REPAIR','REFURBISHMENT','ROUTINE_SERVICE')),
  performed_at_estate_id UUID NOT NULL REFERENCES trustride.resource_estate_register (estate_id),
  description             TEXT NOT NULL,
  cost_kes                NUMERIC(18,2) NOT NULL CHECK (cost_kes >= 0),
  performed_by             UUID NOT NULL,
  condition_before          TEXT,
  condition_after            TEXT,
  completed_at                TIMESTAMPTZ,
  created_at                    TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.resource_maintenance_record IS
  '[Trace: TBOC-v2.0.0 | Article 38.3] The custody trail of every inspection, repair, refurbishment, and routine service performed at a maintenance yard.';

-- --- 3.2 resource_marketplace_inventory ---
CREATE TABLE trustride.resource_marketplace_inventory (
  inventory_item_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_code            TEXT NOT NULL UNIQUE,
  category             TEXT NOT NULL,
  acquisition_source   TEXT NOT NULL,
  acquisition_cost_kes NUMERIC(18,2) NOT NULL CHECK (acquisition_cost_kes >= 0),
  inspection_status    TEXT NOT NULL DEFAULT 'PENDING',
  valuation_kes        NUMERIC(18,2) CHECK (valuation_kes IS NULL OR valuation_kes >= 0),
  refurbishment_status TEXT NOT NULL DEFAULT 'NOT_REQUIRED',
  compliance_status    TEXT NOT NULL DEFAULT 'PENDING_REVIEW',
  custody_estate_id    UUID NOT NULL REFERENCES trustride.resource_estate_register (estate_id),
  lifecycle_state      trustride.resource_inventory_lifecycle_enum NOT NULL DEFAULT 'ACQUIRED',
  listed_at            TIMESTAMPTZ,
  sold_at              TIMESTAMPTZ,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.resource_marketplace_inventory IS
  '[Trace: TBOC-v2.0.0 | Article 40] Own Marketplace items are business resources while held for trade; this table owns the item through its full physical-custody lifecycle up to sale.';

-- --- 3.3 resource_custody_log ---
CREATE TABLE trustride.resource_custody_log (
  custody_log_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_type       trustride.resource_custody_type_enum NOT NULL,
  resource_ref_id     UUID NOT NULL,
  custodian_user_id   UUID NOT NULL,
  location_estate_id  UUID REFERENCES trustride.resource_estate_register (estate_id),
  transferred_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  transferred_by      UUID NOT NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.resource_custody_log IS
  '[Trace: TBOC-v2.0.0 | Article 37.4] Every resource of every type has a named custodian and a recorded location, always -- append-only.';
REVOKE UPDATE, DELETE ON trustride.resource_custody_log FROM PUBLIC;

-- --- 2.7 Engine Event Substrate ---
CREATE TABLE trustride.resource_event_outbox (
  signal_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id   UUID NOT NULL,
  causation_id     UUID,
  emitting_engine  TEXT NOT NULL DEFAULT 'TRS026_ENG002_RESC',
  receiving_engine TEXT NOT NULL,
  signal_type      TEXT NOT NULL,
  payload_in       JSONB NOT NULL,
  signal_status    TEXT NOT NULL DEFAULT 'PENDING'
                      CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason TEXT,
  idempotency_key  TEXT NOT NULL UNIQUE,
  attempt_count    INTEGER NOT NULL DEFAULT 0,
  emitted_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_resource_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);

CREATE TABLE trustride.resource_event_inbox (
  signal_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id   UUID NOT NULL,
  causation_id     UUID,
  emitting_engine  TEXT NOT NULL,
  receiving_engine TEXT NOT NULL DEFAULT 'TRS026_ENG002_RESC',
  signal_type      TEXT NOT NULL,
  payload_in       JSONB NOT NULL,
  payload_out      JSONB,
  signal_status    TEXT NOT NULL DEFAULT 'RECEIVED'
                      CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason TEXT,
  idempotency_key  TEXT NOT NULL UNIQUE,
  received_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at      TIMESTAMPTZ,
  CONSTRAINT chk_resource_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);

-- Deferred FK (declared after resource_workforce_unit exists, matching
-- Foundation's own deferred-FK discipline for genuinely circular references).
ALTER TABLE trustride.resource_workforce_capability
  ADD CONSTRAINT fk_resource_capability_unit FOREIGN KEY (workforce_unit_id) REFERENCES trustride.resource_workforce_unit (workforce_unit_id);

-- ============================================================================
-- PHASE 6 -- FUNCTIONS
-- ============================================================================

-- --- Registration: the lawful way to add a resource, always paired with an
-- --- opening custody_log row (Article 37.3-37.4: custody is accountability
-- --- from the moment of registration, never an informal hand-off).

CREATE OR REPLACE FUNCTION trustride.fn_resource_estate_register(
  p_estate_code TEXT, p_estate_type trustride.resource_estate_type_enum, p_estate_name TEXT,
  p_lat NUMERIC, p_lon NUMERIC, p_jurisdiction TEXT, p_custodian_user_id UUID, p_capacity_description TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public, pg_temp
AS $$
DECLARE
  v_estate_id UUID;
BEGIN
  INSERT INTO trustride.resource_estate_register (estate_code, estate_type, estate_name, location, jurisdiction, custodian_user_id, capacity_description)
  VALUES (p_estate_code, p_estate_type, p_estate_name, ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326), p_jurisdiction, p_custodian_user_id, p_capacity_description)
  RETURNING estate_id INTO v_estate_id;

  INSERT INTO trustride.resource_custody_log (resource_type, resource_ref_id, custodian_user_id, location_estate_id, transferred_by)
  VALUES ('ESTATE', v_estate_id, p_custodian_user_id, v_estate_id, p_custodian_user_id);

  RETURN v_estate_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_estate_register(TEXT, trustride.resource_estate_type_enum, TEXT, NUMERIC, NUMERIC, TEXT, UUID, TEXT) IS
  'The one lawful way to register a physical estate location -- always opens a resource_custody_log row (Article 37.4).';

CREATE OR REPLACE FUNCTION trustride.fn_resource_fleet_register(
  p_thing_id UUID, p_capacity_class_code trustride.resource_capacity_class_enum, p_ownership_type trustride.resource_ownership_type_enum,
  p_registration_particulars TEXT, p_home_estate_id UUID, p_custodian_user_id UUID
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_capacity_class_id UUID;
  v_fleet_resource_id UUID;
BEGIN
  SELECT capacity_class_id INTO v_capacity_class_id FROM trustride.resource_capacity_class WHERE class_code = p_capacity_class_code AND active = TRUE;
  IF v_capacity_class_id IS NULL THEN
    RAISE EXCEPTION 'fn_resource_fleet_register: unknown or inactive capacity_class %', p_capacity_class_code;
  END IF;

  INSERT INTO trustride.resource_fleet_register (thing_id, capacity_class_id, ownership_type, registration_particulars, home_estate_id, custodian_user_id)
  VALUES (p_thing_id, v_capacity_class_id, p_ownership_type, p_registration_particulars, p_home_estate_id, p_custodian_user_id)
  RETURNING fleet_resource_id INTO v_fleet_resource_id;

  INSERT INTO trustride.resource_custody_log (resource_type, resource_ref_id, custodian_user_id, location_estate_id, transferred_by)
  VALUES ('FLEET', v_fleet_resource_id, p_custodian_user_id, p_home_estate_id, p_custodian_user_id);

  INSERT INTO trustride.resource_availability_ledger (resource_type, resource_ref_id, availability_state, reason_code, changed_by)
  VALUES ('FLEET', v_fleet_resource_id, 'OFFLINE', 'AWAITING_VERIFICATION', p_custodian_user_id);

  PERFORM trustride.fn_audit_log_append('resource_fleet_register', v_fleet_resource_id, 'FLEET_RESOURCE_REGISTERED', p_custodian_user_id,
    'USER', NULL, NULL, NULL, jsonb_build_object('thing_id', p_thing_id, 'capacity_class', p_capacity_class_code));

  RETURN v_fleet_resource_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_fleet_register(UUID, trustride.resource_capacity_class_enum, trustride.resource_ownership_type_enum, TEXT, UUID, UUID) IS
  'The one lawful way to register fleet hardware -- always OFFLINE until FLEET_VERIFICATION_UPDATED confirms compliance (Article 41).';

CREATE OR REPLACE FUNCTION trustride.fn_resource_equipment_register(
  p_equipment_type trustride.resource_equipment_type_enum, p_item_code TEXT, p_description TEXT,
  p_home_estate_id UUID, p_custodian_user_id UUID, p_thing_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_equipment_id UUID;
BEGIN
  INSERT INTO trustride.resource_equipment_register (equipment_type, item_code, description, thing_id, home_estate_id)
  VALUES (p_equipment_type, p_item_code, p_description, p_thing_id, p_home_estate_id)
  RETURNING equipment_id INTO v_equipment_id;

  INSERT INTO trustride.resource_custody_log (resource_type, resource_ref_id, custodian_user_id, location_estate_id, transferred_by)
  VALUES ('EQUIPMENT', v_equipment_id, p_custodian_user_id, p_home_estate_id, p_custodian_user_id);

  RETURN v_equipment_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_equipment_register(trustride.resource_equipment_type_enum, TEXT, TEXT, UUID, UUID, UUID) IS
  'The one lawful way to register equipment, uniforms, safety gear, station equipment, or a technology asset.';

CREATE OR REPLACE FUNCTION trustride.fn_resource_workforce_unit_form(
  p_operator_user_id UUID, p_capacity_class_code trustride.resource_capacity_class_enum, p_primary_estate_id UUID, p_fleet_resource_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_capacity_class_id UUID;
  v_workforce_unit_id UUID;
BEGIN
  SELECT capacity_class_id INTO v_capacity_class_id FROM trustride.resource_capacity_class WHERE class_code = p_capacity_class_code AND active = TRUE;
  IF v_capacity_class_id IS NULL THEN
    RAISE EXCEPTION 'fn_resource_workforce_unit_form: unknown or inactive capacity_class %', p_capacity_class_code;
  END IF;

  INSERT INTO trustride.resource_workforce_unit (operator_user_id, fleet_resource_id, capacity_class_id, primary_estate_id)
  VALUES (p_operator_user_id, p_fleet_resource_id, v_capacity_class_id, p_primary_estate_id)
  RETURNING workforce_unit_id INTO v_workforce_unit_id;

  INSERT INTO trustride.resource_custody_log (resource_type, resource_ref_id, custodian_user_id, location_estate_id, transferred_by)
  VALUES ('WORKFORCE_UNIT', v_workforce_unit_id, p_operator_user_id, p_primary_estate_id, p_operator_user_id);

  INSERT INTO trustride.resource_availability_ledger (resource_type, resource_ref_id, availability_state, reason_code, changed_by)
  VALUES ('WORKFORCE_UNIT', v_workforce_unit_id, 'AVAILABLE', 'UNIT_FORMED', p_operator_user_id);

  PERFORM trustride.fn_audit_log_append('resource_workforce_unit', v_workforce_unit_id, 'WORKFORCE_UNIT_FORMED', p_operator_user_id,
    'USER', NULL, NULL, NULL, jsonb_build_object('capacity_class', p_capacity_class_code, 'fleet_resource_id', p_fleet_resource_id));

  RETURN v_workforce_unit_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_workforce_unit_form(UUID, trustride.resource_capacity_class_enum, UUID, UUID) IS
  'The one lawful way to pair an Operator with fleet hardware into a dispatchable unit. The deferred fleet-requirement trigger below enforces that fleet_resource_id is NULL only for a capacity class that does not require it.';

CREATE OR REPLACE FUNCTION trustride.fn_resource_workforce_capability_register(
  p_workforce_unit_id UUID, p_capability_type trustride.resource_capability_type_enum, p_credential_ref TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_capability_id UUID;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM trustride.resource_workforce_unit WHERE workforce_unit_id = p_workforce_unit_id) THEN
    RAISE EXCEPTION 'fn_resource_workforce_capability_register: unknown workforce_unit_id %', p_workforce_unit_id;
  END IF;

  INSERT INTO trustride.resource_workforce_capability (workforce_unit_id, capability_type, credential_ref)
  VALUES (p_workforce_unit_id, p_capability_type, p_credential_ref)
  RETURNING capability_id INTO v_capability_id;

  RETURN v_capability_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_workforce_capability_register(UUID, trustride.resource_capability_type_enum, TEXT) IS
  'Registers an unverified capability claim against a workforce unit; see fn_resource_workforce_capability_verify for the governed verification step.';

CREATE OR REPLACE FUNCTION trustride.fn_resource_workforce_capability_verify(p_capability_id UUID, p_verified_by UUID, p_expires_at TIMESTAMPTZ DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
BEGIN
  UPDATE trustride.resource_workforce_capability
  SET verified = TRUE, verified_at = now(), expires_at = p_expires_at
  WHERE capability_id = p_capability_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_resource_workforce_capability_verify: unknown capability_id %', p_capability_id;
  END IF;

  PERFORM trustride.fn_audit_log_append('resource_workforce_capability', p_capability_id, 'CAPABILITY_VERIFIED', p_verified_by,
    'USER', NULL, NULL, NULL, jsonb_build_object('capability_id', p_capability_id));
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_workforce_capability_verify(UUID, UUID, TIMESTAMPTZ) IS
  'The one lawful way a capability claim becomes verified -- audited, never a silent flag flip.';

CREATE OR REPLACE FUNCTION trustride.fn_resource_financial_asset_register(
  p_asset_code TEXT, p_asset_type trustride.resource_financial_asset_type_enum, p_ownership_type trustride.resource_ownership_type_enum,
  p_principal_amount_kes NUMERIC, p_custodian_user_id UUID, p_home_estate_id UUID, p_currency CHAR(3) DEFAULT 'KES'
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_financial_asset_id UUID;
BEGIN
  INSERT INTO trustride.resource_financial_asset (asset_code, asset_type, ownership_type, currency, principal_amount_kes, current_balance_kes, custodian_user_id, home_estate_id)
  VALUES (p_asset_code, p_asset_type, p_ownership_type, p_currency, p_principal_amount_kes, p_principal_amount_kes, p_custodian_user_id, p_home_estate_id)
  RETURNING financial_asset_id INTO v_financial_asset_id;

  INSERT INTO trustride.resource_custody_log (resource_type, resource_ref_id, custodian_user_id, location_estate_id, transferred_by)
  VALUES ('FINANCIAL_ASSET', v_financial_asset_id, p_custodian_user_id, p_home_estate_id, p_custodian_user_id);

  INSERT INTO trustride.resource_availability_ledger (resource_type, resource_ref_id, availability_state, reason_code, changed_by)
  VALUES ('FINANCIAL_ASSET', v_financial_asset_id, 'OFFLINE', 'AWAITING_COMPLIANCE_REVIEW', p_custodian_user_id);

  PERFORM trustride.fn_audit_log_append('resource_financial_asset', v_financial_asset_id, 'FINANCIAL_ASSET_REGISTERED', p_custodian_user_id,
    'USER', NULL, NULL, NULL, jsonb_build_object('asset_type', p_asset_type, 'principal_amount_kes', p_principal_amount_kes));

  RETURN v_financial_asset_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_financial_asset_register(TEXT, trustride.resource_financial_asset_type_enum, trustride.resource_ownership_type_enum, NUMERIC, UUID, UUID, CHAR) IS
  'The one lawful way to register a financial resource (cash float, financing facility). Registers the resource itself only -- fund movement is Business/Cost/Integration''s domain, never written here directly.';

-- --- Custody: the one lawful way ANY resource type changes hands (Article 37.3-37.4) ---

CREATE OR REPLACE FUNCTION trustride.fn_resource_custody_transfer(
  p_resource_type trustride.resource_custody_type_enum, p_resource_ref_id UUID, p_new_custodian_user_id UUID, p_new_location_estate_id UUID, p_transferred_by UUID
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_custody_log_id UUID;
BEGIN
  INSERT INTO trustride.resource_custody_log (resource_type, resource_ref_id, custodian_user_id, location_estate_id, transferred_by)
  VALUES (p_resource_type, p_resource_ref_id, p_new_custodian_user_id, p_new_location_estate_id, p_transferred_by)
  RETURNING custody_log_id INTO v_custody_log_id;

  CASE p_resource_type
    WHEN 'FLEET' THEN
      UPDATE trustride.resource_fleet_register SET custodian_user_id = p_new_custodian_user_id, home_estate_id = coalesce(p_new_location_estate_id, home_estate_id), updated_at = now() WHERE fleet_resource_id = p_resource_ref_id;
    WHEN 'EQUIPMENT' THEN
      UPDATE trustride.resource_equipment_register SET issued_to_user_id = p_new_custodian_user_id, home_estate_id = coalesce(p_new_location_estate_id, home_estate_id), updated_at = now() WHERE equipment_id = p_resource_ref_id;
    WHEN 'ESTATE' THEN
      UPDATE trustride.resource_estate_register SET custodian_user_id = p_new_custodian_user_id, updated_at = now() WHERE estate_id = p_resource_ref_id;
    WHEN 'FINANCIAL_ASSET' THEN
      UPDATE trustride.resource_financial_asset SET custodian_user_id = p_new_custodian_user_id, home_estate_id = coalesce(p_new_location_estate_id, home_estate_id), updated_at = now() WHERE financial_asset_id = p_resource_ref_id;
    ELSE
      NULL; -- WORKFORCE_UNIT/DEVICE/MARKETPLACE_INVENTORY custody is the log entry itself; no denormalized custodian column to sync
  END CASE;

  PERFORM trustride.fn_audit_log_append('resource_custody_log', v_custody_log_id, 'CUSTODY_TRANSFERRED', p_transferred_by,
    'USER', NULL, NULL, NULL, jsonb_build_object('resource_type', p_resource_type, 'resource_ref_id', p_resource_ref_id, 'new_custodian', p_new_custodian_user_id));

  RETURN v_custody_log_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_custody_transfer(trustride.resource_custody_type_enum, UUID, UUID, UUID, UUID) IS
  'The one lawful way custody of any resource type changes hands -- there is no informal or undocumented hand-off (Article 37.3-37.4).';

-- --- Discovery / Reserve / Assign (Section 4 API contracts, Article 20.2) ---

CREATE OR REPLACE FUNCTION trustride.fn_resource_discover(
  p_required_capacity_class trustride.resource_capacity_class_enum, p_pickup_lat NUMERIC, p_pickup_lon NUMERIC
)
RETURNS TABLE (workforce_unit_id UUID, fleet_resource_id UUID, capacity_class trustride.resource_capacity_class_enum, distance_to_pickup_km NUMERIC, availability_state trustride.resource_availability_state_enum)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = trustride, public, pg_temp
AS $$
DECLARE
  v_pickup_point GEOMETRY;
BEGIN
  v_pickup_point := ST_SetSRID(ST_MakePoint(p_pickup_lon, p_pickup_lat), 4326);

  RETURN QUERY
  SELECT wu.workforce_unit_id, wu.fleet_resource_id, cc.class_code,
    round((ST_DistanceSphere(v_pickup_point, er.location) / 1000.0)::numeric, 2),
    al.availability_state
  FROM trustride.resource_workforce_unit wu
  JOIN trustride.resource_capacity_class cc ON cc.capacity_class_id = wu.capacity_class_id
  JOIN trustride.resource_estate_register er ON er.estate_id = wu.primary_estate_id
  JOIN trustride.resource_availability_ledger al ON al.resource_type = 'WORKFORCE_UNIT' AND al.resource_ref_id = wu.workforce_unit_id AND al.effective_to IS NULL
  WHERE cc.class_code = p_required_capacity_class
    AND wu.unit_status = 'ACTIVE'
    AND al.availability_state = 'AVAILABLE'
  ORDER BY 4 ASC;
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_discover(trustride.resource_capacity_class_enum, NUMERIC, NUMERIC) IS
  '[Trace: §4.1] Candidate workforce units of the required class, nearest first. Read-only -- reserving is a separate, explicit step.';

CREATE OR REPLACE FUNCTION trustride.fn_resource_reserve(p_workforce_unit_id UUID, p_order_id UUID, p_correlation_id UUID, p_changed_by UUID)
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

  INSERT INTO trustride.resource_availability_ledger (resource_type, resource_ref_id, availability_state, reason_code, job_ref_id, changed_by)
  VALUES ('WORKFORCE_UNIT', p_workforce_unit_id, 'RESERVED', 'ORDER_ASSIGNMENT', p_order_id, p_changed_by)
  RETURNING availability_id INTO v_availability_id;

  INSERT INTO trustride.resource_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG004_BUS', 'RESOURCE_RESERVED',
    jsonb_build_object('order_id', p_order_id, 'workforce_unit_id', p_workforce_unit_id, 'capacity_class', v_capacity_class, 'reserved_until', now() + interval '3 minutes'),
    'RESOURCE_RESERVED:' || p_order_id::text || ':' || p_workforce_unit_id::text)
  RETURNING signal_id INTO v_signal_id;

  RETURN v_availability_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_reserve(UUID, UUID, UUID, UUID) IS
  '[Trace: §4.2, Article 20.2] AVAILABLE -> RESERVED, emits RESOURCE_RESERVED to Business.';

CREATE OR REPLACE FUNCTION trustride.fn_resource_assign(p_workforce_unit_id UUID, p_order_id UUID, p_correlation_id UUID, p_changed_by UUID)
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

  INSERT INTO trustride.resource_availability_ledger (resource_type, resource_ref_id, availability_state, reason_code, job_ref_id, changed_by)
  VALUES ('WORKFORCE_UNIT', p_workforce_unit_id, 'ASSIGNED', 'ORDER_ASSIGNMENT_CONFIRMED', p_order_id, p_changed_by)
  RETURNING availability_id INTO v_availability_id;

  INSERT INTO trustride.resource_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG004_BUS', 'RESOURCE_ASSIGNED',
    jsonb_build_object('order_id', p_order_id, 'workforce_unit_id', p_workforce_unit_id, 'capacity_class', v_capacity_class, 'engine_capacity', v_capacity_class, 'thing_id', v_thing_id),
    'RESOURCE_ASSIGNED:' || p_order_id::text || ':' || p_workforce_unit_id::text);

  INSERT INTO trustride.resource_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG005_COST', 'RESOURCE_DISPATCH_INITIATED',
    jsonb_build_object('asset_class', v_capacity_class, 'engine_capacity', v_capacity_class, 'order_id', p_order_id, 'assignment_id', v_availability_id),
    'RESOURCE_DISPATCH_INITIATED:' || p_order_id::text || ':' || p_workforce_unit_id::text);

  RETURN v_availability_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_assign(UUID, UUID, UUID, UUID) IS
  '[Trace: §4, Article 20.2] RESERVED -> ASSIGNED, emits RESOURCE_ASSIGNED to Business and RESOURCE_DISPATCH_INITIATED to Cost.';

-- --- Maintenance lifecycle ---

CREATE OR REPLACE FUNCTION trustride.fn_resource_maintenance_open(
  p_fleet_resource_id UUID, p_maintenance_type TEXT, p_performed_at_estate_id UUID, p_description TEXT, p_cost_kes NUMERIC, p_performed_by UUID, p_condition_before TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_maintenance_id UUID;
BEGIN
  INSERT INTO trustride.resource_maintenance_record (fleet_resource_id, maintenance_type, performed_at_estate_id, description, cost_kes, performed_by, condition_before)
  VALUES (p_fleet_resource_id, p_maintenance_type, p_performed_at_estate_id, p_description, p_cost_kes, p_performed_by, p_condition_before)
  RETURNING maintenance_id INTO v_maintenance_id;

  UPDATE trustride.resource_fleet_register SET lifecycle_state = 'MAINTAINED', updated_at = now() WHERE fleet_resource_id = p_fleet_resource_id;

  UPDATE trustride.resource_availability_ledger SET effective_to = now()
  WHERE resource_type = 'FLEET' AND resource_ref_id = p_fleet_resource_id AND effective_to IS NULL;
  INSERT INTO trustride.resource_availability_ledger (resource_type, resource_ref_id, availability_state, reason_code, changed_by)
  VALUES ('FLEET', p_fleet_resource_id, 'MAINTENANCE', 'MAINTENANCE_OPENED', p_performed_by);

  RETURN v_maintenance_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_maintenance_open(UUID, TEXT, UUID, TEXT, NUMERIC, UUID, TEXT) IS
  'Opens a maintenance event and takes the fleet resource offline for the duration (Article 38.3).';

CREATE OR REPLACE FUNCTION trustride.fn_resource_maintenance_complete(p_maintenance_id UUID, p_condition_after TEXT, p_changed_by UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_fleet_resource_id UUID;
BEGIN
  UPDATE trustride.resource_maintenance_record SET condition_after = p_condition_after, completed_at = now()
  WHERE maintenance_id = p_maintenance_id
  RETURNING fleet_resource_id INTO v_fleet_resource_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_resource_maintenance_complete: unknown maintenance_id %', p_maintenance_id;
  END IF;

  UPDATE trustride.resource_fleet_register SET lifecycle_state = 'VERIFIED', condition_record = p_condition_after, updated_at = now() WHERE fleet_resource_id = v_fleet_resource_id;

  UPDATE trustride.resource_availability_ledger SET effective_to = now()
  WHERE resource_type = 'FLEET' AND resource_ref_id = v_fleet_resource_id AND effective_to IS NULL;
  INSERT INTO trustride.resource_availability_ledger (resource_type, resource_ref_id, availability_state, reason_code, changed_by)
  VALUES ('FLEET', v_fleet_resource_id, 'OFFLINE', 'MAINTENANCE_COMPLETE_AWAITING_VERIFICATION', p_changed_by);
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_maintenance_complete(UUID, TEXT, UUID) IS
  'Closes a maintenance event. The resource returns OFFLINE, not AVAILABLE -- it re-enters service only once FLEET_VERIFICATION_UPDATED confirms compliance.';

-- --- Own Marketplace inventory lifecycle (Article 40) ---

CREATE OR REPLACE FUNCTION trustride.fn_resource_marketplace_inventory_register(
  p_item_code TEXT, p_category TEXT, p_acquisition_source TEXT, p_acquisition_cost_kes NUMERIC, p_custody_estate_id UUID
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_inventory_item_id UUID;
BEGIN
  INSERT INTO trustride.resource_marketplace_inventory (item_code, category, acquisition_source, acquisition_cost_kes, custody_estate_id)
  VALUES (p_item_code, p_category, p_acquisition_source, p_acquisition_cost_kes, p_custody_estate_id)
  RETURNING inventory_item_id INTO v_inventory_item_id;

  RETURN v_inventory_item_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_marketplace_inventory_register(TEXT, TEXT, TEXT, NUMERIC, UUID) IS
  'Registers an Own Marketplace item at ACQUIRED, the first Article 40 lifecycle stage.';

CREATE OR REPLACE FUNCTION trustride.fn_resource_marketplace_inventory_advance(
  p_inventory_item_id UUID, p_new_state trustride.resource_inventory_lifecycle_enum, p_correlation_id UUID DEFAULT gen_random_uuid(),
  p_valuation_kes NUMERIC DEFAULT NULL, p_inspection_status TEXT DEFAULT NULL, p_refurbishment_status TEXT DEFAULT NULL, p_compliance_status TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_current_state trustride.resource_inventory_lifecycle_enum;
  v_valid_sequence trustride.resource_inventory_lifecycle_enum[] := ARRAY[
    'ACQUIRED','INSPECTED','VALUED','REFURBISHED','COMPLIANT','LISTED','SOLD','AFTERCARE','RETIRED'
  ]::trustride.resource_inventory_lifecycle_enum[];
  v_current_idx INTEGER;
  v_new_idx     INTEGER;
BEGIN
  SELECT lifecycle_state INTO v_current_state FROM trustride.resource_marketplace_inventory WHERE inventory_item_id = p_inventory_item_id;
  IF v_current_state IS NULL THEN
    RAISE EXCEPTION 'fn_resource_marketplace_inventory_advance: unknown inventory_item_id %', p_inventory_item_id;
  END IF;

  v_current_idx := array_position(v_valid_sequence, v_current_state);
  v_new_idx := array_position(v_valid_sequence, p_new_state);
  IF v_new_idx IS DISTINCT FROM v_current_idx + 1 THEN
    RAISE EXCEPTION 'fn_resource_marketplace_inventory_advance: % cannot advance directly to % (must follow the Article 40 sequence)', v_current_state, p_new_state;
  END IF;

  UPDATE trustride.resource_marketplace_inventory
  SET lifecycle_state = p_new_state,
      valuation_kes = coalesce(p_valuation_kes, valuation_kes),
      inspection_status = coalesce(p_inspection_status, inspection_status),
      refurbishment_status = coalesce(p_refurbishment_status, refurbishment_status),
      compliance_status = coalesce(p_compliance_status, compliance_status),
      listed_at = CASE WHEN p_new_state = 'LISTED' THEN now() ELSE listed_at END,
      sold_at = CASE WHEN p_new_state = 'SOLD' THEN now() ELSE sold_at END
  WHERE inventory_item_id = p_inventory_item_id;

  IF p_new_state = 'COMPLIANT' THEN
    INSERT INTO trustride.resource_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (p_correlation_id, 'TRS026_ENG003_SERV', 'RESOURCE_MARKETPLACE_ITEM_READY',
      jsonb_build_object('inventory_item_id', p_inventory_item_id, 'lifecycle_state', p_new_state),
      'RESOURCE_MARKETPLACE_ITEM_READY:' || p_inventory_item_id::text);
  END IF;
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_marketplace_inventory_advance(UUID, trustride.resource_inventory_lifecycle_enum, UUID, NUMERIC, TEXT, TEXT, TEXT) IS
  '[Trace: Article 40] Enforces the exact sequential Article 40 lifecycle -- no stage may be skipped. Emits RESOURCE_MARKETPLACE_ITEM_READY on reaching COMPLIANT.';

-- --- Inbound signal accept-handlers (§5.1) ---

CREATE OR REPLACE FUNCTION trustride.fn_resource_assignment_requested_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, public, pg_temp
AS $$
DECLARE
  v_payload      JSONB;
  v_order_id     UUID;
  v_capacity_class trustride.resource_capacity_class_enum;
  v_pickup_lat   NUMERIC;
  v_pickup_lon   NUMERIC;
  v_correlation_id UUID;
  v_best UUID;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_correlation_id FROM trustride.resource_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_resource_assignment_requested_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  v_order_id := (v_payload->>'order_id')::UUID;
  v_capacity_class := (v_payload->>'required_capacity_class')::trustride.resource_capacity_class_enum;
  v_pickup_lat := (v_payload->'pickup_location'->>'latitude')::NUMERIC;
  v_pickup_lon := (v_payload->'pickup_location'->>'longitude')::NUMERIC;

  SELECT workforce_unit_id INTO v_best FROM trustride.fn_resource_discover(v_capacity_class, v_pickup_lat, v_pickup_lon) LIMIT 1;

  IF v_best IS NULL THEN
    UPDATE trustride.resource_event_inbox SET signal_status = 'REJECTED', rejection_reason = 'RESOURCE_NOT_AVAILABLE', accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END IF;

  PERFORM trustride.fn_resource_reserve(v_best, v_order_id, v_correlation_id, '00000000-0000-0000-0000-000000000000'::uuid);

  UPDATE trustride.resource_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now(), payload_out = jsonb_build_object('workforce_unit_id', v_best) WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_assignment_requested_accept(UUID) IS
  '[Trace: §5.1 ASSIGNMENT_REQUESTED] Discovers the nearest AVAILABLE unit and reserves it automatically; rejects at the inbox if none exists, never silently.';

CREATE OR REPLACE FUNCTION trustride.fn_resource_job_completed_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_workforce_unit_id UUID;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.resource_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_resource_job_completed_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  v_workforce_unit_id := (v_payload->>'workforce_unit_id')::UUID;

  UPDATE trustride.resource_availability_ledger SET effective_to = now()
  WHERE resource_type = 'WORKFORCE_UNIT' AND resource_ref_id = v_workforce_unit_id AND effective_to IS NULL;

  INSERT INTO trustride.resource_availability_ledger (resource_type, resource_ref_id, availability_state, reason_code, job_ref_id, changed_by)
  VALUES ('WORKFORCE_UNIT', v_workforce_unit_id, 'AVAILABLE', 'JOB_COMPLETED', (v_payload->>'job_id')::UUID, '00000000-0000-0000-0000-000000000000'::uuid);

  UPDATE trustride.resource_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_job_completed_accept(UUID) IS
  '[Trace: §5.1 JOB_COMPLETED, Article 19 Stage 7] Restores availability to AVAILABLE at the close of every Job.';

CREATE OR REPLACE FUNCTION trustride.fn_resource_fleet_verification_updated_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_fleet_resource_id UUID;
  v_inspection_status TEXT;
  v_insurance_status TEXT;
  v_compliant BOOLEAN;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.resource_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_resource_fleet_verification_updated_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  v_fleet_resource_id := (v_payload->>'fleet_resource_id')::UUID;
  v_inspection_status := v_payload->>'inspection_status';
  v_insurance_status := v_payload->>'insurance_status';
  v_compliant := (v_inspection_status = 'PASSED' AND v_insurance_status = 'ACTIVE');

  UPDATE trustride.resource_fleet_register
  SET inspection_status = v_inspection_status, insurance_status = v_insurance_status,
      lifecycle_state = (CASE WHEN v_compliant THEN 'VERIFIED' ELSE lifecycle_state::text END)::trustride.resource_lifecycle_state_enum, updated_at = now()
  WHERE fleet_resource_id = v_fleet_resource_id;

  UPDATE trustride.resource_availability_ledger SET effective_to = now()
  WHERE resource_type = 'FLEET' AND resource_ref_id = v_fleet_resource_id AND effective_to IS NULL;

  -- A CASE expression with two plain string-literal branches resolves to
  -- text, not the target enum -- unlike a bare literal, it does not get an
  -- implicit cast on INSERT. Found by actually running this signal handler,
  -- not by inspection. Explicit cast required.
  INSERT INTO trustride.resource_availability_ledger (resource_type, resource_ref_id, availability_state, reason_code, changed_by)
  VALUES ('FLEET', v_fleet_resource_id,
    (CASE WHEN v_compliant THEN 'AVAILABLE' ELSE 'OFFLINE' END)::trustride.resource_availability_state_enum,
    CASE WHEN v_compliant THEN 'VERIFICATION_PASSED' ELSE 'VERIFICATION_FAILED_NON_COMPLIANT' END, '00000000-0000-0000-0000-000000000000'::uuid);

  UPDATE trustride.resource_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_fleet_verification_updated_accept(UUID) IS
  '[Trace: §5.1 FLEET_VERIFICATION_UPDATED] A resource that falls out of compliance is transitioned to OFFLINE and made dispatch-ineligible -- never left silently ASSIGNED.';

CREATE OR REPLACE FUNCTION trustride.fn_resource_marketplace_listing_sold_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_inventory_item_id UUID;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.resource_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_resource_marketplace_listing_sold_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  v_inventory_item_id := (v_payload->>'inventory_item_id')::UUID;

  PERFORM trustride.fn_resource_marketplace_inventory_advance(v_inventory_item_id, 'SOLD');
  PERFORM trustride.fn_resource_marketplace_inventory_advance(v_inventory_item_id, 'AFTERCARE');

  UPDATE trustride.resource_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_resource_marketplace_listing_sold_accept(UUID) IS
  '[Trace: §5.1 MARKETPLACE_LISTING_SOLD, Article 40] Closes the item lifecycle to SOLD then AFTERCARE; the custody transfer to the buyer is recorded separately via fn_resource_custody_transfer.';

-- ============================================================================
-- PHASE 7 -- TRIGGERS
-- ============================================================================
-- [Trace: §2.5] PostgreSQL forbids a subquery inside a CHECK constraint; the
-- fleet-requirement rule is therefore a deferred constraint trigger, exactly
-- as the source document's own v1.0.1 remediation specifies.
CREATE OR REPLACE FUNCTION trustride.resource_workforce_unit_fleet_requirement()
RETURNS trigger
LANGUAGE plpgsql SET search_path = trustride, pg_temp
AS $$
BEGIN
  IF NEW.fleet_resource_id IS NULL AND NOT EXISTS (
    SELECT 1 FROM trustride.resource_capacity_class
    WHERE capacity_class_id = NEW.capacity_class_id AND requires_fleet = FALSE
  ) THEN
    RAISE EXCEPTION 'resource_workforce_unit % requires fleet_resource_id for capacity_class_id %',
      NEW.workforce_unit_id, NEW.capacity_class_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_resource_unit_fleet_requirement
  AFTER INSERT OR UPDATE ON trustride.resource_workforce_unit
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trustride.resource_workforce_unit_fleet_requirement();

-- ============================================================================
-- PHASE 8 -- ROW LEVEL SECURITY
-- ============================================================================
-- Uniform pattern across every table in this engine: governed/operational
-- resource state is platform-readable (matching the source document's own
-- design -- discovery, compliance, and availability must be visible for
-- dispatch to work at all), writable only by this engine's own service role.

ALTER TABLE trustride.resource_estate_register ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_estate_register_platform_read ON trustride.resource_estate_register FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_estate_register_service_write ON trustride.resource_estate_register FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.resource_capacity_class ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_capacity_class_platform_read ON trustride.resource_capacity_class FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_capacity_class_service_write ON trustride.resource_capacity_class FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.resource_fleet_register ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_fleet_register_platform_read ON trustride.resource_fleet_register FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_fleet_register_service_write ON trustride.resource_fleet_register FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.resource_equipment_register ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_equipment_register_platform_read ON trustride.resource_equipment_register FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_equipment_register_service_write ON trustride.resource_equipment_register FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.resource_workforce_unit ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_workforce_unit_platform_read ON trustride.resource_workforce_unit FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_workforce_unit_service_write ON trustride.resource_workforce_unit FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.resource_workforce_capability ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_workforce_capability_platform_read ON trustride.resource_workforce_capability FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_workforce_capability_service_write ON trustride.resource_workforce_capability FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.resource_availability_ledger ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_availability_ledger_platform_read ON trustride.resource_availability_ledger FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_availability_ledger_service_write ON trustride.resource_availability_ledger FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);

-- Financial assets: NOT platform-readable -- unlike physical resources,
-- exposing cash-float balances/custodianship broadly is a real business
-- confidentiality concern the source document never had to weigh (it named
-- no financial resource at all). Governor-only read, service write.
ALTER TABLE trustride.resource_financial_asset ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_financial_asset_governor_read ON trustride.resource_financial_asset FOR SELECT TO trustride_authenticated USING (trustride.fn_am_i_governor());
CREATE POLICY resource_financial_asset_service_write ON trustride.resource_financial_asset FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.resource_maintenance_record ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_maintenance_record_platform_read ON trustride.resource_maintenance_record FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_maintenance_record_service_write ON trustride.resource_maintenance_record FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.resource_marketplace_inventory ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_marketplace_inventory_platform_read ON trustride.resource_marketplace_inventory FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_marketplace_inventory_service_write ON trustride.resource_marketplace_inventory FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.resource_custody_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_custody_log_platform_read ON trustride.resource_custody_log FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY resource_custody_log_service_write ON trustride.resource_custody_log FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.resource_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_event_outbox_service_only ON trustride.resource_event_outbox FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.resource_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY resource_event_inbox_service_only ON trustride.resource_event_inbox FOR ALL TO trs026_eng002_resc_service USING (true) WITH CHECK (true);

-- ============================================================================
-- PHASE 9 -- INDEXES
-- ============================================================================
CREATE INDEX idx_resource_estate_location ON trustride.resource_estate_register USING GIST (location);
CREATE INDEX idx_resource_estate_type ON trustride.resource_estate_register (estate_type) WHERE active = TRUE;

CREATE UNIQUE INDEX uq_resource_capacity_class_code ON trustride.resource_capacity_class (class_code) WHERE active = TRUE;

CREATE INDEX idx_resource_fleet_class ON trustride.resource_fleet_register (capacity_class_id) WHERE active = TRUE;
CREATE INDEX idx_resource_fleet_estate ON trustride.resource_fleet_register (home_estate_id);
CREATE INDEX idx_resource_fleet_thing ON trustride.resource_fleet_register (thing_id);

CREATE INDEX idx_resource_equipment_issued ON trustride.resource_equipment_register (issued_to_user_id) WHERE issued_to_user_id IS NOT NULL;
CREATE INDEX idx_resource_equipment_type ON trustride.resource_equipment_register (equipment_type) WHERE active = TRUE;

CREATE UNIQUE INDEX uq_resource_unit_operator_active ON trustride.resource_workforce_unit (operator_user_id) WHERE unit_status = 'ACTIVE';
CREATE INDEX idx_resource_unit_fleet ON trustride.resource_workforce_unit (fleet_resource_id);
CREATE INDEX idx_resource_unit_class ON trustride.resource_workforce_unit (capacity_class_id) WHERE unit_status = 'ACTIVE';

CREATE INDEX idx_resource_capability_unit ON trustride.resource_workforce_capability (workforce_unit_id) WHERE active = TRUE;
CREATE INDEX idx_resource_capability_type ON trustride.resource_workforce_capability (capability_type) WHERE verified = TRUE;

CREATE INDEX idx_resource_availability_current ON trustride.resource_availability_ledger (resource_type, resource_ref_id) WHERE effective_to IS NULL;
CREATE INDEX idx_resource_availability_job ON trustride.resource_availability_ledger (job_ref_id) WHERE job_ref_id IS NOT NULL;

CREATE INDEX idx_resource_financial_asset_estate ON trustride.resource_financial_asset (home_estate_id);
CREATE INDEX idx_resource_financial_asset_type ON trustride.resource_financial_asset (asset_type) WHERE active = TRUE;

CREATE INDEX idx_resource_maintenance_fleet ON trustride.resource_maintenance_record (fleet_resource_id, created_at DESC);
CREATE INDEX idx_resource_maintenance_estate ON trustride.resource_maintenance_record (performed_at_estate_id);

CREATE INDEX idx_resource_inventory_lifecycle ON trustride.resource_marketplace_inventory (lifecycle_state);
CREATE INDEX idx_resource_inventory_estate ON trustride.resource_marketplace_inventory (custody_estate_id);

CREATE INDEX idx_resource_custody_resource ON trustride.resource_custody_log (resource_type, resource_ref_id, transferred_at DESC);

CREATE INDEX idx_resource_outbox_status ON trustride.resource_event_outbox (signal_status);
CREATE INDEX idx_resource_outbox_correlation ON trustride.resource_event_outbox (correlation_id);
CREATE INDEX idx_resource_inbox_status ON trustride.resource_event_inbox (signal_status);
CREATE INDEX idx_resource_inbox_correlation ON trustride.resource_event_inbox (correlation_id);

-- ============================================================================
-- PHASE 10 -- VIEWS
-- ============================================================================
CREATE VIEW trustride.v_resource_current_availability AS
SELECT al.resource_type, al.resource_ref_id, al.availability_state, al.effective_from, al.reason_code
FROM trustride.resource_availability_ledger al
WHERE al.effective_to IS NULL;
COMMENT ON VIEW trustride.v_resource_current_availability IS 'One row per resource: its live availability state right now.';

CREATE VIEW trustride.v_fleet_dispatch_eligible AS
SELECT fr.fleet_resource_id, fr.registration_particulars, cc.class_code, fr.inspection_status, fr.insurance_status, fr.lifecycle_state,
  (fr.inspection_status = 'PASSED' AND fr.insurance_status = 'ACTIVE' AND fr.active) AS dispatch_eligible
FROM trustride.resource_fleet_register fr
JOIN trustride.resource_capacity_class cc ON cc.capacity_class_id = fr.capacity_class_id;
COMMENT ON VIEW trustride.v_fleet_dispatch_eligible IS '[Trace: §4.3] The compliance-check API contract, realized as a queryable view.';

-- ============================================================================
-- PHASE 11 -- PRIVILEGE LOCKDOWN
-- ============================================================================
GRANT USAGE ON SCHEMA trustride TO trs026_eng002_resc_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA trustride TO trs026_eng002_resc_service;
GRANT SELECT ON trustride.v_resource_current_availability, trustride.v_fleet_dispatch_eligible TO trustride_authenticated;

-- Explicit, per-function grants only -- see Correction 6 in the header for why
-- this engine never uses a schema-wide "ALL FUNCTIONS" blanket.
GRANT EXECUTE ON FUNCTION trustride.fn_resource_estate_register(TEXT, trustride.resource_estate_type_enum, TEXT, NUMERIC, NUMERIC, TEXT, UUID, TEXT) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_fleet_register(UUID, trustride.resource_capacity_class_enum, trustride.resource_ownership_type_enum, TEXT, UUID, UUID) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_equipment_register(trustride.resource_equipment_type_enum, TEXT, TEXT, UUID, UUID, UUID) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_workforce_unit_form(UUID, trustride.resource_capacity_class_enum, UUID, UUID) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_workforce_capability_register(UUID, trustride.resource_capability_type_enum, TEXT) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_workforce_capability_verify(UUID, UUID, TIMESTAMPTZ) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_financial_asset_register(TEXT, trustride.resource_financial_asset_type_enum, trustride.resource_ownership_type_enum, NUMERIC, UUID, UUID, CHAR) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_custody_transfer(trustride.resource_custody_type_enum, UUID, UUID, UUID, UUID) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_discover(trustride.resource_capacity_class_enum, NUMERIC, NUMERIC) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_reserve(UUID, UUID, UUID, UUID) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_assign(UUID, UUID, UUID, UUID) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_maintenance_open(UUID, TEXT, UUID, TEXT, NUMERIC, UUID, TEXT) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_maintenance_complete(UUID, TEXT, UUID) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_marketplace_inventory_register(TEXT, TEXT, TEXT, NUMERIC, UUID) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_marketplace_inventory_advance(UUID, trustride.resource_inventory_lifecycle_enum, UUID, NUMERIC, TEXT, TEXT, TEXT) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_assignment_requested_accept(UUID) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_job_completed_accept(UUID) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_fleet_verification_updated_accept(UUID) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_resource_marketplace_listing_sold_accept(UUID) TO trs026_eng002_resc_service;

-- Correction 7: explicit access to the shared Foundation audit service.
GRANT EXECUTE ON FUNCTION trustride.fn_audit_log_append(TEXT, UUID, TEXT, UUID, TEXT, TEXT, TEXT, JSONB, JSONB) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_sequence_next(TEXT) TO trs026_eng002_resc_service;
GRANT EXECUTE ON FUNCTION trustride.fn_am_i_governor() TO trs026_eng002_resc_service;

GRANT trs026_eng002_resc_service TO service_role;

-- ============================================================================
-- PHASE 12 -- VALIDATION
-- ============================================================================
DO $$
DECLARE
  v_table_count    INTEGER;
  v_function_count INTEGER;
BEGIN
  SELECT count(*) INTO v_table_count
  FROM information_schema.tables
  WHERE table_schema = 'trustride' AND table_type = 'BASE TABLE'
    AND table_name LIKE 'resource_%';
  IF v_table_count <> 13 THEN
    RAISE EXCEPTION 'Engine 2 validation failed: expected 13 resource_ tables, found %', v_table_count;
  END IF;

  SELECT count(*) INTO v_function_count
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'trustride' AND p.proname LIKE 'fn_resource%';
  IF v_function_count <> 19 THEN
    RAISE EXCEPTION 'Engine 2 validation failed: expected 19 fn_resource%% functions, found %', v_function_count;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng002_resc_service') THEN
    RAISE EXCEPTION 'Engine 2 validation failed: trs026_eng002_resc_service role missing';
  END IF;

  RAISE NOTICE 'Engine 2 validation passed: 13/13 resource_ tables, 19/19 fn_resource%% functions, service role present.';
END
$$;

-- ============================================================================
-- PHASE 13 -- FINALIZATION & SEED DATA
-- ============================================================================

-- Pre-seed: Kisumu Headquarters (Article 38.1)
INSERT INTO trustride.resource_estate_register (estate_code, estate_type, estate_name, location, jurisdiction, custodian_user_id, compliance_status)
VALUES ('TRS-HQ-KSM-01', 'HQ', 'Kisumu Headquarters', ST_SetSRID(ST_MakePoint(34.767956, -0.091702), 4326),
        'KISUMU_COUNTY', '00000000-0000-0000-0000-000000000000', 'COMPLIANT');

-- Capacity class vocabulary -- including the Founder-directed SEDAN addition.
INSERT INTO trustride.resource_capacity_class (class_code, class_label, domain_affinity, requires_fleet, description) VALUES
  ('BODA_BODA', 'Motorcycle (Boda Boda)', 'TRANSPORT', TRUE, 'Standard motorcycle transport and last-mile delivery capacity.'),
  ('TUKTUK', 'Tuk-Tuk', 'TRANSPORT', TRUE, 'Three-wheeler passenger transport capacity.'),
  ('SEDAN', 'Small Car (Sedan)', 'TRANSPORT', TRUE, 'Standard passenger car capacity for private-hire rides.'),
  ('PICKUP_TOWN', 'Pickup (Town)', 'DELIVERY', TRUE, 'Light pickup for in-town goods movement.'),
  ('VAN_CARGO', 'Cargo Van', 'DELIVERY', TRUE, 'Van-class capacity for larger cargo movement.'),
  ('TRUCK_LIGHT', 'Light Truck', 'DELIVERY', TRUE, 'Light truck capacity for bulk or long-haul goods movement.'),
  ('EXECUTIVE_ASSISTANT_HUMAN', 'Executive Assistant', 'EXECUTIVE_ASSISTANTS', FALSE, 'Human-only capacity for errands, driving, caregiving, cleaning, chef, and shopping pillars (Article 27).');

UPDATE trustride.engine_registry SET status = 'INSTALLED', engine_version = '1.0.1' WHERE engine_code = 'TRS026_ENG002_RESC';
