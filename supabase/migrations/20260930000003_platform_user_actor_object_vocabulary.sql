-- ============================================================================
-- PLATFORM -- USER, ACTOR, OBJECT: THERE IS NO "THING"
-- [Trace: Founder direction 2026-10-01; TRS026-ENG011-PRESENT-003 Sec.2
--  "System elements are Users (persons), Actors (...) and Objects (assets,
--  equipment)"]
--
-- The three system characteristics of TrustRide Services are User, Actor
-- and Object. A person is a User; firms, organisations, external systems and
-- applications are Actors; assets, vehicles, equipment, devices and laptops
-- are Objects. The schema still carried an older word, "thing", for the
-- Object register. Realigned everywhere it lived on the live database:
--
--   thing_registry                    -> object_registry
--   thing_registration                -> object_registration
--   *.thing_id                        -> *.object_id
--   thing_registry.thing_type         -> object_registry.object_type
--   thing_registration_id             -> object_registration_id
--   tracking_session.resource_thing_id-> resource_object_id
--   verification_record.subject_thing_id -> subject_object_id
--   platform_users.identity_primitive PERSON / ENTITY / THING -> PERSON / ENTITY / OBJECT
--   + every constraint, index and policy named after them, and the three
--     Resource functions whose bodies and parameters used the old names.
--
-- Deliberately NOT rewritten: four historical ledger and signal records
-- (resource_ledger_event before/after state, one resource outbox and one
-- business inbox payload) that carry the old key as written at the time.
-- Ledgers are immutable evidence; they record what was true when written.
-- Every write from this migration on uses the new vocabulary.
--
-- Earlier migration files in this repository keep the old word because
-- they are applied history; this migration is the correction of record.
-- ============================================================================

-- ============================================================================
-- PHASE 1 -- TABLES AND COLUMNS
-- ============================================================================
ALTER TABLE trustride.thing_registry RENAME TO object_registry;
ALTER TABLE trustride.object_registry RENAME COLUMN thing_id TO object_id;
ALTER TABLE trustride.object_registry RENAME COLUMN thing_type TO object_type;

ALTER TABLE trustride.thing_registration RENAME TO object_registration;
ALTER TABLE trustride.object_registration RENAME COLUMN thing_registration_id TO object_registration_id;
ALTER TABLE trustride.object_registration RENAME COLUMN thing_id TO object_id;

ALTER TABLE trustride.resource_fleet_register RENAME COLUMN thing_id TO object_id;
ALTER TABLE trustride.resource_equipment_register RENAME COLUMN thing_id TO object_id;
ALTER TABLE trustride.tracking_session RENAME COLUMN resource_thing_id TO resource_object_id;
ALTER TABLE trustride.verification_record RENAME COLUMN subject_thing_id TO subject_object_id;

-- ============================================================================
-- PHASE 2 -- CONSTRAINTS, INDEXES, POLICIES NAMED AFTER THE OLD WORD
-- (renamed generically so nothing is missed; every name is rebuilt with
--  "thing" -> "object" at word boundaries only)
-- ============================================================================
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT conrelid::regclass AS tbl, conname FROM pg_constraint
           WHERE connamespace = 'trustride'::regnamespace AND conname ~ '(^|_)thing(_|$)' LOOP
    EXECUTE format('ALTER TABLE %s RENAME CONSTRAINT %I TO %I', r.tbl, r.conname,
      regexp_replace(r.conname, '(^|_)thing(_|$)', '\1object\2', 'g'));
  END LOOP;

  FOR r IN SELECT c.relname FROM pg_class c
           WHERE c.relnamespace = 'trustride'::regnamespace AND c.relkind = 'i' AND c.relname ~ '(^|_)thing(_|$)' LOOP
    EXECUTE format('ALTER INDEX trustride.%I RENAME TO %I', r.relname,
      regexp_replace(r.relname, '(^|_)thing(_|$)', '\1object\2', 'g'));
  END LOOP;

  FOR r IN SELECT tablename, policyname FROM pg_policies
           WHERE schemaname = 'trustride' AND policyname ~ '(^|_)thing(_|$)' LOOP
    EXECUTE format('ALTER POLICY %I ON trustride.%I RENAME TO %I', r.policyname, r.tablename,
      regexp_replace(r.policyname, '(^|_)thing(_|$)', '\1object\2', 'g'));
  END LOOP;
END;
$$;

-- ============================================================================
-- PHASE 3 -- IDENTITY PRIMITIVES: PERSON / ENTITY / OBJECT
-- ============================================================================
ALTER TABLE trustride.platform_users DROP CONSTRAINT platform_users_identity_primitive_check;
UPDATE trustride.platform_users SET identity_primitive = 'OBJECT' WHERE identity_primitive = 'THING';
ALTER TABLE trustride.platform_users ADD CONSTRAINT platform_users_identity_primitive_check
  CHECK (identity_primitive IN ('PERSON', 'ENTITY', 'OBJECT'));

