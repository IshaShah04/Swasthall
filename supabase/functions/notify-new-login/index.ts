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

function clean(value: unknown, fallback: string, max = 120): string {
  const v = String(value ?? fallback).replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '').trim()
  return (v || fallback).slice(0, max)
}

function base64Url(input: string): string {
  return btoa(input).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
}

function base64UrlBytes(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
}

async function getAccessToken(sa: Record<string, string>): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header = base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const payload = base64Url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }))

  const sigInput = `${header}.${payload}`
  const pemKey = sa.private_key.replace(/\\n/g, '\n')
  const binaryKey = Uint8Array.from(atob(pemKey.replace(/-----[^-]+-----/g, '').replace(/\s/g, '')), c => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey('pkcs8', binaryKey, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'])
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, new TextEncoder().encode(sigInput))
  const jwt = `${sigInput}.${base64UrlBytes(new Uint8Array(sig))}`

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })
  const data = await res.json() as { access_token?: string }
  if (!data.access_token) throw new Error('FCM OAuth token error')
  return data.access_token
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    if (!authHeader.startsWith('Bearer ')) return json({ error: 'Missing Authorization header' }, 401)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const authClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: authHeader } },
    })
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } })

    const { data: { user }, error: authError } = await authClient.auth.getUser()
    if (authError || !user) return json({ error: 'Unauthorized' }, 401)

    const rl = await checkRateLimit(admin, user.id, 'notify-new-login', 10)
    if (!rl.allowed) return json({ error: 'Rate limit exceeded' }, 429)

    const body = await req.json().catch(() => ({})) as Record<string, unknown>
    const userId = clean(body.userId ?? user.id, user.id, 80)
    if (userId !== user.id) return json({ error: 'userId must match logged-in user' }, 403)

    const deviceLabel = clean(body.deviceName, 'Unknown device', 80)
    const platform = clean(body.platform, 'Unknown', 40)
    const locLabel = clean(body.location, 'Unknown location', 120)
    const timeLabel = clean(body.loginTime, new Date().toISOString(), 80)

    const { error: notifError } = await admin.from('notifications').insert({
      user_id: user.id,
      type: 'new_login',
      title: 'New Login Detected',
      body: `Your account was accessed from ${deviceLabel} (${platform}) • ${locLabel}`,
      data: { device: deviceLabel, platform, location: locLabel, login_time: timeLabel },
      read: false,
    })
    if (notifError) console.warn('[notify-new-login] notifications insert error:', notifError.message)

    const { data: profile, error: profileError } = await admin
      .from('profiles')
      .select('fcm_token')
      .eq('id', user.id)
      .maybeSingle()
    if (profileError) throw new Error(profileError.message)

    if (!profile?.fcm_token) return json({ sent: false, reason: 'no_previous_fcm_token', stored_in_db: true })

    const serviceAccount = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT')!) as Record<string, string>
    const accessToken = await getAccessToken(serviceAccount)

    const fcmRes = await fetch(`https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message: {
          token: profile.fcm_token,
          notification: { title: '🔐 New Login Detected', body: `${deviceLabel} • ${locLabel}` },
          data: { type: 'new_login', device: deviceLabel, location: locLabel, login_time: timeLabel },
          android: { priority: 'high', notification: { channel_id: 'security_alerts', sound: 'default' } },
          apns: { payload: { aps: { alert: { title: '🔐 New Login Detected', body: `${deviceLabel} • ${locLabel}` }, sound: 'default', badge: 1 } } },
        },
      }),
    })

    console.log(`[notify-new-login] user=${user.id} fcm_status=${fcmRes.status}`)
    return json({ sent: fcmRes.ok, fcm_status: fcmRes.status })
  } catch (e) {
    console.error('[notify-new-login] unexpected error:', e)
    return json({ error: 'Internal server error' }, 500)
  }
})
