
create or replace function private.aggregate_direct_user_has_permission_v621(
  p_tenant_id uuid,
  p_permission_key text,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=public,private,pg_temp
as $$
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
$$;

revoke all
on function private.aggregate_direct_user_has_permission_v621(uuid,text,uuid)
from public,anon,authenticated;

create or replace function private.erp_user_location_allowed(
  p_tenant_id uuid,
  p_location_id uuid,
  p_required text default 'view',
  p_user_id uuid default auth.uid()
)
returns boolean
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_level text;
  v_rank int;
  v_required int;
  v_operating_location_id uuid;
  v_required_norm text:=lower(coalesce(p_required,'view'));
begin
  if p_user_id is null then
    return false;
  end if;

  select m.operating_location_id
  into v_operating_location_id
  from public.aggregate_direct_transit_locations_v621 m
  where m.tenant_id=p_tenant_id
    and m.transit_location_id=p_location_id;

  if v_operating_location_id is not null then
    if not exists(
      select 1
      from public.tenant_modules tm
      where tm.tenant_id=p_tenant_id
        and tm.module_key='aggregate_yard'
        and tm.enabled
    ) then
      return false;
    end if;

    if private.erp_user_is_owner(p_tenant_id,p_user_id) then
      return true;
    end if;

    if v_required_norm in('operate','manage') then
      if not private.aggregate_direct_user_has_permission_v621(
        p_tenant_id,'aggregate_yard.direct.manage',p_user_id
      ) then
        return false;
      end if;
    else
      if not (
        private.aggregate_direct_user_has_permission_v621(
          p_tenant_id,'aggregate_yard.direct.view',p_user_id
        )
        or private.aggregate_direct_user_has_permission_v621(
          p_tenant_id,'aggregate_yard.direct.manage',p_user_id
        )
      ) then
        return false;
      end if;
    end if;

    if private.aggregate_direct_user_has_permission_v621(
      p_tenant_id,'locations.manage_all',p_user_id
    ) then
      return true;
    end if;

    if v_required_norm='view'
       and private.aggregate_direct_user_has_permission_v621(
         p_tenant_id,'locations.view_all',p_user_id
       ) then
      return true;
    end if;

    p_location_id:=v_operating_location_id;
  end if;

  if private.erp_user_is_owner(p_tenant_id,p_user_id) then
    return true;
  end if;

  select access_level
  into v_level
  from public.business_user_location_access
  where tenant_id=p_tenant_id
    and user_id=p_user_id
    and location_id=p_location_id;

  if v_level is null then
    return false;
  end if;

  v_rank:=case v_level
    when 'manage' then 3
    when 'operate' then 2
    else 1
  end;

  v_required:=case v_required_norm
    when 'manage' then 3
    when 'operate' then 2
    else 1
  end;

  return v_rank>=v_required;
end
$$;

revoke all
on function private.erp_user_location_allowed(uuid,uuid,text,uuid)
from public,anon,authenticated;

drop policy if exists aggregate_direct_transit_locations_v621_read
on public.aggregate_direct_transit_locations_v621;

create policy aggregate_direct_transit_locations_v621_read
on public.aggregate_direct_transit_locations_v621
for select to authenticated
using(
  private.erp_user_has_tenant_access(tenant_id)
  and exists(
    select 1
    from public.tenant_modules tm
    where tm.tenant_id=aggregate_direct_transit_locations_v621.tenant_id
      and tm.module_key='aggregate_yard'
      and tm.enabled
  )
  and private.erp_document_scope_allowed(
    tenant_id,
    operating_location_id,
    null,
    'view'
  )
  and (
    private.erp_has_permission(tenant_id,'aggregate_yard.direct.view')
    or private.erp_has_permission(tenant_id,'aggregate_yard.direct.manage')
    or private.erp_user_is_owner(tenant_id)
  )
);

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
    and private.erp_document_scope_allowed(
      p_tenant_id,
      m.operating_location_id,
      p_operating_location_id,
      'view'
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

create or replace function public.aggregate_yard_dashboard_v621(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_day date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,private,pg_temp
as $$
declare
  v_base jsonb;
  v_stock_on_hand_cft numeric:=0;
  v_stock_available_cft numeric:=0;
  v_stock_by_material jsonb:='[]'::jsonb;
begin
  v_base:=public.aggregate_yard_dashboard_v617(
    p_tenant_id,p_location_id,p_day
  );

  if p_location_id is not null
     and exists(
       select 1
       from public.aggregate_direct_transit_locations_v621 m
       where m.tenant_id=p_tenant_id
         and m.transit_location_id=p_location_id
     ) then
    raise exception 'Direct Supply transit is not a physical yard location';
  end if;

  select
    coalesce(sum(
      case
        when upper(coalesce(u.code,''))='CFT'
        then b.quantity
        else 0
      end
    ),0),
    coalesce(sum(
      case
        when upper(coalesce(u.code,''))='CFT'
        then greatest(
          b.quantity
          -coalesce(b.reserved_quantity,0)
          -coalesce(b.damaged_quantity,0)
          -coalesce(b.quarantine_quantity,0),
          0
        )
        else 0
      end
    ),0)
  into v_stock_on_hand_cft,v_stock_available_cft
  from public.location_stock_balances b
  join public.product_variants pv
    on pv.id=b.variant_id
   and pv.tenant_id=b.tenant_id
   and pv.status='active'
  join public.products p
    on p.id=pv.product_id
   and p.tenant_id=pv.tenant_id
   and p.status='active'
  left join public.inventory_units_v481 u
    on u.id=p.base_unit_id
   and u.tenant_id=p.tenant_id
  where b.tenant_id=p_tenant_id
    and (p_location_id is null or b.location_id=p_location_id)
    and not exists(
      select 1
      from public.aggregate_direct_transit_locations_v621 m
      where m.tenant_id=b.tenant_id
        and m.transit_location_id=b.location_id
    )
    and private.erp_document_scope_allowed(
      p_tenant_id,b.location_id,p_location_id,'view'
    );

  select coalesce(
    jsonb_agg(to_jsonb(q) order by q.product_name,q.variant_name),
    '[]'::jsonb
  )
  into v_stock_by_material
  from (
    select
      pv.id as variant_id,
      p.name as product_name,
      pv.name as variant_name,
      coalesce(u.code,'') as unit_code,
      round(sum(b.quantity),3) as on_hand,
      round(sum(greatest(
        b.quantity
        -coalesce(b.reserved_quantity,0)
        -coalesce(b.damaged_quantity,0)
        -coalesce(b.quarantine_quantity,0),
        0
      )),3) as available,
      round(sum(coalesce(b.reserved_quantity,0)),3) as reserved
    from public.location_stock_balances b
    join public.product_variants pv
      on pv.id=b.variant_id
     and pv.tenant_id=b.tenant_id
     and pv.status='active'
    join public.products p
      on p.id=pv.product_id
     and p.tenant_id=pv.tenant_id
     and p.status='active'
    left join public.inventory_units_v481 u
      on u.id=p.base_unit_id
     and u.tenant_id=p.tenant_id
    where b.tenant_id=p_tenant_id
      and p.item_type='stock'
      and (p_location_id is null or b.location_id=p_location_id)
      and not exists(
        select 1
        from public.aggregate_direct_transit_locations_v621 m
        where m.tenant_id=b.tenant_id
          and m.transit_location_id=b.location_id
      )
      and private.erp_document_scope_allowed(
        p_tenant_id,b.location_id,p_location_id,'view'
      )
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
$$;

revoke all
on function public.aggregate_yard_dashboard_v621(uuid,uuid,date)
from public,anon;

grant execute
on function public.aggregate_yard_dashboard_v621(uuid,uuid,date)
to authenticated,service_role;

insert into public.thq_schema_releases(
  migration_no,
  schema_version,
  release_name,
  notes
)
values(
  313,
  '6.2.1-aggregate-direct-hardening',
  'Aggregate Direct Supply Pre-Activation Hardening',
  'Fixes explicit-user permission resolution for hidden transit access, scopes Direct Supply reads to authorized operating locations, assigns only the selected material to transit for first-use Purchase/Sale screens, and adds a Material Yard dashboard that excludes system transit stock from physical yard balances.'
);;
