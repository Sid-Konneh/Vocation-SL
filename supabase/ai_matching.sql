-- Vocation SL — AI job matching pilot (8 Nov 2026). Safe to re-run.
--
-- An AI text model (gte-small, run inside the Supabase Edge Function
-- "ai-match") turns each published job and each job seeker's profile into a
-- 384-number "embedding" that captures its meaning. Similar meaning = similar
-- numbers, so "lab tech" is close to "Laboratory Technician".
--
--   * ai_embeddings: one row per job / profile. Only the server can read it.
--   * Profiles: headline, about, skills, past job titles and descriptions,
--     studies and preferred job titles. Never name, email, phone, photo,
--     gender or age.
--   * pg_cron runs kick_ai_embed() every minute; it calls the function only
--     when a job or profile is new or changed since its embedding was made.
--   * ai_job_matches(): the signed-in job seeker's similarity to each open job.
--   * ai_applicant_matches(): similarity of each applicant to the job they
--     applied for, for the employer's own jobs only.

create extension if not exists vector with schema extensions;

create table if not exists public.ai_embeddings (
  kind text not null check (kind in ('job', 'profile')),
  ref_id text not null,
  embedding extensions.vector(384),          -- null when there is not enough text yet
  src_updated_at timestamptz not null,       -- the job/profile version it was made from
  updated_at timestamptz not null default now(),
  primary key (kind, ref_id)
);
alter table public.ai_embeddings enable row level security;  -- no policies: server only
revoke all on public.ai_embeddings from anon, authenticated;

-- Jobs and profiles that need a (new) embedding.
create or replace function public.ai_embed_todo(max_rows int default 20)
returns table (kind text, ref_id text)
language sql stable security definer set search_path = public as $$
  (select 'job'::text, j.id
     from public.jobs j
     left join public.ai_embeddings e on e.kind = 'job' and e.ref_id = j.id
    where j.status = 'published'
      and (e.ref_id is null or coalesce(j.updated_at, j.posted_at) > e.src_updated_at)
    limit max_rows)
  union all
  (select 'profile'::text, p.id::text
     from public.profiles p
     left join public.ai_embeddings e on e.kind = 'profile' and e.ref_id = p.id::text
    where p.role is distinct from 'employer'
      and coalesce(p.suspended, false) = false
      and (e.ref_id is null or coalesce(p.updated_at, p.created_at) > e.src_updated_at)
    order by p.updated_at desc nulls last
    limit max_rows);
$$;
revoke all on function public.ai_embed_todo(int) from public, anon, authenticated;
grant execute on function public.ai_embed_todo(int) to service_role;

-- Removes embeddings of deleted, suspended or employer profiles and of jobs
-- that are no longer published.
create or replace function public.ai_embed_cleanup() returns void
language sql security definer set search_path = public as $$
  delete from public.ai_embeddings e
   where (e.kind = 'profile' and not exists (
            select 1 from public.profiles p
             where p.id::text = e.ref_id and p.role is distinct from 'employer' and coalesce(p.suspended, false) = false))
      or (e.kind = 'job' and not exists (
            select 1 from public.jobs j where j.id = e.ref_id and j.status = 'published'));
$$;
revoke all on function public.ai_embed_cleanup() from public, anon, authenticated;

-- Saves one embedding (called by the Edge Function with the service role).
create or replace function public.ai_embed_save(p_kind text, p_ref_id text, p_embedding text, p_src timestamptz)
returns void language sql security definer set search_path = public, extensions as $$
  insert into public.ai_embeddings (kind, ref_id, embedding, src_updated_at, updated_at)
  values (p_kind, p_ref_id, case when p_embedding is null then null else p_embedding::extensions.vector end, p_src, now())
  on conflict (kind, ref_id) do update
    set embedding = excluded.embedding, src_updated_at = excluded.src_updated_at, updated_at = now();
$$;
revoke all on function public.ai_embed_save(text, text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.ai_embed_save(text, text, text, timestamptz) to service_role;

-- The signed-in job seeker's AI similarity (0–1) to each open job.
create or replace function public.ai_job_matches()
returns table (job_id text, similarity real)
language sql stable security definer set search_path = public, extensions as $$
  select j.ref_id, (1 - (j.embedding <=> p.embedding))::real
    from public.ai_embeddings p
    join public.ai_embeddings j on j.kind = 'job' and j.embedding is not null
    join public.jobs jb on jb.id = j.ref_id and jb.status = 'published'
                       and (jb.deadline is null or jb.deadline > now())
   where p.kind = 'profile' and p.ref_id = auth.uid()::text and p.embedding is not null;
$$;
revoke all on function public.ai_job_matches() from public, anon;
grant execute on function public.ai_job_matches() to authenticated;

-- For an employer: each applicant's AI similarity to the job they applied
-- for, on the employer's own company jobs only.
create or replace function public.ai_applicant_matches()
returns table (application_id text, similarity real)
language sql stable security definer set search_path = public, extensions as $$
  select a.id, (1 - (pe.embedding <=> je.embedding))::real
    from public.applications a
    join public.jobs jb on jb.id = a.job_id
    join public.company_members m on m.company_id = jb.company_id and m.user_id = auth.uid()
    join public.ai_embeddings je on je.kind = 'job' and je.ref_id = a.job_id and je.embedding is not null
    join public.ai_embeddings pe on pe.kind = 'profile' and pe.ref_id = a.user_id::text and pe.embedding is not null;
$$;
revoke all on function public.ai_applicant_matches() from public, anon;
grant execute on function public.ai_applicant_matches() to authenticated;

-- Calls the Edge Function when something needs an embedding.
create or replace function public.kick_ai_embed() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  fn_url text;
  secret text;
begin
  perform public.ai_embed_cleanup();
  if not exists (select 1 from public.ai_embed_todo(1)) then
    return;
  end if;
  select value into fn_url from private.push_config where key = 'ai_match_url';
  select value into secret from private.push_config where key = 'webhook_secret';
  if fn_url is null or secret is null then return; end if;
  perform net.http_post(
    url := fn_url,
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', secret),
    timeout_milliseconds := 120000
  );
end $$;
revoke all on function public.kick_ai_embed() from public, anon, authenticated;

insert into private.push_config (key, value)
values ('ai_match_url', 'https://gkglfqsvxyemykpnjxik.supabase.co/functions/v1/ai-match')
on conflict (key) do update set value = excluded.value;

do $$
begin
  perform cron.unschedule('vsl-ai-embed') where exists (select 1 from cron.job where jobname = 'vsl-ai-embed');
  perform cron.schedule('vsl-ai-embed', '* * * * *', 'select public.kick_ai_embed()');
end $$;

notify pgrst, 'reload schema';
