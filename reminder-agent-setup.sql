-- Substans' automatiske undervisningspåmindelser.
-- Kør hele filen én gang i Supabase SQL Editor. Den kan køres igen senere.

create extension if not exists pg_cron;

alter table public.class_messages
add column if not exists source text not null default 'manual'
check (source in ('manual','lesson_reminder'));

create table if not exists public.class_reminder_settings (
  class_id uuid primary key references public.classes(id) on delete cascade,
  enabled boolean not null default true,
  lead_minutes integer not null default 180 check (lead_minutes between 15 and 1440),
  title_template text not null default 'Husk undervisningen {relative_dag}',
  body_template text not null default 'Husk at {hold} har undervisning {relative_dag} kl. {tid}. Åbn Substans Campus for lektionslink og materialer.',
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.class_reminder_settings
alter column title_template set default 'Husk undervisningen {relative_dag}';
alter table public.class_reminder_settings
alter column body_template set default 'Husk at {hold} har undervisning {relative_dag} kl. {tid}. Åbn Substans Campus for lektionslink og materialer.';

update public.class_reminder_settings
set title_template = 'Husk undervisningen {relative_dag}'
where title_template = 'Husk undervisningen i dag';

update public.class_reminder_settings
set body_template = 'Husk at {hold} har undervisning {relative_dag} kl. {tid}. Åbn Substans Campus for lektionslink og materialer.'
where body_template = 'Husk at {hold} har undervisning i dag kl. {tid}. Åbn Substans Campus for lektionslink og materialer.';

create table if not exists public.lesson_reminder_deliveries (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  lesson_date date not null,
  scheduled_start timestamptz not null,
  message_id uuid references public.class_messages(id) on delete set null,
  audience_count integer not null default 0,
  sent_at timestamptz not null default now(),
  unique (class_id, lesson_date)
);

alter table public.lesson_reminder_deliveries
add column if not exists audience_count integer not null default 0;

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

-- Beregner lektioner fra både den faste ugeplan og konkrete kalenderposter.
-- Også morgendagens lektion medtages, så "1 dag før" virker korrekt.
create or replace function public.lesson_reminder_candidates(p_days integer default 8)
returns table (
  target_class_id uuid,
  class_name text,
  lesson_date date,
  lesson_time time,
  lesson_title text,
  reminder_lead_minutes integer,
  reminder_title text,
  reminder_body text,
  scheduled_start timestamptz,
  remind_at timestamptz,
  audience_count integer,
  schedule_source text
)
language sql
stable
security definer
set search_path = ''
as $$
  with local_clock as (
    select timezone('Europe/Copenhagen', now())::date as today
  ),
  date_window as (
    select generate_series(
      local_clock.today,
      local_clock.today + greatest(0, least(coalesce(p_days, 8), 31) - 1),
      interval '1 day'
    )::date as target_date
    from local_clock
  ),
  candidates as (
    select
      class_row.id as target_class_id,
      class_row.name as class_name,
      class_row.weekday as class_weekday,
      date_window.target_date as lesson_date,
      coalesce(calendar_lesson.start_time, class_row.start_time) as lesson_time,
      coalesce(calendar_lesson.title, 'undervisningen') as lesson_title,
      coalesce(setting.lead_minutes, 180) as reminder_lead_minutes,
      coalesce(setting.title_template, 'Husk undervisningen {relative_dag}') as reminder_title,
      coalesce(
        setting.body_template,
        'Husk at {hold} har undervisning {relative_dag} kl. {tid}. Åbn Substans Campus for lektionslink og materialer.'
      ) as reminder_body,
      case extract(isodow from date_window.target_date)
        when 1 then 'Mandag' when 2 then 'Tirsdag' when 3 then 'Onsdag'
        when 4 then 'Torsdag' when 5 then 'Fredag' when 6 then 'Lørdag'
        else 'Søndag'
      end as weekday_name,
      calendar_lesson.id as calendar_lesson_id,
      coalesce(setting.enabled, true) as reminders_enabled,
      (
        select count(*)::integer
        from public.class_enrollments enrollment
        where enrollment.class_id = class_row.id
      ) as audience_count
    from public.classes class_row
    cross join date_window
    left join public.class_reminder_settings setting
      on setting.class_id = class_row.id
    left join lateral (
      select event_row.id, event_row.title, event_row.start_time
      from public.calendar_events event_row
      where event_row.class_id = class_row.id
        and event_row.event_type = 'lesson'
        and event_row.event_date = date_window.target_date
        and event_row.start_time is not null
      order by event_row.start_time
      limit 1
    ) calendar_lesson on true
    where class_row.status = 'active'
      and not exists (
        select 1
        from public.calendar_events holiday
        where holiday.class_id = class_row.id
          and holiday.event_type = 'holiday'
          and holiday.event_date = date_window.target_date
      )
  )
  select
    candidates.target_class_id,
    candidates.class_name,
    candidates.lesson_date,
    candidates.lesson_time,
    candidates.lesson_title,
    candidates.reminder_lead_minutes,
    candidates.reminder_title,
    candidates.reminder_body,
    (candidates.lesson_date + candidates.lesson_time) at time zone 'Europe/Copenhagen' as scheduled_start,
    ((candidates.lesson_date + candidates.lesson_time) at time zone 'Europe/Copenhagen')
      - make_interval(mins => candidates.reminder_lead_minutes) as remind_at,
    candidates.audience_count,
    case when candidates.calendar_lesson_id is null then 'weekly_schedule' else 'calendar' end as schedule_source
  from candidates
  where candidates.reminders_enabled
    and candidates.lesson_time is not null
    and (
      candidates.calendar_lesson_id is not null
      or lower(trim(candidates.weekday_name)) = lower(trim(coalesce(candidates.class_weekday, '')))
    );
$$;

revoke all on function public.lesson_reminder_candidates(integer) from public, anon, authenticated;

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
  today_local date := timezone('Europe/Copenhagen', now())::date;
  target record;
  delivery_uuid uuid;
  message_uuid uuid;
  rendered_title text;
  rendered_body text;
  weekday_label text;
  relative_day_label text;
begin
  for target in
    select candidate.*
    from public.lesson_reminder_candidates(2) candidate
    where now() >= candidate.remind_at
      and now() < candidate.scheduled_start + interval '15 minutes'
    order by candidate.remind_at
  loop
    delivery_uuid := null;
    message_uuid := null;

    insert into public.lesson_reminder_deliveries (
      class_id,
      lesson_date,
      scheduled_start,
      audience_count
    )
    values (
      target.target_class_id,
      target.lesson_date,
      target.scheduled_start,
      target.audience_count
    )
    on conflict (class_id, lesson_date) do nothing
    returning id into delivery_uuid;

    if delivery_uuid is null then
      continue;
    end if;

    weekday_label := case extract(isodow from target.lesson_date)
      when 1 then 'mandag' when 2 then 'tirsdag' when 3 then 'onsdag'
      when 4 then 'torsdag' when 5 then 'fredag' when 6 then 'lørdag'
      else 'søndag'
    end;
    relative_day_label := case
      when target.lesson_date = today_local then 'i dag'
      when target.lesson_date = today_local + 1 then 'i morgen'
      else 'på ' || weekday_label
    end;

    rendered_title := target.reminder_title;
    rendered_title := replace(rendered_title, '{hold}', target.class_name);
    rendered_title := replace(rendered_title, '{tid}', to_char(target.lesson_time, 'HH24:MI'));
    rendered_title := replace(rendered_title, '{dag}', weekday_label);
    rendered_title := replace(rendered_title, '{relative_dag}', relative_day_label);
    rendered_title := replace(rendered_title, '{lektion}', target.lesson_title);

    rendered_body := target.reminder_body;
    rendered_body := replace(rendered_body, '{hold}', target.class_name);
    rendered_body := replace(rendered_body, '{tid}', to_char(target.lesson_time, 'HH24:MI'));
    rendered_body := replace(rendered_body, '{dag}', weekday_label);
    rendered_body := replace(rendered_body, '{relative_dag}', relative_day_label);
    rendered_body := replace(rendered_body, '{lektion}', target.lesson_title);

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
  from public.dispatch_due_lesson_reminders() result
  join public.classes class_row
    on class_row.id = result.reminded_class_id;
end;
$$;

revoke all on function public.run_lesson_reminder_agent() from public, anon;
grant execute on function public.run_lesson_reminder_agent() to authenticated;

create or replace function public.get_lesson_reminder_schedule(p_days integer default 14)
returns table (
  class_id uuid,
  class_name text,
  lesson_date date,
  scheduled_start timestamptz,
  remind_at timestamptz,
  audience_count integer,
  schedule_source text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Kun administratorer kan se påmindelsesplanen.';
  end if;

  return query
  select distinct on (candidate.target_class_id)
    candidate.target_class_id,
    candidate.class_name,
    candidate.lesson_date,
    candidate.scheduled_start,
    candidate.remind_at,
    candidate.audience_count,
    candidate.schedule_source
  from public.lesson_reminder_candidates(greatest(1, least(coalesce(p_days, 14), 31))) candidate
  where candidate.scheduled_start >= now()
    and not exists (
      select 1
      from public.lesson_reminder_deliveries delivery
      where delivery.class_id = candidate.target_class_id
        and delivery.lesson_date = candidate.lesson_date
    )
  order by candidate.target_class_id, candidate.scheduled_start;
end;
$$;

revoke all on function public.get_lesson_reminder_schedule(integer) from public, anon;
grant execute on function public.get_lesson_reminder_schedule(integer) to authenticated;

create or replace function public.get_lesson_reminder_agent_health()
returns table (
  agent_active boolean,
  last_run_status text,
  last_run_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'Kun administratorer kan se agentens status.';
  end if;

  return query
  select
    coalesce(job.active, false),
    coalesce(last_run.status, 'waiting'),
    last_run.start_time
  from (select 1) seed
  left join cron.job job
    on job.jobname = 'substans-lesson-reminder-agent'
  left join lateral (
    select detail.status, detail.start_time
    from cron.job_run_details detail
    where detail.jobid = job.jobid
    order by detail.start_time desc
    limit 1
  ) last_run on true;
end;
$$;

revoke all on function public.get_lesson_reminder_agent_health() from public, anon;
grant execute on function public.get_lesson_reminder_agent_health() to authenticated;

-- Samme jobnavn opdaterer den eksisterende plan, hvis filen køres igen.
select cron.schedule(
  'substans-lesson-reminder-agent',
  '*/5 * * * *',
  'select public.dispatch_due_lesson_reminders();'
);
