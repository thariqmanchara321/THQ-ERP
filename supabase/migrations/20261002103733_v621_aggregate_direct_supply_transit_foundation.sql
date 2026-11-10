
insert into public.permissions(key,name,module_key,description)
values
 ('aggregate_yard.direct.view','View Direct Supply','aggregate_yard','View quarry-to-customer direct supply loads and transit status'),
 ('aggregate_yard.direct.manage','Manage Direct Supply','aggregate_yard','Create and commercially link quarry-to-customer direct supply loads through controlled transit stock')
on conflict(key) do update
set name=excluded.name,module_key=excluded.module_key,description=excluded.description;

create table if not exists public.aggregate_direct_transit_locations_v621(
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operating_location_id uuid not null references public.business_locations(id) on delete restrict,
  transit_location_id uuid not null references public.business_locations(id) on delete restrict,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  primary key(tenant_id,operating_location_id),
  unique(transit_location_id)
);

create index if not exists aggregate_direct_transit_locations_v621_transit_idx
on public.aggregate_direct_transit_locations_v621(tenant_id,transit_location_id);

alter table public.aggregate_direct_transit_locations_v621 enable row level security;

drop policy if exists aggregate_direct_transit_locations_v621_read
on public.aggregate_direct_transit_locations_v621;

create policy aggregate_direct_transit_locations_v621_read
on public.aggregate_direct_transit_locations_v621
for select to authenticated
using(
  private.erp_user_has_tenant_access(tenant_id)
  and exists(
    select 1 from public.tenant_modules tm
    where tm.tenant_id=aggregate_direct_transit_locations_v621.tenant_id
      and tm.module_key='aggregate_yard'
      and tm.enabled
  )
  and (
    private.erp_has_permission(tenant_id,'aggregate_yard.direct.view')
    or private.erp_has_permission(tenant_id,'aggregate_yard.direct.manage')
    or private.erp_has_permission(tenant_id,'aggregate_yard.manage')
  )
);

revoke all on public.aggregate_direct_transit_locations_v621
from public,anon,authenticated;
grant select on public.aggregate_direct_transit_locations_v621
to authenticated,service_role;

create or replace function private.aggregate_direct_assert_view_v621(
  p_tenant_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
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
    raise exception 'Material Yard module is not enabled'
      using errcode='42501';
  end if;

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'aggregate_yard.direct.view')
    or private.erp_has_permission(p_tenant_id,'aggregate_yard.direct.manage')
    or private.erp_has_permission(p_tenant_id,'aggregate_yard.manage')
  ) then
    raise exception 'Direct Supply view permission required'
      using errcode='42501';
  end if;
end
$$;

revoke all
on function private.aggregate_direct_assert_view_v621(uuid)
from public,anon,authenticated;

create or replace function private.aggregate_direct_assert_manage_v621(
  p_tenant_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
begin
  perform private.aggregate_direct_assert_view_v621(p_tenant_id);

  if not (
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'aggregate_yard.direct.manage')
    or private.erp_has_permission(p_tenant_id,'aggregate_yard.manage')
  ) then
    raise exception 'Direct Supply manage permission required'
      using errcode='42501';
  end if;
end
$$;

revoke all
on function private.aggregate_direct_assert_manage_v621(uuid)
from public,anon,authenticated;

create or replace function private.aggregate_direct_ensure_transit_v621(
  p_tenant_id uuid,
  p_operating_location_id uuid
)
returns uuid
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_existing uuid;
  v_source public.business_locations%rowtype;
  v_transit_id uuid;
  v_suffix text;
  v_code text;
  v_prefix text;
