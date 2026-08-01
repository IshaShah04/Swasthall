import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  })
}

function firstNonEmpty(...values: unknown[]): string {
  for (const value of values) {
    const v = String(value ?? '').trim()
    if (v) return v
  }
  return ''
}

function objectFromUnknown(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' ? value as Record<string, unknown> : {}
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const url = new URL(req.url)
    const contentType = req.headers.get('content-type') ?? ''
    let payload: unknown = null

    if (req.method === 'POST') {
      if (contentType.includes('application/json')) {
        payload = await req.json().catch(() => null)
      } else {
        payload = await req.text().catch(() => null)
      }
    }

    const payloadObj = objectFromUnknown(payload)
    const merchantTxnId = firstNonEmpty(
      payloadObj['productId'],
      payloadObj['product_id'],
      payloadObj['merchant_txn_id'],
      url.searchParams.get('productId'),
      url.searchParams.get('product_id'),
      url.searchParams.get('merchant_txn_id'),
    )
    const providerTxnId = firstNonEmpty(
      payloadObj['refId'],
      payloadObj['ref_id'],
      payloadObj['referenceId'],
      payloadObj['txnRefId'],
      url.searchParams.get('refId'),
      url.searchParams.get('ref_id'),
      url.searchParams.get('referenceId'),
      url.searchParams.get('txnRefId'),
    )

    console.log('esewa-sdk-callback hit', {
      method: req.method,
      url: req.url,
      merchantTxnId,
      providerTxnId,
      payload,
    })

    const supabaseUrl = Deno.env.get('SUPABASE_URL')?.trim() ?? ''
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim() ?? ''

    if (supabaseUrl && serviceRoleKey && merchantTxnId) {
      try {
        const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
          auth: { persistSession: false },
        })

        const { data: existing } = await supabaseAdmin
          .from('payment_transactions')
          .select('id')
          .eq('merchant_txn_id', merchantTxnId)
          .maybeSingle()

        if (existing?.id) {
          await supabaseAdmin
            .from('payment_transactions')
            .update({
              provider_txn_id: providerTxnId || null,
              updated_at: new Date().toISOString(),
            })
            .eq('id', existing.id)
        }
      } catch (e) {
        console.error('esewa-sdk-callback payment sync error:', e)
      }
    }

    // Return a simple OK for SDK/browser callback consumers.
    return new Response('OK', {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'text/plain; charset=utf-8' },
    })
  } catch (e) {
    console.error('esewa-sdk-callback error:', e)
    return json({ ok: false, error: String(e) }, 500)
  }
})
