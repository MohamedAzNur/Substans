-- Substans V3: Auth-profiler, roller og sikker adgang.
-- Kan køres flere gange i Supabase SQL Editor.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null default 'student' check (role in ('student','parent','teacher','admin')),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    case when new.raw_user_meta_data->>'role' in ('student','parent','teacher') then new.raw_user_meta_data->>'role' else 'student' end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

insert into public.profiles (id, full_name, role)
select id, coalesce(raw_user_meta_data->>'full_name', split_part(email, '@', 1)), 'student'
from auth.users
on conflict (id) do nothing;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

drop policy if exists "Users read own profile" on public.profiles;
create policy "Users read own profile" on public.profiles
for select to authenticated using (auth.uid() = id);

drop policy if exists "Admins read all profiles" on public.profiles;
create policy "Admins read all profiles" on public.profiles
for select to authenticated using (public.is_admin());

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

alter table public.students enable row level security;

drop policy if exists "Admins manage students" on public.students;
create policy "Admins manage students" on public.students
for all to authenticated using (public.is_admin())
with check (public.is_admin());

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

grant select, insert, update, delete on public.classes to authenticated;
grant select, insert, delete on public.class_enrollments to authenticated;

-- Efter at din bruger er oprettet i Authentication, gør den til admin:
-- update public.profiles set role = 'admin'
-- where id = (select id from auth.users where email = 'DIN_EMAIL');
