-- Vocation SL — admin dashboard additions (run after admin_schema.sql). Safe to re-run.
--   1. Job invoices
--   2. Full user details with sign-in information (admins only)
--   3. Every job is reviewed by an admin before it goes live
--   4. (Superseded by checkmark_fix.sql: the check mark is given separately)
--   5. Two-way messages between employers and candidates on an application
--   6. Help & FAQs, Terms of Use and Privacy Policy (only fills pages that are still empty)

-- ===========================================================================
-- 1. Invoices
-- ===========================================================================
--
-- A draft invoice is created automatically the first time a job goes live
-- (status → published). Admins then enter the cost, issue it and mark it paid.
-- Only admins (level 3+) can edit invoices; viewers and moderators can read
-- them. Employers cannot see invoices.

create sequence if not exists public.invoice_number_seq;

create table if not exists public.invoices (
  id                 uuid primary key default gen_random_uuid(),
  number             text not null unique
                     default 'VSL-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.invoice_number_seq')::text, 5, '0'),
  job_id             text references public.jobs(id) on delete set null,
  company_id         text references public.companies(id) on delete set null,
  job_title          text not null default '',
  bill_to_name       text not null default '',
  bill_to_email      text not null default '',
  bill_to_address    text not null default '',
  description        text not null default 'Job listing on Vocation SL',
  quantity           int not null default 1 check (quantity > 0),
  unit_price         numeric(14, 2) not null default 0 check (unit_price >= 0),
  discount           numeric(14, 2) not null default 0 check (discount >= 0),
  tax_rate           numeric(5, 2) not null default 15 check (tax_rate between 0 and 100),
  subtotal           numeric(14, 2) generated always as (quantity * unit_price) stored,
  tax_amount         numeric(14, 2) generated always as
                     (round(greatest(quantity * unit_price - discount, 0) * tax_rate / 100, 2)) stored,
  total              numeric(14, 2) generated always as
                     (greatest(quantity * unit_price - discount, 0) + round(greatest(quantity * unit_price - discount, 0) * tax_rate / 100, 2)) stored,
  currency           text not null default 'SLE',
  status             text not null default 'draft' check (status in ('draft', 'issued', 'paid', 'void')),
  issue_date         date,
  due_date           date,
  paid_at            timestamptz,
  payment_method     text not null default '',
  payment_reference  text not null default '',
  notes              text not null default '',
  created_by         uuid references auth.users(id) on delete set null default auth.uid(),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists invoices_status_idx on public.invoices (status, created_at desc);
create unique index if not exists invoices_one_per_job on public.invoices (job_id) where job_id is not null and status <> 'void';

-- Fill in the bill-to details from the company when a draft is created.
create or replace function public.invoice_for_job(j public.jobs) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.invoices (job_id, company_id, job_title, bill_to_name, bill_to_email, bill_to_address, created_by)
  select j.id, c.id, j.title, c.name, coalesce(c.email, ''),
         concat_ws(', ', nullif(c.address, ''), nullif(c.location, '')), null
  from public.companies c where c.id = j.company_id
  on conflict do nothing;
end $$;

create or replace function public.invoice_on_publish() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'published' and (tg_op = 'INSERT' or old.status is distinct from 'published') then
    perform public.invoice_for_job(new);
  end if;
  return new;
end $$;

drop trigger if exists invoice_on_publish on public.jobs;
create trigger invoice_on_publish after insert or update of status on public.jobs
  for each row execute function public.invoice_on_publish();

-- Backfill: live jobs from real employers (sample listings have no owner).
do $$
declare j public.jobs;
begin
  for j in select jb.* from public.jobs jb join public.companies c on c.id = jb.company_id
           where jb.status = 'published' and c.owner_id is not null loop
    perform public.invoice_for_job(j);
  end loop;
end $$;

-- Keep timestamps and status dates honest.
create or replace function public.invoices_touch() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  if new.status = 'issued' and new.issue_date is null then new.issue_date := current_date; end if;
  if new.status = 'issued' and new.due_date is null then new.due_date := new.issue_date + 14; end if;
  if new.status = 'paid' and new.paid_at is null then new.paid_at := now(); end if;
  if new.status <> 'paid' then new.paid_at := null; end if;
  return new;
end $$;

drop trigger if exists invoices_touch on public.invoices;
create trigger invoices_touch before insert or update on public.invoices
  for each row execute function public.invoices_touch();

