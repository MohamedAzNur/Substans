-- Substans' automatiske undervisningspåmindelser.
-- Kør hele filen én gang i Supabase SQL Editor.

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
    if not target.reminders_enabled then
      continue;
    end if;

    if target.event_id is null
      and (
        target.class_start_time is null
        or lower(trim(coalesce(target.class_weekday, ''))) <> lower(weekday_local)
      )
    then
      continue;
    end if;

    lesson_time := coalesce(target.event_start_time, target.class_start_time);
    if lesson_time is null then
      continue;
    end if;

    lesson_start_local := today_local + lesson_time;
    if now_local < lesson_start_local - make_interval(mins => target.reminder_lead_minutes)
      or now_local >= lesson_start_local + interval '15 minutes'
    then
      continue;
    end if;

    delivery_uuid := null;
    message_uuid := null;

    insert into public.lesson_reminder_deliveries (
      class_id,
      lesson_date,
      scheduled_start
    )
    values (
      target.target_class_id,
      today_local,
      lesson_start_local at time zone 'Europe/Copenhagen'
    )
    on conflict (class_id, lesson_date) do nothing
    returning id into delivery_uuid;

    if delivery_uuid is null then
      continue;
    end if;

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
        class_id,
        author_profile_id,
        title,
        body,
        is_important,
        source
      )
      values (
        target.target_class_id,
        null,
        rendered_title,
        rendered_body,
        true,
        'lesson_reminder'
      )
      returning id into message_uuid;

      update public.lesson_reminder_deliveries
      set message_id = message_uuid,
          sent_at = now()
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
returns table (
  class_name text,
  message_id uuid,
  status text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Kun administratorer kan køre påmindelsesagenten.';
  end if;

  return query
  select
    class_row.name,
    result.created_message_id,
    result.delivery_status
  from public.dispatch_due_lesson_reminders() as result
  join public.classes as class_row
    on class_row.id = result.reminded_class_id;
end;
$$;

revoke all on function public.run_lesson_reminder_agent() from public, anon;
grant execute on function public.run_lesson_reminder_agent() to authenticated;

-- Samme jobnavn opdaterer den eksisterende plan, hvis filen køres igen.
select cron.schedule(
  'substans-lesson-reminder-agent',
  '*/5 * * * *',
  'select public.dispatch_due_lesson_reminders();'
);
