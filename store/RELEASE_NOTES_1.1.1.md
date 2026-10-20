# Vocation SL 1.1.1 (build 12) — release notes

Includes everything in 1.1.0.

## Google Play "What's new" (en-GB, under 500 characters)

```
What's new in 1.1.1
• Employers can send you documents in messages, such as an offer letter or contract. Tap the file to open it.
• You can reply with a PDF too, for example your signed offer letter.
• Fixes and improvements.
```

## New since 1.1.0
- **Employers, candidate page → Messages:** a paperclip button attaches a PDF (5 MB max) to a message. The message can include text or just the file. The candidate gets the usual message notification.
- **Employers, Candidates → select several → Move and message:** the dialog has a new **Attach a PDF (e.g. offer letter)** option. It uploads the file once and sends the same file to every selected candidate with the stage message. For personal offer letters, send each one from that candidate's page.
- **Job seekers, application → Messages:** attachments show as a PDF card that opens in the in-app viewer. Once the employer has written, job seekers can reply with a PDF as well.
- **Security:**
  - Files are stored in the sender's own folder in the private `documents` bucket, which accepts PDFs only.
  - Only people in that conversation can open a file: the applicant, the hiring company's team, and admins.
  - The database rejects any attachment that isn't the sender's own PDF.

## Database (run BEFORE deploying)
- `supabase/message_attachments.sql`:
  - Adds `attachment_path` and `attachment_name` to `application_messages`.
  - Updates the message guard trigger.
  - Adds the storage read policy for thread members.

## Files
- Web app: https://app.vocationsl.com (deploy after the SQL is run)
- APK: `release/vocation-sl-v1.1.1.apk`
- Play bundle: `release/play/vocation-sl-1.1.1.aab`
