-- Substans: sikker selvbetjening af egen profil.
-- Kør denne fil i Supabase SQL Editor. Den kan køres flere gange.

create or replace function public.update_my_profile(new_full_name text)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_profile public.profiles;
  clean_name text := trim(new_full_name);
begin
  if auth.uid() is null then
    raise exception 'Du skal være logget ind.';
  end if;

  if length(clean_name) < 2 or length(clean_name) > 80 then
    raise exception 'Navnet skal være mellem 2 og 80 tegn.';
  end if;

  update public.profiles
  set full_name = clean_name
  where id = auth.uid()
  returning * into updated_profile;

  if updated_profile.id is null then
    raise exception 'Profilen blev ikke fundet.';
  end if;

  return updated_profile;
end;
$$;

revoke all on function public.update_my_profile(text) from public;
grant execute on function public.update_my_profile(text) to authenticated;
