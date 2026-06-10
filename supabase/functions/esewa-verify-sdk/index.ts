import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { checkRateLimit } from '../_shared/rateLimit.ts'
import { createLogger, getRequestId, startTimer } from '../_shared/logger.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

type VerifyBody = {
  ref_id?: string
  product_id?: string
  amount?: string | number
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  })
}

function normalizeAmount(value: string | number | undefined | null): string {
  if (value === undefined || value === null || value === '') return ''
  const num = Number(value)
  if (Number.isNaN(num)) return String(value).trim()
  return num.toFixed(2)
}

function amountToPaisa(value: string | number | undefined | null): number | null {
  if (value === undefined || value === null || value === '') return null
  const num = Number(value)
  if (Number.isNaN(num)) return null
  return Math.round(num * 100)
}

function pickFirstObject(value: unknown): Record<string, unknown> {
  if (Array.isArray(value)) {
    const first = value[0]
    return first && typeof first === 'object' ? first as Record<string, unknown> : {}
  }
  return value && typeof value === 'object' ? value as Record<string, unknown> : {}
}

async function syncPaymentTransaction(
  supabaseAdmin: ReturnType<typeof createClient>,
  userId: string,
  merchantTxnId: string,
  providerTxnId: string,
  responseAmount: string,
  verified: boolean,
  rawPayload: Record<string, unknown>,
): Promise<{ ok: boolean; error?: string }> {
  if (!merchantTxnId) return { ok: false, error: 'Missing merchant transaction id.' }

  const responseAmountPaisa = amountToPaisa(responseAmount)
  const { data: existing, error: existingError } = await supabaseAdmin
    .from('payment_transactions')
    .select('id,amount_paisa,user_id,provider,merchant_txn_id')
    .eq('user_id', userId)
    .eq('provider', 'esewa')
    .eq('merchant_txn_id', merchantTxnId)
    .maybeSingle()

  if (existingError) {
    console.error('payment_transactions lookup failed:', existingError)
    return { ok: false, error: 'Payment lookup failed.' }
  }

  if (!existing?.id) {
    return { ok: false, error: 'Payment transaction was not initiated for this user.' }
  }

  if (responseAmountPaisa !== null && existing.amount_paisa !== null && responseAmountPaisa !== existing.amount_paisa) {
    await supabaseAdmin
      .from('payment_transactions')
      .update({
        verified: false,
        status: 'failed',
        provider_txn_id: providerTxnId || null,
        error_message: 'Amount mismatch during eSewa verification.',
        raw_verify_payload: rawPayload,
        updated_at: new Date().toISOString(),
      })
      .eq('id', existing.id)
    return { ok: false, error: 'Amount mismatch during verification.' }
  }

  const now = new Date().toISOString()
  const { error: updateError } = await supabaseAdmin
    .from('payment_transactions')
    .update({
      provider_txn_id: providerTxnId || null,
      status: verified ? 'complete' : 'failed',
      verified,
      error_message: verified ? null : 'eSewa transaction is not complete.',
      raw_verify_payload: rawPayload,
      updated_at: now,
      completed_at: verified ? now : null,
    })
    .eq('id', existing.id)

  if (updateError) {
    console.error('payment_transactions update failed:', updateError)
    return { ok: false, error: 'Payment update failed.' }
  }

  return { ok: true }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader?.startsWith('Bearer ')) return json({ error: 'Missing Authorization header' }, 401)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')?.trim() ?? ''
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')?.trim() ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim() ?? ''
    if (!supabaseUrl || !anonKey || !serviceRoleKey) return json({ error: 'Supabase env vars are missing on the server.' }, 500)

    const supabase = createClient(supabaseUrl, anonKey, { auth: { persistSession: false } })
    const token = authHeader.replace('Bearer ', '').trim()
    const { data: { user }, error: authError } = await supabase.auth.getUser(token)
    if (authError || !user) return json({ error: 'Unauthorized' }, 401)

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } })
    const rateLimit = await checkRateLimit(supabaseAdmin, user.id, 'esewa-verify-sdk', 30)
    if (!rateLimit.allowed) return json({ error: 'Too many verification requests. Please slow down for a moment.' }, 429)

    const body = await req.json().catch(() => ({})) as VerifyBody
    const refId = String(body.ref_id ?? '').trim()
    const productId = String(body.product_id ?? '').trim()
    const amount = String(body.amount ?? '').trim()
    if (!refId && (!productId || !amount)) return json({ error: 'ref_id or (product_id and amount) is required' }, 400)

    const merchantId = Deno.env.get('ESEWA_SDK_CLIENT_ID')?.trim() ?? ''
    const merchantSecret = Deno.env.get('ESEWA_SDK_SECRET_ID')?.trim() ?? ''
    const sdkEnv = (Deno.env.get('ESEWA_SDK_ENVIRONMENT') ?? Deno.env.get('ESEWA_ENV') ?? 'test').trim().toLowerCase()
    if (!merchantId || !merchantSecret) return json({ error: 'eSewa SDK verification is not configured on the server.' }, 500)

    const baseUrl = sdkEnv === 'live' || sdkEnv === 'production' || sdkEnv === 'prod'
      ? 'https://esewa.com.np/mobile/transaction'
      : 'https://rc.esewa.com.np/mobile/transaction'

    const url = new URL(baseUrl)
    if (refId) url.searchParams.set('txnRefId', refId)
    else {
      url.searchParams.set('productId', productId)
      url.searchParams.set('amount', amount)
    }

    const gatewayResp = await fetch(url.toString(), {
      method: 'GET',
      headers: { merchantId, merchantSecret, 'Content-Type': 'application/json', Accept: 'application/json' },
    })
    const rawText = await gatewayResp.text()
    if (!gatewayResp.ok) return json({ verified: false, status: 'UNKNOWN', merchant_txn_id: productId, transaction_uuid: productId, transaction_code: refId, total_amount: amount, error: 'Gateway verification failed.' }, 502)

    let parsed: unknown
    try { parsed = JSON.parse(rawText) } catch {
      return json({ verified: false, status: 'UNKNOWN', merchant_txn_id: productId, transaction_uuid: productId, transaction_code: refId, total_amount: amount, error: 'Gateway returned invalid JSON.' }, 502)
    }

    const first = pickFirstObject(parsed)
    const transactionDetails = pickFirstObject(first['transactionDetails'])
    const status = String(transactionDetails['status'] ?? 'UNKNOWN').trim().toUpperCase()
    const responseProductId = String(first['productId'] ?? productId).trim()
    const responseRefId = String(transactionDetails['referenceId'] ?? refId).trim()
    const responseAmount = String(first['totalAmount'] ?? amount).trim()

    const expectedAmount = normalizeAmount(amount)
    const actualAmount = normalizeAmount(responseAmount)
    const productMatches = !productId || responseProductId === productId
    const amountMatches = !amount || actualAmount === expectedAmount
    const isComplete = status === 'COMPLETE'
    const verified = isComplete && productMatches && amountMatches

    const syncResult = await syncPaymentTransaction(supabaseAdmin, user.id, responseProductId, responseRefId, responseAmount, verified, first)
    if (!syncResult.ok) {
      logger.info('Request completed', { duration_ms: elapsed() });
      return json({ verified: false, status, merchant_txn_id: responseProductId, transaction_uuid: responseProductId, transaction_code: responseRefId, total_amount: responseAmount, product_code: merchantId, error: syncResult.error ?? 'Payment sync failed.' }, 400)
    }

    logger.info('Request completed', { duration_ms: elapsed() });
    return json({ verified, status, merchant_txn_id: responseProductId, transaction_uuid: responseProductId, transaction_code: responseRefId, total_amount: responseAmount, product_code: merchantId, checks: { isComplete, productMatches, amountMatches }, error: verified ? null : 'Payment could not be verified as complete.' }, verified ? 200 : 400)
  } catch (e) {
    logger.error('Unhandled error', e)
    logger.info('Request completed', { duration_ms: elapsed() });
    return json({ verified: false, status: 'UNKNOWN', merchant_txn_id: '', transaction_uuid: '', transaction_code: '', total_amount: '0', error: 'Internal server error' }, 500)
  }
})
