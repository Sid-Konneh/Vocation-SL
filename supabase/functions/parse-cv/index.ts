// Vocation SL — "parse-cv" Edge Function.
//
// Reads a job seeker's uploaded CV (PDF or DOCX) with Claude and returns the
// profile details it contains. Called by the signed-in user from the app; it
// only reads files in that user's own folder, and only when they ask.
//
// Secrets (Supabase → Edge Functions → Secrets):
//   ANTHROPIC_API_KEY   from console.anthropic.com → API keys
//   CV_MODEL            optional, defaults to claude-sonnet-5-5
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided automatically.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { strFromU8, unzipSync } from "npm:fflate@0.8.2";

const MAX_PER_DAY = 10;
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
// User-facing problems come back as 200 + { error } so the app can show the message.
const problem = (message: string) => reply({ error: message });

const profileSchema = {
  type: "object",
  properties: {
    full_name: { type: "string" },
    headline: { type: "string", description: "Current or most recent job title, optionally with field, e.g. 'Accounts Assistant'. Max 80 characters." },
    phone: { type: "string" },
    location: { type: "string", description: "Town or district where the person lives, as written in the CV." },
    about: { type: "string", description: "The CV's own profile/summary section, lightly trimmed (max 600 characters). Empty if the CV has no summary." },
    linkedin_url: { type: "string" },
    portfolio_url: { type: "string" },
    experience: {
      type: "array",
      items: {
        type: "object",
        properties: {
          title: { type: "string" },
          company: { type: "string" },
          location: { type: "string" },
          start: { type: "string", description: "YYYY-MM or YYYY" },
          end: { type: "string", description: "YYYY-MM or YYYY; empty if current" },
          current: { type: "boolean" },
          description: { type: "string", description: "Main duties or achievements, max 400 characters." },
        },
        required: ["title", "company"],
      },
    },
    education: {
      type: "array",
      items: {
        type: "object",
        properties: {
          school: { type: "string" },
          degree: { type: "string" },
          field: { type: "string" },
          start_year: { type: "integer" },
          end_year: { type: "integer" },
        },
        required: ["school"],
      },
    },
    skills: { type: "array", items: { type: "string" }, description: "Up to 20 short skill names." },
    languages: {
      type: "array",
      items: {
        type: "object",
        properties: { name: { type: "string" }, level: { type: "string", description: "Native, Fluent, Professional or Basic" } },
        required: ["name"],
      },
    },
    certifications: {
      type: "array",
      items: {
        type: "object",
        properties: { name: { type: "string" }, issuer: { type: "string" }, year: { type: "integer" } },
        required: ["name"],
      },
    },
  },
};

const instructions = `You are reading a CV (résumé) for a job platform in Sierra Leone.
Call save_profile with the details the CV actually contains.
Rules:
- Only use information written in the CV. Never guess or invent names, dates, employers, skills or anything else.
- Leave a field empty, or a list empty, when the CV doesn't say it.
- Dates as YYYY-MM when the month is given, otherwise YYYY. Mark the current job with current: true.
- List experience newest first.
- Keep the person's own wording; fix only obvious typos.`;

/** Plain text from a .docx (word/document.xml). */
function docxText(bytes: Uint8Array): string {
  const files = unzipSync(bytes, { filter: (f) => f.name === "word/document.xml" });
  const xml = files["word/document.xml"];
  if (!xml) return "";
  return strFromU8(xml)
    .replace(/<w:tab\/>/g, "\t")
    .replace(/<\/w:p>/g, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&apos;/g, "'")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function base64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "Method not allowed" }, 405);

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) return problem("Filling your profile from a CV isn't switched on yet.");

  // Who is asking?
  const authHeader = req.headers.get("Authorization") ?? "";
  const asUser = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user } } = await asUser.auth.getUser();
  if (!user) return reply({ error: "Please sign in again." }, 401);

  const { path } = await req.json().catch(() => ({ path: "" }));
  if (typeof path !== "string" || !path.startsWith(`${user.id}/`)) return problem("That file isn't yours.");

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // A few reads a day per person is plenty, and keeps costs predictable.
  const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const { count } = await admin.from("cv_reads").select("*", { count: "exact", head: true }).eq("user_id", user.id).gte("created_at", since);
  if ((count ?? 0) >= MAX_PER_DAY) return problem("You've read several CVs today. Please try again tomorrow.");

  const { data: file, error: dlError } = await admin.storage.from("documents").download(path);
  if (dlError || !file) return problem("We couldn't open that file. Try uploading it again.");
  const bytes = new Uint8Array(await file.arrayBuffer());
  const lower = path.toLowerCase();

  let cvContent: unknown;
  if (lower.endsWith(".pdf")) {
    cvContent = { type: "document", source: { type: "base64", media_type: "application/pdf", data: base64(bytes) } };
  } else if (lower.endsWith(".docx")) {
    const text = docxText(bytes);
    if (text.length < 40) return problem("That document looks empty. Try saving your CV as a PDF.");
    cvContent = { type: "text", text: `CV text:\n\n${text.slice(0, 60000)}` };
  } else {
    return problem("Only PDF and DOCX CVs can be read. Save your CV as a PDF and upload it again.");
  }

  await admin.from("cv_reads").insert({ user_id: user.id });

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({
      model: Deno.env.get("CV_MODEL") ?? "claude-sonnet-5-5",
      max_tokens: 4000,
      system: instructions,
      tools: [{ name: "save_profile", description: "Save the profile details found in the CV.", input_schema: profileSchema }],
      tool_choice: { type: "tool", name: "save_profile" },
      messages: [{ role: "user", content: [cvContent, { type: "text", text: "Read this CV and call save_profile." }] }],
    }),
  });
  if (!res.ok) {
    console.error(`Anthropic ${res.status}: ${await res.text()}`);
    return problem("We couldn't read that CV right now. Please try again later.");
  }
  const out = await res.json();
  const call = (out.content ?? []).find((b: { type: string }) => b.type === "tool_use");
  if (!call) return problem("We couldn't find profile details in that CV.");
  return reply({ profile: call.input });
});
