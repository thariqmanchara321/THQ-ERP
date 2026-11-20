-- THQ ERP v8.3.6 — Operations Intelligence Phase 7: Shared Intelligence Framework, Centralized Risk Detection & Action Centre
-- Author: Antigravity Senior Engineering Team
-- Date: 2026-11-20
-- Release: #712 (v8.3.6)
-- Scope: Centralized finding ingestion, stable deduplication, cross-engine correlation, transparent prioritization, lifecycle transitions & audit history.

begin;

-- ============================================================================
-- 1. EXTEND CANONICAL INSIGHTS TABLE WITH PHASE 7 MODEL
-- ============================================================================

-- Update check constraints on public.erp_intelligence_insights
alter table public.erp_intelligence_insights drop constraint if exists erp_intelligence_insights_engine_check;
alter table public.erp_intelligence_insights add constraint erp_intelligence_insights_engine_check
  check (engine in (
    'executive', 'sales', 'inventory', 'rebalancing', 'procurement', 'supplier', 
    'customer', 'customer_credit', 'financial', 'expense', 'cross_engine', 
    'operations', 'workforce', 'risk_anomaly', 'predictive', 'simulation'
  ));

alter table public.erp_intelligence_insights drop constraint if exists erp_intelligence_insights_severity_check;
alter table public.erp_intelligence_insights add constraint erp_intelligence_insights_severity_check
  check (severity in (
    'informational', 'info', 'low', 'medium', 'warning', 'high', 'critical', 'opportunity'
  ));

alter table public.erp_intelligence_insights drop constraint if exists erp_intelligence_insights_status_check;
alter table public.erp_intelligence_insights add constraint erp_intelligence_insights_status_check
  check (status in (
    'new', 'new_insight', 'acknowledged', 'under_review', 'accepted', 'rejected', 
    'approved', 'executed', 'completed', 'failed', 'resolved', 'dismissed', 'reopened'
  ));

-- Add columns for finding identity, rule, affected entity, deduplication, scoring and audit
alter table public.erp_intelligence_insights add column if not exists detection_rule text default '';
alter table public.erp_intelligence_insights add column if not exists rule_code text default '';
alter table public.erp_intelligence_insights add column if not exists affected_entity_type text default '';
alter table public.erp_intelligence_insights add column if not exists affected_entity_id text default '';
alter table public.erp_intelligence_insights add column if not exists affected_record_ref text default '';
alter table public.erp_intelligence_insights add column if not exists baseline_period jsonb default '{}'::jsonb;
alter table public.erp_intelligence_insights add column if not exists recommended_action jsonb default '{}'::jsonb;
alter table public.erp_intelligence_insights add column if not exists dedup_key text;
alter table public.erp_intelligence_insights add column if not exists occurrence_count integer not null default 1;
alter table public.erp_intelligence_insights add column if not exists first_detected_at timestamptz not null default now();
alter table public.erp_intelligence_insights add column if not exists last_detected_at timestamptz not null default now();
alter table public.erp_intelligence_insights add column if not exists priority_score numeric not null default 0;
alter table public.erp_intelligence_insights add column if not exists priority_reason text default '';
alter table public.erp_intelligence_insights add column if not exists impacted_amount numeric default 0.0;
alter table public.erp_intelligence_insights add column if not exists is_cross_engine boolean not null default false;
alter table public.erp_intelligence_insights add column if not exists contributing_findings jsonb default '[]'::jsonb;
alter table public.erp_intelligence_insights add column if not exists assigned_to uuid references auth.users(id) on delete set null;

create index if not exists idx_erp_intelligence_insights_dedup 
  on public.erp_intelligence_insights(tenant_id, dedup_key);

create index if not exists idx_erp_intelligence_insights_priority 
  on public.erp_intelligence_insights(tenant_id, priority_score desc, last_detected_at desc);

create index if not exists idx_erp_intelligence_insights_rule 
  on public.erp_intelligence_insights(tenant_id, engine, rule_code);

-- ============================================================================
-- 2. ACTIONS TABLE LIFECYCLE CONSTRAINT UPDATE
-- ============================================================================

alter table public.erp_intelligence_actions drop constraint if exists erp_intelligence_actions_status_check;
alter table public.erp_intelligence_actions add constraint erp_intelligence_actions_status_check
  check (status in (
    'pending_approval', 'under_review', 'accepted', 'approved', 'rejected', 'executed', 'completed', 'failed', 'dismissed'
  ));

-- ============================================================================
-- 3. REVIEW & AUDIT HISTORY TABLE
-- ============================================================================

