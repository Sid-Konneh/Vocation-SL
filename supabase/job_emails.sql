-- Vocation SL — job alert emails. Safe to re-run.
--
-- Every time a job goes live, everyone with a Vocation SL account (except
-- employer accounts) gets an email with a link to the job in the app.
-- People can turn the emails off in the app (Notification settings → Job emails)
-- or with the unsubscribe link at the bottom of every email.
--
-- How it works:
--   1. A trigger on public.jobs queues (person, job) pairs when a job goes live.
--   2. pg_cron runs every minute and, when something is waiting, calls the
--      "job-emails" Edge Function, which sends the emails through Hostinger
--      (info@vocationsl.com). Jobs waiting for the same person go in one email.
--   3. The function sends slowly: at most 40 emails an hour and 800 in any 24
--      hours, and pauses 15 minutes when Hostinger says "rate limit" (it blocked
--      us after about 90 emails in 4 minutes). Sign-in emails use the same
--      mailbox, so they need room too. Anything over that is sent later.
--
-- The on/off choice is its own column (not inside profiles.data) because older
-- app versions rewrite profiles.data when saving a profile.

alter table public.profiles add column if not exists job_emails boolean not null default true;

create table if not exists public.job_email_queue (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  job_id     text not null references public.jobs(id) on delete cascade,
  queued_at  timestamptz not null default now(),
  sent_at    timestamptz,
  attempts   int not null default 0,
  error      text,
  primary key (user_id, job_id)
);
create index if not exists job_email_queue_pending_idx on public.job_email_queue (queued_at) where sent_at is null;

create table if not exists public.job_email_log (
  id         bigserial primary key,
  user_id    uuid references public.profiles(id) on delete set null,
  sent_at    timestamptz not null default now(),
  jobs       int not null,
  ok         boolean not null,
  error      text
);
create index if not exists job_email_log_sent_idx on public.job_email_log (sent_at);

-- Only the Edge Function (service role) and admins read these tables.
alter table public.job_email_queue enable row level security;
alter table public.job_email_log enable row level security;
revoke all on public.job_email_queue from anon, authenticated;
revoke all on public.job_email_log from anon, authenticated;
grant select on public.job_email_queue, public.job_email_log to authenticated;
drop policy if exists "admins read job email queue" on public.job_email_queue;
create policy "admins read job email queue" on public.job_email_queue for select using (public.admin_level() >= 1);
drop policy if exists "admins read job email log" on public.job_email_log;
create policy "admins read job email log" on public.job_email_log for select using (public.admin_level() >= 1);

-- Who gets job emails.
create or replace function public.job_email_recipients() returns setof uuid
language sql stable security definer set search_path = public as $$
  select p.id from public.profiles p
  where p.job_emails
    and coalesce(p.suspended, false) = false
    and p.role is distinct from 'employer'
    and p.email like '%_@_%._%';
  -- Apple "Hide My Email" addresses are included since 8 Nov 2026: vocationsl.com
  -- and jobs@vocationsl.com are registered with Apple's private email relay.
$$;
revoke all on function public.job_email_recipients() from public, anon, authenticated;

-- Queue a job for everyone when it goes live. Never stops the job going live.
create or replace function public.job_emails_on_publish() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'published' and (tg_op = 'INSERT' or old.status is distinct from 'published') then
    insert into public.job_email_queue (user_id, job_id)
    select r, new.id from public.job_email_recipients() r
    on conflict (user_id, job_id) do nothing;   -- a job re-published later is not emailed twice
  end if;
  return null;
exception when others then
  return null;
end $$;

drop trigger if exists job_emails_on_publish on public.jobs;
create trigger job_emails_on_publish after insert or update of status on public.jobs
  for each row execute function public.job_emails_on_publish();

-- Someone who turns job emails off stops getting the ones still waiting.
create or replace function public.job_emails_off() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.job_emails = false and old.job_emails = true then
    delete from public.job_email_queue where user_id = new.id and sent_at is null;
  end if;
  return null;
end $$;

drop trigger if exists job_emails_off on public.profiles;
create trigger job_emails_off after update of job_emails on public.profiles
  for each row execute function public.job_emails_off();

-- Called every minute by pg_cron: wakes the Edge Function only when there is
-- something to send (waiting at least 5 minutes, so jobs approved together
-- go in one email).
create or replace function public.kick_job_emails() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  fn_url text;
  secret text;
begin
  if not exists (select 1 from public.job_email_queue where sent_at is null and attempts < 3
                 and queued_at < now() - interval '5 minutes') then
    return;
  end if;
  select value into fn_url from private.push_config where key = 'job_emails_url';
  select value into secret from private.push_config where key = 'webhook_secret';
  if fn_url is null or secret is null then return; end if;
  perform net.http_post(
    url := fn_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', secret),
    timeout_milliseconds := 60000
  );
end $$;
revoke all on function public.kick_job_emails() from public, anon, authenticated;

insert into private.push_config (key, value)
values ('job_emails_url', 'https://gkglfqsvxyemykpnjxik.supabase.co/functions/v1/job-emails')
on conflict (key) do update set value = excluded.value;

do $$
begin
  perform cron.unschedule('vsl-job-emails') where exists (select 1 from cron.job where jobname = 'vsl-job-emails');
  perform cron.schedule('vsl-job-emails', '* * * * *', 'select public.kick_job_emails()');
end $$;

notify pgrst, 'reload schema';
