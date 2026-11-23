-- Migration 717: SEC-P1-02 Subscription Quota Enforcement & Database-Level Entitlement Security
-- Schema version: v8.3.11
-- Remediates unenforced subscription plan quotas (max_locations, max_terminals) in location and device creation RPCs.

begin;

-- 1. Ensure public.subscription_plans has explicit max_terminals limits seeded
update public.subscription_plans
set limits = limits || jsonb_build_object('max_terminals',
  case
    when key = 'trial' then 2
    when key = 'starter' then 2
    when key = 'business' then 6
    when key = 'professional' then 20
    when key = 'enterprise' then 999999
    when key = 'free' then 200
    else coalesce((limits->>'max_locations')::int * 2, 2)
  end
)
where limits->>'max_terminals' is null;

-- 2. Define authoritative entitlement resolver helper
create or replace function private.subscription_effective_limits(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_limits jsonb;
  v_status text;
  v_plan_key text;
  v_loc_limit int;
  v_term_limit int;
begin
  select ts.status, sp.key, (sp.limits || coalesce(ts.limit_overrides, '{}'::jsonb))
  into v_status, v_plan_key, v_limits
  from public.tenant_subscriptions ts
  join public.subscription_plans sp on sp.id = ts.plan_id
  where ts.tenant_id = p_tenant_id;

  if not found then
    -- Fallback for tenants without an explicit subscription row: default to trial plan
    select sp.key, sp.limits
    into v_plan_key, v_limits
    from public.subscription_plans sp
    where sp.key = 'trial' and sp.is_active
    limit 1;

    if not found then
      v_limits := jsonb_build_object(
        'max_locations', 1,
        'max_terminals', 2,
        'max_users', 3
      );
    end if;
    v_status := 'trial';
  end if;

  v_loc_limit := coalesce((v_limits->>'max_locations')::int, 1);
  v_term_limit := coalesce(
    (v_limits->>'max_terminals')::int,
    case
      when v_loc_limit >= 999999 or v_loc_limit < 0 then 999999
      else v_loc_limit * 2
    end,
    2
  );

  return jsonb_build_object(
    'status', v_status,
    'plan_key', v_plan_key,
    'max_locations', v_loc_limit,
    'max_terminals', v_term_limit,
    'max_users', coalesce((v_limits->>'max_users')::int, 3),
    'raw_limits', coalesce(v_limits, '{}'::jsonb)
  );
end;
$$;

-- 3. Define authoritative subscription quota checker
create or replace function private.subscription_check_quota(
  p_tenant_id uuid,
  p_resource text,
  p_requested_increment int default 1
) returns void
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_effective jsonb;
  v_status text;
  v_max int;
  v_current int;
begin
  if p_requested_increment <= 0 then
    return;
  end if;

  -- Advisory transaction lock scoped to tenant subscription quota to prevent race conditions
  perform pg_advisory_xact_lock(hashtextextended('sub_quota:' || p_tenant_id::text, 0));

  v_effective := private.subscription_effective_limits(p_tenant_id);
  v_status := v_effective->>'status';

  if v_status in ('suspended', 'cancelled') then
    raise exception 'Subscription %: resource provisioning disabled for this business', v_status
      using errcode = 'P0001', detail = 'ERR_SUBSCRIPTION_INACTIVE';
  end if;

  if p_resource = 'locations' then
    v_max := (v_effective->>'max_locations')::int;
    -- If unlimited (convention: >= 999999 or < 0)
    if v_max >= 999999 or v_max < 0 then
      return;
    end if;

    select count(*)::int into v_current
    from public.business_locations
    where tenant_id = p_tenant_id and active = true;

    if (v_current + p_requested_increment) > v_max then
      raise exception 'Location limit exceeded for current subscription plan (% active, % maximum permitted, % requested). Upgrade plan to add more locations.',
        v_current, v_max, p_requested_increment
        using errcode = 'P0001', detail = 'ERR_QUOTA_LOCATION_EXCEEDED';
    end if;

  elsif p_resource = 'terminals' then
    v_max := (v_effective->>'max_terminals')::int;
    -- If unlimited (convention: >= 999999 or < 0)
    if v_max >= 999999 or v_max < 0 then
      return;
    end if;

    select count(*)::int into v_current
    from public.business_devices
    where tenant_id = p_tenant_id
      and app_type in ('client', 'pos')
      and (
        status = 'active'
        or (status = 'pending' and (activation_expires_at is null or activation_expires_at > clock_timestamp()))
      );

    if (v_current + p_requested_increment) > v_max then
      raise exception 'Terminal limit exceeded for current subscription plan (% active, % maximum permitted, % requested). Upgrade plan or revoke unused devices to add more terminals.',
        v_current, v_max, p_requested_increment
        using errcode = 'P0001', detail = 'ERR_QUOTA_TERMINAL_EXCEEDED';
    end if;

  else
    raise exception 'Unknown subscription quota resource: %', p_resource;
  end if;
end;
$$;

-- 4. Harden public.platform_location_create_v709
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
  -- 1. Authorization check
  if auth.role() <> 'service_role' and not (
    private.platform_v2_is_admin()
    or (auth.uid() is not null and (
      private.erp_user_is_owner(p_tenant_id, auth.uid())
      or private.erp_has_permission(p_tenant_id, 'settings.manage')
      or private.erp_has_permission(p_tenant_id, 'locations.manage')
      or private.erp_has_permission(p_tenant_id, 'locations.manage_all')
    ))
  ) then
    raise exception 'Access denied' using errcode = '42501';
  end if;

  select * into v_t from public.tenants where id = p_tenant_id;
  if not found then raise exception 'Business not found'; end if;

  if nullif(trim(p_name), '') is null then
    raise exception 'Location name is required';
  end if;

  -- 2. Subscription Quota Checks:
  -- A new location requires 1 location slot AND 2 terminal slots (1 client + 1 pos pre-provisioned)
  perform private.subscription_check_quota(p_tenant_id, 'locations', 1);
  perform private.subscription_check_quota(p_tenant_id, 'terminals', 2);

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

-- 5. Harden public.platform_device_issue_activation_v709
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
  v_req_increment int := 1;
begin
  -- 1. Authorization check
  if auth.role() <> 'service_role' and not (
    private.platform_v2_is_admin()
    or (auth.uid() is not null and (
      private.erp_user_is_owner(p_tenant_id, auth.uid())
      or private.erp_has_permission(p_tenant_id, 'settings.manage')
      or private.erp_has_permission(p_tenant_id, 'locations.manage')
      or private.erp_has_permission(p_tenant_id, 'locations.manage_all')
    ))
  ) then
    raise exception 'Access denied' using errcode = '42501';
  end if;

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

  -- 2. Determine terminal quota increment:
  -- If re-activating an already active or pending device, increment is 0.
  -- If re-activating an inactive/revoked device or inserting a new device, increment is 1.
  if p_device_id is not null and exists (
    select 1 from public.business_devices where id = p_device_id and tenant_id = p_tenant_id
  ) then
    if exists (
      select 1 from public.business_devices
      where id = p_device_id
        and tenant_id = p_tenant_id
        and app_type in ('client', 'pos')
        and (
          status = 'active'
          or (status = 'pending' and (activation_expires_at is null or activation_expires_at > clock_timestamp()))
        )
    ) then
      v_req_increment := 0;
    else
      v_req_increment := 1;
    end if;
  else
    v_req_increment := 1;
  end if;

  if v_req_increment > 0 then
    perform private.subscription_check_quota(p_tenant_id, 'terminals', v_req_increment);
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
        activation_issued_at = now(),
        activation_issued_by = auth.uid(),
        activation_count = coalesce(activation_count, 0) + 1,
        updated_at = now()
    where id = v_device_id;
  else
    v_device_id := gen_random_uuid();
    v_device_code := upper(p_app_type) || '-' || upper(substr(replace(v_device_id::text, '-', ''), 1, 6));
    v_dev_name := coalesce(nullif(trim(p_name), ''), 'Workstation ' || substr(v_code, 1, 4));

    insert into public.business_devices (
      id, tenant_id, location_id, device_code, name, app_type, status,
      activation_hash, activation_expires_at, allowed_modules,
      activation_issued_at, activation_issued_by, activation_count
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
      '{}'::text[],
      now(),
      auth.uid(),
      1
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

-- 6. Harden public.tenant_system_create_v471
create or replace function public.tenant_system_create_v471(
  p_tenant_id uuid,
  p_location_id uuid,
  p_name text,
  p_app_type text,
  p_platform_hint text default null,
  p_module_keys text[] default '{}'::text[],
  p_invoice_prefix text default null,
  p_system_role text default null
) returns jsonb
language plpgsql security definer
set search_path to 'public', 'private', 'extensions', 'pg_temp'
as $$
declare
  v_id uuid := gen_random_uuid();
  v_code text;
  v_device_code text;
  v_exp timestamptz := now() + interval '24 hours';
  v_modules text[] := '{}'::text[];
  v_prefix text;
  v_role text;
begin
  if auth.role() <> 'service_role' and not (
    private.platform_v2_is_admin()
    or (auth.uid() is not null and (
      private.erp_user_is_owner(p_tenant_id, auth.uid())
      or private.erp_has_permission(p_tenant_id, 'locations.manage')
      or private.erp_has_permission(p_tenant_id, 'locations.manage_all')
    ))
  ) then
    raise exception 'Permission denied' using errcode = '42501';
  end if;

  if auth.role() <> 'service_role' and not private.platform_v2_is_admin() and not private.erp_user_is_owner(p_tenant_id, auth.uid())
     and not private.erp_user_location_allowed(p_tenant_id, p_location_id, 'manage') then
    raise exception 'Location manage access denied' using errcode = '42501';
  end if;

  if p_app_type not in ('client', 'pos') then
    raise exception 'Invalid app type';
  end if;

  if not exists (select 1 from public.business_locations where id = p_location_id and tenant_id = p_tenant_id and active) then
    raise exception 'Target store/location is not active';
  end if;

  -- Subscription quota check for new terminal
  perform private.subscription_check_quota(p_tenant_id, 'terminals', 1);

  v_role := coalesce(nullif(trim(p_system_role), ''), case when p_app_type = 'pos' then 'pos' else 'office' end);
  if p_app_type = 'pos' and v_role <> 'pos' then raise exception 'POS systems must use POS role'; end if;
  if p_app_type = 'client' and v_role not in ('back_office', 'office', 'inventory') then raise exception 'Invalid Client system role'; end if;

  if p_app_type = 'pos' then
    select coalesce(array_agg(distinct x), '{}'::text[]) into v_modules
    from unnest(coalesce(p_module_keys, '{}'::text[])) x
    where x in ('sales', 'inventory', 'customers', 'suppliers', 'purchases', 'expenses', 'restaurant', 'logs', 'cashier_shifts', 'notifications', 'tasks', 'support', 'terminal_day')
      and exists (select 1 from public.tenant_modules tm where tm.tenant_id = p_tenant_id and tm.module_key = x and tm.enabled);
    if coalesce(array_length(v_modules, 1), 0) = 0 then raise exception 'Select at least one enabled POS module'; end if;

    if nullif(upper(trim(coalesce(p_invoice_prefix, ''))), '') is null then
      v_prefix := private.v500_next_pos_invoice_prefix(p_tenant_id);
    else
      perform 1 from public.tenants where id = p_tenant_id for update;
      v_prefix := upper(trim(p_invoice_prefix));
      if exists (select 1 from public.business_devices d where d.tenant_id = p_tenant_id and d.app_type = 'pos' and upper(trim(coalesce(d.invoice_prefix, ''))) = v_prefix) then
        raise exception 'Terminal invoice prefix is already in use';
      end if;
    end if;
  else
    v_prefix := null;
  end if;

  v_code := upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 12));
  v_device_code := upper(p_app_type) || '-' || upper(substr(replace(v_id::text, '-', ''), 1, 8));
  insert into public.business_devices (
    id, tenant_id, location_id, device_code, name, app_type, platform_hint, status,
    activation_hash, activation_expires_at, activation_issued_at, activation_issued_by,
    allowed_modules, invoice_prefix, system_role, activation_count
  ) values (
    v_id, p_tenant_id, p_location_id, v_device_code, coalesce(nullif(trim(p_name), ''), 'System'), p_app_type,
    nullif(trim(p_platform_hint), ''), 'pending', encode(digest(v_code, 'sha256'), 'hex'), v_exp, now(), auth.uid(),
    v_modules, v_prefix, v_role, 1
  );

  perform private.business_audit_write_v471(
    p_tenant_id, 'system.create', 'business_device', v_id, v_device_code, null::jsonb,
    jsonb_build_object('location_id', p_location_id, 'app_type', p_app_type, 'system_role', v_role, 'modules', v_modules, 'invoice_prefix', v_prefix)
  );

  return jsonb_build_object(
    'device_id', v_id, 'device_code', v_device_code, 'activation_code', v_code, 'expires_at', v_exp,
    'location_id', p_location_id, 'invoice_prefix', v_prefix, 'allowed_modules', v_modules, 'system_role', v_role
  );
