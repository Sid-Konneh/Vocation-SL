-- Vocation SL — "Approve new companies" and "Review every job" also apply when
-- the employer account belongs to an admin or moderator (run after
-- checkmark_fix.sql and admin_more_schema.sql). Safe to re-run.
--
-- Before: admin and moderator accounts skipped both rules, so a company or job
-- they created as an employer went live at once even with both switches on.
-- Now: creating a company or posting a job follows Platform settings for
-- everyone. Admins still approve, decline, verify and edit from the admin panel.

create or replace function public.companies_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.is_system_write() then return new; end if;
  if tg_op = 'INSERT' then
    new.status := case when public.setting_bool('require_company_approval', true) then 'pending' else 'approved' end;
    new.verified := false;     -- the check mark only comes from an admin, separately
    new.owner_id := auth.uid();
    return new;
  end if;
  if public.admin_level() >= 2 then return new; end if;   -- approving, verifying, suspending
  new.status := old.status;
  new.verified := old.verified;
  new.owner_id := old.owner_id;
  return new;
end $$;

create or replace function public.jobs_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  approved boolean;
  goes_live text;
  as_admin boolean;
begin
  -- Admin path: moderation decisions and edits from the admin panel. Not used when
  -- an admin posts a new job, or submits a draft or declined job, for their own company.
  as_admin := public.is_system_write() or (
    public.admin_level() >= 2 and tg_op = 'UPDATE'
    and not (public.is_company_member(new.company_id)
             and old.status in ('draft', 'declined') and new.status in ('pending', 'published')));

  if as_admin then
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

  -- Employers (including admins posting for their own company).
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

-- Check the two switches (both should say true while approval is wanted):
select key, value from public.platform_settings where key in ('require_company_approval', 'require_job_approval');
