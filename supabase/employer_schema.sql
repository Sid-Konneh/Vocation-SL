-- Vocation SL — employer features (run AFTER schema.sql and seed.sql).
-- Adds company accounts, job management and applicant tracking access.
-- Posting jobs is free. Safe to re-run.
--
-- Trust model:
--   * Any signed-in user can register a company; it starts as 'pending'.
--   * Jobs from a pending company are saved as 'pending' and go live only
--     after an admin sets companies.status = 'approved' (Table Editor or SQL).
--   * Employers see applications, applicant profiles and CVs ONLY for jobs
--     belonging to their own company.

-- ---------------------------------------------------------------------------
-- Companies: ownership, approval status, contact details
-- ---------------------------------------------------------------------------

alter table public.companies alter column id set default gen_random_uuid()::text;
alter table public.companies add column if not exists owner_id uuid references auth.users(id) on delete set null;
-- Existing (seeded) companies become 'approved'; new ones default to 'pending'.
alter table public.companies add column if not exists status text not null default 'approved';
alter table public.companies alter column status set default 'pending';
alter table public.companies add column if not exists email   text not null default '';
alter table public.companies add column if not exists phone   text not null default '';
alter table public.companies add column if not exists address text not null default '';

do $$ begin
  alter table public.companies add constraint companies_status_check
    check (status in ('pending', 'approved', 'rejected', 'suspended'));
exception when duplicate_object then null; end $$;

