# Vocation SL 1.0.7 (build 8) — release notes

Includes everything in 1.0.5 and 1.0.6 (neither was uploaded to Play).

## Google Play "What's new" (en-GB, under 500 characters)

```
What's new in 1.0.7
• Switch between job seeker and employer with one account: set up your company once, then go straight to your dashboard.
• Refer an employer: share your code with companies that are hiring and get SLE 50 by Mobile Money when their first job goes live.
• Shared job links open the job directly in the app or on the web.
• Faster photo and logo uploads.
• Fixes and improvements.
```

## New since 1.0.6
- One account, one company: switching to employer (or signing in through Hire talent) with an account that has a company always opens the dashboard; the setup form appears only once.
- A second company can't be created for the same account (app and database).
- Fixed a race where tapping "Switch to employer" right after signing in flipped back to job seeker.
- If the company can't be checked (no internet), a "Try again" message is shown instead of the setup form.
- Featured job cards adapt to larger phone text sizes.
- New automated test covering job seeker → switch to employer → set up company → dashboard → switch back and forth.

## Database (done, 10 October 2026)
- `supabase/one_company_per_account.sql` — one company per account
- `supabase/fix_company_owner.sql` — companies created by admin accounts now get their owner; vocationxsl@gmail.com repaired (one Vocation SL company kept, duplicates removed)

## Files
- Web app: live at https://app.vocationsl.com (1.0.7, build 8)
- APK: `release/vocation-sl-v1.0.7.apk` (89.8 MB)
- Play bundle: `release/play/vocation-sl-1.0.7.aab` (77.6 MB)

## Upload to Google Play (closed testing)
1. Play Console → Vocation SL → Test and release → Testing → Closed testing → your track → **Create new release**.
2. Upload `vocation-sl-1.0.7.aab` (version name 1.0.7, version code 8).
3. Paste the "What's new" text above.
4. **Next → Save → Send for review**.
