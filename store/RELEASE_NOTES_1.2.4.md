# Vocation SL 1.2.4 (build 17) — release notes

Includes everything in 1.2.0–1.2.3 (see the earlier RELEASE_NOTES_1.2.x files). Upload this bundle to Play instead of any earlier 1.2 bundle that hasn't been uploaded yet.

## Google Play "What's new" (en-GB, under 500 characters)

```
What's new in 1.2
• Pick your interview time from the times an employer offers, and get a reminder the day before.
• Job alerts: e.g. "Accounting jobs in Bo", instantly, daily or weekly.
• See how long since you applied and how quickly the employer usually replies.
• Let employers find you and invite you to apply (you choose).
• Contact support inside the app.
• Smoother sign-up and sign-in for employers.
• Simpler applications: upload a cover letter or skip.
• Fixes and improvements.
```

## Changed since 1.2.3
- **Cover letter step: Upload or Skip only.** The "Write" option and the "Start from a template" button are removed. Upload is selected first.
- **If someone taps Next without a file,** they see "Upload a cover letter, or choose Skip."
- **Cover letters written in earlier applications** still show to employers. Nothing already submitted changes.

## Still required from 1.2.3
- The new **"Confirm signup"** email in Supabase (Authentication → Emails). The wording is in `RELEASE_NOTES_1.2.3.md`. Without it, confirmation links only work in the browser used to sign up.

## Checks
- Code analysis: no issues.
- Tests: all 96 pass, including the apply flow with Upload/Skip.
- Play bundle signed with the upload key (SHA-256 28:10:D7:…:F3:52).

## Files
- Web app: live at https://app.vocationsl.com, https://employers.vocationsl.com and https://admin.vocationsl.com (1.2.4, build 17), 24 October 2026
- APK: `release/vocation-sl-v1.2.4.apk`
- Play bundle: `release/play/vocation-sl-1.2.4.aab`
