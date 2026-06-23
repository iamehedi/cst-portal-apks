-- ============================================================
--  CST PORTAL — UNIFIED SUPABASE SCHEMA
--  Works identically for BOTH the HTML web portal and Flutter app.
--  Run this entire file once in Supabase → SQL Editor.
-- ============================================================

-- ── 0. HELPER FUNCTION (prevents RLS recursion) ─────────────
CREATE OR REPLACE FUNCTION public.get_my_profile_is_admin()
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT COALESCE(
    (SELECT is_admin FROM public.profiles WHERE id = auth.uid() LIMIT 1),
    FALSE
  );
$$;


-- ══════════════════════════════════════════════════════════════
--  1. PROFILES
--  HTML uses: id, email, name, role, semester, status, is_admin,
--             roll, registration, contact, shift, session, photo_url
--  Flutter uses: same — approval is now status='approved' (not bool)
-- ══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.profiles (
  id            uuid PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
  email         text NOT NULL,
  name          text,
  role          text NOT NULL DEFAULT 'student',   -- 'student' | 'teacher'
  semester      integer,
  status        text NOT NULL DEFAULT 'pending',   -- 'pending' | 'approved' | 'rejected'
  is_admin      boolean NOT NULL DEFAULT false,
  roll          text,
  registration  text,
  contact       text,
  shift         text,
  session       text,
  photo_url     text,
  subject       text,          -- teacher only
  designation   text,          -- teacher only
  created_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own_or_admin" ON public.profiles;
DROP POLICY IF EXISTS "profiles_delete_admin" ON public.profiles;

CREATE POLICY "profiles_select_own"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id OR public.get_my_profile_is_admin());

CREATE POLICY "profiles_insert_own"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_update_own_or_admin"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id OR public.get_my_profile_is_admin());

CREATE POLICY "profiles_delete_admin"
  ON public.profiles FOR DELETE
  USING (public.get_my_profile_is_admin());

