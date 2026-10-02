begin;

-- THQ ERP v6.2.1 Direct Supply source mirror.
-- Production received the 311-315 changes incrementally. The original SQL
-- files were live-only and absent from Git, so this repository copy records
-- the final production definitions through migration 315 for deterministic
-- source recovery. Migrations 312-315 below preserve the release registry
-- sequence and document the incremental production checkpoints.

insert into public.permissions(key,module_key,name,description)
values
  ('aggregate_yard.direct.view','aggregate_yard','View Direct Supply','View quarry-to-customer direct supply loads and transit status'),
  ('aggregate_yard.direct.manage','aggregate_yard','Manage Direct Supply','Create and commercially link quarry-to-customer direct supply loads through controlled transit stock')
on conflict(key) do update
set module_key=excluded.module_key,
    name=excluded.name,
    description=excluded.description;

create table if not exists public.aggregate_direct_transit_locations_v621(
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operating_location_id uuid not null references public.business_locations(id) on delete restrict,
  transit_location_id uuid not null unique references public.business_locations(id) on delete restrict,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  primary key(tenant_id,operating_location_id)
);

create index if not exists aggregate_direct_transit_locations_v621_transit_idx
  on public.aggregate_direct_transit_locations_v621(tenant_id,transit_location_id);

alter table public.aggregate_direct_transit_locations_v621 enable row level security;

revoke all on table public.aggregate_direct_transit_locations_v621 from public,anon,authenticated;
grant select on table public.aggregate_direct_transit_locations_v621 to authenticated;
grant all on table public.aggregate_direct_transit_locations_v621 to service_role;

create or replace function private.aggregate_direct_user_has_permission_v621(
  p_tenant_id uuid,
  p_permission_key text,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
  select exists(
    select 1
    from public.tenant_memberships tm
    join public.user_roles ur
      on ur.tenant_id=tm.tenant_id
     and ur.membership_id=tm.id
    join public.roles r
      on r.id=ur.role_id
     and r.tenant_id=tm.tenant_id
    left join public.role_permissions rp
      on rp.role_id=r.id
    where tm.tenant_id=p_tenant_id
      and tm.user_id=p_user_id
      and tm.status='active'
      and (
        r.key='owner'
        or rp.permission_key=p_permission_key
      )
  );
$function$;

create or replace function private.aggregate_direct_assert_view_v621(p_tenant_id uuid)
returns void
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode='42501';
  end if;

  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Tenant access required' using errcode='42501';
  end if;

  if not exists(
    select 1
    from public.tenant_modules tm
    where tm.tenant_id=p_tenant_id
      and tm.module_key='aggregate_yard'
      and tm.enabled
  ) then
    raise exception 'Material Yard module is not enabled' using errcode='42501';
  end if;

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'aggregate_yard.direct.view')
    or private.erp_has_permission(p_tenant_id,'aggregate_yard.direct.manage')
    or private.erp_has_permission(p_tenant_id,'aggregate_yard.manage')
  ) then
    raise exception 'Direct Supply view permission required' using errcode='42501';
  end if;
end
$function$;

create or replace function private.aggregate_direct_assert_manage_v621(p_tenant_id uuid)
returns void
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
begin
  perform private.aggregate_direct_assert_view_v621(p_tenant_id);

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'aggregate_yard.direct.manage')
  ) then
    raise exception 'Direct Supply manage permission required' using errcode='42501';
  end if;
end
$function$;

create or replace function private.aggregate_direct_ensure_transit_v621(
  p_tenant_id uuid,
  p_operating_location_id uuid
)
returns uuid
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_existing uuid;
  v_source public.business_locations%rowtype;
  v_transit_id uuid;
  v_suffix text;
  v_code text;
  v_prefix text;
