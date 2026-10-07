-- Vocation SL — push notifications (Firebase Cloud Messaging). Safe to re-run.
--
-- 1. Each phone or browser that allows alerts registers its FCM token here.
-- 2. Every new row in public.notifications calls the "push" Edge Function,
--    which sends the alert to that user's devices through Firebase.
--
-- After running this file, set the Edge Function address and a secret
-- (see the bottom of this file).

create table if not exists public.push_tokens (
  token       text primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  platform    text not null check (platform in ('android', 'ios', 'web')),
  updated_at  timestamptz not null default now()
);
create index if not exists push_tokens_user_idx on public.push_tokens (user_id);

alter table public.push_tokens enable row level security;
revoke all on public.push_tokens from anon;
drop policy if exists "own push tokens" on public.push_tokens;
create policy "own push tokens" on public.push_tokens for select using (user_id = auth.uid());

-- A device that changes account moves its token to the new account.
create or replace function public.register_push_token(p_token text, p_platform text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in first.' using errcode = '42501'; end if;
  if p_platform not in ('android', 'ios', 'web') then raise exception 'Unknown platform.'; end if;
  insert into public.push_tokens (token, user_id, platform, updated_at)
  values (p_token, auth.uid(), p_platform, now())
  on conflict (token) do update set user_id = auth.uid(), platform = excluded.platform, updated_at = now();
end $$;

create or replace function public.unregister_push_token(p_token text) returns void
language sql security definer set search_path = public as $$
  delete from public.push_tokens where token = p_token and user_id = auth.uid();
$$;

revoke all on function public.register_push_token(text, text) from public, anon;
revoke all on function public.unregister_push_token(text) from public, anon;
grant execute on function public.register_push_token(text, text) to authenticated;
grant execute on function public.unregister_push_token(text) to authenticated;

-- Private settings: the Edge Function address and the shared secret.
-- The private schema is not exposed through the API.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table if not exists private.push_config (
  key    text primary key,
  value  text not null
);

create extension if not exists pg_net with schema extensions;

-- Sends each new alert to the Edge Function. Never blocks the alert itself.
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

  -- Respect the user's notification settings.
  select data->'notification_preferences' into prefs from public.profiles where id = new.user_id;
  if coalesce((prefs->>'push_enabled')::boolean, true) = false then return null; end if;
  if coalesce((prefs->'enabled'->>new.type)::boolean, true) = false then return null; end if;

  -- Employers go to the candidate; job seekers go to their alerts.
  if new.application_id is not null then
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

drop trigger if exists push_on_notification on public.notifications;
create trigger push_on_notification after insert on public.notifications
  for each row execute function public.push_on_notification();

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- After deploying the "push" Edge Function, run (with your own values):
--
--   insert into private.push_config (key, value) values
--     ('function_url',   'https://gkglfqsvxyemykpnjxik.supabase.co/functions/v1/push'),
--     ('webhook_secret', 'THE-SAME-SECRET-YOU-SET-AS-PUSH_WEBHOOK_SECRET')
--   on conflict (key) do update set value = excluded.value;
-- ---------------------------------------------------------------------------
