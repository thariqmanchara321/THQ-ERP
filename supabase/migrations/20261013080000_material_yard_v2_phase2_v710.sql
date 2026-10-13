-- THQ ERP Material Yard v2 Phase 2 (v710)
-- 1. Fix material_daily_rates_get_v708 item_type filtering to support 'stock' goods
-- 2. Enhance aggregate_yard_dashboard_v621 with authoritative today_purchase_value, today_sales_value, and payables

-- 1. Daily Material Rate Board RPC fix
create or replace function public.material_daily_rates_get_v708(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_result jsonb;
begin
  perform private.aggregate_yard_assert_view_v617(p_tenant_id);

  if p_location_id is not null then
    perform private.v4_location_access(p_tenant_id, p_location_id, 'view');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'variant_id', v.id,
    'product_id', p.id,
    'product_name', p.name,
    'variant_name', v.name,
    'sku', v.sku,
    'base_unit_code', coalesce(bu.code, 'CFT'),
    'effective_date', p_date,
    'location_id', p_location_id,
    'purchase_rate', coalesce(r.purchase_rate, v.cost_price, 0),
    'selling_rate', coalesce(r.selling_rate, v.selling_price, 0),
    'wholesale_rate', coalesce(r.wholesale_rate, r.selling_rate, v.selling_price, 0),
    'min_selling_rate', coalesce(r.min_selling_rate, r.purchase_rate, v.cost_price, 0),
    'notes', coalesce(r.notes, ''),
    'previous_purchase_rate', pr.purchase_rate,
    'previous_selling_rate', pr.selling_rate,
    'has_today_rate', case when r.id is not null then true else false end,
    'is_stale', case
      when r.id is null and pr.purchase_rate is not null then true
      when r.effective_date < p_date then true
      else false
    end
  ) order by p.name, v.name), '[]'::jsonb)
  into v_result
  from public.product_variants v
  join public.products p on p.id = v.product_id and p.tenant_id = v.tenant_id
  left join public.product_units_v481 pbu on pbu.tenant_id = v.tenant_id and pbu.variant_id = v.id and pbu.is_base and pbu.active
  left join public.inventory_units_v481 bu on bu.id = pbu.unit_id and bu.tenant_id = pbu.tenant_id and bu.active
  left join public.material_daily_rates_v708 r on r.tenant_id = p_tenant_id
    and (p_location_id is null or r.location_id is null or r.location_id = p_location_id)
    and r.variant_id = v.id
    and r.effective_date = p_date
    and r.partner_type = 'all'
  left join lateral (
    select purchase_rate, selling_rate
    from public.material_daily_rates_v708
    where tenant_id = p_tenant_id
      and (p_location_id is null or location_id is null or location_id = p_location_id)
      and variant_id = v.id
      and effective_date < p_date
      and partner_type = 'all'
    order by effective_date desc
    limit 1
  ) pr on true
  where v.tenant_id = p_tenant_id
    and v.status = 'active'
    and p.status = 'active'
    and (p.item_type is null or p.item_type <> 'service' or p.item_type in ('stock', 'inventory', 'raw_material', 'product', 'goods'));

  return v_result;
end;
$$;

revoke all on function public.material_daily_rates_get_v708(uuid, uuid, date) from public, anon;
grant execute on function public.material_daily_rates_get_v708(uuid, uuid, date) to authenticated, service_role;

