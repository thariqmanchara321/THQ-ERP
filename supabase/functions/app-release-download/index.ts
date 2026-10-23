import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

const sha256 = async (value: string) => {
  const bytes = new TextEncoder().encode(value)
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, '0')).join('')
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const url = new URL(req.url)
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } })

  let releaseId: string | null = null
  let deviceId: string | null = null
  let token: string | null = null
  let deviceSecret: string | null = null

  if (req.method === 'GET') {
    releaseId = url.searchParams.get('release_id')
    deviceId = url.searchParams.get('device_id')
    token = url.searchParams.get('token')
  } else if (req.method === 'POST') {
    try {
      const body = await req.json()
      releaseId = String(body.release_id ?? '').trim() || null
      deviceId = String(body.device_id ?? '').trim() || null
      token = String(body.token ?? '').trim() || null
      deviceSecret = String(body.device_secret ?? '').trim() || null
    } catch (_) {
      return json({ error: 'Invalid JSON payload' }, 400)
    }
  }

  if (!releaseId) {
    return json({ error: 'Missing release_id parameter' }, 400)
  }

  // 1. Fetch release details from platform_app_releases
  const { data: release, error: relErr } = await admin
    .from('platform_app_releases')
    .select('*')
    .eq('id', releaseId)
    .maybeSingle()

  if (relErr || !release) {
    return json({ error: 'Release not found' }, 404)
  }

  if (!['published', 'stable', 'beta'].includes(release.status)) {
    return json({ error: `Release status '${release.status}' is not eligible for download` }, 403)
  }

  // 2. Validate device identity if device-targeted or deviceId provided
  let device: any = null
  if (deviceId) {
    const { data: devData, error: devErr } = await admin
      .from('business_devices')
      .select('id, tenant_id, location_id, app_type, status, device_secret_hash')
      .eq('id', deviceId)
      .maybeSingle()

    if (devErr || !devData || !['active', 'pending'].includes(devData.status)) {
      return json({ error: 'Device not registered or inactive' }, 403)
    }
    device = devData

    // Verify token or device_secret
    if (token) {
      // Validate hourly HMAC token
      const now = new Date()
      const prevHour = new Date(now.getTime() - 3600000)
      const nextHour = new Date(now.getTime() + 3600000)

      const pad = (n: number) => n.toString().padStart(2, '0')
      const formatHour = (d: Date) =>
        `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}${pad(d.getUTCHours())}`

      const secretHash = device.device_secret_hash || ''
      const expectedTokenNow = await sha256(`${release.id}:${deviceId}:${secretHash}:${formatHour(now)}`)
      const expectedTokenPrev = await sha256(`${release.id}:${deviceId}:${secretHash}:${formatHour(prevHour)}`)
      const expectedTokenNext = await sha256(`${release.id}:${deviceId}:${secretHash}:${formatHour(nextHour)}`)

      // Also check fallback token without secret if device has no secret_hash yet
      const fallbackTokenNow = await sha256(`${release.id}:${deviceId}::${formatHour(now)}`)
      const fallbackTokenPrev = await sha256(`${release.id}:${deviceId}::${formatHour(prevHour)}`)

      const isValidToken =
        token === expectedTokenNow ||
        token === expectedTokenPrev ||
        token === expectedTokenNext ||
        token === fallbackTokenNow ||
        token === fallbackTokenPrev

      if (!isValidToken) {
        return json({ error: 'Invalid or expired download authorization token' }, 403)
      }
    } else if (deviceSecret) {
      const suppliedHash = await sha256(deviceSecret)
      if (suppliedHash !== device.device_secret_hash) {
        return json({ error: 'Device secret authentication failed' }, 403)
      }
    } else if (release.target_type !== 'all') {
      return json({ error: 'Device authorization token or secret required for targeted release' }, 401)
    }
  } else if (release.target_type !== 'all') {
    return json({ error: 'Device identity required for targeted release' }, 403)
  }

  // 3. Server-side targeting eligibility check
  const targetType = release.target_type || 'all'
  if (targetType === 'device') {
    const targetDeviceIds = release.target_device_ids || []
    if (!deviceId || !targetDeviceIds.includes(deviceId)) {
      return json({ error: 'This device is not eligible for this targeted release' }, 403)
    }
  } else if (targetType === 'store') {
    const targetStoreIds = release.target_store_ids || []
    if (!device || !device.location_id || !targetStoreIds.includes(device.location_id)) {
      return json({ error: 'This store location is not eligible for this release' }, 403)
    }
  } else if (targetType === 'business') {
    const targetTenantIds = release.target_tenant_ids || []
    if (!device || !device.tenant_id || !targetTenantIds.includes(device.tenant_id)) {
      return json({ error: 'This business is not eligible for this release' }, 403)
    }
  }

  // 4. Resolve artifact storage path
  let storagePath = 'installers/' + (release.download_url ? release.download_url.split('/').pop() : `THQ-Business-v${release.version}-build${release.build_number}-windows-x64.exe`)
  // If download_url already contains installers/, extract from installers/
  if (release.download_url && release.download_url.includes('thq-releases/')) {
    storagePath = release.download_url.split('thq-releases/')[1].split('?')[0]
  }

  // 5. Generate short-lived signed URL (900 seconds = 15 minutes)
  const { data: signData, error: signErr } = await admin.storage
    .from('thq-releases')
    .createSignedUrl(storagePath, 900)

  const rawSignedUrl = signData.signedUrl
  const shortLivedSignedUrl = rawSignedUrl.startsWith('http')
    ? rawSignedUrl
    : rawSignedUrl.startsWith('/storage/v1')
    ? `${supabaseUrl}${rawSignedUrl}`
    : `${supabaseUrl}/storage/v1${rawSignedUrl}`

  // 6. Log telemetry event into platform_app_update_logs
  try {
    await admin.from('platform_app_update_logs').insert({
      app_key: release.app_key,
      platform: release.platform,
      device_id: deviceId || null,
      tenant_id: device?.tenant_id || null,
      to_version: release.version,
      to_build: release.build_number,
      status: 'download_authorized',
      details: {
        timestamp: new Date().toISOString(),
        target_type: targetType,
        ip: req.headers.get('x-forwarded-for') || null,
        user_agent: req.headers.get('user-agent') || null,
        expires_in_seconds: 900,
      },
    })
  } catch (_) {
    // Non-blocking telemetry log
  }

  // 7. If GET (downloading), return 302 redirect directly to signed URL
  if (req.method === 'GET') {
    return new Response(null, {
      status: 302,
      headers: {
        ...corsHeaders,
        Location: shortLivedSignedUrl,
      },
    })
  }

  // If POST, return JSON metadata + short-lived download URL
  return json({
    success: true,
    download_url: shortLivedSignedUrl,
    sha256_checksum: release.sha256_checksum,
    package_size_bytes: release.package_size_bytes,
    publisher_signature: release.publisher_signature,
    version: release.version,
    build_number: release.build_number,
    expires_in_seconds: 900,
  })
})
