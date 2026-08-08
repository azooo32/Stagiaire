-- Add normalized role policies for projects where the original policy migration
-- has already been applied.

create policy managers_can_insert_slides on public.slides
for insert to authenticated
with check (
  exists (
    select 1 from public.users
    where users.id = (select auth.uid())
      and lower(trim(users.role::text)) in ('admin', 'owner', 'manager')
  )
);

create policy managers_can_update_slides on public.slides
for update to authenticated
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
