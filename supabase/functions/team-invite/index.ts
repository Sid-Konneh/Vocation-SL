// Vocation SL — "team-invite" Edge Function.
//
// Called by the database (supabase/team_invites.sql) when a company owner adds
// a colleague who has no Vocation SL account yet. Emails each waiting invite
// once, through the same Hostinger mailbox as the job emails.
//
// Must be deployed with "Enforce JWT verification" OFF.
// Secrets (already set for job-emails): SMTP_PASSWORD, PUSH_WEBHOOK_SECRET.
// Optional: SMTP_HOST, SMTP_USER, EMPLOYER_SITE_URL (https://employers.vocationsl.com).

import { createClient } from "jsr:@supabase/supabase-js@2";
import nodemailer from "npm:nodemailer@6.9.16";

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const secret = Deno.env.get("PUSH_WEBHOOK_SECRET") ?? "";
const smtpUser = Deno.env.get("SMTP_USER") ?? "info@vocationsl.com";
const site = (Deno.env.get("EMPLOYER_SITE_URL") ?? "https://employers.vocationsl.com").replace(/\/$/, "");

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

function render(company: string, inviter: string, email: string, token: string) {
  const who = inviter ? `${inviter} at ${company}` : company;
  const subject = `Join ${company} on Vocation SL`;
  const link = `${site}/?invite=${encodeURIComponent(email)}&t=${token}`;
  const html = `<!doctype html>
<html><body style="margin:0;padding:0;background:#F4F6F2;font-family:Arial,Helvetica,sans-serif;color:#2B3036;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F4F6F2;padding:24px 12px;"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#FFFFFF;border-radius:16px;overflow:hidden;">
<tr><td style="background:#3F7A1F;padding:18px 28px;"><table role="presentation" cellpadding="0" cellspacing="0"><tr><td style="vertical-align:middle;"><img src="https://vocationsl.com/assets/app-icon.png" width="44" height="44" alt="Vocation SL logo" style="display:block;width:44px;height:44px;border-radius:12px;border:0;"></td><td style="vertical-align:middle;padding-left:12px;"><span style="font-size:22px;font-weight:bold;color:#FFFFFF;">Vocation <span style="color:#B9E07F;">SL</span></span></td></tr></table></td></tr>
<tr><td style="padding:28px 28px 20px;">
<p style="margin:0 0 12px;font-size:15px;line-height:1.6;">Hello,</p>
<p style="margin:0 0 12px;font-size:15px;line-height:1.6;">${esc(who)} has added you to the <b>${esc(company)}</b> hiring team on Vocation SL. You'll be able to post jobs, review candidates and message applicants.</p>
<p style="margin:0 0 18px;font-size:15px;line-height:1.6;">Create your account with this email address, <b>${esc(email)}</b>. You'll go straight to the ${esc(company)} dashboard. There is no company profile to set up.</p>
<p style="margin:0 0 18px;"><a href="${link}" style="display:inline-block;padding:11px 22px;border-radius:10px;background:#3F7A1F;font-size:15px;font-weight:bold;color:#FFFFFF;text-decoration:none;">Create your account</a></p>
<p style="margin:0;font-size:13px;line-height:1.6;color:#5E6670;">The button opens <b>Create account</b> with your email filled in. If you use <b>Continue with Google</b>, choose this same email address.</p>
</td></tr>
<tr><td style="padding:16px 28px;border-top:1px solid #E3E7E0;font-size:12px;line-height:1.6;color:#5E6670;">If you weren't expecting this, you can ignore this email. Nothing happens unless you create an account.<br>Vocation SL · VOCATION (SL) LIMITED · 33 New Koribondo Highway, Bo City, Sierra Leone · info@vocationsl.com</td></tr>
</table></td></tr></table></body></html>`;
  const text = [
    "Hello,", "",
    `${who} has added you to the ${company} hiring team on Vocation SL. You'll be able to post jobs, review candidates and message applicants.`, "",
    `Create your account with this email address (${email}): ${link}`,
    `You'll go straight to the ${company} dashboard; there is no company profile to set up. If you use "Continue with Google", choose this same email address.`, "",
    "If you weren't expecting this, you can ignore this email.",
    "Vocation SL · VOCATION (SL) LIMITED · 33 New Koribondo Highway, Bo City · info@vocationsl.com",
  ].join("\n");
  return { subject, html, text };
}

