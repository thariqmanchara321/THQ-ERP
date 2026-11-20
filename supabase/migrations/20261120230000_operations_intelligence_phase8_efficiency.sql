-- ============================================================================
-- THQ ERP — Operations Intelligence Phase 8
-- Operational Efficiency Intelligence Engine
-- Target Supabase Environment: flexi-erp-dev
-- Schema Version: Release #713 / v8.3.7
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Operational Efficiency Intelligence RPC
-- ----------------------------------------------------------------------------
create or replace function public.operational_efficiency_intelligence_v830(
  p_tenant_id uuid,
  p_location_id uuid default null,
  p_days integer default 30
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_caller_id uuid := auth.uid();
  v_can_view_cost boolean := false;
  v_from_ts timestamp with time zone := now() - (coalesce(p_days, 30) || ' days')::interval;
  v_prev_from_ts timestamp with time zone := now() - (coalesce(p_days, 30) * 2 || ' days')::interval;

  -- Sales & Billing Metrics
  v_total_sales integer := 0;
  v_completed_sales integer := 0;
  v_cancelled_sales integer := 0;
  v_cancellation_rate numeric := 0.0;
  v_avg_daily_throughput numeric := 0.0;
  v_peak_hours jsonb := '[]'::jsonb;
  v_held_sales_count integer := 0;

  -- Procurement Metrics
  v_total_pos integer := 0;
  v_completed_pos integer := 0;
  v_pending_approval_pos integer := 0;
  v_avg_po_approval_hours numeric := 0.0;
  v_avg_grn_lead_time_days numeric := 0.0;
  v_overdue_pos integer := 0;
  v_supplier_delay_rate numeric := 0.0;
  v_delayed_orders jsonb := '[]'::jsonb;

  -- Inventory Operations Metrics
  v_total_transfers integer := 0;
  v_completed_transfers integer := 0;
  v_avg_transfer_hours numeric := 0.0;
  v_delayed_transfers_count integer := 0;
  v_transfer_cancellation_rate numeric := 0.0;
  v_delayed_transfers jsonb := '[]'::jsonb;
  v_total_adjustments integer := 0;
  v_pending_adjustments integer := 0;
  v_approved_adjustments integer := 0;
  v_avg_adjustment_approval_hours numeric := 0.0;

  -- Customer Operations Metrics
  v_total_returns integer := 0;
  v_pending_refunds integer := 0;
  v_completed_refunds integer := 0;
  v_return_rate numeric := 0.0;
  v_return_reasons jsonb := '[]'::jsonb;

  -- System & POS Sync Metrics
  v_total_sync_events integer := 0;
  v_synced_count integer := 0;
  v_pending_sync_count integer := 0;
  v_failed_sync_count integer := 0;
  v_conflict_count integer := 0;
  v_avg_sync_delay_minutes numeric := 0.0;
  v_sync_success_rate numeric := 100.0;

  -- Bottlenecks & Overall Score
  v_bottlenecks jsonb := '[]'::jsonb;
  v_efficiency_score numeric := 100.0;
  v_health_status text := 'optimal';
  v_branch_comparisons jsonb := '[]'::jsonb;
  v_data_freshness jsonb;
begin
  -- 1. Tenant Membership & Permissions Verification
  if not private.erp_user_has_tenant_access(p_tenant_id) then
    raise exception 'Access denied: caller does not belong to tenant %.', p_tenant_id
      using errcode = '42501';
  end if;

  v_can_view_cost := private.erp_user_is_owner(p_tenant_id)
    or private.erp_has_permission(p_tenant_id, 'inventory.view_cost')
    or private.erp_has_permission(p_tenant_id, 'inventory.manage')
    or private.erp_has_permission(p_tenant_id, 'accounting.view')
    or private.erp_has_permission(p_tenant_id, 'reports.view');

  -- --------------------------------------------------------------------------
  -- 2. Sales & Billing Operations Efficiency
  -- --------------------------------------------------------------------------
  select
    count(*),
    count(*) filter (where s.status in ('completed', 'posted')),
    count(*) filter (where s.status in ('cancelled', 'void'))
  into v_total_sales, v_completed_sales, v_cancelled_sales
  from public.sales s
  where s.tenant_id = p_tenant_id
    and s.created_at >= v_from_ts;

  if v_total_sales > 0 then
    v_cancellation_rate := round((v_cancelled_sales::numeric / v_total_sales::numeric) * 100.0, 1);
    v_avg_daily_throughput := round(v_completed_sales::numeric / greatest(1, p_days)::numeric, 1);
  end if;

  -- Peak Billing Hours
  select coalesce(jsonb_agg(h), '[]'::jsonb)
  into v_peak_hours
  from (
    select
      extract(hour from coalesce(s.posted_at, s.created_at))::integer as hour_of_day,
      count(*) as bill_count
    from public.sales s
    where s.tenant_id = p_tenant_id
      and s.created_at >= v_from_ts
      and s.status in ('completed', 'posted')
    group by 1
    order by 2 desc
    limit 6
  ) h;

  -- Held sales
  select count(*) into v_held_sales_count
  from public.pos_held_sales phs
  where phs.tenant_id = p_tenant_id
    and (p_location_id is null or phs.location_id = p_location_id)
    and phs.created_at >= v_from_ts;

  -- --------------------------------------------------------------------------
  -- 3. Procurement Operations Efficiency
  -- --------------------------------------------------------------------------
  select
    count(*),
    count(*) filter (where po.status in ('closed', 'received', 'completed')),
    count(*) filter (where po.status in ('submitted', 'pending_approval')),
    coalesce(round(avg(extract(epoch from (po.approved_at - coalesce(po.submitted_at, po.created_at)))) filter (where po.approved_at is not null) / 3600.0, 1), 0.0),
    count(*) filter (where po.status in ('ordered', 'pending', 'partial') and po.expected_date < current_date)
  into v_total_pos, v_completed_pos, v_pending_approval_pos, v_avg_po_approval_hours, v_overdue_pos
  from public.purchase_orders_v480 po
  where po.tenant_id = p_tenant_id
    and (p_location_id is null or po.location_id = p_location_id)
    and po.created_at >= v_from_ts;

  if v_total_pos > 0 then
    v_supplier_delay_rate := round((v_overdue_pos::numeric / v_total_pos::numeric) * 100.0, 1);
  end if;

  -- Average PO to Goods Receipt Note (GRN) lead time
  select coalesce(round(avg(extract(epoch from (gr.created_at - coalesce(po.ordered_at, po.created_at)))) / 86400.0, 1), 0.0)
  into v_avg_grn_lead_time_days
  from public.goods_receipts_v484 gr
  join public.purchase_orders_v480 po on po.id = gr.purchase_order_id
  where po.tenant_id = p_tenant_id
    and (p_location_id is null or po.location_id = p_location_id)
    and gr.created_at >= v_from_ts;

  -- Top Delayed Orders
  select coalesce(jsonb_agg(d), '[]'::jsonb)
  into v_delayed_orders
  from (
    select
      po.id as order_id,
      po.order_number,
      sup.name as supplier_name,
      po.expected_date,
      current_date - po.expected_date as days_overdue,
      po.status,
      case when v_can_view_cost then po.grand_total else null end as grand_total
    from public.purchase_orders_v480 po
    join public.suppliers sup on sup.id = po.supplier_id
    where po.tenant_id = p_tenant_id
      and (p_location_id is null or po.location_id = p_location_id)
      and po.status in ('ordered', 'pending', 'partial')
      and po.expected_date < current_date
    order by po.expected_date asc
    limit 10
  ) d;

  -- --------------------------------------------------------------------------
  -- 4. Inventory Operations Efficiency (Stock Transfers & Adjustments)
  -- --------------------------------------------------------------------------
  select
    count(*),
    count(*) filter (where st.status = 'received'),
    coalesce(round(avg(extract(epoch from (st.received_at - st.created_at))) filter (where st.status = 'received' and st.received_at is not null) / 3600.0, 1), 0.0),
    count(*) filter (where st.status in ('dispatched', 'in_transit') and (st.expected_arrival_date < current_date or st.dispatched_at < now() - interval '48 hours')),
    coalesce(round((count(*) filter (where st.status in ('cancelled', 'rejected'))::numeric / nullif(count(*), 0)) * 100.0, 1), 0.0)
  into v_total_transfers, v_completed_transfers, v_avg_transfer_hours, v_delayed_transfers_count, v_transfer_cancellation_rate
  from public.stock_transfers st
  where st.tenant_id = p_tenant_id
    and (p_location_id is null or st.from_location_id = p_location_id or st.to_location_id = p_location_id)
    and st.created_at >= v_from_ts;

  -- Delayed Transfers list
  select coalesce(jsonb_agg(dt), '[]'::jsonb)
  into v_delayed_transfers
  from (
    select
      st.id as transfer_id,
      st.transfer_number,
      loc_from.name as from_location_name,
      loc_to.name as to_location_name,
      st.status,
      st.expected_arrival_date,
      round(extract(epoch from (now() - coalesce(st.dispatched_at, st.created_at))) / 3600.0, 1) as elapsed_hours
    from public.stock_transfers st
    join public.business_locations loc_from on loc_from.id = st.from_location_id
    join public.business_locations loc_to on loc_to.id = st.to_location_id
    where st.tenant_id = p_tenant_id
      and (p_location_id is null or st.from_location_id = p_location_id or st.to_location_id = p_location_id)
      and st.status in ('dispatched', 'in_transit')
      and (st.expected_arrival_date < current_date or st.dispatched_at < now() - interval '48 hours')
    order by st.created_at asc
    limit 10
  ) dt;

  -- Stock Adjustments
  select
    count(*),
    count(*) filter (where adj.status = 'pending'),
    count(*) filter (where adj.status = 'approved'),
    coalesce(round(avg(extract(epoch from (adj.decided_at - adj.requested_at))) filter (where adj.decided_at is not null) / 3600.0, 1), 0.0)
  into v_total_adjustments, v_pending_adjustments, v_approved_adjustments, v_avg_adjustment_approval_hours
  from public.stock_adjustment_requests_v500 adj
  where adj.tenant_id = p_tenant_id
    and (p_location_id is null or adj.location_id = p_location_id)
    and adj.requested_at >= v_from_ts;

  -- --------------------------------------------------------------------------
  -- 5. Customer Service & Returns Operations
  -- --------------------------------------------------------------------------
  select
    count(*),
    count(*) filter (where sr.refund_status in ('pending', 'partial')),
    count(*) filter (where sr.refund_status = 'completed')
  into v_total_returns, v_pending_refunds, v_completed_refunds
  from public.sales_returns sr
  where sr.tenant_id = p_tenant_id
    and (p_location_id is null or sr.location_id = p_location_id)
    and sr.created_at >= v_from_ts;

  if v_completed_sales > 0 then
    v_return_rate := round((v_total_returns::numeric / v_completed_sales::numeric) * 100.0, 2);
  end if;

  select coalesce(jsonb_agg(rr), '[]'::jsonb)
  into v_return_reasons
  from (
    select
      coalesce(nullif(sr.reason, ''), 'Unspecified') as reason,
      count(*) as count
    from public.sales_returns sr
    where sr.tenant_id = p_tenant_id
      and (p_location_id is null or sr.location_id = p_location_id)
      and sr.created_at >= v_from_ts
    group by 1
    order by 2 desc
    limit 5
  ) rr;

  -- --------------------------------------------------------------------------
  -- 6. POS & Offline System Synchronization Reliability
  -- --------------------------------------------------------------------------
  select
    count(*),
    count(*) filter (where sync.status = 'synced'),
    count(*) filter (where sync.status = 'pending'),
    count(*) filter (where sync.status in ('failed', 'error')),
    count(*) filter (where sync.conflict_code is not null and sync.status <> 'synced'),
    coalesce(round(avg(extract(epoch from (coalesce(sync.synced_at, now()) - sync.first_seen_at))) / 60.0, 1), 0.0)
  into v_total_sync_events, v_synced_count, v_pending_sync_count, v_failed_sync_count, v_conflict_count, v_avg_sync_delay_minutes
  from public.pos_offline_sync_v486 sync
  where sync.tenant_id = p_tenant_id
    and (p_location_id is null or sync.location_id = p_location_id)
    and sync.first_seen_at >= v_from_ts;

  if v_total_sync_events > 0 then
    v_sync_success_rate := round((v_synced_count::numeric / v_total_sync_events::numeric) * 100.0, 1);
  end if;

  -- --------------------------------------------------------------------------
  -- 7. Deterministic Bottleneck Detection Rules
  -- --------------------------------------------------------------------------
  -- Rule 1: PO Approval Bottleneck (>48h avg or >2 pending for >7 days)
  if v_pending_approval_pos >= 2 or v_avg_po_approval_hours > 48.0 then
    v_bottlenecks := v_bottlenecks || jsonb_build_object(
      'rule_code', 'EFF_PO_APPROVAL_BOTTLENECK',
      'title', 'Purchase Order Approval Bottleneck',
      'severity', case when v_pending_approval_pos >= 4 or v_avg_po_approval_hours > 72.0 then 'high' else 'medium' end,
      'affected_process', 'Procurement Authorization',
      'description', 'Purchase orders are experiencing extended approval queues averaging ' || v_avg_po_approval_hours::text || ' hours (' || v_pending_approval_pos::text || ' orders pending).',
      'evidence', jsonb_build_object(
        'pending_approvals', v_pending_approval_pos,
        'avg_approval_hours', v_avg_po_approval_hours
      ),
      'recommendation', 'Review outstanding purchase order requests in the Procurement workspace to authorize replenishment orders.',
      'route', '/purchases'
    );
  end if;

  -- Rule 2: Delayed Supplier Inbound Shipments (>15% delayed)
  if v_overdue_pos > 0 and v_supplier_delay_rate >= 15.0 then
    v_bottlenecks := v_bottlenecks || jsonb_build_object(
      'rule_code', 'EFF_SUPPLIER_DELIVERY_DELAY',
      'title', 'Inbound Supplier Delivery Delays',
      'severity', 'high',
      'affected_process', 'Goods Receiving & Inbound Fulfillment',
      'description', v_overdue_pos::text || ' purchase orders (' || v_supplier_delay_rate::text || '% of total) have passed their expected delivery dates without posted goods receipt.',
      'evidence', jsonb_build_object(
        'overdue_pos_count', v_overdue_pos,
        'delay_rate_pct', v_supplier_delay_rate,
        'avg_lead_time_days', v_avg_grn_lead_time_days
      ),
      'recommendation', 'Expedite overdue orders with affected suppliers or reschedule expected delivery dates.',
      'route', '/purchases'
    );
  end if;

  -- Rule 3: Inter-Store Stock Transfer Transit Delays
  if v_delayed_transfers_count > 0 then
    v_bottlenecks := v_bottlenecks || jsonb_build_object(
      'rule_code', 'EFF_TRANSFER_TRANSIT_DELAY',
      'title', 'Stock Transfer Transit Bottleneck',
      'severity', case when v_delayed_transfers_count >= 3 then 'high' else 'medium' end,
      'affected_process', 'Inter-Store Rebalancing Logistics',
      'description', v_delayed_transfers_count::text || ' inter-store stock transfers have exceeded expected arrival dates or 48 hours in transit.',
      'evidence', jsonb_build_object(
        'delayed_transfers_count', v_delayed_transfers_count,
        'avg_completion_hours', v_avg_transfer_hours
      ),
      'recommendation', 'Coordinate with dispatch logistics and verify physical arrival at receiving branch.',
      'route', '/inventory'
    );
  end if;

  -- Rule 4: Sales Cancellation & Void Rate Spike (>5% with >=10 sales)
  if v_total_sales >= 10 and v_cancellation_rate >= 5.0 then
    v_bottlenecks := v_bottlenecks || jsonb_build_object(
      'rule_code', 'EFF_BILLING_CANCELLATION_SPIKE',
      'title', 'Elevated Bill Cancellation & Void Rate',
      'severity', 'medium',
      'affected_process', 'POS Checkout & Cashier Billing',
      'description', 'Sales cancellations represent ' || v_cancellation_rate::text || '% of billing transactions (' || v_cancelled_sales::text || ' cancelled of ' || v_total_sales::text || ').',
      'evidence', jsonb_build_object(
        'total_bills', v_total_sales,
        'cancelled_bills', v_cancelled_sales,
        'cancellation_rate_pct', v_cancellation_rate
      ),
      'recommendation', 'Inspect void audit reasons and check terminal barcode scanning or pricing mismatches.',
      'route', '/audit'
    );
  end if;

  -- Rule 5: POS Offline Synchronization Backlog / Errors
  if v_failed_sync_count > 0 or v_conflict_count > 0 or (v_pending_sync_count >= 5 and v_avg_sync_delay_minutes > 15.0) then
    v_bottlenecks := v_bottlenecks || jsonb_build_object(
      'rule_code', 'EFF_POS_SYNC_LATENCY_BOTTLENECK',
      'title', 'POS Offline Synchronization Disruption',
      'severity', case when v_failed_sync_count > 0 or v_conflict_count > 0 then 'critical' else 'high' end,
      'affected_process', 'Offline Device Data Synchronization',
      'description', 'Detected ' || v_failed_sync_count::text || ' failed sync attempts and ' || v_conflict_count::text || ' unresolved payload conflicts.',
      'evidence', jsonb_build_object(
        'failed_syncs', v_failed_sync_count,
        'pending_syncs', v_pending_sync_count,
        'conflict_count', v_conflict_count,
        'avg_delay_minutes', v_avg_sync_delay_minutes
      ),
      'recommendation', 'Inspect terminal offline queue, verify store internet connectivity, and resolve sync conflicts.',
      'route', '/audit'
    );
  end if;

  -- Rule 6: Pending Refund Resolution Delay
  if v_pending_refunds >= 3 then
    v_bottlenecks := v_bottlenecks || jsonb_build_object(
      'rule_code', 'EFF_REFUND_SETTLEMENT_DELAY',
      'title', 'Customer Return Refund Backlog',
      'severity', 'medium',
      'affected_process', 'Customer Returns & Refund Processing',
      'description', v_pending_refunds::text || ' customer sales returns remain in pending/partial refund status.',
      'evidence', jsonb_build_object(
        'total_returns', v_total_returns,
        'pending_refunds', v_pending_refunds
      ),
      'recommendation', 'Review outstanding credit notes and disburse approved refunds to customers.',
      'route', '/customers'
    );
  end if;

  -- --------------------------------------------------------------------------
  -- 8. Overall Deterministic Efficiency Score Calculation (0 - 100)
  -- --------------------------------------------------------------------------
  v_efficiency_score := 100.0;
  if v_cancellation_rate > 5.0 then
    v_efficiency_score := v_efficiency_score - least(15.0, (v_cancellation_rate - 5.0) * 1.5);
  end if;
  if v_supplier_delay_rate > 10.0 then
    v_efficiency_score := v_efficiency_score - least(20.0, (v_supplier_delay_rate - 10.0) * 1.0);
  end if;
  if v_delayed_transfers_count > 0 then
    v_efficiency_score := v_efficiency_score - least(20.0, v_delayed_transfers_count * 5.0);
  end if;
  if v_failed_sync_count > 0 or v_conflict_count > 0 then
    v_efficiency_score := v_efficiency_score - least(25.0, (v_failed_sync_count + v_conflict_count) * 8.0);
  end if;
  if v_pending_approval_pos > 2 then
    v_efficiency_score := v_efficiency_score - least(10.0, (v_pending_approval_pos - 2) * 2.5);
  end if;
  if v_pending_adjustments > 3 then
    v_efficiency_score := v_efficiency_score - least(10.0, (v_pending_adjustments - 3) * 2.0);
  end if;

  v_efficiency_score := round(greatest(15.0, v_efficiency_score), 1);

  if v_efficiency_score >= 85.0 then
    v_health_status := 'optimal';
  elsif v_efficiency_score >= 70.0 then
    v_health_status := 'acceptable';
  elsif v_efficiency_score >= 50.0 then
    v_health_status := 'needs_attention';
  else
    v_health_status := 'critical_delay';
  end if;

  -- --------------------------------------------------------------------------
  -- 9. Fair Branch Comparisons & Operational Benchmarking
  -- --------------------------------------------------------------------------
  select coalesce(jsonb_agg(bc), '[]'::jsonb)
  into v_branch_comparisons
  from (
    select
      loc.id as location_id,
      loc.name as location_name,
      loc.location_code as location_code,
      count(distinct st.id) as total_transfers,
      coalesce(round(avg(extract(epoch from (st.received_at - st.created_at))) filter (where st.status = 'received') / 3600.0, 1), 0.0) as avg_transfer_hours,
      count(distinct st.id) filter (where st.status in ('dispatched', 'in_transit') and (st.expected_arrival_date < current_date or st.dispatched_at < now() - interval '48 hours')) as delayed_transfers,
      count(distinct po.id) as total_pos,
      count(distinct po.id) filter (where po.status in ('ordered', 'pending', 'partial') and po.expected_date < current_date) as overdue_pos,
      count(distinct sync.request_id) as sync_events,
      count(distinct sync.request_id) filter (where sync.status in ('failed', 'error')) as sync_errors,
      case
        when (count(distinct st.id) + count(distinct po.id) + count(distinct sync.request_id)) >= 5 then 'sufficient'
        else 'low_volume'
      end as data_sufficiency
    from public.business_locations loc
    left join public.stock_transfers st on (st.from_location_id = loc.id or st.to_location_id = loc.id) and st.created_at >= v_from_ts
    left join public.purchase_orders_v480 po on po.location_id = loc.id and po.created_at >= v_from_ts
    left join public.pos_offline_sync_v486 sync on sync.location_id = loc.id and sync.first_seen_at >= v_from_ts
    where loc.tenant_id = p_tenant_id and loc.active = true
    group by loc.id, loc.name, loc.location_code
    order by loc.name asc
  ) bc;

  -- Data freshness
  v_data_freshness := jsonb_build_object(
    'as_of', now(),
    'evaluated_days', p_days,
    'total_sales_evaluated', v_total_sales,
    'total_pos_evaluated', v_total_pos,
    'total_transfers_evaluated', v_total_transfers,
    'total_sync_events_evaluated', v_total_sync_events
  );

  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'location_id', p_location_id,
    'can_view_cost', v_can_view_cost,
    'data_freshness', v_data_freshness,
    'summary', jsonb_build_object(
      'overall_efficiency_score', v_efficiency_score,
      'health_status', v_health_status,
      'active_bottlenecks_count', jsonb_array_length(v_bottlenecks),
      'avg_daily_throughput', v_avg_daily_throughput,
      'avg_po_cycle_hours', v_avg_po_approval_hours,
      'avg_grn_lead_time_days', v_avg_grn_lead_time_days,
      'avg_transfer_hours', v_avg_transfer_hours,
      'sync_reliability_pct', v_sync_success_rate
    ),
    'sales_billing', jsonb_build_object(
      'total_sales', v_total_sales,
      'completed_sales', v_completed_sales,
      'cancelled_sales', v_cancelled_sales,
      'cancellation_rate_pct', v_cancellation_rate,
      'avg_daily_throughput', v_avg_daily_throughput,
      'held_sales_count', v_held_sales_count,
      'peak_hours', v_peak_hours
    ),
    'procurement', jsonb_build_object(
      'total_pos', v_total_pos,
      'completed_pos', v_completed_pos,
      'pending_approval_pos', v_pending_approval_pos,
      'avg_approval_hours', v_avg_po_approval_hours,
      'avg_grn_lead_time_days', v_avg_grn_lead_time_days,
      'overdue_pos', v_overdue_pos,
      'supplier_delay_rate_pct', v_supplier_delay_rate,
      'delayed_orders', v_delayed_orders
    ),
    'inventory_operations', jsonb_build_object(
      'total_transfers', v_total_transfers,
      'completed_transfers', v_completed_transfers,
      'avg_transfer_hours', v_avg_transfer_hours,
      'delayed_transfers_count', v_delayed_transfers_count,
      'transfer_cancellation_rate_pct', v_transfer_cancellation_rate,
      'delayed_transfers', v_delayed_transfers,
      'total_adjustments', v_total_adjustments,
      'pending_adjustments', v_pending_adjustments,
      'approved_adjustments', v_approved_adjustments,
      'avg_adjustment_approval_hours', v_avg_adjustment_approval_hours
    ),
    'customer_operations', jsonb_build_object(
      'total_returns', v_total_returns,
      'completed_refunds', v_completed_refunds,
      'pending_refunds', v_pending_refunds,
      'return_rate_pct', v_return_rate,
      'return_reasons', v_return_reasons
    ),
    'system_sync', jsonb_build_object(
      'total_sync_events', v_total_sync_events,
      'synced_count', v_synced_count,
      'pending_sync_count', v_pending_sync_count,
      'failed_sync_count', v_failed_sync_count,
      'conflict_count', v_conflict_count,
      'avg_sync_delay_minutes', v_avg_sync_delay_minutes,
      'sync_success_rate_pct', v_sync_success_rate
    ),
    'bottlenecks', v_bottlenecks,
    'branch_comparisons', v_branch_comparisons
  );
