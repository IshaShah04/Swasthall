import { Resend } from 'npm:resend@4.0.0'
import { createClient } from 'jsr:@supabase/supabase-js@2'

const resendApiKey = Deno.env.get('RESEND_API_KEY') ?? ''
const reviewTo = Deno.env.get('REVIEW_ALERT_TO') ?? 'verifyswasthall@gmail.com'
const reviewFrom = Deno.env.get('REVIEW_ALERT_FROM') ?? 'verify@verify.swasthall.com'
const webhookSecret = Deno.env.get('REVIEW_ALERT_SECRET') ?? ''
const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

const resend = new Resend(resendApiKey)
const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } })

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  })
}

function esc(value: unknown): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .slice(0, 300)
}

function normalizeRecord(body: any) {
  return body?.record ?? body?.new ?? body
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  if (!resendApiKey || !supabaseUrl || !serviceRoleKey || !webhookSecret) {
    return json({ error: 'Missing function secrets' }, 500)
  }

  const providedSecret = req.headers.get('x-webhook-secret') ?? ''
  if (providedSecret !== webhookSecret) {
    return json({ error: 'Unauthorized' }, 401)
  }

  try {
    const body = await req.json()
    const row = normalizeRecord(body)

    const userId = row?.user_id?.toString?.() ?? ''
    const role = row?.role?.toString?.() ?? 'unknown'
    const fullName = row?.full_name?.toString?.() ?? 'Unknown User'
    const email = row?.email?.toString?.() ?? ''
    const requiredDocKeys = Array.isArray(row?.required_doc_keys) ? row.required_doc_keys : []
    const submittedDocKeys = Array.isArray(row?.submitted_doc_keys) ? row.submitted_doc_keys : []

    if (!userId) return json({ error: 'Missing user_id in payload' }, 400)

    const html = `
      <div style="font-family:Arial,sans-serif;line-height:1.5">
        <h2>New professional registration ready for review</h2>
        <p><strong>Name:</strong> ${esc(fullName)}</p>
        <p><strong>Email:</strong> ${esc(email)}</p>
        <p><strong>Role:</strong> ${esc(role)}</p>
        <p><strong>User ID:</strong> ${esc(userId)}</p>
        <p><strong>Required docs:</strong> ${requiredDocKeys.map(esc).join(', ') || 'None'}</p>
        <p><strong>Submitted docs:</strong> ${submittedDocKeys.map(esc).join(', ') || 'None'}</p>
        <p>Please review uploaded documents in Supabase before approving the user.</p>
      </div>
    `

    const { data, error } = await resend.emails.send({
      from: reviewFrom,
      to: [reviewTo],
      subject: `Review needed: ${esc(role)} registration for ${esc(fullName)}`,
      html,
    })

    if (error) {
      console.error('Resend error', error)
      return json({ error: 'Email provider failed' }, 500)
    }

    const { error: updateError } = await admin
      .from('professional_review_notifications')
      .update({ email_sent_at: new Date().toISOString(), resend_message_id: data?.id ?? null })
      .eq('user_id', userId)

    if (updateError) {
      console.error('[professional-review-alert]', updateError)
      return json({ error: 'Internal server error' }, 500)
    }

    return json({ ok: true, resendId: data?.id ?? null })
  } catch (error) {
    console.error(error)
    return json({ error: 'Internal server error' }, 500)
  }
})
