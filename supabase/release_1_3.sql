-- Vocation SL — release 1.3 (run before deploying web 1.3.0). Safe to re-run.
--
--   1. Extend or repost a job in one tap: extend_job(job, weeks). The deadline
--      moves on by 1–4 weeks and a draft invoice for the extra weeks is created
--      at the extension price per week (platform setting, default SLE 1,000,
--      excluding GST) for an admin to issue. Employers who post free get a SLE 0
--      invoice marked paid. A closed job is reopened (reviewed first if the
--      company isn't approved). It is not emailed to job seekers again and gets
--      no second posting invoice.
--   2. Admins (moderator and up) can post a job on behalf of a company.
--   3. Weekly report email to employers: views, new applicants and how many job
--      seekers' profiles fit each live job. Data comes from
--      employer_weekly_data(); the Edge Function `employer-weekly` sends it every
--      Monday at 08:00 (Freetown time). Employers can unsubscribe
--      (profiles.weekly_report).
--   4. admin_analytics(): in-depth figures for Admin → Analytics.

-- ---------------------------------------------------------------------------
-- 1. Extend or repost a job
-- ---------------------------------------------------------------------------
insert into public.platform_settings (key, value) values ('extension_price', '1000')
on conflict (key) do nothing;

create or replace function public.extend_job(p_job text, p_weeks int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  j record;
  c record;
  price numeric;
  free_cos jsonb;
  is_free boolean;
  new_deadline timestamptz;
  saved record;
  num text;
  amount numeric;
begin
  if p_weeks is null or p_weeks < 1 or p_weeks > 4 then raise exception 'Choose 1 to 4 weeks.'; end if;
  select * into j from public.jobs where id = p_job;
  if j.id is null or not (public.is_company_member(j.company_id) or public.admin_level() >= 2) then
    raise exception 'Job not found.';
  end if;
  if public.is_suspended() then raise exception 'Your account is suspended.'; end if;
  if j.status not in ('published', 'closed') then
    raise exception 'Only live or closed jobs can be extended. Post the job first.';
  end if;
  select * into c from public.companies where id = j.company_id;
  if c.status in ('rejected', 'suspended') then raise exception 'This company can''t post jobs right now. Email info@vocationsl.com.'; end if;

  select coalesce((value#>>'{}')::numeric, 1000) into price from public.platform_settings where key = 'extension_price';
  price := coalesce(price, 1000);
  select coalesce(value, '[]') into free_cos from public.platform_settings where key = 'free_posting_companies';
  is_free := jsonb_typeof(free_cos) = 'array' and free_cos ? c.id;

  -- From today if the deadline has passed, otherwise from the current deadline. Ends at 23:59 Freetown time (UTC).
  new_deadline := date_trunc('day', greatest(j.deadline, now())) + make_interval(days => 7 * p_weeks) + interval '23 hours 59 minutes';

  update public.jobs set deadline = new_deadline,
                         status = case when status = 'closed' then 'published' else status end
  where id = j.id
  returning * into saved;

  amount := case when is_free then 0 else price * p_weeks end;
  insert into public.invoices (company_id, job_title, bill_to_name, bill_to_email, bill_to_address,
                               description, quantity, unit_price, status, payment_method, notes, paid_at, created_by)
  values (c.id, j.title, c.name, coalesce(c.email, ''), concat_ws(', ', nullif(c.address, ''), nullif(c.location, '')),
          format('Job listing extension: %s (%s %s)', j.title, p_weeks, case when p_weeks = 1 then 'week' else 'weeks' end),
          p_weeks, case when is_free then 0 else price end,
          case when is_free then 'paid' else 'draft' end,
          case when is_free then 'Free posting' else '' end,
          format('%s by %s %s to %s', case when j.status = 'closed' then 'Reposted' else 'Extended' end,
                 p_weeks, case when p_weeks = 1 then 'week' else 'weeks' end, to_char(new_deadline, 'DD Mon YYYY')),
          case when is_free then now() else null end, null)
  returning number into num;

  return jsonb_build_object('deadline', saved.deadline, 'status', saved.status, 'weeks', p_weeks,
                            'invoice', num, 'amount', amount, 'free', is_free);
end $$;
revoke all on function public.extend_job(text, int) from public, anon;
grant execute on function public.extend_job(text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Admins post jobs on behalf of a company ("Post it for me")
-- ---------------------------------------------------------------------------
drop policy if exists "moderators create jobs" on public.jobs;
create policy "moderators create jobs" on public.jobs for insert
  with check (public.admin_level() >= 2);

-- ---------------------------------------------------------------------------
-- 3. Weekly report email to employers
-- ---------------------------------------------------------------------------
alter table public.profiles add column if not exists weekly_report boolean not null default true;

create table if not exists public.job_view_snapshots (
  job_id   text not null,
  taken_at timestamptz not null default now(),
  views    int not null,
  primary key (job_id, taken_at)
);
alter table public.job_view_snapshots enable row level security;   -- server only

create table if not exists public.employer_weekly_log (
  id      bigint generated always as identity primary key,
  user_id uuid,
  sent_at timestamptz not null default now(),
  ok      boolean not null,
  error   text
);
alter table public.employer_weekly_log enable row level security;  -- server only

-- One row per person to email: their company and its live jobs (and jobs
-- closed in the last 7 days), with this week's numbers. p_commit saves this
-- week's view counts so next week can show the change.
create or replace function public.employer_weekly_data(p_commit boolean default false) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  result jsonb;
begin
  with js as (
    select j.*, c.name as company_name
    from public.jobs j join public.companies c on c.id = j.company_id
    where c.status = 'approved'
      and (j.status = 'published' or (j.status = 'closed' and j.updated_at > now() - interval '7 days'))
  ),
  seekers as (
    select p.id, coalesce(p.data->>'location', '') as loc
    from public.profiles p where p.role = 'seeker' and not coalesce(p.suspended, false)
  ),
  per_job as (
    select js.company_id, js.company_name, js.id, js.title, js.status, js.location, js.deadline, js.views,
      js.apply_url <> '' as external, js.apply_clicks, js.external_applied,
      js.views - (select s.views from public.job_view_snapshots s
                  where s.job_id = js.id and s.taken_at <= now() - interval '6 days'
                  order by s.taken_at desc limit 1) as views_week,
      case when js.posted_at > now() - interval '7 days' then js.views end as views_new_job,
      (select count(*) from public.applications a where a.job_id = js.id and a.status <> 'withdrawn') as applicants,
      (select count(*) from public.applications a where a.job_id = js.id and a.submitted_at > now() - interval '7 days') as new_applicants,
      (select count(*) from public.applications a where a.job_id = js.id and a.status = 'applied') as unanswered,
      (select count(*) from public.ai_embeddings je
         join public.ai_embeddings pe on pe.kind = 'profile' and pe.embedding is not null
         join seekers s on s.id::text = pe.ref_id
       where je.kind = 'job' and je.ref_id = js.id and je.embedding is not null
         and 1 - (pe.embedding <=> je.embedding) >= 0.84) as matching,
      (select count(*) from seekers s where lower(s.loc) = lower(js.location)) as in_town
    from js
  ),
  companies_out as (
    select company_id, company_name,
      jsonb_agg(jsonb_build_object(
        'id', id, 'title', title, 'status', status, 'location', location, 'deadline', deadline,
        'views', views, 'views_week', coalesce(views_week, views_new_job), 'external', external,
        'apply_clicks', apply_clicks, 'external_applied', external_applied,
        'applicants', applicants, 'new_applicants', new_applicants, 'unanswered', unanswered,
        'matching', matching, 'in_town', in_town) order by status = 'published' desc, deadline) as jobs
    from per_job group by company_id, company_name
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', p.id, 'email', p.email, 'name', coalesce(p.full_name, ''),
           'company', co.company_name, 'jobs', co.jobs)), '[]'::jsonb)
  into result
  from companies_out co
  join public.company_members m on m.company_id = co.company_id
  join public.profiles p on p.id = m.user_id
  where coalesce(p.weekly_report, true) and not coalesce(p.suspended, false) and coalesce(p.email, '') <> '';

  if p_commit then
    insert into public.job_view_snapshots (job_id, views)
    select id, views from public.jobs where status = 'published'
    on conflict do nothing;
  end if;
  return result;
end $$;
revoke all on function public.employer_weekly_data(boolean) from public, anon, authenticated;

create or replace function public.kick_employer_weekly() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  fn_url text;
  secret text;
begin
  select value into fn_url from private.push_config where key = 'employer_weekly_url';
  select value into secret from private.push_config where key = 'webhook_secret';
  if fn_url is null or secret is null then return; end if;
  perform net.http_post(
    url := fn_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', secret),
    timeout_milliseconds := 120000
  );
end $$;
revoke all on function public.kick_employer_weekly() from public, anon, authenticated;

insert into private.push_config (key, value)
values ('employer_weekly_url', 'https://gkglfqsvxyemykpnjxik.supabase.co/functions/v1/employer-weekly')
on conflict (key) do update set value = excluded.value;

do $$
begin
  perform cron.unschedule('vsl-employer-weekly') where exists (select 1 from cron.job where jobname = 'vsl-employer-weekly');
  perform cron.schedule('vsl-employer-weekly', '0 8 * * 1', 'select public.kick_employer_weekly()');
end $$;

-- ---------------------------------------------------------------------------
-- 4. Admin → Analytics
-- ---------------------------------------------------------------------------
create or replace function public.admin_analytics() returns jsonb
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  r jsonb;
begin
  if public.admin_level() < 1 then raise exception 'Admins only.' using errcode = '42501'; end if;

  with s as (select * from public.profiles where role = 'seeker'),
  a as (select * from public.applications),
  live as (select * from public.jobs where status = 'published'),
  first_reply as (
    select ap.id, extract(epoch from min(m.created_at) - ap.submitted_at) / 3600 as hours
    from public.applications ap join public.application_messages m on m.application_id = ap.id and m.sender_role = 'employer'
    group by ap.id, ap.submitted_at
  ),
  weeks as (select generate_series(date_trunc('week', now()) - interval '11 weeks', date_trunc('week', now()), interval '1 week') as wk)
  select jsonb_build_object(
    'generated_at', now(),

    'seekers', jsonb_build_object(
      'total', (select count(*) from s),
      'new_7d', (select count(*) from s where created_at > now() - interval '7 days'),
      'new_30d', (select count(*) from s where created_at > now() - interval '30 days'),
      'active_7d', (select count(*) from s where last_seen_at > now() - interval '7 days'),
      'active_30d', (select count(*) from s where last_seen_at > now() - interval '30 days'),
      'returned_after_1d', (select count(*) from s where last_seen_at > created_at + interval '1 day'),
      'returned_after_7d', (select count(*) from s where last_seen_at > created_at + interval '7 days')),

    'funnel', jsonb_build_object(
      'signed_up', (select count(*) from s),
      'basics', (select count(*) from s where coalesce(data->>'location', '') <> '' and coalesce(data->>'headline', '') <> ''),
      'cv', (select count(*) from s where coalesce(data->>'resume', '') not in ('', 'null')),
      'applied', (select count(distinct user_id) from a),
      'shortlisted', (select count(distinct user_id) from a where status in ('shortlisted', 'assessment', 'interview', 'hired')),
      'interviewed', (select count(distinct user_id) from a where status in ('interview', 'hired')),
      'hired', (select count(distinct user_id) from a where status = 'hired')),

    'profile', jsonb_build_object(
      'cv', (select count(*) from s where coalesce(data->>'resume', '') not in ('', 'null')),
      'skills', (select count(*) from s where jsonb_typeof(data->'skills') = 'array' and jsonb_array_length(data->'skills') > 0),
      'experience', (select count(*) from s where jsonb_typeof(data->'experience') = 'array' and jsonb_array_length(data->'experience') > 0),
      'education', (select count(*) from s where jsonb_typeof(data->'education') = 'array' and jsonb_array_length(data->'education') > 0),
      'headline', (select count(*) from s where coalesce(data->>'headline', '') <> ''),
      'location', (select count(*) from s where coalesce(data->>'location', '') <> ''),
      'phone', (select count(*) from s where coalesce(data->>'phone', '') <> ''),
      'photo', (select count(*) from s where coalesce(data->>'photo_base64', '') <> ''),
      'discoverable', (select count(*) from s where discoverable),
      'job_alert', (select count(distinct user_id) from public.job_alerts),
      'job_emails', (select count(*) from s where job_emails),
      'push', (select count(distinct t.user_id) from public.push_tokens t join s on s.id = t.user_id)),

    'weekly', (select jsonb_agg(jsonb_build_object(
        'week', to_char(wk, 'YYYY-MM-DD'),
        'seekers', (select count(*) from s where created_at >= wk and created_at < wk + interval '1 week'),
        'employers', (select count(*) from public.profiles p where p.role = 'employer' and p.created_at >= wk and p.created_at < wk + interval '1 week'),
        'applications', (select count(*) from a where submitted_at >= wk and submitted_at < wk + interval '1 week'),
        'jobs', (select count(*) from public.jobs j where j.posted_at >= wk and j.posted_at < wk + interval '1 week' and j.status in ('published', 'closed')),
        'returned_1d', (select count(*) from s where created_at >= wk and created_at < wk + interval '1 week' and last_seen_at > created_at + interval '1 day'))
        order by wk) from weeks),

    'districts', (select coalesce(jsonb_agg(x order by (x->>'seekers')::int desc), '[]') from (
        select jsonb_build_object('district', d,
          'seekers', (select count(*) from s where lower(coalesce(s.data->>'location', '')) = lower(d)),
          'live_jobs', (select count(*) from live where lower(live.location) = lower(d)),
          'applications', (select count(*) from a join public.jobs j on j.id = a.job_id where lower(j.location) = lower(d))) as x
        from (select distinct coalesce(nullif(data->>'location', ''), '(not set)') as d from s
              union select distinct location from public.jobs) ds) q),

    'industries', (select coalesce(jsonb_agg(jsonb_build_object('industry', industry, 'jobs', jobs, 'live_jobs', live_jobs, 'applications', apps, 'views', views) order by apps desc), '[]') from (
        select j.industry, count(*) as jobs, count(*) filter (where j.status = 'published') as live_jobs,
               sum(j.views) as views, (select count(*) from a join public.jobs j2 on j2.id = a.job_id where j2.industry = j.industry) as apps
        from public.jobs j where j.status in ('published', 'closed') group by j.industry) q),

    'jobs', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', j.id, 'title', j.title, 'company', c.name, 'location', j.location, 'status', j.status,
        'days_left', floor(extract(epoch from j.deadline - now()) / 86400),
        'views', j.views, 'external', j.apply_url <> '', 'apply_clicks', j.apply_clicks, 'external_applied', j.external_applied,
        'applicants', (select count(*) from a where a.job_id = j.id and a.status <> 'withdrawn'),
        'unanswered', (select count(*) from a where a.job_id = j.id and a.status = 'applied'),
        'salary', j.salary_max is not null or j.salary_min is not null,
        'matching', (select count(*) from public.ai_embeddings je join public.ai_embeddings pe on pe.kind = 'profile' and pe.embedding is not null
                     where je.kind = 'job' and je.ref_id = j.id and je.embedding is not null and 1 - (pe.embedding <=> je.embedding) >= 0.84))
        order by j.deadline), '[]')
      from live j join public.companies c on c.id = j.company_id),

    'job_totals', jsonb_build_object(
      'live', (select count(*) from live),
      'expired_still_live', (select count(*) from live where deadline < now()),
      'closing_7d', (select count(*) from live where deadline between now() and now() + interval '7 days'),
      'no_salary', (select count(*) from live where salary_max is null and salary_min is null),
      'pending_review', (select count(*) from public.jobs where status = 'pending'),
      'views', (select coalesce(sum(views), 0) from public.jobs),
      'in_app_views', (select coalesce(sum(views), 0) from public.jobs where apply_url = ''),
      'in_app_applications', (select count(*) from a join public.jobs j on j.id = a.job_id where j.apply_url = ''),
      'external_views', (select coalesce(sum(views), 0) from public.jobs where apply_url <> ''),
      'external_clicks', (select coalesce(sum(apply_clicks), 0) from public.jobs),
      'external_applied', (select coalesce(sum(external_applied), 0) from public.jobs)),

    'applications', jsonb_build_object(
      'total', (select count(*) from a),
      'by_status', (select coalesce(jsonb_object_agg(status, n), '{}') from (select status, count(*) n from a group by status) x),
      'untouched_7d', (select count(*) from a where status = 'applied' and submitted_at < now() - interval '7 days'),
      'median_first_reply_hours', (select round(percentile_cont(0.5) within group (order by hours)::numeric, 1) from first_reply),
      'replied', (select count(*) from first_reply),
      'saved_not_applied', (select count(*) from public.saved_jobs sj where not exists (select 1 from a where a.user_id = sj.user_id and a.job_id = sj.job_id)),
      'messages_30d', (select count(*) from public.application_messages where created_at > now() - interval '30 days')),

    'employers', jsonb_build_object(
      'accounts', (select count(*) from public.profiles where role = 'employer'),
      'companies', (select count(*) from public.companies),
      'no_company', (select count(*) from public.profiles p where p.role = 'employer'
                       and not exists (select 1 from public.company_members m where m.user_id = p.id)),
      'with_jobs', (select count(distinct company_id) from public.jobs where status in ('published', 'closed')),
      'with_live_jobs', (select count(distinct company_id) from live),
      'active_7d', (select count(*) from public.profiles where role = 'employer' and last_seen_at > now() - interval '7 days'),
      'list', (select coalesce(jsonb_agg(jsonb_build_object(
          'name', c.name, 'status', c.status, 'jobs', (select count(*) from public.jobs j where j.company_id = c.id and j.status in ('published', 'closed')),
          'live_jobs', (select count(*) from live where live.company_id = c.id),
          'applicants', (select count(*) from a join public.jobs j on j.id = a.job_id where j.company_id = c.id),
          'unanswered', (select count(*) from a join public.jobs j on j.id = a.job_id where j.company_id = c.id and a.status = 'applied'),
          'last_seen', (select max(p.last_seen_at) from public.company_members m join public.profiles p on p.id = m.user_id where m.company_id = c.id),
          'created_at', c.created_at) order by c.created_at desc), '[]') from public.companies c)),

    'notifications', jsonb_build_object(
      'sent_30d', (select count(*) from public.notifications where created_at > now() - interval '30 days'),
      'unread_30d', (select count(*) from public.notifications where created_at > now() - interval '30 days' and not read),
      'push_devices', (select coalesce(jsonb_object_agg(platform, n), '{}') from (select platform, count(*) n from public.push_tokens group by platform) x)),

    'emails', jsonb_build_object(
      'sent_7d', (select count(*) from public.job_email_log where ok and sent_at > now() - interval '7 days'),
      'failed_7d', (select count(*) from public.job_email_log where not ok and sent_at > now() - interval '7 days'),
      'sent_30d', (select count(*) from public.job_email_log where ok and sent_at > now() - interval '30 days'),
      'failed_30d', (select count(*) from public.job_email_log where not ok and sent_at > now() - interval '30 days'),
      'last_sent', (select max(sent_at) from public.job_email_log where ok),
      'waiting', (select count(*) from public.job_email_queue where sent_at is null and attempts < 3),
      'unsubscribed', (select count(*) from s where not job_emails),
      'employer_reports_last', (select max(sent_at) from public.employer_weekly_log where ok)),

    'revenue', jsonb_build_object(
      'by_status', (select coalesce(jsonb_object_agg(status, jsonb_build_object('count', n, 'total', t)), '{}')
                    from (select status, count(*) n, sum(total) t from public.invoices group by status) x),
      'free_postings', (select count(*) from public.invoices where status = 'paid' and total = 0),
      'paid_total', (select coalesce(sum(total), 0) from public.invoices where status = 'paid'),
      'unpaid_total', (select coalesce(sum(total), 0) from public.invoices where status = 'issued'),
      'draft_total', (select coalesce(sum(total), 0) from public.invoices where status = 'draft')),

    'referrals', (select coalesce(jsonb_object_agg(status, n), '{}') from (select status, count(*) n from public.referrals group by status) x)
  ) into r;
  return r;
end $$;
revoke all on function public.admin_analytics() from public, anon;
grant execute on function public.admin_analytics() to authenticated;

notify pgrst, 'reload schema';
