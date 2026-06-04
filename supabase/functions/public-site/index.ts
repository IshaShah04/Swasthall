import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const PUBLIC_SITE_API_SALT = Deno.env.get("PUBLIC_SITE_API_SALT") ?? "change-this-salt-now";
const APK_URL =
  Deno.env.get("APK_URL") ??
  "https://github.com/RaunakShah29/swasthall-pay/releases/download/v1.0.0/Swasthall-v1.0.0-pilot.apk";
const AUTO_APPROVE_FEEDBACK = Deno.env.get("AUTO_APPROVE_FEEDBACK") === "true";

const allowedOrigins = new Set([
  "https://www.swasthall.com",
  "https://swasthall.com",
  "http://localhost:3000",
  "http://127.0.0.1:5500",
]);

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});

function corsHeaders(origin: string | null): HeadersInit {
  const allowOrigin = origin && allowedOrigins.has(origin)
    ? origin
    : "https://www.swasthall.com";

  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Vary": "Origin",
  };
}

function jsonResponse(body: unknown, status = 200, origin: string | null = null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(origin),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

function getEndpoint(req: Request) {
  const pathParts = new URL(req.url).pathname.split("/").filter(Boolean);
  return pathParts[pathParts.length - 1] || "";
}

function getClientIp(req: Request) {
  const forwardedFor = req.headers.get("x-forwarded-for");
  if (forwardedFor) return forwardedFor.split(",")[0].trim();

  return (
    req.headers.get("cf-connecting-ip") ||
    req.headers.get("x-real-ip") ||
    "unknown"
  );
}

async function sha256Hex(input: string) {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function getIpHash(req: Request) {
  return await sha256Hex(`${PUBLIC_SITE_API_SALT}:${getClientIp(req)}`);
}

async function checkRateLimit(
  eventKey: string,
  ipHash: string,
  limit: number,
  windowSeconds: number,
) {
  const { data, error } = await supabase.rpc("bump_website_rate_limit", {
    p_event_key: eventKey,
    p_ip_hash: ipHash,
    p_limit: limit,
    p_window_seconds: windowSeconds,
  });

  if (error) {
    console.error("rate limit error", error);
    return false;
  }

  return data === true;
}

function cleanText(value: unknown, maxLength: number) {
  if (typeof value !== "string") return null;
  const cleaned = value.replace(/\s+/g, " ").trim().slice(0, maxLength);
  return cleaned.length ? cleaned : null;
}

function cleanRole(value: unknown) {
  const allowed = new Set([
    "patient",
    "doctor",
    "nurse",
    "hospital_admin",
    "other",
  ]);

  return typeof value === "string" && allowed.has(value) ? value : null;
}

Deno.serve(async (req) => {
  const origin = req.headers.get("origin");

  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return jsonResponse(
      { error: "Server is not configured." },
      500,
      origin,
    );
  }

  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders(origin),
    });
  }

  const endpoint = getEndpoint(req);

  try {
    if (endpoint === "reviews" && req.method === "GET") {
      const { data, error } = await supabase.rpc("get_public_app_feedback", {
        p_limit: 20,
      });

      if (error) throw error;

      return jsonResponse(data ?? [], 200, origin);
    }

    if (endpoint === "download-count" && req.method === "GET") {
      const { data, error } = await supabase.rpc("get_download_count");

      if (error) throw error;

      return jsonResponse({ count: Number(data ?? 0) }, 200, origin);
    }

    if (endpoint === "feedback" && req.method === "POST") {
      const ipHash = await getIpHash(req);

      const allowed = await checkRateLimit("feedback", ipHash, 5, 60 * 60);
      if (!allowed) {
        return jsonResponse(
          { error: "Too many feedback attempts. Try again later." },
          429,
          origin,
        );
      }

      const body = await req.json().catch(() => null);

      const rating = Number(body?.rating);
      if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
        return jsonResponse({ error: "Invalid rating." }, 400, origin);
      }

      const name = cleanText(body?.name, 60) ?? "Anonymous";
      const role = cleanRole(body?.role);
      const comment = cleanText(body?.comment, 600);
      const userAgent = cleanText(req.headers.get("user-agent"), 300);

      const { error } = await supabase.from("app_feedback").insert({
        rating,
        name,
        role,
        comment,
        ip_hash: ipHash,
        user_agent: userAgent,
        source: "website",
        status: AUTO_APPROVE_FEEDBACK ? "approved" : "pending",
        is_public: AUTO_APPROVE_FEEDBACK,
      });

      if (error) throw error;

      return jsonResponse(
        {
          ok: true,
          status: AUTO_APPROVE_FEEDBACK ? "approved" : "pending",
        },
        201,
        origin,
      );
    }

    if (endpoint === "download" && req.method === "GET") {
      const ipHash = await getIpHash(req);
      const userAgent = cleanText(req.headers.get("user-agent"), 300);

      const shouldCount = await checkRateLimit("download", ipHash, 30, 60 * 60);

      if (shouldCount) {
        const { error } = await supabase.from("app_downloads").insert({
          source: "website",
          version: "v1.0.0",
          ip_hash: ipHash,
          user_agent: userAgent,
        });

        if (error) {
          console.error("download insert error", error);
        }
      }

      return Response.redirect(APK_URL, 302);
    }

    return jsonResponse(
      {
        ok: true,
        service: "swasthall-public-site",
        endpoints: ["/reviews", "/download-count", "/feedback", "/download"],
      },
      200,
      origin,
    );
  } catch (error) {
    console.error("public-site function error", error);

    return jsonResponse(
      { error: "Something went wrong." },
      500,
      origin,
    );
  }
});
