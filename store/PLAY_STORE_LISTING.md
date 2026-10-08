# Vocation SL — Google Play submission pack

Everything to copy into the Google Play Console, in the order the Console asks for it.
Files referred to are in this `store/` folder and `release/play/`.

---

## 0. Before you start

- **Developer account:** https://play.google.com/console/signup — one-time US$25 fee and identity verification (ID document). Choose **Organization** if Vocation SL is a registered business with a D-U-N-S number; otherwise **Personal**.
- **Important for Personal accounts:** Google requires a **closed test with at least 12 testers who stay opted in for 14 days** before you can publish to everyone. Start gathering 12 Gmail addresses (friends, team, early users) now. Organization accounts skip this.
- **Package name:** `org.vocationsl.vocation_sl` (read from the .aab automatically; it can never change after the first upload).
- **Reviewer accounts (needed in step 4, App access):** create two real accounts on https://app.vocationsl.com that Google's reviewers can sign in with:
  - Job seeker: `vocationxsl+playseeker@gmail.com` (sign up, choose **Find a job**)
  - Employer: `vocationxsl+playemployer@gmail.com` (sign up, choose **Hire talent**, register a test company and approve it in Admin)
  - Gmail delivers `+anything` addresses to your normal inbox, so you can confirm both. Use a password you don't use anywhere else.

---

## 1. Create the app

| Field | Value |
|---|---|
| App name | **Vocation SL: Jobs & Hiring** |
| Default language | English (United Kingdom) – en-GB |
| App or game | App |
| Free or paid | Free |
| Declarations | Tick both (Developer Programme Policies, US export laws) |

---

## 2. Main store listing

**App name (max 30):**
```
Vocation SL: Jobs & Hiring
```

**Short description (max 80):**
```
Find jobs across Sierra Leone, apply with your CV and hear back from employers.
```

**Full description (max 4000):**
```
Vocation SL is a job platform built for Sierra Leone. Find work across all 16 districts, apply with your CV in a few steps, follow every application and talk to employers, all from your phone.

FOR JOB SEEKERS
• Search jobs by title, skill or company, and filter by district, industry, job type, experience level, salary and remote work.
• Save jobs and searches, and get alerts when something changes.
• Apply in a few steps with your CV, a cover letter and a note to the employer. PDF, DOC and DOCX files are accepted.
• Track every application: submitted, viewed, shortlisted, assessment, interview, offer and hired.
• Reply to employers inside the app when they message you about an application.
• Get push alerts for messages, interview invitations and status changes, even when the app is closed.
• Keep browsing on a weak connection: jobs and your applications are saved on your phone and sync when you're back online.
• Build a profile with your experience, education, skills, languages, certifications and job preferences.

FOR EMPLOYERS
• Choose "Hire talent" when you sign in and register your company.
• Post jobs with salary, location, requirements and deadlines.
• Manage applicants in a clear table: shortlist, assess, interview, offer and hire.
• Read CVs and cover letters in the app and message candidates directly.
• See insights for every job: views, applications and your hiring funnel.
• View and download invoices for your job listings.

SAFE AND GENUINE
• Every company and every job is reviewed by our team before it goes live.
• Report any suspicious listing in one tap.
• A genuine employer will never ask you for money to apply or attend an interview. If anyone does, report it.
• Your CV is shared only with the employers you apply to. You can delete your account and data at any time from Settings.

Free for job seekers. Covers Western Area Urban and Rural, Bo, Bombali, Bonthe, Falaba, Kailahun, Kambia, Karene, Kenema, Koinadugu, Kono, Moyamba, Port Loko, Pujehun and Tonkolili.

Help: vocationxsl@gmail.com · https://vocationsl.com
```

**Graphics (upload from `store/graphics/`):**

| Asset | File | Required size |
|---|---|---|
| App icon | `play-icon-512.png` | 512 × 512 PNG |
| Feature graphic | `feature-graphic-1024x500.png` | 1024 × 500 PNG |
| Phone screenshots (2–8) | `store/screenshots/*.png` | 1080 × 2400 PNG |

---

## 3. Store settings

| Field | Value |
|---|---|
| App category | **Business** |
| Tags | Jobs, Recruitment, Careers |
| Email address | vocationxsl@gmail.com |
| Website | https://vocationsl.com |
| Phone | (optional — leave empty unless you want it public) |
| External marketing | On |

---

## 4. App content (Policy → App content)

