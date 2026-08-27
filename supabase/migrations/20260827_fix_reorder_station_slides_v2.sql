-- Fix reorder_station_slides: use new_slide_index (not raw slide_index) when computing
-- subtitle_slide_index so slides within the same subtitle group retain the
-- order imposed by slide_index after the +10M phase-1 shift.

CREATE OR REPLACE FUNCTION public.reorder_station_slides(p_station_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  SET CONSTRAINTS slides_station_id_slide_index_key DEFERRED;

  -- Phase 1: move all active slides to a safe temp range to avoid unique-constraint
  -- collisions while we reassign indexes in phase 2.
  UPDATE slides
  SET slide_index          = slide_index + 10000000,
      subtitle_index       = subtitle_index + 10000000,
      subtitle_slide_index = subtitle_slide_index + 10000000
  WHERE station_id = p_station_id AND is_active = true;

  -- Phase 2: compute clean sequential values and apply them.
  --
  -- NOTE: All CTEs below operate on the +10M-shifted rows that were just written.
  -- We derive the logical order from slide_index (which still reflects the
  -- correct insertion position) and then recalculate subtitle_index and
  -- subtitle_slide_index from scratch so they are always consistent.
  WITH ordered AS (
    SELECT
      id,
      -- Global sequential order across the whole station (1, 2, 3...)
      ROW_NUMBER() OVER (ORDER BY slide_index, id)::int  AS new_slide_index,
      lower(trim(coalesce(subtitle, '')))                AS subtitle_key
    FROM slides
    WHERE station_id = p_station_id AND is_active = true
  ),
  subtitle_first_positions AS (
    -- Find the earliest global position for each subtitle group.
    -- Using new_slide_index (not the raw +10M slide_index) gives a clean
    -- 1-based position regardless of how large slide_index grew.
    SELECT
      subtitle_key,
      MIN(new_slide_index) AS first_position
    FROM ordered
    GROUP BY subtitle_key
  ),
  ranked_subtitles AS (
    SELECT
      subtitle_key,
      DENSE_RANK() OVER (ORDER BY first_position, subtitle_key)::int AS new_subtitle_index
    FROM subtitle_first_positions
  ),
  final_ordered AS (
    SELECT
      o.id,
      o.new_slide_index,
      r.new_subtitle_index,
      -- Per-subtitle sequential index ordered by the global slide position.
      -- Using new_slide_index (1-based) makes this deterministic and correct.
      ROW_NUMBER() OVER (
        PARTITION BY o.subtitle_key
        ORDER BY o.new_slide_index, o.id
      )::int AS new_subtitle_slide_index
    FROM ordered o
    JOIN ranked_subtitles r ON o.subtitle_key = r.subtitle_key
  )
  UPDATE slides s
  SET
    slide_index          = f.new_slide_index,
    subtitle_index       = f.new_subtitle_index,
    subtitle_slide_index = f.new_subtitle_slide_index
  FROM final_ordered f
  WHERE s.id = f.id;
END;
$function$;
