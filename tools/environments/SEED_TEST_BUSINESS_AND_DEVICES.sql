-- ============================================================================
-- THQ ERP TEST ENVIRONMENT SEED SCRIPT
-- Project Target: krejepenqgcmnsugbpmv (THQ TEST DATABASE ONLY)
-- Safe to run repeatedly (Idempotent)
-- ============================================================================

do $test_seed$
declare
  v_tenant_id uuid := '11111111-1111-1111-1111-111111111111'::uuid;
  v_location_id uuid := '22222222-2222-2222-2222-222222222222'::uuid;
  v_client_dev_id uuid := '33333333-3333-3333-3333-333333333333'::uuid;
  v_pos_dev_id uuid := '44444444-4444-4444-4444-444444444444'::uuid;
  v_client_mob_id uuid := '55555555-5555-5555-5555-555555555555'::uuid;
  v_pos_mob_id uuid := '66666666-6666-6666-6666-666666666666'::uuid;
  v_act_code text := '123456';
  v_act_hash text;
begin
  -- ABSOLUTE SAFETY GUARD: Reject execution if NOT running on the test database!
  if not exists (select 1 from private.thq_test_environment_identity
                 where singleton and project_ref = 'krejepenqgcmnsugbpmv') then
    raise exception 'FATAL SAFETY ABORT: This seed script can ONLY run on the TEST database (krejepenqgcmnsugbpmv).';
  end if;

  v_act_hash := encode(digest(v_act_code, 'sha256'), 'hex');

  -- 1. Create / Ensure Test Tenant
  insert into public.tenants (
    id,
    business_code,
    name,
    slug,
    business_type,
    status,
    created_at,
    updated_at
  ) values (
    v_tenant_id,
    'THQTEST',
    'THQ Test Enterprise',
    'thqtest',
    'general',
    'active',
    now(),
    now()
  )
  on conflict (id) do update set
    business_code = 'THQTEST',
    name = 'THQ Test Enterprise',
    status = 'active';

  -- 2. Create / Ensure Test Tenant Settings
  insert into public.tenant_settings (
    tenant_id,
    currency_code,
    timezone,
    locale,
    config,
    created_at,
    updated_at
  ) values (
    v_tenant_id,
    'INR',
    'Asia/Kolkata',
    'en-IN',
    '{}'::jsonb,
    now(),
    now()
  )
  on conflict (tenant_id) do update set
    currency_code = 'INR',
    timezone = 'Asia/Kolkata';

  -- 3. Create / Ensure Test Business Location
  insert into public.business_locations (
    id,
    tenant_id,
    location_code,
    name,
    tracking_code,
    location_type,
    country,
    active,
    settings,
    hierarchy_role,
    sort_order,
    created_at,
    updated_at
  ) values (
    v_location_id,
    v_tenant_id,
    'MAIN',
    'Main Test Branch',
    'LOC-MAIN',
    'store',
    'IND',
    true,
    '{}'::jsonb,
    'standard',
    1,
    now(),
    now()
  )
  on conflict (id) do update set
    location_code = 'MAIN',
    name = 'Main Test Branch',
    active = true;

  -- 4. Enable All Core and Operational Modules for Test Tenant
  insert into public.tenant_modules (tenant_id, module_key, enabled)
  select v_tenant_id, m.key, true
  from public.modules m
  where m.is_active or m.key in ('aggregate_yard', 'staff', 'restaurant', 'logistics_operations')
  on conflict (tenant_id, module_key) do update set enabled = true;

  -- 5. Create / Ensure Test Desktop Client Device (Activation Code: 123456)
  insert into public.business_devices (
    id,
    tenant_id,
    location_id,
    device_code,
    name,
    app_type,
    platform_hint,
    status,
    activation_hash,
    activation_expires_at,
    activation_issued_at,
    allowed_modules,
    created_at,
    updated_at
  ) values (
    v_client_dev_id,
    v_tenant_id,
    v_location_id,
    'CLIENT-01',
    'Test Desktop Client',
    'client',
    'windows',
    'pending',
    v_act_hash,
    now() + interval '10 years',
    now(),
    array['sales', 'purchases', 'inventory', 'accounting', 'reports', 'logistics', 'aggregate_yard', 'staff'],
    now(),
    now()
  )
  on conflict (id) do update set
    status = case when business_devices.status = 'active' then 'active' else 'pending' end,
    activation_hash = v_act_hash,
    activation_expires_at = now() + interval '10 years';

  -- 6. Create / Ensure Test POS Device (Activation Code: 123456)
  insert into public.business_devices (
    id,
    tenant_id,
    location_id,
    device_code,
    name,
    app_type,
    platform_hint,
    status,
    activation_hash,
    activation_expires_at,
    activation_issued_at,
    allowed_modules,
    created_at,
    updated_at
  ) values (
    v_pos_dev_id,
    v_tenant_id,
    v_location_id,
    'POS-01',
    'Test POS Terminal',
    'pos',
    'windows',
    'pending',
    v_act_hash,
    now() + interval '10 years',
    now(),
    array['sales', 'pos', 'receipts', 'inventory', 'restaurant'],
    now(),
    now()
  )
  on conflict (id) do update set
    status = case when business_devices.status = 'active' then 'active' else 'pending' end,
    activation_hash = v_act_hash,
    activation_expires_at = now() + interval '10 years';

  -- 7. Create / Ensure Test Mobile Client Device (Activation Code: 123456)
  insert into public.business_devices (
    id,
    tenant_id,
    location_id,
    device_code,
    name,
    app_type,
    platform_hint,
    status,
    activation_hash,
    activation_expires_at,
    activation_issued_at,
    allowed_modules,
    created_at,
    updated_at
  ) values (
    v_client_mob_id,
    v_tenant_id,
    v_location_id,
    'CLIENT-MOB-01',
    'Test Mobile Client',
    'client',
    'android',
    'pending',
    v_act_hash,
    now() + interval '10 years',
    now(),
    array['sales', 'purchases', 'inventory', 'accounting', 'reports', 'logistics', 'aggregate_yard', 'staff'],
    now(),
    now()
  )
  on conflict (id) do update set
    status = case when business_devices.status = 'active' then 'active' else 'pending' end,
    activation_hash = v_act_hash,
    activation_expires_at = now() + interval '10 years';

  -- 8. Create / Ensure Test Mobile POS Device (Activation Code: 123456)
  insert into public.business_devices (
    id,
    tenant_id,
    location_id,
    device_code,
    name,
    app_type,
    platform_hint,
    status,
    activation_hash,
    activation_expires_at,
    activation_issued_at,
    allowed_modules,
    created_at,
    updated_at
  ) values (
    v_pos_mob_id,
    v_tenant_id,
    v_location_id,
    'POS-MOB-01',
    'Test Mobile POS',
    'pos',
    'android',
    'pending',
    v_act_hash,
    now() + interval '10 years',
    now(),
    array['sales', 'pos', 'receipts', 'inventory', 'restaurant'],
    now(),
    now()
  )
  on conflict (id) do update set
    status = case when business_devices.status = 'active' then 'active' else 'pending' end,
    activation_hash = v_act_hash,
    activation_expires_at = now() + interval '10 years';

  raise notice 'THQ TEST SEED COMPLETE: Business Code [THQTEST], Activation Code [%]', v_act_code;
end
$test_seed$;
