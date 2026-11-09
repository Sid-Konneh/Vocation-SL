// Vocation SL — "job-emails" Edge Function.
//
// 1. Called by the database (supabase/job_emails.sql, pg_cron every minute when
//    something is waiting): emails new jobs to job seekers through Hostinger.
//    Jobs waiting for the same person go in one email. Stays under DAILY_CAP
//    emails in any 24 hours, because sign-in emails use the same mailbox.
// 2. Unsubscribe: POST ?a=unsubscribe&u=<user id>&t=<token> turns job emails
//    off. Used by vocationsl.com/unsubscribe and by mail apps' one-click
//    unsubscribe (List-Unsubscribe-Post).
//
// Must be deployed with "Enforce JWT verification" OFF.
//
// Secrets (Supabase → Edge Functions → Secrets):
//   SMTP_PASSWORD        the password of the info@vocationsl.com mailbox (Hostinger)
//   PUSH_WEBHOOK_SECRET  already set (shared with the push function)
//   SITE_URL             already set: https://app.vocationsl.com
// Optional: SMTP_HOST (smtp.hostinger.com), SMTP_USER (info@vocationsl.com),
//           JOB_EMAILS_DAILY_CAP (800).

import { createClient } from "jsr:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const secret = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
const site = (Deno.env.get("SITE_URL") ?? "https://app.vocationsl.com").replace(/\/$/, "");
const fnUrl = `${(Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "")}/functions/v1/job-emails`;
const smtpUser = Deno.env.get("SMTP_USER") ?? "info@vocationsl.com";
// Hostinger refused mail on 9 Nov 2026 after only ~160 in 24 hours, and sign-up
// emails and team invites need the same mailbox, so job emails leave room.
const DAILY_CAP = Number(Deno.env.get("JOB_EMAILS_DAILY_CAP") ?? "100");
// Hostinger blocks bursts (about 90 in 4 minutes was too many on 6 Nov 2026) and
// sign-in emails share the mailbox, so send slowly. Slow sending also means jobs
// that go live close together reach each person in one email.
const HOURLY_CAP = Number(Deno.env.get("JOB_EMAILS_HOURLY_CAP") ?? "20");
const BATCH = 2;           // emails per run (runs every minute)
const BACKOFF_MIN = 15;    // pause after Hostinger says "rate limit"
const isRateLimit = (m: string) => /ratelimit|rate limit|too many|451 4\.7\.1|421/i.test(m);
const MAX_JOBS = 10;       // jobs listed in one email; the rest go in the next one

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type",
};

type Job = {
  id: string; title: string; location: string | null; employment_type: string | null;
  deadline: string | null; status: string; companies: { name: string } | null;
};

async function token(userId: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`job-emails:${userId}`)));
  let s = "";
  for (const b of sig) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "").slice(0, 32);
}

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

const typeLabel: Record<string, string> = {
  fullTime: "Full-time", partTime: "Part-time", contract: "Contract", internship: "Internship",
  volunteer: "Volunteer", temporary: "Temporary",
};

function closes(deadline: string | null): string | null {
  if (!deadline) return null;
  return new Date(deadline).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "Africa/Freetown" });
}

function jobLine(j: Job): string {
  return [j.companies?.name, j.location, typeLabel[j.employment_type ?? ""] ?? j.employment_type].filter(Boolean).join(" · ");
}

