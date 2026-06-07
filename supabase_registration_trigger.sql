-- ============================================================
--  REGISTRATION METADATA TRIGGER — Setup + Verification
--  Run this in Supabase SQL Editor (or via supabase db query).
--  Safe for existing databases — uses IF NOT EXISTS / IF EXISTS.
-- ============================================================


-- ── STEP 1: Add missing columns to profiles table ────────────
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS shift text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS session text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS photo_url text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS subject text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS designation text;


-- ── STEP 2: Create / Replace the trigger function ────────────
-- Reads raw_user_meta_data from Supabase Auth signup
-- and populates ALL profile fields in one INSERT.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (
    id, email, name, role, roll, registration, contact, semester, shift, session, subject, designation
  )
  VALUES (
    NEW.id,
    NEW.email,
    NEW.raw_user_meta_data ->> 'name',
    COALESCE(NEW.raw_user_meta_data ->> 'role', 'student'),
    NEW.raw_user_meta_data ->> 'roll',
    NEW.raw_user_meta_data ->> 'registration',
    NEW.raw_user_meta_data ->> 'contact',
    CASE WHEN NEW.raw_user_meta_data ? 'semester'
         THEN (NEW.raw_user_meta_data ->> 'semester')::integer
         ELSE NULL END,
    NEW.raw_user_meta_data ->> 'shift',
    NEW.raw_user_meta_data ->> 'session',
    NEW.raw_user_meta_data ->> 'subject',
    NEW.raw_user_meta_data ->> 'designation'
  );
  RETURN NEW;
END;
$$;


-- ── STEP 3: Attach trigger to auth.users ─────────────────────
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ── STEP 4: Verify trigger exists ────────────────────────────
SELECT
  tgname AS trigger_name,
  proname AS function_name,
  tgenabled AS enabled
FROM pg_trigger t
JOIN pg_proc p ON t.tgfoid = p.oid
WHERE tgname = 'on_auth_user_created';


-- ── STEP 5: Verify function exists ───────────────────────────
SELECT
  proname AS function_name,
  prosrc AS source_code
FROM pg_proc
WHERE proname = 'handle_new_user';


-- ── STEP 6: Verify profiles columns ──────────────────────────
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'profiles' AND table_schema = 'public'
ORDER BY ordinal_position;


-- ── STEP 7: Check current profiles data ──────────────────────
SELECT
  id, email, name, role, roll, registration, contact,
  semester, shift, session, subject, designation, status, created_at
FROM public.profiles
ORDER BY created_at DESC
LIMIT 10;


-- ── STEP 8: Clean up old profiles with missing data ─────────
-- OPTIONAL: Uncomment to delete profiles that only have email
-- (from before this trigger). Those users can re-register.
--
-- DELETE FROM public.profiles
-- WHERE name IS NULL AND roll IS NULL AND registration IS NULL;
