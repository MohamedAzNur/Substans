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

-- Efter at din bruger er oprettet i Authentication, gør den til admin:
-- update public.profiles set role = 'admin'
-- where id = (select id from auth.users where email = 'DIN_EMAIL');
