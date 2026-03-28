import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ─── FCM V1 push for incoming web calls ───────────────────────────────────────
// Uses FCM HTTP V1 API with service account OAuth2 token.
// Legacy API was deprecated — V1 is the current standard.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { callee_id, caller_id, caller_name, channel_name, booking_id, source } = await req.json();

    if (!callee_id || !channel_name) {
      return new Response(JSON.stringify({ error: "callee_id and channel_name required" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── Get patient FCM token from profiles ───────────────────────────────
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: profile } = await supabase
      .from("profiles")
      .select("fcm_token")
      .eq("id", callee_id)
      .maybeSingle();

    if (!profile?.fcm_token) {
      console.log(`No FCM token for callee ${callee_id}`);
      return new Response(JSON.stringify({ sent: false, reason: "no_fcm_token" }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── Get OAuth2 access token from service account ──────────────────────
    const serviceAccountStr = Deno.env.get("FCM_SERVICE_ACCOUNT")!;
    const serviceAccount    = JSON.parse(serviceAccountStr);
    const projectId         = serviceAccount.project_id;
    const accessToken       = await getAccessToken(serviceAccount);

    // ── Send via FCM V1 API ───────────────────────────────────────────────
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    const callerLabel = caller_name ?? "Doctor";

    const message = {
      message: {
        token: profile.fcm_token,
        // notification: shows a system tray notification when app is killed
        // User taps it → app opens → onMessageOpenedApp fires → call dialog shown
        notification: {
          title: `Incoming call`,
          body:  `${callerLabel} is calling you`,
        },
        data: {
          type:         "incoming_call",
          source:       source ?? "web",   // 'web' or 'zego' — tells app which UI to show
          show_call_ui: (source === 'web' || source == null) ? "true" : "false",
          caller_name:  callerLabel,
          caller_id:    caller_id ?? "",
          channel_name: channel_name,
          booking_id:   booking_id ?? "",
          callee_id:    callee_id,
        },
        android: {
          priority: "high",
          notification: {
            channel_id:   "Swasthall_Call_v1",   // matches your ZEGO channel
            default_sound: true,
            default_vibrate_timings: true,
          },
        },
        apns: {
          headers: { "apns-priority": "10" },
        },
      },
    };

    const fcmRes  = await fetch(fcmUrl, {
      method:  "POST",
      headers: {
        "Content-Type":  "application/json",
        "Authorization": `Bearer ${accessToken}`,
      },
      body: JSON.stringify(message),
    });

    const fcmData = await fcmRes.json();
    console.log(`FCM V1 response for ${callee_id}:`, JSON.stringify(fcmData));

    return new Response(JSON.stringify({ sent: fcmRes.ok, fcm: fcmData }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err) {
    console.error("notify-incoming-call error:", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// ── Generate OAuth2 access token from service account ─────────────────────────
async function getAccessToken(sa: Record<string, string>): Promise<string> {
  const now     = Math.floor(Date.now() / 1000);
  const payload = {
    iss:   sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud:   "https://oauth2.googleapis.com/token",
    iat:   now,
    exp:   now + 3600,
  };

  // Encode JWT header + payload
  const header    = { alg: "RS256", typ: "JWT" };
  const headerB64 = btoa(JSON.stringify(header)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
  const payloadB64 = btoa(JSON.stringify(payload)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
  const signingInput = `${headerB64}.${payloadB64}`;

  // Import the RSA private key
  const pemKey  = sa.private_key.replace(/\\n/g, "\n");
  const keyData = pemToArrayBuffer(pemKey);

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  // Sign
  const encoder   = new TextEncoder();
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    encoder.encode(signingInput)
  );

  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const jwt = `${signingInput}.${sigB64}`;

  // Exchange JWT for access token
  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method:  "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body:    `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  const tokenData = await tokenRes.json();
  if (!tokenData.access_token) throw new Error(`Token error: ${JSON.stringify(tokenData)}`);
  return tokenData.access_token;
}

// ── PEM to ArrayBuffer ─────────────────────────────────────────────────────────
function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\n/g, "");
  const binary = atob(b64);
  const buffer = new ArrayBuffer(binary.length);
  const view   = new Uint8Array(buffer);
  for (let i = 0; i < binary.length; i++) view[i] = binary.charCodeAt(i);
  return buffer;
}
