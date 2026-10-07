-- Vocation SL — admin dashboard (run after employer_schema.sql, logo_schema.sql
-- and account_schema.sql). Safe to re-run.
--
-- Admin access comes ONLY from the admins table, which only an owner can
-- change. Every admin write is checked here by row-level security and
-- recorded in audit_log by triggers. Make the first owner with:
--   insert into public.admins (user_id, role)
--   select id, 'owner' from auth.users where email = 'you@example.com';

-- ---------------------------------------------------------------------------
-- Admin team and permission levels
-- ---------------------------------------------------------------------------

create table if not exists public.admins (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  role        text not null check (role in ('owner', 'admin', 'moderator', 'viewer')),
  added_by    uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

-- 4 owner, 3 admin, 2 moderator, 1 viewer, 0 not an admin.
create or replace function public.admin_level() returns int
language sql stable security definer set search_path = public as $$
  select coalesce((select case role when 'owner' then 4 when 'admin' then 3 when 'moderator' then 2 when 'viewer' then 1 end
                   from public.admins where user_id = auth.uid()), 0);
$$;

-- Never leave the platform without an owner.
create or replace function public.admins_keep_owner() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (tg_op = 'DELETE' and old.role = 'owner') or (tg_op = 'UPDATE' and old.role = 'owner' and new.role <> 'owner') then
    if (select count(*) from public.admins where role = 'owner' and user_id <> old.user_id) = 0 then
      raise exception 'There must always be at least one owner.';
    end if;
  end if;
  if tg_op = 'INSERT' then new.added_by := coalesce(new.added_by, auth.uid()); end if;
  return coalesce(new, old);
end $$;

drop trigger if exists admins_keep_owner on public.admins;
create trigger admins_keep_owner before insert or update or delete on public.admins
  for each row execute function public.admins_keep_owner();

-- ---------------------------------------------------------------------------
-- Profiles: join date, role, last sign-in, suspension
-- ---------------------------------------------------------------------------

alter table public.profiles add column if not exists created_at       timestamptz not null default now();
alter table public.profiles add column if not exists role             text;
alter table public.profiles add column if not exists last_seen_at     timestamptz;
alter table public.profiles add column if not exists suspended        boolean not null default false;
alter table public.profiles add column if not exists suspended_reason text;

-- Make sure every account has a profile row, and backfill the new columns.
insert into public.profiles (id, email, full_name, data, created_at)
select u.id, u.email,
       coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', split_part(u.email, '@', 1)),
       jsonb_build_object('id', u.id, 'email', u.email,
                          'full_name', coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', split_part(u.email, '@', 1))),
       u.created_at
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id);

update public.profiles p
set role = u.raw_user_meta_data->>'role', last_seen_at = u.last_sign_in_at, created_at = u.created_at
from auth.users u where u.id = p.id;

-- Keep role and last sign-in in step with the auth account.
create or replace function public.sync_profile_from_auth() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.profiles
  set role = new.raw_user_meta_data->>'role', last_seen_at = new.last_sign_in_at
  where id = new.id;
  return new;
end $$;

drop trigger if exists on_auth_user_updated on auth.users;
create trigger on_auth_user_updated after update on auth.users
  for each row execute function public.sync_profile_from_auth();

-- Users cannot change their own suspension, role or system dates.
create or replace function public.profiles_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.is_system_write() or public.admin_level() >= 3 then return new; end if;
  if tg_op = 'INSERT' then
    new.suspended := false;
    new.suspended_reason := null;
    return new;
  end if;
  new.suspended := old.suspended;
  new.suspended_reason := old.suspended_reason;
  new.role := old.role;
  new.created_at := old.created_at;
  new.last_seen_at := old.last_seen_at;
  return new;
end $$;

drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard before insert or update on public.profiles
  for each row execute function public.profiles_guard();

create or replace function public.is_suspended() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select suspended from public.profiles where id = auth.uid()), false);
$$;

