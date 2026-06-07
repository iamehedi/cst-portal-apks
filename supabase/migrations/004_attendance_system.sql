-- Smart Attendance Management System
-- Tables, function, and RLS policies for QR-based attendance

-- ─── attendance_sessions ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS attendance_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  department TEXT NOT NULL DEFAULT 'CST',
  subject TEXT NOT NULL,
  semester INTEGER NOT NULL CHECK (semester BETWEEN 1 AND 8),
  current_token TEXT,
  token_created_at TIMESTAMPTZ,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE attendance_sessions ENABLE ROW LEVEL SECURITY;

-- Teacher sees own sessions, admin sees all
CREATE POLICY "attendance_sessions_select" ON attendance_sessions
  FOR SELECT USING (
    auth.uid() = teacher_id
    OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
  );

-- Any authenticated user can create (teacher or admin)
CREATE POLICY "attendance_sessions_insert" ON attendance_sessions
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Teacher updates own sessions, admin updates any
CREATE POLICY "attendance_sessions_update" ON attendance_sessions
  FOR UPDATE USING (
    auth.uid() = teacher_id
    OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
  );

-- Only admin can delete sessions
CREATE POLICY "attendance_sessions_delete" ON attendance_sessions
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
  );

-- ─── attendance_records ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS attendance_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES attendance_sessions(id) ON DELETE CASCADE,
  student_id TEXT NOT NULL,
  student_name TEXT NOT NULL,
  method TEXT NOT NULL CHECK (method IN ('qr', 'manual')),
  marked_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  marked_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE attendance_records ENABLE ROW LEVEL SECURITY;

-- Teacher sees records for their sessions, admin sees all, student sees own
CREATE POLICY "attendance_records_select" ON attendance_records
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM attendance_sessions
      WHERE id = session_id AND (
        teacher_id = auth.uid()
        OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
      )
    )
    OR marked_by = auth.uid()
  );

-- Direct INSERT disabled — all inserts go through validate_and_mark_attendance()
-- No INSERT policy = blocked for client-side inserts

-- Only admin can update/delete records
CREATE POLICY "attendance_records_update" ON attendance_records
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
  );

CREATE POLICY "attendance_records_delete" ON attendance_records
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
  );

-- ─── Indexes ─────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_attendance_sessions_teacher ON attendance_sessions(teacher_id);
CREATE INDEX IF NOT EXISTS idx_attendance_sessions_active ON attendance_sessions(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_attendance_records_session ON attendance_records(session_id);
CREATE INDEX IF NOT EXISTS idx_attendance_records_student ON attendance_records(session_id, student_id);

-- ─── validate_and_mark_attendance() ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION validate_and_mark_attendance(
  p_session_id UUID,
  p_token TEXT,
  p_student_id TEXT,
  p_student_name TEXT,
  p_method TEXT,
  p_user_id UUID
) RETURNS JSONB AS $$
DECLARE
  v_session RECORD;
  v_age_seconds DOUBLE PRECISION;
BEGIN
  -- Find the session
  IF p_session_id IS NOT NULL THEN
    SELECT * INTO v_session FROM attendance_sessions
    WHERE id = p_session_id AND is_active = true;
  ELSE
    -- Look up by token (for manual entry where student doesn't know session_id)
    SELECT * INTO v_session FROM attendance_sessions
    WHERE current_token = UPPER(p_token) AND is_active = true
    ORDER BY token_created_at DESC LIMIT 1;
  END IF;

  IF v_session IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'No active session found');
  END IF;

  -- Check token matches (case-insensitive)
  IF v_session.current_token IS NULL OR v_session.current_token != UPPER(p_token) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid token');
  END IF;

  -- Check token freshness (within 30 seconds)
  IF v_session.token_created_at IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Token not initialized');
  END IF;

  v_age_seconds := EXTRACT(EPOCH FROM (now() - v_session.token_created_at));
  IF v_age_seconds > 30 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Token expired. Please scan again.');
  END IF;

  -- Check duplicate
  IF EXISTS (
    SELECT 1 FROM attendance_records
    WHERE session_id = v_session.id AND student_id = p_student_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Attendance already marked for this session');
  END IF;

  -- Insert the attendance record
  INSERT INTO attendance_records (session_id, student_id, student_name, method, marked_by)
  VALUES (v_session.id, p_student_id, p_student_name, p_method, p_user_id);

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Attendance marked successfully',
    'subject', v_session.subject,
    'semester', v_session.semester,
    'department', v_session.department
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ─── Enable Realtime ─────────────────────────────────────────────────────────
-- Run these in Supabase Dashboard > Database > Replication if not already enabled
-- ALTER PUBLICATION supabase_realtime ADD TABLE attendance_sessions;
-- ALTER PUBLICATION supabase_realtime ADD TABLE attendance_records;