-- 2. Enhanced aggregate_yard_dashboard_v621
create or replace function public.aggregate_yard_dashboard_v621(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_day date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_base jsonb;
  v_stock_on_hand_cft numeric := 0;
  v_stock_available_cft numeric := 0;
  v_stock_by_material jsonb := '[]'::jsonb;
  v_today_purchase_value numeric := 0;
  v_today_sales_value numeric := 0;
  v_payables numeric := 0;
  v_payables_visible boolean := false;
begin
  v_base := public.aggregate_yard_dashboard_v617(
    p_tenant_id, p_location_id, p_day
  );

  if p_location_id is not null
     and exists(
       select 1
       from public.aggregate_direct_transit_locations_v621 m
       where m.tenant_id = p_tenant_id
         and m.transit_location_id = p_location_id
     ) then
    raise exception 'Direct Supply transit is not a physical yard location';
  end if;

  select
    coalesce(sum(
      case
        when upper(coalesce(u.code, '')) = 'CFT'
        then b.quantity
        else 0
      end
    ), 0),
    coalesce(sum(
      case
        when upper(coalesce(u.code, '')) = 'CFT'
        then greatest(
          b.quantity
          - coalesce(b.reserved_quantity, 0)
          - coalesce(b.damaged_quantity, 0)
          - coalesce(b.quarantine_quantity, 0),
          0
        )
        else 0
      end
    ), 0)
  into v_stock_on_hand_cft, v_stock_available_cft
  from public.location_stock_balances b
  join public.product_variants pv
    on pv.id = b.variant_id
   and pv.tenant_id = b.tenant_id
   and pv.status = 'active'
  join public.products p
    on p.id = pv.product_id
   and p.tenant_id = pv.tenant_id
   and p.status = 'active'
  left join public.product_units_v481 pbu
    on pbu.tenant_id = pv.tenant_id
   and pbu.variant_id = pv.id
   and pbu.is_base
   and pbu.active
  left join public.inventory_units_v481 u
    on u.id = pbu.unit_id
   and u.tenant_id = pbu.tenant_id
   and u.active
  where b.tenant_id = p_tenant_id
    and (p_location_id is null or b.location_id = p_location_id)
    and not exists(
      select 1
      from public.aggregate_direct_transit_locations_v621 m
      where m.tenant_id = b.tenant_id
        and m.transit_location_id = b.location_id
    )
    and private.erp_document_scope_allowed(
      p_tenant_id, b.location_id, p_location_id, 'view'
    );

  select coalesce(
    jsonb_agg(to_jsonb(q) order by q.product_name, q.variant_name),
    '[]'::jsonb
  )
  into v_stock_by_material
  from (
    select
      pv.id as variant_id,
      p.name as product_name,
      pv.name as variant_name,
      coalesce(u.code, '') as unit_code,
      round(sum(b.quantity), 3) as on_hand,
      round(sum(greatest(
        b.quantity
        - coalesce(b.reserved_quantity, 0)
        - coalesce(b.damaged_quantity, 0)
        - coalesce(b.quarantine_quantity, 0),
        0
      )), 3) as available,
      round(sum(coalesce(b.reserved_quantity, 0)), 3) as reserved
    from public.location_stock_balances b
    join public.product_variants pv
      on pv.id = b.variant_id
     and pv.tenant_id = b.tenant_id
     and pv.status = 'active'
    join public.products p
      on p.id = pv.product_id
     and p.tenant_id = pv.tenant_id
     and p.status = 'active'
    left join public.product_units_v481 pbu
      on pbu.tenant_id = pv.tenant_id
     and pbu.variant_id = pv.id
     and pbu.is_base
     and pbu.active
    left join public.inventory_units_v481 u
      on u.id = pbu.unit_id
     and u.tenant_id = pbu.tenant_id
     and u.active
    where b.tenant_id = p_tenant_id
      and p.item_type = 'stock'
      and (p_location_id is null or b.location_id = p_location_id)
      and not exists(
        select 1
        from public.aggregate_direct_transit_locations_v621 m
        where m.tenant_id = b.tenant_id
          and m.transit_location_id = b.location_id
      )
      and private.erp_document_scope_allowed(
        p_tenant_id, b.location_id, p_location_id, 'view'
      )
    group by pv.id, p.name, pv.name, u.code
    having sum(b.quantity) <> 0
    order by p.name, pv.name
    limit 200
  ) q;

  -- Today's authoritative purchase and sales values
  select coalesce(sum(p.grand_total), 0)
  into v_today_purchase_value
  from public.purchases p
  where p.tenant_id = p_tenant_id
    and p.purchase_date = p_day
    and coalesce(p.status, '') not in ('void', 'cancelled')
    and (p_location_id is null or exists(select 1 from public.document_origins o where o.tenant_id = p_tenant_id and o.entity_type = 'purchase' and o.entity_id = p.id and o.location_id = p_location_id));

  select coalesce(sum(s.grand_total), 0)
  into v_today_sales_value
  from public.sales s
  where s.tenant_id = p_tenant_id
    and s.sale_date = p_day
    and coalesce(s.status, '') not in ('void', 'cancelled')
    and (p_location_id is null or exists(select 1 from public.document_origins o where o.tenant_id = p_tenant_id and o.entity_type = 'sale' and o.entity_id = s.id and o.location_id = p_location_id));

  -- Supplier Payables
  v_payables_visible :=
    private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id, 'accounting.view')
    or private.erp_has_permission(p_tenant_id, 'purchases.view')
    or private.erp_has_permission(p_tenant_id, 'purchases.manage')
    or private.erp_has_permission(p_tenant_id, 'suppliers.view')
    or private.erp_has_permission(p_tenant_id, 'suppliers.manage');

  if v_payables_visible then
    select coalesce(sum(si.total_outstanding), 0)
    into v_payables
    from public.supplier_payables_intelligence_v480(
      p_tenant_id, p_location_id, '', 5000
    ) si;
  end if;

  return v_base || jsonb_build_object(
    'stock_on_hand_cft', round(v_stock_on_hand_cft, 3),
    'stock_available_cft', round(v_stock_available_cft, 3),
    'stock_by_material', coalesce(v_stock_by_material, '[]'::jsonb),
    'today_purchase_value', round(v_today_purchase_value, 2),
    'today_sales_value', round(v_today_sales_value, 2),
    'payables', case when v_payables_visible then round(v_payables, 2) else null end,
    'payables_visible', v_payables_visible,
    'physical_yard_stock_only', true
  );
end;
$$;

revoke all on function public.aggregate_yard_dashboard_v621(uuid, uuid, date) from public, anon;
grant execute on function public.aggregate_yard_dashboard_v621(uuid, uuid, date) to authenticated, service_role;
