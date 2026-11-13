-- 1.2.19: "Did you apply?" for jobs that take applications on the employer's
-- own website or by email. After tapping apply, signed-in job seekers are asked
-- when they come back to the app. One answer per person per job (latest wins).
-- Employers see totals in the hiring report; admins see platform totals.
-- Safe to run more than once.

create table if not exists public.external_apply_answers (
  job_id      text not null references public.jobs(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  answer      text not null check (answer in ('applied', 'not_yet', 'no')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (job_id, user_id)
);
create index if not exists external_apply_answers_user_idx on public.external_apply_answers (user_id);

alter table public.external_apply_answers enable row level security;
drop policy if exists "own answers" on public.external_apply_answers;
create policy "own answers" on public.external_apply_answers for select using (user_id = auth.uid());
-- No insert/update policies: answers are written only through record_external_apply().

-- "Yes, I applied" count per job, for the employer's job list.
alter table public.jobs add column if not exists external_applied int not null default 0;

-- Employers can't change the counters or the feature request themselves.
create or replace function public.jobs_protect_extras() returns trigger
language plpgsql as $$
begin
  if public.is_system_write() or public.admin_level() >= 2 then return new; end if;
  if tg_op = 'INSERT' then
    new.apply_clicks := 0; new.external_applied := 0; new.feature_requested_at := null;
  else
    new.apply_clicks := old.apply_clicks; new.external_applied := old.external_applied;
    new.feature_requested_at := old.feature_requested_at;
  end if;
  return new;
end $$;

create or replace function public.record_external_apply(p_job text, p_answer text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or p_answer not in ('applied', 'not_yet', 'no') then return; end if;
  if not exists (select 1 from public.jobs where id = p_job and apply_url <> '') then return; end if;
  insert into public.external_apply_answers (job_id, user_id, answer)
  values (p_job, auth.uid(), p_answer)
  on conflict (job_id, user_id) do update set answer = excluded.answer, updated_at = now();
  perform set_config('vsl.system', 'on', true);
  update public.jobs set external_applied =
    (select count(*) from public.external_apply_answers where job_id = p_job and answer = 'applied')
  where id = p_job;
  perform set_config('vsl.system', '', true);
end $$;
revoke all on function public.record_external_apply(text, text) from public, anon;
grant execute on function public.record_external_apply(text, text) to authenticated;

-- Hiring report: adds the answers (otherwise unchanged).
CREATE OR REPLACE FUNCTION public.job_report(p_job text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  ) || jsonb_build_object(
    'external', jsonb_build_object(
      'applied', (select count(*) from public.external_apply_answers where job_id = p_job and answer = 'applied'),
      'not_yet', (select count(*) from public.external_apply_answers where job_id = p_job and answer = 'not_yet'),
      'no',      (select count(*) from public.external_apply_answers where job_id = p_job and answer = 'no')),
    'external_by_day', coalesce((select jsonb_agg(jsonb_build_object('day', d, 'n', n) order by d) from (
                 select (updated_at at time zone 'Africa/Freetown')::date as d, count(*) as n
                 from public.external_apply_answers where job_id = p_job and answer = 'applied' group by 1) x), '[]'::jsonb)
  ) into r;
  return r;
end $function$;

-- Admin overview: adds apply taps and answers (otherwise unchanged).
CREATE OR REPLACE FUNCTION public.admin_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if public.admin_level() < 1 then raise exception 'Admins only'; end if;
  select jsonb_build_object(
    'users_total',        (select count(*) from public.profiles),
    'seekers',            (select count(*) from public.profiles where coalesce(role, 'seeker') = 'seeker'),
    'employers',          (select count(*) from public.profiles where role = 'employer'),
    'suspended',          (select count(*) from public.profiles where suspended),
    'new_users_7d',       (select count(*) from public.profiles where created_at > now() - interval '7 days'),
    'companies_total',    (select count(*) from public.companies),
    'companies_pending',  (select count(*) from public.companies where status = 'pending'),
    'jobs_total',         (select count(*) from public.jobs),
    'jobs_live',          (select count(*) from public.jobs where status = 'published' and deadline > now()),
    'jobs_pending',       (select count(*) from public.jobs where status = 'pending'),
    'applications_total', (select count(*) from public.applications),
    'applications_7d',    (select count(*) from public.applications where submitted_at > now() - interval '7 days'),
    'hires',              (select count(*) from public.applications where status = 'hired'),
    'reports_open',       (select count(*) from public.reports where status in ('open', 'reviewing')),
    'job_views',          (select coalesce(sum(views), 0) from public.jobs),
    'signups_30d',        (select coalesce(jsonb_agg(jsonb_build_object('day', d::date, 'count', c) order by d), '[]')
                           from (select gs as d, (select count(*) from public.profiles p where p.created_at::date = gs::date) as c
                                 from generate_series((current_date - 29)::timestamp, current_date::timestamp, interval '1 day') gs) x),
    'applications_30d',   (select coalesce(jsonb_agg(jsonb_build_object('day', d::date, 'count', c) order by d), '[]')
                           from (select gs as d, (select count(*) from public.applications a where a.submitted_at::date = gs::date) as c
                                 from generate_series((current_date - 29)::timestamp, current_date::timestamp, interval '1 day') gs) x),
    'jobs_30d',           (select coalesce(jsonb_agg(jsonb_build_object('day', d::date, 'count', c) order by d), '[]')
                           from (select gs as d, (select count(*) from public.jobs j where j.status <> 'draft' and j.posted_at::date = gs::date) as c
                                 from generate_series((current_date - 29)::timestamp, current_date::timestamp, interval '1 day') gs) x),
    'by_status',          (select coalesce(jsonb_object_agg(status, c), '{}') from (select status, count(*) c from public.applications group by status) s),
    'top_industries',     (select coalesce(jsonb_agg(jsonb_build_object('label', industry, 'count', c) order by c desc), '[]')
                           from (select industry, count(*) c from public.jobs where status = 'published' group by industry order by c desc limit 8) s),
    'top_locations',      (select coalesce(jsonb_agg(jsonb_build_object('label', location, 'count', c) order by c desc), '[]')
                           from (select location, count(*) c from public.jobs where status = 'published' group by location order by c desc limit 8) s),
    'top_companies',      (select coalesce(jsonb_agg(jsonb_build_object('label', name, 'count', c) order by c desc), '[]')
                           from (select co.name, count(a.id) c from public.companies co join public.jobs j on j.company_id = co.id
                                 join public.applications a on a.job_id = j.id group by co.name order by c desc limit 8) s)
  ) || jsonb_build_object(
    'active_users_7d',     (select count(*) from public.profiles where last_seen_at > now() - interval '7 days'),
    'companies_approved',  (select count(*) from public.companies where status = 'approved'),
    'companies_rejected',  (select count(*) from public.companies where status = 'rejected'),
    'companies_suspended', (select count(*) from public.companies where status = 'suspended'),
    'companies_verified',  (select count(*) from public.companies where verified),
    'jobs_draft',          (select count(*) from public.jobs where status = 'draft'),
    'jobs_closed',         (select count(*) from public.jobs where status = 'closed' or (status = 'published' and deadline <= now())),
    'jobs_closing_7d',     (select count(*) from public.jobs where status = 'published' and deadline > now() and deadline <= now() + interval '7 days'),
    'jobs_featured',       (select count(*) from public.jobs where featured and status = 'published'),
    'avg_salary',          (select coalesce(round(avg((coalesce(salary_min, salary_max) + coalesce(salary_max, salary_min)) / 2.0)), 0)
                            from public.jobs where status = 'published' and coalesce(salary_min, salary_max) is not null),
    'hires_30d',           (select count(*) from public.applications where status = 'hired' and updated_at > now() - interval '30 days'),
    'reports_total',       (select count(*) from public.reports),
    'avg_response_days',   (select round(avg(extract(epoch from ((x.h->>'at')::timestamptz - a.submitted_at)) / 86400)::numeric, 1)
                            from public.applications a
                            cross join lateral (select e as h from jsonb_array_elements(coalesce(a.data->'history', '[]'::jsonb)) e
                                                where e->>'status' not in ('applied', 'withdrawn') order by e->>'at' limit 1) x),
    'by_employment_type',  (select coalesce(jsonb_agg(jsonb_build_object('label', employment_type, 'count', c) order by c desc), '[]')
                            from (select employment_type, count(*) c from public.jobs where status = 'published' group by employment_type) s),
    'by_work_mode',        (select coalesce(jsonb_agg(jsonb_build_object('label', work_mode, 'count', c) order by c desc), '[]')
                            from (select work_mode, count(*) c from public.jobs where status = 'published' group by work_mode) s),
    'by_experience',       (select coalesce(jsonb_agg(jsonb_build_object('label', experience_level, 'count', c) order by c desc), '[]')
                            from (select experience_level, count(*) c from public.jobs where status = 'published' group by experience_level) s),
    'seeker_locations',    (select coalesce(jsonb_agg(jsonb_build_object('label', loc, 'count', c) order by c desc), '[]')
                            from (select coalesce(nullif(data->>'location', ''), 'Not set') loc, count(*) c from public.profiles
                                  where coalesce(role, 'seeker') = 'seeker' group by loc order by c desc limit 8) s),
    'reports_by_reason',   (select coalesce(jsonb_agg(jsonb_build_object('label', reason, 'count', c) order by c desc), '[]')
                            from (select reason, count(*) c from public.reports group by reason order by c desc limit 8) s)
  ) || jsonb_build_object(
    'apply_clicks_total',  (select coalesce(sum(apply_clicks), 0) from public.jobs),
    'external_applied',    (select count(*) from public.external_apply_answers where answer = 'applied'),
    'external_applied_7d', (select count(*) from public.external_apply_answers where answer = 'applied' and updated_at > now() - interval '7 days'),
    'external_answers',    (select count(*) from public.external_apply_answers)
  ) into result;
  return result;
end $function$;
