-- Keep only 3rd-semester class routines.
-- Run once in Supabase → SQL Editor.
DELETE FROM public.class_routine_slots
WHERE semester <> 3;
