-- THQ ERP V8.2.0 — Software Updater Targeting, Storage & Telemetry Clarity
-- Safe, idempotent, backward-compatible migration

begin;

-- ============================================================================
-- 1. EXTEND PLATFORM_APP_RELEASES STATUS & TARGETING CONSTRAINTS
-- ============================================================================

alter table public.platform_app_releases
  drop constraint if exists platform_app_releases_status_check;

alter table public.platform_app_releases
  add constraint platform_app_releases_status_check
  check (status = any (array[
    'draft'::text,
    'uploaded'::text,
    'verified'::text,
    'testing'::text,
    'approved'::text,
    'published'::text,
    'stable'::text,
    'beta'::text,
    'paused'::text,
    'withdrawn'::text,
    'revoked'::text,
    'deprecated'::text,
    'blocked'::text
  ]));

-- Granular targeting columns
alter table public.platform_app_releases
  add column if not exists target_type text not null default 'all',
  add column if not exists target_tenant_ids uuid[] default null,
  add column if not exists target_store_ids uuid[] default null,
  add column if not exists target_device_ids uuid[] default null;

alter table public.platform_app_releases
  drop constraint if exists platform_app_releases_target_type_check;

alter table public.platform_app_releases
  add constraint platform_app_releases_target_type_check
  check (target_type = any (array['all'::text, 'business'::text, 'store'::text, 'device'::text]));

-- ============================================================================
-- 2. TARGETING PREVIEW & CATALOG RPCS FOR ADMIN PANEL
-- ============================================================================

drop function if exists public.platform_release_preview_targets_v820(text, text, text, text, uuid[], uuid[], uuid[]);

