-- THQ ERP v8.3.0 — Operations Intelligence Foundation & Core Schema
-- Author: Antigravity Senior Engineering Team
-- Date: 2026-11-17
-- Scope: Canonical intelligence insight store, action proposals, upgraded inventory & credit analytics, and operational summary RPCs.

begin;

-- ============================================================================
-- 1. CANONICAL INTELLIGENCE INSIGHTS TABLE
-- ============================================================================

create table if not exists public.erp_intelligence_insights(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid references public.business_locations(id) on delete cascade,
  engine text not null check(engine in (
    'executive', 'sales', 'inventory', 'financial', 'customer', 
    'supplier', 'procurement', 'operations', 'workforce', 
    'risk_anomaly', 'predictive', 'simulation'
  )),
  category text not null,
  severity text not null check(severity in ('info', 'warning', 'critical', 'opportunity')),
  priority text not null check(priority in ('low', 'medium', 'high', 'urgent')),
  title text not null,
  description text not null,
  evidence jsonb not null default '{}'::jsonb,
  source_references jsonb not null default '[]'::jsonb,
  confidence numeric not null default 1.0 check(confidence >= 0.0 and confidence <= 1.0),
  data_freshness timestamptz not null default now(),
  status text not null default 'new_insight' check(status in (
    'new_insight', 'acknowledged', 'in_progress', 'resolved', 'dismissed', 'reopened'
  )),
  resolution_note text,
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_erp_intelligence_insights_tenant_engine 
  on public.erp_intelligence_insights(tenant_id, engine, status);

create index if not exists idx_erp_intelligence_insights_tenant_loc_date 
  on public.erp_intelligence_insights(tenant_id, location_id, created_at desc);

create index if not exists idx_erp_intelligence_insights_severity_priority 
  on public.erp_intelligence_insights(tenant_id, severity, priority, status);

alter table public.erp_intelligence_insights enable row level security;

-- Tenant Isolation Policies for Insights
drop policy if exists "erp_intelligence_insights_tenant_read" on public.erp_intelligence_insights;
create policy "erp_intelligence_insights_tenant_read" on public.erp_intelligence_insights
  for select using (private.erp_user_has_tenant_access(tenant_id));

drop policy if exists "erp_intelligence_insights_tenant_write" on public.erp_intelligence_insights;
create policy "erp_intelligence_insights_tenant_write" on public.erp_intelligence_insights
  for insert with check (private.erp_user_has_tenant_access(tenant_id));

drop policy if exists "erp_intelligence_insights_tenant_update" on public.erp_intelligence_insights;
create policy "erp_intelligence_insights_tenant_update" on public.erp_intelligence_insights
  for update using (private.erp_user_has_tenant_access(tenant_id));

drop policy if exists "erp_intelligence_insights_tenant_delete" on public.erp_intelligence_insights;
create policy "erp_intelligence_insights_tenant_delete" on public.erp_intelligence_insights
  for delete using (private.erp_user_is_owner(tenant_id));

-- ============================================================================
-- 2. CANONICAL INTELLIGENCE ACTIONS TABLE
-- ============================================================================

create table if not exists public.erp_intelligence_actions(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  location_id uuid references public.business_locations(id) on delete cascade,
  insight_id uuid references public.erp_intelligence_insights(id) on delete set null,
  action_type text not null check(action_type in (
    'create_purchase_order', 'create_stock_transfer', 'send_payment_reminder', 
    'adjust_reorder_level', 'freeze_customer_credit', 'operational_task'
  )),
  payload jsonb not null default '{}'::jsonb,
  preview_summary text not null,
  required_permission text not null default 'inventory.manage',
  status text not null default 'pending_approval' check(status in (
    'pending_approval', 'approved', 'rejected', 'executed', 'failed'
  )),
  created_by uuid references auth.users(id) on delete set null,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  executed_at timestamptz,
  execution_result jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_erp_intelligence_actions_tenant_status 
  on public.erp_intelligence_actions(tenant_id, status, created_at desc);

create index if not exists idx_erp_intelligence_actions_insight 
  on public.erp_intelligence_actions(tenant_id, insight_id);

alter table public.erp_intelligence_actions enable row level security;

-- Tenant Isolation Policies for Actions
drop policy if exists "erp_intelligence_actions_tenant_read" on public.erp_intelligence_actions;
create policy "erp_intelligence_actions_tenant_read" on public.erp_intelligence_actions
  for select using (private.erp_user_has_tenant_access(tenant_id));

drop policy if exists "erp_intelligence_actions_tenant_write" on public.erp_intelligence_actions;
create policy "erp_intelligence_actions_tenant_write" on public.erp_intelligence_actions
  for insert with check (private.erp_user_has_tenant_access(tenant_id));

drop policy if exists "erp_intelligence_actions_tenant_update" on public.erp_intelligence_actions;
create policy "erp_intelligence_actions_tenant_update" on public.erp_intelligence_actions
  for update using (private.erp_user_has_tenant_access(tenant_id));

-- Revoke public access
revoke all on public.erp_intelligence_insights, public.erp_intelligence_actions from anon, public;
grant all on public.erp_intelligence_insights, public.erp_intelligence_actions to authenticated, service_role;

-- ============================================================================
-- 3. INSIGHT MANAGEMENT RPCS
-- ============================================================================

create or replace function public.erp_intelligence_insight_save_v830(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_engine text default 'operations',
  p_category text default 'general',
  p_severity text default 'info',
  p_priority text default 'medium',
  p_title text default '',
  p_description text default '',
  p_evidence jsonb default '{}'::jsonb,
  p_source_references jsonb default '[]'::jsonb,
  p_confidence numeric default 1.0,
  p_dedup_key text default null
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_id uuid;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied to tenant %', p_tenant_id;
  end if;

  if trim(coalesce(p_title, '')) = '' then
    raise exception 'Insight title is required';
  end if;

  -- Optional deduplication: if identical title and category exists within last 24h, update it
  if p_dedup_key is not null and trim(p_dedup_key) <> '' then
    select id into v_id
    from public.erp_intelligence_insights
    where tenant_id = p_tenant_id
      and engine = p_engine
      and category = p_category
      and title = p_title
      and status in ('new_insight', 'acknowledged', 'in_progress')
      and created_at >= now() - interval '24 hours'
    order by created_at desc
    limit 1;
  end if;

  if v_id is not null then
    update public.erp_intelligence_insights
    set description = p_description,
        evidence = coalesce(p_evidence, '{}'::jsonb),
        source_references = coalesce(p_source_references, '[]'::jsonb),
        confidence = coalesce(p_confidence, 1.0),
        severity = p_severity,
        priority = p_priority,
        data_freshness = now(),
        updated_at = now()
    where id = v_id;
  else
    insert into public.erp_intelligence_insights(
      tenant_id, location_id, engine, category, severity, priority,
      title, description, evidence, source_references, confidence,
      data_freshness, status, created_at, updated_at
    ) values (
      p_tenant_id, p_location_id, p_engine, p_category, p_severity, p_priority,
      p_title, p_description, coalesce(p_evidence, '{}'::jsonb),
      coalesce(p_source_references, '[]'::jsonb), coalesce(p_confidence, 1.0),
      now(), 'new_insight', now(), now()
    ) returning id into v_id;
  end if;

  return v_id;
end $$;

grant execute on function public.erp_intelligence_insight_save_v830(uuid,uuid,text,text,text,text,text,text,jsonb,jsonb,numeric,text) to authenticated;

create or replace function public.erp_intelligence_insight_status_v830(
  p_tenant_id uuid,
  p_insight_id uuid,
  p_status text,
  p_resolution_note text default null
) returns boolean
language plpgsql security definer set search_path=public,private,pg_temp
as $$
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  update public.erp_intelligence_insights
  set status = p_status,
      resolution_note = coalesce(p_resolution_note, resolution_note),
      resolved_by = case when p_status in ('resolved', 'dismissed') then auth.uid() else resolved_by end,
      resolved_at = case when p_status in ('resolved', 'dismissed') then now() else resolved_at end,
      updated_at = now()
  where id = p_insight_id and tenant_id = p_tenant_id;

  return found;
end $$;

grant execute on function public.erp_intelligence_insight_status_v830(uuid,uuid,text,text) to authenticated;

create or replace function public.erp_intelligence_insights_list_v830(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_engine text default null,
  p_severity text default null,
  p_status text default null,
  p_query text default '',
  p_limit integer default 200,
  p_offset integer default 0
) returns table(
  id uuid,
  location_id uuid,
  engine text,
  category text,
  severity text,
  priority text,
  title text,
  description text,
  evidence jsonb,
  source_references jsonb,
  confidence numeric,
  data_freshness timestamptz,
  status text,
  resolution_note text,
  resolved_by uuid,
  resolved_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  q text := '%' || lower(trim(coalesce(p_query, ''))) || '%';
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  return query
  select i.id, i.location_id, i.engine, i.category, i.severity, i.priority,
         i.title, i.description, i.evidence, i.source_references, i.confidence,
         i.data_freshness, i.status, i.resolution_note, i.resolved_by, i.resolved_at,
         i.created_at, i.updated_at
  from public.erp_intelligence_insights i
  where i.tenant_id = p_tenant_id
    and (p_location_id is null or i.location_id is null or i.location_id = p_location_id)
    and (p_engine is null or i.engine = p_engine)
    and (p_severity is null or i.severity = p_severity)
    and (p_status is null or i.status = p_status)
    and (trim(coalesce(p_query, '')) = '' or lower(i.title) like q or lower(i.description) like q or lower(i.category) like q)
  order by 
    case when i.severity = 'critical' then 1
         when i.severity = 'warning' then 2
         when i.severity = 'opportunity' then 3
         else 4 end,
    case when i.priority = 'urgent' then 1
         when i.priority = 'high' then 2
         when i.priority = 'medium' then 3
         else 4 end,
    i.created_at desc
  limit greatest(1, least(coalesce(p_limit, 200), 1000))
  offset greatest(0, coalesce(p_offset, 0));
end $$;

grant execute on function public.erp_intelligence_insights_list_v830(uuid,uuid,text,text,text,text,integer,integer) to authenticated;

-- ============================================================================
-- 4. ACTION MANAGEMENT RPCS
-- ============================================================================

create or replace function public.erp_intelligence_action_create_v830(
  p_tenant_id uuid,
  p_location_id uuid,
  p_insight_id uuid,
  p_action_type text,
  p_payload jsonb,
  p_preview_summary text,
  p_required_permission text default 'inventory.manage'
) returns uuid
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_id uuid;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  insert into public.erp_intelligence_actions(
    tenant_id, location_id, insight_id, action_type, payload,
    preview_summary, required_permission, status, created_by, created_at, updated_at
  ) values (
    p_tenant_id, p_location_id, p_insight_id, p_action_type, coalesce(p_payload, '{}'::jsonb),
    p_preview_summary, coalesce(p_required_permission, 'inventory.manage'),
    'pending_approval', auth.uid(), now(), now()
  ) returning id into v_id;

  return v_id;
end $$;

grant execute on function public.erp_intelligence_action_create_v830(uuid,uuid,uuid,text,jsonb,text,text) to authenticated;

create or replace function public.erp_intelligence_action_decide_v830(
  p_tenant_id uuid,
  p_action_id uuid,
  p_approve boolean,
  p_note text default ''
) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_act public.erp_intelligence_actions%rowtype;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  select * into v_act
  from public.erp_intelligence_actions
  where id = p_action_id and tenant_id = p_tenant_id
  for update;

  if not found then
    raise exception 'Intelligence action not found';
  end if;

  -- Verify required permission
  if not private.erp_user_is_owner(p_tenant_id) and not private.erp_has_permission(p_tenant_id, v_act.required_permission) then
    raise exception 'Permission % required to decide this action', v_act.required_permission;
  end if;

  if v_act.status <> 'pending_approval' then
    raise exception 'Action cannot be decided because it is currently %', v_act.status;
  end if;

  update public.erp_intelligence_actions
  set status = case when p_approve then 'approved' else 'rejected' end,
      approved_by = auth.uid(),
      approved_at = now(),
      execution_result = jsonb_build_object('decision_note', p_note),
      updated_at = now()
  where id = p_action_id;

  return jsonb_build_object(
    'action_id', p_action_id,
    'status', case when p_approve then 'approved' else 'rejected' end,
    'approved_by', auth.uid(),
    'approved_at', now()
  );
end $$;

grant execute on function public.erp_intelligence_action_decide_v830(uuid,uuid,boolean,text) to authenticated;

create or replace function public.erp_intelligence_actions_list_v830(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_status text default null,
  p_limit integer default 200
) returns setof jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  r record;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  for r in
    select a.*, i.title as insight_title, i.severity as insight_severity
    from public.erp_intelligence_actions a
    left join public.erp_intelligence_insights i on i.id = a.insight_id
    where a.tenant_id = p_tenant_id
      and (p_location_id is null or a.location_id is null or a.location_id = p_location_id)
      and (p_status is null or a.status = p_status)
    order by a.created_at desc
    limit greatest(1, least(coalesce(p_limit, 200), 500))
  loop
    return next to_jsonb(r);
  end loop;
  return;
end $$;

grant execute on function public.erp_intelligence_actions_list_v830(uuid,uuid,text,integer) to authenticated;

-- ============================================================================
-- 5. UPGRADED COMPREHENSIVE INVENTORY INTELLIGENCE RPC
-- ============================================================================

create or replace function public.inventory_intelligence_v830(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_days integer default 30,
  p_query text default '',
  p_limit integer default 1000
) returns table(
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
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_from date := current_date - (v_days - 1);
  q text := '%' || lower(trim(coalesce(p_query, ''))) || '%';
  v_can_view_cost boolean := false;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
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
      ), 0), 0))::numeric qty
    from public.sale_items si
    join public.sales s on s.id = si.sale_id
    left join public.document_origins o on o.tenant_id = p_tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
    where s.tenant_id = p_tenant_id
      and s.sale_date between v_from and current_date
      and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
      and (o.location_id is null or private.erp_document_scope_allowed(p_tenant_id, o.location_id, p_location_id, 'view'))
    group by o.location_id, si.variant_id
  ),
  last_sold as (
    select o.location_id, si.variant_id, max(s.sale_date) last_sale
    from public.sale_items si
    join public.sales s on s.id = si.sale_id
    left join public.document_origins o on o.tenant_id = p_tenant_id and o.entity_type = 'sale' and o.entity_id = s.id
    where s.tenant_id = p_tenant_id
      and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or o.location_id = p_location_id)
    group by o.location_id, si.variant_id
  ),
  purchased as (
    select loc_id, var_id, max(dt) last_purchase
    from (
      select coalesce(o.location_id, p.location_id) as loc_id, pi.variant_id as var_id, max(p.purchase_date) as dt
      from public.purchase_items pi
      join public.purchases p on p.id = pi.purchase_id
      left join public.document_origins o on o.tenant_id = p_tenant_id and o.entity_type = 'purchase' and o.entity_id = p.id
      where p.tenant_id = p_tenant_id and coalesce(p.status, '') not in ('void', 'cancelled')
      group by 1, 2
      union all
      select g.location_id as loc_id, gi.variant_id as var_id, max(g.receipt_date) as dt
      from public.goods_receipt_items_v484 gi
      join public.goods_receipts_v484 g on g.id = gi.goods_receipt_id
      where g.tenant_id = p_tenant_id and g.status = 'posted'
      group by 1, 2
    ) u
    group by loc_id, var_id
  ),
  base as (
    select 
      l.id as location_id,
      l.location_code,
      l.name as location_name,
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
    from public.product_variants pv
    join public.products p on p.id = pv.product_id and p.tenant_id = pv.tenant_id
    cross join public.business_locations l
    left join public.location_product_settings s on s.tenant_id = pv.tenant_id and s.location_id = l.id and s.variant_id = pv.id
    left join public.location_stock_balances b on b.tenant_id = pv.tenant_id and b.location_id = l.id and b.variant_id = pv.id
    left join sold so on so.location_id = l.id and so.variant_id = pv.id
    left join last_sold ls on ls.location_id = l.id and ls.variant_id = pv.id
    left join purchased pu on pu.loc_id = l.id and pu.var_id = pv.id
    where pv.tenant_id = p_tenant_id
      and l.tenant_id = p_tenant_id
      and l.active = true
      and (p_location_id is null or l.id = p_location_id)
      and (trim(coalesce(p_query, '')) = '' or lower(p.name) like q or lower(coalesce(pv.sku, '')) like q or lower(coalesce(pv.barcode, '')) like q or lower(coalesce(pv.part_number, '')) like q)
      and (b.quantity > 0 or so.qty > 0 or s.reorder_level > 0 or pv.reorder_level > 0)
  ),
  ranked as (
    select b.*,
      round(b.quantity * b.average_cost, 2)::numeric as stock_val,
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
    r.max_stock, r.average_cost, r.stock_val, r.net_sold_qty, r.daily_sales,
    r.cover_days, r.reorder_qty, r.last_sale, r.last_purchase,
    r.stock_status::text,
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

grant execute on function public.inventory_intelligence_v830(uuid,uuid,integer,text,integer) to authenticated;

-- ============================================================================
-- 6. COMPREHENSIVE OPERATIONS INTELLIGENCE EXECUTIVE SUMMARY RPC
-- ============================================================================

create or replace function public.operations_intelligence_summary_v830(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_days integer default 30
) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v_days integer := greatest(1, least(coalesce(p_days, 30), 365));
  v_from date := current_date - (v_days - 1);
  v_sales numeric := 0;
  v_returns numeric := 0;
  v_cost numeric := 0;
  v_expenses numeric := 0;
  v_receivable numeric := 0;
  v_overdue_recv numeric := 0;
  v_payable numeric := 0;
  v_overdue_pay numeric := 0;
  v_inventory_val numeric := 0;
  v_low_stock bigint := 0;
  v_out_of_stock bigint := 0;
  v_dead_stock bigint := 0;
  v_overstock bigint := 0;
  v_total_variants bigint := 0;
  v_order_count bigint := 0;
  v_aov numeric := 0;
  v_unresolved_insights bigint := 0;
  v_critical_insights bigint := 0;
  v_pending_actions bigint := 0;
  v_pipeline jsonb;
  v_hourly jsonb := '[]'::jsonb;
  v_top_products jsonb := '[]'::jsonb;
  v_can_view_cost boolean := false;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied';
  end if;

  v_can_view_cost := private.erp_user_is_owner(p_tenant_id) 
    or private.erp_has_permission(p_tenant_id, 'inventory.view_cost')
    or private.erp_has_permission(p_tenant_id, 'inventory.manage');

  -- Sales & Revenue metrics
  select coalesce(sum(grand_total), 0), coalesce(sum(cost_total), 0), count(*)
    into v_sales, v_cost, v_order_count
  from public.sales
  where tenant_id = p_tenant_id
    and sale_date between v_from and current_date
    and coalesce(status, '') not in ('void', 'cancelled')
    and (p_location_id is null or location_id = p_location_id);

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
  v_pipeline := public.operations_pipeline_v489(p_tenant_id, p_location_id);

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

  -- Top 10 selling products
  select coalesce(jsonb_agg(to_jsonb(tp)), '[]'::jsonb)
  into v_top_products
  from (
    select pr.name as product_name, pv.sku, sum(si.quantity) as quantity_sold, round(sum(si.line_total), 2) as revenue
    from public.sale_items si
    join public.sales s on s.id = si.sale_id
    join public.product_variants pv on pv.id = si.variant_id
    join public.products pr on pr.id = pv.product_id
    where s.tenant_id = p_tenant_id
      and s.sale_date between v_from and current_date
      and coalesce(s.status, '') not in ('void', 'cancelled')
      and (p_location_id is null or s.location_id = p_location_id)
    group by pr.name, pv.sku
    order by revenue desc
    limit 10
  ) tp;

  -- Hourly distribution
  select coalesce(jsonb_agg(to_jsonb(h)), '[]'::jsonb)
  into v_hourly
  from (
    select extract(hour from created_at)::int as hour, count(*) as count, round(sum(grand_total), 2) as revenue
    from public.sales
    where tenant_id = p_tenant_id
      and sale_date between v_from and current_date
      and coalesce(status, '') not in ('void', 'cancelled')
      and (p_location_id is null or location_id = p_location_id)
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
    'low_stock_count', v_low_stock,
    'out_of_stock_count', v_out_of_stock,
    'dead_stock_count', v_dead_stock,
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
  );
end $$;

grant execute on function public.operations_intelligence_summary_v830(uuid,uuid,integer) to authenticated;

-- Record Schema Release
insert into public.thq_schema_releases(migration_no, schema_version, release_name, notes)
values(
  226, '8.3.0', 'Operations Intelligence Platform Core',
  'Unified Operations Intelligence store: insights table, actions workflow, comprehensive inventory intelligence v830, and executive operational summary.'
) on conflict(migration_no) do update set 
  schema_version = excluded.schema_version,
  release_name = excluded.release_name,
  notes = excluded.notes;

commit;
