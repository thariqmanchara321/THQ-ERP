-- THQ ERP v6.0.1 Mobile POS Purchase + Expense enablement
-- Preserves GST v5.2.2 Build 30 fail-closed transaction rules.

create or replace function public.gst_mobile_pos_purchase_create_v522(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_supplier_invoice_number text,
  p_purchase_date date,
  p_due_date date,
  p_items jsonb,
  p_additional_charges numeric default 0,
  p_round_off numeric default 0,
  p_initial_payment numeric default 0,
  p_payment_method text default 'cash',
  p_payment_reference text default null,
  p_notes text default null,
  p_location_id uuid default null,
  p_device_id uuid default null,
  p_request_id text default null,
  p_supply_type text default null,
  p_place_of_supply_code text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $$
declare
  v_result jsonb;
begin
  -- Mobile POS must post from its registered terminal/store and only when the
  -- terminal is explicitly enabled for Purchases.
  perform private.erp_validate_transaction_origin(
    p_tenant_id,
    p_location_id,
    p_device_id,
    'purchases'
  );

  v_result := public.gst_purchase_create_v520(
    p_tenant_id,
    p_supplier_id,
    p_supplier_invoice_number,
    p_purchase_date,
    p_due_date,
    p_items,
    p_additional_charges,
    p_round_off,
    p_initial_payment,
    p_payment_method,
    p_payment_reference,
    p_notes,
    p_location_id,
    p_device_id,
    p_request_id,
    p_supply_type,
    p_place_of_supply_code
  );

  if nullif(v_result->>'purchase_id','') is null
     or nullif(v_result->>'gst_snapshot_id','') is null
     or nullif(v_result->>'journal_id','') is null then
    raise exception 'Mobile POS Purchase is missing authoritative GST evidence; transaction rolled back';
  end if;

  return coalesce(v_result,'{}'::jsonb) || jsonb_build_object(
    'authoritative_gst', true,
    'channel', 'mobile_pos',
    'writer', 'gst_mobile_pos_purchase_create_v522',
    'legacy_fallback', false
  );
end;
$$;

revoke all on function public.gst_mobile_pos_purchase_create_v522(
  uuid,uuid,text,date,date,jsonb,numeric,numeric,numeric,text,text,text,uuid,uuid,text,text,text
) from public, anon;
grant execute on function public.gst_mobile_pos_purchase_create_v522(
  uuid,uuid,text,date,date,jsonb,numeric,numeric,numeric,text,text,text,uuid,uuid,text,text,text
) to authenticated, service_role;

create or replace function public.mobile_pos_expense_create_v601(
  p_tenant_id uuid,
  p_category_id uuid,
  p_expense_date date,
  p_payee text,
  p_description text,
  p_amount numeric,
  p_tax_amount numeric,
  p_round_off numeric,
  p_payment_method text,
  p_reference_number text,
  p_notes text,
  p_location_id uuid,
  p_device_id uuid,
  p_request_id text
) returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $$
declare
  v_result jsonb;
begin
  -- expenses_create_v489 ultimately validates the same transaction origin.
  -- Validate here as well so this mobile-specific entry point fails before any
  -- downstream work if the device/module is not authorized.
  perform private.erp_validate_transaction_origin(
    p_tenant_id,
    p_location_id,
    p_device_id,
    'expenses'
  );

  v_result := public.expenses_create_v489(
    p_tenant_id,
    p_category_id,
    p_expense_date,
    p_payee,
    p_description,
    p_amount,
    p_tax_amount,
    p_round_off,
    p_payment_method,
    p_reference_number,
    p_notes,
    p_location_id,
    p_device_id,
    p_request_id
  );

  if nullif(v_result->>'expense_id','') is null
     or nullif(v_result->>'journal_id','') is null
     or coalesce(v_result->>'accounting_integrity','') <> 'verified' then
    raise exception 'Mobile POS Expense accounting evidence is incomplete; transaction rolled back';
  end if;

  return coalesce(v_result,'{}'::jsonb) || jsonb_build_object(
    'channel', 'mobile_pos',
    'writer', 'mobile_pos_expense_create_v601',
    'accounting_integrity', 'verified'
  );
end;
$$;

revoke all on function public.mobile_pos_expense_create_v601(
  uuid,uuid,date,text,text,numeric,numeric,numeric,text,text,text,uuid,uuid,text
) from public, anon;
grant execute on function public.mobile_pos_expense_create_v601(
  uuid,uuid,date,text,text,numeric,numeric,numeric,text,text,text,uuid,uuid,text
) to authenticated, service_role;

-- Extend the existing v5.2.2 Build 30 contract instead of inventing a legacy
-- bypass. Mobile Purchase is now an explicit authoritative route.
create or replace function public.gst_transaction_cutover_contract_v522(
  p_tenant_id uuid,
  p_channel text default 'client',
  p_device_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $$
declare
  v jsonb;
  v_channel text := lower(trim(coalesce(p_channel,'client')));
begin
  v := public.gst_transaction_cutover_contract_v520(
    p_tenant_id,
    p_channel,
    p_device_id
  );

  if v_channel='client' then
    v := jsonb_set(
      v,
      '{channel_routes}',
      coalesce(v->'channel_routes','{}'::jsonb) ||
        jsonb_build_object('sale','gst_sale_create_v522'),
      true
    );
  elsif v_channel='pos' then
    v := jsonb_set(
      v,
      '{channel_routes}',
      coalesce(v->'channel_routes','{}'::jsonb) ||
        jsonb_build_object('sale','gst_pos_sale_create_v522'),
      true
    );
  elsif v_channel in ('pos_offline','offline_pos') then
    v := jsonb_set(
      v,
      '{channel_routes}',
      coalesce(v->'channel_routes','{}'::jsonb) ||
        jsonb_build_object('sale_sync','gst_pos_offline_sale_sync_v522'),
      true
    );
  elsif v_channel='mobile_pos' then
    v := jsonb_set(
      v,
      '{channel_routes}',
      coalesce(v->'channel_routes','{}'::jsonb) ||
        jsonb_build_object(
          'sale_sync','gst_mobile_pos_sale_sync_v522',
          'purchase','gst_mobile_pos_purchase_create_v522'
        ),
      true
    );
  end if;

  v := v || jsonb_build_object(
    'version','5.2.2',
    'build',30,
    'multi_payment',true,
    'automatic_round_off',true,
    'legacy_fallback_after_v522_failure',false,
    'additional_charges','service_products_only',
    'payment_methods',jsonb_build_array(
      'cash','upi','card','bank','cheque','wallet','credit','other'
    )
  );
  return v;
end;
$$;

-- Backward-compatible terminal context enrichment. Existing fields stay intact.
create or replace function public.mobile_pos_terminal_context_v488(
  p_tenant_id uuid,
  p_device_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $$
declare
  v_location uuid;
  d public.business_devices%rowtype;
  l public.business_locations%rowtype;
  v_settings jsonb := '{}'::jsonb;
  v_restaurant boolean := false;
  v_shift jsonb;
begin
  v_location := private.v488_mobile_pos_location(p_tenant_id,p_device_id);
  select * into d
  from public.business_devices
  where id=p_device_id and tenant_id=p_tenant_id;

  select * into l
  from public.business_locations
  where id=v_location and tenant_id=p_tenant_id;

  select to_jsonb(s) into v_settings
  from public.mobile_pos_terminal_settings_v488 s
  where s.tenant_id=p_tenant_id and s.device_id=p_device_id;

  select exists(
    select 1
    from public.tenant_modules tm
    where tm.tenant_id=p_tenant_id
      and tm.module_key='restaurant'
      and tm.enabled
  ) into v_restaurant;

  begin
    v_shift := public.cashier_shift_current_v472(p_tenant_id,p_device_id);
  exception when others then
    v_shift := null;
  end;

  return jsonb_build_object(
    'release','4.8.8',
    'mobile_pos',true,
    'device_id',d.id,
    'device_code',d.device_code,
    'device_name',d.name,
    'location_id',l.id,
    'location_code',l.location_code,
    'location_name',l.name,
    'username',coalesce(
      (select u.username::text from public.user_login_names u where u.user_id=auth.uid()),
      auth.uid()::text
    ),
    'restaurant_enabled',v_restaurant,
    'current_shift',v_shift,
    'settings',coalesce(v_settings,'{}'::jsonb),
    'allowed_modules',to_jsonb(coalesce(d.allowed_modules,'{}'::text[])),
    'offline_supported',true,
    'camera_scanner',true,
    'system_printing',true,
    'kot_groundwork',true,
    'mobile_purchase_authoritative',true,
    'mobile_expense_accounting_verified',true
  );
end;
$$;
