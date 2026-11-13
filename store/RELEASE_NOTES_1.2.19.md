# Vocation SL 1.2.19 (build 34), 14 November 2026

## What changed
- **"Did you apply?"** For jobs with an external link (website or email), signed-in job seekers are asked when they come back to the app after tapping apply (`openExternalApply` in `lib/features/jobs/job_details_screen.dart`). Answers: applied, not yet, no. Saved with `record_external_apply()` into `external_apply_answers` (one row per person per job, latest answer wins; RLS: people read only their own rows).
- **Employer stats.** The hiring report shows views, apply taps, "said they applied" (of how many answered), a views-to-applications funnel and "Yes, I applied" by day; also in the PDF. My Jobs shows "N applied · N taps". Count kept in `jobs.external_applied`, protected from employer edits by `jobs_protect_extras`.
- **Admin stats.** The overview shows total apply taps and "said they applied" (this week, total answers) from `admin_stats()`.
- Database: `supabase/external_apply_answers.sql` (applied 13 Nov 2026).

## Release
- Web: 14 Nov 2026.
- Android: release/play/vocation-sl-1.2.19.aab (user uploads).
- iOS: ios.yml build 34, submitted to App Store review.