end;
$$;
revoke all on function public.tenant_system_create_v471(uuid, uuid, text, text, text, text[], text, text) from public, anon;
grant execute on function public.tenant_system_create_v471(uuid, uuid, text, text, text, text[], text, text) to authenticated, service_role;

-- 7. Harden public.tenant_device_issue_activation
create or replace function public.tenant_device_issue_activation(
  p_tenant_id uuid,
  p_location_id uuid,
  p_name text,
  p_app_type text,
  p_platform_hint text default null,
  p_module_keys text[] default '{}'::text[],
  p_invoice_prefix text default null
) returns jsonb
language plpgsql security definer
set search_path to 'public', 'private', 'extensions', 'pg_temp'
as $$
declare
  v_id uuid := gen_random_uuid();
  v_code text;
  v_device_code text;
  v_exp timestamptz := now() + interval '24 hours';
  v_modules text[];
begin
  if auth.role() <> 'service_role' and not (
    private.platform_v2_is_admin()
    or (auth.uid() is not null and (
      private.erp_user_is_owner(p_tenant_id, auth.uid())
      or private.erp_has_permission(p_tenant_id, 'locations.manage')
      or private.erp_has_permission(p_tenant_id, 'locations.manage_all')
    ))
  ) then
    raise exception 'Permission denied' using errcode = '42501';
  end if;

  if auth.role() <> 'service_role' and not private.platform_v2_is_admin() and not private.erp_user_is_owner(p_tenant_id, auth.uid())
     and not private.erp_user_location_allowed(p_tenant_id, p_location_id, 'manage') then
    raise exception 'Location manage access denied' using errcode = '42501';
  end if;

  if p_app_type not in ('client', 'pos') then
    raise exception 'Invalid app type';
  end if;

  if not exists (select 1 from public.business_locations where id = p_location_id and tenant_id = p_tenant_id and active) then
    raise exception 'Store location not found or inactive';
  end if;

  -- Subscription quota check
  perform private.subscription_check_quota(p_tenant_id, 'terminals', 1);

  if p_app_type = 'pos' then
    select coalesce(array_agg(distinct x), '{}'::text[]) into v_modules
    from unnest(coalesce(p_module_keys, '{}'::text[])) x
    where x in ('sales', 'inventory', 'customers', 'suppliers', 'purchases', 'expenses', 'restaurant', 'logs', 'cashier_shifts', 'notifications', 'tasks', 'support')
      and exists (select 1 from public.tenant_modules tm where tm.tenant_id = p_tenant_id and tm.module_key = x and tm.enabled);
  else
    v_modules := '{}'::text[];
  end if;

  if nullif(upper(trim(p_invoice_prefix)), '') is not null and exists (
    select 1 from public.business_devices d
    where d.tenant_id = p_tenant_id and d.status <> 'revoked' and upper(coalesce(d.invoice_prefix, '')) = upper(trim(p_invoice_prefix))
  ) then
    raise exception 'Terminal invoice prefix is already in use';
  end if;

  v_code := upper(substr(encode(gen_random_bytes(8), 'hex'), 1, 12));
  v_device_code := upper(p_app_type) || '-' || upper(substr(replace(v_id::text, '-', ''), 1, 6));

  insert into public.business_devices (
    id, tenant_id, location_id, device_code, name, app_type, platform_hint, status,
    activation_hash, activation_expires_at, allowed_modules, invoice_prefix,
    activation_issued_at, activation_issued_by, activation_count
  ) values (
    v_id, p_tenant_id, p_location_id, v_device_code, trim(p_name), p_app_type,
    nullif(trim(p_platform_hint), ''), 'pending', encode(digest(v_code, 'sha256'), 'hex'), v_exp,
    v_modules, nullif(upper(trim(p_invoice_prefix)), ''),
    now(), auth.uid(), 1
  );

  return jsonb_build_object(
    'device_id', v_id, 'device_code', v_device_code, 'activation_code', v_code, 'expires_at', v_exp, 'allowed_modules', v_modules
  );