create or replace function public.platform_release_preview_targets_v820(
  p_app_key text,
  p_platform text default 'windows',
  p_channel text default 'stable',
  p_target_type text default 'all',
  p_target_tenant_ids uuid[] default null,
  p_target_store_ids uuid[] default null,
  p_target_device_ids uuid[] default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_count integer := 0;
  v_devices jsonb := '[]'::jsonb;
begin
  if not private.platform_v2_is_admin() then
    raise exception 'Platform admin required';
  end if;

  select count(distinct d.id),
         coalesce(jsonb_agg(jsonb_build_object(
           'device_id', d.id,
           'device_code', d.device_code,
           'device_name', d.name,
           'business_name', t.name,
           'location_code', l.location_code
         )), '[]'::jsonb)
  into v_count, v_devices
  from public.business_devices d
  join public.business_locations l on l.id = d.location_id
  join public.tenants t on t.id = d.tenant_id
  left join public.device_app_status s on s.device_id = d.id
  where d.status in ('active', 'pending')
    and (p_app_key is null or d.app_type = lower(trim(p_app_key)) or s.app_key = lower(trim(p_app_key)))
    and (
      coalesce(p_target_type, 'all') = 'all'
      or (p_target_type = 'business' and d.tenant_id = any(p_target_tenant_ids))
      or (p_target_type = 'store' and d.location_id = any(p_target_store_ids))
      or (p_target_type = 'device' and d.id = any(p_target_device_ids))
    );

  return jsonb_build_object(
    'target_type', coalesce(p_target_type, 'all'),
    'eligible_count', coalesce(v_count, 0),
    'sample_devices', coalesce(v_devices, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.platform_release_preview_targets_v820(text, text, text, text, uuid[], uuid[], uuid[]) from public;
grant execute on function public.platform_release_preview_targets_v820(text, text, text, text, uuid[], uuid[], uuid[]) to authenticated, service_role;

drop function if exists public.platform_targeting_catalog_v820();

create or replace function public.platform_targeting_catalog_v820()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_businesses jsonb;
  v_stores jsonb;
  v_devices jsonb;
begin
  if not private.platform_v2_is_admin() then
    raise exception 'Platform admin required';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id,
    'name', t.name,
    'business_code', t.business_code,
    'status', t.status
  ) order by t.name), '[]'::jsonb) into v_businesses
  from public.tenants t;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', l.id,
    'tenant_id', l.tenant_id,
    'name', l.name,
    'location_code', l.location_code
  ) order by l.name), '[]'::jsonb) into v_stores
  from public.business_locations l;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d.id,
    'tenant_id', d.tenant_id,
    'location_id', d.location_id,
    'device_code', d.device_code,
    'name', d.name,
    'app_type', d.app_type,
    'status', d.status
  ) order by d.name), '[]'::jsonb) into v_devices
  from public.business_devices d;

  return jsonb_build_object(
    'businesses', coalesce(v_businesses, '[]'::jsonb),
    'stores', coalesce(v_stores, '[]'::jsonb),
    'devices', coalesce(v_devices, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.platform_targeting_catalog_v820() from public;
grant execute on function public.platform_targeting_catalog_v820() to authenticated, service_role;

-- ============================================================================
-- 3. EXTENDED PLATFORM_APP_RELEASE_SAVE_V820 WITH TARGETING SUPPORT
-- ============================================================================

drop function if exists public.platform_app_release_save_v820(uuid, text, text, text, integer, text, text, boolean, boolean, text, text, bigint, text, text, text, integer);
drop function if exists public.platform_app_release_save_v820(uuid, text, text, text, integer, text, text, boolean, boolean, text, text, bigint, text, text, text, integer, text, uuid[], uuid[], uuid[]);

create or replace function public.platform_app_release_save_v820(
  p_id uuid default null,
  p_app_key text default 'client',
  p_platform text default 'windows',
  p_version text default '8.2.0',
  p_build_number integer default 1,
  p_channel text default 'stable',
  p_status text default 'published',
  p_minimum_supported boolean default false,
  p_mandatory boolean default false,
  p_release_notes text default '',
  p_download_url text default null,
  p_package_size_bytes bigint default 0,
  p_sha256_checksum text default null,
  p_publisher_signature text default null,
  p_min_supported_version text default null,
  p_rollout_percentage integer default 100,
  p_target_type text default 'all',
  p_target_tenant_ids uuid[] default null,
  p_target_store_ids uuid[] default null,
  p_target_device_ids uuid[] default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_id uuid;
  v_app text := lower(trim(coalesce(p_app_key, '')));
  v_platform text := lower(trim(coalesce(p_platform, 'windows')));
  v_channel text := lower(trim(coalesce(p_channel, 'stable')));
  v_status text := lower(trim(coalesce(p_status, 'published')));
  v_ver text := trim(coalesce(p_version, ''));
  v_sha text := lower(trim(coalesce(p_sha256_checksum, '')));
  v_target_type text := lower(trim(coalesce(p_target_type, 'all')));
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('technical_admin') then
    raise exception 'Platform technical admin role required';
  end if;

  if v_app not in ('client', 'pos', 'admin', 'client_mobile', 'mobile_pos') then
    raise exception 'Invalid app key: %', p_app_key;
  end if;

  if v_platform not in ('windows', 'android', 'ios', 'web', 'macos', 'linux') then
    raise exception 'Invalid platform: %', p_platform;
  end if;

  if v_channel not in ('stable', 'beta', 'alpha', 'internal') then
    raise exception 'Invalid channel: %', p_channel;
  end if;

  if v_ver = '' then
    raise exception 'Version cannot be empty';
  end if;

  if p_build_number <= 0 then
    raise exception 'Build number must be greater than zero';
  end if;

  if v_target_type not in ('all', 'business', 'store', 'device') then
    raise exception 'Invalid target type: %', p_target_type;
  end if;

  -- Publishing integrity check: published/stable releases MUST have download_url and sha256
  if v_status in ('published', 'stable') then
    if p_download_url is null or length(trim(p_download_url)) = 0 then
      raise exception 'Cannot publish release without download URL';
    end if;
    if v_sha is null or length(v_sha) <> 64 then
      raise exception 'Cannot publish release without valid 64-char SHA-256 checksum';
    end if;
    if coalesce(p_package_size_bytes, 0) <= 0 then
      raise exception 'Cannot publish release with zero package size';
    end if;
  end if;

  if p_id is null then
    insert into public.platform_app_releases(
      app_key, platform, version, build_number,
      channel, status, minimum_supported, mandatory,
      release_notes, download_url, package_size_bytes,
      sha256_checksum, publisher_signature, min_supported_version,
      rollout_percentage, target_type, target_tenant_ids,
      target_store_ids, target_device_ids,
      created_by, released_at, updated_at
    )
    values (
      v_app, v_platform, v_ver, p_build_number,
      v_channel, v_status, coalesce(p_minimum_supported, false), coalesce(p_mandatory, false),
      coalesce(p_release_notes, ''), nullif(trim(coalesce(p_download_url, '')), ''), coalesce(p_package_size_bytes, 0),
      nullif(v_sha, ''), nullif(trim(coalesce(p_publisher_signature, '')), ''), nullif(trim(coalesce(p_min_supported_version, '')), ''),
      least(greatest(coalesce(p_rollout_percentage, 100), 0), 100),
      v_target_type, p_target_tenant_ids, p_target_store_ids, p_target_device_ids,
      auth.uid(),
      case when v_status in ('published', 'stable') then now() else null end,
      now()
    )
    returning id into v_id;
  else
    update public.platform_app_releases
    set
      app_key = v_app,
      platform = v_platform,
      version = v_ver,
      build_number = p_build_number,
      channel = v_channel,
      status = v_status,
      minimum_supported = coalesce(p_minimum_supported, false),
      mandatory = coalesce(p_mandatory, false),
      release_notes = coalesce(p_release_notes, ''),
      download_url = nullif(trim(coalesce(p_download_url, '')), ''),
      package_size_bytes = coalesce(p_package_size_bytes, 0),
      sha256_checksum = nullif(v_sha, ''),
      publisher_signature = nullif(trim(coalesce(p_publisher_signature, '')), ''),
      min_supported_version = nullif(trim(coalesce(p_min_supported_version, '')), ''),
      rollout_percentage = least(greatest(coalesce(p_rollout_percentage, 100), 0), 100),
      target_type = v_target_type,
      target_tenant_ids = p_target_tenant_ids,
      target_store_ids = p_target_store_ids,
      target_device_ids = p_target_device_ids,
      released_at = case when v_status in ('published', 'stable') and released_at is null then now() else released_at end,
      updated_at = now()
    where id = p_id
    returning id into v_id;
  end if;

  if v_id is null then
    raise exception 'Release not found for id: %', p_id;
  end if;

  perform private.platform_audit_write(
    'app_release.save', 'platform_app_releases', v_id::text, null,
    jsonb_build_object('app_key', v_app, 'version', v_ver, 'build', p_build_number, 'status', v_status, 'target_type', v_target_type)
  );

  return v_id;
end;
$$;

revoke all on function public.platform_app_release_save_v820(uuid, text, text, text, integer, text, text, boolean, boolean, text, text, bigint, text, text, text, integer, text, uuid[], uuid[], uuid[]) from public;
grant execute on function public.platform_app_release_save_v820(uuid, text, text, text, integer, text, text, boolean, boolean, text, text, bigint, text, text, text, integer, text, uuid[], uuid[], uuid[]) to authenticated, service_role;

-- ============================================================================
-- 4. DETERMINISTIC UPDATE DISCOVERY RPC WITH CLEAR STATUS & TELEMETRY
-- ============================================================================

drop function if exists public.app_release_check_v820(text, text, text, text, integer, uuid, uuid);

create or replace function public.app_release_check_v820(
  p_app_key text,
  p_platform text,
  p_channel text default 'stable',
  p_current_version text default '',
  p_current_build integer default 0,
  p_device_id uuid default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_latest record;
  v_skipped record;
  v_app text := lower(trim(coalesce(p_app_key, '')));
  v_platform text := lower(trim(coalesce(p_platform, '')));
  v_channel text := lower(trim(coalesce(p_channel, 'stable')));
  v_current_ver text := trim(coalesce(p_current_version, ''));
  v_current_build int := greatest(coalesce(p_current_build, 0), 0);
  v_tenant_id uuid := p_tenant_id;
  v_location_id uuid;
  v_dev_tenant uuid;
  v_dev_location uuid;
  v_update_avail boolean := false;
  v_mandatory boolean := false;
  v_status text := 'no_update_available';
  v_telemetry_status text := 'no_update_available';
  v_cmp integer;
  v_cohort_val integer := 0;
begin
  if v_app not in ('client', 'pos', 'admin', 'client_mobile', 'mobile_pos') then
    raise exception 'Invalid app key: %', p_app_key;
  end if;

  -- Resolve tenant_id and location_id from trusted business_devices registry if device_id is supplied
  if p_device_id is not null then
    select tenant_id, location_id into v_dev_tenant, v_dev_location
    from public.business_devices
    where id = p_device_id and status in ('active', 'pending');
    if found then
      v_tenant_id := coalesce(v_dev_tenant, v_tenant_id);
      v_location_id := coalesce(v_dev_location, v_location_id);
    end if;
  end if;

  -- Calculate stable cohort for rollout consistency
  v_cohort_val := abs(hashtext(coalesce(p_device_id::text, v_tenant_id::text, 'thq_default_cohort')) % 100);

  -- 1. Select highest-priority matching release satisfying targeting, channel & rollout criteria
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
      or (r.target_type = 'device' and p_device_id is not null and p_device_id = any(r.target_device_ids))
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
      'download_url', v_latest.download_url,
      'package_size_bytes', coalesce(v_latest.package_size_bytes, 0),
      'sha256_checksum', v_latest.sha256_checksum,
      'publisher_signature', v_latest.publisher_signature,
      'release_notes', coalesce(v_latest.release_notes, ''),
      'min_supported_version', v_latest.min_supported_version,
      'released_at', v_latest.released_at,
      'backend_contract', public.thq_backend_contract_v47()
    );
  end if;

  -- 2. No matching release: check if a newer release exists but this device is NOT eligible
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

revoke all on function public.app_release_check_v820(text, text, text, text, integer, uuid, uuid) from public;
grant execute on function public.app_release_check_v820(text, text, text, text, integer, uuid, uuid) to anon, authenticated, service_role;

-- ============================================================================
-- 5. STORAGE BUCKET FOR RELEASES
-- ============================================================================

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values (
  'thq-releases',
  'thq-releases',
  true,
  262144000, -- 250MB
  array['application/octet-stream', 'application/x-msdownload', 'application/zip', 'application/vnd.android.package-archive']::text[]
)
on conflict (id) do update set
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists thq_releases_public_read on storage.objects;
create policy thq_releases_public_read
  on storage.objects for select
  using (bucket_id = 'thq-releases');

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

commit;
