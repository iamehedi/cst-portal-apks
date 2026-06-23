-- Unify BLE Attendance with attendance_records
-- Allows 'ble' method in attendance_records so BLE attendance
-- is stored alongside QR and manual records.

-- ─── attendance_records: allow 'ble' method ──────────────────────────────────
ALTER TABLE attendance_records DROP CONSTRAINT IF EXISTS attendance_records_method_check;
ALTER TABLE attendance_records ADD CONSTRAINT attendance_records_method_check
  CHECK (method IN ('qr', 'manual', 'ble'));

-- ─── attendance_records: prevent duplicate (session_id, student_id) ──────────
-- This enables safe upserts from BLE sync without creating duplicate rows.
-- Clean up any existing orphans first.
DELETE FROM attendance_records WHERE id IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (
      PARTITION BY session_id, student_id ORDER BY marked_at DESC
    ) AS rn
    FROM attendance_records
  ) dup WHERE dup.rn > 1
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_records_session_student
  ON attendance_records(session_id, student_id);