-- ============================================================================
-- PHASE 4 -- FUNCTIONS WHOSE BODIES OR PARAMETERS USED THE OLD NAMES
-- A table rename does not reach inside a function body (bodies are stored as
-- text), so these would fail at run time without this rewrite. Each is
-- rebuilt from its live definition with the old identifiers replaced at
-- word boundaries. A renamed parameter needs DROP + CREATE; existing
-- EXECUTE grants are captured first and re-issued exactly.
-- ============================================================================
DO $$
DECLARE
  r RECORD;
  v_def TEXT;
  v_comment TEXT;
  v_grantees TEXT[];
  v_grantee TEXT;
  v_new_oid OID;
BEGIN
  FOR r IN SELECT p.oid, p.proname, p.proowner, p.proacl, p.oid::regprocedure::text AS sig FROM pg_proc p
           WHERE p.pronamespace = 'trustride'::regnamespace
             AND (p.prosrc ~* '(^|[^a-z])thing' OR pg_get_function_identity_arguments(p.oid) ~* '(^|[^a-z])thing') LOOP
    v_def := pg_get_functiondef(r.oid);
    v_def := regexp_replace(v_def, '(^|[^A-Za-z])thing', '\1object', 'g');
    v_def := regexp_replace(v_def, '(^|[^A-Za-z])Thing', '\1Object', 'g');
    v_def := regexp_replace(v_def, '(^|[^A-Za-z])THING', '\1OBJECT', 'g');

    v_comment := obj_description(r.oid, 'pg_proc');
    v_grantees := ARRAY(SELECT DISTINCT a.grantee::regrole::text FROM aclexplode(r.proacl) a
                        WHERE a.privilege_type = 'EXECUTE' AND a.grantee <> 0 AND a.grantee <> r.proowner);

    EXECUTE format('DROP FUNCTION %s', r.sig);
    EXECUTE v_def;

    SELECT p.oid INTO v_new_oid FROM pg_proc p
    WHERE p.pronamespace = 'trustride'::regnamespace AND p.proname = r.proname
    ORDER BY p.oid DESC LIMIT 1;

    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', v_new_oid::regprocedure);
    FOREACH v_grantee IN ARRAY v_grantees LOOP
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO %s', v_new_oid::regprocedure, v_grantee);
    END LOOP;
    IF v_comment IS NOT NULL THEN
      EXECUTE format('COMMENT ON FUNCTION %s IS %L', v_new_oid::regprocedure,
        regexp_replace(regexp_replace(v_comment, '(^|[^A-Za-z])thing', '\1object', 'g'), '(^|[^A-Za-z])Thing', '\1Object', 'g'));
    END IF;
  END LOOP;
END;
$$;

-- ============================================================================
-- PHASE 5 -- DESCRIPTIONS
-- ============================================================================
COMMENT ON TABLE trustride.object_registry IS
  '[Trace: TBOC-v2.0.0; Founder vocabulary 2026-10-01] The Object register -- assets, vehicles, equipment, devices, laptops. Objects are one of the three system characteristics (User, Actor, Object); every Object is owned by an authenticated User or Actor.';
COMMENT ON TABLE trustride.object_registration IS
  'Statutory registrations held by an Object (NTSA registration, inspection, insurance).';

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT c.oid, c.relname, d.description FROM pg_description d JOIN pg_class c ON c.oid = d.objoid AND d.classoid = 'pg_class'::regclass
           WHERE c.relnamespace = 'trustride'::regnamespace AND d.objsubid = 0 AND d.description ~* '(^|[^a-z])things?([^a-z]|$)' LOOP
    EXECUTE format('COMMENT ON TABLE trustride.%I IS %L', r.relname,
      regexp_replace(regexp_replace(r.description, '(^|[^A-Za-z])Things', '\1Objects', 'g'), '(^|[^A-Za-z])things', '\1objects', 'g'));
  END LOOP;
END;
$$;

-- ============================================================================
-- PHASE 6 -- VALIDATION: no "thing" identifier survives anywhere live
-- ============================================================================
DO $$
DECLARE v_left TEXT;
BEGIN
  SELECT string_agg(x, ', ') INTO v_left FROM (
    SELECT 'table ' || relname AS x FROM pg_class WHERE relnamespace = 'trustride'::regnamespace AND relname ~* '(^|[^a-z])thing'
    UNION ALL SELECT 'column ' || table_name || '.' || column_name FROM information_schema.columns WHERE table_schema = 'trustride' AND column_name ~* '(^|[^a-z])thing'
    UNION ALL SELECT 'constraint ' || conname FROM pg_constraint WHERE connamespace = 'trustride'::regnamespace AND (conname ~* '(^|[^a-z])thing' OR pg_get_constraintdef(oid) ~* '(^|[^a-z])thing')
    UNION ALL SELECT 'policy ' || policyname FROM pg_policies WHERE schemaname = 'trustride' AND policyname ~* '(^|[^a-z])thing'
    UNION ALL SELECT 'function ' || proname FROM pg_proc WHERE pronamespace = 'trustride'::regnamespace AND (prosrc ~* '(^|[^a-z])thing' OR pg_get_function_identity_arguments(oid) ~* '(^|[^a-z])thing')
  ) s;
  IF v_left IS NOT NULL THEN
    RAISE EXCEPTION 'USER/ACTOR/OBJECT VOCABULARY VALIDATION FAILED -- still present: %', v_left;
  END IF;
  RAISE NOTICE 'USER/ACTOR/OBJECT VOCABULARY VALIDATED: no "thing" identifier remains in the trustride schema.';
END;
$$;
