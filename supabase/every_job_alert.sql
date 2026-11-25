-- Vocation SL — "Alert me about every new job" (user's request, 25 Nov 2026).
-- Every job seeker gets an in-app alert, and a push notification on their
-- phone (Android/iPhone) or browser (web), each time a job goes live.
-- On by default; switched off in Notification settings (profiles.every_job_alerts,
-- its own column because old app versions rewrite profiles.data). The push
-- still respects push on/off and the "Saved searches" type switch.
-- Safe to re-run.

alter table public.profiles add column if not exists every_job_alerts boolean not null default true;

create or replace function public.jobs_every_job_alert() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  co text;
  body text;
begin
  if new.status <> 'published' or new.deadline <= now() then return null; end if;
  if tg_op = 'UPDATE' and (old.status = 'published' or old.status = 'closed') then return null; end if;

  select name into co from public.companies where id = new.company_id;
  body := concat_ws(' · ',
                    case when new.company_id = '14bd5c26-ac43-4008-9211-ebe575132ace' then null else co end,
                    nullif(new.location, ''),
                    'apply by ' || to_char(new.deadline, 'FMDD Mon'));

  insert into public.notifications (user_id, type, title, body, job_id)
  select p.id, 'savedSearch', left('New job: ' || new.title, 120), body, new.id
  from public.profiles p
  where p.role = 'seeker' and p.every_job_alerts and not coalesce(p.suspended, false)
    and not exists (select 1 from public.company_members m where m.user_id = p.id)
    and not exists (select 1 from public.notifications n where n.user_id = p.id and n.job_id = new.id);
  return null;
exception when others then
  return null;  -- never block posting a job
end $$;

-- Runs after job_alerts_on_publish (saved-search alerts), so nobody gets two.
drop trigger if exists jobs_every_job_alert on public.jobs;
create trigger jobs_every_job_alert after insert or update of status on public.jobs
  for each row execute function public.jobs_every_job_alert();

notify pgrst, 'reload schema';
