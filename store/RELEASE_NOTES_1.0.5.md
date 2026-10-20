# Vocation SL 1.0.5 (build 6) — release notes

## Google Play "What's new" (en-GB, under 500 characters)

```
What's new in 1.0.5
• Refer an employer: share your code with companies that are hiring. Their sign-up and every job they post count as your referral.
• Shared job links now open the job directly in the app or on the web.
• Employers can add their company logo while signing up and go straight to their dashboard.
• Profile photos and logos are resized automatically, so they upload quickly on mobile data.
• Fixes and improvements.
```

## What changed

**Employers**
- Company logo upload at sign-up fixed (it failed with "new row violates row-level security policy").
- The logo is uploaded before the dashboard opens; the employer sees a welcome message, or a clear note if something didn't save.
- Optional "Referral code" field on the company sign-up form, filled in automatically from a referral link.

**Job seekers**
- New "Refer an employer" screen (Profile, and the sidebar on wide screens): personal code (e.g. VSL-7KQ2M), copy/share link, totals, each referred company with its progress and the jobs it has posted, and "How it works".
- Alerts when a referred company signs up, is approved, posts a job, and when a referral is rewarded.
- Profile photos are resized before saving (large phone photos now work).

**Sharing**
- "Share job" now includes a link: https://app.vocationsl.com/job/<id>.
- The link opens the job in the Android app when installed (app links), otherwise in the web app. If the person isn't signed in, the job opens straight after sign-in.

**Admins**
- New Admin → Referrals page: all referrals, referrer name/email, code, company, every job it posted, filters and search, "Mark as rewarded" / "Not eligible" with a note, and the reward text shown to job seekers (Admin level and up).

## Database (done)
`supabase/referrals.sql` was run on 10 October 2026. It adds the logos storage policy (users upload to their own folder), referral tables, functions and triggers.

## Files
- Web app: deployed to https://app.vocationsl.com (also employers. and admin.)
- APK: `release/vocation-sl-v1.0.5.apk` (for testing / sharing directly)
- Play bundle: `release/play/vocation-sl-1.0.5.aab`

## Upload to Google Play (closed testing)
1. Play Console → Vocation SL → Test and release → Testing → Closed testing → your track → **Create new release**.
2. Upload `vocation-sl-1.0.5.aab`. Version name 1.0.5, version code 6.
3. Paste the "What's new" text above into release notes.
4. **Next → Save → Send for review** (or roll out to the track).
5. Testers get the update through Google Play. This doesn't restart the 14-day testing count.

## App links (one-time, recommended)
For shared links to open the Play-installed app directly, add Google's app signing key fingerprint:
1. Play Console → Test and release → **App integrity** → App signing → copy the **SHA-256 certificate fingerprint** under "App signing key certificate".
2. Send it to Claude; it gets added to `web/.well-known/assetlinks.json` and the web app is redeployed.
Until then, the links still work: they open the job in the browser (web app).
