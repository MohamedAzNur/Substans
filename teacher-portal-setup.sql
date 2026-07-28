-- Substans: sikker adgang for undervisere til deres egne hold.
-- Kør denne fil i Supabase SQL Editor. Den kan køres flere gange.

create or replace function public.current_teacher_id()
returns uuid language sql stable security definer set search_path = public
as $$
  select teacher.id
  from public.teachers teacher
  join public.profiles profile on profile.id = teacher.profile_id
  where teacher.profile_id = auth.uid()
    and profile.role = 'teacher'
  limit 1;
$$;

create or replace function public.teacher_can_manage_class(target_class_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.is_admin() or exists (
    select 1 from public.classes
    where id = target_class_id
      and teacher_id = public.current_teacher_id()
  );
$$;

create or replace function public.teacher_can_access_student(target_student_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.is_admin() or exists (
    select 1
    from public.class_enrollments enrollment
    join public.classes class on class.id = enrollment.class_id
    where enrollment.student_id = target_student_id
      and class.teacher_id = public.current_teacher_id()
  );
$$;

create or replace function public.can_access_class(target_class_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.teacher_can_manage_class(target_class_id) or exists (
    select 1 from public.class_enrollments
    where class_id = target_class_id
      and student_id in (select public.current_student_ids())
  );
$$;

drop policy if exists "Teachers read own teacher profile" on public.teachers;
create policy "Teachers read own teacher profile" on public.teachers
for select to authenticated using (profile_id = auth.uid());

drop policy if exists "Staff read classes" on public.classes;
drop policy if exists "Staff read assigned classes" on public.classes;
create policy "Staff read assigned classes" on public.classes
for select to authenticated using (public.teacher_can_manage_class(id));

drop policy if exists "Staff read class enrollments" on public.class_enrollments;
drop policy if exists "Teachers read assigned enrollments" on public.class_enrollments;
create policy "Teachers read assigned enrollments" on public.class_enrollments
for select to authenticated using (public.teacher_can_manage_class(class_id));

drop policy if exists "Staff read students" on public.students;
drop policy if exists "Teachers read assigned students" on public.students;
create policy "Teachers read assigned students" on public.students
for select to authenticated using (public.teacher_can_access_student(id));

drop policy if exists "Admins manage lesson sessions" on public.lesson_sessions;
drop policy if exists "Staff manage assigned lesson sessions" on public.lesson_sessions;
create policy "Staff manage assigned lesson sessions" on public.lesson_sessions
for all to authenticated
using (public.teacher_can_manage_class(class_id))
with check (public.teacher_can_manage_class(class_id));

drop policy if exists "Admins manage attendance records" on public.attendance_records;
drop policy if exists "Staff manage assigned attendance" on public.attendance_records;
create policy "Staff manage assigned attendance" on public.attendance_records
for all to authenticated
using (
  exists (
    select 1 from public.lesson_sessions lesson
    where lesson.id = lesson_id
      and public.teacher_can_manage_class(lesson.class_id)
  )
)
with check (
  exists (
    select 1 from public.lesson_sessions lesson
    where lesson.id = lesson_id
      and public.teacher_can_manage_class(lesson.class_id)
  )
);

drop policy if exists "Staff manage learning items" on public.learning_items;
create policy "Staff manage learning items" on public.learning_items
for all to authenticated
using (public.teacher_can_manage_class(class_id))
with check (public.teacher_can_manage_class(class_id));

drop policy if exists "Staff manage student feedback" on public.student_feedback;
create policy "Staff manage student feedback" on public.student_feedback
for all to authenticated
using (
  public.teacher_can_access_student(student_id)
  and (class_id is null or public.teacher_can_manage_class(class_id))
)
with check (
  public.teacher_can_access_student(student_id)
  and (class_id is null or public.teacher_can_manage_class(class_id))
);

drop policy if exists "Staff manage class messages" on public.class_messages;
create policy "Staff manage class messages" on public.class_messages
for all to authenticated
using (public.teacher_can_manage_class(class_id))
with check (public.teacher_can_manage_class(class_id));

drop policy if exists "Staff manage calendar events" on public.calendar_events;
create policy "Staff manage calendar events" on public.calendar_events
for all to authenticated
using (public.teacher_can_manage_class(class_id))
with check (public.teacher_can_manage_class(class_id));

-- Faglig udvikling var designet i V3, men tabellen manglede i den aktive database.
-- Den oprettes her, så lærerens genvej til faglig udvikling virker med det samme.
create table if not exists public.student_progress (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  author_profile_id uuid references public.profiles(id) on delete set null,
  subject text not null check (subject in ('Qur’an','Sīrah','ʿAqīdah','Fiqh','Tarbiyah')),
  skill text not null,
  level integer not null check (level between 1 and 5),
  notes text,
  next_goal text,
  created_at timestamptz not null default now()
);

alter table public.student_progress enable row level security;

drop policy if exists "Staff manage student progress" on public.student_progress;
create policy "Staff manage student progress" on public.student_progress
for all to authenticated
using (public.teacher_can_access_student(student_id))
with check (public.teacher_can_access_student(student_id));

drop policy if exists "Families read own progress" on public.student_progress;
create policy "Families read own progress" on public.student_progress
for select to authenticated
using (student_id in (select public.current_student_ids()));

grant select, insert, update, delete on public.student_progress to authenticated;

drop policy if exists "Staff upload learning attachments" on storage.objects;
create policy "Staff upload learning attachments"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'learning-attachments'
  and public.teacher_can_manage_class(((storage.foldername(name))[1])::uuid)
);

drop policy if exists "Staff delete learning attachments" on storage.objects;
create policy "Staff delete learning attachments"
on storage.objects for delete to authenticated
using (
  bucket_id = 'learning-attachments'
  and public.teacher_can_manage_class(((storage.foldername(name))[1])::uuid)
);
