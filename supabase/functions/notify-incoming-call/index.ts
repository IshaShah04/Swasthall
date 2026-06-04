import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rateLimit.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type BookingRow = {
  id: string;
  patient_id: string | null;
  user_id: string | null;
  provider_id: string | null;
  staff_id: string | null;
  doctor_id: string | null;
  hospital_id: string | null;
  room_id: string | null;
  status: string | null;
  is_expired: boolean | null;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

function isParticipant(userId: string, booking: BookingRow): boolean {
  return [
    booking.patient_id,
    booking.user_id,
    booking.provider_id,
    booking.staff_id,
    booking.doctor_id,
    booking.hospital_id,
  ].filter(Boolean).includes(userId);
}

async function isStaffLinked(admin: ReturnType<typeof createClient>, userId: string, booking: BookingRow): Promise<boolean> {
  const { data, error } = await admin
    .from("staff")
    .select("id,hospital_id,user_id,profile_id,doctor_id,nurse_id,technician_id,pharmacist_id")
    .or(`user_id.eq.${userId},profile_id.eq.${userId},id.eq.${userId}`)
    .limit(5);
  if (error) throw new Error(error.message);

  for (const row of data ?? []) {
    if (booking.hospital_id && row.hospital_id === booking.hospital_id) return true;
    if ([booking.provider_id, booking.staff_id, booking.doctor_id].includes(row.id)) return true;
    if ([booking.provider_id, booking.staff_id, booking.doctor_id].includes(row.doctor_id)) return true;
    if ([booking.provider_id, booking.staff_id, booking.doctor_id].includes(row.nurse_id)) return true;
    if ([booking.provider_id, booking.staff_id, booking.doctor_id].includes(row.technician_id)) return true;
    if ([booking.provider_id, booking.staff_id, booking.doctor_id].includes(row.pharmacist_id)) return true;
  }
  return false;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) return json({ error: "Missing Authorization header" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const authClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: authHeader } },
    });
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

    const { data: { user }, error: authError } = await authClient.auth.getUser();
    if (authError || !user) return json({ error: "Unauthorized" }, 401);

    const rl = await checkRateLimit(admin, user.id, "notify-incoming-call", 60);
    if (!rl.allowed) return json({ error: "Rate limit exceeded" }, 429);

    const body = await req.json().catch(() => ({}));
    const calleeId = String(body.callee_id ?? "").trim();
    const channelName = String(body.channel_name ?? "").trim();
    const bookingId = String(body.booking_id ?? "").trim();
    const callerName = String(body.caller_name ?? "Doctor").trim().slice(0, 80) || "Doctor";
    const source = String(body.source ?? "web").trim().slice(0, 20) || "web";

    if (!calleeId || !channelName || !bookingId) {
      return json({ error: "callee_id, channel_name and booking_id are required" }, 400);
    }

    const { data: booking, error: bookingError } = await admin
      .from("bookings")
      .select("id,patient_id,user_id,provider_id,staff_id,doctor_id,hospital_id,room_id,status,is_expired")
      .eq("id", bookingId)
      .maybeSingle();
    if (bookingError) throw new Error(bookingError.message);
    if (!booking) return json({ error: "Booking not found" }, 404);

    const row = booking as BookingRow;
    const blockedStatuses = new Set(["cancelled", "failed", "missed", "expired"]);
    if (row.is_expired || blockedStatuses.has(String(row.status ?? "").toLowerCase())) {
      return json({ error: "Booking is not active" }, 403);
    }

    if (row.room_id && row.room_id !== channelName) {
      return json({ error: "channel_name does not match booking room" }, 403);
    }

    const calleeIsParticipant = isParticipant(calleeId, row);
    if (!calleeIsParticipant) return json({ error: "callee_id is not linked to this booking" }, 403);

    const callerAllowed = isParticipant(user.id, row) || await isStaffLinked(admin, user.id, row);
    if (!callerAllowed) return json({ error: "Unauthorized for this booking" }, 403);

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("fcm_token")
      .eq("id", calleeId)
      .maybeSingle();
    if (profileError) throw new Error(profileError.message);

    if (!profile?.fcm_token) return json({ sent: false, reason: "no_fcm_token" });

    const serviceAccount = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT")!);
    const projectId = serviceAccount.project_id;
    const accessToken = await getAccessToken(serviceAccount);

    const fcmRes = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${accessToken}` },
      body: JSON.stringify({
        message: {
          token: profile.fcm_token,
          notification: { title: "Incoming call", body: `${callerName} is calling you` },
          data: {
            type: "incoming_call",
            source,
            show_call_ui: source === "web" ? "true" : "false",
            caller_name: callerName,
            caller_id: user.id,
            channel_name: channelName,
            booking_id: row.id,
            callee_id: calleeId,
          },
          android: {
            priority: "high",
            notification: { channel_id: "Swasthall_Call_v1", default_sound: true, default_vibrate_timings: true },
          },
          apns: { headers: { "apns-priority": "10" } },
        },
      }),
    });

    const fcmData = await fcmRes.json().catch(() => ({}));
    console.log(`notify-incoming-call: caller=${user.id} callee=${calleeId} booking=${row.id} sent=${fcmRes.ok}`);

    return json({ sent: fcmRes.ok, fcm_status: fcmRes.status, fcm: fcmData });
  } catch (err) {
    console.error("notify-incoming-call error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

async function getAccessToken(sa: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const payload = { iss: sa.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 };
  const header = { alg: "RS256", typ: "JWT" };
  const headerB64 = base64Url(JSON.stringify(header));
  const payloadB64 = base64Url(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;
  const pemKey = sa.private_key.replace(/\\n/g, "\n");
  const keyData = pemToArrayBuffer(pemKey);
  const cryptoKey = await crypto.subtle.importKey("pkcs8", keyData, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", cryptoKey, new TextEncoder().encode(signingInput));
  const jwt = `${signingInput}.${base64UrlBytes(new Uint8Array(signature))}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const tokenData = await tokenRes.json();
  if (!tokenData.access_token) throw new Error("FCM OAuth token error");
  return tokenData.access_token;
}

function base64Url(input: string): string {
  return btoa(input).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function base64UrlBytes(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----BEGIN PRIVATE KEY-----/, "").replace(/-----END PRIVATE KEY-----/, "").replace(/\n/g, "");
  const binary = atob(b64);
  const buffer = new ArrayBuffer(binary.length);
  const view = new Uint8Array(buffer);
  for (let i = 0; i < binary.length; i++) view[i] = binary.charCodeAt(i);
  return buffer;
}
