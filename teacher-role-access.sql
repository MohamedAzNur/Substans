-- Substans: undervisere må kun arbejde med egne hold og deres elever.
-- Kør denne fil i Supabase SQL Editor. Den kan køres flere gange.

create or replace function public.current_teacher_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select teacher.id
  from public.teachers teacher
  join public.profiles profile on profile.id = teacher.profile_id
  where teacher.profile_id = auth.uid()
    and profile.role = 'teacher'
  limit 1;
$$;

create or replace function public.teacher_can_manage_class(target_class_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin() or exists (
    select 1
    from public.classes class
    where class.id = target_class_id
      and class.teacher_id = public.current_teacher_id()
  );
$$;

create or replace function public.teacher_can_access_student(target_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin() or exists (
    select 1
    from public.class_enrollments enrollment
    join public.classes class on class.id = enrollment.class_id
    where enrollment.student_id = target_student_id
      and class.teacher_id = public.current_teacher_id()
  );
$$;

drop policy if exists "Staff read classes" on public.classes;
drop policy if exists "Staff read assigned classes" on public.classes;
create policy "Staff read assigned classes"
on public.classes for select to authenticated
using (public.teacher_can_manage_class(id));

drop policy if exists "Staff read class enrollments" on public.class_enrollments;
drop policy if exists "Teachers read assigned enrollments" on public.class_enrollments;
create policy "Teachers read assigned enrollments"
on public.class_enrollments for select to authenticated
using (public.teacher_can_manage_class(class_id));

drop policy if exists "Staff read students" on public.students;
drop policy if exists "Teachers read assigned students" on public.students;
create policy "Teachers read assigned students"
on public.students for select to authenticated
using (public.teacher_can_access_student(id));
