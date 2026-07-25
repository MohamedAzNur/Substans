-- Substans V3: Auth-profiler, roller og sikker adgang.
-- Kan køres flere gange i Supabase SQL Editor.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  requested_role text check (requested_role in ('student','parent','teacher')),
  role text not null default 'student' check (role in ('student','parent','teacher','admin')),
  created_at timestamptz not null default now()
);

alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists requested_role text check (requested_role in ('student','parent','teacher'));
alter table public.profiles enable row level security;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, requested_role, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    new.email,
    case when new.raw_user_meta_data->>'requested_role' in ('student','parent','teacher') then new.raw_user_meta_data->>'requested_role' else null end,
    'student'
  )
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

insert into public.profiles (id, full_name, email, role)
select id, coalesce(raw_user_meta_data->>'full_name', split_part(email, '@', 1)), email, 'student'
from auth.users
on conflict (id) do update set email = excluded.email;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin', 'teacher')
  );
$$;

drop policy if exists "Users read own profile" on public.profiles;
create policy "Users read own profile" on public.profiles
for select to authenticated using (auth.uid() = id);

drop policy if exists "Admins read all profiles" on public.profiles;
create policy "Admins read all profiles" on public.profiles
for select to authenticated using (public.is_admin());

drop policy if exists "Admins update profiles" on public.profiles;
create policy "Admins update profiles" on public.profiles
for update to authenticated using (public.is_admin())
with check (public.is_admin());

-- Bevar offentlig ansøgning; kun administratorer kan læse og ændre den.
alter table public.applications add column if not exists status text not null default 'new';
alter table public.applications enable row level security;

drop policy if exists "Admins read applications" on public.applications;
create policy "Admins read applications" on public.applications
for select to authenticated using (public.is_admin());

drop policy if exists "Admins update applications" on public.applications;
create policy "Admins update applications" on public.applications
for update to authenticated using (public.is_admin())
with check (public.is_admin());

grant select on public.profiles to authenticated;
grant select, update on public.applications to authenticated;

-- Elever oprettes af administratoren fra godkendte ansøgninger.
create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  application_id bigint unique references public.applications(id) on delete set null,
  full_name text not null,
  age integer check (age between 5 and 17),
  parent_name text not null,
  parent_email text not null,
  parent_phone text,
  status text not null default 'active' check (status in ('active', 'waiting', 'paused')),
  created_at timestamptz not null default now()
);

alter table public.students add column if not exists student_profile_id uuid references public.profiles(id) on delete set null;
alter table public.students add column if not exists parent_profile_id uuid references public.profiles(id) on delete set null;
alter table public.students enable row level security;

create or replace function public.current_student_ids()
returns setof uuid language sql stable security definer set search_path = public
as $$
  select id from public.students
  where student_profile_id = auth.uid()
     or parent_profile_id = auth.uid()
     or lower(parent_email) = lower(coalesce(auth.jwt()->>'email', ''));
$$;

create or replace function public.can_access_class(target_class_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.is_staff() or exists (
    select 1 from public.class_enrollments
    where class_id = target_class_id
      and student_id in (select public.current_student_ids())
  );
$$;

drop policy if exists "Admins manage students" on public.students;
create policy "Admins manage students" on public.students
for all to authenticated using (public.is_admin())
with check (public.is_admin());

drop policy if exists "Families read own students" on public.students;
create policy "Families read own students" on public.students
for select to authenticated using (id in (select public.current_student_ids()));

drop policy if exists "Staff read students" on public.students;
create policy "Staff read students" on public.students
for select to authenticated using (public.is_staff());

grant select, insert, update on public.students to authenticated;

-- Hold og elevtilknytninger.
create table if not exists public.classes (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  weekday text,
  start_time time,
  capacity integer not null default 30 check (capacity between 1 and 100),
  teacher_name text,
  status text not null default 'active' check (status in ('active', 'planned', 'paused')),
  created_at timestamptz not null default now()
);

create table if not exists public.class_enrollments (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (class_id, student_id)
);

alter table public.classes enable row level security;
alter table public.class_enrollments enable row level security;

drop policy if exists "Admins manage classes" on public.classes;
create policy "Admins manage classes" on public.classes
for all to authenticated using (public.is_admin())
with check (public.is_admin());

drop policy if exists "Admins manage class enrollments" on public.class_enrollments;
create policy "Admins manage class enrollments" on public.class_enrollments
for all to authenticated using (public.is_admin())
with check (public.is_admin());

drop policy if exists "Families read own enrollments" on public.class_enrollments;
create policy "Families read own enrollments" on public.class_enrollments
for select to authenticated using (student_id in (select public.current_student_ids()));

drop policy if exists "Staff read class enrollments" on public.class_enrollments;
create policy "Staff read class enrollments" on public.class_enrollments
for select to authenticated using (public.is_staff());

drop policy if exists "Members read enrolled classes" on public.classes;
create policy "Members read enrolled classes" on public.classes
for select to authenticated using (public.can_access_class(id));

grant select, insert, update, delete on public.classes to authenticated;
grant select, insert, delete on public.class_enrollments to authenticated;

-- Undervisere og deres tilknytning til hold.
create table if not exists public.teachers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text not null,
  phone text,
  bio text,
  status text not null default 'active' check (status in ('active', 'invited', 'paused')),
  created_at timestamptz not null default now()
);

