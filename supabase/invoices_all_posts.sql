-- Vocation SL — an invoice for every job post (run after release_1_1.sql and
-- employer_invoices.sql). Safe to re-run.
--
--   * Employers selected in Admin → Platform settings ("free_posting_companies")
--     post free: each job gets a SLE 0 invoice marked paid.
--   * Launch offer: an employer's first free postings get a SLE 0 invoice (as before).
--   * Every other job gets a draft invoice at the posting price for an admin to issue
--     (as before).
--   This applies whether the job went live immediately or after admin approval, and
--   jobs that went live without an invoice get one now.

insert into public.platform_settings (key, value) values ('free_posting_companies', '[]')
on conflict (key) do nothing;

create or replace function public.invoice_for_job(j public.jobs) returns void
language plpgsql security definer set search_path = public as $$
declare
  c record;
  lo jsonb;
  free_n int;
  until_d date;
  used int;
  price numeric;
  free_cos jsonb;
  addr text;
begin
  select * into c from public.companies where id = j.company_id;
  if c.id is null then return; end if;
  addr := concat_ws(', ', nullif(c.address, ''), nullif(c.location, ''));
  select value into lo from public.platform_settings where key = 'launch_offer';
  free_n := coalesce((lo->>'free_posts')::int, 0);
  until_d := coalesce((lo->>'until')::date, date '2000-01-01');
  select coalesce((value#>>'{}')::numeric, 0) into price from public.platform_settings where key = 'posting_price';
  select coalesce(value, '[]') into free_cos from public.platform_settings where key = 'free_posting_companies';
  select count(*) into used from public.invoices where company_id = c.id and launch_free and status <> 'void';

  if jsonb_typeof(free_cos) = 'array' and free_cos ? c.id then
    insert into public.invoices (job_id, company_id, job_title, bill_to_name, bill_to_email, bill_to_address,
                                 unit_price, status, payment_method, notes, created_by)
    values (j.id, c.id, j.title, c.name, coalesce(c.email, ''), addr,
            0, 'paid', 'Free posting', 'Free posting: this employer posts free on Vocation SL', null)
    on conflict do nothing;
  elsif current_date <= until_d and used < free_n then
    insert into public.invoices (job_id, company_id, job_title, bill_to_name, bill_to_email, bill_to_address,
                                 unit_price, launch_free, status, payment_method, notes, created_by)
    values (j.id, c.id, j.title, c.name, coalesce(c.email, ''), addr,
            0, true, 'paid', 'Launch offer',
            format('Free posting %s of %s (launch offer until %s)', used + 1, free_n, to_char(until_d, 'DD Mon YYYY')), null)
    on conflict do nothing;
  else
    -- A draft for an admin to check and issue (employers see it once issued).
    insert into public.invoices (job_id, company_id, job_title, bill_to_name, bill_to_email, bill_to_address, unit_price, created_by)
    values (j.id, c.id, j.title, c.name, coalesce(c.email, ''), addr, coalesce(price, 0), null)
    on conflict do nothing;
  end if;
end $$;

-- The trigger already covers both routes to going live (published on insert,
-- or approved later); recreate it in case it is missing.
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

-- Backfill: live or closed jobs from real employers that have no invoice yet.
do $$
declare j public.jobs;
begin
  for j in select jb.* from public.jobs jb join public.companies c on c.id = jb.company_id
           where jb.status in ('published', 'closed') and c.owner_id is not null
             and not exists (select 1 from public.invoices i where i.job_id = jb.id and i.status <> 'void')
           order by jb.posted_at loop
    perform public.invoice_for_job(j);
  end loop;
end $$;

notify pgrst, 'reload schema';
