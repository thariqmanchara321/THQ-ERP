-- THQ ERP — Aggregate Material Yard Dashboard
-- Schema release 307.
--
-- READ ONLY. No Sales/Purchase/GST/stock/accounting writer is modified.
--
-- Security:
-- * requires active tenant membership
-- * requires aggregate_yard enabled
-- * requires aggregate_yard.view/manage through the existing assertion helper
-- * respects location document scope
-- * finance is only returned to roles already allowed to see
--   Sales/Customers/Accounting data
-- * PUBLIC and anon EXECUTE are revoked

create or replace function public.aggregate_yard_dashboard_v617(
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
  v_day date:=coalesce(p_day,current_date);
  v_today_in_cft numeric:=0;
  v_today_out_cft numeric:=0;
  v_today_in_loads bigint:=0;
  v_today_out_loads bigint:=0;
  v_stock_on_hand_cft numeric:=0;
  v_stock_available_cft numeric:=0;
  v_trucks_on_road bigint:=0;
  v_active_trucks bigint:=0;
  v_pending_delivery_cft numeric:=0;
  v_pending_delivery_loads bigint:=0;
  v_receivables numeric:=0;
  v_receivables_visible boolean:=false;
  v_stock_by_material jsonb:='[]'::jsonb;
  v_active_loads jsonb:='[]'::jsonb;
  v_recent_loads jsonb:='[]'::jsonb;
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

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

  if p_location_id is not null
     and not private.erp_document_scope_allowed(
       p_tenant_id,p_location_id,p_location_id,'view'
     ) then
    raise exception 'Location view access required' using errcode='42501';
  end if;

  select
    coalesce(sum(l.quantity) filter(
      where l.direction='inbound'
        and upper(l.unit_code)='CFT'
        and l.status in('received','completed')
    ),0),
    count(*) filter(
      where l.direction='inbound'
        and l.status in('received','completed')
    ),
    coalesce(sum(l.quantity) filter(
      where l.direction='outbound'
        and upper(l.unit_code)='CFT'
        and l.status in(
          'dispatched','in_transit','arrived','delivered','completed'
        )
    ),0),
    count(*) filter(
      where l.direction='outbound'
        and l.status in(
          'dispatched','in_transit','arrived','delivered','completed'
        )
    ),
    count(distinct l.vehicle_id) filter(
      where l.vehicle_id is not null
        and l.status in('dispatched','in_transit')
    ),
    count(distinct l.vehicle_id) filter(
      where l.vehicle_id is not null
        and l.status in('loading','dispatched','in_transit','arrived')
    ),
    coalesce(sum(l.quantity) filter(
      where l.direction='outbound'
        and upper(l.unit_code)='CFT'
        and l.status in(
          'draft','loading','dispatched','in_transit','arrived'
        )
    ),0),
    count(*) filter(
      where l.direction='outbound'
        and l.status in(
          'draft','loading','dispatched','in_transit','arrived'
        )
    )
  into
    v_today_in_cft,v_today_in_loads,
    v_today_out_cft,v_today_out_loads,
    v_trucks_on_road,v_active_trucks,
    v_pending_delivery_cft,v_pending_delivery_loads
  from public.aggregate_loads_v617 l
  where l.tenant_id=p_tenant_id
    and l.load_date=v_day
    and l.status<>'cancelled'
    and (p_location_id is null or l.location_id=p_location_id)
    and (
      l.location_id is null
      or private.erp_document_scope_allowed(
        p_tenant_id,l.location_id,p_location_id,'view'
      )
    );

  select
    coalesce(sum(
      case when upper(coalesce(u.code,''))='CFT'
           then b.quantity else 0 end
    ),0),
    coalesce(sum(
      case when upper(coalesce(u.code,''))='CFT'
           then greatest(
             b.quantity
             - coalesce(b.reserved_quantity,0)
             - coalesce(b.damaged_quantity,0)
             - coalesce(b.quarantine_quantity,0),
             0
           )
           else 0 end
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
        - coalesce(b.reserved_quantity,0)
        - coalesce(b.damaged_quantity,0)
        - coalesce(b.quarantine_quantity,0),
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
      and private.erp_document_scope_allowed(
        p_tenant_id,b.location_id,p_location_id,'view'
      )
    group by pv.id,p.name,pv.name,u.code
    having sum(b.quantity)<>0
    order by p.name,pv.name
    limit 200
  ) q;

  select coalesce(
    jsonb_agg(to_jsonb(q) order by q.created_at desc),
    '[]'::jsonb
  )
  into v_active_loads
  from (
    select
      l.id as load_id,
      l.load_number,
      l.direction,
      l.status,
      l.product_name_snapshot as product_name,
      l.quantity,
      l.unit_code,
      l.vehicle_registration_snapshot as vehicle_registration,
      l.driver_name_snapshot as driver_name,
      coalesce(l.source_name,s.name,'') as source_name,
      coalesce(l.destination_name,c.name,'') as destination_name,
      l.purchase_id,
      l.sale_id,
      l.created_at
    from public.aggregate_loads_v617 l
    left join public.suppliers s
      on s.id=l.supplier_id
     and s.tenant_id=l.tenant_id
    left join public.customers c
      on c.id=l.customer_id
     and c.tenant_id=l.tenant_id
    where l.tenant_id=p_tenant_id
      and l.status in('loading','dispatched','in_transit','arrived')
      and (p_location_id is null or l.location_id=p_location_id)
      and (
        l.location_id is null
        or private.erp_document_scope_allowed(
          p_tenant_id,l.location_id,p_location_id,'view'
        )
      )
    order by l.created_at desc
    limit 10
  ) q;

  select coalesce(
    jsonb_agg(to_jsonb(q) order by q.created_at desc),
    '[]'::jsonb
  )
  into v_recent_loads
  from (
    select
      l.id as load_id,
      l.load_number,
      l.load_date,
      l.direction,
      l.status,
      l.product_name_snapshot as product_name,
      l.quantity,
      l.unit_code,
      l.vehicle_registration_snapshot as vehicle_registration,
      l.created_at
    from public.aggregate_loads_v617 l
    where l.tenant_id=p_tenant_id
      and (p_location_id is null or l.location_id=p_location_id)
      and (
        l.location_id is null
        or private.erp_document_scope_allowed(
          p_tenant_id,l.location_id,p_location_id,'view'
        )
      )
    order by l.created_at desc
    limit 8
  ) q;

  v_receivables_visible :=
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id,'accounting.view')
    or private.erp_has_permission(p_tenant_id,'sales.view')
    or private.erp_has_permission(p_tenant_id,'sales.manage')
    or private.erp_has_permission(p_tenant_id,'customers.view')
    or private.erp_has_permission(p_tenant_id,'customers.manage');

  if v_receivables_visible then
    select coalesce(sum(ci.total_outstanding),0)
    into v_receivables
    from public.customer_credit_intelligence_v480(
      p_tenant_id,p_location_id,'',5000
    ) ci;
  end if;

  return jsonb_build_object(
    'day',v_day,
    'today_in_cft',round(v_today_in_cft,3),
    'today_in_loads',v_today_in_loads,
    'today_out_cft',round(v_today_out_cft,3),
    'today_out_loads',v_today_out_loads,
    'stock_on_hand_cft',round(v_stock_on_hand_cft,3),
    'stock_available_cft',round(v_stock_available_cft,3),
    'trucks_on_road',v_trucks_on_road,
    'active_trucks',v_active_trucks,
    'pending_delivery_cft',round(v_pending_delivery_cft,3),
    'pending_delivery_loads',v_pending_delivery_loads,
    'receivables',case
      when v_receivables_visible then round(v_receivables,2)
      else null
    end,
    'receivables_visible',v_receivables_visible,
    'stock_by_material',coalesce(v_stock_by_material,'[]'::jsonb),
    'active_loads',coalesce(v_active_loads,'[]'::jsonb),
    'recent_loads',coalesce(v_recent_loads,'[]'::jsonb)
  );
end
$$;

revoke all
on function public.aggregate_yard_dashboard_v617(uuid,uuid,date)
from public,anon;

grant execute
on function public.aggregate_yard_dashboard_v617(uuid,uuid,date)
to authenticated,service_role;

insert into public.thq_schema_releases(
  migration_no,schema_version,release_name,notes
)
values(
  307,
  '6.1.7-aggregate-dashboard',
  'Aggregate Material Yard Dashboard',
  'Adds a read-only, tenant/module/permission-gated Material Yard dashboard RPC using authoritative location stock and customer outstanding data plus operational Load Ticket metrics. CFT summary cards only aggregate CFT quantities; mixed units remain separated in stock-by-material. No transaction writer changes.'
);
