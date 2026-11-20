-- ============================================================================
-- Migration: 20261120150000_operations_intelligence_phase1_repairs.sql
-- Module: Operations Intelligence
-- Phase: Phase 1 — Database RPC Repairs & Core Metrics Foundation
--
-- Repairs:
-- 1. purchase_reorder_suggestions_v480:
--    - Fix ERROR 42703: column pv.tax_rate does not exist by joining public.products pr
--      and retrieving pr.tax_rate.
--    - Enforce cost permission check: mask last_unit_cost when unauthorized.
--    - Optimize last_buy subquery with location-scoping.
-- 2. inventory_intelligence_v480:
--    - Close legacy cost vulnerability by verifying inventory.view_cost / inventory.manage / owner.
--    - Redact average_cost and stock_value to 0 for unauthorized callers.
-- 3. inventory_intelligence_v830:
--    - Fix ERROR 42703: column p.location_id does not exist by querying document_origins.
--    - Eliminate Cartesian product (pv cross join l) by driving from active locations
--      and relevant variants (configured, stocked, sold, or purchased).
--    - Enforce location security and cost permission checks.
-- 4. operations_intelligence_summary_v830:
--    - Fix ERROR 42703: column "location_id" does not exist on public.sales by joining
--      document_origins.
--    - Enforce cost permission masking on profit and inventory metrics.
--    - Return complete metrics with backward-compatible attention fields.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. purchase_reorder_suggestions_v480
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purchase_reorder_suggestions_v480(
  p_tenant_id uuid,
  p_location_id uuid DEFAULT NULL::uuid,
  p_days integer DEFAULT 30,
  p_query text DEFAULT ''::text,
  p_limit integer DEFAULT 1000
)
RETURNS TABLE(
  location_id uuid,
  location_code text,
  location_name text,
  variant_id uuid,
  product_name text,
  sku text,
  current_stock numeric,
  reorder_level numeric,
  max_stock numeric,
  avg_daily_sales numeric,
  days_cover numeric,
  suggested_quantity numeric,
  last_supplier_id uuid,
  last_supplier_name text,
  last_unit_cost numeric,
  tax_rate numeric,
  last_purchase_date date
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $$
declare
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
  with intel as (
    select * from public.inventory_intelligence_v480(p_tenant_id, p_location_id, p_days, p_query, p_limit)
    where suggested_reorder > 0
  ),
  last_buy as (
    select distinct on(o.location_id, pi.variant_id)
      o.location_id,
      pi.variant_id,
      p.supplier_id,
      s.name as supplier_name,
      pi.unit_cost,
      p.purchase_date
    from public.purchase_items pi
    join public.purchases p on p.id = pi.purchase_id
    join public.suppliers s on s.id = p.supplier_id
    join public.document_origins o on o.tenant_id = p_tenant_id and o.entity_type = 'purchase' and o.entity_id = p.id
    where p.tenant_id = p_tenant_id
      and coalesce(p.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
    order by o.location_id, pi.variant_id, p.purchase_date desc, p.created_at desc
  )
  select
    i.location_id,
    i.location_code,
    i.location_name,
    i.variant_id,
    i.product_name,
    i.sku,
    i.available as current_stock,
    i.reorder_level,
    i.max_stock,
    i.avg_daily_sales,
    i.days_cover,
    i.suggested_reorder as suggested_quantity,
    lb.supplier_id as last_supplier_id,
    lb.supplier_name as last_supplier_name,
    case when v_can_view_cost then coalesce(lb.unit_cost, i.average_cost, 0)::numeric else 0::numeric end as last_unit_cost,
    coalesce(pr.tax_rate, 0)::numeric as tax_rate,
    lb.purchase_date as last_purchase_date
  from intel i
  join public.product_variants pv on pv.id = i.variant_id and pv.tenant_id = p_tenant_id
  join public.products pr on pr.id = pv.product_id and pr.tenant_id = p_tenant_id
  left join last_buy lb on lb.location_id = i.location_id and lb.variant_id = i.variant_id
  order by i.location_name, i.status, i.product_name;
end $$;

GRANT ALL ON FUNCTION public.purchase_reorder_suggestions_v480(uuid, uuid, integer, text, integer) TO authenticated;
GRANT ALL ON FUNCTION public.purchase_reorder_suggestions_v480(uuid, uuid, integer, text, integer) TO service_role;

-- ----------------------------------------------------------------------------
-- 2. inventory_intelligence_v480 (Legacy Cost Permission Hardening)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.inventory_intelligence_v480(
  p_tenant_id uuid,
  p_location_id uuid DEFAULT NULL::uuid,
  p_days integer DEFAULT 30,
  p_query text DEFAULT ''::text,
  p_limit integer DEFAULT 1000
)
RETURNS TABLE(
  location_id uuid,
  location_code text,
  location_name text,
  variant_id uuid,
  product_name text,
  sku text,
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
  status text
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
  with sold as (
    select o.location_id, si.variant_id,
      sum(greatest(si.quantity - coalesce((
        select sum(ri.quantity)
        from public.sales_return_items ri
        join public.sales_returns r on r.id = ri.sales_return_id
        where ri.sale_item_id = si.id and r.refund_status <> 'waived' and r.return_date <= current_date
      ), 0), 0))::numeric as qty
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
    select o.location_id, pi.variant_id, max(p.purchase_date) as last_purchase
    from public.purchase_items pi
    join public.purchases p on p.id = pi.purchase_id
    join public.document_origins o on o.tenant_id = p_tenant_id and o.entity_type = 'purchase' and o.entity_id = p.id
    where p.tenant_id = p_tenant_id
      and coalesce(p.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id, o.location_id, p_location_id, 'view')
    group by o.location_id, pi.variant_id
  ),
  base as (
    select
      l.id as location_id,
      l.location_code,
      l.name as location_name,
      pv.id as variant_id,
      p.name as product_name,
      pv.sku,
      coalesce(b.quantity, 0)::numeric as quantity,
      (coalesce(b.quantity, 0) - coalesce(b.reserved_quantity, 0) - coalesce(b.damaged_quantity, 0) - coalesce(b.quarantine_quantity, 0))::numeric as available,
      coalesce(s.reorder_level, pv.reorder_level, 0)::numeric as reorder_level,
      coalesce(s.max_stock, 0)::numeric as max_stock,
      case when v_can_view_cost then coalesce(b.average_cost, pv.cost_price, 0)::numeric else 0::numeric end as average_cost,
      coalesce(so.qty, 0)::numeric as net_sold_qty,
      ls.last_sale,
      pu.last_purchase
    from public.location_product_settings s
    join public.business_locations l on l.id = s.location_id and l.tenant_id = s.tenant_id and l.active
    join public.product_variants pv on pv.id = s.variant_id and pv.tenant_id = s.tenant_id
    join public.products p on p.id = pv.product_id and p.tenant_id = s.tenant_id
    left join public.location_stock_balances b on b.tenant_id = s.tenant_id and b.location_id = s.location_id and b.variant_id = s.variant_id
    left join sold so on so.location_id = s.location_id and so.variant_id = s.variant_id
    left join last_sold ls on ls.location_id = s.location_id and ls.variant_id = s.variant_id
    left join purchased pu on pu.location_id = s.location_id and pu.variant_id = s.variant_id
    where s.tenant_id = p_tenant_id
      and s.active
      and (p_location_id is null or s.location_id = p_location_id)
      and private.erp_document_scope_allowed(p_tenant_id, s.location_id, p_location_id, 'view')
      and (trim(coalesce(p_query, '')) = '' or lower(p.name) like q or lower(coalesce(pv.sku, '')) like q or lower(coalesce(pv.barcode, '')) like q or lower(coalesce(pv.part_number, '')) like q)
  )
  select
    b.location_id,
    b.location_code,
    b.location_name,
    b.variant_id,
    b.product_name,
    b.sku,
    b.quantity,
    b.available,
    b.reorder_level,
    b.max_stock,
    b.average_cost,
    case when v_can_view_cost then round(b.quantity * b.average_cost, 2)::numeric else 0::numeric end as stock_value,
    b.net_sold_qty,
    round(b.net_sold_qty / v_days, 4)::numeric as avg_daily_sales,
    case when b.net_sold_qty <= 0 then null else round(b.available / (b.net_sold_qty / v_days), 1) end::numeric as days_cover,
    greatest(
      case
        when b.max_stock > 0 and b.available <= b.reorder_level then b.max_stock - b.available
        when b.reorder_level > 0 and b.available <= b.reorder_level then greatest(b.reorder_level * 2 - b.available, 0)
        else 0
      end, 0
    )::numeric as suggested_reorder,
    b.last_sale as last_sale_date,
    b.last_purchase as last_purchase_date,
    (case
      when b.available <= 0 then 'out_of_stock'
      when b.reorder_level > 0 and b.available <= b.reorder_level then 'low_stock'
      when b.max_stock > 0 and b.available > b.max_stock then 'overstock'
      when b.net_sold_qty = 0 and b.available > 0 and coalesce(b.last_sale, date '1900-01-01') < current_date - interval '90 days' then 'dead_stock'
      else 'healthy'
    end)::text as status
  from base b
  order by
    case
      when b.available <= 0 then 1
      when b.reorder_level > 0 and b.available <= b.reorder_level then 2
      when b.net_sold_qty = 0 and b.available > 0 and coalesce(b.last_sale, date '1900-01-01') < current_date - interval '90 days' then 3
      when b.max_stock > 0 and b.available > b.max_stock then 4
      else 5
    end,
    b.net_sold_qty desc,
    b.product_name
  limit greatest(1, least(coalesce(p_limit, 1000), 5000));
end $$;

GRANT ALL ON FUNCTION public.inventory_intelligence_v480(uuid, uuid, integer, text, integer) TO authenticated;
GRANT ALL ON FUNCTION public.inventory_intelligence_v480(uuid, uuid, integer, text, integer) TO service_role;

-- ----------------------------------------------------------------------------
-- 3. inventory_intelligence_v830 (Origins Query & Targeted Location Scoping)
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
  abc_class text
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
    select o.location_id, si.variant_id,
      sum(greatest(si.quantity - coalesce((
        select sum(ri.quantity)
        from public.sales_return_items ri
        join public.sales_returns r on r.id = ri.sales_return_id
        where ri.sale_item_id = si.id and r.refund_status <> 'waived' and r.return_date <= current_date
      ), 0), 0))::numeric as qty
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
      (coalesce(b.quantity, 0) - coalesce(b.reserved_quantity, 0) - coalesce(b.damaged_quantity, 0) - coalesce(b.quarantine_quantity, 0))::numeric as available,
      coalesce(s.reorder_level, pv.reorder_level, 0)::numeric as reorder_level,
      coalesce(s.max_stock, 0)::numeric as max_stock,
      case when v_can_view_cost then coalesce(b.average_cost, pv.cost_price, 0)::numeric else 0::numeric end as average_cost,
      coalesce(so.qty, 0)::numeric as net_sold_qty,
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
    where (trim(coalesce(p_query, '')) = '' or lower(p.name) like q or lower(coalesce(pv.sku, '')) like q or lower(coalesce(pv.barcode, '')) like q or lower(coalesce(pv.part_number, '')) like q)
      and (coalesce(b.quantity, 0) > 0 or coalesce(so.qty, 0) > 0 or coalesce(s.reorder_level, pv.reorder_level, 0) > 0)
  ),
  ranked as (
    select b.*,
      case when v_can_view_cost then round(b.quantity * b.average_cost, 2)::numeric else 0::numeric end as stock_val,
      round(b.net_sold_qty / v_days, 4)::numeric as daily_sales,
      case when b.net_sold_qty <= 0 then null else round(b.available / (b.net_sold_qty / v_days), 1) end::numeric as cover_days,
      greatest(
        case
          when b.max_stock > 0 and b.available <= b.reorder_level then b.max_stock - b.available
          when b.reorder_level > 0 and b.available <= b.reorder_level then greatest(b.reorder_level * 2 - b.available, 0)
          else 0
        end, 0
      )::numeric as reorder_qty,
      case
        when b.available <= 0 then 'out_of_stock'
        when b.reorder_level > 0 and b.available <= b.reorder_level then 'low_stock'
        when b.max_stock > 0 and b.available > b.max_stock then 'overstock'
        when b.net_sold_qty = 0 and b.available > 0 and coalesce(b.last_sale, date '1900-01-01') < current_date - interval '90 days' then 'dead_stock'
        else 'healthy'
      end as stock_status,
      cume_dist() over (order by b.net_sold_qty desc) as sales_percentile
    from base b
  )
  select 
    r.location_id, r.location_code, r.location_name, r.variant_id, r.product_id,
    r.product_name, r.sku, r.barcode, r.quantity, r.available, r.reorder_level,
    r.max_stock, r.average_cost, r.stock_val as stock_value, r.net_sold_qty, r.daily_sales as avg_daily_sales,
    r.cover_days as days_cover, r.reorder_qty as suggested_reorder, r.last_sale as last_sale_date, r.last_purchase as last_purchase_date,
    r.stock_status::text as status,
    (case when r.sales_percentile <= 0.70 then 'A'
          when r.sales_percentile <= 0.90 then 'B'
          else 'C' end)::text as abc_class
  from ranked r
  order by
    case when r.stock_status = 'out_of_stock' then 1
         when r.stock_status = 'low_stock' then 2
         when r.stock_status = 'dead_stock' then 3
         when r.stock_status = 'overstock' then 4
         else 5 end,
    r.net_sold_qty desc,
    r.product_name
  limit greatest(1, least(coalesce(p_limit, 1000), 5000));
end $$;

GRANT ALL ON FUNCTION public.inventory_intelligence_v830(uuid, uuid, integer, text, integer) TO authenticated;
GRANT ALL ON FUNCTION public.inventory_intelligence_v830(uuid, uuid, integer, text, integer) TO service_role;

-- ----------------------------------------------------------------------------
-- 4. operations_intelligence_summary_v830 (Origins Sales Scoping & Metrics)
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
  v_sales numeric := 0;
  v_returns numeric := 0;
  v_cost numeric := 0;
  v_order_count bigint := 0;
  v_expenses numeric := 0;
  v_inventory_val numeric := 0;
  v_low_stock bigint := 0;
  v_out_of_stock bigint := 0;
  v_dead_stock bigint := 0;
  v_overstock bigint := 0;
  v_total_variants bigint := 0;
  v_receivable numeric := 0;
  v_overdue_recv numeric := 0;
  v_payable numeric := 0;
  v_overdue_pay numeric := 0;
  v_aov numeric := 0;
  v_unresolved_insights bigint := 0;
  v_critical_insights bigint := 0;
  v_pending_actions bigint := 0;
  v_pipeline jsonb := '{}'::jsonb;
  v_hourly jsonb := '[]'::jsonb;
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

  -- Sales & Revenue metrics (join document_origins for location mapping)
  select coalesce(sum(s.grand_total), 0), coalesce(sum(s.cost_total), 0), count(*)
    into v_sales, v_cost, v_order_count
  from public.sales s
  left join public.document_origins o on o.tenant_id = s.tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
  where s.tenant_id = p_tenant_id
    and s.sale_date between v_from and current_date
    and coalesce(s.status, '') not in ('void', 'cancelled')
    and (p_location_id is null or o.location_id = p_location_id);

  -- Sales returns
  select coalesce(sum(r.grand_total), 0)
    into v_returns
  from public.sales_returns r
  where r.tenant_id = p_tenant_id
    and r.return_date between v_from and current_date
    and r.refund_status <> 'waived'
    and (p_location_id is null or r.location_id = p_location_id);

  if v_order_count > 0 then
    v_aov := round((v_sales - v_returns) / v_order_count, 2);
  end if;

  -- Expenses
  select coalesce(sum(e.total_amount), 0)
    into v_expenses
  from public.expenses e
  left join public.document_origins o on o.tenant_id = e.tenant_id and o.entity_type = 'expense' and o.entity_id = e.id
  where e.tenant_id = p_tenant_id
    and e.expense_date between v_from and current_date
    and e.status = 'posted'
    and (p_location_id is null or o.location_id = p_location_id);

  -- Inventory health from v830 RPC
  select 
    count(*) filter (where status = 'low_stock'),
    count(*) filter (where status = 'out_of_stock'),
    count(*) filter (where status = 'dead_stock'),
    count(*) filter (where status = 'overstock'),
    count(*),
    coalesce(sum(stock_value), 0)
  into v_low_stock, v_out_of_stock, v_dead_stock, v_overstock, v_total_variants, v_inventory_val
  from public.inventory_intelligence_v830(p_tenant_id, p_location_id, v_days, '', 5000);

  -- Customer credit receivables
  select 
    coalesce(sum(total_outstanding), 0),
    coalesce(sum(days_1_30 + days_31_60 + days_61_90 + days_90_plus), 0)
  into v_receivable, v_overdue_recv
  from public.customer_credit_intelligence_v480(p_tenant_id, p_location_id, '', 5000);

  -- Supplier payables
  select 
    coalesce(sum(total_outstanding), 0),
    coalesce(sum(days_1_30 + days_31_60 + days_61_90 + days_90_plus), 0)
  into v_payable, v_overdue_pay
  from public.supplier_payables_intelligence_v480(p_tenant_id, p_location_id, '', 5000);

  -- Operations pipeline
  v_pipeline := coalesce(public.operations_pipeline_v489(p_tenant_id, p_location_id), '{}'::jsonb);

  -- Active insights counts
  select count(*), count(*) filter (where severity = 'critical')
    into v_unresolved_insights, v_critical_insights
  from public.erp_intelligence_insights
  where tenant_id = p_tenant_id
    and status in ('new_insight', 'acknowledged', 'in_progress')
    and (p_location_id is null or location_id is null or location_id = p_location_id);

  -- Pending actions count
  select count(*)
    into v_pending_actions
  from public.erp_intelligence_actions
  where tenant_id = p_tenant_id
    and status = 'pending_approval'
    and (p_location_id is null or location_id is null or location_id = p_location_id);

  -- Top 10 selling products (join document_origins for location mapping)
  select coalesce(jsonb_agg(to_jsonb(tp)), '[]'::jsonb)
  into v_top_products
  from (
    select pr.name as product_name, pv.sku, sum(si.quantity) as quantity_sold, round(sum(si.line_total), 2) as revenue
    from public.sale_items si
    join public.sales s on s.id = si.sale_id
    join public.product_variants pv on pv.id = si.variant_id
    join public.products pr on pr.id = pv.product_id
    left join public.document_origins o on o.tenant_id = s.tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
    where s.tenant_id = p_tenant_id
      and s.sale_date between v_from and current_date
      and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
    group by pr.name, pv.sku
    order by revenue desc
    limit 10
  ) tp;

  -- Hourly distribution (join document_origins for location mapping)
  select coalesce(jsonb_agg(to_jsonb(h)), '[]'::jsonb)
  into v_hourly
  from (
    select extract(hour from s.created_at)::int as hour, count(*) as count, round(sum(s.grand_total), 2) as revenue
    from public.sales s
    left join public.document_origins o on o.tenant_id = s.tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
    where s.tenant_id = p_tenant_id
      and s.sale_date between v_from and current_date
      and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
    group by 1
    order by 1
  ) h;

  return jsonb_build_object(
    'period_days', v_days,
    'from_date', v_from,
    'to_date', current_date,
    'gross_sales', round(v_sales, 2),
    'sales_returns', round(v_returns, 2),
    'net_sales', round(v_sales - v_returns, 2),
    'gross_profit', case when v_can_view_cost then round((v_sales - v_returns) - v_cost, 2) else 0 end,
    'gross_margin_pct', case when v_can_view_cost and (v_sales - v_returns) > 0 
      then round(((v_sales - v_returns) - v_cost) * 100 / (v_sales - v_returns), 2) else 0 end,
    'expenses', round(v_expenses, 2),
    'net_operating_profit', case when v_can_view_cost then round((v_sales - v_returns) - v_cost - v_expenses, 2) else 0 end,
    'order_count', v_order_count,
    'average_order_value', v_aov,
    'inventory_value', case when v_can_view_cost then round(v_inventory_val, 2) else 0 end,
    'total_monitored_variants', v_total_variants,
    'low_stock', v_low_stock,
    'low_stock_count', v_low_stock,
    'out_of_stock', v_out_of_stock,
    'out_of_stock_count', v_out_of_stock,
    'dead_stock', v_dead_stock,
    'dead_stock_count', v_dead_stock,
    'overstock', v_overstock,
    'overstock_count', v_overstock,
    'receivables', round(v_receivable, 2),
    'overdue_receivables', round(v_overdue_recv, 2),
    'payables', round(v_payable, 2),
    'overdue_payables', round(v_overdue_pay, 2),
    'unresolved_insights_count', v_unresolved_insights,
    'critical_insights_count', v_critical_insights,
    'pending_actions_count', v_pending_actions,
    'pipeline', v_pipeline,
    'top_products', v_top_products,
    'hourly_distribution', v_hourly
  ) || v_pipeline;
end $$;

GRANT ALL ON FUNCTION public.operations_intelligence_summary_v830(uuid, uuid, integer) TO authenticated;
GRANT ALL ON FUNCTION public.operations_intelligence_summary_v830(uuid, uuid, integer) TO service_role;

-- ----------------------------------------------------------------------------
-- 5. Record Schema Release
-- ----------------------------------------------------------------------------
INSERT INTO public.thq_schema_releases(migration_no, schema_version, release_name, notes)
VALUES (
  227,
  '8.3.1',
  'Operations Intelligence Phase 1 Repairs',
  'Repairs purchase_reorder_suggestions_v480 tax_rate, inventory_intelligence_v830 location join and Cartesian optimization, operations_intelligence_summary_v830 sales origin join, and inventory_intelligence_v480 cost permission vulnerability.'
)
ON CONFLICT (migration_no) DO UPDATE SET
  schema_version = EXCLUDED.schema_version,
  release_name = EXCLUDED.release_name,
  notes = EXCLUDED.notes,
  applied_at = now();
