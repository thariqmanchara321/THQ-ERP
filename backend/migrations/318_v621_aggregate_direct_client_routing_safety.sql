begin;

-- Production Supabase is already live with this migration.
-- Repository source mirror for THQ ERP v6.2.1 Direct Supply.

create or replace function public.aggregate_yard_context_v617(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare v_result jsonb;
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  select jsonb_build_object(
    'products',coalesce((
      select jsonb_agg(jsonb_build_object(
        'variant_id',v.id,'name',p.name,'variant_name',v.name,'sku',v.sku,
        'cost_price',v.cost_price,'selling_price',v.selling_price,
        'base_unit_code',bu.code,
        'sale_units',coalesce((
          select jsonb_agg(jsonb_build_object(
            'unit_id',u.id,'code',u.code,'name',u.name,'is_base',pu.is_base,
            'is_default_sale',pu.is_default_sale,
            'conversion_to_base',pu.conversion_to_base,'sale_price',pu.sale_price
          ) order by pu.is_default_sale desc,pu.is_base desc,u.code)
          from public.product_units_v481 pu
          join public.inventory_units_v481 u
            on u.id=pu.unit_id and u.tenant_id=pu.tenant_id
          where pu.tenant_id=p_tenant_id and pu.variant_id=v.id
            and pu.active and pu.allow_sale and u.active
        ),'[]'::jsonb)
      ) order by p.name,v.name)
      from public.product_variants v
      join public.products p
        on p.id=v.product_id and p.tenant_id=v.tenant_id
      left join public.inventory_units_v481 bu
        on bu.id=p.base_unit_id and bu.tenant_id=p.tenant_id
      where v.tenant_id=p_tenant_id and v.status='active' and p.status='active'
    ),'[]'::jsonb),
    'vehicles',coalesce((
      select jsonb_agg(jsonb_build_object(
        'vehicle_id',v.id,'registration_number',v.registration_number,
        'vehicle_type',v.vehicle_type,'capacity',v.capacity,
        'capacity_unit',v.capacity_unit,'driver_name',v.driver_name,
        'driver_phone',v.driver_phone,
        'ownership_type',coalesce(ap.ownership_type,'hired'),
        'owner_name',ap.owner_name,'owner_phone',ap.owner_phone,
        'body_length_ft',ap.body_length_ft,'body_width_ft',ap.body_width_ft,
        'body_height_ft',ap.body_height_ft,
        'nominal_capacity_cft',coalesce(
          ap.nominal_capacity_cft,
          case when upper(coalesce(v.capacity_unit,''))='CFT'
               then v.capacity else null end
        ),
        'tare_weight_kg',ap.tare_weight_kg,
        'max_payload_kg',ap.max_payload_kg,
        'default_freight',coalesce(ap.default_freight,0)
      ) order by v.registration_number)
      from public.service_vehicles v
      left join public.aggregate_vehicle_profiles_v617 ap
        on ap.tenant_id=v.tenant_id and ap.vehicle_id=v.id and ap.active
      where v.tenant_id=p_tenant_id and v.active
    ),'[]'::jsonb),
    'drivers',coalesce((
      select jsonb_agg(jsonb_build_object(
        'driver_id',d.id,'name',d.name,'phone',d.phone,
        'license_number',d.license_number
      ) order by d.name)
      from public.logistics_drivers_v61 d
      where d.tenant_id=p_tenant_id and d.active
    ),'[]'::jsonb),
    'suppliers',coalesce((
      select jsonb_agg(jsonb_build_object(
        'supplier_id',s.id,'name',s.name,'phone',s.phone
      ) order by s.name)
      from public.suppliers s
      where s.tenant_id=p_tenant_id and s.status='active'
    ),'[]'::jsonb),
    'customers',coalesce((
      select jsonb_agg(jsonb_build_object(
        'customer_id',c.id,'name',c.name,'phone',c.phone,'is_walk_in',c.is_walk_in
      ) order by c.name)
      from public.customers c
      where c.tenant_id=p_tenant_id and c.status='active'
    ),'[]'::jsonb),
    'locations',coalesce((
      select jsonb_agg(jsonb_build_object(
        'location_id',l.id,'code',l.location_code,'name',l.name,'type',l.location_type
      ) order by l.sort_order,l.name)
      from public.business_locations l
      where l.tenant_id=p_tenant_id
        and l.active
        and not exists(
          select 1
          from public.aggregate_direct_transit_locations_v621 m
          where m.tenant_id=l.tenant_id
            and m.transit_location_id=l.id
        )
    ),'[]'::jsonb)
  ) into v_result;

  return v_result;
end
$function$;

create or replace function public.aggregate_load_list_v619(
  p_tenant_id uuid,
  p_location_id uuid default null::uuid,
  p_status text default null::text,
  p_query text default null::text,
  p_limit integer default 300
)
returns table(
  load_id uuid,
  load_number text,
  load_date date,
  direction text,
  status text,
  location_id uuid,
  variant_id uuid,
  supplier_id uuid,
  customer_id uuid,
  product_name text,
  quantity numeric,
  unit_code text,
  measurement_method text,
  vehicle_id uuid,
  vehicle_registration text,
  driver_name text,
  supplier_name text,
  customer_name text,
  source_name text,
  destination_name text,
  source_reference text,
  freight_mode text,
  freight_amount numeric,
  purchase_id uuid,
  sale_id uuid,
  order_id uuid,
  order_line_id uuid,
  order_number text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  return query
  select
    l.id,l.load_number,l.load_date,l.direction,l.status,l.location_id,
    l.variant_id,l.supplier_id,l.customer_id,l.product_name_snapshot,
    l.quantity,l.unit_code,l.measurement_method,l.vehicle_id,
    l.vehicle_registration_snapshot,l.driver_name_snapshot,
    s.name,c.name,l.source_name,l.destination_name,l.source_reference,
    l.freight_mode,l.freight_amount,l.purchase_id,l.sale_id,
    l.order_id,l.order_line_id,o.order_number,l.created_at
  from public.aggregate_loads_v617 l
  left join public.suppliers s
    on s.id=l.supplier_id and s.tenant_id=l.tenant_id
  left join public.customers c
    on c.id=l.customer_id and c.tenant_id=l.tenant_id
  left join public.aggregate_orders_v618 o
    on o.id=l.order_id and o.tenant_id=l.tenant_id
  where l.tenant_id=p_tenant_id
    and l.direction<>'direct_delivery'
    and (p_location_id is null or l.location_id=p_location_id)
    and (p_status is null or trim(p_status)='' or l.status=lower(trim(p_status)))
    and (
      p_query is null or trim(p_query)=''
      or l.load_number ilike '%'||trim(p_query)||'%'
      or l.product_name_snapshot ilike '%'||trim(p_query)||'%'
      or coalesce(l.vehicle_registration_snapshot,'') ilike '%'||trim(p_query)||'%'
      or coalesce(l.driver_name_snapshot,'') ilike '%'||trim(p_query)||'%'
      or coalesce(s.name,'') ilike '%'||trim(p_query)||'%'
      or coalesce(c.name,'') ilike '%'||trim(p_query)||'%'
      or coalesce(o.order_number,'') ilike '%'||trim(p_query)||'%'
    )
  order by l.created_at desc
  limit greatest(1,least(coalesce(p_limit,300),1000));
end
$function$;

revoke all on function public.aggregate_yard_context_v617(uuid) from public,anon;
grant execute on function public.aggregate_yard_context_v617(uuid) to authenticated,service_role;

revoke all on function public.aggregate_load_list_v619(uuid,uuid,text,text,integer) from public,anon;
grant execute on function public.aggregate_load_list_v619(uuid,uuid,text,text,integer) to authenticated,service_role;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  318,
  '6.2.1-aggregate-direct-client-routing',
  'Aggregate Direct Supply Client Routing Safety',
  'Hides system Direct Supply transit locations from the generic Material Yard context and removes Direct Supply rows from the generic load-list RPC so they are only exposed through the dedicated permission-scoped Direct Supply API. This preserves older Client compatibility while preventing hidden transit locations or Direct Supply loads from appearing as normal Yard records.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,
    release_name=excluded.release_name,
    notes=excluded.notes;

commit;