-- Activity log: same as admin_schema.sql, plus invoice numbers as labels.
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
  det := det - 'data' - 'description' - 'search_text' - 'responsibilities' - 'requirements' - 'preferred' - 'benefits'
             - 'subtotal' - 'tax_amount' - 'notes' - 'bill_to_address';
  if tg_op = 'UPDATE' and det = '{}'::jsonb then return new; end if;
  insert into public.audit_log (actor_id, actor_email, action, target_type, target_id, details)
  values (auth.uid(), (select email from auth.users where id = auth.uid()), lower(tg_op), tg_table_name, tid,
          det || jsonb_build_object('label', coalesce(rec_new->>'number', rec_new->>'name', rec_new->>'title', rec_new->>'full_name', rec_new->>'email',
                                                      rec_old->>'number', rec_old->>'name', rec_old->>'title', rec_old->>'full_name', rec_old->>'email', '')));
  return coalesce(new, old);
end $$;

drop trigger if exists audit_admin_change on public.invoices;
create trigger audit_admin_change after insert or update or delete on public.invoices
  for each row execute function public.audit_admin_change();

-- Access
alter table public.invoices enable row level security;
revoke all on public.invoices from anon;

drop policy if exists "admins read invoices" on public.invoices;
create policy "admins read invoices" on public.invoices for select using (public.admin_level() >= 1);
drop policy if exists "admins manage invoices" on public.invoices;
create policy "admins manage invoices" on public.invoices for all
  using (public.admin_level() >= 3) with check (public.admin_level() >= 3);

grant usage on sequence public.invoice_number_seq to authenticated;

-- ===========================================================================
-- 2. User sign-in details
-- ===========================================================================
--
-- Sign-in information lives in the protected auth schema, so admins read it
-- through this function. Admin level 3+ only (owners and admins); every call
-- is written to the activity log. Passwords are stored only as one-way hashes
-- by Supabase and are never returned.

create or replace function public.admin_user_login(target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  u auth.users;
  result jsonb;
begin
  if public.admin_level() < 3 then
    raise exception 'Only admins can view sign-in details.' using errcode = '42501';
  end if;
  select * into u from auth.users where id = target;
  if not found then return null; end if;

  result := jsonb_build_object(
    'email', u.email,
    'phone', u.phone,
    'providers', coalesce(u.raw_app_meta_data->'providers', jsonb_build_array(u.raw_app_meta_data->>'provider')),
    'created_at', u.created_at,
    'last_sign_in_at', u.last_sign_in_at,
    'email_confirmed_at', u.email_confirmed_at,
    'banned_until', u.banned_until,
    'identities', coalesce((
      select jsonb_agg(jsonb_build_object(
               'provider', i.provider,
               'email', i.identity_data->>'email',
               'created_at', i.created_at,
               'last_sign_in_at', i.last_sign_in_at) order by i.created_at)
      from auth.identities i where i.user_id = target), '[]'),
    'sessions', coalesce((
      select jsonb_agg(x order by x->>'updated_at' desc nulls last)
      from (
        select jsonb_build_object(
                 'created_at', to_jsonb(s)->>'created_at',
                 'updated_at', coalesce(to_jsonb(s)->>'refreshed_at', to_jsonb(s)->>'updated_at'),
                 'user_agent', to_jsonb(s)->>'user_agent',
                 'ip', to_jsonb(s)->>'ip') as x
        from auth.sessions s where s.user_id = target
        order by s.created_at desc limit 10
      ) recent), '[]'),
    'companies', coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'role', m.role, 'status', c.status))
      from public.company_members m join public.companies c on c.id = m.company_id
      where m.user_id = target), '[]'),
    'admin_role', (select role from public.admins where user_id = target),
    'applications', (select count(*) from public.applications where user_id = target)
  );

  insert into public.audit_log (actor_id, actor_email, action, target_type, target_id, details)
  values (auth.uid(), (select email from auth.users where id = auth.uid()), 'view', 'users', target::text,
          jsonb_build_object('label', u.email, 'viewed', 'sign-in details'));
  return result;
end $$;

revoke all on function public.admin_user_login(uuid) from public, anon;
grant execute on function public.admin_user_login(uuid) to authenticated;

-- ===========================================================================
-- 3. Job review: approve, decline (send back for changes) or reject
-- ===========================================================================

alter table public.jobs add column if not exists review_note text not null default '';
alter table public.jobs add column if not exists reviewed_at timestamptz;
alter table public.jobs add column if not exists reviewed_by uuid references auth.users(id) on delete set null;

