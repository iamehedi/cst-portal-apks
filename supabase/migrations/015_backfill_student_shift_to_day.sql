-- Backfill: set shift to 'Day' for all existing students who have
-- NULL or 'Morning' shift. This matches the new frontend default.

UPDATE profiles SET shift = 'Day'
WHERE role = 'student' AND (shift IS NULL OR shift = 'Morning');

UPDATE students SET shift = 'Day'
WHERE shift IS NULL OR shift = 'Morning';
