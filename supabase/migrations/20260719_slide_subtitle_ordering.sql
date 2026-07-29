-- Stable two-level ordering for slide workspace subjects (subtitles).

alter table public.slides
  add column if not exists subtitle_index integer,
  add column if not exists subtitle_slide_index integer;

-- Preserve the existing station/slide order while assigning one order number
-- per subtitle and a local sequence for slides in that subtitle.
with subtitle_groups as (
  select
    station_id,
    lower(trim(coalesce(subtitle, ''))) as subtitle_key,
    min(slide_index) as first_slide_index
  from public.slides
  group by station_id, lower(trim(coalesce(subtitle, '')))
), ranked_groups as (
  select
    station_id,
    subtitle_key,
    dense_rank() over (
      partition by station_id order by first_slide_index, subtitle_key
    ) as new_subtitle_index
  from subtitle_groups
), ordered as (
  select
    slide.id,
    groups.new_subtitle_index,
    row_number() over (
      partition by slide.station_id, lower(trim(coalesce(slide.subtitle, '')))
      order by slide.slide_index, slide.updated_at nulls last, slide.id
    ) as new_subtitle_slide_index
  from public.slides as slide
  join ranked_groups as groups
    on groups.station_id = slide.station_id
   and groups.subtitle_key = lower(trim(coalesce(slide.subtitle, '')))
)
update public.slides as slide
set subtitle_index = ordered.new_subtitle_index,
    subtitle_slide_index = ordered.new_subtitle_slide_index
from ordered
where slide.id = ordered.id
  and (slide.subtitle_index is null or slide.subtitle_slide_index is null);

alter table public.slides
  alter column subtitle_index set default 1,
  alter column subtitle_slide_index set default 1;

update public.slides
set subtitle_index = coalesce(subtitle_index, 1),
    subtitle_slide_index = coalesce(subtitle_slide_index, 1)
where subtitle_index is null or subtitle_slide_index is null;

alter table public.slides
  alter column subtitle_index set not null,
  alter column subtitle_slide_index set not null;

create index if not exists slides_station_subtitle_order_idx
  on public.slides (station_id, subtitle_index, subtitle_slide_index)
  where is_active = true;

create unique index if not exists slides_station_subtitle_slide_order_unique
  on public.slides (station_id, subtitle_index, subtitle_slide_index)
  where is_active = true;

