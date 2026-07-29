-- Migration to redesign student workspace layers for extensibility
-- Renames columns and transforms existing stroke arrays to generic layer objects

-- 1. Rename drawing_data to notes_layer
ALTER TABLE public.user_slide_workspaces RENAME COLUMN drawing_data TO notes_layer;

-- 2. Rename exam_drawing_data to exam_layer
ALTER TABLE public.user_slide_workspaces RENAME COLUMN exam_drawing_data TO exam_layer;

-- 3. Change defaults to new layer object format
ALTER TABLE public.user_slide_workspaces ALTER COLUMN notes_layer SET DEFAULT '{"objects": []}'::jsonb;
ALTER TABLE public.user_slide_workspaces ALTER COLUMN exam_layer SET DEFAULT '{"objects": []}'::jsonb;

-- 4. Convert existing notes_layer arrays to the new layer format with type: stroke
UPDATE public.user_slide_workspaces
SET notes_layer = jsonb_build_object(
  'objects',
  COALESCE(
    (
      SELECT jsonb_agg(elem || '{"type": "stroke"}'::jsonb)
      FROM jsonb_array_elements(notes_layer) AS elem
    ),
    '[]'::jsonb
  )
)
WHERE jsonb_typeof(notes_layer) = 'array';

-- 5. Convert existing exam_layer arrays to the new layer format with type: stroke
UPDATE public.user_slide_workspaces
SET exam_layer = jsonb_build_object(
  'objects',
  COALESCE(
    (
      SELECT jsonb_agg(elem || '{"type": "stroke"}'::jsonb)
      FROM jsonb_array_elements(exam_layer) AS elem
    ),
    '[]'::jsonb
  )
)
WHERE jsonb_typeof(exam_layer) = 'array';

-- 6. If any exam_layer is NULL, set it to the default
UPDATE public.user_slide_workspaces
SET exam_layer = '{"objects": []}'::jsonb
WHERE exam_layer IS NULL;
