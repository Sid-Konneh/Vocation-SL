-- Vocation SL — permanently delete the sample companies and jobs.
-- Sample listings are the companies created by seed.sql, which have no owner
-- account. Deleting a company also deletes its jobs, any applications to
-- those jobs and their messages (database cascades). Real employers'
-- companies (with an owner) are not touched. This cannot be undone.

-- What will be deleted:
select c.name as sample_company,
       (select count(*) from public.jobs j where j.company_id = c.id) as jobs,
       (select count(*) from public.applications a join public.jobs j on j.id = a.job_id where j.company_id = c.id) as applications
from public.companies c
where c.owner_id is null
order by c.name;

do $$
begin
  perform set_config('vsl.system', 'on', true);
  delete from public.companies where owner_id is null;
  -- The demo account, if one was ever created on the live system.
  delete from auth.users where lower(email) in ('demo@vocationsl.app', 'demo@vocationsl.com');
  perform set_config('vsl.system', '', true);
end $$;

-- What's left:
select (select count(*) from public.companies) as companies,
       (select count(*) from public.jobs where status = 'published') as live_jobs;
