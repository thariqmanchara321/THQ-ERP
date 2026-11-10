
create or replace function public.aggregate_direct_materials_v621(
  p_tenant_id uuid
)
returns setof jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
begin
  perform private.aggregate_direct_assert_view_v621(p_tenant_id);

  return query
  select jsonb_build_object(
    'variant_id',pv.id,
    'product_name',p.name,
    'variant_name',pv.name,
    'sku',pv.sku,
    'base_unit_code',bu.code,
    'units',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'code',x.code,
          'name',x.name,
          'is_base',x.is_base,
          'allow_fractional',x.allow_fractional,
          'decimal_places',x.decimal_places
        )
        order by x.is_base desc,x.code
      )
      from (
        select
          u.code,
          u.name,
          pu.is_base,
          u.allow_fractional,
          u.decimal_places
        from public.product_units_v481 pu
        join public.inventory_units_v481 u
          on u.id=pu.unit_id
         and u.tenant_id=pu.tenant_id
        where pu.tenant_id=p_tenant_id
          and pu.variant_id=pv.id
          and pu.active
          and u.active
          and (
            pu.is_base
            or (pu.allow_purchase and pu.allow_sale)
          )
        union
        select
          bu2.code,
          bu2.name,
          true,
          bu2.allow_fractional,
          bu2.decimal_places
        from public.inventory_units_v481 bu2
        where bu2.id=p.base_unit_id
          and bu2.tenant_id=p.tenant_id
          and bu2.active
      ) x
    ),'[]'::jsonb)
  )
  from public.product_variants pv
  join public.products p
    on p.id=pv.product_id
   and p.tenant_id=pv.tenant_id
  left join public.inventory_units_v481 bu
    on bu.id=p.base_unit_id
   and bu.tenant_id=p.tenant_id
  where pv.tenant_id=p_tenant_id
    and pv.status='active'
    and p.status='active'
    and p.item_type='stock'
    and (
      p.base_unit_id is not null
      or exists(
        select 1
        from public.product_units_v481 pu
        where pu.tenant_id=p_tenant_id
          and pu.variant_id=pv.id
          and pu.active
          and pu.allow_purchase
          and pu.allow_sale
      )
    )
  order by p.name,pv.name;
end
$$;

revoke all
on function public.aggregate_direct_materials_v621(uuid)
from public,anon;

grant execute
on function public.aggregate_direct_materials_v621(uuid)
to authenticated,service_role;

