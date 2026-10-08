// Vocation SL — "push" Edge Function.
//
// Called by the database (supabase/push_schema.sql) for every new alert.
// Sends it to the user's phones and browsers with Firebase Cloud Messaging,
// and forgets devices that have uninstalled the app or blocked alerts.
//
// Secrets (Supabase → Edge Functions → Secrets):
//   PUSH_WEBHOOK_SECRET        any long random text; the same value goes in private.push_config
//   FIREBASE_SERVICE_ACCOUNT   the whole JSON file from Firebase → Project settings → Service accounts
//   SITE_URL                   https://vocation-sl-app.vercel.app
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.

import { createClient } from "jsr:@supabase/supabase-js@2";

type Payload = {
  user_id: string;
  title: string;
  body: string;
  type: string;
  notification_id: string;
  application_id: string | null;
  job_id: string | null;
  route: string;
};

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const account: ServiceAccount = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "{}");
const site = (Deno.env.get("SITE_URL") ?? "").replace(/\/$/, "");

let cachedToken: { value: string; expires: number } | null = null;

function base64url(data: ArrayBuffer | string): string {
  const bytes = typeof data === "string" ? new TextEncoder().encode(data) : new Uint8Array(data);
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** OAuth access token for the FCM HTTP v1 API, from the service account. */
async function accessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expires > now + 60) return cachedToken.value;

  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = account.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${header}.${claims}`));
  const jwt = `${header}.${claims}.${base64url(signature)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  if (!res.ok) throw new Error(`Google token request failed: ${res.status} ${await res.text()}`);
  const json = await res.json();
  cachedToken = { value: json.access_token, expires: now + (json.expires_in ?? 3600) };
  return cachedToken.value;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  if (req.headers.get("x-webhook-secret") !== Deno.env.get("PUSH_WEBHOOK_SECRET")) {
    return new Response("Unauthorized", { status: 401 });
  }
  if (!account.project_id) return new Response("FIREBASE_SERVICE_ACCOUNT is not set", { status: 500 });

  const p: Payload = await req.json();
  const { data: devices, error } = await supabase.from("push_tokens").select("token, platform").eq("user_id", p.user_id);
  if (error) return new Response(error.message, { status: 500 });
  if (!devices?.length) return Response.json({ sent: 0 });

  const auth = await accessToken();
  const link = `${site}/#${p.route}`;
  const data = {
    route: p.route,
    type: p.type,
    notification_id: String(p.notification_id ?? ""),
    application_id: p.application_id ?? "",
    job_id: p.job_id ?? "",
  };

  let sent = 0;
  const stale: string[] = [];
  await Promise.all(devices.map(async (d) => {
    const message = {
      token: d.token,
      notification: { title: p.title, body: p.body },
      data,
      android: {
        priority: "high",
        notification: { icon: "ic_stat_notify", color: "#3F7A1F", tag: data.notification_id || undefined },
      },
      webpush: {
        fcm_options: { link },
        notification: { icon: `${site}/icons/Icon-192.png`, badge: `${site}/icons/Icon-192.png` },
      },
    };
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${auth}`, "Content-Type": "application/json" },
      body: JSON.stringify({ message }),
    });
    if (res.ok) {
      sent++;
      return;
    }
    const text = await res.text();
    // The device uninstalled the app, cleared site data or blocked alerts.
    if (res.status === 404 || text.includes("UNREGISTERED") || text.includes("registration-token-not-registered") ||
        (res.status === 400 && text.includes("registration token"))) {
      stale.push(d.token);
    } else {
      console.error(`FCM ${res.status}: ${text}`);
    }
  }));

  if (stale.length) await supabase.from("push_tokens").delete().in("token", stale);
  return Response.json({ sent, removed: stale.length });
});
