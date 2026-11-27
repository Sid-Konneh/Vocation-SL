-- Vocation SL: deadlines and closing a hiring process (owner's request, 27 Nov 2026).
--
--   1. No applications after the deadline. A job takes applications only while
--      it is live (status 'published') and its deadline has not passed. When the
--      employer extends the job (extend_job), the deadline moves and
--      applications open again.
--   2. Employers can close a candidate's hiring process after their final
--      decision, and reopen it if anything changes. While it is closed:
--        * neither side can send messages on that application;
--        * the stage can't be changed (the candidate can still withdraw).
--      The candidate gets a notification when it is closed or reopened.
--   3. Deadline reminders: once a day (09:00 Freetown), every job seeker gets
--      ONE notification (in the app and as a push) listing the live jobs that
--      close in the next 2 days and that they haven't applied to. It respects
--      the "Deadline reminders" switch in Notification settings.
--
-- Run this in the Supabase SQL editor BEFORE deploying the web app that uses
-- it. Safe to run more than once.

-- ---------------------------------------------------------------------------
-- 1. No applications after the deadline
-- ---------------------------------------------------------------------------
create or replace function public.applications_open_check() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  j record;
begin
  -- The service role and the SQL editor (no signed-in user) are not limited.
  if auth.uid() is null then return new; end if;
  select status, deadline into j from public.jobs where id = new.job_id;
  if not found then
    raise exception 'This job is no longer available.' using errcode = 'P0001';
  end if;
  if j.status <> 'published' or j.deadline <= now() then
    raise exception 'Applications for this job have closed.' using errcode = 'P0001';
  end if;
  return new;
end $$;

drop trigger if exists applications_open_check on public.applications;
create trigger applications_open_check before insert on public.applications
  for each row execute function public.applications_open_check();

-- ---------------------------------------------------------------------------
-- 2. Close or reopen a candidate's hiring process
-- ---------------------------------------------------------------------------
alter table public.applications add column if not exists process_closed_at timestamptz;
alter table public.applications add column if not exists process_closed_by uuid references auth.users(id) on delete set null;

create or replace function public.application_process_closed(app_id text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.applications where id = app_id and process_closed_at is not null);
$$;
revoke all on function public.application_process_closed(text) from public, anon;
grant execute on function public.application_process_closed(text) to authenticated;

-- Employers only. Returns {"closed": bool, "closed_at": timestamptz}.
create or replace function public.set_hiring_process_closed(app_id text, p_closed boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r text := public.message_role(app_id);
  a public.applications;
  job_title text;
  company text;
begin
  if r is distinct from 'employer' then
    raise exception 'Only the employer can close or reopen the hiring process.' using errcode = '42501';
  end if;
  if public.is_suspended() then raise exception 'Your account is suspended.' using errcode = '42501'; end if;

  select * into a from public.applications where id = app_id for update;
  if p_closed = (a.process_closed_at is not null) then
    return jsonb_build_object('closed', p_closed, 'closed_at', a.process_closed_at);
  end if;

  update public.applications
     set process_closed_at = case when p_closed then now() end,
         process_closed_by = case when p_closed then auth.uid() end
   where id = app_id
  returning * into a;

  if a.status <> 'withdrawn' then
    select j.title, c.name into job_title, company
    from public.jobs j join public.companies c on c.id = j.company_id where j.id = a.job_id;
    insert into public.notifications (user_id, type, title, body, job_id, application_id)
    values (a.user_id, 'statusChange',
            case when p_closed then 'Hiring process closed' else 'Hiring process reopened' end,
            case when p_closed
                 then format('%s has closed the hiring process for %s. Messages are now off.', company, job_title)
                 else format('%s has reopened the hiring process for %s.', company, job_title) end,
            a.job_id, a.id);
  end if;

  return jsonb_build_object('closed', p_closed, 'closed_at', a.process_closed_at);
end $$;
revoke all on function public.set_hiring_process_closed(text, boolean) from public, anon;
grant execute on function public.set_hiring_process_closed(text, boolean) to authenticated;

-- No stage changes while closed (withdrawing, and "viewed" when an employer
-- opens the candidate, are still allowed).
create or replace function public.applications_closed_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  if auth.uid() is not null
     and old.process_closed_at is not null and new.process_closed_at is not null
     and new.status is distinct from old.status
     and new.status not in ('withdrawn', 'viewed') then
    raise exception 'This hiring process is closed. Reopen it to make changes.' using errcode = 'P0001';
  end if;
  return new;
end $$;

drop trigger if exists applications_closed_guard on public.applications;
create trigger applications_closed_guard before update on public.applications
  for each row execute function public.applications_closed_guard();

-- The conversation status now also says whether the process is closed.
create or replace function public.conversation_status(app_id text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r text := public.message_role(app_id);
  cp record;
  closed_at timestamptz;
begin
  if r is null then raise exception 'You are not part of this conversation.'; end if;
  select * into cp from public.conversation_parties(app_id);
  select process_closed_at into closed_at from public.applications where id = app_id;
  return jsonb_build_object(
    'blocked_by_me', exists (select 1 from public.conversation_blocks where company_id = cp.company_id and user_id = cp.user_id and blocked_by = r),
    'blocked_by_them', exists (select 1 from public.conversation_blocks where company_id = cp.company_id and user_id = cp.user_id and blocked_by <> r),
    'process_closed', closed_at is not null,
    'process_closed_at', closed_at);
end $$;
revoke all on function public.conversation_status(text) from public, anon;
grant execute on function public.conversation_status(text) to authenticated;

-- No new messages once either side has blocked, or the process is closed.
drop policy if exists "thread members send messages" on public.application_messages;
create policy "thread members send messages" on public.application_messages for insert to authenticated
  with check (public.message_role(application_id) is not null
              and not public.conversation_blocked(application_id)
              and not public.application_process_closed(application_id));

-- ---------------------------------------------------------------------------
-- 3. Daily deadline reminders for every job seeker
-- ---------------------------------------------------------------------------
create or replace function public.send_deadline_reminders() returns integer
language plpgsql security definer set search_path = public as $$
declare
  sent integer;
begin
  with closing as (
    select j.id, j.title, j.location, j.deadline
    from public.jobs j
    where j.status = 'published' and j.deadline > now() and j.deadline <= now() + interval '2 days'
  ), targets as (
    select p.id as user_id, c.id as job_id, c.title, c.location, c.deadline
    from public.profiles p cross join closing c
    where p.role = 'seeker'
      and not coalesce(p.suspended, false)
      and coalesce((p.data->'notification_preferences'->'enabled'->>'deadline')::boolean, true)
      and not exists (select 1 from public.company_members m where m.user_id = p.id)
      and not exists (select 1 from public.applications a
                      where a.user_id = p.id and a.job_id = c.id and a.status <> 'withdrawn')
  ), per_user as (
    select t.user_id,
           count(*) as jobs,
           (array_agg(t.job_id order by t.deadline))[1] as first_job,
           (array_agg(t.title order by t.deadline))[1] as first_title,
           (array_agg(nullif(t.location, '') order by t.deadline))[1] as first_location,
           min(t.deadline) as first_deadline,
           string_agg(t.title || coalesce(' (' || nullif(t.location, '') || ')', ''), ', ' order by t.deadline) as list
    from targets t
    group by t.user_id
  )
  insert into public.notifications (user_id, type, title, body, job_id)
  select u.user_id, 'deadline',
         case when u.jobs = 1 then left('Closing soon: ' || u.first_title, 120)
              else u.jobs || ' jobs close in the next 2 days' end,
         case when u.jobs = 1
              then concat_ws(' · ', u.first_location, 'apply by ' || to_char(u.first_deadline, 'FMDD Mon'))
              else case when length(u.list) > 220 then left(u.list, 217) || '...' else u.list end end,
         case when u.jobs = 1 then u.first_job end
  from per_user u
  where not exists (select 1 from public.notifications x
                    where x.user_id = u.user_id and x.type = 'deadline' and x.created_at > now() - interval '20 hours');
  get diagnostics sent = row_count;
  return sent;
end $$;
revoke all on function public.send_deadline_reminders() from public, anon, authenticated;

do $$
begin
  perform cron.unschedule('vsl-deadline-reminders') where exists (select 1 from cron.job where jobname = 'vsl-deadline-reminders');
  perform cron.schedule('vsl-deadline-reminders', '0 9 * * *', 'select public.send_deadline_reminders()');
end $$;

notify pgrst, 'reload schema';
