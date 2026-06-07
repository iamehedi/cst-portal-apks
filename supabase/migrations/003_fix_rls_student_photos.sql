-- ═══════════════════════════════════════════════════════════════════════════════
--  Migration 003: Fix RLS policies for student updates & profile photo storage
-- ═══════════════════════════════════════════════════════════════════════════════

-- ─── 1. Fix students_update_own RLS ──────────────────────────────────────────
-- The old policy used auth.uid() = id, but students.id is an auto-generated UUID
-- (not the auth user's UUID).  Now we use email as the join key instead.
DROP POLICY IF EXISTS "students_update_own" ON public.students;
CREATE POLICY "students_update_own"
  ON public.students FOR UPDATE
  USING (email = auth.email())
  WITH CHECK (email = auth.email());

-- Also add an explicit INSERT policy for admin (for clarity alongside UPDATE/DELETE)
DROP POLICY IF EXISTS "students_insert_admin" ON public.students;
CREATE POLICY "students_insert_admin"
  ON public.students FOR INSERT
  WITH CHECK (public.get_my_profile_is_admin());


-- ─── 2. Storage RLS — student-photos bucket ──────────────────────────────────
-- Only the photo owner (path starts with their auth.uid()) and admins may
-- upload, update, or delete profile photos.  Other buckets remain open to any
-- authenticated user.

-- Drop the old permissive policies
DROP POLICY IF EXISTS "storage_upload_auth" ON storage.objects;
DROP POLICY IF EXISTS "storage_delete_own_or_admin" ON storage.objects;

-- Upload: notes-files & notice-attachments — any authenticated user
CREATE POLICY "storage_upload_notes_notices"
  ON storage.objects FOR INSERT
  WITH CHECK (
    auth.role() = 'authenticated'
    AND bucket_id IN ('notes-files', 'notice-attachments')
  );

-- Upload: student-photos — only owner or admin
CREATE POLICY "storage_upload_student_photos"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'student-photos'
        AND auth.role() = 'authenticated'
        AND (
          name LIKE (auth.uid()::text || '/%')
          OR public.get_my_profile_is_admin()
        )
  );

-- Delete: notes-files & notice-attachments — any authenticated user
CREATE POLICY "storage_delete_notes_notices"
  ON storage.objects FOR DELETE
  USING (
    auth.role() = 'authenticated'
    AND bucket_id IN ('notes-files', 'notice-attachments')
  );

-- Delete: student-photos — only owner or admin
CREATE POLICY "storage_delete_student_photos"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'student-photos'
        AND auth.role() = 'authenticated'
        AND (
          name LIKE (auth.uid()::text || '/%')
          OR public.get_my_profile_is_admin()
        )
  );

-- Update (replace photo): student-photos — only owner or admin
CREATE POLICY "storage_update_student_photos"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'student-photos'
        AND auth.role() = 'authenticated'
        AND (
          name LIKE (auth.uid()::text || '/%')
          OR public.get_my_profile_is_admin()
        )
  )
  WITH CHECK (
    bucket_id = 'student-photos'
        AND auth.role() = 'authenticated'
        AND (
          name LIKE (auth.uid()::text || '/%')
          OR public.get_my_profile_is_admin()
        )
  );
