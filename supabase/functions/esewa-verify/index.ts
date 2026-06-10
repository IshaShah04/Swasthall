import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

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

    const parsedBody = await req.json();
    
    // Validate required fields before processing
    if (
      typeof parsedBody !== "object" ||
      typeof parsedBody.data !== "string" ||
      parsedBody.data.trim() === ""
    ) {
      return new Response(
        JSON.stringify({ error: "Invalid request payload" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const base64Data = parsedBody.data.trim();

    let parsed: Record<string, string>
    try {
      parsed = JSON.parse(atob(base64Data)) as Record<string, string>
    } catch {
      return json({ verified: false, error: 'Invalid base64 data from eSewa' }, 400)
    }

    const signedFieldNames = parsed['signed_field_names'] ?? ''
    const responseSignature = parsed['signature'] ?? ''
    if (!signedFieldNames || !responseSignature) {
      return json({ verified: false, error: 'Missing signature fields in eSewa response' }, 400)
    }

    const message = signedFieldNames
      .split(',')
      .map((field) => `${field}=${parsed[field] ?? ''}`)
      .join(',')

    const secretKey = Deno.env.get('ESEWA_SECRET_KEY')
    if (!secretKey) {
      return json({ verified: false, error: 'Server misconfiguration' }, 500)
    }

    const cryptoKey = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(secretKey),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign'],
    )
    const sigBuffer = await crypto.subtle.sign('HMAC', cryptoKey, new TextEncoder().encode(message))
    const computed = btoa(String.fromCharCode(...new Uint8Array(sigBuffer)))
    const verified = computed === responseSignature

    const transactionUuid = parsed['transaction_uuid'] ?? ''
    const transactionCode = parsed['transaction_code'] ?? parsed['ref_id'] ?? ''
    const status = (parsed['status'] ?? 'UNKNOWN').toUpperCase()
    const totalAmount = parsed['total_amount'] ?? '0'

    if (transactionUuid) {
      await supabaseAdmin
        .from('esewa_checkout_sessions')
        .update({
          gateway_status: status,
          ref_id: transactionCode || null,
          verified,
          verified_at: verified && status === 'COMPLETE' ? new Date().toISOString() : null,
          last_checked_at: new Date().toISOString(),
          last_error: verified ? null : 'Signature mismatch while verifying callback response.',
        })
        .eq('transaction_uuid', transactionUuid)
        .eq('user_id', user.id)
    }

    return json({
      verified,
      status,
      transaction_uuid: transactionUuid,
      transaction_code: transactionCode,
      total_amount: totalAmount,
      product_code: parsed['product_code'] ?? '',
      error: verified ? null : 'Signature mismatch while verifying payment response.',
    })
  } catch (e) {
    console.error('[esewa-verify]', e)
    return json({ verified: false, error: 'Internal server error' }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
