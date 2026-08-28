-- FLEXI ERP V4.2
-- Branch/company stock rollups and integrity checks used by V4.2 and future V4.3 dashboards.
begin;

create or replace function public.inventory_location_stock_summary_v42(p_tenant_id uuid,p_location_id uuid default null)
returns table(
  variant_id uuid,sku text,product_name text,on_hand numeric,reserved numeric,available numeric,damaged numeric,quarantine numeric,
  in_transit_in numeric,in_transit_out numeric,total_company_on_hand numeric
) language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v_all boolean;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  v_all:=private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all');
  if p_location_id is not null then perform private.v4_location_access(p_tenant_id,p_location_id,'view');end if;
  return query
  with scoped as (
    select b.variant_id,
      sum(b.quantity)::numeric on_hand,sum(b.reserved_quantity)::numeric reserved,
      sum(b.damaged_quantity)::numeric damaged,sum(b.quarantine_quantity)::numeric quarantine
    from public.location_stock_balances b
    where b.tenant_id=p_tenant_id and (p_location_id is null or b.location_id=p_location_id)
      and (p_location_id is not null or v_all or private.erp_user_location_allowed(p_tenant_id,b.location_id,'view'))
    group by b.variant_id
  ), company as (
    select b.variant_id,sum(b.quantity)::numeric total
    from public.location_stock_balances b
    where b.tenant_id=p_tenant_id and (v_all or private.erp_user_location_allowed(p_tenant_id,b.location_id,'view'))
    group by b.variant_id
  ), transit_in as (
    select i.variant_id,sum(greatest(i.dispatched_quantity-i.received_quantity,0))::numeric qty
    from public.stock_transfers t join public.stock_transfer_items i on i.transfer_id=t.id
    where t.tenant_id=p_tenant_id and t.status='dispatched' and (p_location_id is null or t.to_location_id=p_location_id)
      and (p_location_id is not null or v_all or private.erp_user_location_allowed(p_tenant_id,t.to_location_id,'view'))
    group by i.variant_id
  ), transit_out as (
    select i.variant_id,sum(greatest(i.dispatched_quantity-i.received_quantity,0))::numeric qty
    from public.stock_transfers t join public.stock_transfer_items i on i.transfer_id=t.id
    where t.tenant_id=p_tenant_id and t.status='dispatched' and (p_location_id is null or t.from_location_id=p_location_id)
      and (p_location_id is not null or v_all or private.erp_user_location_allowed(p_tenant_id,t.from_location_id,'view'))
    group by i.variant_id
  )
  select s.variant_id,pv.sku::text,p.name::text,s.on_hand,s.reserved,
    (s.on_hand-s.reserved-s.damaged-s.quarantine)::numeric,s.damaged,s.quarantine,
    coalesce(ti.qty,0),coalesce(tout.qty,0),coalesce(c.total,0)
  from scoped s join public.product_variants pv on pv.id=s.variant_id join public.products p on p.id=pv.product_id
  left join company c on c.variant_id=s.variant_id left join transit_in ti on ti.variant_id=s.variant_id left join transit_out tout on tout.variant_id=s.variant_id
  order by p.name,pv.sku;
end $$;
grant execute on function public.inventory_location_stock_summary_v42(uuid,uuid) to authenticated;

create or replace function public.inventory_location_overview_v42(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;v_can_view_cost boolean;begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then raise exception 'Access denied';end if;
  v_can_view_cost:=private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'inventory.view_cost') or private.erp_has_permission(p_tenant_id,'inventory.manage');
  select coalesce(jsonb_agg(jsonb_build_object(
    'location_id',l.id,'parent_location_id',l.parent_location_id,'code',l.location_code,'name',l.name,'type',l.location_type,'hierarchy_role',l.hierarchy_role,
    'on_hand',coalesce(s.on_hand,0),'reserved',coalesce(s.reserved,0),'available',coalesce(s.available,0),'stock_value',case when v_can_view_cost then coalesce(s.stock_value,0) else null end,
    'in_transit_in',coalesce(ti.qty,0),'in_transit_out',coalesce(tout.qty,0),'device_count',coalesce(d.device_count,0)
  ) order by case when l.hierarchy_role='main_store' then 0 when l.hierarchy_role='warehouse' then 2 else 1 end,l.sort_order,l.name),'[]'::jsonb)
  into v
  from public.business_locations l
  left join lateral (
    select sum(b.quantity)::numeric on_hand,sum(b.reserved_quantity)::numeric reserved,
      sum(b.quantity-b.reserved_quantity-b.damaged_quantity-b.quarantine_quantity)::numeric available,
      sum(b.quantity*coalesce(nullif(b.average_cost,0),pv.cost_price,0))::numeric stock_value
    from public.location_stock_balances b join public.product_variants pv on pv.id=b.variant_id
    where b.tenant_id=p_tenant_id and b.location_id=l.id
  ) s on true
  left join lateral (
    select sum(greatest(i.dispatched_quantity-i.received_quantity,0))::numeric qty from public.stock_transfers t join public.stock_transfer_items i on i.transfer_id=t.id where t.tenant_id=p_tenant_id and t.to_location_id=l.id and t.status='dispatched'
  ) ti on true
  left join lateral (
    select sum(greatest(i.dispatched_quantity-i.received_quantity,0))::numeric qty from public.stock_transfers t join public.stock_transfer_items i on i.transfer_id=t.id where t.tenant_id=p_tenant_id and t.from_location_id=l.id and t.status='dispatched'
  ) tout on true
  left join lateral (
    select count(*)::bigint device_count from public.business_devices bd where bd.tenant_id=p_tenant_id and bd.location_id=l.id and bd.status<>'revoked'
  ) d on true
  where l.tenant_id=p_tenant_id and l.active
    and (private.erp_user_is_owner(p_tenant_id) or private.erp_has_permission(p_tenant_id,'locations.view_all') or private.erp_has_permission(p_tenant_id,'locations.manage_all') or private.erp_user_location_allowed(p_tenant_id,l.id,'view'));
  return coalesce(v,'[]'::jsonb);
end $$;
grant execute on function public.inventory_location_overview_v42(uuid) to authenticated;

create or replace function public.inventory_stock_integrity_v42(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path=public,private,pg_temp
as $$declare v jsonb;begin
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id,'inventory.manage') then raise exception 'Inventory manage permission required';end if;
  with global_qty as (
    select variant_id,sum(quantity)::numeric qty from public.stock_balances where tenant_id=p_tenant_id group by variant_id
  ), location_qty as (
    select variant_id,sum(quantity)::numeric qty from public.location_stock_balances where tenant_id=p_tenant_id group by variant_id
  ), x as (
    select coalesce(g.variant_id,l.variant_id) variant_id,coalesce(g.qty,0) global_qty,coalesce(l.qty,0) location_qty
    from global_qty g full join location_qty l on l.variant_id=g.variant_id
  )
  select jsonb_build_object(
    'tenant_id',p_tenant_id,'checked_at',now(),'mismatch_count',count(*) filter(where abs(global_qty-location_qty)>0.000001),
    'mismatches',coalesce(jsonb_agg(jsonb_build_object('variant_id',x.variant_id,'sku',pv.sku,'global_quantity',x.global_qty,'location_quantity',x.location_qty,'difference',x.location_qty-x.global_qty)) filter(where abs(global_qty-location_qty)>0.000001),'[]'::jsonb)
  ) into v
  from x left join public.product_variants pv on pv.id=x.variant_id;
  return v;
end $$;
grant execute on function public.inventory_stock_integrity_v42(uuid) to authenticated;

commit;
select 'Flexi ERP V4.2 inventory rollups ready' as status;
