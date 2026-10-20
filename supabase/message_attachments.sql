-- Vocation SL — PDF attachments on messages (run before deploying 1.1.1). Safe to re-run.
-- Employers can send an applicant a PDF (offer letter, contract, interview
-- details) in the message thread, and applicants can send one back (e.g. a
-- signed offer letter). The file is stored in the sender's own folder in the
-- "documents" bucket (PDF only); the message row records its path. Anyone in
-- the thread — the applicant and the hiring company's team — can open it.

alter table public.application_messages add column if not exists attachment_path text;
alter table public.application_messages add column if not exists attachment_name text;

create or replace function public.application_messages_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r text := public.message_role(new.application_id);
begin
  if r is null then raise exception 'You are not part of this application.' using errcode = '42501'; end if;
  if public.is_suspended() then raise exception 'Your account is suspended.' using errcode = '42501'; end if;
  if r = 'candidate' and not exists (
       select 1 from public.application_messages m where m.application_id = new.application_id and m.sender_role = 'employer')
     and not exists (
       select 1 from public.applications a where a.id = new.application_id and coalesce(a.data->>'employer_message', '') <> '') then
    raise exception 'You can reply once the employer has messaged you.' using errcode = '42501';
  end if;

  -- An attachment must be a PDF the sender uploaded to their own folder, so
  -- nobody can share access to someone else's file by naming its path.
  if nullif(btrim(coalesce(new.attachment_path, '')), '') is null then
    new.attachment_path := null;
    new.attachment_name := null;
  else
    if split_part(new.attachment_path, '/', 1) <> auth.uid()::text
       or lower(new.attachment_path) not like '%.pdf'
       or new.attachment_path like '%..%' then
      raise exception 'That attachment can''t be sent.' using errcode = '42501';
    end if;
    new.attachment_name := left(coalesce(nullif(btrim(new.attachment_name), ''), 'Document.pdf'), 200);
    if btrim(coalesce(new.body, '')) = '' then
      new.body := 'Sent a document: ' || new.attachment_name;
    end if;
  end if;

  new.sender_role := r;
  new.sender_id := auth.uid();
  new.created_at := now();
  new.read_at := null;
  new.body := btrim(new.body);
  return new;
end $$;

-- Thread members (and admins who can read the thread) can open its attachments.
do $$
begin
  drop policy if exists "thread members read message attachments" on storage.objects;
  create policy "thread members read message attachments" on storage.objects for select to authenticated
    using (bucket_id = 'documents' and exists (
      select 1 from public.application_messages m
      where m.attachment_path = storage.objects.name
        and (public.message_role(m.application_id) is not null or public.admin_level() >= 1)));
exception when others then
  raise notice 'Storage policy skipped (%). Add it in Storage → Policies.', sqlerrm;
end $$;

notify pgrst, 'reload schema';