function render(name: string, jobs: Job[], unsubscribeUrl: string) {
  const first = (name || "").trim().split(/\s+/)[0];
  const hello = first ? `Hi ${esc(first)},` : "Hi,";
  const intro = jobs.length === 1 ? "A new job is live on Vocation SL:" : `${jobs.length} new jobs are live on Vocation SL:`;
  const subject = jobs.length === 1
    ? `New job: ${jobs[0].title}${jobs[0].companies?.name ? ` at ${jobs[0].companies.name}` : ""}`
    : `${jobs.length} new jobs on Vocation SL`;

  const cards = jobs.map((j) => {
    const c = closes(j.deadline);
    return `<tr><td style="padding:0 0 12px;"><table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border:1px solid #E3E7E0;border-radius:12px;"><tr><td style="padding:14px 16px;">
<div style="font-size:16px;font-weight:bold;color:#14171A;margin:0 0 4px;">${esc(j.title)}</div>
<div style="font-size:13px;color:#5E6670;margin:0 0 ${c ? 2 : 10}px;">${esc(jobLine(j))}</div>
${c ? `<div style="font-size:13px;color:#5E6670;margin:0 0 10px;">Closes ${esc(c)}</div>` : ""}
<a href="${site}/job/${j.id}" style="display:inline-block;padding:9px 18px;border-radius:10px;background:#3F7A1F;font-size:14px;font-weight:bold;color:#FFFFFF;text-decoration:none;">View job</a>
</td></tr></table></td></tr>`;
  }).join("\n");

  const html = `<!doctype html>
<html><body style="margin:0;padding:0;background:#F4F6F2;font-family:Arial,Helvetica,sans-serif;color:#2B3036;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F4F6F2;padding:24px 12px;"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#FFFFFF;border-radius:16px;overflow:hidden;">
<tr><td style="background:#3F7A1F;padding:18px 28px;"><table role="presentation" cellpadding="0" cellspacing="0"><tr><td style="vertical-align:middle;"><img src="https://vocationsl.com/assets/app-icon.png" width="44" height="44" alt="Vocation SL logo" style="display:block;width:44px;height:44px;border-radius:12px;border:0;"></td><td style="vertical-align:middle;padding-left:12px;"><span style="font-size:22px;font-weight:bold;color:#FFFFFF;">Vocation <span style="color:#B9E07F;">SL</span></span></td></tr></table></td></tr>
<tr><td style="padding:28px 28px 16px;">
<p style="margin:0 0 6px;font-size:15px;line-height:1.6;">${hello}</p>
<p style="margin:0 0 18px;font-size:15px;line-height:1.6;">${intro}</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0">
${cards}
</table>
<p style="margin:6px 0 0;font-size:14px;line-height:1.6;">See all jobs and apply in the app: <a href="${site}" style="color:#3F7A1F;font-weight:bold;">app.vocationsl.com</a> or <a href="https://play.google.com/store/apps/details?id=org.vocationsl.vocation_sl" style="color:#3F7A1F;font-weight:bold;">Vocation SL on Google Play</a>.</p>
</td></tr>
<tr><td style="padding:16px 28px;border-top:1px solid #E3E7E0;font-size:12px;line-height:1.6;color:#5E6670;">You get this email because you have a Vocation SL account. To stop job emails, <a href="${unsubscribeUrl}" style="color:#3F7A1F;">unsubscribe</a>, or turn off <b>Job emails</b> in the app under Settings → Notification settings.<br>Vocation SL · VOCATION (SL) LIMITED · 33 New Koribondo Highway, Bo City, Sierra Leone · info@vocationsl.com</td></tr>
</table></td></tr></table></body></html>`;

  const text = [
    first ? `Hi ${first},` : "Hi,", "", intro, "",
    ...jobs.flatMap((j) => {
      const c = closes(j.deadline);
      return [j.title, jobLine(j), ...(c ? [`Closes ${c}`] : []), `${site}/job/${j.id}`, ""];
    }),
    `See all jobs: ${site}`, "",
    `To stop job emails: ${unsubscribeUrl}`,
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
  const { error } = await supabase.from("profiles").update({ job_emails: false }).eq("id", u);
  if (error) return Response.json({ ok: false, error: "Could not update your settings. Please try again." }, { status: 500, headers: cors });
  return Response.json({ ok: true }, { headers: cors });
}

async function send(): Promise<Response> {
  const pass = Deno.env.get("SMTP_PASSWORD");
  if (!pass) return new Response("SMTP_PASSWORD is not set", { status: 500 });

  const ago = (min: number) => new Date(Date.now() - min * 60 * 1000).toISOString();
  // Team invites go first: they share this mailbox and someone is waiting for them.
  const { data: invites } = await supabase.from("team_invites").select("email")
    .is("emailed_at", null).gte("created_at", ago(48 * 60)).limit(1);
  if (invites?.length) return Response.json({ sent: 0, reason: "team invite waiting" });
  const { data: limited } = await supabase.from("job_email_log").select("id").eq("ok", false)
    .ilike("error", "%ratelimit%").gte("sent_at", ago(BACKOFF_MIN)).limit(1);
  if (limited?.length) return Response.json({ sent: 0, reason: "waiting after Hostinger rate limit" });
  const [{ count: day }, { count: hour }] = await Promise.all([
    supabase.from("job_email_log").select("id", { count: "exact", head: true }).eq("ok", true).gte("sent_at", ago(24 * 60)),
    supabase.from("job_email_log").select("id", { count: "exact", head: true }).eq("ok", true).gte("sent_at", ago(60)),
  ]);
  const room = Math.min(BATCH, DAILY_CAP - (day ?? 0), HOURLY_CAP - (hour ?? 0));
  if (room <= 0) return Response.json({ sent: 0, reason: "hourly or daily cap reached" });

  const ready = new Date(Date.now() - 5 * 60 * 1000).toISOString();
  const { data: rows, error } = await supabase.from("job_email_queue")
    .select("user_id, job_id, attempts, queued_at")
    .is("sent_at", null).lt("attempts", 3).lt("queued_at", ready)
    .order("queued_at").limit(5000);
  if (error) return new Response(error.message, { status: 500 });
  if (!rows?.length) return Response.json({ sent: 0 });

  // People in queue order, with their waiting jobs.
  const byUser = new Map<string, string[]>();
  for (const r of rows) {
    if (!byUser.has(r.user_id)) {
      if (byUser.size >= room) continue;
      byUser.set(r.user_id, []);
    }
    byUser.get(r.user_id)!.push(r.job_id);
  }
  const userIds = [...byUser.keys()];
  const jobIds = [...new Set([...byUser.values()].flat())];

  const [{ data: people }, { data: jobs }] = await Promise.all([
    supabase.from("profiles").select("id, email, full_name, job_emails, suspended").in("id", userIds),
    supabase.from("jobs").select("id, title, location, employment_type, deadline, status, companies(name)").in("id", jobIds),
  ]);
  const personById = new Map((people ?? []).map((p) => [p.id, p]));
  const jobById = new Map(((jobs ?? []) as unknown as Job[]).map((j) => [j.id, j]));
  const now = Date.now();
  const live = (j?: Job) => !!j && j.status === "published" && (!j.deadline || new Date(j.deadline).getTime() > now);

  const transport = nodemailer.createTransport({
    host: Deno.env.get("SMTP_HOST") ?? "smtp.hostinger.com",
    port: 465,
    secure: true,
    auth: { user: smtpUser, pass },
    pool: true,
    maxConnections: 1,
  });

  let sent = 0, failed = 0, skipped = 0;
  const errors: string[] = [];
  for (const uid of userIds) {
    const queued = byUser.get(uid)!;
    const p = personById.get(uid);
    if (!p || !p.job_emails || p.suspended || !p.email) {
      await supabase.from("job_email_queue").delete().eq("user_id", uid).is("sent_at", null);
      skipped++;
      continue;
    }
    const gone = queued.filter((id) => !live(jobById.get(id)));
    if (gone.length) {
      await supabase.from("job_email_queue").update({ sent_at: new Date().toISOString(), error: "job no longer live" })
        .eq("user_id", uid).in("job_id", gone);
    }
    const list = queued.filter((id) => live(jobById.get(id))).slice(0, MAX_JOBS).map((id) => jobById.get(id)!);
    if (!list.length) { skipped++; continue; }

    const unsubApi = `${fnUrl}?a=unsubscribe&u=${uid}&t=${await token(uid)}`;
    const unsubPage = `https://vocationsl.com/unsubscribe?u=${uid}&t=${await token(uid)}`;
    const mail = render(p.full_name ?? "", list, unsubPage);
    const ids = list.map((j) => j.id);
    try {
      await transport.sendMail({
        from: { name: "Vocation SL", address: smtpUser },
        to: p.email,
        subject: mail.subject,
        html: mail.html,
        text: mail.text,
        headers: {
          "List-Unsubscribe": `<${unsubApi}>, <mailto:info@vocationsl.com?subject=Unsubscribe%20job%20emails>`,
          "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
        },
      });
      await supabase.from("job_email_queue").update({ sent_at: new Date().toISOString(), error: null }).eq("user_id", uid).in("job_id", ids);
      await supabase.from("job_email_log").insert({ user_id: uid, jobs: ids.length, ok: true });
      sent++;
    } catch (e) {
      const msg = String((e as Error)?.message ?? e).replace(/\s+/g, " ").slice(0, 300);
      failed++;
      errors.push(msg);
      await supabase.from("job_email_log").insert({ user_id: uid, jobs: ids.length, ok: false, error: msg });
      // Hostinger is busy: not this person's fault, so keep them in the queue as they are.
      if (isRateLimit(msg)) break;
      for (const r of rows.filter((r) => r.user_id === uid && ids.includes(r.job_id))) {
        await supabase.from("job_email_queue").update({ attempts: r.attempts + 1, error: msg }).eq("user_id", uid).eq("job_id", r.job_id);
      }
      // Login problems: stop now and try again next minute.
      if (/auth|quota|454|535|550 5\.4/i.test(msg)) break;
    }
  }
  transport.close();
  return Response.json({ sent, failed, skipped, ...(errors.length ? { errors: errors.slice(0, 3) } : {}) });
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
  return send();
});
