-- Vocation SL 1.2 — interview time slots and reminders, job alerts that are
-- actually sent, employer reply times, talent search with invitations, hiring
-- reports, the weekly admin digest and the support inbox.
-- Run once in the SQL editor before deploying 1.2. Safe to re-run.
--
-- Scheduled jobs (reminders, alert digests, weekly admin digest) use pg_cron. If the
-- block in section 9 prints "Scheduling skipped", enable pg_cron under
-- Database → Extensions and run section 9 again.

-- ---------------------------------------------------------------------------
-- 0. Helpers
-- ---------------------------------------------------------------------------

-- A timestamp from text, or null if the text isn't one (never errors).
create or replace function public.try_timestamptz(t text) returns timestamptz
language plpgsql stable as $$
begin
  return t::timestamptz;
exception when others then
  return null;
end $$;

-- Sierra Leone time (GMT all year), e.g. "Tue 21 Oct, 10:00".
create or replace function public.sl_time(t timestamptz) returns text
language sql stable as $$ select to_char(t at time zone 'Africa/Freetown', 'Dy DD Mon, HH24:MI') $$;

-- Whether an application's history reached any of the given stages.
create or replace function public.app_reached(d jsonb, stages text[]) returns boolean
language sql immutable as $$
  select exists (
    select 1 from jsonb_array_elements(case when jsonb_typeof(d->'history') = 'array' then d->'history' else '[]'::jsonb end) h
    where h->>'status' = any(stages));
$$;

-- ---------------------------------------------------------------------------
-- 1. Interview time slots: the employer offers up to 3 times, the applicant
--    picks one, and both are reminded about a day before.
-- ---------------------------------------------------------------------------

create table if not exists public.interview_proposals (
  id              uuid primary key default gen_random_uuid(),
  application_id  text not null references public.applications(id) on delete cascade,
  slots           timestamptz[] not null check (cardinality(slots) between 1 and 3),
  place           text not null default '',
  note            text not null default '',
  status          text not null default 'open' check (status in ('open', 'chosen', 'cancelled')),
  chosen_at       timestamptz,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now()
);
create index if not exists interview_proposals_app_idx on public.interview_proposals (application_id, created_at desc);

alter table public.interview_proposals enable row level security;
revoke all on public.interview_proposals from anon;
drop policy if exists "thread members read interview times" on public.interview_proposals;
create policy "thread members read interview times" on public.interview_proposals for select
  using (public.message_role(application_id) is not null or public.admin_level() >= 1);
-- Written only through the functions below.

create or replace function public.propose_interview(p_app text, p_slots timestamptz[], p_place text default '', p_note text default '')
returns uuid language plpgsql security definer set search_path = public as $$
declare
  a public.applications;
  s timestamptz[];
  pid uuid;
  job_title text;
  company text;
begin
  if public.message_role(p_app) is distinct from 'employer' then
    raise exception 'Only the hiring team can offer interview times.' using errcode = '42501';
  end if;
  if public.is_suspended() then raise exception 'Your account is suspended.' using errcode = '42501'; end if;
  select array_agg(distinct x order by x) into s from unnest(p_slots) x where x is not null;
  if coalesce(cardinality(s), 0) = 0 then raise exception 'Choose at least one interview time.'; end if;
  if cardinality(s) > 3 then raise exception 'Offer up to 3 interview times.'; end if;
  if exists (select 1 from unnest(s) x where x < now() + interval '1 hour') then
    raise exception 'Interview times must be at least an hour from now.';
  end if;
  if exists (select 1 from unnest(s) x where x > now() + interval '120 days') then
    raise exception 'Interview times must be within the next 4 months.';
  end if;
  if length(coalesce(p_place, '')) > 300 or length(coalesce(p_note, '')) > 1000 then
    raise exception 'The place or note is too long.';
  end if;

  select * into a from public.applications where id = p_app;
  if a.status in ('withdrawn', 'rejected', 'hired') then raise exception 'This application is closed.'; end if;

  -- New times replace any earlier offer.
  update public.interview_proposals set status = 'cancelled' where application_id = p_app and status in ('open', 'chosen');
  insert into public.interview_proposals (application_id, slots, place, note, created_by)
  values (p_app, s, btrim(coalesce(p_place, '')), btrim(coalesce(p_note, '')), auth.uid())
  returning id into pid;

  -- Earlier stages move to Interview (the status change notifies the
  -- applicant); a confirmed time from before is cleared.
  update public.applications
     set status = case when status in ('applied', 'viewed', 'shortlisted', 'assessment') then 'interview' else status end,
         data = jsonb_set(data, '{interview_at}', 'null'::jsonb)
   where id = p_app;

  if a.status not in ('applied', 'viewed', 'shortlisted', 'assessment') then
    select j.title, c.name into job_title, company
    from public.jobs j join public.companies c on c.id = j.company_id where j.id = a.job_id;
    insert into public.notifications (user_id, type, title, body, job_id, application_id)
    values (a.user_id, 'interview', 'Choose your interview time',
            format('%s offered %s time%s for %s.', company, cardinality(s), case when cardinality(s) = 1 then '' else 's' end, job_title),
            a.job_id, a.id);
  end if;
  return pid;
