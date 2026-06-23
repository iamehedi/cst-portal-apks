-- BLE Attendance Tables
-- Stores BLE (Bluetooth Low Energy) attendance sessions and records
-- that previously only existed in local SQLite

-- ─── ble_sessions ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ble_sessions (
  id TEXT PRIMARY KEY,
  subject TEXT NOT NULL,
  semester INTEGER NOT NULL CHECK (semester BETWEEN 1 AND 8),
  teacher_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  department TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'closed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at TIMESTAMPTZ
);

ALTER TABLE ble_sessions ENABLE ROW LEVEL SECURITY;

-- Teacher sees own sessions, admin sees all
CREATE POLICY "ble_sessions_select" ON ble_sessions
  FOR SELECT USING (
    auth.uid() = teacher_id
    OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
  );

-- Any authenticated user can create
CREATE POLICY "ble_sessions_insert" ON ble_sessions
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Teacher updates own sessions, admin updates any
CREATE POLICY "ble_sessions_update" ON ble_sessions
  FOR UPDATE USING (
    auth.uid() = teacher_id
    OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
  );

-- Teachers can delete own sessions, admin can delete any
CREATE POLICY "ble_sessions_delete" ON ble_sessions
  FOR DELETE USING (
    auth.uid() = teacher_id
    OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
  );

-- ─── ble_pending_attendance ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ble_pending_attendance (
  id BIGINT NOT NULL,
  session_id TEXT NOT NULL REFERENCES ble_sessions(id) ON DELETE CASCADE,
  student_id TEXT NOT NULL,
  student_name TEXT NOT NULL,
  time TEXT NOT NULL,
  rssi INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'present', 'rejected', 'disconnected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (id, session_id)
);

ALTER TABLE ble_pending_attendance ENABLE ROW LEVEL SECURITY;

-- Teachers see pending for their sessions, admin sees all, student sees own
CREATE POLICY "ble_pending_select" ON ble_pending_attendance
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM ble_sessions
      WHERE id = session_id AND (
        teacher_id = auth.uid()
        OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
      )
    )
    OR student_id = auth.uid()::text
  );

-- Any authenticated user can insert pending
CREATE POLICY "ble_pending_insert" ON ble_pending_attendance
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Teachers/admins can update
CREATE POLICY "ble_pending_update" ON ble_pending_attendance
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM ble_sessions
      WHERE id = session_id AND (
        teacher_id = auth.uid()
        OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
      )
    )
  );

-- Teachers/admins can delete
CREATE POLICY "ble_pending_delete" ON ble_pending_attendance
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM ble_sessions
      WHERE id = session_id AND (
        teacher_id = auth.uid()
        OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
      )
    )
  );

-- ─── ble_final_attendance ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ble_final_attendance (
  student_id TEXT NOT NULL,
  session_id TEXT NOT NULL REFERENCES ble_sessions(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'present' CHECK (status IN ('present', 'rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (student_id, session_id)
);

ALTER TABLE ble_final_attendance ENABLE ROW LEVEL SECURITY;

-- Teachers see final for their sessions, admin sees all, student sees own
CREATE POLICY "ble_final_select" ON ble_final_attendance
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM ble_sessions
      WHERE id = session_id AND (
        teacher_id = auth.uid()
        OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
      )
    )
    OR student_id = auth.uid()::text
  );

-- Any authenticated user can insert final records
CREATE POLICY "ble_final_insert" ON ble_final_attendance
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- Teachers/admins can update
CREATE POLICY "ble_final_update" ON ble_final_attendance
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM ble_sessions
      WHERE id = session_id AND (
        teacher_id = auth.uid()
        OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
      )
    )
  );

-- Teachers/admins can delete final records
CREATE POLICY "ble_final_delete" ON ble_final_attendance
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM ble_sessions
      WHERE id = session_id AND (
        teacher_id = auth.uid()
        OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
      )
    )
  );

-- ─── Indexes ─────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_ble_sessions_teacher ON ble_sessions(teacher_id);
CREATE INDEX IF NOT EXISTS idx_ble_sessions_status ON ble_sessions(status) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_ble_final_session ON ble_final_attendance(session_id);
CREATE INDEX IF NOT EXISTS idx_ble_final_student ON ble_final_attendance(student_id);
CREATE INDEX IF NOT EXISTS idx_ble_pending_session ON ble_pending_attendance(session_id);
CREATE INDEX IF NOT EXISTS idx_ble_pending_student ON ble_pending_attendance(student_id);