async function send(): Promise<Response> {
  const pass = Deno.env.get("SMTP_PASSWORD");
  if (!pass) return new Response("SMTP_PASSWORD is not set", { status: 500 });

  const { data: invites, error } = await supabase.from("team_invites")
    .select("email, token, company_id, invited_by, companies(name)")
    .is("emailed_at", null).gt("created_at", new Date(Date.now() - 2 * 86400000).toISOString())
    .order("created_at").limit(10);
  if (error) return new Response(error.message, { status: 500 });
  if (!invites?.length) return Response.json({ sent: 0 });

  const inviterIds = [...new Set(invites.map((i) => i.invited_by).filter(Boolean))];
  const { data: people } = inviterIds.length
    ? await supabase.from("profiles").select("id, full_name").in("id", inviterIds)
    : { data: [] };
  const names = new Map((people ?? []).map((p) => [p.id, p.full_name ?? ""]));

  const transport = nodemailer.createTransport({
    host: Deno.env.get("SMTP_HOST") ?? "smtp.hostinger.com",
    port: 465,
    secure: true,
    auth: { user: smtpUser, pass },
  });

  let sent = 0, failed = 0;
  for (const i of invites) {
    const company = (i.companies as unknown as { name: string } | null)?.name ?? "your company";
    const mail = render(company, names.get(i.invited_by) ?? "", i.email, i.token);
    try {
      await transport.sendMail({ from: { name: "Vocation SL", address: smtpUser }, to: i.email, ...mail });
      await supabase.from("team_invites").update({ emailed_at: new Date().toISOString(), email_error: null }).eq("email", i.email);
      sent++;
    } catch (e) {
      const msg = String((e as Error)?.message ?? e).replace(/\s+/g, " ").slice(0, 300);
      await supabase.from("team_invites").update({ email_error: msg }).eq("email", i.email);
      failed++;
    }
  }
  transport.close();
  return Response.json({ sent, failed });
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// The invited colleague creates their account from the invite link. Opening
// the link proves the email is theirs (the token was only sent there), so the
// account is created already confirmed: no confirmation email to wait for.
// The sign-up trigger then adds them to the company (team_invites.sql).
async function inviteSignUp(body: Record<string, unknown>): Promise<Response> {
  const reply = (ok: boolean, error?: string) => Response.json(ok ? { ok } : { ok, error }, { headers: cors });
  const email = String(body.email ?? "").trim().toLowerCase();
  const token = String(body.token ?? "");
  const password = String(body.password ?? "");
  const name = String(body.name ?? "").trim();
  if (!email || !/^[0-9a-f]{32}$/.test(token)) return reply(false, "This invite link is not valid. Ask your colleague to invite you again.");
  if (name.length < 2) return reply(false, "Enter your full name.");
  if (password.length < 8) return reply(false, "Use at least 8 characters for your password.");

  const { data: inv } = await supabase.from("team_invites").select("email, token, created_at").eq("email", email).maybeSingle();
  const fresh = inv && Date.now() - new Date(inv.created_at).getTime() < 30 * 86400000;
  if (!inv || inv.token !== token || !fresh) {
    return reply(false, "This invite has expired or was cancelled. Ask your colleague to invite you again.");
  }
  const { error } = await supabase.auth.admin.createUser({
    email, password, email_confirm: true,
    user_metadata: { full_name: name, role: "employer" },
  });
  if (error) {
    return reply(false, /already|registered|exists/i.test(error.message)
      ? "An account with this email already exists. Sign in instead, or tap \"Forgot password?\"."
      : error.message);
  }
  return reply(true);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers: cors });
  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  if (body.action === "signup") return inviteSignUp(body);
  if (!secret || req.headers.get("x-webhook-secret") !== secret) return new Response("Unauthorized", { status: 401 });
  return send();
});
