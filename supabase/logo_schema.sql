-- Vocation SL — company logos (run after employer_schema.sql). Safe to re-run.
-- Logos are public images; only members of a company can upload or replace
-- files in that company's folder (logos/<company_id>/...).

alter table public.companies add column if not exists logo_url text;

do $$
begin
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('logos', 'logos', true, 2097152, array['image/png', 'image/jpeg', 'image/webp'])
  on conflict (id) do update
    set public = true, file_size_limit = 2097152, allowed_mime_types = array['image/png', 'image/jpeg', 'image/webp'];

  drop policy if exists "company logos are public" on storage.objects;
  create policy "company logos are public" on storage.objects for select
    using (bucket_id = 'logos');

  drop policy if exists "members upload company logos" on storage.objects;
  create policy "members upload company logos" on storage.objects for insert to authenticated
    with check (bucket_id = 'logos' and public.is_company_member((storage.foldername(name))[1]));

  drop policy if exists "members replace company logos" on storage.objects;
  create policy "members replace company logos" on storage.objects for update to authenticated
    using (bucket_id = 'logos' and public.is_company_member((storage.foldername(name))[1]))
    with check (bucket_id = 'logos' and public.is_company_member((storage.foldername(name))[1]));

  drop policy if exists "members delete company logos" on storage.objects;
  create policy "members delete company logos" on storage.objects for delete to authenticated
    using (bucket_id = 'logos' and public.is_company_member((storage.foldername(name))[1]));
exception when others then
  raise notice 'Logo storage setup skipped (%). Create a public "logos" bucket in Storage.', sqlerrm;
end $$;

notify pgrst, 'reload schema';
