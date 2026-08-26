-- Platform: capture the authenticated-role bridge in version control, and
-- close a real gap found while verifying the Data API against a live
-- signed-in session.
--
-- 1. GRANT trustride_authenticated TO authenticated already exists live on
--    trustride-stagging (confirmed via pg_has_role), but was never issued
--    by any migration in this repo -- it was applied directly against the
--    project at some earlier point outside this chain. Without it, every
--    RLS policy and function grant in this rebuild (all written against
--    trustride_authenticated) would be invisible to Supabase's real
--    Data-API `authenticated` role. Restated here, idempotently, so a
--    clean rebuild from this migration chain reproduces the live state
--    instead of silently missing it.
--
-- 2. fn_business_actor_register was granted only to the Business engine's
--    own service role (trs026_eng004_bus_service) -- but the frontend
--    calls it directly (the /verify shell's "choose your user type" step)
--    rather than through Engine 11's present_shell command dispatcher, so
--    a real signed-in user could never actually call it. Confirmed via
--    has_function_privilege('authenticated', ...) returning false live.
GRANT trustride_authenticated TO authenticated;

GRANT EXECUTE ON FUNCTION trustride.fn_business_actor_register(UUID, trustride.business_user_type_domain_enum, TEXT)
  TO trustride_authenticated;