create table if not exists public.erp_intelligence_finding_reviews(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  finding_id uuid not null references public.erp_intelligence_insights(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  user_name text default '',
  action text not null,
  from_status text,
  to_status text,
  review_notes text default '',
  assigned_to uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_erp_intelligence_reviews_finding 
  on public.erp_intelligence_finding_reviews(tenant_id, finding_id, created_at desc);

alter table public.erp_intelligence_finding_reviews enable row level security;

drop policy if exists "erp_intelligence_finding_reviews_tenant_read" on public.erp_intelligence_finding_reviews;
create policy "erp_intelligence_finding_reviews_tenant_read" on public.erp_intelligence_finding_reviews
  for select using (private.erp_user_has_tenant_access(tenant_id));

drop policy if exists "erp_intelligence_finding_reviews_tenant_write" on public.erp_intelligence_finding_reviews;
create policy "erp_intelligence_finding_reviews_tenant_write" on public.erp_intelligence_finding_reviews
  for insert with check (private.erp_user_has_tenant_access(tenant_id));

revoke all on public.erp_intelligence_finding_reviews from anon, public;
grant all on public.erp_intelligence_finding_reviews to authenticated, service_role;

-- ============================================================================
-- 4. CENTRALIZED INGESTION & DEDUPLICATION RPC
-- ============================================================================

create or replace function public.erp_intelligence_ingest_findings_v830(
  p_tenant_id uuid,
  p_findings jsonb,
  p_auto_resolve boolean default false,
  p_engine text default null,
  p_location_id uuid default null
) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_item jsonb;
  v_finding_id uuid;
  v_existing_id uuid;
  v_existing_status text;
  v_dedup_key text;
  v_severity text;
  v_priority text;
  v_engine text;
  v_confidence numeric;
  v_impact numeric;
  v_score numeric;
  v_reason text;
  v_rule_code text;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_reopened integer := 0;
  v_resolved integer := 0;
  v_seen_keys text[] := '{}';
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied to tenant %', p_tenant_id;
  end if;

  if p_findings is null or jsonb_typeof(p_findings) <> 'array' then
    return jsonb_build_object(
      'success', true,
      'inserted', 0,
      'updated', 0,
      'reopened', 0,
      'auto_resolved', 0,
      'total_processed', 0
    );
  end if;

  for v_item in select * from jsonb_array_elements(p_findings)
  loop
    v_engine := coalesce(v_item->>'engine', 'operations');
    v_rule_code := coalesce(v_item->>'rule_code', 'GENERIC_ANOMALY');
    v_severity := lower(coalesce(v_item->>'severity', 'medium'));
    if v_severity not in ('informational', 'info', 'low', 'medium', 'warning', 'high', 'critical', 'opportunity') then
      v_severity := 'medium';
    end if;

    v_confidence := coalesce((v_item->>'confidence')::numeric, 1.0);
    v_impact := coalesce((v_item->>'impacted_amount')::numeric, 0.0);

    -- 1. Compute stable deduplication key
    v_dedup_key := coalesce(
      v_item->>'dedup_key',
      md5(p_tenant_id::text || ':' || v_engine || ':' || v_rule_code || ':' || 
          coalesce(v_item->>'affected_entity_type', '') || ':' || 
          coalesce(v_item->>'affected_entity_id', '') || ':' || 
          coalesce(v_item->>'location_id', ''))
    );
    v_seen_keys := array_append(v_seen_keys, v_dedup_key);

    -- 2. Compute transparent priority score & reason
    -- Base score: critical=100, high=70, medium=40, low/warning=25, info=10
    v_score := case 
      when v_severity = 'critical' then 100
      when v_severity in ('high', 'urgent') then 70
      when v_severity in ('medium', 'warning') then 40
      when v_severity in ('low') then 25
      else 10 
    end;

    v_reason := 'Severity: ' || initcap(v_severity) || ' (' || v_score::text || ')';

    -- Financial impact boost
    if v_impact >= 100000 then
      v_score := v_score + 25;
      v_reason := v_reason || ' + High Impact (>100k: +25)';
    elsif v_impact >= 25000 then
      v_score := v_score + 15;
      v_reason := v_reason || ' + Impact (>25k: +15)';
    elsif v_impact >= 5000 then
      v_score := v_score + 5;
      v_reason := v_reason || ' + Impact (>5k: +5)';
    end if;

    -- Multi-location or cross-engine boost
    if coalesce((v_item->>'is_cross_engine')::boolean, false) or (v_item->>'location_id') is null then
      v_score := v_score + 10;
      v_reason := v_reason || ' + Systemic/Cross-Engine (+10)';
    end if;

    -- Confidence weighting
    if v_confidence < 1.0 then
      v_score := round(v_score * v_confidence, 1);
      v_reason := v_reason || ' * Conf (' || v_confidence::text || ')';
    end if;

    v_priority := case
      when v_score >= 100 then 'urgent'
      when v_score >= 70 then 'high'
      when v_score >= 35 then 'medium'
      else 'low'
    end;

    -- 3. Check existing finding by dedup_key
    select id, status into v_existing_id, v_existing_status
    from public.erp_intelligence_insights
    where tenant_id = p_tenant_id
      and dedup_key = v_dedup_key
    order by created_at desc
    limit 1;

    if v_existing_id is not null then
      if v_existing_status in ('resolved', 'dismissed') then
        -- Condition recurred after being resolved: reopen finding
        update public.erp_intelligence_insights
        set status = 'new',
            title = coalesce(v_item->>'title', title),
            description = coalesce(v_item->>'description', description),
            severity = v_severity,
            priority = v_priority,
            priority_score = v_score,
            priority_reason = v_reason,
            confidence = v_confidence,
            impacted_amount = v_impact,
            evidence = coalesce(v_item->'evidence', evidence),
            baseline_period = coalesce(v_item->'baseline_period', baseline_period),
            recommended_action = coalesce(v_item->'recommended_action', recommended_action),
            contributing_findings = coalesce(v_item->'contributing_findings', contributing_findings),
            source_references = coalesce(v_item->'source_references', source_references),
            last_detected_at = now(),
            data_freshness = now(),
            occurrence_count = occurrence_count + 1,
            resolved_at = null,
            resolved_by = null,
            resolution_note = null,
            updated_at = now()
        where id = v_existing_id;

        insert into public.erp_intelligence_finding_reviews(
          tenant_id, finding_id, user_id, user_name, action, from_status, to_status, review_notes
        ) values (
          p_tenant_id, v_existing_id, auth.uid(), 'System Re-scan', 'reopened', v_existing_status, 'new',
          'Finding condition re-detected during intelligence diagnostic scan.'
        );
        v_reopened := v_reopened + 1;
      else
        -- Active finding continues: update metrics, freshness and occurrence count idempotently
        update public.erp_intelligence_insights
        set title = coalesce(v_item->>'title', title),
            description = coalesce(v_item->>'description', description),
            severity = v_severity,
            priority = v_priority,
            priority_score = v_score,
            priority_reason = v_reason,
            confidence = v_confidence,
            impacted_amount = v_impact,
            evidence = coalesce(v_item->'evidence', evidence),
            recommended_action = coalesce(v_item->'recommended_action', recommended_action),
            contributing_findings = coalesce(v_item->'contributing_findings', contributing_findings),
            source_references = coalesce(v_item->'source_references', source_references),
            last_detected_at = now(),
            data_freshness = now(),
            occurrence_count = occurrence_count + 1,
            updated_at = now()
        where id = v_existing_id;
        v_updated := v_updated + 1;
      end if;
    else
      -- 4. Insert new finding
      insert into public.erp_intelligence_insights(
        tenant_id, location_id, engine, category, severity, priority,
        priority_score, priority_reason, title, description, detection_rule,
        rule_code, affected_entity_type, affected_entity_id, affected_record_ref,
        evidence, baseline_period, recommended_action, dedup_key, confidence,
        impacted_amount, is_cross_engine, contributing_findings, source_references,
        data_freshness, status, occurrence_count, first_detected_at, last_detected_at,
        created_at, updated_at
      ) values (
        p_tenant_id,
        case when (v_item->>'location_id') is not null and trim(v_item->>'location_id') <> '' 
             then (v_item->>'location_id')::uuid else null end,
        v_engine,
        coalesce(v_item->>'category', 'general'),
        v_severity,
        v_priority,
        v_score,
        v_reason,
        coalesce(v_item->>'title', 'Untitled Intelligence Finding'),
        coalesce(v_item->>'description', ''),
        coalesce(v_item->>'detection_rule', ''),
        v_rule_code,
        coalesce(v_item->>'affected_entity_type', ''),
        coalesce(v_item->>'affected_entity_id', ''),
        coalesce(v_item->>'affected_record_ref', ''),
        coalesce(v_item->'evidence', '{}'::jsonb),
        coalesce(v_item->'baseline_period', '{}'::jsonb),
        coalesce(v_item->'recommended_action', '{}'::jsonb),
        v_dedup_key,
        v_confidence,
        v_impact,
        coalesce((v_item->>'is_cross_engine')::boolean, false),
        coalesce(v_item->'contributing_findings', '[]'::jsonb),
        coalesce(v_item->'source_references', '[]'::jsonb),
        now(),
        'new',
        1,
        now(),
        now(),
        now(),
        now()
      ) returning id into v_finding_id;

      insert into public.erp_intelligence_finding_reviews(
        tenant_id, finding_id, user_id, user_name, action, from_status, to_status, review_notes
      ) values (
        p_tenant_id, v_finding_id, auth.uid(), 'System Ingestion', 'initial_detection', null, 'new',
        'Initial finding recorded with priority score ' || v_score::text
      );
      v_inserted := v_inserted + 1;
    end if;
  end loop;

  -- 5. Auto-resolve stale findings if requested
  if p_auto_resolve and array_length(v_seen_keys, 1) > 0 then
    update public.erp_intelligence_insights
    set status = 'resolved',
        resolved_at = now(),
        resolved_by = auth.uid(),
        resolution_note = 'Auto-resolved: condition no longer detected in latest scan.',
        updated_at = now()
    where tenant_id = p_tenant_id
      and (p_engine is null or engine = p_engine)
      and (p_location_id is null or location_id = p_location_id)
      and status in ('new', 'under_review', 'accepted')
      and not (dedup_key = any(v_seen_keys));
    get diagnostics v_resolved = row_count;
  end if;

  return jsonb_build_object(
    'success', true,
    'inserted', v_inserted,
    'updated', v_updated,
    'reopened', v_reopened,
    'auto_resolved', v_resolved,
    'total_processed', v_inserted + v_updated + v_reopened
  );
end $$;

grant execute on function public.erp_intelligence_ingest_findings_v830(uuid,jsonb,boolean,text,uuid) to authenticated, service_role;

-- ============================================================================
-- 5. DETERMINISTIC MULTI-ENGINE SCAN & SYNC RPC
-- ============================================================================

create or replace function public.erp_intelligence_scan_and_sync_v830(
  p_tenant_id uuid,
  p_location_id uuid default null
) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_findings jsonb := '[]'::jsonb;
  v_rec record;
  v_ingest_res jsonb;
  v_sales_decline_variants uuid[] := '{}';
  v_overstock_variants uuid[] := '{}';
  v_low_cover_variants uuid[] := '{}';
  v_delayed_suppliers uuid[] := '{}';
  v_has_overdue_debt boolean := false;
  v_cash_balance numeric := 0.0;
  v_tb_diff numeric := 0.0;
  v_cross_engine_count integer := 0;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied to tenant %', p_tenant_id;
  end if;

  -- --------------------------------------------------------------------------
  -- ENGINE 1: Sales Intelligence
  -- --------------------------------------------------------------------------
  -- 1.1 Sharp Sales Drop (>50% drop vs preceding 30d window, prior >= 5)
  for v_rec in (
    select v.id as variant_id, v.sku, p.name as product_name, v.name as variant_name,
           coalesce(cur.qty, 0) as cur_qty, coalesce(prior.qty, 0) as prior_qty,
           coalesce(cur.rev, 0) as cur_rev, coalesce(prior.rev, 0) as prior_rev
    from public.product_variants v
    join public.products p on p.id = v.product_id
    join (
      select si.variant_id, sum(si.quantity) as qty, sum(si.line_total) as rev
      from public.sale_items si
      join public.sales s on s.id = si.sale_id
      where s.tenant_id = p_tenant_id and s.status = 'completed'
        and s.created_at >= now() - interval '60 days' and s.created_at < now() - interval '30 days'
      group by si.variant_id
      having sum(si.quantity) >= 5
    ) prior on prior.variant_id = v.id
    left join (
      select si.variant_id, sum(si.quantity) as qty, sum(si.line_total) as rev
      from public.sale_items si
      join public.sales s on s.id = si.sale_id
      where s.tenant_id = p_tenant_id and s.status = 'completed'
        and s.created_at >= now() - interval '30 days'
      group by si.variant_id
    ) cur on cur.variant_id = v.id
    where p.tenant_id = p_tenant_id
      and coalesce(cur.qty, 0) <= (prior.qty * 0.5)
    limit 20
  ) loop
    v_sales_decline_variants := array_append(v_sales_decline_variants, v_rec.variant_id);
    v_findings := v_findings || jsonb_build_object(
      'engine', 'sales',
      'category', 'demand_contraction',
      'severity', 'warning',
      'rule_code', 'SALES_SHARP_DECLINE',
      'detection_rule', 'Sales volume decreased by >= 50% compared to preceding 30-day window.',
      'title', 'Sharp Sales Drop: ' || v_rec.product_name,
      'description', 'Sales volume fell from ' || v_rec.prior_qty::text || ' units to ' || v_rec.cur_qty::text || ' units.',
      'affected_entity_type', 'product_variant',
      'affected_entity_id', v_rec.variant_id::text,
      'affected_record_ref', coalesce(v_rec.sku, '') || ' / ' || v_rec.product_name,
      'location_id', p_location_id,
      'evidence', jsonb_build_object(
        'current_quantity', v_rec.cur_qty,
        'prior_quantity', v_rec.prior_qty,
        'drop_pct', round((1.0 - (v_rec.cur_qty / nullif(v_rec.prior_qty, 0))) * 100, 1),
        'prior_revenue', v_rec.prior_rev,
        'current_revenue', v_rec.cur_rev
      ),
      'baseline_period', jsonb_build_object('days', 30),
      'confidence', 0.95,
      'impacted_amount', greatest(0, v_rec.prior_rev - v_rec.cur_rev),
      'recommended_action', jsonb_build_object(
        'action_type', 'review_product_demand',
        'label', 'Inspect Product Sales & Pricing',
        'route', '/inventory'
      )
    );
  end loop;

  -- --------------------------------------------------------------------------
  -- ENGINE 2: Inventory Intelligence
  -- --------------------------------------------------------------------------
  -- 2.1 Critical Stockout Risk (cover < 3 days or stock = 0 with demand)
  for v_rec in (
    select b.location_id, b.variant_id, v.sku, p.name as product_name, v.name as variant_name,
           b.quantity as stock_on_hand, b.average_cost,
           coalesce(vel.daily_velocity, 0.0) as daily_velocity,
           case when coalesce(vel.daily_velocity, 0) > 0 then round(b.quantity / vel.daily_velocity, 1) else 999.0 end as cover_days
    from public.location_stock_balances b
    join public.product_variants v on v.id = b.variant_id
    join public.products p on p.id = v.product_id
    join (
      select si.variant_id, sum(si.quantity) / 30.0 as daily_velocity
      from public.sale_items si
      join public.sales s on s.id = si.sale_id
      where s.tenant_id = p_tenant_id and s.status = 'completed'
        and s.created_at >= now() - interval '30 days'
      group by si.variant_id
      having sum(si.quantity) >= 3
    ) vel on vel.variant_id = b.variant_id
    where b.tenant_id = p_tenant_id
      and (p_location_id is null or b.location_id = p_location_id)
      and (b.quantity <= 0 or (b.quantity / nullif(vel.daily_velocity, 0)) < 3.0)
    limit 20
  ) loop
    v_low_cover_variants := array_append(v_low_cover_variants, v_rec.variant_id);
    v_findings := v_findings || jsonb_build_object(
      'engine', 'inventory',
      'category', 'stockout_risk',
      'severity', 'critical',
      'rule_code', 'INV_CRITICAL_STOCKOUT',
      'detection_rule', 'Stock cover is under 3 days with active daily consumer demand.',
      'title', 'Critical Stockout Risk: ' || v_rec.product_name,
      'description', 'Stock on hand is ' || v_rec.stock_on_hand::text || ' units (' || v_rec.cover_days::text || ' days cover). Daily velocity is ' || round(v_rec.daily_velocity, 2)::text || ' units/day.',
      'affected_entity_type', 'product_variant',
      'affected_entity_id', v_rec.variant_id::text,
      'affected_record_ref', coalesce(v_rec.sku, '') || ' / ' || v_rec.product_name,
      'location_id', v_rec.location_id,
      'evidence', jsonb_build_object(
        'stock_on_hand', v_rec.stock_on_hand,
        'daily_velocity', round(v_rec.daily_velocity, 2),
        'stock_cover_days', v_rec.cover_days
      ),
      'confidence', 0.95,
      'impacted_amount', round(v_rec.daily_velocity * 14 * coalesce(v_rec.average_cost, 0), 2),
      'recommended_action', jsonb_build_object(
        'action_type', 'create_replenishment',
        'label', 'Order / Rebalance Replenishment',
        'route', '/purchases'
      )
    );
  end loop;

  -- 2.2 Overstocking & Capital Lock (> 90 days cover with tied capital > 10,000)
  for v_rec in (
    select b.location_id, b.variant_id, v.sku, p.name as product_name, v.name as variant_name,
           b.quantity as stock_on_hand, b.average_cost,
           round(b.quantity * coalesce(b.average_cost, 0), 2) as tied_capital,
           coalesce(vel.daily_velocity, 0.0) as daily_velocity,
           case when coalesce(vel.daily_velocity, 0) > 0 then round(b.quantity / vel.daily_velocity, 1) else 999.0 end as cover_days
    from public.location_stock_balances b
    join public.product_variants v on v.id = b.variant_id
    join public.products p on p.id = v.product_id
    left join (
      select si.variant_id, sum(si.quantity) / 30.0 as daily_velocity
      from public.sale_items si
      join public.sales s on s.id = si.sale_id
      where s.tenant_id = p_tenant_id and s.status = 'completed'
        and s.created_at >= now() - interval '30 days'
      group by si.variant_id
    ) vel on vel.variant_id = b.variant_id
    where b.tenant_id = p_tenant_id
      and (p_location_id is null or b.location_id = p_location_id)
      and b.quantity > 10
      and (b.quantity * coalesce(b.average_cost, 0)) >= 10000
      and (vel.daily_velocity is null or (b.quantity / nullif(vel.daily_velocity, 0)) > 90.0)
    limit 15
  ) loop
    v_overstock_variants := array_append(v_overstock_variants, v_rec.variant_id);
    v_findings := v_findings || jsonb_build_object(
      'engine', 'inventory',
      'category', 'excess_capital',
      'severity', 'medium',
      'rule_code', 'INV_OVERSTOCK_CAPITAL',
      'detection_rule', 'Stock cover exceeds 90 days with substantial capital tied in inventory.',
      'title', 'Excess Inventory Capital: ' || v_rec.product_name,
      'description', 'Current stock of ' || v_rec.stock_on_hand::text || ' units represents ' || v_rec.cover_days::text || ' days cover with tied capital.',
      'affected_entity_type', 'product_variant',
      'affected_entity_id', v_rec.variant_id::text,
      'affected_record_ref', coalesce(v_rec.sku, '') || ' / ' || v_rec.product_name,
      'location_id', v_rec.location_id,
      'evidence', jsonb_build_object(
        'stock_on_hand', v_rec.stock_on_hand,
        'stock_cover_days', v_rec.cover_days,
        'tied_capital', v_rec.tied_capital
      ),
      'confidence', 0.90,
      'impacted_amount', v_rec.tied_capital,
      'recommended_action', jsonb_build_object(
        'action_type', 'review_stock_holding',
        'label', 'Check Reorder Limits & Promotions',
        'route', '/inventory'
      )
    );
  end loop;

  -- --------------------------------------------------------------------------
  -- ENGINE 3: Inter-Store Rebalancing Intelligence
  -- --------------------------------------------------------------------------
  for v_rec in (
    select b1.variant_id, v.sku, p.name as product_name,
           b1.location_id as shortage_loc_id, loc1.name as shortage_loc_name, b1.quantity as shortage_stock,
           b2.location_id as surplus_loc_id, loc2.name as surplus_loc_name, b2.quantity as surplus_stock,
           b1.average_cost
    from public.location_stock_balances b1
    join public.location_stock_balances b2 
      on b2.tenant_id = b1.tenant_id and b2.variant_id = b1.variant_id and b2.location_id <> b1.location_id
    join public.business_locations loc1 on loc1.id = b1.location_id
    join public.business_locations loc2 on loc2.id = b2.location_id
    join public.product_variants v on v.id = b1.variant_id
    join public.products p on p.id = v.product_id
    where b1.tenant_id = p_tenant_id
      and b1.quantity <= 2
      and b2.quantity >= 15
    limit 10
  ) loop
    v_findings := v_findings || jsonb_build_object(
      'engine', 'rebalancing',
      'category', 'inter_store_transfer',
      'severity', 'high',
      'rule_code', 'REBALANCE_TRANSFER_READY',
      'detection_rule', 'One store is in critical stockout while a sister branch holds surplus stock.',
      'title', 'Inter-Store Stock Disparity: ' || v_rec.product_name,
      'description', v_rec.shortage_loc_name || ' has only ' || v_rec.shortage_stock::text || ' units while ' || v_rec.surplus_loc_name || ' holds ' || v_rec.surplus_stock::text || ' units.',
      'affected_entity_type', 'product_variant',
      'affected_entity_id', v_rec.variant_id::text,
      'affected_record_ref', coalesce(v_rec.sku, '') || ' / ' || v_rec.product_name,
      'location_id', v_rec.shortage_loc_id,
      'evidence', jsonb_build_object(
        'shortage_location', v_rec.shortage_loc_name,
        'shortage_stock', v_rec.shortage_stock,
        'surplus_location', v_rec.surplus_loc_name,
        'surplus_stock', v_rec.surplus_stock,
        'suggested_transfer_units', least(10, floor(v_rec.surplus_stock * 0.4))
      ),
      'confidence', 0.95,
      'impacted_amount', round(least(10, floor(v_rec.surplus_stock * 0.4)) * coalesce(v_rec.average_cost, 0), 2),
      'recommended_action', jsonb_build_object(
        'action_type', 'create_stock_transfer',
        'label', 'Create Transfer from ' || v_rec.surplus_loc_name,
        'route', '/inventory',
        'payload', jsonb_build_object(
          'source_location_id', v_rec.surplus_loc_id,
          'target_location_id', v_rec.shortage_loc_id,
          'variant_id', v_rec.variant_id,
          'quantity', least(10, floor(v_rec.surplus_stock * 0.4))
        )
      )
    );
  end loop;

  -- --------------------------------------------------------------------------
  -- ENGINE 4: Supplier Intelligence
  -- --------------------------------------------------------------------------
  for v_rec in (
    select sup.id as supplier_id, sup.name as supplier_name,
           count(pu.id) as total_pos,
           count(pu.id) filter (where (pu.due_date < current_date and pu.status in ('ordered', 'pending', 'partial'))) as delayed_pos,
           coalesce(sum(pu.grand_total), 0) as total_spend
    from public.suppliers sup
    join public.purchases pu on pu.supplier_id = sup.id
    where sup.tenant_id = p_tenant_id
      and pu.created_at >= now() - interval '90 days'
    group by sup.id, sup.name
    having count(pu.id) >= 1
    limit 10
  ) loop
    v_delayed_suppliers := array_append(v_delayed_suppliers, v_rec.supplier_id);
    v_findings := v_findings || jsonb_build_object(
      'engine', 'supplier',
      'category', 'fulfillment_risk',
      'severity', 'high',
      'rule_code', 'SUPPLIER_DELIVERY_DELAYS',
      'detection_rule', 'Supplier has delayed or late shipments across historical purchase orders.',
      'title', 'Persistent Supplier Delivery Delays: ' || v_rec.supplier_name,
      'description', v_rec.supplier_name || ' delayed ' || v_rec.delayed_pos::text || ' of ' || v_rec.total_pos::text || ' recent orders.',
      'affected_entity_type', 'supplier',
      'affected_entity_id', v_rec.supplier_id::text,
      'affected_record_ref', v_rec.supplier_name,
      'location_id', p_location_id,
      'evidence', jsonb_build_object(
        'total_orders', v_rec.total_pos,
        'delayed_orders', v_rec.delayed_pos,
        'delay_rate_pct', round((v_rec.delayed_pos::numeric / nullif(v_rec.total_pos, 0)) * 100, 1),
        'total_spend', v_rec.total_spend
      ),
      'confidence', 0.90,
      'impacted_amount', v_rec.total_spend,
      'recommended_action', jsonb_build_object(
        'action_type', 'review_supplier_contract',
        'label', 'Inspect Supplier Performance',
        'route', '/purchases'
      )
    );
  end loop;

  -- --------------------------------------------------------------------------
  -- ENGINE 5: Customer Credit Intelligence
  -- --------------------------------------------------------------------------
  for v_rec in (
    select
      c.id as customer_id,
      c.name as customer_name,
      coalesce(c.credit_limit, 0) as credit_limit,
      coalesce(sum(case when s.sale_date < current_date - 90 then s.grand_total - coalesce(p.paid, 0) else 0 end), 0) as amount_90_plus,
      coalesce(sum(s.grand_total - coalesce(p.paid, 0)), 0) as current_balance
    from public.customers c
    join public.sales s on s.customer_id = c.id and s.tenant_id = c.tenant_id
    left join lateral (
      select sum(sp.amount) as paid
      from public.sale_payments sp
      where sp.sale_id = s.id and sp.tenant_id = s.tenant_id
    ) p on true
    where c.tenant_id = p_tenant_id
      and coalesce(s.status, '') not in ('draft', 'void', 'cancelled')
    group by c.id, c.name, c.credit_limit
    having sum(s.grand_total - coalesce(p.paid, 0)) > 0.01
      and (
        (coalesce(c.credit_limit, 0) > 0 and sum(s.grand_total - coalesce(p.paid, 0)) > c.credit_limit) or
        sum(case when s.sale_date < current_date - 90 then s.grand_total - coalesce(p.paid, 0) else 0 end) > 2000
      )
    limit 15
  ) loop
    v_has_overdue_debt := true;
    v_findings := v_findings || jsonb_build_object(
      'engine', 'customer_credit',
      'category', 'credit_exposure',
      'severity', case when v_rec.amount_90_plus > 5000 then 'critical' else 'high' end,
      'rule_code', case when v_rec.amount_90_plus > 2000 then 'CREDIT_DEBT_CRITICAL_90D' else 'CREDIT_LIMIT_EXCEEDED' end,
      'detection_rule', 'Customer has severely aged overdue debt (>90 days) or has breached credit limit.',
      'title', 'Critical Overdue Credit Exposure: ' || v_rec.customer_name,
      'description', 'Outstanding balance is ' || v_rec.current_balance::text || ' with overdue debt.',
      'affected_entity_type', 'customer',
      'affected_entity_id', v_rec.customer_id::text,
      'affected_record_ref', v_rec.customer_name,
      'location_id', p_location_id,
      'evidence', jsonb_build_object(
        'current_balance', v_rec.current_balance,
        'credit_limit', v_rec.credit_limit,
        'overdue_90_plus', v_rec.amount_90_plus
      ),
      'confidence', 1.0,
      'impacted_amount', v_rec.current_balance,
      'recommended_action', jsonb_build_object(
        'action_type', 'freeze_customer_credit',
        'label', 'Review Customer Account & Credit Limits',
        'route', '/customers'
      )
    );
  end loop;

  -- --------------------------------------------------------------------------
  -- ENGINE 6: Financial & Accounting Intelligence
  -- --------------------------------------------------------------------------
  -- 6.1 Double-Entry Trial Balance Verification
  select abs(coalesce(sum(jl.debit), 0) - coalesce(sum(jl.credit), 0)) into v_tb_diff
  from public.journal_lines jl
  join public.journal_entries j on j.id = jl.journal_entry_id
  where j.tenant_id = p_tenant_id and j.status = 'posted';

  if coalesce(v_tb_diff, 0) >= 0.01 then
    v_findings := v_findings || jsonb_build_object(
      'engine', 'financial',
      'category', 'accounting_integrity',
      'severity', 'critical',
      'rule_code', 'FIN_TB_DISCREPANCY',
      'detection_rule', 'Total posted debits do not match total posted credits in general ledger.',
      'title', 'Double-Entry Trial Balance Imbalance',
      'description', 'A posted discrepancy of ' || v_tb_diff::text || ' was detected between debits and credits.',
      'affected_entity_type', 'general_ledger',
      'affected_entity_id', 'posted_journals',
      'affected_record_ref', 'General Ledger Trial Balance',
      'location_id', null,
      'evidence', jsonb_build_object('discrepancy_amount', v_tb_diff),
      'confidence', 1.0,
      'impacted_amount', v_tb_diff,
      'recommended_action', jsonb_build_object(
        'action_type', 'audit_ledger',
        'label', 'Run Audit Center Integrity Check #1',
        'route', '/audit'
      )
    );
  end if;

  -- 6.2 Cash Account Balance
  select coalesce(sum(case when a.account_type = 'asset' then jl.debit - jl.credit else 0 end), 0)
    into v_cash_balance
  from public.journal_lines jl
  join public.accounting_accounts a on a.id = jl.account_id
  join public.journal_entries j on j.id = jl.journal_entry_id
  where j.tenant_id = p_tenant_id and j.status = 'posted'
    and (lower(a.name) like '%cash%' or lower(a.code) like '%cash%');

  if v_cash_balance < 0 then
    v_findings := v_findings || jsonb_build_object(
      'engine', 'financial',
      'category', 'liquidity_deficit',
      'severity', 'critical',
      'rule_code', 'FIN_OVERDRAWN_CASH',
      'detection_rule', 'Cash on hand ledger account has a negative closing balance.',
      'title', 'Overdrawn Cash Account Balance',
      'description', 'Closing cash balance is ' || v_cash_balance::text || ' indicating unrecorded cash inflows or negative drawer.',
      'affected_entity_type', 'account',
      'affected_entity_id', 'cash_drawer',
      'affected_record_ref', 'Cash on Hand Account',
      'location_id', null,
      'evidence', jsonb_build_object('closing_balance', v_cash_balance),
      'confidence', 1.0,
      'impacted_amount', abs(v_cash_balance),
      'recommended_action', jsonb_build_object(
        'action_type', 'reconcile_cash',
        'label', 'Reconcile Cash Drawer & Journal Entries',
        'route', '/accounting'
      )
    );
  end if;

  -- --------------------------------------------------------------------------
  -- ENGINE 7: Expense Intelligence
  -- --------------------------------------------------------------------------
  for v_rec in (
    select ec.id as category_id, ec.name as category_name,
           coalesce(cur.total, 0) as cur_total,
           coalesce(prior.total, 0) as prior_total
    from public.expense_categories ec
    join (
      select category_id, sum(amount) as total
      from public.expenses
      where tenant_id = p_tenant_id and status = 'active' and expense_date >= current_date - 30
      group by category_id
    ) cur on cur.category_id = ec.id
    left join (
      select category_id, sum(amount) as total
      from public.expenses
      where tenant_id = p_tenant_id and status = 'active' and expense_date >= current_date - 60 and expense_date < current_date - 30
      group by category_id
    ) prior on prior.category_id = ec.id
    where ec.tenant_id = p_tenant_id
      and coalesce(cur.total, 0) >= 5000
      and (prior.total is null or cur.total >= prior.total * 1.5)
    limit 10
  ) loop
    v_findings := v_findings || jsonb_build_object(
      'engine', 'expense',
      'category', 'budget_spike',
      'severity', 'high',
      'rule_code', 'EXP_CATEGORY_SPIKE',
      'detection_rule', 'Category expenses grew by >= 50% compared to preceding 30-day period.',
      'title', 'Expense Category Surge: ' || v_rec.category_name,
      'description', 'Spend increased to ' || v_rec.cur_total::text || ' from ' || coalesce(v_rec.prior_total, 0)::text || '.',
      'affected_entity_type', 'expense_category',
      'affected_entity_id', v_rec.category_id::text,
      'affected_record_ref', v_rec.category_name,
      'location_id', p_location_id,
      'evidence', jsonb_build_object(
        'current_spend', v_rec.cur_total,
        'prior_spend', coalesce(v_rec.prior_total, 0),
        'growth_pct', case when coalesce(v_rec.prior_total, 0) > 0 then round(((v_rec.cur_total - v_rec.prior_total) / v_rec.prior_total) * 100, 1) else 100.0 end
      ),
      'confidence', 0.95,
      'impacted_amount', greatest(0, v_rec.cur_total - coalesce(v_rec.prior_total, 0)),
      'recommended_action', jsonb_build_object(
        'action_type', 'audit_expenses',
        'label', 'Review Category Expense Vouchers',
        'route', '/expenses'
      )
    );
  end loop;

  -- --------------------------------------------------------------------------
  -- ENGINE 8: Cross-Engine Correlated Intelligence
  -- --------------------------------------------------------------------------
  -- 8.1 Cross: Falling Sales + Excess Inventory on same variant
  if array_length(v_sales_decline_variants, 1) > 0 and array_length(v_overstock_variants, 1) > 0 then
    for v_rec in (
      select v.id as variant_id, v.sku, p.name as product_name
      from public.product_variants v
      join public.products p on p.id = v.product_id
      where v.id = any(v_sales_decline_variants)
        and v.id = any(v_overstock_variants)
      limit 5
    ) loop
      v_cross_engine_count := v_cross_engine_count + 1;
      v_findings := v_findings || jsonb_build_object(
        'engine', 'cross_engine',
        'category', 'inventory_obsolescence_risk',
        'severity', 'high',
        'is_cross_engine', true,
        'rule_code', 'CROSS_SALES_DROP_OVERSTOCK',
        'detection_rule', 'Product exhibits declining consumer sales simultaneously with overstocked inventory cover.',
        'title', 'Sales Decline with Excess Stock: ' || v_rec.product_name,
        'description', 'Product demand is contracting by >= 50% while inventory cover exceeds 90 days, creating severe cash lockup risk.',
        'affected_entity_type', 'product_variant',
        'affected_entity_id', v_rec.variant_id::text,
        'affected_record_ref', coalesce(v_rec.sku, '') || ' / ' || v_rec.product_name,
        'location_id', p_location_id,
        'evidence', jsonb_build_object(
          'contributing_engines', jsonb_build_array('sales', 'inventory'),
          'correlation', 'declining_demand_plus_excess_holding'
        ),
        'contributing_findings', jsonb_build_array('SALES_SHARP_DECLINE', 'INV_OVERSTOCK_CAPITAL'),
        'confidence', 0.95,
        'impacted_amount', 15000.0,
        'recommended_action', jsonb_build_object(
          'action_type', 'clearance_or_markdown',
          'label', 'Plan Promotional Markdown or Transfer',
          'route', '/inventory'
        )
      );
    end loop;
  end if;

  -- 8.2 Cross: Customer Overdue Receivables + Constrained Cash Liquidity
  if v_has_overdue_debt and v_cash_balance < 30000 then
    v_cross_engine_count := v_cross_engine_count + 1;
    v_findings := v_findings || jsonb_build_object(
      'engine', 'cross_engine',
      'category', 'working_capital_squeeze',
      'severity', 'critical',
      'is_cross_engine', true,
      'rule_code', 'CROSS_OVERDUE_AR_LOW_CASH',
      'detection_rule', 'Substantial customer receivables are aged past 90 days while cash liquidity is constrained.',
      'title', 'Working Capital Liquidity Squeeze',
      'description', 'Cash liquidity is under pressure while significant customer balances are stalled in 90+ days overdue.',
      'affected_entity_type', 'working_capital',
      'affected_entity_id', 'liquidity_receivables',
      'affected_record_ref', 'Cash on Hand + Accounts Receivable',
      'location_id', null,
      'evidence', jsonb_build_object(
        'contributing_engines', jsonb_build_array('customer_credit', 'financial'),
        'cash_on_hand', v_cash_balance,
        'status', 'tight_liquidity_with_uncollected_debt'
      ),
      'contributing_findings', jsonb_build_array('CREDIT_DEBT_CRITICAL_90D', 'FIN_OVERDRAWN_CASH'),
      'confidence', 0.98,
      'impacted_amount', 25000.0,
      'recommended_action', jsonb_build_object(
        'action_type', 'accelerate_collections',
        'label', 'Prioritize Overdue Customer Collections',
        'route', '/customers'
      )
    );
  end if;

  -- --------------------------------------------------------------------------
  -- INGEST ALL FINDINGS IDEMPOTENTLY
  -- --------------------------------------------------------------------------
  v_ingest_res := public.erp_intelligence_ingest_findings_v830(
    p_tenant_id => p_tenant_id,
    p_findings => v_findings,
    p_auto_resolve => true,
    p_engine => null,
    p_location_id => p_location_id
  );

  return jsonb_build_object(
    'success', true,
    'tenant_id', p_tenant_id,
    'location_id', p_location_id,
    'scanned_at', now(),
    'engines_scanned', jsonb_build_array('sales', 'inventory', 'rebalancing', 'supplier', 'customer_credit', 'financial', 'expense', 'cross_engine'),
    'total_detected', jsonb_array_length(v_findings),
    'cross_engine_detected', v_cross_engine_count,
    'ingestion', v_ingest_res
  );
end $$;

grant execute on function public.erp_intelligence_scan_and_sync_v830(uuid,uuid) to authenticated, service_role;

-- ============================================================================
-- 6. ACTION CENTRE QUERY & AGGREGATION RPC
-- ============================================================================

create or replace function public.erp_intelligence_action_centre_v830(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_engine text default null,
  p_severity text default null,
  p_status text default null,
  p_category text default null,
  p_query text default '',
  p_limit integer default 100,
  p_offset integer default 0
) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v_can_view_cost boolean;
  v_q text := '%' || lower(trim(coalesce(p_query, ''))) || '%';
  v_total integer;
  v_critical integer;
  v_high integer;
  v_medium integer;
  v_low integer;
  v_unresolved integer;
  v_recently_resolved integer;
  v_by_engine jsonb;
  v_by_status jsonb;
  v_findings jsonb;
  v_cross_insights jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied to tenant %', p_tenant_id;
  end if;

  v_can_view_cost := private.erp_user_is_owner(p_tenant_id) or
                     private.erp_has_permission(p_tenant_id, 'inventory.view_cost') or
                     private.erp_has_permission(p_tenant_id, 'accounting.view') or
                     private.erp_has_permission(p_tenant_id, 'reports.view');

  -- Summary Counts
  select
    count(*),
    count(*) filter (where severity = 'critical'),
    count(*) filter (where severity in ('high', 'urgent')),
    count(*) filter (where severity in ('medium', 'warning')),
    count(*) filter (where severity in ('low', 'info', 'informational', 'opportunity')),
    count(*) filter (where status in ('new', 'new_insight', 'under_review', 'accepted', 'approved', 'in_progress', 'acknowledged')),
    count(*) filter (where status in ('resolved', 'dismissed') and resolved_at >= now() - interval '7 days')
  into
    v_total, v_critical, v_high, v_medium, v_low, v_unresolved, v_recently_resolved
  from public.erp_intelligence_insights
  where tenant_id = p_tenant_id
    and (p_location_id is null or location_id is null or location_id = p_location_id);

  -- Counts by engine
  select jsonb_object_agg(engine, cnt) into v_by_engine
  from (
    select engine, count(*) as cnt
    from public.erp_intelligence_insights
    where tenant_id = p_tenant_id
      and (p_location_id is null or location_id is null or location_id = p_location_id)
      and status in ('new', 'new_insight', 'under_review', 'accepted', 'approved', 'in_progress')
    group by engine
  ) be;

  -- Counts by status
  select jsonb_object_agg(status, cnt) into v_by_status
  from (
    select status, count(*) as cnt
    from public.erp_intelligence_insights
    where tenant_id = p_tenant_id
      and (p_location_id is null or location_id is null or location_id = p_location_id)
    group by status
  ) bs;

  -- Cross-engine insights
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', i.id,
      'title', i.title,
      'description', i.description,
      'severity', i.severity,
      'priority', i.priority,
      'priority_score', i.priority_score,
      'priority_reason', i.priority_reason,
      'rule_code', i.rule_code,
      'affected_record_ref', i.affected_record_ref,
      'evidence', case when v_can_view_cost then i.evidence else '{}'::jsonb end,
      'contributing_findings', i.contributing_findings,
      'recommended_action', i.recommended_action,
      'status', i.status,
      'last_detected_at', i.last_detected_at
    ) order by i.priority_score desc, i.last_detected_at desc
  ), '[]'::jsonb) into v_cross_insights
  from public.erp_intelligence_insights i
  where i.tenant_id = p_tenant_id
    and (p_location_id is null or i.location_id is null or i.location_id = p_location_id)
    and i.is_cross_engine = true
    and i.status in ('new', 'new_insight', 'under_review', 'accepted', 'approved')
  limit 10;

  -- Paginated Findings
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', i.id,
      'location_id', i.location_id,
      'engine', i.engine,
      'category', i.category,
      'severity', i.severity,
      'priority', i.priority,
      'priority_score', i.priority_score,
      'priority_reason', i.priority_reason,
      'title', i.title,
      'description', i.description,
      'detection_rule', i.detection_rule,
      'rule_code', i.rule_code,
      'affected_entity_type', i.affected_entity_type,
      'affected_entity_id', i.affected_entity_id,
      'affected_record_ref', i.affected_record_ref,
      'evidence', case when v_can_view_cost then i.evidence else '{}'::jsonb end,
      'baseline_period', i.baseline_period,
      'recommended_action', i.recommended_action,
      'confidence', i.confidence,
      'impacted_amount', case when v_can_view_cost then i.impacted_amount else null end,
      'is_cross_engine', i.is_cross_engine,
      'contributing_findings', i.contributing_findings,
      'source_references', i.source_references,
      'occurrence_count', i.occurrence_count,
      'first_detected_at', i.first_detected_at,
      'last_detected_at', i.last_detected_at,
      'status', i.status,
      'resolution_note', i.resolution_note,
      'resolved_at', i.resolved_at,
      'assigned_to', i.assigned_to,
      'created_at', i.created_at,
      'updated_at', i.updated_at
    ) order by i.priority_score desc, i.last_detected_at desc
  ), '[]'::jsonb) into v_findings
  from (
    select *
    from public.erp_intelligence_insights
    where tenant_id = p_tenant_id
      and (p_location_id is null or location_id is null or location_id = p_location_id)
      and (p_engine is null or engine = p_engine)
      and (p_severity is null or severity = p_severity)
      and (p_status is null or status = p_status)
      and (p_category is null or category = p_category)
      and (
        trim(coalesce(p_query, '')) = '' or
        lower(title) like v_q or
        lower(description) like v_q or
        lower(affected_record_ref) like v_q or
        lower(rule_code) like v_q
      )
    order by priority_score desc, last_detected_at desc
    limit greatest(1, least(coalesce(p_limit, 100), 500))
    offset greatest(0, coalesce(p_offset, 0))
  ) i;

  return jsonb_build_object(
    'summary', jsonb_build_object(
      'total_findings', coalesce(v_total, 0),
      'critical_count', coalesce(v_critical, 0),
      'high_count', coalesce(v_high, 0),
      'medium_count', coalesce(v_medium, 0),
      'low_count', coalesce(v_low, 0),
      'unresolved_count', coalesce(v_unresolved, 0),
      'recently_resolved_count', coalesce(v_recently_resolved, 0),
      'by_engine', coalesce(v_by_engine, '{}'::jsonb),
      'by_status', coalesce(v_by_status, '{}'::jsonb)
    ),
    'findings', v_findings,
    'cross_engine_insights', v_cross_insights,
    'can_view_cost', v_can_view_cost,
    'pagination', jsonb_build_object(
      'limit', coalesce(p_limit, 100),
      'offset', coalesce(p_offset, 0),
      'count', jsonb_array_length(v_findings)
    )
  );
