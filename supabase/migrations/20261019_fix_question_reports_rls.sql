-- Fix question_reports Row Level Security (RLS) policies
-- Enables:
-- 1. Students can view their own reports and admin replies
-- 2. Admins/owners/managers can update reports (send replies)
-- 3. Students can update their own reports (mark notifications as read)

-- 1. Allow students to SELECT their own reports
DROP POLICY IF EXISTS "Allow users to select their own reports" ON public.question_reports;
CREATE POLICY "Allow users to select their own reports"
ON public.question_reports
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
);

-- 2. Allow admins/owners/managers to UPDATE reports (send replies, change status)
DROP POLICY IF EXISTS "Allow admins/owners/managers to update reports" ON public.question_reports;
CREATE POLICY "Allow admins/owners/managers to update reports"
ON public.question_reports
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE users.id = auth.uid()
      AND lower(trim(users.role::text)) IN ('owner', 'admin', 'manager')
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE users.id = auth.uid()
      AND lower(trim(users.role::text)) IN ('owner', 'admin', 'manager')
  )
);

-- 3. Allow students to UPDATE their own reports (mark as read)
DROP POLICY IF EXISTS "Allow users to mark their own reports as read" ON public.question_reports;
CREATE POLICY "Allow users to mark their own reports as read"
ON public.question_reports
FOR UPDATE
TO authenticated
USING (
  user_id = auth.uid()
)
WITH CHECK (
  user_id = auth.uid()
);
