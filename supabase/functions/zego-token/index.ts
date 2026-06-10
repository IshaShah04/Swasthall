import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rateLimit.ts";
import { requireString, requireUUID, handleValidationError } from '../_shared/validate.ts';

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

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

async function getBookingForRoom(admin: ReturnType<typeof createClient>, roomId: string): Promise<BookingRow | null> {
  const selectCols = "id,patient_id,user_id,provider_id,staff_id,doctor_id,hospital_id,room_id,status,is_expired";

  const { data: byRoom, error: roomError } = await admin
    .from("bookings")
    .select(selectCols)
    .eq("room_id", roomId)
    .limit(1)
    .maybeSingle();

  if (roomError) throw new Error(roomError.message);
  if (byRoom) return byRoom as BookingRow;

  if (isUuid(roomId)) {
    const { data: byId, error: idError } = await admin
      .from("bookings")
      .select(selectCols)
      .eq("id", roomId)
      .limit(1)
      .maybeSingle();

    if (idError) throw new Error(idError.message);
    if (byId) return byId as BookingRow;
  }

  return null;
}

async function isUserLinkedToBooking(
  admin: ReturnType<typeof createClient>,
  userId: string,
  booking: BookingRow,
): Promise<boolean> {
  const directIds = [
    booking.patient_id,
    booking.user_id,
    booking.provider_id,
    booking.staff_id,
    booking.doctor_id,
    booking.hospital_id,
  ].filter(Boolean);

  if (directIds.includes(userId)) return true;

  const { data: staffRows, error: staffError } = await admin
    .from("staff")
    .select("id,hospital_id,user_id,profile_id,doctor_id,nurse_id,technician_id,pharmacist_id")
    .or(`user_id.eq.${userId},profile_id.eq.${userId},id.eq.${userId}`)
    .limit(5);

  if (staffError) throw new Error(staffError.message);

  for (const row of staffRows ?? []) {
    if (booking.hospital_id && row.hospital_id === booking.hospital_id) return true;
    if ([booking.provider_id, booking.staff_id, booking.doctor_id].includes(row.id)) return true;
    if ([booking.provider_id, booking.staff_id, booking.doctor_id].includes(row.doctor_id)) return true;
    if ([booking.provider_id, booking.staff_id, booking.doctor_id].includes(row.nurse_id)) return true;
    if ([booking.provider_id, booking.staff_id, booking.doctor_id].includes(row.technician_id)) return true;
    if ([booking.provider_id, booking.staff_id, booking.doctor_id].includes(row.pharmacist_id)) return true;
  }

  return false;
}

function clampExpireSeconds(value: unknown): number {
  const n = Number(value ?? 1800);
  if (!Number.isFinite(n)) return 1800;
  return Math.min(Math.max(Math.floor(n), 300), 3600);
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) return json({ error: "Missing Authorization header" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const authClient = createClient(supabaseUrl, supabaseAnonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: authHeader } },
    });
    const admin = createClient(supabaseUrl, supabaseServiceKey, { auth: { persistSession: false } });

    const { data: { user }, error: authError } = await authClient.auth.getUser();
    if (authError || !user) return json({ error: "Unauthorized" }, 401);

    const rl = await checkRateLimit(admin, user.id, "zego-token", 30);
    if (!rl.allowed) return json({ error: "Rate limit exceeded" }, 429);

    let roomId: string;
    let zegoUserId: string;
    let expire_seconds: number;
    try {
      const body = await req.json().catch(() => ({}));
      roomId = requireString(body.room_id, 'room_id');
      zegoUserId = requireString(body.user_id, 'user_id');
      expire_seconds = body.expire_seconds ?? 1800;
    } catch (err) {
      return handleValidationError(err);
    }

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("zego_uid")
      .eq("id", user.id)
      .maybeSingle();

    if (profileError) throw new Error(profileError.message);
    if (!profile?.zego_uid || profile.zego_uid !== zegoUserId) {
      return json({ error: "Unauthorized ZEGO user_id" }, 403);
    }

    const booking = await getBookingForRoom(admin, roomId);
    if (!booking) return json({ error: "Call room not found" }, 404);

    const blockedStatuses = new Set(["cancelled", "failed", "missed", "expired"]);
    if (booking.is_expired || blockedStatuses.has(String(booking.status ?? "").toLowerCase())) {
      return json({ error: "Booking is not active" }, 403);
    }

    const allowed = await isUserLinkedToBooking(admin, user.id, booking);
    if (!allowed) return json({ error: "Unauthorized for this call room" }, 403);

    const appId = parseInt(Deno.env.get("ZEGO_APP_ID") ?? "", 10);
    const serverSecret = Deno.env.get("ZEGO_SERVER_SECRET") ?? "";
    if (!appId || !serverSecret) return json({ error: "Server not configured" }, 500);

    const token = await generateToken04(appId, zegoUserId, serverSecret, clampExpireSeconds(expire_seconds));
    console.log(`Token04 generated: caller=${user.id} zego_user=${zegoUserId} room=${roomId} booking=${booking.id}`);

    return json({ token });
  } catch (err) {
    console.error("zego-token error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

async function generateToken04(
  appId: number,
  userId: string,
  serverSecret: string,
  expireSeconds: number,
): Promise<string> {
  const now = (Date.now() / 1000) | 0;
  const expireTime = now + expireSeconds;
  const nonce = (crypto.getRandomValues(new Uint32Array(1))[0] >>> 1);

  const body = JSON.stringify({ app_id: appId, user_id: userId, nonce, ctime: now, expire: expireTime });
  const ivRaw = crypto.getRandomValues(new Uint8Array(16));
  const ivChars = Array.from(ivRaw).map((b) => String(b % 10)).join("");
  const encoder = new TextEncoder();
  const keyBytes = encoder.encode(serverSecret).slice(0, 16);
  const ivBytes = encoder.encode(ivChars);

  const cryptoKey = await crypto.subtle.importKey("raw", keyBytes, { name: "AES-CBC" }, false, ["encrypt"]);
  const cipherBuf = await crypto.subtle.encrypt({ name: "AES-CBC", iv: ivBytes }, cryptoKey, encoder.encode(body));
  const cipher = new Uint8Array(cipherBuf);

  const totalLen = 4 + 2 + 16 + 2 + cipher.length;
  const buf = new Uint8Array(totalLen);
  const view = new DataView(buf.buffer);
  let offset = 0;
  view.setUint32(offset, expireTime, false); offset += 4;
  view.setUint16(offset, 16, false); offset += 2;
  buf.set(ivBytes, offset); offset += 16;
  view.setUint16(offset, cipher.length, false); offset += 2;
  buf.set(cipher, offset);

  return `04${btoa(String.fromCharCode(...buf))}`;
}
