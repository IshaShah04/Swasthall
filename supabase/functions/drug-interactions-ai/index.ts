// supabase/functions/drug-interactions-ai/index.ts
//
// AI-powered drug interaction checker using Gemini's medical knowledge.
// Called after local JSON + Supabase checks as the authoritative fallback.
//
// Input:  { medicines: ["paracetamol", "warfarin", "amoxicillin"] }
// Output: { interactions: [ { drugA, drugB, severity, effect,
//            mechanism, action, monitoring, alternative, onset } ] }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── CORS ─────────────────────────────────────────────────────────────────────
const ALLOWED_ORIGINS = [
  "https://swasthall.com",
  "https://www.swasthall.com",
  "http://localhost:3000",
];

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin");
  const allowedOrigin = !origin || ALLOWED_ORIGINS.includes(origin)
    ? (origin ?? "*")
    : "null";
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

// ── Rate limit ────────────────────────────────────────────────────────────────
// Max 20 AI interaction checks per user per 60 seconds.
// Slightly higher than OCR since this is text-only (cheaper, faster).
const RATE_MAX = 20;
const RATE_WINDOW_MS = 60_000;

// ── Models ────────────────────────────────────────────────────────────────────
const MODELS = [
  "gemini-2.5-flash",
  "gemini-2.5-flash-lite",
];

