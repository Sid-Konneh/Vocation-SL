# Vocation SL 1.2.1 (build 14) — release notes

Includes everything in 1.2.0 (see RELEASE_NOTES_1.2.0.md). Upload this bundle to Play instead of 1.2.0, which was never finished.

## Google Play "What's new" (en-GB, under 500 characters)

```
What's new in 1.2
• Pick your interview time from the times an employer offers, and get a reminder the day before.
• Job alerts: e.g. "Accounting jobs in Bo", instantly, daily or weekly.
• See how long since you applied and how quickly the employer usually replies.
• Let employers find you and invite you to apply (you choose).
• Contact support inside the app.
• Fixes and improvements.
```

## New since 1.2.0
- **Find talent → full profile:**
  - Employers tap a person, or **View full profile**, to see everything they share.
  - That includes photo, headline, about, all experience with descriptions, education, certifications, skills, languages, the jobs they're looking for, and LinkedIn and portfolio links.
  - **Invite to apply** is on the profile page too.
- **Privacy is unchanged:** phone, email and CV stay hidden until the person applies, as the "Let employers find me" switch promises.
- **Fix:** job seekers whose account also belongs to a company now appear in talent search. Only the employer's own team is hidden.

## Database (done, 21 October 2026)
- `talent_profile(p_user)` function.
- Updated `search_talent`.
- Both are in `supabase/release_1_2.sql`.

## Files
- Web app: live at https://app.vocationsl.com (1.2.1, build 14)
- APK: `release/vocation-sl-v1.2.1.apk`
- Play bundle: `release/play/vocation-sl-1.2.1.aab`
