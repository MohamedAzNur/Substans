-- Videoer og visningsstatus for Substans Campus.
-- Kør filen én gang i Supabase SQL Editor.

alter table public.learning_items
add column if not exists video_provider text
check (video_provider in ('youtube', 'uploaded'));

create table if not exists public.video_watch_progress (
  id uuid primary key default gen_random_uuid(),
  learning_item_id uuid not null references public.learning_items(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  watched_seconds numeric(12,2) not null default 0 check (watched_seconds >= 0),
  duration_seconds numeric(12,2) not null default 0 check (duration_seconds >= 0),
  last_position_seconds numeric(12,2) not null default 0 check (last_position_seconds >= 0),
  watched_ranges jsonb not null default '[]'::jsonb,
  started_at timestamptz not null default now(),
  last_watched_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (learning_item_id, student_id)
);

create index if not exists video_watch_progress_item_idx
on public.video_watch_progress(learning_item_id);

create index if not exists video_watch_progress_student_idx
on public.video_watch_progress(student_id);

alter table public.video_watch_progress enable row level security;

drop policy if exists "Members read relevant video progress" on public.video_watch_progress;
create policy "Members read relevant video progress"
on public.video_watch_progress
for select to authenticated
using (
  student_id in (select public.current_student_ids())
  or public.is_admin()
  or exists (
    select 1
    from public.learning_items item
    join public.classes class on class.id = item.class_id
    join public.teachers teacher on teacher.id = class.teacher_id
    join public.class_enrollments enrollment
      on enrollment.class_id = class.id
     and enrollment.student_id = video_watch_progress.student_id
    where item.id = video_watch_progress.learning_item_id
      and teacher.profile_id = auth.uid()
  )
);

drop policy if exists "Students create own video progress" on public.video_watch_progress;
create policy "Students create own video progress"
on public.video_watch_progress
for insert to authenticated
with check (
  exists (
    select 1
    from public.students student
    join public.class_enrollments enrollment on enrollment.student_id = student.id
    join public.learning_items item on item.class_id = enrollment.class_id
    where student.id = video_watch_progress.student_id
      and student.student_profile_id = auth.uid()
      and item.id = video_watch_progress.learning_item_id
  )
);

drop policy if exists "Students update own video progress" on public.video_watch_progress;
create policy "Students update own video progress"
on public.video_watch_progress
for update to authenticated
using (
  exists (
    select 1
    from public.students student
    where student.id = video_watch_progress.student_id
      and student.student_profile_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.students student
    join public.class_enrollments enrollment on enrollment.student_id = student.id
    join public.learning_items item on item.class_id = enrollment.class_id
    where student.id = video_watch_progress.student_id
      and student.student_profile_id = auth.uid()
      and item.id = video_watch_progress.learning_item_id
  )
);

grant select, insert, update on public.video_watch_progress to authenticated;
