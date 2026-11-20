-- ============================================================================
-- THQ ERP — Operations Intelligence Phase 4
-- Advanced Inventory Intelligence & Inter-Store Rebalancing
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Performance Indexes for Advanced Inventory and Transfers
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_stock_transfers_tenant_status_locs
  ON public.stock_transfers (tenant_id, status, from_location_id, to_location_id);

CREATE INDEX IF NOT EXISTS idx_stock_transfer_items_transfer_variant
  ON public.stock_transfer_items (transfer_id, variant_id);

CREATE INDEX IF NOT EXISTS idx_purchase_orders_tenant_status_loc
  ON public.purchase_orders_v480 (tenant_id, status, location_id);

CREATE INDEX IF NOT EXISTS idx_purchase_order_items_po_variant
  ON public.purchase_order_items_v480 (purchase_order_id, variant_id);

-- ----------------------------------------------------------------------------
-- 2. Drop existing inventory_intelligence_v830 to allow 32-column signature
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.inventory_intelligence_v830(uuid, uuid, integer, text, integer);

-- ----------------------------------------------------------------------------
-- 3. Upgraded inventory_intelligence_v830 (Cumulative ABC, Movement Classes,
--    Incoming POs, In-Transit Transfers, Turnover & Excess Valuation)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.inventory_intelligence_v830(
  p_tenant_id uuid,
  p_location_id uuid DEFAULT NULL::uuid,
  p_days integer DEFAULT 30,
  p_query text DEFAULT ''::text,
  p_limit integer DEFAULT 1000
)
RETURNS TABLE (
  location_id uuid,
  location_code text,
  location_name text,
  variant_id uuid,
  product_id uuid,
  product_name text,
  sku text,
  barcode text,
  quantity numeric,
  available numeric,
  reorder_level numeric,
  max_stock numeric,
  average_cost numeric,
  stock_value numeric,
  net_sold_qty numeric,
  avg_daily_sales numeric,
  days_cover numeric,
  suggested_reorder numeric,
  last_sale_date date,
  last_purchase_date date,
  status text,
  abc_class text,
  movement_class text,
  incoming_po_qty numeric,
  in_transit_qty numeric,
  reserved_qty numeric,
  net_effective_stock numeric,
  sales_value numeric,
  cumulative_sales_pct numeric,
  turnover_ratio numeric,
  excess_qty numeric,
  excess_value numeric
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_from date := current_date - (v_days - 1);
  q text := '%' || lower(trim(coalesce(p_query, ''))) || '%';
  v_can_view_cost boolean := false;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if p_location_id is not null and not private.erp_document_scope_allowed(p_tenant_id, p_location_id, p_location_id, 'view') then
    raise exception 'Location access denied';
  end if;

  v_can_view_cost := private.erp_user_is_owner(p_tenant_id) 
    or private.erp_has_permission(p_tenant_id, 'inventory.view_cost')
    or private.erp_has_permission(p_tenant_id, 'inventory.manage');

  return query
  with active_locs as (
    select l.id as location_id, l.location_code, l.name as location_name
    from public.business_locations l
    where l.tenant_id = p_tenant_id
      and l.active = true
      and (p_location_id is null or l.id = p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id, l.id, p_location_id, 'view')
  ),
  sold as (
    select
      o.location_id,
      si.variant_id,
      sum(greatest(si.quantity - coalesce((
        select sum(ri.quantity)
        from public.sales_return_items ri
        join public.sales_returns r on r.id = ri.sales_return_id
        where ri.sale_item_id = si.id and r.refund_status <> 'waived' and r.return_date <= current_date
      ), 0), 0))::numeric as qty,
      round(sum(greatest(si.line_total - coalesce((
        select sum(ri.line_total)
        from public.sales_return_items ri
        join public.sales_returns r on r.id = ri.sales_return_id
        where ri.sale_item_id = si.id and r.refund_status <> 'waived' and r.return_date <= current_date
      ), 0), 0)), 2)::numeric as sales_val
    from public.sale_items si
    join public.sales s on s.id = si.sale_id
    join public.document_origins o on o.tenant_id = p_tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
    where s.tenant_id = p_tenant_id
      and s.sale_date between v_from and current_date
      and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id, o.location_id, p_location_id, 'view')
    group by o.location_id, si.variant_id
  ),
  last_sold as (
    select o.location_id, si.variant_id, max(s.sale_date) as last_sale
    from public.sale_items si
    join public.sales s on s.id = si.sale_id
    join public.document_origins o on o.tenant_id = p_tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
    where s.tenant_id = p_tenant_id
      and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id, o.location_id, p_location_id, 'view')
    group by o.location_id, si.variant_id
  ),
  purchased as (
    select loc_id, var_id, max(dt) as last_purchase
    from (
      select o.location_id as loc_id, pi.variant_id as var_id, max(p.purchase_date) as dt
      from public.purchase_items pi
      join public.purchases p on p.id = pi.purchase_id
      join public.document_origins o on o.tenant_id = p_tenant_id and o.entity_type = 'purchase' and o.entity_id = p.id
      where p.tenant_id = p_tenant_id
        and coalesce(p.status, '') not in ('void', 'cancelled')
        and (p_location_id is null or o.location_id = p_location_id)
        and private.erp_document_scope_allowed(p_tenant_id, o.location_id, p_location_id, 'view')
      group by o.location_id, pi.variant_id
      union all
      select g.location_id as loc_id, gi.variant_id as var_id, max(g.receipt_date) as dt
      from public.goods_receipt_items_v484 gi
      join public.goods_receipts_v484 g on g.id = gi.goods_receipt_id
      where g.tenant_id = p_tenant_id
        and g.status = 'posted'
        and (p_location_id is null or g.location_id = p_location_id)
        and private.erp_document_scope_allowed(p_tenant_id, g.location_id, p_location_id, 'view')
      group by g.location_id, gi.variant_id
    ) u
    group by loc_id, var_id
  ),
  incoming_pos as (
    select
      po.location_id,
      poi.variant_id,
      coalesce(sum(greatest(poi.quantity - coalesce(poi.received_quantity, 0), 0)), 0)::numeric as incoming_qty
    from public.purchase_order_items_v480 poi
    join public.purchase_orders_v480 po on po.id = poi.purchase_order_id
    where po.tenant_id = p_tenant_id
      and po.status in ('approved', 'ordered', 'partially_received')
      and (p_location_id is null or po.location_id = p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id, po.location_id, p_location_id, 'view')
    group by po.location_id, poi.variant_id
  ),
  incoming_transfers as (
    select
      st.to_location_id as location_id,
      sti.variant_id,
      coalesce(sum(greatest(sti.quantity - coalesce(sti.received_quantity, 0), 0)), 0)::numeric as in_transit_qty
    from public.stock_transfer_items sti
    join public.stock_transfers st on st.id = sti.transfer_id
    where st.tenant_id = p_tenant_id
      and st.status in ('approved', 'dispatched', 'in_transit')
      and (p_location_id is null or st.to_location_id = p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id, st.to_location_id, p_location_id, 'view')
    group by st.to_location_id, sti.variant_id
  ),
  outgoing_transfers as (
    select
      st.from_location_id as location_id,
      sti.variant_id,
      coalesce(sum(greatest(sti.quantity - coalesce(sti.received_quantity, 0), 0)), 0)::numeric as committed_transfer_qty
    from public.stock_transfer_items sti
    join public.stock_transfers st on st.id = sti.transfer_id
    where st.tenant_id = p_tenant_id
      and st.status in ('requested', 'approved', 'dispatched', 'in_transit')
      and (p_location_id is null or st.from_location_id = p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id, st.from_location_id, p_location_id, 'view')
    group by st.from_location_id, sti.variant_id
  ),
  relevant_variants as (
    select s.location_id, s.variant_id
    from public.location_product_settings s
    join active_locs al on al.location_id = s.location_id
    where s.tenant_id = p_tenant_id and s.active = true
    union
    select b.location_id, b.variant_id
    from public.location_stock_balances b
    join active_locs al on al.location_id = b.location_id
    where b.tenant_id = p_tenant_id and (coalesce(b.quantity, 0) != 0 or coalesce(b.reserved_quantity, 0) != 0)
    union
    select so.location_id, so.variant_id
    from sold so
    union
    select pu.loc_id as location_id, pu.var_id as variant_id
    from purchased pu
    union
    select ipo.location_id, ipo.variant_id
    from incoming_pos ipo
    union
    select it.location_id, it.variant_id
    from incoming_transfers it
  ),
  base as (
    select 
      al.location_id,
      al.location_code,
      al.location_name,
      pv.id as variant_id,
      p.id as product_id,
      p.name as product_name,
      pv.sku,
      coalesce(pv.barcode, '') as barcode,
      coalesce(b.quantity, 0)::numeric as quantity,
      greatest((coalesce(b.quantity, 0) - coalesce(b.reserved_quantity, 0) - coalesce(b.damaged_quantity, 0) - coalesce(b.quarantine_quantity, 0) - coalesce(ot.committed_transfer_qty, 0)), 0)::numeric as available,
      (coalesce(b.reserved_quantity, 0) + coalesce(ot.committed_transfer_qty, 0))::numeric as reserved_qty,
      coalesce(ipo.incoming_qty, 0)::numeric as incoming_po_qty,
      coalesce(it.in_transit_qty, 0)::numeric as in_transit_qty,
      coalesce(s.reorder_level, pv.reorder_level, 0)::numeric as reorder_level,
      coalesce(s.max_stock, 0)::numeric as max_stock,
      case when v_can_view_cost then coalesce(b.average_cost, pv.cost_price, 0)::numeric else 0::numeric end as average_cost,
      coalesce(so.qty, 0)::numeric as net_sold_qty,
      coalesce(so.sales_val, 0)::numeric as sales_val,
      ls.last_sale,
      pu.last_purchase
    from relevant_variants rv
    join active_locs al on al.location_id = rv.location_id
    join public.product_variants pv on pv.id = rv.variant_id and pv.tenant_id = p_tenant_id
    join public.products p on p.id = pv.product_id and p.tenant_id = p_tenant_id
    left join public.location_product_settings s on s.tenant_id = p_tenant_id and s.location_id = rv.location_id and s.variant_id = rv.variant_id
    left join public.location_stock_balances b on b.tenant_id = p_tenant_id and b.location_id = rv.location_id and b.variant_id = rv.variant_id
    left join sold so on so.location_id = rv.location_id and so.variant_id = rv.variant_id
    left join last_sold ls on ls.location_id = rv.location_id and ls.variant_id = rv.variant_id
    left join purchased pu on pu.loc_id = rv.location_id and pu.var_id = rv.variant_id
    left join incoming_pos ipo on ipo.location_id = rv.location_id and ipo.variant_id = rv.variant_id
    left join incoming_transfers it on it.location_id = rv.location_id and it.variant_id = rv.variant_id
    left join outgoing_transfers ot on ot.location_id = rv.location_id and ot.variant_id = rv.variant_id
    where (trim(coalesce(p_query, '')) = '' or lower(p.name) like q or lower(coalesce(pv.sku, '')) like q or lower(coalesce(pv.barcode, '')) like q or lower(coalesce(pv.part_number, '')) like q)
      and (coalesce(b.quantity, 0) > 0 or coalesce(so.qty, 0) > 0 or coalesce(s.reorder_level, pv.reorder_level, 0) > 0 or coalesce(ipo.incoming_qty, 0) > 0 or coalesce(it.in_transit_qty, 0) > 0)
  ),
  sales_pareto as (
    select
      b.*,
      sum(b.sales_val) over (partition by b.location_id) as total_loc_sales,
      sum(b.sales_val) over (
        partition by b.location_id
        order by b.sales_val desc, b.variant_id
        rows between unbounded preceding and current row
      ) as cum_sales
    from base b
  ),
  ranked as (
    select p.*,
      (p.available + p.incoming_po_qty + p.in_transit_qty)::numeric as net_effective_stock,
      case when v_can_view_cost then round(p.quantity * p.average_cost, 2)::numeric else 0::numeric end as stock_val,
      round(p.net_sold_qty / v_days, 4)::numeric as daily_sales,
      case when p.net_sold_qty <= 0 then null else round(p.available / (p.net_sold_qty / v_days), 1) end::numeric as cover_days,
      
      -- Suggested replenishment takes into account already incoming POs & transfers to prevent duplicate ordering
      case
        when (p.available + p.incoming_po_qty + p.in_transit_qty) <= p.reorder_level and p.reorder_level > 0 then
          greatest(
            case
              when p.max_stock > 0 then p.max_stock - (p.available + p.incoming_po_qty + p.in_transit_qty)
              else (p.reorder_level * 2) - (p.available + p.incoming_po_qty + p.in_transit_qty)
            end, 0
          )::numeric
        else 0::numeric
      end as reorder_qty,
      
      -- Stock Health Status
      case
        when p.available <= 0 then 'out_of_stock'
        when p.available > 0 and (
          (p.net_sold_qty > 0 and (p.available / (p.net_sold_qty / v_days)) <= 7) or
          (p.reorder_level > 0 and p.available <= (p.reorder_level * 0.5))
        ) then 'critical_low'
        when p.reorder_level > 0 and p.available <= p.reorder_level then 'low_stock'
        when p.max_stock > 0 and p.available > p.max_stock then 'overstock'
        when p.quantity > 0 and p.net_sold_qty = 0 and (p.last_sale is null or p.last_sale < current_date - interval '90 days') then 'dead_stock'
        else 'healthy'
      end as stock_status,

      -- Movement Classification (Velocity & Recency)
      case
        when p.quantity > 0 and p.net_sold_qty = 0 and (p.last_sale is null or p.last_sale < current_date - interval '90 days') then 'dead_stock'
        when p.quantity > 0 and p.net_sold_qty = 0 then 'non_moving'
        when p.net_sold_qty > 0 and ((p.net_sold_qty / v_days) >= 1.0 or (p.available / (p.net_sold_qty / v_days)) <= 30) then 'fast_moving'
        when p.net_sold_qty > 0 and (p.available / (p.net_sold_qty / v_days)) <= 90 then 'normal_moving'
        when p.net_sold_qty > 0 and (p.available / (p.net_sold_qty / v_days)) > 90 then 'slow_moving'
        else 'non_moving'
      end as movement_class,

      -- ABC Pareto Classification (70% Class A, 20% Class B, Remaining Class C)
      case
        when p.total_loc_sales > 0 and p.sales_val > 0 then
          round((p.cum_sales * 100.0) / p.total_loc_sales, 2)
        else 0
      end as cumulative_sales_pct,
      case
        when p.total_loc_sales > 0 and p.sales_val > 0 then
          case
            when ((p.cum_sales - p.sales_val) * 1.0) / p.total_loc_sales < 0.70 then 'A'
            when ((p.cum_sales - p.sales_val) * 1.0) / p.total_loc_sales < 0.90 then 'B'
            else 'C'
          end
        else 'C'
      end as abc_class,

      -- Excess Stock calculations
      greatest(case when p.max_stock > 0 and p.available > p.max_stock then p.available - p.max_stock else 0 end, 0)::numeric as excess_qty,
      case
        when v_can_view_cost and p.max_stock > 0 and p.available > p.max_stock then
          round((p.available - p.max_stock) * p.average_cost, 2)::numeric
        else 0::numeric
      end as excess_value,

      -- Turnover Ratio: Annualized Sales Value / Stock Valuation
      case
        when v_can_view_cost and (p.quantity * p.average_cost) > 0 then
          round((p.sales_val * (365.0 / v_days)) / (p.quantity * p.average_cost), 2)::numeric
        when (p.quantity * coalesce(p.average_cost, 1)) > 0 then
          round((p.net_sold_qty * (365.0 / v_days)) / p.quantity, 2)::numeric
        else 0::numeric
      end as turnover_ratio
    from sales_pareto p
  )
  select 
    r.location_id,
    r.location_code,
    r.location_name,
    r.variant_id,
    r.product_id,
    r.product_name,
    r.sku,
    r.barcode,
    r.quantity,
    r.available,
    r.reorder_level,
    r.max_stock,
    r.average_cost,
    r.stock_val as stock_value,
    r.net_sold_qty,
    r.daily_sales as avg_daily_sales,
    r.cover_days as days_cover,
    r.reorder_qty as suggested_reorder,
    r.last_sale as last_sale_date,
    r.last_purchase as last_purchase_date,
    r.stock_status::text as status,
    r.abc_class::text as abc_class,
    r.movement_class::text as movement_class,
    r.incoming_po_qty,
    r.in_transit_qty,
    r.reserved_qty,
    r.net_effective_stock,
    r.sales_val as sales_value,
    r.cumulative_sales_pct,
    r.turnover_ratio,
    r.excess_qty,
    r.excess_value
  from ranked r
  order by
    case when r.stock_status = 'out_of_stock' then 1
         when r.stock_status = 'critical_low' then 2
         when r.stock_status = 'low_stock' then 3
         when r.stock_status = 'dead_stock' then 4
         when r.stock_status = 'overstock' then 5
         else 6 end,
    r.net_sold_qty desc,
    r.product_name
  limit greatest(1, least(coalesce(p_limit, 1000), 5000));