end;
$$;
grant execute on function public.tenant_device_issue_activation(uuid, uuid, text, text, text, text[], text) to authenticated, service_role;

-- 8. Harden public.platform_business_location_save
create or replace function public.platform_business_location_save(
  p_tenant_id uuid,
  p_location_id uuid,
  p_parent_location_id uuid,
  p_location_code text,
  p_name text,
  p_location_type text,
  p_phone text,
  p_email text,
  p_gstin text,
  p_address_line1 text,
  p_address_line2 text,
  p_city text,
  p_state text,
  p_postal_code text,
  p_country text,
  p_invoice_prefix text,
  p_active boolean
) returns uuid
language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_id uuid;
  v_is_new boolean;
  v_is_activating boolean;
begin
  if auth.role() <> 'service_role' and not private.platform_v2_has_role('super_admin') and not private.platform_v2_has_role('support_admin') then
    raise exception 'Platform admin required';
  end if;
  if trim(coalesce(p_name, '')) = '' then raise exception 'Location name required'; end if;

  v_is_new := (p_location_id is null);
  if not v_is_new then
    select (not active and coalesce(p_active, true)) into v_is_activating
    from public.business_locations where id = p_location_id and tenant_id = p_tenant_id;
  else
    v_is_activating := false;
  end if;

  if (v_is_new and coalesce(p_active, true)) or coalesce(v_is_activating, false) then
    perform private.subscription_check_quota(p_tenant_id, 'locations', 1);
  end if;

  if p_location_id is null then
    insert into public.business_locations (
      tenant_id, parent_location_id, location_code, name, location_type,
      phone, email, gstin, address_line1, address_line2, city, state, postal_code,
      country, invoice_prefix, active
    )
    values (
      p_tenant_id, p_parent_location_id, upper(trim(p_location_code)), trim(p_name), p_location_type,
      nullif(trim(p_phone), ''), nullif(trim(p_email), ''), nullif(trim(p_gstin), ''),
      nullif(trim(p_address_line1), ''), nullif(trim(p_address_line2), ''), nullif(trim(p_city), ''),
      nullif(trim(p_state), ''), nullif(trim(p_postal_code), ''), coalesce(nullif(trim(p_country), ''), 'India'),
      nullif(trim(p_invoice_prefix), ''), coalesce(p_active, true)
    )
    returning id into v_id;
  else
    update public.business_locations set
      parent_location_id = p_parent_location_id,
      location_code = upper(trim(p_location_code)),
      name = trim(p_name),
      location_type = p_location_type,
      phone = nullif(trim(p_phone), ''),
      email = nullif(trim(p_email), ''),
      gstin = nullif(trim(p_gstin), ''),
      address_line1 = nullif(trim(p_address_line1), ''),
      address_line2 = nullif(trim(p_address_line2), ''),
      city = nullif(trim(p_city), ''),
      state = nullif(trim(p_state), ''),
      postal_code = nullif(trim(p_postal_code), ''),
      country = coalesce(nullif(trim(p_country), ''), 'India'),
      invoice_prefix = nullif(trim(p_invoice_prefix), ''),
      active = coalesce(p_active, true),
      updated_at = now()
    where id = p_location_id and tenant_id = p_tenant_id
    returning id into v_id;
    if v_id is null then raise exception 'Location not found'; end if;
  end if;

  perform private.platform_audit_write('location.save', 'business_location', v_id::text, p_tenant_id, jsonb_build_object('name', p_name, 'code', p_location_code));
  return v_id;