end $$;

create or replace function public.choose_interview_slot(p_proposal uuid, p_slot timestamptz)
returns void language plpgsql security definer set search_path = public as $$
declare
  p public.interview_proposals;
  a public.applications;
  job_title text;
begin
  select * into p from public.interview_proposals where id = p_proposal;
  if p.id is null then raise exception 'Interview times not found.'; end if;
  if public.message_role(p.application_id) is distinct from 'candidate' then
    raise exception 'Only the applicant can choose a time.' using errcode = '42501';
  end if;
  if p.status <> 'open' then
    raise exception 'These interview times are no longer available. Check your messages for an update.';
  end if;
  if not (p_slot = any(p.slots)) then raise exception 'Choose one of the times offered.'; end if;
  if p_slot < now() then raise exception 'That time has passed. Ask the employer for another time in your messages.'; end if;

  update public.interview_proposals set status = 'chosen', chosen_at = p_slot where id = p.id;
  select * into a from public.applications where id = p.application_id;
  update public.applications set data = jsonb_set(data, '{interview_at}', to_jsonb(p_slot)) where id = a.id;

  select title into job_title from public.jobs where id = a.job_id;
  insert into public.notifications (user_id, type, title, body, job_id, application_id)
  select m.user_id, 'interview', 'Interview time chosen',
         format('%s chose %s for %s.', coalesce(a.data->'applicant'->>'full_name', 'The candidate'), public.sl_time(p_slot), job_title),
         a.job_id, a.id
  from public.company_members m join public.jobs j on j.company_id = m.company_id
  where j.id = a.job_id;
end $$;

revoke all on function public.propose_interview(text, timestamptz[], text, text) from public, anon;
revoke all on function public.choose_interview_slot(uuid, timestamptz) from public, anon;
grant execute on function public.propose_interview(text, timestamptz[], text, text) to authenticated;
grant execute on function public.choose_interview_slot(uuid, timestamptz) to authenticated;

-- Reminders: one per interview time, sent once.
create table if not exists public.interview_reminders (
  application_id  text not null references public.applications(id) on delete cascade,
  interview_at    timestamptz not null,
  sent_at         timestamptz not null default now(),
  primary key (application_id, interview_at)
);
alter table public.interview_reminders enable row level security;
revoke all on public.interview_reminders from anon, authenticated;

-- Runs every hour: reminds the applicant and the hiring team about
-- interviews in the next 24 hours (chosen slots and interviews the employer
-- scheduled directly).
create or replace function public.send_interview_reminders() returns int
language plpgsql security definer set search_path = public as $$
declare
  r record;
  n int := 0;
begin
  for r in
    select distinct on (x.app_id, x.at) x.app_id, x.at, a.user_id, a.job_id, j.title, c.name as company, c.id as company_id,
           coalesce(a.data->'applicant'->>'full_name', 'The candidate') as candidate
    from (
      select p.application_id as app_id, p.chosen_at as at
      from public.interview_proposals p
      where p.status = 'chosen' and p.chosen_at between now() and now() + interval '24 hours'
      union
      select a2.id, public.try_timestamptz(a2.data->>'interview_at')
      from public.applications a2
      where a2.status = 'interview'
        and public.try_timestamptz(a2.data->>'interview_at') between now() and now() + interval '24 hours'
    ) x
    join public.applications a on a.id = x.app_id
    join public.jobs j on j.id = a.job_id
    join public.companies c on c.id = j.company_id
    where a.status not in ('withdrawn', 'rejected', 'hired')
  loop
    insert into public.interview_reminders (application_id, interview_at) values (r.app_id, r.at) on conflict do nothing;
    if found then
      insert into public.notifications (user_id, type, title, body, job_id, application_id)
      values (r.user_id, 'interview', 'Interview reminder', format('%s at %s · %s', r.title, r.company, public.sl_time(r.at)), r.job_id, r.app_id);
      insert into public.notifications (user_id, type, title, body, job_id, application_id)
      select m.user_id, 'interview', 'Interview reminder', format('%s · %s · %s', r.candidate, r.title, public.sl_time(r.at)), r.job_id, r.app_id
      from public.company_members m where m.company_id = r.company_id;
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.send_interview_reminders() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Job alerts: saved searches now send notifications (and push alerts).
--    Instant alerts go out when a job goes live; daily and weekly alerts are
--    grouped into one notification.
-- ---------------------------------------------------------------------------

alter table public.job_alerts add column if not exists last_sent_at timestamptz;

-- Whether a JobFilter (as saved by the app) matches a job.
create or replace function public.alert_matches(f jsonb, j public.jobs, company_name text) returns boolean
language plpgsql stable as $$
declare
  q text := lower(btrim(coalesce(f->>'query', '')));
  hay text;
  t text;
