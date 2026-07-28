-- Substans: elevafleveringer og underviserens vurdering.
-- Kør denne fil i Supabase SQL Editor. Den kan køres flere gange.

create table if not exists public.homework_submissions (
  id uuid primary key default gen_random_uuid(),
  learning_item_id uuid not null references public.learning_items(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  submitted_by uuid references public.profiles(id) on delete set null,
  response_text text,
  file_path text,
  file_name text,
  file_type text,
  file_size bigint,
  status text not null default 'submitted'
    check (status in ('submitted','in_review','returned','approved')),
  teacher_feedback text,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (learning_item_id, student_id)
);

alter table public.homework_submissions enable row level security;

create or replace function public.is_own_student_profile(target_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.students student
    where student.id = target_student_id
      and student.student_profile_id = auth.uid()
  );
$$;

create or replace function public.can_submit_homework(
  target_homework_id uuid,
  target_student_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_own_student_profile(target_student_id)
    and exists (
      select 1
      from public.learning_items item
      join public.class_enrollments enrollment
        on enrollment.class_id = item.class_id
      where item.id = target_homework_id
        and item.kind = 'homework'
        and enrollment.student_id = target_student_id
    );
$$;

create or replace function public.staff_can_manage_submission(
  target_homework_id uuid,
  target_student_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.learning_items item
    where item.id = target_homework_id
      and item.kind = 'homework'
      and public.teacher_can_manage_class(item.class_id)
      and public.teacher_can_access_student(target_student_id)
  );
$$;

drop policy if exists "Families read own homework submissions" on public.homework_submissions;
create policy "Families read own homework submissions"
on public.homework_submissions
for select to authenticated
using (student_id in (select public.current_student_ids()));

drop policy if exists "Families create own homework submissions" on public.homework_submissions;
create policy "Families create own homework submissions"
on public.homework_submissions
for insert to authenticated
with check (
  public.can_submit_homework(learning_item_id, student_id)
  and submitted_by = auth.uid()
  and status = 'submitted'
);

drop policy if exists "Families update own homework submissions" on public.homework_submissions;
create policy "Families update own homework submissions"
on public.homework_submissions
for update to authenticated
using (public.is_own_student_profile(student_id))
with check (
  public.can_submit_homework(learning_item_id, student_id)
  and submitted_by = auth.uid()
  and status = 'submitted'
);

drop policy if exists "Staff manage assigned homework submissions" on public.homework_submissions;
create policy "Staff manage assigned homework submissions"
on public.homework_submissions
for all to authenticated
using (public.staff_can_manage_submission(learning_item_id, student_id))
with check (public.staff_can_manage_submission(learning_item_id, student_id));

grant select, insert, update, delete on public.homework_submissions to authenticated;

insert into storage.buckets (id, name, public, file_size_limit)
values ('homework-submissions', 'homework-submissions', false, 52428800)
on conflict (id) do update
set public = excluded.public, file_size_limit = excluded.file_size_limit;

drop policy if exists "Members read homework submission files" on storage.objects;
create policy "Members read homework submission files"
on storage.objects
for select to authenticated
using (
  bucket_id = 'homework-submissions'
  and (
    ((storage.foldername(name))[1])::uuid in (select public.current_student_ids())
    or public.teacher_can_access_student(((storage.foldername(name))[1])::uuid)
  )
);

drop policy if exists "Families upload homework submission files" on storage.objects;
create policy "Families upload homework submission files"
on storage.objects
for insert to authenticated
with check (
  bucket_id = 'homework-submissions'
  and public.is_own_student_profile(((storage.foldername(name))[1])::uuid)
);

drop policy if exists "Members delete homework submission files" on storage.objects;
create policy "Members delete homework submission files"
on storage.objects
for delete to authenticated
using (
  bucket_id = 'homework-submissions'
  and (
    public.is_own_student_profile(((storage.foldername(name))[1])::uuid)
    or public.teacher_can_access_student(((storage.foldername(name))[1])::uuid)
  )
);
