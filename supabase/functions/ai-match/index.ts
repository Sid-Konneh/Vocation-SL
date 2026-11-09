// Vocation SL — "ai-match" Edge Function (AI job matching pilot, 8 Nov 2026).
//
// Called every minute by the database (supabase/ai_matching.sql, pg_cron →
// kick_ai_embed) when a job or job-seeker profile is new or has changed.
// For each one it builds a short text, runs it through gte-small (an
// open-source AI text model that runs inside Supabase, so no data leaves our
// platform) and saves the 384-number embedding in public.ai_embeddings.
// The app then asks the database how close a person's embedding is to each
// job's (ai_job_matches / ai_applicant_matches).
//
// What goes into a profile's text: headline, about, skills, past job titles
// and descriptions, studies and preferred job titles. Never the name, email,
// phone, photo, location, gender or age.
//
// Must be deployed with "Enforce JWT verification" OFF; it checks the
// x-webhook-secret header (PUSH_WEBHOOK_SECRET) instead.

import { createClient } from "jsr:@supabase/supabase-js@2";

declare const Supabase: { ai: { Session: new (model: string) => { run: (input: string, opts: Record<string, unknown>) => Promise<number[]> } } };

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const secret = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
const model = new Supabase.ai.Session("gte-small");

const BATCH = 80;          // rows per kind per run (about 0.1 s each)
const TIME_BUDGET_MS = 40_000;
const MAX_CHARS = 1800;    // gte-small reads about 512 tokens

type Json = unknown;
const list = (v: Json): Json[] => (Array.isArray(v) ? v : []);
const str = (v: Json): string => {
  if (v == null) return "";
  if (typeof v === "string") return v;
  if (typeof v === "number") return String(v);
  if (typeof v === "object") {
    const o = v as Record<string, Json>;
    return str(o.name ?? o.title ?? o.text ?? o.label ?? "");
  }
  return "";
};
const clean = (parts: string[]) =>
  parts.map((p) => p.replace(/\s+/g, " ").trim()).filter(Boolean).join(". ").slice(0, MAX_CHARS);

const labels: Record<string, string> = {
  fullTime: "Full-time", partTime: "Part-time", contract: "Contract", internship: "Internship",
  volunteer: "Volunteer", temporary: "Temporary",
};

type JobRow = {
  id: string; title: string; industry: string | null; experience_level: string | null; employment_type: string | null;
  about: string | null; description: string | null; skills: Json; requirements: Json; responsibilities: Json;
  updated_at: string | null; posted_at: string | null;
};
type ProfileRow = { id: string; data: Record<string, Json> | null; updated_at: string | null; created_at: string };

function jobText(j: JobRow): string {
  return clean([
    j.title,
    labels[j.employment_type ?? ""] ?? "",
    j.industry ?? "",
    j.experience_level ? `${j.experience_level} level` : "",
    list(j.skills).map(str).join(", "),
    list(j.requirements).map(str).join(". "),
    list(j.responsibilities).map(str).join(". "),
    j.about ?? "",
    j.description ?? "",
  ]);
}

function profileText(p: ProfileRow): string | null {
  const d = p.data ?? {};
  const prefs = (d.preferences ?? {}) as Record<string, Json>;
  const text = clean([
    str(d.headline),
    list(prefs.titles).map(str).join(", "),
    list(d.skills).map(str).join(", "),
    ...list(d.experience).map((e) => {
      const o = (e ?? {}) as Record<string, Json>;
      return [str(o.title), str(o.description)].filter(Boolean).join(": ");
    }),
    ...list(d.education).map((e) => {
      const o = (e ?? {}) as Record<string, Json>;
      return [str(o.degree), str(o.field)].filter(Boolean).join(" in ");
    }),
    list(d.certifications).map(str).join(", "),
    str(d.about),
  ]);
  // Too little to say anything useful about the person yet.
  return text.split(/\s+/).filter((w) => w.length > 1).length >= 2 ? text : null;
}

async function embed(text: string): Promise<string> {
  const v = await model.run(text, { mean_pool: true, normalize: true });
  return `[${Array.from(v).join(",")}]`;
}

async function save(kind: string, id: string, embedding: string | null, src: string) {
  const { error } = await supabase.rpc("ai_embed_save", { p_kind: kind, p_ref_id: id, p_embedding: embedding, p_src: src });
  if (error) throw new Error(`save ${kind} ${id}: ${error.message}`);
}

async function run(): Promise<Response> {
  const started = Date.now();
  const { data: todo, error } = await supabase.rpc("ai_embed_todo", { max_rows: BATCH });
  if (error) return new Response(error.message, { status: 500 });
  const rows = (todo ?? []) as { kind: string; ref_id: string }[];
  const jobIds = rows.filter((r) => r.kind === "job").map((r) => r.ref_id);
  const profileIds = rows.filter((r) => r.kind === "profile").map((r) => r.ref_id);

  const [{ data: jobs }, { data: profiles }] = await Promise.all([
    jobIds.length
      ? supabase.from("jobs").select("id, title, industry, experience_level, employment_type, about, description, skills, requirements, responsibilities, updated_at, posted_at").in("id", jobIds)
      : Promise.resolve({ data: [] as JobRow[] }),
    profileIds.length
      ? supabase.from("profiles").select("id, data, updated_at, created_at").in("id", profileIds)
      : Promise.resolve({ data: [] as ProfileRow[] }),
  ]);

  let done = 0, empty = 0;
  const errors: string[] = [];
  for (const j of (jobs ?? []) as JobRow[]) {
    if (Date.now() - started > TIME_BUDGET_MS) break;
    try {
      await save("job", j.id, await embed(jobText(j)), j.updated_at ?? j.posted_at ?? new Date().toISOString());
      done++;
    } catch (e) { errors.push(String((e as Error).message ?? e).slice(0, 200)); }
  }
  for (const p of (profiles ?? []) as ProfileRow[]) {
    if (Date.now() - started > TIME_BUDGET_MS) break;
    try {
      const text = profileText(p);
      if (!text) empty++;
      await save("profile", p.id, text ? await embed(text) : null, p.updated_at ?? p.created_at);
      done++;
    } catch (e) { errors.push(String((e as Error).message ?? e).slice(0, 200)); }
  }
  return Response.json({ done, empty, ms: Date.now() - started, ...(errors.length ? { errors: errors.slice(0, 3) } : {}) });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  if (!secret || req.headers.get("x-webhook-secret") !== secret) return new Response("Unauthorized", { status: 401 });
  return run();
});
