-- Substans: quizzer og læringstjek.
-- Kør denne fil i Supabase SQL Editor. Den kan køres flere gange.

create table if not exists public.quizzes (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  calendar_event_id uuid references public.calendar_events(id) on delete set null,
  title text not null,
  instructions text,
  status text not null default 'draft'
    check (status in ('draft','published','closed')),
  due_at timestamptz,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.quiz_questions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.quizzes(id) on delete cascade,
  position integer not null check (position > 0),
  prompt text not null,
  option_a text not null,
  option_b text not null,
  option_c text not null,
  option_d text not null,
  correct_option text not null check (correct_option in ('a','b','c','d')),
  explanation text,
  unique (quiz_id, position)
);

create table if not exists public.quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.quizzes(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  submitted_by uuid references public.profiles(id) on delete set null,
  answers jsonb not null default '{}'::jsonb,
  answer_review jsonb not null default '[]'::jsonb,
  score integer not null check (score >= 0),
  total integer not null check (total > 0 and score <= total),
  submitted_at timestamptz not null default now(),
  unique (quiz_id, student_id)
);

alter table public.quizzes enable row level security;
alter table public.quiz_questions enable row level security;
alter table public.quiz_attempts enable row level security;

create or replace function public.can_manage_quiz(target_quiz_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.quizzes quiz
    where quiz.id = target_quiz_id
      and public.teacher_can_manage_class(quiz.class_id)
  );
$$;

create or replace function public.can_access_quiz(target_quiz_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.quizzes quiz
    where quiz.id = target_quiz_id
      and public.can_access_class(quiz.class_id)
      and (
        quiz.status in ('published','closed')
        or public.teacher_can_manage_class(quiz.class_id)
      )
  );
$$;

drop policy if exists "Staff manage assigned quizzes" on public.quizzes;
create policy "Staff manage assigned quizzes"
on public.quizzes
for all to authenticated
using (public.teacher_can_manage_class(class_id))
with check (public.teacher_can_manage_class(class_id));

drop policy if exists "Members read published quizzes" on public.quizzes;
create policy "Members read published quizzes"
on public.quizzes
for select to authenticated
using (
  status in ('published','closed')
  and public.can_access_class(class_id)
);

drop policy if exists "Staff manage quiz questions" on public.quiz_questions;
create policy "Staff manage quiz questions"
on public.quiz_questions
for all to authenticated
using (public.can_manage_quiz(quiz_id))
with check (public.can_manage_quiz(quiz_id));

drop policy if exists "Families read own quiz attempts" on public.quiz_attempts;
create policy "Families read own quiz attempts"
on public.quiz_attempts
for select to authenticated
using (student_id in (select public.current_student_ids()));

drop policy if exists "Staff read assigned quiz attempts" on public.quiz_attempts;
create policy "Staff read assigned quiz attempts"
on public.quiz_attempts
for select to authenticated
using (
  public.can_manage_quiz(quiz_id)
  and public.teacher_can_access_student(student_id)
);

grant select, insert, update, delete on public.quizzes to authenticated;
grant select, insert, update, delete on public.quiz_questions to authenticated;
grant select on public.quiz_attempts to authenticated;

