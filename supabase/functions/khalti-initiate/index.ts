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

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  try {
    const user = await getAuthedUser(req)
    const supabaseAdmin = getAdmin()

    const rateLimit = await checkRateLimit(supabaseAdmin, user.id, 'khalti-initiate', 30)
    if (!rateLimit.allowed) {
      return json({ error: 'Too many payment requests. Please wait a moment.' }, 429)
    }

    const body = await req.json().catch(() => ({})) as Record<string, unknown>

    const amountPaisa = Number(body.amount_paisa ?? 0)
    const purchaseOrderId = String(body.purchase_order_id ?? '').trim()
    const purchaseOrderName = String(body.purchase_order_name ?? '').trim()
    const orderType = String(body.order_type ?? '').trim().toLowerCase()
    const orderId = String(body.order_id ?? '').trim()

    if (!Number.isInteger(amountPaisa) || amountPaisa < 100 || amountPaisa > 50000000) {
      return json({ error: 'Invalid amount_paisa' }, 400)
    }

    if (!amountPaisa || !purchaseOrderId || !purchaseOrderName || !orderType || !orderId) {
      return json({
        error: 'amount_paisa, purchase_order_id, purchase_order_name, order_type and order_id are required',
      }, 400)
    }

    if (!['consultation', 'lab', 'insurance'].includes(orderType)) {
      return json({ error: 'Invalid order_type' }, 400)
    }

    const secretKey = Deno.env.get('KHALTI_SECRET_KEY')?.trim() ?? ''
    const websiteUrl = Deno.env.get('PAYMENT_WEBSITE_URL')?.trim() ?? 'https://app.swasthall.test'
    const returnUrl = Deno.env.get('KHALTI_RETURN_URL')?.trim() ?? `${websiteUrl}/khalti-return`
    const envMode = (Deno.env.get('KHALTI_ENVIRONMENT') ?? 'test').trim().toLowerCase()

    if (!secretKey) {
      return json({ error: 'KHALTI_SECRET_KEY is missing on the server.' }, 500)
    }

    const baseUrl =
      envMode === 'live' || envMode === 'prod' || envMode === 'production'
        ? 'https://khalti.com/api/v2'
        : 'https://dev.khalti.com/api/v2'

    const customerInfo: Record<string, string> = {}
    if (body.customer_name) customerInfo.name = String(body.customer_name)
    if (body.customer_email) customerInfo.email = String(body.customer_email)
    if (body.customer_phone) customerInfo.phone = String(body.customer_phone)

    const gatewayResp = await fetch(`${baseUrl}/epayment/initiate/`, {
      method: 'POST',
      headers: {
        'Authorization': `Key ${secretKey}`,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: JSON.stringify({
        return_url: returnUrl,
        website_url: websiteUrl,
        amount: amountPaisa,
        purchase_order_id: purchaseOrderId,
        purchase_order_name: purchaseOrderName,
        customer_info: Object.keys(customerInfo).length === 0 ? undefined : customerInfo,
      }),
    })

    const rawText = await gatewayResp.text()
    let parsed: Record<string, unknown>
    try {
      parsed = JSON.parse(rawText)
    } catch {
      return json({ error: 'Khalti initiate returned invalid JSON.', raw: rawText }, 502)
    }

    if (!gatewayResp.ok) {
      return json({ error: 'Khalti initiate failed.', raw: parsed }, 502)
    }

    const { error: insertError } = await supabaseAdmin
      .from('payment_transactions')
      .insert({
        user_id: user.id,
        provider: 'khalti',
        order_type: orderType,
        order_id: orderId,
        merchant_txn_id: purchaseOrderId,
        provider_session_id: String(parsed.pidx ?? ''),
        amount_paisa: amountPaisa,
        currency: 'NPR',
        status: 'initiated',
        verified: false,
        raw_initiate_payload: parsed,
      })

    if (insertError) {
      return json({ error: insertError.message }, 500)
    }

    return json({
      payment_url: String(parsed.payment_url ?? ''),
      pidx: String(parsed.pidx ?? ''),
      expires_at: parsed.expires_at ?? null,
      return_url: returnUrl,
    })
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : String(e) }, 500)
  }
})