function buildPrompt(medicines: string[]): string {
  const sanitizeMedicine = (value: string) =>
    value.replace(/[\r\n\t]+/g, " ")
      .replace(/[^\w\s\-().,/'%+]/g, "")
      .trim()
      .slice(0, 100);
  const list = medicines.map((m, i) => `${i + 1}. ${sanitizeMedicine(m)}`).join("\n");
  return `You are a senior clinical pharmacist with expertise in drug interactions, referencing Stockley's Drug Interactions, Lexicomp, Micromedex, and WHO essential medicines guidelines.

A patient in Nepal has been prescribed these medicines:
${list}

Task: Identify ALL clinically significant interactions between every possible pair from the list above.

For each interaction found, classify severity as exactly one of:
- "contraindicated" — must never be combined
- "major" — potentially life-threatening, avoid combination
- "moderate" — significant effect, monitor closely or adjust dose
- "minor" — mild effect, usually manageable

Return ONLY a JSON object. No markdown. No preamble. Just JSON.

{
  "interactions": [
    {
      "drugA": "first drug name (use the name from the input list)",
      "drugB": "second drug name (use the name from the input list)",
      "severity": "contraindicated | major | moderate | minor",
      "effect": "What happens clinically — symptoms, lab changes, risks",
      "mechanism": "Why this interaction occurs pharmacokinetically or pharmacodynamically",
      "action": "Exact clinical recommendation: what the prescriber/patient should do",
      "monitoring": "What to monitor if combination is unavoidable (or null)",
      "alternative": "Safer substitute medicine if available (or null)",
      "onset": "How quickly the interaction develops e.g. rapid, delayed, within 24h (or null)"
    }
  ]
}

RULES:
- Only include pairs with a real, documented clinical interaction
- If no significant interactions exist, return {"interactions":[]}
- Be specific and clinically accurate — this will be shown to patients in Nepal
- Use generic names in effect/mechanism/action even if brand name was given in input
- Do NOT invent interactions that are not well-documented`;
}

serve(async (req) => {
  const cors = getCorsHeaders(req);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    // ── Auth ──────────────────────────────────────────────────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        { status: 401, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !supabaseAnonKey) {
      console.error("Missing Supabase environment configuration");
      return new Response(
        JSON.stringify({ interactions: [], error: "Service configuration error" }),
        { status: 500, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      supabaseUrl,
      supabaseAnonKey,
      { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } }
    );

    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    // ── Rate limit ────────────────────────────────────────────────────────────
    // This endpoint intentionally shares the same rolling window as the
    // prescription OCR flow by reading from prescription_scans. We do not
    // insert an additional tracking row here to avoid double-counting a single
    // user workflow when OCR is followed immediately by interaction analysis.
    const windowStart = new Date(Date.now() - RATE_WINDOW_MS).toISOString();
    const { count, error: countError } = await supabase
      .from("prescription_scans")
      .select("*", { count: "exact", head: true })
      .eq("patient_id", user.id)
      .gte("created_at", windowStart);

    if (countError) {
      console.error("Rate limit check failed for drug-interactions-ai:", countError);
      return new Response(
        JSON.stringify({ interactions: [], error: "Service temporarily unavailable" }),
        { status: 503, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    if ((count ?? 0) >= RATE_MAX) {
      console.warn(`Rate limit hit (interactions): count=${count}`);
      return new Response(
        JSON.stringify({ interactions: [], error: "Rate limit exceeded. Please wait a moment." }),
        { status: 429, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    // ── Body ──────────────────────────────────────────────────────────────────
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return new Response(
        JSON.stringify({ error: "Invalid JSON body" }),
        { status: 400, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    const medicines = Array.isArray(body.medicines) ? body.medicines : undefined;
    if (!medicines || medicines.length < 2) {
      return new Response(
        JSON.stringify({ interactions: [] }),
        { status: 200, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    // Sanitize — keep only strings, strip blanks, limit to 8 medicines max
    const cleaned = medicines
      .filter((m): m is string => typeof m === "string")
      .map((m) => m.trim())
      .filter((m) => m.length > 0)
      .slice(0, 8);

    if (cleaned.length < 2) {
      return new Response(
        JSON.stringify({ interactions: [] }),
        { status: 200, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    const geminiApiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiApiKey) {
      console.error("Missing Gemini configuration for drug-interactions-ai");
      return new Response(
        JSON.stringify({ interactions: [], error: "Service configuration error" }),
        { status: 500, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    const prompt = buildPrompt(cleaned);

    // ── Gemini call ───────────────────────────────────────────────────────────
    let rawText = "";
    let lastError = "";

    for (const model of MODELS) {
      const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
      let res: Response;
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 30_000);
      try {
        res = await fetch(url, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "x-goog-api-key": geminiApiKey,
          },
          body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
            generationConfig: {
              temperature: 0.1,
              maxOutputTokens: 2048,
              topP: 0.8,
            },
          }),
          signal: controller.signal,
        });
      } catch (err) {
        clearTimeout(timeoutId);
        const timeout = err instanceof DOMException && err.name === "AbortError";
        lastError = timeout ? `${model} fetch timeout` : `${model} fetch: ${err}`;
        console.warn(lastError);
        continue;
      }
      clearTimeout(timeoutId);

      if (!res.ok) {
        const text = await res.text();
        lastError = `${model} HTTP ${res.status}: ${text.slice(0, 300)}`;
        console.warn(lastError);
        continue;
      }

      let data: Record<string, unknown> | null = null;
      try {
        data = await res.json();
      } catch (jsonErr) {
        lastError = `${model} invalid JSON: ${jsonErr instanceof Error ? jsonErr.message : String(jsonErr)}`;
        console.warn(lastError);
        continue;
      }
      const candidate = (data as any)?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
      if (!candidate) {
        lastError = `${model} empty candidate`;
        console.warn(lastError);
        continue;
      }

      rawText = candidate;
      console.log(`Drug interaction AI success: model=${model}, medicine_count=${cleaned.length}`);
      break;
    }

    if (!rawText) {
      console.error("All models failed:", lastError);
      return new Response(
        JSON.stringify({ interactions: [], error: "AI service temporarily unavailable" }),
        { status: 200, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    // ── Parse ─────────────────────────────────────────────────────────────────
    const stripped = rawText
      .replace(/^```json\s*/i, "").replace(/^```\s*/i, "").replace(/```\s*$/i, "").trim();

    const jStart = stripped.indexOf("{");
    const jEnd = stripped.lastIndexOf("}") + 1;
    const jsonStr = jStart !== -1 && jEnd > jStart
      ? stripped.slice(jStart, jEnd) : stripped;

    let parsed: { interactions?: unknown[] };
    try {
      parsed = JSON.parse(jsonStr);
    } catch {
      console.error("Parse failed:", stripped.slice(0, 400));
      return new Response(
        JSON.stringify({ interactions: [] }),
        { status: 200, headers: { ...cors, "Content-Type": "application/json" } }
      );
    }

    const sanitizedInteractions = Array.isArray(parsed.interactions)
      ? parsed.interactions
          .filter((item): item is Record<string, unknown> => !!item && typeof item === "object" && !Array.isArray(item))
          .map((item) => ({
            drugA: typeof item.drugA === "string" ? item.drugA.trim() : "",
            drugB: typeof item.drugB === "string" ? item.drugB.trim() : "",
            severity: typeof item.severity === "string" ? item.severity.trim() : "moderate",
            effect: typeof item.effect === "string" ? item.effect : "",
            mechanism: typeof item.mechanism === "string" ? item.mechanism : "",
            action: typeof item.action === "string" ? item.action : "",
            monitoring: typeof item.monitoring === "string" && item.monitoring.trim().length > 0 ? item.monitoring : null,
            alternative: typeof item.alternative === "string" && item.alternative.trim().length > 0 ? item.alternative : null,
            onset: typeof item.onset === "string" && item.onset.trim().length > 0 ? item.onset : null,
          }))
          .filter((item) => item.drugA.length > 0 && item.drugB.length > 0)
      : [];

    console.log(`Found ${sanitizedInteractions.length} AI interactions`);

    return new Response(JSON.stringify({ interactions: sanitizedInteractions }), {
      status: 200,
      headers: { ...cors, "Content-Type": "application/json" },
    });

  } catch (err) {
    console.error("Unhandled:", err);
    return new Response(JSON.stringify({ interactions: [], error: "An internal error occurred" }), {
      status: 500,
      headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
    });
  }
});