create or replace function public.save_quiz(
  target_quiz_id uuid,
  target_class_id uuid,
  target_calendar_event_id uuid,
  target_title text,
  target_instructions text,
  target_status text,
  target_due_at timestamptz,
  target_questions jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  saved_quiz_id uuid;
  question jsonb;
begin
  if not public.teacher_can_manage_class(target_class_id) then
    raise exception 'Du har ikke adgang til holdet.';
  end if;

  if trim(coalesce(target_title, '')) = '' then
    raise exception 'Quizzen skal have en titel.';
  end if;

  if target_status not in ('draft','published','closed') then
    raise exception 'Ugyldig status.';
  end if;

  if jsonb_array_length(coalesce(target_questions, '[]'::jsonb)) = 0 then
    raise exception 'Tilføj mindst ét spørgsmål.';
  end if;

  if target_calendar_event_id is not null and not exists (
    select 1
    from public.calendar_events event
    where event.id = target_calendar_event_id
      and event.class_id = target_class_id
  ) then
    raise exception 'Lektionen hører ikke til det valgte hold.';
  end if;

  if target_quiz_id is null then
    insert into public.quizzes (
      class_id,
      calendar_event_id,
      title,
      instructions,
      status,
      due_at,
      created_by
    )
    values (
      target_class_id,
      target_calendar_event_id,
      trim(target_title),
      nullif(trim(coalesce(target_instructions, '')), ''),
      target_status,
      target_due_at,
      auth.uid()
    )
    returning id into saved_quiz_id;
  else
    if not public.can_manage_quiz(target_quiz_id) then
      raise exception 'Du har ikke adgang til quizzen.';
    end if;

    update public.quizzes
    set
      class_id = target_class_id,
      calendar_event_id = target_calendar_event_id,
      title = trim(target_title),
      instructions = nullif(trim(coalesce(target_instructions, '')), ''),
      status = target_status,
      due_at = target_due_at,
      updated_at = now()
    where id = target_quiz_id
    returning id into saved_quiz_id;
  end if;

  delete from public.quiz_questions where quiz_id = saved_quiz_id;

  for question in
    select value from jsonb_array_elements(target_questions)
  loop
    if trim(coalesce(question->>'prompt', '')) = ''
      or trim(coalesce(question->>'option_a', '')) = ''
      or trim(coalesce(question->>'option_b', '')) = ''
      or trim(coalesce(question->>'option_c', '')) = ''
      or trim(coalesce(question->>'option_d', '')) = ''
      or coalesce(question->>'correct_option', '') not in ('a','b','c','d')
    then
      raise exception 'Alle spørgsmål og svarmuligheder skal udfyldes.';
    end if;

    insert into public.quiz_questions (
      quiz_id,
      position,
      prompt,
      option_a,
      option_b,
      option_c,
      option_d,
      correct_option,
      explanation
    )
    values (
      saved_quiz_id,
      (question->>'position')::integer,
      trim(question->>'prompt'),
      trim(question->>'option_a'),
      trim(question->>'option_b'),
      trim(question->>'option_c'),
      trim(question->>'option_d'),
      question->>'correct_option',
      nullif(trim(coalesce(question->>'explanation', '')), '')
    );
  end loop;

  return saved_quiz_id;
end;
$$;

create or replace function public.get_quiz_questions(target_quiz_id uuid)
returns table (
  id uuid,
  "position" integer,
  prompt text,
  options jsonb
)
language sql
stable
security definer
set search_path = public
as $$
  select
    question.id,
    question.position as "position",
    question.prompt,
    jsonb_build_object(
      'a', question.option_a,
      'b', question.option_b,
      'c', question.option_c,
      'd', question.option_d
    ) as options
  from public.quiz_questions question
  join public.quizzes quiz on quiz.id = question.quiz_id
  where question.quiz_id = target_quiz_id
    and exists (
      select 1
      from public.profiles profile
      where profile.id = auth.uid()
        and profile.role = 'student'
    )
    and public.can_access_quiz(quiz.id)
    and (
      quiz.status = 'published'
      or public.teacher_can_manage_class(quiz.class_id)
    )
  order by question.position;
$$;

create or replace function public.submit_quiz_attempt(
  target_quiz_id uuid,
  target_student_id uuid,
  submitted_answers jsonb
)
returns table (
  attempt_id uuid,
  result_score integer,
  result_total integer,
  result_review jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_quiz public.quizzes%rowtype;
  calculated_score integer;
  calculated_total integer;
  calculated_review jsonb;
  created_attempt_id uuid;
begin
  if not exists (
    select 1
    from public.profiles profile
    where profile.id = auth.uid()
      and profile.role = 'student'
  ) then
    raise exception 'Kun eleven kan aflevere quizzen.';
  end if;

  select * into selected_quiz
  from public.quizzes
  where id = target_quiz_id;

  if selected_quiz.id is null
    or selected_quiz.status <> 'published'
    or not public.can_access_class(selected_quiz.class_id)
  then
    raise exception 'Quizzen er ikke tilgængelig.';
  end if;

  if selected_quiz.due_at is not null and selected_quiz.due_at < now() then
    raise exception 'Fristen er udløbet.';
  end if;

  if not exists (
    select 1
    from public.students student
    where student.id = target_student_id
      and student.student_profile_id = auth.uid()
  ) then
    raise exception 'Quizzen skal besvares fra elevens egen konto.';
  end if;

  if not exists (
    select 1
    from public.class_enrollments enrollment
    where enrollment.class_id = selected_quiz.class_id
      and enrollment.student_id = target_student_id
  ) then
    raise exception 'Eleven er ikke tilmeldt holdet.';
  end if;

  if exists (
    select 1
    from public.quiz_attempts attempt
    where attempt.quiz_id = target_quiz_id
      and attempt.student_id = target_student_id
  ) then
    raise exception 'Læringstjekket er allerede besvaret.';
  end if;

  select
    count(*)::integer,
    count(*) filter (
      where submitted_answers ->> question.id::text = question.correct_option
    )::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'question_id', question.id,
          'position', question.position,
          'prompt', question.prompt,
          'selected', submitted_answers ->> question.id::text,
          'correct', question.correct_option,
          'options', jsonb_build_object(
            'a', question.option_a,
            'b', question.option_b,
            'c', question.option_c,
            'd', question.option_d
          ),
          'is_correct', submitted_answers ->> question.id::text = question.correct_option,
          'explanation', question.explanation
        )
        order by question.position
      ),
      '[]'::jsonb
    )
  into calculated_total, calculated_score, calculated_review
  from public.quiz_questions question
  where question.quiz_id = target_quiz_id;

  if calculated_total = 0 then
    raise exception 'Quizzen har ingen spørgsmål.';
  end if;

  if jsonb_object_length(coalesce(submitted_answers, '{}'::jsonb)) <> calculated_total then
    raise exception 'Alle spørgsmål skal besvares.';
  end if;

  insert into public.quiz_attempts (
    quiz_id,
    student_id,
    submitted_by,
    answers,
    answer_review,
    score,
    total
  )
  values (
    target_quiz_id,
    target_student_id,
    auth.uid(),
    submitted_answers,
    calculated_review,
    calculated_score,
    calculated_total
  )
  returning id into created_attempt_id;

  return query
  select created_attempt_id, calculated_score, calculated_total, calculated_review;
end;
$$;

revoke all on function public.get_quiz_questions(uuid) from public;
revoke all on function public.submit_quiz_attempt(uuid,uuid,jsonb) from public;
revoke all on function public.save_quiz(uuid,uuid,uuid,text,text,text,timestamptz,jsonb) from public;
grant execute on function public.get_quiz_questions(uuid) to authenticated;
grant execute on function public.submit_quiz_attempt(uuid,uuid,jsonb) to authenticated;
grant execute on function public.save_quiz(uuid,uuid,uuid,text,text,text,timestamptz,jsonb) to authenticated;
