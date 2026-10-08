-- Vocation SL — employers see their invoices once issued (run after
-- admin_more_schema.sql and push_schema.sql). Safe to re-run.

-- Company members can read their company's invoices, except drafts.
drop policy if exists "employers read issued invoices" on public.invoices;
create policy "employers read issued invoices" on public.invoices for select
  using (status <> 'draft' and company_id is not null and public.is_company_member(company_id));

-- Alert the company's team when an invoice is issued.
create or replace function public.invoice_issued_notify() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'issued' and (tg_op = 'INSERT' or old.status is distinct from 'issued') and new.company_id is not null then
    insert into public.notifications (user_id, type, title, body, job_id)
    select m.user_id, 'invoice', 'New invoice from Vocation SL',
           format('%s · %s %s due %s', new.number, new.currency, to_char(new.total, 'FM999,999,990.00'),
                  coalesce(to_char(new.due_date, 'DD Mon YYYY'), 'on receipt')),
           new.job_id
    from public.company_members m where m.company_id = new.company_id;
  end if;
  return null;
end $$;

drop trigger if exists invoice_issued_notify on public.invoices;
create trigger invoice_issued_notify after insert or update of status on public.invoices
  for each row execute function public.invoice_issued_notify();

-- Push alerts: invoice alerts open the employer's Invoices screen.
create or replace function public.push_on_notification() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare
  fn_url text;
  secret text;
  prefs  jsonb;
  route  text := '/alerts';
  app_owner uuid;
begin
  select value into fn_url from private.push_config where key = 'function_url';
  select value into secret from private.push_config where key = 'webhook_secret';
  if fn_url is null or secret is null then return null; end if;
  if not exists (select 1 from public.push_tokens where user_id = new.user_id) then return null; end if;

  select data->'notification_preferences' into prefs from public.profiles where id = new.user_id;
  if coalesce((prefs->>'push_enabled')::boolean, true) = false then return null; end if;
  if coalesce((prefs->'enabled'->>new.type)::boolean, true) = false then return null; end if;

  if new.type = 'invoice' then
    route := '/employer/invoices';
  elsif new.application_id is not null then
    select user_id into app_owner from public.applications where id = new.application_id;
    if app_owner is distinct from new.user_id then route := '/employer/candidates/' || new.application_id; end if;
  end if;

  perform net.http_post(
    url := fn_url,
    body := jsonb_build_object(
      'user_id', new.user_id, 'title', new.title, 'body', new.body, 'type', new.type,
      'notification_id', new.id, 'application_id', new.application_id, 'job_id', new.job_id, 'route', route),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', secret),
    timeout_milliseconds := 5000
  );
  return null;
exception when others then
  return null;
end $$;

notify pgrst, 'reload schema';
