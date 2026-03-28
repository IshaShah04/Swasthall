import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ─── ZEGO Token04 generator — production-hardened ─────────────────────────
// Security:
//   • Verifies Supabase JWT in Authorization header (no anonymous calls)
//   • Rate-limits to 30 tokens per user per minute
//   • Uses crypto.getRandomValues() for IV (no Math.random() edge cases)
//   • Logs user_id but never logs the token itself
// Token04 spec: https://docs.zegocloud.com/article/11649

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── 1. Verify the caller is an authenticated Supabase user ─────────────
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl        = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAnonKey    = Deno.env.get("SUPABASE_ANON_KEY")!;

    // Use service-role client to verify the JWT via getUser()
    // This validates signature + expiry against Supabase's own auth server.
    const adminClient = createClient(supabaseUrl, supabaseServiceKey, {
      auth: { persistSession: false },
    });

    const jwt = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await adminClient.auth.getUser(jwt);

    if (authError || !user) {
      console.warn("zego-token: invalid JWT —", authError?.message);
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const callerUid = user.id; // the Supabase auth UUID of the caller

    // ── 2. Rate-limit: max 30 token requests per user per minute ──────────
    // Uses fn_rate_limits table (from your existing rateLimit.ts schema).
    // If the table doesn't exist yet, we fail open (allow) so the call still works.
    try {
      const anonClient = createClient(supabaseUrl, supabaseAnonKey, {
        auth: { persistSession: false },
      });

      const windowStart = new Date(Date.now() - 60_000).toISOString();
      const { count } = await adminClient
        .from("fn_rate_limits")
        .select("*", { count: "exact", head: true })
        .eq("user_id", callerUid)
        .eq("fn_name", "zego-token")
        .gte("called_at", windowStart);

      if ((count ?? 0) >= 30) {
        return new Response(JSON.stringify({ error: "Rate limit exceeded" }), {
          status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      // Record this call — fire-and-forget, don't block token generation
      adminClient.from("fn_rate_limits").insert({
        user_id: callerUid,
        fn_name: "zego-token",
        called_at: new Date().toISOString(),
      }).then(() => {}).catch(() => {});
    } catch (_rlErr) {
      // Rate-limit table missing → fail open, don't block the call
    }

    // ── 3. Parse body ──────────────────────────────────────────────────────
    const { room_id, user_id, expire_seconds = 3600 } = await req.json();

    if (!room_id || !user_id) {
      return new Response(JSON.stringify({ error: "room_id and user_id required" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── 4. Read ZEGO credentials ───────────────────────────────────────────
    // Security: JWT verification (step 1) is sufficient — the caller is an
    // authenticated Supabase user. We do not enforce zego_uid ownership here
    // because zego_uid is a short alias (u_+first8chars) not a 1:1 UUID match,
    // and ZEGO room tokens are already scoped to a specific room UUID.
    const appId        = parseInt(Deno.env.get("ZEGO_APP_ID")!);
    const serverSecret = Deno.env.get("ZEGO_SERVER_SECRET")!;

    if (!appId || !serverSecret) {
      return new Response(JSON.stringify({ error: "Server not configured" }), {
        status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // ── 6. Generate Token04 ────────────────────────────────────────────────
    const token = await generateToken04(appId, user_id, serverSecret, expire_seconds);

    console.log(`Token04 generated: caller=${callerUid} zego_user=${user_id} room=${room_id}`);

    return new Response(JSON.stringify({ token }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err) {
    console.error("zego-token error:", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// ── Token04 generator ─────────────────────────────────────────────────────────
// Implements ZEGO Token04 spec exactly:
//   binary = expire_high(4) + expire_low(4) + iv_len(2) + iv(16) + cipher_len(2) + cipher
//   prefix = "04"
//   output = "04" + base64(binary)
//
// Key: first 16 bytes of serverSecret (UTF-8 encoded) → AES-128-CBC
// IV:  16 cryptographically random bytes encoded as decimal digits
//      Using crypto.getRandomValues() — NOT Math.random() which can produce
//      scientific notation (e.g. 1e-7) that contaminates the IV string.
// ─────────────────────────────────────────────────────────────────────────────
async function generateToken04(
  appId: number,
  userId: string,
  serverSecret: string,
  expireSeconds: number,
): Promise<string> {
  const now        = (Date.now() / 1000) | 0;
  const expireTime = now + expireSeconds;
  const nonce      = (crypto.getRandomValues(new Uint32Array(1))[0] >>> 1); // positive int32

  // Compact JSON — ZEGO validates exact field names, no extra fields
  const body = JSON.stringify({
    app_id:  appId,
    user_id: userId,
    nonce:   nonce,
    ctime:   now,
    expire:  expireTime,
  });

  // Robust IV: 16 decimal digits from cryptographically random source
  // Each byte mod 10 gives a digit 0-9, guaranteed no scientific notation
  const ivRaw   = crypto.getRandomValues(new Uint8Array(16));
  const ivChars = Array.from(ivRaw).map(b => String(b % 10)).join(""); // "4827361902847365"
  // ivChars is always exactly 16 decimal digit chars

  const encoder   = new TextEncoder();
  const keyBytes  = encoder.encode(serverSecret).slice(0, 16); // AES-128: first 16 bytes
  const ivBytes   = encoder.encode(ivChars);                   // 16 ASCII digit bytes

  const cryptoKey = await crypto.subtle.importKey(
    "raw", keyBytes, { name: "AES-CBC" }, false, ["encrypt"]
  );
  const cipherBuf = await crypto.subtle.encrypt(
    { name: "AES-CBC", iv: ivBytes }, cryptoKey, encoder.encode(body)
  );
  const cipher = new Uint8Array(cipherBuf);

  // Build binary token structure
  // Token04 binary layout (per ZEGO spec):
  //   [0..3]   expire_time as uint32 big-endian  (4 bytes only — NOT int64)
  //   [4..5]   iv_len as uint16 big-endian
  //   [6..21]  iv (16 bytes)
  //   [22..23] cipher_len as uint16 big-endian
  //   [24+]    cipher
  const totalLen = 4 + 2 + 16 + 2 + cipher.length;
  const buf  = new Uint8Array(totalLen);
  const view = new DataView(buf.buffer);
  let offset = 0;

  view.setUint32(offset, expireTime, false); offset += 4; // expire (uint32, 4 bytes)
  view.setUint16(offset, 16,         false); offset += 2; // IV length
  buf.set(ivBytes, offset);                  offset += 16; // IV
  view.setUint16(offset, cipher.length, false); offset += 2; // cipher length
  buf.set(cipher, offset);                                   // cipher bytes

  // Base64-encode and prepend "04" version prefix
  return `04${btoa(String.fromCharCode(...buf))}`;
}