end $$;

grant execute on function public.erp_intelligence_action_centre_v830(uuid,uuid,text,text,text,text,text,integer,integer) to authenticated, service_role;

-- ============================================================================
-- 7. STATE TRANSITION & REVIEW AUDIT RPC
-- ============================================================================

create or replace function public.erp_intelligence_finding_transition_v830(
  p_tenant_id uuid,
  p_finding_id uuid,
  p_to_status text,
  p_review_notes text default '',
  p_assigned_to uuid default null
) returns jsonb
language plpgsql security definer set search_path=public,private,pg_temp
as $$
declare
  v_finding public.erp_intelligence_insights%rowtype;
  v_valid_transition boolean := false;
  v_user_name text := 'Authorized Reviewer';
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied to tenant %', p_tenant_id;
  end if;

  select * into v_finding
  from public.erp_intelligence_insights
  where id = p_finding_id and tenant_id = p_tenant_id
  for update;

  if not found then
    raise exception 'Intelligence finding % not found in tenant %', p_finding_id, p_tenant_id;
  end if;

  -- Canonical Valid State Transitions Matrix:
  -- 'new', 'under_review', 'accepted', 'rejected', 'approved', 'executed', 'completed', 'failed', 'resolved', 'dismissed'
  v_valid_transition := case
    when v_finding.status in ('new', 'new_insight', 'reopened') and p_to_status in ('under_review', 'accepted', 'rejected', 'dismissed', 'resolved') then true
    when v_finding.status = 'under_review' and p_to_status in ('accepted', 'rejected', 'dismissed', 'resolved') then true
    when v_finding.status = 'accepted' and p_to_status in ('approved', 'rejected', 'resolved', 'dismissed') then true
    when v_finding.status = 'approved' and p_to_status in ('completed', 'failed', 'resolved', 'dismissed') then true
    when v_finding.status = 'rejected' and p_to_status in ('under_review', 'dismissed', 'new') then true
    when v_finding.status in ('resolved', 'dismissed') and p_to_status in ('new', 'under_review') then true
    when v_finding.status = 'completed' and p_to_status in ('resolved') then true
    when v_finding.status = 'failed' and p_to_status in ('under_review', 'rejected', 'dismissed') then true
    when v_finding.status = p_to_status then true -- idempotent update (e.g. note or assignee change)
    else false
  end;

  if not v_valid_transition then
    raise exception 'Invalid lifecycle transition from % to % for finding %', v_finding.status, p_to_status, p_finding_id;
  end if;

  -- Look up user name
  select coalesce(u.raw_user_meta_data->>'full_name', u.email, 'Authorized Reviewer') into v_user_name
  from auth.users u
  where u.id = auth.uid()
  limit 1;

  -- Update finding row
  update public.erp_intelligence_insights
  set status = p_to_status,
      assigned_to = coalesce(p_assigned_to, assigned_to),
      resolution_note = case when p_to_status in ('resolved', 'dismissed', 'rejected') then coalesce(nullif(trim(p_review_notes), ''), resolution_note) else resolution_note end,
      resolved_by = case when p_to_status in ('resolved', 'dismissed') then auth.uid() else resolved_by end,
      resolved_at = case when p_to_status in ('resolved', 'dismissed') then now() else resolved_at end,
      updated_at = now()
  where id = p_finding_id;

  -- Record audit trail
  insert into public.erp_intelligence_finding_reviews(
    tenant_id, finding_id, user_id, user_name, action,
    from_status, to_status, review_notes, assigned_to, created_at
  ) values (
    p_tenant_id, p_finding_id, auth.uid(), coalesce(v_user_name, 'Reviewer'),
    'status_transition', v_finding.status, p_to_status,
    coalesce(p_review_notes, ''), coalesce(p_assigned_to, v_finding.assigned_to), now()
  );

  return jsonb_build_object(
    'success', true,
    'finding_id', p_finding_id,
    'from_status', v_finding.status,
    'to_status', p_to_status,
    'updated_at', now()
  );
