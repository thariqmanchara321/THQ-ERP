-- THQ ERP V7.1.7 — Authoritative Software Updater and Release Management
-- 1. Extend platform_app_releases with channel, checksum, size, publisher signature, and rollout controls.
-- 2. Create platform_app_update_logs for adoption and error telemetry.
-- 3. Authoritative public.app_release_check_v820 for Client, POS, and Admin.
-- 4. Admin RPCs for publishing, pausing, revoking releases and inspecting telemetry.

begin;

-- ============================================================================
-- 1. EXTEND PLATFORM_APP_RELEASES TABLE
-- ============================================================================

-- Update check constraint on app_key to support all THQ ERP targets
alter table public.platform_app_releases
  drop constraint if exists platform_app_releases_app_key_check;

alter table public.platform_app_releases
  add constraint platform_app_releases_app_key_check
  check (app_key = any (array['client'::text, 'pos'::text, 'admin'::text, 'client_mobile'::text, 'mobile_pos'::text]));

-- Update check constraint on status to support lifecycle management
alter table public.platform_app_releases
  drop constraint if exists platform_app_releases_status_check;

alter table public.platform_app_releases
  add constraint platform_app_releases_status_check
  check (status = any (array['draft'::text, 'published'::text, 'stable'::text, 'beta'::text, 'paused'::text, 'revoked'::text, 'deprecated'::text, 'blocked'::text]));

-- Add new columns safely
alter table public.platform_app_releases
  add column if not exists channel text not null default 'stable',
  add column if not exists package_size_bytes bigint not null default 0,
  add column if not exists sha256_checksum text,
  add column if not exists publisher_signature text,
  add column if not exists min_supported_version text,
  add column if not exists rollout_percentage integer not null default 100,
  add column if not exists created_by uuid references auth.users(id),
  add column if not exists updated_at timestamptz not null default now();

-- Channel and rollout constraints
alter table public.platform_app_releases
  drop constraint if exists platform_app_releases_channel_check;

alter table public.platform_app_releases
  add constraint platform_app_releases_channel_check
  check (channel = any (array['stable'::text, 'beta'::text, 'alpha'::text]));

alter table public.platform_app_releases
  drop constraint if exists platform_app_releases_rollout_check;

alter table public.platform_app_releases
  add constraint platform_app_releases_rollout_check
  check (rollout_percentage >= 0 and rollout_percentage <= 100);

-- Enable RLS and establish clean read policy
alter table public.platform_app_releases enable row level security;

drop policy if exists platform_app_releases_read_policy on public.platform_app_releases;
create policy platform_app_releases_read_policy
  on public.platform_app_releases for select
  using (status in ('published', 'stable', 'beta', 'deprecated') or private.platform_v2_is_admin());

drop policy if exists platform_app_releases_admin_all on public.platform_app_releases;
create policy platform_app_releases_admin_all
  on public.platform_app_releases for all
  using (private.platform_v2_is_admin())
  with check (private.platform_v2_is_admin());

-- ============================================================================
-- 2. CREATE PLATFORM_APP_UPDATE_LOGS
-- ============================================================================

