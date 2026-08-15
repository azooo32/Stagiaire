-- 1. Extend slide_stations to support PDF type
ALTER TABLE public.slide_stations 
  ADD COLUMN IF NOT EXISTS station_type text NOT NULL DEFAULT 'slides' CHECK (station_type IN ('slides', 'pdf'));

-- 2. Extend slides table to support PDF URLs
ALTER TABLE public.slides
  ADD COLUMN IF NOT EXISTS pdf_url text;

-- 3. Create user_pdf_workspaces table for page-by-page PDF annotations
CREATE TABLE IF NOT EXISTS public.user_pdf_workspaces (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE cascade,
  pdf_id uuid NOT NULL REFERENCES public.slides(id) ON DELETE cascade, -- references slides.id representing the PDF document
  station_id uuid NOT NULL REFERENCES public.slide_stations(id) ON DELETE cascade,
  annotations jsonb NOT NULL DEFAULT '{}'::jsonb, -- e.g., { "page_1": { "objects": [...] }, "page_2": { "objects": [...] } }
  last_opened_page int NOT NULL DEFAULT 1,
  last_opened_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
  created_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
  updated_at timestamptz NOT NULL DEFAULT timezone('utc'::text, now()),
  PRIMARY KEY (user_id, pdf_id)
);

-- 4. Enable RLS and setup policies
ALTER TABLE public.user_pdf_workspaces ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read their own PDF workspace" ON public.user_pdf_workspaces;
CREATE POLICY "Users can read their own PDF workspace"
  ON public.user_pdf_workspaces FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert their own PDF workspace" ON public.user_pdf_workspaces;
CREATE POLICY "Users can insert their own PDF workspace"
  ON public.user_pdf_workspaces FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own PDF workspace" ON public.user_pdf_workspaces;
CREATE POLICY "Users can update their own PDF workspace"
  ON public.user_pdf_workspaces FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete their own PDF workspace" ON public.user_pdf_workspaces;
CREATE POLICY "Users can delete their own PDF workspace"
  ON public.user_pdf_workspaces FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

-- 5. Setup updated_at trigger
DROP TRIGGER IF EXISTS set_user_pdf_workspaces_updated_at ON public.user_pdf_workspaces;
CREATE TRIGGER set_user_pdf_workspaces_updated_at
  BEFORE UPDATE ON public.user_pdf_workspaces
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