end $$;

GRANT ALL ON FUNCTION public.inventory_intelligence_v830(uuid, uuid, integer, text, integer) TO authenticated;
GRANT ALL ON FUNCTION public.inventory_intelligence_v830(uuid, uuid, integer, text, integer) TO service_role;

-- ----------------------------------------------------------------------------
-- 4. Inter-Store Stock Rebalancing Recommendations RPC
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.inventory_rebalancing_recommendations_v830(
  p_tenant_id uuid,
  p_location_id uuid DEFAULT NULL::uuid,
  p_days integer DEFAULT 30,
  p_limit integer DEFAULT 100
)
RETURNS TABLE (
  variant_id uuid,
  product_id uuid,
  product_name text,
  sku text,
  barcode text,
  source_location_id uuid,
  source_location_code text,
  source_location_name text,
  source_available numeric,
  source_demand_30d numeric,
  source_excess numeric,
  source_stock_after numeric,
  dest_location_id uuid,
  dest_location_code text,
  dest_location_name text,
  dest_available numeric,
  dest_demand_30d numeric,
  dest_shortage numeric,
  dest_stock_after numeric,
  suggested_transfer_qty numeric,
  priority text,
  reason text,
  estimated_cost numeric,
  active_transfer_exists boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_can_view_cost boolean := false;
  v_loc_count integer := 0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if p_location_id is not null and not private.erp_document_scope_allowed(p_tenant_id, p_location_id, p_location_id, 'view') then
    raise exception 'Location access denied';
  end if;

  v_can_view_cost := private.erp_user_is_owner(p_tenant_id) 
    or private.erp_has_permission(p_tenant_id, 'inventory.view_cost')
    or private.erp_has_permission(p_tenant_id, 'inventory.manage');

  -- Count accessible active locations. If tenant has only 1 store, rebalancing is not applicable.
  select count(*) into v_loc_count
  from public.business_locations l
  where l.tenant_id = p_tenant_id and l.active = true;

  if v_loc_count < 2 then
    return;
  end if;

  return query
  with loc_items as (
    select
      r.location_id,
      r.location_code,
      r.location_name,
      r.variant_id,
      r.product_id,
      r.product_name,
      r.sku,
      r.barcode,
      r.available,
      r.reorder_level,
      r.max_stock,
      r.average_cost,
      r.net_sold_qty,
      r.avg_daily_sales,
      r.days_cover,
      r.incoming_po_qty,
      r.in_transit_qty,
      r.net_effective_stock,
      round(r.avg_daily_sales * 30.0, 1)::numeric as demand_30d,
      greatest(round(r.avg_daily_sales * 30.0, 1), r.reorder_level, 1)::numeric as target_stock,
      -- Buffer to retain at source location (always keep 1.5x 30d demand, reorder level + 20%, or max_stock)
      greatest(
        r.max_stock,
        round(r.avg_daily_sales * 45.0, 1),
        round(r.reorder_level * 1.2, 1),
        5.0
      )::numeric as required_source_buffer
    from public.inventory_intelligence_v830(p_tenant_id, null, v_days, '', 5000) r
  ),
  classified_locs as (
    select
      li.*,
      -- Transferable excess: stock available strictly above the required buffer
      greatest(li.available - li.required_source_buffer, 0)::numeric as transferable_excess,
      -- Shortage: effective stock below reorder level or below 30d target
      case
        when li.net_effective_stock <= li.reorder_level or (li.demand_30d > 0 and li.net_effective_stock <= (li.demand_30d * 0.5)) then
          greatest(li.target_stock - li.net_effective_stock, li.reorder_level - li.net_effective_stock, 1)::numeric
        else 0::numeric
      end as shortage_qty
    from loc_items li
  ),
  paired as (
    select
      src.variant_id,
      src.product_id,
      src.product_name,
      src.sku,
      src.barcode,
      src.location_id as source_loc_id,
      src.location_code as source_loc_code,
      src.location_name as source_loc_name,
      src.available as source_available,
      src.demand_30d as source_demand_30d,
      src.transferable_excess as source_excess,
      dst.location_id as dest_loc_id,
      dst.location_code as dest_loc_code,
      dst.location_name as dest_loc_name,
      dst.available as dest_available,
      dst.demand_30d as dest_demand_30d,
      dst.shortage_qty as dest_shortage,
      round(least(src.transferable_excess, dst.shortage_qty))::numeric as transfer_qty,
      src.average_cost,
      case
        when dst.available <= 0 then 'critical'
        when dst.available <= (dst.reorder_level * 0.5) then 'high'
        else 'normal'
      end as priority_level,
      format(
        '%s has %s transferable excess units (exceeding 30d demand of %s), while %s has %s units shortage (target: %s units, daily demand: %s).',
        src.location_name,
        src.transferable_excess::text,
        src.demand_30d::text,
        dst.location_name,
        dst.shortage_qty::text,
        dst.target_stock::text,
        dst.avg_daily_sales::text
      ) as rationale,
      exists (
        select 1
        from public.stock_transfers st
        join public.stock_transfer_items sti on sti.transfer_id = st.id
        where st.tenant_id = p_tenant_id
          and st.from_location_id = src.location_id
          and st.to_location_id = dst.location_id
          and sti.variant_id = src.variant_id
          and st.status in ('requested', 'approved', 'dispatched', 'in_transit')
      ) as has_active_transfer
    from classified_locs src
    join classified_locs dst on dst.variant_id = src.variant_id and dst.location_id <> src.location_id
    where src.transferable_excess >= 1
      and dst.shortage_qty >= 1
      and (p_location_id is null or src.location_id = p_location_id or dst.location_id = p_location_id)
  )
  select
    p.variant_id,
    p.product_id,
    p.product_name,
    p.sku,
    p.barcode,
    p.source_loc_id as source_location_id,
    p.source_loc_code as source_location_code,
    p.source_loc_name as source_location_name,
    p.source_available,
    p.source_demand_30d,
    p.source_excess,
    (p.source_available - p.transfer_qty)::numeric as source_stock_after,
    p.dest_loc_id as dest_location_id,
    p.dest_loc_code as dest_location_code,
    p.dest_loc_name as dest_location_name,
    p.dest_available,
    p.dest_demand_30d,
    p.dest_shortage,
    (p.dest_available + p.transfer_qty)::numeric as dest_stock_after,
    p.transfer_qty as suggested_transfer_qty,
    p.priority_level as priority,
    p.rationale as reason,
    case when v_can_view_cost then round(p.transfer_qty * p.average_cost, 2)::numeric else 0::numeric end as estimated_cost,
    p.has_active_transfer as active_transfer_exists
  from paired p
  where p.transfer_qty >= 1
  order by
    case when p.priority_level = 'critical' then 1
         when p.priority_level = 'high' then 2
         else 3 end,
    p.transfer_qty desc,
    p.product_name
  limit greatest(1, least(coalesce(p_limit, 100), 500));
end $$;

GRANT ALL ON FUNCTION public.inventory_rebalancing_recommendations_v830(uuid, uuid, integer, integer) TO authenticated;
GRANT ALL ON FUNCTION public.inventory_rebalancing_recommendations_v830(uuid, uuid, integer, integer) TO service_role;

-- ----------------------------------------------------------------------------
-- 5. Recreate operations_intelligence_summary_v830 with Dead/Excess Stock Value
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.operations_intelligence_summary_v830(
  p_tenant_id uuid,
  p_location_id uuid DEFAULT NULL::uuid,
  p_days integer DEFAULT 30
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_from date := current_date - (v_days - 1);
  v_res jsonb;

  -- Flow metrics
  v_gross_sales numeric := 0;
  v_returns numeric := 0;
  v_net_sales numeric := 0;
  v_cogs numeric := 0;
  v_expenses numeric := 0;
  v_order_count integer := 0;

  -- Inventory metrics
  v_low_stock integer := 0;
  v_out_of_stock integer := 0;
  v_dead_stock integer := 0;
  v_overstock integer := 0;
  v_total_variants integer := 0;
  v_inventory_val numeric := 0;
  v_dead_stock_val numeric := 0;
  v_excess_stock_val numeric := 0;
  v_rebalancing_count integer := 0;

  -- Financials
  v_receivable numeric := 0;
  v_overdue_recv numeric := 0;
  v_payable numeric := 0;
  v_overdue_pay numeric := 0;

  -- Ops
  v_pipeline jsonb := '{}'::jsonb;
  v_unresolved_insights integer := 0;
  v_critical_insights integer := 0;
  v_top_products jsonb := '[]'::jsonb;
  v_can_view_cost boolean := false;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;
  if p_location_id is not null and not private.erp_document_scope_allowed(p_tenant_id, p_location_id, p_location_id, 'view') then
    raise exception 'Location access denied';
  end if;

  v_can_view_cost := private.erp_user_is_owner(p_tenant_id) 
    or private.erp_has_permission(p_tenant_id, 'inventory.view_cost')
    or private.erp_has_permission(p_tenant_id, 'inventory.manage');

  -- 1. Sales flow with origins join
  select
    coalesce(sum(s.grand_total), 0),
    count(*),
    coalesce(sum(s.cost_total), 0)
  into v_gross_sales, v_order_count, v_cogs
  from public.sales s
  left join public.document_origins o on o.tenant_id = p_tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
  where s.tenant_id = p_tenant_id
    and s.sale_date between v_from and current_date
    and coalesce(s.status, '') not in ('void', 'cancelled')
    and (p_location_id is null or o.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, o.location_id, p_location_id, 'view');

  -- Returns
  select coalesce(sum(r.grand_total), 0)
  into v_returns
  from public.sales_returns r
  where r.tenant_id = p_tenant_id
    and r.return_date between v_from and current_date
    and r.refund_status <> 'waived'
    and (p_location_id is null or r.location_id = p_location_id)
    and private.erp_document_scope_allowed(p_tenant_id, r.location_id, p_location_id, 'view');

  v_net_sales := greatest(v_gross_sales - v_returns, 0);

  -- Expenses
  select coalesce(sum(e.total_amount), 0)
  into v_expenses
  from public.expenses e
  left join public.document_origins o on o.tenant_id = e.tenant_id and o.entity_type = 'expense' and o.entity_id = e.id
  where e.tenant_id = p_tenant_id
    and e.expense_date between v_from and current_date
    and e.status = 'posted'
    and (p_location_id is null or o.location_id = p_location_id);

  -- Top products by revenue
  select coalesce(jsonb_agg(to_jsonb(p) order by p.revenue desc), '[]'::jsonb)
  into v_top_products
  from (
    select
      p.name as product_name,
      pv.sku,
      sum(si.quantity)::numeric as units_sold,
      round(sum(si.line_total), 2)::numeric as revenue
    from public.sale_items si
    join public.sales s on s.id = si.sale_id
    join public.product_variants pv on pv.id = si.variant_id
    join public.products p on p.id = pv.product_id
    left join public.document_origins o on o.tenant_id = p_tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
    where s.tenant_id = p_tenant_id
      and s.sale_date between v_from and current_date
      and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id, o.location_id, p_location_id, 'view')
    group by p.name, pv.sku
    order by revenue desc
    limit 5
  ) p;

  -- 2. Inventory metrics from inventory_intelligence_v830
  select 
    count(*) filter (where status in ('low_stock', 'critical_low')),
    count(*) filter (where status = 'out_of_stock'),
    count(*) filter (where status = 'dead_stock'),
    count(*) filter (where status = 'overstock'),
    count(*),
    coalesce(sum(stock_value), 0),
    coalesce(sum(case when status = 'dead_stock' then stock_value else 0 end), 0),
    coalesce(sum(excess_value), 0)
  into v_low_stock, v_out_of_stock, v_dead_stock, v_overstock, v_total_variants, v_inventory_val, v_dead_stock_val, v_excess_stock_val
  from public.inventory_intelligence_v830(p_tenant_id, p_location_id, v_days, '', 5000);

  -- Rebalancing opportunities count
  select count(*)
  into v_rebalancing_count
  from public.inventory_rebalancing_recommendations_v830(p_tenant_id, p_location_id, v_days, 100);

  -- 3. Customer credit receivables
  select 
    coalesce(sum(total_outstanding), 0),
    coalesce(sum(days_1_30 + days_31_60 + days_61_90 + days_90_plus), 0)
  into v_receivable, v_overdue_recv
  from public.customer_credit_intelligence_v480(p_tenant_id, p_location_id, '', 5000);

  -- 4. Supplier payables
  select 
    coalesce(sum(total_outstanding), 0),
    coalesce(sum(days_1_30 + days_31_60 + days_61_90 + days_90_plus), 0)
  into v_payable, v_overdue_pay
  from public.supplier_payables_intelligence_v480(p_tenant_id, p_location_id, '', 5000);

  -- 5. Operations pipeline
  v_pipeline := coalesce(public.operations_pipeline_v489(p_tenant_id, p_location_id), '{}'::jsonb);

  -- 6. Active insights counts
  select count(*), count(*) filter (where severity = 'critical')
    into v_unresolved_insights, v_critical_insights
  from public.erp_intelligence_insights
  where tenant_id = p_tenant_id
    and status in ('new_insight', 'acknowledged', 'in_progress')
    and (p_location_id is null or location_id is null or location_id = p_location_id);

  v_res := jsonb_build_object(
    'tenant_id', p_tenant_id,
    'location_id', p_location_id,
    'days', v_days,
    'from_date', v_from,
    'to_date', current_date,
    'gross_sales', v_gross_sales,
    'sales_returns', v_returns,
    'net_sales', v_net_sales,
    'cogs', case when v_can_view_cost then v_cogs else 0 end,
    'gross_profit', case when v_can_view_cost then greatest(v_net_sales - v_cogs, 0) else 0 end,
    'gross_margin_pct', case when v_can_view_cost and v_net_sales > 0 then round(((v_net_sales - v_cogs) * 100.0) / v_net_sales, 2) else 0 end,
    'expenses', v_expenses,
    'net_operating_profit', case when v_can_view_cost then (v_net_sales - v_cogs - v_expenses) else 0 end,
    'order_count', v_order_count,
    'average_order_value', case when v_order_count > 0 then round(v_net_sales / v_order_count, 2) else 0 end,
    'inventory_value', case when v_can_view_cost then v_inventory_val else 0 end,
    'total_monitored_variants', v_total_variants,
    'low_stock', v_low_stock,
    'low_stock_count', v_low_stock,
    'low_stock_variants', v_low_stock,
    'out_of_stock', v_out_of_stock,
    'out_of_stock_count', v_out_of_stock,
    'out_of_stock_variants', v_out_of_stock,
    'dead_stock', v_dead_stock,
    'dead_stock_count', v_dead_stock,
    'dead_stock_variants', v_dead_stock,
    'dead_stock_value', case when v_can_view_cost then v_dead_stock_val else 0 end,
    'overstock', v_overstock,
    'overstock_count', v_overstock,
    'overstock_variants', v_overstock,
    'excess_stock_value', case when v_can_view_cost then v_excess_stock_val else 0 end,
    'rebalancing_opportunities', v_rebalancing_count,
    'receivables', v_receivable,
    'overdue_receivables', v_overdue_recv,
    'payables', v_payable,
    'overdue_payables', v_overdue_pay,
    'top_products', v_top_products,
    'pipeline', v_pipeline,
    'unresolved_insights', v_unresolved_insights,
    'critical_insights', v_critical_insights
  );

  return v_res;
end $$;

GRANT ALL ON FUNCTION public.operations_intelligence_summary_v830(uuid, uuid, integer) TO authenticated;
GRANT ALL ON FUNCTION public.operations_intelligence_summary_v830(uuid, uuid, integer) TO service_role;

-- ----------------------------------------------------------------------------
-- 6. Record Schema Release
-- ----------------------------------------------------------------------------
INSERT INTO public.thq_schema_releases(migration_no, schema_version, release_name, notes)
VALUES (
  229,
  '8.3.3',
  'Operations Intelligence Phase 4: Advanced Inventory Intelligence & Inter-Store Rebalancing',
  'Introduces cumulative sales-value ABC Pareto analysis, movement classification (fast/normal/slow/non-moving/dead), incoming PO and in-transit transfer replenishment awareness, inventory turnover and excess stock valuation, and inter-store stock rebalancing recommendations.'
)
ON CONFLICT (migration_no) DO UPDATE SET
  schema_version = EXCLUDED.schema_version,
  release_name = EXCLUDED.release_name,
  notes = EXCLUDED.notes,
  applied_at = now();