begin
  select m.transit_location_id
  into v_existing
  from public.aggregate_direct_transit_locations_v621 m
  join public.business_locations t
    on t.id=m.transit_location_id
   and t.tenant_id=m.tenant_id
   and t.active
  where m.tenant_id=p_tenant_id
    and m.operating_location_id=p_operating_location_id;

  if v_existing is not null then
    return v_existing;
  end if;

  select *
  into v_source
  from public.business_locations l
  where l.id=p_operating_location_id
    and l.tenant_id=p_tenant_id
    and l.active
  for update;

  if v_source.id is null then
    raise exception 'Operating location not found';
  end if;

  if exists(
    select 1
    from public.aggregate_direct_transit_locations_v621 m
    where m.tenant_id=p_tenant_id
      and m.transit_location_id=p_operating_location_id
  ) then
    raise exception 'A transit location cannot be used as the operating location';
  end if;

  v_suffix:=upper(substr(replace(p_operating_location_id::text,'-',''),1,8));
  v_code:='AGGDST-'||v_suffix;
  v_prefix:='DST'||substr(v_suffix,1,6);

  if exists(
    select 1
    from public.business_locations l
    where l.tenant_id=p_tenant_id
      and upper(l.location_code)=upper(v_code)
  ) then
    raise exception
      'Reserved Direct Supply transit code % is already in use',
      v_code;
  end if;

  insert into public.business_locations(
    tenant_id,
    parent_location_id,
    location_code,
    tracking_code,
    name,
    location_type,
    phone,
    email,
    gstin,
    address_line1,
    address_line2,
    city,
    state,
    postal_code,
    country,
    invoice_prefix,
    active,
    settings,
    hierarchy_role,
    sort_order
  )
  values(
    p_tenant_id,
    v_source.id,
    v_code,
    null,
    'Direct Supply Transit • '||v_source.name,
    'warehouse',
    v_source.phone,
    v_source.email,
    v_source.gstin,
    v_source.address_line1,
    v_source.address_line2,
    v_source.city,
    v_source.state,
    v_source.postal_code,
    v_source.country,
    v_prefix,
    true,
    jsonb_build_object(
      'aggregate_virtual_transit',true,
      'system_managed',true,
      'operating_location_id',v_source.id,
      'operating_location_code',v_source.location_code
    ),
    'operational',
    9999
  )
  returning id into v_transit_id;

  insert into public.aggregate_direct_transit_locations_v621(
    tenant_id,
    operating_location_id,
    transit_location_id,
    created_by
  )
  values(
    p_tenant_id,
    v_source.id,
    v_transit_id,
    auth.uid()
  );

  return v_transit_id;
end
$$;

revoke all
on function private.aggregate_direct_ensure_transit_v621(uuid,uuid)
from public,anon,authenticated;

