-- Drop ALL existing storage.objects policies
DROP POLICY IF EXISTS "Allow only admin to delete files atdje3_0" ON storage.objects;
DROP POLICY IF EXISTS "Allow only admin to delete files atdje3_1" ON storage.objects;
DROP POLICY IF EXISTS "Allow only admin to delete notice-attachments" ON storage.objects;
DROP POLICY IF EXISTS "Allow only admin to delete routine-files" ON storage.objects;
DROP POLICY IF EXISTS "Allow only admin to insert files" ON storage.objects;
DROP POLICY IF EXISTS "Allow only admin to insert notice-attachments" ON storage.objects;
DROP POLICY IF EXISTS "Allow only admin to insert routine-files" ON storage.objects;
DROP POLICY IF EXISTS "Allow only admin to insert student-photos" ON storage.objects;
DROP POLICY IF EXISTS "Allow only admin to delete student-photos" ON storage.objects;
DROP POLICY IF EXISTS "Secure Student Photos" ON storage.objects;
DROP POLICY IF EXISTS "storage_delete_notes_notices" ON storage.objects;
DROP POLICY IF EXISTS "storage_upload_notes_notices" ON storage.objects;
DROP POLICY IF EXISTS "student_photos_delete" ON storage.objects;
DROP POLICY IF EXISTS "student_photos_insert" ON storage.objects;
DROP POLICY IF EXISTS "student_photos_update" ON storage.objects;
DROP POLICY IF EXISTS "storage_read_all" ON storage.objects;
DROP POLICY IF EXISTS "storage_upload_auth" ON storage.objects;
DROP POLICY IF EXISTS "storage_upload_student_photos" ON storage.objects;
DROP POLICY IF EXISTS "storage_delete_own_or_admin" ON storage.objects;
DROP POLICY IF EXISTS "storage_delete_student_photos" ON storage.objects;
DROP POLICY IF EXISTS "storage_update_student_photos" ON storage.objects;
DROP POLICY IF EXISTS "storage_insert_student_photos" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated uploads to student-photos" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated delete student-photos" ON storage.objects;
DROP POLICY IF EXISTS "student_photos_select" ON storage.objects;

-- CREATE clean policies

-- SELECT: all buckets readable
CREATE POLICY "storage_read_all"
  ON storage.objects FOR SELECT
  USING (bucket_id IN ('notes-files', 'notice-attachments', 'student-photos', 'routine-files'));

-- INSERT: notes & notices — any authenticated user
CREATE POLICY "storage_upload_notes_notices"
  ON storage.objects FOR INSERT
  WITH CHECK (
    auth.role() = 'authenticated'
    AND bucket_id IN ('notes-files', 'notice-attachments')
  );

-- INSERT: student-photos — owner (path starts with auth.uid()) OR admin
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

-- DELETE: notes & notices — any authenticated user
CREATE POLICY "storage_delete_notes_notices"
  ON storage.objects FOR DELETE
  USING (
    auth.role() = 'authenticated'
    AND bucket_id IN ('notes-files', 'notice-attachments')
  );

-- DELETE: student-photos — owner OR admin
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

-- UPDATE: student-photos — owner OR admin (needed for upsert=true re-upload)
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

-- Verify
SELECT policyname, cmd
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects'
ORDER BY policyname;
