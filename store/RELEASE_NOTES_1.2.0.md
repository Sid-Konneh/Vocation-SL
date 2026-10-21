# Vocation SL 1.2.0 (build 13) — release notes

Includes everything in 1.1.1.

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

## Job seekers
- **Interview times:** when an employer offers times, the application shows **Choose your interview time**. Confirm one, and you'll be reminded about a day before. None suit you? Reply in Messages.
- **Job alerts:** Saved → Searches & alerts → **New job alert**. Pick a category, a district or town, and optional keywords. Choose Instantly, Daily (one notification each morning) or Weekly. Alerts made from a search work the same way.
- **Application tracker:** each open application shows how long ago you applied and how quickly that employer usually replies. The figure comes from their real reply times over the last 6 months, and is shown only once at least 3 applicants have had a reply.
- **Let employers find me** (Settings, off by default):
  - Approved employers can see your headline, skills, experience, education and languages, and invite you to apply.
  - Your phone, email and CV stay private until you apply.
- **Contact support** (Settings): send a question or report a fake job. Replies arrive in the app as a notification.

## Employers
- **Offer interview times** (candidate page): offer up to 3 times with a place and a note. The candidate picks one; you're told which, and both of you are reminded about a day before. **Set one time** still works for a single fixed time.
- **Offer letter** (candidate page):
  - Fill in the job title, salary, start date, place of work, probation and other terms, and who signs.
  - The app makes a PDF letter with an acceptance section, shows a preview, and sends it in Messages.
  - You can then move the candidate to Offer.
  - The form reminds employers to check the terms against their own policies and Sierra Leone employment law.
- **Find talent** (new menu item):
  - Search job seekers who chose to be found, by skill, location or field.
  - Invite them to a live job with a short note.
  - Up to 30 invitations a day per company, and one invitation per person per job.
  - Available once the company is approved.
- **Hiring report** (My jobs → ⋮ → Hiring report):
  - Views; applications and applications per 100 views; how many reached each stage; and where applicants found the job.
  - Typical reply time, time to first hire, applications by day, and talent search invitations.
  - **Save PDF** for donor or management reports.
- **Help & support** in the menu.

## Admin
- **Support inbox:** read and reply to requests (moderators and up). Close or reopen them. Admins get a notification for each new request.
- **Weekly digest:**
  - The last 7 days, compared with the week before: new users and employers; jobs that went live; applications; revenue received; unpaid and overdue invoices.
  - Also: jobs with scam warning signs, open reports, support requests waiting and referral rewards to pay.
  - Owners and admins get it as a notification every Monday at 07:00. **No email is sent.**

## Notes
- "Where applicants found the job" is recorded from 1.2 onwards. Older applications show as "Not recorded".
- Job alerts and reminders are app and push notifications only. SMS is not included; it would need an SMS provider and a budget per message.
- The scam warning count in the digest is a keyword check. A flagged job may be genuine.

## Database (run BEFORE deploying)
- `supabase/release_1_2.sql`:
  - New tables: interview_proposals, interview_reminders, talent_invites, support_tickets, support_messages.
  - New columns: job_alerts.last_sent_at and profiles.discoverable.
  - Functions and access rules.
  - The alert trigger.
  - Push routes for the new alert types.
  - pg_cron schedules: reminders hourly at :15, alert digests daily at 08:00, admin digest Mondays at 07:00.
- If the SQL editor shows **"Scheduling skipped"**, enable **pg_cron** (Database → Extensions) and run section 9 again.

## Files
- Web app: https://app.vocationsl.com (deploy after the SQL is run)
- APK: `release/vocation-sl-v1.2.0.apk`
- Play bundle: `release/play/vocation-sl-1.2.0.aab`
