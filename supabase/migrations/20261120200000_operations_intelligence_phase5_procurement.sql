-- ============================================================================
-- Migration: 20261120200000_operations_intelligence_phase5_procurement.sql
-- Module: Operations Intelligence Phase 5
-- Scope: Purchase Intelligence, Supplier Intelligence & Procurement Intelligence
-- Release: #230 / Schema Version 8.3.4
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Performance Indexes for Purchase & Supplier Analytics
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_purchases_tenant_date_v830
  ON public.purchases(tenant_id, purchase_date DESC)
  WHERE (coalesce(status, '') NOT IN ('void', 'cancelled'));

CREATE INDEX IF NOT EXISTS idx_purchase_items_tenant_variant_v830
  ON public.purchase_items(tenant_id, variant_id, purchase_id);

CREATE INDEX IF NOT EXISTS idx_purchase_invoices_v484_tenant_date_v830
  ON public.purchase_invoices_v484(tenant_id, invoice_date DESC)
  WHERE (status IN ('posted', 'part_paid', 'paid'));

CREATE INDEX IF NOT EXISTS idx_purchase_invoice_items_v484_variant_v830
  ON public.purchase_invoice_items_v484(variant_id, purchase_invoice_id);

CREATE INDEX IF NOT EXISTS idx_goods_receipts_v484_supplier_po_v830
  ON public.goods_receipts_v484(tenant_id, supplier_id, purchase_order_id, receipt_date DESC)
  WHERE (status = 'posted');

CREATE INDEX IF NOT EXISTS idx_goods_receipt_items_v484_grn_var_v830
  ON public.goods_receipt_items_v484(goods_receipt_id, variant_id);

CREATE INDEX IF NOT EXISTS idx_purchase_returns_tenant_date_v830
  ON public.purchase_returns(tenant_id, return_date DESC)
  WHERE (coalesce(credit_status, '') <> 'waived');

