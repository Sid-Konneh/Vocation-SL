# Vocation SL 1.3.0 (build 35)

Database: `supabase/release_1_3.sql` (applied live 21 Nov 2026). Edge Function `employer-weekly` (deployed, JWT verification off).

## Employers
- **Quicker company setup.** Setup asks only for logo, name, industry, head office, contact email (prefilled from the sign-up email), phone and business address; website optional. About, size, year founded and referral code move to Company profile (About is optional there; if filled, at least 40 characters). A referral code from a referral link is still applied at sign-up; codes can also be added later in Company profile (`claim_referral`).
- **Extend or repost a job** (My jobs → Extend / Repost, or the button next to a deadline that is near or past). 1–4 weeks. `extend_job()` moves the deadline (from the current deadline, or from today if it has passed), reopens closed jobs (reviewed first if the company isn't approved; no second posting invoice; not re-emailed to job seekers) and creates a **draft** invoice for the extra weeks at `platform_settings.extension_price` (SLE 1,000 per week, excl. 15% GST) for an admin to issue. Employers who post free get a SLE 0 paid invoice. "Reopen" now appears only while the deadline is still ahead.
- **Post it for me.** My jobs has a button that opens WhatsApp (+232 73 512 413) or email (info@vocationsl.com) to send an advert.
- **Weekly hiring report email** (Mondays 08:00, cron `vsl-employer-weekly`): per job, views this week (from `job_view_snapshots`, first week shows totals), new and waiting applicants, taps on own apply links, and how many job seekers' profiles strongly fit the job (AI similarity ≥ 0.84). Jobs near or past their deadline get an Extend/Repost button. Unsubscribe: vocationsl.com/unsubscribe-weekly → `profiles.weekly_report = false`. Log: `employer_weekly_log`.

## Admin
- **Post a job for a company**: Employer verification → actions → "Post a job for this company" (approved companies). Opens the normal job editor for that company (PDF advert reading works). Needs RLS policy "moderators create jobs".
- **Analytics** (new section): job seekers (new, active, came back after day 1 / a week), sign-up-to-hire funnel, profile completeness, 12-week trend, job seekers vs live jobs by district, jobs by industry, live job health (days left, views, applied/taps, rate, waiting applicants, strong-fit job seekers, salary), applications (unopened 7+ days, median employer first reply), employers (no company yet, active, per company), notifications and email delivery, invoices and referrals. One RPC: `admin_analytics()`.
- Platform settings: "Price per extra week (extend or repost)".

## Fixes
- A job just posted could vanish from My jobs until the next refresh (a load started before the save overwrote it). `CacheFirstNotifier.build` now keeps local changes made while it loads, and job changes are written to the device cache.