alter table public.jobs drop constraint if exists jobs_status_check;
alter table public.jobs add constraint jobs_status_check
  check (status in ('draft', 'pending', 'published', 'closed', 'declined', 'rejected'));

-- On by default; can be switched off in Platform settings.
insert into public.platform_settings (key, value) values ('require_job_approval', 'true')
on conflict (key) do nothing;

create or replace function public.jobs_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  approved boolean;
  goes_live text;
begin
  -- Admins and moderators: record who reviewed it, and date the job from when it went live.
  if public.is_system_write() or public.admin_level() >= 2 then
    new.updated_at := now();
    if tg_op = 'UPDATE' and new.status is distinct from old.status
       and old.status in ('draft', 'pending', 'declined') and new.status in ('published', 'declined', 'rejected') then
      new.reviewed_at := now();
      new.reviewed_by := auth.uid();
      if new.status = 'published' then
        new.posted_at := now();
        new.review_note := '';
      end if;
    end if;
    return new;
  end if;

  -- Employers.
  select status = 'approved' into approved from public.companies where id = new.company_id;
  goes_live := case when coalesce(approved, false) and not public.setting_bool('require_job_approval', true)
                    then 'published' else 'pending' end;
  new.updated_at := now();

  if tg_op = 'INSERT' then
    if new.status <> 'draft' then new.status := goes_live; end if;
    new.created_by := auth.uid();
    new.applicants := 0;
    new.views := 0;
    new.posted_at := now();
    new.featured := false;
    new.review_note := '';
    new.reviewed_at := null;
    new.reviewed_by := null;
    return new;
  end if;

  if old.status = 'rejected' then
    new.status := 'rejected';                                   -- final
  elsif new.status in ('declined', 'rejected') then
    new.status := old.status;                                   -- only admins decide these
  elsif new.status in ('pending', 'published') and old.status not in ('published', 'closed') then
    new.status := goes_live;                                    -- new or resubmitted: review first
  elsif new.status = 'published' and not coalesce(approved, false) then
    new.status := 'pending';
  end if;

  new.applicants := old.applicants;
  new.views := old.views;
  new.created_by := old.created_by;
  new.featured := old.featured;
  new.review_note := old.review_note;
  new.reviewed_at := old.reviewed_at;
  new.reviewed_by := old.reviewed_by;
  if old.status in ('draft', 'declined') and new.status in ('pending', 'published') then new.posted_at := now(); end if;
  return new;
end $$;

-- Approving a company no longer publishes its waiting jobs while job review is on.
create or replace function public.companies_after() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.owner_id is not null then
    insert into public.company_members (company_id, user_id, role) values (new.id, new.owner_id, 'owner')
    on conflict do nothing;
  end if;
  if tg_op = 'UPDATE' and new.status = 'approved' and old.status is distinct from 'approved'
     and not public.setting_bool('require_job_approval', true) then
    perform set_config('vsl.system', 'on', true);
    update public.jobs set status = 'published', posted_at = now() where company_id = new.id and status = 'pending';
    perform set_config('vsl.system', '', true);
  end if;
  return null;
end $$;

-- Employers can delete drafts and jobs that were declined or rejected.
drop policy if exists "members delete draft jobs" on public.jobs;
create policy "members delete draft jobs" on public.jobs for delete
  using (public.is_company_member(company_id) and status in ('draft', 'declined', 'rejected'));

-- ===========================================================================
-- 4. Approved employers get the verified check mark
-- ===========================================================================

create or replace function public.companies_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.is_system_write() or public.admin_level() >= 2 then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.status := case when public.setting_bool('require_company_approval', true) then 'pending' else 'approved' end;
    new.verified := false;   -- the check mark only comes from an admin approving
    new.owner_id := auth.uid();
    return new;
  end if;
  new.status := old.status;
  new.verified := old.verified;
  new.owner_id := old.owner_id;
  return new;
end $$;


-- ===========================================================================
-- 5. Messages on an application (employer ⇄ candidate)
-- ===========================================================================
--
-- The employer starts the conversation; the candidate can then reply. Only the
-- candidate and members of the hiring company can read or write the thread
-- (admins can read it). The other side gets a notification for each message.

create table if not exists public.application_messages (
  id              uuid primary key default gen_random_uuid(),
  application_id  text not null references public.applications(id) on delete cascade,
  sender_id       uuid references auth.users(id) on delete set null,
  sender_role     text not null check (sender_role in ('candidate', 'employer')),
  body            text not null check (length(btrim(body)) between 1 and 4000),
  created_at      timestamptz not null default now(),
  read_at         timestamptz
);
create index if not exists application_messages_thread_idx on public.application_messages (application_id, created_at);

