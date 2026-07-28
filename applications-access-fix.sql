-- Substans: ansøgningsformularen skal virke for både gæster og indloggede brugere.
-- Kør filen i Supabase SQL Editor. Den kan køres flere gange.

alter table public.applications enable row level security;

grant insert on table public.applications to anon, authenticated;
grant usage, select on sequence public.applications_id_seq to anon, authenticated;

drop policy if exists "Public can submit applications"
on public.applications;

create policy "Public can submit applications"
on public.applications
for insert
to anon, authenticated
with check (true);
