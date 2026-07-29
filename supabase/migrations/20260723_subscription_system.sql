-- View for accessible scientific subjects
CREATE OR REPLACE VIEW public.accessible_subjects AS
SELECT 
  s.id AS subject_id,
  u.id AS user_id
FROM public.subjects s
CROSS JOIN public.users u
WHERE 
  u.id = auth.uid()
  AND (
    u.role IN ('admin', 'owner', 'manager')
    OR 
    EXISTS (
      SELECT 1 FROM public.user_subscriptions us
      WHERE us.user_id = u.id 
        AND us.subject_id = s.id 
        AND us.status = 'active'
        AND (us.expires_at IS NULL OR us.expires_at > NOW())
    )
    OR
    EXISTS (
      SELECT 1 FROM public.university_access ua
      WHERE ua.university = u.university 
        AND ua.status = 'active'
        AND (ua.expires_at IS NULL OR ua.expires_at > NOW())
        AND (ua.subject_id = s.id OR ua.all_scientific = true)
    )
  );

-- View for accessible clinical (practical) subjects
CREATE OR REPLACE VIEW public.accessible_clinical_subjects AS
SELECT 
  cs.id AS clinical_subject_id,
  u.id AS user_id
FROM public.clinical_subjects cs
CROSS JOIN public.users u
WHERE 
  u.id = auth.uid()
  AND (
    u.role IN ('admin', 'owner', 'manager')
    OR 
    EXISTS (
      SELECT 1 FROM public.user_subscriptions us
      WHERE us.user_id = u.id 
        AND us.clinical_subject_id = cs.id 
        AND us.status = 'active'
        AND (us.expires_at IS NULL OR us.expires_at > NOW())
    )
    OR
    EXISTS (
      SELECT 1 FROM public.university_access ua
      WHERE ua.university = u.university 
        AND ua.status = 'active'
        AND (ua.expires_at IS NULL OR ua.expires_at > NOW())
        AND (ua.clinical_subject_id = cs.id OR ua.all_practical = true)
    )
  );
