import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
}
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: corsHeaders })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  const url = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const authHeader = req.headers.get('Authorization') ?? ''

  try {
    const body = await req.json()
    const tenantId = String(body.tenant_id ?? '')
    const action = String(body.action ?? '')
    if (!tenantId || !action) return json({ success: false, error: 'Tenant and action are required.' }, 400)

    const caller = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } })
    const { data: { user } } = await caller.auth.getUser()
    if (!user) return json({ success: false, error: 'Authentication required.' }, 401)

    const { data: context, error: contextError } = await caller.rpc('tenant_user_management_context', { p_tenant_id: tenantId })
    if (contextError || !context || context.can_manage !== true) return json({ success: false, error: 'User-management permission required.' }, 403)

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } })

    const ownerStatus = async (userId: string) => {
      const { data: membership } = await admin.from('tenant_memberships').select('id').eq('tenant_id', tenantId).eq('user_id', userId).eq('status', 'active').maybeSingle()
      if (!membership) return false
      const { data: ur } = await admin.from('user_roles').select('role_id').eq('tenant_id', tenantId).eq('membership_id', membership.id)
      const ids = (ur ?? []).map((x: any) => x.role_id)
      if (!ids.length) return false
      const { data: roles } = await admin.from('roles').select('key').in('id', ids)
      return (roles ?? []).some((r: any) => r.key === 'owner')
    }
    const callerIsOwner = await ownerStatus(user.id)

    const roleFor = async (roleKey: string) => {
      const { data } = await admin.from('roles').select('id,key,name,is_system').eq('tenant_id', tenantId).eq('key', roleKey).maybeSingle()
      return data
    }

    if (action === 'list') {
      const { data: memberships, error } = await admin.from('tenant_memberships').select('id,user_id,status,joined_at').eq('tenant_id', tenantId).order('joined_at')
      if (error) return json({ success: false, error: error.message }, 500)
      const ids = (memberships ?? []).map((m: any) => m.user_id)
      const { data: names } = ids.length ? await admin.from('user_login_names').select('user_id,username,auth_email').in('user_id', ids) : { data: [] as any[] }
      const { data: userRoles } = await admin.from('user_roles').select('membership_id,role_id').eq('tenant_id', tenantId)
      const roleIds = [...new Set((userRoles ?? []).map((x: any) => x.role_id))]
      const { data: roles } = roleIds.length ? await admin.from('roles').select('id,key,name,is_system').in('id', roleIds) : { data: [] as any[] }
      const { data: appAccess } = ids.length ? await admin.from('business_user_app_access').select('user_id,app_key,enabled').eq('tenant_id', tenantId).in('user_id', ids) : { data: [] as any[] }
      const { data: locationAccess } = ids.length ? await admin.from('business_user_location_access').select('user_id,location_id,access_level').eq('tenant_id', tenantId).in('user_id', ids) : { data: [] as any[] }
      const nameMap = new Map((names ?? []).map((x: any) => [x.user_id, x]))
      const { data: authUsers } = await admin.auth.admin.listUsers({ page: 1, perPage: 1000 })
      const authMap = new Map((authUsers?.users ?? []).map((x: any) => [x.id, x]))
      const roleMap = new Map((roles ?? []).map((x: any) => [x.id, x]))
      const users = (memberships ?? []).map((m: any) => {
        const n: any = nameMap.get(m.user_id) ?? {}
        const au: any = authMap.get(m.user_id) ?? {}
        const r = (userRoles ?? []).filter((x: any) => x.membership_id === m.id).map((x: any) => roleMap.get(x.role_id)).filter(Boolean)
        const clientEnabled = (appAccess ?? []).find((x: any) => x.user_id === m.user_id && x.app_key === 'client')?.enabled ?? true
        const posEnabled = (appAccess ?? []).find((x: any) => x.user_id === m.user_id && x.app_key === 'pos')?.enabled ?? false
        return {
          membership_id: m.id, user_id: m.user_id, name: String(au.user_metadata?.name ?? ''), username: n.username ?? '', email: n.auth_email ?? '', status: m.status,
          joined_at: m.joined_at, roles: r, client_enabled: clientEnabled, pos_enabled: posEnabled,
          locations: (locationAccess ?? []).filter((x: any) => x.user_id === m.user_id),
        }
      })
      return json({ success: true, users, roles: context.roles ?? [], locations: context.locations ?? [] })
    }

    if (action === 'create') {
      const username = String(body.username ?? '').trim().toLowerCase()
      const password = String(body.password ?? '')
      const name = String(body.name ?? '').trim()
      const roleKey = String(body.role_key ?? 'cashier')
      const posEnabled = body.pos_enabled === true
      const clientEnabled = body.client_enabled !== false
      const locationIds = Array.isArray(body.location_ids) ? body.location_ids.map(String) : []
      const accessLevel = ['view', 'operate', 'manage'].includes(String(body.access_level ?? 'operate')) ? String(body.access_level ?? 'operate') : 'operate'
      if (username.length < 4 || !/^[a-z0-9._-]+$/i.test(username)) return json({ success: false, error: 'Username must be at least 4 characters and use letters, numbers, dot, dash or underscore.' }, 400)
      if (password.length < 8) return json({ success: false, error: 'Password must be at least 8 characters.' }, 400)
      if (!name) return json({ success: false, error: 'Name is required.' }, 400)
      if (roleKey === 'owner' && !callerIsOwner) return json({ success: false, error: 'Only an owner can create another owner.' }, 403)
      const role = await roleFor(roleKey)
      if (!role) return json({ success: false, error: 'Invalid role.' }, 400)
      const { data: existing } = await admin.from('user_login_names').select('user_id').ilike('username', username).maybeSingle()
      if (existing) return json({ success: false, error: 'Username already exists.' }, 409)

      const syntheticEmail = `${username}.${crypto.randomUUID().slice(0, 8)}@login.flexierp.invalid`
      const { data: created, error: createError } = await admin.auth.admin.createUser({ email: syntheticEmail, password, email_confirm: true, user_metadata: { name } })
      if (createError || !created.user) return json({ success: false, error: createError?.message ?? 'Could not create user.' }, 400)
      const userId = created.user.id
      try {
        await admin.from('user_login_names').insert({ user_id: userId, username, auth_email: syntheticEmail })
        const { data: membership, error: memberError } = await admin.from('tenant_memberships').insert({ tenant_id: tenantId, user_id: userId, status: 'active' }).select('id').single()
        if (memberError || !membership) throw new Error(memberError?.message ?? 'Membership failed')
        await admin.from('user_roles').insert({ tenant_id: tenantId, membership_id: membership.id, role_id: role.id })
        await admin.from('business_user_app_access').upsert([
          { tenant_id: tenantId, user_id: userId, app_key: 'client', enabled: clientEnabled },
          { tenant_id: tenantId, user_id: userId, app_key: 'pos', enabled: posEnabled },
        ])
        if (locationIds.length) await admin.from('business_user_location_access').insert(locationIds.map((locationId: string) => ({ tenant_id: tenantId, user_id: userId, location_id: locationId, access_level: accessLevel })))
        return json({ success: true, user_id: userId, username })
      } catch (e) {
        await admin.auth.admin.deleteUser(userId)
        return json({ success: false, error: String(e) }, 500)
      }
    }

    const targetUserId = String(body.user_id ?? '')
    if (!targetUserId) return json({ success: false, error: 'User ID is required.' }, 400)
    const targetIsOwner = await ownerStatus(targetUserId)
    if (targetIsOwner && !callerIsOwner) return json({ success: false, error: 'Only an owner can modify an owner account.' }, 403)

    if (action === 'reset_password') {
      const password = String(body.password ?? '')
      if (password.length < 8) return json({ success: false, error: 'Password must be at least 8 characters.' }, 400)
      const { error } = await admin.auth.admin.updateUserById(targetUserId, { password })
      return error ? json({ success: false, error: error.message }, 400) : json({ success: true })
    }

    if (action === 'update_access') {
      const roleKey = String(body.role_key ?? '')
      const role = await roleFor(roleKey)
      if (!role) return json({ success: false, error: 'Invalid role.' }, 400)
      if (roleKey === 'owner' && !callerIsOwner) return json({ success: false, error: 'Only an owner can assign Owner.' }, 403)
      const { data: membership } = await admin.from('tenant_memberships').select('id').eq('tenant_id', tenantId).eq('user_id', targetUserId).eq('status', 'active').maybeSingle()
      if (!membership) return json({ success: false, error: 'Membership not found.' }, 404)
      await admin.from('user_roles').delete().eq('tenant_id', tenantId).eq('membership_id', membership.id)
      await admin.from('user_roles').insert({ tenant_id: tenantId, membership_id: membership.id, role_id: role.id })
      const locationIds = Array.isArray(body.location_ids) ? body.location_ids.map(String) : []
      await admin.from('business_user_app_access').upsert([
        { tenant_id: tenantId, user_id: targetUserId, app_key: 'client', enabled: body.client_enabled !== false },
        { tenant_id: tenantId, user_id: targetUserId, app_key: 'pos', enabled: body.pos_enabled === true },
      ])
      await admin.from('business_user_location_access').delete().eq('tenant_id', tenantId).eq('user_id', targetUserId)
      const accessLevel = ['view', 'operate', 'manage'].includes(String(body.access_level ?? 'operate')) ? String(body.access_level ?? 'operate') : 'operate'
      if (locationIds.length && roleKey !== 'owner') await admin.from('business_user_location_access').insert(locationIds.map((locationId: string) => ({ tenant_id: tenantId, user_id: targetUserId, location_id: locationId, access_level: accessLevel })))
      return json({ success: true })
    }

    if (action === 'delete') {
      if (targetIsOwner) return json({ success: false, error: 'Owner accounts cannot be removed here.' }, 400)
      const { data: membership } = await admin.from('tenant_memberships').select('id').eq('tenant_id', tenantId).eq('user_id', targetUserId).maybeSingle()
      if (membership) await admin.from('user_roles').delete().eq('tenant_id', tenantId).eq('membership_id', membership.id)
      await admin.from('business_user_location_access').delete().eq('tenant_id', tenantId).eq('user_id', targetUserId)
      await admin.from('business_user_app_access').delete().eq('tenant_id', tenantId).eq('user_id', targetUserId)
      await admin.from('tenant_memberships').delete().eq('tenant_id', tenantId).eq('user_id', targetUserId)
      return json({ success: true })
    }

    return json({ success: false, error: 'Unsupported action.' }, 400)
  } catch (error) {
    return json({ success: false, error: String(error) }, 500)
  }
})