create or replace function public.aggregate_direct_load_create_v621(
  p_tenant_id uuid,
  p_operating_location_id uuid,
  p_variant_id uuid,
  p_quantity numeric,
  p_unit_code text,
  p_measurement_method text,
  p_body_length_ft numeric,
  p_body_width_ft numeric,
  p_body_height_ft numeric,
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
as $$
declare
  v_transit_id uuid;
  v_result jsonb;
  v_load_id uuid;
  v_measure text:=lower(trim(coalesce(p_measurement_method,'manual')));
  v_unit text:=upper(trim(coalesce(p_unit_code,'')));
begin
  perform private.aggregate_direct_assert_manage_v621(p_tenant_id);
  perform private.v4_location_access(
    p_tenant_id,p_operating_location_id,'operate'
  );

  if p_supplier_id is null then
    raise exception 'Supplier / quarry is required for Direct Supply';
  end if;

  if p_customer_id is null then
    raise exception 'Customer is required for Direct Supply';
  end if;

  if not exists(
    select 1
    from public.product_variants pv
    join public.products p
      on p.id=pv.product_id
     and p.tenant_id=pv.tenant_id
    where pv.id=p_variant_id
      and pv.tenant_id=p_tenant_id
      and pv.status='active'
      and p.status='active'
      and p.item_type='stock'
  ) then
    raise exception 'Active stock material not found';
  end if;

  if v_measure='dimensions' then
    v_unit:='CFT';
  end if;

  if v_unit='' then
    raise exception 'Direct Supply unit is required';
  end if;

  if not (
    exists(
      select 1
      from public.product_variants pv
      join public.products p
        on p.id=pv.product_id
       and p.tenant_id=pv.tenant_id
      join public.inventory_units_v481 u
        on u.id=p.base_unit_id
       and u.tenant_id=p.tenant_id
       and u.active
      where pv.id=p_variant_id
        and pv.tenant_id=p_tenant_id
        and upper(u.code)=v_unit
    )
    or exists(
      select 1
      from public.product_units_v481 pu
      join public.inventory_units_v481 u
        on u.id=pu.unit_id
       and u.tenant_id=pu.tenant_id
      where pu.tenant_id=p_tenant_id
        and pu.variant_id=p_variant_id
        and pu.active
        and u.active
        and pu.allow_purchase
        and pu.allow_sale
        and upper(u.code)=v_unit
    )
  ) then
    raise exception
      'Unit % is not configured for both Purchase and Sale for this material',
      v_unit;
  end if;

  v_transit_id:=private.aggregate_direct_ensure_transit_v621(
    p_tenant_id,p_operating_location_id
  );

  insert into public.location_product_settings(
    tenant_id,location_id,variant_id,active,updated_at
  )
  values(
    p_tenant_id,v_transit_id,p_variant_id,true,now()
  )
  on conflict(tenant_id,location_id,variant_id)
  do update set
    active=true,
    updated_at=now();

  insert into public.location_stock_balances(
    tenant_id,location_id,variant_id
  )
  values(
    p_tenant_id,v_transit_id,p_variant_id
  )
  on conflict do nothing;

  v_result:=public.aggregate_load_create_v617(
    p_tenant_id,
    'direct_delivery',
    v_transit_id,
    p_variant_id,
    p_quantity,
    v_unit,
    v_measure,
    p_body_length_ft,
    p_body_width_ft,
    p_body_height_ft,
    null,
    null,
    null,
    p_vehicle_id,
    p_driver_id,
    p_supplier_id,
    p_customer_id,
    p_source_name,
    p_destination_name,
    p_source_reference,
    p_freight_mode,
    p_freight_amount,
    p_capacity_override,
    p_capacity_override_reason,
    concat_ws(
      ' | ',
      'Direct Supply',
      nullif(trim(coalesce(p_notes,'')),'')
    )
  );

  v_load_id:=nullif(v_result->>'load_id','')::uuid;

  if v_load_id is null then
    raise exception 'Direct Supply load could not be created';
  end if;

  insert into public.aggregate_load_events_v617(
    tenant_id,
    load_id,
    event_type,
    note,
    metadata,
    created_by
  )
  values(
    p_tenant_id,
    v_load_id,
    'direct_supply_prepared',
    'Direct Supply prepared with controlled transit stock',
    jsonb_build_object(
      'operating_location_id',p_operating_location_id,
      'transit_location_id',v_transit_id,
      'unit_code',v_unit
    ),
    auth.uid()
  );

  return v_result||jsonb_build_object(
    'operating_location_id',p_operating_location_id,
    'transit_location_id',v_transit_id,
    'commercial_state','awaiting_purchase'
  );
end
$$;

revoke all
on function public.aggregate_direct_load_create_v621(
  uuid,uuid,uuid,numeric,text,text,numeric,numeric,numeric,
  uuid,uuid,uuid,uuid,text,text,text,text,numeric,boolean,text,text
)
from public,anon;

grant execute
on function public.aggregate_direct_load_create_v621(
  uuid,uuid,uuid,numeric,text,text,numeric,numeric,numeric,
  uuid,uuid,uuid,uuid,text,text,text,text,numeric,boolean,text,text
)
to authenticated,service_role;

insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  314,
  '6.2.1-aggregate-direct-uom',
  'Aggregate Direct Supply UOM Safety',
  'Adds a Direct Supply material/unit catalog and rejects direct loads whose entered unit is not compatible with both Purchase and Sale. Base units remain valid for backward-compatible stock products.'
);;
