-- ============================================================================
-- Engine 1 (Foundation) -- the calendar follows the Public Holidays Act
-- TRS026-ENG-REMEDIATION-001, finding D25
-- ============================================================================
-- Public Holidays Act, Cap. 110, as amended by the Statute Law (Miscellaneous
-- Amendments) Act 2024 (Mazingira Day, 10 October, replaces Utamaduni Day).
-- When a public holiday falls on a Sunday, the following Monday is a public
-- holiday. The calendar lacked Good Friday and Easter Monday 2026, Mazingira
-- Day 2026 and every 2027 date.
--
-- Added: the fixed and Easter-based holidays for 2026 and 2027, with the
-- Sunday substitutes for 2027 (Mazingira Day, Jamhuri Day, Boxing Day).
-- Not added: Idd-ul-Fitr and Idd-ul-Azha, which the Interior Cabinet
-- Secretary declares each year by Gazette notice after the moon is sighted;
-- each is added when gazetted.
--
-- Effect: the established holiday behaviour (Engine 4 working window and
-- working-day clock; the Engine 5 EA statutory method) now applies on these
-- dates. Engine 5 transport pricing does not read the calendar.
-- ============================================================================

INSERT INTO trustride.calendar_reference (calendar_date, day_type, description) VALUES
  ('2026-04-03', 'PUBLIC_HOLIDAY', 'Good Friday'),
  ('2026-04-06', 'PUBLIC_HOLIDAY', 'Easter Monday'),
  ('2026-10-10', 'PUBLIC_HOLIDAY', 'Mazingira Day'),
  ('2027-01-01', 'PUBLIC_HOLIDAY', 'New Year''s Day'),
  ('2027-03-26', 'PUBLIC_HOLIDAY', 'Good Friday'),
  ('2027-03-29', 'PUBLIC_HOLIDAY', 'Easter Monday'),
  ('2027-05-01', 'PUBLIC_HOLIDAY', 'Labour Day'),
  ('2027-06-01', 'PUBLIC_HOLIDAY', 'Madaraka Day'),
  ('2027-10-10', 'PUBLIC_HOLIDAY', 'Mazingira Day'),
  ('2027-10-11', 'PUBLIC_HOLIDAY', 'Mazingira Day (Sunday substitute)'),
  ('2027-10-20', 'PUBLIC_HOLIDAY', 'Mashujaa Day'),
  ('2027-12-12', 'PUBLIC_HOLIDAY', 'Jamhuri Day'),
  ('2027-12-13', 'PUBLIC_HOLIDAY', 'Jamhuri Day (Sunday substitute)'),
  ('2027-12-25', 'PUBLIC_HOLIDAY', 'Christmas Day'),
  ('2027-12-26', 'PUBLIC_HOLIDAY', 'Boxing Day'),
  ('2027-12-27', 'PUBLIC_HOLIDAY', 'Boxing Day (Sunday substitute)')
ON CONFLICT (calendar_date) DO NOTHING;

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
