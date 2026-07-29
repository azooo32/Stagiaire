-- Slide Workspace production schema for Stagiaire.
-- Official slide content stays in public.slides and is managed by owner/admin/manager.
-- Student-owned drawing, writing, markers, and progress stay in public.user_slide_workspaces.

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc'::text, now());
  return new;
end;
$$;

alter table public.slides
  add column if not exists questions jsonb not null default '[]'::jsonb,
  add column if not exists answers jsonb not null default '[]'::jsonb,
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists is_active boolean not null default true,
  add column if not exists updated_at timestamptz not null default timezone('utc'::text, now());

create index if not exists slides_station_index_idx
  on public.slides (station_id, slide_index);

create index if not exists slides_active_station_index_idx
  on public.slides (station_id, slide_index)
  where is_active = true;

drop trigger if exists set_slides_updated_at on public.slides;
create trigger set_slides_updated_at
before update on public.slides
for each row execute function public.set_updated_at();

create table if not exists public.user_slide_workspaces (
  user_id uuid not null references public.users(id) on delete cascade,
  slide_id uuid not null references public.slides(id) on delete cascade,
  station_id uuid not null references public.slide_stations(id) on delete cascade,
  drawing_data jsonb not null default '[]'::jsonb,
  text_annotations jsonb not null default '[]'::jsonb,
  marker_data jsonb not null default '{}'::jsonb,
  progress_data jsonb not null default '{}'::jsonb,
  is_bookmarked boolean not null default false,
  last_opened_at timestamptz,
  pending_sync_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc'::text, now()),
  updated_at timestamptz not null default timezone('utc'::text, now()),
  primary key (user_id, slide_id)
);

create index if not exists user_slide_workspaces_user_station_idx
  on public.user_slide_workspaces (user_id, station_id);

create index if not exists user_slide_workspaces_updated_at_idx
  on public.user_slide_workspaces (updated_at);

create index if not exists user_slide_workspaces_bookmarked_idx
  on public.user_slide_workspaces (user_id, is_bookmarked)
  where is_bookmarked = true;

drop trigger if exists set_user_slide_workspaces_updated_at on public.user_slide_workspaces;
create trigger set_user_slide_workspaces_updated_at
before update on public.user_slide_workspaces
for each row execute function public.set_updated_at();

alter table public.user_slide_workspaces enable row level security;

drop policy if exists "Users can read their own slide workspace" on public.user_slide_workspaces;
create policy "Users can read their own slide workspace"
on public.user_slide_workspaces
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users can insert their own slide workspace" on public.user_slide_workspaces;
create policy "Users can insert their own slide workspace"
on public.user_slide_workspaces
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can update their own slide workspace" on public.user_slide_workspaces;
create policy "Users can update their own slide workspace"
on public.user_slide_workspaces
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own slide workspace" on public.user_slide_workspaces;
create policy "Users can delete their own slide workspace"
on public.user_slide_workspaces
for delete
to authenticated
using (auth.uid() = user_id);
