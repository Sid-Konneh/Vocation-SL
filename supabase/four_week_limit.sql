-- Vocation SL — jobs stay open for at most 4 weeks unless extended
-- (user's decision, 25 Nov 2026: SLE 4,000 per job covers 4 weeks).
-- Safe to re-run.
--
-- jobs.max_deadline = the latest closing date the job has paid for:
--   * new job: the end of the day 4 weeks (28 days) after it is posted,
--     reset to 4 weeks from the day it goes live if it waited for review;
--   * extend_job() moves it to the new deadline (1–4 extra weeks, invoiced).
-- An employer's closing date later than max_deadline is cut back to it, so
-- older app versions keep working. Admins and system writes (e.g. the team's
-- careers.sl listings) can set any date.

alter table public.jobs add column if not exists max_deadline timestamptz;

-- Existing jobs keep the dates they already have.
update public.jobs
set max_deadline = greatest(deadline, date_trunc('day', coalesce(posted_at, now())) + interval '28 days 23 hours 59 minutes')
where max_deadline is null;

create or replace function public.jobs_four_weeks() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  four_weeks timestamptz := date_trunc('day', now()) + interval '28 days 23 hours 59 minutes';
begin
  if public.is_system_write() or public.admin_level() >= 2 then
    if new.max_deadline is null or new.deadline > new.max_deadline then
      new.max_deadline := greatest(coalesce(new.max_deadline, four_weeks), coalesce(new.deadline, four_weeks));
    end if;
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.max_deadline := four_weeks;
  elsif coalesce(current_setting('vsl.extending', true), '') = '1' then
    null;  -- extend_job() sets the new paid-for date
  else
    new.max_deadline := old.max_deadline;
    -- A job that waited for review gets its 4 weeks from the day it goes live.
    if new.status = 'published' and old.status is distinct from 'published' and old.status <> 'closed' then
      new.max_deadline := greatest(coalesce(old.max_deadline, four_weeks), four_weeks);
    end if;
    new.max_deadline := coalesce(new.max_deadline, four_weeks);
  end if;

  if new.deadline is null or new.deadline > new.max_deadline then
    new.deadline := new.max_deadline;
  end if;
  return new;
end $$;

drop trigger if exists jobs_four_weeks on public.jobs;
create trigger jobs_four_weeks before insert or update on public.jobs
  for each row execute function public.jobs_four_weeks();

-- extend_job(): also moves the paid-for date.
do $$
declare d text; n text;
begin
  select pg_get_functiondef('public.extend_job(text, integer)'::regprocedure) into d;
  if d like '%vsl.extending%' then return; end if;
  n := replace(d,
    'update public.jobs set deadline = new_deadline,',
    'perform set_config(''vsl.extending'', ''1'', true);
  update public.jobs set deadline = new_deadline, max_deadline = new_deadline,');
  if n = d then raise exception 'extend_job: pattern not found'; end if;
  execute n;
end $$;

notify pgrst, 'reload schema';
