-- Update reorder_station_slides to order subtitle groups by appearance order (min slide_index) instead of alphabetically.

CREATE OR REPLACE FUNCTION public.reorder_station_slides(p_station_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  SET CONSTRAINTS slides_station_id_slide_index_key DEFERRED;

  -- Phase 1: move all active slides to a safe temp range
  UPDATE slides
  SET slide_index          = slide_index + 10000000,
      subtitle_index       = subtitle_index + 10000000,
      subtitle_slide_index = subtitle_slide_index + 10000000
  WHERE station_id = p_station_id AND is_active = true;

  -- Phase 2: assign final clean sequential values
  WITH ordered AS (
    SELECT
      id,
      ROW_NUMBER() OVER (ORDER BY slide_index, id)::int                                    AS new_slide_index,
      lower(trim(coalesce(subtitle,'')))                                                   AS subtitle_key,
      slide_index
    FROM slides
    WHERE station_id = p_station_id AND is_active = true
  ),
  subtitle_mins AS (
    SELECT
      subtitle_key,
      MIN(slide_index) AS min_slide_index
    FROM ordered
    GROUP BY subtitle_key
  ),
  ranked_subtitles AS (
    SELECT
      subtitle_key,
      DENSE_RANK() OVER (ORDER BY min_slide_index, subtitle_key)::int AS new_subtitle_index
    FROM subtitle_mins
  ),
  final_ordered AS (
    SELECT
      o.id,
      o.new_slide_index,
      r.new_subtitle_index,
      ROW_NUMBER() OVER (PARTITION BY o.subtitle_key ORDER BY o.slide_index, o.id)::int AS new_subtitle_slide_index
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
