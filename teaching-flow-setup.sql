-- Substans: knyt materialer og lektier til en bestemt lektion.
-- Filen kan køres flere gange i Supabase SQL Editor.

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
