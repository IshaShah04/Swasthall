import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { checkRateLimit } from '../_shared/rateLimit.ts'
import { createLogger, getRequestId, startTimer } from '../_shared/logger.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req: Request) => {
  const requestId = getRequestId(req);
  const logger = createLogger('esewa-initiate', requestId);
  const elapsed = startTimer();
  logger.info('Request received', { method: req.method });
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
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token)

    if (authError || !user) {
      return json({ error: 'Unauthorized' }, 401)
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const rateLimit = await checkRateLimit(
      supabaseAdmin,
      user.id,
      'esewa-initiate',
      8,
    )

    if (!rateLimit.allowed) {
      return json(
        { error: 'Too many payment attempts. Please wait a minute and try again.' },
        429,
      )
    }

    const body = (await req.json()) as { amount?: number; order_type?: string; order_id?: string }
    const rawAmount = Number(body.amount)
    const orderType = String(body.order_type ?? 'consultation').trim().toLowerCase()
    const orderIdFromBody = String(body.order_id ?? '').trim()

    if (!rawAmount || rawAmount <= 0 || rawAmount > 500000) {
      return json({ error: 'amount must be a valid positive number' }, 400)
    }

    if (!['consultation', 'lab', 'insurance'].includes(orderType)) {
      return json({ error: 'Invalid order_type' }, 400)
    }

    const secretKey = Deno.env.get('ESEWA_SECRET_KEY')
    const productCode = Deno.env.get('ESEWA_PRODUCT_CODE') ?? 'EPAYTEST'
    const esewaEnv = Deno.env.get('ESEWA_ENV') ?? 'sandbox'
    const browserStartUrl = Deno.env.get('ESEWA_BROWSER_START_URL')

    if (!secretKey) {
      return json({ error: 'Payment gateway is not configured on the server.' }, 500)
    }

    if (!browserStartUrl || !browserStartUrl.startsWith('https://')) {
      return json({ error: 'Browser checkout host is not configured correctly.' }, 500)
    }

    const formUrl =
      esewaEnv === 'live'
        ? 'https://epay.esewa.com.np/api/epay/main/v2/form'
        : 'https://rc-epay.esewa.com.np/api/epay/main/v2/form'

    const transactionUuid = crypto.randomUUID().replace(/-/g, '').slice(0, 20)
    const orderId = orderIdFromBody || transactionUuid
    const totalAmountStr = rawAmount.toFixed(2)
    const browserToken =
      `${crypto.randomUUID().replace(/-/g, '')}` +
      `${crypto.randomUUID().replace(/-/g, '')}`

    const message =
      `total_amount=${totalAmountStr},` +
      `transaction_uuid=${transactionUuid},` +
      `product_code=${productCode}`

    const keyBytes = new TextEncoder().encode(secretKey)
    const msgBytes = new TextEncoder().encode(message)

    const cryptoKey = await crypto.subtle.importKey(
      'raw',
      keyBytes,
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign'],
    )

    const sigBuffer = await crypto.subtle.sign('HMAC', cryptoKey, msgBytes)
    const signature = btoa(String.fromCharCode(...new Uint8Array(sigBuffer)))

    const formFields = {
      amount: totalAmountStr,
      tax_amount: '0',
      total_amount: totalAmountStr,
      transaction_uuid: transactionUuid,
      product_code: productCode,
      product_service_charge: '0',
      product_delivery_charge: '0',
      success_url: 'swasthall://esewa-success',
      failure_url: 'swasthall://esewa-failure',
      signed_field_names: 'total_amount,transaction_uuid,product_code',
      signature,
    }

    const { data: sessionRow, error: insertError } = await supabaseAdmin
      .from('esewa_checkout_sessions')
      .insert({
        user_id: user.id,
        browser_token: browserToken,
        transaction_uuid: transactionUuid,
        total_amount: rawAmount,
        product_code: productCode,
        form_url: formUrl,
        form_fields: formFields,
        gateway_status: 'CREATED',
      })
      .select('id')
      .single()

    if (insertError || !sessionRow) {
      logger.error('esewa_checkout_sessions insert error', insertError)
      logger.info('Request completed', { duration_ms: elapsed() });
      return json({ error: 'Could not create payment session. Please try again.' }, 500)
    }


    const { error: paymentInsertError } = await supabaseAdmin
      .from('payment_transactions')
      .insert({
        user_id: user.id,
        provider: 'esewa',
        order_type: orderType,
        order_id: orderId,
        merchant_txn_id: transactionUuid,
        amount_paisa: Math.round(rawAmount * 100),
        currency: 'NPR',
        status: 'initiated',
        verified: false,
        raw_initiate_payload: { session_id: sessionRow.id, form_fields: formFields },
      })

    if (paymentInsertError) {
      logger.error('payment_transactions insert error', paymentInsertError)
      logger.info('Request completed', { duration_ms: elapsed() });
      return json({ error: 'Could not create payment transaction. Please try again.' }, 500)
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const sessionApiUrl =
      `${supabaseUrl}/functions/v1/esewa-browser-session` +
      `?id=${sessionRow.id}&token=${browserToken}`

    const browserBase = browserStartUrl.replace(/\/+$/, '')
    const checkoutUrl =
      `${browserBase}/api/esewa-start?sessionUrl=${encodeURIComponent(sessionApiUrl)}`

    logger.info('Request completed', { duration_ms: elapsed() });
    return json({
      checkout_url: checkoutUrl,
      transaction_uuid: transactionUuid,
      total_amount: totalAmountStr,
    })
  } catch (e) {
    logger.error('Unhandled error', e)
    logger.info('Request completed', { duration_ms: elapsed() });
    return json({ error: 'Internal server error' }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}