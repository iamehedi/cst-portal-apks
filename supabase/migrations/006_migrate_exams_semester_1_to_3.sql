-- Migrate exam routines stored as 1st semester to 3rd semester
-- The user is in 3rd semester but exam data was saved with semester=1

UPDATE public.exams
SET semester = 3
WHERE semester = 1;

-- Verify the migration
SELECT semester, COUNT(*) as count
FROM public.exams
GROUP BY semester
ORDER BY semester;