-- ---------------------------------------------------------------------------
-- Reports, announcements, pages, settings, activity log
-- ---------------------------------------------------------------------------

create table if not exists public.reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid references auth.users(id) on delete set null,
  target_type  text not null check (target_type in ('job', 'company', 'user')),
  target_id    text not null,
  target_label text not null default '',
  reason       text not null,
  details      text not null default '',
  status       text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  admin_note   text not null default '',
  created_at   timestamptz not null default now(),
  resolved_at  timestamptz,
  resolved_by  uuid references auth.users(id) on delete set null
);
create index if not exists reports_status_idx on public.reports (status, created_at desc);

create table if not exists public.announcements (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  body        text not null default '',
  audience    text not null default 'all' check (audience in ('all', 'seeker', 'employer')),
  level       text not null default 'info' check (level in ('info', 'warning', 'success')),
  active      boolean not null default true,
  starts_at   timestamptz,
  ends_at     timestamptz,
  created_by  uuid references auth.users(id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.site_pages (
  slug        text primary key,
  title       text not null,
  body        text not null default '',
  updated_at  timestamptz not null default now(),
  updated_by  uuid references auth.users(id) on delete set null
);
insert into public.site_pages (slug, title) values
  ('terms', 'Terms of Use'), ('privacy', 'Privacy Policy'), ('help', 'Help & FAQs')
on conflict (slug) do nothing;

create table if not exists public.platform_settings (
  key         text primary key,
  value       jsonb not null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references auth.users(id) on delete set null
);
insert into public.platform_settings (key, value) values
  ('require_company_approval', 'true'),
  ('maintenance', '{"enabled": false, "message": ""}'),
  ('support_email', '"vocationxsl@gmail.com"')
on conflict (key) do nothing;

create or replace function public.setting_bool(k text, fallback boolean) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from public.platform_settings where key = k), fallback);
$$;

create table if not exists public.audit_log (
  id           bigint generated always as identity primary key,
  actor_id     uuid,
  actor_email  text,
  action       text not null,
  target_type  text not null,
  target_id    text,
  details      jsonb not null default '{}',
  created_at   timestamptz not null default now()
);
create index if not exists audit_log_created_idx on public.audit_log (created_at desc);

-- Records every change an admin makes to a watched table.
create or replace function public.audit_admin_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  rec_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  rec_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  tid text;
  det jsonb;
