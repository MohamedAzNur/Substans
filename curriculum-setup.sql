-- Substans: undervisningsplan med læringsmål og progression.
-- Kør denne fil i Supabase SQL Editor. Den kan køres flere gange.

create table if not exists public.curriculum_units (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  subject text not null
    check (subject in ('Qur’an','Sīrah','ʿAqīdah','Fiqh','Tarbiyah')),
  title text not null,
  learning_objective text not null,
  reflection_prompt text,
  status text not null default 'planned'
    check (status in ('planned','in_progress','completed')),
  position integer not null default 1 check (position > 0),
  target_date date,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.curriculum_units enable row level security;

drop policy if exists "Members read accessible curriculum" on public.curriculum_units;
create policy "Members read accessible curriculum"
on public.curriculum_units
for select to authenticated
using (public.can_access_class(class_id));

drop policy if exists "Staff manage assigned curriculum" on public.curriculum_units;
create policy "Staff manage assigned curriculum"
on public.curriculum_units
for all to authenticated
using (public.teacher_can_manage_class(class_id))
with check (public.teacher_can_manage_class(class_id));

grant select, insert, update, delete on public.curriculum_units to authenticated;
