-- Lets a job's apply link be an email address (mailto:) as well as a website,
-- for employers who take applications by email. The app opens either one.
alter table public.jobs drop constraint if exists jobs_apply_url_web;
alter table public.jobs add constraint jobs_apply_url_web
  check (apply_url = ''
         or apply_url ~* '^https?://[^ ]+\.[^ ]+'
         or apply_url ~* '^mailto:[^@ ]+@[^@ ]+\.[^@ ]+');

-- App versions up to 1.2.13 turn an email typed as the apply link into
-- "https://hr@company.org", which opens a website. Save those (and bare
-- addresses) as mailto: links so the apply button opens an email instead.
create or replace function public.jobs_apply_email()
returns trigger language plpgsql as $$
declare
  addr text;
begin
  addr := substring(trim(new.apply_url) from '^(?:https?://)?([^/?#:@\s]+@[^/?#:@\s]+\.[^/?#:@\s]+)/?$');
  if addr is not null then new.apply_url := 'mailto:' || addr; end if;
  return new;
end $$;

drop trigger if exists jobs_apply_email on public.jobs;
create trigger jobs_apply_email before insert or update of apply_url on public.jobs
  for each row execute function public.jobs_apply_email();

-- Fix jobs already saved that way.
update public.jobs set apply_url = 'mailto:' || substring(apply_url from '^https?://([^/?#:@\s]+@[^/?#:@\s]+\.[^/?#:@\s]+)/?$')
where apply_url ~* '^https?://[^/?#:@\s]+@[^/?#:@\s]+\.[^/?#:@\s]+/?$';