begin
  if public.admin_level() = 0 then return coalesce(new, old); end if;
  tid := coalesce(rec_new->>'id', rec_old->>'id', rec_new->>'user_id', rec_old->>'user_id',
                  rec_new->>'key', rec_old->>'key', rec_new->>'slug', rec_old->>'slug');
  det := case tg_op
    when 'INSERT' then rec_new
    when 'DELETE' then rec_old
    else (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(rec_new) e
          where rec_old->e.key is distinct from e.value and e.key <> 'updated_at')
  end;
  det := det - 'data' - 'description' - 'search_text' - 'responsibilities' - 'requirements' - 'preferred' - 'benefits';
  if tg_op = 'UPDATE' and det = '{}'::jsonb then return new; end if;
  insert into public.audit_log (actor_id, actor_email, action, target_type, target_id, details)
  values (auth.uid(), (select email from auth.users where id = auth.uid()), lower(tg_op), tg_table_name, tid,
          det || jsonb_build_object('label', coalesce(rec_new->>'name', rec_new->>'title', rec_new->>'full_name', rec_new->>'email',
                                                      rec_old->>'name', rec_old->>'title', rec_old->>'full_name', rec_old->>'email', '')));
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['companies', 'jobs', 'profiles', 'reports', 'announcements', 'site_pages', 'platform_settings', 'admins'] loop
    execute format('drop trigger if exists audit_admin_change on public.%I', t);
    execute format('create trigger audit_admin_change after insert or update or delete on public.%I for each row execute function public.audit_admin_change()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Moderation-aware guards (replace the employer versions)
-- ---------------------------------------------------------------------------

create or replace function public.companies_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.is_system_write() or public.admin_level() >= 2 then return new; end if;
  if tg_op = 'INSERT' then
    new.status := case when public.setting_bool('require_company_approval', true) then 'pending' else 'approved' end;
    new.verified := false;
    new.owner_id := auth.uid();
    return new;
  end if;
  new.status := old.status;
  new.verified := old.verified;
  new.owner_id := old.owner_id;
  return new;
end $$;

create or replace function public.jobs_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare approved boolean;
begin
  if public.is_system_write() or public.admin_level() >= 2 then
    new.updated_at := now();
    return new;
  end if;
  select status = 'approved' into approved from public.companies where id = new.company_id;
  if new.status = 'published' and not coalesce(approved, false) then new.status := 'pending'; end if;
  new.updated_at := now();
  if tg_op = 'INSERT' then
    new.created_by := auth.uid();
    new.applicants := 0;
    new.views := 0;
    new.posted_at := now();
    new.featured := false;
  else
    new.applicants := old.applicants;
    new.views := old.views;
    new.created_by := old.created_by;
    new.featured := old.featured;
    if old.status = 'draft' and new.status in ('pending', 'published') then new.posted_at := now(); end if;
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------------
-- Admin actions that need more than a table write
-- ---------------------------------------------------------------------------

-- Deletes a user account (and companies where they are the only member).
create or replace function public.admin_delete_user(target uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  my_level int := public.admin_level();
  their_level int := coalesce((select case role when 'owner' then 4 when 'admin' then 3 when 'moderator' then 2 when 'viewer' then 1 end
                               from public.admins where user_id = target), 0);
  victim text;
begin
  if my_level < 3 then raise exception 'Only admins can delete users.'; end if;
  if target = auth.uid() then raise exception 'Use Delete account to remove your own account.'; end if;
  if their_level >= my_level and my_level < 4 then raise exception 'You cannot delete an admin with the same or higher role.'; end if;
  select email into victim from auth.users where id = target;
  delete from public.companies c
  where exists (select 1 from public.company_members m where m.company_id = c.id and m.user_id = target)
    and not exists (select 1 from public.company_members m where m.company_id = c.id and m.user_id <> target);
  delete from auth.users where id = target;
  insert into public.audit_log (actor_id, actor_email, action, target_type, target_id, details)
  values (auth.uid(), (select email from auth.users where id = auth.uid()), 'delete', 'users', target::text,
          jsonb_build_object('label', coalesce(victim, '')));
end $$;
revoke all on function public.admin_delete_user(uuid) from public, anon;
grant execute on function public.admin_delete_user(uuid) to authenticated;

-- One call for the dashboard numbers and charts.
create or replace function public.admin_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
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
  ) into result;
  return result;
end $$;
revoke all on function public.admin_stats() from public, anon;
grant execute on function public.admin_stats() to authenticated;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------

alter table public.admins            enable row level security;
alter table public.reports           enable row level security;
alter table public.announcements     enable row level security;
alter table public.site_pages        enable row level security;
alter table public.platform_settings enable row level security;
alter table public.audit_log         enable row level security;

drop policy if exists "admins read team" on public.admins;
create policy "admins read team" on public.admins for select using (public.admin_level() >= 1 or user_id = auth.uid());
drop policy if exists "owners manage team" on public.admins;
create policy "owners manage team" on public.admins for all using (public.admin_level() = 4) with check (public.admin_level() = 4);

drop policy if exists "admins read profiles" on public.profiles;
create policy "admins read profiles" on public.profiles for select using (public.admin_level() >= 1);
drop policy if exists "admins update profiles" on public.profiles;
create policy "admins update profiles" on public.profiles for update using (public.admin_level() >= 3) with check (public.admin_level() >= 3);

drop policy if exists "admins read companies" on public.companies;
create policy "admins read companies" on public.companies for select using (public.admin_level() >= 1);
drop policy if exists "moderators update companies" on public.companies;
create policy "moderators update companies" on public.companies for update using (public.admin_level() >= 2) with check (public.admin_level() >= 2);
drop policy if exists "admins delete companies" on public.companies;
create policy "admins delete companies" on public.companies for delete using (public.admin_level() >= 3);

drop policy if exists "admins read members" on public.company_members;
create policy "admins read members" on public.company_members for select using (public.admin_level() >= 1);

drop policy if exists "admins read jobs" on public.jobs;
create policy "admins read jobs" on public.jobs for select using (public.admin_level() >= 1);
drop policy if exists "moderators update jobs" on public.jobs;
create policy "moderators update jobs" on public.jobs for update using (public.admin_level() >= 2) with check (public.admin_level() >= 2);
drop policy if exists "moderators delete jobs" on public.jobs;
create policy "moderators delete jobs" on public.jobs for delete using (public.admin_level() >= 2);

drop policy if exists "admins read applications" on public.applications;
create policy "admins read applications" on public.applications for select using (public.admin_level() >= 1);

-- Suspended accounts cannot apply, post jobs or register companies.
drop policy if exists "create own applications" on public.applications;
create policy "create own applications" on public.applications for insert
  with check (auth.uid() = user_id and status = 'applied' and not public.is_suspended());
drop policy if exists "members create jobs" on public.jobs;
create policy "members create jobs" on public.jobs for insert to authenticated
  with check (public.is_company_member(company_id) and not public.is_suspended());
drop policy if exists "members edit jobs" on public.jobs;
create policy "members edit jobs" on public.jobs for update
  using (public.is_company_member(company_id)) with check (public.is_company_member(company_id) and not public.is_suspended());
drop policy if exists "register company" on public.companies;
create policy "register company" on public.companies for insert to authenticated with check (not public.is_suspended());

drop policy if exists "report content" on public.reports;
create policy "report content" on public.reports for insert to authenticated with check (reporter_id = auth.uid() and status = 'open');
drop policy if exists "read reports" on public.reports;
create policy "read reports" on public.reports for select using (reporter_id = auth.uid() or public.admin_level() >= 1);
drop policy if exists "moderators handle reports" on public.reports;
create policy "moderators handle reports" on public.reports for update using (public.admin_level() >= 2) with check (public.admin_level() >= 2);

drop policy if exists "read announcements" on public.announcements;
create policy "read announcements" on public.announcements for select
  using (public.admin_level() >= 1 or (active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now())));
drop policy if exists "admins manage announcements" on public.announcements;
create policy "admins manage announcements" on public.announcements for all using (public.admin_level() >= 3) with check (public.admin_level() >= 3);

drop policy if exists "pages are public" on public.site_pages;
create policy "pages are public" on public.site_pages for select using (true);
drop policy if exists "admins edit pages" on public.site_pages;
create policy "admins edit pages" on public.site_pages for all using (public.admin_level() >= 3) with check (public.admin_level() >= 3);

drop policy if exists "settings are public" on public.platform_settings;
create policy "settings are public" on public.platform_settings for select using (true);
drop policy if exists "admins edit settings" on public.platform_settings;
create policy "admins edit settings" on public.platform_settings for all using (public.admin_level() >= 3) with check (public.admin_level() >= 3);

drop policy if exists "admins read activity" on public.audit_log;
create policy "admins read activity" on public.audit_log for select using (public.admin_level() >= 1);

do $$
begin
  drop policy if exists "admins read documents" on storage.objects;
  create policy "admins read documents" on storage.objects for select to authenticated
    using (bucket_id = 'documents' and public.admin_level() >= 2);
exception when others then
  raise notice 'Storage policy skipped (%).', sqlerrm;
end $$;

notify pgrst, 'reload schema';
