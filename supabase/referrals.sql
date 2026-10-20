-- Vocation SL — employer referrals + logo upload fix (run after admin_more_schema.sql).
-- Safe to re-run. Run the whole file in Supabase → SQL Editor.
--
-- Referrals: every user gets a code (VSL + 5 characters). A new company can
-- enter a code when it signs up (or open employers.vocationsl.com/r/CODE).
-- The referral then follows the company: approved → each job it posts that
-- goes live is recorded on the referral. Admins mark referrals rewarded.

-- ---------------------------------------------------------------------------
-- 1. Logo uploads
-- ---------------------------------------------------------------------------
-- Logos are stored as logos/<user id>/<company id>-logo-<time>.<ext>, so any
-- signed-in user can upload into their own folder (no company membership
-- lookup needed at sign-up). No exception handler here: if this fails you
-- will see the error instead of a silently missing policy.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('logos', 'logos', true, 2097152, array['image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update
  set public = true, file_size_limit = 2097152, allowed_mime_types = array['image/png', 'image/jpeg', 'image/webp'];

drop policy if exists "company logos are public" on storage.objects;
create policy "company logos are public" on storage.objects for select
  using (bucket_id = 'logos');

drop policy if exists "users upload own logos" on storage.objects;
create policy "users upload own logos" on storage.objects for insert to authenticated
  with check (bucket_id = 'logos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "users replace own logos" on storage.objects;
create policy "users replace own logos" on storage.objects for update to authenticated
  using (bucket_id = 'logos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'logos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "users delete own logos" on storage.objects;
create policy "users delete own logos" on storage.objects for delete to authenticated
  using (bucket_id = 'logos' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------------
-- 2. Referral tables
-- ---------------------------------------------------------------------------

create table if not exists public.referral_codes (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  code       text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.referrals (
  id             text primary key default gen_random_uuid()::text,
  referrer_id    uuid not null references auth.users(id) on delete cascade,
  referrer_name  text not null default '',
  referrer_email text not null default '',
  company_id     text not null unique references public.companies(id) on delete cascade,
  company_name   text not null default '',
  code           text not null,
  status         text not null default 'signedUp'
                 check (status in ('signedUp', 'approved', 'qualified', 'rewarded', 'rejected')),
  jobs           jsonb not null default '[]',   -- [{id, title, published_at}] jobs that went live
  note           text not null default '',
  created_at     timestamptz not null default now(),
  qualified_at   timestamptz,
  rewarded_at    timestamptz
);
create index if not exists referrals_referrer_idx on public.referrals (referrer_id, created_at desc);

alter table public.referral_codes enable row level security;
alter table public.referrals enable row level security;

drop policy if exists "read own referral code" on public.referral_codes;
create policy "read own referral code" on public.referral_codes for select
  using (user_id = auth.uid() or public.admin_level() >= 1);

-- Referrers see their own referrals; admins see all. All writes go through
-- the functions below.
drop policy if exists "read referrals" on public.referrals;
create policy "read referrals" on public.referrals for select
  using (referrer_id = auth.uid() or public.admin_level() >= 1);

-- What referrers receive (text set by admins on the Referrals page).
insert into public.platform_settings (key, value) values ('referral_reward', '""')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 3. Functions
-- ---------------------------------------------------------------------------

-- The caller's code, created on first use. Avoids look-alike characters.
create or replace function public.my_referral_code() returns text
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  c text;
  alphabet text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
begin
  if uid is null then raise exception 'Please sign in again.'; end if;
  select code into c from public.referral_codes where user_id = uid;
  if c is not null then return c; end if;
  loop
    c := 'VSL';
    for i in 1..5 loop
      c := c || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    begin
      insert into public.referral_codes (user_id, code) values (uid, c);
      return c;
    exception when unique_violation then
      -- Either the code was taken (try another) or this user got one meanwhile.
      select code into c from public.referral_codes where user_id = uid;
      if c is not null then return c; end if;
    end;
  end loop;
end $$;

create or replace function private_notify_referrer(p_user uuid, p_title text, p_body text) returns void
language sql security definer set search_path = public as $$
  insert into public.notifications (user_id, type, title, body) values (p_user, 'referral', p_title, p_body);
$$;
revoke all on function private_notify_referrer(uuid, text, text) from public, anon, authenticated;

-- Links a company the caller belongs to with the owner of a code.
create or replace function public.claim_referral(p_code text, p_company text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  clean text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  ref_user uuid;
  co record;
  p record;
begin
  if uid is null then raise exception 'Please sign in again.'; end if;
  if not public.is_company_member(p_company) then raise exception 'Only the company''s own team can add a referral code.'; end if;
  select user_id into ref_user from public.referral_codes where code = clean;
  if ref_user is null then raise exception 'That referral code wasn''t found. Check it and try again.'; end if;
  if ref_user = uid then raise exception 'You can''t use your own referral code.'; end if;
  if exists (select 1 from public.referrals where company_id = p_company) then return; end if;

  select name, status into co from public.companies where id = p_company;
  select full_name, email into p from public.profiles where id = ref_user;
  insert into public.referrals (referrer_id, referrer_name, referrer_email, company_id, company_name, code, status)
  values (ref_user, coalesce(p.full_name, ''), coalesce(p.email, ''), p_company, coalesce(co.name, ''), clean,
          case when co.status = 'approved' then 'approved' else 'signedUp' end);

  perform private_notify_referrer(ref_user, 'Your referral signed up',
    format('%s joined Vocation SL with your referral code. We''ll let you know when their jobs go live.', coalesce(co.name, 'A company')));
end $$;

-- Admins: mark a referral rewarded or not eligible (or move it back).
create or replace function public.admin_set_referral(p_id text, p_status text, p_note text default '') returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if public.admin_level() < 2 then raise exception 'Only moderators and admins can update referrals.'; end if;
  if p_status not in ('signedUp', 'approved', 'qualified', 'rewarded', 'rejected') then raise exception 'Unknown status %', p_status; end if;
  update public.referrals
     set status = p_status,
         note = coalesce(p_note, ''),
         rewarded_at = case when p_status = 'rewarded' then now() else null end
   where id = p_id
  returning * into r;
  if r.id is null then raise exception 'Referral not found.'; end if;
  if p_status = 'rewarded' then
    perform private_notify_referrer(r.referrer_id, 'Referral reward',
      format('Thank you for referring %s.%s', r.company_name, case when coalesce(p_note, '') = '' then '' else ' ' || p_note end));
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Triggers: follow the referred company
-- ---------------------------------------------------------------------------

create or replace function public.referrals_on_company() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.status = 'approved' and old.status is distinct from 'approved' then
    update public.referrals set status = 'approved', company_name = new.name
     where company_id = new.id and status = 'signedUp'
    returning * into r;
    if r.id is not null then
      perform private_notify_referrer(r.referrer_id, 'Your referral was approved',
        format('%s is now approved on Vocation SL. Their jobs will count for your referral when they go live.', new.name));
    end if;
  end if;
  return null;
end $$;

drop trigger if exists referrals_on_company on public.companies;
create trigger referrals_on_company after update on public.companies
  for each row execute function public.referrals_on_company();

-- Every job the referred company posts that goes live is added once.
create or replace function public.referrals_on_job() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if new.status <> 'published' or (tg_op = 'UPDATE' and old.status = 'published') then return null; end if;
  select * into r from public.referrals where company_id = new.company_id and status <> 'rejected';
  if r.id is null or r.jobs @> jsonb_build_array(jsonb_build_object('id', new.id)) then return null; end if;

  update public.referrals
     set jobs = jobs || jsonb_build_array(jsonb_build_object('id', new.id, 'title', new.title, 'published_at', now())),
         status = case when status in ('signedUp', 'approved') then 'qualified' else status end,
         qualified_at = coalesce(qualified_at, now())
   where id = r.id;

  perform private_notify_referrer(r.referrer_id, 'A referred company posted a job',
    format('%s posted "%s" on Vocation SL. That''s %s job%s from your referral.', r.company_name, new.title,
           jsonb_array_length(r.jobs) + 1, case when jsonb_array_length(r.jobs) = 0 then '' else 's' end));
  return null;
end $$;

drop trigger if exists referrals_on_job on public.jobs;
create trigger referrals_on_job after insert or update of status on public.jobs
  for each row execute function public.referrals_on_job();

notify pgrst, 'reload schema';
