-- Allow students to delete their own attendance records.
-- The existing policy (attendance_records_delete) only allows admins.
-- We add a separate policy for students: they can delete records where
-- marked_by = auth.uid() (i.e., records they created by marking attendance).

DROP POLICY IF EXISTS "attendance_records_delete_own" ON attendance_records;
CREATE POLICY "attendance_records_delete_own" ON attendance_records
  FOR DELETE USING (marked_by = auth.uid());
