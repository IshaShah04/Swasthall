import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { checkRateLimit } from '../_shared/rateLimit.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return json({ error: 'Missing Authorization header' }, 401)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
    )
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabase.auth.getUser(token)
    if (authError || !user) {
      return json({ error: 'Unauthorized' }, 401)
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const rateLimit = await checkRateLimit(supabaseAdmin, user.id, 'esewa-status', 90)
    if (!rateLimit.allowed) {
      return json({ error: 'Too many status checks. Please slow down for a moment.' }, 429)
    }

    const body = await req.json() as { transaction_uuid?: string }
    const transactionUuid = body.transaction_uuid?.trim() ?? ''
    if (!transactionUuid) {
      return json({ error: 'transaction_uuid is required' }, 400)
    }

    const { data: session, error: sessionError } = await supabaseAdmin
      .from('esewa_checkout_sessions')
      .select('id, user_id, total_amount, product_code, gateway_status, ref_id, transaction_uuid, last_error')
      .eq('transaction_uuid', transactionUuid)
      .maybeSingle()

    if (sessionError || !session) {
      return json({
        verified: false,
        status: 'NOT_FOUND',
        transaction_uuid: transactionUuid,
        transaction_code: '',
        total_amount: '0',
        error: 'Payment session not found.',
      }, 404)
    }

    if ((session.user_id as string) !== user.id) {
      return json({ error: 'Forbidden' }, 403)
    }

    const localStatus = String(session.gateway_status ?? 'UNKNOWN').toUpperCase()
    if (localStatus === 'COMPLETE' || localStatus === 'FULL_REFUND' || localStatus === 'FAILED' || localStatus === 'CANCELLED') {
      return json({
        verified: localStatus === 'COMPLETE',
        status: localStatus,
        transaction_uuid: session.transaction_uuid,
        transaction_code: session.ref_id ?? '',
        total_amount: String(session.total_amount),
        error: session.last_error ?? null,
      })
    }

    const esewaEnv = Deno.env.get('ESEWA_ENV') ?? 'sandbox'
    const statusBase = esewaEnv === 'live'
      ? 'https://esewa.com.np/api/epay/transaction/status/'
      : 'https://rc.esewa.com.np/api/epay/transaction/status/'

    const totalAmount = Number(session.total_amount).toFixed(2)
    const statusUrl = `${statusBase}?product_code=${encodeURIComponent(String(session.product_code))}&total_amount=${encodeURIComponent(totalAmount)}&transaction_uuid=${encodeURIComponent(transactionUuid)}`

    const gatewayResp = await fetch(statusUrl, {
      method: 'GET',
      headers: { 'Accept': 'application/json' },
    })

    if (!gatewayResp.ok) {
      const errorText = await gatewayResp.text()
      return json({
        verified: false,
        status: 'UNKNOWN',
        transaction_uuid: transactionUuid,
        transaction_code: session.ref_id ?? '',
        total_amount: totalAmount,
        error: `Gateway status check failed (${gatewayResp.status}): ${errorText}`,
      }, 502)
    }

    const gatewayData = await gatewayResp.json() as Record<string, unknown>
    const status = String(gatewayData.status ?? 'UNKNOWN').toUpperCase()
    const refId = String(gatewayData.ref_id ?? '')

    await supabaseAdmin
      .from('esewa_checkout_sessions')
      .update({
        gateway_status: status,
        ref_id: refId || null,
        last_checked_at: new Date().toISOString(),
        verified: status === 'COMPLETE',
        verified_at: status === 'COMPLETE' ? new Date().toISOString() : null,
        last_error: null,
      })
      .eq('id', session.id)

    return json({
      verified: status === 'COMPLETE',
      status,
      transaction_uuid: String(gatewayData.transaction_uuid ?? transactionUuid),
      transaction_code: refId,
      total_amount: String(gatewayData.total_amount ?? totalAmount),
      ref_id: refId,
    })
  } catch (e) {
    console.error('esewa-status error:', e)
    return json({
      verified: false,
      status: 'UNKNOWN',
      transaction_uuid: '',
      transaction_code: '',
      total_amount: '0',
      error: String(e),
    }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
