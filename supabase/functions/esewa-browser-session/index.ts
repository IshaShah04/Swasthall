import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'GET') {
    return json({ error: 'Method not allowed' }, 405)
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    if (!supabaseUrl || !serviceRoleKey) {
      return json({ error: 'Server is not configured correctly.' }, 500)
    }

    const url = new URL(req.url)
    const id = (url.searchParams.get('id') ?? '').trim()
    const token = (url.searchParams.get('token') ?? '').trim()

    if (!id || !token) {
      return json({ error: 'Missing id or token.' }, 400)
    }

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey)

    const { data: sessionRow, error: fetchError } = await supabaseAdmin
      .from('esewa_checkout_sessions')
      .select(`
        id,
        browser_token,
        form_url,
        form_fields,
        expires_at,
        gateway_status,
        transaction_uuid,
        total_amount,
        product_code
      `)
      .eq('id', id)
      .eq('browser_token', token)
      .maybeSingle()

    if (fetchError) {
      console.error('esewa-browser-session fetch error:', fetchError)
      return json({ error: 'Could not load payment session.' }, 500)
    }

    if (!sessionRow) {
      return json({ error: 'Payment session not found.' }, 404)
    }

    const expiresAt = new Date(sessionRow.expires_at)
    if (Number.isNaN(expiresAt.getTime()) || expiresAt.getTime() < Date.now()) {
      return json({ error: 'Payment session has expired.' }, 410)
    }

    if (!sessionRow.form_url || !sessionRow.form_fields) {
      return json({ error: 'Payment session is incomplete.' }, 500)
    }

    const allowedStatuses = new Set([
      'CREATED',
      'BROWSER_SESSION_OPENED',
      'BROWSER_RENDERED',
    ])

    const currentStatus = String(sessionRow.gateway_status ?? 'CREATED').toUpperCase()
    if (!allowedStatuses.has(currentStatus)) {
      return json(
        { error: `Payment session is not available in status ${currentStatus}.` },
        409,
      )
    }

    const { error: updateError } = await supabaseAdmin
      .from('esewa_checkout_sessions')
      .update({ gateway_status: 'BROWSER_SESSION_OPENED' })
      .eq('id', sessionRow.id)

    if (updateError) {
      console.error('esewa-browser-session update error:', updateError)
    }

    return json({
      form_url: sessionRow.form_url,
      form_fields: sessionRow.form_fields,
      transaction_uuid: sessionRow.transaction_uuid,
      total_amount: sessionRow.total_amount,
      product_code: sessionRow.product_code,
    })
  } catch (e) {
    console.error('esewa-browser-session unexpected error:', e)
    return json({ error: String(e) }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  })
}