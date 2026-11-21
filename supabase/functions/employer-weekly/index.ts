// Vocation SL — "employer-weekly" Edge Function.
//
// 1. Called every Monday at 08:00 by the database (supabase/release_1_3.sql,
//    cron vsl-employer-weekly → kick_employer_weekly()): emails each employer
//    (company owner and team) a report on their live jobs: views this week,
//    new and unanswered applicants, and how many job seekers' profiles are a
//    strong fit. Jobs past their deadline get an "Extend" reminder.
//    Body options (with the webhook secret): {"dry": true} returns the data
//    without sending; {"only": "<user id>"} sends to that person only.
// 2. Unsubscribe: POST ?a=unsubscribe&u=<user id>&t=<token> turns the weekly
//    report off (profiles.weekly_report). Used by vocationsl.com/unsubscribe-weekly
//    and by mail apps' one-click unsubscribe.
//
// Must be deployed with "Enforce JWT verification" OFF. Uses the same secrets
// as job-emails (SMTP_USER, SMTP_PASSWORD, PUSH_WEBHOOK_SECRET, SITE_URL).

import { createClient } from "jsr:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const secret = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
const site = (Deno.env.get("SITE_URL") ?? "https://app.vocationsl.com").replace(/\/$/, "");
const employerSite = "https://employers.vocationsl.com";
const fnUrl = `${(Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "")}/functions/v1/employer-weekly`;
const smtpUser = Deno.env.get("SMTP_USER") ?? "info@vocationsl.com";
const isRateLimit = (m: string) => /ratelimit|rate limit|too many|451 4\.7\.1|421/i.test(m);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type",
};

type ReportJob = {
  id: string; title: string; status: string; location: string; deadline: string;
  views: number; views_week: number | null; external: boolean; apply_clicks: number; external_applied: number;
  applicants: number; new_applicants: number; unanswered: number; matching: number; in_town: number;
};
type Recipient = { user_id: string; email: string; name: string; company: string; jobs: ReportJob[] };

async function token(userId: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`employer-weekly:${userId}`)));
  let s = "";
  for (const b of sig) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "").slice(0, 32);
}

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const n = (v: number) => v.toLocaleString("en-GB");
const plural = (v: number, one: string, many = `${one}s`) => `${n(v)} ${v === 1 ? one : many}`;

function daysLeft(deadline: string): number {
  return Math.floor((new Date(deadline).getTime() - Date.now()) / 86400000);
}

function closesText(j: ReportJob): string {
  if (j.status === "closed") return "Closed";
  const d = daysLeft(j.deadline);
  const date = new Date(j.deadline).toLocaleDateString("en-GB", { day: "numeric", month: "short", timeZone: "Africa/Freetown" });
  if (d < 0) return `Deadline passed (${date})`;
  if (d === 0) return "Closes today";
  return `Closes ${date} (${plural(d, "day")} left)`;
}

/** The lines of numbers for one job, plain text. */
function stats(j: ReportJob): string[] {
  const views = j.views_week == null ? `${plural(j.views, "view")} in total` : `${plural(j.views_week, "view")} this week (${n(j.views)} in total)`;
  const lines = [views];
  if (j.external) {
    lines.push(`${plural(j.apply_clicks, "tap")} on your apply link${j.external_applied ? `, ${n(j.external_applied)} told us they applied` : ""}`);
  } else {
    lines.push(`${plural(j.new_applicants, "new applicant")} this week (${n(j.applicants)} in total)`);
    if (j.unanswered) lines.push(`${plural(j.unanswered, "applicant")} waiting for you to open their application`);
  }
  if (j.matching) lines.push(`${plural(j.matching, "job seeker")} on Vocation SL ${j.matching === 1 ? "has" : "have"} a profile that strongly fits this job`);
  return lines;
}

function needsExtend(j: ReportJob): boolean {
  return j.status === "closed" || daysLeft(j.deadline) <= 3;
}

