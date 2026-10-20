-- Vocation SL — external application links (run before deploying the release that adds them). Safe to re-run.
-- An employer can send candidates to its own website to apply. Every job is
-- still reviewed by an admin, who sees the link before approving.

alter table public.jobs add column if not exists apply_url text not null default '';

do $$ begin
  alter table public.jobs add constraint jobs_apply_url_web
    check (apply_url = '' or apply_url ~* '^https?://[^ ]+\.[^ ]+');
exception when duplicate_object then null; end $$;

notify pgrst, 'reload schema';
