-- General Events Table
-- Stores college-wide events like seminars, workshops, cultural events, meetings, etc.
-- Separate from off-days (holidays) and exams for clarity.

CREATE TABLE IF NOT EXISTS events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  event_date DATE NOT NULL,
  event_time TEXT DEFAULT '',
  location TEXT DEFAULT '',
  event_type TEXT NOT NULL DEFAULT 'General',
  created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE events ENABLE ROW LEVEL SECURITY;

-- Everyone authenticated can view events
CREATE POLICY "events_select" ON events
  FOR SELECT USING (auth.role() = 'authenticated');

-- Only admin and teachers can insert/update/delete
CREATE POLICY "events_insert" ON events
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND (is_admin = true OR role = 'teacher'))
  );

CREATE POLICY "events_update" ON events
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND (is_admin = true OR role = 'teacher'))
  );

CREATE POLICY "events_delete" ON events
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND (is_admin = true OR role = 'teacher'))
  );

-- Enable realtime so updates propagate instantly
ALTER PUBLICATION supabase_realtime ADD TABLE events;