-- ── Trigger: auto-populate profiles from auth metadata ────────
-- Runs when Supabase Auth creates a new user.
-- Reads raw_user_meta_data (passed from Flutter during signUp)
-- and inserts all profile fields so admin can see them immediately.
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

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ══════════════════════════════════════════════════════════════
--  2. STUDENTS
--  HTML uses: id, name, email, roll, registration, semester (int),
--             shift, session, contact, photo_url
--  Flutter uses: same
-- ══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.students (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text NOT NULL,
  email         text,
  roll          text,
  registration  text,
  semester      integer,
  shift         text,
  session       text,
  contact       text,
  photo_url     text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "students_read_all" ON public.students;
DROP POLICY IF EXISTS "students_write_admin" ON public.students;

CREATE POLICY "students_read_all"
  ON public.students FOR SELECT USING (true);

CREATE POLICY "students_write_admin"
  ON public.students FOR ALL
  USING (public.get_my_profile_is_admin());

-- Students can update their own record when their auth email matches the student's email
-- (students.id is a separate auto-generated UUID, not the auth user's UUID)
CREATE POLICY "students_update_own"
  ON public.students FOR UPDATE
  USING (email = auth.email())
  WITH CHECK (email = auth.email());


-- ══════════════════════════════════════════════════════════════
--  3. TEACHERS
--  HTML uses: teacher_name, subject, designation, email, phone
--  Flutter (old) used: name — FIXED in supabase_service.dart
--  Unified column: teacher_name  (Flutter service updated to match)
-- ══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.teachers (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_name  text NOT NULL,
  subject       text,
  designation   text,
  email         text,
  phone         text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.teachers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "teachers_read_all" ON public.teachers;
DROP POLICY IF EXISTS "teachers_write_admin" ON public.teachers;

CREATE POLICY "teachers_read_all"
  ON public.teachers FOR SELECT USING (true);

CREATE POLICY "teachers_write_admin"
  ON public.teachers FOR ALL
  USING (public.get_my_profile_is_admin());


-- ══════════════════════════════════════════════════════════════
--  4. CLASS ROUTINE SLOTS  (was 'routines' in old Flutter)
--  HTML uses: semester (int), day, period_index, subject,
--             subject_code, teacher, acronym, room
--  Flutter (old) used table 'routines' with: semester (int),
--             day, subject, time, room, teacher
--  Unified table: class_routine_slots  (Flutter service updated)
-- ══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.class_routine_slots (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  semester      integer NOT NULL,
  day           text NOT NULL,   -- 'Sun' | 'Mon' | 'Tue' | 'Wed' | 'Thu'
  period_index  integer NOT NULL, -- 0-based period number
  subject       text NOT NULL,
  subject_code  text,
  teacher       text,
  acronym       text,
  room          text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (semester, day, period_index)
);

ALTER TABLE public.class_routine_slots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "routine_read_all" ON public.class_routine_slots;
DROP POLICY IF EXISTS "routine_write_admin" ON public.class_routine_slots;

CREATE POLICY "routine_read_all"
  ON public.class_routine_slots FOR SELECT USING (true);

CREATE POLICY "routine_write_admin"
  ON public.class_routine_slots FOR ALL
  USING (public.get_my_profile_is_admin());


-- ══════════════════════════════════════════════════════════════
--  5. NOTICES
--  HTML uses: title, description, attachment_url, created_at
--  Flutter (old) used: title, description, priority, created_at
--  Unified: keep all columns (priority defaults to 'normal')
-- ══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.notices (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title           text NOT NULL,
  description     text,
  attachment_url  text,
  priority        text NOT NULL DEFAULT 'normal',  -- 'normal' | 'urgent'
  user_id         uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.notices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notices_read_all" ON public.notices;
DROP POLICY IF EXISTS "notices_write_admin" ON public.notices;

CREATE POLICY "notices_read_all"
  ON public.notices FOR SELECT USING (true);

CREATE POLICY "notices_write_admin"
  ON public.notices FOR ALL
  USING (public.get_my_profile_is_admin());


-- ══════════════════════════════════════════════════════════════
--  6. NOTES (Study Materials)
--  HTML uses: note_title, subject, semester (int),
--             note_file_url, upload_date
--  Flutter (old) used: title, subject, semester, file_url,
--             created_at
--  Unified: use note_title + note_file_url (Flutter service
--           updated to use these columns)
-- ══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.notes (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  note_title    text NOT NULL,
  subject       text,
  semester      integer,
  note_file_url text,
  user_id       uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  upload_date   timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notes_read_all" ON public.notes;
DROP POLICY IF EXISTS "notes_write_admin" ON public.notes;

CREATE POLICY "notes_read_all"
  ON public.notes FOR SELECT USING (true);

CREATE POLICY "notes_write_admin"
  ON public.notes FOR ALL
  USING (public.get_my_profile_is_admin());


-- ══════════════════════════════════════════════════════════════
--  7. EXAMS
--  HTML uses: exam_type, subject, subject_code, exam_date,
--             start_time, end_time, room, teacher, semester
-- ══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.exams (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  exam_type     text NOT NULL,   -- e.g. 'Midterm' | 'Final'
  subject       text NOT NULL,
  subject_code  text NOT NULL,
  exam_date     date NOT NULL,
  start_time    time NOT NULL,
  end_time      time NOT NULL,
  room          text,
  teacher       text,
  semester      integer NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.exams ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "exams_read_all" ON public.exams;
DROP POLICY IF EXISTS "exams_write_admin" ON public.exams;

CREATE POLICY "exams_read_all"
  ON public.exams FOR SELECT USING (true);

CREATE POLICY "exams_write_admin"
  ON public.exams FOR ALL
  USING (public.get_my_profile_is_admin());


-- ══════════════════════════════════════════════════════════════
--  8. STORAGE BUCKETS
--  Run these manually in Supabase → SQL Editor if not created yet.
-- ══════════════════════════════════════════════════════════════
INSERT INTO storage.buckets (id, name, public) VALUES ('student-photos', 'student-photos', true) ON CONFLICT DO NOTHING;
INSERT INTO storage.buckets (id, name, public) VALUES ('notes-files', 'notes-files', true) ON CONFLICT DO NOTHING;
INSERT INTO storage.buckets (id, name, public) VALUES ('notice-attachments', 'notice-attachments', true) ON CONFLICT DO NOTHING;


-- Storage RLS: drop ALL known policies (old + current) to avoid conflicts
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
DROP POLICY IF EXISTS "storage_read_all" ON storage.objects;
DROP POLICY IF EXISTS "storage_upload_auth" ON storage.objects;
DROP POLICY IF EXISTS "storage_upload_notes_notices" ON storage.objects;
DROP POLICY IF EXISTS "storage_upload_student_photos" ON storage.objects;
DROP POLICY IF EXISTS "storage_delete_own_or_admin" ON storage.objects;
DROP POLICY IF EXISTS "storage_delete_notes_notices" ON storage.objects;
DROP POLICY IF EXISTS "storage_delete_student_photos" ON storage.objects;
DROP POLICY IF EXISTS "storage_update_student_photos" ON storage.objects;
DROP POLICY IF EXISTS "storage_insert_student_photos" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated uploads to student-photos" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated delete student-photos" ON storage.objects;
DROP POLICY IF EXISTS "student_photos_insert" ON storage.objects;
DROP POLICY IF EXISTS "student_photos_delete" ON storage.objects;
DROP POLICY IF EXISTS "student_photos_update" ON storage.objects;
DROP POLICY IF EXISTS "student_photos_select" ON storage.objects;

CREATE POLICY "storage_read_all"
  ON storage.objects FOR SELECT
  USING (bucket_id IN ('notes-files', 'notice-attachments', 'student-photos', 'routine-files'));

-- Upload: notes-files & notice-attachments — any authenticated user
CREATE POLICY "storage_upload_notes_notices"
  ON storage.objects FOR INSERT
  WITH CHECK (
    auth.role() = 'authenticated'
    AND bucket_id IN ('notes-files', 'notice-attachments')
  );

-- Upload: student-photos — only owner (path starts with auth.uid()) or admin
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


-- ══════════════════════════════════════════════════════════════
--  9. DEVICE TOKENS (for push notifications)
--  Stores FCM tokens per user so admin can send push notifications
--  when posting notices.
-- ══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.device_tokens (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  token         text NOT NULL,
  device_token  text NOT NULL,
  platform      text NOT NULL DEFAULT 'android',  -- 'android' | 'ios'
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id)
);

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "device_tokens_insert_own" ON public.device_tokens;
DROP POLICY IF EXISTS "device_tokens_select_own_or_admin" ON public.device_tokens;
DROP POLICY IF EXISTS "device_tokens_update_own" ON public.device_tokens;
DROP POLICY IF EXISTS "device_tokens_delete_own" ON public.device_tokens;

-- Users can insert their own device token
CREATE POLICY "device_tokens_insert_own"
  ON public.device_tokens FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can read their own token; service role reads all for push
CREATE POLICY "device_tokens_select_own"
  ON public.device_tokens FOR SELECT
  USING (auth.uid() = user_id);

-- Users can update their own token
CREATE POLICY "device_tokens_update_own"
  ON public.device_tokens FOR UPDATE
  USING (auth.uid() = user_id);

-- Users can delete their own token (e.g. on sign-out)
CREATE POLICY "device_tokens_delete_own"
  ON public.device_tokens FOR DELETE
  USING (auth.uid() = user_id);


-- ══════════════════════════════════════════════════════════════
--  10. FCM TOKENS (lightweight, no user association)
--  Used by saveFcmToken() in main.dart during app startup.
--  Stores device FCM tokens without requiring user login.
-- ══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.fcm_tokens (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token         text NOT NULL UNIQUE,
  platform      text NOT NULL DEFAULT 'android',  -- 'android' | 'ios'
  created_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.fcm_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "fcm_tokens_insert_all" ON public.fcm_tokens;
DROP POLICY IF EXISTS "fcm_tokens_select_all" ON public.fcm_tokens;

-- Allow anyone (including anon) to insert/upsert tokens
-- Tokens are non-sensitive device identifiers needed for push notifications
CREATE POLICY "fcm_tokens_insert_all"
  ON public.fcm_tokens FOR INSERT
  WITH CHECK (true);

-- Allow anyone to read tokens (needed for upsert onConflict check, and admin push)
CREATE POLICY "fcm_tokens_select_all"
  ON public.fcm_tokens FOR SELECT
  USING (true);


-- ══════════════════════════════════════════════════════════════
--  11. BLE ATTENDANCE TABLES
--  Stores BLE (Bluetooth Low Energy) attendance sessions and records
--  that previously only existed in local SQLite.
-- ══════════════════════════════════════════════════════════════

-- ─── ble_sessions ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ble_sessions (
  id TEXT PRIMARY KEY,
  subject TEXT NOT NULL,
  semester INTEGER NOT NULL CHECK (semester BETWEEN 1 AND 8),
  teacher_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  department TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'closed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at TIMESTAMPTZ
);

ALTER TABLE public.ble_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ble_sessions_select" ON public.ble_sessions;
DROP POLICY IF EXISTS "ble_sessions_insert" ON public.ble_sessions;
DROP POLICY IF EXISTS "ble_sessions_update" ON public.ble_sessions;
DROP POLICY IF EXISTS "ble_sessions_delete" ON public.ble_sessions;

CREATE POLICY "ble_sessions_select" ON public.ble_sessions
  FOR SELECT USING (
    auth.uid() = teacher_id
    OR public.get_my_profile_is_admin()
  );

CREATE POLICY "ble_sessions_insert" ON public.ble_sessions
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "ble_sessions_update" ON public.ble_sessions
  FOR UPDATE USING (
    auth.uid() = teacher_id
    OR public.get_my_profile_is_admin()
  );

CREATE POLICY "ble_sessions_delete" ON public.ble_sessions
  FOR DELETE USING (
    auth.uid() = teacher_id
    OR public.get_my_profile_is_admin()
  );

-- ─── ble_pending_attendance ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ble_pending_attendance (
  id BIGINT NOT NULL,
  session_id TEXT NOT NULL REFERENCES public.ble_sessions(id) ON DELETE CASCADE,
  student_id TEXT NOT NULL,
  student_name TEXT NOT NULL,
  time TEXT NOT NULL,
  rssi INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'present', 'rejected', 'disconnected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (id, session_id)
);

ALTER TABLE public.ble_pending_attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ble_pending_select" ON public.ble_pending_attendance;
DROP POLICY IF EXISTS "ble_pending_insert" ON public.ble_pending_attendance;
DROP POLICY IF EXISTS "ble_pending_update" ON public.ble_pending_attendance;
DROP POLICY IF EXISTS "ble_pending_delete" ON public.ble_pending_attendance;

CREATE POLICY "ble_pending_select" ON public.ble_pending_attendance
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.ble_sessions
      WHERE id = session_id AND (
        teacher_id = auth.uid()
        OR public.get_my_profile_is_admin()
      )
    )
    OR student_id = auth.uid()::text
  );

CREATE POLICY "ble_pending_insert" ON public.ble_pending_attendance
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "ble_pending_update" ON public.ble_pending_attendance
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.ble_sessions
      WHERE id = session_id AND (
        teacher_id = auth.uid()
        OR public.get_my_profile_is_admin()
      )
    )
  );

CREATE POLICY "ble_pending_delete" ON public.ble_pending_attendance
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.ble_sessions
      WHERE id = session_id AND (
        teacher_id = auth.uid()
        OR public.get_my_profile_is_admin()
      )
    )
  );

