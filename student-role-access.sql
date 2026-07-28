-- Substans: adskil elevens læringsadgang fra forælderens økonomiadgang.
-- Kør denne fil i Supabase SQL Editor. Den kan køres flere gange.

drop policy if exists "Families read own payments" on public.student_payments;
drop policy if exists "Parents read own payments" on public.student_payments;

create policy "Parents read own payments"
on public.student_payments
for select to authenticated
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
