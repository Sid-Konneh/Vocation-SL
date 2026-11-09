-- Vocation SL — team invites for colleagues who don't have an account yet.
--
-- A company owner adds a colleague by email (Company → Team):
--   * the email already has an account → they join the team straight away
--     (as before);
--   * no account yet → an invite is saved and emailed (Edge Function
--     "team-invite"). When they create an account with that email, they join
--     the company as a recruiter, their account is set to the employer side,
--     and they go straight to the employer dashboard: no company setup.
--
-- Run after release_1_1.sql. Safe to run again.

create table if not exists public.team_invites (
  email       text primary key,                       -- lower-case
  company_id  text not null references public.companies(id) on delete cascade,
  invited_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  emailed_at  timestamptz,
  email_error text
);
-- Private code in the invite link: lets the colleague create an account that
-- is already confirmed (Edge Function "team-invite", action "signup").
alter table public.team_invites add column if not exists token text not null default replace(gen_random_uuid()::text, '-', '');
alter table public.team_invites enable row level security;
revoke all on public.team_invites from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Team list: members, then invites that are still waiting (user_id is null).
-- ---------------------------------------------------------------------------
drop function if exists public.team_members();
create function public.team_members() returns table (user_id uuid, role text, name text, email text, added_at timestamptz)
language sql stable security definer set search_path = public as $$
  with mine as (select company_id from public.company_members where user_id = auth.uid() limit 1)
  select * from (
    select m.user_id, m.role, coalesce(p.full_name, ''), coalesce(u.email, '')::text, m.created_at
    from public.company_members m
    join auth.users u on u.id = m.user_id
    left join public.profiles p on p.id = m.user_id
    where m.company_id = (select company_id from mine)
    order by m.role = 'owner' desc, m.created_at
  ) members
  union all
  select * from (
    -- Placeholder id (no account yet): older app versions expect a value here.
    select md5('invite:' || i.email)::uuid, 'invited', '', i.email, i.created_at
    from public.team_invites i
    where i.company_id = (select company_id from mine)
    order by i.created_at
  ) invites;
$$;
grant execute on function public.team_members() to authenticated;

-- Emails waiting invites through the "team-invite" Edge Function.
create or replace function public.kick_team_invites() returns void
language plpgsql security definer set search_path = public as $$
declare fn_url text; secret text;
begin
  -- Only invites not emailed yet; a failed one is retried for 2 days.
  if not exists (select 1 from public.team_invites where emailed_at is null and created_at > now() - interval '2 days') then
    return;
  end if;
  select value into fn_url from private.push_config where key = 'team_invite_url';
  select value into secret from private.push_config where key = 'webhook_secret';
  if fn_url is null or secret is null then return; end if;
  perform net.http_post(
    url := fn_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', secret),
    timeout_milliseconds := 60000
  );
end $$;
revoke all on function public.kick_team_invites() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Add a colleague. Returns 'added' (has an account) or 'invited' (emailed).
-- ---------------------------------------------------------------------------
drop function if exists public.add_team_member(text);
create function public.add_team_member(p_email text) returns text
language plpgsql security definer set search_path = public as $$
declare
  cid text;
  cname text;
  target uuid;
  addr text := lower(trim(p_email));
  other text;
begin
  select m.company_id into cid from public.company_members m where m.user_id = auth.uid() and m.role = 'owner' limit 1;
  if cid is null then raise exception 'Only the company owner can add team members.'; end if;
  if addr !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Enter your colleague''s email address.'; end if;
  select id into target from auth.users where lower(email) = addr limit 1;

  if target is null then
    select company_id into other from public.team_invites where email = addr;
    if other is not null and other <> cid then
      raise exception 'That email has already been invited by another company.';
    end if;
    insert into public.team_invites (email, company_id, invited_by)
    values (addr, cid, auth.uid())
    on conflict (email) do update set invited_by = excluded.invited_by, created_at = now(), emailed_at = null, email_error = null,
      token = replace(gen_random_uuid()::text, '-', '');
    perform public.kick_team_invites();
    return 'invited';
  end if;

  if target = auth.uid() then raise exception 'You''re already on the team.'; end if;
  if exists (select 1 from public.company_members where user_id = target) or exists (select 1 from public.companies where owner_id = target) then
    raise exception 'That account already belongs to a company.';
  end if;
  insert into public.company_members (company_id, user_id, role) values (cid, target, 'recruiter');
  select name into cname from public.companies where id = cid;
  insert into public.notifications (user_id, type, title, body)
  values (target, 'team', 'You were added to ' || cname,
          'You can now post jobs and review candidates for ' || cname || '. Open Vocation SL and choose Hire talent.');
  return 'added';
end $$;
grant execute on function public.add_team_member(text) to authenticated;

create or replace function public.remove_team_invite(p_email text) returns void
language plpgsql security definer set search_path = public as $$
declare cid text;
begin
  select m.company_id into cid from public.company_members m where m.user_id = auth.uid() and m.role = 'owner' limit 1;
  if cid is null then raise exception 'Only the company owner can cancel invites.'; end if;
  delete from public.team_invites where email = lower(trim(p_email)) and company_id = cid;
end $$;
grant execute on function public.remove_team_invite(text) to authenticated;

-- ---------------------------------------------------------------------------
-- New account: create the profile (as before), then accept a waiting invite.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  -- Email sign-up sends full_name; Google sends full_name or name.
  display_name text := coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(new.email, '@', 1));
  inv public.team_invites;
  cname text;
begin
  insert into public.profiles (id, email, full_name, data)
  values (
    new.id,
    new.email,
    display_name,
    jsonb_build_object('id', new.id, 'email', new.email, 'full_name', display_name)
  )
  on conflict (id) do nothing;

  -- Never let an invite problem stop someone signing up.
  begin
    select * into inv from public.team_invites where email = lower(new.email);
    if inv.email is not null then
      insert into public.company_members (company_id, user_id, role)
      values (inv.company_id, new.id, 'recruiter')
      on conflict do nothing;
      -- Employer side, so the app opens the company's dashboard.
      update auth.users
      set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || '{"role":"employer"}'::jsonb
      where id = new.id;
      update public.profiles set role = 'employer' where id = new.id;
      delete from public.team_invites where email = inv.email;
      select name into cname from public.companies where id = inv.company_id;
      insert into public.notifications (user_id, type, title, body)
      values (new.id, 'team', 'Welcome to ' || cname,
              'You''re on the ' || cname || ' team. You can post jobs, review candidates and message applicants.');
    end if;
  exception when others then
    raise warning 'team invite for % not applied: %', new.email, sqlerrm;
  end;
  return new;
end $$;

insert into private.push_config (key, value)
values ('team_invite_url', 'https://gkglfqsvxyemykpnjxik.supabase.co/functions/v1/team-invite')
on conflict (key) do update set value = excluded.value;

-- Retry invites the mailbox refused (e.g. Hostinger's limit) every minute.
-- While an invite waits, job-emails pauses so the invite goes first.
do $$
begin
  perform cron.unschedule('vsl-team-invites') where exists (select 1 from cron.job where jobname = 'vsl-team-invites');
  perform cron.schedule('vsl-team-invites', '* * * * *', 'select public.kick_team_invites()');
end $$;

notify pgrst, 'reload schema';
