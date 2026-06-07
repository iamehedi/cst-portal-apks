-- Update RLS policies for college_off_days and exams to allow teachers
-- (role = 'teacher') in addition to admins.

-- ─── college_off_days ──────────────────────────────────────────
DROP POLICY IF EXISTS "off_days_insert" ON college_off_days;
CREATE POLICY "off_days_insert" ON college_off_days
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND (is_admin = true OR role = 'teacher'))
  );

DROP POLICY IF EXISTS "off_days_update" ON college_off_days;
CREATE POLICY "off_days_update" ON college_off_days
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND (is_admin = true OR role = 'teacher'))
  );

DROP POLICY IF EXISTS "off_days_delete" ON college_off_days;
CREATE POLICY "off_days_delete" ON college_off_days
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND (is_admin = true OR role = 'teacher'))
  );

-- ─── exams ─────────────────────────────────────────────────────
DROP POLICY IF EXISTS "exams_write_admin" ON exams;
CREATE POLICY "exams_write_admin" ON exams
  FOR ALL USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND (is_admin = true OR role = 'teacher'))
  );
