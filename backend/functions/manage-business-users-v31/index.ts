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
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const url = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const authHeader = req.headers.get('Authorization') ?? ''

  try {
    const body = await req.json()
    const action = body.action

    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    })

    const {
      data: { user },
    } = await caller.auth.getUser()

    if (!user) {
      return json({ success: false, error: 'Authentication required.' }, 401)
    }

    const { data: isAdmin } = await caller.rpc('current_user_is_platform_admin')
    if (isAdmin !== true) {
      return json({ success: false, error: 'Platform admin required.' }, 403)
    }

    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false },
    })

    // Keep the existing, already-working privileged user-management function.
    // V3.1 wraps it to add username identity and does not duplicate auth logic.
    const oldUrl = `${url}/functions/v1/manage-business-users`
    const proxy = async (payload: unknown) => {
      const response = await fetch(oldUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: authHeader,
          apikey: anonKey,
        },
        body: JSON.stringify(payload),
      })
      return await response.json()
    }

    if (action === 'list') {
      const result = await proxy(body)
      if (result.success !== true) {
        return json(result, 400)
      }

      const ids = (result.users ?? [])
        .map((item: any) => item.user_id)
        .filter(Boolean)

      if (ids.length > 0) {
        const { data: names } = await admin
          .from('user_login_names')
          .select('user_id,username')
          .in('user_id', ids)

        const byId = new Map(
          (names ?? []).map((item: any) => [item.user_id, item.username]),
        )

        result.users = (result.users ?? []).map((item: any) => ({
          ...item,
          username: byId.get(item.user_id) ?? '',
        }))
      }

      return json(result)
    }

    if (action === 'create') {
      const username = String(body.username ?? '').trim().toLowerCase()
      const password = String(body.password ?? '')

      if (username.length < 4 || !/^[a-z0-9._-]+$/i.test(username)) {
        return json(
          {
            success: false,
            error:
              'Username must be at least 4 characters and use letters, numbers, dot, dash or underscore.',
          },
          400,
        )
      }

      if (password.length < 8) {
        return json(
          { success: false, error: 'Password must be at least 8 characters.' },
          400,
        )
      }

      const { data: exists } = await admin
        .from('user_login_names')
        .select('user_id')
        .ilike('username', username)
        .maybeSingle()

      if (exists) {
        return json({ success: false, error: 'Username already exists.' }, 409)
      }

      const syntheticEmail =
        `${username}.${crypto.randomUUID().slice(0, 8)}@login.flexierp.invalid`

      const result = await proxy({
        ...body,
        email: syntheticEmail,
        password,
      })

      if (result.success !== true) {
        return json(result, 400)
      }

      const listed = await proxy({
        action: 'list',
        tenant_id: body.tenant_id,
      })

      const created = (listed.users ?? []).find(
        (item: any) =>
          String(item.email ?? '').toLowerCase() === syntheticEmail.toLowerCase(),
      )

      if (!created?.user_id) {
        return json(
          {
            success: false,
            error: 'User created but username mapping could not be completed.',
          },
          500,
        )
      }

      const { error: mappingError } = await admin.from('user_login_names').upsert({
        user_id: created.user_id,
        username,
        auth_email: syntheticEmail,
      })

      if (mappingError) {
        return json(
          {
            success: false,
            error: `Username mapping failed: ${mappingError.message}`,
          },
          500,
        )
      }

      return json({
        ...result,
        username,
        user_id: created.user_id,
      })
    }

    if (action === 'reset_password') {
      const password = String(body.password ?? '')
      if (password.length < 8) {
        return json(
          { success: false, error: 'Password must be at least 8 characters.' },
          400,
        )
      }
    }

    // reset_password, delete and other existing actions continue through the
    // original function, so V3.1 does not weaken or duplicate its authorization.
    return json(await proxy(body))
  } catch (error) {
    return json({ success: false, error: String(error) }, 500)
  }
})
