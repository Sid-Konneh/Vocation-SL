# Vocation SL 1.0.6 (build 7) — release notes

Includes everything in 1.0.5 (see RELEASE_NOTES_1.0.5.md), which was not uploaded to Play.

## Google Play "What's new" (en-GB, under 500 characters)

```
What's new in 1.0.6
• Refer an employer: share your code with companies that are hiring and add your Mobile Money number for rewards.
• Shared job links now open the job directly in the app or on the web.
• Employers add their logo at sign-up and go straight to the dashboard, also after switching from job seeker.
• Profile photos and logos are resized automatically, so they upload quickly on mobile data.
• Fixes and improvements.
```

## New since 1.0.5
- Referrers add their Orange Money or Africell Money number and account name on Refer an employer. Only they and admins can see it; admins see it (with a copy button) on each referral in Admin → Referrals.
- Fixed: after switching from job seeker to employer, creating the company now opens the dashboard (it stayed on the setup screen). The new company is also kept on the device, so reopening the app opens the dashboard.
- Reward text set by the owner: "Get SLE 50 by Mobile Money for each company you refer, once its first job goes live on Vocation SL."
- App links verified with Google using the Play app signing key, so shared links open the Play-installed app.

## Database (done, 10 October 2026)
- `supabase/referrals.sql` — logo storage policy, referral tables, functions and triggers
- `supabase/referral_payout.sql` — Mobile Money details for referrers

## Files
- Web app: live at https://app.vocationsl.com (version 1.0.6, build 7)
- APK: `release/vocation-sl-v1.0.6.apk` (89.8 MB)
- Play bundle: `release/play/vocation-sl-1.0.6.aab` (77.6 MB)

## Upload to Google Play (closed testing)
1. Play Console → Vocation SL → Test and release → Testing → Closed testing → your track → **Create new release**.
2. Upload `vocation-sl-1.0.6.aab` (version name 1.0.6, version code 7).
3. Paste the "What's new" text above.
4. **Next → Save → Send for review**.

## Paying a referral reward
1. Admin → Referrals → **To reward** (companies whose first job is live).
2. Send SLE 50 to the "Pay to" Mobile Money number on the card; keep the transaction ID.
3. **⋮ → Mark as rewarded** with a note, e.g. "SLE 50 Orange Money sent 12 Oct, ref 123456". The referrer gets an alert.
