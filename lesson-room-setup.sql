-- Substans: indhold og status til det digitale lektionsrum.
-- Kør denne fil i Supabase SQL Editor. Den kan køres flere gange.

create table if not exists public.lesson_rooms (
  id uuid primary key default gen_random_uuid(),
  calendar_event_id uuid not null unique references public.calendar_events(id) on delete cascade,
  learning_goal text,
  agenda text,
  preparation text,
  recap text,
  recording_url text,
  status text not null default 'planned'
    check (status in ('planned','live','completed')),
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.lesson_rooms enable row level security;

create or replace function public.can_access_lesson_room(target_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.calendar_events event
    where event.id = target_event_id
      and event.event_type = 'lesson'
      and public.can_access_class(event.class_id)
  );
$$;

create or replace function public.can_manage_lesson_room(target_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.calendar_events event
    where event.id = target_event_id
      and event.event_type = 'lesson'
      and public.teacher_can_manage_class(event.class_id)
  );
$$;

drop policy if exists "Members read accessible lesson rooms" on public.lesson_rooms;
create policy "Members read accessible lesson rooms"
on public.lesson_rooms
for select to authenticated
using (public.can_access_lesson_room(calendar_event_id));

drop policy if exists "Staff manage assigned lesson rooms" on public.lesson_rooms;
create policy "Staff manage assigned lesson rooms"
on public.lesson_rooms
for all to authenticated
using (public.can_manage_lesson_room(calendar_event_id))
with check (public.can_manage_lesson_room(calendar_event_id));

grant select, insert, update, delete on public.lesson_rooms to authenticated;
