-- Vocation SL — Supabase schema
-- Run in the Supabase SQL editor (or `supabase db push`) before seed.sql.
-- Safe to re-run: objects are created only if missing.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Catalogue (public read)
-- ---------------------------------------------------------------------------

create table if not exists public.companies (
  id          text primary key,
  name        text not null,
  industry    text not null,
  location    text not null default '',
  about       text not null default '',
  size        text not null default '',
  founded     int,
  website     text not null default '',
  brand_color bigint not null default 4281302826,
  verified    boolean not null default false,
  created_at  timestamptz not null default now()
);

create table if not exists public.jobs (
  id                text primary key default gen_random_uuid()::text,
  company_id        text not null references public.companies(id) on delete cascade,
  title             text not null,
  location          text not null,
  employment_type   text not null,
  work_mode         text not null,
  industry          text not null,
  experience_level  text not null,
  salary_min        int,
  salary_max        int,
  currency          text not null default 'SLE',
  salary_period     text not null default 'month',
  posted_at         timestamptz not null default now(),
  deadline          timestamptz not null,
  about             text not null default '',
  description       text not null default '',
  responsibilities  jsonb not null default '[]',
  requirements      jsonb not null default '[]',
  preferred         jsonb not null default '[]',
  skills            jsonb not null default '[]',
  benefits          jsonb not null default '[]',
  applicants        int not null default 0,
  featured          boolean not null default false,
  -- Lower-cased text used by the app's keyword search.
  search_text       text generated always as (
    lower(title || ' ' || location || ' ' || industry || ' ' || skills::text)
  ) stored
);

create index if not exists jobs_posted_at_idx on public.jobs (posted_at desc);
create index if not exists jobs_company_idx on public.jobs (company_id);
create index if not exists jobs_location_idx on public.jobs (location);

-- ---------------------------------------------------------------------------
-- User data (owner-only)
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text,
  full_name   text not null default '',
  data        jsonb not null default '{}',   -- full AppUser JSON
  updated_at  timestamptz not null default now()
);

create table if not exists public.applications (
  id            text primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  job_id        text not null references public.jobs(id) on delete cascade,
  status        text not null default 'applied',
  submitted_at  timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  data          jsonb not null default '{}'  -- full JobApplication JSON
);

create unique index if not exists applications_one_live_per_job
  on public.applications (user_id, job_id) where status <> 'withdrawn';

create table if not exists public.notifications (
  id              text primary key default gen_random_uuid()::text,
  user_id         uuid not null references auth.users(id) on delete cascade,
  type            text not null,
  title           text not null,
  body            text not null default '',
  created_at      timestamptz not null default now(),
  read            boolean not null default false,
  job_id          text references public.jobs(id) on delete set null,
  application_id  text references public.applications(id) on delete cascade
);

create index if not exists notifications_user_idx on public.notifications (user_id, created_at desc);

create table if not exists public.saved_jobs (
  user_id   uuid not null references auth.users(id) on delete cascade,
  job_id    text not null references public.jobs(id) on delete cascade,
  saved_at  timestamptz not null default now(),
  primary key (user_id, job_id)
);

create table if not exists public.job_alerts (
  id          text primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  data        jsonb not null default '{}',   -- full JobAlert JSON
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.companies     enable row level security;
alter table public.jobs          enable row level security;
alter table public.profiles      enable row level security;
alter table public.applications  enable row level security;
alter table public.notifications enable row level security;
alter table public.saved_jobs    enable row level security;
alter table public.job_alerts    enable row level security;

drop policy if exists "companies are public" on public.companies;
create policy "companies are public" on public.companies for select using (true);

drop policy if exists "jobs are public" on public.jobs;
create policy "jobs are public" on public.jobs for select using (true);

drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles for all
  using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "read own applications" on public.applications;
create policy "read own applications" on public.applications for select using (auth.uid() = user_id);

drop policy if exists "create own applications" on public.applications;
create policy "create own applications" on public.applications for insert
  with check (auth.uid() = user_id and status = 'applied');

-- Applicants may only withdraw; other status changes come from employers
-- (service role or an employer dashboard with its own policies).
drop policy if exists "withdraw own applications" on public.applications;
create policy "withdraw own applications" on public.applications for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id and status = 'withdrawn');

