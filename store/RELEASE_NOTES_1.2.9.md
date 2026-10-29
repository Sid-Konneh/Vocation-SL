# Vocation SL 1.2.9 (build 22)

## What changed
- **Sign in with Apple.** A black "Sign up with Apple" / "Continue with Apple" button under the Google button. One button does both: a new Apple ID creates an account, an existing one signs in. The Find a job / Hire talent choice is kept, so new employers go to "Set up your company".
- The button only shows when Apple is enabled in Supabase (checked at run time). Demo mode never shows it.
- Wording now mentions Apple: wrong-password message, Settings (set a password), Delete account, and the admin People page ("Apple" sign-in method).

## Setup (done 29 Oct 2026)
- Apple Developer: App ID `org.vocationsl.app`, Services ID `org.vocationsl.web` (return URL `https://gkglfqsvxyemykpnjxik.supabase.co/auth/v1/callback`), Sign in with Apple key `6V2J9MXR74`.
- Supabase: Apple provider on, Client ID `org.vocationsl.web`.
- **The Apple secret key expires about 6 months after it was made (late April 2027).** Make a new one with `Documents\Vocation SL\build\tools\apple-secret.cjs` and the same `.p8` (kept in `Documents\Keys`, never in the repo), then paste it into Supabase.

## Database
No SQL to run.

## Checks
- `flutter analyze lib`: no issues.
- `test/app_flow_test.dart` and `test/release_1_2_test.dart`: all 15 pass.
- Supabase redirects to Apple with the right Client ID; Apple's page accepts it.
