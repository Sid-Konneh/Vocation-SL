-- Release 1.2.10: report and block in employer ⇄ candidate conversations
-- (App Store guideline 1.2: apps with user messaging need reporting and blocking).
--
-- A block is between a company and a candidate, in either direction, and
-- covers every application between them: once either side blocks, neither can
-- send new messages. Reports go to the existing Admin → Reports queue.
--
-- Run this in the Supabase SQL editor BEFORE deploying the 1.2.10 web app.
-- Safe to run more than once.

create table if not exists public.conversation_blocks (
  company_id  text not null references public.companies(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  blocked_by  text not null check (blocked_by in ('candidate', 'employer')),
  created_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  primary key (company_id, user_id, blocked_by)
);

alter table public.conversation_blocks enable row level security;
revoke all on public.conversation_blocks from anon, authenticated;
-- Read and written only through the functions below; admins can read.
drop policy if exists "admins read blocks" on public.conversation_blocks;
create policy "admins read blocks" on public.conversation_blocks for select using (public.admin_level() >= 1);
grant select on public.conversation_blocks to authenticated;

-- The company and candidate behind an application.
create or replace function public.conversation_parties(app_id text, out company_id text, out user_id uuid, out company_name text, out candidate_name text)
language sql stable security definer set search_path = public as $$
  select j.company_id, a.user_id, coalesce(c.name, ''), coalesce(p.full_name, '')
  from public.applications a
  join public.jobs j on j.id = a.job_id
  left join public.companies c on c.id = j.company_id
  left join public.profiles p on p.id = a.user_id
  where a.id = app_id;
$$;
revoke all on function public.conversation_parties(text) from public, anon, authenticated;

-- True when either side has blocked the other.
create or replace function public.conversation_blocked(app_id text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.conversation_blocks b, public.conversation_parties(app_id) cp
    where b.company_id = cp.company_id and b.user_id = cp.user_id);
$$;
revoke all on function public.conversation_blocked(text) from public, anon;
grant execute on function public.conversation_blocked(text) to authenticated;

-- For the signed-in user: {"blocked_by_me": bool, "blocked_by_them": bool}.
create or replace function public.conversation_status(app_id text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  r text := public.message_role(app_id);
  cp record;
begin
  if r is null then raise exception 'You are not part of this conversation.'; end if;
  select * into cp from public.conversation_parties(app_id);
  return jsonb_build_object(
    'blocked_by_me', exists (select 1 from public.conversation_blocks where company_id = cp.company_id and user_id = cp.user_id and blocked_by = r),
    'blocked_by_them', exists (select 1 from public.conversation_blocks where company_id = cp.company_id and user_id = cp.user_id and blocked_by <> r));
end $$;
revoke all on function public.conversation_status(text) from public, anon;
grant execute on function public.conversation_status(text) to authenticated;

-- Blocks (p_block = true) or unblocks the other side of this conversation.
create or replace function public.block_conversation(app_id text, p_block boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  r text := public.message_role(app_id);
  cp record;
begin
  if r is null then raise exception 'You are not part of this conversation.'; end if;
  select * into cp from public.conversation_parties(app_id);
  if p_block then
    insert into public.conversation_blocks (company_id, user_id, blocked_by, created_by)
    values (cp.company_id, cp.user_id, r, auth.uid())
    on conflict do nothing;
  else
    delete from public.conversation_blocks where company_id = cp.company_id and user_id = cp.user_id and blocked_by = r;
  end if;
end $$;
revoke all on function public.block_conversation(text, boolean) from public, anon;
grant execute on function public.block_conversation(text, boolean) to authenticated;

-- Reports the other side: a candidate reports the company, an employer
-- reports the candidate. Moderators see it in Admin → Reports.
create or replace function public.report_conversation(app_id text, p_reason text, p_details text default '') returns void
language plpgsql security definer set search_path = public as $$
declare
  r text := public.message_role(app_id);
  cp record;
begin
  if r is null then raise exception 'You are not part of this conversation.'; end if;
  if length(btrim(coalesce(p_reason, ''))) = 0 then raise exception 'Choose a reason.'; end if;
  select * into cp from public.conversation_parties(app_id);
  insert into public.reports (reporter_id, target_type, target_id, target_label, reason, details)
  values (auth.uid(),
          case when r = 'candidate' then 'company' else 'user' end,
          case when r = 'candidate' then cp.company_id else cp.user_id::text end,
          case when r = 'candidate' then cp.company_name else cp.candidate_name end,
          p_reason,
          btrim(format('Messages on application %s. %s', app_id, coalesce(p_details, ''))));
end $$;
revoke all on function public.report_conversation(text, text, text) from public, anon;
grant execute on function public.report_conversation(text, text, text) to authenticated;

-- No new messages once either side has blocked.
drop policy if exists "thread members send messages" on public.application_messages;
create policy "thread members send messages" on public.application_messages for insert to authenticated
  with check (public.message_role(application_id) is not null and not public.conversation_blocked(application_id));

notify pgrst, 'reload schema';
