-- Allow teachers and admins to delete any attendance record.
--
-- Current policies:
--   attendance_records_delete      — admin only (is_admin = true)
--   attendance_records_delete_own  — student can delete own (marked_by = auth.uid())
--
-- This migration replaces the admin-only delete policy with one that also
-- allows teachers (role = 'teacher' in profiles) to delete any record.
-- This enables the in-app "Delete Record" button on the attendance report
-- screens for both teachers and admins.

DROP POLICY IF EXISTS "attendance_records_delete" ON attendance_records;
CREATE POLICY "attendance_records_delete" ON attendance_records
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid()
        AND (is_admin = true OR role = 'teacher')
    )
  );