-- ─── ble_final_attendance ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ble_final_attendance (
  student_id TEXT NOT NULL,
  session_id TEXT NOT NULL REFERENCES public.ble_sessions(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'present' CHECK (status IN ('present', 'rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (student_id, session_id)
);

ALTER TABLE public.ble_final_attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ble_final_select" ON public.ble_final_attendance;
DROP POLICY IF EXISTS "ble_final_insert" ON public.ble_final_attendance;
DROP POLICY IF EXISTS "ble_final_update" ON public.ble_final_attendance;
DROP POLICY IF EXISTS "ble_final_delete" ON public.ble_final_attendance;

CREATE POLICY "ble_final_select" ON public.ble_final_attendance
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.ble_sessions
      WHERE id = session_id AND (
        teacher_id = auth.uid()
        OR public.get_my_profile_is_admin()
      )
    )
    OR student_id = auth.uid()::text
  );

CREATE POLICY "ble_final_insert" ON public.ble_final_attendance
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "ble_final_update" ON public.ble_final_attendance
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.ble_sessions
      WHERE id = session_id AND (
        teacher_id = auth.uid()
        OR public.get_my_profile_is_admin()
      )
    )
  );

CREATE POLICY "ble_final_delete" ON public.ble_final_attendance
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.ble_sessions
      WHERE id = session_id AND (
        teacher_id = auth.uid()
        OR public.get_my_profile_is_admin()
      )
    )
  );

-- ─── Indexes ─────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_ble_sessions_teacher ON public.ble_sessions(teacher_id);
CREATE INDEX IF NOT EXISTS idx_ble_sessions_status ON public.ble_sessions(status) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_ble_final_session ON public.ble_final_attendance(session_id);
CREATE INDEX IF NOT EXISTS idx_ble_final_student ON public.ble_final_attendance(student_id);
CREATE INDEX IF NOT EXISTS idx_ble_pending_session ON public.ble_pending_attendance(session_id);
CREATE INDEX IF NOT EXISTS idx_ble_pending_student ON public.ble_pending_attendance(student_id);
