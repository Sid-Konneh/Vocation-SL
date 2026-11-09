# Vocation SL 1.2.16 (build 31), 8 November 2026

## What changed
- **AI job matching pilot.** An open-source AI text model (gte-small) runs inside our Supabase project (Edge Function `ai-match`) and turns every published job and every job-seeker profile into an embedding of its meaning. `supabase/ai_matching.sql` stores them in `ai_embeddings` (server only) and provides `ai_job_matches()` and `ai_applicant_matches()`.
- Job seekers: "Recommended for you" and "A good match for you" add the AI similarity to the existing rules (4 points at ≥ 0.84 "AI: a strong fit with your profile", 2 points at ≥ 0.81 "AI: fits your profile"; thresholds from 3,354 real profile–job pairs).
- Employers: Candidates has an "AI match" column (Strong / Good / Low), sortable. Advice only.
- Profile text used: headline, preferred titles, skills, past job titles and descriptions, studies, certifications, about. Never name, email, phone, photo or location.

## Release
- Web: live as 1.2.16 since 8 Nov 2026.
- Android: release/play/vocation-sl-1.2.16.aab (user uploads).
- iOS: after Apple approves 1.2.13.
