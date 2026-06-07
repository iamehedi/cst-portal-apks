-- Enable Realtime for notes and notices tables
-- so that changes (insert/update/delete) propagate instantly
-- to subscribed clients via supabase_flutter's .stream()

do $$
begin
  -- Add notes if not already a member
  begin
    alter publication supabase_realtime add table notes;
  exception
    when sqlstate '42710' then
      -- table is already a member, ignore
  end;

  -- Add notices if not already a member
  begin
    alter publication supabase_realtime add table notices;
  exception
    when sqlstate '42710' then
      -- table is already a member, ignore
  end;
end;
$$;
