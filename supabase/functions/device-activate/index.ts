import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
}
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: corsHeaders })
const sha256 = async (value: string) => {
  const bytes = new TextEncoder().encode(value)
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('')
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const body = await req.json()
    const businessCode = String(body.business_code ?? '').trim().toUpperCase()
    const activationCode = String(body.activation_code ?? '').trim().toUpperCase()
    const installationId = String(body.installation_id ?? '').trim()
    const appKey = String(body.app_key ?? '').trim().toLowerCase()
    const platformHint = String(body.platform_hint ?? '').trim()
    const appVersion = String(body.app_version ?? '').trim()
    if (!businessCode || !activationCode || !installationId || !['client', 'pos'].includes(appKey)) {
      return json({ error: 'Business code, activation code and installation ID are required.' }, 400)
    }

    const url = Deno.env.get('SUPABASE_URL')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const admin = createClient(url, serviceKey, { auth: { persistSession: false } })

    // Only the raw device secret is returned to the app. PostgreSQL receives hashes only.
    const deviceSecret = `${crypto.randomUUID()}${crypto.randomUUID().replaceAll('-', '')}`
    const activationHash = await sha256(activationCode)
    const secretHash = await sha256(deviceSecret)

    const { data, error } = await admin.rpc('system_claim_activation_v47', {
      p_business_code: businessCode,
      p_activation_hash: activationHash,
      p_installation_id: installationId,
      p_app_key: appKey,
      p_secret_hash: secretHash,
      p_platform_hint: platformHint || null,
      p_app_version: appVersion || null,
    })
    if (error) {
      const message = error.message || 'Activation failed.'
      const status = /invalid|expired/i.test(message) ? 401 : /already registered/i.test(message) ? 409 : 500
      return json({ error: message }, status)
    }
    if (!data || typeof data !== 'object') return json({ error: 'Activation returned an incomplete response.' }, 500)

    return json({ ...(data as Record<string, unknown>), device_secret: deviceSecret })
  } catch (error) {
    return json({ error: String(error) }, 500)
  }
})
