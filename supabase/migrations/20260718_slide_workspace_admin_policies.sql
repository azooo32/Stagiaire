-- Enables real slide content management for admins/managers/owners.
-- Official slide records live in public.slides; per-user drawings stay in public.user_slide_workspaces.

alter table public.users
  drop constraint if exists users_role_check;

alter table public.users
  add constraint users_role_check
  check (role::text = any (array['owner'::varchar::text, 'admin'::varchar::text, 'manager'::varchar::text, 'student'::varchar::text]));
alter table public.slides
  add column if not exists title text not null default 'Untitled Slide',
  add column if not exists subtitle text not null default '',
  add column if not exists image_url text,
  add column if not exists is_active boolean not null default true,
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists questions jsonb not null default '[]'::jsonb,
  add column if not exists answers jsonb not null default '[]'::jsonb,
  add column if not exists updated_at timestamptz not null default timezone('utc'::text, now());

alter table public.slides enable row level security;

drop policy if exists "Authenticated users can read active slides" on public.slides;
create policy "Authenticated users can read active slides"
on public.slides
for select
to authenticated
using (is_active = true);

drop policy if exists "Managers can insert slides" on public.slides;
create policy "Managers can insert slides"
on public.slides
for insert
to authenticated
with check (
  exists (
    select 1 from public.users
    where users.id = (select auth.uid())
      and lower(trim(users.role::text)) in ('admin', 'owner', 'manager')
  )
);

drop policy if exists "Managers can update slides" on public.slides;
create policy "Managers can update slides"
on public.slides
for update
to authenticated
using (
  exists (
    select 1 from public.users
    where users.id = (select auth.uid())
      and lower(trim(users.role::text)) in ('admin', 'owner', 'manager')
  )
)
with check (
  exists (
    select 1 from public.users
    where users.id = (select auth.uid())
      and lower(trim(users.role::text)) in ('admin', 'owner', 'manager')
  )
);

drop policy if exists "Managers can delete slides" on public.slides;
create policy "Managers can delete slides"
on public.slides
for delete
to authenticated
using (
  exists (
    select 1 from public.users
    where users.id = (select auth.uid())
      and lower(trim(users.role::text)) in ('admin', 'owner', 'manager')
  )
);

