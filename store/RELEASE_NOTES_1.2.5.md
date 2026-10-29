# Vocation SL 1.2.5 (build 18) — release notes

Includes everything in 1.2.0–1.2.4 (see the earlier RELEASE_NOTES_1.2.x files). Upload this bundle to Play instead of any earlier 1.2 bundle that hasn't been uploaded yet.

## Google Play "What's new" (en-GB, under 500 characters)

```
What's new in 1.2
• Pick your interview time from the times an employer offers, and get a reminder the day before.
• Job alerts: e.g. "Accounting jobs in Bo", instantly, daily or weekly.
• See how long since you applied and how quickly the employer usually replies.
• Let employers find you and invite you to apply (you choose).
• Contact support inside the app.
• A quick guide to help new users get started.
• Simpler applications and smoother employer sign-up.
```

## New since 1.2.4: "How Vocation SL works" guide
**Job seekers** see 5 short screens the first time they open the app:
1. Welcome
2. Complete your profile
3. Search and save jobs
4. Apply and track
5. Stay safe: never pay a fee, and report suspicious jobs

It ends with **Complete my profile** or **Browse jobs**.

**Employers** see 5 screens right after setting up their company:
1. Welcome
2. Get verified
3. Post a job
4. Review candidates
5. Find talent

It ends with **Post my first job** or **Go to dashboard**. The confirmation link still goes straight to "Set up your company".

**Details:**
- **Every screen has Skip**, and people can swipe between screens.
- **Automatic only for accounts created from 24 October 2026.** Existing users don't see it pop up.
- **Anyone can reopen it:** job seekers in **Settings → How Vocation SL works**, employers under **How it works** in the employer menu.
- **It shows once per account on each device.** A new user who signs in on another phone may see it once more.
- **Every step describes a feature that really exists**, e.g. "Report this job" on the job page.

## Still required from 1.2.3
- The new **"Confirm signup"** email in Supabase (Authentication → Emails). The wording is in `RELEASE_NOTES_1.2.3.md`.

## Checks
- Code analysis: no issues.
- Tests: all 99 pass, including 3 new tests for the guide.
- Play bundle signed with the upload key (SHA-256 28:10:D7:…:F3:52).
- No database changes.

## Files
- Web app: live at https://app.vocationsl.com, https://employers.vocationsl.com and https://admin.vocationsl.com (1.2.5, build 18), 24 October 2026
- APK: `release/vocation-sl-v1.2.5.apk`
- Play bundle: `release/play/vocation-sl-1.2.5.aab`
