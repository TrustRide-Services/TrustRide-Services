-- Suite 10 -- commit-time integrity: deferred constraint triggers fire at
-- COMMIT, after every SECURITY DEFINER function has returned, as the
-- caller's own role. The other suites roll back and never reach COMMIT, so
-- this suite forces the deferred checks to fire (SET CONSTRAINTS ALL
-- IMMEDIATE) while still signed in as each non-Office actor -- exactly what
-- a real Data API request does when it commits.
DO $$
DECLARE
  founder UUID; cust UUID; gov UUID; vendor UUID; est UUID; unit UUID; op UUID;
  r JSONB; err TEXT;
BEGIN
  PERFORM pg_temp.t_open_all_hours();
  founder := pg_temp.t_person('Commit Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  cust := pg_temp.t_customer('Commit Customer');
  gov := pg_temp.t_person('Commit Governor', 'GOVERNOR', 'PENDING');
  vendor := pg_temp.t_person('Commit Vendor', NULL);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"CMT-01","estate_name":"Commit Hub","estate_type":"OPERATING_HUB","lat":-0.09,"lon":34.76}');
  est := (r->>'signal')::uuid;
  unit := pg_temp.t_ready_unit(founder, 'BODA_BODA', est, 'Commit Rider');
  SELECT operator_user_id INTO op FROM trustride.resource_workforce_unit WHERE workforce_unit_id = unit;

  -- Customer places an order, then commits as themself.
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RAISE_INTENT', jsonb_build_object('service_code', 'TRANSPORT-BODA-STANDARD',
    'order_lines', '[{"scope_detail":{"origin_zone_code":"KSM-CBD-01","destination_zone_code":"KSM-MILIMANI-02"}}]'::jsonb));
  PERFORM pg_temp.t_check('customer command translated', r->>'status' = 'TRANSLATED', r::text);
  PERFORM pg_temp.t_as(cust);
  BEGIN EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE'; err := NULL; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('customer order commits (deferred checks pass as the customer)', err IS NULL, err);

  -- Governor submits a regulatory request, then commits as themself.
  r := pg_temp.t_cmd(gov, 'TRUSTRIDE_BUSINESS', 'GOVERNOR_APP', 'SUBMIT_REGULATORY_REQUEST',
    '{"scope_lines":[{"line_description":"County levy oversight","scope_detail":{"authority":"Commit County"}}]}');
  PERFORM pg_temp.t_check('governor request translated', r->>'status' = 'TRANSLATED', r::text);
  PERFORM pg_temp.t_as(gov);
  BEGIN EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE'; err := NULL; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('governor request commits', err IS NULL, err);

  -- Vendor applies, then commits as themself.
  r := pg_temp.t_cmd(vendor, 'TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'SUBMIT_VENDOR_LISTING',
    '{"scope_lines":[{"line_description":"Commit Motors","scope_detail":{"vehicle_category":"MOTORCYCLE"}}]}');
  PERFORM pg_temp.t_check('vendor application translated', r->>'status' = 'TRANSLATED', r::text);
  PERFORM pg_temp.t_as(vendor);
  BEGIN EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE'; err := NULL; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('vendor application commits', err IS NULL, err);

  -- Operator changes duty, then commits as themself.
  r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'SET_DUTY', '{"on_duty":false}');
  PERFORM pg_temp.t_check('operator command translated', r->>'status' = 'TRANSLATED', r::text);
  PERFORM pg_temp.t_as(op);
  BEGIN EXECUTE 'SET CONSTRAINTS ALL IMMEDIATE'; err := NULL; EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  EXECUTE 'SET CONSTRAINTS ALL DEFERRED';
  PERFORM pg_temp.t_admin();
  PERFORM pg_temp.t_check('operator command commits', err IS NULL, err);

  -- Every deferred integrity trigger runs with its owner's rights.
  PERFORM pg_temp.t_check('no deferred trigger runs with the caller''s rights', NOT EXISTS (
    SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE NOT t.tgisinternal AND t.tgdeferrable AND t.tgrelid::regclass::text LIKE 'trustride.%' AND NOT p.prosecdef));
  -- The check itself still refuses an unregistered verb at commit.
  PERFORM pg_temp.t_check('an unregistered verb is still refused', pg_temp.t_fails(format(
    'INSERT INTO trustride.present_command_capture (shell_session_id, top_shell, sub_shell, command_type, command_payload) '
    'SELECT session_id, top_shell, sub_shell, ''NOT_A_VERB'', ''{}'' FROM trustride.present_shell_session WHERE user_id = %L LIMIT 1; SET CONSTRAINTS ALL IMMEDIATE', cust)));
END;
$$;