function render(r: Recipient, unsubscribeUrl: string) {
  const first = (r.name || "").trim().split(/\s+/)[0];
  const hello = first ? `Hi ${esc(first)},` : "Hi,";
  const live = r.jobs.filter((j) => j.status === "published");
  const newApps = r.jobs.reduce((s, j) => s + j.new_applicants, 0);
  const waiting = r.jobs.reduce((s, j) => s + j.unanswered, 0);
  const subject = newApps
    ? `${r.company}: ${plural(newApps, "new applicant")} this week on Vocation SL`
    : `${r.company}: your weekly hiring report from Vocation SL`;
  const intro = `Here's how ${live.length === 1 ? "your job is" : `your ${n(live.length)} live jobs are`} doing on Vocation SL this week.`;

  const button = (href: string, label: string, primary = true) =>
    `<a href="${href}" style="display:inline-block;margin:0 8px 0 0;padding:9px 16px;border-radius:10px;${primary ? "background:#3F7A1F;color:#FFFFFF;" : "background:#EFF6E6;color:#2C5A14;"}font-size:14px;font-weight:bold;text-decoration:none;">${label}</a>`;

  const cards = r.jobs.map((j) => {
    const extend = needsExtend(j);
    return `<tr><td style="padding:0 0 12px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border:1px solid ${extend ? "#E8B04A" : "#E3E7E0"};border-radius:12px;"><tr><td style="padding:14px 16px;">
<div style="font-size:16px;font-weight:bold;color:#14171A;margin:0 0 2px;">${esc(j.title)}</div>
<div style="font-size:13px;color:${extend ? "#9A5B00" : "#5E6670"};margin:0 0 10px;">${esc(j.location)} · ${esc(closesText(j))}</div>
${stats(j).map((l) => `<div style="font-size:14px;line-height:1.55;color:#2B3036;">• ${esc(l)}</div>`).join("\n")}
<div style="margin-top:12px;">${!j.external && j.applicants ? button(`${employerSite}/#/employer/candidates?job=${j.id}`, "Review applicants") : ""}${extend ? button(`${employerSite}/#/employer/jobs`, j.status === "closed" ? "Repost this job" : "Extend this job", !(!j.external && j.applicants)) : button(`${employerSite}/#/employer/jobs/${j.id}/report`, "Hiring report", false)}</div>
</td></tr></table></td></tr>`;
  }).join("\n");

  const html = `<!doctype html>
<html><body style="margin:0;padding:0;background:#F4F6F2;font-family:Arial,Helvetica,sans-serif;color:#2B3036;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F4F6F2;padding:24px 12px;"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#FFFFFF;border-radius:16px;overflow:hidden;">
<tr><td style="background:#3F7A1F;padding:18px 28px;"><table role="presentation" cellpadding="0" cellspacing="0"><tr><td style="vertical-align:middle;"><img src="https://vocationsl.com/assets/app-icon.png" width="44" height="44" alt="Vocation SL logo" style="display:block;width:44px;height:44px;border-radius:12px;border:0;"></td><td style="vertical-align:middle;padding-left:12px;"><span style="font-size:22px;font-weight:bold;color:#FFFFFF;">Vocation <span style="color:#B9E07F;">SL</span></span><br><span style="font-size:13px;color:#DDEFC8;">Weekly hiring report</span></td></tr></table></td></tr>
<tr><td style="padding:28px 28px 16px;">
<p style="margin:0 0 6px;font-size:15px;line-height:1.6;">${hello}</p>
<p style="margin:0 0 ${waiting ? 8 : 18}px;font-size:15px;line-height:1.6;">${esc(intro)}</p>
${waiting ? `<p style="margin:0 0 18px;padding:10px 14px;border-radius:10px;background:#FFF6E5;font-size:14px;line-height:1.5;color:#7A4A00;"><b>${plural(waiting, "applicant is", "applicants are")} waiting.</b> Candidates who hear back quickly are more likely to accept an interview.</p>` : ""}
<table role="presentation" width="100%" cellpadding="0" cellspacing="0">
${cards}
</table>
<p style="margin:6px 0 0;font-size:14px;line-height:1.6;">Need more weeks? Extend a job from <b>My jobs</b> for SLE 1,000 a week (+15% GST). Busy? Send your next job advert to <a href="mailto:info@vocationsl.com" style="color:#3F7A1F;font-weight:bold;">info@vocationsl.com</a> or WhatsApp +232 73 512 413 and we'll post it for you.</p>
</td></tr>
<tr><td style="padding:16px 28px;border-top:1px solid #E3E7E0;font-size:12px;line-height:1.6;color:#5E6670;">You get this weekly report because you manage jobs for ${esc(r.company)} on Vocation SL. "Strongly fits" compares the job with job seekers' profiles; it is a guide, not a guarantee. To stop these reports, <a href="${unsubscribeUrl}" style="color:#3F7A1F;">unsubscribe</a>.<br>Vocation SL · VOCATION (SL) LIMITED · 33 New Koribondo Highway, Bo City, Sierra Leone · info@vocationsl.com</td></tr>
</table></td></tr></table></body></html>`;

  const text = [
    first ? `Hi ${first},` : "Hi,", "", intro, "",
    ...(waiting ? [`${plural(waiting, "applicant is", "applicants are")} waiting for you to open their application.`, ""] : []),
    ...r.jobs.flatMap((j) => [
      j.title, `${j.location} · ${closesText(j)}`, ...stats(j).map((l) => `- ${l}`),
      needsExtend(j) ? `${j.status === "closed" ? "Repost" : "Extend"} it from My jobs: ${employerSite}/#/employer/jobs` : `Hiring report: ${employerSite}/#/employer/jobs/${j.id}/report`, "",
    ]),
    "Need more weeks? Extend a job from My jobs for SLE 1,000 a week (+15% GST).",
    "Busy? Send your next job advert to info@vocationsl.com or WhatsApp +232 73 512 413 and we'll post it for you.", "",
    `To stop these reports: ${unsubscribeUrl}`,
    "Vocation SL · VOCATION (SL) LIMITED · 33 New Koribondo Highway, Bo City · info@vocationsl.com",
  ].join("\n");

  return { subject, html, text };
}

