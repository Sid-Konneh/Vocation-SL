# Vocation SL 1.2.15 (build 30)

## What changed
- **Job matching (rule based, no AI).** `JobMatch` scores each job on the profile's town (same area: Freetown = Western Area Urban/Rural/Waterloo, Koidu = Kono, Makeni = Bombali, Lunsar = Port Loko), words shared by the job title/skills and the headline, past job titles, studies, skills and preferred titles, plus preferred job type, industry, work mode and salary. Home "Recommended for you" shows the top 5; job pages show "A good match for you" with the reasons.
- **Quick filters** on Home: "Jobs in <your town>" and Full-time / Contract / Part-time / Internship / Volunteer. Location filters include the same area.
- **PDF advert details (no AI).** When an employer uploads a PDF advert, clearly labelled details are copied word for word into fields left empty: title, location, job type, deadline, full text as description, responsibilities, requirements, and the apply email/link. What the employer typed always stays. Photos and scanned PDFs can't be read. Tests: `test/advert_match_test.dart`.
- **Advert file names.** Adverts are stored as `<user>/<time>/<original name>`, and the viewer and download use that name.
- **Apply by email.** A job's apply link can be an email address. The job page then shows "Apply by email"; tapping it opens a new email to the employer, with the job title as the subject unless the employer set one. Website links still show "Apply on website".
- Employers: "How candidates apply" now says "Website or email" and accepts either.
- Links saved by older app versions as "https://hr@company.org" are read as email addresses.
- **Job emails.** Notification settings has a "Job emails" switch (replaces "Weekly email summary", which never sent anything). It is stored in `profiles.job_emails`, so older app versions can't reset it.
- **Back to all jobs.** A job opened from an email, shared link or QR code is the first page, so it now shows a back button (and the phone's back button) that goes to the jobs list instead of closing the app.
- Support email in the app is info@vocationsl.com (vocationxsl@gmail.com stays the admin sign-in only).

## Database (already run, 4 Nov 2026)
`supabase/apply_by_email.sql`: allows mailto: apply links, and the trigger `jobs_apply_email` saves typed emails as mailto: links, so the button already opens an email in 1.2.13.

`supabase/job_emails.sql` (6 Nov 2026) + Edge Function `job-emails`: every new live job is emailed to all non-employer accounts from info@vocationsl.com (Hostinger), max 800 emails per 24 h, unsubscribe at vocationsl.com/unsubscribe. Needs the `SMTP_PASSWORD` secret.

## Release plan
- Web: live as 1.2.15 since 6 Nov 2026 (apply by email + Job emails switch).
- Android: release/play/vocation-sl-1.2.15.aab, uploaded after Apple approves 1.2.13.
- iOS: build 1.2.15 (30) with the GitHub Actions workflow after Apple approves 1.2.13.

## Checks
- `test/referrals_test.dart`: website and email apply links.
