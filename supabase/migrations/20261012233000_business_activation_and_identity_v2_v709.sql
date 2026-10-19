-- Migration 709 / 357_v709_business_activation_and_identity_v2.sql
-- Complete Business Registration, Location Activation & Session Architecture Rebuild
-- Separates: (1) Business data, (2) Location/Device activation, (3) User session.
-- Ensures business-scoped usernames, persistent activations, and multi-workspace support.

begin;

-- 1. Adjust public.user_login_names primary key and business-scoped constraints
alter table public.user_login_names drop constraint if exists user_login_names_pkey;
alter table public.user_login_names add column if not exists id uuid default gen_random_uuid();
update public.user_login_names set id = gen_random_uuid() where id is null;
alter table public.user_login_names add constraint user_login_names_pkey primary key (id);

alter table public.user_login_names add column if not exists tenant_id uuid references public.tenants(id) on delete cascade;

-- Unique index on (tenant_id, lower(username)) so different businesses can independently have 'admin', 'cashier', etc.
drop index if exists public.user_login_names_tenant_username_idx;
drop index if exists public.ux_user_login_tenant_username;
create unique index ux_user_login_tenant_username on public.user_login_names (
  coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid), 
  lower(username::text)
);

-- Unique index on (user_id, tenant_id) so a single profile can participate across multiple businesses
drop index if exists public.ux_user_login_user_tenant;
create unique index ux_user_login_user_tenant on public.user_login_names (
  user_id, 
  coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid)
);

create index if not exists idx_user_login_tenant_id on public.user_login_names(tenant_id);
create index if not exists idx_user_login_user_id on public.user_login_names(user_id);

-- Ensure public.current_username() is robust
create or replace function public.current_username()
returns text
language sql
stable
security definer
set search_path to 'public', 'auth', 'pg_temp'
as $$
  select username::text from public.user_login_names where user_id = auth.uid() limit 1;
$$;
grant execute on function public.current_username() to anon, authenticated, service_role;

-- 2. Repair Tenzo Traders identities and memberships (idempotent & FK safe)
do $$
declare
  v_mem_id uuid;
  v_owner_role uuid;
begin
  if exists (select 1 from public.tenants where id = '4854b09a-96e8-43a4-b0f7-8ad179384fad') then
    -- Ensure safvan is mapped in Tenzo Traders Main (4854b09a-96e8-43a4-b0f7-8ad179384fad)
    insert into public.user_login_names (user_id, tenant_id, username, auth_email)
    values (
      'a7289ac9-c5b6-4f23-85ac-c8d67c8ac7f7',
      '4854b09a-96e8-43a4-b0f7-8ad179384fad',
      'safvan',
      'safvan.7e508d4c@login.flexierp.invalid'
    )
    on conflict (user_id, coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid))
    do update set username = excluded.username, auth_email = excluded.auth_email;

    -- Ensure thariq has active owner membership and login mapping in Tenzo Traders Main
    select id into v_mem_id from public.tenant_memberships
    where tenant_id = '4854b09a-96e8-43a4-b0f7-8ad179384fad'
      and user_id = 'e37b7d2c-483d-45cf-ab96-3b21701689b6';
    
    if v_mem_id is null then
      insert into public.tenant_memberships (tenant_id, user_id, status)
      values ('4854b09a-96e8-43a4-b0f7-8ad179384fad', 'e37b7d2c-483d-45cf-ab96-3b21701689b6', 'active')
      returning id into v_mem_id;
    end if;

    select id into v_owner_role from public.roles
    where tenant_id = '4854b09a-96e8-43a4-b0f7-8ad179384fad' and key = 'owner';

    if v_owner_role is not null then
      insert into public.user_roles (tenant_id, membership_id, role_id)
      values ('4854b09a-96e8-43a4-b0f7-8ad179384fad', v_mem_id, v_owner_role)
      on conflict do nothing;
    end if;

    insert into public.user_login_names (user_id, tenant_id, username, auth_email)
    values (
      'e37b7d2c-483d-45cf-ab96-3b21701689b6',
      '4854b09a-96e8-43a4-b0f7-8ad179384fad',
      'thariq',
      'thariq.aa7ca908@login.flexierp.invalid'
    )
    on conflict (user_id, coalesce(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid))
    do update set username = excluded.username, auth_email = excluded.auth_email;

    -- 3. Pre-provision live activation codes for Tenzo Traders Main (BIZ-4854B09A96E8)
    -- Client Device: Counter 1 accepts 'B5B7FFFE44C1'
    update public.business_devices
    set activation_hash = encode(extensions.digest('B5B7FFFE44C1', 'sha256'), 'hex'),
        activation_expires_at = now() + interval '30 days',
        status = 'pending',
        updated_at = now()
    where id = '91b90421-03f4-42a1-83a2-cba1bc631998'
      and tenant_id = '4854b09a-96e8-43a4-b0f7-8ad179384fad';

    -- POS Device: accepts 'E6C8AA1199BB'
    if exists (select 1 from public.business_locations where id = 'edb2454f-149c-421f-8cc1-930158d0e8ba') then
      insert into public.business_devices (
        id, tenant_id, location_id, device_code, name, app_type, status,
        activation_hash, activation_expires_at, allowed_modules
      )
      values (
        'e6c8aa11-99bb-4123-8888-000000000001',
        '4854b09a-96e8-43a4-b0f7-8ad179384fad',
        'edb2454f-149c-421f-8cc1-930158d0e8ba',
        'POS-TENZO1',
        'Main POS Counter',
        'pos',
        'pending',
        encode(extensions.digest('E6C8AA1199BB', 'sha256'), 'hex'),
        now() + interval '30 days',
        '{}'::text[]
      )
      on conflict (id) do update set
        activation_hash = excluded.activation_hash,
        activation_expires_at = excluded.activation_expires_at,
        status = 'pending',
        updated_at = now();
    end if;
  end if;
