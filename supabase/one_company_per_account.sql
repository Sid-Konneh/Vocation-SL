-- Vocation SL — one company per account (run after employer_schema.sql). Safe to re-run.
-- An account (one email) can own or belong to only one company. A second
-- "create company" is refused with a clear message; the app updates the
-- existing company instead.

-- 1. Every company's creator is a member (needed to post jobs and upload a logo).
insert into public.company_members (company_id, user_id, role)
select c.id, c.owner_id, 'owner' from public.companies c
where c.owner_id is not null
  and not exists (select 1 from public.company_members m where m.company_id = c.id and m.user_id = c.owner_id)
on conflict do nothing;

-- 2. Refuse a second company for the same account.
create or replace function public.one_company_per_account() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.is_system_write() then return new; end if;
  if exists (select 1 from public.company_members where user_id = auth.uid())
     or exists (select 1 from public.companies where owner_id = auth.uid()) then
    raise exception 'This account already has a company. Open Company profile to edit it.';
  end if;
  return new;
end $$;

drop trigger if exists one_company_per_account on public.companies;
create trigger one_company_per_account before insert on public.companies
  for each row execute function public.one_company_per_account();

-- 3. Backstop at the table level: one owned company per account.
create unique index if not exists companies_one_per_owner on public.companies (owner_id) where owner_id is not null;

notify pgrst, 'reload schema';