end;
$$;


-- ----------------------------------------------------------------------------
-- 2. Operational Efficiency Diagnostic Scanner RPC
-- ----------------------------------------------------------------------------
create or replace function public.operational_efficiency_diagnostic_scan_v830(
  p_tenant_id uuid,
  p_location_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_eff_data jsonb;
  v_bottlenecks jsonb;
  v_findings_batch jsonb := '[]'::jsonb;
  v_b jsonb;
  v_ingest_res jsonb;
  v_inserted integer := 0;
  v_updated integer := 0;
begin
  -- Run the operational efficiency engine
  v_eff_data := public.operational_efficiency_intelligence_v830(
    p_tenant_id => p_tenant_id,
    p_location_id => p_location_id,
    p_days => 30
  );

  v_bottlenecks := v_eff_data->'bottlenecks';

  if v_bottlenecks is not null and jsonb_array_length(v_bottlenecks) > 0 then
    for v_b in select * from jsonb_array_elements(v_bottlenecks) loop
      v_findings_batch := v_findings_batch || jsonb_build_object(
        'engine', 'operations',
        'category', 'workflow_bottleneck',
        'severity', v_b->>'severity',
        'rule_code', v_b->>'rule_code',
        'detection_rule', 'Operational Process Efficiency: ' || (v_b->>'affected_process'),
        'title', v_b->>'title',
        'description', v_b->>'description',
        'affected_entity_type', 'business_process',
        'affected_entity_id', v_b->>'affected_process',
        'affected_record_ref', coalesce(v_b->>'affected_process', 'Operations'),
        'location_id', p_location_id,
        'evidence', v_b->'evidence',
        'confidence', 0.95,
        'impacted_amount', 0.0,
        'recommended_action', jsonb_build_object(
          'action_type', 'process_optimization',
          'label', v_b->>'recommendation',
          'route', v_b->>'route'
        )
      );
    end loop;

    -- Ingest into Phase 7 Shared Intelligence Framework
    v_ingest_res := public.erp_intelligence_ingest_findings_v830(
      p_tenant_id => p_tenant_id,
      p_findings => v_findings_batch
    );

    v_inserted := (v_ingest_res->>'inserted')::integer;
    v_updated := (v_ingest_res->>'updated')::integer;
  end if;

  return jsonb_build_object(
    'success', true,
    'total_detected', coalesce(jsonb_array_length(v_bottlenecks), 0),
    'inserted', v_inserted,
    'updated', v_updated,
    'efficiency_score', v_eff_data->'summary'->'overall_efficiency_score',
    'health_status', v_eff_data->'summary'->'health_status'
  );
end;
$$;


-- ----------------------------------------------------------------------------
-- 3. Register Release #713 (v8.3.7) in thq_schema_releases
-- ----------------------------------------------------------------------------
insert into public.thq_schema_releases (
  migration_no,
  schema_version,
  release_name,
  applied_at,
  notes
) values (
  713,
  'v8.3.7',
  'operations_intelligence_phase8_operational_efficiency',
  now(),
  'Operational efficiency engine measuring sales billing, procurement approval lead time, inter-store transfer completion, POS sync reliability, and deterministic bottleneck detection.'
)
on conflict (migration_no) do update set
  schema_version = excluded.schema_version,
  release_name = excluded.release_name,
  applied_at = excluded.applied_at,
  notes = excluded.notes;