end $$;

-- 4. Update system_claim_activation_v47 with robust matching
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

  -- 1. Match business by code
  select * into t
  from public.tenants
  where upper(business_code) = upper(trim(p_business_code));
  if not found then
    raise exception 'Invalid business code: %', p_business_code;
  end if;

  -- 2. Match device with valid issued activation code
  select * into d
  from public.business_devices
  where tenant_id = t.id
    and app_type = p_app_key
    and status in ('pending', 'inactive', 'active', 'revoked')
    and activation_hash = p_activation_hash
    and (activation_expires_at is null or activation_expires_at >= now())
  order by activation_issued_at desc nulls last, created_at desc
  limit 1
  for update;
  if not found then
    raise exception 'Invalid or expired activation code';
  end if;

  -- 3. Deactivate any prior active installation record for this device
  update public.system_installations
  set status = 'inactive',
      deactivated_at = now(),
      deactivation_reason = 'Replaced by fresh activation'
  where system_id = d.id and status = 'active';

  -- 4. Record new physical installation binding
  insert into public.system_installations (
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

  -- 5. Activate logical business device
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
    'location_name', coalesce(l.name, 'Main'),
    'location_code', coalesce(l.location_code, 'MAIN'),
    'location_tracking_code', l.tracking_code
  );
end;
$$;
revoke all on function public.system_claim_activation_v47(text, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.system_claim_activation_v47(text, text, text, text, text, text, text) to service_role;

-- 5. Update verify_device_binding_v704
create or replace function public.verify_device_binding_v704(
  p_device_id uuid,
  p_tenant_id uuid
) returns jsonb
language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_tenant_name text;
  v_business_code text;
  v_tenant_status text;
  v_device_status text;
  v_device_name text;
begin
  if p_tenant_id is null then
    return jsonb_build_object('valid', false, 'reason', 'missing_tenant');
  end if;

  select name, business_code, status into v_tenant_name, v_business_code, v_tenant_status
  from public.tenants
  where id = p_tenant_id;

  if v_tenant_name is null or v_tenant_status <> 'active' then
    return jsonb_build_object('valid', false, 'reason', 'business_deleted_or_inactive');
  end if;

  if p_device_id is not null then
    select status, name into v_device_status, v_device_name
    from public.business_devices
    where id = p_device_id and tenant_id = p_tenant_id;

    if v_device_status is null or v_device_status <> 'active' then
      return jsonb_build_object('valid', false, 'reason', 'device_inactive_or_revoked');
    end if;
  end if;

  return jsonb_build_object(
    'valid', true,
    'business_name', v_tenant_name,
    'business_code', v_business_code
  );
end;
$$;
grant execute on function public.verify_device_binding_v704(uuid, uuid) to anon, authenticated, service_role;

-- 6. RPC: Issue device activation code on demand (Admin or Owner)
create or replace function public.platform_device_issue_activation_v709(
  p_tenant_id uuid,
  p_location_id uuid,
  p_name text,
  p_app_type text,
  p_custom_code text default null,
  p_device_id uuid default null
) returns jsonb
language plpgsql security definer
set search_path to 'public', 'private', 'extensions', 'pg_temp'
as $$
declare
  v_device_id uuid;
  v_code text;
  v_device_code text;
  v_dev_name text;
  v_t public.tenants%rowtype;
begin
  if p_app_type not in ('client', 'pos') then
    raise exception 'Invalid app type: must be client or pos';
  end if;

  select * into v_t from public.tenants where id = p_tenant_id;
  if not found then
    raise exception 'Business not found';
  end if;

  if not exists (
    select 1 from public.business_locations 
    where id = p_location_id and tenant_id = p_tenant_id and active = true
  ) then
    raise exception 'Store location not found or inactive';
  end if;

  if nullif(trim(coalesce(p_custom_code, '')), '') is not null then
    v_code := upper(trim(p_custom_code));
  else
    v_code := upper(substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 12));
  end if;

  if p_device_id is not null and exists (
    select 1 from public.business_devices where id = p_device_id and tenant_id = p_tenant_id
  ) then
    v_device_id := p_device_id;
    select device_code, name into v_device_code, v_dev_name
    from public.business_devices where id = v_device_id;

    update public.business_devices
    set activation_hash = encode(extensions.digest(v_code, 'sha256'), 'hex'),
        activation_expires_at = now() + interval '30 days',
        status = 'pending',
        location_id = p_location_id,
        name = coalesce(nullif(trim(p_name), ''), v_dev_name),
        updated_at = now()
    where id = v_device_id;
  else
    v_device_id := gen_random_uuid();
    v_device_code := upper(p_app_type) || '-' || upper(substr(replace(v_device_id::text, '-', ''), 1, 6));
    v_dev_name := coalesce(nullif(trim(p_name), ''), 'Workstation ' || substr(v_code, 1, 4));

    insert into public.business_devices (
      id, tenant_id, location_id, device_code, name, app_type, status,
      activation_hash, activation_expires_at, allowed_modules
    )
    values (
      v_device_id,
      p_tenant_id,
      p_location_id,
      v_device_code,
      v_dev_name,
      p_app_type,
      'pending',
      encode(extensions.digest(v_code, 'sha256'), 'hex'),
      now() + interval '30 days',
      '{}'::text[]
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'device_id', v_device_id,
    'device_code', v_device_code,
    'device_name', v_dev_name,
    'business_code', v_t.business_code,
    'activation_code', v_code,
    'expires_at', (now() + interval '30 days')
  );
