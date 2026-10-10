-- Suite 22 -- the calendar follows the Public Holidays Act, Cap. 110 (as amended 2024)
-- (TRS026-ENG-REMEDIATION-001: D25). Fixed and Easter-based holidays for 2026
-- and 2027 are present, with the following Monday when one falls on a Sunday.
DO $$
DECLARE
  n INT; v TEXT;
BEGIN
  SELECT count(*), string_agg(d::text, ' ') INTO n, v FROM unnest(ARRAY[
    '2026-01-01', '2026-04-03', '2026-04-06', '2026-05-01', '2026-06-01', '2026-10-10', '2026-10-20', '2026-12-12', '2026-12-25', '2026-12-26',
    '2027-01-01', '2027-03-26', '2027-03-29', '2027-05-01', '2027-06-01', '2027-10-10', '2027-10-11', '2027-10-20',
    '2027-12-12', '2027-12-13', '2027-12-25', '2027-12-26', '2027-12-27']::date[]) d
  WHERE NOT EXISTS (SELECT 1 FROM trustride.calendar_reference c WHERE c.calendar_date = d AND c.day_type = 'PUBLIC_HOLIDAY');
  PERFORM pg_temp.t_check('D25 every statutory holiday of 2026 and 2027 is on the calendar', n = 0, coalesce(v, ''));
  PERFORM pg_temp.t_check('D25 Utamaduni Day is not on the calendar (replaced by Mazingira Day, 2024)',
    NOT EXISTS (SELECT 1 FROM trustride.calendar_reference WHERE description ILIKE '%Utamaduni%'));
  -- Monday 13 Dec 2027 (Jamhuri Day falls on Sunday) is treated like an established weekday holiday (Madaraka Day 2026).
  v := trustride.fn_business_working_window('2027-12-13'::date)::text;
  PERFORM pg_temp.t_check('D25 the Monday after a Sunday holiday has the holiday working window',
    v IS NOT DISTINCT FROM trustride.fn_business_working_window('2026-06-01'::date)::text, coalesce(v, 'null'));
END
$$;
