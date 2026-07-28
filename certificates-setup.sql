-- Substans: certifikater og gennemførte niveauer.
-- Kør denne fil i Supabase SQL Editor. Den kan køres flere gange.

create table if not exists public.certificates (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  title text not null,
  subject text check (subject is null or subject in ('Qur’an','Sīrah','ʿAqīdah','Fiqh','Tarbiyah')),
  achievement text not null,
  issued_on date not null default current_date,
  issued_by uuid references public.profiles(id) on delete set null,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.certificates enable row level security;

drop policy if exists "Staff manage assigned certificates"
on public.certificates;

create policy "Staff manage assigned certificates"
on public.certificates
for all
to authenticated
using (
  public.teacher_can_manage_class(class_id)
  and public.teacher_can_access_student(student_id)
)
with check (
  public.teacher_can_manage_class(class_id)
  and public.teacher_can_access_student(student_id)
);

drop policy if exists "Families read own active certificates"
on public.certificates;

create policy "Families read own active certificates"
on public.certificates
for select
to authenticated
using (
  revoked_at is null
  and student_id in (select public.current_student_ids())
);

grant select, insert, update, delete
on public.certificates
to authenticated;

create index if not exists certificates_student_idx
on public.certificates (student_id, issued_on desc);

create index if not exists certificates_class_idx
on public.certificates (class_id, issued_on desc);
