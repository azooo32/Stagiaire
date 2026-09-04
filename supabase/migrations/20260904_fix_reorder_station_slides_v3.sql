-- Fix reorder_station_slides v3:
-- 1. Use pg_advisory_xact_lock to prevent race conditions during rapid reordering.
-- 2. Phase 1: assign temporary unique negative indexes ORDERED BY slide_index ASC,
--    preserving the exact intended sequence of slides instead of random order.
-- 3. Phase 2: sequentially derive clean slide_index, subtitle_index, and subtitle_slide_index
--    preserving the relative order of slides and subtitles.

CREATE OR REPLACE FUNCTION public.reorder_station_slides(p_station_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  -- 1. Acquire transaction advisory lock for this specific station
  PERFORM pg_advisory_xact_lock(hashtext(p_station_id::text));

  SET CONSTRAINTS slides_station_id_slide_index_key DEFERRED;

  -- 2. Phase 1: assign temporary unique negative indexes ordered by current slide_index
  WITH numbered AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY slide_index ASC, id ASC) as temp_rn
    FROM slides
    WHERE station_id = p_station_id AND is_active = true
  )
  UPDATE slides s
  SET slide_index = -n.temp_rn
  FROM numbered n
  WHERE s.id = n.id;

  -- 3. Phase 2: compute clean sequential values ordered by preserved slide sequence
  WITH ordered AS (
    SELECT
      id,
      ROW_NUMBER() OVER (ORDER BY -slide_index ASC, id ASC)::int AS new_slide_index,
      lower(trim(coalesce(subtitle, ''))) AS subtitle_key
    FROM slides
    WHERE station_id = p_station_id AND is_active = true
  ),
  subtitle_first_positions AS (
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
