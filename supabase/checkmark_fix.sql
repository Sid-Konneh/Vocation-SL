-- Vocation SL — the verified check mark is given separately by an admin
-- (run after admin_more_schema.sql). Safe to re-run.
--
-- Approving, rejecting or suspending a company no longer changes its check
-- mark. Admins add or remove it with "Add verified badge" in Employer
-- verification.

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

-- Undo the check marks added automatically. Keep any an admin gave on its
-- own with "Add verified badge" (logged with a verified change and no status change).
do $$
begin
  perform set_config('vsl.system', 'on', true);
  update public.companies c set verified = false
  where c.verified and c.owner_id is not null
    and not exists (
      select 1 from public.audit_log l
      where l.target_type = 'companies' and l.target_id = c.id
        and l.details->>'verified' = 'true' and not (l.details ? 'status'));
  perform set_config('vsl.system', '', true);
end $$;

-- Help page wording (only if it still has the original sentence).
update public.site_pages
set body = replace(body,
  'It shows that our team has reviewed and approved the company''s account on Vocation SL. It is not a guarantee about the company, so job seekers should still take the usual care.',
  'It shows that our team has verified the company. Approved companies can post jobs; the check mark is an extra step our team adds separately. It is not a guarantee about the company, so job seekers should still take the usual care.')
where slug = 'help';
