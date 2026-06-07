-- Add class_date and class_time columns to attendance_sessions
-- Run via: supabase db query --linked < this_file.sql

ALTER TABLE attendance_sessions
  ADD COLUMN IF NOT EXISTS class_date DATE,
  ADD COLUMN IF NOT EXISTS class_time TIME;

-- Verify
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'attendance_sessions'
  AND column_name IN ('class_date', 'class_time');