### Privacy policy
```
https://vocationsl.com/privacy
```

### Ads
**No**, my app does not contain ads.

### App access
**All or some functionality is restricted** → Add instructions:
- Name: `Job seeker test account` — username `vocationxsl+playseeker@gmail.com`, password: *(the one you set)*. Notes: `Sign in with email and password. Choose "Find a job".`
- Name: `Employer test account` — username `vocationxsl+playemployer@gmail.com`, password: *(the one you set)*. Notes: `Sign in with email and password. Choose "Hire talent".`

### Content rating (IARC questionnaire)
- Category: **All other app types** (Utility, Productivity, Communication or Other)
- Violence, sexuality, language, controlled substances, gambling: **No** to all
- Does the app allow users to interact or exchange content with each other? **Yes** (employers and candidates can message each other)
- Does the app share the user's current location with other users? **No**
- Does the app allow users to buy digital goods? **No**
- Is the app a web browser or search engine? **No**
- Expected result: rated for everyone, with "Users Interact".

### Target audience and content
- Target age: **18 and over** only
- Appeal to children: **No**

### News app
**No**

### Data safety
**Does your app collect or share any of the required user data types?** Yes
**Is all of the user data collected by your app encrypted in transit?** Yes
**Do you provide a way for users to request that their data is deleted?** Yes
- Account deletion URL: `https://vocationsl.com/delete-account`

Data types collected (none are *shared* — sending an application to an employer happens because the user chooses to, which Google does not count as sharing):

| Data type | Collected | Required or optional | Purposes |
|---|---|---|---|
| Personal info → Name | Yes | Required | App functionality, Account management |
| Personal info → Email address | Yes | Required | App functionality, Account management, Communications |
| Personal info → Phone number | Yes | Optional | App functionality |
| Personal info → User IDs | Yes | Required | App functionality, Account management |
| Personal info → Other info (headline, location/district, experience, education, skills) | Yes | Optional | App functionality |
| Photos and videos → Photos (profile photo, company logo) | Yes | Optional | App functionality |
| Files and docs (CVs, cover letters) | Yes | Optional | App functionality |
| Messages → Other in-app messages | Yes | Optional | App functionality, Communications |
| App activity → App interactions (job views, saved jobs, applications) | Yes | Required | App functionality, Analytics (job view counts for employers) |
| Device or other IDs (push notification token) | Yes | Optional | App functionality (alerts) |

Not collected: location from the device, financial info, health, contacts, calendar, audio, web browsing, crash logs, diagnostics, advertising IDs.

### Government apps / Financial features / Health
Not a government app · No financial features · No health features.

### Account deletion (also asked in Data safety)
- In-app: Profile → Settings → Delete account (employers: More → Delete account)
- Web: `https://vocationsl.com/delete-account`

---

## 5. Release

1. **Testing → Closed testing** (Personal accounts must do this first; Organization accounts can go straight to Production):
   - Create track "Alpha" → **Create new release**.
   - App signing: **Use Google-generated key** (Play App Signing) — recommended.
   - Upload `release/play/vocation-sl-1.0.3.aab`.
   - Release name: `1.0.2`
   - Release notes:
     ```
     <en-GB>
     First release of Vocation SL on Google Play: find and apply for jobs across Sierra Leone, track applications, message employers, get alerts, and hire as an employer.
     </en-GB>
     ```
   - Testers: create an email list with your 12+ testers; share the opt-in link with them. They must stay opted in for 14 days.
   - Countries: **Sierra Leone** (add more if you want).
2. After 14 days (Personal) → **Apply for production access** in the Dashboard, answer the short questions about your test, then **Production → Create new release** → promote the same bundle.
3. Google's review usually takes from a few days to about a week for a new app.

---

## 6. Keep safe

- Your **upload key** is in `C:\Users\user1\vocation-sl-keys\` (keystore + `README-KEEP-SAFE.txt` with the password). Back the folder up somewhere safe now (e.g. an encrypted USB drive or password manager). You need it for every future update. It is not in GitHub and must never be.
- With Play App Signing on, Google holds the final signing key; if the upload key is ever lost, Google support can reset it.

---

## 7. After approval

- Tell me the Play Store link and I'll make the Google Play badge on vocationsl.com live (it currently says "Soon").
- Future updates: increase the version in `pubspec.yaml` (e.g. `1.0.3+4`), I build a new `.aab`, you upload it to a new release.
