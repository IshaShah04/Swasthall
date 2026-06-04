import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { checkRateLimit } from '../_shared/rateLimit.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const GEMINI_MODEL = 'gemini-2.0-flash'
const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta/models'
const MAX_BASE64_CHARS = 8_000_000 // roughly <= 6MB binary image

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  })
}

function detectMimeType(imageBase64: string): string {
  if (imageBase64.startsWith('/9j/')) return 'image/jpeg'
  if (imageBase64.startsWith('iVBOR')) return 'image/png'
  if (imageBase64.startsWith('UklG')) return 'image/webp'
  return 'image/jpeg'
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader?.startsWith('Bearer ')) return json({ error: 'Missing or invalid Authorization header' }, 401)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const supabase = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: authHeader } },
    })
    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) return json({ error: 'Unauthorized' }, 401)

    const supabaseAdmin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } })
    const rl = await checkRateLimit(supabaseAdmin, user.id, 'gemini-prescription-proxy', 12)
    if (!rl.allowed) return json({ error: 'Too many prescription scans. Please wait a minute.' }, 429)

    const body = await req.json().catch(() => ({})) as Record<string, unknown>
    const imageBase64 = String(body.imageBase64 ?? '').trim()
    if (!imageBase64) return json({ error: 'imageBase64 is required' }, 400)
    if (imageBase64.length > MAX_BASE64_CHARS) return json({ error: 'Image is too large. Please upload a smaller image.' }, 413)

    const geminiKey = Deno.env.get('GEMINI_API_KEY')
    if (!geminiKey) return json({ error: 'Gemini API not configured on server' }, 500)

    const prompt = `You are a medical prescription reader.
Carefully read this prescription image and extract medicines only from visible prescription text.
Do not guess unclear medicines. If unreadable, leave fields blank or say unclear.
Return ONLY valid JSON with this structure:
{
  "medicines": [{"name":"","generic":"","dosage":"","frequency":"","duration":"","instructions":""}],
  "notes":"",
  "doctorName":"",
  "patientName":""
}`

    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(), 20_000)

    const geminiRes = await fetch(`${GEMINI_BASE}/${GEMINI_MODEL}:generateContent?key=${geminiKey}`, {
      method: 'POST',
      signal: controller.signal,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }, { inline_data: { mime_type: detectMimeType(imageBase64), data: imageBase64 } }] }],
        generationConfig: { temperature: 0.1, maxOutputTokens: 2048, responseMimeType: 'application/json' },
      }),
    }).finally(() => clearTimeout(timeout))

    if (!geminiRes.ok) {
      const errText = await geminiRes.text().catch(() => '')
      console.error('Gemini API error:', geminiRes.status, errText.slice(0, 500))
      return json({ error: 'Prescription AI service failed.' }, 502)
    }

    const geminiData = await geminiRes.json()
    const rawText: string = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text ?? ''
    if (!rawText) return json({ medicines: [], notes: 'No response from AI' })

    const cleaned = rawText.replace(/```json\s*/gi, '').replace(/```\s*/g, '').trim()
    let parsed: Record<string, unknown>
    try { parsed = JSON.parse(cleaned) } catch {
      console.error('Failed to parse Gemini JSON:', cleaned.slice(0, 500))
      return json({ medicines: [], notes: 'Could not parse prescription' })
    }

    supabaseAdmin.from('prescription_scans').insert({
      user_id: user.id,
      medicines_count: Array.isArray(parsed.medicines) ? parsed.medicines.length : 0,
      scanned_at: new Date().toISOString(),
    }).then(() => {}).catch(() => {})

    console.log(`gemini-prescription-proxy: user=${user.id}`)
    return json(parsed)
  } catch (e) {
    console.error('gemini-prescription-proxy fatal error:', e)
    return json({ error: 'Internal server error' }, 500)
  }
})
