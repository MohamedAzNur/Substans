# Substans

Offentlig hjemmeside og Substans Campus V3.

## V3-filer

- `index.html` — offentlig hjemmeside og eksisterende ansøgningsformular
- `login.html` — Supabase Auth-login
- `admin.html` — rollebeskyttet administration af ansøgninger
- `portal.html` — portal for elev, forælder og underviser
- `reminders.html` — indstillinger og historik for automatiske lektionspåmindelser
- `video.html` — sikker videoafspiller med elevens faktiske seertid og fortsæt-funktion
- `supabase-v3.sql` — profiles-tabel, roller og RLS-politikker

## Aktivering

1. Kør `supabase-v3.sql` i Supabase SQL Editor.
2. Opret en bruger under Authentication.
3. Kør den sidste, kommenterede SQL-linje med brugerens e-mail for at gøre brugeren til admin.
4. Åbn `login.html`.

## Automatisk påmindelsesagent

Kør `reminder-agent-setup.sql` i Supabase SQL Editor på en eksisterende V3-installation.
Agenten kontrollerer undervisningsplanen hvert femte minut og sender som standard en
intern holdbesked tre timer før undervisningen. Tidspunkt og tekst kan ændres pr. hold
på `reminders.html`. Samme hold får højst én automatisk påmindelse pr. undervisningsdag.

## Videolektioner og seertid

Kør `video-tracking-setup.sql` i Supabase SQL Editor på en eksisterende V3-installation.
Underviseren kan derefter indsætte et YouTube-link eller uploade en videofil på
`resources.html`. Elevens faktisk afspillede intervaller, samlede procent, seneste
position og gennemført-status gemmes i `video_watch_progress`. Forældre har læseadgang,
mens kun elevens egen konto kan skrive fremgang.

Production er ikke ændret, før branchen merges til `main`.