-- ----------------------------------------------------------------------------
-- 2. Purchase Intelligence: purchase_intelligence_v830
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purchase_intelligence_v830(
  p_tenant_id uuid,
  p_location_id uuid DEFAULT NULL::uuid,
  p_days integer DEFAULT 30,
  p_query text DEFAULT ''::text
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_from date := current_date - (v_days - 1);
  v_prev_to date := v_from - 1;
  v_prev_from date := v_prev_to - (v_days - 1);
  q text := '%' || lower(trim(coalesce(p_query, ''))) || '%';
  v_can_view_cost boolean := false;
  v_res jsonb;

  -- Current window metrics
  v_cur_gross numeric := 0;
  v_cur_returns numeric := 0;
  v_cur_net numeric := 0;
  v_cur_orders integer := 0;
  v_cur_units numeric := 0;
  v_cur_suppliers integer := 0;

  -- Previous window metrics
  v_prev_gross numeric := 0;
  v_prev_returns numeric := 0;
  v_prev_net numeric := 0;
  v_prev_orders integer := 0;
  v_prev_units numeric := 0;

  -- Growth metrics
  v_growth_net_pct numeric := 0;
  v_growth_orders_pct numeric := 0;
  v_growth_returns_pct numeric := 0;
  v_growth_units_pct numeric := 0;

  -- Structures
  v_daily_trends jsonb := '[]'::jsonb;
  v_weekly_trends jsonb := '[]'::jsonb;
  v_monthly_trends jsonb := '[]'::jsonb;
  v_by_supplier jsonb := '[]'::jsonb;
  v_by_category jsonb := '[]'::jsonb;
  v_by_product jsonb := '[]'::jsonb;
  v_price_changes jsonb := '[]'::jsonb;
  v_price_variance jsonb := '[]'::jsonb;
  v_po_performance jsonb := '{}'::jsonb;
  v_concentration jsonb := '{}'::jsonb;
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

  -- 1. Unified Purchase Lines CTE
  -- Covers both direct purchases and purchase invoices
  with purchases_raw as (
    -- Direct purchases
    select
      p.id as doc_id,
      'direct_purchase' as doc_type,
      p.purchase_number as doc_number,
      p.purchase_date as doc_date,
      o.location_id,
      p.supplier_id,
      p.supplier_name,
      pi.variant_id,
      pv.sku,
      pr.name as product_name,
      coalesce(c.name, 'Uncategorized') as category_name,
      coalesce(pi.entered_quantity, pi.quantity, 0)::numeric as quantity,
      coalesce(pi.entered_unit_cost, pi.unit_cost, 0)::numeric as unit_cost,
      coalesce(pi.line_total, 0)::numeric as line_total
    from public.purchases p
    join public.purchase_items pi on pi.purchase_id = p.id
    join public.product_variants pv on pv.id = pi.variant_id
    join public.products pr on pr.id = pv.product_id
    left join public.product_categories c on c.id = pr.category_id
    left join public.document_origins o on o.entity_type = 'purchase' and o.entity_id = p.id and o.tenant_id = p.tenant_id
    where p.tenant_id = p_tenant_id
      and coalesce(p.status, '') not in ('void', 'cancelled')
      and p.purchase_date between v_prev_from and current_date
      and (p_location_id is null or o.location_id = p_location_id)
      and (o.location_id is null or private.erp_document_scope_allowed(p_tenant_id, o.location_id, p_location_id, 'view'))
    union all
    -- Authoritative GST purchase invoices
    select
      ih.id as doc_id,
      'purchase_invoice' as doc_type,
      ih.invoice_number as doc_number,
      ih.invoice_date as doc_date,
      ih.location_id,
      ih.supplier_id,
      s.name as supplier_name,
      ii.variant_id,
      pv.sku,
      pr.name as product_name,
      coalesce(c.name, 'Uncategorized') as category_name,
      coalesce(ii.quantity, 0)::numeric as quantity,
      coalesce(ii.unit_cost, 0)::numeric as unit_cost,
      coalesce(ii.line_total, 0)::numeric as line_total
    from public.purchase_invoices_v484 ih
    join public.purchase_invoice_items_v484 ii on ii.purchase_invoice_id = ih.id
    join public.product_variants pv on pv.id = ii.variant_id
    join public.products pr on pr.id = pv.product_id
    left join public.product_categories c on c.id = pr.category_id
    join public.suppliers s on s.id = ih.supplier_id
    where ih.tenant_id = p_tenant_id
      and ih.status in ('posted', 'part_paid', 'paid')
      and ih.invoice_date between v_prev_from and current_date
      and (p_location_id is null or ih.location_id = p_location_id)
      and (ih.location_id is null or private.erp_document_scope_allowed(p_tenant_id, ih.location_id, p_location_id, 'view'))
  ),
  returns_raw as (
    select
      r.id,
      r.return_date,
      r.location_id,
      p.supplier_id,
      coalesce(r.grand_total, 0)::numeric as grand_total
    from public.purchase_returns r
    join public.purchases p on p.id = r.purchase_id
    where r.tenant_id = p_tenant_id
      and r.return_date between v_prev_from and current_date
      and coalesce(r.credit_status, '') <> 'waived'
      and (p_location_id is null or r.location_id = p_location_id)
      and (r.location_id is null or private.erp_document_scope_allowed(p_tenant_id, r.location_id, p_location_id, 'view'))
  )
  select
    -- Current period sums
    coalesce(sum(case when doc_date >= v_from then line_total else 0 end), 0),
    coalesce(count(distinct case when doc_date >= v_from then doc_id else null end), 0),
    coalesce(sum(case when doc_date >= v_from then quantity else 0 end), 0),
    coalesce(count(distinct case when doc_date >= v_from then supplier_id else null end), 0),
    -- Previous period sums
    coalesce(sum(case when doc_date < v_from then line_total else 0 end), 0),
    coalesce(count(distinct case when doc_date < v_from then doc_id else null end), 0),
    coalesce(sum(case when doc_date < v_from then quantity else 0 end), 0)
  into
    v_cur_gross, v_cur_orders, v_cur_units, v_cur_suppliers,
    v_prev_gross, v_prev_orders, v_prev_units
  from purchases_raw;

  -- Purchase returns calculation
  select
    coalesce(sum(case when return_date >= v_from then grand_total else 0 end), 0),
    coalesce(sum(case when return_date < v_from then grand_total else 0 end), 0)
  into v_cur_returns, v_prev_returns
  from public.purchase_returns r
  where r.tenant_id = p_tenant_id
    and r.return_date between v_prev_from and current_date
    and coalesce(r.credit_status, '') <> 'waived'
    and (p_location_id is null or r.location_id = p_location_id);

  v_cur_net := greatest(v_cur_gross - v_cur_returns, 0);
  v_prev_net := greatest(v_prev_gross - v_prev_returns, 0);

  -- Percentage growth metrics
  v_growth_net_pct := case when v_prev_net > 0 then round(((v_cur_net - v_prev_net) * 100.0) / v_prev_net, 2) else 0 end;
  v_growth_orders_pct := case when v_prev_orders > 0 then round(((v_cur_orders - v_prev_orders) * 100.0) / v_prev_orders, 2) else 0 end;
  v_growth_returns_pct := case when v_prev_returns > 0 then round(((v_cur_returns - v_prev_returns) * 100.0) / v_prev_returns, 2) else 0 end;
  v_growth_units_pct := case when v_prev_units > 0 then round(((v_cur_units - v_prev_units) * 100.0) / v_prev_units, 2) else 0 end;

  -- 2. Daily Trends
  select coalesce(jsonb_agg(to_jsonb(t) order by t.day_date), '[]'::jsonb)
  into v_daily_trends
  from (
    select
      d::date as day_date,
      to_char(d, 'Dy, Mon DD') as label,
      coalesce(sum(p.line_total), 0)::numeric as gross_purchases,
      coalesce(sum(r.grand_total), 0)::numeric as returns,
      greatest(coalesce(sum(p.line_total), 0) - coalesce(sum(r.grand_total), 0), 0)::numeric as net_purchases,
      count(distinct p.doc_id)::integer as order_count
    from generate_series(v_from::timestamp, current_date::timestamp, '1 day'::interval) d
    left join (
      select doc_id, doc_date, line_total from (
        select p.id as doc_id, p.purchase_date as doc_date, pi.line_total
        from public.purchases p
        join public.purchase_items pi on pi.purchase_id = p.id
        left join public.document_origins o on o.entity_type = 'purchase' and o.entity_id = p.id and o.tenant_id = p.tenant_id
        where p.tenant_id = p_tenant_id and coalesce(p.status, '') not in ('void', 'cancelled')
          and p.purchase_date between v_from and current_date
          and (p_location_id is null or o.location_id = p_location_id)
        union all
        select ih.id as doc_id, ih.invoice_date as doc_date, ii.line_total
        from public.purchase_invoices_v484 ih
        join public.purchase_invoice_items_v484 ii on ii.purchase_invoice_id = ih.id
        where ih.tenant_id = p_tenant_id and ih.status in ('posted', 'part_paid', 'paid')
          and ih.invoice_date between v_from and current_date
          and (p_location_id is null or ih.location_id = p_location_id)
      ) u
    ) p on p.doc_date = d::date
    left join (
      select return_date, grand_total from public.purchase_returns
      where tenant_id = p_tenant_id and return_date between v_from and current_date
        and coalesce(credit_status, '') <> 'waived'
        and (p_location_id is null or location_id = p_location_id)
    ) r on r.return_date = d::date
    group by d::date, to_char(d, 'Dy, Mon DD')
  ) t;

  -- 3. Top Suppliers by Spend in Current Window
  select coalesce(jsonb_agg(to_jsonb(s) order by s.spend desc), '[]'::jsonb)
  into v_by_supplier
  from (
    select
      sup.supplier_id,
      sup.supplier_name,
      round(sum(sup.line_total), 2)::numeric as spend,
      count(distinct sup.doc_id)::integer as po_count,
      case when v_cur_gross > 0 then round((sum(sup.line_total) * 100.0) / v_cur_gross, 2) else 0 end::numeric as share_pct
    from (
      select p.supplier_id, p.supplier_name, p.id as doc_id, pi.line_total
      from public.purchases p
      join public.purchase_items pi on pi.purchase_id = p.id
      left join public.document_origins o on o.entity_type = 'purchase' and o.entity_id = p.id and o.tenant_id = p.tenant_id
      where p.tenant_id = p_tenant_id and coalesce(p.status, '') not in ('void', 'cancelled')
        and p.purchase_date between v_from and current_date
        and (p_location_id is null or o.location_id = p_location_id)
      union all
      select ih.supplier_id, s.name as supplier_name, ih.id as doc_id, ii.line_total
      from public.purchase_invoices_v484 ih
      join public.purchase_invoice_items_v484 ii on ii.purchase_invoice_id = ih.id
      join public.suppliers s on s.id = ih.supplier_id
      where ih.tenant_id = p_tenant_id and ih.status in ('posted', 'part_paid', 'paid')
        and ih.invoice_date between v_from and current_date
        and (p_location_id is null or ih.location_id = p_location_id)
    ) sup
    group by sup.supplier_id, sup.supplier_name
    order by spend desc
    limit 10
  ) s;

  -- Purchase concentration (Top 3 suppliers share)
  select jsonb_build_object(
    'top3_spend', coalesce(sum(s.spend), 0),
    'top3_share_pct', case when v_cur_gross > 0 then round((coalesce(sum(s.spend), 0) * 100.0) / v_cur_gross, 2) else 0 end,
    'dependency_level', case 
      when v_cur_gross > 0 and (sum(s.spend) * 100.0 / v_cur_gross) >= 70 then 'high_concentration'
      when v_cur_gross > 0 and (sum(s.spend) * 100.0 / v_cur_gross) >= 45 then 'moderate_concentration'
      else 'diversified'
    end
  )
  into v_concentration
  from (
    select (value->>'spend')::numeric as spend
    from jsonb_array_elements(v_by_supplier)
    limit 3
  ) s;

  -- 4. Category Breakdown
  select coalesce(jsonb_agg(to_jsonb(c) order by c.spend desc), '[]'::jsonb)
  into v_by_category
  from (
    select
      cat.category_name,
      round(sum(cat.line_total), 2)::numeric as spend,
      round(sum(cat.quantity), 2)::numeric as units,
      case when v_cur_gross > 0 then round((sum(cat.line_total) * 100.0) / v_cur_gross, 2) else 0 end::numeric as share_pct
    from (
      select coalesce(c.name, 'Uncategorized') as category_name, pi.line_total, coalesce(pi.entered_quantity, pi.quantity, 0) as quantity
      from public.purchases p
      join public.purchase_items pi on pi.purchase_id = p.id
      join public.product_variants pv on pv.id = pi.variant_id
      join public.products pr on pr.id = pv.product_id
      left join public.product_categories c on c.id = pr.category_id
      left join public.document_origins o on o.entity_type = 'purchase' and o.entity_id = p.id and o.tenant_id = p.tenant_id
      where p.tenant_id = p_tenant_id and coalesce(p.status, '') not in ('void', 'cancelled')
        and p.purchase_date between v_from and current_date
        and (p_location_id is null or o.location_id = p_location_id)
      union all
      select coalesce(c.name, 'Uncategorized') as category_name, ii.line_total, coalesce(ii.quantity, 0) as quantity
      from public.purchase_invoices_v484 ih
      join public.purchase_invoice_items_v484 ii on ii.purchase_invoice_id = ih.id
      join public.product_variants pv on pv.id = ii.variant_id
      join public.products pr on pr.id = pv.product_id
      left join public.product_categories c on c.id = pr.category_id
      where ih.tenant_id = p_tenant_id and ih.status in ('posted', 'part_paid', 'paid')
        and ih.invoice_date between v_from and current_date
        and (p_location_id is null or ih.location_id = p_location_id)
    ) cat
    group by cat.category_name
    order by spend desc
    limit 10
  ) c;

  -- 5. Top Purchased Products
  select coalesce(jsonb_agg(to_jsonb(p) order by p.total_spend desc), '[]'::jsonb)
  into v_by_product
  from (
    select
      prod.variant_id,
      prod.product_name,
      prod.sku,
      prod.category_name,
      round(sum(prod.quantity), 2)::numeric as units,
      round(sum(prod.line_total), 2)::numeric as total_spend,
      case when sum(prod.quantity) > 0 then round(sum(prod.line_total) / sum(prod.quantity), 2) else 0 end::numeric as avg_unit_cost,
      max(prod.unit_cost)::numeric as latest_price
    from (
      select pi.variant_id, pr.name as product_name, pv.sku, coalesce(c.name, 'General') as category_name,
             coalesce(pi.entered_quantity, pi.quantity, 0) as quantity, pi.line_total, coalesce(pi.entered_unit_cost, pi.unit_cost, 0) as unit_cost
      from public.purchases p
      join public.purchase_items pi on pi.purchase_id = p.id
      join public.product_variants pv on pv.id = pi.variant_id
      join public.products pr on pr.id = pv.product_id
      left join public.product_categories c on c.id = pr.category_id
      left join public.document_origins o on o.entity_type = 'purchase' and o.entity_id = p.id and o.tenant_id = p.tenant_id
      where p.tenant_id = p_tenant_id and coalesce(p.status, '') not in ('void', 'cancelled')
        and p.purchase_date between v_from and current_date
        and (p_location_id is null or o.location_id = p_location_id)
      union all
      select ii.variant_id, pr.name as product_name, pv.sku, coalesce(c.name, 'General') as category_name,
             coalesce(ii.quantity, 0) as quantity, ii.line_total, coalesce(ii.unit_cost, 0) as unit_cost
      from public.purchase_invoices_v484 ih
      join public.purchase_invoice_items_v484 ii on ii.purchase_invoice_id = ih.id
      join public.product_variants pv on pv.id = ii.variant_id
      join public.products pr on pr.id = pv.product_id
      left join public.product_categories c on c.id = pr.category_id
      where ih.tenant_id = p_tenant_id and ih.status in ('posted', 'part_paid', 'paid')
        and ih.invoice_date between v_from and current_date
        and (p_location_id is null or ih.location_id = p_location_id)
    ) prod
    group by prod.variant_id, prod.product_name, prod.sku, prod.category_name
    order by total_spend desc
    limit 15
  ) p;

  -- 6. Price Intelligence: Notable Price Changes
  select coalesce(jsonb_agg(to_jsonb(pc) order by abs(pc.price_change_pct) desc), '[]'::jsonb)
  into v_price_changes
  from (
    select
      cur.variant_id,
      cur.product_name,
      cur.sku,
      cur.avg_cost as latest_price,
      prev.avg_cost as previous_price,
      round(((cur.avg_cost - prev.avg_cost) * 100.0) / prev.avg_cost, 2)::numeric as price_change_pct,
      (cur.avg_cost > prev.avg_cost) as is_increase
    from (
      select pi.variant_id, pr.name as product_name, pv.sku, round(sum(pi.line_total) / nullif(sum(pi.quantity), 0), 2) as avg_cost
      from public.purchases p
      join public.purchase_items pi on pi.purchase_id = p.id
      join public.product_variants pv on pv.id = pi.variant_id
      join public.products pr on pr.id = pv.product_id
      where p.tenant_id = p_tenant_id and coalesce(p.status, '') not in ('void', 'cancelled')
        and p.purchase_date between v_from and current_date
      group by pi.variant_id, pr.name, pv.sku
      having sum(pi.quantity) > 0
    ) cur
    join (
      select pi.variant_id, round(sum(pi.line_total) / nullif(sum(pi.quantity), 0), 2) as avg_cost
      from public.purchases p
      join public.purchase_items pi on pi.purchase_id = p.id
      where p.tenant_id = p_tenant_id and coalesce(p.status, '') not in ('void', 'cancelled')
        and p.purchase_date between v_prev_from and v_prev_to
      group by pi.variant_id
      having sum(pi.quantity) > 0
    ) prev on prev.variant_id = cur.variant_id
    where abs(((cur.avg_cost - prev.avg_cost) * 100.0) / prev.avg_cost) >= 2.0
    limit 10
  ) pc;

  -- 7. Purchase Order Fulfilment & Performance
  select jsonb_build_object(
    'total_orders', count(*),
    'draft_count', count(*) filter (where po.status = 'draft'),
    'submitted_count', count(*) filter (where po.status = 'submitted'),
    'approved_count', count(*) filter (where po.status = 'approved'),
    'ordered_count', count(*) filter (where po.status = 'ordered'),
    'partially_received_count', count(*) filter (where po.status = 'partially_received'),
    'received_count', count(*) filter (where po.status = 'received'),
    'cancelled_count', count(*) filter (where po.status = 'cancelled'),
    'delayed_orders_count', count(*) filter (where po.expected_date is not null and po.expected_date < current_date and po.status in ('approved', 'ordered', 'partially_received')),
    'total_ordered_qty', coalesce(sum(poi.quantity), 0),
    'total_received_qty', coalesce(sum(poi.received_quantity), 0),
    'fulfillment_rate_pct', case when coalesce(sum(poi.quantity), 0) > 0 then round((sum(poi.received_quantity) * 100.0) / sum(poi.quantity), 1) else 100.0 end,
    'total_po_value', case when v_can_view_cost then coalesce(sum(po.grand_total), 0) else 0 end,
    'avg_lead_time_days', coalesce((
      select round(avg(g.receipt_date - po2.order_date), 1)
      from public.goods_receipts_v484 g
      join public.purchase_orders_v480 po2 on po2.id = g.purchase_order_id
      where g.tenant_id = p_tenant_id and g.status = 'posted'
        and (p_location_id is null or g.location_id = p_location_id)
    ), 0.0)
  )
  into v_po_performance
  from public.purchase_orders_v480 po
  left join public.purchase_order_items_v480 poi on poi.purchase_order_id = po.id
  where po.tenant_id = p_tenant_id
    and po.order_date between v_from and current_date
    and (p_location_id is null or po.location_id = p_location_id);

  -- Assemble final JSON result
  v_res := jsonb_build_object(
    'tenant_id', p_tenant_id,
    'location_id', p_location_id,
    'days', v_days,
    'from_date', v_from,
    'to_date', current_date,
    'prev_from_date', v_prev_from,
    'prev_to_date', v_prev_to,
    'can_view_cost', v_can_view_cost,
    'summary', jsonb_build_object(
      'current', jsonb_build_object(
        'gross_purchases', case when v_can_view_cost then v_cur_gross else 0 end,
        'purchase_returns', case when v_can_view_cost then v_cur_returns else 0 end,
        'net_purchases', case when v_can_view_cost then v_cur_net else 0 end,
        'order_count', v_cur_orders,
        'average_order_value', case when v_can_view_cost and v_cur_orders > 0 then round(v_cur_net / v_cur_orders, 2) else 0 end,
        'units_purchased', v_cur_units,
        'active_suppliers_count', v_cur_suppliers
      ),
      'previous', jsonb_build_object(
        'gross_purchases', case when v_can_view_cost then v_prev_gross else 0 end,
        'purchase_returns', case when v_can_view_cost then v_prev_returns else 0 end,
        'net_purchases', case when v_can_view_cost then v_prev_net else 0 end,
        'order_count', v_prev_orders,
        'average_order_value', case when v_can_view_cost and v_prev_orders > 0 then round(v_prev_net / v_prev_orders, 2) else 0 end,
        'units_purchased', v_prev_units
      ),
      'growth', jsonb_build_object(
        'net_purchases_pct', v_growth_net_pct,
        'order_count_pct', v_growth_orders_pct,
        'returns_pct', v_growth_returns_pct,
        'units_purchased_pct', v_growth_units_pct
      ),
      'concentration', v_concentration
    ),
    'trends', jsonb_build_object(
      'daily', v_daily_trends
    ),
    'by_supplier', v_by_supplier,
    'by_category', v_by_category,
    'by_product', v_by_product,
    'price_changes', v_price_changes,
    'po_performance', v_po_performance
  );

  return v_res;
end $$;

GRANT ALL ON FUNCTION public.purchase_intelligence_v830(uuid, uuid, integer, text) TO authenticated;
GRANT ALL ON FUNCTION public.purchase_intelligence_v830(uuid, uuid, integer, text) TO service_role;

-- ----------------------------------------------------------------------------
-- 3. Supplier Intelligence: supplier_intelligence_v830
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.supplier_intelligence_v830(
  p_tenant_id uuid,
  p_location_id uuid DEFAULT NULL::uuid,
  p_days integer DEFAULT 30,
  p_query text DEFAULT ''::text,
  p_limit integer DEFAULT 200
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_from date := current_date - (v_days - 1);
  q text := '%' || lower(trim(coalesce(p_query, ''))) || '%';
  v_can_view_cost boolean := false;
  v_total_spend numeric := 0;
  v_total_suppliers integer := 0;
  v_active_suppliers integer := 0;
  v_high_risk_count integer := 0;
  v_total_debt numeric := 0;
  v_suppliers_list jsonb := '[]'::jsonb;
  v_res jsonb;
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

  -- Total active suppliers count in tenant
  select count(*) into v_total_suppliers
  from public.suppliers s
  where s.tenant_id = p_tenant_id and coalesce(s.status, 'active') = 'active';

  -- Total spend in period across tenant/location
  select coalesce(sum(p.grand_total), 0) into v_total_spend
  from public.purchases p
  left join public.document_origins o on o.entity_type = 'purchase' and o.entity_id = p.id and o.tenant_id = p.tenant_id
  where p.tenant_id = p_tenant_id and coalesce(p.status, '') not in ('void', 'cancelled')
    and p.purchase_date between v_from and current_date
    and (p_location_id is null or o.location_id = p_location_id);

  -- Assemble comprehensive supplier profiles CTE
  with supplier_purchases as (
    select
      p.supplier_id,
      count(distinct p.id) as order_count,
      coalesce(sum(p.grand_total), 0)::numeric as spend,
      count(distinct pi.variant_id) as product_coverage,
      max(p.purchase_date) as last_order_date
    from public.purchases p
    join public.purchase_items pi on pi.purchase_id = p.id
    left join public.document_origins o on o.entity_type = 'purchase' and o.entity_id = p.id and o.tenant_id = p.tenant_id
    where p.tenant_id = p_tenant_id and coalesce(p.status, '') not in ('void', 'cancelled')
      and p.purchase_date between v_from and current_date
      and (p_location_id is null or o.location_id = p_location_id)
    group by p.supplier_id
  ),
  supplier_orders as (
    select
      po.supplier_id,
      count(distinct po.id) as po_count,
      coalesce(sum(poi.quantity), 0)::numeric as ordered_qty,
      coalesce(sum(poi.received_quantity), 0)::numeric as received_qty
    from public.purchase_orders_v480 po
    left join public.purchase_order_items_v480 poi on poi.purchase_order_id = po.id
    where po.tenant_id = p_tenant_id and po.status <> 'cancelled'
      and po.order_date between v_from and current_date
      and (p_location_id is null or po.location_id = p_location_id)
    group by po.supplier_id
  ),
  supplier_grns as (
    select
      g.supplier_id,
      count(distinct g.id) as grn_count,
      coalesce(sum(gri.accepted_quantity), 0)::numeric as accepted_qty,
      coalesce(sum(gri.damaged_quantity), 0)::numeric as damaged_qty,
      coalesce(sum(gri.rejected_quantity), 0)::numeric as rejected_qty,
      coalesce(round(avg(g.receipt_date - po.order_date), 1), 0)::numeric as avg_lead_days,
      round(avg(case when po.expected_date is null or g.receipt_date <= po.expected_date then 100.0 else 0.0 end), 1)::numeric as on_time_pct
    from public.goods_receipts_v484 g
    join public.goods_receipt_items_v484 gri on gri.goods_receipt_id = g.id
    join public.purchase_orders_v480 po on po.id = g.purchase_order_id
    where g.tenant_id = p_tenant_id and g.status = 'posted'
      and g.receipt_date between v_from and current_date
      and (p_location_id is null or g.location_id = p_location_id)
    group by g.supplier_id
  ),
  supplier_returns as (
    select
      p.supplier_id,
      coalesce(sum(r.grand_total), 0)::numeric as return_amt
    from public.purchase_returns r
    join public.purchases p on p.id = r.purchase_id
    where r.tenant_id = p_tenant_id and r.return_date between v_from and current_date
      and coalesce(r.credit_status, '') <> 'waived'
      and (p_location_id is null or r.location_id = p_location_id)
    group by p.supplier_id
  ),
  supplier_debts as (
    select
      p.supplier_id,
      coalesce(sum(p.total_outstanding), 0)::numeric as total_outstanding,
      coalesce(sum(p.current_amount), 0)::numeric as current_debt,
      coalesce(sum(p.days_1_30), 0)::numeric as days_1_30,
      coalesce(sum(p.days_31_60), 0)::numeric as days_31_60,
      coalesce(sum(p.days_61_90), 0)::numeric as days_61_90,
      coalesce(sum(p.days_90_plus), 0)::numeric as days_90_plus,
      max(p.status) as aging_status
    from public.supplier_payables_intelligence_v480(p_tenant_id, p_location_id, '', 1000) p
    group by p.supplier_id
  ),
  compiled_suppliers as (
    select
      s.id as supplier_id,
      s.name as supplier_name,
      coalesce(s.phone, '') as phone,
      coalesce(s.email, '') as email,
      coalesce(sp.spend, 0)::numeric as spend,
      coalesce(sp.order_count, so.po_count, 0)::integer as order_count,
      case when v_total_spend > 0 then round((coalesce(sp.spend, 0) * 100.0) / v_total_spend, 2) else 0 end::numeric as share_pct,
      coalesce(sp.product_coverage, 0)::integer as product_coverage_count,
      coalesce(gr.avg_lead_days, 0)::numeric as avg_lead_time_days,
      case 
        when coalesce(so.ordered_qty, 0) > 0 then round((coalesce(gr.accepted_qty, so.received_qty, 0) * 100.0) / so.ordered_qty, 1)
        when coalesce(sp.order_count, 0) > 0 then 100.0
        else 0.0
      end::numeric as fulfillment_rate_pct,
      coalesce(gr.on_time_pct, 100.0)::numeric as on_time_delivery_pct,
      case 
        when (coalesce(gr.accepted_qty, 0) + coalesce(gr.damaged_qty, 0) + coalesce(gr.rejected_qty, 0)) > 0 
        then round(((coalesce(gr.damaged_qty, 0) + coalesce(gr.rejected_qty, 0)) * 100.0) / (gr.accepted_qty + gr.damaged_qty + gr.rejected_qty), 1)
        else 0.0
      end::numeric as damaged_rejected_pct,
      case 
        when coalesce(sp.spend, 0) > 0 then round((coalesce(sr.return_amt, 0) * 100.0) / sp.spend, 1)
        else 0.0
      end::numeric as return_rate_pct,
      coalesce(sd.total_outstanding, 0)::numeric as outstanding_payable,
      coalesce(sd.days_90_plus, 0)::numeric as debt_90_plus,
      coalesce(sd.aging_status, 'clear')::text as aging_status,
      sp.last_order_date,
      case when (coalesce(sp.order_count, 0) + coalesce(so.po_count, 0)) >= 2 then 'sufficient' else 'insufficient_history' end as data_sufficiency
    from public.suppliers s
    left join supplier_purchases sp on sp.supplier_id = s.id
    left join supplier_orders so on so.supplier_id = s.id
    left join supplier_grns gr on gr.supplier_id = s.id
    left join supplier_returns sr on sr.supplier_id = s.id
    left join supplier_debts sd on sd.supplier_id = s.id
    where s.tenant_id = p_tenant_id and coalesce(s.status, 'active') = 'active'
      and (trim(coalesce(p_query, '')) = '' or lower(s.name) like q or lower(coalesce(s.phone, '')) like q)
  )
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'supplier_id', cs.supplier_id,
        'supplier_name', cs.supplier_name,
        'phone', cs.phone,
        'email', cs.email,
        'spend', case when v_can_view_cost then cs.spend else 0 end,
        'order_count', cs.order_count,
        'share_pct', cs.share_pct,
        'product_coverage_count', cs.product_coverage_count,
        'avg_lead_time_days', cs.avg_lead_time_days,
        'fulfillment_rate_pct', cs.fulfillment_rate_pct,
        'on_time_delivery_pct', cs.on_time_delivery_pct,
        'damaged_rejected_pct', cs.damaged_rejected_pct,
        'return_rate_pct', cs.return_rate_pct,
        'outstanding_payable', cs.outstanding_payable,
        'aging_status', cs.aging_status,
        'last_order_date', cs.last_order_date,
        'data_sufficiency', cs.data_sufficiency,
        'risk_score', case
          when cs.debt_90_plus > 0 or (cs.on_time_delivery_pct < 65 and cs.order_count >= 2) or cs.damaged_rejected_pct > 8 then 'high'
          when cs.share_pct >= 40 or cs.return_rate_pct > 5 or cs.on_time_delivery_pct < 80 then 'medium'
          else 'low'
        end,
        'risk_indicators', array_remove(array[
          case when cs.debt_90_plus > 0 then 'Critical overdue payables (>90 days)' else null end,
          case when cs.on_time_delivery_pct < 70 and cs.order_count >= 2 then 'Frequent delivery delays (<70% on-time)' else null end,
          case when cs.damaged_rejected_pct > 5 then 'High damaged / rejected rate (>5%)' else null end,
          case when cs.share_pct >= 40 and v_total_spend > 10000 then 'High purchase dependency (>40% of spend)' else null end,
          case when cs.return_rate_pct > 5 then 'Elevated purchase return rate (>5%)' else null end
        ], null)
      )
      order by cs.spend desc, cs.supplier_name
    ), '[]'::jsonb),
    count(*) filter (where cs.spend > 0),
    count(*) filter (where cs.debt_90_plus > 0 or (cs.on_time_delivery_pct < 65 and cs.order_count >= 2) or cs.damaged_rejected_pct > 8),
    coalesce(sum(cs.outstanding_payable), 0)
  into v_suppliers_list, v_active_suppliers, v_high_risk_count, v_total_debt
  from compiled_suppliers cs;

  v_res := jsonb_build_object(
    'tenant_id', p_tenant_id,
    'location_id', p_location_id,
    'days', v_days,
    'from_date', v_from,
    'to_date', current_date,
    'can_view_cost', v_can_view_cost,
    'summary', jsonb_build_object(
      'total_suppliers_count', v_total_suppliers,
      'active_suppliers_count', v_active_suppliers,
      'total_spend', case when v_can_view_cost then v_total_spend else 0 end,
      'total_outstanding_payable', v_total_debt,
      'high_risk_suppliers_count', v_high_risk_count,
      'avg_fulfillment_rate', coalesce((
        select round(avg((elem->>'fulfillment_rate_pct')::numeric), 1)
        from jsonb_array_elements(v_suppliers_list) elem
        where (elem->>'order_count')::int > 0
      ), 100.0),
      'avg_lead_time_days', coalesce((
        select round(avg((elem->>'avg_lead_time_days')::numeric), 1)
        from jsonb_array_elements(v_suppliers_list) elem
        where (elem->>'avg_lead_time_days')::numeric > 0
      ), 0.0)
    ),
    'suppliers', v_suppliers_list
  );

  return v_res;
