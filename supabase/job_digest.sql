-- Vocation SL — job alert emails as a twice-weekly round-up (run after job_emails.sql). Safe to re-run.
--
-- Before: every job was queued for every job seeker as soon as it went live, so
-- each job meant up to ~600 emails, and Hostinger allows about 100 a day.
-- Now:
--   * Going live no longer queues emails.
--   * Every Monday and Thursday at 07:00 (Freetown), queue_job_digest() queues
--     each job seeker the jobs that went live in the last 7 days and are open
--     for at least another day. Each job still reaches a person at most once
--     (primary key user_id + job_id).
--   * The job-emails function (unchanged) sends one email per person with up to
--     10 jobs, slowly, within the daily cap. People who used the app most
--     recently are queued first, so they hear first.
--   With ~600 job seekers and ~100 emails a day, each person gets about one
--   email a week.

create or replace function public.job_emails_on_publish() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- Jobs are emailed in the twice-weekly round-up (queue_job_digest), not one by one.
  return null;
end $$;

create or replace function public.queue_job_digest(p_days int default 7) returns int
language plpgsql security definer set search_path = public as $$
declare
  n int;
begin
  if auth.uid() is not null and public.admin_level() < 3 then
    raise exception 'Only admins can queue the job round-up.' using errcode = '42501';
  end if;
  with people as (
    select p.id, row_number() over (order by p.last_seen_at desc nulls last, p.created_at desc) as rn
    from public.profiles p
    where p.id in (select public.job_email_recipients())
  ),
  fresh as (
    select j.id from public.jobs j
    where j.status = 'published'
      and j.deadline > now() + interval '1 day'
      and j.posted_at > now() - make_interval(days => p_days)
  )
  insert into public.job_email_queue (user_id, job_id, queued_at)
  -- Most recently active people get the earliest place in the queue.
  select people.id, fresh.id, now() - interval '10 minutes' - make_interval(secs => 100000 - people.rn)
  from people cross join fresh
  on conflict (user_id, job_id) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.queue_job_digest(int) from public, anon;
grant execute on function public.queue_job_digest(int) to authenticated;

do $$
begin
  perform cron.unschedule('vsl-job-digest') where exists (select 1 from cron.job where jobname = 'vsl-job-digest');
  perform cron.schedule('vsl-job-digest', '0 7 * * 1,4', 'select public.queue_job_digest(7)');
end $$;

notify pgrst, 'reload schema';
