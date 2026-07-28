-- Substans: atomisk og sikker godkendelse af login-konti.
-- Kør filen i Supabase SQL Editor. Den kan køres flere gange.

create or replace function public.assign_profile_access(
  target_profile_id uuid,
  new_role text,
  target_link_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  affected_rows integer;
begin
  if not public.is_admin() then
    raise exception 'Kun administratorer kan ændre kontoadgang';
  end if;

  if target_profile_id = auth.uid() then
    raise exception 'Din egen administratorkonto er beskyttet';
  end if;

  if new_role not in ('pending','student','parent','teacher','admin') then
    raise exception 'Ugyldig rolle';
  end if;

  if new_role in ('student','parent','teacher') and target_link_id is null then
    raise exception 'Vælg en tilknytning';
  end if;

  update public.students
  set student_profile_id = null
  where student_profile_id = target_profile_id;

  update public.students
  set parent_profile_id = null
  where parent_profile_id = target_profile_id;

  update public.teachers
  set profile_id = null
  where profile_id = target_profile_id;

  update public.profiles
  set role = new_role,
      requested_role = null
  where id = target_profile_id;

  get diagnostics affected_rows = row_count;
  if affected_rows <> 1 then
    raise exception 'Kontoen blev ikke fundet';
  end if;

  if new_role = 'student' then
    update public.students
    set student_profile_id = target_profile_id
    where id = target_link_id;
  elsif new_role = 'parent' then
    update public.students
    set parent_profile_id = target_profile_id
    where id = target_link_id;
  elsif new_role = 'teacher' then
    update public.teachers
    set profile_id = target_profile_id
    where id = target_link_id;
  else
    return;
  end if;

  get diagnostics affected_rows = row_count;
  if affected_rows <> 1 then
    raise exception 'Tilknytningen blev ikke fundet';
  end if;
end;
$$;

revoke all on function public.assign_profile_access(uuid,text,uuid) from public;
grant execute on function public.assign_profile_access(uuid,text,uuid) to authenticated;
