-- ============================================================
-- Migration: subject_stage_question_counts
-- Purpose  : Add a JSONB column `stage_question_counts` to the
--            `subjects` table that is kept in sync automatically
--            via a trigger on the `questions` table.
--
-- Structure of the JSON value (keyed by "<university>|<stage>"):
--   {
--     "كلية طب نينوى|المرحلة الخامسة": 120,
--     "كلية طب بغداد|المرحلة السادسة":  85,
--     "|المرحلة الخامسة": 45,   -- no university filter
--     "كلية طب نينوى|": 200,   -- no stage filter
--     "|": 350                   -- global (no university, no stage)
--   }
--
-- The Home screen / AppProvider reads this column to get the
-- exact count for a student based on their (university, stage).
-- ============================================================


-- ── 1. Add the column ────────────────────────────────────────
ALTER TABLE public.subjects
  ADD COLUMN IF NOT EXISTS stage_question_counts JSONB NOT NULL DEFAULT '{}';


-- ── 2. Function that rebuilds counts for ONE subject ─────────
CREATE OR REPLACE FUNCTION public.rebuild_subject_stage_counts(p_subject_name TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_counts   JSONB := '{}';
  v_row      RECORD;
  v_key      TEXT;
  v_cur_val  BIGINT;
BEGIN
  -- Aggregate question counts grouped by (university, stage)
  FOR v_row IN
    SELECT
      COALESCE(TRIM(university), '') AS univ,
      COALESCE(TRIM(stage),      '') AS stg,
      COUNT(*)                        AS cnt
    FROM public.questions
    WHERE
      subject       = p_subject_name
      AND (is_deleted IS NULL OR is_deleted = FALSE)
    GROUP BY COALESCE(TRIM(university), ''), COALESCE(TRIM(stage), '')
  LOOP
    v_key     := v_row.univ || '|' || v_row.stg;
    v_cur_val := COALESCE((v_counts ->> v_key)::BIGINT, 0);
    v_counts  := jsonb_set(v_counts, ARRAY[v_key], to_jsonb(v_cur_val + v_row.cnt));
  END LOOP;

  UPDATE public.subjects
    SET stage_question_counts = v_counts
  WHERE name = p_subject_name;
END;
$$;


-- ── 3. Trigger function called on questions INSERT/UPDATE/DELETE ──
CREATE OR REPLACE FUNCTION public.trg_sync_subject_stage_counts()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_affected_subject TEXT;
BEGIN
  -- Determine which subject name was affected
  IF (TG_OP = 'DELETE') THEN
    v_affected_subject := OLD.subject;
  ELSE
    v_affected_subject := NEW.subject;
  END IF;

  -- Skip if no subject
  IF v_affected_subject IS NULL OR TRIM(v_affected_subject) = '' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Rebuild counts for that subject
  PERFORM public.rebuild_subject_stage_counts(TRIM(v_affected_subject));

  RETURN COALESCE(NEW, OLD);
END;
$$;


-- ── 4. Attach trigger to questions table ─────────────────────
DROP TRIGGER IF EXISTS trg_sync_subject_stage_counts ON public.questions;
CREATE TRIGGER trg_sync_subject_stage_counts
  AFTER INSERT OR UPDATE OR DELETE
  ON public.questions
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_sync_subject_stage_counts();


-- ── 5. Back-fill existing subjects ───────────────────────────
DO $$
DECLARE
  v_name TEXT;
BEGIN
  FOR v_name IN
    SELECT DISTINCT name FROM public.subjects WHERE name IS NOT NULL
  LOOP
    PERFORM public.rebuild_subject_stage_counts(v_name);
  END LOOP;
END;
$$;