create or replace function public.aggregate_direct_prepare_v621(
  p_tenant_id uuid,
  p_operating_location_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_transit_id uuid;
  v_transit public.business_locations%rowtype;
  v_operating public.business_locations%rowtype;
begin
  perform private.aggregate_direct_assert_manage_v621(p_tenant_id);
  perform private.v4_location_access(
    p_tenant_id,p_operating_location_id,'operate'
  );

  v_transit_id:=private.aggregate_direct_ensure_transit_v621(
    p_tenant_id,p_operating_location_id
  );

  select * into v_operating
  from public.business_locations
  where id=p_operating_location_id and tenant_id=p_tenant_id;

  select * into v_transit
  from public.business_locations
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
$$;

revoke all
on function public.aggregate_direct_prepare_v621(uuid,uuid)
from public,anon;
grant execute
on function public.aggregate_direct_prepare_v621(uuid,uuid)
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

  v_transit_id:=private.aggregate_direct_ensure_transit_v621(
    p_tenant_id,p_operating_location_id
  );

  v_result:=public.aggregate_load_create_v617(
    p_tenant_id,
    'direct_delivery',
    v_transit_id,
    p_variant_id,
    p_quantity,
    p_unit_code,
    p_measurement_method,
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
      'transit_location_id',v_transit_id
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

create or replace function public.aggregate_direct_link_document_v621(
  p_tenant_id uuid,
  p_load_id uuid,
  p_document_type text,
  p_document_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
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

  select *
  into v_load
  from public.aggregate_loads_v617
  where id=p_load_id
    and tenant_id=p_tenant_id
  for update;

  if v_load.id is null then
    raise exception 'Direct Supply load not found';
  end if;

  if v_load.direction<>'direct_delivery' then
    raise exception 'Only Direct Supply loads can use this document link';
  end if;

  if v_load.status='cancelled' then
    raise exception 'Cancelled Direct Supply load cannot be linked';
  end if;

  select *
  into v_map
  from public.aggregate_direct_transit_locations_v621 m
  where m.tenant_id=p_tenant_id
    and m.transit_location_id=v_load.location_id;

  if v_map.transit_location_id is null then
    raise exception 'Direct Supply load is not using controlled transit stock';
  end if;

  perform private.v4_location_access(
    p_tenant_id,v_map.operating_location_id,'operate'
  );

  if not exists(
    select 1
    from public.document_origins d
    where d.tenant_id=p_tenant_id
      and d.entity_type=v_type
      and d.entity_id=p_document_id
      and d.location_id=v_map.transit_location_id
  ) then
    raise exception
      'The % must be posted to the Direct Supply transit location',
      initcap(v_type);
  end if;

  if v_type='purchase' then
    if v_load.purchase_id is not null
       and v_load.purchase_id<>p_document_id then
      raise exception 'Load is already linked to another Purchase';
    end if;

    select p.purchase_number,p.supplier_id
    into v_ref,v_party
    from public.purchases p
    where p.id=p_document_id
      and p.tenant_id=p_tenant_id
      and p.status='posted'
    for update;

    if v_ref is null then
      raise exception 'Posted Purchase not found';
    end if;

    if v_party is distinct from v_load.supplier_id then
      raise exception 'Purchase supplier does not match the Direct Supply load';
    end if;

    select coalesce(sum(
      case
        when upper(coalesce(pi.entered_unit_code,pi.unit_code,''))
             =upper(v_load.unit_code)
        then coalesce(pi.entered_quantity,pi.quantity)
        else 0
      end
    ),0)
    into v_document_qty
    from public.purchase_items pi
    where pi.tenant_id=p_tenant_id
      and pi.purchase_id=p_document_id
      and pi.variant_id=v_load.variant_id;

    select coalesce(sum(x.quantity),0)
    into v_allocated_qty
    from public.aggregate_loads_v617 x
    where x.tenant_id=p_tenant_id
      and x.id<>p_load_id
      and x.direction='direct_delivery'
      and x.purchase_id=p_document_id
      and x.variant_id=v_load.variant_id
      and upper(x.unit_code)=upper(v_load.unit_code)
      and x.status<>'cancelled';

    if v_document_qty<=0
       or v_allocated_qty+v_load.quantity>v_document_qty+0.0001 then
      raise exception
        'Purchase quantity is insufficient for this Direct Supply allocation';
    end if;

    update public.aggregate_loads_v617
    set purchase_id=p_document_id,
        updated_by=auth.uid(),
        updated_at=now()
    where id=p_load_id and tenant_id=p_tenant_id;

  elsif v_type='sale' then
    if v_load.purchase_id is null then
      raise exception
        'Post and link the Direct Supply Purchase before posting the Sale';
    end if;

    if v_load.sale_id is not null
       and v_load.sale_id<>p_document_id then
      raise exception 'Load is already linked to another Sale';
    end if;

    select s.sale_number,s.customer_id
    into v_ref,v_party
    from public.sales s
    where s.id=p_document_id
      and s.tenant_id=p_tenant_id
      and s.status='posted'
    for update;

    if v_ref is null then
      raise exception 'Posted Sale not found';
    end if;

    if v_party is distinct from v_load.customer_id then
      raise exception 'Sale customer does not match the Direct Supply load';
    end if;

    select coalesce(sum(
      case
        when upper(coalesce(si.entered_unit_code,si.unit_code,''))
             =upper(v_load.unit_code)
        then coalesce(si.entered_quantity,si.quantity)
        else 0
      end
    ),0)
    into v_document_qty
    from public.sale_items si
    where si.tenant_id=p_tenant_id
      and si.sale_id=p_document_id
      and si.variant_id=v_load.variant_id;

    select coalesce(sum(x.quantity),0)
    into v_allocated_qty
    from public.aggregate_loads_v617 x
    where x.tenant_id=p_tenant_id
      and x.id<>p_load_id
      and x.direction='direct_delivery'
      and x.sale_id=p_document_id
      and x.variant_id=v_load.variant_id
      and upper(x.unit_code)=upper(v_load.unit_code)
      and x.status<>'cancelled';

    if v_document_qty<=0
       or v_allocated_qty+v_load.quantity>v_document_qty+0.0001 then
      raise exception
        'Sale quantity is insufficient for this Direct Supply allocation';
    end if;

    update public.aggregate_loads_v617
    set sale_id=p_document_id,
        updated_by=auth.uid(),
        updated_at=now()
    where id=p_load_id and tenant_id=p_tenant_id;

  else
    raise exception 'Document type must be purchase or sale';
  end if;

  insert into public.aggregate_load_events_v617(
    tenant_id,load_id,event_type,note,metadata,created_by
  )
  values(
    p_tenant_id,
    p_load_id,
    'direct_document_linked',
    initcap(v_type)||' '||v_ref||' linked to Direct Supply',
    jsonb_build_object(
      'document_type',v_type,
      'document_id',p_document_id,
      'reference',v_ref,
      'validated_quantity',v_document_qty,
      'allocated_before',v_allocated_qty,
      'load_quantity',v_load.quantity,
      'unit_code',v_load.unit_code,
      'transit_location_id',v_map.transit_location_id,
      'operating_location_id',v_map.operating_location_id
    ),
    auth.uid()
  );

  return jsonb_build_object(
    'load_id',p_load_id,
    'load_number',v_load.load_number,
    'document_type',v_type,
    'document_id',p_document_id,
    'reference',v_ref,
    'operating_location_id',v_map.operating_location_id,
    'transit_location_id',v_map.transit_location_id,
    'commercial_state',
      case
        when v_type='sale' then 'commercial_complete'
        else 'ready_for_sale'
      end
  );
end
$$;

revoke all
on function public.aggregate_direct_link_document_v621(
  uuid,uuid,text,uuid
)
from public,anon;
grant execute
on function public.aggregate_direct_link_document_v621(
  uuid,uuid,text,uuid
)
to authenticated,service_role;

create or replace function public.aggregate_direct_list_v621(
  p_tenant_id uuid,
  p_operating_location_id uuid default null,
  p_query text default null,
  p_limit integer default 300
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
    'load_id',l.id,
    'load_number',l.load_number,
    'load_date',l.load_date,
    'status',l.status,
    'operating_location_id',m.operating_location_id,
    'operating_location_code',ol.location_code,
    'operating_location_name',ol.name,
    'transit_location_id',m.transit_location_id,
    'transit_location_code',tl.location_code,
    'variant_id',l.variant_id,
    'product_name',l.product_name_snapshot,
    'quantity',l.quantity,
    'unit_code',l.unit_code,
    'measurement_method',l.measurement_method,
    'vehicle_id',l.vehicle_id,
    'vehicle_registration',l.vehicle_registration_snapshot,
    'driver_name',l.driver_name_snapshot,
    'supplier_id',l.supplier_id,
    'supplier_name',sp.name,
    'customer_id',l.customer_id,
    'customer_name',c.name,
    'source_name',l.source_name,
    'destination_name',l.destination_name,
    'source_reference',l.source_reference,
    'purchase_id',l.purchase_id,
    'purchase_number',p.purchase_number,
    'sale_id',l.sale_id,
    'sale_number',s.sale_number,
    'freight_mode',l.freight_mode,
    'freight_amount',l.freight_amount,
    'commercial_state',
      case
        when l.purchase_id is null then 'awaiting_purchase'
        when l.sale_id is null then 'ready_for_sale'
        else 'commercial_complete'
      end,
    'transit_stock_balance',coalesce(b.quantity,0),
    'created_at',l.created_at
  )
  from public.aggregate_loads_v617 l
  join public.aggregate_direct_transit_locations_v621 m
    on m.tenant_id=l.tenant_id
   and m.transit_location_id=l.location_id
  join public.business_locations ol
    on ol.id=m.operating_location_id
   and ol.tenant_id=m.tenant_id
  join public.business_locations tl
    on tl.id=m.transit_location_id
   and tl.tenant_id=m.tenant_id
  left join public.suppliers sp
    on sp.id=l.supplier_id and sp.tenant_id=l.tenant_id
  left join public.customers c
    on c.id=l.customer_id and c.tenant_id=l.tenant_id
  left join public.purchases p
    on p.id=l.purchase_id and p.tenant_id=l.tenant_id
  left join public.sales s
    on s.id=l.sale_id and s.tenant_id=l.tenant_id
  left join public.location_stock_balances b
    on b.tenant_id=l.tenant_id
   and b.location_id=l.location_id
   and b.variant_id=l.variant_id
  where l.tenant_id=p_tenant_id
    and l.direction='direct_delivery'
    and (
      p_operating_location_id is null
      or m.operating_location_id=p_operating_location_id
    )
    and (
      p_operating_location_id is null
      or private.erp_document_scope_allowed(
        p_tenant_id,m.operating_location_id,p_operating_location_id,'view'
      )
    )
    and (
      p_query is null
      or trim(p_query)=''
      or l.load_number ilike '%'||trim(p_query)||'%'
      or l.product_name_snapshot ilike '%'||trim(p_query)||'%'
      or coalesce(l.vehicle_registration_snapshot,'')
           ilike '%'||trim(p_query)||'%'
      or coalesce(sp.name,'') ilike '%'||trim(p_query)||'%'
      or coalesce(c.name,'') ilike '%'||trim(p_query)||'%'
      or coalesce(p.purchase_number,'') ilike '%'||trim(p_query)||'%'
      or coalesce(s.sale_number,'') ilike '%'||trim(p_query)||'%'
    )
  order by l.created_at desc
  limit greatest(1,least(coalesce(p_limit,300),1000));
end
$$;

revoke all
on function public.aggregate_direct_list_v621(
  uuid,uuid,text,integer
)
from public,anon;
grant execute
on function public.aggregate_direct_list_v621(
  uuid,uuid,text,integer
)
to authenticated,service_role;

create or replace function private.aggregate_yard_grant_default_permissions_v617(
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path=public,private,pg_temp
as $$
begin
  insert into public.role_permissions(role_id,permission_key)
  select r.id,p.key
  from public.roles r
  join public.permissions p on p.module_key='aggregate_yard'
  where r.tenant_id=p_tenant_id
    and (
      r.key='owner'
      or (
        r.key='manager'
        and p.key in(
          'aggregate_yard.view',
          'aggregate_yard.manage',
          'aggregate_yard.override_capacity',
          'aggregate_yard.orders.view',
          'aggregate_yard.orders.manage',
          'aggregate_yard.freight.view',
          'aggregate_yard.freight.manage',
          'aggregate_yard.direct.view',
          'aggregate_yard.direct.manage'
        )
      )
      or (
        r.key='store_keeper'
        and p.key in(
          'aggregate_yard.view',
          'aggregate_yard.manage',
          'aggregate_yard.orders.view',
          'aggregate_yard.orders.manage',
          'aggregate_yard.freight.view',
          'aggregate_yard.direct.view'
        )
      )
      or (
        r.key='salesperson'
        and p.key in(
          'aggregate_yard.view',
          'aggregate_yard.orders.view',
          'aggregate_yard.orders.manage',
          'aggregate_yard.direct.view'
        )
      )
      or (
        r.key='accountant'
        and p.key in(
          'aggregate_yard.view',
          'aggregate_yard.orders.view',
          'aggregate_yard.freight.view',
          'aggregate_yard.direct.view'
        )
      )
    )
  on conflict do nothing;
end
$$;

revoke all
on function private.aggregate_yard_grant_default_permissions_v617(uuid)
from public,anon,authenticated;

insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  311,
  '6.2.1-aggregate-direct-supply',
  'Aggregate Direct Supply Transit Foundation',
  'Adds tenant-gated quarry-to-customer Direct Supply using lazily created system transit locations per operating location. Purchase must post to transit before Sale; Sale stock cannot go negative. Direct document linking validates transit origin, party, material, unit and allocated quantity. Normal yard Sales/Purchases remain unchanged.'
);;