end $$;

grant execute on function public.erp_intelligence_finding_transition_v830(uuid,uuid,text,text,uuid) to authenticated, service_role;

-- ============================================================================
-- 8. REVIEWS AUDIT HISTORY LISTING RPC
-- ============================================================================

create or replace function public.erp_intelligence_finding_reviews_v830(
  p_tenant_id uuid,
  p_finding_id uuid
) returns jsonb
language plpgsql stable security definer set search_path=public,private,pg_temp
as $$
declare
  v_reviews jsonb;
begin
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied to tenant %', p_tenant_id;
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', r.id,
      'finding_id', r.finding_id,
      'user_id', r.user_id,
      'user_name', r.user_name,
      'action', r.action,
      'from_status', r.from_status,
      'to_status', r.to_status,
      'review_notes', r.review_notes,
      'assigned_to', r.assigned_to,
      'created_at', r.created_at
    ) order by r.created_at desc
  ), '[]'::jsonb) into v_reviews
  from public.erp_intelligence_finding_reviews r
  where r.tenant_id = p_tenant_id and r.finding_id = p_finding_id;

  return v_reviews;
end $$;

grant execute on function public.erp_intelligence_finding_reviews_v830(uuid,uuid) to authenticated, service_role;

-- ============================================================================
-- 9. REGISTER SCHEMA RELEASE #712
-- ============================================================================

insert into public.thq_schema_releases (
  migration_no,
  schema_version,
  release_name,
  applied_at,
  notes
)
values (
  712,
  '8.3.6',
  'Operations Intelligence Phase 7: Shared Intelligence Framework, Centralized Risk Detection & Action Centre',
  now(),
  'Shared intelligence finding model, multi-engine centralized ingestion, deduplication, cross-engine correlation, transparent prioritization, lifecycle transitions & audit history.'
)
on conflict (migration_no) do update
set schema_version = excluded.schema_version,
    release_name = excluded.release_name,
    applied_at = now(),
    notes = excluded.notes;

commit;
