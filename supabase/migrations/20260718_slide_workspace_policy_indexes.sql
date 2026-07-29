-- Performance hardening for user_slide_workspaces.
-- Adds direct indexes for foreign keys and optimizes auth.uid() use in RLS policies.

create index if not exists user_slide_workspaces_slide_id_idx
  on public.user_slide_workspaces (slide_id);

create index if not exists user_slide_workspaces_station_id_idx
  on public.user_slide_workspaces (station_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = timezone('utc'::text, now());
  return new;
end;
$$;

drop policy if exists "Users can read their own slide workspace" on public.user_slide_workspaces;
create policy "Users can read their own slide workspace"
on public.user_slide_workspaces
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can insert their own slide workspace" on public.user_slide_workspaces;
create policy "Users can insert their own slide workspace"
on public.user_slide_workspaces
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their own slide workspace" on public.user_slide_workspaces;
create policy "Users can update their own slide workspace"
on public.user_slide_workspaces
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete their own slide workspace" on public.user_slide_workspaces;
create policy "Users can delete their own slide workspace"
on public.user_slide_workspaces
for delete
to authenticated
using ((select auth.uid()) = user_id);
