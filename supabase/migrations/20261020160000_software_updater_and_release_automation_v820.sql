-- THQ ERP V8.2.0 — Complete Software Updater, Security Hardening & Release Automation
-- Phase 1 - 11 Backend Implementation
-- Idempotent, safe, backward-compatible migration

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

-- Granular targeting columns (Phase 4 requirement)
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
-- 2. SECURE & DETERMINISTIC UPDATE DISCOVERY RPC (app_release_check_v820)
-- ============================================================================

drop function if exists public.app_release_check_v820(text, text, text, text, integer, uuid, uuid);
drop function if exists public.app_release_check_v820(text, text, text, text, integer, uuid, uuid, uuid);

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
  v_status text := 'latest';
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

  -- Select highest-priority matching release satisfying targeting, channel & rollout criteria
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
      -- Target Option A: All installations
      coalesce(r.target_type, 'all') = 'all'
      -- Target Option B: Specific Businesses (Fail closed if tenant not proven)
      or (r.target_type = 'business' and v_tenant_id is not null and v_tenant_id = any(r.target_tenant_ids))
      -- Target Option C: Specific Stores (Fail closed if store not proven)
      or (r.target_type = 'store' and v_location_id is not null and v_location_id = any(r.target_store_ids))
      -- Target Option D: Specific Devices (Fail closed if device not proven)
      or (r.target_type = 'device' and p_device_id is not null and p_device_id = any(r.target_device_ids))
    )
  order by
    -- Priority: Device-specific > Store-specific > Business-specific > All
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
    -- Protect against downgrade attacks: latest version must be semantically newer
    -- or same version with higher build number
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
    elsif v_mandatory and v_update_avail then
      v_status := 'update_required';
    elsif v_update_avail then
      v_status := 'update_available';
    else
      v_status := 'latest';
    end if;

    -- Upsert device_app_status telemetry safely if device_id is provided
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
      exception when others then
        -- Telemetry logging must never block update discovery
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

  -- Upsert device_app_status when already up to date
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
          'update_status', 'latest'
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
    exception when others then
      -- Telemetry logging must never block update discovery
    end;
  end if;

  return jsonb_build_object(
    'update_available', false,
    'is_mandatory', false,
    'status', 'latest',
    'app_key', v_app,
    'platform', v_platform,
    'channel', v_channel,
    'target_type', 'all',
    'latest_version', v_current_ver,
    'latest_build', v_current_build,
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
-- 3. TARGETING PREVIEW & CATALOG RPCS FOR ADMIN PANEL
-- ============================================================================

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
-- 4. EXTENDED PLATFORM_APP_RELEASE_SAVE_V820 WITH TARGETING SUPPORT
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
  p_download_url text default '',
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
  v_plat text := lower(trim(coalesce(p_platform, '')));
  v_ver text := trim(coalesce(p_version, ''));
  v_chan text := lower(trim(coalesce(p_channel, 'stable')));
  v_stat text := lower(trim(coalesce(p_status, 'published')));
  v_checksum text := nullif(lower(trim(coalesce(p_sha256_checksum, ''))), '');
  v_signature text := nullif(trim(coalesce(p_publisher_signature, '')), '');
  v_target_type text := lower(trim(coalesce(p_target_type, 'all')));
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('technical_admin') then
    raise exception 'Platform technical admin role required';
  end if;

  if v_app not in ('client', 'pos', 'admin', 'client_mobile', 'mobile_pos') then
    raise exception 'Invalid application identity: %', p_app_key;
  end if;

  if v_plat = '' or v_ver = '' then
    raise exception 'Platform and version are required';
  end if;

  if v_chan not in ('stable', 'beta', 'alpha') then
    v_chan := 'stable';
  end if;

  if v_stat not in ('draft', 'published', 'stable', 'beta', 'paused', 'revoked', 'deprecated', 'blocked') then
    v_stat := 'published';
  end if;

  if v_target_type not in ('all', 'business', 'store', 'device') then
    v_target_type := 'all';
  end if;

  if p_minimum_supported then
    update public.platform_app_releases
    set minimum_supported = false
    where app_key = v_app and platform = v_plat;
  end if;

  if p_id is null then
    insert into public.platform_app_releases(
      app_key, platform, version, build_number,
      channel, status, minimum_supported, mandatory,
      release_notes, download_url, package_size_bytes,
      sha256_checksum, publisher_signature, min_supported_version,
      rollout_percentage, target_type, target_tenant_ids,
      target_store_ids, target_device_ids, created_by, released_at, updated_at
    )
    values (
      v_app, v_plat, v_ver, greatest(coalesce(p_build_number, 1), 1),
      v_chan, v_stat, coalesce(p_minimum_supported, false), coalesce(p_mandatory, false),
      nullif(trim(coalesce(p_release_notes, '')), ''), nullif(trim(coalesce(p_download_url, '')), ''),
      greatest(coalesce(p_package_size_bytes, 0), 0),
      v_checksum, v_signature, nullif(trim(coalesce(p_min_supported_version, '')), ''),
      least(greatest(coalesce(p_rollout_percentage, 100), 0), 100),
      v_target_type, p_target_tenant_ids, p_target_store_ids, p_target_device_ids,
      auth.uid(), now(), now()
    )
    returning id into v_id;
  else
    update public.platform_app_releases
    set app_key = v_app,
        platform = v_plat,
        version = v_ver,
        build_number = greatest(coalesce(p_build_number, 1), 1),
        channel = v_chan,
        status = v_stat,
        minimum_supported = coalesce(p_minimum_supported, false),
        mandatory = coalesce(p_mandatory, false),
        release_notes = nullif(trim(coalesce(p_release_notes, '')), ''),
        download_url = nullif(trim(coalesce(p_download_url, '')), ''),
        package_size_bytes = greatest(coalesce(p_package_size_bytes, 0), 0),
        sha256_checksum = v_checksum,
        publisher_signature = v_signature,
        min_supported_version = nullif(trim(coalesce(p_min_supported_version, '')), ''),
        rollout_percentage = least(greatest(coalesce(p_rollout_percentage, 100), 0), 100),
        target_type = v_target_type,
        target_tenant_ids = p_target_tenant_ids,
        target_store_ids = p_target_store_ids,
        target_device_ids = p_target_device_ids,
        updated_at = now()
    where id = p_id
    returning id into v_id;
  end if;

  if v_id is null then
    raise exception 'Release not found for id: %', p_id;
  end if;

  perform private.platform_audit_write(
    'app_release.save', 'platform_app_releases', v_id::text, null,
    jsonb_build_object('app_key', v_app, 'version', v_ver, 'build', p_build_number, 'status', v_stat, 'target_type', v_target_type)
  );

  return v_id;
end;
$$;

revoke all on function public.platform_app_release_save_v820(uuid, text, text, text, integer, text, text, boolean, boolean, text, text, bigint, text, text, text, integer, text, uuid[], uuid[], uuid[]) from public;
grant execute on function public.platform_app_release_save_v820(uuid, text, text, text, integer, text, text, boolean, boolean, text, text, bigint, text, text, text, integer, text, uuid[], uuid[], uuid[]) to authenticated, service_role;

-- ============================================================================
-- 5. TELEMETRY RECORDING & REPORTING RPCS
-- ============================================================================

drop function if exists public.app_update_log_record_v820(text, text, uuid, uuid, text, integer, text, integer, text, text, jsonb);
drop function if exists public.app_update_log_record_v820(text, text, uuid, uuid, text, integer, text, integer, text, text, jsonb, uuid, jsonb);

create or replace function public.app_update_log_record_v820(
  p_app_key text,
  p_platform text default 'windows',
  p_device_id uuid default null,
  p_tenant_id uuid default null,
  p_from_version text default null,
  p_from_build integer default 0,
  p_to_version text default null,
  p_to_build integer default 0,
  p_status text default 'unknown',
  p_error_message text default null,
  p_details jsonb default '{}'::jsonb,
  p_release_id uuid default null,
  p_metadata jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_id uuid;
  v_final_details jsonb;
  v_status text := lower(trim(coalesce(p_status, 'unknown')));
begin
  if auth.uid() is not null and p_tenant_id is not null and not private.platform_v2_is_admin() then
    if not exists (
      select 1 from public.user_login_names uln
      where uln.tenant_id = p_tenant_id and uln.user_id = auth.uid()
    ) then
      p_tenant_id := null;
    end if;
  end if;

  v_final_details := coalesce(p_details, '{}'::jsonb);
  if p_metadata is not null and p_metadata <> '{}'::jsonb then
    v_final_details := v_final_details || p_metadata;
  end if;
  if p_release_id is not null then
    v_final_details := jsonb_set(v_final_details, '{release_id}', to_jsonb(p_release_id::text), true);
  end if;

  insert into public.platform_app_update_logs(
    app_key, platform, device_id, tenant_id,
    from_version, from_build, to_version, to_build,
    status, error_message, details
  )
  values (
    lower(trim(coalesce(p_app_key, 'unknown'))),
    lower(trim(coalesce(p_platform, 'windows'))),
    p_device_id,
    p_tenant_id,
    nullif(trim(coalesce(p_from_version, '')), ''),
    coalesce(p_from_build, 0),
    nullif(trim(coalesce(p_to_version, '')), ''),
    coalesce(p_to_build, 0),
    v_status,
    nullif(trim(coalesce(p_error_message, '')), ''),
    v_final_details
  )
  returning id into v_id;

  if p_device_id is not null and p_tenant_id is not null then
    begin
      update public.device_app_status
      set
        version = coalesce(nullif(trim(coalesce(p_to_version, '')), ''), version),
        build_number = case when v_status = 'success' or v_status = 'installed' then coalesce(p_to_build, build_number) else build_number end,
        last_seen_at = now(),
        metadata = metadata || jsonb_build_object(
          'last_update_status', v_status,
          'last_update_attempt', now(),
          'last_update_error', p_error_message
        )
      where device_id = p_device_id;
    exception when others then
      -- Ignore status update errors
    end;
  end if;

  return jsonb_build_object('success', true, 'log_id', v_id);
end;
$$;

revoke all on function public.app_update_log_record_v820(text, text, uuid, uuid, text, integer, text, integer, text, text, jsonb, uuid, jsonb) from public;
grant execute on function public.app_update_log_record_v820(text, text, uuid, uuid, text, integer, text, integer, text, text, jsonb, uuid, jsonb) to anon, authenticated, service_role;

-- Paginated telemetry RPC
drop function if exists public.platform_app_update_logs_list_v820(text, integer);
drop function if exists public.platform_app_update_logs_list_v820(text, integer, integer, text);

create or replace function public.platform_app_update_logs_list_v820(
  p_app_key text default null,
  p_limit integer default 100,
  p_offset integer default 0,
  p_status text default null
)
returns table(
  id uuid,
  app_key text,
  platform text,
  device_id uuid,
  tenant_id uuid,
  tenant_name text,
  from_version text,
  from_build integer,
  to_version text,
  to_build integer,
  status text,
  error_message text,
  details jsonb,
  created_at timestamptz
)
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('technical_admin') then
    raise exception 'Platform technical admin role required';
  end if;

  return query
  select
    l.id,
    l.app_key,
    l.platform,
    l.device_id,
    l.tenant_id,
    t.name as tenant_name,
    l.from_version,
    l.from_build,
    l.to_version,
    l.to_build,
    l.status,
    l.error_message,
    l.details,
    l.created_at
  from public.platform_app_update_logs l
  left join public.tenants t on t.id = l.tenant_id
  where (p_app_key is null or l.app_key = lower(trim(p_app_key)))
    and (p_status is null or l.status = lower(trim(p_status)))
  order by l.created_at desc
  limit least(greatest(coalesce(p_limit, 100), 1), 500)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

revoke all on function public.platform_app_update_logs_list_v820(text, integer, integer, text) from public;
grant execute on function public.platform_app_update_logs_list_v820(text, integer, integer, text) to authenticated, service_role;

-- ============================================================================
-- 6. STORAGE BUCKET FOR RELEASES (Phase 5 requirement)
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

-- RLS policies for storage.objects
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
