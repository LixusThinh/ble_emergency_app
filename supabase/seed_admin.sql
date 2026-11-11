-- Makes an existing account the first administrator. Run once in the
-- Supabase SQL Editor (it runs as the database owner, so it is not subject to
-- the rules in the migration). Sign up in the app or the admin web first,
-- then replace the email below.
update public.profiles
set role = 'admin'
where email = 'ten-ban@example.com';

-- Expect exactly one row.
select id, email, role from public.profiles where role = 'admin';
