begin;

-- THQ ERP v6.0.1 Build 2 - P1 Stabilization 02
-- Migration 272
--
-- Scope:
--   1) Fail-closed device heartbeat / revocation enforcement.
--   2) Future authoritative GST Sales Return / Purchase Return global stock
--      movements retain their source reference.
--
-- Compatibility:
--   * Public function signatures are unchanged.
--   * Manual and legacy inventory_adjust_stock calls keep manual_adjustment
--     semantics.
--   * Historical movements are not rewritten.
--   * GST v5.1 legacy_unverified / v5.2 authoritative routing is unchanged.
--   * No legacy fallback is introduced.

create or replace function public.device_heartbeat_v4(
  p_tenant_id uuid,
  p_device_id uuid,
  p_app_key text,
  p_platform text,
  p_version text,
  p_build integer,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_latest record;
  v_installation text;
  v_location_id uuid;
  v_app_key text := lower(trim(coalesce(p_app_key,'')));
  v_updated integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if v_app_key not in ('client','pos') then
    raise exception 'Unsupported application';
  end if;

  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  if not exists(
    select 1
    from public.tenants t
    where t.id=p_tenant_id
      and t.status='active'
  ) then
    raise exception 'Business is inactive';
  end if;

  if not private.erp_user_app_allowed(p_tenant_id,v_app_key,auth.uid()) then
    raise exception 'This user is not enabled for this application';
  end if;

  select d.installation_id,d.location_id
    into v_installation,v_location_id
  from public.business_devices d
  where d.id=p_device_id
    and d.tenant_id=p_tenant_id
    and d.app_type=v_app_key
    and d.status='active';

  if not found then
    raise exception 'System installation is not active';
  end if;

  if nullif(trim(coalesce(v_installation,'')),'') is null then
    raise exception 'System installation is not active';
  end if;

  if v_app_key='pos' then
    perform private.v4_location_access(
      p_tenant_id,
      v_location_id,
      'operate'
    );
  else
    perform private.v4_location_access(
      p_tenant_id,
      v_location_id,
      'view'
    );
  end if;

  if not exists(
    select 1
    from public.system_installations si
    where si.tenant_id=p_tenant_id
      and si.system_id=p_device_id
      and si.installation_id=v_installation
      and si.status='active'
  ) then
    raise exception 'System installation is not active';
  end if;

  update public.business_devices d
  set last_seen_at=now()
  where d.id=p_device_id
    and d.tenant_id=p_tenant_id
    and d.app_type=v_app_key
    and d.status='active'
    and d.installation_id=v_installation;

  get diagnostics v_updated = row_count;
  if v_updated<>1 then
    raise exception 'System installation is not active';
  end if;

  update public.system_installations si
  set last_seen_at=now(),
      platform_hint=coalesce(nullif(trim(p_platform),''),si.platform_hint),
      app_version=nullif(trim(coalesce(p_version,'')),'')
  where si.tenant_id=p_tenant_id
    and si.system_id=p_device_id
    and si.installation_id=v_installation
    and si.status='active';

  get diagnostics v_updated = row_count;
  if v_updated<>1 then
    raise exception 'System installation is not active';
  end if;

  insert into public.device_app_status(
    device_id,
    tenant_id,
    app_key,
    platform,
    version,
    build_number,
    last_seen_at,
    metadata
  )
  values(
    p_device_id,
    p_tenant_id,
    v_app_key,
    p_platform,
    p_version,
    coalesce(p_build,0),
    now(),
    coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict(device_id) do update
  set tenant_id=excluded.tenant_id,
      app_key=excluded.app_key,
      platform=excluded.platform,
      version=excluded.version,
      build_number=excluded.build_number,
      last_seen_at=now(),
      metadata=excluded.metadata;

  select *
    into v_latest
  from public.platform_app_releases
  where app_key=v_app_key
    and platform=p_platform
    and status='stable'
  order by released_at desc
  limit 1;

  return jsonb_build_object(
    'latest_version',v_latest.version,
    'mandatory',coalesce(v_latest.mandatory,false),
    'status',
      case
        when v_latest.version is null or v_latest.version=p_version
          then 'latest'
        when coalesce(v_latest.mandatory,false)
          then 'update_required'
        else 'update_available'
      end,
    'release_notes',v_latest.release_notes,
    'download_url',v_latest.download_url,
    'backend',public.thq_backend_contract_v47()
  );
end
$function$;


create or replace function public.inventory_adjust_stock(
  p_tenant_id uuid,
  p_variant_id uuid,
  p_quantity_delta numeric,
  p_note text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_location_id uuid;
  v_item_type text;
  v_current_quantity numeric;
  v_new_quantity numeric;
  v_movement_type text;
  v_unit_cost numeric;

  -- Authoritative GST return context. These remain null for all ordinary,
  -- manual and legacy calls.
  v_context_type text;
  v_context_id uuid;
  v_reference_type text := 'manual_adjustment';
  v_reference_id uuid;
  v_reference_number text;
begin
  -- ----------------------------------------------------------
  -- PERMISSION (preserve existing behavior)
  -- ----------------------------------------------------------
  if not private.has_permission(
    p_tenant_id,
    'inventory.manage'
  ) then
    raise exception 'Access denied'
      using errcode = '42501';
  end if;

  -- ----------------------------------------------------------
  -- VALIDATE QUANTITY
  -- ----------------------------------------------------------
  if p_quantity_delta is null
     or p_quantity_delta = 0 then
    raise exception 'Adjustment quantity cannot be zero';
  end if;

  -- ----------------------------------------------------------
  -- AUTHORITATIVE GST RETURN REFERENCE
  --
  -- The v5.2 GST writers enter + bind this transaction context before
  -- inventory_adjust_stock is called. We intentionally recognize only
  -- return contexts. All other calls remain manual adjustments.
  -- ----------------------------------------------------------
  select c.source_type,c.source_id
    into v_context_type,v_context_id
  from private.gst_authoritative_tx_context_v520 c
  where c.txid=txid_current()
    and c.tenant_id=p_tenant_id
  limit 1;

  if v_context_type='sales_return' then
    if v_context_id is null then
      raise exception 'GST authoritative Sales Return context is not bound';
    end if;

    if p_quantity_delta<=0 then
      raise exception 'GST authoritative Sales Return stock movement must increase stock';
    end if;

    select sr.return_number
      into v_reference_number
    from public.sales_returns sr
    where sr.tenant_id=p_tenant_id
      and sr.id=v_context_id;

    if not found then
      raise exception 'GST authoritative Sales Return source not found';
    end if;

    v_movement_type := 'sale_return';
    v_reference_type := 'sales_return';
    v_reference_id := v_context_id;

  elsif v_context_type='purchase_return' then
    if v_context_id is null then
      raise exception 'GST authoritative Purchase Return context is not bound';
    end if;

    if p_quantity_delta>=0 then
      raise exception 'GST authoritative Purchase Return stock movement must decrease stock';
    end if;

    select pr.return_number
      into v_reference_number
    from public.purchase_returns pr
    where pr.tenant_id=p_tenant_id
      and pr.id=v_context_id;

    if not found then
      raise exception 'GST authoritative Purchase Return source not found';
    end if;

    v_movement_type := 'purchase_return';
    v_reference_type := 'purchase_return';
    v_reference_id := v_context_id;
  end if;

  -- ----------------------------------------------------------
  -- PRODUCT
  -- ----------------------------------------------------------
  select p.item_type,pv.cost_price
    into v_item_type,v_unit_cost
  from public.product_variants pv
  join public.products p
    on p.id=pv.product_id
   and p.tenant_id=pv.tenant_id
  where pv.id=p_variant_id
    and pv.tenant_id=p_tenant_id;

  if v_item_type is null then
    raise exception 'Product not found';
  end if;

  if v_item_type<>'stock' then
    raise exception 'Stock adjustment is only allowed for stock items';
  end if;

  -- ----------------------------------------------------------
  -- DEFAULT GLOBAL INVENTORY LOCATION (preserve existing behavior)
  -- ----------------------------------------------------------
  select il.id
    into v_location_id
  from public.inventory_locations il
  where il.tenant_id=p_tenant_id
    and il.is_active=true
  order by
    il.is_default desc,
    case when il.code='MAIN' then 0 else 1 end,
    il.created_at
  limit 1;

  if v_location_id is null then
    raise exception 'No active inventory location exists';
  end if;

  -- ----------------------------------------------------------
  -- ENSURE BALANCE ROW EXISTS
  -- ----------------------------------------------------------
  insert into public.stock_balances(
    tenant_id,
    location_id,
    variant_id,
    quantity,
    updated_at
  )
  values(
    p_tenant_id,
    v_location_id,
    p_variant_id,
    0,
    now()
  )
  on conflict(
    tenant_id,
    location_id,
    variant_id
  ) do nothing;

  -- ----------------------------------------------------------
  -- LOCK CURRENT BALANCE
  -- ----------------------------------------------------------
  select sb.quantity
    into v_current_quantity
  from public.stock_balances sb
  where sb.tenant_id=p_tenant_id
    and sb.location_id=v_location_id
    and sb.variant_id=p_variant_id
  for update;

  v_current_quantity:=coalesce(v_current_quantity,0);
  v_new_quantity:=v_current_quantity+p_quantity_delta;

  if v_new_quantity<0 then
    raise exception
      'Adjustment would make stock negative. Current stock: %',
      v_current_quantity;
  end if;

  -- Ordinary/manual/legacy calls keep the previous movement semantics.
  if v_movement_type is null then
    if p_quantity_delta>0 then
      v_movement_type:='adjustment_in';
    else
      v_movement_type:='adjustment_out';
    end if;
  end if;

  -- ----------------------------------------------------------
  -- STOCK MOVEMENT LEDGER
  -- ----------------------------------------------------------
  insert into public.stock_movements(
    tenant_id,
    variant_id,
    location_id,
    movement_type,
    quantity_delta,
    unit_cost,
    reference_type,
    reference_id,
    reference_number,
    note,
    occurred_at,
    created_by
  )
  values(
    p_tenant_id,
    p_variant_id,
    v_location_id,
    v_movement_type,
    p_quantity_delta,
    v_unit_cost,
    v_reference_type,
    v_reference_id,
    v_reference_number,
    nullif(trim(coalesce(p_note,'')),''),
    now(),
    auth.uid()
  );

  -- ----------------------------------------------------------
  -- UPDATE CURRENT BALANCE
  -- ----------------------------------------------------------
  update public.stock_balances
  set quantity=v_new_quantity,
      updated_at=now()
  where tenant_id=p_tenant_id
    and location_id=v_location_id
    and variant_id=p_variant_id;

  return jsonb_build_object(
    'success',true,
    'old_quantity',v_current_quantity,
    'quantity_delta',p_quantity_delta,
    'new_quantity',v_new_quantity
  );
end
$function$;


-- Migration self-checks. These validate the installed definitions without
-- creating any business transaction or rewriting historical evidence.
do $verify$
declare
  v_heartbeat text;
  v_stock text;
begin
  select pg_get_functiondef(p.oid)
    into v_heartbeat
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='device_heartbeat_v4'
    and p.prokind='f'
  limit 1;

  if v_heartbeat is null
     or position('Authentication required' in v_heartbeat)=0
     or position('erp_user_has_tenant_access' in v_heartbeat)=0
     or position('erp_user_app_allowed' in v_heartbeat)=0
     or position('v4_location_access' in v_heartbeat)=0
     or position('system_installations' in v_heartbeat)=0
     or position('d.app_type=v_app_key' in replace(v_heartbeat,' ',''))=0 then
    raise exception 'device_heartbeat_v4 hardening verification failed';
  end if;

  select pg_get_functiondef(p.oid)
    into v_stock
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='inventory_adjust_stock'
    and p.prokind='f'
  limit 1;

  if v_stock is null
     or position('gst_authoritative_tx_context_v520' in v_stock)=0
     or position('sales_return' in v_stock)=0
     or position('sales_returns' in v_stock)=0
     or position('purchase_return' in v_stock)=0
     or position('purchase_returns' in v_stock)=0
     or position('reference_id' in v_stock)=0
     or position('reference_number' in v_stock)=0
     or position('manual_adjustment' in v_stock)=0 then
    raise exception 'inventory_adjust_stock traceability verification failed';
  end if;
end
$verify$;


insert into public.thq_schema_releases(
  migration_no,
  schema_version,
  release_name,
  notes
)
values(
  272,
  '6.0.1-build2-p1b',
  'v6.0.1 Build 2 P1 Session and Return Traceability Hardening',
  'Fail-closes Client/POS device heartbeat against authentication, tenant/app/location/device/installation revocation. Future authoritative GST Sales and Purchase Returns now write globally referenced stock movements while preserving manual/legacy adjustment behavior and historical evidence.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