begin
  select * into v_source
  from public.business_locations l
  where l.id=p_operating_location_id
    and l.tenant_id=p_tenant_id
    and l.active
  for update;

  if v_source.id is null then
    raise exception 'Operating location not found';
  end if;

  select m.transit_location_id into v_existing
  from public.aggregate_direct_transit_locations_v621 m
  where m.tenant_id=p_tenant_id
    and m.operating_location_id=p_operating_location_id;

  if v_existing is not null then
    update public.business_locations t
    set parent_location_id=v_source.id,
        name='Direct Supply Transit • '||v_source.name,
        location_type='warehouse',
        phone=v_source.phone,
        email=v_source.email,
        gstin=v_source.gstin,
        address_line1=v_source.address_line1,
        address_line2=v_source.address_line2,
        city=v_source.city,
        state=v_source.state,
        postal_code=v_source.postal_code,
        country=v_source.country,
        active=true,
        settings=coalesce(t.settings,'{}'::jsonb)||jsonb_build_object(
          'aggregate_virtual_transit',true,
          'system_managed',true,
          'operating_location_id',v_source.id,
          'operating_location_code',v_source.location_code
        ),
        hierarchy_role='operational',
        sort_order=9999,
        updated_at=now()
    where t.id=v_existing and t.tenant_id=p_tenant_id;

    if not found then
      raise exception 'Mapped Direct Supply transit location is missing';
    end if;
    return v_existing;
  end if;

  if exists(
    select 1 from public.aggregate_direct_transit_locations_v621 m
    where m.tenant_id=p_tenant_id
      and m.transit_location_id=p_operating_location_id
  ) then
    raise exception 'A transit location cannot be used as the operating location';
  end if;

  v_suffix:=upper(substr(replace(p_operating_location_id::text,'-',''),1,8));
  v_code:='AGGDST-'||v_suffix;
  v_prefix:='DST'||substr(v_suffix,1,6);

  if exists(
    select 1 from public.business_locations l
    where l.tenant_id=p_tenant_id
      and upper(l.location_code)=upper(v_code)
  ) then
    raise exception 'Reserved Direct Supply transit code % is already in use',v_code;
  end if;

  insert into public.business_locations(
    tenant_id,parent_location_id,location_code,tracking_code,name,
    location_type,phone,email,gstin,address_line1,address_line2,
    city,state,postal_code,country,invoice_prefix,active,settings,
    hierarchy_role,sort_order
  ) values(
    p_tenant_id,v_source.id,v_code,null,
    'Direct Supply Transit • '||v_source.name,
    'warehouse',v_source.phone,v_source.email,v_source.gstin,
    v_source.address_line1,v_source.address_line2,v_source.city,
    v_source.state,v_source.postal_code,v_source.country,v_prefix,
    true,
    jsonb_build_object(
      'aggregate_virtual_transit',true,
      'system_managed',true,
      'operating_location_id',v_source.id,
      'operating_location_code',v_source.location_code
    ),
    'operational',9999
  ) returning id into v_transit_id;

  insert into public.aggregate_direct_transit_locations_v621(
    tenant_id,operating_location_id,transit_location_id,created_by
  ) values(p_tenant_id,v_source.id,v_transit_id,auth.uid());

  return v_transit_id;
end
$function$;

create or replace function private.erp_user_location_allowed(
  p_tenant_id uuid,
  p_location_id uuid,
  p_required text default 'view'::text,
  p_user_id uuid default auth.uid()
)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_level text;
  v_rank int;
  v_required int;
  v_operating_location_id uuid;
  v_required_norm text:=lower(coalesce(p_required,'view'));
begin
  if p_user_id is null then return false; end if;

  select m.operating_location_id into v_operating_location_id
  from public.aggregate_direct_transit_locations_v621 m
  where m.tenant_id=p_tenant_id and m.transit_location_id=p_location_id;

  if v_operating_location_id is not null then
    if not exists(
      select 1 from public.tenant_modules tm
      where tm.tenant_id=p_tenant_id
        and tm.module_key='aggregate_yard'
        and tm.enabled
    ) then return false; end if;

    if private.erp_user_is_owner(p_tenant_id,p_user_id) then return true; end if;

    if v_required_norm in('operate','manage') then
      if not private.aggregate_direct_user_has_permission_v621(
        p_tenant_id,'aggregate_yard.direct.manage',p_user_id
      ) then return false; end if;
    else
      if not (
        private.aggregate_direct_user_has_permission_v621(
          p_tenant_id,'aggregate_yard.direct.view',p_user_id
        ) or private.aggregate_direct_user_has_permission_v621(
          p_tenant_id,'aggregate_yard.direct.manage',p_user_id
        )
      ) then return false; end if;
    end if;

    if private.aggregate_direct_user_has_permission_v621(
      p_tenant_id,'locations.manage_all',p_user_id
    ) then return true; end if;

    if v_required_norm='view' and private.aggregate_direct_user_has_permission_v621(
      p_tenant_id,'locations.view_all',p_user_id
    ) then return true; end if;

    p_location_id:=v_operating_location_id;
  end if;

  if private.erp_user_is_owner(p_tenant_id,p_user_id) then return true; end if;

  select access_level into v_level
  from public.business_user_location_access
  where tenant_id=p_tenant_id
    and user_id=p_user_id
    and location_id=p_location_id;

  if v_level is null then return false; end if;

  v_rank:=case v_level when 'manage' then 3 when 'operate' then 2 else 1 end;
  v_required:=case v_required_norm when 'manage' then 3 when 'operate' then 2 else 1 end;
  return v_rank>=v_required;
