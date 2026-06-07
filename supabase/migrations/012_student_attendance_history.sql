-- Student Attendance History
-- SECURITY DEFINER RPC so students can view their own attendance records with session info
-- without needing direct SELECT on attendance_sessions (which is teacher/admin only)

CREATE OR REPLACE FUNCTION public.get_student_attendance(p_student_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id UUID;
  v_result JSONB;
BEGIN
  -- Only allow the authenticated user to query their own attendance
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('error', 'Not authenticated');
  END IF;

  WITH student_records AS (
    SELECT
      ar.id,
      ar.student_id,
      ar.student_name,
      ar.method,
      ar.marked_at,
      as2.subject,
      as2.semester,
      as2.department,
      as2.class_date,
      as2.class_time
    FROM public.attendance_records ar
    JOIN public.attendance_sessions as2 ON ar.session_id = as2.id
    WHERE ar.student_id = p_student_id
      AND ar.marked_by = v_user_id
    ORDER BY ar.marked_at DESC
  ),
  subject_totals AS (
    SELECT
      subject,
      semester,
      COUNT(*) AS total_sessions
    FROM public.attendance_sessions
    GROUP BY subject, semester
  ),
  subject_stats AS (
    SELECT
      sr.subject,
      sr.semester,
      sr.department,
      COUNT(*) AS attended,
      COALESCE(st.total_sessions, 0) AS total_sessions,
      ROUND((COUNT(*)::numeric / NULLIF(st.total_sessions, 0) * 100))::int AS percentage
    FROM student_records sr
    LEFT JOIN subject_totals st USING (subject, semester)
    GROUP BY sr.subject, sr.semester, sr.department, st.total_sessions
    ORDER BY sr.subject
  )
  SELECT jsonb_build_object(
    'records', COALESCE((SELECT jsonb_agg(row_to_json(sr.*)) FROM student_records sr), '[]'::jsonb),
    'stats', COALESCE((SELECT jsonb_agg(row_to_json(ss.*)) FROM subject_stats ss), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;
