-- Vocation SL — alerts for company and job approval (run after
-- approval_for_admin_accounts.sql, release_1_2.sql and employer_invoices.sql).
-- Safe to re-run.
--
-- Admins, owners and moderators get a "reviewAdmin" alert when a new company or
-- job is waiting for approval. The company's team gets a "review" alert when
-- an admin approves, declines or rejects their company or job.
-- Push alerts open the right screen, including invoice alerts again.

-- Tells everyone who can approve (moderator and above).
create or replace function public.notify_review_staff(p_title text, p_body text, p_job text) returns void
language sql security definer set search_path = public as $$
  insert into public.notifications (user_id, type, title, body, job_id)
  select a.user_id, 'reviewAdmin', p_title, left(p_body, 200), p_job
  from public.admins a where a.role in ('owner', 'admin', 'moderator');
$$;

-- Tells the company's hiring team.
create or replace function public.notify_company_team(p_company text, p_title text, p_body text, p_job text) returns void
language sql security definer set search_path = public as $$
  insert into public.notifications (user_id, type, title, body, job_id)
  select m.user_id, 'review', p_title, left(p_body, 200), p_job
  from public.company_members m where m.company_id = p_company;
$$;

revoke all on function public.notify_review_staff(text, text, text) from public, anon, authenticated;
revoke all on function public.notify_company_team(text, text, text, text) from public, anon, authenticated;

create or replace function public.review_alerts_company() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'pending' and (tg_op = 'INSERT' or old.status is distinct from 'pending') then
    perform public.notify_review_staff('New company to review', format('%s is waiting for approval.', new.name), null);
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    perform public.notify_company_team(new.id,
      case new.status
        when 'approved'  then 'Your company is approved'
        when 'rejected'  then 'Your company was not approved'
        when 'suspended' then 'Your company is suspended'
        else 'Company status updated' end,
      case new.status
        when 'approved'  then format('%s is approved on Vocation SL. Jobs you post now go to review or live, as set by our team.', new.name)
        when 'rejected'  then format('%s was not approved. Contact Vocation SL support to find out why.', new.name)
        when 'suspended' then format('%s is suspended. Contact Vocation SL support.', new.name)
        else format('%s: %s', new.name, new.status) end,
      null);
  end if;
  return null;
end $$;

drop trigger if exists review_alerts_company on public.companies;
create trigger review_alerts_company after insert or update of status on public.companies
  for each row execute function public.review_alerts_company();

create or replace function public.review_alerts_job() returns trigger
language plpgsql security definer set search_path = public as $$
declare cname text;
begin
  select name into cname from public.companies where id = new.company_id;
  if new.status = 'pending' and (tg_op = 'INSERT' or old.status is distinct from 'pending') then
    perform public.notify_review_staff('Job to review: ' || new.title,
      format('%s · %s', coalesce(cname, 'A company'), new.location), new.id);
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status in ('published', 'declined', 'rejected') then
    perform public.notify_company_team(new.company_id,
      case new.status
        when 'published' then 'Your job is live: '
        when 'declined'  then 'Changes needed: '
        else 'Job not approved: ' end || new.title,
      case new.status
        when 'published' then 'Job seekers can now see and apply for it.'
        when 'declined'  then coalesce(nullif(btrim(new.review_note), ''), 'Edit the job and submit it again.')
        else coalesce(nullif(btrim(new.review_note), ''), 'This job will not be published.') end,
      new.id);
  end if;
  return null;
end $$;

drop trigger if exists review_alerts_job on public.jobs;
create trigger review_alerts_job after insert or update of status on public.jobs
  for each row execute function public.review_alerts_job();

-- Push alerts open the right page (adds review and invoice routes).
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
  elsif new.type = 'invoice' then
    route := '/employer/invoices';
  elsif new.type = 'reviewAdmin' then
    route := case when new.job_id is not null then '/admin/jobs' else '/admin/employers' end;
  elsif new.type = 'review' then
    route := case when new.job_id is not null then '/employer/jobs' else '/employer/company' end;
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

notify pgrst, 'reload schema';