end
$function$;

create or replace function public.aggregate_direct_prepare_v621(
  p_tenant_id uuid,
  p_operating_location_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_transit_id uuid;
  v_transit public.business_locations%rowtype;
  v_operating public.business_locations%rowtype;
begin
  perform private.aggregate_direct_assert_manage_v621(p_tenant_id);
  perform private.v4_location_access(p_tenant_id,p_operating_location_id,'operate');

  v_transit_id:=private.aggregate_direct_ensure_transit_v621(
    p_tenant_id,p_operating_location_id
  );

  select * into v_operating from public.business_locations
  where id=p_operating_location_id and tenant_id=p_tenant_id;
  select * into v_transit from public.business_locations
  where id=v_transit_id and tenant_id=p_tenant_id and active;

  return jsonb_build_object(
    'operating_location_id',v_operating.id,
    'operating_location_code',v_operating.location_code,
    'operating_location_name',v_operating.name,
    'transit_location_id',v_transit.id,
    'transit_location_code',v_transit.location_code,
    'transit_location_name',v_transit.name,
    'legal_state',v_transit.state,
    'gstin',v_transit.gstin
  );
end
$function$;

create or replace function public.aggregate_direct_materials_v621(p_tenant_id uuid)
returns setof jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
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
      select jsonb_agg(jsonb_build_object(
        'code',x.code,'name',x.name,'is_base',x.is_base,
        'allow_fractional',x.allow_fractional,'decimal_places',x.decimal_places
      ) order by x.is_base desc,x.code)
      from (
        select u.code,u.name,pu.is_base,u.allow_fractional,u.decimal_places
        from public.product_units_v481 pu
        join public.inventory_units_v481 u
          on u.id=pu.unit_id and u.tenant_id=pu.tenant_id
        where pu.tenant_id=p_tenant_id
          and pu.variant_id=pv.id
          and pu.active and u.active
          and (pu.is_base or (pu.allow_purchase and pu.allow_sale))
        union
        select bu2.code,bu2.name,true,bu2.allow_fractional,bu2.decimal_places
        from public.inventory_units_v481 bu2
        where bu2.id=p.base_unit_id
          and bu2.tenant_id=p.tenant_id
          and bu2.active
      ) x
    ),'[]'::jsonb)
  )
  from public.product_variants pv
  join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id
  left join public.inventory_units_v481 bu on bu.id=p.base_unit_id and bu.tenant_id=p.tenant_id
  where pv.tenant_id=p_tenant_id
    and pv.status='active'
    and p.status='active'
    and p.item_type='stock'
    and (
      p.base_unit_id is not null
      or exists(
        select 1 from public.product_units_v481 pu
        where pu.tenant_id=p_tenant_id
          and pu.variant_id=pv.id
          and pu.active
          and pu.allow_purchase
          and pu.allow_sale
      )
    )
  order by p.name,pv.name;
end
$function$;

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
    where pv.id=p_variant_id
      and pv.tenant_id=p_tenant_id
      and pv.status='active'
      and p.status='active'
      and p.item_type='stock'
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
      where pv.id=p_variant_id and pv.tenant_id=p_tenant_id and upper(u.code)=v_unit
    )
    or exists(
      select 1
      from public.product_units_v481 pu
      join public.inventory_units_v481 u
        on u.id=pu.unit_id and u.tenant_id=pu.tenant_id
      where pu.tenant_id=p_tenant_id
        and pu.variant_id=p_variant_id
        and pu.active and u.active
        and pu.allow_purchase and pu.allow_sale
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
  ) values(p_tenant_id,v_transit_id,p_variant_id,true,now())
  on conflict(tenant_id,location_id,variant_id)
  do update set active=true,updated_at=now();

  insert into public.location_stock_balances(tenant_id,location_id,variant_id)
  values(p_tenant_id,v_transit_id,p_variant_id)
  on conflict do nothing;

  v_result:=public.aggregate_load_create_v617(
    p_tenant_id,'direct_delivery',v_transit_id,p_variant_id,p_quantity,v_unit,v_measure,
    p_body_length_ft,p_body_width_ft,p_body_height_ft,null,null,null,
    p_vehicle_id,p_driver_id,p_supplier_id,p_customer_id,p_source_name,
    p_destination_name,p_source_reference,p_freight_mode,p_freight_amount,
    p_capacity_override,p_capacity_override_reason,
    concat_ws(' | ','Direct Supply',nullif(trim(coalesce(p_notes,'')),''))
  );

  v_load_id:=nullif(v_result->>'load_id','')::uuid;
  if v_load_id is null then raise exception 'Direct Supply load could not be created'; end if;

  insert into public.aggregate_load_events_v617(
    tenant_id,load_id,event_type,note,metadata,created_by
  ) values(
    p_tenant_id,v_load_id,'direct_supply_prepared',
    'Direct Supply prepared with controlled transit stock',
    jsonb_build_object(
      'operating_location_id',p_operating_location_id,
      'transit_location_id',v_transit_id,
      'unit_code',v_unit
    ),auth.uid()
  );

  return v_result||jsonb_build_object(
    'operating_location_id',p_operating_location_id,
    'transit_location_id',v_transit_id,
    'commercial_state','awaiting_purchase'
  );
