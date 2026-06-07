-- Add a simpler SELECT policy on profiles for authenticated users.
-- The existing policies rely on custom functions (is_admin(), get_my_profile_is_admin())
-- which Supabase Realtime subscriptions cannot properly evaluate, causing
-- RealtimeSubscribeException(channelError) on any .stream() on the profiles table.
--
-- This policy allows any authenticated user to SELECT all rows in the profiles table.
-- The app already controls visibility at the UI layer (admin/teacher-only screens).
-- The role='student' filter is applied at the query level in .eq('role', 'student').

do $$
begin
  begin
    create policy "profiles_select_authenticated_all"
      on public.profiles
      for select
      to authenticated
      using (true);
  exception
    when sqlstate '42710' then
      -- policy already exists, ignore
  end;
end;
$$;
