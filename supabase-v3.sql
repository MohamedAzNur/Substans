-- Substans V3: Auth-profiler, roller og sikker adgang.
-- Kan køres flere gange i Supabase SQL Editor.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  requested_role text check (requested_role in ('student','parent','teacher')),
  role text not null default 'pending' check (role in ('pending','student','parent','teacher','admin')),
  created_at timestamptz not null default now()
);

alter table public.profiles add column if not exists email text;
alter table public.profiles add column if not exists requested_role text check (requested_role in ('student','parent','teacher'));
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('pending','student','parent','teacher','admin'));
alter table public.profiles alter column role set default 'pending';
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
    'pending'
  )
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

insert into public.profiles (id, full_name, email, role)
select id, coalesce(raw_user_meta_data->>'full_name', split_part(email, '@', 1)), email, 'pending'
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

-- Skolebetalinger og familiens betalingsoverblik.
create table if not exists public.student_payments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  description text not null,
  amount numeric(10,2) not null check (amount > 0),
  due_date date not null,
  status text not null default 'pending' check (status in ('pending','paid','cancelled')),
  paid_at timestamptz,
  notes text,
  created_at timestamptz not null default now()
);
alter table public.student_payments enable row level security;
drop policy if exists "Admins manage student payments" on public.student_payments;
create policy "Admins manage student payments" on public.student_payments for all to authenticated
using (public.is_admin()) with check (public.is_admin());
drop policy if exists "Families read own payments" on public.student_payments;
drop policy if exists "Parents read own payments" on public.student_payments;
create policy "Parents read own payments" on public.student_payments for select to authenticated
using (
  exists (
    select 1
    from public.students student
    where student.id = student_payments.student_id
      and (
        student.parent_profile_id = auth.uid()
        or lower(student.parent_email) = lower(coalesce(auth.jwt()->>'email', ''))
      )
  )
);
grant select,insert,update,delete on public.student_payments to authenticated;

-- Fælles kalender for lektioner, arrangementer og ferie.
create table if not exists public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  author_profile_id uuid references public.profiles(id) on delete set null,
  event_type text not null default 'lesson' check (event_type in ('lesson','event','holiday')),
  title text not null,
  event_date date not null,
  start_time time,
  duration_minutes integer check (duration_minutes between 15 and 480),
  meeting_url text,
  details text,
  created_at timestamptz not null default now()
);
alter table public.calendar_events enable row level security;
drop policy if exists "Staff manage calendar events" on public.calendar_events;
create policy "Staff manage calendar events" on public.calendar_events for all to authenticated
using (public.is_staff()) with check (public.is_staff());
drop policy if exists "Members read calendar events" on public.calendar_events;
create policy "Members read calendar events" on public.calendar_events for select to authenticated
using (public.can_access_class(class_id));
grant select,insert,update,delete on public.calendar_events to authenticated;

-- Knyt materiale og lektier til den konkrete lektion, når de oprettes i det samlede lærerflow.
alter table public.learning_items
add column if not exists calendar_event_id uuid
references public.calendar_events(id) on delete set null;

create index if not exists learning_items_calendar_event_id_idx
on public.learning_items(calendar_event_id);

alter table public.student_feedback
add column if not exists calendar_event_id uuid
references public.calendar_events(id) on delete set null;

create index if not exists student_feedback_calendar_event_id_idx
on public.student_feedback(calendar_event_id);

-- Faglig progression med forståelse og næste mål.
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
create policy "Staff manage student progress" on public.student_progress for all to authenticated
using (public.is_staff()) with check (public.is_staff());
drop policy if exists "Families read own progress" on public.student_progress;
create policy "Families read own progress" on public.student_progress for select to authenticated
using (student_id in (select public.current_student_ids()));
grant select,insert,update,delete on public.student_progress to authenticated;

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

-- Automatisk undervisningsagent. Kører hvert femte minut og sender højst
-- én holdbesked pr. undervisningsdag. Dansk tid og feriedage respekteres.
create extension if not exists pg_cron;

alter table public.class_messages
add column if not exists source text not null default 'manual'
check (source in ('manual','lesson_reminder'));

