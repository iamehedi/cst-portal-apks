-- Make the notice-push-notification trigger non-blocking
-- Wraps the edge function call in a try-catch so a notification failure
-- doesn't roll back the notice INSERT.

CREATE OR REPLACE FUNCTION public.handle_notice_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  BEGIN
    PERFORM supabase_functions.http_request(
      'https://cqtbntuyornjwqqzwrdy.supabase.co/functions/v1/send-notice-notification',
      'POST',
      '{"Content-type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNxdGJudHV5b3JuandxcXp3cmR5Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTE2MDY1MCwiZXhwIjoyMDk0NzM2NjUwfQ.JK3weHvnp7eXaqowwLY2Myf8Z2zk6qw45UXtEslUeDs"}',
      '{}',
      '5000'
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Notice notification failed for notice %: %', NEW.id, SQLERRM;
  END;
  RETURN NEW;
END;
$$;

-- Replace the trigger to use the new non-blocking function
DROP TRIGGER IF EXISTS "notice-push-notification" ON public.notices;
CREATE TRIGGER "notice-push-notification" AFTER INSERT ON public.notices
  FOR EACH ROW EXECUTE FUNCTION public.handle_notice_notification();
