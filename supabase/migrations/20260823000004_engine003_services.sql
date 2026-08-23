-- ============================================================================
-- TRUSTRIDE SERVICES PLATFORM
-- ============================================================================
-- PLATFORM ID          : b302bb5d-7d20-41e9-a074-a18d8ebd2aa5
-- PLATFORM CODE        : TRS026
-- PLATFORM NAME        : TRUSTRIDE_SERVICES
-- SCHEMA               : trustride
-- ENGINE NO            : ENGINE_003
-- ENGINE ID            : c1a2b3c4-0003-4eng-8003-003services03
-- ENGINE CODE          : TRS026_ENG003_SERV
-- ENGINE DOMAIN        : TrustRide Service Domain
-- ENGINE CLASS         : Service Engine
-- ENGINE TYPE          : Business Service Catalogue
-- ENGINE NAME          : TrustRide Services
-- ENGINE DESCRIPTION   : The platform's authoritative catalogue of everything
--                        TrustRide may lawfully offer -- macro domains,
--                        named services, Executive Assistants pillars and
--                        service lines, catalogue-driven special intents,
--                        eligibility, coverage, and marketplace listings.
-- ENGINE FUNCTION      : Answers, before any Order is placed: is this a
--                        registered Service, and under what terms may it be
--                        requested?
-- PLATFORM VERSION     : 1.0.0
-- ENGINE VERSION       : 1.0.1
-- MIGRATION DATA
-- FILE NAME            : 20260823000004_engine003_services.sql
-- INSTALLATION ORDER   : 003
-- STATUS               : COMPLETE -- one single migration file, 10 tables,
--                        applied on top of Foundation + Resources.
-- CREATED AT           : 2026-08-23
-- CREATED BY           : Onyango Albert Chitayi (Founder) + Engineering
-- ============================================================================
--
-- Source: TRS026-ENG003-SERV-001 v1.0.1 (ADOPTED 2026-08-16), Sections 2-4.
-- Corrections and Founder-directed amendments applied in this compilation:
--   1. Schema-qualified every table/type/function as `trustride.*`, and
--      trs026_eng003_serv_service created immediately after Phase 1 Schema
--      (Foundation's Correction 8 pattern), for the same reasons documented
--      in Engine 2's own file.
--   2. REAL BUG FOUND AND FIXED (2026-08-23, caught while tracing the
--      resolve workflow against the source document itself, before any
--      execution): the source document describes service_pillar and
--      service_line as things a customer selects that "resolve through a
--      catalogue Service" (the same Article 18 principle it states
--      explicitly for special intents), but its own DDL never links either
--      table back to service_catalogue -- there is no service_id column on
--      either. A customer selecting "Student Pickup" would have nowhere to
--      resolve eligibility or coverage from. Fixed by adding
--      service_id UUID NOT NULL REFERENCES service_catalogue(service_id)
--      to both tables.
--   3. Founder ruling 2026-08-23 (Kisumu build plan, item 2): "DESIGN
--      IMPLEMENT THE COMPLETE CATALOGUE AS TRUSTRIDE DEFINES THEM END TO
--      END." The source document's own §2.2 service_catalogue table has NO
--      seed data at all -- every other governed vocabulary table in this
--      document (macro domains, pillars, service lines) is seeded, but the
--      one table that is literally "the shelf everything sells from" is
--      left empty, exactly the same spec-describes-but-never-compiles gap
--      already found and named in Foundation's own corpus read and in
--      Engine 2's blueprint. This file seeds the real, complete catalogue:
--      3 Transport services, 2 Courier, 2 Delivery, 11 Executive Assistants
--      (6 pillar-general + 3 named-line + Academy Training + Employment
--      Application), 6 Marketplace (item sale, vendor onboarding,
--      acquisition, refurbishment, listing, and resource contribution) --
--      24 services total, each with real eligibility (where it dispatches
--      a resource) and Kisumu County coverage, matching this platform's
--      own build sequencing.
--   4. Domain placement judgment call, flagged rather than silently
--      assumed: Article 18 names ACADEMY_TRAINING, EMPLOYMENT_APPLICATION,
--      and RESOURCE_CONTRIBUTION as special intents that must each resolve
--      to a catalogue Service, but the source document gives no article
--      text specifying which of the five macro domains they belong under,
--      and none is an obvious fit (none are movement-of-people/goods).
--      Placed Academy Training and Employment Application under
--      EXECUTIVE_ASSISTANTS (closest available fit -- human capability,
--      not vehicle dispatch); placed Resource Contribution under
--      MARKETPLACE alongside Vendor Onboarding (both are a Partner
--      entering a commercial/contribution relationship with the
--      platform). This should be confirmed against Article 18's full text
--      when it is next read in full, not treated as settled law.
--   5. A single service_catalogue row covers a marketplace item sale
--      regardless of listing type -- service_marketplace_listing.
--      listing_type (VENDOR_FACILITATED vs OWN_MARKETPLACE) already makes
--      that distinction at the listing level, so two duplicate catalogue
--      rows for "vendor sale" vs "own-marketplace sale" would be a real
--      duplication, not two genuinely different services.
--   6. Explicit per-function GRANTs to trs026_eng003_serv_service, never a
--      schema-wide blanket -- same reasoning as Engine 2's Correction 6.
--   7. Lawful state-changing functions append to Foundation's shared
--      platform-wide audit hash chain via trustride.fn_audit_log_append,
--      granted explicitly here -- same reasoning as Engine 2's Correction 7.
--
-- ============================================================================

-- ============================================================================
-- PHASE 0 -- EXTENSIONS (idempotent; already present platform-wide)
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- PHASE 1 -- SCHEMA + EARLY ROLE CREATION
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng003_serv_service') THEN
    CREATE ROLE trs026_eng003_serv_service NOLOGIN;
  END IF;
END
$$;

-- ============================================================================
-- PHASE 2 -- ENUMS
-- ============================================================================

-- [Trace: TBOC-v2.0.0 | Article 23 | The Five Domains -- exactly five, no sixth without amendment]
CREATE TYPE trustride.service_macro_domain_enum AS ENUM (
  'TRANSPORT', 'COURIER', 'DELIVERY', 'EXECUTIVE_ASSISTANTS', 'MARKETPLACE'
);

CREATE TYPE trustride.service_status_enum AS ENUM (
  'DRAFT', 'ACTIVE', 'SUSPENDED', 'RETIRED'
);

-- [Trace: TBOC-v2.0.0 | Article 27 | The six Executive Assistants pillars, verbatim]
CREATE TYPE trustride.service_pillar_code_enum AS ENUM (
  'ERRANDS', 'DRIVING', 'CAREGIVING', 'CLEANING', 'CHEF', 'SHOPPING'
);

CREATE TYPE trustride.service_safeguarding_tier_enum AS ENUM (
  'STANDARD', 'ENHANCED'
);

