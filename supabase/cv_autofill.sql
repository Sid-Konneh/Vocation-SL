-- Vocation SL — "Fill my profile from my CV" (run after schema.sql). Safe to re-run.
-- Counts CV reads so each person is limited to a few per day (see the
-- parse-cv Edge Function). Only the Edge Function (service role) uses it.

create table if not exists public.cv_reads (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);
create index if not exists cv_reads_user_idx on public.cv_reads (user_id, created_at desc);

alter table public.cv_reads enable row level security;
revoke all on public.cv_reads from anon, authenticated;

-- Privacy Policy: say that CVs are read by an AI service when the user asks.
update public.site_pages
set body = replace(body,
  'Service providers: we use trusted providers to host our database, files and website, and Google if you choose to sign in with Google.',
  'Service providers: we use trusted providers to host our database, files and website, Google if you choose to sign in with Google, and Anthropic''s Claude AI to read your CV when you tap "Fill my profile from my CV".'),
    updated_at = now()
where slug = 'privacy';

notify pgrst, 'reload schema';
