// supabase/functions/gemini-prescription-proxy/index.ts
//
// Gemini Vision call to read handwritten prescriptions.
// Extracts all medicines, dosage, frequency and suggested reminder time.
//
// Auth: standard Supabase pattern — anon key + user JWT → getUser().
// This matches what the Supabase Flutter client sends via functions.invoke().

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const GEMINI_MODEL = "gemini-2.5-flash";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── Auth ──────────────────────────────────────────────────────────────────
    // IMPORTANT: Use ANON_KEY + user JWT, NOT SERVICE_ROLE_KEY.
    // SERVICE_ROLE_KEY causes "Invalid JWT" because it creates a key-type
    // mismatch. The anon key + forwarded Authorization header is the correct
    // Supabase edge function auth pattern.
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,   // ← ANON_KEY, not SERVICE_ROLE_KEY
      {
        global: { headers: { Authorization: authHeader } },
        auth: { persistSession: false },
      }
    );

    const {
      data: { user },
      error: authError,
    } = await supabaseClient.auth.getUser();

    if (authError || !user) {
      console.error("Auth failed:", authError?.message);
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // ── Parse body ────────────────────────────────────────────────────────────
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return new Response(
        JSON.stringify({ error: "Invalid JSON body" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Flutter sends: { imageBase64: "..." }
    const imageBase64 = body.imageBase64 as string | undefined;
    if (!imageBase64 || imageBase64.length === 0) {
      return new Response(
        JSON.stringify({ error: "Missing imageBase64 in request body" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const geminiApiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiApiKey) {
      return new Response(
        JSON.stringify({ error: "GEMINI_API_KEY not configured on server" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // ── Gemini Vision prompt ──────────────────────────────────────────────────
    const prompt = `You are a clinical pharmacist assistant specialising in Nepal medications.
Analyse this doctor's prescription image carefully.

Extract ALL medications written on it, even if the handwriting is difficult.

Return ONLY a JSON object in this exact format — no markdown, no explanation:
{
  "medicines": [
    {
      "name": "medicine name as written",
      "generic": "generic/active ingredient name if identifiable",
      "dosage": "dose strength e.g. 500mg",
      "frequency": "e.g. twice daily, TDS, OD",
      "duration": "e.g. 5 days, 1 week",
      "instructions": "e.g. after meals, with water"
    }
  ],
  "reminder_hour": 8,
  "reminder_minute": 0,
  "notes": "any other clinical instructions e.g. rest, diet, follow-up"
}

Rules:
- Include every medicine visible, even vitamins and supplements
- For reminder_hour/minute: use the first morning dose time if specified, default 8:00 AM
- Use common Nepal brand names as written (Napa, Cetamol, Flexon, Amoxil, etc.)
- If a field is not readable or not specified, use null
- Do NOT include patient name, age, address, or any identifying information
- Return only the JSON object, nothing else`;

    // ── Gemini Vision API ─────────────────────────────────────────────────────
    const geminiUrl =
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${geminiApiKey}`;

    const geminiResponse = await fetch(geminiUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              { text: prompt },
              {
                inline_data: {
                  mime_type: "image/jpeg",
                  data: imageBase64,
                },
              },
            ],
          },
        ],
        generationConfig: {
          temperature: 0.1,
          maxOutputTokens: 1024,
          responseMimeType: "application/json",
        },
      }),
    });

    if (!geminiResponse.ok) {
      const errText = await geminiResponse.text();
      console.error("Gemini error:", geminiResponse.status, errText);
      return new Response(
        JSON.stringify({ error: `Gemini API error: ${geminiResponse.status}`, detail: errText }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const geminiData = await geminiResponse.json();
    const rawText: string =
      geminiData?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";

    if (!rawText) {
      return new Response(
        JSON.stringify({ error: "Gemini returned empty response" }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Strip markdown fences if model ignores responseMimeType
    const cleaned = rawText
      .replace(/```json\s*/gi, "")
      .replace(/```\s*/g, "")
      .trim();

    // Extract JSON object — guard against any preamble text
    const jsonStart = cleaned.indexOf("{");
    const jsonEnd = cleaned.lastIndexOf("}") + 1;
    const jsonStr =
      jsonStart !== -1 && jsonEnd > jsonStart
        ? cleaned.slice(jsonStart, jsonEnd)
        : cleaned;

    let parsed: Record<string, unknown>;
    try {
      parsed = JSON.parse(jsonStr);
    } catch {
      console.error("JSON parse failed:", cleaned);
      return new Response(
        JSON.stringify({
          medicines: [],
          raw_text: rawText,
          error: "Could not parse prescription — try a clearer photo",
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const medCount = (parsed.medicines as unknown[] | undefined)?.length ?? 0;
    console.log(`Extracted ${medCount} medicines for user=${user.id}`);

    return new Response(JSON.stringify(parsed), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err) {
    console.error("Unhandled error:", err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
