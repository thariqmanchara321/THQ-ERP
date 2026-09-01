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
    const username = String(body.username ?? '').trim().toLowerCase()
    const password = String(body.password ?? '')
    const appKey = String(body.app_key ?? 'admin').trim().toLowerCase()
    const deviceId = String(body.device_id ?? '').trim()
    const deviceSecret = String(body.device_secret ?? '').trim()
    const authorizationScope = String(body.authorization_scope ?? '').trim().toLowerCase()
    if (username.length < 4 || !password) return json({ error: 'Username and password are required.' }, 400)
    if (!['admin','client','pos'].includes(appKey)) return json({ error: 'Invalid application.' }, 400)
    if (!['', 'change_binding'].includes(authorizationScope)) return json({ error: 'Invalid authorization scope.' }, 400)

    const url = Deno.env.get('SUPABASE_URL')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const admin = createClient(url, serviceKey, { auth: { persistSession: false } })

    let device: any = null
    let membership: any = null
    if (appKey !== 'admin') {
      if (!deviceId || !deviceSecret) return json({ error: 'This system must be activated before login.', code: 'DEVICE_ACTIVATION_REQUIRED' }, 403)
      const { data } = await admin.from('business_devices').select('id,tenant_id,location_id,app_type,status,device_secret_hash').eq('id',deviceId).maybeSingle()
      const suppliedHash = await sha256(deviceSecret)
      const { data: installation } = await admin.from('system_installations')
        .select('id,secret_hash,status').eq('system_id', deviceId).eq('status', 'active').maybeSingle()
      if (!data || data.status !== 'active' || data.app_type !== appKey || data.device_secret_hash !== suppliedHash || !installation || installation.secret_hash !== suppliedHash) {
        return json({ error: 'Device registration is invalid or revoked.', code:'DEVICE_INVALID' }, 403)
      }
      device = data
    }

    const { data: identity, error: identityError } = await admin.from('user_login_names').select('user_id,auth_email').eq('username', username).maybeSingle()
    if (identityError || !identity) return json({ error: 'Invalid username or password.' }, 401)

    if (device) {
      const { data: activeMembership } = await admin.from('tenant_memberships').select('id').eq('tenant_id',device.tenant_id).eq('user_id',identity.user_id).eq('status','active').maybeSingle()
      if (!activeMembership) return json({ error: 'This user does not have access to this business.', code:'TENANT_ACCESS_DENIED' }, 403)
      membership = activeMembership
    }

    const auth = createClient(url, anonKey, { auth: { persistSession: false } })
    const { data, error } = await auth.auth.signInWithPassword({ email: identity.auth_email, password })
    if (error || !data.session) return json({ error: 'Invalid username or password.' }, 401)

    if (authorizationScope === 'change_binding') {
      if (!device || !membership) {
        return json({ error: 'A currently activated Client/POS is required.', code: 'DEVICE_ACTIVATION_REQUIRED' }, 403)
      }

      const { data: userRoles, error: userRolesError } = await admin
        .from('user_roles')
        .select('role_id')
        .eq('tenant_id', device.tenant_id)
        .eq('membership_id', membership.id)
      if (userRolesError) return json({ error: 'Could not verify administrator role.' }, 500)

      const roleIds = (userRoles ?? []).map((row: any) => row.role_id)
      if (!roleIds.length) {
        return json({ error: 'Owner or administrator password is required.', code: 'OWNER_ADMIN_REQUIRED' }, 403)
      }

      const { data: roles, error: rolesError } = await admin
        .from('roles')
        .select('id,key')
        .in('id', roleIds)
      if (rolesError) return json({ error: 'Could not verify administrator role.' }, 500)

      const isOwnerOrAdminRole = (roles ?? []).some(
        (role: any) => role.key === 'owner' || role.key === 'admin',
      )
      const { data: settingsPermission, error: permissionError } = await admin
        .from('role_permissions')
        .select('role_id')
        .in('role_id', roleIds)
        .eq('permission_key', 'settings.manage')
        .limit(1)
      if (permissionError) return json({ error: 'Could not verify administrator permission.' }, 500)

      if (!isOwnerOrAdminRole && !(settingsPermission ?? []).length) {
        return json({ error: 'Owner or administrator password is required.', code: 'OWNER_ADMIN_REQUIRED' }, 403)
      }

      const seenAt = new Date().toISOString()
      await admin.from('business_devices').update({ last_seen_at:seenAt }).eq('id',device.id)
      await admin.from('system_installations').update({ last_seen_at:seenAt }).eq('system_id',device.id).eq('status','active')
      return json({
        authorized: true,
        tenant_id: device.tenant_id,
        location_id: device.location_id,
        device_id: device.id,
      })
    }

    if (device) {
      const seenAt = new Date().toISOString()
      await admin.from('business_devices').update({ last_seen_at:seenAt }).eq('id',device.id)
      await admin.from('system_installations').update({ last_seen_at:seenAt }).eq('system_id',device.id).eq('status','active')
    }
    return json({
      access_token:data.session.access_token, refresh_token:data.session.refresh_token, expires_at:data.session.expires_at, user:data.user,
      tenant_id:device?.tenant_id ?? null, location_id:device?.location_id ?? null, device_id:device?.id ?? null,
    })
  } catch (_) {
    return json({ error: 'Login failed.' }, 500)
  }
})