-- 'candidate', 'employer' or null for the signed-in user on this application.
create or replace function public.message_role(app_id text) returns text
language sql stable security definer set search_path = public as $$
  select case when a.user_id = auth.uid() then 'candidate'
              when public.is_company_member(j.company_id) then 'employer' end
  from public.applications a join public.jobs j on j.id = a.job_id
  where a.id = app_id;
$$;

create or replace function public.application_messages_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r text := public.message_role(new.application_id);
begin
  if r is null then raise exception 'You are not part of this application.' using errcode = '42501'; end if;
  if public.is_suspended() then raise exception 'Your account is suspended.' using errcode = '42501'; end if;
  if r = 'candidate' and not exists (
       select 1 from public.application_messages m where m.application_id = new.application_id and m.sender_role = 'employer')
     and not exists (
       select 1 from public.applications a where a.id = new.application_id and coalesce(a.data->>'employer_message', '') <> '') then
    raise exception 'You can reply once the employer has messaged you.' using errcode = '42501';
  end if;
  new.sender_role := r;
  new.sender_id := auth.uid();
  new.created_at := now();
  new.read_at := null;
  new.body := btrim(new.body);
  return new;
end $$;

drop trigger if exists application_messages_guard on public.application_messages;
create trigger application_messages_guard before insert on public.application_messages
  for each row execute function public.application_messages_guard();

-- Notify the other side.
create or replace function public.application_messages_notify() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  a public.applications;
  job_title text;
  company text;
  preview text := left(new.body, 140);
