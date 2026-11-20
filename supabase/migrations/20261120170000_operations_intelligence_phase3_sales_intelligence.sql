-- ============================================================================
-- THQ ERP: Operations Intelligence Phase 3
-- Sales & Customer Purchasing Intelligence Foundation (v8.3.2)
-- Migration: 228
-- Release: 8.3.2 - Sales Intelligence & Customer RFM Analysis
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Performance Indexes for Sales Intelligence
-- ----------------------------------------------------------------------------
create index if not exists idx_sales_tenant_date_status
  on public.sales(tenant_id, sale_date, status);

create index if not exists idx_sales_tenant_customer_date
  on public.sales(tenant_id, customer_id, sale_date);

create index if not exists idx_sale_items_tenant_sale_variant
  on public.sale_items(tenant_id, sale_id, variant_id);

create index if not exists idx_sales_returns_tenant_date
  on public.sales_returns(tenant_id, return_date);

-- ----------------------------------------------------------------------------
-- 2. Sales Intelligence RPC (v8.3.2)
-- ----------------------------------------------------------------------------
create or replace function public.sales_intelligence_v830(
  p_tenant_id uuid,
  p_location_id uuid default null::uuid,
  p_days integer default 30,
  p_query text default ''::text
)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_from date := current_date - (v_days - 1);
  v_to date := current_date;
  v_prev_from date := v_from - v_days;
  v_prev_to date := v_from - 1;
  v_q text := '%' || lower(trim(coalesce(p_query, ''))) || '%';

  v_can_view_cost boolean := false;
  v_total_revenue numeric := 0;

  v_cur_gross_sales numeric := 0;
  v_cur_returns numeric := 0;
  v_cur_net_sales numeric := 0;
  v_cur_order_count bigint := 0;
  v_cur_units_sold numeric := 0;
  v_cur_cogs numeric := 0;
  v_cur_return_cogs numeric := 0;
  v_cur_aov numeric := 0;
  v_cur_gross_profit numeric := 0;
  v_cur_gross_margin_pct numeric := 0;

  v_prev_gross_sales numeric := 0;
  v_prev_returns numeric := 0;
  v_prev_net_sales numeric := 0;
  v_prev_order_count bigint := 0;
  v_prev_units_sold numeric := 0;
  v_prev_cogs numeric := 0;
  v_prev_return_cogs numeric := 0;
  v_prev_aov numeric := 0;
  v_prev_gross_profit numeric := 0;
  v_prev_gross_margin_pct numeric := 0;

  v_cur_active_cust bigint := 0;
  v_cur_new_cust bigint := 0;
  v_cur_repeat_cust bigint := 0;
  v_cur_at_risk_cust bigint := 0;
  v_cur_dormant_cust bigint := 0;
  v_prev_repeat_cust bigint := 0;

  v_performance jsonb := '{}'::jsonb;
  v_daily_trends jsonb := '[]'::jsonb;
  v_weekly_trends jsonb := '[]'::jsonb;
  v_monthly_trends jsonb := '[]'::jsonb;
  v_best_selling jsonb := '[]'::jsonb;
  v_highest_volume jsonb := '[]'::jsonb;
  v_growing_products jsonb := '[]'::jsonb;
  v_declining_products jsonb := '[]'::jsonb;
  v_category_performance jsonb := '[]'::jsonb;
  v_customer_summary jsonb := '{}'::jsonb;
  v_customer_segments jsonb := '[]'::jsonb;
  v_top_customers jsonb := '[]'::jsonb;
  v_anomalies jsonb := '[]'::jsonb;

  rec record;
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

  -- --------------------------------------------------------------------------
  -- 1. Current Period Overall Sales & Returns
  -- --------------------------------------------------------------------------
  select
    coalesce(sum(s.grand_total), 0),
    coalesce(sum(s.cost_total), 0),
    count(distinct s.id)
  into v_cur_gross_sales, v_cur_cogs, v_cur_order_count
  from public.sales s
  left join public.document_origins o on o.tenant_id = s.tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
  where s.tenant_id = p_tenant_id
    and s.sale_date between v_from and v_to
    and coalesce(s.status, '') not in ('void', 'cancelled')
    and (p_location_id is null or o.location_id = p_location_id);

  select coalesce(sum(si.quantity), 0)
  into v_cur_units_sold
  from public.sale_items si
  join public.sales s on s.id = si.sale_id and s.tenant_id = si.tenant_id
  left join public.document_origins o on o.tenant_id = s.tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
  where s.tenant_id = p_tenant_id
    and s.sale_date between v_from and v_to
    and coalesce(s.status, '') not in ('void', 'cancelled')
    and (p_location_id is null or o.location_id = p_location_id);

  select coalesce(sum(r.grand_total), 0)
  into v_cur_returns
  from public.sales_returns r
  where r.tenant_id = p_tenant_id
    and r.return_date between v_from and v_to
    and r.refund_status <> 'waived'
    and (p_location_id is null or r.location_id = p_location_id);

  select coalesce(sum(ri.quantity * coalesce(si.unit_cost, 0)), 0)
  into v_cur_return_cogs
  from public.sales_return_items ri
  join public.sales_returns r on r.id = ri.sales_return_id
  left join public.sale_items si on si.id = ri.sale_item_id
  where r.tenant_id = p_tenant_id
    and r.return_date between v_from and v_to
    and r.refund_status <> 'waived'
    and (p_location_id is null or r.location_id = p_location_id);

  v_cur_net_sales := round(v_cur_gross_sales - v_cur_returns, 2);
  v_total_revenue := v_cur_net_sales;

  if v_cur_order_count > 0 then
    v_cur_aov := round(v_cur_net_sales / v_cur_order_count, 2);
  end if;

  if v_can_view_cost then
    v_cur_gross_profit := round(v_cur_net_sales - (v_cur_cogs - v_cur_return_cogs), 2);
    if v_cur_net_sales > 0 then
      v_cur_gross_margin_pct := round((v_cur_gross_profit * 100.0) / v_cur_net_sales, 2);
    end if;
  end if;

  -- --------------------------------------------------------------------------
  -- 2. Previous Period Overall Sales & Returns
  -- --------------------------------------------------------------------------
  select
    coalesce(sum(s.grand_total), 0),
    coalesce(sum(s.cost_total), 0),
    count(distinct s.id)
  into v_prev_gross_sales, v_prev_cogs, v_prev_order_count
  from public.sales s
  left join public.document_origins o on o.tenant_id = s.tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
  where s.tenant_id = p_tenant_id
    and s.sale_date between v_prev_from and v_prev_to
    and coalesce(s.status, '') not in ('void', 'cancelled')
    and (p_location_id is null or o.location_id = p_location_id);

  select coalesce(sum(si.quantity), 0)
  into v_prev_units_sold
  from public.sale_items si
  join public.sales s on s.id = si.sale_id and s.tenant_id = si.tenant_id
  left join public.document_origins o on o.tenant_id = s.tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
  where s.tenant_id = p_tenant_id
    and s.sale_date between v_prev_from and v_prev_to
    and coalesce(s.status, '') not in ('void', 'cancelled')
    and (p_location_id is null or o.location_id = p_location_id);

  select coalesce(sum(r.grand_total), 0)
  into v_prev_returns
  from public.sales_returns r
  where r.tenant_id = p_tenant_id
    and r.return_date between v_prev_from and v_prev_to
    and r.refund_status <> 'waived'
    and (p_location_id is null or r.location_id = p_location_id);

  select coalesce(sum(ri.quantity * coalesce(si.unit_cost, 0)), 0)
  into v_prev_return_cogs
  from public.sales_return_items ri
  join public.sales_returns r on r.id = ri.sales_return_id
  left join public.sale_items si on si.id = ri.sale_item_id
  where r.tenant_id = p_tenant_id
    and r.return_date between v_prev_from and v_prev_to
    and r.refund_status <> 'waived'
    and (p_location_id is null or r.location_id = p_location_id);

  v_prev_net_sales := round(v_prev_gross_sales - v_prev_returns, 2);

  if v_prev_order_count > 0 then
    v_prev_aov := round(v_prev_net_sales / v_prev_order_count, 2);
  end if;

  if v_can_view_cost then
    v_prev_gross_profit := round(v_prev_net_sales - (v_prev_cogs - v_prev_return_cogs), 2);
    if v_prev_net_sales > 0 then
      v_prev_gross_margin_pct := round((v_prev_gross_profit * 100.0) / v_prev_net_sales, 2);
    end if;
  end if;

  v_performance := jsonb_build_object(
    'current', jsonb_build_object(
      'gross_sales', round(v_cur_gross_sales, 2),
      'sales_returns', round(v_cur_returns, 2),
      'net_sales', round(v_cur_net_sales, 2),
      'order_count', v_cur_order_count,
      'units_sold', round(v_cur_units_sold, 2),
      'aov', v_cur_aov,
      'gross_profit', case when v_can_view_cost then v_cur_gross_profit else 0 end,
      'gross_margin_pct', case when v_can_view_cost then v_cur_gross_margin_pct else 0 end
    ),
    'previous', jsonb_build_object(
      'gross_sales', round(v_prev_gross_sales, 2),
      'sales_returns', round(v_prev_returns, 2),
      'net_sales', round(v_prev_net_sales, 2),
      'order_count', v_prev_order_count,
      'units_sold', round(v_prev_units_sold, 2),
      'aov', v_prev_aov,
      'gross_profit', case when v_can_view_cost then v_prev_gross_profit else 0 end,
      'gross_margin_pct', case when v_can_view_cost then v_prev_gross_margin_pct else 0 end
    ),
    'growth', jsonb_build_object(
      'gross_sales_pct', case when v_prev_gross_sales > 0 then round(((v_cur_gross_sales - v_prev_gross_sales) * 100.0) / v_prev_gross_sales, 2) else null end,
      'net_sales_pct', case when v_prev_net_sales > 0 then round(((v_cur_net_sales - v_prev_net_sales) * 100.0) / v_prev_net_sales, 2) else null end,
      'order_count_pct', case when v_prev_order_count > 0 then round(((v_cur_order_count - v_prev_order_count)::numeric * 100.0) / v_prev_order_count, 2) else null end,
      'units_sold_pct', case when v_prev_units_sold > 0 then round(((v_cur_units_sold - v_prev_units_sold) * 100.0) / v_prev_units_sold, 2) else null end,
      'aov_pct', case when v_prev_aov > 0 then round(((v_cur_aov - v_prev_aov) * 100.0) / v_prev_aov, 2) else null end
    )
  );

  -- --------------------------------------------------------------------------
  -- 3. Sales Trends (Daily, Weekly, Monthly)
  -- --------------------------------------------------------------------------
  -- Daily trend (all days in current period)
  select coalesce(jsonb_agg(to_jsonb(dt) order by dt.day_date), '[]'::jsonb)
  into v_daily_trends
  from (
    select
      to_char(d.dt, 'YYYY-MM-DD') as day_date,
      to_char(d.dt, 'Dy, Mon DD') as label,
      round(coalesce(sum(s.grand_total), 0) - coalesce(sum(r.grand_total), 0), 2) as net_sales,
      round(coalesce(sum(s.grand_total), 0), 2) as gross_sales,
      round(coalesce(sum(r.grand_total), 0), 2) as returns,
      count(distinct s.id) as order_count
    from generate_series(v_from::timestamp, v_to::timestamp, '1 day'::interval) d(dt)
    left join (
      select s1.id, s1.sale_date, s1.grand_total
      from public.sales s1
      left join public.document_origins o1 on o1.tenant_id = s1.tenant_id and o1.entity_type = 'sale' and o1.entity_id = s1.id
      where s1.tenant_id = p_tenant_id
        and s1.sale_date between v_from and v_to
        and coalesce(s1.status, '') not in ('void', 'cancelled')
        and (p_location_id is null or o1.location_id = p_location_id)
    ) s on s.sale_date = d.dt::date
    left join (
      select r1.id, r1.return_date, r1.grand_total
      from public.sales_returns r1
      where r1.tenant_id = p_tenant_id
        and r1.return_date between v_from and v_to
        and r1.refund_status <> 'waived'
        and (p_location_id is null or r1.location_id = p_location_id)
    ) r on r.return_date = d.dt::date
    group by d.dt
    order by d.dt
  ) dt;

  -- Weekly trend (trailing 12 weeks)
  select coalesce(jsonb_agg(to_jsonb(wt) order by wt.week_start), '[]'::jsonb)
  into v_weekly_trends
  from (
    select
      to_char(date_trunc('week', s.sale_date), 'YYYY-MM-DD') as week_start,
      'Wk ' || to_char(date_trunc('week', s.sale_date), 'IW (Mon DD)') as label,
      round(coalesce(sum(s.grand_total), 0), 2) as gross_sales,
      count(distinct s.id) as order_count
    from public.sales s
    left join public.document_origins o on o.tenant_id = s.tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
    where s.tenant_id = p_tenant_id
      and s.sale_date >= (current_date - interval '12 weeks')::date
      and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
    group by date_trunc('week', s.sale_date)
    order by date_trunc('week', s.sale_date)
  ) wt;

  -- Monthly trend (trailing 12 months)
  select coalesce(jsonb_agg(to_jsonb(mt) order by mt.month_start), '[]'::jsonb)
  into v_monthly_trends
  from (
    select
      to_char(date_trunc('month', s.sale_date), 'YYYY-MM-DD') as month_start,
      to_char(date_trunc('month', s.sale_date), 'Mon YYYY') as label,
      round(coalesce(sum(s.grand_total), 0), 2) as gross_sales,
      count(distinct s.id) as order_count
    from public.sales s
    left join public.document_origins o on o.tenant_id = s.tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
    where s.tenant_id = p_tenant_id
      and s.sale_date >= (current_date - interval '12 months')::date
      and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
    group by date_trunc('month', s.sale_date)
    order by date_trunc('month', s.sale_date)
  ) mt;

  -- --------------------------------------------------------------------------
  -- 4. Product & Category Performance (Single-pass CTE without temp tables)
  -- --------------------------------------------------------------------------
  with cur_prod as (
    select
      pv.id as variant_id,
      pr.id as product_id,
      pr.name as product_name,
      coalesce(nullif(pv.name, ''), pr.name) as variant_name,
      coalesce(pv.sku, '') as sku,
      coalesce(pc.name, 'Uncategorized') as category_name,
      sum(si.quantity)::numeric as sold_qty,
      round(sum(si.line_total), 2)::numeric as revenue,
      round(sum(si.cost_total), 2)::numeric as cogs
    from public.sale_items si
    join public.sales s on s.id = si.sale_id and s.tenant_id = si.tenant_id
    join public.product_variants pv on pv.id = si.variant_id
    join public.products pr on pr.id = pv.product_id
    left join public.product_categories pc on pc.id = pr.category_id and pc.tenant_id = pr.tenant_id
    left join public.document_origins o on o.tenant_id = s.tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
    where s.tenant_id = p_tenant_id
      and s.sale_date between v_from and v_to
      and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
      and (p_query = '' or lower(pr.name) like v_q or lower(coalesce(pv.sku, '')) like v_q or lower(coalesce(pc.name, '')) like v_q)
    group by pv.id, pr.id, pr.name, pv.name, pv.sku, pc.name
  ),
  prev_prod as (
    select
      pv.id as variant_id,
      sum(si.quantity)::numeric as sold_qty,
      round(sum(si.line_total), 2)::numeric as revenue
    from public.sale_items si
    join public.sales s on s.id = si.sale_id and s.tenant_id = si.tenant_id
    join public.product_variants pv on pv.id = si.variant_id
    left join public.document_origins o on o.tenant_id = s.tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
    where s.tenant_id = p_tenant_id
      and s.sale_date between v_prev_from and v_prev_to
      and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
    group by pv.id
  ),
  merged_prod as (
    select
      cp.variant_id,
      cp.product_id,
      cp.product_name,
      cp.variant_name,
      cp.sku,
      cp.category_name,
      cp.sold_qty,
      cp.revenue,
      case when v_can_view_cost then round(cp.revenue - cp.cogs, 2) else 0 end as gross_profit,
      case when v_can_view_cost and cp.revenue > 0 then round(((cp.revenue - cp.cogs) * 100.0) / cp.revenue, 2) else null end as margin_pct,
      case when v_cur_gross_sales > 0 then round((cp.revenue * 100.0) / v_cur_gross_sales, 2) else 0 end as contribution_pct,
      coalesce(pp.revenue, 0) as prev_revenue,
      coalesce(pp.sold_qty, 0) as prev_sold_qty,
      case
        when coalesce(pp.revenue, 0) > 0 then round(((cp.revenue - pp.revenue) * 100.0) / pp.revenue, 2)
        else null
      end as growth_pct
    from cur_prod cp
    left join prev_prod pp on pp.variant_id = cp.variant_id
  )
  select
    coalesce((select jsonb_agg(to_jsonb(p) order by p.revenue desc) from (select * from merged_prod order by revenue desc limit 20) p), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(p) order by p.sold_qty desc) from (select * from merged_prod order by sold_qty desc limit 20) p), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(p) order by p.growth_pct desc) from (select * from merged_prod where growth_pct > 0 and prev_revenue > 0 order by growth_pct desc limit 15) p), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(p) order by p.growth_pct asc) from (select * from merged_prod where growth_pct < 0 and prev_revenue > 0 order by growth_pct asc limit 15) p), '[]'::jsonb),
    coalesce((
      select jsonb_agg(to_jsonb(c) order by c.revenue desc)
      from (
        select
          category_name,
          round(sum(revenue), 2) as revenue,
          sum(sold_qty) as units_sold,
          round(sum(prev_revenue), 2) as prev_revenue,
          case when sum(prev_revenue) > 0 then round(((sum(revenue) - sum(prev_revenue)) * 100.0) / sum(prev_revenue), 2) else null end as growth_pct,
          case when v_cur_gross_sales > 0 then round((sum(revenue) * 100.0) / v_cur_gross_sales, 2) else 0 end as contribution_pct,
          case when v_can_view_cost then round(sum(gross_profit), 2) else 0 end as gross_profit,
          case when v_can_view_cost and sum(revenue) > 0 then round((sum(gross_profit) * 100.0) / sum(revenue), 2) else null end as gross_margin_pct
        from merged_prod
        group by category_name
        order by revenue desc
      ) c
    ), '[]'::jsonb)
  into
    v_best_selling,
    v_highest_volume,
    v_growing_products,
    v_declining_products,
    v_category_performance;

  -- --------------------------------------------------------------------------
  -- 5. Customer Purchasing Intelligence & RFM (Single-pass CTE without temp tables)
  -- --------------------------------------------------------------------------
  with cust_raw as (
    select
      coalesce(c.id, s.customer_id) as customer_id,
      coalesce(c.name, s.customer_name, 'Direct Client') as customer_name,
      coalesce(c.phone, s.customer_phone, '') as phone,
      count(*) filter (where s.sale_date between v_from and v_to) as period_orders,
      coalesce(sum(s.grand_total) filter (where s.sale_date between v_from and v_to), 0) as period_spend,
      count(*) filter (where s.sale_date between v_prev_from and v_prev_to) as prev_period_orders,
      count(*) as lifetime_orders,
      coalesce(sum(s.grand_total), 0) as lifetime_spend,
      min(s.sale_date) as first_sale_date,
      max(s.sale_date) as latest_sale_date,
      (current_date - max(s.sale_date))::int as recency_days
    from public.sales s
    left join public.customers c on c.id = s.customer_id and c.tenant_id = s.tenant_id
    left join public.document_origins o on o.tenant_id = s.tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
    where s.tenant_id = p_tenant_id
      and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
      and (p_query = '' or lower(coalesce(c.name, s.customer_name, '')) like v_q or lower(coalesce(c.phone, s.customer_phone, '')) like v_q)
    group by coalesce(c.id, s.customer_id), coalesce(c.name, s.customer_name, 'Direct Client'), coalesce(c.phone, s.customer_phone, '')
  ),
  classified as (
    select
      cr.*,
      case
        -- 1. Champions: Recent (< 30d), frequent (>= 4 orders), high spend
        when cr.recency_days <= 30 and (cr.period_orders >= 4 or cr.lifetime_orders >= 10) and cr.period_spend >= 10000 then 'Champions'
        -- 2. Loyal Customers: Consistent recent purchases (< 60d, >= 3 orders)
        when cr.recency_days <= 60 and (cr.period_orders >= 3 or cr.lifetime_orders >= 5) then 'Loyal Customers'
        -- 3. Potential Loyalists: Recent (< 30d) with 1-2 orders, returning buyers
        when cr.recency_days <= 30 and cr.period_orders in (1, 2) and cr.first_sale_date < v_from then 'Potential Loyalists'
        -- 4. New Customers: First purchase ever within this period
        when cr.first_sale_date >= v_from and cr.recency_days <= 30 then 'New Customers'
        -- 5. At Risk: Valuable before (lifetime orders >= 2) but haven't bought in 61-120 days
        when cr.recency_days between 61 and 120 and cr.lifetime_orders >= 2 then 'At Risk'
        -- 6. Dormant: Haven't purchased in > 120 days
        when cr.recency_days > 120 then 'Dormant'
        else 'Occasional Buyers'
      end as segment,
      case when cr.period_orders > 0 then round(cr.period_spend / cr.period_orders, 2) else 0 end as aov
    from cust_raw cr
  )
  select
    coalesce(count(*) filter (where period_orders > 0), 0),
    coalesce(count(*) filter (where first_sale_date >= v_from), 0),
    coalesce(count(*) filter (where period_orders >= 2 or (period_orders >= 1 and first_sale_date < v_from)), 0),
    coalesce(count(*) filter (where segment = 'At Risk'), 0),
    coalesce(count(*) filter (where segment = 'Dormant'), 0),
    coalesce(count(*) filter (where prev_period_orders >= 2 or (prev_period_orders >= 1 and first_sale_date < v_prev_from)), 0),
    coalesce((
      select jsonb_agg(to_jsonb(sg))
      from (
        select
          segment,
          count(*) as count,
          round(sum(period_spend), 2) as spend,
          case when count(*) > 0 and (select count(*) from classified) > 0
            then round((count(*)::numeric * 100.0) / (select count(*) from classified), 2)
            else 0
          end as pct_of_customers,
          case segment
            when 'Champions' then 'Recency <= 30d, Frequency >= 4, High Spend (>= 10,000)'
            when 'Loyal Customers' then 'Recency <= 60d, Frequency >= 3 orders'
            when 'Potential Loyalists' then 'Recency <= 30d, 1–2 orders, Returning buyer'
            when 'New Customers' then 'First purchase ever occurred within current analysis period'
            when 'At Risk' then 'Recency 61–120d, previously >= 2 lifetime orders'
            when 'Dormant' then 'Recency > 120d without recent purchases'
            else 'Infrequent or single past purchase'
          end as criteria
        from classified
        group by segment
        order by count(*) desc
      ) sg
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(to_jsonb(tc))
      from (
        select
          customer_id,
          customer_name,
          phone,
          segment,
          recency_days,
          period_orders,
          round(period_spend, 2) as period_spend,
          lifetime_orders,
          round(lifetime_spend, 2) as lifetime_spend,
          aov
        from classified
        order by period_spend desc, lifetime_spend desc
        limit 20
      ) tc
    ), '[]'::jsonb)
  into
    v_cur_active_cust,
    v_cur_new_cust,
    v_cur_repeat_cust,
    v_cur_at_risk_cust,
    v_cur_dormant_cust,
    v_prev_repeat_cust,
    v_customer_segments,
    v_top_customers
  from classified;

  v_customer_summary := jsonb_build_object(
    'total_active_customers', v_cur_active_cust,
    'new_customers', v_cur_new_cust,
    'repeat_customers', v_cur_repeat_cust,
    'at_risk_customers', v_cur_at_risk_cust,
    'dormant_customers', v_cur_dormant_cust,
    'repeat_rate_pct', case when v_cur_active_cust > 0 then round((v_cur_repeat_cust::numeric * 100.0) / v_cur_active_cust, 2) else 0 end,
    'average_customer_spend', case when v_cur_active_cust > 0 then round(v_cur_net_sales / v_cur_active_cust, 2) else 0 end,
    'average_purchase_frequency', case when v_cur_active_cust > 0 then round(v_cur_order_count::numeric / v_cur_active_cust, 2) else 0 end
  );

  -- --------------------------------------------------------------------------
  -- 6. Sales Anomaly Indicators
  -- --------------------------------------------------------------------------
  -- Anomaly 1: Sudden Revenue Decline (> 25% drop, min volume 10,000)
  if v_prev_net_sales >= 10000 and v_cur_net_sales < (v_prev_net_sales * 0.75) then
    v_anomalies := v_anomalies || jsonb_build_array(jsonb_build_object(
      'code', 'revenue_decline',
      'title', 'Sudden Revenue Decline',
      'severity', case when v_cur_net_sales < (v_prev_net_sales * 0.60) then 'critical' else 'warning' end,
      'metric', '-' || round(((v_prev_net_sales - v_cur_net_sales) * 100.0) / v_prev_net_sales, 1) || '% vs prev',
      'description', 'Net revenue declined by ' || round(((v_prev_net_sales - v_cur_net_sales) * 100.0) / v_prev_net_sales, 1) || '% compared to previous period (' || v_cur_net_sales || ' vs ' || v_prev_net_sales || ').',
      'recommendation', 'Inspect account activity for top customers, verify item stock availability, and check for operational interruptions.'
    ));
  end if;

  -- Anomaly 2: Exceptional Sales Spike (> 50% increase, min volume 5,000)
  if v_prev_net_sales >= 5000 and v_cur_net_sales > (v_prev_net_sales * 1.50) then
    v_anomalies := v_anomalies || jsonb_build_array(jsonb_build_object(
      'code', 'sales_spike',
      'title', 'Exceptional Sales Spike',
      'severity', 'info',
      'metric', '+' || round(((v_cur_net_sales - v_prev_net_sales) * 100.0) / v_prev_net_sales, 1) || '% vs prev',
      'description', 'Net revenue increased by ' || round(((v_cur_net_sales - v_prev_net_sales) * 100.0) / v_prev_net_sales, 1) || '% over previous period (' || v_cur_net_sales || ' vs ' || v_prev_net_sales || ').',
      'recommendation', 'Anticipate replenishment needs to prevent stockouts on rapidly depleting product lines.'
    ));
  end if;

  -- Anomaly 3: Significant AOV Shift (> 30% shift, min 10 orders each period)
  if v_prev_order_count >= 10 and v_cur_order_count >= 10 and v_prev_aov > 0 and abs(v_cur_aov - v_prev_aov) / v_prev_aov >= 0.30 then
    v_anomalies := v_anomalies || jsonb_build_array(jsonb_build_object(
      'code', 'aov_shift',
      'title', 'Significant Average Order Value Shift',
      'severity', case when v_cur_aov < v_prev_aov then 'warning' else 'info' end,
      'metric', case when v_cur_aov >= v_prev_aov then '+' else '-' end || round(abs(v_cur_aov - v_prev_aov) * 100.0 / v_prev_aov, 1) || '% AOV',
      'description', 'Average order value shifted by ' || round(((v_cur_aov - v_prev_aov) * 100.0) / v_prev_aov, 1) || '% (' || v_cur_aov || ' vs ' || v_prev_aov || ').',
      'recommendation', 'Analyze changes in customer order composition, bulk purchasing discounts, and product mix.'
    ));
  end if;

  -- Anomaly 4: Sudden Category Decline (> 30% drop for major category >= 10% of prev sales)
  for rec in (
    select
      elem->>'category_name' as category_name,
      (elem->>'revenue')::numeric as revenue,
      (elem->>'prev_revenue')::numeric as prev_revenue,
      (elem->>'growth_pct')::numeric as growth_pct
    from jsonb_array_elements(v_category_performance) as elem
    where (elem->>'prev_revenue')::numeric >= (v_prev_gross_sales * 0.10)
      and (elem->>'growth_pct')::numeric <= -30.0
    limit 2
  ) loop
    v_anomalies := v_anomalies || jsonb_build_array(jsonb_build_object(
      'code', 'category_decline',
      'title', 'Category Contraction: ' || rec.category_name,
      'severity', 'warning',
      'metric', rec.growth_pct || '% revenue',
      'description', 'Category "' || rec.category_name || '" declined by ' || abs(rec.growth_pct) || '% vs previous period (' || rec.revenue || ' vs ' || rec.prev_revenue || ').',
      'recommendation', 'Verify supplier fulfillment, pricing competitiveness, and consumer preference shifts in this category.'
    ));
  end loop;

  -- Anomaly 5: Unusually High Returns (> 8% of gross sales, min returns 1,000)
  if v_cur_gross_sales >= 10000 and v_cur_returns >= 1000 and (v_cur_returns / v_cur_gross_sales) >= 0.08 then
    v_anomalies := v_anomalies || jsonb_build_array(jsonb_build_object(
      'code', 'high_returns',
      'title', 'Elevated Sales Return Rate',
      'severity', case when (v_cur_returns / v_cur_gross_sales) >= 0.15 then 'critical' else 'warning' end,
      'metric', round((v_cur_returns * 100.0) / v_cur_gross_sales, 1) || '% return rate',
      'description', 'Sales returns represent ' || round((v_cur_returns * 100.0) / v_cur_gross_sales, 1) || '% of gross sales (' || v_cur_returns || ' returned vs ' || v_cur_gross_sales || ' gross).',
      'recommendation', 'Inspect returned goods for quality defects, shipping damage, or billing inaccuracies.'
    ));
  end if;

  -- Anomaly 6: Repeat Purchasing Decline (> 25% drop, min 5 repeat customers prev)
  if v_prev_repeat_cust >= 5 and v_cur_repeat_cust < (v_prev_repeat_cust * 0.75) then
    v_anomalies := v_anomalies || jsonb_build_array(jsonb_build_object(
      'code', 'repeat_decline',
      'title', 'Repeat Customer Retention Drop',
      'severity', 'warning',
      'metric', '-' || round(((v_prev_repeat_cust - v_cur_repeat_cust) * 100.0) / v_prev_repeat_cust, 1) || '% repeat buyers',
      'description', 'Repeat active buyers fell from ' || v_prev_repeat_cust || ' to ' || v_cur_repeat_cust || ' (-' || round(((v_prev_repeat_cust - v_cur_repeat_cust) * 100.0) / v_prev_repeat_cust, 1) || '%).',
      'recommendation', 'Engage At-Risk and Dormant customer accounts with relationship check-ins and tailored offers.'
    ));
  end if;

  -- --------------------------------------------------------------------------
  -- 7. Build Output Object
  -- --------------------------------------------------------------------------
  return jsonb_build_object(
    'period_days', v_days,
    'from_date', v_from,
    'to_date', v_to,
    'can_view_cost', v_can_view_cost,
    'performance', v_performance,
    'trends', jsonb_build_object(
      'daily', v_daily_trends,
      'weekly', v_weekly_trends,
      'monthly', v_monthly_trends
    ),
    'products', jsonb_build_object(
      'best_selling', v_best_selling,
      'highest_volume', v_highest_volume,
      'growing', v_growing_products,
      'declining', v_declining_products
    ),
    'categories', v_category_performance,
    'customer_intelligence', jsonb_build_object(
      'summary', v_customer_summary,
      'segments', v_customer_segments,
      'top_customers', v_top_customers
    ),
    'anomalies', v_anomalies
  );
end $$;

grant all on function public.sales_intelligence_v830(uuid, uuid, integer, text) to authenticated;
grant all on function public.sales_intelligence_v830(uuid, uuid, integer, text) to service_role;

-- ----------------------------------------------------------------------------
-- 3. Record Schema Release
-- ----------------------------------------------------------------------------
insert into public.thq_schema_releases(migration_no, schema_version, release_name, notes)
values (
  228,
  '8.3.2',
  'Operations Intelligence Phase 3: Sales & Customer Purchasing Intelligence',
  'Introduces sales_intelligence_v830 with authoritative gross/net sales, returns, COGS and cost protection, daily/weekly/monthly trends, category and product performance, customer RFM segmentation, and rule-based anomaly indicators.'
)
on conflict (migration_no) do update set
  schema_version = excluded.schema_version,
  release_name = excluded.release_name,
  notes = excluded.notes,
  applied_at = now();
