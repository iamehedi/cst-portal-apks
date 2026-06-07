-- Enable Realtime for all remaining tables that use .stream() in the Dart code
-- but are not yet members of the supabase_realtime publication.
--
-- Already enabled: notices, notes, college_off_days, events
-- Now enabling: students, class_routine_slots, teachers, exams,
--              profiles, attendance_sessions, attendance_records

do $$
begin
  -- students (StudentsScreen live list)
  begin
    alter publication supabase_realtime add table students;
  exception when sqlstate '42710' then end;

  -- class_routine_slots (RoutineScreen live updates)
  begin
    alter publication supabase_realtime add table class_routine_slots;
  exception when sqlstate '42710' then end;

  -- teachers (TeachersScreen live list)
  begin
    alter publication supabase_realtime add table teachers;
  exception when sqlstate '42710' then end;

  -- exams (ExamRoutineScreen live updates)
  begin
    alter publication supabase_realtime add table exams;
  exception when sqlstate '42710' then end;

  -- profiles (pending approvals streaming to admin, approved profiles to StudentsScreen)
  begin
    alter publication supabase_realtime add table profiles;
  exception when sqlstate '42710' then end;

  -- attendance_sessions (live session tracking for teacher & students)
  begin
    alter publication supabase_realtime add table attendance_sessions;
  exception when sqlstate '42710' then end;

  -- attendance_records (live count during attendance marking)
  begin
    alter publication supabase_realtime add table attendance_records;
  exception when sqlstate '42710' then end;
end;
$$;
