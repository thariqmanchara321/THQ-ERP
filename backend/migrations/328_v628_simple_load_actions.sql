begin;

create or replace function public.aggregate_load_detail_v628(
  p_tenant_id uuid,
  p_load_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare
  v_result jsonb;
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  select jsonb_build_object(
    'load_id',l.id,
    'load_number',l.load_number,
    'load_date',l.load_date,
    'direction',l.direction,
    'status',l.status,
    'location_id',l.location_id,
    'variant_id',l.variant_id,
    'product_name',l.product_name_snapshot,
    'unit_code',l.unit_code,
    'quantity',l.quantity,
    'measurement_method',l.measurement_method,
    'body_length_ft',l.body_length_ft,
    'body_width_ft',l.body_width_ft,
    'body_height_ft',l.body_height_ft,
    'gross_weight_kg',l.gross_weight_kg,
    'tare_weight_kg',l.tare_weight_kg,
    'net_weight_kg',l.net_weight_kg,
    'vehicle_id',l.vehicle_id,
    'driver_id',l.driver_id,
    'supplier_id',l.supplier_id,
    'customer_id',l.customer_id,
    'source_name',l.source_name,
    'destination_name',l.destination_name,
    'source_reference',l.source_reference,
    'freight_mode',l.freight_mode,
    'freight_amount',l.freight_amount,
    'capacity_override',l.capacity_override,
    'capacity_override_reason',l.capacity_override_reason,
    'notes',l.notes,
    'purchase_id',l.purchase_id,
    'sale_id',l.sale_id,
    'order_id',l.order_id,
    'order_line_id',l.order_line_id
  )
  into v_result
  from public.aggregate_loads_v617 l
  where l.id=p_load_id
    and l.tenant_id=p_tenant_id;

  if v_result is null then
    raise exception 'Load not found';
  end if;

  return v_result;
end
$function$;

revoke all on function public.aggregate_load_detail_v628(uuid,uuid)
from public,anon;
grant execute on function public.aggregate_load_detail_v628(uuid,uuid)
to authenticated,service_role;

create or replace function public.aggregate_load_confirm_v628(
  p_tenant_id uuid,
  p_load_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare
  v_row public.aggregate_loads_v617%rowtype;
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  select *
  into v_row
  from public.aggregate_loads_v617
  where id=p_load_id
    and tenant_id=p_tenant_id
  for update;

  if v_row.id is null then
    raise exception 'Load not found';
  end if;

  if v_row.status='completed' then
    return jsonb_build_object(
      'success',true,
      'already_confirmed',true,
      'load_id',v_row.id,
      'load_number',v_row.load_number,
      'status','completed'
    );
  end if;

  if v_row.status='cancelled' then
    raise exception 'Cancelled load cannot be confirmed';
  end if;

  update public.aggregate_loads_v617
  set status='completed',
      updated_by=auth.uid(),
      updated_at=now()
  where id=v_row.id
    and tenant_id=p_tenant_id;

  insert into public.aggregate_load_events_v617(
    tenant_id,load_id,event_type,from_status,to_status,note,created_by
  )
  values(
    p_tenant_id,v_row.id,'confirmed',v_row.status,'completed',
    'Load confirmed',auth.uid()
  );

  perform private.business_audit_write_v471(
    p_tenant_id,
    'aggregate_load.confirm',
    'aggregate_load',
    v_row.id,
    v_row.load_number,
    to_jsonb(v_row),
    jsonb_build_object('status','completed')
  );

  return jsonb_build_object(
    'success',true,
    'already_confirmed',false,
    'load_id',v_row.id,
    'load_number',v_row.load_number,
    'status','completed'
  );
end
$function$;

revoke all on function public.aggregate_load_confirm_v628(uuid,uuid)
from public,anon;
grant execute on function public.aggregate_load_confirm_v628(uuid,uuid)
to authenticated,service_role;

create or replace function public.aggregate_load_delete_v628(
  p_tenant_id uuid,
  p_load_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $function$
declare
  v_row public.aggregate_loads_v617%rowtype;
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  select *
  into v_row
  from public.aggregate_loads_v617
  where id=p_load_id
    and tenant_id=p_tenant_id
  for update;

  if v_row.id is null then
    raise exception 'Load not found';
  end if;

  if v_row.status='completed' then
    raise exception 'Confirmed load cannot be deleted';
  end if;

  if v_row.purchase_id is not null or v_row.sale_id is not null then
    raise exception 'Load linked to a Purchase or Sale cannot be deleted';
  end if;

  if v_row.order_id is not null or v_row.order_line_id is not null then
    raise exception 'Customer Order load cannot be deleted from Load Register';
  end if;

  if exists(
    select 1
    from public.aggregate_freight_settlements_v620 f
    where f.tenant_id=p_tenant_id
      and f.load_id=p_load_id
  ) then
    raise exception 'Load with settled freight cannot be deleted';
  end if;

  perform private.business_audit_write_v471(
    p_tenant_id,
    'aggregate_load.delete',
    'aggregate_load',
    v_row.id,
    v_row.load_number,
    to_jsonb(v_row),
    null
  );

  delete from public.aggregate_loads_v617
  where id=v_row.id
    and tenant_id=p_tenant_id;

  return jsonb_build_object(
    'success',true,
    'load_id',v_row.id,
    'load_number',v_row.load_number,
    'deleted',true
  );
end
$function$;

revoke all on function public.aggregate_load_delete_v628(uuid,uuid)
from public,anon;
grant execute on function public.aggregate_load_delete_v628(uuid,uuid)
to authenticated,service_role;

create or replace function public.aggregate_load_edit_v628(
  p_tenant_id uuid,
  p_load_id uuid,
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
set search_path=public,private,pg_temp
as $function$
declare
  v_row public.aggregate_loads_v617%rowtype;
  v_after public.aggregate_loads_v617%rowtype;
  v_qty numeric;
  v_product text;
  v_vehicle public.service_vehicles%rowtype;
  v_driver public.logistics_drivers_v61%rowtype;
  v_capacity numeric;
  v_measure text:=lower(coalesce(p_measurement_method,'manual'));
  v_unit text:=upper(coalesce(nullif(trim(p_unit_code),''),'CFT'));
  v_direction text:=lower(trim(coalesce(p_direction,'')));
  v_freight_mode text:=lower(coalesce(p_freight_mode,'none'));
begin
  perform private.aggregate_yard_assert_manage_v617(p_tenant_id);

  select *
  into v_row
  from public.aggregate_loads_v617
  where id=p_load_id
    and tenant_id=p_tenant_id
  for update;

  if v_row.id is null then
    raise exception 'Load not found';
  end if;

  if v_row.status in('completed','cancelled') then
    raise exception 'Confirmed or cancelled load cannot be edited';
  end if;

  if v_row.purchase_id is not null or v_row.sale_id is not null then
    raise exception 'Load linked to a Purchase or Sale cannot be edited';
  end if;

  if v_row.order_id is not null or v_row.order_line_id is not null then
    raise exception 'Customer Order load cannot be edited from Load Register';
  end if;

  if exists(
    select 1
    from public.aggregate_freight_settlements_v620 f
    where f.tenant_id=p_tenant_id
      and f.load_id=p_load_id
  ) then
    raise exception 'Load with settled freight cannot be edited';
  end if;

  if v_direction not in('inbound','outbound') then
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

  if v_product is null then
    raise exception 'Product variant not found';
  end if;

  if v_measure='dimensions' then
    if coalesce(p_body_length_ft,0)<=0
       or coalesce(p_body_width_ft,0)<=0
       or coalesce(p_body_height_ft,0)<=0 then
      raise exception 'Length, width and height are required for dimension measurement';
    end if;
    v_qty:=round(p_body_length_ft*p_body_width_ft*p_body_height_ft,3);
    v_unit:='CFT';
  elsif v_measure='weighbridge' then
    if coalesce(
         p_net_weight_kg,
         coalesce(p_gross_weight_kg,0)-coalesce(p_tare_weight_kg,0)
       )<=0 then
      raise exception 'Positive net weight is required for weighbridge measurement';
    end if;
    v_qty:=coalesce(p_quantity,p_net_weight_kg);
    if coalesce(v_qty,0)<=0 then
      raise exception 'Positive quantity is required';
    end if;
  elsif v_measure='manual' then
    v_qty:=p_quantity;
    if coalesce(v_qty,0)<=0 then
      raise exception 'Positive quantity is required';
    end if;
  else
    raise exception 'Invalid measurement method';
  end if;

  if p_vehicle_id is not null then
    select *
    into v_vehicle
    from public.service_vehicles
    where id=p_vehicle_id
      and tenant_id=p_tenant_id
      and active;

    if v_vehicle.id is null then
      raise exception 'Vehicle not found';
    end if;

    select coalesce(
      ap.nominal_capacity_cft,
      case
        when upper(coalesce(v_vehicle.capacity_unit,''))='CFT'
        then v_vehicle.capacity
        else null
      end
    )
    into v_capacity
    from (select 1) x
    left join public.aggregate_vehicle_profiles_v617 ap
      on ap.tenant_id=p_tenant_id
     and ap.vehicle_id=p_vehicle_id
     and ap.active;
  end if;

  if p_driver_id is not null then
    select *
    into v_driver
    from public.logistics_drivers_v61
    where id=p_driver_id
      and tenant_id=p_tenant_id
      and active;

    if v_driver.id is null then
      raise exception 'Driver not found';
    end if;
  end if;

  if p_supplier_id is not null
     and not exists(
       select 1 from public.suppliers
       where id=p_supplier_id and tenant_id=p_tenant_id
     ) then
    raise exception 'Supplier not found';
  end if;

  if p_customer_id is not null
     and not exists(
       select 1 from public.customers
       where id=p_customer_id and tenant_id=p_tenant_id
     ) then
    raise exception 'Customer not found';
  end if;

  if v_unit='CFT'
     and v_capacity is not null
     and v_qty>v_capacity*1.05 then
    if not coalesce(p_capacity_override,false) then
      raise exception
        'Load quantity % CFT exceeds vehicle capacity % CFT',
        v_qty,v_capacity;
    end if;

    if not private.erp_has_permission(
      p_tenant_id,'aggregate_yard.override_capacity'
    ) then
      raise exception 'Capacity override permission required'
        using errcode='42501';
    end if;

    if nullif(trim(coalesce(p_capacity_override_reason,'')),'') is null then
      raise exception 'Capacity override reason is required';
    end if;
  end if;

  if coalesce(p_capacity_override,false)
     and nullif(trim(coalesce(p_capacity_override_reason,'')),'') is null then
    raise exception 'Capacity override reason is required';
  end if;

  if v_freight_mode not in(
    'none','own','hired','supplier','customer','included'
  ) then
    raise exception 'Invalid freight mode';
  end if;

  update public.aggregate_loads_v617
  set direction=v_direction,
      location_id=p_location_id,
      variant_id=p_variant_id,
      product_name_snapshot=v_product,
      unit_code=v_unit,
      quantity=v_qty,
      measurement_method=v_measure,
      body_length_ft=p_body_length_ft,
      body_width_ft=p_body_width_ft,
      body_height_ft=p_body_height_ft,
      gross_weight_kg=p_gross_weight_kg,
      tare_weight_kg=p_tare_weight_kg,
      net_weight_kg=coalesce(
        p_net_weight_kg,
        case
          when p_gross_weight_kg is not null and p_tare_weight_kg is not null
          then p_gross_weight_kg-p_tare_weight_kg
        end
      ),
      vehicle_id=p_vehicle_id,
      driver_id=p_driver_id,
      vehicle_registration_snapshot=v_vehicle.registration_number,
      driver_name_snapshot=coalesce(v_driver.name,v_vehicle.driver_name),
      driver_phone_snapshot=coalesce(v_driver.phone,v_vehicle.driver_phone),
      supplier_id=p_supplier_id,
      customer_id=p_customer_id,
      source_name=nullif(trim(p_source_name),''),
      destination_name=nullif(trim(p_destination_name),''),
      source_reference=nullif(trim(p_source_reference),''),
      freight_mode=v_freight_mode,
      freight_amount=greatest(coalesce(p_freight_amount,0),0),
      capacity_override=coalesce(p_capacity_override,false),
      capacity_override_reason=nullif(trim(p_capacity_override_reason),''),
      notes=nullif(trim(p_notes),''),
      updated_by=auth.uid(),
      updated_at=now()
  where id=v_row.id
    and tenant_id=p_tenant_id
  returning * into v_after;

  insert into public.aggregate_load_events_v617(
    tenant_id,load_id,event_type,from_status,to_status,note,metadata,created_by
  )
  values(
    p_tenant_id,
    v_row.id,
    'edited',
    v_row.status,
    v_row.status,
    'Load details edited',
    jsonb_build_object(
      'old_quantity',v_row.quantity,
      'new_quantity',v_after.quantity,
      'old_unit_code',v_row.unit_code,
      'new_unit_code',v_after.unit_code
    ),
    auth.uid()
  );

  perform private.business_audit_write_v471(
    p_tenant_id,
    'aggregate_load.edit',
    'aggregate_load',
    v_row.id,
    v_row.load_number,
    to_jsonb(v_row),
    to_jsonb(v_after)
  );

  return jsonb_build_object(
    'success',true,
    'load_id',v_after.id,
    'load_number',v_after.load_number,
    'status',v_after.status,
    'quantity',v_after.quantity,
    'unit_code',v_after.unit_code
  );
end
$function$;

revoke all on function public.aggregate_load_edit_v628(
  uuid,uuid,text,uuid,uuid,numeric,text,text,numeric,numeric,numeric,
  numeric,numeric,numeric,uuid,uuid,uuid,uuid,text,text,text,text,numeric,
  boolean,text,text
) from public,anon;

grant execute on function public.aggregate_load_edit_v628(
  uuid,uuid,text,uuid,uuid,numeric,text,text,numeric,numeric,numeric,
  numeric,numeric,numeric,uuid,uuid,uuid,uuid,text,text,text,text,numeric,
  boolean,text,text
) to authenticated,service_role;

insert into public.thq_schema_releases(
  migration_no,
  schema_version,
  release_name,
  notes
)
values(
  328,
  '6.2.8-simple-load-actions',
  'Simple Load Confirm Edit Delete',
  'Simplifies Material Yard load management to Draft -> Confirmed with explicit Confirm, Edit and Delete actions. Load confirmation remains operational only and does not post stock, GST, accounting, receivables or payables.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
