# Vocation SL 1.0.8 (build 9) — release notes

Includes everything in 1.0.5–1.0.7.

## Google Play "What's new" (en-GB, under 500 characters)

```
What's new in 1.0.8
• Supporting documents: when an employer asks, attach up to 5 PDFs (certificates, ID and more) with your application.
• All documents are now PDF, so employers can open them on any phone or computer.
• Employers can share or copy a link to any live job.
• Switch between job seeker and employer with one account.
• Refer an employer and get SLE 50 by Mobile Money.
• Fixes and improvements.
```

## New since 1.0.7
- **Employers:** "Ask for supporting documents" switch on the job form, with a note saying which documents (e.g. certificates, ID). Candidate page lists and opens the attached PDFs.
- **Job seekers:** an optional "Documents" step after the cover letter, shown only when the job asks for documents; up to 5 PDFs, each up to 5 MB. The job page shows a "How to apply" list with the requested documents.
- **PDF only:** CVs, cover letters and supporting documents must be PDF (the app, the website text and the storage bucket all enforce it). Photos and logos are still images.
- **Share job links:** employers can Share or Copy the link of any live job from My jobs. Job seekers can apply from that link or from the job list in the app.
- **Fix:** the employer dashboard shows jobs and applicants straight after a company is created.

## Database (done, 15 October 2026)
- `supabase/supporting_documents.sql` — jobs.documents_requested and jobs.documents_note; documents bucket limited to PDF.

## Files
- Web app: live at https://app.vocationsl.com (1.0.8, build 9)
- APK: `release/vocation-sl-v1.0.8.apk` (89.8 MB)
- Play bundle: `release/play/vocation-sl-1.0.8.aab` (77.6 MB)

## Upload to Google Play
Closed testing (or production, once approved) → Create new release → upload `vocation-sl-1.0.8.aab` (version code 9) → paste "What's new" → Next → Save → Send for review.

## Note
Older app versions (1.0.7 and below) still offer DOC/DOCX uploads; those uploads are now refused by the server. Ask testers to update to 1.0.8.
