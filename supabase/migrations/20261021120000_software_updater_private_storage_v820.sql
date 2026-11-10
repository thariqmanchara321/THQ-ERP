-- THQ ERP V8.2.0 — Forward-Only Migration: Private Storage & Secure Release Authorization
-- Safe, idempotent, backward-compatible migration

begin;

-- ============================================================================
-- 1. HARDEN STORAGE BUCKET: ENFORCE PRIVATE STORAGE
-- ============================================================================

-- Ensure thq-releases bucket is private
update storage.buckets
set public = false
where id = 'thq-releases';

-- Drop public read policy on storage.objects for thq-releases
drop policy if exists thq_releases_public_read on storage.objects;

-- Ensure platform admins retain insert and update permissions
drop policy if exists thq_releases_admin_insert on storage.objects;
create policy thq_releases_admin_insert
  on storage.objects for insert
  with check (
    bucket_id = 'thq-releases'
    and private.platform_v2_is_admin()
  );

drop policy if exists thq_releases_admin_update on storage.objects;
create policy thq_releases_admin_update
  on storage.objects for update
  using (
    bucket_id = 'thq-releases'
    and private.platform_v2_is_admin()
  );

drop policy if exists thq_releases_admin_select on storage.objects;
create policy thq_releases_admin_select
  on storage.objects for select
  using (
    bucket_id = 'thq-releases'
    and private.platform_v2_is_admin()
  );

-- ============================================================================
-- 2. HARDEN RELEASE CHECK RPC WITH DEVICE IDENTITY & TIMED TOKEN SIGNING
-- ============================================================================

drop function if exists public.app_release_check_v820(text, text, text, text, integer, uuid, uuid);
drop function if exists public.app_release_check_v820(text, text, text, text, integer, uuid, uuid, text);

