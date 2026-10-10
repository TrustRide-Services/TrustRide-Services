-- Suite 18 -- no duplicate index outside Engine 5, and every foreign key on a
-- table in operational use has a supporting index (TRS026-ENG-REMEDIATION-001: D21).
DO $$
DECLARE
  n INT; v TEXT;
BEGIN
  SELECT count(*), string_agg(a.indexrelid::regclass::text || '=' || b.indexrelid::regclass::text, ' ') INTO n, v
  FROM pg_index a JOIN pg_index b ON a.indrelid = b.indrelid AND a.indkey::text = b.indkey::text AND a.indclass::text = b.indclass::text
    AND coalesce(pg_get_expr(a.indpred, a.indrelid), '') = coalesce(pg_get_expr(b.indpred, b.indrelid), '') AND a.indexrelid < b.indexrelid
  JOIN pg_class c ON c.oid = a.indrelid
  WHERE c.relnamespace = 'trustride'::regnamespace AND c.relname NOT LIKE 'cost\_%' AND c.relname NOT LIKE 'fare\_%';
  PERFORM pg_temp.t_check('D21 no duplicate index outside Engine 5', n = 0, coalesce(v, ''));

  SELECT count(*), string_agg(x.t || '(' || x.col || ')', ' ') INTO n, v FROM (VALUES
    ('business_job', 'order_line_id'), ('business_support_case', 'job_id'), ('business_support_case', 'order_id'),
    ('business_support_message', 'case_id'), ('coord_admission_decision', 'admission_session_id'), ('coord_admission_session', 'admission_policy_id'),
    ('entity_system_credential', 'issued_by'), ('entity_system_credential', 'system_user_id'), ('object_registry', 'custody_entity_id'),
    ('object_registry', 'custody_user_id'), ('orch_routing_audit', 'routing_decision_id'), ('present_shell_session', 'access_id'),
    ('present_shell_session', 'acting_person_user_id'), ('resource_custody_log', 'location_estate_id'), ('resource_location_event', 'binding_id'),
    ('resource_workforce_unit', 'primary_estate_id'), ('service_marketplace_listing', 'service_id'), ('verification_record', 'subject_object_id'),
    ('advisory_forecast', 'model_id')) x(t, col)
  WHERE NOT EXISTS (SELECT 1 FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = i.indkey[0]
                    WHERE i.indrelid = ('trustride.' || x.t)::regclass AND a.attname = x.col);
  PERFORM pg_temp.t_check('D21 the 19 operational foreign keys have a supporting index', n = 0, coalesce(v, ''));
END
$$;
