-- Enable Row Level Security (RLS) on both tables
ALTER TABLE public.user_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.university_access ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS "Owners can do everything on user_subscriptions" ON public.user_subscriptions;
DROP POLICY IF EXISTS "Users can read their own subscriptions" ON public.user_subscriptions;
DROP POLICY IF EXISTS "Owners can do everything on university_access" ON public.university_access;
DROP POLICY IF EXISTS "Users can read their university access" ON public.university_access;

-- 1. Policies for user_subscriptions (Owner-Only Mutation and Read)
CREATE POLICY "Owners can do everything on user_subscriptions"
ON public.user_subscriptions
FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE users.id = auth.uid()
      AND lower(trim(users.role::text)) = 'owner'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE users.id = auth.uid()
      AND lower(trim(users.role::text)) = 'owner'
  )
);

CREATE POLICY "Users can read their own subscriptions"
ON public.user_subscriptions
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
);

-- 2. Policies for university_access (Owner-Only Mutation and Read)
CREATE POLICY "Owners can do everything on university_access"
ON public.university_access
FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE users.id = auth.uid()
      AND lower(trim(users.role::text)) = 'owner'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE users.id = auth.uid()
      AND lower(trim(users.role::text)) = 'owner'
  )
);

CREATE POLICY "Users can read their university access"
ON public.university_access
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users
    WHERE users.id = auth.uid()
      AND users.university = university
  )
);
