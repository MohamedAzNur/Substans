-- Substans: obligatorisk Sīrah-quiz om Makkah-perioden.
-- Scriptet kan køres igen. Det opdaterer den samme quiz i stedet for at oprette dubletter.

do $$
declare
  target_class_id uuid;
  target_quiz_id uuid;
begin
  select id
  into target_class_id
  from public.classes
  where status in ('active','planned')
  order by
    case when status = 'active' then 0 else 1 end,
    created_at
  limit 1;

  if target_class_id is null then
    insert into public.classes (name, capacity, status)
    values ('Grundforløb 1', 30, 'planned')
    returning id into target_class_id;
  end if;

  select id
  into target_quiz_id
  from public.quizzes
  where class_id = target_class_id
    and title = 'Sīrah: Makkah-perioden'
  limit 1;

  if target_quiz_id is null then
    insert into public.quizzes (
      class_id,
      title,
      instructions,
      status,
      created_by,
      updated_at
    )
    values (
      target_class_id,
      'Sīrah: Makkah-perioden',
      'Besvar alle 10 spørgsmål. Efter aflevering kan du se dit resultat, dine svar og forklaringen til hvert spørgsmål.',
      'published',
      auth.uid(),
      now()
    )
    returning id into target_quiz_id;
  else
    update public.quizzes
    set
      instructions = 'Besvar alle 10 spørgsmål. Efter aflevering kan du se dit resultat, dine svar og forklaringen til hvert spørgsmål.',
      status = 'published',
      due_at = null,
      updated_at = now()
    where id = target_quiz_id;

    delete from public.quiz_questions
    where quiz_id = target_quiz_id;
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
  values
    (
      target_quiz_id, 1,
      'Hvor befandt Profeten Muhammad ﷺ sig, da den første åbenbaring kom?',
      'I Kaʿbah', 'I hulen Ḥirāʾ', 'I Madinah', 'På bjerget Uḥud',
      'b',
      'Den første åbenbaring kom, mens Profeten ﷺ opholdt sig i hulen Ḥirāʾ uden for Makkah.'
    ),
    (
      target_quiz_id, 2,
      'Hvilken engel bragte den første åbenbaring?',
      'Mīkāʾīl', 'Isrāfīl', 'Jibrīl', 'Mālik',
      'c',
      'Englen Jibrīl bragte Allahs åbenbaring til Profeten Muhammad ﷺ.'
    ),
    (
      target_quiz_id, 3,
      'Hvad var det første ord i den første åbenbaring?',
      'Iqraʾ – Læs', 'Uṣbur – Vær tålmodig', 'Udhkur – Husk', 'Uʿbud – Tilbed',
      'a',
      'Den første åbenbaring begyndte med ordet “Iqraʾ” i Sūrah al-ʿAlaq.'
    ),
    (
      target_quiz_id, 4,
      'Hvem var den første, der troede på Profetens ﷺ budskab?',
      'Abū Bakr', 'ʿAlī ibn Abī Ṭālib', 'Khadījah bint Khuwaylid', 'Zayd ibn Ḥārithah',
      'c',
      'Khadījah støttede Profeten ﷺ og var den første, der troede på hans budskab.'
    ),
    (
      target_quiz_id, 5,
      'Hvor længe foregik den tidlige invitation til islam hovedsageligt i det skjulte?',
      'Cirka ét år', 'Cirka tre år', 'Cirka syv år', 'Cirka ti år',
      'b',
      'De tidlige muslimer blev undervist og inviterede forsigtigt i omtrent tre år, før kaldet blev mere offentligt.'
    ),
    (
      target_quiz_id, 6,
      'Hvad blev Dār al-Arqam især brugt til?',
      'Handel og opbevaring', 'Politiske forhandlinger med Quraysh', 'Undervisning og samling af de tidlige muslimer', 'Forberedelse af rejsen til Madinah',
      'c',
      'Dār al-Arqam var et trygt samlingssted, hvor de tidlige muslimer lærte om islam.'
    ),
    (
      target_quiz_id, 7,
      'Hvorfor udvandrede en gruppe muslimer til Abessinien?',
      'For at drive handel', 'For at undslippe forfølgelse og finde beskyttelse hos en retfærdig konge', 'For at bygge en moské', 'For at møde en muslimsk hær',
      'b',
      'Muslimerne søgte sikkerhed i Abessinien, fordi kongen dér var kendt for retfærdighed.'
    ),
    (
      target_quiz_id, 8,
      'Hvilke to nære støtter døde i “Sorgens år”?',
      'Ḥamzah og ʿUmar', 'Abū Bakr og ʿUthmān', 'Khadījah og Abū Ṭālib', 'ʿAlī og Zayd',
      'c',
      'Profeten ﷺ mistede sin hustru Khadījah og sin onkel og beskytter Abū Ṭālib i samme periode.'
    ),
    (
      target_quiz_id, 9,
      'Hvad blev gjort obligatorisk under al-Isrāʾ wal-Miʿrāj?',
      'Fasten i Ramaḍān', 'Zakāh', 'De fem daglige bønner', 'Ḥajj',
      'c',
      'De fem daglige bønner blev gjort obligatoriske i forbindelse med al-Isrāʾ wal-Miʿrāj.'
    ),
    (
      target_quiz_id, 10,
      'Hvilken begivenhed markerede afslutningen på Makkah-perioden?',
      'Slaget ved Badr', 'Hijrah til Madinah', 'Erobringen af Makkah', 'Hudaybiyah-aftalen',
      'b',
      'Makkah-perioden sluttede med Hijrah, hvor Profeten ﷺ og muslimerne udvandrede til Madinah.'
    );
end;
$$;
