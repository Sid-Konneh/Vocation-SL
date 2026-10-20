-- Vocation SL — supporting documents on applications (run before deploying 1.0.8). Safe to re-run.
-- Employers can ask applicants for supporting documents; applicants attach up
-- to 5 PDFs. The files are stored in the applicant's own folder in the
-- "documents" bucket, so the existing storage policies already let the
-- employer of that job (and admins) open them. The list of files is saved
-- inside the application's data.

alter table public.jobs add column if not exists documents_requested boolean not null default false;
alter table public.jobs add column if not exists documents_note text not null default '';

-- Documents are PDF only from 1.0.8. Limit the storage bucket to PDFs as well
-- (existing DOC/DOCX files stay readable).
update storage.buckets
   set allowed_mime_types = array['application/pdf']
 where id = 'documents';

notify pgrst, 'reload schema';
