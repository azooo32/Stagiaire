-- Migration: Create app_updates table and storage bucket
CREATE TABLE IF NOT EXISTS public.app_updates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version_code INT NOT NULL,
    version_name TEXT NOT NULL,
    apk_url TEXT NOT NULL,
    release_notes TEXT DEFAULT '',
    is_forced BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.app_updates ENABLE ROW LEVEL SECURITY;

-- Allow public read for app_updates
DROP POLICY IF EXISTS "Allow public read for app_updates" ON public.app_updates;
CREATE POLICY "Allow public read for app_updates" ON public.app_updates
    FOR SELECT
    USING (true);

-- Allow authenticated admins / service role full access
DROP POLICY IF EXISTS "Allow admin modify app_updates" ON public.app_updates;
CREATE POLICY "Allow admin modify app_updates" ON public.app_updates
    FOR ALL
    USING (auth.role() = 'service_role' OR (auth.jwt() ->> 'role') = 'admin');

-- Bucket configuration
INSERT INTO storage.buckets (id, name, public)
VALUES ('app-updates', 'app-updates', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Policy to allow public downloads
DROP POLICY IF EXISTS "Allow public read app-updates" ON storage.objects;
CREATE POLICY "Allow public read app-updates" ON storage.objects
    FOR SELECT
    USING (bucket_id = 'app-updates');
