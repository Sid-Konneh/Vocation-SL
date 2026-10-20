-- Vocation SL 1.1 — launch offer, prices, featured listings, website taps,
-- screening questions, team access and career tips. Run once, before the
-- 1.1 release goes live. Safe to re-run.

-- ---------------------------------------------------------------------------
-- 1. Prices and launch offer (editable in Admin → Platform settings)
-- ---------------------------------------------------------------------------
insert into public.platform_settings (key, value) values
  ('posting_price', '5000'),
  ('featured_price', '1500'),
  ('launch_offer', '{"free_posts": 5, "until": "2026-12-31"}')
on conflict (key) do nothing;

alter table public.invoices add column if not exists launch_free boolean not null default false;

-- A job going live creates its invoice. During the launch offer an employer's
-- first free postings get a zero invoice marked paid; after that the invoice
-- is a draft at the standard posting price for an admin to issue.
create or replace function public.invoice_for_job(j public.jobs) returns void
language plpgsql security definer set search_path = public as $$
declare
  c record;
  lo jsonb;
  free_n int;
  until_d date;
  used int;
  price numeric;
begin
  select * into c from public.companies where id = j.company_id;
  if c.id is null then return; end if;
  select value into lo from public.platform_settings where key = 'launch_offer';
  free_n := coalesce((lo->>'free_posts')::int, 0);
  until_d := coalesce((lo->>'until')::date, date '2000-01-01');
  select coalesce((value#>>'{}')::numeric, 0) into price from public.platform_settings where key = 'posting_price';
  select count(*) into used from public.invoices where company_id = c.id and launch_free and status <> 'void';

  if current_date <= until_d and used < free_n then
    insert into public.invoices (job_id, company_id, job_title, bill_to_name, bill_to_email, bill_to_address,
                                 unit_price, launch_free, status, payment_method, notes, created_by)
    values (j.id, c.id, j.title, c.name, coalesce(c.email, ''), concat_ws(', ', nullif(c.address, ''), nullif(c.location, '')),
            0, true, 'paid', 'Launch offer',
            format('Free posting %s of %s (launch offer until %s)', used + 1, free_n, to_char(until_d, 'DD Mon YYYY')), null)
    on conflict do nothing;
  else
    insert into public.invoices (job_id, company_id, job_title, bill_to_name, bill_to_email, bill_to_address, unit_price, created_by)
    values (j.id, c.id, j.title, c.name, coalesce(c.email, ''), concat_ws(', ', nullif(c.address, ''), nullif(c.location, '')),
            coalesce(price, 0), null)
    on conflict do nothing;
  end if;
end $$;

-- The signed-in employer's launch offer: how many free postings are left.
create or replace function public.launch_offer_status() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  cid text;
  lo jsonb;
  used int := 0;
begin
  select company_id into cid from public.company_members where user_id = auth.uid() limit 1;
  select value into lo from public.platform_settings where key = 'launch_offer';
  if cid is not null then
    select count(*) into used from public.invoices where company_id = cid and launch_free and status <> 'void';
  end if;
  return jsonb_build_object(
    'free_posts', coalesce((lo->>'free_posts')::int, 0),
    'until', lo->>'until',
    'used', used,
    'active', current_date <= coalesce((lo->>'until')::date, date '2000-01-01'));
end $$;

-- ---------------------------------------------------------------------------
-- 2. Jobs: website taps, featured requests, screening questions
-- ---------------------------------------------------------------------------
alter table public.jobs add column if not exists apply_clicks int not null default 0;
alter table public.jobs add column if not exists feature_requested_at timestamptz;
alter table public.jobs add column if not exists screening jsonb not null default '[]';

do $$ begin
  alter table public.jobs add constraint jobs_screening_max5 check (jsonb_typeof(screening) = 'array' and jsonb_array_length(screening) <= 5);
exception when duplicate_object then null; end $$;

-- Employers can't change the counters or the feature request themselves.
create or replace function public.jobs_protect_extras() returns trigger
language plpgsql as $$
begin
  if public.is_system_write() or public.admin_level() >= 2 then return new; end if;
  if tg_op = 'INSERT' then
    new.apply_clicks := 0;
    new.feature_requested_at := null;
  else
    new.apply_clicks := old.apply_clicks;
    new.feature_requested_at := old.feature_requested_at;
  end if;
  return new;
end $$;

drop trigger if exists jobs_protect_extras on public.jobs;
create trigger jobs_protect_extras before insert or update on public.jobs
  for each row execute function public.jobs_protect_extras();

-- Counts a tap on "Apply on website" (anyone may call it).
create or replace function public.record_apply_click(p_job text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform set_config('vsl.system', 'on', true);
  update public.jobs set apply_clicks = apply_clicks + 1 where id = p_job and apply_url <> '' and status = 'published';
  perform set_config('vsl.system', '', true);
end $$;
grant execute on function public.record_apply_click(text) to anon, authenticated;

-- An employer asks for a live job to be featured. An invoice is issued at the
-- featured price; an admin switches "Featured" on once it is paid.
create or replace function public.request_featured(p_job text) returns text
language plpgsql security definer set search_path = public as $$
declare
  j record;
  c record;
  price numeric;
  num text;
begin
  select * into j from public.jobs where id = p_job;
  if j.id is null or not public.is_company_member(j.company_id) then raise exception 'Job not found.'; end if;
  if j.status <> 'published' then raise exception 'Only live jobs can be featured.'; end if;
  if j.featured then raise exception 'This job is already featured.'; end if;
  if j.feature_requested_at is not null then raise exception 'You''ve already asked to feature this job. We''ll switch it on once the invoice is paid.'; end if;
  select * into c from public.companies where id = j.company_id;
  select coalesce((value#>>'{}')::numeric, 0) into price from public.platform_settings where key = 'featured_price';

  insert into public.invoices (company_id, job_title, bill_to_name, bill_to_email, bill_to_address, description, unit_price, status, created_by)
  values (c.id, j.title, c.name, coalesce(c.email, ''), concat_ws(', ', nullif(c.address, ''), nullif(c.location, '')),
          'Featured listing: ' || j.title, price, 'issued', null)
  returning number into num;

  perform set_config('vsl.system', 'on', true);
  update public.jobs set feature_requested_at = now() where id = j.id;
  perform set_config('vsl.system', '', true);
  return num;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Team access: a company owner adds colleagues by email
-- ---------------------------------------------------------------------------
create or replace function public.team_members() returns table (user_id uuid, role text, name text, email text, added_at timestamptz)
language sql stable security definer set search_path = public as $$
  select m.user_id, m.role, coalesce(p.full_name, ''), coalesce(u.email, ''), m.created_at
  from public.company_members m
  join auth.users u on u.id = m.user_id
  left join public.profiles p on p.id = m.user_id
  where m.company_id = (select company_id from public.company_members where user_id = auth.uid() limit 1)
  order by m.role = 'owner' desc, m.created_at;
$$;

create or replace function public.add_team_member(p_email text) returns void
language plpgsql security definer set search_path = public as $$
declare
  cid text;
  cname text;
  target uuid;
begin
  select m.company_id into cid from public.company_members m where m.user_id = auth.uid() and m.role = 'owner' limit 1;
  if cid is null then raise exception 'Only the company owner can add team members.'; end if;
  select id into target from auth.users where lower(email) = lower(trim(p_email)) limit 1;
  if target is null then raise exception 'No Vocation SL account uses that email. Ask your colleague to sign up first, then add them.'; end if;
  if target = auth.uid() then raise exception 'You''re already on the team.'; end if;
  if exists (select 1 from public.company_members where user_id = target) or exists (select 1 from public.companies where owner_id = target) then
    raise exception 'That account already belongs to a company.';
  end if;
  insert into public.company_members (company_id, user_id, role) values (cid, target, 'recruiter');
  select name into cname from public.companies where id = cid;
  insert into public.notifications (user_id, type, title, body)
  values (target, 'team', 'You were added to ' || cname,
          'You can now post jobs and review candidates for ' || cname || '. Open Vocation SL and choose Hire talent.');
end $$;

create or replace function public.remove_team_member(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare cid text;
begin
  select m.company_id into cid from public.company_members m where m.user_id = auth.uid() and m.role = 'owner' limit 1;
  if cid is null then raise exception 'Only the company owner can remove team members.'; end if;
  if p_user = auth.uid() then raise exception 'The owner can''t be removed.'; end if;
  delete from public.company_members where company_id = cid and user_id = p_user and role <> 'owner';
end $$;

-- ---------------------------------------------------------------------------
-- 4. Career tips page (editable in Admin → Content)
-- ---------------------------------------------------------------------------
insert into public.site_pages (slug, title, body) values ('career-tips', 'Career tips', '')
on conflict (slug) do nothing;

notify pgrst, 'reload schema';