async function unsubscribe(url: URL): Promise<Response> {
  const u = url.searchParams.get("u") ?? "";
  const t = url.searchParams.get("t") ?? "";
  if (!/^[0-9a-f-]{36}$/i.test(u) || t !== await token(u)) {
    return Response.json({ ok: false, error: "This unsubscribe link is not valid." }, { status: 400, headers: cors });
  }
  const { error } = await supabase.from("profiles").update({ weekly_report: false }).eq("id", u);
  if (error) return Response.json({ ok: false, error: "Could not update your settings. Please try again." }, { status: 500, headers: cors });
  return Response.json({ ok: true }, { headers: cors });
}

async function send(opts: { dry?: boolean; only?: string }): Promise<Response> {
  const { data, error } = await supabase.rpc("employer_weekly_data", { p_commit: !opts.dry && !opts.only });
  if (error) return new Response(error.message, { status: 500 });
  let people = (data ?? []) as Recipient[];
  if (opts.only) people = people.filter((p) => p.user_id === opts.only);
  if (opts.dry) return Response.json({ recipients: people.length, people });

  const pass = Deno.env.get("SMTP_PASSWORD");
  if (!pass) return new Response("SMTP_PASSWORD is not set", { status: 500 });
  const transport = nodemailer.createTransport({
    host: Deno.env.get("SMTP_HOST") ?? "smtp.hostinger.com",
    port: 465,
    secure: true,
    auth: { user: smtpUser, pass },
    pool: true,
    maxConnections: 1,
  });

  let sent = 0, failed = 0;
  const errors: string[] = [];
  for (const p of people) {
    if (!p.jobs?.length) continue;
    const t = await token(p.user_id);
    const unsubPage = `https://vocationsl.com/unsubscribe-weekly?u=${p.user_id}&t=${t}`;
    const unsubApi = `${fnUrl}?a=unsubscribe&u=${p.user_id}&t=${t}`;
    const mail = render(p, unsubPage);
    try {
      await transport.sendMail({
        from: { name: "Vocation SL", address: smtpUser },
        to: p.email,
        subject: mail.subject,
        html: mail.html,
        text: mail.text,
        headers: {
          "List-Unsubscribe": `<${unsubApi}>, <mailto:info@vocationsl.com?subject=Unsubscribe%20weekly%20report>`,
          "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
        },
      });
      await supabase.from("employer_weekly_log").insert({ user_id: p.user_id, ok: true });
      sent++;
    } catch (e) {
      const msg = String((e as Error)?.message ?? e).replace(/\s+/g, " ").slice(0, 300);
      failed++;
      errors.push(msg);
      await supabase.from("employer_weekly_log").insert({ user_id: p.user_id, ok: false, error: msg });
      if (isRateLimit(msg) || /auth|quota|454|535/i.test(msg)) break;
    }
    // Hostinger dislikes bursts.
    await new Promise((r) => setTimeout(r, 1500));
  }
  transport.close();
  return Response.json({ sent, failed, ...(errors.length ? { errors: errors.slice(0, 3) } : {}) });
}

Deno.serve(async (req) => {
  const url = new URL(req.url);
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (url.searchParams.get("a") === "unsubscribe") {
    if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers: cors });
    return unsubscribe(url);
  }
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  if (!secret || req.headers.get("x-webhook-secret") !== secret) return new Response("Unauthorized", { status: 401 });
  let body: { dry?: boolean; only?: string } = {};
  try { body = await req.json(); } catch { /* empty body */ }
  return send(body);
});