create or replace function public.app_release_check_v820(
  p_app_key text,
  p_platform text default 'windows',
  p_channel text default 'stable',
  p_current_version text default '',
  p_current_build integer default 0,
  p_device_id uuid default null,
  p_tenant_id uuid default null,
  p_device_secret_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'extensions', 'pg_temp'
as $$
declare
  v_app text := lower(trim(coalesce(p_app_key, '')));
  v_platform text := lower(trim(coalesce(p_platform, 'windows')));
  v_channel text := lower(trim(coalesce(p_channel, 'stable')));
  v_current_ver text := trim(coalesce(p_current_version, ''));
  v_current_build integer := coalesce(p_current_build, 0);

  v_tenant_id uuid := p_tenant_id;
  v_location_id uuid;
  v_dev_secret_hash text;
  v_dev_status text;

  v_latest public.platform_app_releases%rowtype;
  v_skipped public.platform_app_releases%rowtype;
  v_update_avail boolean := false;
  v_mandatory boolean := false;
  v_status text := 'no_update_available';
  v_telemetry_status text := 'no_update_available';
  v_cmp integer;
  v_cohort_val integer;

  v_auth_token text;
  v_secure_download_url text;
  v_storage_object_name text;
begin
  if v_app not in ('client', 'pos', 'admin', 'client_mobile', 'mobile_pos') then
    raise exception 'Invalid app key: %', p_app_key;
  end if;

  -- 1. Validate device registration if device_id is provided; reject untrusted IDs
  if p_device_id is not null then
    select tenant_id, location_id, device_secret_hash, status
    into v_tenant_id, v_location_id, v_dev_secret_hash, v_dev_status
    from public.business_devices
    where id = p_device_id and status in ('active', 'pending');

    if not found then
      -- Untrusted / revoked device ID supplied
      v_tenant_id := null;
      v_location_id := null;
      v_dev_secret_hash := null;
    elsif p_device_secret_hash is not null and v_dev_secret_hash is not null then
      if p_device_secret_hash <> v_dev_secret_hash then
        -- Secret mismatch: reject identity
        v_tenant_id := null;
        v_location_id := null;
        v_dev_secret_hash := null;
      end if;
    end if;
  end if;

  -- Calculate stable cohort for rollout consistency
  v_cohort_val := abs(hashtext(coalesce(p_device_id::text, v_tenant_id::text, 'thq_default_cohort')) % 100);

  -- 2. Select highest-priority matching release satisfying targeting, channel & rollout criteria
  select * into v_latest
  from public.platform_app_releases r
  where r.app_key = v_app
    and lower(r.platform) = v_platform
    and r.status in ('published', 'stable', 'beta')
    and (r.channel = v_channel or (v_channel = 'beta' and r.channel = 'stable') or (r.channel = 'stable'))
    and r.download_url is not null
    and length(trim(r.download_url)) > 0
    and r.sha256_checksum is not null
    and length(trim(r.sha256_checksum)) = 64
    and (r.rollout_percentage >= 100 or v_cohort_val < r.rollout_percentage)
    and (
      coalesce(r.target_type, 'all') = 'all'
      or (r.target_type = 'business' and v_tenant_id is not null and v_tenant_id = any(r.target_tenant_ids))
      or (r.target_type = 'store' and v_location_id is not null and v_location_id = any(r.target_store_ids))
      or (r.target_type = 'device' and p_device_id is not null and v_dev_secret_hash is not null and p_device_id = any(r.target_device_ids))
    )
  order by
    case coalesce(r.target_type, 'all')
      when 'device' then 4
      when 'store' then 3
      when 'business' then 2
      else 1
    end desc,
    private.semver_sort_key(r.version) desc,
    r.build_number desc,
    r.released_at desc
  limit 1;

  if v_latest.id is not null then
    -- Version comparison
    if v_current_ver = '' then
      v_update_avail := true;
    else
      v_cmp := private.compare_semver(v_latest.version, v_current_ver);
      if v_cmp > 0 or (v_cmp = 0 and v_latest.build_number > v_current_build) then
        v_update_avail := true;
      else
        v_update_avail := false;
      end if;
    end if;

    if coalesce(v_latest.mandatory, false) = true then
      v_mandatory := true;
    end if;

    if v_latest.status = 'blocked' then
      v_status := 'blocked';
      v_telemetry_status := 'blocked';
    elsif v_mandatory and v_update_avail then
      v_status := 'update_required';
      v_telemetry_status := 'update_available';
    elsif v_update_avail then
      v_status := 'update_available';
      v_telemetry_status := 'update_available';
    else
      v_status := 'latest';
      v_telemetry_status := 'no_update_available';
    end if;

    -- Upsert device_app_status telemetry
    if p_device_id is not null and v_tenant_id is not null then
      begin
        insert into public.device_app_status(
          device_id, tenant_id, app_key, platform, version, build_number, last_seen_at, metadata
        )
        values (
          p_device_id, v_tenant_id, v_app, v_platform, v_current_ver, v_current_build, now(),
          jsonb_build_object(
            'last_checked_at', now(),
            'channel', v_channel,
            'latest_available_version', v_latest.version,
            'latest_available_build', v_latest.build_number,
            'update_status', v_status,
            'target_type', v_latest.target_type
          )
        )
        on conflict (device_id) do update set
          tenant_id = excluded.tenant_id,
          app_key = excluded.app_key,
          platform = excluded.platform,
          version = excluded.version,
          build_number = excluded.build_number,
          last_seen_at = now(),
          metadata = public.device_app_status.metadata || excluded.metadata;
      exception when others then null;
      end;
    end if;

    -- Record in platform_app_update_logs for Admin visibility
    if p_device_id is not null or v_tenant_id is not null then
      begin
        insert into public.platform_app_update_logs(
          app_key, platform, device_id, tenant_id,
          from_version, from_build, to_version, to_build,
          status, details
        )
        values (
          v_app, v_platform, p_device_id, v_tenant_id,
          v_current_ver, v_current_build,
          v_latest.version, v_latest.build_number,
          v_telemetry_status,
          jsonb_build_object(
            'check_timestamp', now(),
            'channel', v_channel,
            'release_id', v_latest.id,
            'target_type', coalesce(v_latest.target_type, 'all'),
            'is_mandatory', v_mandatory
          )
        );
      exception when others then null;
      end;
    end if;

    -- Generate timed download token for private storage authentication
    v_auth_token := encode(
      extensions.digest(
        v_latest.id::text || ':' || coalesce(p_device_id::text, '') || ':' || coalesce(v_dev_secret_hash, '') || ':' || to_char(now() at time zone 'UTC', 'YYYYMMDDHH24'),
        'sha256'
      ),
      'hex'
    );

    -- Secure download endpoint: edge function app-release-download with .exe path to satisfy downloader validation
    v_storage_object_name := 'THQ-Business-v' || v_latest.version || '-b' || v_latest.build_number::text || '-windows-x64.exe';
    v_secure_download_url := 'https://yguzrxcdvyimjrfvtcvp.supabase.co/functions/v1/app-release-download/' || v_storage_object_name
      || '?release_id=' || v_latest.id::text
      || '&device_id=' || coalesce(p_device_id::text, '')
      || '&token=' || v_auth_token;

    return jsonb_build_object(
      'update_available', v_update_avail,
      'is_mandatory', v_mandatory,
      'status', v_status,
      'app_key', v_app,
      'platform', v_platform,
      'channel', v_latest.channel,
      'target_type', coalesce(v_latest.target_type, 'all'),
      'latest_version', v_latest.version,
      'latest_build', v_latest.build_number,
      'current_version', v_current_ver,
      'current_build', v_current_build,
      'download_url', v_secure_download_url,
      'package_size_bytes', coalesce(v_latest.package_size_bytes, 0),
      'sha256_checksum', v_latest.sha256_checksum,
      'publisher_signature', v_latest.publisher_signature,
      'release_notes', coalesce(v_latest.release_notes, ''),
      'min_supported_version', v_latest.min_supported_version,
      'released_at', v_latest.released_at,
      'backend_contract', public.thq_backend_contract_v47()
    );
  end if;

  -- 3. No matching release: check if a newer release exists but this device is NOT eligible
  select * into v_skipped
  from public.platform_app_releases r
  where r.app_key = v_app
    and lower(r.platform) = v_platform
    and r.status in ('published', 'stable', 'beta')
    and (r.download_url is not null and length(trim(r.download_url)) > 0)
    and (private.compare_semver(r.version, v_current_ver) > 0 or (private.compare_semver(r.version, v_current_ver) = 0 and r.build_number > v_current_build))
  order by private.semver_sort_key(r.version) desc, r.build_number desc
  limit 1;

  if v_skipped.id is not null then
    v_status := 'not_eligible';
    v_telemetry_status := 'not_eligible';
  else
    v_status := 'no_update_available';
    v_telemetry_status := 'no_update_available';
  end if;

  -- Upsert device_app_status when not updating
  if p_device_id is not null and v_tenant_id is not null then
    begin
      insert into public.device_app_status(
        device_id, tenant_id, app_key, platform, version, build_number, last_seen_at, metadata
      )
      values (
        p_device_id, v_tenant_id, v_app, v_platform, v_current_ver, v_current_build, now(),
        jsonb_build_object(
          'last_checked_at', now(),
          'channel', v_channel,
          'update_status', v_status
        )
      )
      on conflict (device_id) do update set
        tenant_id = excluded.tenant_id,
        app_key = excluded.app_key,
        platform = excluded.platform,
        version = excluded.version,
        build_number = excluded.build_number,
        last_seen_at = now(),
        metadata = public.device_app_status.metadata || excluded.metadata;
    exception when others then null;
    end;
  end if;

  -- Record telemetry log into platform_app_update_logs for Admin clarity
  if p_device_id is not null or v_tenant_id is not null then
    begin
      insert into public.platform_app_update_logs(
        app_key, platform, device_id, tenant_id,
        from_version, from_build, to_version, to_build,
        status, details
      )
      values (
        v_app, v_platform, p_device_id, v_tenant_id,
        v_current_ver, v_current_build,
        coalesce(v_skipped.version, v_current_ver),
        coalesce(v_skipped.build_number, v_current_build),
        v_telemetry_status,
        jsonb_build_object(
          'check_timestamp', now(),
          'channel', v_channel,
          'skipped_release_id', v_skipped.id,
          'skipped_target_type', v_skipped.target_type
        )
      );
    exception when others then null;
    end;
  end if;

  return jsonb_build_object(
    'update_available', false,
    'is_mandatory', false,
    'status', v_status,
    'app_key', v_app,
    'platform', v_platform,
    'channel', v_channel,
    'target_type', 'all',
    'latest_version', coalesce(v_skipped.version, v_current_ver),
    'latest_build', coalesce(v_skipped.build_number, v_current_build),
    'current_version', v_current_ver,
    'current_build', v_current_build,
    'download_url', null,
    'package_size_bytes', 0,
    'sha256_checksum', null,
    'publisher_signature', null,
    'release_notes', '',
    'min_supported_version', null,
    'released_at', null,
    'backend_contract', public.thq_backend_contract_v47()
  );
end;
$$;

revoke all on function public.app_release_check_v820(text, text, text, text, integer, uuid, uuid, text) from public;
grant execute on function public.app_release_check_v820(text, text, text, text, integer, uuid, uuid, text) to anon, authenticated, service_role;

-- ============================================================================
-- 3. SANITIZE STORED DOWNLOAD URLS IN PLATFORM_APP_RELEASES
-- ============================================================================

-- Ensure release 2ce4c76b-22ff-4730-bb64-b7c32b5b0667 points to internal storage path
update public.platform_app_releases
set download_url = 'installers/THQ-Business-v8.2.0-build17-windows-x64.exe',
    package_size_bytes = 17715089,
    sha256_checksum = '42b5bb7c9f67f5f0224e9214397080a3e24e6ba8c454314feea637872c8ddf84'
where id = '2ce4c76b-22ff-4730-bb64-b7c32b5b0667';

commit;
