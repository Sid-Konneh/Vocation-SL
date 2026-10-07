-- Vocation SL — self-service account deletion (run after employer_schema.sql).
-- Safe to re-run.
--
-- delete_my_account() deletes ONLY the signed-in user (auth.uid()):
--   * their auth account; profile, applications, notifications, saved jobs,
--     job alerts and company memberships go with it (ON DELETE CASCADE);
--   * any company where they are the ONLY member, with its jobs (and the
--     applications to those jobs).
-- Uploaded files (CVs, cover letters, logos) are removed by the app through
-- the Storage API just before this runs, because Supabase does not allow
-- deleting storage files from SQL.

create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not signed in';
  end if;

  delete from public.companies c
  where exists (select 1 from public.company_members m where m.company_id = c.id and m.user_id = uid)
    and not exists (select 1 from public.company_members m where m.company_id = c.id and m.user_id <> uid);

  delete from auth.users where id = uid;
end $$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

notify pgrst, 'reload schema';