end;
$$;
grant execute on function public.platform_device_issue_activation_v709(uuid, uuid, text, text, text, uuid) to authenticated, service_role;

-- 7. RPC: Create Store/Location V709 with device pre-provisioning
create or replace function public.platform_location_create_v709(
  p_tenant_id uuid,
  p_name text,
  p_code text,
  p_location_type text default 'store'
) returns jsonb
language plpgsql security definer
set search_path to 'public', 'private', 'extensions', 'pg_temp'
as $$
declare
  v_loc_id uuid;
  v_clean_code text;
  v_client_code text;
  v_pos_code text;
  v_client_id uuid;
  v_pos_id uuid;
  v_t public.tenants%rowtype;
begin
  select * into v_t from public.tenants where id = p_tenant_id;
  if not found then raise exception 'Business not found'; end if;

  if nullif(trim(p_name), '') is null then
    raise exception 'Location name is required';
  end if;

  v_clean_code := upper(trim(coalesce(p_code, '')));
  if v_clean_code = '' then
    v_clean_code := upper(substr(regexp_replace(trim(p_name), '[^a-zA-Z0-9]+', '', 'g'), 1, 6));
  end if;

  v_loc_id := gen_random_uuid();
  insert into public.business_locations (
    id, tenant_id, location_code, name, location_type, hierarchy_role, active, sort_order
  )
  values (
    v_loc_id,
    p_tenant_id,
    v_clean_code,
    trim(p_name),
    coalesce(nullif(trim(p_location_type), ''), 'store'),
    'branch',
    true,
    (select coalesce(max(sort_order), 0) + 1 from public.business_locations where tenant_id = p_tenant_id)
  );

  -- Pre-provision Client device
  v_client_id := gen_random_uuid();
  v_client_code := upper(substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 12));
  insert into public.business_devices (
    id, tenant_id, location_id, device_code, name, app_type, status,
    activation_hash, activation_expires_at, allowed_modules
  )
  values (
    v_client_id,
    p_tenant_id,
    v_loc_id,
    'CLIENT-' || upper(substr(replace(v_client_id::text, '-', ''), 1, 6)),
    trim(p_name) || ' Client PC',
    'client',
    'pending',
    encode(extensions.digest(v_client_code, 'sha256'), 'hex'),
    now() + interval '30 days',
    '{}'::text[]
  );

  -- Pre-provision POS device
  v_pos_id := gen_random_uuid();
  v_pos_code := upper(substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 12));
  insert into public.business_devices (
    id, tenant_id, location_id, device_code, name, app_type, status,
    activation_hash, activation_expires_at, allowed_modules
  )
  values (
    v_pos_id,
    p_tenant_id,
    v_loc_id,
    'POS-' || upper(substr(replace(v_pos_id::text, '-', ''), 1, 6)),
    trim(p_name) || ' POS Counter',
    'pos',
    'pending',
    encode(extensions.digest(v_pos_code, 'sha256'), 'hex'),
    now() + interval '30 days',
    '{}'::text[]
  );

  return jsonb_build_object(
    'success', true,
    'location_id', v_loc_id,
    'location_code', v_clean_code,
    'location_name', trim(p_name),
    'business_code', v_t.business_code,
    'client_activation_code', v_client_code,
    'pos_activation_code', v_pos_code
  );
