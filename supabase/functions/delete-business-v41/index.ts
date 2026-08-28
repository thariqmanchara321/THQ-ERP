import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: corsHeaders })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'POST required.' }, 405)

  const url = Deno.env.get('SUPABASE_URL')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const authHeader = req.headers.get('Authorization') ?? ''

  try {
    const body = await req.json()
    const tenantId = String(body.tenant_id ?? '')
    const password = String(body.password ?? '')
    const confirmCode = String(body.confirm_code ?? '').trim().toUpperCase()
    const mode = String(body.mode ?? 'archive').toLowerCase()

    if (!tenantId || !password) return json({ error: 'Business and password are required.' }, 400)

    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    })
    const { data: authData, error: authError } = await caller.auth.getUser()
    if (authError || !authData.user) return json({ error: 'Authentication required.' }, 401)

    const { data: adminContext, error: adminContextError } = await caller.rpc('platform_current_admin_context')
    if (adminContextError || adminContext?.is_admin !== true || adminContext?.role_key !== 'super_admin') {
      return json({ error: 'Platform Super Admin required.' }, 403)
    }

    const email = authData.user.email
    if (!email) return json({ error: 'Current admin account has no authentication email.' }, 400)

    // Re-authenticate the current admin with the supplied password.
    const verifier = createClient(url, anonKey, { auth: { persistSession: false } })
    const { error: passwordError } = await verifier.auth.signInWithPassword({ email, password })
    if (passwordError) return json({ error: 'Incorrect password.' }, 403)

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } })

    if (mode === 'archive') {
      const { error } = await caller.rpc('platform_business_archive_v41', {
        p_tenant_id: tenantId,
        p_reason: String(body.reason ?? 'Archived from Admin Panel'),
      })
      if (error) return json({ error: error.message }, 400)
      return json({ success: true, mode: 'archive' })
    }

    if (mode !== 'delete') return json({ error: 'Invalid deletion mode.' }, 400)
    if (!confirmCode) return json({ error: 'Business code confirmation is required.' }, 400)

    // Validate the immutable business code and division hierarchy inside a protected
    // SECURITY DEFINER RPC. This also writes the delete-request audit record without
    // exposing the private schema through PostgREST.
    const { data: deleteContext, error: prepareError } = await caller.rpc('platform_business_prepare_delete_v41', {
      p_tenant_id: tenantId,
      p_confirm_code: confirmCode,
    })
    if (prepareError) return json({ error: prepareError.message }, 409)
    if (!deleteContext?.tenant_id) return json({ error: 'Business delete validation failed.' }, 409)

    const { data: deleted, error: deleteError } = await admin.rpc('platform_business_delete_v471', {
      p_tenant_id: tenantId,
    })
    if (deleteError) return json({ error: `Delete blocked by database integrity: ${deleteError.message}` }, 409)
    if (deleted?.success !== true) return json({ error: 'Business deletion did not complete.' }, 409)

    return json({ success: true, mode: 'delete', tenant_id: tenantId })
  } catch (error) {
    return json({ error: String(error) }, 500)
  }
})