begin
  if f is null or jsonb_typeof(f) <> 'object' then return false; end if;
  if jsonb_typeof(f->'locations') = 'array' and jsonb_array_length(f->'locations') > 0 and not (f->'locations') ? j.location then return false; end if;
  if jsonb_typeof(f->'industries') = 'array' and jsonb_array_length(f->'industries') > 0 and not (f->'industries') ? j.industry then return false; end if;
  if jsonb_typeof(f->'employment_types') = 'array' and jsonb_array_length(f->'employment_types') > 0 and not (f->'employment_types') ? j.employment_type then return false; end if;
  if jsonb_typeof(f->'work_modes') = 'array' and jsonb_array_length(f->'work_modes') > 0 and not (f->'work_modes') ? j.work_mode then return false; end if;
  if jsonb_typeof(f->'experience_levels') = 'array' and jsonb_array_length(f->'experience_levels') > 0 and not (f->'experience_levels') ? j.experience_level then return false; end if;
  if jsonb_typeof(f->'min_salary') = 'number' and coalesce(j.salary_max, j.salary_min, 0) < (f->>'min_salary')::numeric then return false; end if;
  if coalesce(f->>'company_id', '') <> '' and j.company_id <> f->>'company_id' then return false; end if;
  if q <> '' then
    hay := lower(concat_ws(' ', j.title, company_name, j.location, j.industry, j.skills::text));
    foreach t in array regexp_split_to_array(q, '\s+') loop
      if position(t in hay) = 0 then return false; end if;
    end loop;
  end if;
  return true;
end $$;

create or replace function public.job_alerts_on_publish() returns trigger
language plpgsql security definer set search_path = public as $$
declare cname text;
begin
  if new.status = 'published' and (tg_op = 'INSERT' or old.status is distinct from 'published') and new.deadline > now() then
    select name into cname from public.companies where id = new.company_id;
    insert into public.notifications (user_id, type, title, body, job_id)
    select distinct on (a.user_id) a.user_id, 'savedSearch', 'New job: ' || new.title,
           format('%s · %s · matches your alert "%s"', cname, new.location, coalesce(a.data->>'name', 'Saved search')), new.id
    from public.job_alerts a
    where coalesce((a.data->>'enabled')::boolean, true)
      and coalesce(a.data->>'frequency', 'daily') = 'instant'
      and public.alert_matches(a.data->'filter', new, cname)
      and not exists (select 1 from public.company_members m where m.company_id = new.company_id and m.user_id = a.user_id)
      and not exists (select 1 from public.notifications n where n.user_id = a.user_id and n.job_id = new.id and n.type = 'savedSearch')
    order by a.user_id;
  end if;
  return null;
exception when others then
  return null; -- alerts must never stop a job from going live
end $$;

drop trigger if exists job_alerts_on_publish on public.jobs;
create trigger job_alerts_on_publish after insert or update of status on public.jobs
  for each row execute function public.job_alerts_on_publish();

-- Runs every morning: one notification per daily alert (and per weekly alert
-- once a week) listing the new matching jobs.
create or replace function public.send_job_alert_digests() returns int
language plpgsql security definer set search_path = public as $$
declare
  a record;
  since timestamptz;
  n int;
  first_id text;
  first_title text;
  first_company text;
  sent int := 0;
begin
  for a in
    select * from public.job_alerts
    where coalesce((data->>'enabled')::boolean, true) and coalesce(data->>'frequency', 'daily') in ('daily', 'weekly')
  loop
    since := coalesce(a.last_sent_at, public.try_timestamptz(a.data->>'created_at'), a.created_at);
    if a.data->>'frequency' = 'weekly' and since > now() - interval '167 hours' then continue; end if;
    if coalesce(a.data->>'frequency', 'daily') = 'daily' and since > now() - interval '23 hours' then continue; end if;

    select count(*), (array_agg(j.id order by j.posted_at desc))[1], (array_agg(j.title order by j.posted_at desc))[1],
           (array_agg(c.name order by j.posted_at desc))[1]
      into n, first_id, first_title, first_company
    from public.jobs j join public.companies c on c.id = j.company_id
    where j.status = 'published' and j.deadline > now() and j.posted_at > since
      and public.alert_matches(a.data->'filter', j, c.name)
      and not exists (select 1 from public.company_members m where m.company_id = j.company_id and m.user_id = a.user_id);

    if n > 0 then
      insert into public.notifications (user_id, type, title, body, job_id)
      values (a.user_id, 'savedSearch',
              case when n = 1 then format('New job for "%s"', coalesce(a.data->>'name', 'your alert'))
                   else format('%s new jobs for "%s"', n, coalesce(a.data->>'name', 'your alert')) end,
              case when n = 1 then format('%s · %s', first_title, first_company)
                   else format('%s at %s and %s more', first_title, first_company, n - 1) end,
              case when n = 1 then first_id end);
      sent := sent + 1;
    end if;
    update public.job_alerts set last_sent_at = now() where id = a.id;
  end loop;
  return sent;