end
$function$;

create or replace function public.aggregate_direct_list_v621(
  p_tenant_id uuid,
  p_operating_location_id uuid default null::uuid,
  p_query text default null::text,
  p_limit integer default 300
)
returns setof jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
begin
  perform private.aggregate_direct_assert_view_v621(p_tenant_id);
  return query
  select jsonb_build_object(
    'load_id',l.id,'load_number',l.load_number,'load_date',l.load_date,'status',l.status,
    'operating_location_id',m.operating_location_id,
    'operating_location_code',ol.location_code,'operating_location_name',ol.name,
    'transit_location_id',m.transit_location_id,'transit_location_code',tl.location_code,
    'variant_id',l.variant_id,'product_name',l.product_name_snapshot,
    'quantity',l.quantity,'unit_code',l.unit_code,'measurement_method',l.measurement_method,
    'vehicle_id',l.vehicle_id,'vehicle_registration',l.vehicle_registration_snapshot,
    'driver_name',l.driver_name_snapshot,
    'supplier_id',l.supplier_id,'supplier_name',sp.name,
    'customer_id',l.customer_id,'customer_name',c.name,
    'source_name',l.source_name,'destination_name',l.destination_name,
    'source_reference',l.source_reference,
    'purchase_id',l.purchase_id,'purchase_number',p.purchase_number,
    'sale_id',l.sale_id,'sale_number',s.sale_number,
    'freight_mode',l.freight_mode,'freight_amount',l.freight_amount,
    'commercial_state',case
      when l.purchase_id is null then 'awaiting_purchase'
      when l.sale_id is null then 'ready_for_sale'
      else 'commercial_complete'
    end,
    'transit_stock_balance',coalesce(b.quantity,0),'created_at',l.created_at
  )
  from public.aggregate_loads_v617 l
  join public.aggregate_direct_transit_locations_v621 m
    on m.tenant_id=l.tenant_id and m.transit_location_id=l.location_id
  join public.business_locations ol
    on ol.id=m.operating_location_id and ol.tenant_id=m.tenant_id
  join public.business_locations tl
    on tl.id=m.transit_location_id and tl.tenant_id=m.tenant_id
  left join public.suppliers sp on sp.id=l.supplier_id and sp.tenant_id=l.tenant_id
  left join public.customers c on c.id=l.customer_id and c.tenant_id=l.tenant_id
  left join public.purchases p on p.id=l.purchase_id and p.tenant_id=l.tenant_id
  left join public.sales s on s.id=l.sale_id and s.tenant_id=l.tenant_id
  left join public.location_stock_balances b
    on b.tenant_id=l.tenant_id and b.location_id=l.location_id and b.variant_id=l.variant_id
  where l.tenant_id=p_tenant_id
    and l.direction='direct_delivery'
    and (p_operating_location_id is null or m.operating_location_id=p_operating_location_id)
    and private.erp_document_scope_allowed(
      p_tenant_id,m.operating_location_id,p_operating_location_id,'view'
    )
    and (
      p_query is null or trim(p_query)=''
      or l.load_number ilike '%'||trim(p_query)||'%'
      or l.product_name_snapshot ilike '%'||trim(p_query)||'%'
      or coalesce(l.vehicle_registration_snapshot,'') ilike '%'||trim(p_query)||'%'
      or coalesce(sp.name,'') ilike '%'||trim(p_query)||'%'
      or coalesce(c.name,'') ilike '%'||trim(p_query)||'%'
      or coalesce(p.purchase_number,'') ilike '%'||trim(p_query)||'%'
      or coalesce(s.sale_number,'') ilike '%'||trim(p_query)||'%'
    )
  order by l.created_at desc
  limit greatest(1,least(coalesce(p_limit,300),1000));
end
$function$;