alter table public.teachers add column if not exists profile_id uuid unique references public.profiles(id) on delete set null;
alter table public.classes
add column if not exists teacher_id uuid references public.teachers(id) on delete set null;

alter table public.teachers enable row level security;

drop policy if exists "Admins manage teachers" on public.teachers;
create policy "Admins manage teachers" on public.teachers
for all to authenticated using (public.is_admin())
with check (public.is_admin());

grant select, insert, update, delete on public.teachers to authenticated;

-- Lektioner og fremmøde.
create table if not exists public.lesson_sessions (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  lesson_date date not null,
  topic text not null,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.lesson_sessions(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  status text not null check (status in ('present', 'absent', 'excused')),
  updated_at timestamptz not null default now(),
  unique (lesson_id, student_id)
);

alter table public.lesson_sessions enable row level security;
alter table public.attendance_records enable row level security;

drop policy if exists "Admins manage lesson sessions" on public.lesson_sessions;
create policy "Admins manage lesson sessions" on public.lesson_sessions
for all to authenticated using (public.is_admin())
with check (public.is_admin());

drop policy if exists "Admins manage attendance records" on public.attendance_records;
create policy "Admins manage attendance records" on public.attendance_records
for all to authenticated using (public.is_admin())
with check (public.is_admin());

grant select, insert, update, delete on public.lesson_sessions to authenticated;
grant select, insert, update, delete on public.attendance_records to authenticated;

-- Materialer og lektier til holdene.
create table if not exists public.learning_items (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  kind text not null check (kind in ('material', 'homework')),
  title text not null,
  description text,
  resource_url text,
  file_path text,
  file_name text,
  file_type text,
  file_size bigint,
  due_date date,
  created_at timestamptz not null default now()
);

alter table public.learning_items add column if not exists file_path text;
alter table public.learning_items add column if not exists file_name text;
alter table public.learning_items add column if not exists file_type text;
alter table public.learning_items add column if not exists file_size bigint;
alter table public.learning_items enable row level security;

drop policy if exists "Admins manage learning items" on public.learning_items;
drop policy if exists "Staff manage learning items" on public.learning_items;
create policy "Staff manage learning items" on public.learning_items
for all to authenticated using (public.is_staff())
with check (public.is_staff());

drop policy if exists "Members read learning items" on public.learning_items;
create policy "Members read learning items" on public.learning_items
for select to authenticated using (public.can_access_class(class_id));

drop policy if exists "Staff read classes" on public.classes;
create policy "Staff read classes" on public.classes
for select to authenticated using (public.is_staff());

grant select, insert, update, delete on public.learning_items to authenticated;

-- Personlig feedback til elever og familier.
create table if not exists public.student_feedback (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  class_id uuid references public.classes(id) on delete set null,
  author_profile_id uuid references public.profiles(id) on delete set null,
  focus text not null,
  feedback_text text not null,
  next_step text,
  created_at timestamptz not null default now()
);

alter table public.student_feedback enable row level security;

drop policy if exists "Staff manage student feedback" on public.student_feedback;
create policy "Staff manage student feedback" on public.student_feedback
for all to authenticated using (public.is_staff())
with check (public.is_staff());

drop policy if exists "Families read own feedback" on public.student_feedback;
create policy "Families read own feedback" on public.student_feedback
for select to authenticated using (student_id in (select public.current_student_ids()));

grant select, insert, update, delete on public.student_feedback to authenticated;

-- Meddelelser fra skolen til familier på et hold.
create table if not exists public.class_messages (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  author_profile_id uuid references public.profiles(id) on delete set null,
  title text not null,
  body text not null,
  is_important boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.class_messages enable row level security;

drop policy if exists "Staff manage class messages" on public.class_messages;
create policy "Staff manage class messages" on public.class_messages
for all to authenticated using (public.is_staff())
with check (public.is_staff());

drop policy if exists "Members read class messages" on public.class_messages;
create policy "Members read class messages" on public.class_messages
for select to authenticated using (public.can_access_class(class_id));

grant select, insert, update, delete on public.class_messages to authenticated;

-- Privat filområde til materialer og lektier. Filer åbnes via tidsbegrænsede links.
insert into storage.buckets (id, name, public, file_size_limit)
values ('learning-attachments', 'learning-attachments', false, 52428800)
on conflict (id) do update
set public = excluded.public, file_size_limit = excluded.file_size_limit;

drop policy if exists "Authenticated users read learning attachments" on storage.objects;
drop policy if exists "Members read learning attachments" on storage.objects;
create policy "Members read learning attachments"
on storage.objects for select to authenticated
using (
  bucket_id = 'learning-attachments'
  and public.can_access_class(((storage.foldername(name))[1])::uuid)
);

drop policy if exists "Staff upload learning attachments" on storage.objects;
create policy "Staff upload learning attachments"
on storage.objects for insert to authenticated
with check (bucket_id = 'learning-attachments' and public.is_staff());

drop policy if exists "Staff delete learning attachments" on storage.objects;
create policy "Staff delete learning attachments"
on storage.objects for delete to authenticated
using (bucket_id = 'learning-attachments' and public.is_staff());

-- Efter at din bruger er oprettet i Authentication, gør den til admin:
-- update public.profiles set role = 'admin'
-- where id = (select id from auth.users where email = 'DIN_EMAIL');