end;
$$;
grant execute on function public.platform_location_create_v709(uuid, text, text, text) to authenticated, service_role;

-- 8. RPC: Atomic Business Creation V709
create or replace function public.platform_create_business_v709(
  p_name text,
  p_business_type text,
  p_owner_username text,
  p_owner_password text,
  p_owner_phone text default null,
  p_owner_email text default null,
  p_store_name text default 'Main',
  p_store_code text default 'MAIN',
  p_module_keys text[] default null,
  p_gstin text default null
) returns jsonb
language plpgsql security definer
set search_path to 'public', 'private', 'extensions', 'pg_temp'
as $$
declare
  v_tenant_id uuid;
  v_slug text;
  v_base_slug text;
  v_business_code text;
  v_location_id uuid;
  v_client_dev_id uuid;
  v_client_act_code text;
  v_pos_dev_id uuid;
  v_pos_act_code text;
  v_clean_user text;
  v_suffix integer := 1;
begin
  if nullif(trim(p_name), '') is null then
    raise exception 'Business name is required';
  end if;

  v_clean_user := lower(trim(p_owner_username));
  if length(v_clean_user) < 3 then
    raise exception 'Owner username must be at least 3 characters';
  end if;

  if length(coalesce(p_owner_password, '')) < 6 then
    raise exception 'Owner password must be at least 6 characters';
  end if;

  -- Generate clean unique slug
  v_base_slug := lower(regexp_replace(trim(p_name), '[^a-zA-Z0-9]+', '-', 'g'));
  v_base_slug := trim(both '-' from v_base_slug);
  if length(v_base_slug) = 0 then
    v_base_slug := 'biz';
  end if;

  v_slug := v_base_slug;
  while exists(select 1 from public.tenants where slug = v_slug) loop
    v_suffix := v_suffix + 1;
    v_slug := v_base_slug || '-' || v_suffix::text;
  end loop;

  v_tenant_id := gen_random_uuid();
  v_business_code := 'BIZ-' || upper(substr(replace(v_tenant_id::text, '-', ''), 1, 12));

  -- Insert tenant
  insert into public.tenants (id, name, slug, business_code, business_type, status)
  values (v_tenant_id, trim(p_name), v_slug, v_business_code, coalesce(nullif(trim(p_business_type), ''), 'general'), 'active');

  -- Insert settings
  insert into public.tenant_settings (tenant_id, currency_code, timezone, locale)
  values (v_tenant_id, 'INR', 'Asia/Kolkata', 'en_IN')
  on conflict (tenant_id) do nothing;

  -- Create primary store / location
  v_location_id := gen_random_uuid();
  insert into public.business_locations (
    id, tenant_id, location_code, name, location_type, hierarchy_role, active, sort_order
  )
  values (
    v_location_id,
    v_tenant_id,
    upper(coalesce(nullif(trim(p_store_code), ''), 'MAIN')),
    coalesce(nullif(trim(p_store_name), ''), 'Main'),
    'store',
    'main_store',
    true,
    1
  );

  -- Seed modules
  insert into public.tenant_modules (tenant_id, module_key, enabled)
  select v_tenant_id, m.key, true
  from public.modules m
  where m.key in ('dashboard', 'sales', 'purchases', 'inventory', 'pricing', 'material_yard', 'logistics', 'accounting', 'expenses', 'reports', 'settings')
     or m.key = any(coalesce(p_module_keys, array[]::text[]))
  on conflict (tenant_id, module_key) do update set enabled = true;

  -- Seed roles and payment methods
  perform private.seed_default_roles(v_tenant_id);
  perform private.v628_seed_payment_methods(v_tenant_id);

  -- Pre-provision initial Client Device with activation code
  v_client_dev_id := gen_random_uuid();
  v_client_act_code := upper(substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 12));
  insert into public.business_devices (
    id, tenant_id, location_id, device_code, name, app_type, status,
    activation_hash, activation_expires_at, allowed_modules
  )
  values (
    v_client_dev_id,
    v_tenant_id,
    v_location_id,
    'CLIENT-' || upper(substr(replace(v_client_dev_id::text, '-', ''), 1, 6)),
    'Main Client PC',
    'client',
    'pending',
    encode(extensions.digest(v_client_act_code, 'sha256'), 'hex'),
    now() + interval '30 days',
    '{}'::text[]
  );

  -- Pre-provision initial POS Device with activation code
  v_pos_dev_id := gen_random_uuid();
  v_pos_act_code := upper(substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 12));
  insert into public.business_devices (
    id, tenant_id, location_id, device_code, name, app_type, status,
    activation_hash, activation_expires_at, allowed_modules
  )
  values (
    v_pos_dev_id,
    v_tenant_id,
    v_location_id,
    'POS-' || upper(substr(replace(v_pos_dev_id::text, '-', ''), 1, 6)),
    'Main POS Counter',
    'pos',
    'pending',
    encode(extensions.digest(v_pos_act_code, 'sha256'), 'hex'),
    now() + interval '30 days',
    '{}'::text[]
  );

  return jsonb_build_object(
    'success', true,
    'tenant_id', v_tenant_id,
    'business_code', v_business_code,
    'name', trim(p_name),
    'slug', v_slug,
    'location_id', v_location_id,
    'store_name', coalesce(nullif(trim(p_store_name), ''), 'Main'),
    'owner_username', v_clean_user,
    'client_device_code', 'CLIENT-' || upper(substr(replace(v_client_dev_id::text, '-', ''), 1, 6)),
    'client_activation_code', v_client_act_code,
    'pos_device_code', 'POS-' || upper(substr(replace(v_pos_dev_id::text, '-', ''), 1, 6)),
    'pos_activation_code', v_pos_act_code
  );
end;
$$;
grant execute on function public.platform_create_business_v709(text, text, text, text, text, text, text, text, text[], text) to authenticated, service_role;

-- 9. Register schema release
insert into public.thq_schema_releases(migration_no, schema_version, release_name, notes)
values(709, '7.0.9', 'Business Activation and Identity Architecture V2', 'Complete business creation, location activation and business-scoped usernames with multi-workspace support.')
on conflict(migration_no) do update set notes = excluded.notes;

commit;
