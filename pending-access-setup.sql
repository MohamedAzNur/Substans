-- Substans: nye login-konti afventer godkendelse, før de får en brugerrolle.
-- Kør denne fil i Supabase SQL Editor. Den kan køres flere gange.

alter table public.profiles
drop constraint if exists profiles_role_check;

alter table public.profiles
add constraint profiles_role_check
check (role in ('pending','student','parent','teacher','admin'));

alter table public.profiles
alter column role set default 'pending';

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, requested_role, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    new.email,
    case
      when new.raw_user_meta_data->>'requested_role' in ('student','parent','teacher')
      then new.raw_user_meta_data->>'requested_role'
      else null
    end,
    'pending'
  )
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;
