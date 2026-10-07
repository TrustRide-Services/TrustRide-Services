-- Local mirror only (never applied to Supabase): the stock supabase/postgres
-- image ships an older GoTrue auth.users shape and no migrations ledger.
-- Bring both to what a hosted project has, before the migration chain runs.
CREATE SCHEMA IF NOT EXISTS supabase_migrations;
CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations (version TEXT PRIMARY KEY, statements TEXT[], name TEXT);
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at TIMESTAMPTZ;
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS phone_confirmed_at TIMESTAMPTZ;
