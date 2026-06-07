-- College Off-Days Management
-- Stores date ranges when the college is closed (holidays, breaks, etc.)
-- Students can still view routines but reminders are suppressed.

CREATE TABLE IF NOT EXISTS college_off_days (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  reason TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT valid_dates CHECK (end_date >= start_date)
);

ALTER TABLE college_off_days ENABLE ROW LEVEL SECURITY;

-- Everyone authenticated can view off days
CREATE POLICY "off_days_select" ON college_off_days
  FOR SELECT USING (auth.role() = 'authenticated');

-- Only admin can insert/update/delete
CREATE POLICY "off_days_insert" ON college_off_days
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
  );

CREATE POLICY "off_days_update" ON college_off_days
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
  );

CREATE POLICY "off_days_delete" ON college_off_days
  FOR DELETE USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
  );

-- Enable realtime so updates propagate instantly
ALTER PUBLICATION supabase_realtime ADD TABLE college_off_days;