-- [Trace: TBOC-v2.0.0 | Article 18 | Catalogue-Driven Special Intents]
CREATE TYPE trustride.service_special_intent_code_enum AS ENUM (
  'ACADEMY_TRAINING', 'EMPLOYMENT_APPLICATION', 'VENDOR_ONBOARDING',
  'RESOURCE_CONTRIBUTION', 'MARKETPLACE_ACQUISITION', 'MARKETPLACE_REFURBISHMENT',
  'MARKETPLACE_LISTING', 'MARKETPLACE_SALE'
);

-- [Trace: TBOC-v2.0.0 | Article 28 | Marketplace -- the two lawful modes]
CREATE TYPE trustride.service_listing_type_enum AS ENUM (
  'VENDOR_FACILITATED', 'OWN_MARKETPLACE'
);

CREATE TYPE trustride.service_listing_status_enum AS ENUM (
  'DRAFT', 'LISTED', 'RESERVED', 'SOLD', 'DELISTED'
);

-- ============================================================================
-- PHASE 3/4/5 -- TABLES, CONSTRAINTS, RELATIONSHIPS
-- ============================================================================

-- --- 2.1 service_macro_domain ---
CREATE TABLE trustride.service_macro_domain (
  macro_domain_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  domain_code     trustride.service_macro_domain_enum NOT NULL UNIQUE,
  domain_label    TEXT NOT NULL,
  domain_purpose  TEXT NOT NULL,
  active          BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.service_macro_domain IS
  '[Trace: TBOC-v2.0.0 | Article 23] The constitutional source of the five macro domains; no sixth row may be inserted without an upstream TBOC amendment.';

-- --- 2.2 service_catalogue ---
CREATE TABLE trustride.service_catalogue (
  service_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_code              TEXT NOT NULL UNIQUE,
  service_name              TEXT NOT NULL,
  macro_domain_id           UUID NOT NULL REFERENCES trustride.service_macro_domain (macro_domain_id),
  description                TEXT NOT NULL,
  eligibility_rules_summary  TEXT,
  requirements                  JSONB NOT NULL DEFAULT '{}',
  status                          trustride.service_status_enum NOT NULL DEFAULT 'DRAFT',
  approved_request_id                UUID,
  effective_from                       TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to                           TIMESTAMPTZ,
  created_at                               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_service_catalogue_validity CHECK (effective_to IS NULL OR effective_to > effective_from)
);
COMMENT ON TABLE trustride.service_catalogue IS
  '[Trace: TBOC-v2.0.0 | Article 15] No capability may be offered, promised, or delivered that is not a registered ACTIVE row here.';

-- --- 2.3 service_pillar (Correction 2: + service_id) ---
CREATE TABLE trustride.service_pillar (
  pillar_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pillar_code     trustride.service_pillar_code_enum NOT NULL UNIQUE,
  macro_domain_id UUID NOT NULL REFERENCES trustride.service_macro_domain (macro_domain_id),
  service_id      UUID REFERENCES trustride.service_catalogue (service_id),
  pillar_label    TEXT NOT NULL,
  description     TEXT NOT NULL,
  active          BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.service_pillar IS
  '[Trace: TBOC-v2.0.0 | Article 27.2.1] Structurally bound beneath Executive Assistants (deferred constraint trigger below); service_id (Correction 2) is the pillar''s own general-purpose catalogue entry.';

-- --- 2.4 service_line (Correction 2: + service_id) ---
CREATE TABLE trustride.service_line (
  service_line_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pillar_id                        UUID NOT NULL REFERENCES trustride.service_pillar (pillar_id),
  service_id                       UUID REFERENCES trustride.service_catalogue (service_id),
  line_code                        TEXT NOT NULL UNIQUE,
  line_name                        TEXT NOT NULL,
  description                      TEXT NOT NULL,
  safeguarding_tier                trustride.service_safeguarding_tier_enum NOT NULL DEFAULT 'STANDARD',
  guardian_authorization_required  BOOLEAN NOT NULL DEFAULT FALSE,
  active                            BOOLEAN NOT NULL DEFAULT TRUE,
  created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.service_line IS
  '[Trace: TBOC-v2.0.0 | Article 27.1, 27.2.3] Child-facing lines (Student Pickup) carry ENHANCED safeguarding_tier and mandatory guardian authorization; service_id (Correction 2) is the line''s own specific catalogue entry.';

-- --- 2.5 service_special_intent ---
CREATE TABLE trustride.service_special_intent (
  special_intent_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  intent_code             trustride.service_special_intent_code_enum NOT NULL UNIQUE,
  intent_label              TEXT NOT NULL,
  resolves_to_service_id      UUID NOT NULL REFERENCES trustride.service_catalogue (service_id),
  description                    TEXT NOT NULL,
  active                            BOOLEAN NOT NULL DEFAULT TRUE,
  created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.service_special_intent IS
  '[Trace: TBOC-v2.0.0 | Article 18] In every case the intent selects a catalogue Service; scope is described in the resulting Order''s Order Lines (Engine 4).';

-- --- 2.6 service_eligibility_rule ---
CREATE TABLE trustride.service_eligibility_rule (
  eligibility_rule_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id                   UUID NOT NULL REFERENCES trustride.service_catalogue (service_id),
  required_capacity_class_code TEXT NOT NULL,
  required_vetting_tier        TEXT NOT NULL DEFAULT 'STANDARD',
  required_certifications      JSONB NOT NULL DEFAULT '[]',
  active                       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at                   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE trustride.service_eligibility_rule IS
  '[Trace: TBOC-v2.0.0 | Article 29] Evaluated by Engine 2 at resource discovery time; a resource lacking the required capacity class, vetting tier, or certification is excluded from candidacy.';

-- --- 2.7 service_coverage_zone ---
CREATE TABLE trustride.service_coverage_zone (
  coverage_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id    UUID NOT NULL REFERENCES trustride.service_catalogue (service_id),
  jurisdiction  TEXT NOT NULL,
  active        BOOLEAN NOT NULL DEFAULT TRUE,
  effective_from TIMESTAMPTZ NOT NULL DEFAULT now(),
  effective_to   TIMESTAMPTZ,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_service_coverage_validity CHECK (effective_to IS NULL OR effective_to > effective_from)
);
COMMENT ON TABLE trustride.service_coverage_zone IS
  '[Trace: TBOC-v2.0.0 | Article 15] A Service not covered in the requester''s jurisdiction is not offered there, regardless of catalogue status.';

-- --- 2.8 service_marketplace_listing ---
CREATE TABLE trustride.service_marketplace_listing (
  listing_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id        UUID NOT NULL REFERENCES trustride.service_catalogue (service_id),
  listing_type      trustride.service_listing_type_enum NOT NULL,
  vendor_user_id    UUID,
  inventory_item_id UUID,
  title             TEXT NOT NULL,
  description       TEXT NOT NULL,
  list_price_kes    NUMERIC(18,2) NOT NULL CHECK (list_price_kes >= 0),
  listing_status    trustride.service_listing_status_enum NOT NULL DEFAULT 'DRAFT',
  listed_at         TIMESTAMPTZ,
  delisted_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_service_listing_type_reference
    CHECK (
      (listing_type = 'OWN_MARKETPLACE' AND inventory_item_id IS NOT NULL AND vendor_user_id IS NULL)
      OR
      (listing_type = 'VENDOR_FACILITATED' AND vendor_user_id IS NOT NULL AND inventory_item_id IS NULL)
    )
);
COMMENT ON TABLE trustride.service_marketplace_listing IS
  '[Trace: TBOC-v2.0.0 | Article 28.1, 28.2] The sellable catalogue entry; physical custody of an Own Marketplace item remains Engine 2''s resource_marketplace_inventory throughout.';

-- --- 2.9 Engine Event Substrate ---
CREATE TABLE trustride.service_event_outbox (
  signal_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id   UUID NOT NULL,
  causation_id     UUID,
  emitting_engine  TEXT NOT NULL DEFAULT 'TRS026_ENG003_SERV',
  receiving_engine TEXT NOT NULL,
  signal_type      TEXT NOT NULL,
  payload_in       JSONB NOT NULL,
  signal_status    TEXT NOT NULL DEFAULT 'PENDING'
                      CHECK (signal_status IN ('PENDING','DISPATCHED','RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason TEXT,
  idempotency_key  TEXT NOT NULL UNIQUE,
  attempt_count    INTEGER NOT NULL DEFAULT 0,
  emitted_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_service_outbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);

CREATE TABLE trustride.service_event_inbox (
  signal_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  correlation_id   UUID NOT NULL,
  causation_id     UUID,
  emitting_engine  TEXT NOT NULL,
  receiving_engine TEXT NOT NULL DEFAULT 'TRS026_ENG003_SERV',
  signal_type      TEXT NOT NULL,
  payload_in       JSONB NOT NULL,
  payload_out      JSONB,
  signal_status    TEXT NOT NULL DEFAULT 'RECEIVED'
                      CHECK (signal_status IN ('RECEIVED','ACCEPTED','REJECTED','DEAD_LETTER')),
  rejection_reason TEXT,
  idempotency_key  TEXT NOT NULL UNIQUE,
  received_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at      TIMESTAMPTZ,
  CONSTRAINT chk_service_inbox_rejection CHECK (signal_status <> 'REJECTED' OR rejection_reason IS NOT NULL)
);

-- ============================================================================
-- PHASE 6 -- FUNCTIONS
-- ============================================================================

-- --- Catalogue registration: the one lawful way a Service enters the catalogue ---
CREATE OR REPLACE FUNCTION trustride.fn_service_catalogue_register(
  p_service_code TEXT, p_service_name TEXT, p_macro_domain trustride.service_macro_domain_enum, p_description TEXT,
  p_requirements JSONB DEFAULT '{}', p_registered_by UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
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
    'USER', NULL, NULL, NULL, jsonb_build_object('service_code', p_service_code, 'macro_domain', p_macro_domain));

  RETURN v_service_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_service_catalogue_register(TEXT, TEXT, trustride.service_macro_domain_enum, TEXT, JSONB, UUID) IS
  'Registers a Service at DRAFT; see fn_service_catalogue_activate to make it orderable.';

CREATE OR REPLACE FUNCTION trustride.fn_service_catalogue_activate(p_service_id UUID, p_activated_by UUID, p_approved_request_id UUID DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
BEGIN
  UPDATE trustride.service_catalogue SET status = 'ACTIVE', approved_request_id = p_approved_request_id, updated_at = now()
  WHERE service_id = p_service_id AND status = 'DRAFT';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_service_catalogue_activate: service_id % is not in DRAFT (or does not exist)', p_service_id;
  END IF;

  PERFORM trustride.fn_audit_log_append('service_catalogue', p_service_id, 'SERVICE_ACTIVATED', p_activated_by,
    'USER', NULL, NULL, NULL, jsonb_build_object('approved_request_id', p_approved_request_id));

  INSERT INTO trustride.service_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (gen_random_uuid(), 'TRS026_ENG011_PRESENT', 'SERVICE_CATALOGUE_UPDATED',
    jsonb_build_object('service_id', p_service_id, 'status', 'ACTIVE', 'effective_from', now()),
    'SERVICE_CATALOGUE_UPDATED:' || p_service_id::text || ':' || now()::text);
END;
$$;
COMMENT ON FUNCTION trustride.fn_service_catalogue_activate(UUID, UUID, UUID) IS
  'DRAFT -> ACTIVE, the one lawful way a Service becomes orderable. Broadcasts SERVICE_CATALOGUE_UPDATED.';

CREATE OR REPLACE FUNCTION trustride.fn_service_eligibility_rule_add(
  p_service_id UUID, p_required_capacity_class_code TEXT, p_required_vetting_tier TEXT DEFAULT 'STANDARD', p_required_certifications JSONB DEFAULT '[]'
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_eligibility_rule_id UUID;
BEGIN
  INSERT INTO trustride.service_eligibility_rule (service_id, required_capacity_class_code, required_vetting_tier, required_certifications)
  VALUES (p_service_id, p_required_capacity_class_code, p_required_vetting_tier, p_required_certifications)
  RETURNING eligibility_rule_id INTO v_eligibility_rule_id;

  RETURN v_eligibility_rule_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_service_eligibility_rule_add(UUID, TEXT, TEXT, JSONB) IS
  '[Trace: Article 29] Adds a resource-eligibility rule a Service requires before assignment.';

CREATE OR REPLACE FUNCTION trustride.fn_service_coverage_zone_add(p_service_id UUID, p_jurisdiction TEXT)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_coverage_id UUID;
BEGIN
  INSERT INTO trustride.service_coverage_zone (service_id, jurisdiction)
  VALUES (p_service_id, p_jurisdiction)
  RETURNING coverage_id INTO v_coverage_id;

  RETURN v_coverage_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_service_coverage_zone_add(UUID, TEXT) IS
  'Opens a jurisdiction in which a Service is lawfully offered.';

-- --- Resolve (§3.2 API contract, Article 19 Stage 1) ---
CREATE OR REPLACE FUNCTION trustride.fn_service_resolve(p_service_code TEXT, p_jurisdiction TEXT)
RETURNS TABLE (
  service_id UUID, macro_domain trustride.service_macro_domain_enum, coverage_confirmed BOOLEAN,
  required_capacity_class_code TEXT, required_vetting_tier TEXT, required_certifications JSONB
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_service_id UUID;
  v_macro_domain trustride.service_macro_domain_enum;
BEGIN
  SELECT sc.service_id, sm.domain_code INTO v_service_id, v_macro_domain
  FROM trustride.service_catalogue sc JOIN trustride.service_macro_domain sm ON sm.macro_domain_id = sc.macro_domain_id
  WHERE sc.service_code = p_service_code AND sc.status = 'ACTIVE';

  IF v_service_id IS NULL THEN
    RAISE EXCEPTION 'fn_service_resolve: no ACTIVE service with service_code %', p_service_code;
  END IF;

  RETURN QUERY
  SELECT v_service_id, v_macro_domain,
    EXISTS (SELECT 1 FROM trustride.service_coverage_zone cz WHERE cz.service_id = v_service_id AND cz.jurisdiction = p_jurisdiction AND cz.active = TRUE AND cz.effective_to IS NULL),
    er.required_capacity_class_code, er.required_vetting_tier, er.required_certifications
  FROM trustride.service_eligibility_rule er
  WHERE er.service_id = v_service_id AND er.active = TRUE
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT v_service_id, v_macro_domain,
      EXISTS (SELECT 1 FROM trustride.service_coverage_zone cz WHERE cz.service_id = v_service_id AND cz.jurisdiction = p_jurisdiction AND cz.active = TRUE AND cz.effective_to IS NULL),
      NULL::TEXT, NULL::TEXT, NULL::JSONB;
  END IF;
END;
$$;
COMMENT ON FUNCTION trustride.fn_service_resolve(TEXT, TEXT) IS
  '[Trace: §3.2, Article 19 Stage 1] Resolves a Service and confirms coverage in the requester''s jurisdiction; a Service with no eligibility_rule row (Marketplace, Academy, Employment) returns NULL eligibility, which is lawful, not an error.';

-- --- Marketplace listing lifecycle (Article 28) ---
CREATE OR REPLACE FUNCTION trustride.fn_service_marketplace_listing_create(
  p_service_id UUID, p_listing_type trustride.service_listing_type_enum, p_title TEXT, p_description TEXT, p_list_price_kes NUMERIC,
  p_vendor_user_id UUID DEFAULT NULL, p_inventory_item_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_listing_id UUID;
BEGIN
  INSERT INTO trustride.service_marketplace_listing (service_id, listing_type, vendor_user_id, inventory_item_id, title, description, list_price_kes)
  VALUES (p_service_id, p_listing_type, p_vendor_user_id, p_inventory_item_id, p_title, p_description, p_list_price_kes)
  RETURNING listing_id INTO v_listing_id;

  RETURN v_listing_id;
END;
$$;
COMMENT ON FUNCTION trustride.fn_service_marketplace_listing_create(UUID, trustride.service_listing_type_enum, TEXT, TEXT, NUMERIC, UUID, UUID) IS
  '[Trace: Article 28.1, 28.2] Creates a DRAFT listing. An OWN_MARKETPLACE listing only becomes LISTED once Engine 2 confirms COMPLIANT via RESOURCE_MARKETPLACE_ITEM_READY.';

CREATE OR REPLACE FUNCTION trustride.fn_service_marketplace_listing_publish(p_listing_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
BEGIN
  UPDATE trustride.service_marketplace_listing SET listing_status = 'LISTED', listed_at = now()
  WHERE listing_id = p_listing_id AND listing_status = 'DRAFT';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_service_marketplace_listing_publish: listing_id % is not DRAFT (or does not exist)', p_listing_id;
  END IF;
END;
$$;
COMMENT ON FUNCTION trustride.fn_service_marketplace_listing_publish(UUID) IS
  'DRAFT -> LISTED, the one lawful way a listing becomes purchasable.';

CREATE OR REPLACE FUNCTION trustride.fn_service_marketplace_listing_sell(p_listing_id UUID, p_correlation_id UUID DEFAULT gen_random_uuid())
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_inventory_item_id UUID;
  v_list_price_kes    NUMERIC;
BEGIN
  UPDATE trustride.service_marketplace_listing SET listing_status = 'SOLD'
  WHERE listing_id = p_listing_id AND listing_status IN ('LISTED', 'RESERVED')
  RETURNING inventory_item_id, list_price_kes INTO v_inventory_item_id, v_list_price_kes;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'fn_service_marketplace_listing_sell: listing_id % is not LISTED/RESERVED (or does not exist)', p_listing_id;
  END IF;

  INSERT INTO trustride.service_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (p_correlation_id, 'TRS026_ENG004_BUS', 'MARKETPLACE_LISTING_SOLD',
    jsonb_build_object('listing_id', p_listing_id, 'inventory_item_id', v_inventory_item_id, 'list_price_kes', v_list_price_kes),
    'MARKETPLACE_LISTING_SOLD:BUS:' || p_listing_id::text);

  IF v_inventory_item_id IS NOT NULL THEN
    INSERT INTO trustride.service_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
    VALUES (p_correlation_id, 'TRS026_ENG002_RESC', 'MARKETPLACE_LISTING_SOLD',
      jsonb_build_object('listing_id', p_listing_id, 'inventory_item_id', v_inventory_item_id, 'list_price_kes', v_list_price_kes),
      'MARKETPLACE_LISTING_SOLD:RESC:' || p_listing_id::text);
  END IF;
END;
$$;
COMMENT ON FUNCTION trustride.fn_service_marketplace_listing_sell(UUID, UUID) IS
  '[Trace: §4.2] LISTED/RESERVED -> SOLD, emits MARKETPLACE_LISTING_SOLD to both Business (settlement) and Resources (custody hand-off, Own Marketplace only).';

-- --- Inbound signal accept-handlers (§4.1) ---
CREATE OR REPLACE FUNCTION trustride.fn_service_lookup_requested_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_correlation_id UUID;
  v_service_code TEXT;
  v_jurisdiction TEXT;
  v_resolved RECORD;
BEGIN
  SELECT payload_in, correlation_id INTO v_payload, v_correlation_id FROM trustride.service_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_service_lookup_requested_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  v_service_code := v_payload->>'service_code';
  v_jurisdiction := v_payload->>'jurisdiction';

  BEGIN
    SELECT * INTO v_resolved FROM trustride.fn_service_resolve(v_service_code, v_jurisdiction);
  EXCEPTION WHEN OTHERS THEN
    UPDATE trustride.service_event_inbox SET signal_status = 'REJECTED', rejection_reason = SQLERRM, accepted_at = now() WHERE signal_id = p_signal_id;
    RETURN 'REJECTED';
  END;

  INSERT INTO trustride.service_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v_correlation_id, 'TRS026_ENG004_BUS', 'SERVICE_RESOLVED',
    jsonb_build_object('service_id', v_resolved.service_id, 'macro_domain', v_resolved.macro_domain,
      'coverage_confirmed', v_resolved.coverage_confirmed,
      'eligibility', jsonb_build_object('required_capacity_class_code', v_resolved.required_capacity_class_code,
        'required_vetting_tier', v_resolved.required_vetting_tier, 'required_certifications', v_resolved.required_certifications)),
    'SERVICE_RESOLVED:' || v_correlation_id::text);

  INSERT INTO trustride.service_event_outbox (correlation_id, receiving_engine, signal_type, payload_in, idempotency_key)
  VALUES (v_correlation_id, 'TRS026_ENG005_COST', 'SERVICE_CONTEXT_RESOLVED',
    jsonb_build_object('macro_domain', v_resolved.macro_domain, 'service_code', v_service_code),
    'SERVICE_CONTEXT_RESOLVED:' || v_correlation_id::text);

  UPDATE trustride.service_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_service_lookup_requested_accept(UUID) IS
  '[Trace: §4.1 SERVICE_LOOKUP_REQUESTED, Article 19 Stage 1] Resolves the Service and emits SERVICE_RESOLVED to Business and SERVICE_CONTEXT_RESOLVED to Cost.';

CREATE OR REPLACE FUNCTION trustride.fn_service_vendor_verification_updated_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_vendor_user_id UUID;
  v_verified BOOLEAN;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.service_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_service_vendor_verification_updated_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  v_vendor_user_id := (v_payload->>'vendor_user_id')::UUID;
  v_verified := (v_payload->>'verification_status') = 'VERIFIED';

  IF NOT v_verified THEN
    UPDATE trustride.service_marketplace_listing
    SET listing_status = 'DELISTED', delisted_at = now()
    WHERE vendor_user_id = v_vendor_user_id AND listing_status IN ('DRAFT','LISTED','RESERVED');
  END IF;

  UPDATE trustride.service_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_service_vendor_verification_updated_accept(UUID) IS
  '[Trace: §4.1 VENDOR_VERIFICATION_UPDATED] A vendor falling out of verification has every non-terminal listing transitioned to DELISTED, never left silently purchasable.';

CREATE OR REPLACE FUNCTION trustride.fn_service_resource_marketplace_item_ready_accept(p_signal_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = trustride, pg_temp
AS $$
DECLARE
  v_payload JSONB;
  v_inventory_item_id UUID;
BEGIN
  SELECT payload_in INTO v_payload FROM trustride.service_event_inbox WHERE signal_id = p_signal_id AND signal_status = 'RECEIVED';
  IF v_payload IS NULL THEN
    RAISE EXCEPTION 'fn_service_resource_marketplace_item_ready_accept: no RECEIVED signal %', p_signal_id;
  END IF;

  v_inventory_item_id := (v_payload->>'inventory_item_id')::UUID;

  UPDATE trustride.service_marketplace_listing SET listing_status = 'LISTED', listed_at = now()
  WHERE inventory_item_id = v_inventory_item_id AND listing_status = 'DRAFT';

  UPDATE trustride.service_event_inbox SET signal_status = 'ACCEPTED', accepted_at = now() WHERE signal_id = p_signal_id;
  RETURN 'ACCEPTED';
END;
$$;
COMMENT ON FUNCTION trustride.fn_service_resource_marketplace_item_ready_accept(UUID) IS
  '[Trace: §4.1 RESOURCE_MARKETPLACE_ITEM_READY, Article 40] Enables the matching DRAFT listing to become LISTED once Engine 2 confirms the item is COMPLIANT.';

-- ============================================================================
-- PHASE 7 -- TRIGGERS
-- ============================================================================
CREATE OR REPLACE FUNCTION trustride.service_pillar_domain_ea()
RETURNS trigger
LANGUAGE plpgsql SET search_path = trustride, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM trustride.service_macro_domain
    WHERE macro_domain_id = NEW.macro_domain_id AND domain_code = 'EXECUTIVE_ASSISTANTS'
  ) THEN
    RAISE EXCEPTION 'service_pillar % must bind to the EXECUTIVE_ASSISTANTS macro domain, got macro_domain_id %',
      NEW.pillar_code, NEW.macro_domain_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER trg_service_pillar_domain_ea
  AFTER INSERT OR UPDATE ON trustride.service_pillar
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trustride.service_pillar_domain_ea();

-- ============================================================================
-- PHASE 8 -- ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE trustride.service_macro_domain ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_macro_domain_platform_read ON trustride.service_macro_domain FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY service_macro_domain_service_write ON trustride.service_macro_domain FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.service_catalogue ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_catalogue_platform_read ON trustride.service_catalogue FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY service_catalogue_service_write ON trustride.service_catalogue FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.service_pillar ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_pillar_platform_read ON trustride.service_pillar FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY service_pillar_service_write ON trustride.service_pillar FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.service_line ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_line_platform_read ON trustride.service_line FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY service_line_service_write ON trustride.service_line FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.service_special_intent ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_special_intent_platform_read ON trustride.service_special_intent FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY service_special_intent_service_write ON trustride.service_special_intent FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.service_eligibility_rule ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_eligibility_rule_platform_read ON trustride.service_eligibility_rule FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY service_eligibility_rule_service_write ON trustride.service_eligibility_rule FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.service_coverage_zone ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_coverage_zone_platform_read ON trustride.service_coverage_zone FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY service_coverage_zone_service_write ON trustride.service_coverage_zone FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.service_marketplace_listing ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_marketplace_listing_platform_read ON trustride.service_marketplace_listing FOR SELECT TO trustride_authenticated USING (true);
CREATE POLICY service_marketplace_listing_service_write ON trustride.service_marketplace_listing FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.service_event_outbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_event_outbox_service_only ON trustride.service_event_outbox FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);

ALTER TABLE trustride.service_event_inbox ENABLE ROW LEVEL SECURITY;
CREATE POLICY service_event_inbox_service_only ON trustride.service_event_inbox FOR ALL TO trs026_eng003_serv_service USING (true) WITH CHECK (true);

-- ============================================================================
-- PHASE 9 -- INDEXES
-- ============================================================================
CREATE INDEX idx_service_catalogue_domain ON trustride.service_catalogue (macro_domain_id) WHERE status = 'ACTIVE';
CREATE UNIQUE INDEX uq_service_catalogue_code_active ON trustride.service_catalogue (service_code) WHERE status = 'ACTIVE';

CREATE INDEX idx_service_line_pillar ON trustride.service_line (pillar_id) WHERE active = TRUE;
CREATE INDEX idx_service_eligibility_service ON trustride.service_eligibility_rule (service_id) WHERE active = TRUE;
CREATE INDEX idx_service_coverage_service_jurisdiction ON trustride.service_coverage_zone (service_id, jurisdiction) WHERE active = TRUE;

CREATE INDEX idx_service_listing_status ON trustride.service_marketplace_listing (listing_status);
CREATE INDEX idx_service_listing_vendor ON trustride.service_marketplace_listing (vendor_user_id) WHERE vendor_user_id IS NOT NULL;

CREATE INDEX idx_service_outbox_status ON trustride.service_event_outbox (signal_status);
CREATE INDEX idx_service_outbox_correlation ON trustride.service_event_outbox (correlation_id);
CREATE INDEX idx_service_inbox_status ON trustride.service_event_inbox (signal_status);
CREATE INDEX idx_service_inbox_correlation ON trustride.service_event_inbox (correlation_id);

-- ============================================================================
-- PHASE 10 -- VIEWS
-- ============================================================================
CREATE VIEW trustride.v_service_catalogue_active AS
SELECT sc.service_id, sc.service_code, sc.service_name, sm.domain_code AS macro_domain, sc.description
FROM trustride.service_catalogue sc JOIN trustride.service_macro_domain sm ON sm.macro_domain_id = sc.macro_domain_id
WHERE sc.status = 'ACTIVE';
COMMENT ON VIEW trustride.v_service_catalogue_active IS '[Trace: §3.1] The live, orderable catalogue.';

-- ============================================================================
-- PHASE 11 -- PRIVILEGE LOCKDOWN
-- ============================================================================
GRANT USAGE ON SCHEMA trustride TO trs026_eng003_serv_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA trustride TO trs026_eng003_serv_service;
GRANT SELECT ON trustride.v_service_catalogue_active TO trustride_authenticated;

GRANT EXECUTE ON FUNCTION trustride.fn_service_catalogue_register(TEXT, TEXT, trustride.service_macro_domain_enum, TEXT, JSONB, UUID) TO trs026_eng003_serv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_service_catalogue_activate(UUID, UUID, UUID) TO trs026_eng003_serv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_service_eligibility_rule_add(UUID, TEXT, TEXT, JSONB) TO trs026_eng003_serv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_service_coverage_zone_add(UUID, TEXT) TO trs026_eng003_serv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_service_resolve(TEXT, TEXT) TO trs026_eng003_serv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_service_marketplace_listing_create(UUID, trustride.service_listing_type_enum, TEXT, TEXT, NUMERIC, UUID, UUID) TO trs026_eng003_serv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_service_marketplace_listing_publish(UUID) TO trs026_eng003_serv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_service_marketplace_listing_sell(UUID, UUID) TO trs026_eng003_serv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_service_lookup_requested_accept(UUID) TO trs026_eng003_serv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_service_vendor_verification_updated_accept(UUID) TO trs026_eng003_serv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_service_resource_marketplace_item_ready_accept(UUID) TO trs026_eng003_serv_service;

GRANT EXECUTE ON FUNCTION trustride.fn_audit_log_append(TEXT, UUID, TEXT, UUID, TEXT, TEXT, TEXT, JSONB, JSONB) TO trs026_eng003_serv_service;
GRANT EXECUTE ON FUNCTION trustride.fn_sequence_next(TEXT) TO trs026_eng003_serv_service;

GRANT trs026_eng003_serv_service TO service_role;

-- ============================================================================
-- PHASE 12 -- VALIDATION
-- ============================================================================
DO $$
DECLARE
  v_table_count    INTEGER;
  v_function_count INTEGER;
  v_catalogue_count INTEGER;
BEGIN
  SELECT count(*) INTO v_table_count
  FROM information_schema.tables
  WHERE table_schema = 'trustride' AND table_type = 'BASE TABLE' AND table_name LIKE 'service_%';
  IF v_table_count <> 10 THEN
    RAISE EXCEPTION 'Engine 3 validation failed: expected 10 service_ tables, found %', v_table_count;
  END IF;

  SELECT count(*) INTO v_function_count
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'trustride' AND p.proname LIKE 'fn_service%';
  IF v_function_count <> 11 THEN
    RAISE EXCEPTION 'Engine 3 validation failed: expected 11 fn_service%% functions, found %', v_function_count;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'trs026_eng003_serv_service') THEN
    RAISE EXCEPTION 'Engine 3 validation failed: trs026_eng003_serv_service role missing';
  END IF;

  RAISE NOTICE 'Engine 3 validation passed: 10/10 service_ tables, 11/11 fn_service%% functions, service role present.';
END
$$;

-- ============================================================================
-- PHASE 13 -- FINALIZATION & SEED DATA
-- ============================================================================

-- --- 2.1 Five macro domains ---
INSERT INTO trustride.service_macro_domain (domain_code, domain_label, domain_purpose) VALUES
  ('TRANSPORT', 'Transport', 'Safe, tracked, professionally delivered movement of people (Article 24).'),
  ('COURIER', 'Courier', 'Fast, accountable movement of documents and parcels with chain of custody (Article 25).'),
  ('DELIVERY', 'Delivery', 'Reliable movement of goods from origin to recipient, including merchant-originated orders (Article 26).'),
  ('EXECUTIVE_ASSISTANTS', 'Executive Assistants', 'Human assistance services across six pillars: Errands, Driving, Caregiving, Cleaning, Chef, Shopping (Article 27).'),
  ('MARKETPLACE', 'Marketplace', 'Vendor-facilitated and TrustRide Own Marketplace trade (Article 28).');

-- --- 2.2 The complete catalogue (Correction 3 -- Founder-directed, "end to end") ---
DO $$
DECLARE
  v_id UUID;
  v_transport UUID; v_courier UUID; v_delivery UUID; v_ea UUID; v_marketplace UUID;
BEGIN
  SELECT macro_domain_id INTO v_transport FROM trustride.service_macro_domain WHERE domain_code = 'TRANSPORT';
  SELECT macro_domain_id INTO v_courier FROM trustride.service_macro_domain WHERE domain_code = 'COURIER';
  SELECT macro_domain_id INTO v_delivery FROM trustride.service_macro_domain WHERE domain_code = 'DELIVERY';
  SELECT macro_domain_id INTO v_ea FROM trustride.service_macro_domain WHERE domain_code = 'EXECUTIVE_ASSISTANTS';
  SELECT macro_domain_id INTO v_marketplace FROM trustride.service_macro_domain WHERE domain_code = 'MARKETPLACE';

  -- TRANSPORT (3)
  INSERT INTO trustride.service_catalogue (service_code, service_name, macro_domain_id, description, status) VALUES
    ('TRANSPORT-BODA-STANDARD', 'Standard Ride (Boda Boda)', v_transport, 'Motorcycle transport for a single passenger, point to point.', 'ACTIVE'),
    ('TRANSPORT-TUKTUK-STANDARD', 'Tuk-Tuk Ride', v_transport, 'Three-wheeler passenger transport for short in-town trips.', 'ACTIVE'),
    ('TRANSPORT-SEDAN-STANDARD', 'Car Ride (Sedan)', v_transport, 'Private-hire car transport for passengers who prefer or require a car.', 'ACTIVE');

  -- COURIER (2)
  INSERT INTO trustride.service_catalogue (service_code, service_name, macro_domain_id, description, status) VALUES
    ('COURIER-DOCUMENT', 'Document Courier', v_courier, 'Fast, chain-of-custody delivery of documents and small envelopes.', 'ACTIVE'),
    ('COURIER-PARCEL', 'Parcel Courier', v_courier, 'Accountable delivery of small to medium parcels.', 'ACTIVE');

  -- DELIVERY (2)
  INSERT INTO trustride.service_catalogue (service_code, service_name, macro_domain_id, description, status) VALUES
    ('DELIVERY-GOODS-TOWN', 'Goods Delivery (Town)', v_delivery, 'In-town movement of goods too large for courier, using pickup-class capacity.', 'ACTIVE'),
    ('DELIVERY-CARGO-BULK', 'Bulk Cargo Delivery', v_delivery, 'Van or light-truck capacity for larger or longer-haul goods movement.', 'ACTIVE');

  -- EXECUTIVE_ASSISTANTS (11: 6 pillar-general + 3 named line + 2 special-intent-only)
  INSERT INTO trustride.service_catalogue (service_code, service_name, macro_domain_id, description, status) VALUES
    ('EA-ERRANDS-GENERAL', 'Errands', v_ea, 'Office, banking, government, and personal errands executed on behalf of the requester.', 'ACTIVE'),
    ('EA-ERRANDS-SCHOOL_VISITATION', 'School Visitation', v_ea, 'Delegated school visits: delivery of fees, materials, and documents; representation at school appointments; check-ins on students.', 'ACTIVE'),
    ('EA-DRIVING-GENERAL', 'Personal Driving', v_ea, 'Personal and executive driving support, including chauffeur-style assignments.', 'ACTIVE'),
    ('EA-DRIVING-STUDENT_PICKUP', 'Student Pickup', v_ea, 'School runs: picking up students after closing and returning them to school, under guardian authorization.', 'ACTIVE'),
    ('EA-CAREGIVING-GENERAL', 'Caregiving', v_ea, 'Vetted care support for children, the elderly, and vulnerable persons.', 'ACTIVE'),
    ('EA-CLEANING-GENERAL', 'Cleaning', v_ea, 'Professional residential and commercial cleaning support.', 'ACTIVE'),
    ('EA-CHEF-GENERAL', 'Chef', v_ea, 'Meal preparation and culinary support services.', 'ACTIVE'),
    ('EA-SHOPPING-GENERAL', 'Shopping', v_ea, 'Personal shopping and procurement assistance.', 'ACTIVE'),
    ('EA-SHOPPING-REPRESENTATION_DELIVERY', 'Shopping Representation & Shopping Deliveries', v_ea, 'Shopping executed on behalf of the requester and delivery of the purchased goods to the requester''s destination.', 'ACTIVE'),
    ('EA-ACADEMY-TRAINING', 'Academy Training Enrollment', v_ea, 'Enrollment in TrustRide Academy training programmes (Article 18 special intent -- domain placement is a judgment call, see header Correction 4).', 'ACTIVE'),
    ('EA-EMPLOYMENT-APPLICATION', 'Employment Application', v_ea, 'Application to join TrustRide as an Operator or workforce member (Article 18 special intent -- domain placement is a judgment call, see header Correction 4).', 'ACTIVE');

  -- MARKETPLACE (6)
  INSERT INTO trustride.service_catalogue (service_code, service_name, macro_domain_id, description, status) VALUES
    ('MARKETPLACE-ITEM-SALE', 'Marketplace Item Sale', v_marketplace, 'The sale of a marketplace item, vendor-facilitated or TrustRide Own Marketplace -- listing_type on the listing itself makes that distinction.', 'ACTIVE'),
    ('MARKETPLACE-VENDOR-ONBOARDING', 'Vendor Onboarding', v_marketplace, 'A Partner applying to become a verified marketplace vendor.', 'ACTIVE'),
    ('MARKETPLACE-ITEM-ACQUISITION', 'Marketplace Item Acquisition', v_marketplace, 'TrustRide acquiring an item for the Own Marketplace (Article 40, stage ACQUIRED).', 'ACTIVE'),
    ('MARKETPLACE-ITEM-REFURBISHMENT', 'Marketplace Item Refurbishment', v_marketplace, 'Refurbishment of an Own Marketplace item prior to listing (Article 40, stage REFURBISHED).', 'ACTIVE'),
    ('MARKETPLACE-ITEM-LISTING', 'Marketplace Item Listing', v_marketplace, 'The act of listing a compliant item for sale (Article 40, stage LISTED).', 'ACTIVE'),
    ('MARKETPLACE-RESOURCE-CONTRIBUTION', 'Resource Contribution', v_marketplace, 'A Partner contributing fleet, equipment, or other capacity to the platform (Article 37 partner-contributed resources).', 'ACTIVE');
END
$$;

-- --- Eligibility rules -- only for services that actually dispatch a resource ---
INSERT INTO trustride.service_eligibility_rule (service_id, required_capacity_class_code, required_vetting_tier)
SELECT service_id, 'BODA_BODA', 'STANDARD' FROM trustride.service_catalogue WHERE service_code = 'TRANSPORT-BODA-STANDARD'
UNION ALL SELECT service_id, 'TUKTUK', 'STANDARD' FROM trustride.service_catalogue WHERE service_code = 'TRANSPORT-TUKTUK-STANDARD'
UNION ALL SELECT service_id, 'SEDAN', 'STANDARD' FROM trustride.service_catalogue WHERE service_code = 'TRANSPORT-SEDAN-STANDARD'
UNION ALL SELECT service_id, 'BODA_BODA', 'STANDARD' FROM trustride.service_catalogue WHERE service_code = 'COURIER-DOCUMENT'
UNION ALL SELECT service_id, 'BODA_BODA', 'STANDARD' FROM trustride.service_catalogue WHERE service_code = 'COURIER-PARCEL'
UNION ALL SELECT service_id, 'PICKUP_TOWN', 'STANDARD' FROM trustride.service_catalogue WHERE service_code = 'DELIVERY-GOODS-TOWN'
UNION ALL SELECT service_id, 'VAN_CARGO', 'STANDARD' FROM trustride.service_catalogue WHERE service_code = 'DELIVERY-CARGO-BULK'
UNION ALL SELECT service_id, 'EXECUTIVE_ASSISTANT_HUMAN', 'STANDARD' FROM trustride.service_catalogue WHERE service_code = 'EA-ERRANDS-GENERAL'
UNION ALL SELECT service_id, 'EXECUTIVE_ASSISTANT_HUMAN', 'ENHANCED' FROM trustride.service_catalogue WHERE service_code = 'EA-ERRANDS-SCHOOL_VISITATION'
UNION ALL SELECT service_id, 'EXECUTIVE_ASSISTANT_HUMAN', 'STANDARD' FROM trustride.service_catalogue WHERE service_code = 'EA-DRIVING-GENERAL'
UNION ALL SELECT service_id, 'EXECUTIVE_ASSISTANT_HUMAN', 'ENHANCED' FROM trustride.service_catalogue WHERE service_code = 'EA-DRIVING-STUDENT_PICKUP'
UNION ALL SELECT service_id, 'EXECUTIVE_ASSISTANT_HUMAN', 'ENHANCED' FROM trustride.service_catalogue WHERE service_code = 'EA-CAREGIVING-GENERAL'
UNION ALL SELECT service_id, 'EXECUTIVE_ASSISTANT_HUMAN', 'STANDARD' FROM trustride.service_catalogue WHERE service_code = 'EA-CLEANING-GENERAL'
UNION ALL SELECT service_id, 'EXECUTIVE_ASSISTANT_HUMAN', 'STANDARD' FROM trustride.service_catalogue WHERE service_code = 'EA-CHEF-GENERAL'
UNION ALL SELECT service_id, 'EXECUTIVE_ASSISTANT_HUMAN', 'STANDARD' FROM trustride.service_catalogue WHERE service_code = 'EA-SHOPPING-GENERAL'
UNION ALL SELECT service_id, 'EXECUTIVE_ASSISTANT_HUMAN', 'STANDARD' FROM trustride.service_catalogue WHERE service_code = 'EA-SHOPPING-REPRESENTATION_DELIVERY';

-- --- Coverage: Kisumu County first, matching this platform's own build sequencing ---
INSERT INTO trustride.service_coverage_zone (service_id, jurisdiction)
SELECT service_id, 'KISUMU_COUNTY' FROM trustride.service_catalogue WHERE status = 'ACTIVE';

-- --- Executive Assistants pillars, linked to their general catalogue entry (Correction 2) ---
INSERT INTO trustride.service_pillar (pillar_code, macro_domain_id, service_id, pillar_label, description)
SELECT v.pillar_code::trustride.service_pillar_code_enum, d.macro_domain_id, sc.service_id, v.pillar_label, v.description
FROM (VALUES
  ('ERRANDS', 'Errands', 'Office, banking, government, and personal errands executed on behalf of the requester.', 'EA-ERRANDS-GENERAL'),
  ('DRIVING', 'Driving', 'Personal and executive driving support, including chauffeur-style assignments.', 'EA-DRIVING-GENERAL'),
  ('CAREGIVING', 'Caregiving', 'Vetted care support for children, the elderly, and vulnerable persons.', 'EA-CAREGIVING-GENERAL'),
  ('CLEANING', 'Cleaning', 'Professional residential and commercial cleaning support.', 'EA-CLEANING-GENERAL'),
  ('CHEF', 'Chef', 'Meal preparation and culinary support services.', 'EA-CHEF-GENERAL'),
  ('SHOPPING', 'Shopping', 'Personal shopping and procurement assistance.', 'EA-SHOPPING-GENERAL')
) AS v(pillar_code, pillar_label, description, service_code)
JOIN trustride.service_macro_domain d ON d.domain_code = 'EXECUTIVE_ASSISTANTS'
JOIN trustride.service_catalogue sc ON sc.service_code = v.service_code;

-- --- Named service lines, linked to their specific catalogue entry (Correction 2) ---
INSERT INTO trustride.service_line (pillar_id, service_id, line_code, line_name, description, safeguarding_tier, guardian_authorization_required)
SELECT p.pillar_id, sc.service_id, v.line_code, v.line_name, v.description, v.tier::trustride.service_safeguarding_tier_enum, v.guardian_req
FROM (VALUES
  ('ERRANDS', 'SCHOOL_VISITATION', 'School Visitation', 'Delegated school visits: delivery of fees, materials, and documents; representation at school appointments; check-ins on students.', 'ENHANCED', TRUE, 'EA-ERRANDS-SCHOOL_VISITATION'),
  ('DRIVING', 'STUDENT_PICKUP', 'Student Pickup', 'School runs: picking up students by motorcycle or car after closing and returning them to school, under guardian authorization.', 'ENHANCED', TRUE, 'EA-DRIVING-STUDENT_PICKUP'),
  ('SHOPPING', 'SHOPPING_REPRESENTATION_DELIVERY', 'Shopping Representation & Shopping Deliveries', 'Shopping executed on behalf of the requester and delivery of the purchased goods to the requester''s destination.', 'STANDARD', FALSE, 'EA-SHOPPING-REPRESENTATION_DELIVERY')
) AS v(pillar_code, line_code, line_name, description, tier, guardian_req, service_code)
JOIN trustride.service_pillar p ON p.pillar_code = v.pillar_code::trustride.service_pillar_code_enum
JOIN trustride.service_catalogue sc ON sc.service_code = v.service_code;

-- --- Special intents, each resolving to its catalogue Service (Article 18) ---
INSERT INTO trustride.service_special_intent (intent_code, intent_label, resolves_to_service_id, description)
SELECT v.intent_code::trustride.service_special_intent_code_enum, v.intent_label, sc.service_id, v.description
FROM (VALUES
  ('ACADEMY_TRAINING', 'Academy Training', 'Enrollment in TrustRide Academy training programmes.', 'EA-ACADEMY-TRAINING'),
  ('EMPLOYMENT_APPLICATION', 'Employment Application', 'Application to join TrustRide as an Operator or workforce member.', 'EA-EMPLOYMENT-APPLICATION'),
  ('VENDOR_ONBOARDING', 'Vendor Onboarding', 'A Partner applying to become a verified marketplace vendor.', 'MARKETPLACE-VENDOR-ONBOARDING'),
  ('RESOURCE_CONTRIBUTION', 'Resource Contribution', 'A Partner contributing fleet, equipment, or other capacity to the platform.', 'MARKETPLACE-RESOURCE-CONTRIBUTION'),
  ('MARKETPLACE_ACQUISITION', 'Marketplace Item Acquisition', 'TrustRide acquiring an item for the Own Marketplace.', 'MARKETPLACE-ITEM-ACQUISITION'),
  ('MARKETPLACE_REFURBISHMENT', 'Marketplace Item Refurbishment', 'Refurbishment of an Own Marketplace item prior to listing.', 'MARKETPLACE-ITEM-REFURBISHMENT'),
  ('MARKETPLACE_LISTING', 'Marketplace Item Listing', 'The act of listing a compliant item for sale.', 'MARKETPLACE-ITEM-LISTING'),
  ('MARKETPLACE_SALE', 'Marketplace Item Sale', 'The sale of a marketplace item to a buyer.', 'MARKETPLACE-ITEM-SALE')
) AS v(intent_code, intent_label, description, service_code)
JOIN trustride.service_catalogue sc ON sc.service_code = v.service_code;

UPDATE trustride.engine_registry SET status = 'INSTALLED', engine_version = '1.0.1' WHERE engine_code = 'TRS026_ENG003_SERV';
