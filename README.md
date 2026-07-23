# Substans

Offentlig hjemmeside og Substans Campus V3.

## V3-filer

- `index.html` — offentlig hjemmeside og eksisterende ansøgningsformular
- `login.html` — Supabase Auth-login
- `admin.html` — rollebeskyttet administration af ansøgninger
- `portal.html` — portal for elev, forælder og underviser
- `supabase-v3.sql` — profiles-tabel, roller og RLS-politikker

## Aktivering

1. Kør `supabase-v3.sql` i Supabase SQL Editor.
2. Opret en bruger under Authentication.
3. Kør den sidste, kommenterede SQL-linje med brugerens e-mail for at gøre brugeren til admin.
4. Åbn `login.html`.

Production er ikke ændret, før branchen merges til `main`.
