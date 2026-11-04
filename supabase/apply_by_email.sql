-- Lets a job's apply link be an email address (mailto:) as well as a website,
-- for employers who take applications by email. The app opens either one.
alter table public.jobs drop constraint if exists jobs_apply_url_web;
alter table public.jobs add constraint jobs_apply_url_web
  check (apply_url = ''
         or apply_url ~* '^https?://[^ ]+\.[^ ]+'
         or apply_url ~* '^mailto:[^@ ]+@[^@ ]+\.[^@ ]+');
