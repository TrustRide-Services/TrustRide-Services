-- Suite 24 -- the invariants behind the residual audit-probe exceptions, stated correctly
-- (Construction Directive WP1). The probes A3 (I3, I4) and A7 asserted the wrong
-- observable; these checks assert what the system must actually guarantee.
--   I3  the assigned operator moves COMPLETED -> VERIFIED (the designed step; the
--       proof's "Verification + release"), and nothing advances a VERIFIED job;
--       no other operator can advance it at any stage.
--   I4  one approval settles once and the settlement reaches its final state,
--       RECEIPT_GENERATED (INITIATED > AUTHORIZED > SETTLED > LEDGER_POSTED >
--       RECEIPT_GENERATED); a second approval and a retry are refused.
--   A7  a revoked system key is refused at ingestion (UNAUTHENTICATED) and
--       writes no location.
--   Historical queue entries registered as unrecoverable never count as work in
--   flight.
DO $$
DECLARE
  founder UUID; cust UUID; est UUID; boda UUID; boda2 UUID; ord UUID; j UUID; op UUID; op2 UUID; r JSONB; v TEXT; n INT;
  sys UUID; key TEXT; q UUID; snap UUID; inflight_before INT; inflight_after INT;
BEGIN
  PERFORM pg_temp.t_open_all_hours();
  founder := pg_temp.t_person('Resid Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  cust := pg_temp.t_customer('Resid Cust');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"RSD-24","estate_name":"Resid Hub","estate_type":"OPERATING_HUB","lat":-0.09,"lon":34.76}');
  est := (r->>'signal')::uuid;
  boda := pg_temp.t_ready_unit(founder, 'BODA_BODA', est, 'Resid Rider');
  ord := pg_temp.t_order_to_completed(cust);
  boda2 := pg_temp.t_ready_unit(founder, 'BODA_BODA', est, 'Resid Rider Two');
  SELECT job_id INTO j FROM trustride.business_job WHERE order_id = ord;
  -- the operator actually assigned (any on-duty unit may have been matched), and one who is not
  SELECT wu.operator_user_id INTO op FROM trustride.business_job bj JOIN trustride.resource_workforce_unit wu ON wu.workforce_unit_id = bj.workforce_unit_id WHERE bj.job_id = j;
  SELECT operator_user_id INTO op2 FROM trustride.resource_workforce_unit WHERE workforce_unit_id IN (boda, boda2) AND operator_user_id <> op LIMIT 1;

  -- ============ I3
  SELECT status::text INTO v FROM trustride.business_job WHERE job_id = j;
  PERFORM pg_temp.t_check('I3 fixture: the job is COMPLETED', v = 'COMPLETED', v);
  r := pg_temp.t_cmd(op2, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', jsonb_build_object('job_id', j));
  PERFORM pg_temp.t_check('I3 another operator cannot advance the job', r->>'status' <> 'TRANSLATED', left(r::text, 160));
  r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', jsonb_build_object('job_id', j));
  SELECT status::text INTO v FROM trustride.business_job WHERE job_id = j;
  PERFORM pg_temp.t_check('I3 the assigned operator verifies the completed job', r->>'status' = 'TRANSLATED' AND v = 'VERIFIED', v || ' ' || left(r::text, 120));
  r := pg_temp.t_cmd(op, 'TRUSTRIDE_OFFICE', 'OPERATOR_APP', 'EMIT_PROGRESS_SIGNAL', jsonb_build_object('job_id', j));
  SELECT status::text INTO v FROM trustride.business_job WHERE job_id = j;
  PERFORM pg_temp.t_check('I3 nothing advances a VERIFIED job', r->>'status' <> 'TRANSLATED' AND v = 'VERIFIED', v || ' ' || left(r::text, 160));

  -- ============ I4
  PERFORM pg_temp.t_cycle(6);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'CONFIRM_SIMULATED_PAYMENT', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_cycle(8);
  SELECT payment_status::text INTO v FROM trustride.business_settlement WHERE order_id = ord;
  PERFORM pg_temp.t_check('I4 the approval settles and the settlement reaches RECEIPT_GENERATED', v = 'RECEIPT_GENERATED', coalesce(v, 'none') || ' / ' || left(r::text, 100));
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'CONFIRM_SIMULATED_PAYMENT', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_cycle(4);
  SELECT count(*) INTO n FROM trustride.integration_payment_gateway_transaction WHERE order_id = ord AND txn_status = 'SETTLED';
  PERFORM pg_temp.t_check('I4 a second approval is refused and settles nothing more', r->>'status' <> 'TRANSLATED' AND n = 1, n || ' settled / ' || left(r::text, 100));
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'RETRY_PAYMENT', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_check('I4 retrying a settled payment is refused', r->>'status' <> 'TRANSLATED', left(r::text, 160));

  -- ============ A7
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_EXTERNAL_SYSTEM', '{"system_name":"Resid Tracker","purpose":"suite 24"}');
  sys := (r->>'signal')::uuid;
  PERFORM pg_temp.t_as(founder);  key := trustride.fn_external_system_credential_issue(sys, ARRAY['TELEMETRY_INGEST']);  PERFORM pg_temp.t_admin();
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REVOKE_SYSTEM_CREDENTIAL', jsonb_build_object('key_prefix', split_part(key, '.', 1)));
  SELECT count(*) INTO n FROM trustride.resource_location_event;
  v := trustride.fn_integration_telemetry_ingest(key, '[{"imei":"867000000000024","lat":-0.09,"lng":34.76,"gpstime":1}]')::text;
  PERFORM pg_temp.t_check('A7 a revoked key is refused at ingestion (UNAUTHENTICATED)', r->>'status' = 'TRANSLATED' AND v ILIKE '%UNAUTHENTICATED%', left(v, 120));
  PERFORM pg_temp.t_check('A7 the refused ingestion wrote no location', (SELECT count(*) FROM trustride.resource_location_event) = n);

  -- ============ historical queue exceptions never count as in flight
  PERFORM pg_temp.t_check('register of unrecoverable historical queue entries exists',
    to_regclass('trustride.orch_queue_historical_exception') IS NOT NULL);
  IF to_regclass('trustride.orch_queue_historical_exception') IS NOT NULL THEN
    snap := trustride.fn_orch_capacity_snapshot_record();
    SELECT signals_in_flight INTO inflight_before FROM trustride.orch_capacity_snapshot WHERE capacity_snapshot_id = snap;
    INSERT INTO trustride.orch_signal_queue (signal_id, correlation_id, source_engine_code, destination_engine_code, signal_type, queue_partition_id, queue_status, idempotency_key)
    SELECT gen_random_uuid(), gen_random_uuid(), 'TRS026_ENG004_BUS', 'TRS026_ENG011_PRESENT', 'SUITE24_ORPHAN', queue_partition_id, 'DISPATCHED', 'suite24:' || gen_random_uuid()
    FROM trustride.orch_queue_partition LIMIT 1 RETURNING queue_id INTO q;
    EXECUTE 'INSERT INTO trustride.orch_queue_historical_exception (queue_id, classification, evidence) VALUES ($1, ''UNRECOVERABLE_NO_INBOX_RECORD'', ''suite 24'')' USING q;
    snap := trustride.fn_orch_capacity_snapshot_record();
    SELECT signals_in_flight INTO inflight_after FROM trustride.orch_capacity_snapshot WHERE capacity_snapshot_id = snap;
    PERFORM pg_temp.t_check('a registered historical exception does not count as in flight', inflight_after = inflight_before,
      inflight_before || ' -> ' || inflight_after);
  END IF;
END
$$;
