# Vocation SL 1.2.17 (build 32), 9 November 2026

## What changed
- **Team invites.** A company owner can add a colleague who has no Vocation SL account. `supabase/team_invites.sql` saves the invite (`team_invites`, with a private token) and the Edge Function `team-invite` emails it through Hostinger. The link opens employers.vocationsl.com on Create account with the email filled in (`?invite=<email>&t=<token>`).
- Creating the account from the link calls `team-invite` (action `signup`), which creates the account already confirmed (no confirmation email). The sign-up trigger (`handle_new_user`) adds them to the company as a recruiter and sets the employer side, so they go straight to the dashboard.
- Team list shows waiting invites ("Invited"); owners can cancel them.
- Email priority: `job-emails` pauses while a team invite is waiting; job emails capped at 100/day, 20/hour so sign-up emails and invites have room in the Hostinger mailbox. Invites retry every minute for 2 days; links expire after 30 days.

## Release
- Web: live 9 Nov 2026.
- Android: release/play/vocation-sl-1.2.17.aab (user uploads).
- iOS: after Apple approves the version in review.