begin
  select * into a from public.applications where id = new.application_id;
  select j.title, c.name into job_title, company
  from public.jobs j join public.companies c on c.id = j.company_id where j.id = a.job_id;

  if new.sender_role = 'employer' then
    insert into public.notifications (user_id, type, title, body, job_id, application_id)
    values (a.user_id, 'message', format('Message from %s', company), preview, a.job_id, a.id);
  else
    insert into public.notifications (user_id, type, title, body, job_id, application_id)
    select m.user_id, 'message',
           format('Reply from %s', coalesce(a.data#>>'{applicant,full_name}', 'a candidate')),
           format('%s · %s', job_title, preview), a.job_id, a.id
    from public.company_members m join public.jobs j on j.company_id = m.company_id
    where j.id = a.job_id;
  end if;
  return null;
end $$;

drop trigger if exists application_messages_notify on public.application_messages;
create trigger application_messages_notify after insert on public.application_messages
  for each row execute function public.application_messages_notify();

-- Marks the other side's messages in a thread as read.
create or replace function public.mark_messages_read(app_id text) returns void
language plpgsql security definer set search_path = public as $$
declare r text := public.message_role(app_id);
begin
  if r is null then return; end if;
  update public.application_messages set read_at = now()
  where application_id = app_id and sender_role <> r and read_at is null;
end $$;
revoke all on function public.mark_messages_read(text) from public, anon;
grant execute on function public.mark_messages_read(text) to authenticated;

alter table public.application_messages enable row level security;
revoke all on public.application_messages from anon;

drop policy if exists "thread members read messages" on public.application_messages;
create policy "thread members read messages" on public.application_messages for select
  using (public.message_role(application_id) is not null or public.admin_level() >= 1);
drop policy if exists "thread members send messages" on public.application_messages;
create policy "thread members send messages" on public.application_messages for insert to authenticated
  with check (public.message_role(application_id) is not null);

notify pgrst, 'reload schema';

-- ===========================================================================
-- 6. Help & FAQs, Terms of Use, Privacy Policy
-- ===========================================================================
-- Fills a page only while it is still empty, so edits made in
-- Admin → Content are never overwritten. Edit them there at any time.

update public.site_pages set title = 'Help & FAQs', updated_at = now(), body = $page$
# Welcome to Vocation SL

Vocation SL helps people across Sierra Leone find work, and helps employers find the right people. This page answers the questions we hear most. If yours isn't here, email us at vocationxsl@gmail.com and a member of our team will get back to you.

# For job seekers

How much does it cost to use Vocation SL?
Nothing. Searching, saving jobs, applying and messaging employers are free for job seekers.

How do I apply for a job?
Open the job, tap Apply, choose or upload your CV, add a cover letter if you like, and send. You can follow every application under Applications, from Submitted to Viewed, Shortlisted, Interview and Offer.

What files can I upload?
CVs and cover letters in PDF, DOC or DOCX format. PDF is best: employers can read it straight away in the app.

Can I see my own CV and cover letter after applying?
Yes. Open the application and tap the document to view it. Your current CV is also on your Profile.

How do I talk to an employer?
When an employer writes to you about an application, you get a notification and the message appears on that application. You can reply there. To keep conversations relevant, replies open once the employer has written first.

Can I search jobs outside Freetown?
Yes. Filter by any of Sierra Leone's 16 districts or by main town, as well as by industry, job type, experience, salary, remote work and date posted.

Does the app work with a weak connection?
Yes. Jobs and your applications are saved on your device, so you can keep browsing offline. Anything you change is sent when you're back online.

How do I withdraw an application?
Open it under Applications and tap Withdraw application. The employer is told you are no longer interested. This can't be undone.

# Staying safe

A genuine employer will never ask you to pay to apply, to attend an interview, or for a uniform, training or a medical before you are hired. If anyone asks you for money, stop and report the job: open it, tap the menu (⋮) and choose Report this job. Our team reviews every report.

Never share your password, mobile money PIN or bank details with an employer.

# For employers

How do I post a job?
Choose Hire talent when you sign in, register your company and post your vacancy. New companies are reviewed by our team before their jobs can go live.

Why is my job "Awaiting approval"?
Every job is reviewed by our team before it is published, to keep listings genuine and accurate. You'll see the status change in My jobs as soon as it has been reviewed.

My job says "Changes needed". What do I do?
Our team has sent it back with a note explaining what to fix. Edit the job and tap Resubmit for review.

What does the green check mark mean?
It shows that our team has verified the company. Approved companies can post jobs; the check mark is an extra step our team adds separately. It is not a guarantee about the company, so job seekers should still take the usual care.

Is posting a job free?
Charges for job listings are agreed with each employer. Where a fee applies, we send an invoice for the listing once it is approved. Contact us for current rates.

Can I message candidates?
Yes. Open a candidate and write in Messages. They are notified and can reply, and you'll see a badge on your candidate list when they do.

# Your account

How do I reset my password?
On the sign-in screen, tap Forgot password and follow the link we email you.

How do I delete my account?
Go to Settings → Delete account. This permanently removes your profile, CV, cover letters, saved jobs and applications.

My account has been suspended. What can I do?
You'll see the reason on screen. If you think it's a mistake, email vocationxsl@gmail.com from the address on your account.

# Contact us

Email: vocationxsl@gmail.com
$page$
where slug = 'help' and btrim(body) = '';

update public.site_pages set title = 'Terms of Use', updated_at = now(), body = $page$
# Terms of Use

Effective date: 7 October 2026

These terms are an agreement between you and Vocation SL ("we", "us"). They apply whenever you use the Vocation SL app or website. By creating an account or using the service, you agree to them. If you don't agree, please don't use Vocation SL.

# 1. What Vocation SL is

Vocation SL is an online platform that lists job vacancies in Sierra Leone and lets job seekers apply and communicate with employers. We are not an employer or a recruitment agency for the jobs listed, we are not a party to any job offer or employment contract, and we do not guarantee that you will find work or suitable candidates.

# 2. Your account

You must be at least 18 years old to create an account.
Give accurate information and keep it up to date.
Keep your password private. You are responsible for activity on your account.
One person per account. Don't create an account for someone else without their permission.
Tell us straight away at vocationxsl@gmail.com if you think your account has been misused.

# 3. Job seekers

Only apply with information and documents that are true and your own.
Your CV, cover letter, profile and messages are shared with an employer when you apply to their job.
Using Vocation SL as a job seeker is free.

# 4. Employers

Only post real, current vacancies that you are authorised to fill, with honest information about the role, pay and location.
You must never ask candidates for money, at any stage, for any reason.
Use candidates' information only to consider them for the job they applied to, and handle it securely and lawfully.
Every company and every job is reviewed by our team before it goes live. We may approve, send back for changes, reject, close or remove any listing.
Charges for job listings, if any, are agreed with you in advance and set out on our invoice. Invoices are payable by the due date shown.

# 5. Things you must not do

Post false, misleading, discriminatory or illegal content.
Collect fees from job seekers, or use the platform for scams, pyramid schemes or unrelated advertising.
Harass, threaten or abuse anyone.
Copy, scrape or resell listings or user data.
Try to break, overload or get around the security of the service.

# 6. Reviews, suspensions and removal

To keep Vocation SL safe, we may review content, remove listings, and suspend or close accounts that break these terms or put other users at risk. Where we can, we will tell you why. If you think we got it wrong, email vocationxsl@gmail.com.

# 7. Your content

You keep ownership of what you upload. You give us permission to store, display and share it as needed to run the service, for example showing your application to the employer you applied to. This permission ends when you delete the content or your account, except where we must keep records by law.

# 8. Availability

We work hard to keep Vocation SL running, but we can't promise it will always be available or error-free. We may change or improve features over time.

# 9. Our responsibility

Employers are responsible for their listings and hiring decisions, and job seekers for the information they provide. We are not responsible for the conduct of other users, or for any loss arising from a job, offer or contact made through Vocation SL, except where the law says we cannot limit our responsibility.

# 10. Ending your use

You can stop using Vocation SL at any time and delete your account in Settings → Delete account.

# 11. Changes to these terms

We may update these terms. When we make important changes we will let you know in the app. Continuing to use Vocation SL after a change means you accept the updated terms.

# 12. Law

These terms are governed by the laws of Sierra Leone.

# 13. Contact

Questions about these terms: vocationxsl@gmail.com
$page$
where slug = 'terms' and btrim(body) = '';

update public.site_pages set title = 'Privacy Policy', updated_at = now(), body = $page$
# Privacy Policy

Effective date: 7 October 2026

Your trust matters to us. This policy explains what information Vocation SL collects, why, who can see it, and the choices you have.

# Information we collect

Account details: your name, email address, phone number, and whether you use Vocation SL to find a job or to hire.
Sign-in information: how you sign in (email and password, or Google), when your account was created, when you last signed in, and the device and browser of your active sessions. Passwords are stored only in encrypted (hashed) form and can't be read by anyone, including us.
Profile: what you choose to add, such as your photo, headline, location, experience, education, skills, languages, certifications and job preferences.
Documents: CVs and cover letters you upload.
Applications and messages: the jobs you apply to, their progress, and messages between you and employers.
Employer information: company details and logo, job listings, candidate stages and invoices.
Reports you send us about jobs or users.
Activity on the service, such as job views, saved jobs and saved searches, used to run features and count views.

# How we use it

To run Vocation SL: show jobs, send applications, deliver messages and notifications, and keep your account working.
To keep the service safe: review companies and jobs before they go live, investigate reports, and prevent fraud and misuse.
To improve the service, using totals and trends.
To contact you about your account or important changes.

We do not sell your personal information.

# Who can see your information

Employers: when you apply to a job, that employer can see your application, CV, cover letter, profile and your messages with them. Employers you have not applied to cannot see your CV or applications.
Job seekers: can see company profiles and job listings.
Our team: authorised Vocation SL staff can access information when needed to review content, handle reports, provide support and keep the service secure. Access depends on each person's role, and admin actions, including viewing a user's sign-in details, are recorded.
Service providers: we use trusted providers to host our database, files and website, Google if you choose to sign in with Google, and Anthropic''s Claude AI to read your CV when you tap "Fill my profile from my CV". They process information only to provide their services to us. These providers may store information on servers outside Sierra Leone.
Legal requests: we may share information where the law requires it.

# Information on your device

The app keeps a copy of jobs, your profile and your applications on your device so it works offline. Signing out stops your account being used on that device.

# How long we keep it

We keep your information while your account is open. When you delete your account, we delete your profile, documents, saved items and applications. Records we must keep for legal or accounting reasons, such as employer invoices and our admin activity log, may be kept for as long as required.

# Your choices and rights

View and update your profile at any time in the app.
View your own CV and cover letters in the app.
Control notifications in Settings.
Delete your account and data in Settings → Delete account.
Ask us for a copy of your information, or to correct it, by emailing vocationxsl@gmail.com from the address on your account.

# Security

We use access rules so that people can see only what they are allowed to, private storage for documents, short-lived links for viewing files, and encrypted connections. No system is perfectly secure, so please use a strong password and keep it private.

# Children

Vocation SL is for people aged 18 and over. We do not knowingly collect information from children.

# Changes to this policy

We may update this policy. When we make important changes we will tell you in the app before they take effect.

# Contact

Questions or requests about your privacy: vocationxsl@gmail.com
$page$
where slug = 'privacy' and btrim(body) = '';

notify pgrst, 'reload schema';
