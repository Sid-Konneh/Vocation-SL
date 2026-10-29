# Vocation SL 1.2.2 (build 15) — release notes

Includes everything in 1.2.0 and 1.2.1 (see RELEASE_NOTES_1.2.0.md and RELEASE_NOTES_1.2.1.md). Upload this bundle to Play instead of 1.2.1 if 1.2.1 hasn't been uploaded yet.

## Google Play "What's new" (en-GB, under 500 characters)

```
What's new in 1.2
• Pick your interview time from the times an employer offers, and get a reminder the day before.
• Job alerts: e.g. "Accounting jobs in Bo", instantly, daily or weekly.
• See how long since you applied and how quickly the employer usually replies.
• Let employers find you and invite you to apply (you choose).
• Contact support inside the app.
• Faster setup for new employers after confirming their email.
• Fixes and improvements.
```

## Fixed since 1.2.1
**New employers now go straight to "Set up your company" after tapping the email confirmation link.** Before, they waited, sometimes saw the sign-in screen for a moment, then saw a grey dashboard-shaped placeholder before company setup appeared. It looked as if setup had been skipped.
- **"Hire talent" is saved on the account at sign-up.** The confirmation link opens the employer side even in a different browser or on another phone. Before, the choice was only remembered in the browser used to sign up.
- **No flash of the sign-in screen:** the app waits up to 10 seconds for the confirmation link to finish signing the person in.
- **Faster:** the app checks whether the account has a company while the logo animation plays.
- **Clearer while loading:** "Getting your employer account ready…" replaces the dashboard-shaped placeholder.

## Not affected
- Existing accounts: anyone who already confirmed their email isn't changed. Employers who ended up on the job seeker side can switch to employer from the menu.
- No database changes in this release.

## Known limit
If the confirmation link is opened in a different browser from the one used to sign up, the person may be asked to sign in once. This is a Supabase security rule. After signing in, they go to the employer side.

## Files
- Web app: live at https://app.vocationsl.com, https://employers.vocationsl.com and https://admin.vocationsl.com (1.2.2, build 15), 23 October 2026
- APK: `release/vocation-sl-v1.2.2.apk`
- Play bundle: `release/play/vocation-sl-1.2.2.aab` (signed with the upload key, SHA-256 28:10:D7:…:F3:52)