create table if not exists public.platform_app_update_logs (
  id uuid primary key default gen_random_uuid(),
  app_key text not null,
  platform text not null,
  device_id uuid,
  tenant_id uuid references public.tenants(id) on delete set null,
  from_version text,
  from_build integer,
  to_version text,
  to_build integer,
  status text not null, -- checking, available, downloading, verified, installing, success, failed
  error_message text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_platform_app_update_logs_app_plat
  on public.platform_app_update_logs(app_key, platform, created_at desc);

create index if not exists idx_platform_app_update_logs_device
  on public.platform_app_update_logs(device_id, created_at desc);

alter table public.platform_app_update_logs enable row level security;

drop policy if exists platform_app_update_logs_insert on public.platform_app_update_logs;
create policy platform_app_update_logs_insert
  on public.platform_app_update_logs for insert
  with check (true);

drop policy if exists platform_app_update_logs_select on public.platform_app_update_logs;
create policy platform_app_update_logs_select
  on public.platform_app_update_logs for select
  using (private.platform_v2_is_admin() or auth.uid() is not null);

-- ============================================================================
-- 2.5 SEMVER COMPARISON HELPER (Prevents Downgrade Attacks)
-- ============================================================================

create or replace function private.compare_semver(p_v1 text, p_v2 text)
returns integer
language plpgsql
immutable
as $$
declare
  p1 text[] := string_to_array(regexp_replace(coalesce(p_v1, '0'), '[^0-9.]', '', 'g'), '.');
  p2 text[] := string_to_array(regexp_replace(coalesce(p_v2, '0'), '[^0-9.]', '', 'g'), '.');
  n1 int;
  n2 int;
  i int;
  len int := greatest(coalesce(array_length(p1, 1), 0), coalesce(array_length(p2, 1), 0), 3);
begin
  for i in 1..len loop
    n1 := coalesce(nullif(p1[i], '')::int, 0);
    n2 := coalesce(nullif(p2[i], '')::int, 0);
    if n1 > n2 then return 1; end if;
    if n1 < n2 then return -1; end if;
  end loop;
  return 0;
end;
$$;

create or replace function private.semver_sort_key(p_v text)
returns bigint
language plpgsql
immutable
as $$
declare
  p text[] := string_to_array(regexp_replace(coalesce(p_v, '0'), '[^0-9.]', '', 'g'), '.');
  m bigint := coalesce(nullif(p[1], '')::bigint, 0);
  n bigint := coalesce(nullif(p[2], '')::bigint, 0);
  k bigint := coalesce(nullif(p[3], '')::bigint, 0);
begin
  return (m * 100000000) + (n * 10000) + k;
end;
$$;

-- ============================================================================
-- 3. CLIENT UPDATE CHECK RPC (app_release_check_v820)
-- ============================================================================

create or replace function public.app_release_check_v820(
  p_app_key text,
  p_platform text,
  p_channel text default 'stable',
  p_current_version text default null,
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
  v_update_avail boolean := false;
  v_mandatory boolean := false;
  v_status text := 'latest';
  v_cmp integer;
begin
  if v_app not in ('client', 'pos', 'admin', 'client_mobile', 'mobile_pos') then
    raise exception 'Invalid app key: %', p_app_key;
  end if;

  -- Select newest published eligible release matching channel or stable fallback
  select * into v_latest
  from public.platform_app_releases
  where app_key = v_app
    and lower(platform) = v_platform
    and status in ('published', 'stable', 'beta')
    and (channel = v_channel or (v_channel = 'beta' and channel = 'stable') or channel = 'stable')
    and rollout_percentage > 0
  order by private.semver_sort_key(version) desc, build_number desc, released_at desc
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

    return jsonb_build_object(
      'update_available', v_update_avail,
      'is_mandatory', v_mandatory,
      'status', v_status,
      'app_key', v_app,
      'platform', v_platform,
      'channel', v_latest.channel,
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

  return jsonb_build_object(
    'update_available', false,
    'is_mandatory', false,
    'status', 'latest',
    'app_key', v_app,
    'platform', v_platform,
    'channel', v_channel,
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

-- ============================================================================
-- 4. UPDATE TELEMETRY LOG RECORDING RPC
-- ============================================================================

create or replace function public.app_update_log_record_v820(
  p_app_key text,
  p_platform text,
  p_device_id uuid default null,
  p_tenant_id uuid default null,
  p_from_version text default null,
  p_from_build integer default 0,
  p_to_version text default null,
  p_to_build integer default 0,
  p_status text default 'unknown',
  p_error_message text default null,
  p_details jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_id uuid;
begin
  insert into public.platform_app_update_logs(
    app_key, platform, device_id, tenant_id,
    from_version, from_build, to_version, to_build,
    status, error_message, details
  )
  values (
    lower(trim(coalesce(p_app_key, 'unknown'))),
    lower(trim(coalesce(p_platform, 'unknown'))),
    p_device_id, p_tenant_id,
    nullif(trim(coalesce(p_from_version, '')), ''),
    p_from_build,
    nullif(trim(coalesce(p_to_version, '')), ''),
    p_to_build,
    lower(trim(coalesce(p_status, 'unknown'))),
    nullif(trim(coalesce(p_error_message, '')), ''),
    coalesce(p_details, '{}'::jsonb)
  )
  returning id into v_id;

  return jsonb_build_object('success', true, 'log_id', v_id);
end;
$$;

-- ============================================================================
-- 5. ADMIN RELEASE MANAGEMENT RPCS
-- ============================================================================

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
  p_rollout_percentage integer default 100
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
      rollout_percentage, created_by, released_at, updated_at
    )
    values (
      v_app, v_plat, v_ver, greatest(coalesce(p_build_number, 1), 1),
      v_chan, v_stat, coalesce(p_minimum_supported, false), coalesce(p_mandatory, false),
      nullif(trim(coalesce(p_release_notes, '')), ''), nullif(trim(coalesce(p_download_url, '')), ''),
      greatest(coalesce(p_package_size_bytes, 0), 0),
      v_checksum, v_signature, nullif(trim(coalesce(p_min_supported_version, '')), ''),
      least(greatest(coalesce(p_rollout_percentage, 100), 0), 100),
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
        updated_at = now()
    where id = p_id
    returning id into v_id;
  end if;

  if v_id is null then
    raise exception 'Release not found for id: %', p_id;
  end if;

  perform private.platform_audit_write(
    'app_release.save', 'platform_app_releases', v_id::text, null,
    jsonb_build_object('app_key', v_app, 'version', v_ver, 'build', p_build_number, 'status', v_stat)
  );

  return v_id;
end;
$$;

-- Backward compatibility adapter for legacy platform_app_release_save_v4
create or replace function public.platform_app_release_save_v4(
  p_id uuid,
  p_app_key text,
  p_platform text,
  p_version text,
  p_build_number integer,
  p_status text,
  p_minimum_supported boolean,
  p_mandatory boolean,
  p_release_notes text,
  p_download_url text
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
begin
  return public.platform_app_release_save_v820(
    p_id := p_id,
    p_app_key := p_app_key,
    p_platform := p_platform,
    p_version := p_version,
    p_build_number := p_build_number,
    p_channel := 'stable',
    p_status := p_status,
    p_minimum_supported := p_minimum_supported,
    p_mandatory := p_mandatory,
    p_release_notes := p_release_notes,
    p_download_url := p_download_url
  );
end;
$$;

create or replace function public.platform_app_release_set_status_v820(
  p_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_stat text := lower(trim(coalesce(p_status, '')));
begin
  if not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('technical_admin') then
    raise exception 'Platform technical admin role required';
  end if;

  if v_stat not in ('draft', 'published', 'stable', 'beta', 'paused', 'revoked', 'deprecated', 'blocked') then
    raise exception 'Invalid release status: %', p_status;
  end if;

  update public.platform_app_releases
  set status = v_stat, updated_at = now()
  where id = p_id;

  if not found then
    raise exception 'Release not found for id: %', p_id;
  end if;

  perform private.platform_audit_write(
    'app_release.set_status', 'platform_app_releases', p_id::text, null,
    jsonb_build_object('status', v_stat)
  );
end;
$$;

create or replace function public.platform_app_update_logs_list_v820(
  p_app_key text default null,
  p_limit integer default 200
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
  if not private.platform_v2_is_admin() then
    raise exception 'Platform admin access required';
  end if;

  return query
  select l.id, l.app_key, l.platform, l.device_id, l.tenant_id, t.name as tenant_name,
         l.from_version, l.from_build, l.to_version, l.to_build,
         l.status, l.error_message, l.details, l.created_at
  from public.platform_app_update_logs l
  left join public.tenants t on t.id = l.tenant_id
  where (p_app_key is null or l.app_key = lower(trim(p_app_key)))
  order by l.created_at desc
  limit least(greatest(coalesce(p_limit, 200), 1), 1000);
end;
$$;

-- Permissions and grants
revoke all on function public.app_release_check_v820(text, text, text, text, integer, uuid, uuid) from public;
grant execute on function public.app_release_check_v820(text, text, text, text, integer, uuid, uuid) to anon, authenticated, service_role;

revoke all on function public.app_update_log_record_v820(text, text, uuid, uuid, text, integer, text, integer, text, text, jsonb) from public;
grant execute on function public.app_update_log_record_v820(text, text, uuid, uuid, text, integer, text, integer, text, text, jsonb) to anon, authenticated, service_role;

revoke all on function public.platform_app_release_save_v820(uuid, text, text, text, integer, text, text, boolean, boolean, text, text, bigint, text, text, text, integer) from public;
grant execute on function public.platform_app_release_save_v820(uuid, text, text, text, integer, text, text, boolean, boolean, text, text, bigint, text, text, text, integer) to authenticated, service_role;

revoke all on function public.platform_app_release_set_status_v820(uuid, text) from public;
grant execute on function public.platform_app_release_set_status_v820(uuid, text) to authenticated, service_role;

revoke all on function public.platform_app_update_logs_list_v820(text, integer) from public;
grant execute on function public.platform_app_update_logs_list_v820(text, integer) to authenticated, service_role;

commit;