end $$;
revoke all on function public.send_job_alert_digests() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. How quickly an employer usually replies (for applicants)
-- ---------------------------------------------------------------------------
-- Counts only; no applicant details leave the database.
create or replace function public.employer_reply_speed(p_company text) returns jsonb
language sql stable security definer set search_path = public as $$
  with apps as (
    select a.submitted_at,
           least(
             (select min(public.try_timestamptz(h->>'at'))
              from jsonb_array_elements(case when jsonb_typeof(a.data->'history') = 'array' then a.data->'history' else '[]'::jsonb end) h
              where h->>'status' not in ('applied', 'withdrawn')),
             (select min(m.created_at) from public.application_messages m where m.application_id = a.id and m.sender_role = 'employer')
           ) as first_reply
    from public.applications a join public.jobs j on j.id = a.job_id
    where j.company_id = p_company and a.submitted_at > now() - interval '180 days' and a.status <> 'withdrawn'
  ), replied as (
    select extract(epoch from (first_reply - submitted_at)) / 3600.0 as hrs from apps where first_reply is not null
  )
  select jsonb_build_object(
    'applications', (select count(*) from apps),
    'replied', (select count(*) from replied),
    'median_hours', (select percentile_cont(0.5) within group (order by hrs) from replied),
    'replied_within_7_days', (select count(*) from replied where hrs <= 168)
  );