create or replace function public.aggregate_direct_link_document_v621(
  p_tenant_id uuid,
  p_load_id uuid,
  p_document_type text,
  p_document_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_type text:=lower(trim(coalesce(p_document_type,'')));
  v_load public.aggregate_loads_v617%rowtype;
  v_map public.aggregate_direct_transit_locations_v621%rowtype;
  v_ref text;
  v_document_qty numeric:=0;
  v_allocated_qty numeric:=0;
  v_party uuid;
begin
  perform private.aggregate_direct_assert_manage_v621(p_tenant_id);

  select * into v_load
  from public.aggregate_loads_v617
  where id=p_load_id and tenant_id=p_tenant_id
  for update;

  if v_load.id is null then raise exception 'Direct Supply load not found'; end if;
  if v_load.direction<>'direct_delivery' then raise exception 'Only Direct Supply loads can use this document link'; end if;
  if v_load.status='cancelled' then raise exception 'Cancelled Direct Supply load cannot be linked'; end if;

  select * into v_map
  from public.aggregate_direct_transit_locations_v621 m
  where m.tenant_id=p_tenant_id and m.transit_location_id=v_load.location_id;

  if v_map.transit_location_id is null then
    raise exception 'Direct Supply load is not using controlled transit stock';
  end if;

  perform private.v4_location_access(p_tenant_id,v_map.operating_location_id,'operate');

  if not exists(
    select 1 from public.document_origins d
    where d.tenant_id=p_tenant_id
      and d.entity_type=v_type
      and d.entity_id=p_document_id
      and d.location_id=v_map.transit_location_id
  ) then
    raise exception 'The % must be posted to the Direct Supply transit location',initcap(v_type);
  end if;

  if v_type='purchase' then
    if v_load.purchase_id is not null and v_load.purchase_id<>p_document_id then
      raise exception 'Load is already linked to another Purchase';
    end if;

    select p.purchase_number,p.supplier_id into v_ref,v_party
    from public.purchases p
    where p.id=p_document_id and p.tenant_id=p_tenant_id and p.status='posted'
    for update;
    if v_ref is null then raise exception 'Posted Purchase not found'; end if;
    if v_party is distinct from v_load.supplier_id then
      raise exception 'Purchase supplier does not match the Direct Supply load';
    end if;

    select coalesce(sum(case
      when upper(coalesce(pi.entered_unit_code,pi.unit_code,''))=upper(v_load.unit_code)
      then coalesce(pi.entered_quantity,pi.quantity) else 0 end),0)
    into v_document_qty
    from public.purchase_items pi
    where pi.tenant_id=p_tenant_id
      and pi.purchase_id=p_document_id
      and pi.variant_id=v_load.variant_id;

    select coalesce(sum(x.quantity),0) into v_allocated_qty
    from public.aggregate_loads_v617 x
    where x.tenant_id=p_tenant_id
      and x.id<>p_load_id
      and x.direction='direct_delivery'
      and x.purchase_id=p_document_id
      and x.variant_id=v_load.variant_id
      and upper(x.unit_code)=upper(v_load.unit_code)
      and x.status<>'cancelled';

    if v_document_qty<=0 or v_allocated_qty+v_load.quantity>v_document_qty+0.0001 then
      raise exception 'Purchase quantity is insufficient for this Direct Supply allocation';
    end if;

    update public.aggregate_loads_v617
    set purchase_id=p_document_id,updated_by=auth.uid(),updated_at=now()
    where id=p_load_id and tenant_id=p_tenant_id;

  elsif v_type='sale' then
    if v_load.purchase_id is null then
      raise exception 'Post and link the Direct Supply Purchase before posting the Sale';
    end if;
    if v_load.sale_id is not null and v_load.sale_id<>p_document_id then
      raise exception 'Load is already linked to another Sale';
    end if;

    select s.sale_number,s.customer_id into v_ref,v_party
    from public.sales s
    where s.id=p_document_id and s.tenant_id=p_tenant_id and s.status='posted'
    for update;
    if v_ref is null then raise exception 'Posted Sale not found'; end if;
    if v_party is distinct from v_load.customer_id then
      raise exception 'Sale customer does not match the Direct Supply load';
    end if;

    select coalesce(sum(case
      when upper(coalesce(si.entered_unit_code,si.unit_code,''))=upper(v_load.unit_code)
      then coalesce(si.entered_quantity,si.quantity) else 0 end),0)
    into v_document_qty
    from public.sale_items si
    where si.tenant_id=p_tenant_id
      and si.sale_id=p_document_id
      and si.variant_id=v_load.variant_id;

    select coalesce(sum(x.quantity),0) into v_allocated_qty
    from public.aggregate_loads_v617 x
    where x.tenant_id=p_tenant_id
      and x.id<>p_load_id
      and x.direction='direct_delivery'
      and x.sale_id=p_document_id
      and x.variant_id=v_load.variant_id
      and upper(x.unit_code)=upper(v_load.unit_code)
      and x.status<>'cancelled';

    if v_document_qty<=0 or v_allocated_qty+v_load.quantity>v_document_qty+0.0001 then
      raise exception 'Sale quantity is insufficient for this Direct Supply allocation';
    end if;

    update public.aggregate_loads_v617
    set sale_id=p_document_id,updated_by=auth.uid(),updated_at=now()
    where id=p_load_id and tenant_id=p_tenant_id;
  else
    raise exception 'Document type must be purchase or sale';
  end if;

  insert into public.aggregate_load_events_v617(
    tenant_id,load_id,event_type,note,metadata,created_by
  ) values(
    p_tenant_id,p_load_id,'direct_document_linked',
    initcap(v_type)||' '||v_ref||' linked to Direct Supply',
    jsonb_build_object(
      'document_type',v_type,'document_id',p_document_id,'reference',v_ref,
      'validated_quantity',v_document_qty,'allocated_before',v_allocated_qty,
      'load_quantity',v_load.quantity,'unit_code',v_load.unit_code,
      'transit_location_id',v_map.transit_location_id,
      'operating_location_id',v_map.operating_location_id
    ),auth.uid()
  );

  return jsonb_build_object(
    'load_id',p_load_id,'load_number',v_load.load_number,
    'document_type',v_type,'document_id',p_document_id,'reference',v_ref,
    'operating_location_id',v_map.operating_location_id,
    'transit_location_id',v_map.transit_location_id,
    'commercial_state',case when v_type='sale' then 'commercial_complete' else 'ready_for_sale' end
  );
end
$function$;

create or replace function public.aggregate_direct_document_candidates_v621(
  p_tenant_id uuid,
  p_load_id uuid,
  p_document_type text,
  p_limit integer default 50
)
returns setof jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_type text:=lower(trim(coalesce(p_document_type,'')));
  v_load public.aggregate_loads_v617%rowtype;
  v_map public.aggregate_direct_transit_locations_v621%rowtype;
begin
  perform private.aggregate_direct_assert_manage_v621(p_tenant_id);
  select * into v_load from public.aggregate_loads_v617
  where id=p_load_id and tenant_id=p_tenant_id;

  if v_load.id is null or v_load.direction<>'direct_delivery' or v_load.status='cancelled' then
    raise exception 'Active Direct Supply load not found';
  end if;

  select * into v_map
  from public.aggregate_direct_transit_locations_v621 m
  where m.tenant_id=p_tenant_id and m.transit_location_id=v_load.location_id;
  if v_map.transit_location_id is null then raise exception 'Controlled transit mapping not found'; end if;

  perform private.v4_location_access(p_tenant_id,v_map.operating_location_id,'operate');

  if v_type='purchase' then
    return query
    with docs as (
      select p.id document_id,p.purchase_number document_number,p.purchase_date document_date,
             sp.name party_name,
             sum(case when upper(coalesce(pi.entered_unit_code,pi.unit_code,''))=upper(v_load.unit_code)
                      then coalesce(pi.entered_quantity,pi.quantity) else 0 end)::numeric document_qty,
             p.created_at
      from public.purchases p
      join public.document_origins d
        on d.tenant_id=p.tenant_id and d.entity_type='purchase'
       and d.entity_id=p.id and d.location_id=v_map.transit_location_id
      join public.purchase_items pi
        on pi.tenant_id=p.tenant_id and pi.purchase_id=p.id and pi.variant_id=v_load.variant_id
      join public.suppliers sp on sp.id=p.supplier_id and sp.tenant_id=p.tenant_id
      where p.tenant_id=p_tenant_id and p.status='posted' and p.supplier_id=v_load.supplier_id
      group by p.id,p.purchase_number,p.purchase_date,sp.name,p.created_at
    ), allocations as (
      select x.purchase_id document_id,sum(x.quantity)::numeric allocated_qty
      from public.aggregate_loads_v617 x
      where x.tenant_id=p_tenant_id and x.id<>p_load_id
        and x.direction='direct_delivery' and x.purchase_id is not null
        and x.variant_id=v_load.variant_id and upper(x.unit_code)=upper(v_load.unit_code)
        and x.status<>'cancelled'
      group by x.purchase_id
    )
    select jsonb_build_object(
      'document_type','purchase','document_id',d.document_id,
      'document_number',d.document_number,'document_date',d.document_date,
      'party_name',d.party_name,'document_quantity',d.document_qty,
      'allocated_quantity',coalesce(a.allocated_qty,0),
      'remaining_quantity',greatest(d.document_qty-coalesce(a.allocated_qty,0),0),
      'unit_code',v_load.unit_code,'already_linked',v_load.purchase_id=d.document_id,
      'created_at',d.created_at
    )
    from docs d left join allocations a on a.document_id=d.document_id
    where d.document_qty>0
      and (v_load.purchase_id=d.document_id
           or d.document_qty-coalesce(a.allocated_qty,0)>=v_load.quantity-0.0001)
    order by (v_load.purchase_id=d.document_id) desc,d.created_at desc
    limit greatest(1,least(coalesce(p_limit,50),200));

  elsif v_type='sale' then
    if v_load.purchase_id is null then raise exception 'Link the Direct Supply Purchase first'; end if;

    return query
    with docs as (
      select s.id document_id,s.sale_number document_number,s.sale_date document_date,
             c.name party_name,
             sum(case when upper(coalesce(si.entered_unit_code,si.unit_code,''))=upper(v_load.unit_code)
                      then coalesce(si.entered_quantity,si.quantity) else 0 end)::numeric document_qty,
             s.created_at
      from public.sales s
      join public.document_origins d
        on d.tenant_id=s.tenant_id and d.entity_type='sale'
       and d.entity_id=s.id and d.location_id=v_map.transit_location_id
      join public.sale_items si
        on si.tenant_id=s.tenant_id and si.sale_id=s.id and si.variant_id=v_load.variant_id
      join public.customers c on c.id=s.customer_id and c.tenant_id=s.tenant_id
      where s.tenant_id=p_tenant_id and s.status='posted' and s.customer_id=v_load.customer_id
      group by s.id,s.sale_number,s.sale_date,c.name,s.created_at
    ), allocations as (
      select x.sale_id document_id,sum(x.quantity)::numeric allocated_qty
      from public.aggregate_loads_v617 x
      where x.tenant_id=p_tenant_id and x.id<>p_load_id
        and x.direction='direct_delivery' and x.sale_id is not null
        and x.variant_id=v_load.variant_id and upper(x.unit_code)=upper(v_load.unit_code)
        and x.status<>'cancelled'
      group by x.sale_id
    )
    select jsonb_build_object(
      'document_type','sale','document_id',d.document_id,
      'document_number',d.document_number,'document_date',d.document_date,
      'party_name',d.party_name,'document_quantity',d.document_qty,
      'allocated_quantity',coalesce(a.allocated_qty,0),
      'remaining_quantity',greatest(d.document_qty-coalesce(a.allocated_qty,0),0),
      'unit_code',v_load.unit_code,'already_linked',v_load.sale_id=d.document_id,
      'created_at',d.created_at
    )
    from docs d left join allocations a on a.document_id=d.document_id
    where d.document_qty>0
      and (v_load.sale_id=d.document_id
           or d.document_qty-coalesce(a.allocated_qty,0)>=v_load.quantity-0.0001)
    order by (v_load.sale_id=d.document_id) desc,d.created_at desc
    limit greatest(1,least(coalesce(p_limit,50),200));
  else
    raise exception 'Document type must be purchase or sale';
  end if;
end
$function$;

create or replace function public.aggregate_yard_dashboard_v621(
  p_tenant_id uuid,
  p_location_id uuid default null::uuid,
  p_day date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_base jsonb;
  v_stock_on_hand_cft numeric:=0;
  v_stock_available_cft numeric:=0;
  v_stock_by_material jsonb:='[]'::jsonb;
begin
  v_base:=public.aggregate_yard_dashboard_v617(p_tenant_id,p_location_id,p_day);

  if p_location_id is not null and exists(
    select 1 from public.aggregate_direct_transit_locations_v621 m
    where m.tenant_id=p_tenant_id and m.transit_location_id=p_location_id
  ) then raise exception 'Direct Supply transit is not a physical yard location'; end if;

  select
    coalesce(sum(case when upper(coalesce(u.code,''))='CFT' then b.quantity else 0 end),0),
    coalesce(sum(case when upper(coalesce(u.code,''))='CFT'
      then greatest(b.quantity-coalesce(b.reserved_quantity,0)-coalesce(b.damaged_quantity,0)-coalesce(b.quarantine_quantity,0),0)
      else 0 end),0)
  into v_stock_on_hand_cft,v_stock_available_cft
  from public.location_stock_balances b
  join public.product_variants pv on pv.id=b.variant_id and pv.tenant_id=b.tenant_id and pv.status='active'
  join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id and p.status='active'
  left join public.inventory_units_v481 u on u.id=p.base_unit_id and u.tenant_id=p.tenant_id
  where b.tenant_id=p_tenant_id
    and (p_location_id is null or b.location_id=p_location_id)
    and not exists(
      select 1 from public.aggregate_direct_transit_locations_v621 m
      where m.tenant_id=b.tenant_id and m.transit_location_id=b.location_id
    )
    and private.erp_document_scope_allowed(p_tenant_id,b.location_id,p_location_id,'view');

  select coalesce(jsonb_agg(to_jsonb(q) order by q.product_name,q.variant_name),'[]'::jsonb)
  into v_stock_by_material
  from (
    select pv.id variant_id,p.name product_name,pv.name variant_name,coalesce(u.code,'') unit_code,
      round(sum(b.quantity),3) on_hand,
      round(sum(greatest(b.quantity-coalesce(b.reserved_quantity,0)-coalesce(b.damaged_quantity,0)-coalesce(b.quarantine_quantity,0),0)),3) available,
      round(sum(coalesce(b.reserved_quantity,0)),3) reserved
    from public.location_stock_balances b
    join public.product_variants pv on pv.id=b.variant_id and pv.tenant_id=b.tenant_id and pv.status='active'
    join public.products p on p.id=pv.product_id and p.tenant_id=pv.tenant_id and p.status='active'
    left join public.inventory_units_v481 u on u.id=p.base_unit_id and u.tenant_id=p.tenant_id
    where b.tenant_id=p_tenant_id
      and p.item_type='stock'
      and (p_location_id is null or b.location_id=p_location_id)
      and not exists(
        select 1 from public.aggregate_direct_transit_locations_v621 m
        where m.tenant_id=b.tenant_id and m.transit_location_id=b.location_id
      )
      and private.erp_document_scope_allowed(p_tenant_id,b.location_id,p_location_id,'view')
    group by pv.id,p.name,pv.name,u.code
    having sum(b.quantity)<>0
    order by p.name,pv.name
    limit 200
  ) q;

  return v_base||jsonb_build_object(
    'stock_on_hand_cft',round(v_stock_on_hand_cft,3),
    'stock_available_cft',round(v_stock_available_cft,3),
    'stock_by_material',coalesce(v_stock_by_material,'[]'::jsonb),
    'physical_yard_stock_only',true
  );
end
$function$;

drop policy if exists aggregate_direct_transit_locations_v621_read
  on public.aggregate_direct_transit_locations_v621;
create policy aggregate_direct_transit_locations_v621_read
on public.aggregate_direct_transit_locations_v621
for select
to authenticated
using (
  private.erp_user_has_tenant_access(tenant_id)
  and exists(
    select 1 from public.tenant_modules tm
    where tm.tenant_id=aggregate_direct_transit_locations_v621.tenant_id
      and tm.module_key='aggregate_yard' and tm.enabled
  )
  and private.erp_document_scope_allowed(tenant_id,operating_location_id,null::uuid,'view')
  and (
    private.erp_has_permission(tenant_id,'aggregate_yard.direct.view')
    or private.erp_has_permission(tenant_id,'aggregate_yard.direct.manage')
    or private.erp_user_is_owner(tenant_id)
  )
);

revoke all on function private.aggregate_direct_user_has_permission_v621(uuid,text,uuid) from public,anon,authenticated;
revoke all on function private.aggregate_direct_assert_view_v621(uuid) from public,anon,authenticated;
revoke all on function private.aggregate_direct_assert_manage_v621(uuid) from public,anon,authenticated;
revoke all on function private.aggregate_direct_ensure_transit_v621(uuid,uuid) from public,anon,authenticated;

do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure::text as sig
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in(
      'aggregate_direct_prepare_v621','aggregate_direct_materials_v621',
      'aggregate_direct_load_create_v621','aggregate_direct_list_v621',
      'aggregate_direct_link_document_v621','aggregate_direct_document_candidates_v621',
      'aggregate_yard_dashboard_v621'
    )
  loop
    execute 'revoke all on function '||r.sig||' from public,anon';
    execute 'grant execute on function '||r.sig||' to authenticated,service_role';
  end loop;
end$$;

insert into public.thq_schema_releases(migration_no,schema_version,release_name,notes)
values(
  311,'6.2.1-aggregate-direct-supply','Aggregate Direct Supply Transit Foundation',
  'Adds tenant-gated quarry-to-customer Direct Supply using lazily created system transit locations per operating location. Purchase must post to transit before Sale; Sale stock cannot go negative. Direct document linking validates transit origin, party, material, unit and allocated quantity. Normal yard Sales/Purchases remain unchanged.'
)
on conflict(migration_no) do update
set schema_version=excluded.schema_version,release_name=excluded.release_name,notes=excluded.notes;

commit;
