# Vocation SL 1.2.8 (build 21)

## What changed
- **Cover letter required.** Job seekers must upload a cover letter as a PDF to apply. The Skip option is gone; the step shows "Upload your cover letter as a PDF to continue" until a file is added.
- PDF only: the picker already refused other file types; no change there.
- Wording updated to match: the "How to apply" list on job details, the in-app guide for job seekers, and the note in the employer job editor.
- Applications sent before 1.2.8 without a cover letter still show "No cover letter".

## Database
No SQL to run.

## Checks
- `flutter analyze` on the changed files: no issues.
- `test/app_flow_test.dart` (now uploads a PDF cover letter) and `test/onboarding_test.dart`: all pass.

## Google Play notes
See `release/play/vocation-sl-1.2.8-release-notes.txt`.
