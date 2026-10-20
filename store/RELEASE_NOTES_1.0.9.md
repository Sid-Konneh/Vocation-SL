# Vocation SL 1.0.9 (build 10) — release notes

Includes everything in 1.0.5–1.0.8.

## Google Play "What's new" (en-GB, under 500 characters)

```
What's new in 1.0.9
• Some employers now take applications on their own website: tap "Apply on website" to go straight there.
• Supporting documents: attach up to 5 PDFs when an employer asks.
• All documents are PDF, so employers can open them anywhere.
• Employers can share a link to any live job.
• Refer an employer and get SLE 50 by Mobile Money.
• Fixes and improvements.
```

## New since 1.0.8
- **Employers:** "How candidates apply" on the job form: **On Vocation SL** (applications, CVs and documents arrive in Candidates) or **On our website** (enter an application link; candidates are sent there).
- **Job seekers:** jobs with a link show **"Apply on website"**. Before leaving the app they see the website's name and a reminder that genuine employers never ask for money.
- **Admins:** the job review panel shows the external link in orange, so it can be checked before the job is approved.
- Links are checked to be real web addresses (https:// is added if missing); the database also rejects anything that isn't a web address.

## Database (done, 15 October 2026)
- `supabase/external_apply_link.sql` — jobs.apply_url with a web-address check.

## Files
- Web app: live at https://app.vocationsl.com (1.0.9, build 10)
- APK: `release/vocation-sl-v1.0.9.apk` (89.8 MB)
- Play bundle: `release/play/vocation-sl-1.0.9.aab` (77.7 MB)
