-- Migration: Fix Users RLS policies and allow students, admins, and owners to update stage safely
-- Fixes "infinite recursion detected in policy for relation users" (ERROR 42P17)
-- and "more than one row returned by a subquery used as an expression" (ERROR 21000)

-- 1. Helper functions with SECURITY DEFINER to avoid RLS recursion
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 
        FROM users 
        WHERE id = auth.uid() 
        AND role = 'admin'
    );
$$;

CREATE OR REPLACE FUNCTION public.is_admin_or_owner()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 
        FROM users 
        WHERE id = auth.uid() 
        AND role IN ('admin', 'owner')
    );
$$;

-- 2. Drop problematic policies
DROP POLICY IF EXISTS "Admin can update non-owner users" ON users;
DROP POLICY IF EXISTS "Users can update own personal data" ON users;
DROP POLICY IF EXISTS "Users can view own data" ON users;

-- 3. SELECT Policy: Users can view their own data, Admins and Owners can view all users
CREATE POLICY "Users can view own data or admin/owner can view all" ON users
FOR SELECT TO authenticated
USING (
    (auth.uid() = id) OR is_admin_or_owner()
);

-- 4. UPDATE Policy for Admin: Admin can update non-owner users
CREATE POLICY "Admin can update non-owner users" ON users
FOR UPDATE TO authenticated
USING (
    is_admin() AND role <> 'owner'
)
WITH CHECK (
    is_admin() AND role <> 'owner'
);

-- 5. UPDATE Policy for Users: Students/Users can update their own profile
CREATE POLICY "Users can update own profile" ON users
FOR UPDATE TO authenticated
USING (
    auth.uid() = id
)
WITH CHECK (
    auth.uid() = id
);

-- 6. Trigger to prevent non-admins from modifying sensitive columns (role, status, email)
CREATE OR REPLACE FUNCTION public.protect_user_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT is_admin_or_owner() THEN
        IF NEW.role IS DISTINCT FROM OLD.role THEN
            RAISE EXCEPTION 'You are not allowed to change your role';
        END IF;
        IF NEW.status IS DISTINCT FROM OLD.status THEN
            RAISE EXCEPTION 'You are not allowed to change your status';
        END IF;
        IF NEW.email IS DISTINCT FROM OLD.email THEN
            RAISE EXCEPTION 'You are not allowed to change your email';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_protect_user_fields ON users;
CREATE TRIGGER trigger_protect_user_fields
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION protect_user_fields();
