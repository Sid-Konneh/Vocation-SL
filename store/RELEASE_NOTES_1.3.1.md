# Vocation SL 1.3.1 (build 36)

Database: `supabase/job_digest.sql` (applied live 21 Nov 2026).

## Job seekers
- Job page shows "Be the first to apply" / "Be an early applicant: N people have applied" / "N people have applied" for jobs applied to in the app (real count). Jobs applied to on the employer's site or by email show "New: be one of the first to apply" for 3 days and no count (the old "0 applicants" line is gone for them). `lib/models/job_signals.dart`.
- "Responsive employer · Usually replies in about N days" on jobs from employers with at least 3 replies, 60%+ of applicants answered and a median first reply within 7 days (existing `employer_reply_speed`, last 6 months). Tooltip shows the counts.
- Job alert emails are a twice-weekly round-up (Mon and Thu 07:00, cron `vsl-job-digest` → `queue_job_digest(7)`), most recently active people first; about one email per person a week within Hostinger's ~100/day.

## Admin
- **Listed jobs (leads)**: vacancies the team listed for other employers (Vocation SL company, "Role (Employer)" titles), grouped by employer with views, apply taps and "said they applied", plus a ready message (Copy / Email HR / WhatsApp) inviting them to post directly. `lib/admin/features/listed_jobs.dart`.
