# Vocation SL 1.2.10 (build 25)

## What changed
- **Report and block in messages.** Every employer ⇄ candidate conversation has a ⋯ menu:
  - **Report** the other side (reasons: asked for money, harassment, spam or scam, inappropriate content, something else). Candidates report the company, employers report the candidate. Reports appear in Admin → Reports.
  - **Block** the other side. A block covers every application between that company and candidate; once either side blocks, neither can send new messages ("Messages are off"). The blocker can unblock from the same menu.
- Needed for the App Store (guideline 1.2: apps with user messaging must offer reporting and blocking).
- Employer payments (posting invoices, "Feature this job") are unchanged on all platforms.

## Database: run BEFORE deploying the web app
`supabase/conversation_safety.sql` (new table `conversation_blocks`, functions `conversation_status`, `block_conversation`, `report_conversation`, and the message insert policy now refuses messages in blocked conversations). Safe to run more than once.

## Checks
- `test/conversation_safety_test.dart` (block, unblock, report), plus the app and employer flow tests.

## Store notes
Google Play / App Store:
```
<en-GB>
What's new in 1.2.10

• Report or block a company or candidate from any conversation, so you only hear from people you want to
</en-GB>
```