create table if not exists public.class_reminder_settings (
  class_id uuid primary key references public.classes(id) on delete cascade,
  enabled boolean not null default true,
  lead_minutes integer not null default 180 check (lead_minutes between 15 and 1440),
  title_template text not null default 'Husk undervisningen i dag',
  body_template text not null default 'Husk at {hold} har undervisning i dag kl. {tid}. Åbn Substans Campus for lektionslink og materialer.',
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.lesson_reminder_deliveries (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  lesson_date date not null,
  scheduled_start timestamptz not null,
  message_id uuid references public.class_messages(id) on delete set null,
  sent_at timestamptz not null default now(),
  unique (class_id, lesson_date)
);

alter table public.class_reminder_settings enable row level security;
alter table public.lesson_reminder_deliveries enable row level security;

drop policy if exists "Admins manage reminder settings" on public.class_reminder_settings;
create policy "Admins manage reminder settings"
on public.class_reminder_settings for all to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "Admins read reminder deliveries" on public.lesson_reminder_deliveries;
create policy "Admins read reminder deliveries"
on public.lesson_reminder_deliveries for select to authenticated
using (public.is_admin());

grant select, insert, update, delete on public.class_reminder_settings to authenticated;
grant select on public.lesson_reminder_deliveries to authenticated;

create or replace function public.dispatch_due_lesson_reminders()
returns table (
  reminded_class_id uuid,
  created_message_id uuid,
  delivery_status text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  now_local timestamp := timezone('Europe/Copenhagen', now());
  today_local date := timezone('Europe/Copenhagen', now())::date;
  weekday_local text := case extract(isodow from timezone('Europe/Copenhagen', now()))
    when 1 then 'Mandag'
    when 2 then 'Tirsdag'
    when 3 then 'Onsdag'
    when 4 then 'Torsdag'
    when 5 then 'Fredag'
    when 6 then 'Lørdag'
    else 'Søndag'
  end;
  target record;
  lesson_time time;
  lesson_start_local timestamp;
  delivery_uuid uuid;
  message_uuid uuid;
  rendered_title text;
  rendered_body text;
begin
  for target in
    select
      class_row.id as target_class_id,
      class_row.name as class_name,
      class_row.weekday as class_weekday,
      class_row.start_time as class_start_time,
      coalesce(setting.enabled, true) as reminders_enabled,
      coalesce(setting.lead_minutes, 180) as reminder_lead_minutes,
      coalesce(setting.title_template, 'Husk undervisningen i dag') as reminder_title,
      coalesce(
        setting.body_template,
        'Husk at {hold} har undervisning i dag kl. {tid}. Åbn Substans Campus for lektionslink og materialer.'
      ) as reminder_body,
      today_event.id as event_id,
      today_event.title as event_title,
      today_event.start_time as event_start_time
    from public.classes as class_row
    left join public.class_reminder_settings as setting
      on setting.class_id = class_row.id
    left join lateral (
      select event_row.id, event_row.title, event_row.start_time
      from public.calendar_events as event_row
      where event_row.class_id = class_row.id
        and event_row.event_type = 'lesson'
        and event_row.event_date = today_local
        and event_row.start_time is not null
      order by event_row.start_time
      limit 1
    ) as today_event on true
    where class_row.status = 'active'
      and not exists (
        select 1
        from public.calendar_events as holiday
        where holiday.class_id = class_row.id
          and holiday.event_type = 'holiday'
          and holiday.event_date = today_local
      )
  loop
    if not target.reminders_enabled then continue; end if;

    if target.event_id is null
      and (
        target.class_start_time is null
        or lower(trim(coalesce(target.class_weekday, ''))) <> lower(weekday_local)
      )
    then
      continue;
    end if;

    lesson_time := coalesce(target.event_start_time, target.class_start_time);
    if lesson_time is null then continue; end if;

    lesson_start_local := today_local + lesson_time;
    if now_local < lesson_start_local - make_interval(mins => target.reminder_lead_minutes)
      or now_local >= lesson_start_local + interval '15 minutes'
    then
      continue;
    end if;

    delivery_uuid := null;
    message_uuid := null;
    insert into public.lesson_reminder_deliveries (class_id, lesson_date, scheduled_start)
    values (
      target.target_class_id,
      today_local,
      lesson_start_local at time zone 'Europe/Copenhagen'
    )
    on conflict (class_id, lesson_date) do nothing
    returning id into delivery_uuid;
    if delivery_uuid is null then continue; end if;

    rendered_title := replace(
      replace(
        replace(target.reminder_title, '{hold}', target.class_name),
        '{tid}',
        to_char(lesson_time, 'HH24:MI')
      ),
      '{lektion}',
      coalesce(target.event_title, 'undervisningen')
    );
    rendered_body := replace(
      replace(
        replace(
          replace(target.reminder_body, '{hold}', target.class_name),
          '{tid}',
          to_char(lesson_time, 'HH24:MI')
        ),
        '{dag}',
        lower(weekday_local)
      ),
      '{lektion}',
      coalesce(target.event_title, 'undervisningen')
    );

    begin
      insert into public.class_messages (
        class_id, author_profile_id, title, body, is_important, source
      )
      values (
        target.target_class_id, null, rendered_title, rendered_body, true, 'lesson_reminder'
      )
      returning id into message_uuid;

      update public.lesson_reminder_deliveries
      set message_id = message_uuid, sent_at = now()
      where id = delivery_uuid;

      reminded_class_id := target.target_class_id;
      created_message_id := message_uuid;
      delivery_status := 'sent';
      return next;
    exception when others then
      delete from public.lesson_reminder_deliveries where id = delivery_uuid;
      raise warning 'Kunne ikke sende påmindelse til hold %: %', target.target_class_id, sqlerrm;
    end;
  end loop;
end;
$$;

revoke all on function public.dispatch_due_lesson_reminders() from public, anon, authenticated;

create or replace function public.run_lesson_reminder_agent()
returns table (class_name text, message_id uuid, status text)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Kun administratorer kan køre påmindelsesagenten.';
  end if;
  return query
  select class_row.name, result.created_message_id, result.delivery_status
  from public.dispatch_due_lesson_reminders() as result
  join public.classes as class_row on class_row.id = result.reminded_class_id;
end;
$$;

revoke all on function public.run_lesson_reminder_agent() from public, anon;
grant execute on function public.run_lesson_reminder_agent() to authenticated;

select cron.schedule(
  'substans-lesson-reminder-agent',
  '*/5 * * * *',
  'select public.dispatch_due_lesson_reminders();'
);

-- Efter at din bruger er oprettet i Authentication, gør den til admin:
-- update public.profiles set role = 'admin'
-- where id = (select id from auth.users where email = 'DIN_EMAIL');
