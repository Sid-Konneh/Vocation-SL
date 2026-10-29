-- Vocation SL — job adverts (run before deploying the release that adds them). Safe to re-run.
-- An employer can attach the job advert as a PDF or photo instead of typing
-- the full description. Adverts are public like the job itself and stored as
-- job-adverts/<user id>/<time>-advert.<ext>. Every job is still reviewed by an
-- admin, who sees the advert before approving.

alter table public.jobs add column if not exists advert_url text not null default '';

-- Only files from our own bucket, so an advert can't point anywhere else.
do $$ begin
  alter table public.jobs add constraint jobs_advert_url_ours
    check (advert_url = '' or advert_url ~ '^https://[^ ]+/storage/v1/object/public/job-adverts/[^ ]+$');
exception when duplicate_object then null; end $$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('job-adverts', 'job-adverts', true, 5242880, array['application/pdf', 'image/png', 'image/jpeg', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "job adverts are public" on storage.objects;
create policy "job adverts are public" on storage.objects for select
  using (bucket_id = 'job-adverts');

drop policy if exists "users upload own job adverts" on storage.objects;
create policy "users upload own job adverts" on storage.objects for insert to authenticated
  with check (bucket_id = 'job-adverts' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "users delete own job adverts" on storage.objects;
create policy "users delete own job adverts" on storage.objects for delete to authenticated
  using (bucket_id = 'job-adverts' and (storage.foldername(name))[1] = auth.uid()::text);

notify pgrst, 'reload schema';
