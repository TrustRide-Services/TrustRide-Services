-- Suite 14 -- views never widen what a caller may read (TRS026-ENG-REMEDIATION-001: D02).
-- A view runs with the reading caller's rights (security_invoker) or is not
-- readable by signed-in users at all; no view accepts writes; a customer
-- cannot read another customer's order through any view.
DO $$
DECLARE
  founder UUID; a UUID; b UUID; est UUID; boda UUID; ord UUID; r JSONB; n INT; t RECORD; ok BOOLEAN; v TEXT;
BEGIN
  PERFORM pg_temp.t_open_all_hours();
  founder := pg_temp.t_person('ViewSec Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  a := pg_temp.t_customer('ViewSec Cust A');
  b := pg_temp.t_customer('ViewSec Cust B');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"VSEC-01","estate_name":"ViewSec Hub","estate_type":"OPERATING_HUB","lat":-0.09,"lon":34.76}');
  est := (r->>'signal')::uuid;
  boda := pg_temp.t_ready_unit(founder, 'BODA_BODA', est, 'ViewSec Rider');
  ord := pg_temp.t_order_to_completed(b);

  -- ============ D02 exploit replay: A reads B's order through the order-status view
  PERFORM pg_temp.t_as(a);
  BEGIN SELECT count(*) INTO n FROM trustride.v_business_order_status WHERE requester_user_id = b; v := n::text;
  EXCEPTION WHEN insufficient_privilege THEN n := 0; v := 'permission denied'; END;
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('D02 customer A reads none of B''s orders through v_business_order_status', n = 0, v);

  -- ============ D02 every view: no signed-in read that bypasses row-level security, no writes
  FOR t IN SELECT c.oid, c.relname, coalesce(c.reloptions, '{}') @> ARRAY['security_invoker=true'] AS invoker
           FROM pg_class c WHERE c.relnamespace = 'trustride'::regnamespace AND c.relkind = 'v' ORDER BY c.relname LOOP
    ok := t.invoker OR NOT (has_table_privilege('authenticated', t.oid, 'SELECT') OR has_table_privilege('anon', t.oid, 'SELECT'));
    PERFORM pg_temp.t_check('D02 ' || t.relname || ' cannot be read past row-level security', ok,
      'invoker=' || t.invoker || ' authenticated_select=' || has_table_privilege('authenticated', t.oid, 'SELECT'));
  END LOOP;
  SELECT count(*) INTO n FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) x
  WHERE c.relnamespace = 'trustride'::regnamespace AND c.relkind = 'v' AND x.grantee <> c.relowner
    AND x.privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
  PERFORM pg_temp.t_check('D02 no role but the owner holds INSERT, UPDATE, DELETE or TRUNCATE on any view', n = 0, n::text);

  -- ============ positive control: B still sees its own order through the gateway projection
  r := pg_temp.t_cmd(b, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'OPEN_SUPPORT_CASE', '{"category":"ORDER_ISSUE","subject":"Own order","body":"control"}');
  PERFORM pg_temp.t_check('D02 positive control: B still acts on its own account', r->>'status' = 'TRANSLATED', r::text);

  -- ============ systemic guard
  SELECT count(*) INTO n FROM trustride.fn_platform_conformance_violations() WHERE check_code IN ('VIEW_BYPASSES_ROW_SECURITY', 'VIEW_GRANTS_WRITE');
  PERFORM pg_temp.t_check('systemic: the conformance assertion covers view reads and view writes',
    pg_get_functiondef('trustride.fn_platform_conformance_violations()'::regprocedure) LIKE '%VIEW_BYPASSES_ROW_SECURITY%'
    AND pg_get_functiondef('trustride.fn_platform_conformance_violations()'::regprocedure) LIKE '%VIEW_GRANTS_WRITE%' AND n = 0, n::text);
  -- The guard bites: a re-granted read on a definer view is a violation.
  GRANT SELECT ON trustride.v_cost_registry_active TO trustride_authenticated;
  SELECT count(*) INTO n FROM trustride.fn_platform_conformance_violations() WHERE check_code = 'VIEW_BYPASSES_ROW_SECURITY';
  REVOKE SELECT ON trustride.v_cost_registry_active FROM trustride_authenticated;
  PERFORM pg_temp.t_check('systemic: re-granting signed-in read on a definer view is caught', n = 1, n::text);
  -- Engine 5 view definition and options are as established.
  PERFORM pg_temp.t_check('Engine 5 v_cost_registry_active keeps its established options (no security_invoker)',
    (SELECT reloptions IS NULL FROM pg_class WHERE oid = 'trustride.v_cost_registry_active'::regclass));
END
$$;