end $$;

GRANT ALL ON FUNCTION public.supplier_intelligence_v830(uuid, uuid, integer, text, integer) TO authenticated;
GRANT ALL ON FUNCTION public.supplier_intelligence_v830(uuid, uuid, integer, text, integer) TO service_role;

-- ----------------------------------------------------------------------------
-- 4. Procurement Intelligence: procurement_intelligence_v830
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.procurement_intelligence_v830(
  p_tenant_id uuid,
  p_location_id uuid DEFAULT NULL::uuid,
  p_days integer DEFAULT 30,
  p_query text DEFAULT ''::text,
  p_limit integer DEFAULT 500
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'private', 'pg_temp'
AS $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  q text := '%' || lower(trim(coalesce(p_query, ''))) || '%';
  v_can_view_cost boolean := false;
  v_recommendations jsonb := '[]'::jsonb;
  v_res jsonb;

  -- Summary counters
  v_total_rec_count integer := 0;
  v_critical_count integer := 0;
  v_high_count integer := 0;
  v_normal_count integer := 0;
  v_covered_count integer := 0;
  v_rebalance_alt_count integer := 0;
  v_estimated_cost_total numeric := 0;
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

  -- Base stock intelligence from inventory_intelligence_v830
  with stock_base as (
    select * from public.inventory_intelligence_v830(p_tenant_id, p_location_id, v_days, p_query, p_limit)
  ),
  -- Identify physical stock candidates needing attention or replenishment
  candidates as (
    select sb.* 
    from stock_base sb
    join public.products pr on pr.id = sb.product_id
    where coalesce(pr.item_type, 'stock') = 'stock'
      and (
        sb.suggested_reorder > 0
        or (sb.reorder_level > 0 and sb.net_effective_stock < sb.reorder_level)
        or (sb.avg_daily_sales > 0 and sb.available <= 0)
        or (sb.status in ('out_of_stock', 'critical_low', 'low_stock') and (sb.reorder_level > 0 or sb.avg_daily_sales > 0))
      )
  ),
  -- Inter-store rebalancing possibilities for candidates
  rebal as (
    select
      dest_location_id,
      variant_id,
      source_location_name,
      suggested_transfer_qty
    from public.inventory_rebalancing_recommendations_v830(p_tenant_id, p_location_id, v_days, 100)
  ),
  -- Historical supplier intelligence for candidate variants
  supplier_history as (
    select distinct on (c.location_id, c.variant_id)
      c.location_id,
      c.variant_id,
      p.supplier_id,
      s.name as supplier_name,
      coalesce(pi.entered_unit_cost, pi.unit_cost, 0)::numeric as latest_cost,
      coalesce(sup_perf.avg_lead_days, 4)::numeric as lead_days,
      coalesce(sup_perf.on_time_pct, 90)::numeric as on_time_pct,
      (select count(distinct p2.supplier_id) from public.purchases p2 join public.purchase_items pi2 on pi2.purchase_id = p2.id where p2.tenant_id = p_tenant_id and pi2.variant_id = c.variant_id) as total_known_suppliers
    from candidates c
    join public.purchase_items pi on pi.variant_id = c.variant_id
    join public.purchases p on p.id = pi.purchase_id
    join public.suppliers s on s.id = p.supplier_id
    left join (
      select g.supplier_id, avg(g.receipt_date - po.order_date) as avg_lead_days, avg(case when po.expected_date is null or g.receipt_date <= po.expected_date then 100.0 else 0.0 end) as on_time_pct
      from public.goods_receipts_v484 g
      join public.purchase_orders_v480 po on po.id = g.purchase_order_id
      where g.tenant_id = p_tenant_id and g.status = 'posted'
      group by g.supplier_id
    ) sup_perf on sup_perf.supplier_id = p.supplier_id
    where p.tenant_id = p_tenant_id and coalesce(p.status, '') not in ('void', 'cancelled')
    order by c.location_id, c.variant_id, p.purchase_date desc, p.created_at desc
  ),
  procurement_eval as (
    select
      md5(c.location_id::text || '|' || c.variant_id::text) as recommendation_id,
      c.location_id,
      c.location_code,
      c.location_name,
      c.variant_id,
      c.product_id,
      c.product_name,
      c.sku,
      c.barcode,
      c.available as available_stock,
      c.reserved_qty as reserved_stock,
      c.incoming_po_qty,
      c.in_transit_qty,
      c.net_effective_stock,
      c.reorder_level,
      c.max_stock,
      c.avg_daily_sales,
      c.days_cover,
      -- Suggested Purchase Qty (deterministic and stock-aware)
      case
        when c.suggested_reorder > 0 then c.suggested_reorder
        when c.reorder_level > 0 and c.net_effective_stock < c.reorder_level then
          greatest(
            case when c.max_stock > 0 then c.max_stock - c.net_effective_stock
                 else (c.reorder_level * 2) - c.net_effective_stock end,
            1
          )
        when c.avg_daily_sales > 0 and c.net_effective_stock <= 0 then
          greatest(ceil(c.avg_daily_sales * coalesce(sh.lead_days, 7) * 2), 1)
        else 0
      end as suggested_purchase_qty,
      -- Urgency classification
      case
        when (case
          when c.suggested_reorder > 0 then c.suggested_reorder
          when c.reorder_level > 0 and c.net_effective_stock < c.reorder_level then
            greatest(
              case when c.max_stock > 0 then c.max_stock - c.net_effective_stock
                   else (c.reorder_level * 2) - c.net_effective_stock end,
              1
            )
          when c.avg_daily_sales > 0 and c.net_effective_stock <= 0 then
            greatest(ceil(c.avg_daily_sales * coalesce(sh.lead_days, 7) * 2), 1)
          else 0
        end) = 0 then 'covered'
        when c.available <= 0 and (c.incoming_po_qty + c.in_transit_qty) = 0 then 'critical'
        when c.days_cover is not null and c.days_cover <= 3.0 and (c.incoming_po_qty + c.in_transit_qty) = 0 then 'critical'
        when c.available < c.reorder_level and (c.incoming_po_qty + c.in_transit_qty) = 0 then 'high'
        when c.net_effective_stock < c.reorder_level then 'normal'
        else 'normal'
      end as urgency,
      -- Expected days to stockout
      case when c.avg_daily_sales > 0 then round(c.available / c.avg_daily_sales, 1) else null end as stockout_risk_days,
      -- Lead time demand
      round(c.avg_daily_sales * coalesce(sh.lead_days, 5), 1) as lead_time_demand,
      -- Post-receipt stock projection
      (c.net_effective_stock + (case
        when c.suggested_reorder > 0 then c.suggested_reorder
        when c.reorder_level > 0 and c.net_effective_stock < c.reorder_level then
          greatest(
            case when c.max_stock > 0 then c.max_stock - c.net_effective_stock
                 else (c.reorder_level * 2) - c.net_effective_stock end,
            1
          )
        when c.avg_daily_sales > 0 and c.net_effective_stock <= 0 then
          greatest(ceil(c.avg_daily_sales * coalesce(sh.lead_days, 7) * 2), 1)
        else 0
      end)) as expected_stock_after_po,
      -- Rebalancing alternative
      (rb.suggested_transfer_qty is not null and rb.suggested_transfer_qty > 0) as has_rebalancing_opportunity,
      rb.source_location_name as rebalancing_source_location,
      rb.suggested_transfer_qty as rebalancing_transfer_qty,
      -- Supplier details
      sh.supplier_id as suggested_supplier_id,
      sh.supplier_name as suggested_supplier_name,
      coalesce(sh.latest_cost, c.average_cost, 0)::numeric as estimated_unit_cost,
      round((case
        when c.suggested_reorder > 0 then c.suggested_reorder
        when c.reorder_level > 0 and c.net_effective_stock < c.reorder_level then
          greatest(
            case when c.max_stock > 0 then c.max_stock - c.net_effective_stock
                 else (c.reorder_level * 2) - c.net_effective_stock end,
            1
          )
        when c.avg_daily_sales > 0 and c.net_effective_stock <= 0 then
          greatest(ceil(c.avg_daily_sales * coalesce(sh.lead_days, 7) * 2), 1)
        else 0
      end) * coalesce(sh.latest_cost, c.average_cost, 0), 2)::numeric as estimated_purchase_cost,
      -- Explainability reason
      case
        when rb.suggested_transfer_qty is not null and rb.suggested_transfer_qty > 0 then
          'Store transfer alternative: ' || rb.source_location_name || ' holds transferable surplus stock. Consider internal transfer before placing external PO.'
        when sh.supplier_name is not null and sh.total_known_suppliers > 1 then
          'Recommended ' || sh.supplier_name || ': primary supplier with historical cost ' || coalesce(round(sh.latest_cost, 2)::text, 'N/A') || ' and ' || round(sh.on_time_pct, 0)::text || '% on-time delivery record.'
        when sh.supplier_name is not null then
          'Primary supplier based on purchase history.'
        else
          'No supplier purchase history recorded. Assign preferred supplier on PO creation.'
      end as supplier_reason
    from candidates c
    left join rebal rb on rb.dest_location_id = c.location_id and rb.variant_id = c.variant_id
    left join supplier_history sh on sh.location_id = c.location_id and sh.variant_id = c.variant_id
  )
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'recommendation_id', pe.recommendation_id,
        'location_id', pe.location_id,
        'location_code', pe.location_code,
        'location_name', pe.location_name,
        'variant_id', pe.variant_id,
        'product_id', pe.product_id,
        'product_name', pe.product_name,
        'sku', pe.sku,
        'barcode', pe.barcode,
        'available_stock', pe.available_stock,
        'reserved_stock', pe.reserved_stock,
        'incoming_po_qty', pe.incoming_po_qty,
        'in_transit_qty', pe.in_transit_qty,
        'net_effective_stock', pe.net_effective_stock,
        'reorder_level', pe.reorder_level,
        'max_stock', pe.max_stock,
        'avg_daily_sales', pe.avg_daily_sales,
        'days_cover', pe.days_cover,
        'suggested_purchase_qty', pe.suggested_purchase_qty,
        'urgency', pe.urgency,
        'stockout_risk_days', pe.stockout_risk_days,
        'lead_time_demand', pe.lead_time_demand,
        'expected_stock_after_po', pe.expected_stock_after_po,
        'has_rebalancing_opportunity', pe.has_rebalancing_opportunity,
        'rebalancing_source_location', pe.rebalancing_source_location,
        'rebalancing_transfer_qty', pe.rebalancing_transfer_qty,
        'suggested_supplier_id', pe.suggested_supplier_id,
        'suggested_supplier_name', pe.suggested_supplier_name,
        'estimated_unit_cost', case when v_can_view_cost then pe.estimated_unit_cost else 0 end,
        'estimated_purchase_cost', case when v_can_view_cost then pe.estimated_purchase_cost else 0 end,
        'supplier_reason', pe.supplier_reason,
        'lifecycle_status', 'recommended'
      )
      order by
        case pe.urgency when 'critical' then 1 when 'high' then 2 when 'normal' then 3 else 4 end,
        pe.location_name, pe.product_name
    ), '[]'::jsonb),
    count(*) filter (where pe.suggested_purchase_qty > 0),
    count(*) filter (where pe.urgency = 'critical'),
    count(*) filter (where pe.urgency = 'high'),
    count(*) filter (where pe.urgency = 'normal'),
    count(*) filter (where pe.urgency = 'covered'),
    count(*) filter (where pe.has_rebalancing_opportunity = true),
    coalesce(sum(case when v_can_view_cost then pe.estimated_purchase_cost else 0 end), 0)
  into
    v_recommendations,
    v_total_rec_count,
    v_critical_count,
    v_high_count,
    v_normal_count,
    v_covered_count,
    v_rebalance_alt_count,
    v_estimated_cost_total
  from procurement_eval pe;

  v_res := jsonb_build_object(
    'tenant_id', p_tenant_id,
    'location_id', p_location_id,
    'days', v_days,
    'can_view_cost', v_can_view_cost,
    'summary', jsonb_build_object(
      'total_recommended_skus', v_total_rec_count,
      'critical_skus_count', v_critical_count,
      'high_urgency_skus_count', v_high_count,
      'normal_urgency_skus_count', v_normal_count,
      'incoming_stock_covered_skus', v_covered_count,
      'rebalancing_alternative_skus', v_rebalance_alt_count,
      'total_estimated_procurement_cost', v_estimated_cost_total
    ),
    'recommendations', v_recommendations
  );

  return v_res;
end $$;

GRANT ALL ON FUNCTION public.procurement_intelligence_v830(uuid, uuid, integer, text, integer) TO authenticated;
GRANT ALL ON FUNCTION public.procurement_intelligence_v830(uuid, uuid, integer, text, integer) TO service_role;

-- ----------------------------------------------------------------------------
-- 5. Register Schema Release in thq_schema_releases
-- ----------------------------------------------------------------------------
INSERT INTO public.thq_schema_releases (
  migration_no,
  schema_version,
  release_name,
  notes
)
VALUES (
  710,
  '8.3.4',
  'Operations Intelligence Phase 5: Purchase, Supplier & Procurement Intelligence',
  'Introduces purchase_intelligence_v830, supplier_intelligence_v830, procurement_intelligence_v830, performance indexes and Action Centre workflow integration.'
)
ON CONFLICT (migration_no) DO UPDATE SET
  schema_version = EXCLUDED.schema_version,
  release_name = EXCLUDED.release_name,
  notes = EXCLUDED.notes,
  applied_at = now();
