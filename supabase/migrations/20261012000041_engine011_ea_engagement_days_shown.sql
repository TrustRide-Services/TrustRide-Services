-- ============================================================================
-- Engine 11 -- an Executive Assistant booked by the day is shown as days
-- Construction Directive WP3 (D24 follow-through)
-- ============================================================================
-- Migration 040 lets a customer book an assistant by the day (1-6 days, hours
-- per day). The customer's order view and the operator's job card showed only
-- billed_hours, so a two-day booking would read as "8 hours". Both projections
-- now also carry engagement_unit and billed_days. Additive keys only.
-- ============================================================================

DO $patch$
DECLARE
  v_def TEXT;
BEGIN
  SELECT pg_get_functiondef('trustride.fn_present_proj_order_detail(uuid,jsonb)'::regprocedure) INTO v_def;
  IF position(E'''billed_hours'', l.scope_detail->>''billed_hours'',' IN v_def) = 0 THEN RAISE EXCEPTION 'order detail anchor not found'; END IF;
  EXECUTE replace(v_def, E'''billed_hours'', l.scope_detail->>''billed_hours'',',
    E'''billed_hours'', l.scope_detail->>''billed_hours'', ''billed_days'', l.scope_detail->>''billed_days'', ''engagement_unit'', l.scope_detail->>''engagement_unit'',');

  SELECT pg_get_functiondef('trustride.fn_present_operator_job_card(uuid)'::regprocedure) INTO v_def;
  IF position(E'''billed_hours'', l.scope_detail->>''billed_hours'',' IN v_def) = 0 THEN RAISE EXCEPTION 'job card anchor not found'; END IF;
  EXECUTE replace(v_def, E'''billed_hours'', l.scope_detail->>''billed_hours'',',
    E'''billed_hours'', l.scope_detail->>''billed_hours'', ''billed_days'', l.scope_detail->>''billed_days'',');
END;
$patch$;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