$$;
revoke all on function public.employer_reply_speed(text) from public, anon;
grant execute on function public.employer_reply_speed(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Talent search: job seekers choose to be found; approved employers search
--    a short summary and invite people to apply. Contact details stay private
--    until the person applies.
-- ---------------------------------------------------------------------------

alter table public.profiles add column if not exists discoverable boolean not null default false;

create table if not exists public.talent_invites (
  id          uuid primary key default gen_random_uuid(),
  company_id  text not null references public.companies(id) on delete cascade,
  job_id      text not null references public.jobs(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  note        text not null default '',
  invited_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (job_id, user_id)
);
create index if not exists talent_invites_company_idx on public.talent_invites (company_id, created_at desc);

alter table public.talent_invites enable row level security;
revoke all on public.talent_invites from anon;
drop policy if exists "companies read their invites" on public.talent_invites;
create policy "companies read their invites" on public.talent_invites for select
  using (public.is_company_member(company_id) or user_id = auth.uid() or public.admin_level() >= 1);

create or replace function public.search_talent(p_query text default '', p_location text default '', p_industry text default '',
                                                p_limit int default 30, p_offset int default 0)
returns table (user_id uuid, full_name text, headline text, location text, about text, skills jsonb,
               experience jsonb, education jsonb, languages jsonb, updated_at timestamptz, invited_jobs text[])
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  cid text;
  q text := lower(btrim(coalesce(p_query, '')));
begin
  select m.company_id into cid
  from public.company_members m join public.companies c on c.id = m.company_id
  where m.user_id = auth.uid() and c.status = 'approved' limit 1;
  if cid is null then raise exception 'Talent search opens once your company is approved.' using errcode = '42501'; end if;

  return query
  select p.id, coalesce(nullif(p.data->>'full_name', ''), p.full_name, ''),
         coalesce(p.data->>'headline', ''), coalesce(p.data->>'location', ''), left(coalesce(p.data->>'about', ''), 400),
         case when jsonb_typeof(p.data->'skills') = 'array' then p.data->'skills' else '[]'::jsonb end,
         coalesce((select jsonb_agg(jsonb_build_object('title', e->>'title', 'company', e->>'company', 'start', e->>'start', 'end', e->'end'))
                   from (select e from jsonb_array_elements(case when jsonb_typeof(p.data->'experience') = 'array' then p.data->'experience' else '[]'::jsonb end) e limit 4) x), '[]'::jsonb),
         coalesce((select jsonb_agg(jsonb_build_object('degree', e->>'degree', 'field', e->>'field', 'school', e->>'school', 'end_year', e->'end_year'))
                   from (select e from jsonb_array_elements(case when jsonb_typeof(p.data->'education') = 'array' then p.data->'education' else '[]'::jsonb end) e limit 3) x), '[]'::jsonb),
         case when jsonb_typeof(p.data->'languages') = 'array' then p.data->'languages' else '[]'::jsonb end,
         p.updated_at,
         coalesce((select array_agg(ti.job_id) from public.talent_invites ti where ti.user_id = p.id and ti.company_id = cid), '{}')
  from public.profiles p
  where p.discoverable
    and not p.suspended
    and p.id <> auth.uid()
    -- One account can be both a job seeker and an employer; hide only your own team.
    and not exists (select 1 from public.company_members m where m.user_id = p.id and m.company_id = cid)
    and (coalesce(p_location, '') = '' or p.data->>'location' = p_location
         or (jsonb_typeof(p.data->'preferences'->'locations') = 'array' and (p.data->'preferences'->'locations') ? p_location))
    and (coalesce(p_industry, '') = ''
         or (jsonb_typeof(p.data->'preferences'->'industries') = 'array' and (p.data->'preferences'->'industries') ? p_industry))
    and (q = '' or not exists (
          select 1 from unnest(regexp_split_to_array(q, '\s+')) t
          where position(t in lower(concat_ws(' ', p.data->>'full_name', p.data->>'headline', p.data->>'about', p.data->>'location',
                                              (p.data->'skills')::text, (p.data->'experience')::text, (p.data->'education')::text))) = 0))
  order by p.updated_at desc
  limit least(greatest(coalesce(p_limit, 30), 1), 50) offset greatest(coalesce(p_offset, 0), 0);
end $$;

create or replace function public.invite_to_apply(p_user uuid, p_job text, p_note text default '')
returns void language plpgsql security definer set search_path = public as $$
declare
  j public.jobs;
  cname text;
  today int;
begin
  select * into j from public.jobs where id = p_job;
  if j.id is null or not public.is_company_member(j.company_id) then raise exception 'Job not found.' using errcode = '42501'; end if;
  if public.is_suspended() then raise exception 'Your account is suspended.' using errcode = '42501'; end if;
  if j.status <> 'published' or j.deadline <= now() then raise exception 'You can invite people to live jobs only.'; end if;
  if not exists (select 1 from public.profiles where id = p_user and discoverable and not suspended) then
    raise exception 'This person is no longer open to invitations.';
  end if;
  if exists (select 1 from public.applications where user_id = p_user and job_id = p_job and status <> 'withdrawn') then
    raise exception 'They have already applied for this job.';
  end if;
  if exists (select 1 from public.talent_invites where user_id = p_user and job_id = p_job) then
    raise exception 'You''ve already invited them to this job.';
  end if;
  select count(*) into today from public.talent_invites where company_id = j.company_id and created_at > now() - interval '1 day';
  if today >= 30 then raise exception 'You can send up to 30 invitations a day. Try again tomorrow.'; end if;
  if length(coalesce(p_note, '')) > 500 then raise exception 'Keep the note under 500 characters.'; end if;

  insert into public.talent_invites (company_id, job_id, user_id, note, invited_by)
  values (j.company_id, j.id, p_user, btrim(coalesce(p_note, '')), auth.uid());
  select name into cname from public.companies where id = j.company_id;
  insert into public.notifications (user_id, type, title, body, job_id)
  values (p_user, 'invite', format('%s invited you to apply', cname),
          case when btrim(coalesce(p_note, '')) = '' then format('%s · %s. Tap to see the job.', j.title, j.location)
               else format('%s · %s', j.title, left(btrim(p_note), 160)) end,
          j.id);
end $$;

-- The full profile of someone who chose to be found, for approved employers.
-- Phone, email and CV are left out: they're shared when the person applies.
create or replace function public.talent_profile(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  d jsonb;
begin
  if not exists (select 1 from public.company_members m join public.companies c on c.id = m.company_id
                 where m.user_id = auth.uid() and c.status = 'approved') then
    raise exception 'Talent search opens once your company is approved.' using errcode = '42501';
  end if;
  select p.data || jsonb_build_object('id', p.id, 'full_name', coalesce(nullif(p.data->>'full_name', ''), p.full_name, ''),
                                      'updated_at', p.updated_at)
    into d
  from public.profiles p
  where p.id = p_user and p.discoverable and not p.suspended;
  if d is null then raise exception 'This person is no longer open to employers.'; end if;
  return d - 'email' - 'phone' - 'resume' - 'notification_preferences';
end $$;
revoke all on function public.talent_profile(uuid) from public, anon;
grant execute on function public.talent_profile(uuid) to authenticated;

revoke all on function public.search_talent(text, text, text, int, int) from public, anon;
revoke all on function public.invite_to_apply(uuid, text, text) from public, anon;
grant execute on function public.search_talent(text, text, text, int, int) to authenticated;
grant execute on function public.invite_to_apply(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Hiring report per job (views, applications, stages, sources, speed)
-- ---------------------------------------------------------------------------
-- Applications record where the applicant found the job in data->>'source'
-- (from 1.2 on; older applications show as "not recorded").
create or replace function public.job_report(p_job text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  j public.jobs;
  r jsonb;
begin
  select * into j from public.jobs where id = p_job;
  if j.id is null or not (public.is_company_member(j.company_id) or public.admin_level() >= 1) then
    raise exception 'Job not found.' using errcode = '42501';
  end if;

  with apps as (
    select a.id, a.user_id, a.status, a.submitted_at, a.data,
           least(
             (select min(public.try_timestamptz(h->>'at'))
              from jsonb_array_elements(case when jsonb_typeof(a.data->'history') = 'array' then a.data->'history' else '[]'::jsonb end) h
              where h->>'status' not in ('applied', 'withdrawn')),
             (select min(m.created_at) from public.application_messages m where m.application_id = a.id and m.sender_role = 'employer')
           ) as first_reply,
           (select min(public.try_timestamptz(h->>'at'))
            from jsonb_array_elements(case when jsonb_typeof(a.data->'history') = 'array' then a.data->'history' else '[]'::jsonb end) h
            where h->>'status' = 'hired') as hired_at
    from public.applications a where a.job_id = p_job
  ), replied as (
    select extract(epoch from (first_reply - submitted_at)) / 3600.0 as hrs from apps where first_reply is not null
  )
  select jsonb_build_object(
    'job_id', j.id,
    'title', j.title,
    'status', j.status,
    'location', j.location,
    'posted_at', j.posted_at,
    'deadline', j.deadline,
    'views', j.views,
    'apply_clicks', coalesce(j.apply_clicks, 0),
    'applies_externally', coalesce(j.apply_url, '') <> '',
    'applications', (select count(*) from apps),
    'withdrawn', (select count(*) from apps where status = 'withdrawn'),
    'current', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) as n from apps group by status) s), '{}'::jsonb),
    'reached', jsonb_build_object(
      'shortlisted', (select count(*) from apps where public.app_reached(data, array['shortlisted', 'assessment', 'interview', 'offer', 'hired'])),
      'interview',   (select count(*) from apps where public.app_reached(data, array['interview', 'offer', 'hired'])),
      'offer',       (select count(*) from apps where public.app_reached(data, array['offer', 'hired'])),
      'hired',       (select count(*) from apps where public.app_reached(data, array['hired']) or status = 'hired')),
    'sources', coalesce((select jsonb_object_agg(src, n) from (
                 select coalesce(nullif(data->>'source', ''), 'unknown') as src, count(*) as n from apps group by 1) s), '{}'::jsonb),
    'invites_sent', (select count(*) from public.talent_invites where job_id = p_job),
    'invited_applied', (select count(*) from apps where user_id in (select ti.user_id from public.talent_invites ti where ti.job_id = p_job)),
    'replied', (select count(*) from replied),
    'median_reply_hours', (select percentile_cont(0.5) within group (order by hrs) from replied),
    'first_hire_days', (select extract(epoch from (min(hired_at) - j.posted_at)) / 86400.0 from apps where hired_at is not null),
    'by_day', coalesce((select jsonb_agg(jsonb_build_object('day', d, 'n', n) order by d) from (
                 select (submitted_at at time zone 'Africa/Freetown')::date as d, count(*) as n from apps group by 1) x), '[]'::jsonb),
    'generated_at', now()
  ) into r;
  return r;
end $$;
revoke all on function public.job_report(text) from public, anon;
grant execute on function public.job_report(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Support inbox: users write to the Vocation SL team in the app
-- ---------------------------------------------------------------------------

create table if not exists public.support_tickets (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  subject          text not null check (length(btrim(subject)) between 3 and 150),
  category         text not null default 'other'
                   check (category in ('account', 'jobs', 'applications', 'employer', 'payment', 'scam', 'bug', 'other')),
  side             text not null default 'seeker' check (side in ('seeker', 'employer')),
  status           text not null default 'open' check (status in ('open', 'answered', 'closed')),
  created_at       timestamptz not null default now(),
  last_message_at  timestamptz not null default now()
);
create index if not exists support_tickets_user_idx on public.support_tickets (user_id, last_message_at desc);
create index if not exists support_tickets_status_idx on public.support_tickets (status, last_message_at desc);

create table if not exists public.support_messages (
  id          uuid primary key default gen_random_uuid(),
  ticket_id   uuid not null references public.support_tickets(id) on delete cascade,
  sender_id   uuid references auth.users(id) on delete set null,
  from_staff  boolean not null default false,
  body        text not null check (length(btrim(body)) between 1 and 4000),
  created_at  timestamptz not null default now()
);
create index if not exists support_messages_ticket_idx on public.support_messages (ticket_id, created_at);

alter table public.support_tickets enable row level security;
alter table public.support_messages enable row level security;
revoke all on public.support_tickets from anon;
revoke all on public.support_messages from anon;
drop policy if exists "own or staff read tickets" on public.support_tickets;
create policy "own or staff read tickets" on public.support_tickets for select
  using (user_id = auth.uid() or public.admin_level() >= 1);
drop policy if exists "own or staff read support messages" on public.support_messages;
create policy "own or staff read support messages" on public.support_messages for select
  using (exists (select 1 from public.support_tickets t where t.id = ticket_id and (t.user_id = auth.uid() or public.admin_level() >= 1)));
-- Written only through the functions below.

-- Tells moderators and above about new requests and replies.
create or replace function public.notify_support_staff(p_title text, p_body text) returns void
language sql security definer set search_path = public as $$
  insert into public.notifications (user_id, type, title, body)
  select a.user_id, 'supportAdmin', p_title, left(p_body, 200) from public.admins a where a.role in ('owner', 'admin', 'moderator');
$$;
revoke all on function public.notify_support_staff(text, text) from public, anon, authenticated;

create or replace function public.open_support_ticket(p_subject text, p_category text, p_body text, p_side text default 'seeker')
returns uuid language plpgsql security definer set search_path = public as $$
declare
  tid uuid;
  recent int;
begin
  if auth.uid() is null then raise exception 'Sign in first.' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_body, ''))) < 10 then raise exception 'Tell us a little more (at least 10 characters).'; end if;
  select count(*) into recent from public.support_tickets where user_id = auth.uid() and created_at > now() - interval '1 day';
  if recent >= 5 then raise exception 'You''ve sent 5 requests today. Reply in an existing request, or try again tomorrow.'; end if;

  insert into public.support_tickets (user_id, subject, category, side)
  values (auth.uid(), btrim(p_subject),
          case when p_category in ('account', 'jobs', 'applications', 'employer', 'payment', 'scam', 'bug', 'other') then p_category else 'other' end,
          case when p_side = 'employer' then 'employer' else 'seeker' end)
  returning id into tid;
  insert into public.support_messages (ticket_id, sender_id, from_staff, body) values (tid, auth.uid(), false, btrim(p_body));
  perform public.notify_support_staff('New support request', btrim(p_subject));
  return tid;
