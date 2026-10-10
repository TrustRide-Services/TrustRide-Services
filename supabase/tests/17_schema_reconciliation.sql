-- Suite 17 -- the database holds what the migrations say, and no more
-- (TRS026-ENG-REMEDIATION-001: D19). Grants found only on staging are gone,
-- and the append-only audit chains carry no write grant beyond their owner.
DO $$
DECLARE
  n INT; v TEXT;
BEGIN
  SELECT count(*) INTO n FROM information_schema.role_table_grants
  WHERE table_schema = 'trustride' AND table_name IN ('resource_ledger_event', 'v_resource_eagle_eye') AND grantee = 'trs026_eng004_bus_service';
  PERFORM pg_temp.t_check('D19 Engine 4 holds no grant on the resource ledger or its view (none granted by any migration)', n = 0, n::text);

  SELECT count(*), string_agg(DISTINCT c.relname || ':' || pg_get_userbyid(x.grantee) || ':' || x.privilege_type, ' ') INTO n, v
  FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) x
  WHERE c.relnamespace = 'trustride'::regnamespace AND c.relkind = 'r' AND x.grantee <> c.relowner
    AND x.privilege_type IN ('UPDATE', 'DELETE', 'TRUNCATE')
    AND c.relname IN ('audit_log', 'resource_ledger_event', 'present_decision_log', 'advisory_decision_log', 'model_decision_log',
                      'orch_execution_audit', 'orch_routing_audit', 'platform_audit_chain_seal', 'platform_audit_chain');
  PERFORM pg_temp.t_check('D19 no role but the owner holds UPDATE, DELETE or TRUNCATE on an audit chain', n = 0, left(coalesce(v, ''), 300));
END
$$;
