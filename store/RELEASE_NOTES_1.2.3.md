# Vocation SL 1.2.3 (build 16) — release notes

Includes everything in 1.2.0–1.2.2. Upload this bundle to Play instead of 1.2.1 or 1.2.2 if they haven't been uploaded yet.

## Google Play "What's new" (en-GB, under 500 characters)

```
What's new in 1.2
• Pick your interview time from the times an employer offers, and get a reminder the day before.
• Job alerts: e.g. "Accounting jobs in Bo", instantly, daily or weekly.
• See how long since you applied and how quickly the employer usually replies.
• Let employers find you and invite you to apply (you choose).
• Contact support inside the app.
• Smoother sign-up and sign-in for employers.
• Fixes and improvements.
```

## Fixed since 1.2.2
- **The confirmation link works in any browser or phone.**
  - It now carries a one-time code that the app checks itself. Before, the link only finished signing in on the browser used to sign up.
  - Email apps that check links (e.g. Outlook, Gmail) can no longer use it up first.
  - Employers land on "Set up your company", and job seekers on the jobs page.
  - **Needs the new "Confirm signup" email in Supabase.** It was given to the owner on 23 October 2026 and is copied below.
- **Signing in opens the account's own side.**
  - If the person doesn't touch the "Find a job / Hire talent" switch, an employer account opens the employer side.
  - An employer who confirmed but didn't set up their company goes straight to "Set up your company" after signing in with email and password.
  - Accounts that never picked a side still follow the switch.
- **Clearer messages:**
  - **Signing up with an email that already has an account** now says so. Before, Supabase silently kept the old password, so the new one then failed with "Invalid login credentials".
  - **Wrong email or password** now explains the options: Continue with Google, or Forgot password.
  - **Expired or already-used confirmation links** are explained on the sign-in screen.

## Supabase "Confirm signup" email (Authentication → Emails)
```html
<h2>Confirm your Vocation SL account</h2>
<p>Thanks for signing up. Tap the button below to confirm your email and continue.</p>
<p>
  <a href="{{ if eq (printf "%v" .Data.role) "employer" }}https://employers.vocationsl.com{{ else }}https://app.vocationsl.com{{ end }}/?token_hash={{ .TokenHash }}&type=email"
     style="display:inline-block;padding:12px 20px;background:#1E8E3E;color:#ffffff;text-decoration:none;border-radius:8px;font-weight:600">
    Confirm my email
  </a>
</p>
<p>If you didn't create this account, you can ignore this email.</p>
```

## Files
- Web app: live at https://app.vocationsl.com and https://employers.vocationsl.com (1.2.3, build 16), 23 October 2026
- APK: `release/vocation-sl-v1.2.3.apk`
- Play bundle: `release/play/vocation-sl-1.2.3.aab` (signed with the upload key, SHA-256 28:10:D7:…:F3:52)
