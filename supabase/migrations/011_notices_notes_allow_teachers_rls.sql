-- Update RLS policies for notices and notes to allow teachers
-- (role = 'teacher') in addition to admins.
-- Previously only is_admin = true was allowed via get_my_profile_is_admin() helper.

-- ─── notices ─────────────────────────────────────────────────
DROP POLICY IF EXISTS "notices_write_admin" ON public.notices;
CREATE POLICY "notices_write_admin" ON public.notices
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND (is_admin = true OR role = 'teacher'))
  );

-- ─── notes ───────────────────────────────────────────────────
DROP POLICY IF EXISTS "notes_write_admin" ON public.notes;
CREATE POLICY "notes_write_admin" ON public.notes
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND (is_admin = true OR role = 'teacher'))
  );
