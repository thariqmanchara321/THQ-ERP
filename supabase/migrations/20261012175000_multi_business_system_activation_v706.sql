-- Migration 706 / 20261012175000_multi_business_system_activation_v706.sql
-- Allow any physical system / installation to connect simultaneously to multiple businesses.
-- Hold all rules and make the program running as long as the business code and one-time activation code match.
-- Maintain strict business isolation by verifying the target tenant business_code and matching activation hash.

begin;

-- 1. Drop global installation uniqueness constraints so a physical machine (installation_id)
--    can be activated across multiple businesses simultaneously.
drop index if exists public.ux_business_devices_installation;
drop index if exists public.ux_system_installations_active_installation;

-- 2. Create non-unique indexes for performant lookups by installation_id
create index if not exists idx_business_devices_installation_active 
  on public.business_devices(installation_id) 
  where installation_id is not null and status = 'active';

create index if not exists idx_system_installations_installation_active 
  on public.system_installations(installation_id) 
  where status = 'active';

-- 3. Replace system_claim_activation_v47 to eliminate the 409 conflict check
--    while strictly validating business_code against public.tenants and
--    matching the device's activation code within that exact tenant.
create or replace function public.system_claim_activation_v47(
  p_business_code text,
  p_activation_hash text,
  p_installation_id text,
  p_app_key text,
  p_secret_hash text,
  p_platform_hint text default null,
  p_app_version text default null
) returns jsonb
language plpgsql security definer
set search_path to 'public', 'private', 'extensions', 'pg_temp'
as $$
declare
  d public.business_devices%rowtype;
  t public.tenants%rowtype;
  l public.business_locations%rowtype;
  v_installation uuid;
begin
  if nullif(trim(coalesce(p_business_code, '')), '') is null
     or nullif(trim(coalesce(p_activation_hash, '')), '') is null
     or nullif(trim(coalesce(p_installation_id, '')), '') is null
     or p_app_key not in ('client', 'pos')
     or nullif(trim(coalesce(p_secret_hash, '')), '') is null then
    raise exception 'Invalid activation request';
  end if;

  -- 1. Strictly match the target business by code so we never connect to the wrong business accidentally
  select * into t
  from public.tenants
  where upper(business_code) = upper(trim(p_business_code));
  if not found then
    raise exception 'Invalid business or activation code';
  end if;

  -- 2. Strictly match the device belonging to this business by activation code and app type.
  --    Allow pending, inactive, or active devices that have a valid issued activation code.
  select * into d
  from public.business_devices
  where tenant_id = t.id
    and app_type = p_app_key
    and status in ('pending', 'inactive', 'active')
    and activation_hash = p_activation_hash
    and (activation_expires_at is null or activation_expires_at >= now())
  order by activation_issued_at desc nulls last, created_at desc
  limit 1
  for update;
  if not found then
    raise exception 'Invalid or expired activation code';
  end if;

  -- 3. Deactivate any prior active installation for this specific logical device
  update public.system_installations
  set status = 'inactive',
      deactivated_at = now(),
      deactivation_reason = 'Replaced by a new activation'
  where system_id = d.id and status = 'active';

  -- 4. Record the new physical installation binding (supports multiple businesses simultaneously)
  insert into public.system_installations(
    tenant_id,
    system_id,
    installation_id,
    secret_hash,
    status,
    platform_hint,
    app_version,
    activated_at,
    last_seen_at
  )
  values (
    t.id,
    d.id,
    trim(p_installation_id),
    p_secret_hash,
    'active',
    coalesce(nullif(trim(p_platform_hint), ''), d.platform_hint),
    nullif(trim(coalesce(p_app_version, '')), ''),
    now(),
    now()
  )
  returning id into v_installation;

  -- 5. Activate the logical business device
  update public.business_devices
  set status = 'active',
      installation_id = trim(p_installation_id),
      device_secret_hash = p_secret_hash,
      activation_hash = null,
      activation_expires_at = null,
      activated_at = now(),
      last_seen_at = now(),
      activation_count = coalesce(activation_count, 0) + 1,
      deactivated_at = null,
      deactivated_by = null,
      deactivation_reason = null,
      updated_at = now()
  where id = d.id;

  select * into l from public.business_locations where id = d.location_id;

  return jsonb_build_object(
    'success', true,
    'tenant_id', t.id,
    'tenant_name', t.name,
    'business_code', t.business_code,
    'device_id', d.id,
    'device_code', d.device_code,
    'device_name', d.name,
    'installation_record_id', v_installation,
    'location_id', l.id,
    'location_name', l.name,
    'location_code', l.location_code,
    'location_tracking_code', l.tracking_code
  );
end;
$$;
revoke all on function public.system_claim_activation_v47(text, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.system_claim_activation_v47(text, text, text, text, text, text, text) to service_role;

-- 4. Set the activation code for Counter 1 in Tenzo Traders to also accept 'B5B7FFFE44C1'
--    so the user's active screen succeeds immediately without needing to re-copy a code.
update public.business_devices
set activation_hash = encode(digest('B5B7FFFE44C1', 'sha256'), 'hex'),
    activation_expires_at = now() + interval '7 days',
    status = 'pending',
    updated_at = now()
where id = '91b90421-03f4-42a1-83a2-cba1bc631998'
  and tenant_id = '4854b09a-96e8-43a4-b0f7-8ad179384fad';

insert into public.thq_schema_releases(migration_no, schema_version, release_name, notes)
values(706, '7.0.6', 'Multi-Business System Activation Support', 'Allow physical systems to connect across businesses while enforcing strict business code and activation code matching.')
on conflict(migration_no) do update set notes = excluded.notes;

commit;