drop policy if exists "own notifications" on public.notifications;
create policy "own notifications" on public.notifications for select using (auth.uid() = user_id);
drop policy if exists "update own notifications" on public.notifications;
create policy "update own notifications" on public.notifications for update
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "delete own notifications" on public.notifications;
create policy "delete own notifications" on public.notifications for delete using (auth.uid() = user_id);

drop policy if exists "own saved jobs" on public.saved_jobs;
create policy "own saved jobs" on public.saved_jobs for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own job alerts" on public.job_alerts;
create policy "own job alerts" on public.job_alerts for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

-- Create a profile row when someone signs up.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  -- Email sign-up sends full_name; Google sends full_name or name.
  display_name text := coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(new.email, '@', 1));
begin
  insert into public.profiles (id, email, full_name, data)
  values (
    new.id,
    new.email,
    display_name,
    jsonb_build_object('id', new.id, 'email', new.email, 'full_name', display_name)
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Notify the applicant on submission and on every status change, and keep
-- updated_at, applicant counts and the JSON copy of the status in sync.
create or replace function public.application_events() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  job_title text;
  company   text;
  ntype     text;
  ntitle    text;
  nbody     text;
begin
  select j.title, c.name into job_title, company
  from public.jobs j join public.companies c on c.id = j.company_id where j.id = new.job_id;

  if tg_op = 'INSERT' then
    update public.jobs set applicants = applicants + 1 where id = new.job_id;
    insert into public.notifications (user_id, type, title, body, job_id, application_id)
    values (new.user_id, 'submitted', 'Application submitted',
            format('Your application for %s was sent to %s.', job_title, company), new.job_id, new.id);
    return new;
  end if;

  if new.status is distinct from old.status then
    new.updated_at := now();
    if new.status <> 'withdrawn' then
      -- Keep the JSON history in step with status changes made by employers.
      new.data := jsonb_set(
        jsonb_set(new.data, '{status}', to_jsonb(new.status)),
        '{history}',
        coalesce(new.data->'history', '[]'::jsonb) || jsonb_build_array(jsonb_build_object('status', new.status, 'at', now(), 'note', null))
      );
      ntype := case new.status
        when 'viewed' then 'viewed'
        when 'shortlisted' then 'shortlisted'
        when 'interview' then 'interview'
        else 'statusChange' end;
      ntitle := case new.status
        when 'viewed' then 'Application viewed'
        when 'shortlisted' then 'You were shortlisted'
        when 'assessment' then 'Assessment requested'
        when 'interview' then 'Interview invitation'
        when 'offer' then 'You received an offer'
        when 'hired' then 'You got the job'
        when 'rejected' then 'Application update'
        else 'Application update' end;
      nbody := format('%s · %s', job_title, company);
      insert into public.notifications (user_id, type, title, body, job_id, application_id)
      values (new.user_id, ntype, ntitle, nbody, new.job_id, new.id);
    end if;
  end if;
  return new;
end $$;

drop trigger if exists applications_after_insert on public.applications;
create trigger applications_after_insert after insert on public.applications
  for each row execute function public.application_events();

drop trigger if exists applications_before_update on public.applications;
create trigger applications_before_update before update on public.applications
  for each row execute function public.application_events();

-- ---------------------------------------------------------------------------
-- Storage: private bucket for CVs and cover letters, one folder per user.
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('documents', 'documents', false)
on conflict (id) do nothing;

drop policy if exists "users manage own documents" on storage.objects;
create policy "users manage own documents" on storage.objects for all
  using (bucket_id = 'documents' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'documents' and (storage.foldername(name))[1] = auth.uid()::text);
