begin;

-- Production Supabase is already live with this migration.
-- Repository source mirror for THQ ERP v6.2.1 Direct Supply.

create or replace function private.aggregate_load_create_core_v621(
  p_tenant_id uuid,
  p_direction text,
  p_location_id uuid,
  p_variant_id uuid,
  p_quantity numeric,
  p_unit_code text,
  p_measurement_method text,
  p_body_length_ft numeric,
  p_body_width_ft numeric,
  p_body_height_ft numeric,
  p_gross_weight_kg numeric,
  p_tare_weight_kg numeric,
  p_net_weight_kg numeric,
  p_vehicle_id uuid,
  p_driver_id uuid,
  p_supplier_id uuid,
  p_customer_id uuid,
  p_source_name text,
  p_destination_name text,
  p_source_reference text,
  p_freight_mode text,
  p_freight_amount numeric,
  p_capacity_override boolean,
  p_capacity_override_reason text,
  p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_qty numeric;
  v_product text;
  v_vehicle public.service_vehicles%rowtype;
  v_driver public.logistics_drivers_v61%rowtype;
  v_capacity numeric;
  v_number text;
  v_id uuid;
  v_measure text:=lower(coalesce(p_measurement_method,'manual'));
  v_unit text:=upper(coalesce(nullif(trim(p_unit_code),''),'CFT'));
begin
  if lower(coalesce(p_direction,'')) not in('inbound','outbound','direct_delivery') then
    raise exception 'Invalid load direction';
  end if;

  if p_location_id is not null
     and not exists(
       select 1
       from public.business_locations l
       where l.id=p_location_id
         and l.tenant_id=p_tenant_id
         and l.active
     ) then
    raise exception 'Location not found';
  end if;

  select
    p.name
    || case
         when nullif(trim(v.name),'') is not null
              and lower(trim(v.name)) not in('default','standard')
         then ' - '||v.name
         else ''
       end
  into v_product
  from public.product_variants v
  join public.products p
    on p.id=v.product_id
   and p.tenant_id=v.tenant_id
  where v.id=p_variant_id
    and v.tenant_id=p_tenant_id
    and v.status='active'
    and p.status='active';

  if v_product is null then raise exception 'Product variant not found'; end if;

  if v_measure='dimensions' then
    if coalesce(p_body_length_ft,0)<=0
       or coalesce(p_body_width_ft,0)<=0
       or coalesce(p_body_height_ft,0)<=0 then
      raise exception 'Length, width and height are required for dimension measurement';
    end if;
    v_qty:=round(p_body_length_ft*p_body_width_ft*p_body_height_ft,3);
    v_unit:='CFT';
  elsif v_measure='weighbridge' then
    if coalesce(p_net_weight_kg,coalesce(p_gross_weight_kg,0)-coalesce(p_tare_weight_kg,0))<=0 then
      raise exception 'Positive net weight is required for weighbridge measurement';
    end if;
    v_qty:=coalesce(p_quantity,p_net_weight_kg);
    if coalesce(v_qty,0)<=0 then raise exception 'Positive quantity is required'; end if;
  elsif v_measure='manual' then
    v_qty:=p_quantity;
    if coalesce(v_qty,0)<=0 then raise exception 'Positive quantity is required'; end if;
  else
    raise exception 'Invalid measurement method';
  end if;

  if p_vehicle_id is not null then
    select * into v_vehicle
    from public.service_vehicles
    where id=p_vehicle_id and tenant_id=p_tenant_id and active;
    if v_vehicle.id is null then raise exception 'Vehicle not found'; end if;

    select coalesce(
      ap.nominal_capacity_cft,
      case when upper(coalesce(v_vehicle.capacity_unit,''))='CFT'
           then v_vehicle.capacity else null end
    )
    into v_capacity
    from (select 1) x
    left join public.aggregate_vehicle_profiles_v617 ap
      on ap.tenant_id=p_tenant_id
     and ap.vehicle_id=p_vehicle_id
     and ap.active;
  end if;

  if p_driver_id is not null then
    select * into v_driver
    from public.logistics_drivers_v61
    where id=p_driver_id and tenant_id=p_tenant_id and active;
    if v_driver.id is null then raise exception 'Driver not found'; end if;
  end if;

  if p_supplier_id is not null and not exists(
    select 1 from public.suppliers
    where id=p_supplier_id and tenant_id=p_tenant_id
  ) then raise exception 'Supplier not found'; end if;

  if p_customer_id is not null and not exists(
    select 1 from public.customers
    where id=p_customer_id and tenant_id=p_tenant_id
  ) then raise exception 'Customer not found'; end if;

  if v_unit='CFT' and v_capacity is not null and v_qty>v_capacity*1.05 then
    if not coalesce(p_capacity_override,false) then
      raise exception 'Load quantity % CFT exceeds vehicle capacity % CFT',v_qty,v_capacity;
    end if;
    if not private.erp_has_permission(p_tenant_id,'aggregate_yard.override_capacity') then
      raise exception 'Capacity override permission required' using errcode='42501';
    end if;
    if nullif(trim(coalesce(p_capacity_override_reason,'')),'') is null then
      raise exception 'Capacity override reason is required';
    end if;
  end if;

  if lower(coalesce(p_freight_mode,'none'))
     not in('none','own','hired','supplier','customer','included') then
    raise exception 'Invalid freight mode';
  end if;

  v_number:='LOAD-'||to_char(current_date,'YYYYMMDD')||'-'
    ||lpad(nextval('public.aggregate_load_number_seq_v617')::text,6,'0');

  insert into public.aggregate_loads_v617(
    tenant_id,load_number,direction,status,location_id,variant_id,
    product_name_snapshot,unit_code,quantity,measurement_method,
    body_length_ft,body_width_ft,body_height_ft,gross_weight_kg,
    tare_weight_kg,net_weight_kg,vehicle_id,driver_id,
    vehicle_registration_snapshot,driver_name_snapshot,driver_phone_snapshot,
    supplier_id,customer_id,source_name,destination_name,source_reference,
    freight_mode,freight_amount,capacity_override,capacity_override_reason,
    notes,created_by,updated_by
  )
  values(
    p_tenant_id,v_number,lower(p_direction),'draft',p_location_id,p_variant_id,
    v_product,v_unit,v_qty,v_measure,p_body_length_ft,p_body_width_ft,
    p_body_height_ft,p_gross_weight_kg,p_tare_weight_kg,
    coalesce(
      p_net_weight_kg,
      case when p_gross_weight_kg is not null and p_tare_weight_kg is not null
           then p_gross_weight_kg-p_tare_weight_kg end
    ),
    p_vehicle_id,p_driver_id,v_vehicle.registration_number,
    coalesce(v_driver.name,v_vehicle.driver_name),
    coalesce(v_driver.phone,v_vehicle.driver_phone),
    p_supplier_id,p_customer_id,nullif(trim(p_source_name),''),
    nullif(trim(p_destination_name),''),nullif(trim(p_source_reference),''),
    lower(coalesce(p_freight_mode,'none')),
    greatest(coalesce(p_freight_amount,0),0),
    coalesce(p_capacity_override,false),
    nullif(trim(p_capacity_override_reason),''),
    nullif(trim(p_notes),''),auth.uid(),auth.uid()
  )
  returning id into v_id;

  insert into public.aggregate_load_events_v617(
    tenant_id,load_id,event_type,to_status,note,created_by
  )
  values(
    p_tenant_id,v_id,'created','draft','Load ticket created',auth.uid()
  );

  return jsonb_build_object(
    'load_id',v_id,'load_number',v_number,'quantity',v_qty,
    'unit_code',v_unit,'vehicle_capacity_cft',v_capacity,'status','draft'
  );
end
$function$;

revoke all on function private.aggregate_load_create_core_v621(
  uuid,text,uuid,uuid,numeric,text,text,numeric,numeric,numeric,numeric,numeric,numeric,
  uuid,uuid,uuid,uuid,text,text,text,text,numeric,boolean,text,text
) from public,anon,authenticated;
grant execute on function private.aggregate_load_create_core_v621(
  uuid,text,uuid,uuid,numeric,text,text,numeric,numeric,numeric,numeric,numeric,numeric,
  uuid,uuid,uuid,uuid,text,text,text,text,numeric,boolean,text,text
) to postgres,service_role;

create or replace function public.aggregate_load_create_v617(
  p_tenant_id uuid,p_direction text,p_location_id uuid,p_variant_id uuid,
  p_quantity numeric,p_unit_code text,p_measurement_method text,
  p_body_length_ft numeric,p_body_width_ft numeric,p_body_height_ft numeric,
  p_gross_weight_kg numeric,p_tare_weight_kg numeric,p_net_weight_kg numeric,
  p_vehicle_id uuid,p_driver_id uuid,p_supplier_id uuid,p_customer_id uuid,
  p_source_name text,p_destination_name text,p_source_reference text,
  p_freight_mode text,p_freight_amount numeric,p_capacity_override boolean,
  p_capacity_override_reason text,p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  if lower(trim(coalesce(p_direction,'')))='direct_delivery' then
    raise exception 'Use the Direct Supply workflow for quarry-to-customer loads';
  end if;

  return private.aggregate_load_create_core_v621(
    p_tenant_id,p_direction,p_location_id,p_variant_id,p_quantity,p_unit_code,
    p_measurement_method,p_body_length_ft,p_body_width_ft,p_body_height_ft,
    p_gross_weight_kg,p_tare_weight_kg,p_net_weight_kg,p_vehicle_id,p_driver_id,
    p_supplier_id,p_customer_id,p_source_name,p_destination_name,p_source_reference,
    p_freight_mode,p_freight_amount,p_capacity_override,p_capacity_override_reason,
    p_notes
  );
end
$function$;

create or replace function public.aggregate_direct_load_create_v621(
  p_tenant_id uuid,p_operating_location_id uuid,p_variant_id uuid,
  p_quantity numeric,p_unit_code text,p_measurement_method text,
  p_body_length_ft numeric,p_body_width_ft numeric,p_body_height_ft numeric,
  p_vehicle_id uuid,p_driver_id uuid,p_supplier_id uuid,p_customer_id uuid,
  p_source_name text,p_destination_name text,p_source_reference text,
  p_freight_mode text,p_freight_amount numeric,p_capacity_override boolean,
  p_capacity_override_reason text,p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_transit_id uuid;
  v_result jsonb;
  v_load_id uuid;
  v_measure text:=lower(trim(coalesce(p_measurement_method,'manual')));
  v_unit text:=upper(trim(coalesce(p_unit_code,'')));
begin
  perform private.aggregate_direct_assert_manage_v621(p_tenant_id);
  perform private.v4_location_access(p_tenant_id,p_operating_location_id,'operate');

  if p_supplier_id is null then raise exception 'Supplier / quarry is required for Direct Supply'; end if;
  if p_customer_id is null then raise exception 'Customer is required for Direct Supply'; end if;

  if not exists(
    select 1
    from public.product_variants pv
    join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id
    where pv.id=p_variant_id and pv.tenant_id=p_tenant_id
      and pv.status='active' and p.status='active' and p.item_type='stock'
  ) then raise exception 'Active stock material not found'; end if;

  if v_measure='dimensions' then v_unit:='CFT'; end if;
  if v_unit='' then raise exception 'Direct Supply unit is required'; end if;

  if not (
    exists(
      select 1
      from public.product_variants pv
      join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id
      join public.inventory_units_v481 u
        on u.id=p.base_unit_id and u.tenant_id=p.tenant_id and u.active
      where pv.id=p_variant_id and pv.tenant_id=p_tenant_id
        and upper(u.code)=v_unit
    )
    or exists(
      select 1
      from public.product_units_v481 pu
      join public.inventory_units_v481 u
        on u.id=pu.unit_id and u.tenant_id=pu.tenant_id
      where pu.tenant_id=p_tenant_id and pu.variant_id=p_variant_id
        and pu.active and u.active and pu.allow_purchase and pu.allow_sale
        and upper(u.code)=v_unit
    )
  ) then
    raise exception 'Unit % is not configured for both Purchase and Sale for this material',v_unit;
  end if;

  v_transit_id:=private.aggregate_direct_ensure_transit_v621(
    p_tenant_id,p_operating_location_id
  );

  insert into public.location_product_settings(
    tenant_id,location_id,variant_id,active,updated_at
  )
  values(p_tenant_id,v_transit_id,p_variant_id,true,now())
  on conflict(tenant_id,location_id,variant_id)
  do update set active=true,updated_at=now();

  insert into public.location_stock_balances(tenant_id,location_id,variant_id)
  values(p_tenant_id,v_transit_id,p_variant_id)
  on conflict do nothing;

  v_result:=private.aggregate_load_create_core_v621(
    p_tenant_id,'direct_delivery',v_transit_id,p_variant_id,p_quantity,v_unit,
    v_measure,p_body_length_ft,p_body_width_ft,p_body_height_ft,
    null,null,null,p_vehicle_id,p_driver_id,p_supplier_id,p_customer_id,
    p_source_name,p_destination_name,p_source_reference,p_freight_mode,
    p_freight_amount,p_capacity_override,p_capacity_override_reason,
    concat_ws(' | ','Direct Supply',nullif(trim(coalesce(p_notes,'')),''))
  );

  v_load_id:=nullif(v_result->>'load_id','')::uuid;
  if v_load_id is null then raise exception 'Direct Supply load could not be created'; end if;

  insert into public.aggregate_load_events_v617(
    tenant_id,load_id,event_type,note,metadata,created_by
  )
  values(
    p_tenant_id,v_load_id,'direct_supply_prepared',
    'Direct Supply prepared with controlled transit stock',
    jsonb_build_object(
      'operating_location_id',p_operating_location_id,
      'transit_location_id',v_transit_id,'unit_code',v_unit
    ),
    auth.uid()
  );

  return v_result||jsonb_build_object(
    'operating_location_id',p_operating_location_id,
    'transit_location_id',v_transit_id,
    'commercial_state','awaiting_purchase'
  );
end
$function$;

create or replace function public.aggregate_load_status_v617(
  p_tenant_id uuid,p_load_id uuid,p_status text,p_note text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_row public.aggregate_loads_v617%rowtype;
  v_next text:=lower(trim(coalesce(p_status,'')));
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  select * into v_row
  from public.aggregate_loads_v617
  where id=p_load_id and tenant_id=p_tenant_id
  for update;

  if v_row.id is null then raise exception 'Load not found'; end if;
  if v_row.direction='direct_delivery' then
    raise exception 'Use the Direct Supply status workflow for this load';
  end if;

  if not (
    (v_row.status='draft' and v_next in('loading','cancelled'))
    or (v_row.status='loading' and v_next in('dispatched','in_transit','cancelled'))
    or (v_row.status='dispatched' and v_next in('in_transit','arrived','cancelled'))
    or (v_row.status='in_transit' and v_next in('arrived','cancelled'))
    or (
      v_row.status='arrived'
      and (
        (v_row.direction='inbound' and v_next in('received','cancelled'))
        or (v_row.direction='outbound' and v_next in('delivered','cancelled'))
      )
    )
    or (v_row.status='received' and v_next='completed')
    or (v_row.status='delivered' and v_next='completed')
  ) then
    raise exception 'Invalid load status transition: % -> %',v_row.status,v_next;
  end if;

  update public.aggregate_loads_v617
  set status=v_next,updated_by=auth.uid(),updated_at=now()
  where id=p_load_id and tenant_id=p_tenant_id;

  insert into public.aggregate_load_events_v617(
    tenant_id,load_id,event_type,from_status,to_status,note,created_by
  )
  values(
    p_tenant_id,p_load_id,'status_changed',v_row.status,v_next,
    nullif(trim(p_note),''),auth.uid()
  );

  return jsonb_build_object(
    'load_id',p_load_id,'load_number',v_row.load_number,'status',v_next
  );
end
$function$;

create or replace function public.aggregate_direct_status_v621(
  p_tenant_id uuid,p_load_id uuid,p_status text,p_note text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_row public.aggregate_loads_v617%rowtype;
  v_map public.aggregate_direct_transit_locations_v621%rowtype;
  v_next text:=lower(trim(coalesce(p_status,'')));
begin
  perform private.aggregate_direct_assert_manage_v621(p_tenant_id);

  select * into v_row
  from public.aggregate_loads_v617
  where id=p_load_id and tenant_id=p_tenant_id
  for update;

  if v_row.id is null or v_row.direction<>'direct_delivery' then
    raise exception 'Direct Supply load not found';
  end if;

  select * into v_map
  from public.aggregate_direct_transit_locations_v621 m
  where m.tenant_id=p_tenant_id and m.transit_location_id=v_row.location_id;

  if v_map.transit_location_id is null then
    raise exception 'Controlled transit mapping not found';
  end if;

  perform private.v4_location_access(
    p_tenant_id,v_map.operating_location_id,'operate'
  );

  if not (
    (v_row.status='draft' and v_next in('loading','cancelled'))
    or (v_row.status='loading' and v_next in('dispatched','in_transit','cancelled'))
    or (v_row.status='dispatched' and v_next in('in_transit','arrived','cancelled'))
    or (v_row.status='in_transit' and v_next in('arrived','cancelled'))
    or (v_row.status='arrived' and v_next in('delivered','cancelled'))
    or (v_row.status='delivered' and v_next='completed')
  ) then
    raise exception 'Invalid Direct Supply status transition: % -> %',v_row.status,v_next;
  end if;

  update public.aggregate_loads_v617
  set status=v_next,updated_by=auth.uid(),updated_at=now()
  where id=p_load_id and tenant_id=p_tenant_id;

  insert into public.aggregate_load_events_v617(
    tenant_id,load_id,event_type,from_status,to_status,note,metadata,created_by
  )
  values(
    p_tenant_id,p_load_id,'status_changed',v_row.status,v_next,
    nullif(trim(p_note),''),
    jsonb_build_object(
      'workflow','direct_supply',
      'operating_location_id',v_map.operating_location_id,
      'transit_location_id',v_map.transit_location_id
    ),
    auth.uid()
  );

  return jsonb_build_object(
    'load_id',p_load_id,
    'load_number',v_row.load_number,
    'status',v_next,
    'commercial_state',
      case
        when v_row.purchase_id is null then 'awaiting_purchase'
        when v_row.sale_id is null then 'ready_for_sale'
        else 'commercial_complete'
      end
  );
end
$function$;

revoke all on function public.aggregate_direct_status_v621(uuid,uuid,text,text) from public,anon;
grant execute on function public.aggregate_direct_status_v621(uuid,uuid,text,text)
  to authenticated,service_role;

revoke all on function public.aggregate_load_create_v617(
  uuid,text,uuid,uuid,numeric,text,text,numeric,numeric,numeric,numeric,numeric,numeric,
  uuid,uuid,uuid,uuid,text,text,text,text,numeric,boolean,text,text
) from public,anon;
grant execute on function public.aggregate_load_create_v617(
  uuid,text,uuid,uuid,numeric,text,text,numeric,numeric,numeric,numeric,numeric,numeric,
  uuid,uuid,uuid,uuid,text,text,text,text,numeric,boolean,text,text
) to authenticated,service_role;

revoke all on function public.aggregate_direct_load_create_v621(
  uuid,uuid,uuid,numeric,text,text,numeric,numeric,numeric,uuid,uuid,uuid,uuid,
  text,text,text,text,numeric,boolean,text,text
) from public,anon;
grant execute on function public.aggregate_direct_load_create_v621(
  uuid,uuid,uuid,numeric,text,text,numeric,numeric,numeric,uuid,uuid,uuid,uuid,
  text,text,text,text,numeric,boolean,text,text
) to authenticated,service_role;

revoke all on function public.aggregate_load_status_v617(uuid,uuid,text,text)
  from public,anon;
grant execute on function public.aggregate_load_status_v617(uuid,uuid,text,text)
  to authenticated,service_role;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  320,
  '6.2.1-aggregate-direct-permission-isolation',
  'Aggregate Direct Supply Permission Isolation',
  'Separates normal Yard load creation/status from Direct Supply. Generic Load Create and Status reject direct_delivery; Direct Supply uses a private shared load core plus dedicated direct.manage-authorized create/status RPCs scoped through the operating location. Capacity override remains separately permissioned. Existing normal Yard behavior remains unchanged.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
