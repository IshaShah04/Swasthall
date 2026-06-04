import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { checkRateLimit } from '../_shared/rateLimit.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  })
}

async function getAuthedUser(req: Request) {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader?.startsWith('Bearer ')) {
    throw new Error('Missing Authorization header')
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { auth: { persistSession: false } },
  )

  const token = authHeader.replace('Bearer ', '').trim()
  const { data: { user }, error } = await supabase.auth.getUser(token)
  if (error || !user) throw new Error('Unauthorized')
  return user
}

function getAdmin() {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  )
}

function mapStatus(status: string): 'pending' | 'complete' | 'failed' | 'cancelled' | 'expired' {
  switch (status.toLowerCase()) {
    case 'completed':
      return 'complete'
    case 'pending':
    case 'initiated':
      return 'pending'
    case 'expired':
      return 'expired'
    case 'canceled':
    case 'cancelled':
      return 'cancelled'
    default:
      return 'failed'
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  try {
    const user = await getAuthedUser(req)
    const supabaseAdmin = getAdmin()

    const rateLimit = await checkRateLimit(supabaseAdmin, user.id, 'khalti-verify', 60)
    if (!rateLimit.allowed) {
      return json({ error: 'Too many verification requests. Please slow down.' }, 429)
    }

    const body = await req.json().catch(() => ({})) as Record<string, unknown>
    const pidx = String(body.pidx ?? '').trim()
    const amountPaisa = Number(body.amount_paisa ?? 0)

    if (!pidx) return json({ error: 'pidx is required' }, 400)

    const secretKey = Deno.env.get('KHALTI_SECRET_KEY')?.trim() ?? ''
    const envMode = (Deno.env.get('KHALTI_ENVIRONMENT') ?? 'test').trim().toLowerCase()
    const baseUrl =
      envMode === 'live' || envMode === 'prod' || envMode === 'production'
        ? 'https://khalti.com/api/v2'
        : 'https://dev.khalti.com/api/v2'

    if (!secretKey) {
      return json({ error: 'KHALTI_SECRET_KEY is missing on the server.' }, 500)
    }

    const gatewayResp = await fetch(`${baseUrl}/epayment/lookup/`, {
      method: 'POST',
      headers: {
        'Authorization': `Key ${secretKey}`,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: JSON.stringify({ pidx }),
    })

    const rawText = await gatewayResp.text()
    let parsed: Record<string, unknown>
    try {
      parsed = JSON.parse(rawText)
    } catch {
      return json({ error: 'Khalti lookup returned invalid JSON.', raw: rawText }, 502)
    }

    if (!gatewayResp.ok) {
      return json({ error: 'Khalti lookup failed.', raw: parsed }, 502)
    }

    const status = String(parsed.status ?? 'UNKNOWN')
    const totalAmount = Number(parsed.total_amount ?? 0)
    const amountMatches = amountPaisa <= 0 || totalAmount == amountPaisa
    const verified = status === 'Completed' && amountMatches
    const mappedStatus = verified ? 'complete' : mapStatus(status)

    const updatePayload = {
      verified,
      status: mappedStatus,
      provider_txn_id: parsed.transaction_id ?? null,
      raw_verify_payload: parsed,
      error_message: verified
        ? null
        : amountMatches
            ? 'Khalti payment is not completed yet.'
            : 'Amount mismatch during Khalti verification.',
      completed_at: verified ? new Date().toISOString() : null,
    }

    const { error: updateError } = await supabaseAdmin
      .from('payment_transactions')
      .update(updatePayload)
      .eq('provider', 'khalti')
      .eq('provider_session_id', pidx)
      .eq('user_id', user.id)

    if (updateError) {
      return json({ error: updateError.message }, 500)
    }

    return json({
      verified,
      status,
      pidx: String(parsed.pidx ?? pidx),
      transaction_code: String(parsed.transaction_id ?? ''),
      total_amount: String(parsed.total_amount ?? ''),
      error: verified
        ? null
        : amountMatches
            ? 'Khalti payment not completed.'
            : 'Amount mismatch during verification.',
      raw: parsed,
    }, verified ? 200 : 400)
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500)
  }
})
