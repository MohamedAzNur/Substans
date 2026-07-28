-- Substans: læsemarkeringer til notifikationscenteret.
-- Kør denne fil i Supabase SQL Editor. Den kan køres flere gange.

create table if not exists public.notification_reads (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  source_type text not null,
  source_id uuid not null,
  read_at timestamptz not null default now(),
  unique (profile_id, source_type, source_id)
);

alter table public.notification_reads enable row level security;

drop policy if exists "Users manage own notification reads"
on public.notification_reads;

create policy "Users manage own notification reads"
on public.notification_reads
for all
to authenticated
using (profile_id = auth.uid())
with check (profile_id = auth.uid());

grant select, insert, update, delete
on public.notification_reads
to authenticated;

create index if not exists notification_reads_profile_idx
on public.notification_reads (profile_id, read_at desc);
