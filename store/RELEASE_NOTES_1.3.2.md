# Vocation SL 1.3.2 (build 37)

Includes everything in 1.3.1 (applicant count / early applicant, Responsive employer). No database changes.

## Sign up and sign in with Google or Apple
- Android: `MainActivity` launchMode `singleTop` → `singleTask`. With `taskAffinity=""`, the return link from the browser started a second, cold copy of the app; the first copy stayed on the sign-in screen. Now the running app is reused.
- iPhone: the Safari sheet used for Google/Apple is closed (`closeInAppWebView`) as soon as the session arrives, instead of staying on screen.
- Sign-in screen (phones): while the browser is open it says what to do; on return it shows "Signing you in…"; after 25 s without a session, or if the return link fails (error from `onAuthStateChange`, now handled via `authErrorProvider`), it shows a clear "try again" message. Cancel button.