end $$;

create or replace function public.reply_support(p_ticket uuid, p_body text)
returns void language plpgsql security definer set search_path = public as $$
declare
  t public.support_tickets;
  staff boolean := public.admin_level() >= 2;
begin
  select * into t from public.support_tickets where id = p_ticket;
  if t.id is null or not (staff or t.user_id = auth.uid()) then raise exception 'Request not found.' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_body, ''))) = 0 then raise exception 'Write a message first.'; end if;
  -- Staff reply as the team; the owner of the request replies as themselves.
  staff := staff and t.user_id <> auth.uid();
  insert into public.support_messages (ticket_id, sender_id, from_staff, body) values (t.id, auth.uid(), staff, btrim(p_body));
  update public.support_tickets set status = case when staff then 'answered' else 'open' end, last_message_at = now() where id = t.id;
  if staff then
    insert into public.notifications (user_id, type, title, body)
    values (t.user_id, 'support', 'Reply from Vocation SL support', left(t.subject || ': ' || btrim(p_body), 200));
  else
    perform public.notify_support_staff('Support reply', t.subject);
  end if;
end $$;

create or replace function public.set_support_status(p_ticket uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare t public.support_tickets;
begin
  select * into t from public.support_tickets where id = p_ticket;
  if t.id is null or not (public.admin_level() >= 2 or t.user_id = auth.uid()) then raise exception 'Request not found.' using errcode = '42501'; end if;
  if p_status not in ('open', 'answered', 'closed') then raise exception 'Unknown status.'; end if;
  if public.admin_level() < 2 and p_status <> 'closed' and p_status <> 'open' then raise exception 'Not allowed.'; end if;
  update public.support_tickets set status = p_status where id = t.id;
end $$;

revoke all on function public.open_support_ticket(text, text, text, text) from public, anon;
revoke all on function public.reply_support(uuid, text) from public, anon;
revoke all on function public.set_support_status(uuid, text) from public, anon;
grant execute on function public.open_support_ticket(text, text, text, text) to authenticated;
grant execute on function public.reply_support(uuid, text) to authenticated;
grant execute on function public.set_support_status(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Weekly admin digest (Admin → Weekly digest, plus a Monday notification)
-- ---------------------------------------------------------------------------

create or replace function public.admin_weekly_digest() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  since timestamptz := now() - interval '7 days';
  prev  timestamptz := now() - interval '14 days';
begin
  if not (public.admin_level() >= 1) then
    raise exception 'Admins only.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'from', since,
    'to', now(),
    'new_users',            (select count(*) from public.profiles where created_at >= since),
    'new_users_prev',       (select count(*) from public.profiles where created_at >= prev and created_at < since),
    'new_employers',        (select count(*) from public.companies where created_at >= since),
    'new_employers_prev',   (select count(*) from public.companies where created_at >= prev and created_at < since),
    'new_employer_names',   coalesce((select jsonb_agg(name order by created_at desc) from (
                               select name, created_at from public.companies where created_at >= since order by created_at desc limit 10) c), '[]'::jsonb),
    'companies_pending',    (select count(*) from public.companies where status = 'pending'),
    'jobs_new',             (select count(*) from public.jobs where status = 'published' and posted_at >= since),
    'jobs_new_prev',        (select count(*) from public.jobs where status in ('published', 'closed') and posted_at >= prev and posted_at < since),
    'jobs_pending',         (select count(*) from public.jobs where status = 'pending'),
    'jobs_live',            (select count(*) from public.jobs where status = 'published' and deadline > now()),
    'applications',         (select count(*) from public.applications where submitted_at >= since),
    'applications_prev',    (select count(*) from public.applications where submitted_at >= prev and submitted_at < since),
    'revenue_paid',         (select coalesce(sum(total), 0) from public.invoices where status = 'paid' and paid_at >= since),
    'revenue_paid_prev',    (select coalesce(sum(total), 0) from public.invoices where status = 'paid' and paid_at >= prev and paid_at < since),
    'unpaid_count',         (select count(*) from public.invoices where status = 'issued'),
    'unpaid_total',         (select coalesce(sum(total), 0) from public.invoices where status = 'issued'),
    'overdue_count',        (select count(*) from public.invoices where status = 'issued' and due_date < current_date),
    'reports_open',         (select count(*) from public.reports where status in ('open', 'reviewing')),
    'flagged_jobs',         (select count(*) from public.jobs
                             where status in ('pending', 'published') and posted_at >= since
                               and lower(concat_ws(' ', title, about, description, requirements::text, benefits::text, apply_url))
                                   ~ '(registration|application|processing|training|medical|uniform|interview|form)\s+(fee|fees|charge)|mobile money pin|bank details|wa\.me/|whatsapp only|bit\.ly|tinyurl'),
    'support_open',         (select count(*) from public.support_tickets where status = 'open'),
    'referrals_to_pay',     (select count(*) from public.referrals where status = 'qualified')
  );
end $$;
revoke all on function public.admin_weekly_digest() from public, anon;
grant execute on function public.admin_weekly_digest() to authenticated;

-- Monday mornings (pg_cron): a notification to every owner and admin that
-- opens Admin → Weekly digest. No email is sent.
create or replace function public.send_weekly_digest() returns int
language plpgsql security definer set search_path = public as $$
declare
  since timestamptz := now() - interval '7 days';
  apps int;
  jobs int;
  employers int;
  paid numeric;
  unpaid int;
  n int;
begin
  -- pg_cron runs without a signed-in user; people need admin rights.
  if auth.uid() is not null and public.admin_level() < 3 then
    raise exception 'Only admins can send the digest.' using errcode = '42501';
  end if;
  select count(*) into apps from public.applications where submitted_at >= since;
  select count(*) into jobs from public.jobs where status = 'published' and posted_at >= since;
  select count(*) into employers from public.companies where created_at >= since;
  select coalesce(sum(total), 0) into paid from public.invoices where status = 'paid' and paid_at >= since;
  select count(*) into unpaid from public.invoices where status = 'issued';
  insert into public.notifications (user_id, type, title, body)
  select a.user_id, 'digest', 'Your weekly digest',
         format('%s applications · %s new jobs · %s new employers · SLE %s received · %s unpaid invoices',
                apps, jobs, employers, to_char(paid, 'FM999,999,999'), unpaid)
  from public.admins a where a.role in ('owner', 'admin');
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.send_weekly_digest() from public, anon;
grant execute on function public.send_weekly_digest() to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Push alerts open the right page for the new alert types
-- ---------------------------------------------------------------------------

create or replace function public.push_on_notification() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare
  fn_url text;
  secret text;
  prefs  jsonb;
  route  text := '/alerts';
  app_owner uuid;
begin
  select value into fn_url from private.push_config where key = 'function_url';
  select value into secret from private.push_config where key = 'webhook_secret';
  if fn_url is null or secret is null then return null; end if;
  if not exists (select 1 from public.push_tokens where user_id = new.user_id) then return null; end if;

  -- Respect the user's notification settings.
  select data->'notification_preferences' into prefs from public.profiles where id = new.user_id;
  if coalesce((prefs->>'push_enabled')::boolean, true) = false then return null; end if;
  if coalesce((prefs->'enabled'->>new.type)::boolean, true) = false then return null; end if;

  if new.type = 'support' then
    route := '/support';
  elsif new.type = 'supportAdmin' then
    route := '/admin/support';
  elsif new.type = 'digest' then
    route := '/admin/digest';
  elsif new.application_id is not null then
    -- Employers go to the candidate; job seekers go to their alerts.
    select user_id into app_owner from public.applications where id = new.application_id;
    if app_owner is distinct from new.user_id then route := '/employer/candidates/' || new.application_id; end if;
  elsif new.job_id is not null and new.type in ('savedSearch', 'invite', 'newMatch') then
    route := '/job/' || new.job_id;
  end if;

  perform net.http_post(
    url := fn_url,
    body := jsonb_build_object(
      'user_id', new.user_id, 'title', new.title, 'body', new.body, 'type', new.type,
      'notification_id', new.id, 'application_id', new.application_id, 'job_id', new.job_id, 'route', route),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', secret),
    timeout_milliseconds := 5000
  );
  return null;
exception when others then
  return null;
end $$;

-- ---------------------------------------------------------------------------
-- 9. Schedules (Freetown time = UTC)
-- ---------------------------------------------------------------------------
do $$
begin
  create extension if not exists pg_cron with schema pg_catalog;
  perform cron.schedule('vsl-interview-reminders', '15 * * * *', 'select public.send_interview_reminders()');
  perform cron.schedule('vsl-job-alert-digests', '0 8 * * *', 'select public.send_job_alert_digests()');
  perform cron.schedule('vsl-weekly-digest', '0 7 * * 1', 'select public.send_weekly_digest()');
exception when others then
  raise notice 'Scheduling skipped (%). Enable pg_cron under Database → Extensions, then run section 9 again.', sqlerrm;
end $$;

notify pgrst, 'reload schema';