create table if not exists public.company_members (
  company_id  text not null references public.companies(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  role        text not null default 'owner' check (role in ('owner', 'recruiter')),
  created_at  timestamptz not null default now(),
  primary key (company_id, user_id)
);
create index if not exists company_members_user_idx on public.company_members (user_id);

-- Security-definer helper so policies can check membership without recursion.
create or replace function public.is_company_member(cid text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.company_members where company_id = cid and user_id = auth.uid());
$$;

-- System writes (counters, approvals) set this flag so triggers allow them.
create or replace function public.is_system_write() returns boolean
language sql stable as $$ select coalesce(current_setting('vsl.system', true), '') = 'on' or auth.uid() is null; $$;

-- ---------------------------------------------------------------------------
-- Jobs: lifecycle status, views
-- ---------------------------------------------------------------------------

alter table public.jobs add column if not exists status text not null default 'published';
alter table public.jobs alter column status set default 'draft';
alter table public.jobs add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table public.jobs add column if not exists views      int  not null default 0;
alter table public.jobs add column if not exists updated_at timestamptz not null default now();

do $$ begin
  alter table public.jobs add constraint jobs_status_check
    check (status in ('draft', 'pending', 'published', 'closed'));
exception when duplicate_object then null; end $$;

create index if not exists jobs_status_idx on public.jobs (status);

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

-- New company: always pending, owned by its creator, creator becomes owner member.
create or replace function public.companies_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if not public.is_system_write() then
      new.status := 'pending';
      new.verified := false;
      new.owner_id := auth.uid();
    end if;
    return new;
  end if;
  -- UPDATE: employers cannot change approval, verification or ownership.
  if not public.is_system_write() then
    new.status := old.status;
    new.verified := old.verified;
    new.owner_id := old.owner_id;
  end if;
  return new;
end $$;

create or replace function public.companies_after() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.owner_id is not null then
    insert into public.company_members (company_id, user_id, role) values (new.id, new.owner_id, 'owner')
    on conflict do nothing;
  end if;
  -- Approval publishes the jobs that were waiting.
  if tg_op = 'UPDATE' and new.status = 'approved' and old.status is distinct from 'approved' then
    perform set_config('vsl.system', 'on', true);
    update public.jobs set status = 'published', posted_at = now() where company_id = new.id and status = 'pending';
    perform set_config('vsl.system', '', true);
  end if;
  return null;
end $$;

drop trigger if exists companies_guard on public.companies;
create trigger companies_guard before insert or update on public.companies
  for each row execute function public.companies_guard();
drop trigger if exists companies_after on public.companies;
create trigger companies_after after insert or update on public.companies
  for each row execute function public.companies_after();

-- Jobs: hold back unapproved companies and protect counters/featured flag.
create or replace function public.jobs_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare approved boolean;
begin
  if public.is_system_write() then
    new.updated_at := now();
    return new;
  end if;
  select status = 'approved' into approved from public.companies where id = new.company_id;
  if new.status = 'published' and not coalesce(approved, false) then
    new.status := 'pending';
  end if;
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    new.applicants := 0;
    new.views := 0;
    new.posted_at := now();
    new.featured := false;  -- featuring is decided by the Vocation SL team
  else
    new.applicants := old.applicants;
    new.views := old.views;
    new.created_by := old.created_by;
    new.featured := old.featured;
    if old.status = 'draft' and new.status in ('pending', 'published') then new.posted_at := now(); end if;
  end if;
  return new;
end $$;

drop trigger if exists jobs_guard on public.jobs;
create trigger jobs_guard before insert or update on public.jobs
  for each row execute function public.jobs_guard();

-- Applications: notifications both ways, history, and limits on what an
-- employer may change (status and employer-facing fields only).
create or replace function public.application_events() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  job_title text;
  company   text;
  cid       text;
  ntype     text;
  ntitle    text;
  is_employer boolean;
begin
  select j.title, c.name, c.id into job_title, company, cid
  from public.jobs j join public.companies c on c.id = j.company_id where j.id = new.job_id;

  if tg_op = 'INSERT' then
    perform set_config('vsl.system', 'on', true);
    update public.jobs set applicants = applicants + 1 where id = new.job_id;
    perform set_config('vsl.system', '', true);
    insert into public.notifications (user_id, type, title, body, job_id, application_id)
    values (new.user_id, 'submitted', 'Application submitted',
            format('Your application for %s was sent to %s.', job_title, company), new.job_id, new.id);
    -- Tell everyone on the hiring team.
    insert into public.notifications (user_id, type, title, body, job_id, application_id)
    select m.user_id, 'newApplicant', 'New applicant',
           format('%s applied for %s.', coalesce(new.data->'applicant'->>'full_name', 'A candidate'), job_title),
           new.job_id, new.id
    from public.company_members m where m.company_id = cid;
    return new;
  end if;

  is_employer := auth.uid() is not null and auth.uid() <> new.user_id;

  if is_employer then
    -- Keep the applicant's submission intact; accept only employer fields.
    new.data := old.data
      || jsonb_build_object(
           'employer_message',   new.data->'employer_message',
           'interview_at',       new.data->'interview_at',
           'next_step_deadline', new.data->'next_step_deadline');
    new.user_id := old.user_id;
    new.job_id := old.job_id;
    new.submitted_at := old.submitted_at;
    if new.status = 'withdrawn' then new.status := old.status; end if;

    if (new.data->>'employer_message') is distinct from (old.data->>'employer_message')
       and coalesce(new.data->>'employer_message', '') <> '' then
      insert into public.notifications (user_id, type, title, body, job_id, application_id)
      values (new.user_id, 'message', format('New message from %s', company), left(new.data->>'employer_message', 200), new.job_id, new.id);
    end if;
  end if;

  if new.status is distinct from old.status then
    new.updated_at := now();
    new.data := jsonb_set(
      jsonb_set(new.data, '{status}', to_jsonb(new.status)),
      '{history}',
      coalesce(new.data->'history', '[]'::jsonb)
        || case when new.status = 'withdrawn' and (new.data->'history') @> jsonb_build_array(jsonb_build_object('status', 'withdrawn'))
                then '[]'::jsonb
                else jsonb_build_array(jsonb_build_object('status', new.status, 'at', now(), 'note', null)) end
    );
    if new.status = 'withdrawn' then
      insert into public.notifications (user_id, type, title, body, job_id, application_id)
      select m.user_id, 'statusChange', 'Application withdrawn',
             format('%s withdrew from %s.', coalesce(new.data->'applicant'->>'full_name', 'A candidate'), job_title),
             new.job_id, new.id
      from public.company_members m where m.company_id = cid;
    else
      ntype := case new.status when 'viewed' then 'viewed' when 'shortlisted' then 'shortlisted'
                               when 'interview' then 'interview' else 'statusChange' end;
      ntitle := case new.status
        when 'viewed' then 'Application viewed'
        when 'shortlisted' then 'You were shortlisted'
        when 'assessment' then 'Assessment requested'
        when 'interview' then 'Interview invitation'
        when 'offer' then 'You received an offer'
        when 'hired' then 'You got the job'
        else 'Application update' end;
      insert into public.notifications (user_id, type, title, body, job_id, application_id)
      values (new.user_id, ntype, ntitle, format('%s · %s', job_title, company), new.job_id, new.id);
    end if;
  elsif new.data is distinct from old.data then
    new.updated_at := now();
  end if;
  return new;
end $$;

-- Counts a job view (called by the job-seeker app).
create or replace function public.record_job_view(p_job text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('vsl.system', 'on', true);
  update public.jobs set views = views + 1 where id = p_job and status = 'published';
  perform set_config('vsl.system', '', true);
end $$;
grant execute on function public.record_job_view(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.company_members  enable row level security;

-- Companies: public sees approved; members see their own (any status).
drop policy if exists "companies are public" on public.companies;
drop policy if exists "companies readable" on public.companies;
-- owner_id check lets the creator read the row back in the same INSERT
-- (the membership row is added by an AFTER trigger).
create policy "companies readable" on public.companies for select
  using (status = 'approved' or owner_id = auth.uid() or public.is_company_member(id));
drop policy if exists "register company" on public.companies;
create policy "register company" on public.companies for insert to authenticated with check (true);
drop policy if exists "members edit company" on public.companies;
create policy "members edit company" on public.companies for update
  using (public.is_company_member(id)) with check (public.is_company_member(id));

drop policy if exists "see own memberships" on public.company_members;
create policy "see own memberships" on public.company_members for select
  using (user_id = auth.uid() or public.is_company_member(company_id));

-- Jobs: public sees published; members manage their company's jobs.
drop policy if exists "jobs are public" on public.jobs;
drop policy if exists "jobs readable" on public.jobs;
create policy "jobs readable" on public.jobs for select
  using (status = 'published' or public.is_company_member(company_id));
drop policy if exists "members create jobs" on public.jobs;
create policy "members create jobs" on public.jobs for insert to authenticated
  with check (public.is_company_member(company_id));
drop policy if exists "members edit jobs" on public.jobs;
create policy "members edit jobs" on public.jobs for update
  using (public.is_company_member(company_id)) with check (public.is_company_member(company_id));
drop policy if exists "members delete draft jobs" on public.jobs;
create policy "members delete draft jobs" on public.jobs for delete
  using (public.is_company_member(company_id) and status = 'draft');

-- Applications: employers read and progress applications to their jobs.
drop policy if exists "employers read applications" on public.applications;
create policy "employers read applications" on public.applications for select
  using (exists (select 1 from public.jobs j where j.id = job_id and public.is_company_member(j.company_id)));
drop policy if exists "employers update applications" on public.applications;
-- WITH CHECK repeats the membership test: permissive policies are OR'd, so
-- without it an applicant could pass this check and set their own status.
create policy "employers update applications" on public.applications for update
  using (exists (select 1 from public.jobs j where j.id = job_id and public.is_company_member(j.company_id)))
  with check (
    exists (select 1 from public.jobs j where j.id = job_id and public.is_company_member(j.company_id))
    and status in ('applied', 'viewed', 'shortlisted', 'assessment', 'interview', 'offer', 'hired', 'rejected'));

-- Applicant profiles: visible to employers the person has applied to.
drop policy if exists "employers read applicant profiles" on public.profiles;
create policy "employers read applicant profiles" on public.profiles for select
  using (exists (
    select 1 from public.applications a join public.jobs j on j.id = a.job_id
    where a.user_id = profiles.id and public.is_company_member(j.company_id)));

-- Storage: employers may read CVs/cover letters of people who applied to them.
do $$
begin
  drop policy if exists "employers read applicant documents" on storage.objects;
  create policy "employers read applicant documents" on storage.objects for select to authenticated
    using (bucket_id = 'documents' and exists (
      select 1 from public.applications a join public.jobs j on j.id = a.job_id
      where a.user_id::text = (storage.foldername(name))[1] and public.is_company_member(j.company_id)));
exception when others then
  raise notice 'Storage policy skipped (%). Add it in Storage → Policies.', sqlerrm;
end $$;

notify pgrst, 'reload schema';
