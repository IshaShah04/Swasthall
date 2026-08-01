// supabase/functions/esewa-checkout/index.ts
//
// GET /esewa-checkout?id=SESSION_UUID
//
// Returns an HTML page that auto-submits the signed eSewa payment form.
// Flutter opens this URL in the system browser — no WebView needed.
// On success eSewa redirects to swasthall://esewa-success?data=BASE64
// On failure eSewa redirects to swasthall://esewa-failure
//
// Deploy:
//   supabase functions deploy esewa-checkout --no-verify-jwt

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUCCESS_DEEPLINK = 'swasthall://esewa-success'
const FAILURE_DEEPLINK = 'swasthall://esewa-failure'

Deno.serve(async (req: Request) => {
  // Allow browser preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: { 'Access-Control-Allow-Origin': '*' },
    })
  }

  const url = new URL(req.url)
  const id  = url.searchParams.get('id')

  if (!id) {
    return new Response('Missing ?id param', { status: 400 })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  // Fetch the signed form fields stored by esewa-initiate
  const { data: session, error } = await supabase
    .from('esewa_checkout_sessions')
    .select('form_url, form_fields, expires_at')
    .eq('id', id)
    .maybeSingle()

  if (error || !session) {
    return new Response(
      buildErrorHtml('Session not found', 'This payment link is invalid or has already been used.'),
      { status: 404, headers: new Headers({ 'Content-Type': 'text/html; charset=utf-8', 'X-Content-Type-Options': 'nosniff' }) },
    )
  }

  if (new Date(session.expires_at as string) < new Date()) {
    return new Response(
      buildErrorHtml('Session Expired', 'This payment link has expired. Please go back to the app and try again.'),
      { status: 410, headers: new Headers({ 'Content-Type': 'text/html; charset=utf-8', 'X-Content-Type-Options': 'nosniff' }) },
    )
  }

  // Override success/failure URLs with deep links so eSewa returns to the app
  const fields = { ...(session.form_fields as Record<string, string>) }
  fields['success_url'] = SUCCESS_DEEPLINK
  fields['failure_url'] = FAILURE_DEEPLINK

  // Build hidden <input> tags
  const inputs = Object.entries(fields)
    .map(([name, value]) =>
      `    <input type="hidden" name="${escapeHtml(name)}" value="${escapeHtml(value)}">`,
    )
    .join('\n')

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
  <title>Redirecting to eSewa…</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      min-height: 100svh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      background: linear-gradient(160deg, #f0fdf4 0%, #dcfce7 100%);
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      color: #111827;
      padding: 24px;
    }

    .card {
      background: white;
      border-radius: 24px;
      padding: 40px 32px 36px;
      text-align: center;
      box-shadow: 0 8px 40px rgba(0, 0, 0, 0.10);
      max-width: 380px;
      width: 100%;
    }

    .logo-wrap {
      width: 72px;
      height: 72px;
      background: #60bb46;
      border-radius: 20px;
      display: flex;
      align-items: center;
      justify-content: center;
      margin: 0 auto 22px;
      box-shadow: 0 6px 20px rgba(96, 187, 70, 0.35);
    }

    .logo-wrap svg { width: 40px; height: 40px; fill: white; }

    h1 { font-size: 22px; font-weight: 700; margin-bottom: 10px; color: #111827; }

    p  { color: #6b7280; font-size: 15px; line-height: 1.5; margin-bottom: 28px; }

    .spinner-wrap {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 12px;
      color: #60bb46;
      font-size: 14px;
      font-weight: 500;
    }

    .spinner {
      width: 28px; height: 28px;
      border: 3px solid #dcfce7;
      border-top-color: #60bb46;
      border-radius: 50%;
      animation: spin 0.75s linear infinite;
      flex-shrink: 0;
    }

    @keyframes spin { to { transform: rotate(360deg); } }

    .secure-badge {
      margin-top: 28px;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      font-size: 12px;
      color: #9ca3af;
    }

    .secure-badge svg { width: 14px; height: 14px; fill: #9ca3af; }
  </style>
</head>
<body>
  <div class="card">
    <!-- eSewa-style "e" logo -->
    <div class="logo-wrap">
      <svg viewBox="0 0 40 40" xmlns="http://www.w3.org/2000/svg">
        <text x="5" y="32" font-size="30" font-weight="900" font-family="Arial,sans-serif">e</text>
      </svg>
    </div>

    <h1>Opening eSewa</h1>
    <p>Redirecting you securely to complete your payment. Please do not close this page.</p>

    <div class="spinner-wrap">
      <div class="spinner"></div>
      <span>Connecting to eSewa…</span>
    </div>

    <div class="secure-badge">
      <svg viewBox="0 0 20 20" xmlns="http://www.w3.org/2000/svg">
        <path d="M10 1.5L3 4.5v5c0 4.25 2.95 8.22 7 9.18 4.05-.96 7-4.93 7-9.18v-5L10 1.5z"/>
      </svg>
      Secured by eSewa Payment Gateway
    </div>
  </div>

  <!-- Hidden form — auto-submitted by JS after 800 ms visual delay -->
  <form id="esewa-form" method="POST" action="${escapeHtml(session.form_url as string)}">
${inputs}
  </form>

  <script>
    (function () {
      // Small delay so user sees the loading screen, not a blank flash
      var delay = 800;
      setTimeout(function () {
        try {
          document.getElementById('esewa-form').submit();
        } catch (e) {
          // Fallback: show manual button if JS submit fails
          document.querySelector('p').textContent =
            'Tap the button below to continue to eSewa.';
          var btn = document.createElement('button');
          btn.textContent = 'Continue to eSewa';
          btn.style.cssText =
            'margin-top:20px;padding:14px 32px;background:#60bb46;color:white;' +
            'border:none;border-radius:12px;font-size:16px;font-weight:700;cursor:pointer;width:100%;';
          btn.onclick = function () { document.getElementById('esewa-form').submit(); };
          document.querySelector('.card').appendChild(btn);
          document.querySelector('.spinner-wrap').style.display = 'none';
        }
      }, delay);
    })();
  </script>
</body>
</html>`

  // Use new Headers() — plain object gets silently overridden by Supabase proxy middleware
  const htmlHeaders = new Headers()
  htmlHeaders.set('Content-Type', 'text/html; charset=utf-8')
  htmlHeaders.set('X-Content-Type-Options', 'nosniff')
  htmlHeaders.set('Cache-Control', 'no-store')
  return new Response(html, { status: 200, headers: htmlHeaders })
})

// ── Helpers ───────────────────────────────────────────────────────────────────

function escapeHtml(str: string): string {
  return str
    .replace(/&/g,  '&amp;')
    .replace(/</g,  '&lt;')
    .replace(/>/g,  '&gt;')
    .replace(/"/g,  '&quot;')
    .replace(/'/g,  '&#x27;')
}

function buildErrorHtml(title: string, message: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0">
  <title>${escapeHtml(title)}</title>
  <style>
    body { font-family: -apple-system, sans-serif; display: flex; align-items: center;
           justify-content: center; min-height: 100svh; background: #fef2f2; padding: 24px; }
    .card { background: white; border-radius: 20px; padding: 36px 28px; text-align: center;
            max-width: 360px; box-shadow: 0 4px 24px rgba(0,0,0,.08); }
    h1 { color: #dc2626; font-size: 20px; margin-bottom: 12px; }
    p  { color: #6b7280; font-size: 14px; line-height: 1.5; }
  </style>
</head>
<body>
  <div class="card">
    <h1>${escapeHtml(title)}</h1>
    <p>${escapeHtml(message)}</p>
  </div>
</body>
</html>`
}