end;
$$;
grant execute on function public.platform_business_location_save(uuid, uuid, uuid, text, text, text, text, text, text, text, text, text, text, text, text, text, boolean) to authenticated, service_role;

-- 9. Harden public.tenant_business_location_save_v4
create or replace function public.tenant_business_location_save_v4(
  p_tenant_id uuid,
  p_location_id uuid,
  p_parent_location_id uuid,
  p_location_code text,
  p_name text,
  p_location_type text,
  p_phone text,
  p_email text,
  p_gstin text,
  p_address_line1 text,
  p_address_line2 text,
  p_city text,
  p_state text,
  p_postal_code text,
  p_country text,
  p_invoice_prefix text,
  p_logo_url text,
  p_active boolean
) returns uuid
language plpgsql security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_id uuid;
  v_settings jsonb;
  v_is_new boolean;
  v_is_activating boolean;
begin
  if auth.role() <> 'service_role' and not private.platform_v2_is_admin() then
    if not (auth.uid() is not null and (
      private.erp_user_is_owner(p_tenant_id, auth.uid())
      or private.erp_has_permission(p_tenant_id, 'locations.manage')
      or private.erp_has_permission(p_tenant_id, 'locations.manage_all')
    )) then
      raise exception 'Permission denied' using errcode = '42501';
    end if;
  end if;

  if trim(coalesce(p_location_code, '')) = '' then raise exception 'Location code required'; end if;
  if trim(coalesce(p_name, '')) = '' then raise exception 'Location name required'; end if;
  if p_parent_location_id is not null and not exists (select 1 from public.business_locations where id = p_parent_location_id and tenant_id = p_tenant_id) then
    raise exception 'Invalid parent location';
  end if;

  v_is_new := (p_location_id is null);
  if not v_is_new then
    select (not active and coalesce(p_active, true)) into v_is_activating
    from public.business_locations where id = p_location_id and tenant_id = p_tenant_id;
  else
    v_is_activating := false;
  end if;

  if (v_is_new and coalesce(p_active, true)) or coalesce(v_is_activating, false) then
    perform private.subscription_check_quota(p_tenant_id, 'locations', 1);
  end if;

  v_settings := jsonb_build_object('logo_url', nullif(trim(coalesce(p_logo_url, '')), ''));

  if p_location_id is null then
    insert into public.business_locations (
      tenant_id, parent_location_id, location_code, name, location_type, phone, email, gstin,
      address_line1, address_line2, city, state, postal_code, country, invoice_prefix, settings, active
    ) values (
      p_tenant_id, p_parent_location_id, upper(trim(p_location_code)), trim(p_name), p_location_type,
      nullif(trim(coalesce(p_phone, '')), ''), nullif(trim(coalesce(p_email, '')), ''), nullif(upper(trim(coalesce(p_gstin, ''))), ''),
      nullif(trim(coalesce(p_address_line1, '')), ''), nullif(trim(coalesce(p_address_line2, '')), ''), nullif(trim(coalesce(p_city, '')), ''),
      nullif(trim(coalesce(p_state, '')), ''), nullif(trim(coalesce(p_postal_code, '')), ''), coalesce(nullif(trim(coalesce(p_country, '')), ''), 'India'),
      nullif(upper(trim(coalesce(p_invoice_prefix, ''))), ''), v_settings, coalesce(p_active, true)
    ) returning id into v_id;
  else
    if auth.role() <> 'service_role' and not private.platform_v2_is_admin() and not private.erp_user_is_owner(p_tenant_id, auth.uid())
       and not private.erp_user_location_allowed(p_tenant_id, p_location_id, 'manage') then
      raise exception 'Location manage access denied' using errcode = '42501';
    end if;

    update public.business_locations set
      parent_location_id = p_parent_location_id,
      location_code = upper(trim(p_location_code)),
      name = trim(p_name),
      location_type = p_location_type,
      phone = nullif(trim(coalesce(p_phone, '')), ''),
      email = nullif(trim(coalesce(p_email, '')), ''),
      gstin = nullif(upper(trim(coalesce(p_gstin, ''))), ''),
      address_line1 = nullif(trim(coalesce(p_address_line1, '')), ''),
      address_line2 = nullif(trim(coalesce(p_address_line2, '')), ''),
      city = nullif(trim(coalesce(p_city, '')), ''),
      state = nullif(trim(coalesce(p_state, '')), ''),
      postal_code = nullif(trim(coalesce(p_postal_code, '')), ''),
      country = coalesce(nullif(trim(coalesce(p_country, '')), ''), 'India'),
      invoice_prefix = nullif(upper(trim(coalesce(p_invoice_prefix, ''))), ''),
      settings = coalesce(public.business_locations.settings, '{}'::jsonb) || v_settings,
      active = coalesce(p_active, true),
      updated_at = now()
    where id = p_location_id and tenant_id = p_tenant_id
    returning id into v_id;
  end if;

  if v_id is null then raise exception 'Location not found'; end if;
  return v_id;
end;
$$;
grant execute on function public.tenant_business_location_save_v4(uuid, uuid, uuid, text, text, text, text, text, text, text, text, text, text, text, text, text, text, boolean) to authenticated, service_role;

-- 10. Register Schema Release #717 / v8.3.11
insert into public.thq_schema_releases(migration_no, schema_version, release_name, notes)
values(
  717,
  'v8.3.11',
  'sec_p1_02_subscription_quota_enforcement',
  'Enforce authoritative subscription limits (max_locations, max_terminals) in platform_location_create_v709, platform_device_issue_activation_v709, tenant_system_create_v471, and location save routines with tenant concurrency locking.'
)
on conflict(migration_no) do update
set schema_version = excluded.schema_version,
    release_name = excluded.release_name,
    notes = excluded.notes;

commit;
