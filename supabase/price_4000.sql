-- 25 Nov 2026: price is SLE 4,000 per job for 4 weeks + 15% GST (applied live).
update public.platform_settings set value = '4000'::jsonb where key = 'posting_price';
alter table public.invoices alter column description set default 'Job listing on Vocation SL (4 weeks)';
