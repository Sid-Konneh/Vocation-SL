# Vocation SL

A job discovery and application app for Sierra Leone, built with Flutter for Android, iOS and the web.

Job seekers can search and filter jobs, save jobs and searches, apply with a CV and cover letter, track each application through a visual timeline, and get alerts for new matches and status changes. The app works offline: it shows cached data and queues changes until the connection returns.

> **Demo data:** out of the box the app runs on a built-in demo backend. All employers, jobs and the demo user are **fictional examples** created for this project. They do not represent real organisations or real vacancies.

## Try it

| | |
|---|---|
| Demo login | `demo@vocationsl.app` / `Demo@2026` (or tap **Continue with demo account**) |
| Android | Install `release/vocation-sl-v1.0.1.apk` (sideload; enable "Install unknown apps") |
| Web | https://vocation-sl.vercel.app |

In demo mode, an application you submit moves through the pipeline by itself so you can see tracking and notifications work: viewed after ~40 seconds, shortlisted after ~2 minutes, interview invitation after ~4 minutes.

## Features

- **Discovery:** home feed with featured and recommended jobs, browse by industry, pull to refresh, infinite scroll.
- **Search and filters:** keyword (title, skill, company), location, employment type, industry, experience level, minimum salary, remote/hybrid/on-site, date posted, company and sort. Recent searches. Save any search as an alert.
- **Job details:** about, description, responsibilities, eligibility, preferred qualifications, skills (with your skill match), benefits, salary, location, deadline, company info; apply, save and share.
- **Applications:** a five-step flow (confirm details → CV upload in PDF/DOC/DOCX → upload or write a cover letter → note to the employer → review), then submit and a confirmation screen.
- **Tracking:** Applied → Viewed → Shortlisted → Assessment → Interview → Offer → Hired, plus Rejected and Withdrawn. Timeline, status history, documents, notes, interview dates, deadlines, employer messages and withdrawal.
- **Alerts:** new matches, saved-search results, submission, viewed, shortlisted, interview, status changes, employer messages and deadlines. Unread badge, mark as read, swipe to delete, per-type preferences.
- **Profile:** photo, headline, about, experience, education, skills, certifications, languages, CV, portfolio, LinkedIn, job preferences and a profile-strength meter.
- **Offline:** Hive cache with expiry, cache-first loading with background refresh, an offline banner, an outbox that replays writes on reconnect, and retry everywhere.
- **Loading and empty states:** shimmer skeletons for every list and detail page, designed empty and error states.
- **Responsive and accessible:** bottom navigation on phones and a navigation rail on tablets and desktop; semantic labels, large touch targets, respects text scaling and reduced motion; light and dark themes.

## Architecture

```
lib/
  core/          config, errors, theme (design tokens), routing (go_router), storage (Hive), network, utils
  models/        Job, Company, JobApplication, ApplicationStatus, AppNotification, SavedJob, JobAlert, AppUser, Resume, CoverLetter, JobFilter
  data/
    backend/     VocationBackend interface + DemoBackend + SupabaseBackend
    demo/        demo companies, jobs, user, applications, notifications
  repositories/  JobRepository, ApplicationRepository, UserRepository, NotificationRepository, SavedJobRepository, SyncService (offline outbox)
  services/      file picking/validation, sharing
  providers/     Riverpod controllers (cache-first base class, paged search, user data)
  features/      splash, auth, shell, jobs, apply, applications, saved, notifications, profile
  widgets/       design-system components: job cards, skeletons, empty/error states, logo
supabase/        schema.sql (tables, RLS, triggers, storage) and seed.sql
tool/            generate_seed.dart (builds seed.sql from the demo data)
```

The UI talks only to Riverpod controllers, the controllers talk to repositories, and the repositories talk to the `VocationBackend` interface. To move to another backend (Firebase, a REST API), implement `VocationBackend` and pass it in `main.dart`. No screen code changes.

## Run locally

```bash
flutter pub get
flutter run                 # demo backend
flutter test                # unit tests + end-to-end flow test
```

### Testing tools

**Profile → Settings → Testing tools** has switches to simulate offline mode, a slow network and server errors, plus a reset for the demo data. Use them to check skeletons, offline banners, queued applications, sync and retry states without touching your Wi-Fi.

## Connect Supabase

1. Create a project at [supabase.com](https://supabase.com).
2. In the SQL editor, run `supabase/schema.sql`, then `supabase/seed.sql`.
   (To refresh demo dates later: `dart run tool/generate_seed.dart`, then run `seed.sql` again.)
3. In **Authentication → Providers → Email**, decide whether to require email confirmation.
4. Build or run with your project URL and **publishable (anon) key**:

```bash
flutter run --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
            --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

The publishable key is meant to be public; row-level security in `schema.sql` restricts each user to their own profile, applications, notifications, saved jobs, alerts and documents. **Never** put the service-role key in the app.

Employer-side status changes (viewed, shortlisted, interview…) are made by updating `applications.status` with the service role or an employer dashboard; a trigger records the history and creates the applicant's notification.

> The Supabase backend is implemented and compiles, but it has not yet been run against a live Supabase project. Test it with your project before launch.

## Deploy the web app to Vercel

The repo includes a prebuilt web app in `deploy/web` and a `vercel.json` that serves it as-is, so Vercel doesn't need Flutter installed.

1. On [vercel.com](https://vercel.com), choose **Add New → Project** and import this GitHub repo.
2. Leave the framework preset as **Other**. `vercel.json` already sets the output directory and turns off the build step.
3. Deploy.

To update the site, rebuild and commit:

```bash
flutter build web --release
rm -rf deploy/web && cp -r build/web deploy/web
```

Add the `--dart-define` flags above to `flutter build web` to make the deployed site use Supabase.

## Build the Android APK

```bash
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```

The included APK is signed with the default debug key, which is fine for testing and sharing directly but **not** accepted by the Play Store. Before publishing, create an upload keystore and configure release signing in `android/app/build.gradle.kts` ([guide](https://docs.flutter.dev/deployment/android#sign-the-app)).

## Branding

The logo is redrawn in code (`lib/widgets/vocation_logo.dart`) and as `assets/images/logo.svg`, based on the Vocation SL mark: an interlaced black V and green A. Launcher icons and splash images are generated from `assets/images/*.png`:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

To use the original logo file instead, replace `assets/images/app_icon.png` (1024×1024, white background), `app_icon_foreground.png` and `splash_logo.png` (transparent), then run the two commands above.

## Help & support

Email **vocationxsl@gmail.com**.

## Licences

Plus Jakarta Sans is used under the SIL Open Font License (`assets/fonts/OFL.txt`).
