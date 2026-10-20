-- Vocation SL — companies created by admin accounts had no owner (run once).
-- Cause: companies_guard returned early for admins before setting owner_id,
-- so an admin who created their own company could never find it again and
-- each attempt created another one.

-- 1. Always record who created a company, admins included.
create or replace function public.companies_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.owner_id is null and auth.uid() is not null then
    new.owner_id := auth.uid();
  end if;
  if public.is_system_write() or public.admin_level() >= 2 then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.status := case when public.setting_bool('require_company_approval', true) then 'pending' else 'approved' end;
    new.verified := false;   -- the check mark only comes from an admin
    new.owner_id := auth.uid();
    return new;
  end if;
  new.status := old.status;
  new.verified := old.verified;
  new.owner_id := old.owner_id;
  return new;
end $$;

-- 2. Repair vocationxsl@gmail.com: keep the newest approved "Vocation SL"
--    company, give it its owner, and remove the extra copies (only ones with no jobs).
do $$
declare
  uid  uuid;
  keep text;
begin
  select id into uid from auth.users where email = 'vocationxsl@gmail.com';
  if uid is null then raise notice 'Account not found'; return; end if;

  select id into keep from public.companies
   where owner_id is null and email = 'vocationxsl@gmail.com'
   order by (status = 'approved') desc, created_at desc
   limit 1;
  if keep is null then raise notice 'No company to repair'; return; end if;

  perform set_config('vsl.system', 'on', true);
  update public.companies set owner_id = uid where id = keep;
  insert into public.company_members (company_id, user_id, role) values (keep, uid, 'owner')
  on conflict do nothing;

  delete from public.companies c
   where c.owner_id is null and c.email = 'vocationxsl@gmail.com' and c.id <> keep
     and not exists (select 1 from public.jobs j where j.company_id = c.id);
  perform set_config('vsl.system', '', true);

  raise notice 'Kept company %', keep;
end $$;

-- 3. Check: should show one Vocation SL company, owned, with is_member = true.
select c.id, c.name, c.status, c.owner_id is not null as has_owner,
       exists (select 1 from public.company_members m where m.company_id = c.id and m.user_id = c.owner_id) as is_member,
       (select count(*) from public.companies x where x.email = 'vocationxsl@gmail.com') as companies_with_this_email
from public.companies c
where c.owner_id = (select id from auth.users where email = 'vocationxsl@gmail.com');
