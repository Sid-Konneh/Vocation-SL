-- Public contact email is now info@vocationsl.com (2 Nov 2026).
-- vocationxsl@gmail.com stays as the admin sign-in account; only text shown to users changes.

-- Support email shown in the app (suspended screen, help, etc.)
insert into public.platform_settings (key, value) values ('support_email', '"info@vocationsl.com"')
on conflict (key) do update set value = excluded.value, updated_at = now();

-- In-app Help, Terms and Privacy pages
update public.site_pages
   set body = replace(body, 'vocationxsl@gmail.com', 'info@vocationsl.com'), updated_at = now()
 where body like '%vocationxsl@gmail.com%';

-- Active announcements
update public.announcements
   set body = replace(body, 'vocationxsl@gmail.com', 'info@vocationsl.com')
 where body like '%vocationxsl@gmail.com%';

-- Check: every count should be 0
select 'site_pages' as tbl, count(*) from public.site_pages where body like '%vocationxsl@gmail.com%'
union all select 'announcements', count(*) from public.announcements where body like '%vocationxsl@gmail.com%'
union all select 'support_email', count(*) from public.platform_settings where key = 'support_email' and value::text like '%gmail%';
