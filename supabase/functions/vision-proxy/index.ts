// supabase/functions/vision-proxy/index.ts
// FIXED: Restricted CORS, rate limiting (5 calls/min — Vision API is expensive).

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rateLimit.ts";

const GOOGLE_VISION_API_KEY = Deno.env.get("GOOGLE_VISION_API_KEY") ?? "";
const SUPABASE_URL          = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const MAX_IMAGE_BYTES = 10 * 1024 * 1024; // 10 MB
const RATE_LIMIT_CALLS_PER_MINUTE = 5;    // Vision API is expensive — keep low

// ── SECURITY FIX: Restrict CORS ───────────────────────────────────────────────
const ALLOWED_ORIGINS = [
  "https://swasthall.com",
  "https://app.swasthall.com",
  "capacitor://localhost",
  "http://localhost:3000",
];

function corsHeaders(requestOrigin: string | null): Record<string, string> {
  const origin = ALLOWED_ORIGINS.includes(requestOrigin ?? "")
    ? (requestOrigin as string)
    : ALLOWED_ORIGINS[0];
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

serve(async (req) => {
  const requestOrigin = req.headers.get("Origin");
  const headers = corsHeaders(requestOrigin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers });
  }

  try {
    // ── 1. Verify JWT ─────────────────────────────────────────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization." }), {
        status: 401, headers: { ...headers, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token." }), {
        status: 401, headers: { ...headers, "Content-Type": "application/json" },
      });
    }

    // ── 2. Rate limit ─────────────────────────────────────────────────────────
    const { allowed, remaining } = await checkRateLimit(
      supabase, user.id, "vision-proxy", RATE_LIMIT_CALLS_PER_MINUTE
    );

    if (!allowed) {
      return new Response(JSON.stringify({ error: "Rate limit exceeded. Try again in a minute." }), {
        status: 429,
        headers: { ...headers, "Content-Type": "application/json", "Retry-After": "60" },
      });
    }

    // ── 3. Parse & size-check image ───────────────────────────────────────────
    const body = await req.json();
    const imageBase64: string = body.imageBase64 ?? "";

    if (!imageBase64) {
      return new Response(JSON.stringify({ error: "No image provided." }), {
        status: 400, headers: { ...headers, "Content-Type": "application/json" },
      });
    }

    const estimatedBytes = Math.ceil((imageBase64.length * 3) / 4);
    if (estimatedBytes > MAX_IMAGE_BYTES) {
      return new Response(
        JSON.stringify({ error: "Image too large. Maximum size is 10 MB." }),
        { status: 413, headers: { ...headers, "Content-Type": "application/json" } }
      );
    }

    // ── 4. Call Google Vision API ─────────────────────────────────────────────
    const visionUrl = `https://vision.googleapis.com/v1/images:annotate?key=${GOOGLE_VISION_API_KEY}`;

    const visionRes = await fetch(visionUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        requests: [{
          image: { content: imageBase64 },
          features: [{ type: "DOCUMENT_TEXT_DETECTION" }],
        }],
      }),
    });

    if (!visionRes.ok) {
      const errText = await visionRes.text();
      console.error("Vision API error:", errText);
      return new Response(JSON.stringify({ error: "Vision service error." }), {
        status: 502, headers: { ...headers, "Content-Type": "application/json" },
      });
    }

    const visionData = await visionRes.json();
    const text: string | undefined =
      visionData?.responses?.[0]?.fullTextAnnotation?.text;

    return new Response(JSON.stringify({ text: text ?? null }), {
      status: 200,
      headers: {
        ...headers,
        "Content-Type": "application/json",
        "X-RateLimit-Remaining": remaining.toString(),
      },
    });

  } catch (err) {
    console.error("vision-proxy error:", err);
    return new Response(JSON.stringify({ error: "Internal server error." }), {
      status: 500, headers: { ...corsHeaders(req.headers.get("Origin")), "Content-Type": "application/json" },
    });
  }
});
