-- Migration: 20260905_pdf_lecture_recordings.sql
-- Create pdf_lecture_recordings table for synchronized lecture audio recordings on PDF documents

CREATE TABLE IF NOT EXISTS public.pdf_lecture_recordings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pdf_id uuid NOT NULL REFERENCES public.slides(id) ON DELETE cascade,
  station_id uuid NOT NULL REFERENCES public.slide_stations(id) ON DELETE cascade,
  audio_url text NOT NULL,
  duration_ms integer NOT NULL DEFAULT 0,
  page_number integer NOT NULL DEFAULT 1,
  position_x double precision NOT NULL DEFAULT 0.0,
  position_y double precision NOT NULL DEFAULT 0.0,
  strokes_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  pointer_events jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_by uuid REFERENCES public.users(id) ON DELETE set null,
  created_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_pdf_lecture_recordings_pdf_id 
  ON public.pdf_lecture_recordings(pdf_id);

ALTER TABLE public.pdf_lecture_recordings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "All authenticated users can read lecture recordings" ON public.pdf_lecture_recordings;
CREATE POLICY "All authenticated users can read lecture recordings"
  ON public.pdf_lecture_recordings FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Managers can insert lecture recordings" ON public.pdf_lecture_recordings;
CREATE POLICY "Managers can insert lecture recordings"
  ON public.pdf_lecture_recordings FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND lower(trim(users.role::text)) = ANY (ARRAY['admin', 'owner', 'manager'])
    )
  );

DROP POLICY IF EXISTS "Managers can update lecture recordings" ON public.pdf_lecture_recordings;
CREATE POLICY "Managers can update lecture recordings"
  ON public.pdf_lecture_recordings FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND lower(trim(users.role::text)) = ANY (ARRAY['admin', 'owner', 'manager'])
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND lower(trim(users.role::text)) = ANY (ARRAY['admin', 'owner', 'manager'])
    )
  );

DROP POLICY IF EXISTS "Managers can delete lecture recordings" ON public.pdf_lecture_recordings;
CREATE POLICY "Managers can delete lecture recordings"
  ON public.pdf_lecture_recordings FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND lower(trim(users.role::text)) = ANY (ARRAY['admin', 'owner', 'manager'])
    )
  );

DROP TRIGGER IF EXISTS set_pdf_lecture_recordings_updated_at ON public.pdf_lecture_recordings;
CREATE TRIGGER set_pdf_lecture_recordings_updated_at
  BEFORE UPDATE ON public.pdf_lecture_recordings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
